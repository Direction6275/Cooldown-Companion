--[[
    CooldownCompanion - Core/Migrations.lua: migration orchestrator and cutoff helpers
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local Masque = CooldownCompanion.Masque

local pairs = pairs
local ipairs = ipairs
local type = type
local next = next
local rawget = rawget

local IMPORT_CHECKPOINT_KEY = "_cdcImportCheckpoint"
local IMPORT_CHECKPOINT_VERSION = "1.15"
local LEGACY_SUPPORT_FLOOR_VERSION = IMPORT_CHECKPOINT_VERSION
local LEGACY_UNSUPPORTED_MAX_VERSION = "1.14"

local function CompareVersion(left, right)
    left = tostring(left or "")
    right = tostring(right or "")

    local leftParts = {}
    for part in left:gmatch("%d+") do
        leftParts[#leftParts + 1] = tonumber(part) or 0
    end

    local rightParts = {}
    for part in right:gmatch("%d+") do
        rightParts[#rightParts + 1] = tonumber(part) or 0
    end

    if #leftParts == 0 or #rightParts == 0 then
        return nil
    end

    local maxParts = math.max(#leftParts, #rightParts)
    for index = 1, maxParts do
        local leftPart = leftParts[index] or 0
        local rightPart = rightParts[index] or 0
        if leftPart ~= rightPart then
            return leftPart < rightPart and -1 or 1
        end
    end

    return 0
end

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

function CooldownCompanion:StampImportCheckpoint(payload)
    if type(payload) == "table" then
        payload[IMPORT_CHECKPOINT_KEY] = IMPORT_CHECKPOINT_VERSION
    end
    return payload
end

function CooldownCompanion:StampExportPayloadCheckpoint(payload, exportKind)
    self:StampImportCheckpoint(payload)
    if exportKind == "diagnostic" and type(payload) == "table" and type(payload.profile) == "table" then
        self:StampImportCheckpoint(payload.profile)
    end
    return payload
end

function CooldownCompanion:HasSupportedImportCheckpoint(payload)
    if type(payload) ~= "table" then
        return false
    end

    local comparison = CompareVersion(payload[IMPORT_CHECKPOINT_KEY], IMPORT_CHECKPOINT_VERSION)
    return comparison ~= nil and comparison >= 0
end

function CooldownCompanion:IsUnsupportedImportPayload(payload)
    if type(payload) ~= "table" then
        return false
    end
    return self:IsUnsupportedLegacyProfile(payload) or not self:HasSupportedImportCheckpoint(payload)
end

function CooldownCompanion:GetLegacySupportCutoffMessage(dataLabel)
    dataLabel = dataLabel or "data"
    return ("This build supports Cooldown Companion %s and newer data. This %s appears to come from %s or older. To recover it, load or import it with an older addon version, then export it again after it has been opened by %s."):format(
        LEGACY_SUPPORT_FLOOR_VERSION,
        dataLabel,
        LEGACY_UNSUPPORTED_MAX_VERSION,
        LEGACY_SUPPORT_FLOOR_VERSION
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
    self:MigrateBorderRenderModeOverrides()
    self:MigrateIconFillTimerDefaults()
    self:MigrateCharacterScopedBarSettings()
    self:MigratePanelAnchorCenter()
    self:MigrateContainerAnchorsToScreenOffsets()
    self:MigrateContainerAlphaToPanel()
    self:MigrateStrataOrderExpansion()
    self:MigrateCustomAuraBarSlots5()
    self:MigrateLayoutOrderToSpecKeyed()
    self:MigrateResourceBarExpandedSpecLayouts()
    self:MigrateBaseSpellResolution()
    self:MigrateSpecColorsToSpecOverrides()
    self:MigrateResourceBarDisplayProfiles()
    self:MigrateCustomAuraBarsToCustomBars()
    self:MigrateDurationFormatSettings()
    self:StampImportCheckpoint(self.db and self.db.profile)
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
    profile.borderRenderModeOverridesMigrated = nil
    profile._migratedContainerAnchorsToScreenOffsets = nil
    profile._migratedContainerAlphaToPanel = nil
    profile._migratedContainerHeroTalentStamps = nil
    profile._migratedPanelAnchorCenter = nil
    profile._migratedStrataOrder6 = nil
    profile._migratedCustomAuraSlots5 = nil
    profile._migratedCustomAuraSlots5v2 = nil
    profile._migratedBaseSpells = nil
    profile._migratedIconFillTimerDefaults = nil
    profile._migratedLayoutOrder = nil
    profile._migratedResourceBarExpandedSpecLayouts = nil
    profile._migratedSpecOverrides = nil
    profile._migratedResourceBarDisplayProfiles = nil
    profile._migratedResourceBarDisplayProfilesV2 = nil
    profile._migratedCustomBarsDynamic = nil
    profile._migratedCustomBarsDynamicV2 = nil
    profile._migratedDurationFormatSettings = nil
end

