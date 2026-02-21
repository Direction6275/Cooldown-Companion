--[[
    CooldownCompanion - Core/Migrations.lua: All migration functions and helpers
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local Masque = CooldownCompanion.Masque

local pairs = pairs
local ipairs = ipairs
local type = type

function CooldownCompanion:MigrateGroupOwnership()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.createdBy == nil and group.isGlobal == nil then
            group.isGlobal = true
            group.createdBy = "migrated"
        end
    end
end

function CooldownCompanion:MigrateFolderOwnership()
    local db = self.db.profile
    if not db.folders then return end
    for folderId, folder in pairs(db.folders) do
        if folder.section == "char" and not folder.createdBy then
            -- Infer owner from child groups
            local owner
            for _, group in pairs(db.groups) do
                if group.folderId == folderId and group.createdBy then
                    owner = group.createdBy
                    break
                end
            end
            folder.createdBy = owner or self.db.keys.char
        end
    end
end

function CooldownCompanion:MigrateOrphanedGroups()
    local currentChar = self.db.keys.char
    local currentName = currentChar:match("^(.+) %- ")
    if not currentName then return end
    for groupId, group in pairs(self.db.profile.groups) do
        if not group.isGlobal and group.createdBy
           and group.createdBy ~= currentChar
           and group.createdBy ~= "migrated" then
            local ownerName = group.createdBy:match("^(.+) %- ")
            if ownerName == currentName then
                group.createdBy = currentChar
            end
        end
    end
    -- Reclaim orphaned folders from realm renames
    if self.db.profile.folders then
        for _, folder in pairs(self.db.profile.folders) do
            if folder.section == "char" and folder.createdBy
               and folder.createdBy ~= currentChar then
                local ownerName = folder.createdBy:match("^(.+) %- ")
                if ownerName == currentName then
                    folder.createdBy = currentChar
                end
            end
        end
    end
end

function CooldownCompanion:MigrateAlphaSystem()
    for groupId, group in pairs(self.db.profile.groups) do
        -- Remove old hide fields
        group.hideWhileMounted = nil
        group.hideInCombat = nil
        group.hideOutOfCombat = nil
        group.hideNoTarget = nil
        -- Remove deprecated force-hide fields (replaced by force-visible-only checkboxes)
        group.forceHideTargetExists = nil
        group.forceHideMouseover = nil
        -- Ensure new defaults exist
        if group.baselineAlpha == nil then group.baselineAlpha = 1 end
        if group.fadeDelay == nil then group.fadeDelay = 1 end
        if group.fadeInDuration == nil then group.fadeInDuration = 0.2 end
        if group.fadeOutDuration == nil then group.fadeOutDuration = 0.2 end
    end
end

function CooldownCompanion:MigrateDisplayMode()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.displayMode == nil then
            group.displayMode = "icons"
        end
    end
end

function CooldownCompanion:MigrateMasqueField()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.masqueEnabled == nil then
            group.masqueEnabled = false
        end
        -- If Masque addon is not available but group had it enabled, disable it
        if group.masqueEnabled and not Masque then
            group.masqueEnabled = false
        end
    end
end

function CooldownCompanion:MigrateRemoveBarChargeOldFields()
    for _, group in pairs(self.db.profile.groups) do
        if group.style then
            group.style.barChargeGap = nil
        end
        if group.buttons then
            for _, bd in ipairs(group.buttons) do
                bd.barChargeMissingColor = nil
                bd.barChargeSwipe = nil
                bd.barChargeGap = nil
                bd.barReverseCharges = nil
                bd.barCdTextOnRechargeBar = nil
            end
        end
    end
end

function CooldownCompanion:MigrateVisibility()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.compactLayout == nil then
            group.compactLayout = false
        end
        if group.maxVisibleButtons == nil then
            group.maxVisibleButtons = 0
        end
    end
end

function CooldownCompanion:MigrateFolders()
    if self.db.profile.folders == nil then
        self.db.profile.folders = {}
    end
    if self.db.profile.nextFolderId == nil then
        self.db.profile.nextFolderId = 1
    end
end

function CooldownCompanion:ReverseMigrateMW()
    local rb = self.db.profile.resourceBars
    if not rb then return end

    -- If MW was previously migrated to customAuraBars[1], restore it to resources[100]
    if rb.migrationVersion and rb.migrationVersion >= 1 then
        local cab1 = rb.customAuraBars and rb.customAuraBars[1]
        if cab1 and cab1.spellID == 187880 then
            if not rb.resources then rb.resources = {} end
            rb.resources[100] = {
                enabled = cab1.enabled ~= false,
                mwBaseColor = cab1.barColor,
                mwOverlayColor = cab1.overlayColor,
                mwMaxColor = cab1.maxColor,
            }
            -- Clear the custom aura bar slot
            rb.customAuraBars[1] = { enabled = false }
        end
        rb.migrationVersion = nil
    end

    -- Clean maxColor from any existing custom aura bar slots
    if rb.customAuraBars then
        for _, cab in pairs(rb.customAuraBars) do
            if cab then cab.maxColor = nil end
        end
    end
end

function CooldownCompanion:MigrateCustomAuraBarsToSpecKeyed()
    local rb = self.db.profile.resourceBars
    if not rb or not rb.customAuraBars then return end
    -- Old format has integer key [1] with an enabled field; spec IDs are 3+ digits
    local first = rb.customAuraBars[1]
    if first and type(first) == "table" and first.enabled ~= nil then
        rb.customAuraBars = {}
    end
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
