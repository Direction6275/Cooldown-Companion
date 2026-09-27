-- Rotation Assistant is an ordinary saved entry with a separate spell view.
-- Recommendation state belongs to runtime frames, never to SavedVariables.
local _, ST = ...
local CooldownCompanion = ST.Addon

function ST.GetConfiguredButtonData(buttonData)
    return buttonData and (rawget(buttonData, "_rotationAssistantEntry") or buttonData)
end

function CooldownCompanion:CreateRotationAssistantEntry(settings)
    local entry = settings and CopyTable(settings) or {}
    -- The legacy config lens wrote temporary spell data into its settings.
    for key in pairs(entry) do
        if type(key) == "string" and key:sub(1, 1) == "_" then entry[key] = nil end
    end
    entry.type, entry.rotationAssistant = "spell", true
    entry.id, entry.name = ST.ROTATION_ASSISTANT_ACTION_SPELL_ID, ST.ROTATION_ASSISTANT_NAME
    entry.addedAs = "spell"
    entry.manualIcon, entry.displayAs, entry.barPlacement = nil, nil, nil
    entry.auraTracking, entry.isPassive, entry.hasCharges, entry.maxCharges = nil, nil, nil, nil
    return entry
end

function CooldownCompanion:IsRotationAssistantActionSpell(spellID)
    return type(spellID) == "number" and not issecretvalue(spellID)
        and (spellID == ST.ROTATION_ASSISTANT_ACTION_SPELL_ID
            or spellID == self:GetRotationAssistantActionSpellID())
end

function CooldownCompanion:GetRotationAssistantRuntimeData(frame, entry)
    local records = frame._rotationAssistantEntries
    if not records then records = {}; frame._rotationAssistantEntries = records end
    local record = records[entry]
    if not record then
        record = setmetatable({
            _rotationAssistantEntry = entry,
            _rotationAssistantVirtual = true,
            _rotationAssistantMissing = true,
            id = entry.id, name = entry.name,
        }, { __index = entry })
        records[entry] = record
    end
    return record
end

function CooldownCompanion:AddRotationAssistantEntry(groupId, options)
    options = options or {}
    local group = self.db.profile.groups[groupId]
    if not group then return nil end
    local entry = self:CreateRotationAssistantEntry()
    local reason = self:GetPanelManualEntryRejectMessage(group, entry)
        or (options.section and ST.IsAuraOnlyPanelSection(group, options.section)
            and self:GetAuraSectionEntryRejectMessage(group, options.section, entry))
    if reason then self:Print(reason); return nil end
    local index = #group.buttons + 1
    group.buttons[index] = entry
    if options.section then ST.SetPanelSectionForEntry(group, entry, options.section) end
    self:KeepPanelSingleLineOnGrowth(group, index - 1)
    self:RefreshGroupFrame(groupId)
    return index
end

-- Idempotent ingress conversion. Keep IDs and all panel-owned settings intact.
local function ConvertPanel(group)
    if type(group) ~= "table" or group.displayMode ~= "rotationAssistant" then return end
    group.displayMode = "icons"
    if not group.templateVersion then
        group.buttons = { CooldownCompanion:CreateRotationAssistantEntry(group.rotationAssistantEntry) }
    end
    group.rotationAssistantEntry = nil
end

function CooldownCompanion:MigrateRotationAssistantPanels(profile)
    for _, group in pairs(profile and profile.groups or {}) do ConvertPanel(group) end
end

function ST.ConvertRotationAssistantImport(data)
    if type(data) ~= "table" then return data end
    local candidate = CopyTable(data)
    local function Visit(value)
        if type(value) ~= "table" then return end
        ConvertPanel(value)
        for key, child in pairs(value) do
            if type(key) ~= "string" or key:sub(1, 1) ~= "_" then Visit(child) end
        end
    end
    Visit(candidate)
    return candidate
end

function CooldownCompanion:GetRotationAssistantActionSpellID()
    local assistedCombat = C_AssistedCombat
    if assistedCombat and assistedCombat.GetActionSpell then
        local spellID = assistedCombat.GetActionSpell()
        if type(spellID) == "number" and not issecretvalue(spellID) and spellID > 0 then
            return spellID
        end
    end
    return ST.ROTATION_ASSISTANT_ACTION_SPELL_ID
end

function CooldownCompanion:GetRotationAssistantFallbackIcon(spellID)
    spellID = spellID or self:GetRotationAssistantActionSpellID()
    if spellID and C_Spell and C_Spell.GetSpellTexture then
        local icon = C_Spell.GetSpellTexture(spellID)
        if icon and not issecretvalue(icon) then
            return icon
        end
    end
    return ST.ROTATION_ASSISTANT_FALLBACK_ICON
end

function CooldownCompanion:GetRotationAssistantRecommendationSpellID()
    local assistedCombat = C_AssistedCombat
    if not (assistedCombat and assistedCombat.GetNextCastSpell) then
        self._rotationAssistantAvailable = false
        self._rotationAssistantUnavailableReason = "apiUnavailable"
        return nil
    end

    if assistedCombat.IsAvailable then
        local available, reason = assistedCombat.IsAvailable()
        self._rotationAssistantAvailable = available == true
        self._rotationAssistantUnavailableReason = reason
        if available ~= true then
            return nil
        end
    else
        self._rotationAssistantAvailable = true
        self._rotationAssistantUnavailableReason = nil
    end

    local spellID = assistedCombat.GetNextCastSpell(false)
    if type(spellID) == "number" and not issecretvalue(spellID) and spellID > 0 then
        return spellID
    end
    return nil
end

function CooldownCompanion:ClearRotationAssistantButtonRuntime(button)
    if not button then return end
    button._chargesSpent = nil
    button._zeroChargesConfirmed = nil
    button._nilConfirmPending = nil
    button._chargeState = nil
    button._chargeRecharging = nil
    button._chargeCooldownVisualActive = nil
    button._chargeRenderCount = nil
    button._currentReadableCharges = nil
    button._chargeCountReadable = nil
    button._sndInitialized = nil
    button._bindingKeyInfos = nil
    button._displaySpellId = nil
    button._liveOverrideSpellId = nil
    button._lastSpellTexture = nil
    button._lastTextureCheckAt = nil
    button._baseNoCooldown = nil
    button._baseNoCooldownSpellId = nil
    button._noCooldown = nil
    button._noCooldownSpellId = nil
    button._resourceGateCost = nil
    button._resourceGateCostSpellId = nil
    button._baseResourceGateCost = nil
    button._baseResourceGateCostSpellId = nil
    button._spellOutOfRange = nil
    button._auraActive = false
    button._procOverlayActive = false
end

function CooldownCompanion:RefreshRotationAssistantButton(button)
    local buttonData = button and button.buttonData
    if not self:IsRotationAssistantButtonData(buttonData)
        or not rawget(buttonData, "_rotationAssistantEntry") then
        return false
    end

    local recommendedSpellID = self:GetRotationAssistantRecommendationSpellID()
    local missing = recommendedSpellID == nil
    local displaySpellID = recommendedSpellID or self:GetRotationAssistantActionSpellID()
    local changed = buttonData.id ~= displaySpellID
        or buttonData._rotationAssistantSpellID ~= recommendedSpellID
        or buttonData._rotationAssistantMissing ~= missing

    if changed then
        buttonData.hasCharges, buttonData.maxCharges = nil, nil
        buttonData._hasDisplayCount, buttonData._displayCountFamily = nil, nil
        buttonData._castCountCandidate, buttonData._castCountSelf, buttonData._castCountEventSpellID = nil, nil, nil
    end

    buttonData.id = displaySpellID
    buttonData._rotationAssistantSpellID = recommendedSpellID
    buttonData._rotationAssistantMissing = missing
    buttonData.name = recommendedSpellID and C_Spell.GetSpellName(recommendedSpellID) or ST.ROTATION_ASSISTANT_NAME
    if self.UpdateSpellChargeMetadata then
        self:UpdateSpellChargeMetadata(buttonData, displaySpellID, {
            clearInactiveMaxCharges = true,
        })
    end
    button._rotationAssistantSpellID = recommendedSpellID

    if changed then
        self:ClearRotationAssistantButtonRuntime(button)
        if self.UpdateButtonIcon then
            self:UpdateButtonIcon(button)
        end
        if self.RefreshResolvedItemKeybindState then
            self:RefreshResolvedItemKeybindState(button, buttonData)
        end
        if self.RequestRangeCheckRegistrationRefresh then
            self:RequestRangeCheckRegistrationRefresh()
        end
    end

    return changed
end
