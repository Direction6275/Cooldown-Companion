--[[
    CooldownCompanion - Core/Migrations.lua: migration orchestrator and cutoff helpers
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

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
    if type(profile) ~= "table" or rawget(profile, "type") ~= nil then
        return false
    end

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

local function HasSupportedCheckpoint(payload)
    if type(payload) ~= "table" then
        return false
    end

    local comparison = CompareVersion(payload[IMPORT_CHECKPOINT_KEY], IMPORT_CHECKPOINT_VERSION)
    return comparison ~= nil and comparison >= 0
end

local function GetSavedVariablesProfile(savedVariables, defaultProfile)
    if type(savedVariables) ~= "table" then
        return nil
    end

    if defaultProfile == true then
        defaultProfile = "Default"
    end

    local charName = UnitName and UnitName("player")
    local realmName = GetRealmName and GetRealmName()
    local charKey = charName and realmName and (charName .. " - " .. realmName)
    local profileKey = type(savedVariables.profileKeys) == "table"
        and charKey
        and savedVariables.profileKeys[charKey]
        or defaultProfile
        or charKey

    return type(savedVariables.profiles) == "table" and profileKey and savedVariables.profiles[profileKey] or nil
end

function CooldownCompanion:InspectSavedProfileCheckpoint(savedVariables, defaultProfile)
    local state = {
        hadSavedVariables = type(savedVariables) == "table",
        profileExisted = false,
        profileLookedLikePayload = false,
        profileHadSupportedCheckpoint = false,
    }

    local profile = GetSavedVariablesProfile(savedVariables, defaultProfile)
    if type(profile) ~= "table" then
        return state
    end

    state.profileExisted = true
    state.profileLookedLikePayload = LooksLikeProfilePayload(profile)
    state.profileHadSupportedCheckpoint = HasSupportedCheckpoint(profile)
    return state
end

function CooldownCompanion:IsUnsupportedLegacyProfile(profile, allowMissingCheckpoint)
    if type(profile) ~= "table" then return false end

    if LooksLikeProfilePayload(profile) and not HasSupportedCheckpoint(profile) then
        return not allowMissingCheckpoint
    end

    local groups = profile.groups
    local containers = profile.groupContainers
    local hasContainerTable = type(containers) == "table"

    -- Treat profile-shaped payloads without container-era storage as unsupported.
    if LooksLikeProfilePayload(profile) and not hasContainerTable then
        return true
    end

    return type(groups) == "table"
        and next(groups) ~= nil
        and hasContainerTable
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
    return HasSupportedCheckpoint(payload)
end

function CooldownCompanion:IsUnsupportedImportPayload(payload)
    if type(payload) ~= "table" then
        return false
    end
    if payload._cdcUnsupportedCompactFormat then
        return true
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

-- Consolidated entry point: enforces the 1.15 data cutoff and stamps profiles
-- that are allowed to continue. Add new post-1.15 migrations here in order.
function CooldownCompanion:RunAllMigrations()
    local checkpointState = self._savedProfileCheckpointState
    local allowMissingCheckpoint = self._allowMissingMigrationCheckpointOnce
        or (checkpointState and (
            not checkpointState.hadSavedVariables
            or not checkpointState.profileExisted
            or not checkpointState.profileLookedLikePayload
        ))
    self._allowMissingMigrationCheckpointOnce = nil
    self._savedProfileCheckpointState = nil

    if self:IsUnsupportedLegacyProfile(self.db and self.db.profile, allowMissingCheckpoint) then
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

    self:StampImportCheckpoint(self.db and self.db.profile)
    return true
end

function CooldownCompanion:ClearMigrationSentinels()
    -- Kept as the import hook for future post-1.15 migrations.
end

