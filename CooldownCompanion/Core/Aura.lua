--[[
    CooldownCompanion - Core/Aura.lua: slim aura event handlers (OnUnitAura,
    OnTargetChanged), config-time aura resolution, CDM
    viewer system (BuildViewerAuraMap, FindViewerChildForSpell,
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
local IsDistinctCDMAuraIdentity = ST.IsDistinctCDMAuraIdentity
local IsConcreteSpellID = ST.IsConcreteSpellID
local ResolveCDMAppliedAuraSpellID = ST.ResolveCDMAppliedAuraSpellID
local pendingViewerAuraMapToken = 0
local pendingViewerAuraMapAllowGate = true
local FindChildInViewers

-- Pass-scoped resolution memos. ACTIVE ONLY between BeginAuraCandidatePass and
-- EndAuraCandidatePass, which wrap exactly one aura rebind pass; with no pass
-- open every resolver in this file must behave exactly as an unmemoized call.
-- The stamp is the frame time the pass opened: a pass is synchronous within one
-- frame, so an error escaping before the end call cannot carry a stale memo
-- into a later frame.
local candidatePassActive = false
local candidatePassStamp = 0
local candidateMemoPlain = {}
local candidateMemoConstrained = {}
local viewerFrameMissPlain = {}
local viewerFrameMissBuff = {}

local function IsAuraCandidatePassActive()
    return candidatePassActive and candidatePassStamp == GetTime()
end

local function WipeAuraCandidatePassMemos()
    wipe(candidateMemoPlain)
    wipe(candidateMemoConstrained)
    wipe(viewerFrameMissPlain)
    wipe(viewerFrameMissBuff)
end

function ST.BeginAuraCandidatePass()
    WipeAuraCandidatePassMemos()
    candidatePassActive = true
    candidatePassStamp = GetTime()
end

function ST.EndAuraCandidatePass()
    candidatePassActive = false
    candidatePassStamp = 0
    WipeAuraCandidatePassMemos()
end

-- Viewer association fingerprint: the ordered per-row spell associations that
-- BuildViewerAuraMap's TAIL consumes (sound map, aura rebind, config refresh).
-- Frame-derived on purpose — an item frame's cooldownInfo IS the CDM data
-- provider's cached row table, and Blizzard mutates that table in place when a
-- spell override flips, so this is the only view that sees an Eclipse-style
-- transform. The static C-side data behind those tables changes only through
-- CooldownViewerSettings.OnDataChanged, spec change and login, every one of
-- which drives an UNGATED rebuild.
--
-- Row order comes from layoutIndex, never GetChildren() order: RefreshLayout
-- releases the item pool through a hash walk and re-acquires LIFO, so which
-- frame holds which row reshuffles on every pass even when the rows are
-- identical.
local viewerAssociationFingerprint = {}
local viewerAssociationFingerprintLength = 0
local viewerAssociationFingerprintKnown = false
local pendingViewerAssociation = {}
local pendingViewerAssociationLength = 0
local pendingViewerAssociationUnknown = false
local viewerAssociationRowScratch = {}

-- Fail open: a value that is secret or not numeric makes the whole fingerprint
-- unknown, and an unknown fingerprint always compares as changed.
local function PushViewerAssociationValue(value)
    if pendingViewerAssociationUnknown then return end
    if issecretvalue(value) then
        pendingViewerAssociationUnknown = true
        return
    end
    local numeric = (value == nil) and 0 or tonumber(value)
    if type(numeric) ~= "number" then
        pendingViewerAssociationUnknown = true
        return
    end
    pendingViewerAssociationLength = pendingViewerAssociationLength + 1
    pendingViewerAssociation[pendingViewerAssociationLength] = numeric
end

local function BeginViewerAssociationFingerprint()
    pendingViewerAssociationLength = 0
    pendingViewerAssociationUnknown = false
end

-- Returns true when the associations differ from the last accepted
-- fingerprint, when they are unknown, or when none was recorded yet.
local function CommitViewerAssociationFingerprint()
    if pendingViewerAssociationUnknown then
        viewerAssociationFingerprintKnown = false
        viewerAssociationFingerprintLength = 0
        wipe(viewerAssociationFingerprint)
        return true
    end
    local changed = not viewerAssociationFingerprintKnown
        or viewerAssociationFingerprintLength ~= pendingViewerAssociationLength
    if not changed then
        for i = 1, pendingViewerAssociationLength do
            if viewerAssociationFingerprint[i] ~= pendingViewerAssociation[i] then
                changed = true
                break
            end
        end
    end
    if changed then
        wipe(viewerAssociationFingerprint)
        for i = 1, pendingViewerAssociationLength do
            viewerAssociationFingerprint[i] = pendingViewerAssociation[i]
        end
        viewerAssociationFingerprintLength = pendingViewerAssociationLength
        viewerAssociationFingerprintKnown = true
    end
    return changed
end

local function IsBuffViewerChild(frame)
    if not frame then return false end
    local parent = frame:GetParent()
    local parentName = parent and parent:GetName()
    return BUFF_VIEWER_SET[parentName] == true
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
    local rowCount = 0
    wipe(viewerAssociationRowScratch)
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
            -- Fingerprint bucket. A released pool frame carries no
            -- cooldownInfo, so every child reaching here is an active row and
            -- holds the layoutIndex RefreshLayout stamped on it.
            local layoutIndex = tonumber(child.layoutIndex)
            if layoutIndex and layoutIndex >= 1 then
                viewerAssociationRowScratch[layoutIndex] = child
                if layoutIndex > rowCount then
                    rowCount = layoutIndex
                end
            else
                pendingViewerAssociationUnknown = true
            end
        end
    end

    -- Fixed per-row shape (cooldownID, spellID, both override forms, linked
    -- count, linked IDs) so a variable-length linked list can never alias the
    -- next row, and a row hole emits the same header with no associations.
    PushViewerAssociationValue(rowCount)
    for index = 1, rowCount do
        local child = viewerAssociationRowScratch[index]
        local info = child and child.cooldownInfo
        if info then
            PushViewerAssociationValue(child.cooldownID)
            PushViewerAssociationValue(info.spellID)
            PushViewerAssociationValue(info.overrideSpellID)
            PushViewerAssociationValue(info.overrideTooltipSpellID)
            local linked = info.linkedSpellIDs
            local linkedCount = linked and #linked or 0
            PushViewerAssociationValue(linkedCount)
            for linkedIndex = 1, linkedCount do
                PushViewerAssociationValue(linked[linkedIndex])
            end
        else
            PushViewerAssociationValue(0)
            PushViewerAssociationValue(0)
            PushViewerAssociationValue(0)
            PushViewerAssociationValue(0)
            PushViewerAssociationValue(0)
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

-- The ONE tracked-aura unit classifier; every surface (runtime binds, config,
-- migrations, panels, custom bars) must route through it or their answers
-- drift. C_Spell.IsSpellHarmful answers "can this spell target hostiles",
-- NOT buff-vs-debuff: a self-buff whose record carries an enemy-facing rider
-- effect reads harmful even on its applied-aura ID, and no static API
-- distinguishes that shape from a real target debuff. Those auras need an
-- explicit unit here; everything else keeps the harmful probe.
local AURA_UNIT_OVERRIDES = {
    -- Galactic Guardian: the buff lands on the player, but its record's
    -- empowered-Moonfire hook targets the enemy, so it reads harmful.
    [213708] = "player",
}

local function ClassifyAuraSpellUnit(spellID)
    local numericID = tonumber(spellID)
    if not (numericID and C_Spell.DoesSpellExist(numericID)) then
        return nil
    end
    local override = AURA_UNIT_OVERRIDES[numericID]
    if override then
        return override
    end
    return C_Spell.IsSpellHarmful(numericID) and "target" or "player"
end
ST.ClassifyAuraSpellUnit = ClassifyAuraSpellUnit
CooldownCompanion.ClassifyAuraSpellUnit = ClassifyAuraSpellUnit

local function IsAuraCandidateUnitAllowed(spellID, requiredUnit)
    if requiredUnit == nil then
        return true
    end
    local unit = ClassifyAuraSpellUnit(spellID)
    return unit == requiredUnit
end

-- Explicit candidate lists own the slot polarity for ordinary spell entries.
-- The migration and config writer keep those lists single-polarity; the stored
-- unit remains the fallback when spell data is temporarily unavailable.
local function ResolveExplicitAuraCandidateUnit(buttonData)
    local rawIDs = buttonData and buttonData.auraSpellID and tostring(buttonData.auraSpellID) or nil
    if not rawIDs then
        return nil
    end
    for id in rawIDs:gmatch("%d+") do
        local unit = ClassifyAuraSpellUnit(id)
        if unit then
            return unit
        end
    end
    if buttonData.auraUnit == "player" or buttonData.auraUnit == "target" then
        return buttonData.auraUnit
    end
    return nil
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

-- Abilities that apply an aura under a DIFFERENT spellID (e.g. Rake 1822
-- applies bleed 155722) get no linkage from GetCooldownAuraBySpellID; the only
-- API source is the Cooldown Manager's data rows — cooldownInfo.linkedSpellIDs
-- is the exact list Blizzard's own tracked bars match auras against. Pure data
-- API (no viewer frames); the spell->cooldownID map is the one SoundAlerts
-- maintains, rebuilt alongside the viewer aura map.
--
-- Deliberately NO distinct-identity guard here: that guard protects DISPLAY
-- identity (which icon/name a plain spell entry shows), and the standing
-- linked-ID ruling is that multi-link ambiguity gates display labels only,
-- never resolution. Candidate sets carry EVERY linked stage so Blizzard picks
-- the active one — Roll the Bones (1214909) links only distinct-NAMED outcome
-- auras (One of a Kind 1214933, ...), and guarding them out here left a plain
-- spell entry's includeSpellIDs matching none of the buffs the cast applies,
-- while the same spell added AS an aura (guard-free path) matched them all.
local function AppendCdmLinkedAuraIDs(candidateSet, orderedSet, orderedIDs, buttonData, spellID, requiredUnit)
    local addon = CooldownCompanion
    addon:EnsureSoundAlertSpellMap()
    local cooldownIDs = addon._soundAlertSpellToCooldownIDs and addon._soundAlertSpellToCooldownIDs[spellID]
    if not cooldownIDs then
        return
    end
    for cooldownID in pairs(cooldownIDs) do
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
        if info and info.linkedSpellIDs then
            for _, linkedID in ipairs(info.linkedSpellIDs) do
                if IsAuraCandidateUnitAllowed(linkedID, requiredUnit) then
                    AppendOrderedAuraCandidateID(candidateSet, orderedSet, orderedIDs, linkedID)
                end
            end
        end
    end
end

-- Pure-data applied-aura resolution: no viewer frames, so it works with the
-- Cooldown Manager display disabled and before viewers materialize. Walks the
-- CDM data rows for the spell (the same spell->cooldownID map SoundAlerts
-- maintains) and returns the applied-aura identity when the spell's OWN row
-- links one under a different spellID. The map keys every row identity
-- (overrides, linked, base), so a row only counts when its base spellID is
-- the queried spell and no override identity is active — the exact branch
-- shape of the frame path in ResolveDirectBuffViewerSpellID, so the two
-- paths cannot disagree, and a row reached through one of its OTHER linked
-- IDs can never donate a sibling aura.
local function ResolveCdmLinkedAppliedAuraSpellID(spellID)
    local numericID = tonumber(spellID)
    if not numericID or numericID == 0 then
        return nil
    end
    local addon = CooldownCompanion
    addon:EnsureSoundAlertSpellMap()
    local cooldownIDs = addon._soundAlertSpellToCooldownIDs
        and addon._soundAlertSpellToCooldownIDs[numericID]
    if not cooldownIDs then
        return nil
    end
    -- Deterministic walk: the map values are sets, and hash order must not
    -- decide identity when a spell sits in several rows.
    local orderedCooldownIDs = {}
    for cooldownID in pairs(cooldownIDs) do
        orderedCooldownIDs[#orderedCooldownIDs + 1] = cooldownID
    end
    table.sort(orderedCooldownIDs)
    for _, cooldownID in ipairs(orderedCooldownIDs) do
        local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
        -- Overrides gate this row only when they are a DIFFERENT spell (a
        -- real transform). Blizzard routinely stamps overrideSpellID with
        -- the row's own spellID (Shield of the Righteous carries
        -- overrideSpellID=53600 on live); a self-override is not a
        -- transform and must not disqualify the row.
        if info and tonumber(info.spellID) == numericID
            and not (IsConcreteSpellID(info.overrideTooltipSpellID)
                and info.overrideTooltipSpellID ~= numericID)
            and not (IsConcreteSpellID(info.overrideSpellID)
                and info.overrideSpellID ~= numericID) then
            local appliedID = ResolveCDMAppliedAuraSpellID(info, numericID)
            if appliedID and appliedID ~= numericID then
                return appliedID
            end
        end
    end
    return nil
end

-- The one frame-free applied-identity step, shared by every resolver that
-- consults it, so the guard set cannot drift between call sites. The
-- distinct-identity guard is a no-op for standalone aura entries (their
-- entry shape is not a plain spell entry), matching each chain's existing
-- guard posture.
local function ResolveLinkedAppliedAuraForButton(buttonData, spellID)
    local linkedAppliedID = ResolveCdmLinkedAppliedAuraSpellID(spellID)
    if linkedAppliedID and not IsDistinctAuraIdentityForButton(buttonData, linkedAppliedID) then
        return linkedAppliedID
    end
    return nil
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

    -- A miss costs a GetChildren() sweep of all four viewers, and one rebind
    -- pass asks for the same misses over and over. The memo is PASS-SCOPED and
    -- never persistent: outside a pass a viewer can materialize a child at any
    -- time, and a remembered miss would then be wrong.
    local missMemo = buffOnly and viewerFrameMissBuff or viewerFrameMissPlain
    local passActive = IsAuraCandidatePassActive()
    if passActive and missMemo[numericID] then
        return nil
    end

    candidate = FindChildInViewers(VIEWER_NAMES, numericID, buffOnly)
    if candidate then
        CooldownCompanion.viewerAuraFrames[numericID] = candidate
    elseif passActive then
        missMemo[numericID] = true
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
        -- Overrides equal to the row's own spellID are Blizzard's routine
        -- self-stamp, not a transform; returning them verbatim would
        -- short-circuit the applied-aura rule below (Shield of the
        -- Righteous carries overrideSpellID=53600 on live).
        local tooltipOverride = tonumber(info.overrideTooltipSpellID)
        if tooltipOverride and tooltipOverride ~= 0 and tooltipOverride ~= numericID then
            return tooltipOverride
        end

        local spellOverride = tonumber(info.overrideSpellID)
        if spellOverride and spellOverride ~= 0 and spellOverride ~= numericID then
            return spellOverride
        end

        -- The row identity is the cast spell; the applied aura may live only
        -- in linkedSpellIDs (Fire Breath 357208 -> 357209, Shield of the
        -- Righteous 53600 -> 132403). Override forms above stay verbatim --
        -- they are the dynamic identity of transforming spells. Parenthesized
        -- to drop the helper's ambiguity flag from this single-value contract.
        return (ResolveCDMAppliedAuraSpellID(info, numericID))
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

    -- Frame-free twin of the direct resolution above, so the applied identity
    -- still leads the candidate order when no buff viewer frame exists.
    local linkedAppliedID = ResolveLinkedAppliedAuraForButton(buttonData, baseId)
    if linkedAppliedID then
        AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, linkedAppliedID)
    end

    local resolvedAuraId = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
    if resolvedAuraId then
        AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, resolvedAuraId)
    end

    AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData.id)
    AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, baseId)

    AppendCdmLinkedAuraIDs(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData, baseId)

    return orderedCandidateIDs, candidateIDs, orderedCandidateSet
end

-- originalCandidateSet is REQUIRED: the sole caller has just built it, and
-- re-deriving it here re-ran the whole standalone resolution a second time.
local function AppendStandaloneFallbackAuraCandidateIDs(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData, rawIDs, originalCandidateSet)
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

local function BuildOrderedAuraCandidateIDs(buttonData, constrainImplicitFallbacks)
    local candidateIDs = {}
    local orderedCandidateSet = {}
    local orderedCandidateIDs = {}

    if not (buttonData and buttonData.type == "spell") then
        return orderedCandidateIDs, candidateIDs, orderedCandidateSet
    end

    local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id

    local function AppendSpellAssociationAuraIDs(requiredUnit)
        if IsAuraCandidateUnitAllowed(buttonData.id, requiredUnit) then
            AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData.id)
        end
        if IsAuraCandidateUnitAllowed(baseId, requiredUnit) then
            AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, baseId)
        end

        local resolvedAuraId = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
        if resolvedAuraId
            and not IsDistinctAuraIdentityForButton(buttonData, resolvedAuraId)
            and IsAuraCandidateUnitAllowed(resolvedAuraId, requiredUnit) then
            AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, resolvedAuraId)
        end

        AppendCdmLinkedAuraIDs(candidateIDs, orderedCandidateSet, orderedCandidateIDs,
            buttonData, baseId, requiredUnit)
    end

    if buttonData.addedAs == "aura" then
        local originalAuraIDs, originalCandidateSet = BuildStandaloneOriginalAuraCandidateIDs(buttonData)
        for _, spellID in ipairs(originalAuraIDs) do
            AppendOrderedAuraCandidateID(candidateIDs, orderedCandidateSet, orderedCandidateIDs, spellID)
        end
        AppendStandaloneFallbackAuraCandidateIDs(candidateIDs, orderedCandidateSet, orderedCandidateIDs,
            buttonData, buttonData.auraSpellID, originalCandidateSet)
    else
        AppendOrderedAuraCandidateIDsFromString(candidateIDs, orderedCandidateSet, orderedCandidateIDs, buttonData.auraSpellID)
        local requiredUnit = constrainImplicitFallbacks
            and ResolveExplicitAuraCandidateUnit(buttonData) or nil
        AppendSpellAssociationAuraIDs(requiredUnit)
    end

    return orderedCandidateIDs, candidateIDs, orderedCandidateSet
end

-- The one memoized entrance to candidate resolution: every resolver below
-- routes through it, so one rebind pass resolves each (entry, constrain flag)
-- pair exactly once no matter how many surfaces ask. With no pass open this is
-- a plain call through to the builder, so nothing outside a pass changes.
--
-- The memo keys on the entry TABLE, so it is only valid while that table's
-- candidate-relevant fields (type, id, addedAs, auraSpellID, auraUnit) hold
-- still — which is the pass's own contract. It never writes to the entry.
local function ResolveOrderedAuraCandidateIDs(buttonData, constrainImplicitFallbacks)
    if not (type(buttonData) == "table" and IsAuraCandidatePassActive()) then
        return BuildOrderedAuraCandidateIDs(buttonData, constrainImplicitFallbacks)
    end
    local memo = constrainImplicitFallbacks and candidateMemoConstrained or candidateMemoPlain
    local cached = memo[buttonData]
    if not cached then
        local orderedCandidateIDs, candidateIDs, orderedCandidateSet =
            BuildOrderedAuraCandidateIDs(buttonData, constrainImplicitFallbacks)
        cached = { orderedCandidateIDs, candidateIDs, orderedCandidateSet }
        memo[buttonData] = cached
    end
    return cached[1], cached[2], cached[3]
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
    -- Target-existence and target-hostility force conditions are read fresh by
    -- the alpha pass, so a swap has to find the driver running.
    self:EnsureAlphaDriverArmed()
end


local function ResolveImplicitSpellEntryAuraSpellID(buttonData)
    if buttonData.type ~= "spell" then return nil end
    local directAuraID = ResolveDirectBuffViewerSpellID(buttonData.id)
    if directAuraID and not IsDistinctAuraIdentityForButton(buttonData, directAuraID) then
        return directAuraID
    end
    -- Resolve through base spell so form-variant spells (e.g. Stampeding
    -- Roar: 106898/77764/77761) use the base ID for aura lookups — the
    -- buff is always applied as the base spell regardless of form.
    local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id
    -- Frame-free twin of the direct resolution above (works with the CDM
    -- display disabled): a CDM data row that links the applied aura under
    -- a different spellID owns the identity, per Blizzard's own matcher.
    local linkedAppliedID = ResolveLinkedAppliedAuraForButton(buttonData, baseId)
    if linkedAppliedID then
        return linkedAppliedID
    end
    local auraId = NormalizeResolvedAuraSpellID(baseId, C_UnitAuras.GetCooldownAuraBySpellID(baseId))
    if auraId and not IsDistinctAuraIdentityForButton(buttonData, auraId) then
        return auraId
    end
    -- Many spells share the same ID for cast and buff; fall back to the base spell ID
    return baseId
end

function CooldownCompanion:ResolveAuraSpellID(buttonData)
    if not buttonData.auraTracking then return nil end
    if buttonData.addedAs ~= "aura" and buttonData.auraSpellID then
        local first = tostring(buttonData.auraSpellID):match("%d+")
        return first and tonumber(first)
    end
    if buttonData.addedAs == "aura" then
        local orderedCandidateIDs = ResolveOrderedAuraCandidateIDs(buttonData)
        return orderedCandidateIDs[1]
    end
    return ResolveImplicitSpellEntryAuraSpellID(buttonData)
end

-- Config display only: the spell entry's own applied-aura identity,
-- independent of any explicit tracked list (ResolveAuraSpellID
-- short-circuits on that list). Not a bind input.
function CooldownCompanion:ResolveImplicitAuraSpellID(buttonData)
    if not (type(buttonData) == "table" and buttonData.addedAs ~= "aura") then
        return nil
    end
    return ResolveImplicitSpellEntryAuraSpellID(buttonData)
end

-- Ordered candidate list (primary first), for callers that need priority
-- order rather than a lookup set — e.g. the pandemic-threshold base-duration
-- query, which takes the first candidate that reports a real aura duration.
-- The returned list is read-only for callers: inside a rebind pass it is the
-- memo's own array and is handed to every asker for that entry.
function CooldownCompanion:GetOrderedAuraCandidateSpellIDs(buttonData, constrainImplicitFallbacks)
    return (ResolveOrderedAuraCandidateIDs(buttonData, constrainImplicitFallbacks))
end

-- Full ordered candidate set as a lookup table, for AuraDisplay's
-- includeSpellIDs filters (config-time resolution; not combat-blocked).
-- Aura-capable panel entries pass constrainImplicitFallbacks=true so an
-- explicit Aura list owns the slot polarity; Custom Bars omit it and retain
-- their existing candidate behavior.
-- The set is built fresh on every call even when the ordered list came from
-- the pass memo: it is handed to Blizzard as an includeSpellIDs filter and
-- retained per slot, so no two binds may share one table.
function CooldownCompanion:GetAuraCandidateSpellIDSet(buttonData, constrainImplicitFallbacks)
    local orderedCandidateIDs = ResolveOrderedAuraCandidateIDs(buttonData, constrainImplicitFallbacks)
    if #orderedCandidateIDs == 0 then return nil end
    local set = {}
    for _, spellID in ipairs(orderedCandidateIDs) do
        set[spellID] = true
    end
    return set
end

function CooldownCompanion:InferConfirmedAuraSpellIDString(buttonData)
    if not (buttonData and buttonData.type == "spell") then
        return nil
    end

    if buttonData.auraSpellID then
        return tostring(buttonData.auraSpellID)
    end

    local directAuraID = ResolveDirectBuffViewerSpellID(buttonData.id)
    if directAuraID and not IsDistinctAuraIdentityForButton(buttonData, directAuraID) then
        return tostring(directAuraID)
    end

    local baseId = C_Spell.GetBaseSpell(buttonData.id) or buttonData.id
    -- Frame-free twin of the direct resolution above: this is the resolver
    -- that PERSISTS into stored config, so it must agree with the live
    -- chain when no buff viewer frame exists.
    local linkedAppliedID = ResolveLinkedAppliedAuraForButton(buttonData, baseId)
    if linkedAppliedID and linkedAppliedID ~= buttonData.id then
        return tostring(linkedAppliedID)
    end
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

    local numericSpellID = tonumber(buttonData.id)
    local baseId = numericSpellID and (C_Spell.GetBaseSpell(numericSpellID) or numericSpellID) or nil

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

    if not numericSpellID then
        return nil
    end

    local directAuraID = ResolveDirectBuffViewerSpellID(buttonData.id)
    if directAuraID and not IsDistinctAuraIdentityForButton(buttonData, directAuraID) then
        return directAuraID
    end

    -- Frame-free twin of the direct resolution above.
    local linkedAppliedID = ResolveLinkedAppliedAuraForButton(buttonData, baseId)
    if linkedAppliedID then
        return linkedAppliedID
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
        return ClassifyAuraSpellUnit(resolvedSpellID) or "player"
    end
    if buttonData and buttonData.id then
        return ClassifyAuraSpellUnit(buttonData.id) or "player"
    end
    return "player"
end

-- Aura shell (12.1 compositing): an aura entry that yields its resting
-- appearance so the native aura display renders the active visual on top.
-- Two forms, mutually exclusive in config:
--   hideWhileAuraNotActive -> hidden shell, alpha 0
--   auraShellDim           -> dimmed shell, DIM_FALLBACK_ALPHA
-- Both compose the same full active visual, so every consumer that asks
-- "is this a shell entry" must accept either. Owned here because four
-- callers across Core and ButtonFrame need the same answer and drifted
-- when they each kept their own copy.
--
-- auraShellDim is 12.1-native and deliberately NOT the main-era
-- useBaselineAlphaFallback key it replaces. That key's presence was
-- ambiguous: either a live setting, or residue main left behind when its
-- partner toggle was switched back off -- and nothing in the stored shape
-- distinguishes them. Migrating onto a distinct key makes the pass
-- idempotent by construction: it converts the legacy pair, clears legacy
-- orphans, and never has cause to touch this key at all.
function CooldownCompanion:IsAuraShellEntry(buttonData)
    if not buttonData then return false end
    if not (buttonData.auraTracking or buttonData.addedAs == "aura") then
        return false
    end
    return buttonData.hideWhileAuraNotActive == true
        or buttonData.auraShellDim == true
end

-- Resting alpha for a shell entry. Hide wins when both keys are somehow set,
-- matching the shell predicate's intent.
-- Callers gate on IsAuraShellEntry first, so a non-shell entry never
-- reaches this.
function CooldownCompanion:GetAuraShellRestingAlpha(buttonData)
    if buttonData and buttonData.hideWhileAuraNotActive == true then
        return 0
    end
    return self.DIM_FALLBACK_ALPHA
end

-- Keep Cooldown Swipe (12.1 compositing): the entry opts out of the
-- aura display's icon takeover, so the CC icon and its own cooldown swipe
-- stay visible while the aura contributes its overlays (stack text,
-- duration text, glows) per their own settings. Only meaningful where a
-- spell cooldown exists to keep: never standalone aura entries or
-- passives, and never a shell entry (its CC layer is statically hidden or
-- dimmed, so with the cover off there would be nothing underneath).
-- Icons-only is a host property and stays at call sites; the stored key
-- is inert, never stripped, on other hosts.
--
-- The flag is a STYLE key (the whileAuraActive override section), so every
-- caller must hand in the style the host actually renders with -- the
-- panel style, or the entry's effective style where a section is promoted.
-- A nil style reads as off rather than falling back to the panel: there is
-- no correct panel to guess at here, and the entry-shape terms below stay
-- authoritative either way.
function CooldownCompanion:IsKeepSpellCooldownSwipeEntry(buttonData, style)
    return buttonData ~= nil
        and style ~= nil
        and style.auraKeepSpellCooldownSwipe == true
        and buttonData.auraTracking == true
        and buttonData.addedAs ~= "aura"
        and buttonData.isPassive ~= true
        and not self:IsAuraShellEntry(buttonData)
end

-- Draw policy for the aura duration swipe, shared by the slot kit and both
-- preview stand-ins so the three sites cannot drift: the style toggle must
-- not be off, and a keep-swipe entry never draws it (the spell's own
-- cooldown swipe owns the icon; two swipes would stack). Host rules stay
-- with the callers -- bars have no aura swipe at all.
function CooldownCompanion:ShouldDrawAuraDurationSwipe(buttonData, style)
    return (not style or style.showAuraDurationSwipe ~= false)
        and not self:IsKeepSpellCooldownSwipeEntry(buttonData, style)
end

-- Desaturate-while-active policy for the aura layer, shared by the slot
-- kit and both preview stand-ins so the sites cannot drift (same pattern
-- as the swipe policy above). Pure flag policy: whether an aura-layer
-- icon region is visible to carry it stays with the callers -- the kit's
-- alpha writes live, explicit composition mirrors in the previews.
--
-- The invert flag is a style key (whileAuraActive section); neverDesaturate
-- stays entry data, so the two are read from different stores on purpose.
function CooldownCompanion:ShouldDesaturateAuraLayerWhileActive(buttonData, style)
    return buttonData ~= nil
        and style ~= nil
        and style.invertAuraDesaturationLogic == true
        and not buttonData.neverDesaturate
end

-- Aura config previews draw onto CC-side regions -- the exact ones a shell
-- makes transparent -- so a shell exposes for as long as one runs. Which
-- kinds qualify depends on the display mode, because the regions differ:
--   icons: the duration text and stack text live on overlayFrame, and the
--          swipe widget sits over the button chrome.
--   bars:  the duration BAR preview drains the statusBar, and the duration
--          and stack text write into barTextFrame/overlayFrame. There is no
--          swipe on a bar.
-- Owned here rather than per-mode because bar mode's copy was cloned from
-- the icon list without swapping the kinds -- it claimed the icon-only
-- swipe and omitted the bar-only drain, which is the whole reason the two
-- sets now live side by side where a mismatch is visible.
local AURA_PREVIEW_SHELL_KINDS_ICON = {
    aura_duration_text = true,
    -- Same stand-in as the duration text, so the same shell has to open.
    pandemic_marker = true,
    aura_stack_text = true,
    aura_duration_swipe = true,
}

local AURA_PREVIEW_SHELL_KINDS_BAR = {
    aura_duration_bar = true,
    aura_duration_text = true,
    pandemic_marker = true,
    aura_stack_text = true,
}

function CooldownCompanion:IsAuraPreviewKindExposingShell(kind, isBar)
    if not kind then return false end
    local kinds = isBar and AURA_PREVIEW_SHELL_KINDS_BAR or AURA_PREVIEW_SHELL_KINDS_ICON
    return kinds[kind] == true
end

-- The one live shell-alpha decision, for both display modes: 1 = no shell (the
-- entry renders normally, including while an unlock preview exposes it),
-- 0 = full shell (the aura display is the entire visible button),
-- fractional = the dim shell under the full-strength aura display. Static
-- by design -- resolved at style time, never from aura state. Icon and bar
-- mode each kept a private copy of this chain and the copies drifted (the
-- bar one cloned the icon preview-kind list), so it lives with the shell
-- predicate now.
function CooldownCompanion:GetAuraShellAlpha(button, buttonData)
    if not self:IsAuraShellEntry(buttonData) then
        return 1
    end
    local frame = button and button:GetParent()
    if not self._combatForcedLock
        and frame
        and (frame._containerUnlockPreviewActive == true
            or frame._panelUnlockPreviewActive == true) then
        return 1
    end
    return self:GetAuraShellRestingAlpha(buttonData)
end

-- Mode dispatch for the shell appliers, so call sites that serve both
-- display modes stop repeating the _isBar ternary. The appliers themselves
-- stay per-mode (they own different region sets) and are looked up through
-- ST at call time -- they are assigned by IconMode/BarMode, which load
-- after this file.
function ST._ApplyShellVisualsForButton(button, buttonData)
    if button._isBar then
        if ST._ApplyBarAuraShellVisuals then
            ST._ApplyBarAuraShellVisuals(button, buttonData)
        end
    elseif ST._ApplyAuraShellVisuals then
        ST._ApplyAuraShellVisuals(button, buttonData)
    end
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

-- 12.1 bar aura fill modes (PTR 6, tracker C2): the Blizzard-driven duration
-- timer, or the ApplicationBar stack fill. auraBar.mode == "stacks" — kept
-- dormant by the aura-rebuild migration exactly for this revival — selects
-- the stack fill; anything else means duration.

function CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    return type(auraBar) == "table" and auraBar.mode == "stacks"
end

function CooldownCompanion:SetBarPanelAuraStackDisplay(buttonData, wantStacks)
    if type(buttonData.auraBar) ~= "table" then
        if not wantStacks then return end
        buttonData.auraBar = {}
    end
    buttonData.auraBar.mode = wantStacks and "stacks" or "duration"
end

-- Stack display style (live parity, C2 round 3): how a stack-mode bar
-- renders — "segmented" (per-stack segments/blocks) or "continuous" (plain
-- fill growing with stacks). Stored in auraBar.stackDisplayMode, nil =
-- segmented. Live's specific stack_* mode values carried the style on the
-- mode key; the aura-rebuild migration splits them onto this vocabulary, so
-- a live "continuous" choice does revive as "continuous" and every other
-- live-era value resolves to the segmented default.
function CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    local mode = type(auraBar) == "table" and auraBar.stackDisplayMode or nil
    if mode == "continuous" then
        return "continuous"
    end
    return "segmented"
end

function CooldownCompanion:SetBarPanelAuraStackDisplayMode(buttonData, displayMode)
    if type(buttonData.auraBar) ~= "table" then
        if displayMode == nil or displayMode == "segmented" then return end
        buttonData.auraBar = {}
    end
    buttonData.auraBar.stackDisplayMode = displayMode ~= "segmented" and displayMode or nil
end

-- Segment gap (live parity): per-button width of the painted gap between
-- stack segments. Stored raw, clamped on read; 0 = solid unsegmented fill.
function CooldownCompanion:GetBarPanelAuraSegmentGap(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    local value = type(auraBar) == "table" and tonumber(auraBar.segmentGap) or nil
    if not value then return 4 end
    value = math.floor(value + 0.5)
    if value < 0 then return 0 end
    if value > 20 then return 20 end
    return value
end

function CooldownCompanion:SetBarPanelAuraSegmentGap(buttonData, value)
    if type(buttonData.auraBar) ~= "table" then
        buttonData.auraBar = {}
    end
    buttonData.auraBar.segmentGap = value
end

-- Segmented smoothing (live parity revival, tracker C2): whether a
-- segmented stack bar sweeps or snaps between stack counts. Same key and
-- "on"/"off" normalizer as the resource-side control — one feature in the
-- UI even though the mechanism differs (Blizzard's ApplicationBar
-- interpolation here, CC-side smoothing there). Live wrote the same
-- "on"/"off" vocabulary, so the aura-rebuild migration carries stored
-- values over unchanged and nil takes the "on" default. Continuous stack
-- fills always smooth and ignore this (owner ruling 2026-07-24, resource
-- parity: the toggle governs segmented displays only).
function CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    local value = type(auraBar) == "table" and auraBar.segmentedSmoothing or nil
    return ST.NormalizeSegmentedSmoothing(value)
end

function CooldownCompanion:SetBarPanelAuraSegmentedSmoothing(buttonData, value)
    value = ST.NormalizeSegmentedSmoothing(value)
    if type(buttonData.auraBar) ~= "table" then
        if value == ST.SEGMENTED_SMOOTHING_ON then return end
        buttonData.auraBar = {}
    end
    buttonData.auraBar.segmentedSmoothing = value ~= ST.SEGMENTED_SMOOTHING_ON and value or nil
end

-- Widget block gap presets (2026-08-15): the gap between block-style
-- stacks is baked into the bundled fill atlas (the Blizzard-driven fill
-- reveals whole blocks by cropping that artwork), so the choice is a
-- PRESET picking which atlas set the bind uses, never a free pixel
-- value. Values are atlas texels of 512; 10 is the original artwork and
-- the stored-nil default.
ST.STACK_BLOCK_GAP_DEFAULT = 10
local STACK_BLOCK_GAP_PRESETS = { [0] = true, [5] = true, [10] = true, [15] = true, [20] = true }
local STACK_BLOCK_GAP_STEPS = { 20, 15, 10, 5, 0 }

-- Artwork exists only where every block keeps >= 6 of the atlas's 512
-- texels (the bound the original gap-20 set was drawn to); wide gaps at
-- high block counts would otherwise eat the blocks entirely. The atlas
-- generator, this predicate, and the config dropdown all share the rule.
function CooldownCompanion:IsStackBlockGapPresetAvailable(gapTexels, maxStacks)
    if not STACK_BLOCK_GAP_PRESETS[gapTexels] then return false end
    if not maxStacks then return true end
    return (512 - (maxStacks - 1) * gapTexels) / maxStacks >= 6
end

-- With maxStacks, the stored preset steps DOWN to the nearest one whose
-- artwork exists for that count (a talent can raise the max after the
-- choice was made); the stored value is preserved so a lower max
-- restores it.
function CooldownCompanion:GetAuraStackBlockGapTexels(buttonData, maxStacks)
    local auraBar = buttonData and buttonData.auraBar
    local value = type(auraBar) == "table" and tonumber(auraBar.blockGap) or nil
    if not (value and STACK_BLOCK_GAP_PRESETS[value]) then
        value = ST.STACK_BLOCK_GAP_DEFAULT
    end
    if maxStacks then
        for _, preset in ipairs(STACK_BLOCK_GAP_STEPS) do
            if preset <= value and self:IsStackBlockGapPresetAvailable(preset, maxStacks) then
                return preset
            end
        end
        return 0
    end
    return value
end

function CooldownCompanion:SetAuraStackBlockGapTexels(buttonData, value)
    value = tonumber(value)
    if not (value and STACK_BLOCK_GAP_PRESETS[value]) or value == ST.STACK_BLOCK_GAP_DEFAULT then
        value = nil
    end
    if type(buttonData.auraBar) ~= "table" then
        if value == nil then return end
        buttonData.auraBar = {}
    end
    buttonData.auraBar.blockGap = value
end

-- Stack text formatter options. The count is SECRET in combat, so these
-- settings only shape the engine-side NumericRuleFormatter breakpoints;
-- nothing here reads or compares the live count. Stored in auraBar beside
-- the other per-entry stack settings; nil keys mean off.
ST.AURA_STACK_THRESHOLD_COLOR_DEFAULT = { 1, 0.82, 0, 1 }
ST.AURA_STACK_MAX_COLOR_DEFAULT = { 1, 0.25, 0.1, 1 }

function CooldownCompanion:IsAuraStackCountAtOneEnabled(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    return type(auraBar) == "table" and auraBar.showCountAtOne == true
end

function CooldownCompanion:SetAuraStackCountAtOneEnabled(buttonData, enabled)
    if type(buttonData.auraBar) ~= "table" then
        if not enabled then return end
        buttonData.auraBar = {}
    end
    buttonData.auraBar.showCountAtOne = enabled and true or nil
end

function CooldownCompanion:GetAuraStackThresholdValue(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    local value = type(auraBar) == "table" and tonumber(auraBar.thresholdValue) or nil
    if not value then return nil end
    value = math.floor(value + 0.5)
    if value < 2 then return 2 end
    return value
end

function CooldownCompanion:SetAuraStackThresholdValue(buttonData, value)
    if type(buttonData.auraBar) ~= "table" then
        if value == nil then return end
        buttonData.auraBar = {}
    end
    buttonData.auraBar.thresholdValue = value
end

function CooldownCompanion:GetAuraStackThresholdColor(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    local color = type(auraBar) == "table" and auraBar.thresholdColor or nil
    if type(color) == "table" then return color end
    return ST.AURA_STACK_THRESHOLD_COLOR_DEFAULT
end

function CooldownCompanion:IsAuraStackMaxColorEnabled(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    return type(auraBar) == "table" and auraBar.maxColorEnabled == true
end

function CooldownCompanion:SetAuraStackMaxColorEnabled(buttonData, enabled)
    if type(buttonData.auraBar) ~= "table" then
        if not enabled then return end
        buttonData.auraBar = {}
    end
    buttonData.auraBar.maxColorEnabled = enabled and true or nil
end

function CooldownCompanion:GetAuraStackMaxColor(buttonData)
    local auraBar = buttonData and buttonData.auraBar
    local color = type(auraBar) == "table" and auraBar.maxColor or nil
    if type(color) == "table" then return color end
    return ST.AURA_STACK_MAX_COLOR_DEFAULT
end

-- The ONE resolver for the whole feature (review batch 2026-08-15): every
-- consumer — formatter breakpoints, config previews — reads this same
-- clamped view, so the clamp/prefer rules cannot drift between them.
-- Returns nil when the feature is off for this entry.
--   threshold      integer >= 2, capped at maxStacks when one resolved
--   maxOn          true only when enabled AND maxStacks resolved
--   maxStacks      automatic max (nil when the game reports none)
--   thresholdColor / maxColor   display-only tables; never mutate them
function CooldownCompanion:ResolveAuraStackThresholdPolicy(buttonData)
    local threshold = self:GetAuraStackThresholdValue(buttonData)
    local maxOn = self:IsAuraStackMaxColorEnabled(buttonData)
    if not (threshold or maxOn) then return nil end
    local maxStacks = self:GetAuraStackBarMax(buttonData, true)
    if maxOn and not maxStacks then maxOn = false end
    if threshold and maxStacks and threshold > maxStacks then threshold = maxStacks end
    if not (threshold or maxOn) then return nil end
    return {
        threshold = threshold,
        maxOn = maxOn,
        maxStacks = maxStacks,
        thresholdColor = self:GetAuraStackThresholdColor(buttonData),
        maxColor = self:GetAuraStackMaxColor(buttonData),
    }
end

-- Automatic max-stacks resolution (owner ruling: automatic only, no manual
-- field). The lookup is talent-aware and returns 0 for IDs that carry no
-- stacking aura (V24), so the highest candidate wins and anything ≤ 1 means
-- "not a stacking aura" — callers fall back to the duration fill. The return
-- is documented SecretWhenUnitAuraRestricted; callers run OOC, but a secret
-- is still discarded before any comparison.
function CooldownCompanion:GetAuraStackBarMax(buttonData, constrainImplicitFallbacks)
    local getMax = C_Spell.GetSpellMaxCumulativeAuraApplications
    if not getMax then return nil end
    -- The ordered list holds exactly the IDs the candidate SET is keyed by,
    -- and the highest max wins regardless of order, so this needs no set table
    -- of its own.
    local orderedCandidateIDs = ResolveOrderedAuraCandidateIDs(buttonData, constrainImplicitFallbacks)
    if #orderedCandidateIDs == 0 then return nil end
    local best = 0
    for _, spellID in ipairs(orderedCandidateIDs) do
        local maxApplications = getMax(spellID)
        if not issecretvalue(maxApplications) and type(maxApplications) == "number"
            and maxApplications > best then
            best = maxApplications
        end
    end
    if best > 1 then
        return best
    end
    return nil
end


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

-- allowAssociationGate is OPT-IN, so a caller added later inherits today's
-- unconditional behavior. It is also STICKY across the coalescing window: one
-- ungated request in flight must not be swallowed by a gated one queued after
-- it in the same frame.
function CooldownCompanion:QueueBuildViewerAuraMap(allowAssociationGate)
    if not allowAssociationGate then
        pendingViewerAuraMapAllowGate = false
    end
    pendingViewerAuraMapToken = pendingViewerAuraMapToken + 1
    local token = pendingViewerAuraMapToken
    C_Timer.After(0, function()
        if pendingViewerAuraMapToken ~= token then return end
        local gated = pendingViewerAuraMapAllowGate
        pendingViewerAuraMapAllowGate = true
        -- The config panel reads the same derived associations the tail feeds,
        -- so it refreshes exactly when the tail runs.
        if self:BuildViewerAuraMap(gated) then
            self:RefreshConfigPanel()
        end
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
--
-- Returns whether the TAIL (sound map + aura rebind) ran, so the queued caller
-- can pair its config refresh with it.
function CooldownCompanion:BuildViewerAuraMap(allowAssociationGate)
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

    BeginViewerAssociationFingerprint()
    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer then
            AddViewerAuraMapChildren(self, name, AddViewerAuraChild, viewer:GetChildren())
        else
            -- An absent viewer still occupies its slot in the fixed order.
            PushViewerAssociationValue(0)
        end
    end
    -- Ensure tracked buttons can find their viewer child even if
    -- buttonData.id is a non-current override form of a transforming spell.
    self:MapButtonSpellsToViewers()

    -- Everything above is UNCONDITIONAL. Blizzard fires RefreshLayout on every
    -- full-update UNIT_AURA and recycles the item pool through a hash walk, so
    -- every cached frame reference goes stale whether or not the rows changed.
    -- Only the consumers of the DERIVED associations are gated, and only for
    -- callers that opted in.
    local associationsChanged = CommitViewerAssociationFingerprint()
    if allowAssociationGate and not associationsChanged then
        return false
    end

    -- Rebuild spell -> cooldown alert capability mapping used by per-button sound alerts.
    self:RebuildSoundAlertSpellMap()

    -- Aura candidate sets resolve through this map (linked-aura sets, buff
    -- viewer children), so bound slot filters go stale when it changes —
    -- re-request the coalesced, OOC-deferred rebind every rebuild.
    if self.RequestAuraRebind then
        self:RequestAuraRebind("viewer-map")
    end
    return true
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
