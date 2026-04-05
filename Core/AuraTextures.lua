--[[
    CooldownCompanion - Core/AuraTextures.lua
    Blizzard-first aura texture library, recent proc capture, and runtime
    texture rendering for aura-capable buttons.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_pi = math.pi
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

local FILTER_LIBRARY = "library"
local FILTER_RECENT = "recent"
local FILTER_ATLASES = "atlases"
local MAX_ATLAS_SEARCH_RESULTS = 200
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

local BUILTIN_LIBRARY = {
    {
        key = "builtin:rotation-helper-proc-altglow",
        label = "Rotation Helper Alt Glow",
        category = "Starter Library",
        sourceType = "atlas",
        sourceValue = "UI-HUD-RotationHelper-ProcAltGlow",
        blendMode = "ADD",
        searchText = "rotation helper alt glow blizzard starter",
    },
}

local FILTER_OPTIONS = {
    [FILTER_LIBRARY] = "Blizzard Library",
    [FILTER_RECENT] = "Recent Proc Overlays",
    [FILTER_ATLASES] = "Atlas Search",
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

local function GetAtlasSearchCache()
    if CooldownCompanion._auraTextureAtlasCache then
        return CooldownCompanion._auraTextureAtlasCache
    end

    local cache = {}
    local atlasList = C_Texture.GetAtlasElements()
    if atlasList then
        for _, atlas in ipairs(atlasList) do
            cache[#cache + 1] = {
                atlas = atlas,
                lower = string_lower(atlas),
            }
        end
    end

    table_sort(cache, function(a, b)
        return a.lower < b.lower
    end)

    CooldownCompanion._auraTextureAtlasCache = cache
    return cache
end

local function BuildAtlasEntry(atlas)
    local info = C_Texture.GetAtlasInfo(atlas)
    local fileID = info and info.file or nil
    local width = info and info.width or nil
    local height = info and info.height or nil
    local filename = info and info.filename or nil
    local subtitleParts = {}

    if fileID then
        subtitleParts[#subtitleParts + 1] = "File " .. tostring(fileID)
    end
    if width and height then
        subtitleParts[#subtitleParts + 1] = tostring(width) .. "x" .. tostring(height)
    end
    if type(filename) == "string" and filename ~= "" then
        subtitleParts[#subtitleParts + 1] = filename
    end

    return {
        key = "atlas:" .. atlas,
        label = atlas,
        category = "Atlas Search",
        sourceType = "atlas",
        sourceValue = atlas,
        width = width,
        height = height,
        subtitle = table.concat(subtitleParts, "  |  "),
        searchText = string_lower(atlas .. " " .. (filename or "") .. " " .. tostring(fileID or "")),
    }
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

function CooldownCompanion:GetAuraTexturePickerFilters()
    return FILTER_OPTIONS, { FILTER_LIBRARY, FILTER_RECENT, FILTER_ATLASES }
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
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = UI_PARENT_NAME,
            x = 0,
            y = 0,
        }
    end

    return NormalizeAuraTextureSettings(group.textureSettings)
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
            category = entry.category,
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
    local filter = FILTER_OPTIONS[filterValue] and filterValue or FILTER_LIBRARY
    local entries = {}

    if filter == FILTER_LIBRARY then
        for _, entry in ipairs(BuildBuiltinEntries()) do
            if query == "" or string_find(entry.searchText, query, 1, true) then
                entries[#entries + 1] = entry
            end
        end
        for _, entry in ipairs(self:GetRecentAuraTextureEntries()) do
            if query == "" or string_find(entry.searchText, query, 1, true) then
                entries[#entries + 1] = entry
            end
        end
        table_sort(entries, function(a, b)
            if a.category == b.category then
                return a.label < b.label
            end
            return a.category < b.category
        end)
        return entries
    end

    if filter == FILTER_RECENT then
        for _, entry in ipairs(self:GetRecentAuraTextureEntries()) do
            if query == "" or string_find(entry.searchText, query, 1, true) then
                entries[#entries + 1] = entry
            end
        end
        return entries
    end

    if #query < 2 then
        return entries
    end

    local atlasCache = GetAtlasSearchCache()
    for _, atlas in ipairs(atlasCache) do
        if string_find(atlas.lower, query, 1, true) then
            entries[#entries + 1] = BuildAtlasEntry(atlas.atlas)
            if #entries >= MAX_ATLAS_SEARCH_RESULTS then
                break
            end
        end
    end

    return entries
end

local function ResolveTextureDimensions(settings)
    local dims = LOCATION_DIMENSIONS[settings.locationType] or LOCATION_DIMENSIONS[LOCATION_CENTER]
    local baseWidth = settings.width and settings.width > 0 and settings.width or DEFAULT_TEXTURE_SIZE
    local baseHeight = settings.height and settings.height > 0 and settings.height or DEFAULT_TEXTURE_SIZE

    return baseWidth * dims.width * settings.scale,
        baseHeight * dims.height * settings.scale
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

local function ApplyTextureVisual(texture, settings, alpha, flipH, flipV)
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
    texture:Show()
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

    local primary = host:CreateTexture(nil, "ARTWORK", nil, 1)
    local secondary = host:CreateTexture(nil, "ARTWORK", nil, 1)
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

function CooldownCompanion:HideAuraTextureVisual(button)
    local host = button and button.auraTextureHost
    if not host then
        return
    end

    if host._isDragging then
        host._isDragging = nil
        host:StopMovingOrSizing()
    end
    host.primaryTexture:Hide()
    host.secondaryTexture:Hide()
    host._dragEnabled = nil
    host:EnableMouse(false)
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

    self:HideAuraTextureVisual(button)
    button.auraTextureHost:SetParent(nil)
    button.auraTextureHost = nil
end

local function GetStandaloneLayout(settings, width, height)
    local dims = LOCATION_DIMENSIONS[settings.locationType] or LOCATION_DIMENSIONS[LOCATION_CENTER]
    local pairSpacing = settings.pairSpacing or DEFAULT_TEXTURE_PAIR_SPACING

    local function GetHorizontalSpan(pieceWidth, gap)
        local primaryLeft = (-(gap / 2)) - pieceWidth
        local primaryRight = -(gap / 2)
        local secondaryLeft = gap / 2
        local secondaryRight = secondaryLeft + pieceWidth
        return math_max(primaryRight, secondaryRight) - math_min(primaryLeft, secondaryLeft)
    end

    local function GetVerticalSpan(pieceHeight, gap)
        local bottomBottom = (-(gap / 2)) - pieceHeight
        local bottomTop = -(gap / 2)
        local topBottom = gap / 2
        local topTop = topBottom + pieceHeight
        return math_max(bottomTop, topTop) - math_min(bottomBottom, topBottom)
    end

    if dims.layout == "pair_horizontal" then
        local gap = width * pairSpacing
        return dims, GetHorizontalSpan(width, gap), height, gap
    end
    if dims.layout == "pair_vertical" then
        local gap = height * pairSpacing
        return dims, width, GetVerticalSpan(height, gap), gap
    end

    return dims, width, height, 0
end

local function LayoutSingleTexture(host, settings, dims, width, height, alpha)
    local primary = host.primaryTexture
    local secondary = host.secondaryTexture
    if not primary or not secondary then
        return false
    end

    primary:ClearAllPoints()
    primary:SetSize(width, height)

    primary:SetPoint(dims.point, host, dims.relPoint, 0, 0)
    secondary:Hide()

    if not ApplyTextureSource(primary, settings) then
        primary:Hide()
        return false
    end

    ApplyTextureVisual(primary, settings, alpha, dims.flipH, dims.flipV)
    return true
end

local function LayoutHorizontalPair(host, settings, width, height, alpha, gap)
    local primary = host.primaryTexture
    local secondary = host.secondaryTexture
    if not primary or not secondary then
        return false
    end

    primary:ClearAllPoints()
    secondary:ClearAllPoints()
    primary:SetSize(width, height)
    secondary:SetSize(width, height)
    primary:SetPoint("RIGHT", host, "CENTER", -(gap / 2), 0)
    secondary:SetPoint("LEFT", host, "CENTER", gap / 2, 0)

    local shownPrimary = ApplyTextureSource(primary, settings)
    local shownSecondary = ApplyTextureSource(secondary, settings)
    if shownPrimary then
        ApplyTextureVisual(primary, settings, alpha, false, false)
    else
        primary:Hide()
    end
    if shownSecondary then
        ApplyTextureVisual(secondary, settings, alpha, true, false)
    else
        secondary:Hide()
    end

    return shownPrimary or shownSecondary
end

local function LayoutVerticalPair(host, settings, width, height, alpha, gap)
    local primary = host.primaryTexture
    local secondary = host.secondaryTexture
    if not primary or not secondary then
        return false
    end

    primary:ClearAllPoints()
    secondary:ClearAllPoints()
    primary:SetSize(width, height)
    secondary:SetSize(width, height)
    primary:SetPoint("BOTTOM", host, "CENTER", 0, -(gap / 2))
    secondary:SetPoint("TOP", host, "CENTER", 0, gap / 2)

    local shownPrimary = ApplyTextureSource(primary, settings)
    local shownSecondary = ApplyTextureSource(secondary, settings)
    if shownPrimary then
        ApplyTextureVisual(primary, settings, alpha, false, false)
    else
        primary:Hide()
    end
    if shownSecondary then
        ApplyTextureVisual(secondary, settings, alpha, false, true)
    else
        secondary:Hide()
    end

    return shownPrimary or shownSecondary
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

    if CS.selectedButton == nil and (CS.panelSettingsTab == "appearance" or CS.panelSettingsTab == "layout") then
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
    local visibilityAlpha = 1
    if not isUnlocked and not isEditing and not hasPreviewSelection and not isConfigForceVisible then
        visibilityAlpha = button._rawVisibilityAlphaOverride or 1
    end
    local alpha = Clamp(baseAlpha * visibilityAlpha, 0, 1)
    local width, height = ResolveTextureDimensions(settings)
    local dims, totalWidth, totalHeight, gap = GetStandaloneLayout(settings, width, height)

    host:SetFrameStrata(button:GetFrameStrata())
    host:SetFrameLevel((button:GetFrameLevel() or 1) + 20)
    SyncAuraTextureControlLevels(host)
    host:SetSize(math_max(totalWidth, 1), math_max(totalHeight, 1))
    if not host._isDragging then
        host:ClearAllPoints()
        host:SetPoint(settings.point, relativeFrame, settings.relativePoint, settings.x, settings.y)
    end
    host:Show()

    local shown
    if dims.layout == "pair_horizontal" then
        shown = LayoutHorizontalPair(host, settings, width, height, alpha, gap)
    elseif dims.layout == "pair_vertical" then
        shown = LayoutVerticalPair(host, settings, width, height, alpha, gap)
    else
        shown = LayoutSingleTexture(host, settings, dims, width, height, alpha, gap)
    end

    if not shown then
        self:HideAuraTextureVisual(button)
        if button:GetAlpha() ~= 0 then
            button:SetAlpha(0)
            button._lastVisAlpha = 0
        end
        return
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
