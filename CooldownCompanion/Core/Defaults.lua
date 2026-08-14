--[[
    CooldownCompanion - Core/Defaults.lua: Profile schema and override sections registry
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

ST.DISPLAY_MODE_ROTATION_ASSISTANT = "rotationAssistant"
ST.ROTATION_ASSISTANT_NAME = "Assistant Panel"
ST.ROTATION_ASSISTANT_ACTION_SPELL_ID = 1229376
ST.ROTATION_ASSISTANT_FALLBACK_ICON = 6718291

-- The one dim strength every "dim instead of hide" rule renders at: the
-- aura-inactive shell and the seven cooldown-family rules alike. These used
-- to read the panel's Baseline Alpha, which defaults to 1 and therefore made
-- the toggles do nothing on a stock panel. Baseline Alpha still governs panel
-- alpha fade; it no longer governs dimming. Lives here so it is defined
-- before Aura.lua and Visibility.lua and readable from the config addon.
CooldownCompanion.DIM_FALLBACK_ALPHA = 0.4

-- Default database structure
local defaults = {
    global = {
        characterInfo = {},  -- [charKey] = { classFilename, classID }
        changelog = {
            lastSeenVersion = nil,
            fontSize = 13,
        },
        tutorials = {
            firstIconPanel = {
                completed = false,
                dismissed = false,
                lastVersionSeen = nil,
            },
        },
    },
    profile = {
        minimap = {
            hide = false,
        },
        escClosesConfig = true,
        profileOnePixelBorders = false,
        profileWideFontEnabled = false,
        profileWideFontName = nil,
        profileWideFontOutline = nil,
        profileWideBarTextureEnabled = false,
        profileWideBarTextureName = nil,
        showAdvanced = {},
        groupSettingPresets = {
            icons = {},
            bars = {},
        },
        auraTextureLibrary = {
            textureFavorites = {},
        },
        groups = {
            --[[
                [groupId] = {
                    name = "Group Name",
                    anchor = {
                        point = "CENTER",
                        relativeTo = "UIParent",
                        relativePoint = "CENTER",
                        x = 0,
                        y = 0,
                    },
                    buttons = {
                        [index] = {
                            type = "spell" or "item" or "equipmentSlot",
                            id = spellId or itemId, -- spell/item entries only
                            itemSlot = 13 or 14, -- equipmentSlot entries only
                            itemSlotKind = "trinket", -- equipmentSlot entries only
                            name = "Spell/Item/Slot Name",
                        }
                    },
                    style = {
                        buttonSize = 36,
                        buttonSpacing = 2,
                        borderSize = 1,
                        borderRenderMode = "custom",
                        borderColor = {0, 0, 0, 1},
                        backgroundColor = {0, 0, 0, 0.5},
                        orientation = "horizontal", -- "horizontal" or "vertical"
                        growthOrigin = "TOPLEFT", -- "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"
                        buttonsPerRow = 12,
                        showCooldownText = true,
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
                        showAuraText = true, -- nil defaults to true via ~= false
                        auraTextFont = "Friz Quadrata TT",
                        auraTextFontSize = 12,
                        auraTextFontOutline = "OUTLINE",
                        auraTextFontColor = {0, 0.925, 1, 1},
                        pandemicMarkerEnabled = true, -- group-wide kill switch for the marker feature
                        pandemicMarkerText = "!!",
                        pandemicMarkerColorMode = "marker", -- "off" / "marker" / "whole"
                        pandemicMarkerColor = {1, 0.5, 0, 1},
                        iconWidthRatio = 1.0, -- 1.0 = square, <1 = taller, >1 = wider
                        maintainAspectRatio = true, -- Prevent icon image stretching
                        iconZoom = 0, -- % the artwork is cropped toward center (WeakAuras-style zoom)
                        showTooltips = false,
                        tooltipAnchor = "default", -- "default"/"above"/"below"/"left"/"right"/"cursor"
                        tooltipHideInCombat = false,
                        allowPings = false, -- Entries answer the ping keybind like Cooldown Manager items
                        desaturateOnCooldown = true, -- Desaturate icon while on cooldown
                        showCooldownSwipe = true,
                        showAuraDurationSwipe = true,
                        showCooldownSwipeFill = true,
                        cooldownSwipeReverse = false,
                        cooldownSwipeEdgeEnabled = false, -- explicit-true; Blizzard's 12.1 cooldowns draw no edge
                        cooldownSwipeAlpha = 0.8,
                        cooldownSwipeEdgeColor = {1, 1, 1, 1},
                        showAuraDurationSwipeFill = true,
                        auraDurationSwipeReverse = true,
                        auraDurationSwipeEdgeEnabled = false, -- explicit-true; mirrors the cooldown edge default
                        auraDurationSwipeAlpha = 0.8,
                        auraDurationSwipeEdgeColor = {1, 1, 1, 1},
                        auraUseBlizzardSwipe = false,
                        showGCDSwipe = false, -- Show GCD swipe animation on icons
                        showOutOfRange = true, -- Red-tint icons when target is out of range
                        showAssistedHighlight = false, -- Highlight the assisted combat recommended spell
                        assistedHighlightHostileTargetOnly = true, -- Show only for hostile (attackable) targets
                        assistedHighlightStyle = "blizzard", -- "blizzard", "solid", or "proc"
                        assistedHighlightColor = {0.3, 1, 0.3, 0.9},
                        assistedHighlightBorderSize = 2,
                        assistedHighlightBlizzardOverhang = 32, -- % overhang for blizzard style
                        assistedHighlightProcOverhang = 32, -- % overhang for proc style
                        assistedHighlightProcColor = {1, 1, 1, 1},
                        assistedHighlightCombatOnly = false,
                        showUnusable = true,
                        unusableVisualMode = "dim",
                        iconUnusableTintColor = {0.4, 0.4, 0.4, 1},
                        iconTintColor = {1, 1, 1, 1},           -- base icon vertex color (RGBA)
                        iconCooldownTintEnabled = false,         -- apply separate tint when on cooldown
                        iconCooldownTintColor = {1, 0, 0.102, 1}, -- cooldown tint (default: 60% opacity white)
                        iconAuraTintEnabled = false,             -- apply separate tint when aura is active
                        iconAuraTintColor = {0, 0.925, 1, 1},       -- aura tint (default: white full opacity)
                        iconFillEnabled = false,
                        iconFillOrientation = "vertical",
                        iconFillReverse = false,
                        iconFillTimerBehavior = "drain",
                        iconFillCooldownColor = {0.6, 0.13, 0.18, 0.55},
                        showLossOfControl = true,
                        procGlowOverhang = 32,
                        procGlowColor = {1, 1, 1, 1},
                        procGlowStyle = "glow",
                        procGlowSize = 30,
                        procGlowThickness = 4,
                        procGlowSpeed = 50,
                        procGlowLines = 8,
                        procGlowCombatOnly = false,
                        pandemicEffectEnabled = false, -- explicit-true master switch (PTR 8 pandemic display)
                        pandemicGlowStyle = "solid", -- kit styles, same menu as auraGlowStyle
                        pandemicGlowColor = {1, 0.5, 0, 1},
                        pandemicGlowColor2 = {1, 1, 1, 0.9}, -- colorShift second color
                        pandemicGlowSize = 2,        -- border/dash px, or overhang % (proc/ants)
                        pandemicGlowThickness = 3,   -- dash thickness px
                        pandemicGlowSpeed = 0.5,     -- seconds: pulse/shift cycle, or dashes lap
                        pandemicGlowLines = 5,       -- dash count
                        barPandemicColor = {1, 0.5, 0, 1},
                        auraGlowStyle = "pulse", -- kit styles: none/solid/pulse/colorShift/dashes/ants/proc/overlay
                        auraGlowColor = {1, 0.84, 0, 0.9},
                        auraGlowColor2 = {0.1, 0.3, 1, 0.9}, -- colorShift second color
                        auraGlowSize = 2,        -- border/dash px, or overhang % (proc/ants)
                        auraGlowSpeed = 0.5,     -- seconds: pulse/shift cycle, or dashes lap
                        auraGlowDashCount = 5,   -- dashes style only (1..8)
                        auraGlowDashThickness = 3, -- dashes style only, line thickness px
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
                        strataOrder = nil, -- custom layer order (ST.DEFAULT_STRATA_ORDER length) or nil for default
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
                    },
                    enabled = true,
                    displayMode = "icons",    -- "icons" or "bars"
                    frameStrata = nil,        -- nil = "MEDIUM" (default), or "BACKGROUND"/"LOW"/"HIGH"/"DIALOG"
                    inheritPanelAlpha = true, -- panels anchored to panels inherit target panel alpha by default
                    -- Alpha fade system
                    baselineAlpha = 1,        -- alpha when no force conditions met (0-1)
                    forceAlphaInCombat = false,
                    forceAlphaOutOfCombat = false,
                    forceAlphaRegularMounted = false,
                    forceAlphaDragonriding = false,
                    forceAlphaTargetExists = false,
                    forceAlphaTargetEnemyOnly = false,
                    forceAlphaFocusExists = false,
                    forceAlphaMouseover = false,
                    -- Force-hidden conditions (drive alpha to 0)
                    forceHideInCombat = false,
                    forceHideOutOfCombat = false,
                    forceHideRegularMounted = false,
                    forceHideDragonriding = false,
                    fadeDelay = 1,            -- seconds before fading after mouseover ends
                    fadeInDuration = 0.2,     -- fade-in animation seconds
                    fadeOutDuration = 0.2,    -- fade-out animation seconds
                    -- Load conditions: true = unload group in this context
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
                }
            ]]
        },
        nextGroupId = 1,
        groupContainers = {},  -- [containerId] = { name, order, enabled, locked, specs, heroTalents, loadConditions, alpha/fade, anchor, ... }
        nextContainerId = 1,
        globalStyle = {
            buttonSize = 36,
            buttonSpacing = 2,
            borderSize = 1,
            borderRenderMode = "custom",
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
            pandemicMarkerEnabled = true,
            pandemicMarkerText = "!!",
            pandemicMarkerColorMode = "marker",
            pandemicMarkerColor = {1, 0.5, 0, 1},
            iconWidthRatio = 1.0,
            maintainAspectRatio = true,
            showTooltips = false,
            tooltipAnchor = "default",
            tooltipHideInCombat = false,
            allowPings = false,
            desaturateOnCooldown = true,
            showCooldownSwipe = true,
            showAuraDurationSwipe = true,
            showCooldownSwipeFill = true,
            cooldownSwipeReverse = false,
            cooldownSwipeEdgeEnabled = false, -- explicit-true; Blizzard's 12.1 cooldowns draw no edge
            cooldownSwipeAlpha = 0.8,
            cooldownSwipeEdgeColor = {1, 1, 1, 1},
            showAuraDurationSwipeFill = true,
            auraDurationSwipeReverse = true,
            auraDurationSwipeEdgeEnabled = false, -- explicit-true; mirrors the cooldown edge default
            auraDurationSwipeAlpha = 0.8,
            auraDurationSwipeEdgeColor = {1, 1, 1, 1},
            auraUseBlizzardSwipe = false,
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
            showUnusable = true,
            unusableVisualMode = "dim",
            iconUnusableTintColor = {0.4, 0.4, 0.4, 1},
            iconTintColor = {1, 1, 1, 1},
            iconCooldownTintEnabled = false,
            iconCooldownTintColor = {1, 0, 0.102, 1},
            iconAuraTintEnabled = false,
            iconAuraTintColor = {0, 0.925, 1, 1},
            iconFillEnabled = false,
            iconFillOrientation = "vertical",
            iconFillReverse = false,
            iconFillTimerBehavior = "drain",
            iconFillCooldownColor = {0.6, 0.13, 0.18, 0.55},
            showLossOfControl = true,
            procGlowOverhang = 32,
            procGlowColor = {1, 1, 1, 1},
            procGlowStyle = "glow",
            procGlowSize = 30,
            procGlowThickness = 4,
            procGlowSpeed = 50,
            procGlowLines = 8,
            procGlowCombatOnly = false,
            pandemicEffectEnabled = false, -- explicit-true master switch (PTR 8 pandemic display)
            pandemicGlowStyle = "solid", -- kit styles, same menu as auraGlowStyle
            pandemicGlowColor = {1, 0.5, 0, 1},
            pandemicGlowColor2 = {1, 1, 1, 0.9}, -- colorShift second color
            pandemicGlowSize = 2,        -- border/dash px, or overhang % (proc/ants)
            pandemicGlowThickness = 3,   -- dash thickness px
            pandemicGlowSpeed = 0.5,     -- seconds: pulse/shift cycle, or dashes lap
            pandemicGlowLines = 5,       -- dash count
            barPandemicColor = {1, 0.5, 0, 1},
            auraGlowStyle = "pulse", -- kit styles: none/solid/pulse/colorShift/dashes/ants/proc/overlay
            auraGlowColor = {1, 0.84, 0, 0.9},
            auraGlowColor2 = {0.1, 0.3, 1, 0.9}, -- colorShift second color
            auraGlowSize = 2,        -- border/dash px, or overhang % (proc/ants)
            auraGlowSpeed = 0.5,     -- seconds: pulse/shift cycle, or dashes lap
            auraGlowDashCount = 5,   -- dashes style only (1..8)
            auraGlowDashThickness = 3, -- dashes style only, line thickness px
            readyGlowStyle = "none",
            readyGlowColor = {0.2, 1.0, 0.2, 1},
            readyGlowSize = 5,
            readyGlowThickness = 4,
            readyGlowSpeed = 50,
            readyGlowLines = 8,
            readyGlowCombatOnly = false,
            readyGlowOnlyAtMaxCharges = false,
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
            -- Bar display mode defaults
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
            barTexture = "Solid",
            -- Text display mode defaults
            -- Text entries auto-size from a measured worst-case render of
            -- their format, so textPadding is the only manual size knob. The
            -- retired textWidth/textHeight pair is stripped from saved data
            -- by StripRetiredTextSizeKeys in Core/Migrations.lua.
            textPadding = 4,
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
            textBorderRenderMode = "custom",
            textBorderColor = {0, 0, 0, 1},
            textShadow = false,
            durationFormat = "clock",
            showTextGroupHeader = false,
            textHeaderFontSize = 12,
            textHeaderFontColor = {1, 1, 1, 1},
        },
        locked = false,
        resourceBarsByClass = {},
        resourceBarMigration = {
            conflicts = {},
            unsafeCharKeys = {},
        },
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
            verticalFillDirection = "bottom_to_top", -- "bottom_to_top" or "top_to_bottom"
            barTexture = "Solid",
            backgroundColor = { 0, 0, 0, 0.5 },
            borderStyle = "pixel",
            borderColor = { 0, 0, 0, 1 },
            borderSize = 1,
            borderRenderMode = "custom",
            segmentedSmoothing = "on",
            segmentGap = 4,
            hideManaForNonHealer = true,
            resources = {
                [-1] = {
                    enabled = false,
                    healthBarColor = nil,
                    healthBarOpacity = 0.7,
                    healthBarGradient = false,
                    healthBarFullColor = nil,
                    healthBarHalfColor = nil,
                    healthBarLowColor = nil,
                    healthBackgroundColor = nil,
                    healthBackgroundGradient = true,
                    healthBackgroundFullColor = nil,
                    healthBackgroundHalfColor = nil,
                    healthBackgroundLowColor = nil,
                    healthBackgroundOpacity = 1,
                    showText = false,
                    textFormat = "percent",
                    showAbsorbs = true,
                    showHealAbsorbs = true,
                    showIncomingHeals = true,
                    showLowHealthAlert = false,
                    healthAbsorbColor = { 0.55, 0.85, 1.0, 0.45 },
                    healthAbsorbTexture = "Solid",
                    healthHealAbsorbColor = { 1.0, 0.12, 0.12, 0.55 },
                    healthHealAbsorbTexture = "Solid",
                    healthIncomingHealColor = { 0.1, 0.85, 0.35, 0.45 },
                    healthIncomingHealTexture = "Solid",
                    healthLowHealthAlertColor = { 1.0, 0.08, 0.04, 0.35 },
                    healthLowHealthAlertTexture = "Solid",
                    healthLowHealthAlertMissingHealthOnly = false,
                },
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
            customBars = {},
            nextCustomBarId = 1,
            layoutOrder = {},
            displayProfiles = {},
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
            forceAlphaTargetEnemyOnly = false,
            forceAlphaFocusExists = false,
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
            iconZoom = 0,
            iconFlipSide = false,
            iconOffset = false,
            iconOffsetX = 0,
            iconOffsetY = 0,
            iconBorderSize = 1,
            iconBorderRenderMode = "custom",
            showSpark = true,
            showSparkTrail = true,
            showInterruptShake = true,
            showInterruptGlow = true,
            showCastFinishFX = true,
            borderStyle = "pixel",
            borderColor = { 0, 0, 0, 1 },
            borderSize = 1,
            borderRenderMode = "custom",
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

ST._defaults = defaults

function ST.IsRotationAssistantDisplayMode(displayMode)
    return displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT
end

function ST.IsIconLikeDisplayMode(displayMode)
    return displayMode == nil
        or displayMode == "icons"
        or displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT
end

function CooldownCompanion:IsRotationAssistantGroup(group)
    return group and ST.IsRotationAssistantDisplayMode(group.displayMode) or false
end

function CooldownCompanion:IsRotationAssistantButtonData(buttonData)
    return buttonData and buttonData._rotationAssistantVirtual == true or false
end

function CooldownCompanion:IsIconLikeDisplayMode(displayMode)
    return ST.IsIconLikeDisplayMode(displayMode)
end

function CooldownCompanion:GetPanelManualEntryRejectMessage(group, entryData)
    if self:IsRotationAssistantGroup(group) then
        return "Assistant Panels are populated automatically."
    end
    if group and group.displayMode == "textures" and group.buttons and #group.buttons >= 1 then
        return "Texture Panels can only hold one entry. Remove the current entry first if you want to replace it."
    end
    -- Primary aura entries (addedAs == "aura") only display through the aura
    -- system, which binds to icon, bar, and Texture panels; refuse moving them
    -- anywhere else. Ordinary spell entries that
    -- merely have aura tracking enabled keep a valid cooldown display and
    -- stay movable. entryData is a single
    -- buttonData table or an array of them (move paths pass it; add paths
    -- gate aura adds before reaching here).
    if entryData and group then
        local displayMode = group.displayMode or "icons"
        if displayMode ~= "icons" and displayMode ~= "bars" and displayMode ~= "textures" then
            local entries = entryData[1] and entryData or { entryData }
            for _, bd in ipairs(entries) do
                if bd and bd.addedAs == "aura" then
                    return "Use an icon or bar panel for Aura tracking."
                end
            end
        end
    end
    return nil
end

function CooldownCompanion:CanPanelAcceptManualEntry(group)
    return self:GetPanelManualEntryRejectMessage(group) == nil
end

function CooldownCompanion:GetRotationAssistantActionSpellID()
    local assistedCombat = C_AssistedCombat
    if assistedCombat and assistedCombat.GetActionSpell then
        local spellID = assistedCombat.GetActionSpell()
        if type(spellID) == "number" and not issecretvalue(spellID) and spellID > 0 then
            return spellID
        end
    end
    return ST.ROTATION_ASSISTANT_ACTION_SPELL_ID
end

function CooldownCompanion:GetRotationAssistantFallbackIcon(spellID)
    spellID = spellID or self:GetRotationAssistantActionSpellID()
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local icon = C_Spell.GetSpellTexture(spellID)
        if icon and not issecretvalue(icon) then
            return icon
        end
    end
    return ST.ROTATION_ASSISTANT_FALLBACK_ICON
end

function CooldownCompanion:GetRotationAssistantEntrySettings(group, create)
    if not group then return nil end
    local entry = group.rotationAssistantEntry
    if type(entry) ~= "table" then
        if create == false then
            return nil
        end
        entry = {}
        group.rotationAssistantEntry = entry
    end
    return entry
end

function CooldownCompanion:GetRotationAssistantConfigButtonData(group)
    local entry = self:GetRotationAssistantEntrySettings(group, true)
    if not entry then return nil end
    entry.type = "spell"
    entry.id = self:GetRotationAssistantActionSpellID()
    entry.name = ST.ROTATION_ASSISTANT_NAME
    entry.manualIcon = self:GetRotationAssistantFallbackIcon()
    entry._rotationAssistantVirtual = true
    entry._rotationAssistantMissing = true
    return entry
end

function CooldownCompanion:GetRotationAssistantRecommendationSpellID()
    local assistedCombat = C_AssistedCombat
    if not (assistedCombat and assistedCombat.GetNextCastSpell) then
        self._rotationAssistantAvailable = false
        self._rotationAssistantUnavailableReason = "apiUnavailable"
        return nil
    end

    if assistedCombat.IsAvailable then
        local available, reason = assistedCombat.IsAvailable()
        self._rotationAssistantAvailable = available == true
        self._rotationAssistantUnavailableReason = reason
        if available ~= true then
            return nil
        end
    else
        self._rotationAssistantAvailable = true
        self._rotationAssistantUnavailableReason = nil
    end

    local spellID = assistedCombat.GetNextCastSpell(false)
    if type(spellID) == "number" and not issecretvalue(spellID) and spellID > 0 then
        return spellID
    end
    return nil
end

function CooldownCompanion:GetRotationAssistantButtonData(frame)
    if not frame then return nil end
    local groups = self.db and self.db.profile and self.db.profile.groups
    local groupId = frame.groupId or frame._groupId
    local group = groupId and groups and groups[groupId]
    local entrySettings = self:GetRotationAssistantEntrySettings(group, false)
    local buttonData = frame._rotationAssistantButtonData
    if not buttonData then
        buttonData = {
            type = "spell",
            id = self:GetRotationAssistantActionSpellID(),
            name = ST.ROTATION_ASSISTANT_NAME,
            _rotationAssistantVirtual = true,
            _rotationAssistantMissing = true,
        }
        frame._rotationAssistantButtonData = buttonData
    end
    buttonData.loadConditions = entrySettings and entrySettings.loadConditions or nil
    return buttonData
end

function CooldownCompanion:ClearRotationAssistantButtonRuntime(button)
    if not button then return end
    button._displaySpellId = nil
    button._liveOverrideSpellId = nil
    button._lastSpellTexture = nil
    button._lastTextureCheckAt = nil
    button._baseNoCooldown = nil
    button._baseNoCooldownSpellId = nil
    button._noCooldown = nil
    button._noCooldownSpellId = nil
    button._resourceGateCost = nil
    button._resourceGateCostSpellId = nil
    button._baseResourceGateCost = nil
    button._baseResourceGateCostSpellId = nil
    button._spellOutOfRange = nil
    button._auraActive = false
    button._procOverlayActive = false
end

function CooldownCompanion:RefreshRotationAssistantButton(button)
    local buttonData = button and button.buttonData
    if not self:IsRotationAssistantButtonData(buttonData) then
        return false
    end

    local recommendedSpellID = self:GetRotationAssistantRecommendationSpellID()
    local missing = recommendedSpellID == nil
    local displaySpellID = recommendedSpellID or self:GetRotationAssistantActionSpellID()
    local changed = buttonData.id ~= displaySpellID
        or buttonData._rotationAssistantSpellID ~= recommendedSpellID
        or buttonData._rotationAssistantMissing ~= missing

    buttonData.id = displaySpellID
    buttonData._rotationAssistantSpellID = recommendedSpellID
    buttonData._rotationAssistantMissing = missing
    buttonData.name = recommendedSpellID and C_Spell.GetSpellName(recommendedSpellID) or ST.ROTATION_ASSISTANT_NAME
    if self.UpdateSpellChargeMetadata then
        self:UpdateSpellChargeMetadata(buttonData, displaySpellID, {
            clearInactiveMaxCharges = true,
        })
    end
    button._rotationAssistantSpellID = recommendedSpellID

    if changed then
        self:ClearRotationAssistantButtonRuntime(button)
        if self.UpdateButtonIcon then
            self:UpdateButtonIcon(button)
        end
        if self.RefreshResolvedItemKeybindState then
            self:RefreshResolvedItemKeybindState(button, buttonData)
        end
        if self.UpdateRangeCheckRegistrations then
            self:UpdateRangeCheckRegistrations()
        end
    end

    return changed
end

------------------------------------------------------------------------
-- OVERRIDE SECTIONS REGISTRY
-- Maps section IDs to their labels, style keys, and applicable display modes.
-- Used by promote/revert logic and UI builders.
------------------------------------------------------------------------
ST.OVERRIDE_SECTIONS = {
    -- Icon Mode — Appearance Tab
    borderSettings = {
        label = "Border",
        keys = {"borderSize", "borderRenderMode", "borderColor"},
        modes = {icons = true, bars = true, rotationAssistant = true},
    },
    cooldownText = {
        label = "Cooldown Text",
        keys = {"showCooldownText", "cooldownFont", "cooldownFontSize", "cooldownFontOutline", "cooldownFontColor", "cooldownTextAnchor", "cooldownTextXOffset", "cooldownTextYOffset"},
        modes = {icons = true, bars = true},
    },
    -- The four pandemicMarker* keys used to ride this list, because the marker
    -- is drawn into this text. They moved to the pandemic sections below when
    -- the config grew a Pandemic section, so one override covers the whole
    -- refresh-window feature. MigratePandemicOverrideOwnership re-homes the
    -- overrides that were promoted under the old list; the two edits ship as
    -- one unit, or RevertSection stops clearing keys it no longer owns.
    auraText = {
        label = "Aura Duration Text",
        keys = {"showAuraText", "auraTextFont", "auraTextFontSize", "auraTextFontOutline", "auraTextFontColor", "separateTextPositions", "auraTextAnchor", "auraTextXOffset", "auraTextYOffset"},
        modes = {icons = true, bars = true},
    },
    auraStackText = {
        label = "Aura Stack Text",
        keys = {"showAuraStackText", "auraStackFont", "auraStackFontSize", "auraStackFontOutline", "auraStackFontColor", "auraStackAnchor", "auraStackXOffset", "auraStackYOffset"},
        modes = {icons = true, bars = true},
    },
    keybindText = {
        label = "Keybind Text",
        keys = {"showKeybindText", "keybindFont", "keybindFontSize", "keybindFontOutline", "keybindFontColor", "keybindAnchor", "keybindXOffset", "keybindYOffset"},
        modes = {icons = true, rotationAssistant = true},
    },
    chargeText = {
        label = "Charge Text",
        keys = {"showChargeText", "chargeFont", "chargeFontSize", "chargeFontOutline", "chargeFontColor", "chargeFontColorMissing", "chargeFontColorZero", "chargeAnchor", "chargeXOffset", "chargeYOffset"},
        modes = {icons = true, bars = true},
    },
    -- Icon Mode — Extras Tab
    desaturation = {
        label = "Desaturation",
        keys = {"desaturateOnCooldown"},
        modes = {icons = true, bars = true, rotationAssistant = true},
    },
    cooldownSwipe = {
        label = "Cooldown Swipe",
        keys = {"showCooldownSwipe", "showCooldownSwipeFill", "cooldownSwipeReverse", "cooldownSwipeEdgeEnabled", "cooldownSwipeAlpha", "cooldownSwipeEdgeColor"},
        modes = {icons = true, rotationAssistant = true},
    },
    showGCDSwipe = {
        label = "Show GCD Swipe",
        keys = {"showGCDSwipe"},
        modes = {icons = true, bars = true, rotationAssistant = true},
    },
    showOutOfRange = {
        label = "Show Out of Range",
        keys = {"showOutOfRange"},
        modes = {icons = true, rotationAssistant = true},
    },
    showTooltips = {
        label = "Show Tooltips",
        keys = {"showTooltips"},
        modes = {icons = true, bars = true, rotationAssistant = true},
    },
    lossOfControl = {
        label = "Loss of Control",
        keys = {"showLossOfControl"},
        modes = {icons = true, bars = true, rotationAssistant = true},
    },
    unusableDimming = {
        label = "Unusable Visual",
        keys = {"showUnusable", "unusableVisualMode", "iconUnusableTintColor"},
        modes = {icons = true, bars = true, rotationAssistant = true},
    },
    iconTint = {
        label = "Icon Tint",
        keys = {"iconTintColor", "iconCooldownTintEnabled", "iconCooldownTintColor", "iconAuraTintEnabled", "iconAuraTintColor", "backgroundColor"},
        modes = {icons = true, bars = true},
    },
    iconZoom = {
        label = "Icon Zoom",
        keys = {"iconZoom"},
        modes = {icons = true, bars = true, rotationAssistant = true},
        defaults = {iconZoom = 0},
    },
    iconFillTimer = {
        label = "Icon Fill Timer",
        keys = {"iconFillEnabled", "iconFillOrientation", "iconFillReverse", "iconFillTimerBehavior", "iconFillCooldownColor"},
        modes = {icons = true},
    },
    assistedHighlight = {
        label = "Assisted Highlight",
        keys = {"showAssistedHighlight", "assistedHighlightHostileTargetOnly", "assistedHighlightStyle", "assistedHighlightColor", "assistedHighlightBorderSize", "assistedHighlightBlizzardOverhang", "assistedHighlightProcOverhang", "assistedHighlightProcColor", "assistedHighlightCombatOnly"},
        modes = {icons = true},
    },
    procGlow = {
        label = "Proc Glow",
        keys = {"procGlowStyle", "procGlowColor", "procGlowSize", "procGlowThickness", "procGlowSpeed", "procGlowLines", "procGlowCombatOnly"},
        modes = {icons = true},
    },
    -- PTR 8 lit the pandemic key family up (the kit rig in AuraDisplay.lua);
    -- the enable is now explicit-true pandemicEffectEnabled. Offered as a
    -- per-entry override section (owner ruling) alongside the plain
    -- pandemicEffect checkbox; live-era promotions carry forward with
    -- their values sanitized by the aura-glow migration. The retired
    -- live-era keys left these lists with the Phase 3 retirement: the
    -- migration's every-import strip owns their cleanup now.
    -- ONE section for the whole refresh-window feature across both display
    -- modes: the glow (icons) or the fill recolor (bars), plus the marker that
    -- decorates the duration text in either. It replaces the old pandemicGlow
    -- and pandemicBar pair, which MigratePandemicOverrideOwnership renames.
    --
    -- One section, not two, because the two would share keys. Sections are the
    -- unit Customize copies and Revert deletes, and nothing clears an override
    -- when a panel changes display mode, so an icons entry converted to bars
    -- would carry a stored pandemicGlow it could revert while pandemicBar still
    -- offered Customize. Either action would then write or wipe keys the other
    -- section still listed. The marker keys made that overlap span
    -- user-authored text and colour, which is not recoverable; merging removes
    -- the collision instead of policing it.
    pandemic = {
        label = "Pandemic",
        keys = {"pandemicEffectEnabled",
            "pandemicGlowStyle", "pandemicGlowColor", "pandemicGlowColor2", "pandemicGlowSize", "pandemicGlowThickness", "pandemicGlowSpeed", "pandemicGlowLines",
            "barPandemicColor",
            "pandemicMarkerEnabled", "pandemicMarkerText", "pandemicMarkerColorMode", "pandemicMarkerColor"},
        modes = {icons = true, bars = true},
    },
    auraIndicator = {
        label = "Show Aura Glow",
        keys = {"auraGlowStyle", "auraGlowColor", "auraGlowColor2", "auraGlowSize", "auraGlowSpeed", "auraGlowDashCount", "auraGlowDashThickness"},
        modes = {icons = true},
    },
    auraDurationSwipe = {
        label = "Aura Duration Swipe",
        keys = {"showAuraDurationSwipe", "showAuraDurationSwipeFill", "auraDurationSwipeReverse", "auraDurationSwipeEdgeEnabled", "auraDurationSwipeAlpha", "auraDurationSwipeEdgeColor", "auraUseBlizzardSwipe"},
        modes = {icons = true},
    },
    readyGlow = {
        label = "Ready Glow",
        keys = {"readyGlowStyle", "readyGlowColor", "readyGlowSize", "readyGlowThickness", "readyGlowSpeed", "readyGlowLines", "readyGlowCombatOnly", "readyGlowOnlyAtMaxCharges", "readyGlowDuration"},
        modes = {icons = true},
    },
    keyPressHighlight = {
        label = "Key Press Highlight",
        keys = {"keyPressHighlightStyle", "keyPressHighlightColor", "keyPressHighlightSize", "keyPressHighlightCombatOnly"},
        modes = {icons = true},
    },
    -- Bar Mode — Appearance Tab
    -- The bar pandemic display (the fill recolor: pandemicEffectEnabled +
    -- barPandemicColor) is NOT here: it shares the mode-spanning "pandemic"
    -- section above with the icons glow and the marker. The dormant
    -- pandemicBarEffect/Pulse/ColorShift families retired in Phase 3 (the
    -- migration's every-import strip owns their cleanup). barActiveAura is
    -- live (LCG-removal project wired it through the aura kit).
    barActiveAura = {
        label = "Active Aura Indicator",
        keys = {"barAuraIndicatorEnabled", "barAuraColor", "barAuraEffect", "barAuraEffectColor", "barAuraEffectSize", "barAuraEffectThickness", "barAuraEffectSpeed", "barAuraEffectLines", "barAuraPulseEnabled", "barAuraPulseSpeed", "barAuraColorShiftEnabled", "barAuraColorShiftSpeed", "barAuraColorShiftColor"},
        modes = {bars = true},
    },
    barIcon = {
        label = "Bar Icon",
        keys = {"showBarIcon", "barIconReverse", "barIconOffset", "barIconSizeOverride", "barIconSize"},
        defaults = {
            showBarIcon = true,
            barIconReverse = false,
            barIconOffset = 0,
            barIconSizeOverride = false,
            barIconSize = 20,
        },
        modes = {bars = true},
    },
    barColor = {
        label = "Bar Color",
        keys = {"barColor"},
        modes = {bars = true},
    },
    barCooldownColor = {
        label = "Bar Cooldown Color",
        keys = {"barCooldownColor"},
        modes = {bars = true},
    },
    barChargeColor = {
        label = "Bar Recharging Color",
        keys = {"barChargeColor"},
        modes = {bars = true},
    },
    barBgColor = {
        label = "Bar Background Color",
        keys = {"barBgColor"},
        modes = {bars = true},
    },
    barNameText = {
        label = "Name Text",
        keys = {"showBarNameText", "barNameTextReverse", "barNameFont", "barNameFontSize", "barNameFontOutline", "barNameFontColor"},
        modes = {bars = true},
    },
    barReadyText = {
        label = "Ready Text",
        keys = {"showBarReadyText", "barReadyText", "barReadyTextColor", "barReadyFontSize", "barReadyFont", "barReadyFontOutline"},
        modes = {bars = true},
    },
    -- Text Mode
    -- (No textFormat section: the per-entry format override is the flat
    -- buttonData.textFormat field, edited on the panel's Format tab as a lens
    -- onto the selected entry, and never went through the styleOverrides
    -- section machinery.)
    textFont = {
        label = "Text Font",
        keys = {"textFont", "textFontSize", "textFontOutline", "textAlignment", "textShadow"},
        modes = {text = true},
    },
    textColors = {
        label = "Text Colors",
        keys = {"textFontColor", "textCooldownColor", "textReadyColor", "textAuraColor", "textCustomColor", "textReadyText"},
        modes = {text = true},
    },
    textBackground = {
        label = "Text Background",
        keys = {"textBgColor", "textBorderSize", "textBorderRenderMode", "textBorderColor"},
        modes = {text = true},
    },
}

-- Display order for the registry above, wherever an entry's overrides are
-- listed (the entry-slot hover tooltip and the config's Customizations list
-- both walk this).
ST.OVERRIDE_SECTION_ORDER = {
    "borderSettings", "cooldownText", "auraText", "auraStackText",
    "iconFillTimer", "cooldownSwipe", "auraDurationSwipe", "showGCDSwipe", "keybindText", "chargeText", "desaturation", "showOutOfRange", "showTooltips",
    -- "pandemic" spans both display modes (like auraText above), so it sits in
    -- the icons run rather than being listed twice.
    "lossOfControl", "unusableDimming", "iconTint", "iconZoom", "assistedHighlight", "procGlow", "auraIndicator", "pandemic", "readyGlow", "keyPressHighlight",
    "barIcon", "barActiveAura", "barColor", "barCooldownColor", "barChargeColor", "barBgColor", "barNameText", "barReadyText",
    "textFont", "textColors", "textBackground",
}

-- Completeness backstop: a section added to ST.OVERRIDE_SECTIONS but
-- forgotten above would still customize, revert and render - and silently
-- vanish from every listing that walks the order. Append any such section
-- (alphabetically, at the end) so the curated order stays hand-authored but
-- can never disagree with the registry about MEMBERSHIP.
do
    local listed = {}
    for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER) do
        listed[sectionId] = true
    end
    local missing = {}
    for sectionId in pairs(ST.OVERRIDE_SECTIONS) do
        if not listed[sectionId] then
            missing[#missing + 1] = sectionId
        end
    end
    table.sort(missing)
    for _, sectionId in ipairs(missing) do
        ST.OVERRIDE_SECTION_ORDER[#ST.OVERRIDE_SECTION_ORDER + 1] = sectionId
    end
end

ST.EQUIPMENT_SLOT_DENIED_OVERRIDE_SECTIONS = {
    auraText = true,
    auraStackText = true,
    auraDurationSwipe = true,
    assistedHighlight = true,
    procGlow = true,
    auraIndicator = true,
    pandemic = true,
    barActiveAura = true,
}

ST.NO_COOLDOWN_DENIED_OVERRIDE_SECTIONS = {
    desaturation = true,
    readyGlow = true,
}

-- Standalone aura entries (addedAs == "aura") have no cast, cooldown, or
-- charges, so the sections styling those mechanics can never apply. Add
-- intent is immutable, which makes it safe for GetEffectiveStyle's prune pass
-- to drop stored overrides for these sections. Gates that CAN toggle (aura
-- tracking on ordinary entries) must stay config-side only, or the prune pass
-- would delete saved overrides the moment the toggle turns off. NOT denied:
-- keybindText (custom keybind text renders on aura entries) and cooldownText
-- (its position keys place the aura duration text in shared-position mode).
ST.AURA_ENTRY_DENIED_OVERRIDE_SECTIONS = {
    cooldownSwipe = true,
    showGCDSwipe = true,
    desaturation = true,
    showOutOfRange = true,
    iconFillTimer = true,
    chargeText = true,
    lossOfControl = true,
    unusableDimming = true,
    assistedHighlight = true,
    procGlow = true,
    readyGlow = true,
    keyPressHighlight = true,
}

function ST.CanButtonUseOverrideSection(buttonData, sectionId)
    if buttonData and buttonData.type == "equipmentSlot" then
        if ST.EQUIPMENT_SLOT_DENIED_OVERRIDE_SECTIONS[sectionId] then
            return false, "entryType"
        end
        return true
    end
    if buttonData and buttonData.addedAs == "aura"
        and ST.AURA_ENTRY_DENIED_OVERRIDE_SECTIONS[sectionId] then
        return false, "entryType"
    end
    return true
end
