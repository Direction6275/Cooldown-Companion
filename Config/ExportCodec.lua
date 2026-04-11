--[[
    CooldownCompanion - Config/ExportCodec
    Shared export/import codec for share strings and diagnostic payloads.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local AceSerializer = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub("LibDeflate")

local COMPRESSION_CONFIG = { level = 9 }
local COMPACT_FORMAT_KEY = "_cdcExportFormat"
local CURRENT_COMPACT_FORMAT_VALUE = "compact3"
local PREVIOUS_COMPACT_FORMAT_VALUE = "compact2"
local LEGACY_COMPACT_FORMAT_VALUE = "compact1"

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
    groupContainers = "groupContainers",
    folders = "folders",
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

-- Compact payloads must rehydrate against a frozen baseline, not the
-- importer's current runtime defaults. If profile defaults change in a future
-- release, keep the old snapshot here and bump CURRENT_COMPACT_FORMAT_VALUE.
local COMPACT_PROFILE_DEFAULTS = {
    [CURRENT_COMPACT_FORMAT_VALUE] = {
        minimap = {
            hide = false,
        },
        hideInfoButtons = false,
        escClosesConfig = true,
        showAdvanced = {},
        autoAddPrefs = {
            lastSource = "actionbars",
            selectedBars = { true, true, true, true, true, true },
            showSkipped = false,
            showSources = true,
            sortMode = "source_then_name",
        },
        groupSettingPresets = {
            icons = {},
            bars = {},
        },
        auraTextureLibrary = {
            textureFavorites = {},
        },
        globalStyle = {
            buttonSize = 36,
            buttonSpacing = 2,
            borderSize = 1,
            borderColor = {0, 0, 0, 1},
            cooldownFontSize = 12,
            cooldownFontOutline = "OUTLINE",
            cooldownFont = "Friz Quadrata TT",
            cooldownFontColor = {1, 1, 1, 1},
            cooldownTextAnchor = "CENTER",
            cooldownTextXOffset = 0,
            cooldownTextYOffset = 0,
            separateTextPositions = false,
            auraTextAnchor = "TOPLEFT",
            auraTextXOffset = 2,
            auraTextYOffset = -2,
            iconWidthRatio = 1.0,
            maintainAspectRatio = true,
            showTooltips = false,
            desaturateOnCooldown = true,
            showCooldownSwipe = true,
            showCooldownSwipeFill = true,
            cooldownSwipeReverse = false,
            showCooldownSwipeEdge = true,
            cooldownSwipeAlpha = 0.8,
            cooldownSwipeEdgeColor = {1, 1, 1, 1},
            showGCDSwipe = false,
            showOutOfRange = true,
            showAssistedHighlight = false,
            assistedHighlightHostileTargetOnly = true,
            assistedHighlightStyle = "blizzard",
            assistedHighlightColor = {0.3, 1, 0.3, 0.9},
            assistedHighlightBorderSize = 2,
            assistedHighlightBlizzardOverhang = 32,
            assistedHighlightProcOverhang = 32,
            assistedHighlightCombatOnly = false,
            showUnusable = false,
            iconUnusableTintColor = {0.4, 0.4, 0.4, 1},
            iconTintColor = {1, 1, 1, 1},
            iconCooldownTintEnabled = false,
            iconCooldownTintColor = {1, 0, 0.102, 1},
            iconAuraTintEnabled = false,
            iconAuraTintColor = {0, 0.925, 1, 1},
            showLossOfControl = false,
            procGlowOverhang = 32,
            procGlowColor = {1, 1, 1, 1},
            procGlowStyle = "glow",
            procGlowSize = 30,
            procGlowThickness = 4,
            procGlowSpeed = 50,
            procGlowLines = 8,
            procGlowCombatOnly = false,
            pandemicGlowStyle = "solid",
            pandemicGlowColor = {1, 0.5, 0, 1},
            pandemicGlowSize = 5,
            pandemicGlowThickness = 4,
            pandemicGlowSpeed = 50,
            pandemicGlowLines = 8,
            pandemicGlowCombatOnly = false,
            barPandemicColor = {1, 0.5, 0, 1},
            pandemicBarEffect = "none",
            pandemicBarEffectColor = {1, 0.5, 0, 1},
            pandemicBarEffectSize = 5,
            pandemicBarEffectThickness = 4,
            pandemicBarEffectSpeed = 50,
            pandemicBarEffectLines = 8,
            pandemicBarPulseEnabled = false,
            pandemicBarPulseSpeed = 0.5,
            pandemicBarColorShiftEnabled = false,
            pandemicBarColorShiftSpeed = 0.5,
            pandemicBarColorShiftColor = {1, 1, 1, 1},
            auraGlowStyle = "pixel",
            auraGlowColor = {1, 0.84, 0, 0.9},
            auraGlowSize = 8,
            auraGlowThickness = 4,
            auraGlowSpeed = 50,
            auraGlowLines = 8,
            auraGlowInvert = false,
            auraGlowCombatOnly = false,
            readyGlowStyle = "none",
            readyGlowColor = {0.2, 1.0, 0.2, 1},
            readyGlowSize = 5,
            readyGlowThickness = 4,
            readyGlowSpeed = 50,
            readyGlowLines = 8,
            readyGlowCombatOnly = false,
            readyGlowDuration = 0,
            keyPressHighlightStyle = "none",
            keyPressHighlightColor = {1, 1, 1, 0.4},
            keyPressHighlightSize = 5,
            keyPressHighlightCombatOnly = false,
            barAuraColor = {0.2, 1.0, 0.2, 1.0},
            barAuraEffect = "color",
            barAuraEffectColor = {1, 0.84, 0, 0.9},
            barAuraEffectSize = 8,
            barAuraEffectThickness = 4,
            barAuraEffectSpeed = 50,
            barAuraEffectLines = 8,
            barAuraPulseEnabled = false,
            barAuraPulseSpeed = 0.5,
            barAuraColorShiftEnabled = false,
            barAuraColorShiftSpeed = 0.5,
            barAuraColorShiftColor = {1, 1, 1, 1},
            textureIndicators = {
                proc = { enabled = false, effectType = "pulse", speed = 0.5, color = {1, 1, 1, 1}, combatOnly = false },
                aura = { enabled = false, effectType = "colorShift", speed = 0.5, color = {1, 0.84, 0, 1}, combatOnly = false, invert = false },
                pandemic = { enabled = false, effectType = "shrinkExpand", speed = 0.5, color = {1, 0.5, 0, 1}, combatOnly = false },
                ready = { enabled = false, effectType = "bounce", speed = 0.5, color = {0.2, 1.0, 0.2, 1}, combatOnly = false },
                unusable = { enabled = false, effectType = "pulse", speed = 0.5, color = {1, 0.35, 0.35, 1}, combatOnly = false },
            },
            assistedHighlightProcColor = {1, 1, 1, 1},
            strataOrder = nil,
            showKeybindText = false,
            keybindFont = "Friz Quadrata TT",
            keybindFontSize = 10,
            keybindFontOutline = "OUTLINE",
            keybindFontColor = {1, 1, 1, 1},
            keybindAnchor = "TOPRIGHT",
            keybindXOffset = -2,
            keybindYOffset = -2,
            showChargeText = true,
            chargeFont = "Friz Quadrata TT",
            chargeFontSize = 12,
            chargeFontOutline = "OUTLINE",
            chargeFontColor = {1, 1, 1, 1},
            chargeFontColorMissing = {1, 1, 1, 1},
            chargeFontColorZero = {1, 1, 1, 1},
            chargeAnchor = "BOTTOMRIGHT",
            chargeXOffset = -2,
            chargeYOffset = 2,
            barLength = 180,
            barHeight = 20,
            barColor = {0.2, 0.6, 1.0, 1.0},
            barCooldownColor = {0.6, 0.13, 0.18, 1.0},
            barChargeColor = {1.0, 0.82, 0.0, 1.0},
            barBgColor = {0.1, 0.1, 0.1, 0.8},
            showBarIcon = true,
            barIconSizeOverride = false,
            barIconSize = 20,
            showBarNameText = true,
            barNameFont = "Friz Quadrata TT",
            barNameFontSize = 10,
            barNameFontOutline = "OUTLINE",
            barNameFontColor = {1, 1, 1, 1},
            showBarReadyText = false,
            barReadyText = "Ready",
            barReadyTextColor = {0.2, 1.0, 0.2, 1.0},
            barReadyFontSize = 12,
            barReadyFont = "Friz Quadrata TT",
            barReadyFontOutline = "OUTLINE",
            barUpdateInterval = 0.025,
            barTexture = "Solid",
            textWidth = 200,
            textHeight = 20,
            textFormat = "{name}  {status}",
            textFont = "Friz Quadrata TT",
            textFontSize = 12,
            textFontOutline = "OUTLINE",
            textFontColor = {1, 1, 1, 1},
            textAlignment = "LEFT",
            textCooldownColor = {1, 0.3, 0.3, 1},
            textReadyColor = {0.2, 1.0, 0.2, 1},
            textReadyText = "Ready",
            textAuraColor = {0, 0.925, 1, 1},
            textCustomColor = {1, 0.82, 0, 1},
            textBgColor = {0, 0, 0, 0},
            textBorderSize = 0,
            textBorderColor = {0, 0, 0, 1},
            textShadow = false,
            decimalTimers = false,
            showTextGroupHeader = false,
            textHeaderFontSize = 12,
            textHeaderFontColor = {1, 1, 1, 1},
        },
        locked = false,
        cdmHidden = false,
        resourceBars = {
            enabled = false,
            anchorGroupId = nil,
            inheritAlpha = false,
            orientation = "horizontal",
            yOffset = 3,
            verticalXOffset = 3,
            barHeight = 12,
            barWidth = 12,
            barSpacing = 3.6,
            verticalFillDirection = "bottom_to_top",
            barTexture = "Solid",
            backgroundColor = { 0, 0, 0, 0.5 },
            borderStyle = "pixel",
            borderColor = { 0, 0, 0, 1 },
            borderSize = 1,
            segmentGap = 4,
            hideManaForNonHealer = true,
            resources = {
                [100] = {
                    enabled = true,
                    mwBaseColor = nil,
                    mwOverlayColor = nil,
                    mwMaxColor = nil,
                    segThresholdEnabled = false,
                    segThresholdValue = 1,
                    segThresholdColor = nil,
                    continuousTickEnabled = false,
                    continuousTickMode = "percent",
                    continuousTickPercent = 50,
                    continuousTickAbsolute = 50,
                    continuousTickColor = nil,
                    continuousTickCombatOnly = false,
                },
                [101] = {
                    enabled = true,
                    staggerGreenColor = nil,
                    staggerYellowColor = nil,
                    staggerRedColor = nil,
                    showText = false,
                    textFormat = "percent",
                },
            },
            customAuraBarSlots = {
                [1] = { position = "below", order = 1001 },
                [2] = { position = "below", order = 1002 },
                [3] = { position = "below", order = 1003 },
                [4] = { position = "below", order = 1004 },
                [5] = { position = "below", order = 1005 },
            },
            customAuraBars = {},
            layoutOrder = {},
            textFont = "Friz Quadrata TT",
            textFontSize = 10,
            textFontOutline = "OUTLINE",
            textFontColor = { 1, 1, 1, 1 },
            textFormat = "current",
            independentAnchorEnabled = false,
            independentAnchorLocked = true,
            independentAnchor = nil,
            independentWidth = nil,
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
            customFade = false,
            fadeDelay = 1,
            fadeInDuration = 0.2,
            fadeOutDuration = 0.2,
        },
        castBar = {
            enabled = false,
            stylingEnabled = true,
            anchorGroupId = nil,
            position = "below",
            order = 2000,
            panelAnchorYOffsetEnabled = false,
            panelAnchorYOffset = 0,
            height = 15,
            barColor = { 1.0, 0.7, 0.0, 1.0 },
            backgroundColor = { 0, 0, 0, 0.5 },
            barTexture = "Solid",
            showIcon = true,
            iconSize = 16,
            iconFlipSide = false,
            iconOffset = false,
            iconOffsetX = 0,
            iconOffsetY = 0,
            iconBorderSize = 1,
            showSpark = true,
            showSparkTrail = true,
            showInterruptShake = true,
            showInterruptGlow = true,
            showCastFinishFX = true,
            borderStyle = "pixel",
            borderColor = { 0, 0, 0, 1 },
            borderSize = 1,
            showNameText = true,
            nameFont = "Friz Quadrata TT",
            nameFontSize = 10,
            nameFontOutline = "OUTLINE",
            nameFontColor = { 1, 1, 1, 1 },
            showCastTimeText = true,
            castTimeFont = "Friz Quadrata TT",
            castTimeFontSize = 10,
            castTimeFontOutline = "OUTLINE",
            castTimeFontColor = { 1, 1, 1, 1 },
            castTimeXOffset = 0,
            castTimeYOffset = 0,
            independentAnchorEnabled = false,
            independentAnchorLocked = true,
            independentAnchor = nil,
            independentWidth = nil,
        },
        frameAnchoring = {
            enabled = false,
            anchorGroupId = nil,
            mirroring = true,
            inheritAlpha = true,
            unitFrameAddon = nil,
            customPlayerFrame = "",
            customTargetFrame = "",
            player = {
                anchorPoint = "RIGHT",
                relativePoint = "LEFT",
                xOffset = -10,
                yOffset = 0,
            },
            target = {
                anchorPoint = "LEFT",
                relativePoint = "RIGHT",
                xOffset = 10,
                yOffset = 0,
            },
        },
    },
}

local COMPACT_ENTITY_DEFAULTS = {
    [CURRENT_COMPACT_FORMAT_VALUE] = {
        loadConditions = {
            raid = false,
            dungeon = false,
            delve = false,
            battleground = false,
            arena = false,
            openWorld = false,
            rested = false,
            petBattle = true,
            vehicleUI = true,
        },
        panel = {
            displayMode = "icons",
            masqueEnabled = false,
            compactLayout = false,
            maxVisibleButtons = 0,
            compactGrowthDirection = "center",
            baselineAlpha = 1,
            fadeDelay = 1,
            fadeInDuration = 0.2,
            fadeOutDuration = 0.2,
        },
        container = {
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
        },
        containerAnchor = {
            point = "CENTER",
            relativeTo = "UIParent",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
    },
}

COMPACT_PROFILE_DEFAULTS[PREVIOUS_COMPACT_FORMAT_VALUE] = CopyTable(COMPACT_PROFILE_DEFAULTS[CURRENT_COMPACT_FORMAT_VALUE])
COMPACT_PROFILE_DEFAULTS[PREVIOUS_COMPACT_FORMAT_VALUE].auraTextureLibrary.recentProcOverlays = {}
COMPACT_ENTITY_DEFAULTS[PREVIOUS_COMPACT_FORMAT_VALUE] = CopyTable(COMPACT_ENTITY_DEFAULTS[CURRENT_COMPACT_FORMAT_VALUE])

-- compact1 shipped before defaults were version-pinned. Freeze it against the
-- original baseline so older compact strings do not drift as live defaults
-- evolve in later releases.
COMPACT_PROFILE_DEFAULTS[LEGACY_COMPACT_FORMAT_VALUE] = CopyTable(COMPACT_PROFILE_DEFAULTS[PREVIOUS_COMPACT_FORMAT_VALUE])
COMPACT_ENTITY_DEFAULTS[LEGACY_COMPACT_FORMAT_VALUE] = CopyTable(COMPACT_ENTITY_DEFAULTS[PREVIOUS_COMPACT_FORMAT_VALUE])

local function CopyValue(value)
    if type(value) == "table" then
        return CopyTable(value)
    end
    return value
end

local function PrepareSharedImportText(text)
    if type(text) ~= "string" then
        return nil, nil, false
    end

    local trimmed = text:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil, nil, false
    end

    local isLegacy = trimmed:sub(1, 2) == "^1"
    local compact = isLegacy and trimmed or trimmed:gsub("%s+", "")
    if compact == "" then
        return nil, nil, false
    end

    return trimmed, compact, isLegacy
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

local function GetDefaultsProfile(formatVersion)
    local frozenDefaults = COMPACT_PROFILE_DEFAULTS[formatVersion]
    if frozenDefaults then
        return frozenDefaults
    end
    return ST._defaults and ST._defaults.profile or {}
end

local function GetSubsystemDefaults(defaultKey, formatVersion)
    local profileDefaults = GetDefaultsProfile(formatVersion)
    if type(profileDefaults[defaultKey]) == "table" then
        return profileDefaults[defaultKey]
    end
    return {}
end

local function GetEntityDefaults(formatVersion)
    return COMPACT_ENTITY_DEFAULTS[formatVersion]
end

local function GetLoadConditionsDefaults(formatVersion)
    local entityDefaults = GetEntityDefaults(formatVersion)
    if entityDefaults and entityDefaults.loadConditions then
        return entityDefaults.loadConditions
    end
    return LOAD_CONDITIONS_DEFAULTS
end

local function GetPanelDefaults(formatVersion)
    local entityDefaults = GetEntityDefaults(formatVersion)
    if entityDefaults and entityDefaults.panel then
        return entityDefaults.panel
    end
    return PANEL_DEFAULTS
end

local function GetContainerDefaults(formatVersion)
    local entityDefaults = GetEntityDefaults(formatVersion)
    if entityDefaults and entityDefaults.container then
        return entityDefaults.container
    end
    return CONTAINER_DEFAULTS
end

local function GetContainerDefaultAnchor(formatVersion)
    local entityDefaults = GetEntityDefaults(formatVersion)
    if entityDefaults and entityDefaults.containerAnchor then
        return entityDefaults.containerAnchor
    end
    return CONTAINER_DEFAULT_ANCHOR
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

local function CompactLoadConditions(loadConditions, formatVersion)
    if type(loadConditions) ~= "table" then
        return nil
    end
    local compact = CompactTableAgainstDefaults(loadConditions, GetLoadConditionsDefaults(formatVersion))
    return compact or {}
end

local function RehydrateLoadConditions(loadConditions, formatVersion)
    if type(loadConditions) ~= "table" then
        return nil
    end
    return MergeWithDefaults(loadConditions, GetLoadConditionsDefaults(formatVersion))
end

local function CompactPanel(group, styleDefaults, panelContainerRef, formatVersion)
    if type(group) ~= "table" then
        return nil
    end

    local panelDefaults = GetPanelDefaults(formatVersion)
    local compact = {}
    for key, value in pairs(group) do
        if key == "style" then
            local compactStyle = CompactTableAgainstDefaults(value, styleDefaults)
            if compactStyle then
                compact.style = compactStyle
            end
        elseif key == "loadConditions" then
            local compactLoadConditions = CompactLoadConditions(value, formatVersion)
            if compactLoadConditions then
                compact.loadConditions = compactLoadConditions
            end
        elseif key == "anchor" then
            local compactAnchor = CompactAnchorIfDefault(value, BuildPanelDefaultAnchor(panelContainerRef))
            if compactAnchor then
                compact.anchor = compactAnchor
            end
        elseif panelDefaults[key] ~= nil then
            if not DeepEqual(value, panelDefaults[key]) then
                compact[key] = CopyValue(value)
            end
        else
            compact[key] = CopyValue(value)
        end
    end
    return compact
end

local function RehydratePanel(group, styleDefaults, panelContainerRef, formatVersion)
    if type(group) ~= "table" then
        return
    end

    local panelDefaults = GetPanelDefaults(formatVersion)
    group.style = MergeWithDefaults(group.style, styleDefaults)

    if group.loadConditions ~= nil then
        group.loadConditions = RehydrateLoadConditions(group.loadConditions, formatVersion)
    end

    local defaultAnchor = BuildPanelDefaultAnchor(panelContainerRef)
    if group.anchor == nil and defaultAnchor then
        group.anchor = CopyTable(defaultAnchor)
    elseif type(group.anchor) == "table" and defaultAnchor then
        group.anchor = MergeWithDefaults(group.anchor, defaultAnchor)
    end

    for key, defaultValue in pairs(panelDefaults) do
        if group[key] == nil then
            group[key] = CopyValue(defaultValue)
        end
    end
end

local function CompactContainer(container, formatVersion)
    if type(container) ~= "table" then
        return nil
    end

    local containerDefaults = GetContainerDefaults(formatVersion)
    local containerAnchorDefaults = GetContainerDefaultAnchor(formatVersion)
    local compact = {}
    for key, value in pairs(container) do
        if key == "loadConditions" then
            local compactLoadConditions = CompactLoadConditions(value, formatVersion)
            if compactLoadConditions then
                compact.loadConditions = compactLoadConditions
            end
        elseif key == "anchor" then
            local compactAnchor = CompactAnchorIfDefault(value, containerAnchorDefaults)
            if compactAnchor then
                compact.anchor = compactAnchor
            end
        elseif containerDefaults[key] ~= nil then
            if not DeepEqual(value, containerDefaults[key]) then
                compact[key] = CopyValue(value)
            end
        else
            compact[key] = CopyValue(value)
        end
    end
    return compact
end

local function RehydrateContainer(container, formatVersion)
    if type(container) ~= "table" then
        return
    end

    local containerDefaults = GetContainerDefaults(formatVersion)
    local containerAnchorDefaults = GetContainerDefaultAnchor(formatVersion)
    if container.loadConditions ~= nil then
        container.loadConditions = RehydrateLoadConditions(container.loadConditions, formatVersion)
    end

    if container.anchor == nil then
        container.anchor = CopyTable(containerAnchorDefaults)
    elseif type(container.anchor) == "table" then
        container.anchor = MergeWithDefaults(container.anchor, containerAnchorDefaults)
    end
    if CooldownCompanion and CooldownCompanion.NormalizeContainerAnchor then
        container.anchor = CooldownCompanion:NormalizeContainerAnchor(container.anchor)
    end

    for key, defaultValue in pairs(containerDefaults) do
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

local function CompactScopedSettings(settings, defaultKey, preserveEmptyRoot, formatVersion)
    if type(settings) ~= "table" then
        return CopyValue(settings)
    end

    local compact = CompactTableAgainstDefaults(settings, GetSubsystemDefaults(defaultKey, formatVersion))
    if compact then
        return compact
    end
    if preserveEmptyRoot then
        return {}
    end
    return nil
end

local function RehydrateScopedSettings(settings, defaultKey, formatVersion)
    return MergeWithDefaults(settings, GetSubsystemDefaults(defaultKey, formatVersion))
end

local function CompactScopedStore(store, defaultKey, formatVersion)
    if type(store) ~= "table" then
        return CopyValue(store)
    end

    local compact = {}
    for charKey, settings in pairs(store) do
        compact[charKey] = CompactScopedSettings(settings, defaultKey, true, formatVersion) or {}
    end
    return compact
end

local function RehydrateScopedStore(store, defaultKey, formatVersion)
    if type(store) ~= "table" then
        return store
    end

    for charKey, settings in pairs(store) do
        if type(settings) == "table" then
            store[charKey] = RehydrateScopedSettings(settings, defaultKey, formatVersion)
        end
    end
    return store
end

local function NormalizeTextureLibraryStore(store)
    if type(store) ~= "table" then
        return store
    end

    if type(CooldownCompanion.NormalizeAuraTextureLibraryStore) == "function" then
        return CooldownCompanion:NormalizeAuraTextureLibraryStore(store)
    end

    if type(store.customTextures) ~= "table" then
        store.customTextures = {}
    end
    if type(store.textureFavorites) ~= "table" then
        store.textureFavorites = {}
    end

    local legacyFavorites = store.sharedMediaFavorites
    if type(legacyFavorites) == "table" then
        for storedKey, storedValue in pairs(legacyFavorites) do
            if type(storedValue) == "string" then
                store.textureFavorites[storedValue] = store.textureFavorites[storedValue] or storedValue
            elseif type(storedValue) == "table" then
                local favoriteKey = storedValue.favoriteKey
                if type(favoriteKey) == "string" then
                    store.textureFavorites[favoriteKey] = store.textureFavorites[favoriteKey] or CopyTable(storedValue)
                end
            end
            legacyFavorites[storedKey] = nil
        end
    end

    if type(store.textureFavorites) == "table" then
        for favoriteKey, favoriteValue in pairs(store.textureFavorites) do
            local storedFavoriteKey = type(favoriteValue) == "table" and favoriteValue.favoriteKey or nil
            if (type(favoriteKey) == "string" and string.find(favoriteKey, "^favorite:legacy%-proc:"))
                or (type(storedFavoriteKey) == "string" and string.find(storedFavoriteKey, "^favorite:legacy%-proc:")) then
                store.textureFavorites[favoriteKey] = nil
            end
        end
    end

    store.sharedMediaFavorites = nil
    store.recentProcOverlays = nil
    return store
end

local function NormalizeTextureLibraryProfile(profile)
    if type(profile) ~= "table" then
        return profile
    end

    if type(profile.auraTextureLibrary) ~= "table" then
        return profile
    end

    profile.auraTextureLibrary = NormalizeTextureLibraryStore(profile.auraTextureLibrary)
    return profile
end

local function NormalizeTextureLibraryPayload(data)
    if type(data) ~= "table" then
        return data
    end

    if type(data.profile) == "table" then
        data.profile = NormalizeTextureLibraryProfile(data.profile)
        return data
    end

    if data.type then
        return data
    end

    return NormalizeTextureLibraryProfile(data)
end

local function CompactProfile(profile, formatVersion)
    if type(profile) ~= "table" then
        return profile
    end

    profile = NormalizeTextureLibraryProfile(CopyTable(profile))
    local profileDefaults = GetDefaultsProfile(formatVersion)
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
                local compactValue = CompactScopedSettings(value, SCOPED_SYSTEM_DEFAULTS[key], true, formatVersion)
                if compactValue ~= nil then
                    compact[key] = compactValue
                end
            elseif SCOPED_STORE_KEYS[key] then
                compact[key] = CompactScopedStore(value, SCOPED_STORE_KEYS[key], formatVersion)
            elseif key == "groups" and type(value) == "table" then
                local compactGroups = {}
                for groupId, group in pairs(value) do
                    compactGroups[groupId] = CompactPanel(group, globalStyleDefaults, group.parentContainerId, formatVersion)
                end
                compact.groups = compactGroups
            elseif key == "groupContainers" and type(value) == "table" then
                local compactContainers = {}
                for containerId, container in pairs(value) do
                    compactContainers[containerId] = CompactContainer(container, formatVersion)
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

local function RehydrateProfile(profile, formatVersion)
    if type(profile) ~= "table" then
        return profile
    end

    local profileDefaults = GetDefaultsProfile(formatVersion)

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
            profile[key] = RehydrateScopedSettings(profile[key], defaultKey, formatVersion)
        end
    end

    for key, defaultKey in pairs(SCOPED_STORE_KEYS) do
        if profile[key] ~= nil then
            profile[key] = RehydrateScopedStore(profile[key], defaultKey, formatVersion)
        end
    end

    local globalStyleDefaults = profile.globalStyle or profileDefaults.globalStyle or {}

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                RehydratePanel(group, globalStyleDefaults, group.parentContainerId, formatVersion)
            end
        end
    end

    if type(profile.groupContainers) == "table" then
        for _, container in pairs(profile.groupContainers) do
            if type(container) == "table" then
                RehydrateContainer(container, formatVersion)
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

    return NormalizeTextureLibraryProfile(profile)
end

local function CompactEntityPayload(payload, formatVersion)
    if type(payload) ~= "table" then
        return payload
    end

    local compact = CopyTable(payload)
    local globalStyleDefaults = GetSubsystemDefaults("globalStyle", formatVersion)

    if payload.group then
        compact.group = CompactPanel(payload.group, globalStyleDefaults, nil, formatVersion)
    end
    if type(payload.groups) == "table" then
        compact.groups = {}
        for index, group in ipairs(payload.groups) do
            compact.groups[index] = CompactPanel(group, globalStyleDefaults, nil, formatVersion)
        end
    end
    if payload.container then
        compact.container = CompactContainer(payload.container, formatVersion)
    end
    if type(payload.panels) == "table" then
        compact.panels = {}
        local panelContainerRef = payload._originalContainerId
        for index, panel in ipairs(payload.panels) do
            compact.panels[index] = CompactPanel(panel, globalStyleDefaults, panelContainerRef, formatVersion)
        end
    end
    if type(payload.containers) == "table" then
        compact.containers = {}
        for index, entry in ipairs(payload.containers) do
            local compactEntry = {}
            for key, value in pairs(entry) do
                if key == "container" then
                    compactEntry.container = CompactContainer(value, formatVersion)
                elseif key == "panels" and type(value) == "table" then
                    compactEntry.panels = {}
                    local panelContainerRef = entry._originalContainerId
                    for panelIndex, panel in ipairs(value) do
                        compactEntry.panels[panelIndex] = CompactPanel(panel, globalStyleDefaults, panelContainerRef, formatVersion)
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

local function RehydrateEntityPayload(payload, formatVersion)
    if type(payload) ~= "table" then
        return payload
    end

    local globalStyleDefaults = GetSubsystemDefaults("globalStyle", formatVersion)

    if type(payload.group) == "table" then
        RehydratePanel(payload.group, globalStyleDefaults, nil, formatVersion)
    end
    if type(payload.groups) == "table" then
        for _, group in ipairs(payload.groups) do
            if type(group) == "table" then
                RehydratePanel(group, globalStyleDefaults, nil, formatVersion)
            end
        end
    end
    if type(payload.container) == "table" then
        RehydrateContainer(payload.container, formatVersion)
    end
    if type(payload.panels) == "table" then
        local panelContainerRef = payload._originalContainerId
        for _, panel in ipairs(payload.panels) do
            if type(panel) == "table" then
                RehydratePanel(panel, globalStyleDefaults, panelContainerRef, formatVersion)
            end
        end
    end
    if type(payload.containers) == "table" then
        for _, entry in ipairs(payload.containers) do
            if type(entry.container) == "table" then
                RehydrateContainer(entry.container, formatVersion)
            end
            if type(entry.panels) == "table" then
                local panelContainerRef = entry._originalContainerId
                for _, panel in ipairs(entry.panels) do
                    if type(panel) == "table" then
                        RehydratePanel(panel, globalStyleDefaults, panelContainerRef, formatVersion)
                    end
                end
            end
        end
    end

    return payload
end

local function CompactDiagnosticSnapshot(snapshot, formatVersion)
    if type(snapshot) ~= "table" then
        return snapshot
    end

    local compact = CopyTable(snapshot)

    if type(compact.profile) == "table" then
        compact.profile = CompactProfile(compact.profile, formatVersion)
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

local function RehydrateCompactPayload(data, formatVersion)
    if type(data) ~= "table" then
        return data
    end

    if data.profile and type(data.profile) == "table" then
        data.profile = RehydrateProfile(data.profile, formatVersion)
        return NormalizeTextureLibraryPayload(data)
    end

    if data.type then
        return RehydrateEntityPayload(data, formatVersion)
    end

    return NormalizeTextureLibraryProfile(RehydrateProfile(data, formatVersion))
end

local function EncodeSharedPayload(payload, exportKind)
    local exportData = CopyTable(payload)
    local formatVersion = CURRENT_COMPACT_FORMAT_VALUE

    if exportKind == "profile" then
        exportData = CompactProfile(exportData, formatVersion)
    elseif exportKind == "diagnostic" then
        exportData = CompactDiagnosticSnapshot(exportData, formatVersion)
    else
        exportData = CompactEntityPayload(exportData, formatVersion)
    end

    exportData[COMPACT_FORMAT_KEY] = formatVersion

    local serialized = AceSerializer:Serialize(exportData)
    local compressed = LibDeflate:CompressDeflate(serialized, COMPRESSION_CONFIG)
    return LibDeflate:EncodeForPrint(compressed)
end

local function DecodeSharedPayload(text)
    local trimmed, normalized, isLegacy = PrepareSharedImportText(text)
    if not trimmed then
        return false, nil
    end

    if isLegacy then
        return false, nil
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

    local formatVersion = data[COMPACT_FORMAT_KEY]
    if formatVersion == LEGACY_COMPACT_FORMAT_VALUE
        or formatVersion == PREVIOUS_COMPACT_FORMAT_VALUE
        or formatVersion == CURRENT_COMPACT_FORMAT_VALUE then
        data[COMPACT_FORMAT_KEY] = nil
        data = RehydrateCompactPayload(data, formatVersion)
    else
        data = NormalizeTextureLibraryPayload(data)
    end

    return true, data
end

ST._EncodeSharedPayload = EncodeSharedPayload
ST._DecodeSharedPayload = DecodeSharedPayload
ST._PrepareSharedImportText = PrepareSharedImportText
