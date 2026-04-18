--[[
    CooldownCompanion - Core/AuraTexturesPicker.lua
    Aura texture library storage, picker entries, and selection helpers.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local LSM = LibStub("LibSharedMedia-3.0")
local AT = ST._AT

local C_Spell_GetSpellName = C_Spell.GetSpellName
local ipairs = ipairs
local pairs = pairs
local string_find = string.find
local string_format = string.format
local string_gsub = string.gsub
local string_lower = string.lower
local string_trim = strtrim
local table_concat = table.concat
local table_insert = table.insert
local table_sort = table.sort
local tonumber = tonumber
local type = type

local FILTER_SYMBOLS = AT.FILTER_SYMBOLS
local FILTER_BLIZZARD_PROC = AT.FILTER_BLIZZARD_PROC
local FILTER_CUSTOM = AT.FILTER_CUSTOM
local FILTER_SHAREDMEDIA = AT.FILTER_SHAREDMEDIA
local FILTER_FAVORITES = AT.FILTER_FAVORITES
local FILTER_OTHER = AT.FILTER_OTHER
local SHARED_MEDIA_SOURCE_TYPE = AT.SHARED_MEDIA_SOURCE_TYPE
local SHARED_MEDIA_TYPE_ORDER = AT.SHARED_MEDIA_TYPE_ORDER
local SHARED_MEDIA_TYPE_SORT = AT.SHARED_MEDIA_TYPE_SORT
local SHARED_MEDIA_TYPE_LABELS = AT.SHARED_MEDIA_TYPE_LABELS
local FILTER_OPTIONS = AT.FILTER_OPTIONS
local LOCATION_CENTER = AT.LOCATION_CENTER
local DEFAULT_TEXTURE_PAIR_SPACING = AT.DEFAULT_TEXTURE_PAIR_SPACING
local BUILTIN_LIBRARY = AT.BUILTIN_LIBRARY
local CopyColor = AT.CopyColor
local Clamp = AT.Clamp
local NormalizeBlendMode = AT.NormalizeBlendMode
local NormalizeTextureLayout = AT.NormalizeTextureLayout
local BuildLocationSubtitle = AT.BuildLocationSubtitle
local NormalizeAuraTextureSourceType = AT.NormalizeAuraTextureSourceType
local NormalizeSharedMediaType = AT.NormalizeSharedMediaType
local NormalizeAuraTextureSettings = AT.NormalizeAuraTextureSettings

local function BuildSharedMediaLibraryKey(mediaType, mediaKey)
    local normalizedType = NormalizeSharedMediaType(mediaType)
    if not normalizedType or type(mediaKey) ~= "string" or mediaKey == "" then
        return nil
    end

    return "lsm:" .. normalizedType .. ":" .. mediaKey
end

local function BuildSharedMediaLabel(mediaKey, savedLabel)
    if type(savedLabel) == "string" and savedLabel ~= "" then
        return savedLabel
    end
    if type(mediaKey) == "string" and mediaKey ~= "" then
        return mediaKey
    end
    return "SharedMedia Texture"
end

local function BuildSharedMediaEntry(mediaType, mediaKey, savedLabel, options)
    options = type(options) == "table" and options or {}

    local normalizedType = NormalizeSharedMediaType(mediaType)
    if not normalizedType or type(mediaKey) ~= "string" or mediaKey == "" then
        return nil
    end

    local label = BuildSharedMediaLabel(mediaKey, savedLabel)
    local isFavorited = options.isFavorited == true
    local isMissing = options.isMissing == true
    local categoryKey = options.categoryKey or FILTER_SHAREDMEDIA
    local typeLabel = SHARED_MEDIA_TYPE_LABELS[normalizedType] or normalizedType
    local stateLabel = isMissing and "Missing or unavailable"
        or (isFavorited and "Favorited" or "SharedMedia")
    local subtitle = typeLabel .. "  |  " .. stateLabel

    return {
        key = BuildSharedMediaLibraryKey(normalizedType, mediaKey),
        libraryKey = BuildSharedMediaLibraryKey(normalizedType, mediaKey),
        label = label,
        categoryKey = categoryKey,
        category = FILTER_OPTIONS[categoryKey],
        sourceType = SHARED_MEDIA_SOURCE_TYPE,
        sourceValue = mediaKey,
        mediaType = normalizedType,
        layoutAgnostic = true,
        color = { 1, 1, 1, 1 },
        blendMode = "BLEND",
        subtitle = subtitle,
        searchText = string_lower(label .. " " .. mediaKey .. " " .. normalizedType .. " " .. stateLabel),
        favoriteOriginCategoryKey = FILTER_SHAREDMEDIA,
        isMissingSharedMedia = isMissing,
        canFavorite = not isFavorited and not isMissing,
        canRemoveFavorite = isFavorited,
    }
end

local function ReadSharedMediaFavoriteRecord(value)
    if type(value) ~= "table" then
        return nil, nil, nil
    end

    local mediaType = NormalizeSharedMediaType(value.mediaType)
    local mediaKey = value.key or value.mediaKey or value.sourceValue
    mediaKey = type(mediaKey) == "string" and string_trim(mediaKey) or nil
    local label = type(value.label) == "string" and value.label or nil
    if not mediaType or not mediaKey or mediaKey == "" then
        return nil, nil, nil
    end

    return mediaType, mediaKey, label
end

local function BuildAuraTextureFavoriteKey(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local favoriteKey = entry.libraryKey or entry.key
    if type(favoriteKey) == "string" and favoriteKey ~= "" then
        return favoriteKey
    end

    return nil
end

local function BuildAuraTextureFavoriteRecord(entry)
    local favoriteKey = BuildAuraTextureFavoriteKey(entry)
    local originCategoryKey = type(entry) == "table" and entry.favoriteOriginCategoryKey or nil
    if not favoriteKey or not FILTER_OPTIONS[originCategoryKey] or originCategoryKey == FILTER_FAVORITES then
        return nil
    end

    return {
        favoriteKey = favoriteKey,
        label = type(entry.label) == "string" and entry.label or tostring(entry.sourceValue),
        originCategoryKey = originCategoryKey,
        sourceType = entry.sourceType,
        sourceValue = entry.sourceValue,
        mediaType = entry.mediaType,
        layoutAgnostic = entry.layoutAgnostic == true,
        locationType = entry.locationType,
        width = tonumber(entry.width) or nil,
        height = tonumber(entry.height) or nil,
        color = CopyColor(entry.color) or { 1, 1, 1, 1 },
        blendMode = NormalizeBlendMode(entry.blendMode),
        scale = tonumber(entry.scale) or nil,
        subtitle = type(entry.subtitle) == "string" and entry.subtitle or nil,
        searchText = type(entry.searchText) == "string" and entry.searchText or nil,
    }
end

local function ReadAuraTextureFavoriteRecord(value)
    if type(value) ~= "table" then
        return nil
    end

    local favoriteKey = value.favoriteKey or value.key or value.libraryKey
    local originCategoryKey = FILTER_OPTIONS[value.originCategoryKey] and value.originCategoryKey or FILTER_OTHER
    local sourceType = NormalizeAuraTextureSourceType(value.sourceType)
    local sourceValue = value.sourceValue
    local mediaType = sourceType == SHARED_MEDIA_SOURCE_TYPE
        and NormalizeSharedMediaType(value.mediaType)
        or nil

    if type(favoriteKey) ~= "string" or favoriteKey == "" or not sourceType or sourceValue == nil then
        return nil
    end
    if sourceType == SHARED_MEDIA_SOURCE_TYPE and not mediaType then
        return nil
    end

    return {
        favoriteKey = favoriteKey,
        label = type(value.label) == "string" and value.label or tostring(sourceValue),
        originCategoryKey = originCategoryKey,
        sourceType = sourceType,
        sourceValue = sourceValue,
        mediaType = mediaType,
        layoutAgnostic = value.layoutAgnostic ~= false,
        locationType = value.locationType,
        width = tonumber(value.width) or nil,
        height = tonumber(value.height) or nil,
        color = CopyColor(value.color) or { 1, 1, 1, 1 },
        blendMode = NormalizeBlendMode(value.blendMode),
        scale = tonumber(value.scale) or nil,
        subtitle = type(value.subtitle) == "string" and value.subtitle or nil,
        searchText = type(value.searchText) == "string" and value.searchText or nil,
    }
end

local function BuildFavoriteAuraTextureEntry(value)
    local record = ReadAuraTextureFavoriteRecord(value)
    if not record then
        return nil
    end

    local isMissingSharedMedia = false
    local subtitle = record.subtitle
    if record.sourceType == SHARED_MEDIA_SOURCE_TYPE then
        local typeLabel = SHARED_MEDIA_TYPE_LABELS[record.mediaType] or record.mediaType
        isMissingSharedMedia = LSM:Fetch(record.mediaType, record.sourceValue, true) == nil
        local stateLabel = isMissingSharedMedia and "Missing or unavailable" or "Favorite"
        subtitle = typeLabel .. "  |  " .. stateLabel
    elseif subtitle and subtitle ~= "" then
        subtitle = subtitle .. "  |  " .. (FILTER_OPTIONS[record.originCategoryKey] or FILTER_OPTIONS[FILTER_OTHER])
    else
        subtitle = FILTER_OPTIONS[record.originCategoryKey] or FILTER_OPTIONS[FILTER_OTHER]
    end

    return {
        key = record.favoriteKey,
        libraryKey = record.favoriteKey,
        label = record.label,
        categoryKey = FILTER_FAVORITES,
        category = FILTER_OPTIONS[FILTER_FAVORITES],
        favoriteOriginCategoryKey = record.originCategoryKey,
        sourceType = record.sourceType,
        sourceValue = record.sourceValue,
        mediaType = record.mediaType,
        layoutAgnostic = record.layoutAgnostic,
        locationType = record.locationType,
        width = record.width,
        height = record.height,
        color = CopyColor(record.color) or { 1, 1, 1, 1 },
        blendMode = NormalizeBlendMode(record.blendMode),
        scale = record.scale,
        subtitle = subtitle,
        searchText = record.searchText
            or string_lower(record.label .. " " .. tostring(record.sourceValue) .. " " .. subtitle .. " favorite"),
        canFavorite = false,
        canRemoveFavorite = true,
        isFavoriteRecord = true,
        isMissingSharedMedia = isMissingSharedMedia,
    }
end

local function MigrateLegacySharedMediaFavorites(store)
    local favorites = store and store.textureFavorites or nil
    local legacyFavorites = store and store.sharedMediaFavorites or nil
    if type(favorites) ~= "table" or type(legacyFavorites) ~= "table" then
        return
    end

    for storedKey, storedValue in pairs(legacyFavorites) do
        local mediaType, mediaKey, savedLabel = ReadSharedMediaFavoriteRecord(storedValue)
        local libraryKey = BuildSharedMediaLibraryKey(mediaType, mediaKey)
        if libraryKey then
            local favoriteEntry = BuildSharedMediaEntry(mediaType, mediaKey, savedLabel, {
                categoryKey = FILTER_FAVORITES,
                isFavorited = true,
                isMissing = LSM:Fetch(mediaType, mediaKey, true) == nil,
            })
            if favoriteEntry then
                favoriteEntry.favoriteOriginCategoryKey = FILTER_SHAREDMEDIA
                favorites[libraryKey] = favorites[libraryKey] or BuildAuraTextureFavoriteRecord(favoriteEntry)
            end
        end

        legacyFavorites[storedKey] = nil
    end

    store.sharedMediaFavorites = nil
end

local function IsLegacyProcFavoriteKey(favoriteKey)
    return type(favoriteKey) == "string" and string_find(favoriteKey, "^favorite:legacy%-proc:", 1, false) ~= nil
end

local function CleanupLegacyRecentArtifacts(store)
    if type(store) ~= "table" then
        return
    end

    if type(store.textureFavorites) == "table" then
        for favoriteKey, favoriteValue in pairs(store.textureFavorites) do
            local favoriteRecord = ReadAuraTextureFavoriteRecord(favoriteValue)
            if IsLegacyProcFavoriteKey(favoriteKey)
                or (favoriteRecord and IsLegacyProcFavoriteKey(favoriteRecord.favoriteKey)) then
                store.textureFavorites[favoriteKey] = nil
            end
        end
    end

    store.recentProcOverlays = nil
end

function CooldownCompanion:NormalizeAuraTextureLibraryStore(store)
    if type(store) ~= "table" then
        return nil
    end

    if type(store.customTextures) ~= "table" then
        store.customTextures = {}
    end

    if type(store.textureFavorites) ~= "table" then
        store.textureFavorites = {}
    end

    MigrateLegacySharedMediaFavorites(store)
    CleanupLegacyRecentArtifacts(store)
    return store
end

local function GetAuraTextureFavoriteStore(store)
    local normalizedStore = CooldownCompanion:NormalizeAuraTextureLibraryStore(store)
    return normalizedStore and normalizedStore.textureFavorites or nil
end

local function ApplyFavoriteStateToEntry(entry, favorites)
    if type(entry) ~= "table" then
        return nil
    end

    local favoriteKey = BuildAuraTextureFavoriteKey(entry)
    local isFavorited = favoriteKey ~= nil and type(favorites) == "table" and favorites[favoriteKey] ~= nil
    entry.canFavorite = not isFavorited
    entry.canRemoveFavorite = isFavorited
    entry.isFavoriteRecord = nil

    if entry.sourceType == SHARED_MEDIA_SOURCE_TYPE then
        local typeLabel = SHARED_MEDIA_TYPE_LABELS[entry.mediaType] or entry.mediaType
        local stateLabel = entry.isMissingSharedMedia and "Missing or unavailable"
            or (isFavorited and "Favorited" or "SharedMedia")
        entry.subtitle = typeLabel .. "  |  " .. stateLabel
        entry.searchText = string_lower(entry.label .. " " .. tostring(entry.sourceValue) .. " " .. tostring(entry.mediaType) .. " " .. stateLabel)
    end

    return entry
end

local function AreTextureNumbersEqual(a, b)
    if a == nil and b == nil then
        return true
    end
    if type(a) ~= "number" or type(b) ~= "number" then
        return false
    end
    return math.abs(a - b) <= 0.0001
end

local function AreTextureColorsEqual(a, b)
    local left = CopyColor(a) or { 1, 1, 1, 1 }
    local right = CopyColor(b) or { 1, 1, 1, 1 }
    for index = 1, 4 do
        if not AreTextureNumbersEqual(left[index] or 1, right[index] or 1) then
            return false
        end
    end
    return true
end

function CooldownCompanion:DoesAuraTexturePickerEntryMatchSelection(entry, selection)
    if type(entry) ~= "table" or type(selection) ~= "table" then
        return false
    end

    local selectionLibraryKey = selection.libraryKey
    if type(selectionLibraryKey) == "string" and selectionLibraryKey ~= "" then
        return entry.key == selectionLibraryKey
    end

    if entry.sourceType ~= selection.sourceType or entry.sourceValue ~= selection.sourceValue then
        return false
    end

    if entry.sourceType == SHARED_MEDIA_SOURCE_TYPE and entry.mediaType ~= selection.mediaType then
        return false
    end

    if not entry.layoutAgnostic then
        local entryLocationType = NormalizeTextureLayout(entry.locationType)
        local selectionLocationType = NormalizeTextureLayout(selection.locationType)
        if entryLocationType ~= selectionLocationType then
            return false
        end
    end

    if not AreTextureNumbersEqual(entry.scale or 1, selection.scale or 1) then
        return false
    end

    if NormalizeBlendMode(entry.blendMode) ~= NormalizeBlendMode(selection.blendMode) then
        return false
    end

    if not AreTextureColorsEqual(entry.color, selection.color) then
        return false
    end

    return true
end

function CooldownCompanion:FindAuraTexturePickerEntry(entries, selection)
    if type(selection) ~= "table" then
        return nil
    end

    for _, entry in ipairs(entries or {}) do
        if self:DoesAuraTexturePickerEntryMatchSelection(entry, selection) then
            return entry
        end
    end

    return nil
end

function CooldownCompanion:ApplyTexturePanelEntry(settings, entry)
    if type(settings) ~= "table" or type(entry) ~= "table" then
        return
    end

    local entryLocationType, entryDefaultPairSpacing
    if entry.locationType ~= nil then
        entryLocationType, entryDefaultPairSpacing = NormalizeTextureLayout(entry.locationType)
    end

    settings.sourceType = entry.sourceType
    settings.sourceValue = entry.sourceValue
    settings.mediaType = entry.mediaType
    settings.libraryKey = entry.libraryKey or entry.key
    settings.label = entry.label
    settings.locationType = entryLocationType or NormalizeTextureLayout(settings.locationType)
    settings.width = entry.width
    settings.height = entry.height
    settings.color = CopyColor(entry.color) or { 1, 1, 1, 1 }
    settings.blendMode = NormalizeBlendMode(settings.blendMode or "BLEND")
    settings.scale = Clamp(entry.scale or settings.scale or 1, 0.25, 4)
    settings.alpha = Clamp(settings.alpha or 1, 0.05, 1)
    settings.rotation = Clamp(settings.rotation or 0, AT.MIN_TEXTURE_ROTATION, AT.MAX_TEXTURE_ROTATION)
    settings.stretchX = Clamp(settings.stretchX or 0, AT.MIN_TEXTURE_STRETCH, AT.MAX_TEXTURE_STRETCH)
    settings.stretchY = Clamp(settings.stretchY or 0, AT.MIN_TEXTURE_STRETCH, AT.MAX_TEXTURE_STRETCH)
    settings.pairSpacing = Clamp(
        entry.pairSpacing or entryDefaultPairSpacing or settings.pairSpacing or DEFAULT_TEXTURE_PAIR_SPACING,
        AT.MIN_TEXTURE_PAIR_SPACING,
        AT.MAX_TEXTURE_PAIR_SPACING
    )
    settings.point = AT.NormalizeAnchorPoint(settings.point or "CENTER")
    settings.relativePoint = AT.NormalizeAnchorPoint(settings.relativePoint or "CENTER")
    settings.relativeTo = AT.UI_PARENT_NAME
    settings.x = tonumber(settings.x) or 0
    settings.y = tonumber(settings.y) or 0
end

function CooldownCompanion:CreateTexturePanelSelection(entry, baseSettings)
    if type(entry) ~= "table" then
        return nil
    end

    local base = type(baseSettings) == "table" and NormalizeAuraTextureSettings(baseSettings) or nil
    local entryLocationType, entryDefaultPairSpacing
    if entry.locationType ~= nil then
        entryLocationType, entryDefaultPairSpacing = NormalizeTextureLayout(entry.locationType)
    end
    local selection = {
        libraryKey = entry.libraryKey or entry.key,
        sourceType = entry.sourceType,
        sourceValue = entry.sourceValue,
        mediaType = entry.mediaType,
        label = entry.label,
        scale = entry.scale or (base and base.scale) or 1,
        alpha = base and base.alpha or 1,
        blendMode = NormalizeBlendMode((base and base.blendMode) or "BLEND"),
        rotation = base and base.rotation or 0,
        stretchX = base and base.stretchX or 0,
        stretchY = base and base.stretchY or 0,
        point = base and base.point or "CENTER",
        relativePoint = base and base.relativePoint or "CENTER",
        relativeTo = AT.UI_PARENT_NAME,
        x = base and base.x or 0,
        y = base and base.y or 0,
        color = CopyColor(base and base.color) or CopyColor(entry.color) or { 1, 1, 1, 1 },
        locationType = entryLocationType or (base and base.locationType) or LOCATION_CENTER,
        pairSpacing = entry.pairSpacing or entryDefaultPairSpacing or (base and base.pairSpacing) or DEFAULT_TEXTURE_PAIR_SPACING,
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

local SUPPORTED_CUSTOM_TEXTURE_EXTENSIONS = {
    blp = true,
    jpg = true,
    jpeg = true,
    png = true,
    tga = true,
}

local function NormalizeCustomTexturePath(path)
    if type(path) ~= "string" then
        return nil
    end

    local normalized = string_trim(path)
    if normalized == "" then
        return nil
    end

    normalized = string_gsub(normalized, "/", "\\")
    normalized = string_gsub(normalized, "\\+", "\\")

    local lowerPath = string_lower(normalized)
    if string_find(lowerPath, "^[a-z]:") or not string_find(lowerPath, "^interface\\") then
        return nil
    end

    -- WoW only requires an explicit suffix for PNG paths; BLP/JPG/TGA can be
    -- loaded with or without the extension, so the normalizer must allow both.
    local extension = lowerPath:match("%.([a-z0-9]+)$")
    if extension and not SUPPORTED_CUSTOM_TEXTURE_EXTENSIONS[extension] then
        return nil
    end

    if not extension and string_find(lowerPath, "%.$") then
        return nil
    end

    return normalized
end

local function BuildCustomTexturePathKey(normalizedPath)
    if type(normalizedPath) ~= "string" or normalizedPath == "" then
        return nil
    end
    -- Keep the saved shelf key tied to the exact normalized path so distinct
    -- files like Glow.blp and Glow.tga cannot silently overwrite each other.
    return string_lower(normalizedPath)
end

local function GetCustomTexturePathExtension(normalizedPath)
    if type(normalizedPath) ~= "string" or normalizedPath == "" then
        return nil
    end

    return string_lower(normalizedPath):match("%.([a-z0-9]+)$")
end

local function BuildCustomTextureCanonicalKey(normalizedPath)
    local pathKey = BuildCustomTexturePathKey(normalizedPath)
    if not pathKey then
        return nil
    end

    local extension = GetCustomTexturePathExtension(normalizedPath)
    if extension and extension ~= "png" and SUPPORTED_CUSTOM_TEXTURE_EXTENSIONS[extension] then
        return pathKey:gsub("%.[a-z0-9]+$", "")
    end

    return pathKey
end

local function BuildCustomTextureLabel(normalizedPath)
    if type(normalizedPath) ~= "string" or normalizedPath == "" then
        return "Custom Texture"
    end

    local fileName = normalizedPath:match("([^\\]+)$")
    return fileName or normalizedPath
end

local function NormalizeCustomTextureDimensions(width, height)
    local normalizedWidth = tonumber(width)
    local normalizedHeight = tonumber(height)

    if not normalizedWidth or normalizedWidth <= 0 or not normalizedHeight or normalizedHeight <= 0 then
        return nil, nil
    end

    return normalizedWidth, normalizedHeight
end

local function ReadCustomTextureRecord(value)
    if type(value) == "string" then
        return NormalizeCustomTexturePath(value), nil, nil
    end

    if type(value) ~= "table" then
        return nil, nil, nil
    end

    local normalizedPath = NormalizeCustomTexturePath(value.path or value.sourceValue or value.texturePath)
    local width, height = NormalizeCustomTextureDimensions(value.width, value.height)
    return normalizedPath, width, height
end

local function BuildCustomTextureEntry(value)
    local normalizedPath, width, height = ReadCustomTextureRecord(value)
    local pathKey = BuildCustomTexturePathKey(normalizedPath)
    if not normalizedPath or not pathKey then
        return nil
    end

    local label = BuildCustomTextureLabel(normalizedPath)

    return {
        key = "custom:" .. pathKey,
        libraryKey = "custom:" .. pathKey,
        label = label,
        categoryKey = FILTER_CUSTOM,
        category = FILTER_OPTIONS[FILTER_CUSTOM],
        sourceType = "file",
        sourceValue = normalizedPath,
        layoutAgnostic = true,
        color = { 1, 1, 1, 1 },
        blendMode = "BLEND",
        width = width,
        height = height,
        subtitle = normalizedPath,
        searchText = string_lower(label .. " " .. normalizedPath .. " custom texture"),
        isCustomTexture = true,
    }
end

function CooldownCompanion:NormalizeCustomAuraTexturePath(path)
    return NormalizeCustomTexturePath(path)
end

function CooldownCompanion:IsCustomAuraTextureSelection(selection)
    if type(selection) ~= "table" then
        return false
    end

    if type(selection.libraryKey) == "string" and string_find(selection.libraryKey, "^custom:", 1, false) then
        return true
    end

    return selection.sourceType == "file"
        and type(selection.sourceValue) == "string"
        and NormalizeCustomTexturePath(selection.sourceValue) ~= nil
end

function CooldownCompanion:EnsureAuraTextureLibraryStore()
    local profile = self.db and self.db.profile
    if not profile then
        return nil
    end
    if type(profile.auraTextureLibrary) ~= "table" then
        profile.auraTextureLibrary = {
            customTextures = {},
            textureFavorites = {},
        }
    end

    return self:NormalizeAuraTextureLibraryStore(profile.auraTextureLibrary)
end

function CooldownCompanion:GetSharedMediaAuraTextureEntries()
    local store = self:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    local entries = {}

    for _, mediaType in ipairs(SHARED_MEDIA_TYPE_ORDER) do
        for _, mediaKey in ipairs(LSM:List(mediaType) or {}) do
            local favoriteKey = BuildSharedMediaLibraryKey(mediaType, mediaKey)
            local savedFavorite = favoriteKey and favorites and favorites[favoriteKey] or nil
            local savedRecord = savedFavorite and ReadAuraTextureFavoriteRecord(savedFavorite) or nil
            local entry = BuildSharedMediaEntry(
                mediaType,
                mediaKey,
                savedRecord and savedRecord.label or nil,
                {
                    isFavorited = savedFavorite ~= nil,
                    isMissing = LSM:Fetch(mediaType, mediaKey, true) == nil,
                }
            )
            if entry then
                entries[#entries + 1] = entry
            end
        end
    end

    table_sort(entries, function(a, b)
        local aLabel = string_lower(a.label or "")
        local bLabel = string_lower(b.label or "")
        if aLabel == bLabel then
            local aType = SHARED_MEDIA_TYPE_SORT[a.mediaType] or 99
            local bType = SHARED_MEDIA_TYPE_SORT[b.mediaType] or 99
            if aType == bType then
                return (a.sourceValue or "") < (b.sourceValue or "")
            end
            return aType < bType
        end
        return aLabel < bLabel
    end)

    return entries
end

function CooldownCompanion:GetFavoriteAuraTextureEntries()
    local store = self:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    local entries = {}

    for storedKey, storedValue in pairs(favorites or {}) do
        local record = ReadAuraTextureFavoriteRecord(storedValue)
        if not record then
            favorites[storedKey] = nil
        else
            if record.favoriteKey ~= storedKey then
                favorites[record.favoriteKey] = storedValue
                favorites[storedKey] = nil
            end

            local entry = BuildFavoriteAuraTextureEntry(storedValue)
            if entry then
                entries[#entries + 1] = entry
            else
                favorites[record.favoriteKey] = nil
            end
        end
    end

    table_sort(entries, function(a, b)
        if a.isMissingSharedMedia ~= b.isMissingSharedMedia then
            return not a.isMissingSharedMedia
        end

        local aLabel = string_lower(a.label or "")
        local bLabel = string_lower(b.label or "")
        if aLabel == bLabel then
            return (a.libraryKey or a.key or "") < (b.libraryKey or b.key or "")
        end
        return aLabel < bLabel
    end)

    return entries
end

function CooldownCompanion:SaveFavoriteAuraTexture(entryOrMediaType, mediaKey, label)
    local entry = nil
    if type(entryOrMediaType) == "table" then
        entry = entryOrMediaType
    else
        local normalizedType = NormalizeSharedMediaType(entryOrMediaType)
        local normalizedKey = type(mediaKey) == "string" and string_trim(mediaKey) or nil
        local libraryKey = BuildSharedMediaLibraryKey(normalizedType, normalizedKey)
        if not libraryKey then
            return nil
        end

        entry = BuildSharedMediaEntry(normalizedType, normalizedKey, label, {
            isFavorited = true,
            isMissing = LSM:Fetch(normalizedType, normalizedKey, true) == nil,
        })
    end

    local record = BuildAuraTextureFavoriteRecord(entry)
    if not record then
        return nil
    end

    local store = self:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    if not favorites then
        return nil
    end

    favorites[record.favoriteKey] = record

    return BuildFavoriteAuraTextureEntry(record)
end

function CooldownCompanion:RemoveFavoriteAuraTexture(entryOrKey, mediaKey)
    local store = self:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    if not favorites then
        return
    end

    local favoriteKey = nil
    if type(entryOrKey) == "table" then
        favoriteKey = BuildAuraTextureFavoriteKey(entryOrKey)
    end
    if mediaKey ~= nil then
        favoriteKey = BuildSharedMediaLibraryKey(entryOrKey, mediaKey)
    elseif not favoriteKey and type(entryOrKey) == "string" then
        favoriteKey = entryOrKey
    end

    if not favoriteKey then
        return
    end

    favorites[favoriteKey] = nil
end

function CooldownCompanion:GetCustomAuraTextureEntries()
    local store = self:EnsureAuraTextureLibraryStore()
    local customTextures = store and store.customTextures or nil
    local entries = {}

    for key, storedValue in pairs(customTextures or {}) do
        local entry = BuildCustomTextureEntry(storedValue)
        if entry then
            entries[#entries + 1] = entry
        else
            customTextures[key] = nil
        end
    end

    table_sort(entries, function(a, b)
        return a.label < b.label
    end)

    return entries
end

function CooldownCompanion:SaveCustomAuraTexture(path, width, height)
    local normalizedPath = NormalizeCustomTexturePath(path)
    local pathKey = BuildCustomTexturePathKey(normalizedPath)
    if not normalizedPath or not pathKey then
        return nil
    end

    local store = self:EnsureAuraTextureLibraryStore()
    if not store then
        return nil
    end

    local normalizedWidth, normalizedHeight = NormalizeCustomTextureDimensions(width, height)
    store.customTextures[pathKey] = {
        path = normalizedPath,
        width = normalizedWidth,
        height = normalizedHeight,
    }

    return BuildCustomTextureEntry(store.customTextures[pathKey])
end

function CooldownCompanion:ResolveCustomAuraTextureSubmission(path)
    local normalizedPath = NormalizeCustomTexturePath(path)
    local pathKey = BuildCustomTexturePathKey(normalizedPath)
    if not normalizedPath or not pathKey then
        return nil, nil, "Enter a WoW texture path like Interface\\AddOns\\MyPack\\Texture.tga."
    end

    local store = self:EnsureAuraTextureLibraryStore()
    if not store then
        return nil, nil, "Texture library is unavailable right now."
    end

    local existingExact = store.customTextures[pathKey]
    if existingExact then
        return BuildCustomTextureEntry(existingExact), nil, nil
    end

    local typedExtension = GetCustomTexturePathExtension(normalizedPath)
    if typedExtension ~= nil then
        -- Explicit file variants should stay addable beside an older
        -- extensionless save; only exact path matches should collapse here.
        return nil, normalizedPath, nil
    end

    local canonicalKey = BuildCustomTextureCanonicalKey(normalizedPath)
    local variantCount = 0
    local soleVariantEntry = nil

    for _, storedValue in pairs(store.customTextures) do
        local storedPath = ReadCustomTextureRecord(storedValue)
        if storedPath and BuildCustomTextureCanonicalKey(storedPath) == canonicalKey then
            variantCount = variantCount + 1
            soleVariantEntry = BuildCustomTextureEntry(storedValue)
        end
    end

    if variantCount == 0 then
        return nil, normalizedPath, nil
    end
    if variantCount == 1 then
        return soleVariantEntry, nil, nil
    end

    return nil, nil, "More than one custom texture uses this name. Include the file extension."
end

function CooldownCompanion:RemoveCustomAuraTexture(pathOrKey)
    local store = self:EnsureAuraTextureLibraryStore()
    if not store then
        return
    end

    local pathKey = nil
    if type(pathOrKey) == "string" and string_find(pathOrKey, "^custom:", 1, false) then
        pathKey = pathOrKey:sub(8)
    else
        pathKey = BuildCustomTexturePathKey(pathOrKey)
    end

    if not pathKey then
        return
    end

    store.customTextures[pathKey] = nil
end

local function BuildBlizzardProcOverlayEntries()
    local overlayLibrary = ST._spellActivationOverlayLibrary
    local rows = overlayLibrary and overlayLibrary.entries
    local entries = {}
    local deduped = {}

    if type(rows) ~= "table" then
        return entries
    end

    for _, row in ipairs(rows) do
        local spellID = tonumber(row.spellID)
        local fileDataID = tonumber(row.fileDataID)
        if spellID and spellID > 0 and fileDataID and fileDataID > 0 then
            local spellName = C_Spell_GetSpellName(spellID) or ("Spell " .. tostring(spellID))
            local locationType = tonumber(row.locationType)
            local locationSubtitle = BuildLocationSubtitle(locationType)
            local color = CopyColor(row.color) or { 1, 1, 1, 1 }
            local scale = tonumber(row.scale) or 1
            -- Treat the Blizzard proc browser as an art library, not a layout library.
            -- Different DB2 rows often point at the same visual and only vary by Blizzard's
            -- authored placement metadata, while our config already lets the user choose the
            -- final layout. We intentionally dedupe by visual identity and keep placement only
            -- as searchable/informational metadata so the browser stays consistent.
            local key = string_format(
                "builtin:proc:%d:%.4f:%.4f:%.4f:%.4f:%.4f",
                fileDataID,
                scale,
                color[1] or 1,
                color[2] or 1,
                color[3] or 1,
                color[4] or 1
            )
            local entry = deduped[key]
            if not entry then
                entry = {
                    key = key,
                    label = spellName .. " Proc Overlay",
                    categoryKey = FILTER_BLIZZARD_PROC,
                    category = FILTER_OPTIONS[FILTER_BLIZZARD_PROC],
                    sourceType = "file",
                    sourceValue = fileDataID,
                    -- Leave location unset so selecting a Blizzard proc does not force a
                    -- built-in layout; the layout control remains the source of truth.
                    locationType = nil,
                    layoutAgnostic = true,
                    color = color,
                    blendMode = "ADD",
                    scale = scale,
                    subtitle = tostring(spellID) .. "  |  File " .. tostring(fileDataID),
                    _spellIDs = { tostring(spellID) },
                    _spellNames = { spellName },
                    _spellCount = 1,
                    _locationSubtitles = {
                        [locationSubtitle] = true,
                    },
                    _seenSpellIDs = {
                        [spellID] = true,
                    },
                    _seenSpellNames = {
                        [spellName] = true,
                    },
                }
                deduped[key] = entry
                entries[#entries + 1] = entry
            elseif not entry._seenSpellIDs[spellID] then
                entry._seenSpellIDs[spellID] = true
                entry._spellCount = (entry._spellCount or 1) + 1
                table_insert(entry._spellIDs, tostring(spellID))
                if not entry._seenSpellNames[spellName] then
                    entry._seenSpellNames[spellName] = true
                    table_insert(entry._spellNames, spellName)
                end
                entry._locationSubtitles[locationSubtitle] = true
            end
        end
    end

    for _, entry in ipairs(entries) do
        local locationAliases = {}
        for subtitle in pairs(entry._locationSubtitles or {}) do
            locationAliases[#locationAliases + 1] = subtitle
        end
        table_sort(locationAliases)
        local baseSearchText = entry.label
            .. " "
            .. table_concat(entry._spellNames or {}, " ")
            .. " "
            .. table_concat(entry._spellIDs or {}, " ")
            .. " "
            .. tostring(entry.sourceValue)
            .. " "
            .. table_concat(locationAliases, " ")
        if (entry._spellCount or 1) > 1 then
            entry.subtitle = entry.subtitle .. "  |  Used by " .. tostring(entry._spellCount) .. " spells"
        end
        entry.searchText = string_lower(baseSearchText)
        entry._spellIDs = nil
        entry._spellNames = nil
        entry._spellCount = nil
        entry._locationSubtitles = nil
        entry._seenSpellIDs = nil
        entry._seenSpellNames = nil
    end

    table_sort(entries, function(a, b)
        return a.label < b.label
    end)

    return entries
end

local function BuildBuiltinEntries()
    local entries = {}
    local store = CooldownCompanion:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    for _, entry in ipairs(BUILTIN_LIBRARY) do
        entries[#entries + 1] = ApplyFavoriteStateToEntry({
            key = entry.key,
            label = entry.label,
            categoryKey = entry.categoryKey or FILTER_OTHER,
            category = entry.category or FILTER_OPTIONS[entry.categoryKey] or FILTER_OPTIONS[FILTER_OTHER],
            favoriteOriginCategoryKey = entry.categoryKey or FILTER_OTHER,
            sourceType = entry.sourceType,
            sourceValue = entry.sourceValue,
            width = entry.width,
            height = entry.height,
            color = CopyColor(entry.color) or { 1, 1, 1, 1 },
            blendMode = NormalizeBlendMode(entry.blendMode),
            subtitle = entry.subtitle,
            searchText = entry.searchText or string_lower(entry.label),
        }, favorites)
    end
    for _, entry in ipairs(BuildBlizzardProcOverlayEntries()) do
        entry.favoriteOriginCategoryKey = entry.categoryKey or FILTER_BLIZZARD_PROC
        entries[#entries + 1] = ApplyFavoriteStateToEntry(entry, favorites)
    end
    return entries
end

function CooldownCompanion:GetAuraTexturePickerEntries(searchText, filterValue)
    local query = type(searchText) == "string" and string_lower(string_trim(searchText)) or ""
    local filter = FILTER_OPTIONS[filterValue] and filterValue or FILTER_SYMBOLS
    local entries = {}

    if filter == FILTER_SHAREDMEDIA then
        for _, entry in ipairs(self:GetSharedMediaAuraTextureEntries()) do
            if query == "" or string_find(entry.searchText, query, 1, true) then
                entries[#entries + 1] = entry
            end
        end
        return entries
    end

    if filter == FILTER_FAVORITES then
        for _, entry in ipairs(self:GetFavoriteAuraTextureEntries()) do
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
    return FILTER_OPTIONS, {
        FILTER_SYMBOLS,
        FILTER_BLIZZARD_PROC,
        FILTER_SHAREDMEDIA,
        FILTER_FAVORITES,
        FILTER_OTHER,
    }
end

function CooldownCompanion:GetAuraTexturePickerFilterForSelection(selection)
    if type(selection) ~= "table" then
        return FILTER_SYMBOLS
    end

    local favoriteEntry = self:FindAuraTexturePickerEntry(self:GetFavoriteAuraTextureEntries(), selection)
    if favoriteEntry then
        return FILTER_FAVORITES
    end

    local builtinEntry = self:FindAuraTexturePickerEntry(BuildBuiltinEntries(), selection)
    if builtinEntry then
        return builtinEntry.categoryKey or FILTER_OTHER
    end

    local sharedMediaEntry = self:FindAuraTexturePickerEntry(self:GetSharedMediaAuraTextureEntries(), selection)
    if sharedMediaEntry or selection.sourceType == SHARED_MEDIA_SOURCE_TYPE then
        return FILTER_SHAREDMEDIA
    end

    return FILTER_SYMBOLS
end
