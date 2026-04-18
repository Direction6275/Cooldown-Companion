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

CooldownCompanion.TRIGGER_PANEL_TEXT_MAX_LENGTH = 120
CooldownCompanion.TRIGGER_PANEL_TEXT_MAX_LINES = 4
CooldownCompanion.TRIGGER_PANEL_TEXT_INSET_X = 4
CooldownCompanion.TRIGGER_PANEL_TEXT_INSET_Y = 2
CooldownCompanion.TRIGGER_PANEL_TEXT_OVERFLOW_X = 6
CooldownCompanion.TRIGGER_PANEL_TEXT_OVERFLOW_Y = 4

local C_Item_IsUsableItem = C_Item.IsUsableItem
local C_Spell_GetSpellName = C_Spell.GetSpellName
local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local GetTime = GetTime
local ipairs = ipairs
local issecretvalue = issecretvalue
local math_abs = math.abs
local math_cos = math.cos
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_pi = math.pi
local math_rad = math.rad
local math_sin = math.sin
local pairs = pairs
local string_find = string.find
local string_format = string.format
local string_gsub = string.gsub
local string_lower = string.lower
local string_trim = strtrim
local string_upper = string.upper
local table_concat = table.concat
local table_insert = table.insert
local table_sort = table.sort
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
local NUDGE_BTN_SIZE = 12
local NUDGE_GAP = 2
local NUDGE_REPEAT_DELAY = 0.5
local NUDGE_REPEAT_INTERVAL = 0.05

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

local TEXTURE_INDICATOR_SECTION_ORDER = {
    "proc",
    "aura",
    "pandemic",
    "ready",
    "unusable",
}

local TEXTURE_INDICATOR_DEFAULTS = {
    proc = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_PULSE,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 1, 1, 1 },
        combatOnly = false,
    },
    aura = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 0.84, 0, 1 },
        combatOnly = false,
        invert = false,
    },
    pandemic = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 0.5, 0, 1 },
        combatOnly = false,
    },
    ready = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_BOUNCE,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 0.2, 1, 0.2, 1 },
        combatOnly = false,
    },
    unusable = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_PULSE,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 0.35, 0.35, 1 },
        combatOnly = false,
    },
}

CooldownCompanion.TRIGGER_PANEL_EFFECT_ORDER = {
    TEXTURE_INDICATOR_EFFECT_PULSE,
    TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT,
    TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND,
    TEXTURE_INDICATOR_EFFECT_BOUNCE,
}

CooldownCompanion.TRIGGER_PANEL_EFFECT_DEFAULTS = {
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

local function NormalizeTextureIndicatorStore(styleTable)
    if type(styleTable) ~= "table" then
        return nil
    end

    if type(styleTable.textureIndicators) ~= "table" then
        styleTable.textureIndicators = {}
    end

    local store = styleTable.textureIndicators
    for _, sectionKey in ipairs(TEXTURE_INDICATOR_SECTION_ORDER) do
        store[sectionKey] = NormalizeTextureIndicatorSection(sectionKey, store[sectionKey])
    end

    return store
end

function CooldownCompanion.NormalizeTriggerPanelEffectSection(effectKey, effectData)
    local defaults = CooldownCompanion.TRIGGER_PANEL_EFFECT_DEFAULTS[effectKey]
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

function CooldownCompanion.NormalizeTriggerPanelEffectStore(triggerSettings)
    if type(triggerSettings) ~= "table" then
        return nil
    end

    if type(triggerSettings.effects) ~= "table" then
        triggerSettings.effects = {}
    end

    local store = triggerSettings.effects
    for _, effectKey in ipairs(CooldownCompanion.TRIGGER_PANEL_EFFECT_ORDER) do
        store[effectKey] = CooldownCompanion.NormalizeTriggerPanelEffectSection(effectKey, store[effectKey])
    end

    return store
end

local function GetTriggerConditionOrderForButtonData(buttonData)
    if type(buttonData) ~= "table" then
        return TRIGGER_CONDITION_ORDERS.spell
    end

    if buttonData.type == "item" or buttonData.type == "equipitem" then
        local order = { "cooldownActive", "rangeActive", "usable" }
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
AT.FILTER_CUSTOM = FILTER_CUSTOM
AT.FILTER_SHAREDMEDIA = FILTER_SHAREDMEDIA
AT.FILTER_FAVORITES = FILTER_FAVORITES
AT.FILTER_OTHER = FILTER_OTHER
AT.DEFAULT_TEXTURE_SIZE = DEFAULT_TEXTURE_SIZE
AT.UI_PARENT_NAME = UI_PARENT_NAME
AT.LOCATION_CENTER = LOCATION_CENTER
AT.LOCATION_LEFTRIGHT = LOCATION_LEFTRIGHT
AT.LOCATION_TOPBOTTOM = LOCATION_TOPBOTTOM
AT.LOCATION_LABELS = LOCATION_LABELS
AT.TEXTURE_LAYOUT_LABELS = TEXTURE_LAYOUT_LABELS
AT.LOCATION_DIMENSIONS = LOCATION_DIMENSIONS
AT.SHARED_MEDIA_SOURCE_TYPE = SHARED_MEDIA_SOURCE_TYPE
AT.SHARED_MEDIA_TYPE_ORDER = SHARED_MEDIA_TYPE_ORDER
AT.SHARED_MEDIA_TYPE_SORT = SHARED_MEDIA_TYPE_SORT
AT.SHARED_MEDIA_TYPE_LABELS = SHARED_MEDIA_TYPE_LABELS
AT.FILTER_OPTIONS = FILTER_OPTIONS
AT.LOCATION_ORDER = LOCATION_ORDER
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
AT.TEXTURE_INDICATOR_SECTION_ORDER = TEXTURE_INDICATOR_SECTION_ORDER
AT.TEXTURE_INDICATOR_DEFAULTS = TEXTURE_INDICATOR_DEFAULTS
AT.TRIGGER_CONDITION_LABELS = TRIGGER_CONDITION_LABELS
AT.TRIGGER_EXPECTED_LABELS = TRIGGER_EXPECTED_LABELS
AT.TRIGGER_STATE_LABELS = TRIGGER_STATE_LABELS
AT.BUILTIN_LIBRARY = AT.BUILTIN_LIBRARY or {}
AT.CopyColor = CopyColor
AT.Clamp = Clamp
AT.NormalizeBlendMode = NormalizeBlendMode
AT.NormalizeTextureIndicatorEffect = NormalizeTextureIndicatorEffect
AT.NormalizeTextureIndicatorSection = NormalizeTextureIndicatorSection
AT.NormalizeTextureIndicatorStore = NormalizeTextureIndicatorStore
AT.GetTriggerConditionOrderForButtonData = GetTriggerConditionOrderForButtonData
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
    settings.relativeTo = UI_PARENT_NAME
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

function CooldownCompanion:IsAuraTextureButtonSupported(buttonData)
    return type(buttonData) == "table"
        and buttonData.type == "spell"
        and (buttonData.auraTracking == true or buttonData.isPassive == true)
end

function CooldownCompanion:IsTexturePanelGroup(group)
    return type(group) == "table" and group.displayMode == "textures"
end

function CooldownCompanion:IsTriggerPanelGroup(group)
    return type(group) == "table" and group.displayMode == "trigger"
end

function CooldownCompanion:IsStandaloneTexturePanelGroup(group)
    return self:IsTexturePanelGroup(group) or self:IsTriggerPanelGroup(group)
end

function CooldownCompanion:GetTexturePanelLocationOptions()
    local options = {}
    for _, locationType in ipairs(LOCATION_ORDER) do
        options[locationType] = TEXTURE_LAYOUT_LABELS[locationType]
    end
    return options, LOCATION_ORDER
end

function CooldownCompanion:GetTexturePanelLayoutSelectionValue(locationType)
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

function CooldownCompanion:GetTexturePanelSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.textureSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.textureSettings = {
            blendMode = "BLEND",
            locationType = LOCATION_CENTER,
            pairSpacing = DEFAULT_TEXTURE_PAIR_SPACING,
            rotation = 0,
            stretchX = 0,
            stretchY = 0,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = UI_PARENT_NAME,
            x = 0,
            y = 0,
        }
    end

    return NormalizeAuraTextureSettings(group.textureSettings)
end

function CooldownCompanion:GetTriggerPanelSignalSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings = {}
    end

    if type(group.triggerSettings.signal) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings.signal = {
            blendMode = "BLEND",
            locationType = LOCATION_CENTER,
            pairSpacing = DEFAULT_TEXTURE_PAIR_SPACING,
            rotation = 0,
            stretchX = 0,
            stretchY = 0,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = UI_PARENT_NAME,
            x = 0,
            y = 0,
        }
    end

    return NormalizeAuraTextureSettings(group.triggerSettings.signal)
end

function CooldownCompanion:GetTriggerPanelEffectSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings = {}
    end

    if type(group.triggerSettings.effects) ~= "table" and not createIfMissing then
        return nil
    end

    return CooldownCompanion.NormalizeTriggerPanelEffectStore(group.triggerSettings)
end

function CooldownCompanion:GetTextureIndicatorTransformTarget(host)
    if not host then
        return nil
    end

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

function CooldownCompanion.NormalizeTriggerDisplayType(displayType)
    if displayType == "icon" or displayType == "text" then
        return displayType
    end
    return "texture"
end

function CooldownCompanion.IsValidTriggerPanelIconTexture(iconTexture)
    local iconType = type(iconTexture)
    if iconType ~= "number" and iconType ~= "string" then
        return false
    end

    local probe = CooldownCompanion._triggerPanelIconValidationTexture
    if not probe then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        probe = holder:CreateTexture(nil, "ARTWORK")
        holder.texture = probe
        CooldownCompanion._triggerPanelIconValidationTexture = probe
    end

    probe:SetTexture(nil)
    probe:SetTexture(iconTexture)
    local resolvedTexture = probe:GetTexture()
    probe:SetTexture(nil)

    return resolvedTexture ~= nil
end

function CooldownCompanion.NormalizeTriggerIconSettings(settings)
    if type(settings) ~= "table" then
        return nil
    end

    settings.manualIcon = CooldownCompanion.IsValidTriggerPanelIconTexture(settings.manualIcon)
            and settings.manualIcon
        or nil
    settings.maintainAspectRatio = settings.maintainAspectRatio ~= false
    settings.buttonSize = Clamp(tonumber(settings.buttonSize) or 36, 10, 150)
    settings.iconWidth = Clamp(tonumber(settings.iconWidth) or settings.buttonSize, 10, 150)
    settings.iconHeight = Clamp(tonumber(settings.iconHeight) or settings.buttonSize, 10, 150)
    settings.borderSize = Clamp(tonumber(settings.borderSize) or 1, 0, 5)
    settings.borderColor = CopyColor(settings.borderColor) or { 0, 0, 0, 1 }
    settings.backgroundColor = CopyColor(settings.backgroundColor) or { 0, 0, 0, 0.5 }
    settings.iconTintColor = CopyColor(settings.iconTintColor) or { 1, 1, 1, 1 }

    return settings
end

function CooldownCompanion.NormalizeTriggerTextSettings(settings)
    if type(settings) ~= "table" then
        return nil
    end

    settings.value = type(settings.value) == "string" and settings.value or ""
    settings.textFont = type(settings.textFont) == "string" and settings.textFont or "Friz Quadrata TT"
    settings.textFontSize = Clamp(tonumber(settings.textFontSize) or 12, 6, 72)
    settings.textFontOutline = type(settings.textFontOutline) == "string" and settings.textFontOutline or "OUTLINE"
    settings.textFontColor = CopyColor(settings.textFontColor) or { 1, 1, 1, 1 }
    settings.textBgColor = CopyColor(settings.textBgColor) or { 0, 0, 0, 0 }
    settings.textAlignment = (settings.textAlignment == "LEFT" or settings.textAlignment == "RIGHT") and settings.textAlignment or "CENTER"

    return settings
end

function CooldownCompanion.NormalizeTriggerPanelTextLineEndings(value)
    if type(value) ~= "string" then
        return ""
    end

    return string_gsub(string_gsub(value, "\r\n", "\n"), "\r", "\n")
end

function CooldownCompanion.SanitizeTriggerPanelTextValue(value)
    value = CooldownCompanion.NormalizeTriggerPanelTextLineEndings(value)

    local maxLength = CooldownCompanion.TRIGGER_PANEL_TEXT_MAX_LENGTH or 120
    if #value > maxLength then
        value = value:sub(1, maxLength)
    end

    local maxLines = CooldownCompanion.TRIGGER_PANEL_TEXT_MAX_LINES or 4
    local lineCount = 1
    local cutIndex = nil
    for index = 1, #value do
        if value:sub(index, index) == "\n" then
            lineCount = lineCount + 1
            if lineCount > maxLines then
                cutIndex = index - 1
                break
            end
        end
    end

    if cutIndex then
        value = value:sub(1, cutIndex)
    end

    return value
end

function CooldownCompanion.CountTriggerPanelTextLines(value)
    value = CooldownCompanion.NormalizeTriggerPanelTextLineEndings(value)
    if value == "" then
        return 1
    end

    local lineCount = 1
    for index = 1, #value do
        if value:sub(index, index) == "\n" then
            lineCount = lineCount + 1
        end
    end

    return lineCount
end

function CooldownCompanion:GetTriggerPanelDisplayType(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return "texture"
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return "texture"
        end
        group.triggerSettings = {}
    end

    group.triggerSettings.displayType = CooldownCompanion.NormalizeTriggerDisplayType(group.triggerSettings.displayType)
    return group.triggerSettings.displayType
end

function CooldownCompanion:GetTriggerPanelIconSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings = {}
    end

    if type(group.triggerSettings.icon) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings.icon = {
            manualIcon = nil,
            maintainAspectRatio = true,
            buttonSize = 36,
            iconWidth = 36,
            iconHeight = 36,
            borderSize = 1,
            borderColor = { 0, 0, 0, 1 },
            backgroundColor = { 0, 0, 0, 0.5 },
            iconTintColor = { 1, 1, 1, 1 },
        }
    end

    return CooldownCompanion.NormalizeTriggerIconSettings(group.triggerSettings.icon)
end

function CooldownCompanion:GetTriggerPanelTextSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings = {}
    end

    if type(group.triggerSettings.text) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings.text = {
            value = "",
            textFont = "Friz Quadrata TT",
            textFontSize = 12,
            textFontOutline = "OUTLINE",
            textFontColor = { 1, 1, 1, 1 },
            textBgColor = { 0, 0, 0, 0 },
        }
    end

    return CooldownCompanion.NormalizeTriggerTextSettings(group.triggerSettings.text)
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
        if not excluded[key] then
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

function CooldownCompanion:GetTriggerConditionStateValue(buttonData, clauseIndex)
    if type(buttonData) ~= "table" then
        return nil
    end

    local clause = self:GetTriggerConditionClauses(buttonData)[clauseIndex or 1]
    if not clause then
        return nil
    end

    local conditionKey = NormalizeTriggerConditionKey(buttonData, clause.key)
    if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
        return clause.expected == false and "false" or "true"
    end

    return NormalizeTriggerStateKey(conditionKey, clause.state)
end

function CooldownCompanion:SetTriggerConditionClauses(buttonData, clauses)
    if type(buttonData) ~= "table" then
        return
    end

    buttonData.triggerConditions = clauses
    self:NormalizeTriggerConditionRowData(buttonData)
end

function CooldownCompanion:SetTriggerConditionKey(buttonData, clauseIndex, conditionKey)
    if type(buttonData) ~= "table" then
        return
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    local clause = clauses[clauseIndex]
    if not clause then
        return
    end

    clause.key = conditionKey
    clause.expected = nil
    clause.state = nil
    self:SetTriggerConditionClauses(buttonData, clauses)
end

function CooldownCompanion:SetTriggerConditionStateValue(buttonData, value, clauseIndex)
    if type(buttonData) ~= "table" then
        return
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    local clause = clauses[clauseIndex or 1]
    if not clause then
        return
    end

    local conditionKey = NormalizeTriggerConditionKey(buttonData, clause.key)
    if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
        clause.expected = (value ~= "false")
        clause.state = nil
        self:SetTriggerConditionClauses(buttonData, clauses)
        return
    end

    clause.state = NormalizeTriggerStateKey(conditionKey, value)
    clause.expected = nil
    self:SetTriggerConditionClauses(buttonData, clauses)
end

function CooldownCompanion:AddTriggerConditionClause(buttonData, conditionKey)
    if type(buttonData) ~= "table" then
        return false
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    local excludedKeys = {}
    for _, clause in ipairs(clauses) do
        excludedKeys[#excludedKeys + 1] = clause.key
    end

    local _, order = self:GetTriggerConditionTypeOptions(buttonData, excludedKeys)
    if #order == 0 then
        return false
    end

    clauses[#clauses + 1] = { key = conditionKey or order[1] }
    self:SetTriggerConditionClauses(buttonData, clauses)
    return true
end

function CooldownCompanion:RemoveTriggerConditionClause(buttonData, clauseIndex)
    if type(buttonData) ~= "table" then
        return false
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    if #clauses <= 1 or not clauses[clauseIndex] then
        return false
    end

    table.remove(clauses, clauseIndex)
    self:SetTriggerConditionClauses(buttonData, clauses)
    return true
end

function CooldownCompanion:GetTriggerConditionSummary(buttonData)
    if type(buttonData) ~= "table" then
        return nil
    end

    local summaries = {}
    for _, clause in ipairs(self:GetTriggerConditionClauses(buttonData)) do
        local conditionKey = NormalizeTriggerConditionKey(buttonData, clause.key)
        local conditionLabel = TRIGGER_CONDITION_LABELS[conditionKey]
        local stateLabel
        if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
            stateLabel = (TRIGGER_EXPECTED_LABELS[conditionKey] or TRIGGER_EXPECTED_LABELS.cooldownActive)[clause.expected == false and "false" or "true"]
        else
            local stateKey = NormalizeTriggerStateKey(conditionKey, clause.state)
            stateLabel = TRIGGER_STATE_LABELS[conditionKey] and TRIGGER_STATE_LABELS[conditionKey][stateKey]
        end
        if conditionLabel and stateLabel then
            summaries[#summaries + 1] = conditionLabel .. " " .. stateLabel
        end
    end

    if #summaries == 0 then
        return nil
    end

    return table_concat(summaries, " AND ")
end

function CooldownCompanion:GetCompactTriggerConditionSummary(buttonData, maxVisibleClauses)
    if type(buttonData) ~= "table" then
        return nil
    end

    local count = #self:GetTriggerConditionClauses(buttonData)
    if count <= 0 then
        return nil
    end

    return "Conditions: " .. count
end

function CooldownCompanion:GetTexturePanelIndicatorSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.style) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.style = {}
    end

    if type(group.style.textureIndicators) ~= "table" and not createIfMissing then
        return nil
    end

    return NormalizeTextureIndicatorStore(group.style)
end

function CooldownCompanion:GetTextureIndicatorSectionOrder()
    return TEXTURE_INDICATOR_SECTION_ORDER
end


