--[[
    CooldownCompanion - Core/Migrations.lua: All migration functions and helpers
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local Masque = CooldownCompanion.Masque

local pairs = pairs
local ipairs = ipairs
local type = type
local next = next
local rawget = rawget

local LEGACY_SUPPORT_FLOOR_VERSION = "1.10"
local LEGACY_UNSUPPORTED_MAX_VERSION = "1.9"

local function LooksLikeProfilePayload(profile)
    return rawget(profile, "groups") ~= nil
        or rawget(profile, "groupContainers") ~= nil
        or rawget(profile, "globalStyle") ~= nil
        or rawget(profile, "nextGroupId") ~= nil
        or rawget(profile, "nextContainerId") ~= nil
        or rawget(profile, "nextFolderId") ~= nil
        or rawget(profile, "folders") ~= nil
        or rawget(profile, "bars") ~= nil
        or rawget(profile, "resourceBars") ~= nil
        or rawget(profile, "castBar") ~= nil
        or rawget(profile, "frameAnchoring") ~= nil
end

function CooldownCompanion:IsUnsupportedLegacyProfile(profile)
    if type(profile) ~= "table" then return false end

    local groups = profile.groups
    local containers = profile.groupContainers
    local hasContainerTable = type(containers) == "table"

    -- Treat profile-shaped payloads without container-era storage as unsupported.
    if LooksLikeProfilePayload(profile) and not hasContainerTable then
        return true
    end

    return type(groups) == "table"
        and next(groups) ~= nil
        and not next(containers)
end

function CooldownCompanion:GetLegacySupportCutoffMessage(dataLabel)
    dataLabel = dataLabel or "data"
    return ("This build supports Cooldown Companion %s and newer. This %s appears to come from %s or older. Use an older addon version first if you need to recover it."):format(
        LEGACY_SUPPORT_FLOOR_VERSION,
        dataLabel,
        LEGACY_UNSUPPORTED_MAX_VERSION
    )
end

function CooldownCompanion:NotifyLegacySupportCutoff(dataLabel)
    self:Print(self:GetLegacySupportCutoffMessage(dataLabel))
end

-- Consolidated entry point: runs all migrations in the correct order.
-- Called from OnEnable, OnProfileChanged, OnProfileCopied, OnProfileReset,
-- and after profile import to ensure every profile is fully migrated.
function CooldownCompanion:RunAllMigrations()
    if self:IsUnsupportedLegacyProfile(self.db and self.db.profile) then
        self._unsupportedLegacyProfile = true
        if not self._unsupportedLegacyProfileNotified then
            self:NotifyLegacySupportCutoff("profile")
            self._unsupportedLegacyProfileNotified = true
        end
        return false
    end

    self._unsupportedLegacyProfile = false
    self._unsupportedLegacyProfileNotified = nil
    self._pendingUnsupportedLegacyHide = nil

    self:MigrateGroupOwnership()
    self:MigrateFolderOwnership()
    self:MigrateOrphanedGroups()
    self:MigrateAlphaSystem()
    self:MigrateDisplayMode()
    self:MigrateMasqueField()
    self:MigrateRemoveBarChargeOldFields()
    self:MigrateVisibility()
    self:MigrateStandaloneAuraMetadata()
    self:MigrateAddedAsClassification()
    self:MigrateInvertAuraDesaturationLogic()
    self:MigrateFolders()
    self:MigrateFolderSpecFilters()
    self:MigrateContainerHeroTalentStamps()
    self:ReverseMigrateMW()
    self:MigrateCustomAuraBarsToSpecKeyed()
    self:MigrateLSMNames()
    self:MigrateChargeTextToGroupStyle()
    self:MigrateProcGlowToStyleOverrides()
    self:MigrateGlowSettingsToGroupStyle()
    self:MigrateAuraIndicatorToGroupStyle()
    self:MigrateAssistedHighlightHostileTargetOnly()
    self:MigrateBarOrdering()
    self:MigrateRemoveAuraDurationCache()
    self:MigrateResourceBarYOffset()
    self:MigrateLegacyCastBarYOffsetField()
    self:MigrateResourceAuraOverlayEntries()
    self:MigrateMaxStacksGlowStyles()
    self:MigrateTalentConditions()
    self:MigrateChoiceTalentConditions()
    self:MigrateNewDefaults()
    self:MigrateCharacterScopedBarSettings()
    self:MigratePanelAnchorCenter()
    self:MigrateContainerAnchorsToScreenOffsets()
    self:MigrateContainerAlphaToPanel()
    self:MigrateStrataOrderExpansion()
    self:MigrateCustomAuraBarSlots5()
    self:MigrateLayoutOrderToSpecKeyed()
    self:MigrateBaseSpellResolution()
    self:MigrateSpecColorsToSpecOverrides()
    return true
end

-- Clear all migration sentinel flags so migrations re-evaluate the actual data.
-- Called before RunAllMigrations() after profile/group/diagnostic import to ensure
-- sentinel flags (from the imported data or prior profile state) don't suppress
-- migrations that need to run on the freshly imported data.
function CooldownCompanion:ClearMigrationSentinels()
    local profile = self.db.profile
    profile.lsmMigrated = nil
    profile.chargeTextMigrated = nil
    profile.procGlowOverrideMigrated = nil
    profile.glowSettingsMigrated = nil
    profile.auraIndicatorMigrated = nil
    profile.assistedHighlightHostileTargetOnlyMigrated = nil
    profile.addedAsClassificationMigrated = nil
    profile.addedAsClassificationV2Migrated = nil
    profile.standaloneAuraMetadataMigrated = nil
    profile.standaloneAuraLinkMetadataMigrated = nil
    profile.standaloneAuraMetadataV2Migrated = nil
    profile.invertAuraDesaturationLogicMigrated = nil
    profile.talentConditionsMigrated = nil
    profile.choiceTalentConditionsMigrated = nil
    profile.newDefaultsMigrated = nil
    profile._migratedContainerAnchorsToScreenOffsets = nil
    profile._migratedContainerAlphaToPanel = nil
    profile._migratedContainerHeroTalentStamps = nil
    profile._migratedPanelAnchorCenter = nil
    profile._migratedStrataOrder6 = nil
    profile._migratedCustomAuraSlots5 = nil
    profile._migratedCustomAuraSlots5v2 = nil
    profile._migratedBaseSpells = nil
    profile._migratedLayoutOrder = nil
    profile._migratedSpecOverrides = nil
end

function CooldownCompanion:MigrateGroupOwnership()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.parentContainerId then
            -- Panels inherit visibility from their container — clear stale
            -- ownership fields that may have been re-stamped before this guard
            -- existed, or left over from an incomplete migration cycle.
            if group.isGlobal ~= nil then group.isGlobal = nil end
            if group.createdBy == "migrated" then group.createdBy = nil end
        elseif group.createdBy == nil and group.isGlobal == nil then
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

        -- Legacy mounted tri-state -> split Regular Mount + Dragonriding.
        -- Preserve behavior by copying legacy mounted settings to both buckets.
        local hadLegacyMounted = group.forceAlphaMounted ~= nil or group.forceHideMounted ~= nil
        if hadLegacyMounted then
            local legacyVisible = group.forceAlphaMounted == true
            local legacyHidden = group.forceHideMounted == true
            if rawget(group, "forceAlphaRegularMounted") == nil then
                group.forceAlphaRegularMounted = legacyVisible
            end
            if rawget(group, "forceHideRegularMounted") == nil then
                group.forceHideRegularMounted = legacyHidden
            end
            if rawget(group, "forceAlphaDragonriding") == nil then
                group.forceAlphaDragonriding = legacyVisible
            end
            if rawget(group, "forceHideDragonriding") == nil then
                group.forceHideDragonriding = legacyHidden
            end
        end
        group.forceAlphaMounted = nil
        group.forceHideMounted = nil

        -- Remove deprecated force-hide fields (replaced by force-visible-only checkboxes)
        group.forceHideTargetExists = nil
        group.forceHideMouseover = nil
        -- Ensure new defaults exist
        if group.baselineAlpha == nil then group.baselineAlpha = 1 end
        if group.fadeDelay == nil then group.fadeDelay = 1 end
        if group.fadeInDuration == nil then group.fadeInDuration = 0.2 end
        if group.fadeOutDuration == nil then group.fadeOutDuration = 0.2 end
    end

    -- Migrate legacy mounted keys in saved group setting presets.
    local presetStore = self.db.profile.groupSettingPresets
    if type(presetStore) == "table" then
        for _, mode in ipairs({"icons", "bars"}) do
            local modeStore = presetStore[mode]
            if type(modeStore) == "table" then
                for _, preset in pairs(modeStore) do
                    local groupData = type(preset) == "table" and preset.group or nil
                    if type(groupData) == "table" then
                        local hadLegacyMounted = groupData.forceAlphaMounted ~= nil or groupData.forceHideMounted ~= nil
                        if hadLegacyMounted then
                            local legacyVisible = groupData.forceAlphaMounted == true
                            local legacyHidden = groupData.forceHideMounted == true
                            if groupData.forceAlphaRegularMounted == nil then
                                groupData.forceAlphaRegularMounted = legacyVisible
                            end
                            if groupData.forceHideRegularMounted == nil then
                                groupData.forceHideRegularMounted = legacyHidden
                            end
                            if groupData.forceAlphaDragonriding == nil then
                                groupData.forceAlphaDragonriding = legacyVisible
                            end
                            if groupData.forceHideDragonriding == nil then
                                groupData.forceHideDragonriding = legacyHidden
                            end
                        end
                        groupData.forceAlphaMounted = nil
                        groupData.forceHideMounted = nil
                    end
                end
            end
        end
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

function CooldownCompanion:MigrateFolders()
    if self.db.profile.folders == nil then
        self.db.profile.folders = {}
    end
    if self.db.profile.nextFolderId == nil then
        self.db.profile.nextFolderId = 1
    end
end

function CooldownCompanion:MigrateFolderSpecFilters()
    local db = self.db.profile
    if not db.folders then return end

    for folderId, folder in pairs(db.folders) do
        if folder.specs ~= nil and type(folder.specs) ~= "table" then
            folder.specs = nil
        end

        if folder.specs then
            local normalizedSpecs = {}
            for specId, enabled in pairs(folder.specs) do
                local numSpecId = tonumber(specId)
                if enabled and numSpecId then
                    normalizedSpecs[numSpecId] = true
                end
            end
            if next(normalizedSpecs) then
                folder.specs = normalizedSpecs
            else
                folder.specs = nil
            end
        end

        if folder.heroTalents ~= nil and type(folder.heroTalents) ~= "table" then
            folder.heroTalents = nil
        end
        if folder.heroTalents then
            local normalizedHero = {}
            for subTreeID, enabled in pairs(folder.heroTalents) do
                local numSubTreeID = tonumber(subTreeID)
                if enabled and numSubTreeID then
                    normalizedHero[numSubTreeID] = true
                end
            end
            if next(normalizedHero) then
                folder.heroTalents = normalizedHero
            else
                folder.heroTalents = nil
            end
        end
        if not (folder.specs and next(folder.specs)) then
            folder.heroTalents = nil
        end

        if folder.specs and next(folder.specs) then
            self:ApplyFolderSpecFilterToChildren(folderId)
        end
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

function CooldownCompanion:MigrateBarOrdering()
    local profile = self.db.profile
    local rb = profile.resourceBars
    local cb = profile.castBar
    if not rb then return end

    -- Skip if already migrated (old fields are gone) or never configured
    if rb.position == nil and rb.stackOrder == nil then return end

    local oldPosition = rb.position or "below"
    local oldStackOrder = rb.stackOrder or "resource_first"

    -- Assign unique sequential orders to class resources per power type.
    -- Order matches the CLASS_RESOURCES/SPEC_RESOURCES tables in ResourceBar.lua.
    -- We use a fixed broad list covering all classes; non-enabled resources are ignored.
    -- Each power type gets a unique value so the sort is deterministic.
    local defaultResourceOrder = {
        [0]  = 1,    -- Mana
        [1]  = 2,    -- Rage
        [2]  = 3,    -- Focus
        [3]  = 4,    -- Energy
        [4]  = 5,    -- ComboPoints
        [5]  = 6,    -- Runes
        [6]  = 7,    -- RunicPower
        [7]  = 8,    -- SoulShards
        [8]  = 9,    -- LunarPower
        [9]  = 10,   -- HolyPower
        [11] = 11,   -- Maelstrom
        [12] = 12,   -- Chi
        [13] = 13,   -- Insanity
        [16] = 14,   -- ArcaneCharges
        [17] = 15,   -- Fury
        [18] = 16,   -- Pain
        [19] = 17,   -- Essence
        [100] = 18,  -- Maelstrom Weapon
    }

    -- Set position/order on any resources already in the db
    if rb.resources then
        for pt, res in pairs(rb.resources) do
            res.position = oldPosition
            res.order = defaultResourceOrder[pt] or 1
        end
    end

    -- Set position/order on custom aura bar slots
    if not rb.customAuraBarSlots then
        rb.customAuraBarSlots = {}
    end
    for i = 1, 5 do
        if not rb.customAuraBarSlots[i] then
            rb.customAuraBarSlots[i] = {}
        end
        rb.customAuraBarSlots[i].position = oldPosition
        rb.customAuraBarSlots[i].order = 1000 + i
    end

    -- Migrate cast bar order based on old stackOrder
    if cb then
        if oldStackOrder == "cast_first" then
            cb.order = 0
        else
            cb.order = 2000
        end
        -- Migrate cast bar position to match old resource bar position
        if cb.position == nil then
            cb.position = oldPosition
        end
    end

    -- Remove old fields
    rb.position = nil
    rb.stackOrder = nil
    rb.reverseResourceOrder = nil

    -- castBar.yOffset is no longer used for gap (shared gap comes from resourceBars.yOffset).
    -- Clear any non-default value so it doesn't mislead future code.
    if cb and (cb.yOffset or 0) ~= 0 then
        cb.yOffset = 0
    end
end

-- Remove vestigial auraDurationCache from profile (no longer in defaults).
-- It was never written to at runtime; this just cleans up stale SavedVariables.
function CooldownCompanion:MigrateRemoveAuraDurationCache()
    self.db.profile.auraDurationCache = nil
end

-- Normalize only legacy shared resource-bar settings that predate the
-- character-scoped buckets. Modern character-scoped values may be negative on
-- purpose now, so leave those untouched.
function CooldownCompanion:MigrateResourceBarYOffset()
    local function normalizeLegacyYOffset(settings)
        if type(settings) == "table" and settings.yOffset and settings.yOffset < 0 then
            settings.yOffset = math.abs(settings.yOffset)
        end
    end

    normalizeLegacyYOffset(rawget(self.db.profile, "resourceBars"))
    normalizeLegacyYOffset(rawget(self.db.profile, "legacyResourceBarsSeed"))
end

-- Remove the old castBar.yOffset field from all storage buckets.
-- Attached-mode cast bar gap now comes from resourceBars.yOffset plus the
-- new opt-in castBar.panelAnchorYOffset delta.
function CooldownCompanion:MigrateLegacyCastBarYOffsetField()
    local profile = self.db.profile
    if profile._migratedLegacyCastBarYOffsetField then return end

    local function clearLegacyYOffset(settings)
        if type(settings) == "table" and settings.yOffset ~= nil then
            settings.yOffset = nil
        end
    end

    clearLegacyYOffset(rawget(profile, "castBar"))
    clearLegacyYOffset(rawget(profile, "legacyCastBarSeed"))

    local store = rawget(profile, "castBarByChar")
    if type(store) == "table" then
        for _, settings in pairs(store) do
            clearLegacyYOffset(settings)
        end
    end

    profile._migratedLegacyCastBarYOffsetField = true
end

local function HasResourceAuraOverlayEntries(resource)
    if type(resource) ~= "table" or type(resource.auraOverlayEntries) ~= "table" then
        return false
    end
    return next(resource.auraOverlayEntries) ~= nil
end

local function HasLegacyResourceAuraOverlayData(resource)
    if type(resource) ~= "table" then
        return false
    end
    return resource.auraColorSpellID ~= nil
        or resource.auraActiveColor ~= nil
        or resource.auraColorTrackingMode ~= nil
        or resource.auraColorMaxStacks ~= nil
end

local function GetEffectiveResourceAuraOverlayEnabled(resource)
    if type(resource) ~= "table" then
        return false
    end
    if type(resource.auraOverlayEnabled) == "boolean" then
        return resource.auraOverlayEnabled
    end
    if HasResourceAuraOverlayEntries(resource) then
        return true
    end
    local auraSpellID = tonumber(resource.auraColorSpellID)
    return auraSpellID and auraSpellID > 0 or false
end

local function CopyResourceAuraOverlayColor(color)
    if type(color) ~= "table" or color[1] == nil or color[2] == nil or color[3] == nil then
        return nil
    end
    return { color[1], color[2], color[3] }
end

local function ClearLegacyResourceAuraOverlayFields(resource)
    if type(resource) ~= "table" then
        return
    end
    resource.auraColorSpellID = nil
    resource.auraActiveColor = nil
    resource.auraColorTrackingMode = nil
    resource.auraColorMaxStacks = nil
end

function CooldownCompanion:MigrateResourceAuraOverlayEntries()
    -- Resource aura overlay legacy conversion now happens when the current
    -- character's resource bar settings bucket is materialized from the shared
    -- seed, so the data can be filtered by character/class before becoming
    -- persistent per-character state.
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

function CooldownCompanion:MigrateCharacterScopedBarSettings()
    self:CaptureLegacyScopedBarSettingsSeeds()
    self:EnsureLegacyScopedBarSeenCharacters()
    self:EnsureCurrentCharacterScopedBarSettings()
end

function CooldownCompanion:MigratePanelAnchorCenter()
    local profile = self.db and self.db.profile
    if not profile or profile._migratedPanelAnchorCenter then return end

    local containers = profile.groupContainers or {}
    for _, group in pairs(profile.groups or {}) do
        local pcid = group.parentContainerId
        if pcid and containers[pcid] then
            local a = group.anchor
            if a and a.point == "TOPLEFT"
               and a.relativeTo == "CooldownCompanionContainer" .. pcid
               and a.relativePoint == "TOPLEFT"
               and (a.x or 0) == 0 and (a.y or 0) == 0 then
                a.point = "CENTER"
                a.relativePoint = "CENTER"
            end
        end
    end

    profile._migratedPanelAnchorCenter = true
end

function CooldownCompanion:MigrateContainerAnchorsToScreenOffsets()
    local profile = self.db.profile
    if profile._migratedContainerAnchorsToScreenOffsets then return end

    for containerId, container in pairs(profile.groupContainers or {}) do
        if self:IsContainerVisibleToCurrentChar(containerId) then
            container.anchor = self:NormalizeContainerAnchor(container.anchor)
        end
    end

    profile._migratedContainerAnchorsToScreenOffsets = true
end

-------------------------------------------------------------------------
-- MigrateContainerAlphaToPanel: Copies container-level alpha settings
-- down to each child panel so panels own their own alpha independently.
-------------------------------------------------------------------------
local ALPHA_FIELDS = {
    "baselineAlpha",
    "forceAlphaInCombat", "forceAlphaOutOfCombat",
    "forceAlphaRegularMounted", "forceAlphaDragonriding",
    "forceAlphaTargetExists", "forceAlphaMouseover",
    "forceHideInCombat", "forceHideOutOfCombat",
    "forceHideRegularMounted", "forceHideDragonriding",
    "fadeInDuration", "fadeOutDuration", "fadeDelay",
    "customFade", "treatTravelFormAsMounted",
}

function CooldownCompanion:MigrateContainerAlphaToPanel()
    local profile = self.db.profile
    if profile._migratedContainerAlphaToPanel then return end

    local containers = profile.groupContainers
    if not containers then
        profile._migratedContainerAlphaToPanel = true
        return
    end

    for containerId, container in pairs(containers) do
        -- Check if container has non-default alpha settings
        local hasCustomAlpha = (container.baselineAlpha ~= nil and container.baselineAlpha ~= 1)
        if not hasCustomAlpha then
            for _, key in ipairs(ALPHA_FIELDS) do
                if key ~= "baselineAlpha" and container[key] then
                    hasCustomAlpha = true
                    break
                end
            end
        end

        -- Copy alpha fields to each child panel that has default alpha
        for groupId, group in pairs(profile.groups) do
            if group.parentContainerId == containerId then
                if hasCustomAlpha then
                    -- Only copy to panels with default alpha (no custom settings)
                    local panelHasCustomAlpha = (group.baselineAlpha ~= nil and group.baselineAlpha ~= 1)
                    if not panelHasCustomAlpha then
                        for _, key in ipairs(ALPHA_FIELDS) do
                            if key ~= "baselineAlpha" and group[key] then
                                panelHasCustomAlpha = true
                                break
                            end
                        end
                    end

                    if not panelHasCustomAlpha then
                        for _, key in ipairs(ALPHA_FIELDS) do
                            local val = container[key]
                            if val ~= nil then
                                if type(val) == "table" then
                                    group[key] = CopyTable(val)
                                else
                                    group[key] = val
                                end
                            end
                        end
                    end
                end

                -- Ensure every panel has baselineAlpha set for nil-safety
                if group.baselineAlpha == nil then
                    group.baselineAlpha = 1
                end
            end
        end
    end

    profile._migratedContainerAlphaToPanel = true
end

-- Clear hero talents that were stamped onto containers by the old authoritative
-- ApplyFolderSpecFilterToChildren.  Those values were folder copies, not
-- user-set.  With the new cascading model, GetEffectiveHeroTalents reads the
-- folder at runtime so the stamped copies are stale duplicates.
function CooldownCompanion:MigrateContainerHeroTalentStamps()
    local profile = self.db.profile
    if profile._migratedContainerHeroTalentStamps then return end

    local containers = profile.groupContainers
    local folders = profile.folders
    if not containers or not folders then
        profile._migratedContainerHeroTalentStamps = true
        return
    end

    for _, container in pairs(containers) do
        local folderId = container.folderId
        if folderId then
            local folder = folders[folderId]
            if folder and folder.heroTalents and next(folder.heroTalents) then
                container.heroTalents = nil
            end
        end
    end

    profile._migratedContainerHeroTalentStamps = true
end

-- Expand 4-element strataOrder arrays to 6-element by inserting auraGlow and readyGlow.
-- These were previously hardcoded at cooldown:GetFrameLevel() + 1 (just above cooldown),
-- so we insert them immediately after the "cooldown" entry to preserve that visual position.
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

local function BackfillCustomAuraBarSlots5(rb)
    if type(rb) ~= "table" then return end

    if not rb.customAuraBarSlots then
        rb.customAuraBarSlots = {}
    end
    for i = 4, 5 do
        if not rb.customAuraBarSlots[i] then
            rb.customAuraBarSlots[i] = { position = "below", order = 1000 + i }
        end
    end

    if rb.customAuraBars then
        for _, specBars in pairs(rb.customAuraBars) do
            if type(specBars) == "table" then
                for i = 4, 5 do
                    if not specBars[i] then
                        specBars[i] = { enabled = false }
                    end
                end
            end
        end
    end
end

function CooldownCompanion:MigrateCustomAuraBarSlots5()
    local profile = self.db.profile
    if profile._migratedCustomAuraSlots5v2 then return end

    -- Clean up stale v1 sentinel
    profile._migratedCustomAuraSlots5 = nil

    -- Legacy / seed resource bar settings
    BackfillCustomAuraBarSlots5(rawget(profile, "resourceBars"))
    BackfillCustomAuraBarSlots5(rawget(profile, "legacyResourceBarsSeed"))

    -- Character-scoped buckets
    local store = rawget(profile, "resourceBarsByChar")
    if type(store) == "table" then
        for _, charSettings in pairs(store) do
            BackfillCustomAuraBarSlots5(charSettings)
        end
    end

    profile._migratedCustomAuraSlots5v2 = true
end

-- Migrate flat per-character layout position/order fields into the new
-- per-spec layoutOrder table.  Copies existing arrangement to ALL specs of
-- the current character's class so every spec starts with the previous layout.
function CooldownCompanion:MigrateLayoutOrderToSpecKeyed()
    local profile = self.db.profile
    if profile._migratedLayoutOrder then return end

    local _, _, classID = UnitClass("player")
    if not classID then return end

    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    if numSpecs == 0 then return end

    local specIDs = {}
    for i = 1, numSpecs do
        local specID = GetSpecializationInfoForClassID(classID, i)
        if specID then
            specIDs[#specIDs + 1] = specID
        end
    end
    if #specIDs == 0 then return end

    -- Extract layout fields from a resource bar settings table + optional cast bar table
    local function ExtractLayout(rbSettings, cbSettings)
        local layout = {
            resources = {},
            customAuraBarSlots = {},
            castBar = { position = "below", order = 2000 },
        }

        if type(rbSettings) == "table" and type(rbSettings.resources) == "table" then
            for pt, res in pairs(rbSettings.resources) do
                if type(res) == "table" and (res.position or res.order or res.verticalPosition or res.verticalOrder) then
                    layout.resources[pt] = {
                        position = res.position,
                        order = res.order,
                        verticalPosition = res.verticalPosition,
                        verticalOrder = res.verticalOrder,
                    }
                end
            end
        end

        if type(rbSettings) == "table" and type(rbSettings.customAuraBarSlots) == "table" then
            for slotIdx, slot in pairs(rbSettings.customAuraBarSlots) do
                if type(slot) == "table" and (slot.position or slot.order or slot.verticalPosition or slot.verticalOrder) then
                    layout.customAuraBarSlots[slotIdx] = {
                        position = slot.position,
                        order = slot.order,
                        verticalPosition = slot.verticalPosition,
                        verticalOrder = slot.verticalOrder,
                    }
                end
            end
        end

        if type(cbSettings) == "table" then
            if cbSettings.position or cbSettings.order then
                layout.castBar = {
                    position = cbSettings.position or "below",
                    order = cbSettings.order or 2000,
                }
            end
        end

        return layout
    end

    -- Copy layout to all specs (only for specs not already present)
    local function ApplyLayoutToAllSpecs(rbSettings, layout)
        if not rbSettings.layoutOrder then rbSettings.layoutOrder = {} end
        local allPresent = true
        for _, specID in ipairs(specIDs) do
            if not rbSettings.layoutOrder[specID] then allPresent = false; break end
        end
        if allPresent then return end

        for _, specID in ipairs(specIDs) do
            if not rbSettings.layoutOrder[specID] then
                rbSettings.layoutOrder[specID] = CopyTable(layout)
            end
        end
    end

    -- Migrate character-scoped buckets
    local rbStore = rawget(profile, "resourceBarsByChar")
    local cbStore = rawget(profile, "castBarByChar")
    if type(rbStore) == "table" then
        for charKey, rbSettings in pairs(rbStore) do
            if type(rbSettings) == "table" then
                local cbSettings = type(cbStore) == "table" and cbStore[charKey] or nil
                local layout = ExtractLayout(rbSettings, cbSettings)
                ApplyLayoutToAllSpecs(rbSettings, layout)
            end
        end
    end

    -- Migrate legacy seed
    local seed = rawget(profile, "legacyResourceBarsSeed")
    if type(seed) == "table" then
        local cbSeed = rawget(profile, "legacyCastBarSeed")
        local layout = ExtractLayout(seed, cbSeed)
        ApplyLayoutToAllSpecs(seed, layout)
    end

    profile._migratedLayoutOrder = true
end

-- Resolve stored spell IDs to their base form so the override chain can
-- freely transform to any variant at runtime.  Skip items (implicit via
-- type check), pet spells (may not resolve through GetBaseSpell), and CDM
-- child slots (viewer-frame mapping uses specific IDs).
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
function CooldownCompanion:MigrateSpecColorsToSpecOverrides()
    local profile = self.db and self.db.profile
    if not profile then return end
    if profile._migratedSpecOverrides then return end

    local function migrateSettings(settings)
        if type(settings) ~= "table" or type(settings.resources) ~= "table" then return end
        for _, resource in pairs(settings.resources) do
            if type(resource) == "table" and type(resource.specColors) == "table" then
                resource.specOverrides = resource.specColors
                resource.specColors = nil
            elseif type(resource) == "table" and resource.specColors ~= nil then
                resource.specColors = nil
            end
        end
    end

    -- Legacy / seed resource bar settings
    migrateSettings(rawget(profile, "resourceBars"))
    migrateSettings(rawget(profile, "legacyResourceBarsSeed"))

    -- Character-scoped buckets
    local store = rawget(profile, "resourceBarsByChar")
    if type(store) == "table" then
        for _, charSettings in pairs(store) do
            migrateSettings(charSettings)
        end
    end

    profile._migratedSpecOverrides = true
end

