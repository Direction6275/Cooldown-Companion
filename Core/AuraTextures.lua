--[[
    CooldownCompanion - Core/AuraTextures.lua
    Blizzard-first aura texture library, recent proc capture, and runtime
    texture rendering for aura-capable buttons.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local C_Item_IsUsableItem = C_Item.IsUsableItem
local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local GetTime = GetTime
local ipairs = ipairs
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
local FILTER_CLASS_AURAS = "classAuras"
local FILTER_OTHER = "other"
local FILTER_RECENT = "recent"
local MAX_RECENT_OVERLAYS = 200
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

local BUILTIN_LIBRARY = {}

local function AddBuiltinAtlas(categoryKey, atlas, width, height, subtitle, searchText, label)
    if type(atlas) ~= "string" or atlas == "" then
        return
    end

    BUILTIN_LIBRARY[#BUILTIN_LIBRARY + 1] = {
        key = "builtin:" .. categoryKey .. ":" .. atlas,
        label = label or string_trim(atlas),
        categoryKey = categoryKey or FILTER_OTHER,
        sourceType = "atlas",
        sourceValue = atlas,
        width = width,
        height = height,
        subtitle = subtitle,
        searchText = searchText or string_lower((label or atlas) .. " " .. (subtitle or "")),
    }
end

local ARTIFACT_RUNES_SUBTITLE = "Interface/Artifacts/ArtifactRunes"
local ARTIFACT_RUNES_ATLASES = {
    { "Rune-01-dark", 75, 77 },
    { "Rune-01-light", 75, 77 },
    { "Rune-02-dark", 75, 77 },
    { "Rune-02-light", 75, 77 },
    { "Rune-03-dark", 75, 77 },
    { "Rune-03-light", 75, 77 },
    { "Rune-04-dark", 75, 77 },
    { "Rune-04-light", 75, 77 },
    { "Rune-05-dark", 75, 77 },
    { "Rune-05-light", 75, 77 },
    { "Rune-06-dark", 75, 77 },
    { "Rune-06-light", 75, 77 },
    { "Rune-07-dark", 75, 77 },
    { "Rune-07-light", 75, 77 },
    { "Rune-08-dark", 75, 77 },
    { "Rune-08-light", 75, 77 },
    { "Rune-09-dark", 75, 77 },
    { "Rune-09-light", 75, 77 },
    { "Rune-10-dark ", 75, 77, "Rune-10-dark" },
    { "Rune-10-light", 75, 77 },
    { "Rune-11-dark", 75, 77 },
    { "Rune-11-light", 75, 77 },
}

for _, atlasInfo in ipairs(ARTIFACT_RUNES_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        ARTIFACT_RUNES_SUBTITLE,
        string_lower(label .. " artifact runes rune symbol artifacts"),
        label
    )
end

local FILTER_OPTIONS = {
    [FILTER_SYMBOLS] = "Symbols",
    [FILTER_CLASS_AURAS] = "Class Auras",
    [FILTER_OTHER] = "Other",
    [FILTER_RECENT] = "Recent Proc Overlays",
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

local function BuildRecentOverlayKey(fileDataID, locationType, scale, r, g, b)
    return string_format(
        "%s:%s:%s:%s:%s:%s",
        tostring(fileDataID),
        tostring(locationType),
        tostring(scale),
        tostring(r),
        tostring(g),
        tostring(b)
    )
end

local function BuildLocationSubtitle(locationType)
    local normalizedLocationType = NormalizeTextureLayout(locationType)
    return TEXTURE_LAYOUT_LABELS[normalizedLocationType] or "Single"
end

local function NormalizeAuraTextureSettings(settings)
    if type(settings) ~= "table" then
        return nil
    end

    settings.sourceType = settings.sourceType == "atlas" and "atlas" or (settings.sourceType == "file" and "file" or nil)
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

function CooldownCompanion:GetTexturePanelLocationOptions()
    local options = {}
    for _, locationType in ipairs(LOCATION_ORDER) do
        options[locationType] = TEXTURE_LAYOUT_LABELS[locationType]
    end
    return options, LOCATION_ORDER
end

local function ResolveGroup(groupOrId)
    if type(groupOrId) == "table" then
        return groupOrId
    end
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    return profile and profile.groups and profile.groups[groupOrId] or nil
end

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

function CooldownCompanion:ApplyTexturePanelEntry(settings, entry)
    if type(settings) ~= "table" or type(entry) ~= "table" then
        return
    end

    settings.sourceType = entry.sourceType
    settings.sourceValue = entry.sourceValue
    settings.label = entry.label
    settings.locationType = NormalizeTextureLayout(settings.locationType)
    settings.width = entry.width
    settings.height = entry.height
    settings.color = CopyColor(entry.color) or { 1, 1, 1, 1 }
    settings.blendMode = NormalizeBlendMode(entry.blendMode or settings.blendMode)
    settings.scale = Clamp(settings.scale or 1, 0.25, 4)
    settings.alpha = Clamp(settings.alpha or 1, 0.05, 1)
    settings.rotation = Clamp(settings.rotation or 0, MIN_TEXTURE_ROTATION, MAX_TEXTURE_ROTATION)
    settings.stretchX = Clamp(settings.stretchX or 0, MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH)
    settings.stretchY = Clamp(settings.stretchY or 0, MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH)
    settings.pairSpacing = Clamp(settings.pairSpacing or DEFAULT_TEXTURE_PAIR_SPACING, MIN_TEXTURE_PAIR_SPACING, MAX_TEXTURE_PAIR_SPACING)
    settings.point = NormalizeAnchorPoint(settings.point or "CENTER")
    settings.relativePoint = NormalizeAnchorPoint(settings.relativePoint or "CENTER")
    settings.relativeTo = UI_PARENT_NAME
    settings.x = tonumber(settings.x) or 0
    settings.y = tonumber(settings.y) or 0
end

function CooldownCompanion:CreateTexturePanelSelection(entry, baseSettings)
    if type(entry) ~= "table" then
        return nil
    end

    local base = type(baseSettings) == "table" and NormalizeAuraTextureSettings(baseSettings) or nil
    local selection = {
        sourceType = entry.sourceType,
        sourceValue = entry.sourceValue,
        label = entry.label,
        scale = base and base.scale or entry.scale or 1,
        alpha = base and base.alpha or 1,
        blendMode = NormalizeBlendMode((base and base.blendMode) or entry.blendMode),
        rotation = base and base.rotation or 0,
        stretchX = base and base.stretchX or 0,
        stretchY = base and base.stretchY or 0,
        point = base and base.point or "CENTER",
        relativePoint = base and base.relativePoint or "CENTER",
        relativeTo = UI_PARENT_NAME,
        x = base and base.x or 0,
        y = base and base.y or 0,
        color = CopyColor(base and base.color) or CopyColor(entry.color) or { 1, 1, 1, 1 },
        locationType = base and base.locationType or LOCATION_CENTER,
        pairSpacing = base and base.pairSpacing or DEFAULT_TEXTURE_PAIR_SPACING,
        width = entry.width,
        height = entry.height,
    }

    return NormalizeAuraTextureSettings(selection)
end

function CooldownCompanion:GetTexturePanelSelectionLabel(groupOrId)
    local settings = self:GetTexturePanelSettings(groupOrId)
    if not settings or not settings.sourceType then
        return nil
    end
    return settings.label or tostring(settings.sourceValue)
end

function CooldownCompanion:EnsureAuraTextureLibraryStore()
    local profile = self.db and self.db.profile
    if not profile then
        return nil
    end
    if type(profile.auraTextureLibrary) ~= "table" then
        profile.auraTextureLibrary = {
            recentProcOverlays = {},
        }
    elseif type(profile.auraTextureLibrary.recentProcOverlays) ~= "table" then
        profile.auraTextureLibrary.recentProcOverlays = {}
    end
    return profile.auraTextureLibrary
end

function CooldownCompanion:RecordRecentAuraTextureOverlay(spellID, fileDataID, locationType, scale, r, g, b)
    if type(fileDataID) ~= "number" or fileDataID <= 0 then
        return
    end

    local store = self:EnsureAuraTextureLibraryStore()
    if not store then
        return
    end

    local key = BuildRecentOverlayKey(fileDataID, locationType, scale, r, g, b)
    local recent = store.recentProcOverlays
    local spellName = C_Spell.GetSpellName(spellID) or ("Spell " .. tostring(spellID))

    recent[key] = {
        key = key,
        spellID = spellID,
        spellName = spellName,
        label = spellName .. " Proc Overlay",
        sourceType = "file",
        sourceValue = fileDataID,
        locationType = NormalizeTextureLayout(locationType),
        color = {
            Clamp((tonumber(r) or 255) / 255, 0, 1),
            Clamp((tonumber(g) or 255) / 255, 0, 1),
            Clamp((tonumber(b) or 255) / 255, 0, 1),
            1,
        },
        blendMode = "ADD",
        scale = tonumber(scale) or 1,
        lastSeenAt = time(),
    }

    local keys = {}
    for overlayKey in pairs(recent) do
        keys[#keys + 1] = overlayKey
    end
    if #keys <= MAX_RECENT_OVERLAYS then
        return
    end

    table_sort(keys, function(a, b)
        local aTime = recent[a] and recent[a].lastSeenAt or 0
        local bTime = recent[b] and recent[b].lastSeenAt or 0
        return aTime > bTime
    end)

    for index = MAX_RECENT_OVERLAYS + 1, #keys do
        recent[keys[index]] = nil
    end
end

function CooldownCompanion:GetRecentAuraTextureEntries()
    local store = self:EnsureAuraTextureLibraryStore()
    local entries = {}
    local recent = store and store.recentProcOverlays or nil

    if recent then
        for key, entry in pairs(recent) do
            local label = entry.label or entry.spellName or ("File " .. tostring(entry.sourceValue))
            entries[#entries + 1] = {
                key = "recent:" .. key,
                label = label,
                category = "Recent Proc Overlays",
                sourceType = "file",
                sourceValue = entry.sourceValue,
                locationType = (NormalizeTextureLayout(entry.locationType)),
                color = CopyColor(entry.color) or { 1, 1, 1, 1 },
                blendMode = NormalizeBlendMode(entry.blendMode),
                subtitle = tostring(entry.spellID or "?") .. "  |  File " .. tostring(entry.sourceValue) .. "  |  " .. BuildLocationSubtitle(entry.locationType),
                searchText = string_lower(label .. " " .. tostring(entry.spellID or "") .. " " .. tostring(entry.sourceValue) .. " " .. BuildLocationSubtitle(entry.locationType)),
                lastSeenAt = entry.lastSeenAt or 0,
            }
        end
    end

    table_sort(entries, function(a, b)
        local aTime = a.lastSeenAt or 0
        local bTime = b.lastSeenAt or 0
        if aTime == bTime then
            return a.label < b.label
        end
        return aTime > bTime
    end)

    return entries
end

local function BuildBuiltinEntries()
    local entries = {}
    for _, entry in ipairs(BUILTIN_LIBRARY) do
        entries[#entries + 1] = {
            key = entry.key,
            label = entry.label,
            categoryKey = entry.categoryKey or FILTER_OTHER,
            category = entry.category or FILTER_OPTIONS[entry.categoryKey] or FILTER_OPTIONS[FILTER_OTHER],
            sourceType = entry.sourceType,
            sourceValue = entry.sourceValue,
            width = entry.width,
            height = entry.height,
            color = CopyColor(entry.color) or { 1, 1, 1, 1 },
            blendMode = NormalizeBlendMode(entry.blendMode),
            subtitle = entry.subtitle,
            searchText = entry.searchText or string_lower(entry.label),
        }
    end
    return entries
end

function CooldownCompanion:GetAuraTexturePickerEntries(searchText, filterValue)
    local query = type(searchText) == "string" and string_lower(string_trim(searchText)) or ""
    local filter = FILTER_OPTIONS[filterValue] and filterValue or FILTER_SYMBOLS
    local entries = {}

    if filter == FILTER_RECENT then
        for _, entry in ipairs(self:GetRecentAuraTextureEntries()) do
            if query == "" or string_find(entry.searchText, query, 1, true) then
                entries[#entries + 1] = entry
            end
        end
        return entries
    end

    for _, entry in ipairs(BuildBuiltinEntries()) do
        if entry.categoryKey == filter and (query == "" or string_find(entry.searchText, query, 1, true)) then
            entries[#entries + 1] = entry
        end
    end

    table_sort(entries, function(a, b)
        return a.label < b.label
    end)

    return entries
end

function CooldownCompanion:GetAuraTexturePickerFilters()
    return FILTER_OPTIONS, { FILTER_SYMBOLS, FILTER_CLASS_AURAS, FILTER_OTHER, FILTER_RECENT }
end

function CooldownCompanion:GetAuraTexturePickerFilterForSelection(selection)
    if type(selection) ~= "table" then
        return FILTER_SYMBOLS
    end

    for _, entry in ipairs(BuildBuiltinEntries()) do
        if entry.sourceType == selection.sourceType and entry.sourceValue == selection.sourceValue then
            return entry.categoryKey or FILTER_OTHER
        end
    end

    if selection.sourceType == "file" then
        return FILTER_RECENT
    end

    return FILTER_SYMBOLS
end

local function ApplyTextureSource(texture, settings)
    if settings.sourceType == "atlas" then
        if type(settings.sourceValue) ~= "string" or not C_Texture.GetAtlasExists(settings.sourceValue) then
            texture:Hide()
            return false
        end
        texture:SetAtlas(settings.sourceValue, false)
        return true
    end

    if settings.sourceType == "file" then
        texture:SetTexture(settings.sourceValue)
        return true
    end

    texture:Hide()
    return false
end

local function ApplyTextureVisual(texture, settings, alpha, flipH, flipV, rotationRadians)
    local left, right, top, bottom = 0, 1, 0, 1
    if flipH then
        left, right = 1, 0
    end
    if flipV then
        top, bottom = 1, 0
    end
    texture:SetTexCoord(left, right, top, bottom)
    texture:SetBlendMode(settings.blendMode)
    local color = settings.color or { 1, 1, 1, 1 }
    texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha)
    texture:SetRotation(rotationRadians or 0)
    texture:Show()
end

function CooldownCompanion:BuildTexturePanelGeometry(settings, baseWidth, baseHeight)
    local dims = LOCATION_DIMENSIONS[settings.locationType] or LOCATION_DIMENSIONS[LOCATION_CENTER]
    local pieceWidth = math_max(1, (baseWidth or DEFAULT_TEXTURE_SIZE) * (dims.width or 1) * GetStretchMultiplier(settings.stretchX))
    local pieceHeight = math_max(1, (baseHeight or DEFAULT_TEXTURE_SIZE) * (dims.height or 1) * GetStretchMultiplier(settings.stretchY))
    local rotationRadians = math_rad(tonumber(settings.rotation) or 0)
    local pairSpacing = tonumber(settings.pairSpacing) or DEFAULT_TEXTURE_PAIR_SPACING
    local gap = 0
    local pieces = {
        { centerX = 0, centerY = 0, flipH = false, flipV = false },
    }

    if dims.layout == "pair_horizontal" then
        gap = pieceWidth * pairSpacing
        local centerOffset = (pieceWidth + gap) / 2
        pieces = {
            { centerX = -centerOffset, centerY = 0, flipH = false, flipV = false },
            { centerX = centerOffset, centerY = 0, flipH = true, flipV = false },
        }
    elseif dims.layout == "pair_vertical" then
        gap = pieceHeight * pairSpacing
        local centerOffset = (pieceHeight + gap) / 2
        pieces = {
            { centerX = 0, centerY = -centerOffset, flipH = false, flipV = false },
            { centerX = 0, centerY = centerOffset, flipH = false, flipV = true },
        }
    end

    local rotatedPieceWidth = math_max(1, (math_abs(pieceWidth * math_cos(rotationRadians)) + math_abs(pieceHeight * math_sin(rotationRadians))))
    local rotatedPieceHeight = math_max(1, (math_abs(pieceWidth * math_sin(rotationRadians)) + math_abs(pieceHeight * math_cos(rotationRadians))))
    local minLeft, maxRight = nil, nil
    local minBottom, maxTop = nil, nil

    for _, piece in ipairs(pieces) do
        local centerX, centerY = RotateOffset(piece.centerX, piece.centerY, rotationRadians)
        piece.centerX = centerX
        piece.centerY = centerY

        local left = centerX - (rotatedPieceWidth / 2)
        local right = centerX + (rotatedPieceWidth / 2)
        local bottom = centerY - (rotatedPieceHeight / 2)
        local top = centerY + (rotatedPieceHeight / 2)

        minLeft = minLeft and math_min(minLeft, left) or left
        maxRight = maxRight and math_max(maxRight, right) or right
        minBottom = minBottom and math_min(minBottom, bottom) or bottom
        maxTop = maxTop and math_max(maxTop, top) or top
    end

    return {
        rotationRadians = rotationRadians,
        pieceWidth = pieceWidth,
        pieceHeight = pieceHeight,
        rotatedPieceWidth = rotatedPieceWidth,
        rotatedPieceHeight = rotatedPieceHeight,
        boundsWidth = math_max(1, (maxRight or (rotatedPieceWidth / 2)) - (minLeft or -(rotatedPieceWidth / 2))),
        boundsHeight = math_max(1, (maxTop or (rotatedPieceHeight / 2)) - (minBottom or -(rotatedPieceHeight / 2))),
        pieces = pieces,
        layout = dims.layout or "single",
        gap = gap,
    }
end

local function LayoutTexturePieces(host, settings, geometry, alpha)
    local visualRoot = host.visualRoot or host
    local textures = {
        host.primaryTexture,
        host.secondaryTexture,
    }
    local shown = false

    for index, texture in ipairs(textures) do
        local piece = geometry.pieces[index]
        if not texture or not piece then
            if texture then
                texture:Hide()
            end
        else
            texture:ClearAllPoints()
            texture:SetSize(geometry.pieceWidth, geometry.pieceHeight)
            texture:SetPoint("CENTER", visualRoot, "CENTER", piece.centerX, piece.centerY)

            if ApplyTextureSource(texture, settings) then
                ApplyTextureVisual(texture, settings, alpha, piece.flipH, piece.flipV, geometry.rotationRadians)
                shown = true
            else
                texture:Hide()
            end
        end
    end

    return shown
end

local function SetTextureIndicatorBaseVisuals(host)
    if not host then
        return
    end

    local settings = host._activeTextureSettings
    local geometry = host._activeTextureGeometry
    if not settings or not geometry then
        return
    end

    local color = settings.color or { 1, 1, 1, 1 }
    local baseAlpha = Clamp((color[4] or 1) * (settings.alpha or 1), 0.05, 1)
    local textures = {
        host.primaryTexture,
        host.secondaryTexture,
    }

    for index, texture in ipairs(textures) do
        local piece = geometry.pieces[index]
        if texture and piece and texture:IsShown() then
            ApplyTextureVisual(texture, settings, baseAlpha, piece.flipH, piece.flipV, geometry.rotationRadians)
        end
    end

    host._indicatorBaseAlpha = baseAlpha
    host._indicatorBaseColor = CopyColor(color) or { 1, 1, 1, 1 }
end

local function ResetTextureIndicatorTransformState(host)
    if not host or not host.visualRoot then
        return
    end

    host.visualRoot:SetScale(1)
    host.visualRoot:ClearAllPoints()
    host.visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
end

local function GetTextureIndicatorLoopPhase(now, duration)
    duration = Clamp(tonumber(duration) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    local progress = now / duration
    return progress - math_floor(progress)
end

local TextureIndicatorOnUpdate

local function RefreshTextureIndicatorUpdater(host)
    if not host or not host.visualRoot then
        return
    end

    local wantsManualUpdate = host._textureColorShiftActive
        or host._textureShrinkActive
        or host._textureBounceActive

    if not wantsManualUpdate or not host._activeTextureSettings or not host._activeTextureGeometry then
        host:SetScript("OnUpdate", nil)
        ResetTextureIndicatorTransformState(host)
        SetTextureIndicatorBaseVisuals(host)
        return
    end

    host:SetScript("OnUpdate", TextureIndicatorOnUpdate)
    TextureIndicatorOnUpdate(host, 0)
end

TextureIndicatorOnUpdate = function(self)
    if not self or not self.visualRoot or not self._activeTextureSettings or not self._activeTextureGeometry then
        RefreshTextureIndicatorUpdater(self)
        return
    end

    local settings = self._activeTextureSettings
    local now = GetTime()
    SetTextureIndicatorBaseVisuals(self)
    local baseColor = self._indicatorBaseColor or { 1, 1, 1, 1 }
    local baseAlpha = self._indicatorBaseAlpha or 1

    if self._textureColorShiftActive then
        local shift = self._textureColorShiftColor or { 1, 1, 1, 1 }
        local colorPhase = GetTextureIndicatorLoopPhase(now, self._textureColorShiftSpeed)
        local t = 0.5 - (0.5 * math_cos(colorPhase * 2 * math_pi))
        local shiftAlpha = Clamp((shift[4] or 1) * (settings.alpha or 1), 0.05, 1)
        local alpha = baseAlpha + ((shiftAlpha - baseAlpha) * t)

        local primaryTexture = self.primaryTexture
        if primaryTexture and primaryTexture:IsShown() then
            primaryTexture:SetVertexColor(
                (baseColor[1] or 1) + (((shift[1] or 1) - (baseColor[1] or 1)) * t),
                (baseColor[2] or 1) + (((shift[2] or 1) - (baseColor[2] or 1)) * t),
                (baseColor[3] or 1) + (((shift[3] or 1) - (baseColor[3] or 1)) * t),
                alpha
            )
        end

        local secondaryTexture = self.secondaryTexture
        if secondaryTexture and secondaryTexture:IsShown() then
            secondaryTexture:SetVertexColor(
                (baseColor[1] or 1) + (((shift[1] or 1) - (baseColor[1] or 1)) * t),
                (baseColor[2] or 1) + (((shift[2] or 1) - (baseColor[2] or 1)) * t),
                (baseColor[3] or 1) + (((shift[3] or 1) - (baseColor[3] or 1)) * t),
                alpha
            )
        end
    end

    local scale = 1
    if self._textureShrinkActive then
        local shrinkPhase = GetTextureIndicatorLoopPhase(
            now - (self._textureShrinkStartTime or now),
            self._textureShrinkSpeed
        )
        local shrinkT = 0.5 - (0.5 * math_cos(shrinkPhase * 2 * math_pi))
        scale = 1 - ((1 - DEFAULT_TEXTURE_SHRINK_SCALE) * shrinkT)
    end
    self.visualRoot:SetScale(scale)

    local bounceOffsetY = 0
    if self._textureBounceActive then
        local bouncePhase = GetTextureIndicatorLoopPhase(
            now - (self._textureBounceStartTime or now),
            self._textureBounceSpeed
        )
        local amplitude = self._textureBounceAmplitude or DEFAULT_TEXTURE_BOUNCE_PIXELS
        if bouncePhase < 0.5 then
            local riseT = bouncePhase / 0.5
            bounceOffsetY = amplitude * (1 - ((1 - riseT) * (1 - riseT)))
        else
            local fallT = (bouncePhase - 0.5) / 0.5
            bounceOffsetY = amplitude * (1 - (fallT * fallT))
        end
    end

    self.visualRoot:ClearAllPoints()
    self.visualRoot:SetPoint("CENTER", self, "CENTER", 0, bounceOffsetY)
end

local function StopTextureIndicatorAnimation(host, effectType)
    if not host or not host.visualRoot or not host._textureIndicatorAnimations then
        return
    end

    local animData = host._textureIndicatorAnimations[effectType]
    if not animData or not animData.group then
        return
    end

    animData.group:Stop()
end

local function EnsureTextureIndicatorAnimation(host, effectType)
    if not host or not host.visualRoot then
        return nil
    end

    host._textureIndicatorAnimations = host._textureIndicatorAnimations or {}
    local existing = host._textureIndicatorAnimations[effectType]
    if existing then
        return existing
    end

    local visualRoot = host.visualRoot
    local group = visualRoot:CreateAnimationGroup()
    group:SetLooping("BOUNCE")

    local animData = { group = group }
    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE then
        local alphaAnim = group:CreateAnimation("Alpha")
        alphaAnim:SetFromAlpha(1)
        alphaAnim:SetToAlpha(DEFAULT_TEXTURE_PULSE_ALPHA)
        animData.alpha = alphaAnim
    elseif effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND then
        local scaleAnim = group:CreateAnimation("Scale")
        scaleAnim:SetScaleFrom(1, 1)
        scaleAnim:SetScaleTo(DEFAULT_TEXTURE_SHRINK_SCALE, DEFAULT_TEXTURE_SHRINK_SCALE)
        scaleAnim:SetOrigin("CENTER", 0, 0)
        animData.scale = scaleAnim
    elseif effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        local translation = group:CreateAnimation("Translation")
        translation:SetOffset(0, DEFAULT_TEXTURE_BOUNCE_PIXELS)
        animData.translation = translation
    end

    host._textureIndicatorAnimations[effectType] = animData
    return animData
end

local function SetTextureIndicatorAnimation(host, effectType, active, speed, amplitude)
    if not host or not host.visualRoot then
        return
    end

    if effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND then
        local wasActive = host._textureShrinkActive == true
        host._textureShrinkActive = active and true or nil
        host._textureShrinkSpeed = active and Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED) or nil
        if host._textureShrinkActive and not wasActive then
            host._textureShrinkStartTime = GetTime()
        elseif not host._textureShrinkActive then
            host._textureShrinkStartTime = nil
        end
        RefreshTextureIndicatorUpdater(host)
        return
    elseif effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        local wasActive = host._textureBounceActive == true
        host._textureBounceActive = active and true or nil
        host._textureBounceSpeed = active and Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED) or nil
        host._textureBounceAmplitude = active and (amplitude or DEFAULT_TEXTURE_BOUNCE_PIXELS) or nil
        if host._textureBounceActive and not wasActive then
            host._textureBounceStartTime = GetTime()
        elseif not host._textureBounceActive then
            host._textureBounceStartTime = nil
        end
        RefreshTextureIndicatorUpdater(host)
        return
    end

    if not active then
        StopTextureIndicatorAnimation(host, effectType)
        if effectType == TEXTURE_INDICATOR_EFFECT_PULSE then
            host.visualRoot:SetAlpha(1)
        end
        return
    end

    local animData = EnsureTextureIndicatorAnimation(host, effectType)
    if not animData then
        return
    end

    speed = Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE and animData.alpha then
        animData.alpha:SetDuration(speed)
    end

    if not animData.group:IsPlaying() then
        animData.group:Play()
    end
end

local function StopTextureColorShift(host)
    if not host then
        return
    end

    host._textureColorShiftActive = nil
    RefreshTextureIndicatorUpdater(host)
end

local function StartTextureColorShift(host, shiftColor, speed)
    if not host then
        return
    end

    host._textureColorShiftActive = true
    host._textureColorShiftColor = CopyColor(shiftColor) or { 1, 1, 1, 1 }
    host._textureColorShiftSpeed = Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    RefreshTextureIndicatorUpdater(host)
end

local function StopAllTextureIndicatorEffects(host)
    if not host or not host.visualRoot then
        return
    end

    StopTextureIndicatorAnimation(host, TEXTURE_INDICATOR_EFFECT_PULSE)
    host._textureShrinkActive = nil
    host._textureShrinkSpeed = nil
    host._textureShrinkStartTime = nil
    host._textureBounceActive = nil
    host._textureBounceSpeed = nil
    host._textureBounceAmplitude = nil
    host._textureBounceStartTime = nil
    host._textureColorShiftActive = nil
    host._textureColorShiftColor = nil
    host._textureColorShiftSpeed = nil
    host.visualRoot:SetAlpha(1)
    ResetTextureIndicatorTransformState(host)
    host:SetScript("OnUpdate", nil)
    SetTextureIndicatorBaseVisuals(host)
end

local function IsTextureIndicatorSectionActive(button, sectionKey, config)
    if not button or type(config) ~= "table" or not config.enabled then
        return false
    end

    if sectionKey == "proc" and button._textureProcPreview then
        return true
    end
    if sectionKey == "aura" and button._textureAuraPreview then
        return true
    end
    if sectionKey == "pandemic" and button._texturePandemicPreview then
        return true
    end
    if sectionKey == "ready" and button._textureReadyPreview then
        return true
    end
    if sectionKey == "unusable" and button._textureUnusablePreview then
        return true
    end

    if config.combatOnly and not InCombatLockdown() then
        return false
    end

    if sectionKey == "proc" then
        return button._procOverlayActive == true
    end

    if sectionKey == "aura" then
        if button._auraTrackingReady ~= true or not button._auraSpellID then
            return false
        end
        if config.invert then
            if button._auraUnit == "target" and not UnitExists("target") then
                return false
            end
            return button._auraActive ~= true
        end
        return button._auraActive == true
    end

    if sectionKey == "pandemic" then
        return button._auraActive == true and button._inPandemic == true
    end

    if sectionKey == "ready" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive or button._noCooldown then
            return false
        end
        return button._desatCooldownActive == false
    end

    if sectionKey == "unusable" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive then
            return false
        end
        if buttonData.type == "spell" then
            return not C_Spell_IsSpellUsable(buttonData.id)
        end
        if buttonData.type == "item" or buttonData.type == "equipitem" then
            return not C_Item_IsUsableItem(buttonData.id)
        end
        return false
    end

    return false
end

local function ApplyTextureIndicatorEffects(host, button, group)
    if not host or not button or type(group) ~= "table" then
        return
    end

    local indicators = CooldownCompanion:GetTexturePanelIndicatorSettings(group)
    if not indicators then
        StopAllTextureIndicatorEffects(host)
        return
    end

    local effectStates = {}
    for _, sectionKey in ipairs(TEXTURE_INDICATOR_SECTION_ORDER) do
        local config = indicators[sectionKey]
        if IsTextureIndicatorSectionActive(button, sectionKey, config) then
            local effectType = NormalizeTextureIndicatorEffect(config.effectType)
            if effectType ~= TEXTURE_INDICATOR_EFFECT_NONE and not effectStates[effectType] then
                effectStates[effectType] = config
            end
        end
    end

    local bounceAmplitude = math_max(6, math_min(DEFAULT_TEXTURE_BOUNCE_PIXELS, (host._activeTextureGeometry and host._activeTextureGeometry.boundsHeight or DEFAULT_TEXTURE_BOUNCE_PIXELS) * 0.12))

    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_PULSE,
        effectStates[TEXTURE_INDICATOR_EFFECT_PULSE] ~= nil,
        effectStates[TEXTURE_INDICATOR_EFFECT_PULSE] and effectStates[TEXTURE_INDICATOR_EFFECT_PULSE].speed or nil
    )
    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND,
        effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND] ~= nil,
        effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND] and effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND].speed or nil
    )
    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_BOUNCE,
        effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE] ~= nil,
        effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE] and effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE].speed or nil,
        bounceAmplitude
    )

    local colorShift = effectStates[TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT]
    if colorShift then
        StartTextureColorShift(host, colorShift.color, colorShift.speed)
    else
        StopTextureColorShift(host)
    end
end

local function CreateAuraTextureOutline(host)
    local fill = host:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", host, "TOPLEFT", -4, 4)
    fill:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 4, -4)
    fill:SetColorTexture(0.05, 0.35, 0.5, 0.12)
    fill:Hide()

    local edges = {}
    local edgeSpecs = {
        { point1 = "TOPLEFT", point2 = "TOPRIGHT", x1 = -4, y1 = 4, x2 = 4, y2 = 4, width = 1, height = nil },
        { point1 = "BOTTOMLEFT", point2 = "BOTTOMRIGHT", x1 = -4, y1 = -4, x2 = 4, y2 = -4, width = 1, height = nil },
        { point1 = "TOPLEFT", point2 = "BOTTOMLEFT", x1 = -4, y1 = 4, x2 = -4, y2 = -4, width = nil, height = 1 },
        { point1 = "TOPRIGHT", point2 = "BOTTOMRIGHT", x1 = 4, y1 = 4, x2 = 4, y2 = -4, width = nil, height = 1 },
    }

    for index, spec in ipairs(edgeSpecs) do
        local edge = host:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(0.2, 0.8, 1, 0.95)
        edge:SetPoint(spec.point1, host, spec.point1, spec.x1, spec.y1)
        edge:SetPoint(spec.point2, host, spec.point2, spec.x2, spec.y2)
        if spec.width then
            edge:SetHeight(spec.width)
        end
        if spec.height then
            edge:SetWidth(spec.height)
        end
        edge:Hide()
        edges[index] = edge
    end

    host.auraTextureOutlineFill = fill
    host.auraTextureOutlineEdges = edges
end

local function SetAuraTextureOutlineShown(host, shown)
    if not host.auraTextureOutlineFill then
        CreateAuraTextureOutline(host)
    end

    host.auraTextureOutlineFill:SetShown(shown)
    for _, edge in ipairs(host.auraTextureOutlineEdges or {}) do
        edge:SetShown(shown)
    end
end

local function UpdateTextureHostCoordLabel(host, x, y)
    if host and host.coordLabel and host.coordLabel.text then
        host.coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x or 0, y or 0))
    end
end

local function SaveTextureHostPosition(host)
    if not host then
        return
    end

    local owner = host._ownerButton
    local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
    local settings = group and CooldownCompanion:GetTexturePanelSettings(group)
    if not settings or not settings.sourceType then
        return
    end

    local point, _, relPoint, x, y = host:GetPoint(1)
    settings.point = NormalizeAnchorPoint(point)
    settings.relativePoint = NormalizeAnchorPoint(relPoint)
    settings.relativeTo = UI_PARENT_NAME
    settings.x = math_floor(((x or 0) * 10) + 0.5) / 10
    settings.y = math_floor(((y or 0) * 10) + 0.5) / 10

    UpdateTextureHostCoordLabel(host, settings.x, settings.y)
    CooldownCompanion:UpdateAuraTextureVisual(owner)
    if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function EnsureAuraTextureNudger(host)
    if host.nudger then
        return
    end

    local nudger = CreateFrame("Frame", nil, host.dragHandle, "BackdropTemplate")
    nudger:SetSize(NUDGE_BTN_SIZE * 2 + NUDGE_GAP, NUDGE_BTN_SIZE * 2 + NUDGE_GAP)
    nudger:SetPoint("BOTTOM", host.dragHandle, "TOP", 0, 2)
    nudger:SetFrameStrata(host.dragHandle:GetFrameStrata())
    nudger:SetFrameLevel(host.dragHandle:GetFrameLevel() + 5)
    nudger:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    nudger:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(nudger)
    nudger.buttons = {}

    local directions = {
        { atlas = "common-dropdown-icon-back", rotation = -math_pi / 2, anchor = "BOTTOM", dx =  0, dy =  1, ox = 0,         oy = NUDGE_GAP },
        { atlas = "common-dropdown-icon-next", rotation = -math_pi / 2, anchor = "TOP",    dx =  0, dy = -1, ox = 0,         oy = -NUDGE_GAP },
        { atlas = "common-dropdown-icon-back", rotation = 0,            anchor = "RIGHT",  dx = -1, dy =  0, ox = -NUDGE_GAP, oy = 0 },
        { atlas = "common-dropdown-icon-next", rotation = 0,            anchor = "LEFT",   dx =  1, dy =  0, ox = NUDGE_GAP,  oy = 0 },
    }

    local function DoNudge(dx, dy)
        host:AdjustPointsOffset(dx, dy)
        local _, _, _, x, y = host:GetPoint()
        local owner = host._ownerButton
        local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
        local settings = group and CooldownCompanion:GetTexturePanelSettings(group)
        if settings then
            settings.x = math_floor((x or 0) * 10 + 0.5) / 10
            settings.y = math_floor((y or 0) * 10 + 0.5) / 10
        end
        UpdateTextureHostCoordLabel(host, x, y)
    end

    for _, dir in ipairs(directions) do
        local btn = CreateFrame("Button", nil, nudger)
        btn:SetSize(NUDGE_BTN_SIZE, NUDGE_BTN_SIZE)
        btn:SetPoint(dir.anchor, nudger, "CENTER", dir.ox, dir.oy)
        btn:EnableMouse(true)
        nudger.buttons[#nudger.buttons + 1] = btn

        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetAtlas(dir.atlas)
        arrow:SetAllPoints()
        arrow:SetRotation(dir.rotation)
        arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
        btn.arrow = arrow

        btn:SetScript("OnEnter", function(self)
            self.arrow:SetVertexColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
            SaveTextureHostPosition(host)
        end)

        btn:SetScript("OnMouseDown", function(self)
            DoNudge(dir.dx, dir.dy)
            self.nudgeDelayTimer = C_Timer.NewTimer(NUDGE_REPEAT_DELAY, function()
                self.nudgeTicker = C_Timer.NewTicker(NUDGE_REPEAT_INTERVAL, function()
                    DoNudge(dir.dx, dir.dy)
                end)
            end)
        end)

        btn:SetScript("OnMouseUp", function(self)
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
            SaveTextureHostPosition(host)
        end)
    end

    host.nudger = nudger
end

local function EnsureAuraTextureDragHandle(host)
    if host.dragHandle then
        return
    end

    local dragHandle = CreateFrame("Frame", nil, host, "BackdropTemplate")
    dragHandle:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 2)
    dragHandle:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, 2)
    dragHandle:SetHeight(15)
    dragHandle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    dragHandle:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(dragHandle)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:EnableMouse(true)

    local text = dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 1, 1, 1)
    dragHandle.text = text

    local coordLabel = CreateFrame("Frame", nil, dragHandle, "BackdropTemplate")
    coordLabel:SetHeight(15)
    coordLabel:SetPoint("TOPLEFT", dragHandle, "BOTTOMLEFT", 0, -2)
    coordLabel:SetPoint("TOPRIGHT", dragHandle, "BOTTOMRIGHT", 0, -2)
    coordLabel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    coordLabel:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(coordLabel)
    coordLabel.text = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coordLabel.text:SetPoint("CENTER")
    coordLabel.text:SetTextColor(1, 1, 1, 1)

    dragHandle:SetScript("OnDragStart", function()
        if host._dragEnabled then
            host._isDragging = true
            host:StartMoving()
        end
    end)
    dragHandle:SetScript("OnDragStop", function()
        host._isDragging = nil
        host:StopMovingOrSizing()
        SaveTextureHostPosition(host)
    end)
    dragHandle:SetScript("OnMouseUp", function(_, button)
        if button ~= "MiddleButton" then
            return
        end

        local owner = host._ownerButton
        local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
        if not group then
            return
        end

        group.locked = nil
        CooldownCompanion:RefreshGroupFrame(owner._groupId)
        CooldownCompanion:RefreshAllAuraTextureVisuals()
        if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
            CooldownCompanion:RefreshConfigPanel()
        end
        CooldownCompanion:Print((group.name or "Texture Panel") .. " locked.")
    end)

    host.dragHandle = dragHandle
    host.coordLabel = coordLabel
    EnsureAuraTextureNudger(host)
end

local function SyncAuraTextureControlLevels(host)
    if not host then
        return
    end

    local strata = host:GetFrameStrata()
    local baseLevel = host:GetFrameLevel() or 1

    if host.dragHandle then
        host.dragHandle:SetFrameStrata(strata)
        host.dragHandle:SetFrameLevel(baseLevel + 5)
    end
    if host.coordLabel then
        host.coordLabel:SetFrameStrata(strata)
        host.coordLabel:SetFrameLevel(baseLevel + 6)
    end
    if host.nudger then
        host.nudger:SetFrameStrata(strata)
        host.nudger:SetFrameLevel(baseLevel + 10)
        for index, btn in ipairs(host.nudger.buttons or {}) do
            btn:SetFrameStrata(strata)
            btn:SetFrameLevel(baseLevel + 11 + index)
        end
    end
end

local function EnsureAuraTextureHost(button)
    if button.auraTextureHost then
        return button.auraTextureHost
    end

    local host = CreateFrame("Frame", nil, UIParent)
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    host:EnableMouse(false)
    host:Hide()
    host._ownerButton = button

    local visualRoot = CreateFrame("Frame", nil, host)
    visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
    visualRoot:SetSize(1, 1)
    host.visualRoot = visualRoot

    local primary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    local secondary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    primary:Hide()
    secondary:Hide()
    host.primaryTexture = primary
    host.secondaryTexture = secondary

    host:SetScript("OnDragStart", function(self)
        if not self._dragEnabled then
            return
        end
        self._isDragging = true
        self:StartMoving()
    end)

    host:SetScript("OnDragStop", function(self)
        self._isDragging = nil
        self:StopMovingOrSizing()
        SaveTextureHostPosition(self)
    end)

    CreateAuraTextureOutline(host)
    EnsureAuraTextureDragHandle(host)
    button.auraTextureHost = host
    return host
end

local function GetTexturePanelAlphaModuleId(groupId)
    if not groupId then
        return nil
    end
    return "texture_panel_" .. tostring(groupId)
end

local function GetTexturePanelLayoutPreviewAlpha(button)
    local CS = ST._configState
    if not button or not CS or CS.panelSettingsTab ~= "layout" or CS.selectedGroup ~= button._groupId then
        return nil
    end

    local preview = CS.texturePanelAlphaPreview
    if type(preview) ~= "table" then
        return nil
    end

    return preview[button._groupId]
end

function CooldownCompanion:HideAuraTextureVisual(button)
    local alphaModuleId = button and GetTexturePanelAlphaModuleId(button._groupId) or nil
    if alphaModuleId then
        self:UnregisterModuleAlpha(alphaModuleId, true)
    end

    local host = button and button.auraTextureHost
    if not host then
        return
    end

    StopAllTextureIndicatorEffects(host)
    if host._isDragging then
        host._isDragging = nil
        host:StopMovingOrSizing()
    end
    host.primaryTexture:Hide()
    host.secondaryTexture:Hide()
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._dragEnabled = nil
    host:EnableMouse(false)
    host:SetAlpha(1)
    SetAuraTextureOutlineShown(host, false)
    if host.dragHandle then
        host.dragHandle:Hide()
    end
    if host.coordLabel then
        host.coordLabel:Hide()
    end
    if host.nudger then
        for _, btn in ipairs(host.nudger.buttons or {}) do
            if btn.nudgeDelayTimer then
                btn.nudgeDelayTimer:Cancel()
                btn.nudgeDelayTimer = nil
            end
            if btn.nudgeTicker then
                btn.nudgeTicker:Cancel()
                btn.nudgeTicker = nil
            end
        end
        host.nudger:Hide()
    end
    host:Hide()
end

function CooldownCompanion:ReleaseAuraTextureVisual(button)
    if not button or not button.auraTextureHost then
        return
    end

    local alphaModuleId = GetTexturePanelAlphaModuleId(button._groupId)
    self:HideAuraTextureVisual(button)
    if alphaModuleId then
        self:UnregisterModuleAlpha(alphaModuleId)
    end
    button.auraTextureHost:SetParent(nil)
    button.auraTextureHost = nil
end

local function IsTexturePanelEditingButton(button)
    local CS = ST._configState
    if not CS or not CS.configFrame or not CS.configFrame.frame or not CS.configFrame.frame:IsShown() then
        return false
    end
    if CS.selectedGroup ~= button._groupId then
        return false
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not CooldownCompanion:IsTexturePanelGroup(group) then
        return false
    end

    if CS.selectedButton == nil and (CS.panelSettingsTab == "appearance" or CS.panelSettingsTab == "effects" or CS.panelSettingsTab == "layout") then
        return true
    end

    local pickerWindow = CS.auraTexturePickerWindow
    return pickerWindow and pickerWindow._targetGroupId == button._groupId
end

local function IsTexturePanelConfigForceVisible(button)
    if not button then
        return false
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not CooldownCompanion:IsTexturePanelGroup(group) then
        return false
    end

    return ST.IsConfigButtonForceVisible(button)
end

local function ResolveActiveAuraTextureSettings(button)
    local preview = button._auraTexturePreviewSelection
    if type(preview) == "table" then
        return NormalizeAuraTextureSettings(preview)
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not CooldownCompanion:IsTexturePanelGroup(group) then
        return nil
    end

    local settings = CooldownCompanion:GetTexturePanelSettings(group)
    if not settings or not settings.sourceType or settings.sourceValue == nil then
        return nil
    end
    if not settings.enabled and not IsTexturePanelEditingButton(button) then
        return nil
    end

    return settings
end

function CooldownCompanion:UpdateAuraTextureVisual(button)
    if not button or button._isText then
        return
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not self:IsTexturePanelGroup(group) then
        self:HideAuraTextureVisual(button)
        return
    end

    local settings = ResolveActiveAuraTextureSettings(button)
    local isEditing = IsTexturePanelEditingButton(button)
    local isConfigForceVisible = IsTexturePanelConfigForceVisible(button)
    local isUnlocked = group and group.locked == false
    local hasPreviewSelection = type(button._auraTexturePreviewSelection) == "table"
    local showTexture = false

    if settings then
        if hasPreviewSelection then
            showTexture = true
        elseif isEditing then
            showTexture = true
        elseif isConfigForceVisible then
            showTexture = true
        elseif isUnlocked then
            showTexture = true
        elseif button:GetParent()
            and button:GetParent():IsShown()
            and not (button._rawVisibilityHidden == true) then
            showTexture = true
        end
    end

    if not settings or not showTexture then
        self:HideAuraTextureVisual(button)
        if button:GetAlpha() ~= 0 then
            button:SetAlpha(0)
            button._lastVisAlpha = 0
        end
        return
    end

    local host = EnsureAuraTextureHost(button)
    local relativeFrame = UIParent
    local baseAlpha = Clamp((settings.color and settings.color[4] or 1) * settings.alpha, 0.05, 1)
    local alpha = Clamp(baseAlpha, 0, 1)
    local sourceWidth = settings.width and settings.width > 0 and settings.width or DEFAULT_TEXTURE_SIZE
    local sourceHeight = settings.height and settings.height > 0 and settings.height or DEFAULT_TEXTURE_SIZE
    local geometry = self:BuildTexturePanelGeometry(settings, sourceWidth * settings.scale, sourceHeight * settings.scale)

    host:SetFrameStrata(button:GetFrameStrata())
    host:SetFrameLevel((button:GetFrameLevel() or 1) + 20)
    SyncAuraTextureControlLevels(host)
    host:SetSize(geometry.boundsWidth, geometry.boundsHeight)
    if host.visualRoot then
        host.visualRoot:SetSize(geometry.boundsWidth, geometry.boundsHeight)
    end
    if not host._isDragging then
        host:ClearAllPoints()
        host:SetPoint(settings.point, relativeFrame, settings.relativePoint, settings.x, settings.y)
    end
    host:Show()

    local shown = LayoutTexturePieces(host, settings, geometry, alpha)

    if not shown then
        self:HideAuraTextureVisual(button)
        if button:GetAlpha() ~= 0 then
            button:SetAlpha(0)
            button._lastVisAlpha = 0
        end
        return
    end

    host._activeTextureSettings = settings
    host._activeTextureGeometry = geometry
    SetTextureIndicatorBaseVisuals(host)
    ApplyTextureIndicatorEffects(host, button, group)

    local alphaModuleId = GetTexturePanelAlphaModuleId(button._groupId)
    local layoutPreviewAlpha = GetTexturePanelLayoutPreviewAlpha(button)
    local bypassModuleAlpha = isEditing or isConfigForceVisible or isUnlocked
    if alphaModuleId then
        if bypassModuleAlpha then
            self:UnregisterModuleAlpha(alphaModuleId, true)
            host:SetAlpha(layoutPreviewAlpha ~= nil and layoutPreviewAlpha or 1)
        else
            self:RegisterModuleAlpha(alphaModuleId, group, { host })
            local alphaState = self.alphaState and self.alphaState[alphaModuleId]
            if alphaState and alphaState.currentAlpha ~= nil then
                host:SetAlpha(alphaState.currentAlpha)
            end
        end
    end

    local savedSettings = group and group.textureSettings or nil
    host._dragEnabled = isUnlocked and type(savedSettings) == "table" and savedSettings.sourceType ~= nil
    host:EnableMouse(false)
    SetAuraTextureOutlineShown(host, false)
    if host.dragHandle and host.coordLabel then
        host.dragHandle.text:SetText(group and group.name or "Texture Panel")
        if host._isDragging then
            local _, _, _, currentX, currentY = host:GetPoint()
            UpdateTextureHostCoordLabel(host, currentX, currentY)
        else
            UpdateTextureHostCoordLabel(host, settings.x, settings.y)
        end
        local showHeader = host._dragEnabled == true
        host.dragHandle:SetShown(showHeader)
        host.coordLabel:SetShown(showHeader)
        if host.nudger then
            host.nudger:SetShown(showHeader)
        end
    end
    if button:GetAlpha() ~= 0 then
        button:SetAlpha(0)
        button._lastVisAlpha = 0
    end
end

function CooldownCompanion:RefreshAllAuraTextureVisuals()
    for _, frame in pairs(self.groupFrames or {}) do
        for _, button in ipairs(frame.buttons or {}) do
            self:UpdateAuraTextureVisual(button)
        end
    end
end
