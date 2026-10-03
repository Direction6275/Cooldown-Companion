--[[
    CooldownCompanion - Core/AuraTextures.lua
    Blizzard-first aura texture library and runtime texture rendering
    for aura-capable buttons.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local AT = ST._AT or {}
ST._AT = AT

local ipairs = ipairs
local math_cos = math.cos
local math_max = math.max
local math_sin = math.sin
local pairs = pairs

local function IsRuntimeItemLike(buttonData)
    return buttonData
        and (buttonData.type == "item" or buttonData.type == "equipmentSlot" or buttonData.type == "equipitem")
end
local string_upper = string.upper
local tonumber = tonumber
local type = type

local SCREEN_LOCATION = Enum and Enum.ScreenLocationType or {}
local LOCATION_CENTER = SCREEN_LOCATION.Center or 0
local LOCATION_LEFT = SCREEN_LOCATION.Left or 1
local LOCATION_RIGHT = SCREEN_LOCATION.Right or 2
local LOCATION_TOP = SCREEN_LOCATION.Top or 3
local LOCATION_BOTTOM = SCREEN_LOCATION.Bottom or 4
local LOCATION_TOPLEFT = SCREEN_LOCATION.TopLeft or 5
local LOCATION_TOPRIGHT = SCREEN_LOCATION.TopRight or 6
local LOCATION_LEFTOUTSIDE = SCREEN_LOCATION.LeftOutside or 7
local LOCATION_RIGHTOUTSIDE = SCREEN_LOCATION.RightOutside or 8
local LOCATION_LEFTRIGHT = SCREEN_LOCATION.LeftRight or 9
local LOCATION_TOPBOTTOM = SCREEN_LOCATION.TopBottom or 10
local LOCATION_LEFTRIGHTOUTSIDE = SCREEN_LOCATION.LeftRightOutside or 11

local FILTER_SYMBOLS = "symbols"
local FILTER_BLIZZARD_PROC = "blizzardProc"
local FILTER_CUSTOM = "custom"
local FILTER_SHAREDMEDIA = "sharedMedia"
local FILTER_FAVORITES = "favorites"
local FILTER_OTHER = "other"
local DEFAULT_TEXTURE_SIZE = 128
local UI_PARENT_NAME = "UIParent"

local LOCATION_LABELS = {
    [LOCATION_CENTER] = "Center",
    [LOCATION_LEFT] = "Left",
    [LOCATION_RIGHT] = "Right",
    [LOCATION_TOP] = "Top",
    [LOCATION_BOTTOM] = "Bottom",
    [LOCATION_TOPLEFT] = "Top Left",
    [LOCATION_TOPRIGHT] = "Top Right",
    [LOCATION_LEFTRIGHT] = "Left + Right",
    [LOCATION_TOPBOTTOM] = "Top + Bottom",
    [LOCATION_LEFTRIGHTOUTSIDE] = "Left + Right Outside",
}

local SHARED_MEDIA_SOURCE_TYPE = "sharedMedia"
local SHARED_MEDIA_TYPE_ORDER = {
    "background",
    "border",
    "statusbar",
}

local SHARED_MEDIA_TYPE_SORT = {
    background = 1,
    border = 2,
    statusbar = 3,
}

local SHARED_MEDIA_TYPE_LABELS = {
    background = "Background",
    border = "Border",
    statusbar = "Status Bar",
}

local TEXTURE_LAYOUT_LABELS = {
    [LOCATION_CENTER] = "Single",
    [LOCATION_LEFTRIGHT] = "Left + Right",
    [LOCATION_TOPBOTTOM] = "Top + Bottom",
}

local LOCATION_DIMENSIONS = {
    [LOCATION_CENTER] = { width = 1.0, height = 1.0, layout = "single", point = "CENTER", relPoint = "CENTER" },
    [LOCATION_LEFT] = { width = 0.5, height = 1.0, layout = "single", point = "RIGHT", relPoint = "CENTER" },
    [LOCATION_RIGHT] = { width = 0.5, height = 1.0, layout = "single", point = "LEFT", relPoint = "CENTER" },
    [LOCATION_TOP] = { width = 1.0, height = 0.5, layout = "single", point = "BOTTOM", relPoint = "CENTER" },
    [LOCATION_BOTTOM] = { width = 1.0, height = 0.5, layout = "single", point = "TOP", relPoint = "CENTER", flipV = true },
    [LOCATION_TOPLEFT] = { width = 0.5, height = 0.5, layout = "single", point = "BOTTOMRIGHT", relPoint = "TOPLEFT" },
    [LOCATION_TOPRIGHT] = { width = 0.5, height = 0.5, layout = "single", point = "BOTTOMLEFT", relPoint = "TOPRIGHT", flipH = true },
    [LOCATION_LEFTOUTSIDE] = { width = 0.5, height = 1.0, layout = "single", point = "RIGHT", relPoint = "LEFT", outside = true },
    [LOCATION_RIGHTOUTSIDE] = { width = 0.5, height = 1.0, layout = "single", point = "LEFT", relPoint = "RIGHT", outside = true, flipH = true },
    [LOCATION_LEFTRIGHT] = { width = 0.5, height = 1.0, layout = "pair_horizontal" },
    [LOCATION_TOPBOTTOM] = { width = 1.0, height = 0.5, layout = "pair_vertical" },
    [LOCATION_LEFTRIGHTOUTSIDE] = { width = 0.5, height = 1.0, layout = "pair_horizontal_outside" },
}

local FILTER_OPTIONS = {
    [FILTER_SYMBOLS] = "Symbols",
    [FILTER_BLIZZARD_PROC] = "Blizzard Proc Overlays",
    [FILTER_CUSTOM] = "Custom",
    [FILTER_SHAREDMEDIA] = "SharedMedia",
    [FILTER_FAVORITES] = "Favorites",
    [FILTER_OTHER] = "Other",
}

local LOCATION_ORDER = {
    LOCATION_CENTER,
    LOCATION_LEFTRIGHT,
    LOCATION_TOPBOTTOM,
}

local DEFAULT_TEXTURE_PAIR_SPACING = 0
local LEGACY_OUTSIDE_PAIR_SPACING = 0.15
local MIN_TEXTURE_PAIR_SPACING = -5
local MAX_TEXTURE_PAIR_SPACING = 5
local MIN_TEXTURE_ROTATION = -180
local MAX_TEXTURE_ROTATION = 180
local MIN_TEXTURE_STRETCH = -0.75
local MAX_TEXTURE_STRETCH = 2
local TEXTURE_INDICATOR_EFFECT_NONE = "none"
local TEXTURE_INDICATOR_EFFECT_PULSE = "pulse"
local TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT = "colorShift"
local TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND = "shrinkExpand"
local TEXTURE_INDICATOR_EFFECT_BOUNCE = "bounce"
local MIN_TEXTURE_INDICATOR_SPEED = 0.1
local MAX_TEXTURE_INDICATOR_SPEED = 2.0
local DEFAULT_TEXTURE_INDICATOR_SPEED = 0.5
local DEFAULT_TEXTURE_PULSE_ALPHA = 0.45
local DEFAULT_TEXTURE_SHRINK_SCALE = 0.82
local DEFAULT_TEXTURE_BOUNCE_PIXELS = 18

-- LEGACY CONVERSION ONLY: defaults for the retired Texture panel's single
-- aura effect (group.style.textureIndicators.aura). I.ReadEffects reads it
-- only for an old aura Indicator that has not yet stored effectVersion 1.
local TEXTURE_INDICATOR_DEFAULTS = {
    aura = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 0.84, 0, 1 },
        combatOnly = false,
        invert = false,
    },
}

CooldownCompanion.INDICATOR_EFFECT_DEFAULTS = {
    pulse = {
        enabled = false,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
    },
    colorShift = {
        enabled = false,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 1, 1, 1 },
    },
    shrinkExpand = {
        enabled = false,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
    },
    bounce = {
        enabled = false,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
    },
}

local TRIGGER_CONDITION_LABELS = {
    cooldownActive = "Cooldown",
    auraActive = "Aura",
    procActive = "Proc",
    rangeActive = "Range",
    usable = "Usable",
    chargesRecharging = "Charge Recharge",
    chargeState = "Charge State",
    countTextActive = "Count Text",
    countState = "Display Count",
}

local TRIGGER_EXPECTED_LABELS = {
    cooldownActive = {
        ["true"] = "On Cooldown",
        ["false"] = "Off Cooldown",
    },
    auraActive = {
        ["true"] = "Active",
        ["false"] = "Inactive",
    },
    procActive = {
        ["true"] = "Active",
        ["false"] = "Inactive",
    },
    rangeActive = {
        ["true"] = "In Range",
        ["false"] = "Out of Range",
    },
    usable = {
        ["true"] = "Usable",
        ["false"] = "Unusable",
    },
    chargesRecharging = {
        ["true"] = "Recharging",
        ["false"] = "Not Recharging",
    },
    countTextActive = {
        ["true"] = "Shown",
        ["false"] = "Hidden",
    },
}

local TRIGGER_STATE_LABELS = {
    chargeState = {
        full = "Full",
        missing = "Missing",
        zero = "Zero",
    },
    countState = {
        full = "Full",
        missing = "Missing",
        zero = "Zero",
    },
}

local TRIGGER_CONDITION_ORDERS = {
    spell = { "cooldownActive", "auraActive", "procActive", "rangeActive", "usable" },
    passiveSpell = { "auraActive", "procActive" },
    item = { "cooldownActive", "rangeActive", "usable" },
}

local function CopyColor(color)
    if type(color) ~= "table" then
        return nil
    end
    return { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
end

local function Clamp(value, minValue, maxValue)
    if type(value) ~= "number" then
        return minValue
    end
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function NormalizeBlendMode(mode)
    local normalized = type(mode) == "string" and string_upper(mode) or "ADD"
    if normalized == "BLEND" or normalized == "ADD" then
        return normalized
    end
    return "ADD"
end

local function NormalizeTextureIndicatorEffect(effectType)
    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE
        or effectType == TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT
        or effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND
        or effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        return effectType
    end
    return TEXTURE_INDICATOR_EFFECT_NONE
end

local function NormalizeTextureIndicatorSection(sectionKey, sectionData)
    local defaults = TEXTURE_INDICATOR_DEFAULTS[sectionKey]
    if not defaults then
        return nil
    end

    sectionData = type(sectionData) == "table" and sectionData or {}
    sectionData.enabled = sectionData.enabled == true
    sectionData.effectType = NormalizeTextureIndicatorEffect(sectionData.effectType or defaults.effectType)
    sectionData.speed = Clamp(tonumber(sectionData.speed) or defaults.speed or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    sectionData.color = CopyColor(sectionData.color) or CopyColor(defaults.color) or { 1, 1, 1, 1 }
    sectionData.combatOnly = sectionData.combatOnly == true
    if defaults.invert ~= nil then
        sectionData.invert = sectionData.invert == true
    else
        sectionData.invert = nil
    end

    return sectionData
end

CooldownCompanion.NormalizeTextureIndicatorSection = NormalizeTextureIndicatorSection

function CooldownCompanion.NormalizeIndicatorEffectSection(effectKey, effectData)
    local defaults = CooldownCompanion.INDICATOR_EFFECT_DEFAULTS[effectKey]
    if not defaults then
        return nil
    end

    effectData = type(effectData) == "table" and effectData or {}
    effectData.enabled = effectData.enabled == true
    effectData.speed = Clamp(
        tonumber(effectData.speed) or defaults.speed or DEFAULT_TEXTURE_INDICATOR_SPEED,
        MIN_TEXTURE_INDICATOR_SPEED,
        MAX_TEXTURE_INDICATOR_SPEED
    )

    if defaults.color ~= nil then
        effectData.color = CopyColor(effectData.color) or CopyColor(defaults.color) or { 1, 1, 1, 1 }
    else
        effectData.color = nil
    end

    return effectData
end

function CooldownCompanion.NormalizeIndicatorEffectStore(triggerSettings)
    if type(triggerSettings) ~= "table" then
        return nil
    end

    if type(triggerSettings.effects) ~= "table" then
        triggerSettings.effects = {}
    end

    local store = triggerSettings.effects
    for _, effectKey in ipairs(ST.Indicator.EffectOrder) do
        store[effectKey] = CooldownCompanion.NormalizeIndicatorEffectSection(effectKey, store[effectKey])
    end

    return store
end

local function GetTriggerConditionOrderForButtonData(buttonData)
    if type(buttonData) ~= "table" then
        return TRIGGER_CONDITION_ORDERS.spell
    end

    if IsRuntimeItemLike(buttonData) then
        local order = { "cooldownActive", "rangeActive", "usable" }
        if buttonData.hasCharges == true then
            order[#order + 1] = "chargesRecharging"
            order[#order + 1] = "chargeState"
        end
        return order
    end

    if buttonData.type == "spell" and buttonData.isPassiveCooldown == true then
        local order = { "cooldownActive" }
        if buttonData.hasCharges == true then
            order[#order + 1] = "chargesRecharging"
            order[#order + 1] = "chargeState"
        end
        return order
    end

    if buttonData.type == "spell" and buttonData.isPassive == true then
        return { "auraActive", "procActive" }
    end

    local order = { "cooldownActive", "auraActive", "procActive", "rangeActive", "usable" }
    if buttonData.hasCharges == true then
        order[#order + 1] = "chargesRecharging"
        order[#order + 1] = "chargeState"
    elseif CooldownCompanion.HasNonChargeCountTextBehavior
            and CooldownCompanion.HasNonChargeCountTextBehavior(buttonData) then
        order[#order + 1] = "countTextActive"
        if buttonData._hasDisplayCount == true or buttonData._displayCountFamily == true then
            order[#order + 1] = "countState"
        end
    end
    return order
end

local function NormalizeTriggerConditionKey(buttonData, conditionKey)
    local order = GetTriggerConditionOrderForButtonData(buttonData)
    if conditionKey == nil then
        return order[1]
    end

    for _, validKey in ipairs(order) do
        if conditionKey == validKey then
            return conditionKey
        end
    end
    return nil
end

local function NormalizeTriggerStateKey(conditionKey, stateKey)
    if not TRIGGER_STATE_LABELS[conditionKey] then
        return nil
    end

    for _, validKey in ipairs({ "full", "missing", "zero" }) do
        if stateKey == validKey then
            return validKey
        end
    end

    return "full"
end


local VALID_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local function NormalizeAnchorPoint(anchor)
    if type(anchor) ~= "string" or not VALID_POINTS[anchor] then
        return "CENTER"
    end
    return anchor
end

local function NormalizeIndicatorAnchorRelativeTo(relativeTo)
    if type(relativeTo) ~= "string" or relativeTo == "" then
        return UI_PARENT_NAME
    end
    if relativeTo == UI_PARENT_NAME then
        return relativeTo
    end
    if relativeTo:match("^CooldownCompanionGroup%d+$")
        or relativeTo:match("^CooldownCompanionContainer%d+$") then
        return relativeTo
    end
    if relativeTo:find("^CooldownCompanion") then
        return UI_PARENT_NAME
    end
    return relativeTo
end

local function NormalizeTextureLayout(locationType)
    if LOCATION_DIMENSIONS[locationType] then
        if locationType == LOCATION_LEFTRIGHTOUTSIDE then
            return LOCATION_LEFTRIGHT, LEGACY_OUTSIDE_PAIR_SPACING
        end
        return locationType, DEFAULT_TEXTURE_PAIR_SPACING
    end
    if locationType == LOCATION_LEFTRIGHT then
        return LOCATION_LEFTRIGHT, DEFAULT_TEXTURE_PAIR_SPACING
    end
    if locationType == LOCATION_TOPBOTTOM then
        return LOCATION_TOPBOTTOM, DEFAULT_TEXTURE_PAIR_SPACING
    end
    if locationType == LOCATION_LEFTRIGHTOUTSIDE then
        return LOCATION_LEFTRIGHT, LEGACY_OUTSIDE_PAIR_SPACING
    end
    return LOCATION_CENTER, DEFAULT_TEXTURE_PAIR_SPACING
end

local function GetStretchMultiplier(value)
    return math_max(0.05, 1 + (tonumber(value) or 0))
end

local function RotateOffset(x, y, radians)
    if not radians or radians == 0 then
        return x, y
    end

    local cosAngle = math_cos(radians)
    local sinAngle = math_sin(radians)
    return (x * cosAngle) - (y * sinAngle), (x * sinAngle) + (y * cosAngle)
end

local function BuildLocationSubtitle(locationType)
    if LOCATION_LABELS[locationType] then
        return LOCATION_LABELS[locationType]
    end

    local normalizedLocationType = NormalizeTextureLayout(locationType)
    return TEXTURE_LAYOUT_LABELS[normalizedLocationType] or LOCATION_LABELS[normalizedLocationType] or "Center"
end

local function NormalizeAuraTextureSourceType(sourceType)
    if sourceType == "atlas" or sourceType == "file" or sourceType == SHARED_MEDIA_SOURCE_TYPE then
        return sourceType
    end
    return nil
end

local function NormalizeSharedMediaType(mediaType)
    if mediaType == "background" or mediaType == "border" or mediaType == "statusbar" then
        return mediaType
    end
    return nil
end

AT.FILTER_SYMBOLS = FILTER_SYMBOLS
AT.FILTER_BLIZZARD_PROC = FILTER_BLIZZARD_PROC
AT.FILTER_SHAREDMEDIA = FILTER_SHAREDMEDIA
AT.FILTER_FAVORITES = FILTER_FAVORITES
AT.FILTER_OTHER = FILTER_OTHER
AT.DEFAULT_TEXTURE_SIZE = DEFAULT_TEXTURE_SIZE
AT.UI_PARENT_NAME = UI_PARENT_NAME
AT.LOCATION_CENTER = LOCATION_CENTER
AT.LOCATION_DIMENSIONS = LOCATION_DIMENSIONS
AT.SHARED_MEDIA_SOURCE_TYPE = SHARED_MEDIA_SOURCE_TYPE
AT.SHARED_MEDIA_TYPE_ORDER = SHARED_MEDIA_TYPE_ORDER
AT.SHARED_MEDIA_TYPE_SORT = SHARED_MEDIA_TYPE_SORT
AT.SHARED_MEDIA_TYPE_LABELS = SHARED_MEDIA_TYPE_LABELS
AT.FILTER_OPTIONS = FILTER_OPTIONS
AT.DEFAULT_TEXTURE_PAIR_SPACING = DEFAULT_TEXTURE_PAIR_SPACING
AT.MIN_TEXTURE_PAIR_SPACING = MIN_TEXTURE_PAIR_SPACING
AT.MAX_TEXTURE_PAIR_SPACING = MAX_TEXTURE_PAIR_SPACING
AT.MIN_TEXTURE_ROTATION = MIN_TEXTURE_ROTATION
AT.MAX_TEXTURE_ROTATION = MAX_TEXTURE_ROTATION
AT.MIN_TEXTURE_STRETCH = MIN_TEXTURE_STRETCH
AT.MAX_TEXTURE_STRETCH = MAX_TEXTURE_STRETCH
AT.TEXTURE_INDICATOR_EFFECT_NONE = TEXTURE_INDICATOR_EFFECT_NONE
AT.TEXTURE_INDICATOR_EFFECT_PULSE = TEXTURE_INDICATOR_EFFECT_PULSE
AT.TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT = TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT
AT.TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND = TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND
AT.TEXTURE_INDICATOR_EFFECT_BOUNCE = TEXTURE_INDICATOR_EFFECT_BOUNCE
AT.MIN_TEXTURE_INDICATOR_SPEED = MIN_TEXTURE_INDICATOR_SPEED
AT.MAX_TEXTURE_INDICATOR_SPEED = MAX_TEXTURE_INDICATOR_SPEED
AT.DEFAULT_TEXTURE_INDICATOR_SPEED = DEFAULT_TEXTURE_INDICATOR_SPEED
AT.DEFAULT_TEXTURE_PULSE_ALPHA = DEFAULT_TEXTURE_PULSE_ALPHA
AT.DEFAULT_TEXTURE_SHRINK_SCALE = DEFAULT_TEXTURE_SHRINK_SCALE
AT.DEFAULT_TEXTURE_BOUNCE_PIXELS = DEFAULT_TEXTURE_BOUNCE_PIXELS

-- Shrink / Expand's scale at `phase` (0-1) through one loop. The one curve
-- for the preview / CC-side path (AuraTexturesEffects) and the native aura
-- slot path (AuraDisplay), so the two can never drift apart.
function AT.ShrinkScaleAtPhase(phase)
    local t = 0.5 - (0.5 * math.cos(phase * 2 * math.pi))
    return 1 - ((1 - DEFAULT_TEXTURE_SHRINK_SCALE) * t)
end
AT.TRIGGER_EXPECTED_LABELS = TRIGGER_EXPECTED_LABELS
AT.BUILTIN_LIBRARY = AT.BUILTIN_LIBRARY or {}
AT.CopyColor = CopyColor
AT.Clamp = Clamp
AT.NormalizeBlendMode = NormalizeBlendMode
AT.NormalizeTextureIndicatorEffect = NormalizeTextureIndicatorEffect
AT.NormalizeTriggerConditionKey = NormalizeTriggerConditionKey
AT.NormalizeTriggerStateKey = NormalizeTriggerStateKey
AT.NormalizeAnchorPoint = NormalizeAnchorPoint
AT.NormalizeTextureLayout = NormalizeTextureLayout
AT.GetStretchMultiplier = GetStretchMultiplier
AT.RotateOffset = RotateOffset
AT.BuildLocationSubtitle = BuildLocationSubtitle
AT.NormalizeAuraTextureSourceType = NormalizeAuraTextureSourceType
AT.NormalizeSharedMediaType = NormalizeSharedMediaType

function CooldownCompanion:ResolveAuraTextureAsset(sourceType, sourceValue, mediaType)
    local normalizedSourceType = NormalizeAuraTextureSourceType(sourceType)

    if normalizedSourceType == "atlas" then
        if type(sourceValue) == "string" and C_Texture.GetAtlasExists(sourceValue) then
            return "atlas", sourceValue
        end
        return nil
    end

    if normalizedSourceType == "file" then
        if sourceValue ~= nil then
            return "file", sourceValue
        end
        return nil
    end

    if normalizedSourceType == SHARED_MEDIA_SOURCE_TYPE then
        local normalizedMediaType = NormalizeSharedMediaType(mediaType)
        if not normalizedMediaType or type(sourceValue) ~= "string" or sourceValue == "" then
            return nil
        end

        local resolvedPath = LSM:Fetch(normalizedMediaType, sourceValue, true)
        if type(resolvedPath) == "string" and resolvedPath ~= "" then
            return "file", resolvedPath
        end
        return nil
    end

    return nil
end

local function NormalizeAuraTextureSettings(settings)
    if type(settings) ~= "table" then
        return nil
    end

    settings.sourceType = NormalizeAuraTextureSourceType(settings.sourceType)
    settings.label = type(settings.label) == "string" and settings.label or nil
    settings.sourceValue = settings.sourceValue
    settings.enabled = settings.sourceType ~= nil and settings.sourceValue ~= nil
    settings.mode = settings.mode == "replace" and "replace" or "overlay"
    settings.scale = Clamp(settings.scale or 1, 0.25, 4)
    settings.alpha = Clamp(settings.alpha or 1, 0.05, 1)
    settings.blendMode = NormalizeBlendMode(settings.blendMode)
    settings.rotation = Clamp(tonumber(settings.rotation) or 0, MIN_TEXTURE_ROTATION, MAX_TEXTURE_ROTATION)
    settings.stretchX = Clamp(tonumber(settings.stretchX) or 0, MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH)
    settings.stretchY = Clamp(tonumber(settings.stretchY) or 0, MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH)
    settings.point = NormalizeAnchorPoint(settings.point or settings.anchor)
    settings.relativePoint = NormalizeAnchorPoint(settings.relativePoint)
    settings.relativeTo = NormalizeIndicatorAnchorRelativeTo(settings.relativeTo)
    settings.x = tonumber(settings.x or settings.xOffset) or 0
    settings.y = tonumber(settings.y or settings.yOffset) or 0
    settings.anchor = nil
    settings.mediaType = settings.sourceType == SHARED_MEDIA_SOURCE_TYPE
        and NormalizeSharedMediaType(settings.mediaType)
        or nil
    settings.xOffset = nil
    settings.yOffset = nil
    settings.color = CopyColor(settings.color) or { 1, 1, 1, 1 }
    local normalizedLocationType, defaultPairSpacing = NormalizeTextureLayout(settings.locationType)
    settings.locationType = normalizedLocationType
    local rawPairSpacing = tonumber(settings.pairSpacing)
    if rawPairSpacing == nil then
        settings.pairSpacing = defaultPairSpacing
    else
        settings.pairSpacing = Clamp(rawPairSpacing, MIN_TEXTURE_PAIR_SPACING, MAX_TEXTURE_PAIR_SPACING)
    end
    settings.width = tonumber(settings.width) or nil
    settings.height = tonumber(settings.height) or nil

    return settings
end

-- An aura Indicator's primary Aura entry is intrinsically aura-controlled.
-- Ordinary spell entries retain the explicit opt-in so legacy auraTracking
-- residue cannot silently reactivate them. Only the main source
-- is the aura: an aura Indicator's extra spell sources are rule sources and
-- never own an aura slot. A While Missing aura or an aura list owns no slot
-- either: CC draws it behind a presence tracker (AuraDisplay "presence").
function CooldownCompanion:IsIndicatorAuraDisplayEnabled(group, buttonData)
    return ST.Indicator.IsAura(group)
        and not ST.Indicator.UsesPresence(group)
        and type(buttonData) == "table"
        and buttonData == ST.Indicator.Primary(group)
        and buttonData.type == "spell"
        and buttonData.enabled ~= false
        and (buttonData.addedAs == "aura"
            or buttonData.textureAuraDisplayEnabled == true)
end

-- Texture-only tracking deliberately does not set the general auraTracking
-- flag: doing so would silently turn tracking back on if the entry were later
-- converted to an icon or bar. Resolve the same ordered candidate identity
-- directly while the Texture Aura display is active instead.
function CooldownCompanion:ResolveIndicatorAuraSpellID(buttonData)
    if not (type(buttonData) == "table"
        and buttonData.type == "spell"
        and (buttonData.addedAs == "aura"
            or buttonData.textureAuraDisplayEnabled == true)
        and self.GetOrderedAuraCandidateSpellIDs) then
        return nil
    end

    local orderedCandidateIDs = self:GetOrderedAuraCandidateSpellIDs(buttonData)
    return orderedCandidateIDs and orderedCandidateIDs[1] or nil
end

-- Mutation helper for user actions that place a primary Aura entry into an
-- aura Indicator (new add, move, or panel conversion). Primary Aura entries
-- have no opt-out there; ordinary spell entries still do.
function CooldownCompanion:EnableIndicatorAuraDisplayForEntry(group, buttonData)
    if not (ST.Indicator.IsAura(group)
        and type(buttonData) == "table"
        and buttonData.type == "spell"
        and buttonData.addedAs == "aura") then
        return false
    end

    buttonData.textureAuraDisplayEnabled = true
    return true
end

function CooldownCompanion:IsConditionsIndicatorGroup(group)
    return ST.IsIndicatorGroup(group) and not ST.Indicator.IsAura(group)
end

function CooldownCompanion:GetIndicatorTextureLayoutOptions()
    local options = {}
    for _, locationType in ipairs(LOCATION_ORDER) do
        options[locationType] = TEXTURE_LAYOUT_LABELS[locationType]
    end
    return options, LOCATION_ORDER
end

function CooldownCompanion:GetIndicatorTextureLayoutValue(locationType)
    local normalizedLocationType = NormalizeTextureLayout(locationType)
    if normalizedLocationType == LOCATION_LEFTRIGHT or normalizedLocationType == LOCATION_TOPBOTTOM then
        return normalizedLocationType
    end
    return LOCATION_CENTER
end

local function ResolveGroup(groupOrId)
    if type(groupOrId) == "table" then
        return groupOrId
    end
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    return profile and profile.groups and profile.groups[groupOrId] or nil
end

AT.NormalizeAuraTextureSettings = NormalizeAuraTextureSettings
AT.ResolveGroup = ResolveGroup

function CooldownCompanion:GetIndicatorTextureSettings(groupOrId)
    local group = ResolveGroup(groupOrId)
    if ST.IsIndicatorGroup(group) then return NormalizeAuraTextureSettings(ST.Indicator.Initialize(group).signal) end
end

function CooldownCompanion:GetIndicatorEffectSettings(groupOrId)
    local group = ResolveGroup(groupOrId)
    if not ST.IsIndicatorGroup(group) then return end
    ST.Indicator.Effects(group)
    return ST.Indicator.NormalizeEffectsForFamily(group,
        CooldownCompanion.NormalizeIndicatorEffectStore(ST.Indicator.Settings(group)))
end

function CooldownCompanion:GetTextureIndicatorTransformTarget(host)
    if not host then
        return nil
    end
    if host.indicatorReadouts then return host.visualRoot end

    if host._activeDisplayType == "icon" and host.iconFrame then
        return host.iconFrame
    end

    if host._activeDisplayType == "text" and host.textFrame then
        return host.textFrame
    end

    return host.visualRoot
end

function CooldownCompanion:ResetTextureIndicatorRootState(host)
    if not host or not host.visualRoot then
        return
    end

    host.visualRoot:SetScale(1)
    host.visualRoot:ClearAllPoints()
    host.visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
end

function CooldownCompanion.IsValidIndicatorIconTexture(iconTexture)
    local iconType = type(iconTexture)
    if iconType ~= "number" and iconType ~= "string" then
        return false
    end

    local probe = CooldownCompanion._indicatorIconValidationTexture
    if not probe then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        probe = holder:CreateTexture(nil, "ARTWORK")
        holder.texture = probe
        CooldownCompanion._indicatorIconValidationTexture = probe
    end

    probe:SetTexture(nil)
    probe:SetTexture(iconTexture)
    local resolvedTexture = probe:GetTexture()
    probe:SetTexture(nil)

    return resolvedTexture ~= nil
end

function CooldownCompanion.NormalizeIndicatorIconSettings(settings)
    if type(settings) ~= "table" then
        return nil
    end

    settings.manualIcon = CooldownCompanion.IsValidIndicatorIconTexture(settings.manualIcon)
            and settings.manualIcon
        or nil
    settings.maintainAspectRatio = settings.maintainAspectRatio ~= false
    settings.iconZoom = Clamp(tonumber(settings.iconZoom) or 0, 0, 50)
    settings.buttonSize = Clamp(tonumber(settings.buttonSize) or 36, 10, 150)
    settings.iconWidth = Clamp(tonumber(settings.iconWidth) or settings.buttonSize, 10, 150)
    settings.iconHeight = Clamp(tonumber(settings.iconHeight) or settings.buttonSize, 10, 150)
    settings.borderSize = Clamp(tonumber(settings.borderSize) or 1, 0, 5)
    settings.borderRenderMode = ST.GetBorderRenderMode(settings)
    settings.borderColor = CopyColor(settings.borderColor) or { 0, 0, 0, 1 }
    settings.backgroundColor = CopyColor(settings.backgroundColor) or { 0, 0, 0, 0.5 }
    settings.iconTintColor = CopyColor(settings.iconTintColor) or { 1, 1, 1, 1 }

    return settings
end


function CooldownCompanion:GetIndicatorDisplayType(groupOrId)
    local settings = ST.Indicator.Settings(ResolveGroup(groupOrId))
    return settings and settings.displayType or "icon"
end

function CooldownCompanion:GetIndicatorIconSettings(groupOrId)
    local group = ResolveGroup(groupOrId)
    if ST.IsIndicatorGroup(group) then return CooldownCompanion.NormalizeIndicatorIconSettings(ST.Indicator.Initialize(group).icon) end
end


function CooldownCompanion:BuildLegacyTriggerConditionClause(buttonData)
    if type(buttonData) ~= "table" then
        return nil
    end

    local conditionKey = NormalizeTriggerConditionKey(buttonData, buttonData.triggerCondition)
    if not conditionKey then
        return nil
    end

    local clause = { key = conditionKey }
    if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
        clause.expected = buttonData.triggerExpected ~= false
    else
        clause.state = NormalizeTriggerStateKey(conditionKey, buttonData.triggerState)
    end

    return clause
end

function CooldownCompanion:NormalizeTriggerConditionClause(buttonData, clause, usedKeys)
    if type(clause) ~= "table" then
        return nil
    end

    local conditionKey = NormalizeTriggerConditionKey(
        buttonData,
        clause.key or clause.conditionKey or clause.triggerCondition
    )
    if not conditionKey or (usedKeys and usedKeys[conditionKey]) then
        return nil
    end

    local normalized = { key = conditionKey }
    if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
        normalized.expected = clause.expected ~= false and clause.expected ~= "false"
    else
        normalized.state = NormalizeTriggerStateKey(conditionKey, clause.state or clause.triggerState)
    end

    if usedKeys then
        usedKeys[conditionKey] = true
    end

    return normalized
end

function CooldownCompanion:GetTriggerConditionClauses(buttonData)
    if type(buttonData) ~= "table" then
        return {}
    end

    local normalizedClauses = {}
    local usedKeys = {}
    local sourceClauses = type(buttonData.triggerConditions) == "table" and buttonData.triggerConditions or nil

    if sourceClauses then
        for _, clause in ipairs(sourceClauses) do
            local normalizedClause = self:NormalizeTriggerConditionClause(buttonData, clause, usedKeys)
            if normalizedClause then
                normalizedClauses[#normalizedClauses + 1] = normalizedClause
            end
        end

        if #normalizedClauses == 0 then
            return {}
        end
    end

    if #normalizedClauses == 0 then
        local legacyClause = self:BuildLegacyTriggerConditionClause(buttonData)
        if legacyClause then
            usedKeys[legacyClause.key] = true
            normalizedClauses[1] = legacyClause
        elseif buttonData.triggerCondition ~= nil then
            return {}
        end
    end

    if #normalizedClauses == 0 then
        local fallbackKey = NormalizeTriggerConditionKey(buttonData, nil)
        if fallbackKey then
            if TRIGGER_EXPECTED_LABELS[fallbackKey] ~= nil then
                normalizedClauses[1] = {
                    key = fallbackKey,
                    expected = true,
                }
            else
                normalizedClauses[1] = {
                    key = fallbackKey,
                    state = NormalizeTriggerStateKey(fallbackKey, nil),
                }
            end
        end
    end

    return normalizedClauses
end

function CooldownCompanion:NormalizeTriggerConditionRowData(buttonData)
    if type(buttonData) ~= "table" then
        return nil
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    local primaryClause = clauses[1]
    if primaryClause then
        buttonData.triggerCondition = primaryClause.key
        if TRIGGER_EXPECTED_LABELS[primaryClause.key] ~= nil then
            buttonData.triggerExpected = primaryClause.expected ~= false
            buttonData.triggerState = nil
        else
            buttonData.triggerState = NormalizeTriggerStateKey(primaryClause.key, primaryClause.state)
            buttonData.triggerExpected = nil
        end
    end

    if type(buttonData.triggerConditions) == "table" and #clauses > 0 then
        buttonData.triggerConditions = clauses
    end

    if buttonData.type == "spell" then
        local hasAuraClause = false
        for _, clause in ipairs(clauses) do
            if clause.key == "auraActive" then
                hasAuraClause = true
                break
            end
        end

        local shouldAuraTrack = buttonData.isPassive == true
            or buttonData.addedAs == "aura"
            or hasAuraClause
        if shouldAuraTrack then
            buttonData.auraTracking = true
            buttonData.auraIndicatorEnabled = true
            if buttonData.addedAs ~= "aura" and buttonData.isPassive == true then
                buttonData.addedAs = "aura"
            end
        else
            buttonData.auraTracking = false
            buttonData.auraIndicatorEnabled = false
        end
    end

    return buttonData
end

function CooldownCompanion:TriggerRowUsesCondition(buttonData, conditionKey)
    if type(buttonData) ~= "table" or type(conditionKey) ~= "string" then
        return false
    end

    for _, clause in ipairs(self:GetTriggerConditionClauses(buttonData)) do
        if clause.key == conditionKey then
            return true
        end
    end

    return false
end

-- 12.1 aura teardown: auraActive stays VALID for stored clauses (removing it
-- from the validation lists would make NormalizeTriggerConditionRowData drop
-- saved aura clauses at load), but it is no longer OFFERED for new clauses.
local RETIRED_TRIGGER_CONDITION_OFFERS = {
    auraActive = true,
}

function CooldownCompanion:GetTriggerConditionTypeOptions(buttonData, excludedKeys)
    local order = GetTriggerConditionOrderForButtonData(buttonData)
    local excluded = {}
    if type(excludedKeys) == "table" then
        for _, key in ipairs(excludedKeys) do
            if type(key) == "string" then
                excluded[key] = true
            end
        end
        for key, value in pairs(excludedKeys) do
            if value == true and type(key) == "string" then
                excluded[key] = true
            end
        end
    end

    local options = {}
    local filteredOrder = {}
    for _, key in ipairs(order) do
        if not excluded[key] and not RETIRED_TRIGGER_CONDITION_OFFERS[key] then
            options[key] = TRIGGER_CONDITION_LABELS[key]
            filteredOrder[#filteredOrder + 1] = key
        end
    end
    return options, filteredOrder
end

function CooldownCompanion:GetTriggerConditionExpectedOptions(conditionKey)
    if TRIGGER_STATE_LABELS[conditionKey] then
        return TRIGGER_STATE_LABELS[conditionKey], { "full", "missing", "zero" }
    end

    local options = TRIGGER_EXPECTED_LABELS[conditionKey] or TRIGGER_EXPECTED_LABELS.cooldownActive
    return options, { "true", "false" }
end
