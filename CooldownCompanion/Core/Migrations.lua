--[[
    CooldownCompanion - Core/Migrations.lua: migration orchestrator and cutoff helpers
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local type = type
local next = next
local rawget = rawget
local pairs = pairs
local ipairs = ipairs

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

local function HasTriggerConditionConfig(buttonData)
    return buttonData.triggerCondition ~= nil
        or buttonData.triggerExpected ~= nil
        or buttonData.triggerState ~= nil
        or buttonData.triggerConditions ~= nil
end

local function ClearTriggerConditionConfig(buttonData)
    local changed = false
    if buttonData.triggerCondition ~= nil then
        buttonData.triggerCondition = nil
        changed = true
    end
    if buttonData.triggerExpected ~= nil then
        buttonData.triggerExpected = nil
        changed = true
    end
    if buttonData.triggerState ~= nil then
        buttonData.triggerState = nil
        changed = true
    end
    if buttonData.triggerConditions ~= nil then
        buttonData.triggerConditions = nil
        changed = true
    end
    return changed
end

local function NormalizePromotedPassiveCooldownTriggerConditions(buttonData)
    if not HasTriggerConditionConfig(buttonData) then
        return false
    end
    if not (CooldownCompanion.GetTriggerConditionClauses and CooldownCompanion.NormalizeTriggerConditionRowData) then
        return false
    end

    local clauses = CooldownCompanion:GetTriggerConditionClauses(buttonData)
    local changed = false
    if #clauses == 0 then
        changed = ClearTriggerConditionConfig(buttonData)
    end

    CooldownCompanion:NormalizeTriggerConditionRowData(buttonData)
    return changed
end

local function NormalizePassiveCooldownButtons(profile)
    if type(profile) ~= "table" or type(profile.groups) ~= "table" then
        return false
    end
    if not ST.IsPassiveCooldownSpell then
        return false
    end

    local changed = false
    for _, group in pairs(profile.groups) do
        if type(group) == "table" and type(group.buttons) == "table" then
            for _, buttonData in ipairs(group.buttons) do
                if type(buttonData) == "table"
                    and buttonData.type == "spell"
                    and (buttonData.isPassive == true or buttonData.isPassiveCooldown == true) then
                    local isPassiveCooldown = buttonData.isPassiveCooldown == true
                        or ST.IsPassiveCooldownSpell(buttonData.id)
                    if isPassiveCooldown then
                        if buttonData.isPassiveCooldown ~= true then
                            buttonData.isPassiveCooldown = true
                            changed = true
                        end
                        if buttonData.isPassive ~= nil then
                            buttonData.isPassive = nil
                            changed = true
                        end
                        if buttonData.auraTracking ~= false then
                            buttonData.auraTracking = false
                            changed = true
                        end
                        if buttonData.addedAs ~= "spell" then
                            buttonData.addedAs = "spell"
                            changed = true
                        end
                        if NormalizePromotedPassiveCooldownTriggerConditions(buttonData) then
                            changed = true
                        end
                    end
                end
            end
        end
    end
    return changed
end

local function BackfillUnusableVisualOverrideModes(profile)
    if type(profile) ~= "table" or type(profile.groups) ~= "table" then
        return false
    end

    local changed = false
    for _, group in pairs(profile.groups) do
        if type(group) == "table" and type(group.buttons) == "table" then
            for _, buttonData in ipairs(group.buttons) do
                local overrides = type(buttonData) == "table" and buttonData.styleOverrides
                local overrideSections = type(buttonData) == "table" and buttonData.overrideSections
                if type(overrides) == "table"
                    and type(overrideSections) == "table"
                    and overrideSections.unusableDimming == true
                    and overrides.unusableVisualMode == nil then
                    overrides.unusableVisualMode = ST.UNUSABLE_VISUAL_MODE_DIM or "dim"
                    changed = true
                end
            end
        end
    end
    return changed
end

local AURA_DURATION_SWIPE_STYLE_MIRRORS = {
    { auraKey = "showAuraDurationSwipeFill", cooldownKey = "showCooldownSwipeFill", default = true },
    { auraKey = "auraDurationSwipeReverse", cooldownKey = "cooldownSwipeReverse", default = false },
    { auraKey = "showAuraDurationSwipeEdge", cooldownKey = "showCooldownSwipeEdge", default = true },
    { auraKey = "auraDurationSwipeAlpha", cooldownKey = "cooldownSwipeAlpha", default = 0.8 },
    { auraKey = "auraDurationSwipeEdgeColor", cooldownKey = "cooldownSwipeEdgeColor", default = {1, 1, 1, 1} },
}

local function ResolveMirroredCooldownSwipeStyleValue(style, fallbackStyle, cooldownKey, defaultValue)
    local value = style and style[cooldownKey]
    if value == nil and type(fallbackStyle) == "table" then
        value = fallbackStyle[cooldownKey]
    end
    if value == nil then
        value = defaultValue
    end
    if type(value) == "table" then
        return CopyTable(value)
    end
    return value
end

local function BackfillAuraDurationSwipeStyle(style, fallbackStyle)
    if type(style) ~= "table" then
        return false
    end

    local changed = false
    if style.showAuraDurationSwipe == nil then
        local showCooldownSwipe = style.showCooldownSwipe
        if showCooldownSwipe == nil and type(fallbackStyle) == "table" then
            showCooldownSwipe = fallbackStyle.showCooldownSwipe
        end
        style.showAuraDurationSwipe = showCooldownSwipe ~= false
        changed = true
    end

    for _, mirror in ipairs(AURA_DURATION_SWIPE_STYLE_MIRRORS) do
        if style[mirror.auraKey] == nil then
            style[mirror.auraKey] = ResolveMirroredCooldownSwipeStyleValue(style, fallbackStyle, mirror.cooldownKey, mirror.default)
            changed = true
        end
    end

    return changed
end

local function BackfillAuraDurationSwipeSettings(profile)
    if type(profile) ~= "table" then
        return false
    end

    local changed = BackfillAuraDurationSwipeStyle(profile.globalStyle)

    if type(profile.groups) == "table" then
        for _, group in pairs(profile.groups) do
            if type(group) == "table" then
                if BackfillAuraDurationSwipeStyle(group.style, profile.globalStyle) then
                    changed = true
                end

                if type(group.buttons) == "table" then
                    for _, buttonData in ipairs(group.buttons) do
                        if type(buttonData) == "table" then
                            local overrideSections = buttonData.overrideSections
                            local hasAuraSwipeOverride = type(overrideSections) == "table"
                                and (overrideSections.cooldownSwipe == true or overrideSections.auraDurationSwipe == true)
                            if hasAuraSwipeOverride and BackfillAuraDurationSwipeStyle(buttonData.styleOverrides, group.style) then
                                changed = true
                            end

                            if type(overrideSections) == "table"
                                and overrideSections.cooldownSwipe == true
                                and overrideSections.auraDurationSwipe ~= true then
                                overrideSections.auraDurationSwipe = true
                                changed = true
                            end
                        end
                    end
                end
            end
        end
    end

    return changed
end

local function ClearRetiredAutoAddPrefs(profile)
    if type(profile) ~= "table" or profile.autoAddPrefs == nil then
        return false
    end
    profile.autoAddPrefs = nil
    return true
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
    ClearRetiredAutoAddPrefs(self.db and self.db.profile)
    NormalizePassiveCooldownButtons(self.db and self.db.profile)
    BackfillUnusableVisualOverrideModes(self.db and self.db.profile)
    BackfillAuraDurationSwipeSettings(self.db and self.db.profile)
    if self.RunResourceBarClassScopeMigration then
        self:RunResourceBarClassScopeMigration()
    end
    if self.SanitizeCursorAnchorPolicy and not self._deferCursorAnchorPolicySanitizer then
        self:SanitizeCursorAnchorPolicy(self.db and self.db.profile)
    end
    if self.NormalizePanelAlphaInheritance then
        self:NormalizePanelAlphaInheritance(self.db and self.db.profile)
    end
    return true
end

function CooldownCompanion:ClearMigrationSentinels()
    -- Kept as the import hook for future post-1.15 migrations.
end

