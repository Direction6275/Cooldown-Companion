local ST = {
    Addon = {},
    _defaults = {
        profile = {
            minimap = {},
            hideInfoButtons = false,
            escClosesConfig = true,
            showAdvanced = false,
            autoAddPrefs = {},
            groupSettingPresets = {},
            auraTextureLibrary = {},
            globalStyle = {},
            locked = false,
            cdmHidden = false,
            resourceBars = {},
            castBar = {},
            frameAnchoring = {},
        },
    },
}

local function deepCopy(value)
    if type(value) ~= "table" then
        return value
    end

    local copy = {}
    for key, child in pairs(value) do
        copy[deepCopy(key)] = deepCopy(child)
    end
    return copy
end

CopyTable = deepCopy

local function assertEquals(actual, expected, label)
    if actual ~= expected then
        error(string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)), 2)
    end
end

local function assertTrue(value, label)
    if not value then
        error(label, 2)
    end
end

local function assertFalse(value, label)
    if value then
        error(label, 2)
    end
end

local migrationChunk = assert(loadfile("Core/Migrations.lua"))
migrationChunk("CooldownCompanion", ST)

local addon = ST.Addon
addon.db = {
    profile = {
        groups = {},
        groupContainers = {},
    },
}
addon.printed = {}

function addon:Print(message)
    self.printed[#self.printed + 1] = message
end

local migrationCalls = {}
local migrationNames = {
    "MigrateGroupOwnership",
    "MigrateFolderOwnership",
    "MigrateOrphanedGroups",
    "MigrateAlphaSystem",
    "MigrateDisplayMode",
    "MigrateMasqueField",
    "MigrateRemoveBarChargeOldFields",
    "MigrateVisibility",
    "MigrateStandaloneAuraMetadata",
    "MigrateAddedAsClassification",
    "MigrateInvertAuraDesaturationLogic",
    "MigrateFolders",
    "MigrateFolderSpecFilters",
    "MigrateContainerHeroTalentStamps",
    "ReverseMigrateMW",
    "MigrateCustomAuraBarsToSpecKeyed",
    "MigrateLSMNames",
    "MigrateChargeTextToGroupStyle",
    "MigrateProcGlowToStyleOverrides",
    "MigrateGlowSettingsToGroupStyle",
    "MigrateAuraIndicatorToGroupStyle",
    "MigrateAssistedHighlightHostileTargetOnly",
    "MigrateBarOrdering",
    "MigrateRemoveAuraDurationCache",
    "MigrateResourceBarYOffset",
    "MigrateLegacyCastBarYOffsetField",
    "MigrateResourceAuraOverlayEntries",
    "MigrateMaxStacksGlowStyles",
    "MigrateTalentConditions",
    "MigrateChoiceTalentConditions",
    "MigrateNewDefaults",
    "MigrateBorderRenderModeOverrides",
    "MigrateIconFillTimerDefaults",
    "MigrateCharacterScopedBarSettings",
    "MigratePanelAnchorCenter",
    "MigrateContainerAnchorsToScreenOffsets",
    "MigrateContainerAlphaToPanel",
    "MigrateStrataOrderExpansion",
    "MigrateCustomAuraBarSlots5",
    "MigrateLayoutOrderToSpecKeyed",
    "MigrateResourceBarExpandedSpecLayouts",
    "MigrateBaseSpellResolution",
    "MigrateSpecColorsToSpecOverrides",
    "MigrateResourceBarDisplayProfiles",
    "MigrateCustomAuraBarsToCustomBars",
    "MigrateDurationFormatSettings",
}

for _, name in ipairs(migrationNames) do
    addon[name] = function()
        migrationCalls[#migrationCalls + 1] = name
    end
end

assertTrue(addon:IsUnsupportedImportPayload({ globalStyle = {} }), "missing checkpoint is unsupported for imports")
assertFalse(addon:HasSupportedImportCheckpoint({ _cdcImportCheckpoint = "1.14.99" }), "older checkpoint is unsupported")
assertTrue(addon:HasSupportedImportCheckpoint({ _cdcImportCheckpoint = "1.15" }), "1.15 checkpoint is supported")
assertTrue(addon:HasSupportedImportCheckpoint({ _cdcImportCheckpoint = "1.15.2" }), "1.15 patch checkpoint is supported")
assertTrue(addon:HasSupportedImportCheckpoint({ _cdcImportCheckpoint = "1.16" }), "newer checkpoint is supported")

local stamped = addon:StampImportCheckpoint({ type = "customBars" })
assertEquals(stamped._cdcImportCheckpoint, "1.15", "manual stamp records checkpoint")
assertFalse(addon:IsUnsupportedImportPayload(stamped), "stamped payload is supported for imports")

assertTrue(addon:RunAllMigrations(), "local profile migrations still run")
assertEquals(#migrationCalls, #migrationNames, "all stubbed migrations ran before checkpoint stamp")
assertEquals(addon.db.profile._cdcImportCheckpoint, "1.15", "local profile is stamped after migrations")

local serializedStore = {}
local nextSerializedId = 0
local aceSerializer = {}
function aceSerializer:Serialize(data)
    nextSerializedId = nextSerializedId + 1
    local key = "serialized:" .. nextSerializedId
    serializedStore[key] = deepCopy(data)
    return key
end
function aceSerializer:Deserialize(key)
    return serializedStore[key] ~= nil, deepCopy(serializedStore[key])
end

local libDeflate = {}
function libDeflate:CompressDeflate(value)
    return value
end
function libDeflate:EncodeForPrint(value)
    return value
end
function libDeflate:DecodeForPrint(value)
    return value
end
function libDeflate:DecompressDeflate(value)
    return value
end

function LibStub(name)
    if name == "AceSerializer-3.0" then
        return aceSerializer
    end
    if name == "LibDeflate" then
        return libDeflate
    end
    error("unexpected library: " .. tostring(name), 2)
end

local codecChunk = assert(loadfile("Config/ExportCodec.lua"))
codecChunk("CooldownCompanion", ST)

local encodedProfile = ST._EncodeSharedPayload({ globalStyle = {} }, "profile")
local profileOk, decodedProfile = ST._DecodeSharedPayload(encodedProfile)
assertTrue(profileOk, "encoded profile decodes")
assertTrue(addon:HasSupportedImportCheckpoint(decodedProfile), "profile export keeps checkpoint after decode")

local encodedEntity = ST._EncodeSharedPayload({ type = "customBars", version = 1, bars = { { customBarId = 1 } } }, "entity")
local entityOk, decodedEntity = ST._DecodeSharedPayload(encodedEntity)
assertTrue(entityOk, "encoded entity decodes")
assertEquals(decodedEntity.type, "customBars", "entity type survives decode")
assertTrue(addon:HasSupportedImportCheckpoint(decodedEntity), "entity export keeps checkpoint after decode")

local encodedDiagnostic = ST._EncodeSharedPayload({ meta = {}, runtime = {}, profile = { globalStyle = {} } }, "diagnostic")
local diagnosticOk, decodedDiagnostic = ST._DecodeSharedPayload(encodedDiagnostic)
assertTrue(diagnosticOk, "encoded diagnostic decodes")
assertTrue(addon:HasSupportedImportCheckpoint(decodedDiagnostic), "diagnostic export keeps top-level checkpoint")
assertTrue(addon:HasSupportedImportCheckpoint(decodedDiagnostic.profile), "diagnostic profile keeps nested checkpoint")

print("migration checkpoint tests passed")
