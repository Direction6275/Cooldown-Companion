--[[
    CooldownCompanion - Core/Aura.lua: Aura event handlers (OnUnitAura, ClearAuraUnit,
    OnTargetChanged), aura resolution, ABILITY_BUFF_OVERRIDES, CDM viewer system
    (ApplyCdmAlpha, BuildViewerAuraMap, FindViewerChildForSpell, FindCooldownViewerChild,
    OnViewerSpellOverrideUpdated)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon


local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local tostring = tostring
local tonumber = tonumber

-- Import cross-file variables (viewer system)
local VIEWER_NAMES = ST._VIEWER_NAMES
local COOLDOWN_VIEWER_NAMES = ST._COOLDOWN_VIEWER_NAMES
local BUFF_VIEWER_SET = ST._BUFF_VIEWER_SET
local cdmAlphaGuard = ST._cdmAlphaGuard
local pendingViewerAuraMapToken = 0
local FindChildInViewers
local TRACKED_AURA_CATEGORIES = {
    Enum.CooldownViewerCategory.TrackedBuff,
    Enum.CooldownViewerCategory.TrackedBar,
}
local COOLDOWN_VIEWER_ASSOCIATION_CATEGORIES = {
    Enum.CooldownViewerCategory.Essential,
    Enum.CooldownViewerCategory.Utility,
    Enum.CooldownViewerCategory.TrackedBuff,
    Enum.CooldownViewerCategory.TrackedBar,
}

local function IsBuffViewerChild(frame)
    if not frame then return false end
    local parent = frame:GetParent()
    local parentName = parent and parent:GetName()
    return BUFF_VIEWER_SET[parentName] == true
end

local function AddAuraCandidateID(candidateSet, spellID)
    local numericID = tonumber(spellID)
    if numericID and numericID ~= 0 then
        candidateSet[numericID] = true
    end
end

local function AddAuraCandidateIDsFromString(candidateSet, rawIDs)
    if not rawIDs then
        return
    end
    for id in tostring(rawIDs):gmatch("%d+") do
        AddAuraCandidateID(candidateSet, id)
    end
end

local function AppendOrderedAuraCandidateID(candidateSet, orderedSet, orderedIDs, spellID)
    local numericID = tonumber(spellID)
    if not numericID or numericID == 0 then
        return
    end
    candidateSet[numericID] = true
    if orderedSet[numericID] then
        return
    end
    orderedSet[numericID] = true
    orderedIDs[#orderedIDs + 1] = numericID
end

local function AppendOrderedAuraCandidateIDsFromString(candidateSet, orderedSet, orderedIDs, rawIDs)
    if not rawIDs then
        return
    end
    for id in tostring(rawIDs):gmatch("%d+") do
        AppendOrderedAuraCandidateID(candidateSet, orderedSet, orderedIDs, id)
    end
end

local function AddCooldownInfoCandidateIDs(candidateSet, cooldownInfo)
    if type(cooldownInfo) ~= "table" then
        return
    end

    AddAuraCandidateID(candidateSet, cooldownInfo.spellID)
    AddAuraCandidateID(candidateSet, cooldownInfo.overrideSpellID)
    AddAuraCandidateID(candidateSet, cooldownInfo.overrideTooltipSpellID)

    if cooldownInfo.linkedSpellIDs then
        for _, linkedSpellID in ipairs(cooldownInfo.linkedSpellIDs) do
            AddAuraCandidateID(candidateSet, linkedSpellID)
        end
    end
end

local function HasBuffSuffixName(name)
    return type(name) == "string" and name:match("%s%([Bb]uff%)$") ~= nil
end

local function NormalizeResolvedAuraSpellID(baseId, auraSpellID)
    local numericAuraID = tonumber(auraSpellID)
    if not numericAuraID or numericAuraID == 0 then
        return nil
    end

    local auraBase = C_Spell.GetBaseSpell(numericAuraID)
    if auraBase and auraBase == baseId and auraBase ~= numericAuraID then
        return baseId
    end

    return numericAuraID
end

local function ResolveViewerFrameForSpellID(spellID, buffOnly)
    local numericID = tonumber(spellID)
    if not numericID or numericID == 0 then
        return nil
    end

    local candidate = CooldownCompanion.viewerAuraFrames and CooldownCompanion.viewerAuraFrames[numericID]
    if candidate and type(candidate.cooldownInfo) == "table" and (not buffOnly or IsBuffViewerChild(candidate)) then
        return candidate
    end

    candidate = FindChildInViewers(VIEWER_NAMES, numericID, buffOnly)
    if candidate then
        CooldownCompanion.viewerAuraFrames[numericID] = candidate
    end
    return candidate
end

local function ResolveDirectBuffViewerSpellID(spellID)
    local numericID = tonumber(spellID)
    if not numericID or numericID == 0 then
        return nil
    end

    local frame = ResolveViewerFrameForSpellID(numericID, true)
    local info = frame and frame.cooldownInfo
    if type(info) ~= "table" then
        return nil
    end

    if tonumber(info.overrideTooltipSpellID) == numericID
        or tonumber(info.overrideSpellID) == numericID
        or tonumber(info.spellID) == numericID then
        return numericID
    end
    return nil
end

local function CooldownInfoMatchesCandidateSet(cooldownInfo, candidateSet)
    if type(cooldownInfo) ~= "table" then
        return false
    end

    local function MatchesSpellID(spellID)
        local numericID = tonumber(spellID)
        if not numericID or numericID == 0 then
            return false
        end
        if candidateSet[numericID] then
            return true
        end

        local baseSpellID = C_Spell.GetBaseSpell(numericID)
        return baseSpellID and baseSpellID ~= numericID and candidateSet[baseSpellID] == true
    end

    if MatchesSpellID(cooldownInfo.spellID)
        or MatchesSpellID(cooldownInfo.overrideSpellID)
        or MatchesSpellID(cooldownInfo.overrideTooltipSpellID) then
        return true
    end

    if cooldownInfo.linkedSpellIDs then
        for _, linkedSpellID in ipairs(cooldownInfo.linkedSpellIDs) do
            if MatchesSpellID(linkedSpellID) then
                return true
            end
        end
    end

    return false
end

local function GetCooldownViewerDataProvider()
    if not (CooldownViewerSettings and CooldownViewerSettings.GetDataProvider) then
        return nil
    end
    return CooldownViewerSettings:GetDataProvider()
end

local function ForEachRawCooldownInfo(callback)
    for _, category in ipairs(COOLDOWN_VIEWER_ASSOCIATION_CATEGORIES) do
        local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(category, true)
        if cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if info then
                    callback(cooldownID, info, category)
                end
            end
        end
    end
end

local function ForEachAuraLayoutInfo(callback)
    local dataProvider = GetCooldownViewerDataProvider()
    if not dataProvider then
        return false
    end

    for _, category in ipairs(TRACKED_AURA_CATEGORIES) do
        local cooldownIDs = dataProvider:GetOrderedCooldownIDsForCategory(category, true)
        if cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                local info = dataProvider:GetCooldownInfoForID(cooldownID)
                if info then
                    callback(cooldownID, info, category, true)
                end
            end
        end
    end

    local hiddenAuraCategory = Enum.CooldownViewerCategory.HiddenAura
    if hiddenAuraCategory ~= nil then
        local cooldownIDs = dataProvider:GetOrderedCooldownIDsForCategory(hiddenAuraCategory, true)
        if cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                local info = dataProvider:GetCooldownInfoForID(cooldownID)
                if info then
                    callback(cooldownID, info, hiddenAuraCategory, false)
                end
            end
        end
    end

    return true
end

function CooldownCompanion:OnUnitAura(event, unit, updateInfo)
    self._cooldownsDirty = true
    if unit == "player" and self._isDracthyr then
        self:InvalidateMountAlphaCache()
    end

    if not updateInfo then return end

    -- Merged single-pass processing: removals, pandemic updates, and target-switch
    -- signaling in one ForEachButton call instead of three separate iterations.
    -- Removals are processed first so refreshed auras (remove + add in same event)
    -- work correctly — the update path re-checks _auraInstanceID after removals.
    local removedIDs = updateInfo.removedAuraInstanceIDs
    local updatedIDs = updateInfo.updatedAuraInstanceIDs
    local isTarget = (unit == "target")
    if removedIDs or updatedIDs or isTarget then
        self:ForEachButton(function(button)
            if button._auraInstanceID and button._auraUnit == unit then
                if removedIDs then
                    for _, instId in ipairs(removedIDs) do
                        if button._auraInstanceID == instId then
                            button._auraInstanceID = nil
                            button._inPandemic = false
                            button._auraEventRemoved = true
                            break
                        end
                    end
                end
                -- Aura reapplication (pandemic refresh) arrives as an update, not a
                -- removal + add.  Clear pandemic state and suppress the grace hold so
                -- the next evaluation clears pandemic immediately instead of holding 0.3s.
                if updatedIDs and button._auraInstanceID then
                    for _, instId in ipairs(updatedIDs) do
                        if button._auraInstanceID == instId then
                            button._inPandemic = false
                            button._pandemicGraceStart = nil
                            button._pandemicGraceSuppressed = true
                            break
                        end
                    end
                end
            end
            -- Signal that the server has delivered target aura data, so the hold
            -- logic in CooldownUpdate can terminate early instead of waiting for the
            -- safety cap timeout.
            if isTarget and button._targetSwitchAt then
                button._targetSwitchDataReceived = true
            end
        end)
    end

    -- Update immediately — CDM viewer frames registered their event handlers
    -- before our addon loaded, so by the time this handler fires the CDM has
    -- already refreshed its children with fresh auraInstanceID data.
    if unit == "target" or unit == "player" then
        self:UpdateAllCooldowns()
    end
end

-- Clear aura state on buttons tracking a unit when that unit changes (target/focus switch).
-- The viewer will re-evaluate on its next tick; this ensures stale data is cleared promptly.
function CooldownCompanion:ClearAuraUnit(unitToken)
    self:ForEachButton(function(button, bd)
        if bd.auraTracking or bd.isPassive then
            local configUnit = bd.auraUnit or "player"
            local shouldClear = button._auraUnit == unitToken
            if not shouldClear and configUnit == unitToken then
                shouldClear = true
            end
            if shouldClear then
                button._auraInstanceID = nil
                button._auraActive = false
                button._inPandemic = false
                button._targetSwitchAt = nil
                button._targetSwitchDataReceived = nil
                button._auraUnit = configUnit
            end
        end
    end)
    self._cooldownsDirty = true
end

function CooldownCompanion:OnTargetChanged()
    if not UnitExists("target") then
        -- Deselected target: clear all target aura state immediately
        self:ClearAuraUnit("target")
        return
    end
    -- New target: clear stale instance IDs so the viewer path doesn't
    -- read old auraInstanceIDs.  Keep _auraActive so the hold can
    -- maintain visual continuity while CDM refreshes.
    local now = GetTime()
    self:ForEachButton(function(button, bd)
        if bd.auraTracking or bd.isPassive then
            local configUnit = bd.auraUnit or "player"
            local isTarget = button._auraUnit == "target"
                or configUnit == "target"
            if isTarget then
                button._auraInstanceID = nil
                button._inPandemic = false
                button._targetSwitchAt = now
                button._targetSwitchDataReceived = nil
                button._auraUnit = "target"
            end
        end
    end)
    -- Synchronous probe: CDM viewer frames register their event handlers on
    -- Blizzard frames created before addons load.  If UNIT_TARGET has already
    -- been processed by the time PLAYER_TARGET_CHANGED fires, the CDM children
    -- will have fresh auraInstanceID data.  Probing immediately lets the
    -- primary path clear _targetSwitchAt in the same frame — zero hold.
    self:UpdateAllCooldowns()
end


function CooldownCompanion:ResolveAuraSpellID(buttonData)
    if not buttonData.auraTracking then return nil end
    if buttonData.auraSpellID then
        local first = tostring(buttonData.auraSpellID):match("%d+")
        return first and tonumber(first)
    end
    if buttonData.type == "spell" then
        local directAuraID = ResolveDirectBuffViewerSpellID(buttonData.id)
        if directAuraID then
            return directAuraID
        end
        -- Resolve through base spell so form-variant spells (e.g. Stampeding
        -- Roar: 106898/77764/77761) use the base ID for aura lookups — the
        -- buff is always applied as the base spell regardless of form.
        local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id
        local auraId = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
        if auraId then
            return auraId
        end
        -- Many spells share the same ID for cast and buff; fall back to the base spell ID
        return baseId
    end
    return nil
end

function CooldownCompanion:InferConfirmedAuraSpellIDString(buttonData)
    if not (buttonData and buttonData.type == "spell") then
        return nil
    end

    if buttonData.auraSpellID then
        return tostring(buttonData.auraSpellID)
    end

    local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[buttonData.id]
    if overrideBuffs then
        return overrideBuffs
    end

    local directAuraID = ResolveDirectBuffViewerSpellID(buttonData.id)
    if directAuraID then
        return tostring(directAuraID)
    end

    local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id
    local resolvedAuraId = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
    if resolvedAuraId and resolvedAuraId ~= buttonData.id then
        return tostring(resolvedAuraId)
    end

    local buffViewerFrame = self:ResolveBuffViewerFrameForSpell(baseId)
        or (baseId ~= buttonData.id and self:ResolveBuffViewerFrameForSpell(buttonData.id))
    local distinctAuraIDs = {}
    if buffViewerFrame and type(buffViewerFrame.cooldownInfo) == "table" then
        local info = buffViewerFrame.cooldownInfo
        for _, spellID in ipairs({
            info.overrideSpellID,
            info.overrideTooltipSpellID,
        }) do
            local numericID = tonumber(spellID)
            if numericID and numericID ~= 0 and numericID ~= buttonData.id and numericID ~= baseId then
                distinctAuraIDs[numericID] = true
            end
        end
        if info.linkedSpellIDs then
            for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
                local numericID = tonumber(linkedSpellID)
                if numericID and numericID ~= 0 and numericID ~= buttonData.id and numericID ~= baseId then
                    distinctAuraIDs[numericID] = true
                end
            end
        end
    end

    local inferredAuraSpellID
    for spellID in pairs(distinctAuraIDs) do
        if inferredAuraSpellID then
            return nil
        end
        inferredAuraSpellID = tostring(spellID)
    end

    return inferredAuraSpellID
end

function CooldownCompanion:ResolveStandaloneAuraDefaultSpellID(buttonData)
    if not (buttonData and buttonData.type == "spell") then
        return nil
    end

    local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id

    local function ResolveSingleSpellID(rawIDs)
        if not rawIDs then
            return nil
        end

        local resolvedID
        for id in tostring(rawIDs):gmatch("%d+") do
            local numericID = tonumber(id)
            if numericID and numericID ~= 0 then
                if resolvedID and resolvedID ~= numericID then
                    return nil
                end
                resolvedID = numericID
            end
        end

        return resolvedID
    end

    local explicitAuraID = ResolveSingleSpellID(buttonData.auraSpellID)
    if explicitAuraID then
        return explicitAuraID
    end

    local directAuraID = ResolveDirectBuffViewerSpellID(buttonData.id)
    if directAuraID then
        return directAuraID
    end

    local resolvedAuraID = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
    if resolvedAuraID then
        return resolvedAuraID
    end

    local buffViewerFrame = self:ResolveBuffViewerFrameForSpell(baseId)
        or (baseId ~= buttonData.id and self:ResolveBuffViewerFrameForSpell(buttonData.id))
    if not (buffViewerFrame and type(buffViewerFrame.cooldownInfo) == "table") then
        return nil
    end

    local info = buffViewerFrame.cooldownInfo
    local metadataCandidate
    for _, spellID in ipairs({info.spellID, info.overrideSpellID, info.overrideTooltipSpellID}) do
        local numericID = tonumber(spellID)
        if numericID and numericID ~= 0 and numericID ~= buttonData.id and numericID ~= baseId then
            if metadataCandidate and metadataCandidate ~= numericID then
                return nil
            end
            metadataCandidate = numericID
        end
    end
    if info.linkedSpellIDs then
        for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
            local numericID = tonumber(linkedSpellID)
            if numericID and numericID ~= 0 and numericID ~= buttonData.id and numericID ~= baseId then
                if metadataCandidate and metadataCandidate ~= numericID then
                    return nil
                end
                metadataCandidate = numericID
            end
        end
    end

    return metadataCandidate
end

function CooldownCompanion:ResolveStandaloneAuraDefaultUnit(buttonData)
    local resolvedSpellID = self:ResolveStandaloneAuraDefaultSpellID(buttonData)
    if resolvedSpellID then
        return C_Spell.IsSpellHarmful(resolvedSpellID) and "target" or "player"
    end
    if buttonData and buttonData.id then
        return C_Spell.IsSpellHarmful(buttonData.id) and "target" or "player"
    end
    return "player"
end

function CooldownCompanion:ResolveAuraTrackingAssociationData(buttonData, viewerFrame)
    local data = {
        hasAssociatedAura = false,
        hasTrackedAuraLayout = false,
        trackedBuffViewerFrame = nil,
    }

    if not (buttonData and buttonData.type == "spell") then
        return data
    end

    local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id
    local candidateIDs = {}
    local orderedCandidateSet = {}
    local orderedCandidateIDs = {}

    AppendOrderedAuraCandidateIDsFromString(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData.auraSpellID)
    AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData.id)
    AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, baseId)

    local resolvedAuraId = C_UnitAuras.GetCooldownAuraBySpellID(baseId)
    if resolvedAuraId and resolvedAuraId ~= 0 then
        data.hasAssociatedAura = true
        AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, resolvedAuraId)
    end

    local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[buttonData.id]
    if overrideBuffs then
        AppendOrderedAuraCandidateIDsFromString(candidateIDs, orderedCandidateSet, orderedCandidateIDs, overrideBuffs)
    end

    local function MergeCooldownInfo(cooldownInfo)
        if type(cooldownInfo) ~= "table" then
            return
        end
        AddCooldownInfoCandidateIDs(candidateIDs, cooldownInfo)
    end

    if viewerFrame and IsBuffViewerChild(viewerFrame) and type(viewerFrame.cooldownInfo) == "table" then
        data.trackedBuffViewerFrame = viewerFrame
        data.hasAssociatedAura = true
        MergeCooldownInfo(viewerFrame.cooldownInfo)
    end

    -- Raw cooldown records expand candidate spell IDs, but the config text should
    -- only consider an aura "found" if Blizzard places it in the aura layout
    -- itself (tracked or hidden/not displayed), not merely on a cooldown record.
    for _ = 1, 2 do
        ForEachRawCooldownInfo(function(_cooldownID, info)
            if CooldownInfoMatchesCandidateSet(info, candidateIDs) then
                MergeCooldownInfo(info)
            end
        end)
    end

    for spellID in pairs(candidateIDs) do
        AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, spellID)
    end

    if not data.trackedBuffViewerFrame then
        for _, spellID in ipairs(orderedCandidateIDs) do
            local candidate = self:ResolveBuffViewerFrameForSpell(spellID)
            if candidate then
                data.trackedBuffViewerFrame = candidate
                data.hasAssociatedAura = true
                MergeCooldownInfo(candidate.cooldownInfo)
                break
            end
        end
    end

    for _, spellID in ipairs(orderedCandidateIDs) do
        local candidate = ResolveViewerFrameForSpellID(spellID, false)
        if candidate and type(candidate.cooldownInfo) == "table" then
            MergeCooldownInfo(candidate.cooldownInfo)
        end
    end

    for _ = 1, 2 do
        ForEachAuraLayoutInfo(function(_cooldownID, info, _category, isTracked)
            if CooldownInfoMatchesCandidateSet(info, candidateIDs) then
                if isTracked then
                    data.hasTrackedAuraLayout = true
                end
                data.hasAssociatedAura = true
                MergeCooldownInfo(info)
            end
        end)
    end

    return data
end

function CooldownCompanion:ShouldRecoverLegacyStandaloneAuraEntry(buttonData, siblingButtons, options)
    if not (buttonData and buttonData.type == "spell") then
        return false
    end

    options = options or {}

    if buttonData.isPassive == true then
        return true
    end

    if options.trustExplicitAuraLabel ~= false and buttonData.addedAs == "aura" then
        return true
    end

    local hasAuraMarkers = buttonData.auraTracking == true
        or buttonData.auraIndicatorEnabled == true
        or buttonData.auraSpellID ~= nil
    if not hasAuraMarkers then
        return false
    end

    if HasBuffSuffixName(buttonData.name) then
        return true
    end

    return false
end

function CooldownCompanion:NormalizeStandaloneAuraButtonData(buttonData, siblingButtons, options)
    if not (buttonData and buttonData.type == "spell") then
        return false
    end

    local recoverLegacyAura = self:ShouldRecoverLegacyStandaloneAuraEntry(buttonData, siblingButtons, options)
    local isAuraOnlyEntry = recoverLegacyAura
    if not isAuraOnlyEntry then
        return false
    end

    local changed = false
    if buttonData.addedAs ~= "aura" then
        buttonData.addedAs = "aura"
        changed = true
    end

    -- Aura entries are never dynamic spell buttons: keep auraTracking on so
    -- they remain aura-only even when CDM is temporarily not ready.
    if buttonData.addedAs == "aura" and buttonData.auraTracking ~= true then
        buttonData.auraTracking = true
        changed = true
    end

    if buttonData.auraIndicatorEnabled == nil then
        buttonData.auraIndicatorEnabled = true
        changed = true
    end

    if not buttonData.auraSpellID then
        local inferredAuraSpellID = self:InferConfirmedAuraSpellIDString(buttonData)
        if inferredAuraSpellID then
            buttonData.auraSpellID = inferredAuraSpellID
            changed = true
        end
    end

    if buttonData.auraUnit ~= "player" and buttonData.auraUnit ~= "target" then
        buttonData.auraUnit = self:ResolveStandaloneAuraDefaultUnit(buttonData)
        changed = true
    end

    return changed
end

function CooldownCompanion:IsAuraTrackingReady(buttonData, cdmEnabled, viewerFrame)
    if not (buttonData and buttonData.type == "spell") then
        return false
    end

    if buttonData.auraTracking ~= true and buttonData.isPassive ~= true then
        return false
    end

    if cdmEnabled == nil then
        cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    end
    if cdmEnabled ~= true then
        return false
    end

    if viewerFrame ~= nil then
        return true
    end

    -- Passive player auras can still track through direct aura API fallback
    -- even when Blizzard has not built a readable Buff viewer child yet.
    return buttonData.isPassive == true and (buttonData.auraUnit or "player") == "player"
end

function CooldownCompanion:ResolveAuraTrackingConfigStatus(buttonData, cdmEnabled, viewerFrame)
    local status = {
        state = "disabled",
        ready = false,
        cdmEnabled = false,
        hasAssociatedAura = false,
        hasTrackedAuraLayout = false,
    }

    if not (buttonData and buttonData.type == "spell") then
        return status
    end

    if buttonData.auraTracking ~= true and buttonData.isPassive ~= true then
        return status
    end

    if cdmEnabled == nil then
        cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    end
    status.cdmEnabled = cdmEnabled == true
    if not status.cdmEnabled then
        status.state = "cdmDisabled"
        return status
    end

    local associationData = self:ResolveAuraTrackingAssociationData(buttonData, viewerFrame)
    local hasTrackedBuffViewer = associationData.trackedBuffViewerFrame ~= nil
    local hasTrackedAuraLayout = associationData.hasTrackedAuraLayout == true
    status.hasAssociatedAura = associationData.hasAssociatedAura == true
    status.hasTrackedAuraLayout = hasTrackedAuraLayout

    if hasTrackedBuffViewer then
        status.ready = true
        status.state = "ready"
        return status
    end

    if hasTrackedAuraLayout then
        status.state = "trackedAuraUnavailable"
        return status
    end

    if status.hasAssociatedAura then
        status.state = "associatedAuraNotTracked"
        return status
    end

    status.state = "noAssociatedAura"
    return status
end

function CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData)
    if not buttonData or buttonData.type ~= "spell" then return nil end
    if buttonData.cdmChildSlot then
        local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
        local slotChild = allChildren and allChildren[buttonData.cdmChildSlot]
        if IsBuffViewerChild(slotChild) then
            return slotChild
        end
    end

    local associationData = self:ResolveAuraTrackingAssociationData(buttonData)
    return associationData.trackedBuffViewerFrame
end

-- Hardcoded ability → buff overrides for spells whose ability ID and buff IDs
-- are completely unlinked by any API (GetCooldownAuraBySpellID returns 0).
-- Format: [abilitySpellID] = "comma-separated buff spell IDs"
CooldownCompanion.ABILITY_BUFF_OVERRIDES = {
    -- Legacy compatibility only: older saved Eclipse buttons may still use
    -- the ability IDs, but new adds must choose the specific CDM aura row.
    [1233346] = "48517,48518",  -- Solar Eclipse legacy ability -> Eclipse buffs
    [1233272] = "48517,48518",  -- Lunar Eclipse legacy ability -> Eclipse buffs
}

-------------------------------------------------------------------------------
-- CDM Viewer System (merged from Core/ViewerAura.lua)
-------------------------------------------------------------------------------

-- Shared helper: scan a list of viewer frames for a child matching spellID.
-- Checks cooldownInfo spell associations used by CDM (base, overrides, linked).
FindChildInViewers = function(viewerNames, spellID, buffOnly)
    for _, name in ipairs(viewerNames) do
        local viewer = _G[name]
        if viewer then
            for _, child in pairs({viewer:GetChildren()}) do
                local info = child.cooldownInfo
                if info and (not buffOnly or IsBuffViewerChild(child)) then
                    if info.spellID == spellID
                       or info.overrideSpellID == spellID
                       or info.overrideTooltipSpellID == spellID then
                        return child
                    end
                    if info.linkedSpellIDs then
                        for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
                            if linkedSpellID == spellID then
                                return child
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

function CooldownCompanion:ApplyCdmAlpha()
    local hidden = self.db.profile.cdmHidden and not self._cdmPickMode
    local alpha = hidden and 0 or 1
    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer then
            cdmAlphaGuard[viewer] = true
            viewer:SetAlpha(alpha)
            cdmAlphaGuard[viewer] = nil
            if not InCombatLockdown() then
                if hidden then
                    for _, child in pairs({viewer:GetChildren()}) do
                        child:SetMouseMotionEnabled(false)
                    end
                else
                    -- Restore tooltip state using Blizzard's own pattern
                    for itemFrame in viewer.itemFramePool:EnumerateActive() do
                        itemFrame:SetTooltipsShown(viewer.tooltipsShown)
                    end
                end
            end
        end
    end
end

function CooldownCompanion:QueueBuildViewerAuraMap()
    pendingViewerAuraMapToken = pendingViewerAuraMapToken + 1
    local token = pendingViewerAuraMapToken
    C_Timer.After(0, function()
        if pendingViewerAuraMapToken ~= token then return end
        self:BuildViewerAuraMap()
        self:RefreshConfigPanel()
    end)
end

function CooldownCompanion:ResolveBuffViewerFrameForSpell(spellID)
    local enabled = self._cdmViewerEnabled
    if enabled == nil then enabled = GetCVarBool("cooldownViewerEnabled") end
    if not spellID or spellID == 0 or not enabled then
        return nil
    end

    local child = self.viewerAuraFrames and self.viewerAuraFrames[spellID]
    if IsBuffViewerChild(child) and type(child.cooldownInfo) == "table" then
        return child
    end

    child = FindChildInViewers(VIEWER_NAMES, spellID, true)
    if child then
        self.viewerAuraFrames[spellID] = child
        return child
    end
    return nil
end

-- Build a mapping from spellID → Blizzard cooldown viewer child frame.
-- The viewer frames (EssentialCooldownViewer, UtilityCooldownViewer, etc.)
-- run untainted code that reads secret aura data and stores the result
-- (auraInstanceID, auraDataUnit) as plain frame properties we can read.
function CooldownCompanion:BuildViewerAuraMap()
    wipe(self.viewerAuraFrames)
    wipe(self.viewerAuraAllChildren)

    local function AddViewerAuraChild(spellID, child)
        if not spellID or not child then
            return
        end
        if not self.viewerAuraAllChildren[spellID] then
            self.viewerAuraAllChildren[spellID] = {}
        end
        local children = self.viewerAuraAllChildren[spellID]
        for _, existing in ipairs(children) do
            if existing == child then
                return
            end
        end
        table.insert(children, child)
    end

    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer then
            for _, child in pairs({viewer:GetChildren()}) do
                local info = child.cooldownInfo
                if info then
                    local spellID = info.spellID
                    if spellID then
                        self.viewerAuraFrames[spellID] = child
                        -- Track all children per base spellID for buff viewers only.
                        -- Duplicate detection is for same-section duplicates (e.g.
                        -- Diabolic Ritual twice in Tracked Buffs), not cross-section
                        -- matches (e.g. Agony in Essential + Buffs).
                        if BUFF_VIEWER_SET[name] then
                            AddViewerAuraChild(spellID, child)
                        end
                    end
                    local override = info.overrideSpellID
                    if override then
                        self.viewerAuraFrames[override] = child
                    end
                    local tooltipOverride = info.overrideTooltipSpellID
                    if tooltipOverride then
                        self.viewerAuraFrames[tooltipOverride] = child
                    end
                    if info.linkedSpellIDs then
                        for _, linked in ipairs(info.linkedSpellIDs) do
                            self.viewerAuraFrames[linked] = child
                        end
                    end
                    if BUFF_VIEWER_SET[name] then
                        local specificSpellID = info.overrideTooltipSpellID or info.overrideSpellID
                        if specificSpellID and specificSpellID ~= spellID then
                            AddViewerAuraChild(specificSpellID, child)
                        end
                    end
                end
            end
        end
    end
    -- Ensure tracked buttons can find their viewer child even if
    -- buttonData.id is a non-current override form of a transforming spell.
    self:MapButtonSpellsToViewers()

    -- Map hardcoded overrides: ability IDs and buff IDs → viewer child.
    -- Group by buff string so sibling abilities can cross-map to the same
    -- viewer child even if only one form is current.
    local groupsByBuffs = {}
    for abilityID, buffIDStr in pairs(self.ABILITY_BUFF_OVERRIDES) do
        if not groupsByBuffs[buffIDStr] then
            groupsByBuffs[buffIDStr] = {}
        end
        groupsByBuffs[buffIDStr][#groupsByBuffs[buffIDStr] + 1] = abilityID
    end
    for buffIDStr, abilityIDs in pairs(groupsByBuffs) do
        -- Prefer a BuffIcon/BuffBar child (tracks aura duration) over
        -- Essential/Utility (tracks cooldown only). Check buff IDs first
        -- since the initial scan maps them to the correct viewer type.
        local child
        for id in buffIDStr:gmatch("%d+") do
            local c = self.viewerAuraFrames[tonumber(id)]
            if c then
                local p = c:GetParent()
                local pn = p and p:GetName()
                if pn == "BuffIconCooldownViewer" or pn == "BuffBarCooldownViewer" then
                    child = c
                    break
                end
            end
        end
        if not child then
            for _, abilityID in ipairs(abilityIDs) do
                child = self.viewerAuraFrames[abilityID]
                if child then break end
            end
        end
        if not child then
            for _, abilityID in ipairs(abilityIDs) do
                child = self:FindViewerChildForSpell(abilityID)
                if child then break end
            end
        end
        if child then
            for _, abilityID in ipairs(abilityIDs) do
                self.viewerAuraFrames[abilityID] = child
            end
            -- Map buff IDs only if they aren't already mapped by the initial scan.
            -- Each buff may have its own viewer child (e.g. Solar vs Lunar Eclipse).
            for id in buffIDStr:gmatch("%d+") do
                local numID = tonumber(id)
                if not self.viewerAuraFrames[numID] then
                    self.viewerAuraFrames[numID] = child
                end
            end
        end
    end

    -- Rebuild spell -> cooldown alert capability mapping used by per-button sound alerts.
    self:RebuildSoundAlertSpellMap()

    -- Re-enforce mouse state for hidden CDM after map rebuild
    if self.db.profile.cdmHidden and not self._cdmPickMode then
        for _, name2 in ipairs(VIEWER_NAMES) do
            local v = _G[name2]
            if v then
                for _, child in pairs({v:GetChildren()}) do
                    child:SetMouseMotionEnabled(false)
                end
            end
        end
    end
end

-- For each tracked button, ensure viewerAuraFrames contains an entry
-- for buttonData.id. Handles the case where the spell was added while
-- in one form (e.g. Solar Eclipse) but the map was rebuilt while the
-- spell is in a different form (e.g. Lunar Eclipse).
function CooldownCompanion:MapButtonSpellsToViewers()
    self:ForEachButton(function(button, bd)
        local id = bd.id
        if id and bd.type == "spell" and not self.viewerAuraFrames[id] then
            local child = self:FindViewerChildForSpell(id)
            if child then
                self.viewerAuraFrames[id] = child
            end
        end
    end)
end

-- Scan viewer children to find one that tracks a given spellID.
-- Checks spellID, overrideSpellID, overrideTooltipSpellID on each child,
-- then uses GetBaseSpell to resolve override forms back to their base spell.
-- Returns the child frame if found, nil otherwise.
function CooldownCompanion:FindViewerChildForSpell(spellID)
    local child = FindChildInViewers(VIEWER_NAMES, spellID)
    if child then return child end
    -- GetBaseSpell (AllowedWhenTainted): resolve override → base, then check map.
    local baseSpellID = C_Spell.GetBaseSpell(spellID)
    if baseSpellID and baseSpellID ~= spellID then
        child = self.viewerAuraFrames[baseSpellID]
        if child then return child end
    end
    -- Override table: check buff IDs and sibling abilities
    local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[spellID]
    if overrideBuffs then
        for id in overrideBuffs:gmatch("%d+") do
            child = self.viewerAuraFrames[tonumber(id)]
            if child then return child end
        end
        for sibID, sibBuffs in pairs(self.ABILITY_BUFF_OVERRIDES) do
            if sibBuffs == overrideBuffs and sibID ~= spellID then
                child = self.viewerAuraFrames[sibID]
                if child then return child end
            end
        end
    end
    return nil
end

-- Find a cooldown viewer child (Essential/Utility only) for a spell.
-- Used by UpdateButtonIcon to get dynamic icon/name from the cooldown tracker
-- rather than the buff tracker (BuffIcon/BuffBar), which uses static buff spell IDs.
function CooldownCompanion:FindCooldownViewerChild(spellID)
    local child = FindChildInViewers(COOLDOWN_VIEWER_NAMES, spellID)
    if child then return child end
    -- Try base spell resolution
    local baseSpellID = C_Spell.GetBaseSpell(spellID)
    if baseSpellID and baseSpellID ~= spellID then
        return self:FindCooldownViewerChild(baseSpellID)
    end
    -- Try sibling abilities from override table
    local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[spellID]
    if overrideBuffs then
        for sibID, sibBuffs in pairs(self.ABILITY_BUFF_OVERRIDES) do
            if sibBuffs == overrideBuffs and sibID ~= spellID then
                child = FindChildInViewers(COOLDOWN_VIEWER_NAMES, sibID)
                if child then return child end
            end
        end
    end
    return nil
end

-- When a spell transforms (e.g. Solar Eclipse → Lunar Eclipse), map the new
-- override spell ID to the same viewer child frame so lookups work for both forms.
function CooldownCompanion:OnViewerSpellOverrideUpdated(event, baseSpellID, overrideSpellID)
    if not baseSpellID then return end
    -- Multi-child: find the specific child whose overrideSpellID matches
    local allChildren = self.viewerAuraAllChildren[baseSpellID]
    if allChildren and overrideSpellID then
        for _, c in ipairs(allChildren) do
            if c.cooldownInfo and c.cooldownInfo.overrideSpellID == overrideSpellID then
                self.viewerAuraFrames[overrideSpellID] = c
                break
            end
        end
    elseif overrideSpellID then
        -- Single-child fallback (original behavior)
        local child = self.viewerAuraFrames[baseSpellID]
        if child then
            self.viewerAuraFrames[overrideSpellID] = child
        end
    end
    -- Refresh icons/names now that the viewer child's overrideSpellID is current
    self:OnSpellUpdateIcon()
    -- Coalesce config updates while shapeshift/form override events settle.
    self:QueueOverrideConfigRefresh(baseSpellID, overrideSpellID)
end
