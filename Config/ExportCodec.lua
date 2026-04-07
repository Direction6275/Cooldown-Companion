--[[
    CooldownCompanion - Config/ExportCodec
    Shared export/import codec for share strings and diagnostic payloads.
]]

local ADDON_NAME, ST = ...

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local COMPRESSION_CONFIG = { level = 9 }
local COMPACT_FORMAT_KEY = "_cdcExportFormat"
local COMPACT_FORMAT_VALUE = "compact1"

local LOAD_CONDITIONS_DEFAULTS = {
    raid = false,
    dungeon = false,
    delve = false,
    battleground = false,
    arena = false,
    openWorld = false,
    rested = false,
    petBattle = true,
    vehicleUI = true,
}

local PANEL_DEFAULTS = {
    displayMode = "icons",
    masqueEnabled = false,
    compactLayout = false,
    maxVisibleButtons = 0,
    compactGrowthDirection = "center",
    baselineAlpha = 1,
    fadeDelay = 1,
    fadeInDuration = 0.2,
    fadeOutDuration = 0.2,
}

local CONTAINER_DEFAULTS = {
    enabled = true,
    locked = true,
    baselineAlpha = 1,
    forceAlphaInCombat = false,
    forceAlphaOutOfCombat = false,
    forceAlphaRegularMounted = false,
    forceAlphaDragonriding = false,
    forceAlphaTargetExists = false,
    forceAlphaMouseover = false,
    forceHideInCombat = false,
    forceHideOutOfCombat = false,
    forceHideRegularMounted = false,
    forceHideDragonriding = false,
    treatTravelFormAsMounted = false,
    fadeDelay = 1,
    fadeInDuration = 0.2,
    fadeOutDuration = 0.2,
}

local CONTAINER_DEFAULT_ANCHOR = {
    point = "CENTER",
    relativeTo = "UIParent",
    relativePoint = "CENTER",
    x = 0,
    y = 0,
}

local PROFILE_DEFAULT_KEYS = {
    minimap = "minimap",
    hideInfoButtons = "hideInfoButtons",
    escClosesConfig = "escClosesConfig",
    showAdvanced = "showAdvanced",
    autoAddPrefs = "autoAddPrefs",
    groupSettingPresets = "groupSettingPresets",
    auraTextureLibrary = "auraTextureLibrary",
    globalStyle = "globalStyle",
    locked = "locked",
    cdmHidden = "cdmHidden",
    resourceBars = "resourceBars",
    castBar = "castBar",
    frameAnchoring = "frameAnchoring",
}

local SCOPED_SYSTEM_DEFAULTS = {
    resourceBars = "resourceBars",
    castBar = "castBar",
    frameAnchoring = "frameAnchoring",
    legacyResourceBarsSeed = "resourceBars",
    legacyCastBarSeed = "castBar",
    legacyFrameAnchoringSeed = "frameAnchoring",
}

local SCOPED_STORE_KEYS = {
    resourceBarsByChar = "resourceBars",
    castBarByChar = "castBar",
    frameAnchoringByChar = "frameAnchoring",
}

local function CopyValue(value)
    if type(value) == "table" then
        return CopyTable(value)
    end
    return value
end

local function IsMigrationSentinelKey(key)
    return type(key) == "string" and (key:match("^_migrated") or key:match("Migrated$"))
end

local function DeepEqual(a, b)
    if type(a) ~= type(b) then
        return false
    end
    if type(a) ~= "table" then
        return a == b
    end

    for key, value in pairs(a) do
        if not DeepEqual(value, b and b[key]) then
            return false
        end
    end
    for key in pairs(b or {}) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

local function CompactTableAgainstDefaults(source, defaults)
    if type(source) ~= "table" then
        if defaults ~= nil and DeepEqual(source, defaults) then
            return nil
        end
        return CopyValue(source)
    end

    local result = {}
    local hasAny = false

    for key, value in pairs(source) do
        local defaultValue = type(defaults) == "table" and defaults[key] or nil
        local compactValue

        if type(value) == "table" then
            compactValue = CompactTableAgainstDefaults(value, defaultValue)
        elseif defaultValue ~= nil and DeepEqual(value, defaultValue) then
            compactValue = nil
        else
            compactValue = value
        end

        if compactValue ~= nil then
            result[key] = compactValue
            hasAny = true
        end
    end

    if not hasAny then
        return nil
    end
    return result
end

local function MergeWithDefaults(source, defaults)
    if type(defaults) ~= "table" then
        return CopyValue(source)
    end

    local result = CopyTable(defaults)
    if type(source) ~= "table" then
        return result
    end

    for key, value in pairs(source) do
        if type(value) == "table" and type(result[key]) == "table" then
            result[key] = MergeWithDefaults(value, result[key])
        else
            result[key] = CopyValue(value)
        end
    end
    return result
end

local function GetDefaultsProfile()
    return ST._defaults and ST._defaults.profile or {}
end

local function GetSubsystemDefaults(defaultKey)
    local profileDefaults = GetDefaultsProfile()
    if type(profileDefaults[defaultKey]) == "table" then
        return profileDefaults[defaultKey]
    end
    return {}
end

local function BuildPanelDefaultAnchor(containerRef)
    if not containerRef then
        return nil
    end
    return {
        point = "CENTER",
        relativeTo = "CooldownCompanionContainer" .. tostring(containerRef),
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
end

local function CompactAnchorIfDefault(anchor, defaultAnchor)
    if type(anchor) ~= "table" then
        return nil
    end
    if type(defaultAnchor) == "table" and DeepEqual(anchor, defaultAnchor) then
        return nil
    end
    return CopyTable(anchor)
end

local function CompactLoadConditions(loadConditions)
    if type(loadConditions) ~= "table" then
        return nil
    end
    local compact = CompactTableAgainstDefaults(loadConditions, LOAD_CONDITIONS_DEFAULTS)
    return compact or {}
end

local function RehydrateLoadConditions(loadConditions)
    if type(loadConditions) ~= "table" then
        return nil
    end
    return MergeWithDefaults(loadConditions, LOAD_CONDITIONS_DEFAULTS)
end

local function CompactPanel(group, styleDefaults, panelContainerRef)
    if type(group) ~= "table" then
        return nil
    end

    local compact = {}
    for key, value in pairs(group) do
        if key == "style" then
            local compactStyle = CompactTableAgainstDefaults(value, styleDefaults)
            if compactStyle then
                compact.style = compactStyle
            end
        elseif key == "loadConditions" then
            local compactLoadConditions = CompactLoadConditions(value)
            if compactLoadConditions then
                compact.loadConditions = compactLoadConditions
            end
        elseif key == "anchor" then
            local compactAnchor = CompactAnchorIfDefault(value, BuildPanelDefaultAnchor(panelContainerRef))
            if compactAnchor then
                compact.anchor = compactAnchor
            end
        elseif PANEL_DEFAULTS[key] ~= nil then
            if not DeepEqual(value, PANEL_DEFAULTS[key]) then
                compact[key] = CopyValue(value)
            end
        else
            compact[key] = CopyValue(value)
        end
    end
    return compact
end

local function RehydratePanel(group, styleDefaults, panelContainerRef)
    if type(group) ~= "table" then
        return
    end

    group.style = MergeWithDefaults(group.style, styleDefaults)

    if group.loadConditions ~= nil then
        group.loadConditions = RehydrateLoadConditions(group.loadConditions)
    end

    local defaultAnchor = BuildPanelDefaultAnchor(panelContainerRef)
    if group.anchor == nil and defaultAnchor then
        group.anchor = CopyTable(defaultAnchor)
    elseif type(group.anchor) == "table" and defaultAnchor then
        group.anchor = MergeWithDefaults(group.anchor, defaultAnchor)
    end

    for key, defaultValue in pairs(PANEL_DEFAULTS) do
        if group[key] == nil then
            group[key] = CopyValue(defaultValue)
        end
    end
end

local function CompactContainer(container)
    if type(container) ~= "table" then
        return nil
    end

    local compact = {}
    for key, value in pairs(container) do
        if key == "loadConditions" then
            local compactLoadConditions = CompactLoadConditions(value)
            if compactLoadConditions then
                compact.loadConditions = compactLoadConditions
            end
        elseif key == "anchor" then
            local compactAnchor = CompactAnchorIfDefault(value, CONTAINER_DEFAULT_ANCHOR)
            if compactAnchor then
                compact.anchor = compactAnchor
            end
        elseif CONTAINER_DEFAULTS[key] ~= nil then
            if not DeepEqual(value, CONTAINER_DEFAULTS[key]) then
                compact[key] = CopyValue(value)
            end
        else
            compact[key] = CopyValue(value)
        end
    end
    return compact
end

local function RehydrateContainer(container)
    if type(container) ~= "table" then
        return
    end

    if container.loadConditions ~= nil then
        container.loadConditions = RehydrateLoadConditions(container.loadConditions)
    end

    if container.anchor == nil then
        container.anchor = CopyTable(CONTAINER_DEFAULT_ANCHOR)
    elseif type(container.anchor) == "table" then
        container.anchor = MergeWithDefaults(container.anchor, CONTAINER_DEFAULT_ANCHOR)
    end

    for key, defaultValue in pairs(CONTAINER_DEFAULTS) do
        if container[key] == nil then
            container[key] = CopyValue(defaultValue)
        end
    end
end

local function CompactFolder(folder)
    if type(folder) ~= "table" then
        return nil
    end

    local compact = {}
    for key, value in pairs(folder) do
        if key == "specs" or key == "heroTalents" then
            if type(value) == "table" and next(value) ~= nil then
                compact[key] = CopyTable(value)
            end
        else
            compact[key] = CopyValue(value)
        end
    end
    return compact
end

local function CompactScopedSettings(settings, defaultKey, preserveEmptyRoot)
    if type(settings) ~= "table" then
        return CopyValue(settings)
    end

    local compact = CompactTableAgainstDefaults(settings, GetSubsystemDefaults(defaultKey))
    if compact then
        return compact
    end
    if preserveEmptyRoot then
        return {}
    end
    return nil
end

local function RehydrateScopedSettings(settings, defaultKey)
    return MergeWithDefaults(settings, GetSubsystemDefaults(defaultKey))
end

local function CompactScopedStore(store, defaultKey)
    if type(store) ~= "table" then
        return CopyValue(store)
    end

    local compact = {}
    for charKey, settings in pairs(store) do
        compact[charKey] = CompactScopedSettings(settings, defaultKey, true) or {}
    end
    return compact
end

local function RehydrateScopedStore(store, defaultKey)
    if type(store) ~= "table" then
        return store
    end

    for charKey, settings in pairs(store) do
        if type(settings) == "table" then
            store[charKey] = RehydrateScopedSettings(settings, defaultKey)
        end
    end
    return store
end

local function CompactProfile(profile)
    if type(profile) ~= "table" then
        return profile
    end

    local profileDefaults = GetDefaultsProfile()
    local globalStyleDefaults = profile.globalStyle or profileDefaults.globalStyle or {}
    local compact = {}

    for key, value in pairs(profile) do
        if not IsMigrationSentinelKey(key) then
            if PROFILE_DEFAULT_KEYS[key] then
                local compactValue = CompactTableAgainstDefaults(value, profileDefaults[PROFILE_DEFAULT_KEYS[key]])
                if compactValue ~= nil then
                    compact[key] = compactValue
                end
            elseif SCOPED_SYSTEM_DEFAULTS[key] then
                local compactValue = CompactScopedSettings(value, SCOPED_SYSTEM_DEFAULTS[key], true)
                if compactValue ~= nil then
                    compact[key] = compactValue
                end
            elseif SCOPED_STORE_KEYS[key] then
                compact[key] = CompactScopedStore(value, SCOPED_STORE_KEYS[key])
            elseif key == "groups" and type(value) == "table" then
                local compactGroups = {}
                for groupId, group in pairs(value) do
                    compactGroups[groupId] = CompactPanel(group, globalStyleDefaults, group.parentContainerId)
                end
                compact.groups = compactGroups
            elseif key == "groupContainers" and type(value) == "table" then
                local compactContainers = {}
                for containerId, container in pairs(value) do
                    compactContainers[containerId] = CompactContainer(container)
                end
                compact.groupContainers = compactContainers
            elseif key == "folders" and type(value) == "table" then
                local compactFolders = {}
                for folderId, folder in pairs(value) do
                    compactFolders[folderId] = CompactFolder(folder)
                end
                compact.folders = compactFolders
            else
                compact[key] = CopyValue(value)
            end
        end
    end

    return compact
end

local function RehydrateProfile(profile)
    if type(profile) ~= "table" then
        return profile
    end

    local profileDefaults = GetDefaultsProfile()

    for key, defaultKey in pairs(PROFILE_DEFAULT_KEYS) do
        local defaultValue = profileDefaults[defaultKey]
        if type(defaultValue) == "table" then
            profile[key] = MergeWithDefaults(profile[key], defaultValue)
        elseif profile[key] == nil then
            profile[key] = defaultValue
        end
    end

    for key, defaultKey in pairs(SCOPED_SYSTEM_DEFAULTS) do
        if profile[key] ~= nil then
            profile[key] = RehydrateScopedSettings(profile[key], defaultKey)
        end
    end

    for key, defaultKey in pairs(SCOPED_STORE_KEYS) do
        if profile[key] ~= nil then
            profile[key] = RehydrateScopedStore(profile[key], defaultKey)
        end
    end

    local globalStyleDefaults = profile.globalStyle or profileDefaults.globalStyle or {}

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                RehydratePanel(group, globalStyleDefaults, group.parentContainerId)
            end
        end
    end

    if type(profile.groupContainers) == "table" then
        for _, container in pairs(profile.groupContainers) do
            if type(container) == "table" then
                RehydrateContainer(container)
            end
        end
    end

    if type(profile.folders) == "table" then
        for _, folder in pairs(profile.folders) do
            if type(folder) == "table" then
                if folder.specs and not next(folder.specs) then
                    folder.specs = nil
                end
                if folder.heroTalents and not next(folder.heroTalents) then
                    folder.heroTalents = nil
                end
            end
        end
    end

    return profile
end

local function CompactEntityPayload(payload)
    if type(payload) ~= "table" then
        return payload
    end

    local compact = CopyTable(payload)
    local globalStyleDefaults = GetSubsystemDefaults("globalStyle")

    if payload.group then
        compact.group = CompactPanel(payload.group, globalStyleDefaults, nil)
    end
    if type(payload.groups) == "table" then
        compact.groups = {}
        for index, group in ipairs(payload.groups) do
            compact.groups[index] = CompactPanel(group, globalStyleDefaults, nil)
        end
    end
    if payload.container then
        compact.container = CompactContainer(payload.container)
    end
    if type(payload.panels) == "table" then
        compact.panels = {}
        local panelContainerRef = payload._originalContainerId
        for index, panel in ipairs(payload.panels) do
            compact.panels[index] = CompactPanel(panel, globalStyleDefaults, panelContainerRef)
        end
    end
    if type(payload.containers) == "table" then
        compact.containers = {}
        for index, entry in ipairs(payload.containers) do
            local compactEntry = {}
            for key, value in pairs(entry) do
                if key == "container" then
                    compactEntry.container = CompactContainer(value)
                elseif key == "panels" and type(value) == "table" then
                    compactEntry.panels = {}
                    local panelContainerRef = entry._originalContainerId
                    for panelIndex, panel in ipairs(value) do
                        compactEntry.panels[panelIndex] = CompactPanel(panel, globalStyleDefaults, panelContainerRef)
                    end
                else
                    compactEntry[key] = CopyValue(value)
                end
            end
            compact.containers[index] = compactEntry
        end
    end
    if payload.folder then
        compact.folder = CompactFolder(payload.folder)
    end
    if type(payload.containers) ~= "table" and payload.type == "folder" then
        compact.folder = CompactFolder(payload.folder)
    end

    return compact
end

local function RehydrateEntityPayload(payload)
    if type(payload) ~= "table" then
        return payload
    end

    local globalStyleDefaults = GetSubsystemDefaults("globalStyle")

    if type(payload.group) == "table" then
        RehydratePanel(payload.group, globalStyleDefaults, nil)
    end
    if type(payload.groups) == "table" then
        for _, group in ipairs(payload.groups) do
            if type(group) == "table" then
                RehydratePanel(group, globalStyleDefaults, nil)
            end
        end
    end
    if type(payload.container) == "table" then
        RehydrateContainer(payload.container)
    end
    if type(payload.panels) == "table" then
        local panelContainerRef = payload._originalContainerId
        for _, panel in ipairs(payload.panels) do
            if type(panel) == "table" then
                RehydratePanel(panel, globalStyleDefaults, panelContainerRef)
            end
        end
    end
    if type(payload.containers) == "table" then
        for _, entry in ipairs(payload.containers) do
            if type(entry.container) == "table" then
                RehydrateContainer(entry.container)
            end
            if type(entry.panels) == "table" then
                local panelContainerRef = entry._originalContainerId
                for _, panel in ipairs(entry.panels) do
                    if type(panel) == "table" then
                        RehydratePanel(panel, globalStyleDefaults, panelContainerRef)
                    end
                end
            end
        end
    end

    return payload
end

local function CompactDiagnosticSnapshot(snapshot)
    if type(snapshot) ~= "table" then
        return snapshot
    end

    local compact = CopyTable(snapshot)

    if type(compact.profile) == "table" then
        compact.profile = CompactProfile(compact.profile)
    end

    if type(compact.runtime) == "table" then
        compact.runtime.currentInstanceType = nil

        local groupFrameStates = compact.runtime.groupFrameStates
        if type(groupFrameStates) == "table" then
            for _, state in pairs(groupFrameStates) do
                if type(state) == "table" then
                    state.exists = nil
                end
            end
        end

        local containerFrameStates = compact.runtime.containerFrameStates
        if type(containerFrameStates) == "table" then
            for _, state in pairs(containerFrameStates) do
                if type(state) == "table" then
                    state.exists = nil
                end
            end
        end
    end

    return compact
end

local function RehydrateCompactPayload(data)
    if type(data) ~= "table" then
        return data
    end

    if data.profile and type(data.profile) == "table" then
        data.profile = RehydrateProfile(data.profile)
        return data
    end

    if data.type then
        return RehydrateEntityPayload(data)
    end

    return RehydrateProfile(data)
end

local function EncodeSharedPayload(payload, exportKind)
    local exportData = CopyTable(payload)

    if exportKind == "profile" then
        exportData = CompactProfile(exportData)
    elseif exportKind == "diagnostic" then
        exportData = CompactDiagnosticSnapshot(exportData)
    else
        exportData = CompactEntityPayload(exportData)
    end

    exportData[COMPACT_FORMAT_KEY] = COMPACT_FORMAT_VALUE

    local serialized = AceSerializer:Serialize(exportData)
    local compressed = LibDeflate:CompressDeflate(serialized, COMPRESSION_CONFIG)
    return LibDeflate:EncodeForPrint(compressed)
end

local function DecodeSharedPayload(text)
    if type(text) ~= "string" then
        return false, nil
    end

    local normalized = text:gsub("%s+", "")
    if normalized == "" then
        return false, nil
    end

    if normalized:sub(1, 2) == "^1" then
        return AceSerializer:Deserialize(normalized)
    end

    local decoded = LibDeflate:DecodeForPrint(normalized)
    if not decoded then
        return false, nil
    end

    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return false, nil
    end

    local success, data = AceSerializer:Deserialize(decompressed)
    if not (success and type(data) == "table") then
        return false, nil
    end

    if data[COMPACT_FORMAT_KEY] == COMPACT_FORMAT_VALUE then
        data[COMPACT_FORMAT_KEY] = nil
        RehydrateCompactPayload(data)
    end

    return true, data
end

ST._EncodeSharedPayload = EncodeSharedPayload
ST._DecodeSharedPayload = DecodeSharedPayload
