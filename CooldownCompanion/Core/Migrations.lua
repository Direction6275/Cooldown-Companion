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

local function CaptureAuraDurationSwipeStyleState(style)
    if type(style) ~= "table" then
        return nil
    end

    local values = {
        showCooldownSwipe = rawget(style, "showCooldownSwipe"),
        auraUseBlizzardSwipe = rawget(style, "auraUseBlizzardSwipe"),
    }
    local auraKeys = {
        showAuraDurationSwipe = rawget(style, "showAuraDurationSwipe") ~= nil,
    }

    for _, mirror in ipairs(AURA_DURATION_SWIPE_STYLE_MIRRORS) do
        values[mirror.cooldownKey] = rawget(style, mirror.cooldownKey)
        auraKeys[mirror.auraKey] = rawget(style, mirror.auraKey) ~= nil
    end

    return {
        values = values,
        auraKeys = auraKeys,
    }
end

local function HasCapturedAuraDurationSwipeKey(styleState, auraKey)
    return type(styleState) == "table"
        and type(styleState.auraKeys) == "table"
        and styleState.auraKeys[auraKey] == true
end

local function ShouldBackfillAuraDurationSwipeKey(style, styleState, auraKey)
    if type(style) ~= "table" then
        return false
    end
    if rawget(style, auraKey) == nil then
        return true
    end
    return styleState ~= nil and not HasCapturedAuraDurationSwipeKey(styleState, auraKey)
end

local function ResolveStyleValue(style, styleState, fallbackStyle, fallbackState, key, defaultValue)
    local values = type(styleState) == "table" and styleState.values
    local value
    if type(values) == "table" then
        value = values[key]
    end
    if value == nil and type(style) == "table" then
        value = rawget(style, key)
    end

    if value == nil then
        local fallbackValues = type(fallbackState) == "table" and fallbackState.values
        if type(fallbackValues) == "table" then
            value = fallbackValues[key]
        end
    end
    if value == nil and type(fallbackStyle) == "table" then
        value = rawget(fallbackStyle, key)
    end
    if value == nil then
        value = defaultValue
    end
    if type(value) == "table" then
        return CopyTable(value)
    end
    return value
end

local function BackfillAuraDurationSwipeStyle(style, fallbackStyle, styleState, fallbackState)
    if type(style) ~= "table" then
        return false
    end

    local changed = false
    if ShouldBackfillAuraDurationSwipeKey(style, styleState, "showAuraDurationSwipe") then
        local auraUseBlizzardSwipe = ResolveStyleValue(style, styleState, fallbackStyle, fallbackState, "auraUseBlizzardSwipe", false)
        if auraUseBlizzardSwipe == true then
            style.showAuraDurationSwipe = true
        else
            local showCooldownSwipe = ResolveStyleValue(style, styleState, fallbackStyle, fallbackState, "showCooldownSwipe", true)
            style.showAuraDurationSwipe = showCooldownSwipe ~= false
        end
        changed = true
    end

    for _, mirror in ipairs(AURA_DURATION_SWIPE_STYLE_MIRRORS) do
        if ShouldBackfillAuraDurationSwipeKey(style, styleState, mirror.auraKey) then
            style[mirror.auraKey] = ResolveStyleValue(style, styleState, fallbackStyle, fallbackState, mirror.cooldownKey, mirror.default)
            changed = true
        end
    end

    return changed
end

local function BackfillAuraDurationSwipeSettings(profile, savedProfileState)
    if type(profile) ~= "table" then
        return false
    end

    local globalStyleState = savedProfileState and savedProfileState.globalStyle
    local changed = BackfillAuraDurationSwipeStyle(profile.globalStyle, nil, globalStyleState)

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

    if type(profile.groupSettingPresets) == "table" then
        for _, presetStore in pairs(profile.groupSettingPresets) do
            if type(presetStore) == "table" then
                for _, presetData in pairs(presetStore) do
                    if type(presetData) == "table" and BackfillAuraDurationSwipeStyle(presetData.style, profile.globalStyle) then
                        changed = true
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
    state.auraDurationSwipe = {
        globalStyle = CaptureAuraDurationSwipeStyleState(profile.globalStyle),
    }
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

-- 12.1 aura rebuild migration: keep-what-maps (field names unchanged), drop
-- what has no 12.1 equivalent, recompute the tracked unit from spell polarity
-- (the anti-cheat gate allows only buffs-on-player and own-debuffs-on-target).
-- Idempotent; gated on a one-time profile stamp so users see the summary once.
-- Untouched on purpose: pandemic style keys (dormant until Blizzard fixes),
-- stored auraActive trigger clauses (retired-offer pattern), and custom-bar
-- aura entries (the later bars phases own their migration).
local function ClassifyAuraSpellUnit(spellID)
    if not (spellID and C_Spell.DoesSpellExist and C_Spell.DoesSpellExist(spellID)) then
        return nil
    end
    return C_Spell.IsSpellHarmful(spellID) and "target" or "player"
end

local function MigrateAuraEntry(self, buttonData, counts)
    -- hide-while-aura-active: LOST in 12.1 (no compliant mechanism).
    if buttonData.hideWhileAuraActive ~= nil then
        buttonData.hideWhileAuraActive = nil
        counts.hideActive = counts.hideActive + 1
    end

    -- Aura-removed sounds: no 12.1 API (gain sounds survive natively).
    local events = type(buttonData.soundAlerts) == "table"
        and type(buttonData.soundAlerts.events) == "table"
        and buttonData.soundAlerts.events or nil
    if events and events.onAuraRemoved ~= nil then
        events.onAuraRemoved = nil
        counts.lossSounds = counts.lossSounds + 1
    end

    -- Bar stack displays: plain numeric text only (pips/segments/overlays
    -- need the numeric stack value, which is secret in combat).
    local auraBar = type(buttonData.auraBar) == "table" and buttonData.auraBar or nil
    if auraBar then
        local touched = false
        local mode = auraBar.mode
        if mode == "stack" or mode == "stack_continuous" or mode == "stack_segmented" or mode == "stack_overlay" then
            auraBar.mode = "stacks"
            touched = true
        end
        if auraBar.stackDisplayMode ~= nil or auraBar.segmentGap ~= nil
            or auraBar.segmentedSmoothing ~= nil or auraBar.maxStacks ~= nil then
            auraBar.stackDisplayMode = nil
            auraBar.segmentGap = nil
            auraBar.segmentedSmoothing = nil
            auraBar.maxStacks = nil
            touched = true
        end
        if touched then
            counts.stackModes = counts.stackModes + 1
        end
    end

    -- Mixed buff/debuff candidate lists are unrepresentable (one slot, one
    -- polarity): keep the majority polarity plus unclassifiable IDs.
    local polarity = nil
    local raw = buttonData.auraSpellID and tostring(buttonData.auraSpellID) or nil
    if raw then
        local helpfulCount, harmfulCount = 0, 0
        for id in raw:gmatch("%d+") do
            local unit = ClassifyAuraSpellUnit(tonumber(id))
            if unit == "target" then
                harmfulCount = harmfulCount + 1
            elseif unit == "player" then
                helpfulCount = helpfulCount + 1
            end
        end
        if helpfulCount > 0 and harmfulCount > 0 then
            local keepUnit = harmfulCount > helpfulCount and "target" or "player"
            local rebuilt = {}
            for id in raw:gmatch("%d+") do
                local numericID = tonumber(id)
                local unit = ClassifyAuraSpellUnit(numericID)
                if numericID and (unit == nil or unit == keepUnit) then
                    rebuilt[#rebuilt + 1] = tostring(numericID)
                end
            end
            buttonData.auraSpellID = table.concat(rebuilt, ",")
            counts.mixed = counts.mixed + 1
            polarity = keepUnit
        elseif harmfulCount > 0 then
            polarity = "target"
        elseif helpfulCount > 0 then
            polarity = "player"
        end
    end
    if polarity == nil then
        polarity = ClassifyAuraSpellUnit(self:ResolveAuraSpellID(buttonData))
    end
    if polarity and buttonData.auraUnit ~= polarity then
        if buttonData.auraUnit ~= nil then
            counts.unit = counts.unit + 1
        end
        buttonData.auraUnit = polarity
    end

    -- Re-assert the standalone-entry invariants (idempotent, CDM-free).
    if buttonData.addedAs == "aura" and self.NormalizeStandaloneAuraButtonData then
        self:NormalizeStandaloneAuraButtonData(buttonData)
    end
end

local function MigrateAuraTrackingRebuild(self, profile)
    if type(profile) ~= "table" or profile._cdcAuraRebuildMigrated then return end
    local counts = { hideActive = 0, stackModes = 0, lossSounds = 0, mixed = 0, unit = 0 }
    local groups = profile.groups
    if type(groups) == "table" then
        for _, group in pairs(groups) do
            local buttons = type(group) == "table" and group.buttons or nil
            if type(buttons) == "table" then
                for _, buttonData in ipairs(buttons) do
                    if type(buttonData) == "table" and buttonData.type == "spell"
                        and (buttonData.auraTracking or buttonData.addedAs == "aura") then
                        MigrateAuraEntry(self, buttonData, counts)
                    end
                end
            end
        end
    end
    profile._cdcAuraRebuildMigrated = true
    local dropped = {}
    if counts.hideActive > 0 then dropped[#dropped + 1] = ("hide-while-aura-active (x%d)"):format(counts.hideActive) end
    if counts.stackModes > 0 then dropped[#dropped + 1] = ("bar stack segment displays (x%d)"):format(counts.stackModes) end
    if counts.lossSounds > 0 then dropped[#dropped + 1] = ("aura-removed sounds (x%d)"):format(counts.lossSounds) end
    if counts.mixed > 0 then dropped[#dropped + 1] = ("mixed buff/debuff aura lists trimmed (x%d)"):format(counts.mixed) end
    if counts.unit > 0 then dropped[#dropped + 1] = ("tracked-unit corrections (x%d)"):format(counts.unit) end
    if #dropped > 0 then
        self:Print("Aura tracking updated for 12.1. Adjusted settings with no 12.1 equivalent: "
            .. table.concat(dropped, ", ") .. ".")
    end
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
    BackfillAuraDurationSwipeSettings(self.db and self.db.profile, checkpointState and checkpointState.auraDurationSwipe)
    MigrateAuraTrackingRebuild(self, self.db and self.db.profile)
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
    -- Import hook: clear one-time stamps so imported pre-rebuild profiles
    -- re-run their passes (each pass is idempotent; re-running on migrated
    -- data changes nothing and prints nothing).
    local profile = self.db and self.db.profile
    if type(profile) == "table" then
        profile._cdcAuraRebuildMigrated = nil
    end
end

