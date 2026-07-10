--[[
    CooldownCompanion - Core/Aura.lua: slim aura event handlers (OnUnitAura,
    OnTargetChanged), config-time aura resolution, ABILITY_BUFF_OVERRIDES, CDM
    viewer system (ApplyCdmAlpha, BuildViewerAuraMap, FindViewerChildForSpell,
    FindCooldownViewerChild, OnViewerSpellOverrideUpdated).
    12.1 demolition: runtime aura reading removed pending the AuraContainer rebuild.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon


local ipairs = ipairs
local pairs = pairs
local select = select
local wipe = wipe
local tostring = tostring
local tonumber = tonumber

-- Import cross-file variables (viewer system)
local VIEWER_NAMES = ST._VIEWER_NAMES
local COOLDOWN_VIEWER_NAMES = ST._COOLDOWN_VIEWER_NAMES
local BUFF_VIEWER_SET = ST._BUFF_VIEWER_SET
local cdmAlphaGuard = ST._cdmAlphaGuard
local IsDistinctCDMAuraIdentity = ST.IsDistinctCDMAuraIdentity
local pendingViewerAuraMapToken = 0
local FindChildInViewers

local function IsBuffViewerChild(frame)
    if not frame then return false end
    local parent = frame:GetParent()
    local parentName = parent and parent:GetName()
    return BUFF_VIEWER_SET[parentName] == true
end

local function SetViewerChildrenMouseMotion(enabled, ...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        if child then
            child:SetMouseMotionEnabled(enabled)
        end
    end
end

local function FindMatchingViewerChild(spellID, buffOnly, ...)
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        local info = child and child.cooldownInfo
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
    return nil
end

local function AddViewerAuraMapChildren(addon, viewerName, addViewerAuraChild, ...)
    local isBuffViewer = BUFF_VIEWER_SET[viewerName] == true
    for i = 1, select("#", ...) do
        local child = select(i, ...)
        local info = child and child.cooldownInfo
        if info then
            local spellID = info.spellID
            if spellID then
                addon.viewerAuraFrames[spellID] = child
                -- Track all children per base spellID for buff viewers only.
                -- Duplicate detection is for same-section duplicates (e.g.
                -- Diabolic Ritual twice in Tracked Buffs), not cross-section
                -- matches (e.g. Agony in Essential + Buffs).
                if isBuffViewer then
                    addViewerAuraChild(spellID, child)
                end
            end
            local override = info.overrideSpellID
            if override then
                addon.viewerAuraFrames[override] = child
            end
            local tooltipOverride = info.overrideTooltipSpellID
            if tooltipOverride then
                addon.viewerAuraFrames[tooltipOverride] = child
            end
            if info.linkedSpellIDs then
                for _, linked in ipairs(info.linkedSpellIDs) do
                    addon.viewerAuraFrames[linked] = child
                end
            end
            if isBuffViewer then
                local specificSpellID = info.overrideTooltipSpellID or info.overrideSpellID
                if specificSpellID and specificSpellID ~= spellID then
                    addViewerAuraChild(specificSpellID, child)
                end
            end
        end
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


local function HasBuffSuffixName(name)
    return type(name) == "string" and name:match("%s%([Bb]uff%)$") ~= nil
end

local function IsDistinctAuraIdentityForButton(buttonData, auraID)
    return ST.IsPlainSpellEntry
        and ST.IsPlainSpellEntry(buttonData)
        and auraID
        and IsDistinctCDMAuraIdentity
        and IsDistinctCDMAuraIdentity(buttonData.id, auraID)
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
        or tonumber(info.overrideSpellID) == numericID then
        return numericID
    end

    if tonumber(info.spellID) == numericID then
        local tooltipOverride = tonumber(info.overrideTooltipSpellID)
        if tooltipOverride and tooltipOverride ~= 0 then
            return tooltipOverride
        end

        local spellOverride = tonumber(info.overrideSpellID)
        if spellOverride and spellOverride ~= 0 then
            return spellOverride
        end

        return numericID
    end

    return nil
end

local function BuildStandaloneOriginalAuraCandidateIDs(buttonData)
    local candidateIDs = {}
    local orderedCandidateSet = {}
    local orderedCandidateIDs = {}

    if not (buttonData and buttonData.type == "spell") then
        return orderedCandidateIDs, candidateIDs, orderedCandidateSet
    end

    local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id

    local directAuraID = ResolveDirectBuffViewerSpellID(buttonData.id)
    if directAuraID then
        AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, directAuraID)
    end

    local resolvedAuraId = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
    if resolvedAuraId then
        AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, resolvedAuraId)
    end

    AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData.id)
    AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, baseId)

    local overrideBuffs = CooldownCompanion.ABILITY_BUFF_OVERRIDES and CooldownCompanion.ABILITY_BUFF_OVERRIDES[buttonData.id]
    if overrideBuffs then
        AppendOrderedAuraCandidateIDsFromString(candidateIDs, orderedCandidateSet, orderedCandidateIDs, overrideBuffs)
    end

    return orderedCandidateIDs, candidateIDs, orderedCandidateSet
end

local function AppendStandaloneFallbackAuraCandidateIDs(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData, rawIDs)
    local _, originalCandidateSet = BuildStandaloneOriginalAuraCandidateIDs(buttonData)
    if not rawIDs then
        return
    end
    for id in tostring(rawIDs):gmatch("%d+") do
        local numericID = tonumber(id)
        if numericID and not originalCandidateSet[numericID] then
            AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, numericID)
        end
    end
end


local function BuildStandaloneAuraFallbackSpellIDText(buttonData, rawIDs)
    local _, originalCandidateSet = BuildStandaloneOriginalAuraCandidateIDs(buttonData)
    local fallbackIDs = {}
    local seen = {}
    if not rawIDs then
        return nil
    end
    for id in tostring(rawIDs):gmatch("%d+") do
        local numericID = tonumber(id)
        if numericID and not originalCandidateSet[numericID] and not seen[numericID] then
            seen[numericID] = true
            fallbackIDs[#fallbackIDs + 1] = tostring(numericID)
        end
    end
    return #fallbackIDs > 0 and table.concat(fallbackIDs, ",") or nil
end

local function BuildOrderedAuraCandidateIDs(buttonData)
    local candidateIDs = {}
    local orderedCandidateSet = {}
    local orderedCandidateIDs = {}

    if not (buttonData and buttonData.type == "spell") then
        return orderedCandidateIDs, candidateIDs, orderedCandidateSet
    end

    local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id

    local function AppendSpellAssociationAuraIDs()
        AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData.id)
        AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, baseId)

        local resolvedAuraId = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
        if resolvedAuraId and not IsDistinctAuraIdentityForButton(buttonData, resolvedAuraId) then
            AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, resolvedAuraId)
        end
    end

    if buttonData.addedAs == "aura" then
        local originalAuraIDs = BuildStandaloneOriginalAuraCandidateIDs(buttonData)
        for _, spellID in ipairs(originalAuraIDs) do
            AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, spellID)
        end
        AppendStandaloneFallbackAuraCandidateIDs(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData, buttonData.auraSpellID)
    else
        AppendOrderedAuraCandidateIDsFromString(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData.auraSpellID)
        AppendSpellAssociationAuraIDs()
    end

    local overrideBuffs = buttonData.addedAs ~= "aura"
        and CooldownCompanion.ABILITY_BUFF_OVERRIDES
        and CooldownCompanion.ABILITY_BUFF_OVERRIDES[buttonData.id]
    if overrideBuffs then
        AppendOrderedAuraCandidateIDsFromString(candidateIDs, orderedCandidateSet, orderedCandidateIDs, overrideBuffs)
    end

    return orderedCandidateIDs, candidateIDs, orderedCandidateSet
end


function CooldownCompanion:GetStandaloneAuraFallbackSpellIDText(buttonData, rawIDs)
    return BuildStandaloneAuraFallbackSpellIDText(buttonData, rawIDs or (buttonData and buttonData.auraSpellID))
end





-- Slim (12.1 demolition): aura tracking removed. Sole surviving duty is the
-- Dracthyr Soar mount-alpha cache invalidation (AlphaFade.lua Soar read is a
-- flagged follow-up).
function CooldownCompanion:OnUnitAura(event, unit, updateInfo)
    if unit == "player" and self._isDracthyr then
        self:InvalidateMountAlphaCache()
    end
end

-- Slim (12.1 demolition): kept because FrameAnchoring.lua hooksecurefunc's this
-- method (inheritAlpha resync rides the hook); the dirty mark keeps
-- target-dependent kept visuals (range tint, {oor} text) repainting promptly.
function CooldownCompanion:OnTargetChanged()
    self:MarkCooldownsDirty("target-changed")
end


function CooldownCompanion:ResolveAuraSpellID(buttonData)
    if not buttonData.auraTracking then return nil end
    if buttonData.addedAs ~= "aura" and buttonData.auraSpellID then
        local first = tostring(buttonData.auraSpellID):match("%d+")
        return first and tonumber(first)
    end
    if buttonData.addedAs == "aura" then
        local orderedCandidateIDs = BuildOrderedAuraCandidateIDs(buttonData)
        return orderedCandidateIDs[1]
    end
    if buttonData.type == "spell" then
        local directAuraID = ResolveDirectBuffViewerSpellID(buttonData.id)
        if directAuraID and not IsDistinctAuraIdentityForButton(buttonData, directAuraID) then
            return directAuraID
        end
        -- Resolve through base spell so form-variant spells (e.g. Stampeding
        -- Roar: 106898/77764/77761) use the base ID for aura lookups — the
        -- buff is always applied as the base spell regardless of form.
        local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id
        local auraId = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
        if auraId and not IsDistinctAuraIdentityForButton(buttonData, auraId) then
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
    if directAuraID and not IsDistinctAuraIdentityForButton(buttonData, directAuraID) then
        return tostring(directAuraID)
    end

    local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id
    local resolvedAuraId = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
    if resolvedAuraId
        and resolvedAuraId ~= buttonData.id
        and not IsDistinctAuraIdentityForButton(buttonData, resolvedAuraId) then
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
            if numericID
                and numericID ~= 0
                and numericID ~= buttonData.id
                and numericID ~= baseId
                and not IsDistinctAuraIdentityForButton(buttonData, numericID) then
                distinctAuraIDs[numericID] = true
            end
        end
        if info.linkedSpellIDs then
            for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
                local numericID = tonumber(linkedSpellID)
                if numericID
                    and numericID ~= 0
                    and numericID ~= buttonData.id
                    and numericID ~= baseId
                    and not IsDistinctAuraIdentityForButton(buttonData, numericID) then
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

    local explicitAuraID = buttonData.addedAs ~= "aura" and ResolveSingleSpellID(buttonData.auraSpellID) or nil
    if explicitAuraID then
        return explicitAuraID
    end

    local directAuraID = ResolveDirectBuffViewerSpellID(buttonData.id)
    if directAuraID and not IsDistinctAuraIdentityForButton(buttonData, directAuraID) then
        return directAuraID
    end

    local resolvedAuraID = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
    if resolvedAuraID and not IsDistinctAuraIdentityForButton(buttonData, resolvedAuraID) then
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
        if numericID
            and numericID ~= 0
            and numericID ~= buttonData.id
            and numericID ~= baseId
            and not IsDistinctAuraIdentityForButton(buttonData, numericID) then
            if metadataCandidate and metadataCandidate ~= numericID then
                return nil
            end
            metadataCandidate = numericID
        end
    end
    if info.linkedSpellIDs then
        for _, linkedSpellID in ipairs(info.linkedSpellIDs) do
            local numericID = tonumber(linkedSpellID)
            if numericID
                and numericID ~= 0
                and numericID ~= buttonData.id
                and numericID ~= baseId
                and not IsDistinctAuraIdentityForButton(buttonData, numericID) then
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

    if buttonData.addedAs == "aura" then
        local fallbackIDs = self:GetStandaloneAuraFallbackSpellIDText(buttonData)
        if buttonData.auraSpellID ~= fallbackIDs then
            buttonData.auraSpellID = fallbackIDs
            changed = true
        end
    elseif not buttonData.auraSpellID then
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

local BAR_PANEL_AURA_STACK_MODES = {
    stacks = true,
    stack = true,
    stack_continuous = true,
    stack_segmented = true,
    stack_overlay = true,
}

local BAR_PANEL_AURA_ACTIVE_MODES = {
    active = true,
    duration = true,
}


local function NormalizeBarPanelAuraStackMode(mode)
    if mode == "stack_continuous" then
        return "stack_continuous"
    elseif mode == "stack_overlay" then
        return "stack_overlay"
    elseif mode == "stack_segmented" then
        return "stack_segmented"
    end
    return nil
end

local function GetBarPanelAuraStackDisplayFromMode(mode)
    mode = NormalizeBarPanelAuraStackMode(mode)
    if mode == "stack_continuous" then
        return "continuous"
    elseif mode == "stack_overlay" then
        return "overlay"
    end
    return "segmented"
end


local function ClampBarPanelAuraNumber(value, minValue, maxValue, defaultValue)
    value = tonumber(value) or defaultValue
    if value < minValue then
        return minValue
    elseif value > maxValue then
        return maxValue
    end
    return value
end

function CooldownCompanion:IsBarPanelAuraDisplayEligible(buttonData)
    if not (buttonData and buttonData.type == "spell") then
        return false
    end
    return buttonData.addedAs == "aura" or buttonData.auraTracking == true
end

function CooldownCompanion:GetBarPanelAuraDisplayKind(buttonData)
    if not self:IsBarPanelAuraDisplayEligible(buttonData) then
        return "active"
    end

    local auraBar = buttonData.auraBar
    local mode = type(auraBar) == "table" and auraBar.mode or nil
    if BAR_PANEL_AURA_STACK_MODES[mode] then
        return "stacks"
    end
    if mode == nil or BAR_PANEL_AURA_ACTIVE_MODES[mode] then
        return "active"
    end
    return "active"
end

function CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData)
    return self:GetBarPanelAuraDisplayKind(buttonData) == "stacks"
end


function CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    local mode = type(auraBar) == "table" and auraBar.mode or nil
    if type(auraBar) == "table" then
        mode = NormalizeBarPanelAuraStackMode(mode) or NormalizeBarPanelAuraStackMode(auraBar.stackDisplayMode)
    end
    return GetBarPanelAuraStackDisplayFromMode(mode)
end


function CooldownCompanion:GetBarPanelAuraMaxStacks(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    local value = type(auraBar) == "table" and auraBar.maxStacks or nil
    return math.floor(ClampBarPanelAuraNumber(value, 1, 99, 1) + 0.5)
end


function CooldownCompanion:GetBarPanelAuraSegmentGap(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    local value = type(auraBar) == "table" and auraBar.segmentGap or nil
    return ClampBarPanelAuraNumber(value, 0, 20, 4)
end



function CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    return ST.NormalizeSegmentedSmoothing(type(auraBar) == "table" and auraBar.segmentedSmoothing or nil)
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
            local child = FindMatchingViewerChild(spellID, buffOnly, viewer:GetChildren())
            if child then
                return child
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
                    SetViewerChildrenMouseMotion(false, viewer:GetChildren())
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

-- Map readable cooldownInfo spell identities to Blizzard cooldown viewer
-- children for retained config-time and association behavior. In 12.1, do not
-- treat child aura fields as runtime truth: auraSpellID/auraInstanceID become
-- secret in combat, and instance-ID aura APIs hard-error for addon code in
-- restricted combat.
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
            AddViewerAuraMapChildren(self, name, AddViewerAuraChild, viewer:GetChildren())
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
                SetViewerChildrenMouseMotion(false, v:GetChildren())
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
    if self.QueueOverrideConfigRefresh then
        self:QueueOverrideConfigRefresh(baseSpellID, overrideSpellID)
    end
end
