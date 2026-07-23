--[[
    CooldownCompanion - Core/SoundAlerts.lua
    Per-button spell sound alerts (Blizzard CDM scoped): config helpers,
    CDM validity mapping, LSM sound playback/preview, runtime trigger detection.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local LSM = LibStub("LibSharedMedia-3.0")

local ipairs = ipairs
local pairs = pairs
local next = next
local type = type
local tostring = tostring
local tonumber = tonumber
local issecretvalue = issecretvalue

local function UsesChargeBehavior(buttonData)
    return CooldownCompanion.UsesChargeBehavior(buttonData)
end

local SOUND_NONE_KEY = "None"
local DEFAULT_SOUND_CHANNEL = "Master"
local BLIZZARD_SOUNDKIT_KEY_PREFIX = "__blz_soundkit:"
local BLIZZARD_TTS_KEY = "__blz_tts"

local BLIZZARD_SOUND_CATEGORY_ORDER = {
    "Instruments",
    "Animals",
    "Impacts",
    "War3",
    "War2",
    "Devices",
}

local BLIZZARD_SOUND_CATEGORY_LABELS = {
    Instruments = COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_INSTRUMENTS or "Instruments",
    Animals = COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_ANIMALS or "Animals",
    Impacts = COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_IMPACTS or "Impacts",
    War3 = COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_WAR3 or "Warcraft 3",
    War2 = COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_WAR2 or "Warcraft 2",
    Devices = COOLDOWN_VIEWER_SETTINGS_SOUND_ALERT_CATEGORY_DEVICES or "Devices",
}

local BLIZZARD_TTS_LABEL = COOLDOWN_VIEWER_SETTINGS_ALERT_LABEL_SOUND_TYPE_TEXT_TO_SPEECH or "Text to Speech"

local SOUND_ALERT_EVENT_ORDER = {
    "available",
    "onCooldown",
    "chargeGained",
}

-- Config-facing event order. onAuraApplied is config-only here: the sound is
-- played natively (C_UnitAuras.AddAuraSound, registered by AuraDisplay
-- at bind time), never by the runtime transition engine, which keeps iterating
-- SOUND_ALERT_EVENT_ORDER above.
local CONFIG_SOUND_ALERT_EVENT_ORDER = {
    "available",
    "onCooldown",
    "chargeGained",
    "onAuraApplied",
}

local SOUND_ALERT_EVENT_LABELS = {
    available = "Available",
    onCooldown = "On Cooldown",
    chargeGained = "Charge Gained",
    onAuraApplied = "Aura Applied",
}
local CHARGE_AVAILABLE_MERGED_LABEL = "Available / Charge Gained"
local TRIGGER_PANEL_SOUND_EVENT_LABELS = {
    onShow = "Triggered",
}

local SPELL_SOUND_ALERT_EVENTS = {
    available = true,
    onCooldown = true,
    chargeGained = true,
}

local EVENT_ENUM_TO_KEY = {
    [Enum.CooldownViewerAlertEventType.Available] = "available",
    [Enum.CooldownViewerAlertEventType.OnCooldown] = "onCooldown",
    [Enum.CooldownViewerAlertEventType.ChargeGained] = "chargeGained",
}

local COOLDOWN_VIEWER_CATEGORIES = {
    Enum.CooldownViewerCategory.Essential,
    Enum.CooldownViewerCategory.Utility,
    Enum.CooldownViewerCategory.TrackedBuff,
    Enum.CooldownViewerCategory.TrackedBar,
}

local function AddCooldownIDForSpell(spellToCooldownIDs, spellID, cooldownID)
    if not spellID or spellID == 0 then return end
    local entry = spellToCooldownIDs[spellID]
    if not entry then
        entry = {}
        spellToCooldownIDs[spellID] = entry
    end
    entry[cooldownID] = true
end

local function IsSpellCustomBarChargeAlertMerged(customBar)
    if type(customBar) ~= "table" or customBar.entryType ~= "spell" then
        return false
    end
    if customBar.hasCharges == true or (tonumber(customBar.maxCharges) or 0) > 1 then
        return true
    end
    local events = customBar.soundAlerts and customBar.soundAlerts.events
    return type(events) == "table" and events.chargeGained ~= nil
end

local function NormalizeSpellCustomBarAlertEvents(scopedEvents)
    if type(scopedEvents) ~= "table" then
        return scopedEvents
    end

    if scopedEvents.chargeGained then
        scopedEvents.available = true
        scopedEvents.chargeGained = nil
    end
    -- Custom bars have no aura display binding yet; the bars phases own
    -- custom-bar aura sounds.
    scopedEvents.onAuraApplied = nil
    return scopedEvents
end

local function ResolveGroup(groupOrId)
    if type(groupOrId) == "table" then
        return groupOrId
    end

    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    return profile and profile.groups and profile.groups[groupOrId] or nil
end

function CooldownCompanion:RebuildSoundAlertSpellMap()
    local spellToCooldownIDs = {}

    for _, category in ipairs(COOLDOWN_VIEWER_CATEGORIES) do
        local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(category, true)
        if cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if info then
                    AddCooldownIDForSpell(spellToCooldownIDs, info.spellID, cooldownID)
                    AddCooldownIDForSpell(spellToCooldownIDs, info.overrideSpellID, cooldownID)
                    AddCooldownIDForSpell(spellToCooldownIDs, info.overrideTooltipSpellID, cooldownID)

                    if info.linkedSpellIDs then
                        for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
                            AddCooldownIDForSpell(spellToCooldownIDs, linkedSpellID, cooldownID)
                        end
                    end

                    if info.spellID then
                        local baseSpellID = C_Spell.GetBaseSpell(info.spellID)
                        if baseSpellID and baseSpellID ~= info.spellID then
                            AddCooldownIDForSpell(spellToCooldownIDs, baseSpellID, cooldownID)
                        end
                    end
                end
            end
        end
    end

    self._soundAlertSpellToCooldownIDs = spellToCooldownIDs
    self._soundAlertValidEventTypesByCooldownID = {}
end

function CooldownCompanion:EnsureSoundAlertSpellMap()
    if not self._soundAlertSpellToCooldownIDs then
        self:RebuildSoundAlertSpellMap()
    end
end

local function ResolveCooldownIDsForSpell(spellToCooldownIDs, spellID)
    if not spellID then return nil end

    local cooldownIDs = spellToCooldownIDs[spellID]
    if cooldownIDs then return cooldownIDs end

    local baseSpellID = C_Spell.GetBaseSpell(spellID)
    if baseSpellID and baseSpellID ~= spellID then
        cooldownIDs = spellToCooldownIDs[baseSpellID]
        if cooldownIDs then return cooldownIDs end
    end

    local overrideSpellID = C_Spell.GetOverrideSpell(spellID)
    if overrideSpellID and overrideSpellID ~= 0 and overrideSpellID ~= spellID then
        cooldownIDs = spellToCooldownIDs[overrideSpellID]
        if cooldownIDs then return cooldownIDs end
    end

    return nil
end

function CooldownCompanion:GetValidSoundAlertEventsForCooldownID(cooldownID)
    local byCooldownID = self._soundAlertValidEventTypesByCooldownID
    if not byCooldownID then
        byCooldownID = {}
        self._soundAlertValidEventTypesByCooldownID = byCooldownID
    end

    local cached = byCooldownID[cooldownID]
    if cached then return cached end

    local validEvents = {}
    local validEventTypes = C_CooldownViewer.GetValidAlertTypes(cooldownID)
    if validEventTypes then
        for _, eventType in ipairs(validEventTypes) do
            local eventKey = EVENT_ENUM_TO_KEY[eventType]
            if eventKey then
                validEvents[eventKey] = true
            end
        end
    end

    byCooldownID[cooldownID] = validEvents
    return validEvents
end

function CooldownCompanion:GetValidSoundAlertEventsForButton(buttonData, spellIDOverride)
    if not buttonData or buttonData.type ~= "spell" then return nil end

    self:EnsureSoundAlertSpellMap()
    local spellToCooldownIDs = self._soundAlertSpellToCooldownIDs
    if not spellToCooldownIDs then return nil end

    local spellID = spellIDOverride or buttonData.id
    local cooldownIDs = ResolveCooldownIDsForSpell(spellToCooldownIDs, spellID)
    if not cooldownIDs then return nil end

    local validEvents = {}
    for cooldownID in pairs(cooldownIDs) do
        local perCooldownEvents = self:GetValidSoundAlertEventsForCooldownID(cooldownID)
        for eventKey in pairs(perCooldownEvents) do
            validEvents[eventKey] = true
        end
    end

    if not next(validEvents) then
        return nil
    end
    return validEvents
end

-- Returns (allowSpellEvents, allowAuraApplied); nil for non-spell entries.
-- The aura-applied sound is the one compliant aura sound event: played
-- natively via C_UnitAuras.AddAuraSound, registered by AuraDisplay
-- when the entry's aura display binds. Standalone aura entries have no cast
-- or cooldown, so it is their only event.
local function GetSoundAlertEntryScope(buttonData)
    if not buttonData or buttonData.type ~= "spell" then return nil end

    if buttonData.addedAs == "aura" then
        return false, true
    end

    return true, buttonData.auraTracking == true
end

function CooldownCompanion:GetScopedValidSoundAlertEventsForButton(buttonData, spellIDOverride)
    local allowSpellEvents, allowAuraApplied = GetSoundAlertEntryScope(buttonData)
    if allowSpellEvents == nil then
        return nil
    end

    local scopedEvents = {}
    if allowSpellEvents then
        local spellSourceID = spellIDOverride or buttonData.id
        local spellEvents = self:GetValidSoundAlertEventsForButton(buttonData, spellSourceID)
        if spellEvents then
            for eventKey in pairs(spellEvents) do
                if SPELL_SOUND_ALERT_EVENTS[eventKey] then
                    scopedEvents[eventKey] = true
                end
            end
        end
    end

    -- For charge-based spells, merge Charge Gained into Available so users
    -- configure one sound that plays for any charge gain (including max).
    if UsesChargeBehavior(buttonData) then
        if scopedEvents.chargeGained then
            scopedEvents.available = true
        end
        scopedEvents.chargeGained = nil
    end

    if allowAuraApplied then
        scopedEvents.onAuraApplied = true
    end

    if not next(scopedEvents) then
        return nil
    end
    return scopedEvents
end

function CooldownCompanion:GetScopedValidSoundAlertEventsForCustomBar(customBar)
    if type(customBar) ~= "table" or not customBar.spellID then
        return nil
    end

    local entryType = customBar.entryType or "aura"
    local scopedEvents = {}
    if entryType == "aura" then
        -- 12.1 aura teardown: aura-driven custom bars are dormant and aura
        -- sound events no longer exist.
        return nil
    elseif entryType == "spell" then
        local scoped = NormalizeSpellCustomBarAlertEvents(self:GetScopedValidSoundAlertEventsForButton({
            type = "spell",
            id = customBar.spellID,
            hasCharges = customBar.hasCharges,
            maxCharges = customBar.maxCharges,
            auraTracking = customBar.auraTracking == true,
            auraSpellID = customBar.auraSpellID,
            auraUnit = customBar.auraUnit,
        }, customBar.spellID))
        -- Stripping onAuraApplied can empty the set; keep the nil-when-none
        -- contract so the config shows its "no alertable events" label.
        if scoped and not next(scoped) then
            return nil
        end
        return scoped
    end

    if not next(scopedEvents) then
        return nil
    end
    return scopedEvents
end

function CooldownCompanion:GetButtonSoundAlertConfig(buttonData, createIfMissing)
    if not buttonData then return nil end

    local cfg = buttonData.soundAlerts
    if not cfg and createIfMissing then
        cfg = {}
        buttonData.soundAlerts = cfg
    end
    if not cfg then return nil end

    if createIfMissing and cfg.channel == nil then
        cfg.channel = DEFAULT_SOUND_CHANNEL
    end

    if createIfMissing and type(cfg.events) ~= "table" then
        cfg.events = {}
    end

    return cfg
end

function CooldownCompanion:GetCustomBarSoundAlertConfig(customBar, createIfMissing)
    if type(customBar) ~= "table" then return nil end
    local cfg = customBar.soundAlerts
    if type(cfg) ~= "table" then
        if not createIfMissing then return nil end
        cfg = {}
        customBar.soundAlerts = cfg
    end
    if createIfMissing and cfg.channel == nil then
        cfg.channel = DEFAULT_SOUND_CHANNEL
    end
    if createIfMissing and type(cfg.events) ~= "table" then
        cfg.events = {}
    end
    return cfg
end

function CooldownCompanion:GetButtonSoundAlertChannel(buttonData)
    local cfg = self:GetButtonSoundAlertConfig(buttonData, false)
    local channel = cfg and cfg.channel
    if channel and channel ~= "" then
        return channel
    end
    return DEFAULT_SOUND_CHANNEL
end

function CooldownCompanion:GetCustomBarSoundAlertChannel(customBar)
    local cfg = self:GetCustomBarSoundAlertConfig(customBar, false)
    local channel = cfg and cfg.channel
    if channel and channel ~= "" then
        return channel
    end
    return DEFAULT_SOUND_CHANNEL
end

function CooldownCompanion:GetTriggerPanelSoundAlertConfig(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" or group.displayMode ~= "trigger" then
        return nil
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings = {}
    end

    local cfg = group.triggerSettings.soundAlerts
    if not cfg and createIfMissing then
        cfg = {}
        group.triggerSettings.soundAlerts = cfg
    end

    return cfg
end

function CooldownCompanion:GetTriggerPanelSoundAlertSelection(groupOrId, eventKey)
    if TRIGGER_PANEL_SOUND_EVENT_LABELS[eventKey] == nil then
        return SOUND_NONE_KEY
    end

    local cfg = self:GetTriggerPanelSoundAlertConfig(groupOrId, false)
    local soundName = cfg and cfg[eventKey]
    return soundName or SOUND_NONE_KEY
end

function CooldownCompanion:SetTriggerPanelSoundAlertEvent(groupOrId, eventKey, soundName)
    if TRIGGER_PANEL_SOUND_EVENT_LABELS[eventKey] == nil then
        return
    end

    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" or group.displayMode ~= "trigger" then
        return
    end

    local cfg = self:GetTriggerPanelSoundAlertConfig(group, true)
    if not cfg then
        return
    end

    if not soundName or soundName == SOUND_NONE_KEY then
        cfg[eventKey] = nil
    else
        cfg[eventKey] = soundName
    end

    if not next(cfg) then
        group.triggerSettings.soundAlerts = nil
    end
end

function CooldownCompanion:GetTriggerPanelSoundAlertEventLabel(eventKey)
    return TRIGGER_PANEL_SOUND_EVENT_LABELS[eventKey] or eventKey
end

function CooldownCompanion:GetButtonSoundAlertSelection(buttonData, eventKey)
    local cfg = self:GetButtonSoundAlertConfig(buttonData, false)
    local events = cfg and cfg.events
    if events and UsesChargeBehavior(buttonData) and eventKey == "available" then
        local merged = events.available or events.chargeGained
        if merged then
            return merged
        end
    end
    if events and events[eventKey] then
        return events[eventKey]
    end
    return SOUND_NONE_KEY
end

function CooldownCompanion:GetCustomBarSoundAlertSelection(customBar, eventKey)
    local cfg = self:GetCustomBarSoundAlertConfig(customBar, false)
    local events = cfg and cfg.events
    if events and IsSpellCustomBarChargeAlertMerged(customBar) and eventKey == "available" then
        local merged = events.available or events.chargeGained
        if merged then
            return merged
        end
    end
    if events and events[eventKey] then
        return events[eventKey]
    end
    return SOUND_NONE_KEY
end

function CooldownCompanion:SetButtonSoundAlertEvent(buttonData, eventKey, soundName)
    if not SOUND_ALERT_EVENT_LABELS[eventKey] then return end

    local cfg = self:GetButtonSoundAlertConfig(buttonData, true)
    local events = cfg.events

    if UsesChargeBehavior(buttonData) and eventKey == "chargeGained" then
        eventKey = "available"
    end

    if UsesChargeBehavior(buttonData) and eventKey == "available" then
        if not soundName or soundName == SOUND_NONE_KEY then
            events.available = nil
            events.chargeGained = nil
        else
            events.available = soundName
            events.chargeGained = nil
        end
    else
        if not soundName or soundName == SOUND_NONE_KEY then
            events[eventKey] = nil
        else
            events[eventKey] = soundName
        end
    end

    if not next(events) then
        cfg.events = nil
        if (cfg.channel == nil or cfg.channel == DEFAULT_SOUND_CHANNEL) then
            buttonData.soundAlerts = nil
        end
    end
end

function CooldownCompanion:SetCustomBarSoundAlertEvent(customBar, eventKey, soundName)
    if not SOUND_ALERT_EVENT_LABELS[eventKey] then return end

    local validEvents = self:GetScopedValidSoundAlertEventsForCustomBar(customBar)
    if not (validEvents and validEvents[eventKey]) then return end

    local cfg = self:GetCustomBarSoundAlertConfig(customBar, true)
    local events = cfg.events
    if customBar.entryType == "spell" and eventKey == "chargeGained" then
        eventKey = "available"
    end

    if customBar.entryType == "spell" and eventKey == "available" then
        if not soundName or soundName == SOUND_NONE_KEY then
            events.available = nil
            events.chargeGained = nil
        else
            events.available = soundName
            events.chargeGained = nil
        end
    else
        if not soundName or soundName == SOUND_NONE_KEY then
            events[eventKey] = nil
        else
            events[eventKey] = soundName
        end
    end

    if not next(events) then
        cfg.events = nil
        if cfg.channel == nil or cfg.channel == DEFAULT_SOUND_CHANNEL then
            customBar.soundAlerts = nil
        end
    end
end

function CooldownCompanion:GetSoundAlertOptions()
    local options = { [SOUND_NONE_KEY] = SOUND_NONE_KEY }

    local soundData = _G.CooldownViewerSoundData
    if type(soundData) == "table" then
        local function AddBlizzardCategory(categoryKey)
            local categoryData = soundData[categoryKey]
            if type(categoryData) ~= "table" then return end

            local categoryText = BLIZZARD_SOUND_CATEGORY_LABELS[categoryKey] or categoryKey
            for _, soundEntry in ipairs(categoryData) do
                if type(soundEntry) == "table" and soundEntry.soundKitID and soundEntry.text then
                    local optionKey = BLIZZARD_SOUNDKIT_KEY_PREFIX .. tostring(soundEntry.soundKitID)
                    options[optionKey] = ("%s - %s"):format(categoryText, soundEntry.text)
                end
            end
        end

        for _, categoryKey in ipairs(BLIZZARD_SOUND_CATEGORY_ORDER) do
            AddBlizzardCategory(categoryKey)
        end

        for categoryKey, _ in pairs(soundData) do
            local alreadyOrdered = false
            for _, orderedCategory in ipairs(BLIZZARD_SOUND_CATEGORY_ORDER) do
                if orderedCategory == categoryKey then
                    alreadyOrdered = true
                    break
                end
            end
            if not alreadyOrdered then
                AddBlizzardCategory(categoryKey)
            end
        end

        options[BLIZZARD_TTS_KEY] = BLIZZARD_TTS_LABEL
    end

    for _, soundName in ipairs(LSM:List("sound")) do
        local soundSource = LSM:Fetch("sound", soundName, true)
        if (type(soundSource) == "string" and soundSource ~= "") or type(soundSource) == "number" then
            options[soundName] = soundName
        end
    end
    return options
end

function CooldownCompanion:GetSoundAlertEventOrder()
    return CONFIG_SOUND_ALERT_EVENT_ORDER
end

function CooldownCompanion:GetSoundAlertEventLabel(eventKey)
    return SOUND_ALERT_EVENT_LABELS[eventKey] or eventKey
end

function CooldownCompanion:GetSoundAlertEventLabelForButton(buttonData, eventKey)
    if UsesChargeBehavior(buttonData) and eventKey == "available" then
        return CHARGE_AVAILABLE_MERGED_LABEL
    end
    return self:GetSoundAlertEventLabel(eventKey)
end

function CooldownCompanion:GetCustomBarSoundAlertEventLabel(customBar, eventKey)
    if IsSpellCustomBarChargeAlertMerged(customBar) and eventKey == "available" then
        return CHARGE_AVAILABLE_MERGED_LABEL
    end
    return self:GetSoundAlertEventLabel(eventKey)
end

local function ParseBlizzardSoundSelection(soundName)
    if type(soundName) ~= "string" then
        return nil, nil
    end

    if soundName == BLIZZARD_TTS_KEY then
        return "tts", true
    end

    local soundKitID = tonumber(soundName:match("^" .. BLIZZARD_SOUNDKIT_KEY_PREFIX:gsub("%p", "%%%0") .. "(%d+)$"))
    if soundKitID then
        return "soundkit", soundKitID
    end

    return nil, nil
end

local function GetButtonSpeechText(buttonData)
    if buttonData and buttonData.type == "spell" and buttonData.id then
        local spellInfo = C_Spell.GetSpellInfo(buttonData.id)
        if spellInfo and spellInfo.name then
            return spellInfo.name
        end
    end
    return "Cooldown alert"
end

local function GetCustomBarSpeechText(customBar)
    if type(customBar) == "table" then
        local spellID = tonumber(customBar.spellID)
        if spellID then
            local spellInfo = C_Spell.GetSpellInfo(spellID)
            if spellInfo and spellInfo.name then
                return spellInfo.name
            end
        end
        if type(customBar.label) == "string" and customBar.label ~= "" then
            return customBar.label
        end
    end
    return "Custom bar alert"
end

local function GetTriggerPanelSpeechText(group)
    if type(group) == "table" and type(group.name) == "string" and group.name ~= "" then
        return group.name
    end
    return "Trigger alert"
end

local function PlaySharedMediaSound(soundName, channel, speechText)
    if not soundName or soundName == SOUND_NONE_KEY then return false end

    local sourceType, sourceValue = ParseBlizzardSoundSelection(soundName)
    if sourceType == "soundkit" then
        local willPlay = PlaySound(sourceValue, channel or DEFAULT_SOUND_CHANNEL)
        return willPlay and true or false
    elseif sourceType == "tts" then
        if type(TextToSpeechFrame_PlayCooldownAlertMessage) == "function" then
            TextToSpeechFrame_PlayCooldownAlertMessage(nil, speechText or "Cooldown alert", true)
            return true
        end
        return false
    end

    local soundSource = LSM:Fetch("sound", soundName)
    if not soundSource or soundSource == 1 then
        return false
    end

    if type(soundSource) == "number" then
        -- Numeric LSM registrations can represent SoundKit IDs.
        local willPlayKit = PlaySound(soundSource, channel or DEFAULT_SOUND_CHANNEL)
        if willPlayKit then
            return true
        end
    end

    local willPlayFile = PlaySoundFile(soundSource, channel or DEFAULT_SOUND_CHANNEL)
    return willPlayFile and true or false
end

function CooldownCompanion:PreviewSoundAlertSelection(buttonData, soundName)
    return PlaySharedMediaSound(soundName, self:GetButtonSoundAlertChannel(buttonData), GetButtonSpeechText(buttonData))
end

-- Options list for the aura-applied event. C_UnitAuras.AddAuraSound
-- plays sound FILES, so only shared-media sounds that resolve to a file path
-- are offered; Blizzard soundkit and text-to-speech selections have no file
-- form (numeric registrations are excluded as ambiguous — CC treats them as
-- SoundKit IDs in PlaySharedMediaSound).
function CooldownCompanion:GetAuraAppliedSoundAlertOptions()
    local options = { [SOUND_NONE_KEY] = SOUND_NONE_KEY }
    for _, soundName in ipairs(LSM:List("sound")) do
        local soundSource = LSM:Fetch("sound", soundName, true)
        if type(soundSource) == "string" and soundSource ~= "" then
            options[soundName] = soundName
        end
    end
    return options
end

-- Resolve the entry's configured aura-applied sound to what
-- C_UnitAuras.AddAuraSound accepts. Returns (soundFileName, channel)
-- or nil when unset or not file-backed.
function CooldownCompanion:GetAuraAppliedSoundFileForButton(buttonData)
    local cfg = self:GetButtonSoundAlertConfig(buttonData, false)
    local soundName = cfg and cfg.events and cfg.events.onAuraApplied
    if not soundName or soundName == SOUND_NONE_KEY then return nil end
    if ParseBlizzardSoundSelection(soundName) then return nil end

    local soundSource = LSM:Fetch("sound", soundName)
    if type(soundSource) == "string" and soundSource ~= "" then
        return soundSource, self:GetButtonSoundAlertChannel(buttonData)
    end
    return nil
end

function CooldownCompanion:PreviewTriggerPanelSoundAlertSelection(groupOrId, soundName)
    local group = ResolveGroup(groupOrId)
    return PlaySharedMediaSound(soundName, DEFAULT_SOUND_CHANNEL, GetTriggerPanelSpeechText(group))
end

function CooldownCompanion:PlayButtonSoundAlertEvent(buttonData, eventKey)
    if UsesChargeBehavior(buttonData) and eventKey == "chargeGained" then
        eventKey = "available"
    end

    local cfg = self:GetButtonSoundAlertConfig(buttonData, false)
    local soundName = cfg and cfg.events and cfg.events[eventKey]
    if (not soundName) and UsesChargeBehavior(buttonData) and eventKey == "available" then
        soundName = cfg and cfg.events and cfg.events.chargeGained
    end
    if not soundName then return false end

    return PlaySharedMediaSound(soundName, self:GetButtonSoundAlertChannel(buttonData), GetButtonSpeechText(buttonData))
end

function CooldownCompanion:PlayCustomBarSoundAlertEvent(customBar, eventKey)
    if customBar and customBar.entryType == "spell" and eventKey == "chargeGained" then
        eventKey = "available"
    end
    local cfg = self:GetCustomBarSoundAlertConfig(customBar, false)
    local soundName = cfg and cfg.events and cfg.events[eventKey]
    if (not soundName) and customBar and customBar.entryType == "spell" and eventKey == "available" then
        soundName = cfg and cfg.events and cfg.events.chargeGained
    end
    if not soundName or soundName == SOUND_NONE_KEY then return false end

    return PlaySharedMediaSound(soundName, self:GetCustomBarSoundAlertChannel(customBar), GetCustomBarSpeechText(customBar))
end

function CooldownCompanion:PlayTriggerPanelSoundAlertEvent(groupOrId, eventKey)
    if TRIGGER_PANEL_SOUND_EVENT_LABELS[eventKey] == nil then
        return false
    end

    local group = ResolveGroup(groupOrId)
    local soundName = self:GetTriggerPanelSoundAlertSelection(group, eventKey)
    if not soundName or soundName == SOUND_NONE_KEY then
        return false
    end

    return PlaySharedMediaSound(soundName, DEFAULT_SOUND_CHANNEL, GetTriggerPanelSpeechText(group))
end

local function CollectEnabledSoundAlertEvents(events, validEvents, mergeChargeEvents)
    local enabledEvents = {}
    for _, eventKey in ipairs(SOUND_ALERT_EVENT_ORDER) do
        if not (mergeChargeEvents and eventKey == "chargeGained") then
            local soundName = events[eventKey]
            if mergeChargeEvents and eventKey == "available" and not soundName then
                soundName = events.chargeGained
            end
            if validEvents[eventKey] and soundName and soundName ~= SOUND_NONE_KEY then
                enabledEvents[eventKey] = true
            end
        end
    end

    if not next(enabledEvents) then
        return nil
    end
    return enabledEvents
end

function CooldownCompanion:GetEnabledSoundAlertEventsForButton(buttonData, spellIDOverride)
    local cfg = self:GetButtonSoundAlertConfig(buttonData, false)
    if not cfg or type(cfg.events) ~= "table" then
        return nil
    end

    local validEvents = self:GetScopedValidSoundAlertEventsForButton(buttonData, spellIDOverride)
    if not validEvents then
        return nil
    end

    return CollectEnabledSoundAlertEvents(cfg.events, validEvents, UsesChargeBehavior(buttonData))
end

function CooldownCompanion:GetEnabledSoundAlertEventsForCustomBar(customBar)
    local cfg = self:GetCustomBarSoundAlertConfig(customBar, false)
    if not cfg or type(cfg.events) ~= "table" then
        return nil
    end

    local validEvents = self:GetScopedValidSoundAlertEventsForCustomBar(customBar)
    if not validEvents then
        return nil
    end

    return CollectEnabledSoundAlertEvents(cfg.events, validEvents, IsSpellCustomBarChargeAlertMerged(customBar))
end

local function DidGainChargeSincePreviousState(state, cooldownActive, currentCharges, chargeRecharging, chargeCooldownStartTime)
    if currentCharges and state._sndPrevCharges and currentCharges > state._sndPrevCharges then
        return true
    end
    if chargeRecharging and state._sndPrevChargeRecharging
       and chargeCooldownStartTime and state._sndPrevChargeCooldownStart
       and chargeCooldownStartTime > state._sndPrevChargeCooldownStart then
        return true
    end
    if (not chargeRecharging) and state._sndPrevChargeRecharging then
        return true
    end
    if state._sndPrevCooldownActive and not cooldownActive
       and state._sndPrevChargeRecharging then
        -- Fallback for charge spells where readable counts/timestamps are
        -- unavailable: only treat cooldown edge as a gain if we were already
        -- in a charge-recharging state.
        return true
    end
    return false
end

local function PlayCustomBarTransitionSound(customBar, eventKey)
    CooldownCompanion:PlayCustomBarSoundAlertEvent(customBar, eventKey)
end

local function PlayButtonTransitionSound(buttonData, eventKey)
    CooldownCompanion:PlayButtonSoundAlertEvent(buttonData, eventKey)
end

local function UpdateCooldownSoundAlertTransitions(state, enabledEvents, opts)
    local cooldownActive = opts.cooldownActive and true or false
    local auraActive = opts.auraActive and true or false
    local chargeRecharging = opts.chargeRecharging and true or false
    local currentCharges = opts.currentCharges
    local chargeCooldownStartTime = opts.chargeCooldownStartTime

    if not state._sndInitialized then
        state._sndInitialized = true
        state._sndPrevCooldownActive = cooldownActive
        if opts.includeAuraEvents then
            state._sndPrevAuraActive = auraActive
        end
        state._sndPrevCharges = currentCharges
        state._sndPrevChargeRecharging = chargeRecharging
        state._sndPrevChargeCooldownStart = chargeCooldownStartTime
        return
    end

    if opts.includeAuraEvents then
        if enabledEvents.onAuraApplied and auraActive and not state._sndPrevAuraActive then
            opts.play(opts.playContext, "onAuraApplied")
        end

        if enabledEvents.onAuraRemoved and state._sndPrevAuraActive and not auraActive then
            opts.play(opts.playContext, "onAuraRemoved")
        end
    end

    if enabledEvents.onCooldown and cooldownActive and not state._sndPrevCooldownActive then
        opts.play(opts.playContext, "onCooldown")
    end

    if enabledEvents.available then
        if opts.usesChargeBehavior then
            if DidGainChargeSincePreviousState(state, cooldownActive, currentCharges, chargeRecharging, chargeCooldownStartTime) then
                opts.play(opts.playContext, "available")
            end
        elseif state._sndPrevCooldownActive and not cooldownActive then
            opts.play(opts.playContext, "available")
        end
    end

    state._sndPrevCooldownActive = cooldownActive
    if opts.includeAuraEvents then
        state._sndPrevAuraActive = auraActive
    end
    state._sndPrevChargeRecharging = chargeRecharging
    if currentCharges ~= nil then
        state._sndPrevCharges = currentCharges
    end
    if chargeCooldownStartTime ~= nil then
        state._sndPrevChargeCooldownStart = chargeCooldownStartTime
    end
end

-- cooldownResult is a reused evaluation scratch: copy scalar fields only and
-- never store the table or read it after this call returns.
function CooldownCompanion:UpdateCustomBarSoundAlerts(barInfo, auraActive, cooldownActive, cooldownResult)
    local customBar = barInfo and barInfo.cabConfig
    local enabledEvents = self:GetEnabledSoundAlertEventsForCustomBar(customBar)
    if not enabledEvents then
        if barInfo then
            barInfo._sndInitialized = nil
        end
        return
    end

    if customBar and customBar.entryType == "spell" then
        local chargeRecharging = cooldownResult and cooldownResult.chargeRecharging == true
        local currentCharges = cooldownResult and cooldownResult.currentCharges
        local chargeCooldownStartTime
        local charges = cooldownResult and cooldownResult.charges
        if charges and charges.cooldownStartTime ~= nil and not issecretvalue(charges.cooldownStartTime) then
            chargeCooldownStartTime = charges.cooldownStartTime
        end

        local opts = barInfo._sndTransitionOptions
        if not opts then
            opts = {}
            barInfo._sndTransitionOptions = opts
        end
        opts.cooldownActive = cooldownActive
        opts.auraActive = auraActive
        opts.currentCharges = currentCharges
        opts.chargeRecharging = chargeRecharging
        opts.chargeCooldownStartTime = chargeCooldownStartTime
        opts.includeAuraEvents = customBar.auraTracking == true
        opts.usesChargeBehavior = cooldownResult and cooldownResult.hasCharges == true
        opts.play = PlayCustomBarTransitionSound
        opts.playContext = customBar
        UpdateCooldownSoundAlertTransitions(barInfo, enabledEvents, opts)
        return
    end

    local opts = barInfo._sndTransitionOptions
    if not opts then
        opts = {}
        barInfo._sndTransitionOptions = opts
    end
    opts.cooldownActive = nil
    opts.auraActive = auraActive
    opts.currentCharges = nil
    opts.chargeRecharging = nil
    opts.chargeCooldownStartTime = nil
    opts.includeAuraEvents = true
    opts.usesChargeBehavior = nil
    opts.play = PlayCustomBarTransitionSound
    opts.playContext = customBar
    UpdateCooldownSoundAlertTransitions(barInfo, enabledEvents, opts)
end

function CooldownCompanion:UpdateButtonSoundAlerts(button, cooldownSpellID, _isOnGCD, cooldownActive, auraActive, currentCharges, _maxCharges, chargeRecharging, chargeCooldownStartTime)
    local buttonData = button and button.buttonData
    if not buttonData or buttonData.type ~= "spell" then return end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if group and group.displayMode == "trigger" then
        button._sndInitialized = nil
        return
    end

    local enabledEvents = self:GetEnabledSoundAlertEventsForButton(buttonData, cooldownSpellID)
    if not enabledEvents and cooldownSpellID and cooldownSpellID ~= buttonData.id then
        enabledEvents = self:GetEnabledSoundAlertEventsForButton(buttonData, buttonData.id)
    end
    if not enabledEvents then
        button._sndInitialized = nil
        return
    end

    local opts = button._sndTransitionOptions
    if not opts then
        opts = {}
        button._sndTransitionOptions = opts
    end
    opts.cooldownActive = cooldownActive
    opts.auraActive = auraActive
    opts.currentCharges = currentCharges
    opts.chargeRecharging = chargeRecharging
    opts.chargeCooldownStartTime = chargeCooldownStartTime
    opts.includeAuraEvents = true
    opts.usesChargeBehavior = UsesChargeBehavior(buttonData)
    opts.play = PlayButtonTransitionSound
    opts.playContext = buttonData
    UpdateCooldownSoundAlertTransitions(button, enabledEvents, opts)
end

function CooldownCompanion:UpdateTriggerPanelSoundAlerts(frame, group, triggerMatched)
    if not frame or type(group) ~= "table" or group.displayMode ~= "trigger" then
        return
    end

    triggerMatched = triggerMatched == true

    if not frame._triggerSoundInitialized then
        frame._triggerSoundInitialized = true
        frame._triggerSoundWasVisible = triggerMatched
        return
    end

    if triggerMatched and not frame._triggerSoundWasVisible then
        self:PlayTriggerPanelSoundAlertEvent(group, "onShow")
    end

    frame._triggerSoundWasVisible = triggerMatched
end
