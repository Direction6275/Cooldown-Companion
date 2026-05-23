--[[
    CooldownCompanion - Core/MigrationsButtonSettings.lua: button, style, text, glow, and visual setting migrations.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local Masque = CooldownCompanion.Masque

local pairs = pairs
local ipairs = ipairs
local type = type
local next = next
local rawget = rawget

function CooldownCompanion:MigrateVisibility()
    local function NormalizeCompactGrowthDirection(growthDirection)
        if growthDirection == "start" or growthDirection == "left" or growthDirection == "top" then
            return "start"
        end
        if growthDirection == "end" or growthDirection == "right" or growthDirection == "bottom" then
            return "end"
        end
        return "center"
    end

    for groupId, group in pairs(self.db.profile.groups) do
        if group.compactLayout == nil then
            group.compactLayout = false
        end
        if group.maxVisibleButtons == nil then
            group.maxVisibleButtons = 0
        end
        group.compactGrowthDirection = NormalizeCompactGrowthDirection(group.compactGrowthDirection)
    end
end

function CooldownCompanion:MigrateAddedAsClassification()
    local profile = self.db.profile
    if profile.addedAsClassificationV2Migrated then return end

    for _, group in pairs(self.db.profile.groups) do
        if group.buttons then
            for _, buttonData in ipairs(group.buttons) do
                if buttonData.type == "spell" then
                    local addedAs = buttonData.addedAs
                    if addedAs ~= "spell" and addedAs ~= "aura" then
                        addedAs = self:ShouldRecoverLegacyStandaloneAuraEntry(
                            buttonData,
                            group.buttons,
                            { trustExplicitAuraLabel = false }
                        ) and "aura" or "spell"
                    end

                    buttonData.addedAs = addedAs
                end
            end
        end
    end

    profile.addedAsClassificationMigrated = true
    profile.addedAsClassificationV2Migrated = true
end

function CooldownCompanion:MigrateStandaloneAuraMetadata()
    local profile = self.db.profile
    if profile.standaloneAuraMetadataV2Migrated then return end

    for _, group in pairs(profile.groups or {}) do
        if group.buttons then
            for _, buttonData in ipairs(group.buttons) do
                self:NormalizeStandaloneAuraButtonData(buttonData, group.buttons, {
                    -- Be conservative on legacy/imported data: an old saved
                    -- addedAs="aura" label is not enough proof by itself that
                    -- the entry was intentionally created as aura-only.
                    trustExplicitAuraLabel = false,
                })
            end
        end
    end

    profile.standaloneAuraLinkMetadataMigrated = true
    profile.standaloneAuraMetadataV2Migrated = true
end

function CooldownCompanion:MigrateInvertAuraDesaturationLogic()
    local profile = self.db.profile
    if profile.invertAuraDesaturationLogicMigrated then return end

    for _, group in pairs(profile.groups or {}) do
        if group.buttons then
            for _, buttonData in ipairs(group.buttons) do
                if buttonData.saturateWhileAuraNotActive ~= nil then
                    if buttonData.isPassive and buttonData.saturateWhileAuraNotActive then
                        buttonData.neverDesaturate = true
                    end
                    buttonData.saturateWhileAuraNotActive = nil
                end
            end
        end
    end

    profile.invertAuraDesaturationLogicMigrated = true
end

-- LSM path-to-name migration tables
local FONT_PATH_TO_LSM = {
    ["Fonts\\FRIZQT__.TTF"]  = "Friz Quadrata TT",
    ["Fonts\\ARIALN.TTF"]    = "Arial Narrow",
    ["Fonts\\MORPHEUS.TTF"]  = "Morpheus",
    ["Fonts\\SKURRI.TTF"]    = "Skurri",
    ["Fonts\\2002.TTF"]      = "2002",
    ["Fonts\\NIMROD.TTF"]    = "Nimrod MT",
}
local TEXTURE_PATH_TO_LSM = {
    ["Interface\\BUTTONS\\WHITE8X8"]                           = "Solid",
    ["Interface\\TargetingFrame\\UI-StatusBar"]                = "Blizzard",
    ["Interface\\RaidFrame\\Raid-Bar-Hp-Fill"]                 = "Blizzard Raid Bar",
    ["Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"] = "Blizzard Character Skills Bar",
}

function CooldownCompanion:MigrateLSMNames()
    local profile = self.db.profile
    if profile.lsmMigrated then return end

    -- Migrate group styles
    for _, group in pairs(profile.groups) do
        local s = group.style
        if s then
            for _, key in ipairs({"cooldownFont", "keybindFont", "auraTextFont", "barNameFont", "barReadyFont", "chargeFont"}) do
                if s[key] and FONT_PATH_TO_LSM[s[key]] then
                    s[key] = FONT_PATH_TO_LSM[s[key]]
                end
            end
            if s.barTexture and TEXTURE_PATH_TO_LSM[s.barTexture] then
                s.barTexture = TEXTURE_PATH_TO_LSM[s.barTexture]
            end
        end
        -- Per-button fonts (charge font on legacy buttonData, or in styleOverrides)
        if group.buttons then
            for _, bd in ipairs(group.buttons) do
                if bd.chargeFont and FONT_PATH_TO_LSM[bd.chargeFont] then
                    bd.chargeFont = FONT_PATH_TO_LSM[bd.chargeFont]
                end
                if bd.itemCountFont and FONT_PATH_TO_LSM[bd.itemCountFont] then
                    bd.itemCountFont = FONT_PATH_TO_LSM[bd.itemCountFont]
                end
                -- styleOverrides fonts
                if bd.styleOverrides then
                    for _, key in ipairs({"chargeFont", "cooldownFont", "keybindFont", "auraTextFont", "barNameFont", "barReadyFont"}) do
                        if bd.styleOverrides[key] and FONT_PATH_TO_LSM[bd.styleOverrides[key]] then
                            bd.styleOverrides[key] = FONT_PATH_TO_LSM[bd.styleOverrides[key]]
                        end
                    end
                end
            end
        end
    end

    -- Migrate globalStyle
    local gs = profile.globalStyle
    if gs then
        for _, key in ipairs({"cooldownFont", "keybindFont", "auraTextFont", "barNameFont", "barReadyFont", "chargeFont"}) do
            if gs[key] and FONT_PATH_TO_LSM[gs[key]] then
                gs[key] = FONT_PATH_TO_LSM[gs[key]]
            end
        end
        if gs.barTexture and TEXTURE_PATH_TO_LSM[gs.barTexture] then
            gs.barTexture = TEXTURE_PATH_TO_LSM[gs.barTexture]
        end
    end

    -- Migrate resourceBars
    local rb = profile.resourceBars
    if rb then
        if rb.barTexture and TEXTURE_PATH_TO_LSM[rb.barTexture] then
            rb.barTexture = TEXTURE_PATH_TO_LSM[rb.barTexture]
        end
        if rb.textFont and FONT_PATH_TO_LSM[rb.textFont] then
            rb.textFont = FONT_PATH_TO_LSM[rb.textFont]
        end
    end

    -- Migrate castBar
    local cb = profile.castBar
    if cb then
        if cb.barTexture and TEXTURE_PATH_TO_LSM[cb.barTexture] then
            cb.barTexture = TEXTURE_PATH_TO_LSM[cb.barTexture]
        end
        if cb.nameFont and FONT_PATH_TO_LSM[cb.nameFont] then
            cb.nameFont = FONT_PATH_TO_LSM[cb.nameFont]
        end
        if cb.castTimeFont and FONT_PATH_TO_LSM[cb.castTimeFont] then
            cb.castTimeFont = FONT_PATH_TO_LSM[cb.castTimeFont]
        end
    end

    profile.lsmMigrated = true
end

-- Charge text keys that migrate from buttonData to group.style
local CHARGE_TEXT_KEYS = {
    "showChargeText", "chargeFont", "chargeFontSize", "chargeFontOutline",
    "chargeFontColor", "chargeFontColorMissing", "chargeFontColorZero",
    "chargeAnchor", "chargeXOffset", "chargeYOffset",
}

local CHARGE_TEXT_DEFAULTS = {
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
}

function CooldownCompanion:MigrateChargeTextToGroupStyle()
    local profile = self.db.profile
    if profile.chargeTextMigrated then return end

    for _, group in pairs(profile.groups) do
        local style = group.style
        if style and style.chargeFont == nil then
            -- Find the first button with charge text settings to adopt as group defaults
            local adopted = false
            if group.buttons then
                for _, bd in ipairs(group.buttons) do
                    if bd.chargeFont or bd.chargeFontSize or bd.chargeFontOutline then
                        -- Adopt this button's values as the group defaults
                        for _, key in ipairs(CHARGE_TEXT_KEYS) do
                            if bd[key] ~= nil then
                                if type(bd[key]) == "table" then
                                    style[key] = CopyTable(bd[key])
                                else
                                    style[key] = bd[key]
                                end
                            else
                                style[key] = CHARGE_TEXT_DEFAULTS[key]
                                if type(style[key]) == "table" then
                                    style[key] = CopyTable(style[key])
                                end
                            end
                        end
                        adopted = true
                        break
                    end
                end
            end

            -- No button had custom charge text → apply defaults to group style
            if not adopted then
                for _, key in ipairs(CHARGE_TEXT_KEYS) do
                    local def = CHARGE_TEXT_DEFAULTS[key]
                    if type(def) == "table" then
                        style[key] = CopyTable(def)
                    else
                        style[key] = def
                    end
                end
            end

            -- Now scan all buttons: create overrides for buttons that differ from group defaults
            if group.buttons then
                for _, bd in ipairs(group.buttons) do
                    local hasDiff = false
                    for _, key in ipairs(CHARGE_TEXT_KEYS) do
                        if bd[key] ~= nil then
                            local bdVal = bd[key]
                            local grpVal = style[key]
                            if type(bdVal) == "table" and type(grpVal) == "table" then
                                for k = 1, #bdVal do
                                    if bdVal[k] ~= grpVal[k] then hasDiff = true; break end
                                end
                            elseif bdVal ~= grpVal then
                                hasDiff = true
                            end
                            if hasDiff then break end
                        end
                    end

                    if hasDiff then
                        if not bd.styleOverrides then bd.styleOverrides = {} end
                        if not bd.overrideSections then bd.overrideSections = {} end
                        for _, key in ipairs(CHARGE_TEXT_KEYS) do
                            if bd[key] ~= nil then
                                if type(bd[key]) == "table" then
                                    bd.styleOverrides[key] = CopyTable(bd[key])
                                else
                                    bd.styleOverrides[key] = bd[key]
                                end
                            else
                                -- Use group default for keys this button didn't customize
                                local def = style[key]
                                if type(def) == "table" then
                                    bd.styleOverrides[key] = CopyTable(def)
                                else
                                    bd.styleOverrides[key] = def
                                end
                            end
                        end
                        bd.overrideSections.chargeText = true
                    end

                    -- Remove old per-button charge text fields
                    for _, key in ipairs(CHARGE_TEXT_KEYS) do
                        bd[key] = nil
                    end
                end
            end
        end
    end

    -- Also ensure globalStyle has charge text defaults
    local gs = profile.globalStyle
    if gs and gs.chargeFont == nil then
        for _, key in ipairs(CHARGE_TEXT_KEYS) do
            local def = CHARGE_TEXT_DEFAULTS[key]
            if type(def) == "table" then
                gs[key] = CopyTable(def)
            else
                gs[key] = def
            end
        end
    end

    profile.chargeTextMigrated = true
end

function CooldownCompanion:MigrateProcGlowToStyleOverrides()
    local profile = self.db.profile
    if profile.procGlowOverrideMigrated then return end

    for _, group in pairs(profile.groups) do
        if group.buttons then
            for _, bd in ipairs(group.buttons) do
                if bd.procGlowColor then
                    if not bd.styleOverrides then bd.styleOverrides = {} end
                    if not bd.overrideSections then bd.overrideSections = {} end
                    bd.styleOverrides.procGlowColor = bd.procGlowColor
                    bd.procGlowColor = nil
                    -- Also copy group default for procGlowOverhang into overrides
                    -- so the section is complete
                    if not bd.styleOverrides.procGlowOverhang and group.style then
                        bd.styleOverrides.procGlowOverhang = group.style.procGlowOverhang or 32
                    end
                    bd.overrideSections.procGlow = true
                end
            end
        end
    end

    profile.procGlowOverrideMigrated = true
end

------------------------------------------------------------------------
-- MIGRATION: Move glow appearance settings from per-button to group style
------------------------------------------------------------------------
local PROC_GLOW_KEYS = {"procGlowStyle", "procGlowSize", "procGlowThickness", "procGlowSpeed"}
local PROC_GLOW_DEFAULTS = {procGlowStyle = "glow", procGlowSize = 32, procGlowThickness = 2, procGlowSpeed = 60}

local PANDEMIC_GLOW_KEYS = {"pandemicGlowStyle", "pandemicGlowColor", "pandemicGlowSize", "pandemicGlowThickness", "pandemicGlowSpeed"}
local PANDEMIC_GLOW_DEFAULTS = {pandemicGlowStyle = "solid", pandemicGlowColor = {1, 0.5, 0, 1}, pandemicGlowSize = 2, pandemicGlowThickness = 2, pandemicGlowSpeed = 60}

local PANDEMIC_BAR_KEYS = {"barPandemicColor", "pandemicBarEffect", "pandemicBarEffectColor", "pandemicBarEffectSize", "pandemicBarEffectThickness", "pandemicBarEffectSpeed"}
local PANDEMIC_BAR_DEFAULTS = {barPandemicColor = {1, 0.5, 0, 1}, pandemicBarEffect = "none", pandemicBarEffectColor = {1, 0.5, 0, 1}, pandemicBarEffectSize = 2, pandemicBarEffectThickness = 2, pandemicBarEffectSpeed = 60}

local AURA_INDICATOR_KEYS = {"auraGlowStyle", "auraGlowColor", "auraGlowSize", "auraGlowThickness", "auraGlowSpeed"}
local AURA_INDICATOR_DEFAULTS = {auraGlowStyle = "pixel", auraGlowColor = {1, 0.84, 0, 0.9}, auraGlowSize = 4, auraGlowThickness = 2, auraGlowSpeed = 60}

local BAR_ACTIVE_AURA_KEYS = {"barAuraColor", "barAuraEffect", "barAuraEffectColor", "barAuraEffectSize", "barAuraEffectThickness", "barAuraEffectSpeed"}
local BAR_ACTIVE_AURA_DEFAULTS = {barAuraColor = {0.2, 1.0, 0.2, 1.0}, barAuraEffect = "none", barAuraEffectColor = {1, 0.84, 0, 0.9}, barAuraEffectSize = 4, barAuraEffectThickness = 2, barAuraEffectSpeed = 60}

-- Compare two values (handles tables and scalars)
local function ValuesMatch(a, b)
    if type(a) == "table" and type(b) == "table" then
        for k = 1, math.max(#a, #b) do
            if a[k] ~= b[k] then return false end
        end
        return true
    end
    return a == b
end

-- Copy a value (deep copy tables)
local function CopyVal(v)
    if type(v) == "table" then return CopyTable(v) end
    return v
end

-- Generic migration helper: moves per-button keys to group style defaults,
-- creating overrides for buttons that differ.
-- keysList: ordered list of style keys
-- defaultsMap: default values for each key
-- sectionId: override section ID
-- resolveButtonValue: function(bd, key) -> value to use for this button (handles renames/fallbacks)
-- cleanupButton: function(bd) to remove old per-button keys
local function MigrateKeysToGroupStyle(group, keysList, defaultsMap, sectionId, resolveButtonValue, cleanupButton)
    local style = group.style

    -- Find first button with any of these keys set → adopt as group defaults
    local adopted = false
    if group.buttons then
        for _, bd in ipairs(group.buttons) do
            local hasAny = false
            for _, key in ipairs(keysList) do
                if resolveButtonValue(bd, key) ~= nil then
                    hasAny = true
                    break
                end
            end
            if hasAny then
                for _, key in ipairs(keysList) do
                    local val = resolveButtonValue(bd, key)
                    if val ~= nil then
                        style[key] = CopyVal(val)
                    else
                        style[key] = CopyVal(defaultsMap[key])
                    end
                end
                adopted = true
                break
            end
        end
    end

    -- No button had custom values → apply defaults to group style
    if not adopted then
        for _, key in ipairs(keysList) do
            if style[key] == nil then
                style[key] = CopyVal(defaultsMap[key])
            end
        end
    end

    -- Scan all buttons: create overrides for buttons that differ from group defaults
    if group.buttons then
        for _, bd in ipairs(group.buttons) do
            local hasDiff = false
            for _, key in ipairs(keysList) do
                local bdVal = resolveButtonValue(bd, key)
                if bdVal ~= nil then
                    if not ValuesMatch(bdVal, style[key]) then
                        hasDiff = true
                        break
                    end
                end
            end

            if hasDiff then
                if not bd.styleOverrides then bd.styleOverrides = {} end
                if not bd.overrideSections then bd.overrideSections = {} end
                for _, key in ipairs(keysList) do
                    local bdVal = resolveButtonValue(bd, key)
                    if bdVal ~= nil then
                        bd.styleOverrides[key] = CopyVal(bdVal)
                    else
                        bd.styleOverrides[key] = CopyVal(style[key])
                    end
                end
                bd.overrideSections[sectionId] = true
            end

            -- Clean up old per-button keys
            cleanupButton(bd)
        end
    end
end

function CooldownCompanion:MigrateGlowSettingsToGroupStyle()
    local profile = self.db.profile
    if profile.glowSettingsMigrated then return end

    for _, group in pairs(profile.groups) do
        local style = group.style
        if style then

        -- 1. Proc Glow (icon mode): migrate procGlowStyle/Size/Thickness/Speed
        -- Sentinel: procGlowStyle == nil means pre-migration
        if style.procGlowStyle == nil then
            -- Handle procGlowOverhang → procGlowSize rename on group style
            if style.procGlowOverhang then
                style.procGlowSize = style.procGlowOverhang
            end

            MigrateKeysToGroupStyle(group, PROC_GLOW_KEYS, PROC_GLOW_DEFAULTS, "procGlow",
                function(bd, key)
                    if key == "procGlowSize" then
                        -- Check for procGlowSize first, then fallback aliases
                        if bd.procGlowSize ~= nil then return bd.procGlowSize end
                        return nil
                    end
                    return bd[key]
                end,
                function(bd)
                    bd.procGlowStyle = nil
                    bd.procGlowSize = nil
                    bd.procGlowThickness = nil
                    bd.procGlowSpeed = nil
                    -- Also handle procGlowOverhang in existing styleOverrides
                    if bd.styleOverrides and bd.styleOverrides.procGlowOverhang then
                        bd.styleOverrides.procGlowSize = bd.styleOverrides.procGlowSize or bd.styleOverrides.procGlowOverhang
                        bd.styleOverrides.procGlowOverhang = nil
                    end
                end
            )
            -- procGlowColor is already on style (handled by prior migration) — add to override section keys
            -- If any button already has procGlow override with procGlowColor, ensure new keys are populated
            if group.buttons then
                for _, bd in ipairs(group.buttons) do
                    if bd.overrideSections and bd.overrideSections.procGlow and bd.styleOverrides then
                        -- Ensure all 5 keys are present in override
                        for _, key in ipairs(PROC_GLOW_KEYS) do
                            if bd.styleOverrides[key] == nil then
                                bd.styleOverrides[key] = CopyVal(style[key])
                            end
                        end
                        if bd.styleOverrides.procGlowColor == nil then
                            bd.styleOverrides.procGlowColor = CopyVal(style.procGlowColor or {1, 1, 1, 1})
                        end
                    end
                end
            end
        end

        -- 2. Pandemic Glow (icon mode)
        if style.pandemicGlowStyle == nil then
            MigrateKeysToGroupStyle(group, PANDEMIC_GLOW_KEYS, PANDEMIC_GLOW_DEFAULTS, "pandemicGlow",
                function(bd, key)
                    -- Resolve legacy fallbacks: auraGlowStyle → pandemicGlowStyle, etc.
                    if key == "pandemicGlowStyle" then
                        return bd.pandemicGlowStyle or bd.auraGlowStyle
                    elseif key == "pandemicGlowSize" then
                        return bd.pandemicGlowSize or bd.auraGlowSize
                    elseif key == "pandemicGlowThickness" then
                        return bd.pandemicGlowThickness or bd.auraGlowThickness
                    elseif key == "pandemicGlowSpeed" then
                        return bd.pandemicGlowSpeed or bd.auraGlowSpeed
                    end
                    return bd[key]
                end,
                function(bd)
                    bd.pandemicGlowStyle = nil
                    bd.pandemicGlowColor = nil
                    bd.pandemicGlowSize = nil
                    bd.pandemicGlowThickness = nil
                    bd.pandemicGlowSpeed = nil
                end
            )
        end

        -- 3. Pandemic Bar
        if style.barPandemicColor == nil then
            MigrateKeysToGroupStyle(group, PANDEMIC_BAR_KEYS, PANDEMIC_BAR_DEFAULTS, "pandemicBar",
                function(bd, key)
                    if key == "pandemicBarEffectColor" then
                        -- Old code used pandemicGlowColor for bar effect color
                        return bd.pandemicGlowColor
                    elseif key == "pandemicBarEffect" then
                        return bd.pandemicBarEffect or bd.barAuraEffect
                    end
                    return bd[key]
                end,
                function(bd)
                    bd.barPandemicColor = nil
                    bd.pandemicBarEffect = nil
                    -- pandemicGlowColor in bar context → now pandemicBarEffectColor
                    -- (pandemicGlowColor already cleaned up by pandemic glow icon migration above)
                    bd.pandemicBarEffectSize = nil
                    bd.pandemicBarEffectThickness = nil
                    bd.pandemicBarEffectSpeed = nil
                end
            )
        end

        end -- if style
    end

    -- Ensure globalStyle has the new keys
    local gs = profile.globalStyle
    if gs then
        for _, key in ipairs(PROC_GLOW_KEYS) do
            if gs[key] == nil then gs[key] = CopyVal(PROC_GLOW_DEFAULTS[key]) end
        end
        for _, key in ipairs(PANDEMIC_GLOW_KEYS) do
            if gs[key] == nil then gs[key] = CopyVal(PANDEMIC_GLOW_DEFAULTS[key]) end
        end
        for _, key in ipairs(PANDEMIC_BAR_KEYS) do
            if gs[key] == nil then gs[key] = CopyVal(PANDEMIC_BAR_DEFAULTS[key]) end
        end
    end

    profile.glowSettingsMigrated = true
end

function CooldownCompanion:MigrateAuraIndicatorToGroupStyle()
    local profile = self.db.profile
    if profile.auraIndicatorMigrated then return end

    for _, group in pairs(profile.groups) do
        local style = group.style
        if style then

        -- 4. Active Aura Indicator (icon mode)
        if style.auraGlowStyle == nil then
            -- Pre-scan: record which buttons had non-"none" aura indicator before migration cleans up keys
            local enabledButtons = {}
            if group.buttons then
                for i, bd in ipairs(group.buttons) do
                    if bd.auraGlowStyle and bd.auraGlowStyle ~= "none" then
                        enabledButtons[i] = true
                    end
                end
            end

            MigrateKeysToGroupStyle(group, AURA_INDICATOR_KEYS, AURA_INDICATOR_DEFAULTS, "auraIndicator",
                function(bd, key)
                    return bd[key]
                end,
                function(bd)
                    bd.auraGlowStyle = nil
                    bd.auraGlowColor = nil
                    bd.auraGlowSize = nil
                    bd.auraGlowThickness = nil
                    bd.auraGlowSpeed = nil
                end
            )

            -- Convert enable state: set auraIndicatorEnabled for buttons that had non-"none" styles
            if group.buttons then
                for i, bd in ipairs(group.buttons) do
                    if enabledButtons[i] then
                        bd.auraIndicatorEnabled = true
                    end
                end
            end
        end

        -- 5. Active Aura Indicator (bar mode)
        if style.barAuraColor == nil then
            -- Pre-scan: record which buttons had bar aura indicator enabled
            local enabledButtons = {}
            if group.buttons then
                for i, bd in ipairs(group.buttons) do
                    if bd.barAuraColor or (bd.barAuraEffect and bd.barAuraEffect ~= "none") then
                        enabledButtons[i] = true
                    end
                end
            end

            MigrateKeysToGroupStyle(group, BAR_ACTIVE_AURA_KEYS, BAR_ACTIVE_AURA_DEFAULTS, "barActiveAura",
                function(bd, key)
                    return bd[key]
                end,
                function(bd)
                    bd.barAuraColor = nil
                    bd.barAuraEffect = nil
                    bd.barAuraEffectColor = nil
                    bd.barAuraEffectSize = nil
                    bd.barAuraEffectThickness = nil
                    bd.barAuraEffectSpeed = nil
                end
            )

            -- Convert enable state
            if group.buttons then
                for i, bd in ipairs(group.buttons) do
                    if enabledButtons[i] then
                        bd.auraIndicatorEnabled = true
                    end
                end
            end
        end

        end -- if style
    end

    -- Ensure globalStyle has the new keys
    local gs = profile.globalStyle
    if gs then
        for _, key in ipairs(AURA_INDICATOR_KEYS) do
            if gs[key] == nil then gs[key] = CopyVal(AURA_INDICATOR_DEFAULTS[key]) end
        end
        for _, key in ipairs(BAR_ACTIVE_AURA_KEYS) do
            if gs[key] == nil then gs[key] = CopyVal(BAR_ACTIVE_AURA_DEFAULTS[key]) end
        end
    end

    profile.auraIndicatorMigrated = true
end

-- Backfill assistedHighlightHostileTargetOnly for legacy profiles and freeze
-- its value into existing assistedHighlight per-button overrides.
function CooldownCompanion:MigrateAssistedHighlightHostileTargetOnly()
    local profile = self.db.profile
    if profile.assistedHighlightHostileTargetOnlyMigrated then return end

    for _, group in pairs(profile.groups) do
        local style = group.style
        if style and style.assistedHighlightHostileTargetOnly == nil then
            style.assistedHighlightHostileTargetOnly = true
        end

        local groupVal = (style and style.assistedHighlightHostileTargetOnly)
        if groupVal == nil then groupVal = true end

        if group.buttons then
            for _, bd in ipairs(group.buttons) do
                if bd.overrideSections and bd.overrideSections.assistedHighlight then
                    if not bd.styleOverrides then bd.styleOverrides = {} end
                    if bd.styleOverrides.assistedHighlightHostileTargetOnly == nil then
                        bd.styleOverrides.assistedHighlightHostileTargetOnly = groupVal
                    end
                end
            end
        end
    end

    local gs = profile.globalStyle
    if gs and gs.assistedHighlightHostileTargetOnly == nil then
        gs.assistedHighlightHostileTargetOnly = true
    end

    profile.assistedHighlightHostileTargetOnlyMigrated = true
end

-- Migrate old frame-based glow styles to new StatusBar indicator styles.
local OLD_GLOW_STYLE_MAP = {
    solid = "solidBorder",
    pixel = "solidBorder",
    glow = "pulsingBorder",
    lcgButton = "pulsingBorder",
    lcgAutocast = "pulsingBorder",
}
function CooldownCompanion:MigrateMaxStacksGlowStyles()
    local rb = self.db.profile.resourceBars
    if not rb or not rb.customAuraBars then return end
    for _, specBars in pairs(rb.customAuraBars) do
        if type(specBars) == "table" then
            for _, cab in ipairs(specBars) do
                if cab and cab.maxStacksGlowStyle then
                    local mapped = OLD_GLOW_STYLE_MAP[cab.maxStacksGlowStyle]
                    if mapped then
                        cab.maxStacksGlowStyle = mapped
                        -- Clean up removed fields
                        cab.maxStacksGlowThickness = nil
                        cab.maxStacksGlowSpeed = nil
                    end
                end
            end
        end
    end
end

-- Preserve old default values for existing profiles when default schema changes.
-- New defaults: desaturateOnCooldown=true, showOutOfRange=true, showGCDSwipe=false,
-- showLossOfControl=false, showTooltips=false, barAuraEffect="color",
-- resourceBars.enabled=false, castBar.enabled=false, frameAnchoring.inheritAlpha=true.
-- Migrate flat talent condition fields (talentNodeID, talentEntryID, talentSpellID,
-- talentName, talentShow) into the new talentConditions array format.
function CooldownCompanion:MigrateTalentConditions()
    if self.db.profile.talentConditionsMigrated then return end
    local profile = self.db.profile

    for _, group in pairs(profile.groups) do
        if group.buttons then
            for _, bd in pairs(group.buttons) do
                if bd.talentNodeID then
                    bd.talentConditions = {
                        {
                            nodeID  = bd.talentNodeID,
                            entryID = bd.talentEntryID,
                            spellID = bd.talentSpellID,
                            name    = bd.talentName,
                            show    = bd.talentShow or "taken",
                        },
                    }
                    bd.talentNodeID  = nil
                    bd.talentEntryID = nil
                    bd.talentSpellID = nil
                    bd.talentName    = nil
                    bd.talentShow    = nil
                end
            end
        end
    end

    profile.talentConditionsMigrated = true
end

function CooldownCompanion:MigrateChoiceTalentConditions()
    local profile = self.db.profile
    if profile.choiceTalentConditionsMigrated then return end

    for _, group in pairs(profile.groups) do
        if group.buttons then
            for _, bd in pairs(group.buttons) do
                local normalized, changed = self:NormalizeTalentConditions(bd.talentConditions)
                if changed then
                    bd.talentConditions = normalized
                end
            end
        end
    end

    profile.choiceTalentConditionsMigrated = true
end

-- Uses rawget for metatabled tables so we only write when the user never explicitly set
-- the field (rawget returns nil), preventing the new metatable default from silently
-- changing existing behavior.
function CooldownCompanion:MigrateNewDefaults()
    if self.db.profile.newDefaultsMigrated then return end
    local profile = self.db.profile

    -- Module-level (metatabled): use rawget to detect never-set fields
    local rb = rawget(profile, "resourceBars")
    if rb then
        if rawget(rb, "enabled") == nil then rb.enabled = true end
    end
    local cb = rawget(profile, "castBar")
    if cb then
        if rawget(cb, "enabled") == nil then cb.enabled = true end
    end
    local fa = rawget(profile, "frameAnchoring")
    if fa then
        if rawget(fa, "inheritAlpha") == nil then fa.inheritAlpha = false end
    end

    -- GlobalStyle (metatabled): use rawget
    local gs = rawget(profile, "globalStyle")
    if gs then
        if rawget(gs, "desaturateOnCooldown") == nil then gs.desaturateOnCooldown = false end
        if rawget(gs, "showOutOfRange") == nil then gs.showOutOfRange = false end
        if rawget(gs, "barAuraEffect") == nil then gs.barAuraEffect = "none" end
        if rawget(gs, "showGCDSwipe") == nil then gs.showGCDSwipe = true end
        if rawget(gs, "showLossOfControl") == nil then gs.showLossOfControl = true end
        if rawget(gs, "showTooltips") == nil then gs.showTooltips = true end
    end

    -- Per-group style (plain tables from CopyTable): nil check is sufficient
    for _, group in pairs(profile.groups) do
        local s = group.style
        if s then
            if s.desaturateOnCooldown == nil then s.desaturateOnCooldown = false end
            if s.showOutOfRange == nil then s.showOutOfRange = false end
            if s.showGCDSwipe == nil then s.showGCDSwipe = true end
            if s.showLossOfControl == nil then s.showLossOfControl = true end
            if s.showTooltips == nil then s.showTooltips = true end
            if s.barAuraEffect == nil then s.barAuraEffect = "none" end
        end
    end

    profile.newDefaultsMigrated = true
end

function CooldownCompanion:MigrateBorderRenderModeOverrides()
    local profile = self.db.profile
    if profile.borderRenderModeOverridesMigrated then return end

    for _, group in pairs(profile.groups) do
        if group.buttons then
            for _, bd in ipairs(group.buttons) do
                if bd.overrideSections then
                    if bd.overrideSections.borderSettings then
                        if not bd.styleOverrides then bd.styleOverrides = {} end
                        if rawget(bd.styleOverrides, "borderRenderMode") == nil then
                            bd.styleOverrides.borderRenderMode = ST.BORDER_RENDER_MODE_CUSTOM
                        end
                    end
                    if bd.overrideSections.textBackground then
                        if not bd.styleOverrides then bd.styleOverrides = {} end
                        if rawget(bd.styleOverrides, "textBorderRenderMode") == nil then
                            bd.styleOverrides.textBorderRenderMode = ST.BORDER_RENDER_MODE_CUSTOM
                        end
                    end
                end
            end
        end
    end

    profile.borderRenderModeOverridesMigrated = true
end

local DURATION_FORMAT_CLOCK = "clock"
local DURATION_FORMAT_DECIMAL_UNDER_60 = "decimal_under_60"

local function MigrateDurationFormatTable(settings)
    if type(settings) ~= "table" then
        return
    end

    local legacyDecimal = rawget(settings, "decimalTimers")
    if rawget(settings, "durationFormat") == nil and legacyDecimal ~= nil then
        settings.durationFormat = legacyDecimal and DURATION_FORMAT_DECIMAL_UNDER_60 or DURATION_FORMAT_CLOCK
    end
    if legacyDecimal ~= nil then
        settings.decimalTimers = nil
    end
end

local function MigrateDurationFormatForGroup(group)
    if type(group) ~= "table" then
        return
    end

    MigrateDurationFormatTable(group.style)
end

local function MigrateDurationFormatCustomBars(container)
    if type(container) ~= "table" then
        return
    end

    local function migrateCollection(collection)
        if type(collection) ~= "table" then
            return
        end

        for _, entry in pairs(collection) do
            MigrateDurationFormatTable(entry)
            if type(entry) == "table" then
                for _, nestedEntry in pairs(entry) do
                    MigrateDurationFormatTable(nestedEntry)
                end
            end
        end
    end

    migrateCollection(container.customBars)
    migrateCollection(container.customAuraBars)
end

function CooldownCompanion:MigrateDurationFormatSettings()
    local profile = self.db and self.db.profile
    if not profile or profile._migratedDurationFormatSettings then return end

    MigrateDurationFormatTable(rawget(profile, "globalStyle"))

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            MigrateDurationFormatForGroup(group)
        end
    end

    MigrateDurationFormatCustomBars(rawget(profile, "resourceBars"))
    MigrateDurationFormatCustomBars(rawget(profile, "legacyResourceBarsSeed"))

    local store = rawget(profile, "resourceBarsByChar")
    if type(store) == "table" then
        for _, charSettings in pairs(store) do
            MigrateDurationFormatCustomBars(charSettings)
        end
    end

    profile._migratedDurationFormatSettings = true
end

local ICON_FILL_COOLDOWN_COLOR_DEFAULT = {0.6, 0.13, 0.18, 0.55}
local ICON_FILL_AURA_COLOR_DEFAULT = {0.2, 1.0, 0.2, 0.55}

local function EnsureIconFillTimerDefaults(style)
    if type(style) ~= "table" then return end
    if rawget(style, "iconFillEnabled") == nil then style.iconFillEnabled = false end
    if rawget(style, "iconFillCooldownColor") == nil then style.iconFillCooldownColor = CopyTable(ICON_FILL_COOLDOWN_COLOR_DEFAULT) end
    if rawget(style, "iconFillAuraColor") == nil then style.iconFillAuraColor = CopyTable(ICON_FILL_AURA_COLOR_DEFAULT) end
end

function CooldownCompanion:MigrateIconFillTimerDefaults()
    local profile = self.db and self.db.profile
    if not profile or profile._migratedIconFillTimerDefaults then return end

    EnsureIconFillTimerDefaults(rawget(profile, "globalStyle"))

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            EnsureIconFillTimerDefaults(group and group.style)
        end
    end

    profile._migratedIconFillTimerDefaults = true
end


function CooldownCompanion:MigrateStrataOrderExpansion()
    local profile = self.db.profile
    if profile._migratedStrataOrder6 then return end

    local function ExpandStrataOrder(order)
        if not order or type(order) ~= "table" or #order ~= 4 then return end
        -- Find where "cooldown" sits in the old array
        local cooldownPos
        for i = 1, 4 do
            if order[i] == "cooldown" then
                cooldownPos = i
                break
            end
        end
        -- Insert auraGlow and readyGlow right after cooldown (or at the start if not found)
        local insertAt = (cooldownPos or 0) + 1
        table.insert(order, insertAt, "auraGlow")
        table.insert(order, insertAt + 1, "readyGlow")
    end

    -- Migrate per-group style.strataOrder
    for _, group in pairs(profile.groups) do
        if group.style then
            ExpandStrataOrder(group.style.strataOrder)
        end
    end

    -- Migrate globalStyle.strataOrder
    if profile.globalStyle then
        ExpandStrataOrder(profile.globalStyle.strataOrder)
    end

    -- Migrate saved icon presets
    local presets = profile.groupSettingPresets and profile.groupSettingPresets.icons
    if presets then
        for _, preset in pairs(presets) do
            if preset.style then
                ExpandStrataOrder(preset.style.strataOrder)
            end
        end
    end

    profile._migratedStrataOrder6 = true
end

function CooldownCompanion:MigrateBaseSpellResolution()
    local profile = self.db.profile
    if profile._migratedBaseSpells then return end

    local migrated, skipped = 0, 0
    for _, group in pairs(profile.groups or {}) do
        if group.buttons then
            for _, bd in ipairs(group.buttons) do
                if bd.type == "spell" and bd.id and not bd.isPetSpell and not bd.cdmChildSlot then
                    local baseID = C_Spell.GetBaseSpell(bd.id)
                    if not baseID then
                        -- Spell data not loaded yet; don't commit the sentinel.
                        skipped = skipped + 1
                    elseif baseID ~= 0 and baseID ~= bd.id then
                        bd.id = baseID
                        bd.name = C_Spell.GetSpellName(baseID) or bd.name
                        migrated = migrated + 1
                    end
                end
            end
        end
    end

    if skipped > 0 then
        -- Don't set sentinel; re-run on next load when data may be available.
        return
    end

    profile._migratedBaseSpells = true
end

-- Rename resource specColors -> specOverrides in all scoped bar settings.
