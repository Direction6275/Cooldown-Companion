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
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior

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
    "onAuraApplied",
    "onAuraRemoved",
}

local SOUND_ALERT_EVENT_LABELS = {
    available = "Available",
    onCooldown = "On Cooldown",
    chargeGained = "Charge Gained",
    onAuraApplied = "On Aura Applied",
    onAuraRemoved = "On Aura Removed",
}
local CHARGE_AVAILABLE_MERGED_LABEL = "Available / Charge Gained"

local SPELL_SOUND_ALERT_EVENTS = {
    available = true,
    onCooldown = true,
    chargeGained = true,
}

local AURA_SOUND_ALERT_EVENTS = {
    onAuraApplied = true,
    onAuraRemoved = true,
}

local EVENT_ENUM_TO_KEY = {
    [Enum.CooldownViewerAlertEventType.Available] = "available",
    [Enum.CooldownViewerAlertEventType.OnCooldown] = "onCooldown",
    [Enum.CooldownViewerAlertEventType.ChargeGained] = "chargeGained",
    [Enum.CooldownViewerAlertEventType.OnAuraApplied] = "onAuraApplied",
    [Enum.CooldownViewerAlertEventType.OnAuraRemoved] = "onAuraRemoved",
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

local function GetSoundAlertEntryScope(buttonData)
    if not buttonData or buttonData.type ~= "spell" then return nil, nil end

    if buttonData.addedAs == "aura" then
        if buttonData.auraTracking then
            return false, true
        end
        return nil, nil
    end

    if buttonData.auraTracking then
        return true, true
    end

    return true, false
end

local function AddUniqueSpellID(dest, seen, spellID)
    if not spellID or spellID == 0 then return end
    if seen[spellID] then return end
    seen[spellID] = true
    dest[#dest + 1] = spellID
end

local function BuildAuraSourceSpellIDs(self, buttonData, spellIDOverride)
    local spellIDs = {}
    local seen = {}

    if buttonData and buttonData.auraSpellID then
        for id in tostring(buttonData.auraSpellID):gmatch("%d+") do
            AddUniqueSpellID(spellIDs, seen, tonumber(id))
        end
    end

    if buttonData and buttonData.type == "spell" then
        local auraID = C_UnitAuras.GetCooldownAuraBySpellID(buttonData.id)
        AddUniqueSpellID(spellIDs, seen, auraID)
        AddUniqueSpellID(spellIDs, seen, buttonData.id)

        local overrideBuffs = self.ABILITY_BUFF_OVERRIDES and self.ABILITY_BUFF_OVERRIDES[buttonData.id]
        if overrideBuffs then
            for id in tostring(overrideBuffs):gmatch("%d+") do
                AddUniqueSpellID(spellIDs, seen, tonumber(id))
            end
        end
    end

    if spellIDOverride and buttonData and buttonData.type == "spell" then
        local overrideAuraID = C_UnitAuras.GetCooldownAuraBySpellID(spellIDOverride)
        AddUniqueSpellID(spellIDs, seen, overrideAuraID)
        AddUniqueSpellID(spellIDs, seen, spellIDOverride)
    end

    return spellIDs
end

function CooldownCompanion:GetScopedValidSoundAlertEventsForButton(buttonData, spellIDOverride)
    local allowSpellEvents, allowAuraEvents = GetSoundAlertEntryScope(buttonData)
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

    if allowAuraEvents then
        local auraSourceSpellIDs = BuildAuraSourceSpellIDs(self, buttonData, spellIDOverride)
        for _, auraSourceSpellID in ipairs(auraSourceSpellIDs) do
            local auraEvents = self:GetValidSoundAlertEventsForButton(buttonData, auraSourceSpellID)
            if auraEvents then
                for eventKey in pairs(auraEvents) do
                    if AURA_SOUND_ALERT_EVENTS[eventKey] then
                        scopedEvents[eventKey] = true
                    end
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

function CooldownCompanion:GetButtonSoundAlertChannel(buttonData)
    local cfg = self:GetButtonSoundAlertConfig(buttonData, false)
    local channel = cfg and cfg.channel
    if channel and channel ~= "" then
        return channel
    end
    return DEFAULT_SOUND_CHANNEL
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
    return SOUND_ALERT_EVENT_ORDER
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

function CooldownCompanion:GetEnabledSoundAlertEventsForButton(buttonData, spellIDOverride)
    local cfg = self:GetButtonSoundAlertConfig(buttonData, false)
    if not cfg or type(cfg.events) ~= "table" then
        return nil
    end

    local validEvents = self:GetScopedValidSoundAlertEventsForButton(buttonData, spellIDOverride)
    if not validEvents then
        return nil
    end

    local enabledEvents = {}
    for _, eventKey in ipairs(SOUND_ALERT_EVENT_ORDER) do
        if not (UsesChargeBehavior(buttonData) and eventKey == "chargeGained") then
            local soundName = cfg.events[eventKey]
            if UsesChargeBehavior(buttonData) and eventKey == "available" and not soundName then
                soundName = cfg.events.chargeGained
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

function CooldownCompanion:UpdateButtonSoundAlerts(button, cooldownSpellID, _isOnGCD, cooldownActive, auraActive, currentCharges, _maxCharges, chargeRecharging, chargeCooldownStartTime)
    local buttonData = button and button.buttonData
    if not buttonData or buttonData.type ~= "spell" then return end

    local enabledEvents = self:GetEnabledSoundAlertEventsForButton(buttonData, cooldownSpellID)
    if not enabledEvents and cooldownSpellID and cooldownSpellID ~= buttonData.id then
        enabledEvents = self:GetEnabledSoundAlertEventsForButton(buttonData, buttonData.id)
    end
    if not enabledEvents then
        button._sndInitialized = nil
        return
    end

    cooldownActive = cooldownActive and true or false
    auraActive = auraActive and true or false
    chargeRecharging = chargeRecharging and true or false

    if not button._sndInitialized then
        button._sndInitialized = true
        button._sndPrevCooldownActive = cooldownActive
        button._sndPrevAuraActive = auraActive
        button._sndPrevCharges = currentCharges
        button._sndPrevChargeRecharging = chargeRecharging
        button._sndPrevChargeCooldownStart = chargeCooldownStartTime
        return
    end

    if enabledEvents.onAuraApplied and auraActive and not button._sndPrevAuraActive then
        self:PlayButtonSoundAlertEvent(buttonData, "onAuraApplied")
    end

    if enabledEvents.onAuraRemoved and button._sndPrevAuraActive and not auraActive then
        self:PlayButtonSoundAlertEvent(buttonData, "onAuraRemoved")
    end

    if enabledEvents.onCooldown and cooldownActive and not button._sndPrevCooldownActive then
        self:PlayButtonSoundAlertEvent(buttonData, "onCooldown")
    end

    if enabledEvents.available then
        if UsesChargeBehavior(buttonData) then
            local gainedCharge = false
            if currentCharges and button._sndPrevCharges and currentCharges > button._sndPrevCharges then
                gainedCharge = true
            elseif chargeRecharging and button._sndPrevChargeRecharging
               and chargeCooldownStartTime and button._sndPrevChargeCooldownStart
               and chargeCooldownStartTime > button._sndPrevChargeCooldownStart then
                gainedCharge = true
            elseif (not chargeRecharging) and button._sndPrevChargeRecharging then
                gainedCharge = true
            elseif button._sndPrevCooldownActive and not cooldownActive
               and button._sndPrevChargeRecharging then
                -- Fallback for charge spells where readable counts/timestamps are
                -- unavailable: only treat cooldown edge as a gain if we were
                -- already in a charge-recharging state.
                gainedCharge = true
            end

            if gainedCharge then
                self:PlayButtonSoundAlertEvent(buttonData, "available")
            end
        elseif (not UsesChargeBehavior(buttonData)) and button._sndPrevCooldownActive and not cooldownActive then
            self:PlayButtonSoundAlertEvent(buttonData, "available")
        end
    end

    button._sndPrevCooldownActive = cooldownActive
    button._sndPrevAuraActive = auraActive
    button._sndPrevChargeRecharging = chargeRecharging
    if currentCharges ~= nil then
        button._sndPrevCharges = currentCharges
    end
    if chargeCooldownStartTime ~= nil then
        button._sndPrevChargeCooldownStart = chargeCooldownStartTime
    end
end
