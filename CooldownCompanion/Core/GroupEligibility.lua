--[[
    CooldownCompanion - GroupEligibility
    Group and entry eligibility, load conditions, class/spec scope, and talent checks.

    Part of the GroupOperations family; see its ordered block in the addon TOC.
    Public methods attach to ST.Addon; local state stays with its owner.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local select = select
local next = next
local type = type

local LOAD_CONDITION_DEFAULTS = {
    raid = false,
    dungeon = false,
    delve = false,
    battleground = false,
    arena = false,
    openWorld = false,
    rested = false,
    petBattle = true,
    vehicleUI = true,
}

local LOCAL_LOAD_CONDITION_DEFAULTS = {
    raid = false,
    dungeon = false,
    delve = false,
    battleground = false,
    arena = false,
    openWorld = false,
    rested = false,
    petBattle = false,
    vehicleUI = false,
}

local LOAD_CONDITION_ALLOWLIST_KEYS = {
    classAllowlist = true,
    specAllowlist = true,
    characterAllowlist = true,
}

local function NormalizeClassKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    return string.upper(key)
end

local function NormalizeSpecKey(key)
    local specId = tonumber(key)
    if not specId then return nil end
    return specId
end

local function NormalizeCharacterKey(key)
    if type(key) ~= "string" or key == "" then return nil end
    return key
end

local function NormalizeTruthyMap(map, normalizer, failClosed)
    if map == nil then return nil, false, false end
    if type(map) ~= "table" then return nil, true, true end

    local normalized = {}
    local sawEntry = false
    local invalidEnabledEntry = false
    for key, enabled in pairs(map) do
        sawEntry = true
        if enabled == true then
            local normalizedKey = normalizer(key)
            if normalizedKey ~= nil then
                normalized[normalizedKey] = true
            else
                invalidEnabledEntry = true
            end
        end
    end

    if next(normalized) then
        return normalized, false, true
    end
    if invalidEnabledEntry and failClosed then
        return {}, true, true
    end
    if sawEntry and failClosed then
        return {}, false, true
    end
    return nil, false, false
end

local function CopyTruthyMap(map)
    if not map then return nil end
    local copy = {}
    for key in pairs(map) do
        copy[key] = true
    end
    return copy
end

local function IntersectTruthyMaps(left, right)
    local intersection = {}
    for key in pairs(left or {}) do
        if right and right[key] then
            intersection[key] = true
        end
    end
    return intersection
end

local function AddEffectiveSource(sources, map, inherited, normalizer)
    local normalized, malformed, hasRestriction = NormalizeTruthyMap(map, normalizer, true)
    if hasRestriction then
        sources[#sources + 1] = {
            values = normalized or {},
            inherited = inherited and true or false,
            malformed = malformed and true or false,
        }
    end
end

local function AddCombinedEffectiveSource(sources, inherited, normalizer, ...)
    local values
    local hasRestriction = false
    local malformed = false

    for index = 1, select("#", ...) do
        local normalized, sourceMalformed, sourceHasRestriction = NormalizeTruthyMap(select(index, ...), normalizer, true)
        if sourceMalformed then
            malformed = true
        end
        if sourceHasRestriction then
            hasRestriction = true
            values = values or {}
            for key in pairs(normalized or {}) do
                values[key] = true
            end
        end
    end

    if hasRestriction then
        sources[#sources + 1] = {
            values = values,
            inherited = inherited and true or false,
            malformed = malformed,
        }
    end
end

local function ResolveEffectiveSources(sources)
    local effective
    local inherited = false
    local hasRestriction = false

    for _, source in ipairs(sources or {}) do
        hasRestriction = true
        if source.inherited then inherited = true end
        if source.malformed then
            effective = {}
        elseif effective == nil then
            effective = CopyTruthyMap(source.values) or {}
        else
            effective = IntersectTruthyMaps(effective, source.values)
        end
    end

    return effective, inherited, hasRestriction
end

local function AddEntityEffectiveSpecSource(sources, entity, inherited)
    AddCombinedEffectiveSource(
        sources,
        inherited,
        NormalizeSpecKey,
        entity and entity.specs,
        entity and entity.loadConditions and entity.loadConditions.specAllowlist
    )
end

local function MergeEligibilityAllowlist(state, key, map, normalizer)
    local normalized, malformed, hasRestriction = NormalizeTruthyMap(map, normalizer, true)
    if malformed then
        state[key .. "Restricted"] = true
        state[key .. "NoMatch"] = true
        state[key] = {}
        return false
    end
    if not hasRestriction then return true end

    local restrictedKey = key .. "Restricted"
    state[restrictedKey] = true
    if state[key] == nil then
        state[key] = CopyTruthyMap(normalized) or {}
    else
        state[key] = IntersectTruthyMaps(state[key], normalized)
    end
    return true
end

local function AllowlistMatches(state, key, currentValue)
    if not state[key .. "Restricted"] then return true end
    if state[key .. "NoMatch"] then return false end
    if currentValue == nil then return false end
    return state[key] and state[key][currentValue] == true
end

function CooldownCompanion:IsGroupVisibleToCurrentChar(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end

    -- For panels, delegate visibility to the parent container
    if group.parentContainerId then
        return self:IsContainerVisibleToCurrentChar(group.parentContainerId)
    end

    -- Legacy path (no container)
    local scope = self:ResolveProfileEntityClassScope(group, {
        isGlobal = group.isGlobal == true,
    })
    return scope.runtimeVisible == true
end

-- Resolve the container for a panel group, or nil if the group has no container.
function CooldownCompanion:GetParentContainer(groupOrGroupId)
    local group = groupOrGroupId
    if type(groupOrGroupId) == "number" then
        group = self.db.profile.groups[groupOrGroupId]
    end
    if not group or not group.parentContainerId then return nil end
    local containers = self.db.profile.groupContainers
    return containers and containers[group.parentContainerId]
end

function CooldownCompanion:IsGroupVisibleInUnlockPreview(groupId, opts)
    opts = opts or {}

    local group = opts.group or self.db.profile.groups[groupId]
    if not group then
        return false
    end
    if (not opts.ignoreArrangePanelSuppression and self:IsArrangePanelSuppressed(groupId))
        or (group.parentContainerId
            and self:IsArrangeContainerSuppressed(group.parentContainerId)) then
        return false
    end

    if opts.panelUnlockPreview then
        if not self:IsPanelUnlockPreviewActive(group) then
            return false
        end
    else
        if not group.parentContainerId then
            return false
        end

        local container = opts.container or self:GetParentContainer(group)
        if not opts.assumeContainerUnlocked and not self:IsContainerUnlockPreviewActive(container) then
            return false
        end
    end

    -- An Aura Panel joins the Rotation Assistant in skipping the entry checks:
    -- both are placed and sized before they have entries (the Aura Panel keeps a
    -- reserved one-cell footprint for exactly this), so "no saved entry" must
    -- not mean "not on screen to arrange".
    local skipEntryChecks = self:IsRotationAssistantGroup(group) or ST.IsAuraPanelGroup(group)
    if not skipEntryChecks and not (group.buttons and #group.buttons > 0) then
        return false
    end
    if not skipEntryChecks and not self:GroupHasUsableButtons(group, {
        checkLoadConditions = false,
    }) then
        return false
    end

    local groupFrame = opts.groupFrame
    if groupFrame == nil and groupId then
        groupFrame = self.groupFrames and self.groupFrames[groupId] or nil
    end
    -- Same exemption on the runtime side. An Aura Panel renders its entries
    -- through its own aura container and materializes no CC buttons at all, so
    -- an empty button list is its normal state rather than the "nothing
    -- rendered yet" signal this check reads it as everywhere else.
    -- The same emptiness, one cluster at a time. A MIXED panel whose entries all
    -- sit in aura sections materializes no CC button either, so its frame reads
    -- empty while those sections still own a rectangle to arrange. Only the
    -- FRAME check is exempted: the data checks above stay in force, because
    -- those entries are saved entries and answer them honestly.
    if groupFrame
        and not skipEntryChecks
        and not ST.PanelHasAuraSection(group)
        and (not groupFrame.buttons or #groupFrame.buttons == 0) then
        return false
    end

    local checkCharVisibility = opts.checkCharVisibility
    if checkCharVisibility == nil then
        checkCharVisibility = true
    end
    if checkCharVisibility and groupId and not self:IsGroupVisibleToCurrentChar(groupId) then
        return false
    end

    if not opts.panelUnlockPreview then
        if self.IsGroupEligibilityMet and not self:IsGroupEligibilityMet(group) then
            return false
        end

        local effectiveSpecs, _, hasSpecFilter = self:GetEffectiveSpecs(group)
        if hasSpecFilter then
            if not (self._currentSpecId and effectiveSpecs[self._currentSpecId]) then
                return false
            end
        end
    end

    return true
end

-- Cursor-anchored panels have no stable position (they ride the live cursor,
-- or park on the dummy cursor while pinned), so they never join the container
-- mover's footprint: no wrapper stretch, no member overlay, no arrange
-- selection. Their offset is edited through the dummy-cursor preview instead.
function CooldownCompanion:GetContainerUnlockPreviewPanels(containerId, panels)
    local previewPanels = {}
    local panelList = panels or self:GetPanels(containerId)
    for _, panelInfo in ipairs(panelList) do
        if not self:IsGroupCursorAnchored(panelInfo.group)
            and self:IsGroupVisibleInUnlockPreview(panelInfo.groupId, {
                group = panelInfo.group,
                checkCharVisibility = true,
                ignoreArrangePanelSuppression = true,
            }) then
            previewPanels[#previewPanels + 1] = panelInfo
        end
    end
    return previewPanels
end

function CooldownCompanion:ContainerHasArrangeEligiblePanel(containerId)
    for _, panelInfo in ipairs(self:GetPanels(containerId)) do
        if not self:IsGroupCursorAnchored(panelInfo.group)
            and self:IsGroupVisibleInUnlockPreview(panelInfo.groupId, {
                group = panelInfo.group,
                checkCharVisibility = true,
                assumeContainerUnlocked = true,
            }) then
            return true
        end
    end
    return false
end

function CooldownCompanion:GetEffectiveSpecs(group)
    if not group then return nil, false end

    local sources = {}
    local container = self:GetParentContainer(group)
    if container then
        AddEntityEffectiveSpecSource(sources, container, true)
        AddEntityEffectiveSpecSource(sources, group, false)
    else
        AddEntityEffectiveSpecSource(sources, group, false)
    end

    return ResolveEffectiveSources(sources)
end

function CooldownCompanion:GetInheritedEffectiveSpecs(group)
    if not group then return nil, false end

    local sources = {}
    local container = self:GetParentContainer(group)
    if container then
        AddEntityEffectiveSpecSource(sources, container, true)
    end

    return ResolveEffectiveSources(sources)
end

function CooldownCompanion:GetEffectiveHeroTalents(group)
    if not group then return nil, false end

    local sources = {}

    local container = self:GetParentContainer(group)
    if container then
        AddEffectiveSource(sources, container.heroTalents, true, NormalizeSpecKey)
        AddEffectiveSource(sources, group.heroTalents, false, NormalizeSpecKey)
    else
        AddEffectiveSource(sources, group.heroTalents, false, NormalizeSpecKey)
    end

    return ResolveEffectiveSources(sources)
end

local function CopyTalentCondition(cond)
    return {
        nodeID = cond.nodeID,
        entryID = cond.entryID,
        spellID = cond.spellID,
        name = cond.name,
        show = cond.show or "taken",
        classID = cond.classID,
        className = cond.className,
        specID = cond.specID,
        specName = cond.specName,
        heroSubTreeID = cond.heroSubTreeID,
        heroName = cond.heroName,
    }
end

local function IsLegacyChoiceRowCondition(cond)
    return type(cond) == "table"
        and cond.entryID == nil
        and cond.spellID == nil
        and type(cond.name) == "string"
        and cond.name:sub(1, 12) == "Choice row: "
end

local function IsHeroSpecProxyCondition(cond)
    return type(cond) == "table"
        and cond.nodeID ~= nil
        and cond.heroSubTreeID ~= nil
        and cond.entryID == nil
        and type(cond.name) == "string"
        and type(cond.heroName) == "string"
        and cond.name == cond.heroName
end

ST._IsHeroSpecProxyCondition = IsHeroSpecProxyCondition

function CooldownCompanion:NormalizeTalentConditions(conditions)
    if type(conditions) ~= "table" then return nil, false end

    local grouped = {}
    local orderedGroupKeys = {}
    local passthrough = {}
    local hasDuplicateNode = false
    local hasLegacyChoiceRow = false
    local hasUnscopedNodeCondition = false
    local scopedSpecIDs = {}
    local scopedHeroIDs = {}
    local scopedSpecCount = 0
    local scopedHeroCount = 0

    for _, cond in ipairs(conditions) do
        if type(cond) == "table" and cond.nodeID then
            if IsLegacyChoiceRowCondition(cond) then
                hasLegacyChoiceRow = true
            end
            if not cond.specID and not cond.classID and not cond.className then
                hasUnscopedNodeCondition = true
            end
            if cond.specID and not scopedSpecIDs[cond.specID] then
                scopedSpecIDs[cond.specID] = true
                scopedSpecCount = scopedSpecCount + 1
            end
            if cond.heroSubTreeID and not scopedHeroIDs[cond.heroSubTreeID] then
                scopedHeroIDs[cond.heroSubTreeID] = true
                scopedHeroCount = scopedHeroCount + 1
            end

            local groupKey = tostring(cond.nodeID)
                .. "|" .. tostring(cond.classID or 0)
                .. "|" .. tostring(cond.specID or 0)
                .. "|" .. tostring(cond.heroSubTreeID or 0)
            local group = grouped[groupKey]
            if not group then
                group = {}
                grouped[groupKey] = group
                orderedGroupKeys[#orderedGroupKeys + 1] = groupKey
            else
                hasDuplicateNode = true
            end
            group[#group + 1] = cond
        else
            passthrough[#passthrough + 1] = cond
        end
    end

    if not hasDuplicateNode
        and not hasLegacyChoiceRow
        and scopedSpecCount <= 1
        and scopedHeroCount <= 1
        and not (scopedSpecCount > 0 and hasUnscopedNodeCondition)
    then
        return conditions, false
    end

    local normalized = {}
    for _, cond in ipairs(passthrough) do
        normalized[#normalized + 1] = cond
    end

    for _, groupKey in ipairs(orderedGroupKeys) do
        local group = grouped[groupKey]
        if group and #group > 0 then
            local firstCondition = nil
            local firstSpecific = nil
            local takenCount = 0
            local seenEntries = {}
            local takenCondition = nil
            local uniqueEntryCount = 0
            local specificCount = 0

            for _, cond in ipairs(group) do
                if not firstCondition and not IsLegacyChoiceRowCondition(cond) then
                    firstCondition = cond
                end

                if cond.entryID ~= nil then
                    if not firstSpecific then
                        firstSpecific = cond
                    end
                    specificCount = specificCount + 1
                    if not seenEntries[cond.entryID] then
                        seenEntries[cond.entryID] = true
                        uniqueEntryCount = uniqueEntryCount + 1
                    end

                    if (cond.show or "taken") == "not_taken" then
                        -- no-op
                    else
                        takenCount = takenCount + 1
                        takenCondition = cond
                    end
                end
            end

            local resolved
            if specificCount > 1 and specificCount == uniqueEntryCount and uniqueEntryCount > 1 then
                if takenCount == 1 then
                    resolved = CopyTalentCondition(takenCondition)
                else
                    resolved = CopyTalentCondition(firstSpecific)
                end
            end

            if not resolved then
                local fallback = firstSpecific or firstCondition
                if fallback then
                    resolved = CopyTalentCondition(fallback)
                end
            end

            if resolved then
                normalized[#normalized + 1] = resolved
            end
        end
    end

    local chosenSpecID = nil
    for _, cond in ipairs(normalized) do
        if type(cond) == "table" and cond.nodeID and cond.specID then
            chosenSpecID = cond.specID
            break
        end
    end
    if chosenSpecID then
        local filtered = {}
        for _, cond in ipairs(normalized) do
            if type(cond) == "table" and cond.nodeID then
                if cond.classID or cond.className or cond.specID == chosenSpecID then
                    filtered[#filtered + 1] = cond
                end
            else
                filtered[#filtered + 1] = cond
            end
        end
        normalized = filtered
    end

    local chosenHeroSubTreeID = nil
    for _, cond in ipairs(normalized) do
        if type(cond) == "table" and cond.nodeID and cond.heroSubTreeID then
            chosenHeroSubTreeID = cond.heroSubTreeID
            break
        end
    end
    if chosenHeroSubTreeID then
        local filtered = {}
        for _, cond in ipairs(normalized) do
            if type(cond) == "table" and cond.nodeID then
                if not cond.heroSubTreeID or cond.heroSubTreeID == chosenHeroSubTreeID then
                    filtered[#filtered + 1] = cond
                end
            else
                filtered[#filtered + 1] = cond
            end
        end
        normalized = filtered
    end

    if #normalized == 0 then
        return nil, true
    end
    return normalized, true
end

function CooldownCompanion:IsHeroTalentAllowed(group)
    local effectiveHeroTalents, _, hasHeroTalentFilter = self:GetEffectiveHeroTalents(group)
    if not hasHeroTalentFilter then return true end
    local heroSpecId = self._currentHeroSpecId
    if not heroSpecId then return true end  -- low level, no hero talent selected
    return effectiveHeroTalents[heroSpecId] == true
end

function CooldownCompanion:GroupHasUsableButtons(group, opts)
    opts = opts or {}
    if self:IsRotationAssistantGroup(group) then
        if opts.checkLoadConditions == false then
            return true
        end
        local entrySettings = self:GetRotationAssistantEntrySettings(group, false)
        return self:IsButtonLoadConditionMet(entrySettings or {}, group)
    end
    if not (group and group.buttons and #group.buttons > 0) then
        return false
    end
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, opts) then
            return true
        end
    end
    return false
end

function CooldownCompanion:GetGroupLayoutButtonCount(groupId, group, opts)
    opts = opts or {}
    if self:IsRotationAssistantGroup(group) then
        return 1
    end

    if not (group and group.buttons and #group.buttons > 0) then
        return 0
    end

    local buttonUsabilityOptions = opts.buttonUsabilityOptions

    local count = 0
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
            count = count + 1
        end
    end
    return count
end

-- Ordered identity of the entries an Aura Panel currently reserves cells for.
--
-- An Aura Panel materializes no CC buttons, so the entry-identity comparison
-- every other group makes against frame.buttons has nothing to read. This string
-- stands in for that list: PopulateGroupButtons stamps it on the frame, and
-- GroupButtonSetNeedsRebuild diffs against it on the next availability sweep so
-- the panel keeps a refresh trigger of its own.
--
-- Walked over group.buttons with the SAME predicate and the SAME options
-- GetGroupLayoutButtonCount uses -- which is how GetAuraPanelGridMetrics counts
-- cells -- so the signature and the cell count can never disagree about which
-- entries are in.
--
-- ORDER carries the identity and the count does not: two mutually exclusive
-- talent auras can swap with the entry count unchanged, and the panel still has
-- to repopulate and rebind.
--
-- Identity per entry is _auraKey, which is the same string the aura engine keys
-- the panel's aura groups by -- so two entries this signature calls the same are
-- two entries the bind pass would also collapse into one. Entries with no key
-- (pre-subtype or hand-edited data, which the bind pass parks) still occupy a
-- cell, so they are carried under a distinct prefix by type and id rather than
-- dropped: a keyless entry coming or going still moves the footprint.
local function AppendAuraEntryToken(signature, buttonData)
    local auraKey = buttonData._auraKey
    if auraKey then
        return signature .. "\031k" .. tostring(auraKey)
    end
    return signature .. "\031?"
        .. tostring(buttonData.type) .. ":" .. tostring(buttonData.id)
end

function CooldownCompanion:GetAuraPanelEntrySignature(group, buttonUsabilityOptions)
    if not (group and group.buttons) then
        return ""
    end

    local signature = ""
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
            signature = AppendAuraEntryToken(signature, buttonData)
        end
    end
    return signature
end

-- The same string for a MIXED panel, scoped to the entries that render through
-- an aura SECTION. Those entries materialize no CC button either, so the
-- frame.buttons comparison GroupButtonSetNeedsRebuild makes for every ordinary
-- panel cannot see them -- and it must not try, or a panel with one aura section
-- would report "needs rebuild" on every availability sweep forever. Filtering
-- them out of that comparison deletes their refresh trigger, exactly the way a
-- flat false once deleted the Aura Panel's; this restores it.
--
-- Empty for a panel with no aura section, so an ordinary panel stores and
-- compares nothing.
function CooldownCompanion:GetAuraSectionEntrySignature(group, buttonUsabilityOptions)
    if not (group and group.buttons and ST.PanelHasAuraSection(group)) then
        return ""
    end

    local signature = ""
    for _, buttonData in ipairs(group.buttons) do
        if ST.IsAuraSectionEntry(group, buttonData)
            and self:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
            signature = AppendAuraEntryToken(signature, buttonData)
        end
    end
    return signature
end

local UNLOCK_PREVIEW_BUTTON_USABILITY_OPTIONS = {
    checkLoadConditions = false,
}

function CooldownCompanion:GetGroupButtonUsabilityOptions(groupId, group)
    local frame = groupId and self.groupFrames and self.groupFrames[groupId]
    if frame
        and (frame._containerUnlockPreviewActive == true
            or frame._panelUnlockPreviewActive == true) then
        return UNLOCK_PREVIEW_BUTTON_USABILITY_OPTIONS
    end

    return nil
end

function CooldownCompanion:GetGroupLayoutButtonUsabilityOptions(groupId, group)
    return self:GetGroupButtonUsabilityOptions(groupId, group)
end

function CooldownCompanion:IsGroupActive(groupId, opts)
    opts = opts or {}
    local db = self.db and self.db.profile
    local group = opts.group or (db and db.groups and db.groups[groupId])
    if not group then return false end

    -- If this panel has a parent container, check container-level state first
    local container = self:GetParentContainer(group)
    if container and not opts.ignoreUnlockPreview and self:IsContainerUnlockPreviewActive(container) then
        return self:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            container = container,
            checkCharVisibility = opts.checkCharVisibility,
        })
    end
    if not opts.ignoreUnlockPreview and self:IsPanelUnlockPreviewActive(group) then
        return self:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            panelUnlockPreview = true,
            checkCharVisibility = opts.checkCharVisibility,
        })
    end
    if container then
        if container.enabled == false then return false end
        if group.enabled == false then return false end

    else
        -- Legacy path: enabled lives on the group
        if group.enabled == false then return false end
    end

    -- Spec and hero talent filtering (GetEffectiveSpecs already delegates to container)
    local effectiveSpecs, _, hasSpecFilter = self:GetEffectiveSpecs(group)
    if hasSpecFilter then
        if not (self._currentSpecId and effectiveSpecs[self._currentSpecId]) then
            return false
        end
    end

    if not self:IsHeroTalentAllowed(group) then return false end

    local checkCharVisibility = opts.checkCharVisibility
    if checkCharVisibility == nil then checkCharVisibility = true end
    if checkCharVisibility and groupId and not self:IsGroupVisibleToCurrentChar(groupId) then
        return false
    end

    if opts.checkLoadConditions ~= false then
        if not self:IsGroupLoadConditionMet(group) then
            return false
        end
    end

    local buttonUsabilityOptions = opts.buttonUsabilityOptions

    if opts.requireButtons and not self:GroupHasUsableButtons(group, {
        checkLoadConditions = opts.checkLoadConditions,
        ignoreSpellAvailability = buttonUsabilityOptions and buttonUsabilityOptions.ignoreSpellAvailability,
        ignoreItemAvailability = buttonUsabilityOptions and buttonUsabilityOptions.ignoreItemAvailability,
        ignoreTalentConditions = buttonUsabilityOptions and buttonUsabilityOptions.ignoreTalentConditions,
    }) then
        return false
    end

    return true
end

function CooldownCompanion:CleanHeroTalentsForSpec(group, specId)
    if not group.heroTalents or not next(group.heroTalents) then return end
    local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
    if not subTreeIDs then return end
    for _, subTreeID in ipairs(subTreeIDs) do
        group.heroTalents[subTreeID] = nil
    end
    if not next(group.heroTalents) then
        group.heroTalents = nil
    end
end

local function ClearEmptyCoreLoadConditions(entity)
    if type(entity) ~= "table" or type(entity.loadConditions) ~= "table" then return end
    if not next(entity.loadConditions) then
        entity.loadConditions = nil
    end
end

local GetClassKeyFromClassID = ST._GetResourceBarClassKeyFromClassID
local GetClassIDFromClassKey = ST._GetClassIDFromResourceBarClassKey

local function GetCurrentScopeClassKey(addon)
    local classFilename = addon and addon._playerClassFilename
    if not classFilename and UnitClass then
        classFilename = select(2, UnitClass("player"))
    end
    return NormalizeClassKey(classFilename)
end

local function GetSpecClassKey(specId)
    if not (C_SpecializationInfo and C_SpecializationInfo.GetClassIDFromSpecID) then
        return nil
    end
    return GetClassKeyFromClassID(C_SpecializationInfo.GetClassIDFromSpecID(tonumber(specId)))
end

local function SpecBelongsToClass(specId, classKey)
    if not classKey then return true end
    local specClassKey = GetSpecClassKey(specId)
    return specClassKey == classKey
end

local function HeroTalentBelongsToClass(subTreeID, classKey)
    subTreeID = tonumber(subTreeID)
    if not classKey then return true end
    if not (subTreeID
        and C_ClassTalents
        and C_ClassTalents.GetHeroTalentSpecsForClassSpec
        and C_SpecializationInfo
        and C_SpecializationInfo.GetNumSpecializationsForClassID
        and C_SpecializationInfo.GetSpecializationInfo)
    then
        return false
    end

    local classID = GetClassIDFromClassKey(classKey)
    if not classID then return false end

    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    for specIndex = 1, numSpecs do
        local specId = C_SpecializationInfo.GetSpecializationInfo(
            specIndex,
            false,
            false,
            nil,
            nil,
            nil,
            classID
        )
        local subTreeIDs = specId and C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
        for _, availableSubTreeID in ipairs(subTreeIDs or {}) do
            if tonumber(availableSubTreeID) == subTreeID then
                return true
            end
        end
    end
    return false
end

local function GetCharacterClassKey(addon, charKey)
    local info = charKey
        and addon
        and addon.db
        and addon.db.global
        and addon.db.global.characterInfo
        and addon.db.global.characterInfo[charKey]
    if type(info) ~= "table" then
        return nil
    end
    return NormalizeClassKey(info.classFilename)
        or GetClassKeyFromClassID(info.classID)
end

local function BuildClassScopeResult(scope, opts)
    opts = opts or {}
    return {
        scope = scope,
        sectionKey = opts.sectionKey,
        ownerCharKey = opts.ownerCharKey,
        ownerClassKey = opts.ownerClassKey,
        currentClassKey = opts.currentClassKey,
        currentCharKey = opts.currentCharKey,
        isGlobal = scope == "global",
        isCurrentClass = scope == "current-class",
        isOtherClass = scope == "other-class",
        isInvalid = scope == "invalid",
        runtimeVisible = scope == "global" or scope == "current-class",
        invalidReason = opts.invalidReason,
    }
end

local function ResolveProfileEntityClassScope(addon, entity, opts)
    opts = opts or {}
    local currentCharKey = opts.currentCharKey
        or addon and addon.db and addon.db.keys and addon.db.keys.char
        or nil
    local currentClassKey = NormalizeClassKey(opts.currentClassKey)
        or GetCurrentScopeClassKey(addon)

    if type(entity) ~= "table" then
        return BuildClassScopeResult("invalid", {
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "invalid",
            invalidReason = "missing-entity",
        })
    end

    if opts.isGlobal == true then
        return BuildClassScopeResult("global", {
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "global",
        })
    end

    local ownerCharKey = opts.ownerCharKey or entity.createdBy
    if type(ownerCharKey) ~= "string" or ownerCharKey == "" then
        return BuildClassScopeResult("invalid", {
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "invalid",
            invalidReason = "missing-owner",
        })
    end

    local ownerClassKey = GetCharacterClassKey(addon, ownerCharKey)
    if not ownerClassKey then
        return BuildClassScopeResult("invalid", {
            ownerCharKey = ownerCharKey,
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "invalid",
            invalidReason = "missing-owner-class",
        })
    end

    if ownerClassKey == currentClassKey then
        return BuildClassScopeResult("current-class", {
            ownerCharKey = ownerCharKey,
            ownerClassKey = ownerClassKey,
            currentCharKey = currentCharKey,
            currentClassKey = currentClassKey,
            sectionKey = "char",
        })
    end

    return BuildClassScopeResult("other-class", {
        ownerCharKey = ownerCharKey,
        ownerClassKey = ownerClassKey,
        currentCharKey = currentCharKey,
        currentClassKey = currentClassKey,
        sectionKey = "class:" .. ownerClassKey,
    })
end

function CooldownCompanion:ResolveProfileEntityClassScope(entity, opts)
    return ResolveProfileEntityClassScope(self, entity, opts)
end

function CooldownCompanion:ResolveContainerClassScope(containerOrContainerId, opts)
    local container = containerOrContainerId
    if type(containerOrContainerId) == "number" then
        local db = self.db and self.db.profile
        container = db and db.groupContainers and db.groupContainers[containerOrContainerId] or nil
    end
    opts = opts and CopyTable(opts) or {}
    opts.isGlobal = type(container) == "table" and container.isGlobal == true
    return ResolveProfileEntityClassScope(self, container, opts)
end

function CooldownCompanion:CanMovePanelToContainer(groupOrGroupId, targetContainerOrContainerId)
    local db = self.db and self.db.profile
    if not (db and db.groups and db.groupContainers) then
        return false, "missing-profile"
    end

    local group = groupOrGroupId
    if type(groupOrGroupId) ~= "table" then
        group = db.groups[groupOrGroupId]
    end
    if type(group) ~= "table" or not group.parentContainerId then
        return false, "missing-source-panel"
    end

    local targetContainer = targetContainerOrContainerId
    local targetContainerId
    if type(targetContainerOrContainerId) ~= "table" then
        targetContainerId = targetContainerOrContainerId
        targetContainer = db.groupContainers[targetContainerOrContainerId]
    else
        for containerId, container in pairs(db.groupContainers) do
            if container == targetContainer then
                targetContainerId = containerId
                break
            end
        end
    end
    if type(targetContainer) ~= "table" then
        return false, "missing-target-container"
    end
    if targetContainerId and group.parentContainerId == targetContainerId then
        return false, "same-container"
    end

    local sourceScope = self:ResolveContainerClassScope(group.parentContainerId)
    local targetScope = self:ResolveContainerClassScope(targetContainer)
    if sourceScope.isInvalid or targetScope.isInvalid then
        return false, "invalid-class-scope"
    end
    if sourceScope.scope ~= targetScope.scope then
        return false, "scope-mismatch"
    end
    if sourceScope.scope == "global" then
        return true
    end
    if sourceScope.ownerClassKey == targetScope.ownerClassKey then
        return true
    end
    return false, "mixed-class-panel"
end

function CooldownCompanion:CanMoveEntryToGroup(sourceGroupId, targetGroupId)
    local db = self.db and self.db.profile
    if not (db and db.groups) then
        return false
    end
    if sourceGroupId == targetGroupId then
        return false
    end

    local sourceGroup = db.groups[sourceGroupId]
    local targetGroup = db.groups[targetGroupId]
    if not (sourceGroup and targetGroup and sourceGroup.parentContainerId and targetGroup.parentContainerId) then
        return false
    end

    if not self.ResolveContainerClassScope then
        return self:IsGroupVisibleToCurrentChar(targetGroupId)
    end

    local sourceScope = self:ResolveContainerClassScope(sourceGroup.parentContainerId)
    if not sourceScope or sourceScope.isInvalid then
        return false
    end

    if sourceScope.isOtherClass then
        local targetScope = self:ResolveContainerClassScope(targetGroup.parentContainerId)
        return targetScope
            and targetScope.isInvalid ~= true
            and targetScope.isOtherClass == true
            and targetScope.ownerClassKey == sourceScope.ownerClassKey
    end

    return self:IsGroupVisibleToCurrentChar(targetGroupId)
end

local function PruneSpecMapToClass(addon, entity, map, classKey)
    if type(map) ~= "table" or not classKey then return false end
    local changed = false
    for key in pairs(map) do
        local specId = NormalizeSpecKey(key)
        if specId and SpecBelongsToClass(specId, classKey) then
            if key ~= specId then
                map[specId] = true
                map[key] = nil
                changed = true
            end
        else
            map[key] = nil
            if specId then
                map[specId] = nil
                if addon and addon.CleanHeroTalentsForSpec then
                    addon:CleanHeroTalentsForSpec(entity, specId)
                end
            end
            changed = true
        end
    end
    return changed
end

local function CharacterKeyMatchesClass(addon, charKey, classKey, ownerCharKey)
    if not classKey then return true end
    if charKey and ownerCharKey and charKey == ownerCharKey then
        return true
    end
    local currentCharKey = addon and addon.db and addon.db.keys and addon.db.keys.char
    if charKey and currentCharKey and charKey == currentCharKey then
        return true
    end
    return GetCharacterClassKey(addon, charKey) == classKey
end

local function PruneCharacterMapToClass(addon, map, classKey, ownerCharKey)
    if type(map) ~= "table" or not classKey then return false end
    local changed = false
    for key in pairs(map) do
        local charKey = NormalizeCharacterKey(key)
        if not (charKey and CharacterKeyMatchesClass(addon, charKey, classKey, ownerCharKey)) then
            map[key] = nil
            if charKey then
                map[charKey] = nil
            end
            changed = true
        end
    end
    return changed
end

local function PruneHeroTalentMapToClass(entity, classKey)
    if type(entity) ~= "table" or type(entity.heroTalents) ~= "table" or not classKey then return false end
    local changed = false
    for subTreeID in pairs(entity.heroTalents) do
        local normalizedSubTreeID = tonumber(subTreeID)
        if normalizedSubTreeID and HeroTalentBelongsToClass(normalizedSubTreeID, classKey) then
            if subTreeID ~= normalizedSubTreeID then
                entity.heroTalents[normalizedSubTreeID] = true
                entity.heroTalents[subTreeID] = nil
                changed = true
            end
        else
            entity.heroTalents[subTreeID] = nil
            if normalizedSubTreeID then
                entity.heroTalents[normalizedSubTreeID] = nil
            end
            changed = true
        end
    end
    if not next(entity.heroTalents) then
        entity.heroTalents = nil
    end
    return changed
end

local function WithOwnerCharKey(opts, ownerCharKey)
    if opts and opts.ownerCharKey then return opts end
    local scopedOpts = opts and CopyTable(opts) or {}
    scopedOpts.ownerCharKey = ownerCharKey
    return scopedOpts
end

function CooldownCompanion:NormalizeEligibilityForCharacterScope(entity, opts)
    if type(entity) ~= "table" then return false end
    opts = opts or {}
    local ownerCharKey = opts.ownerCharKey
        or entity.createdBy
        or (self.db and self.db.keys and self.db.keys.char)
    local classKey = NormalizeClassKey(opts.scopeClassKey)
        or GetCharacterClassKey(self, ownerCharKey)
        or GetCurrentScopeClassKey(self)
    local changed = false

    if PruneSpecMapToClass(self, entity, entity.specs, classKey) then
        changed = true
        if type(entity.specs) == "table" and not next(entity.specs) then
            entity.specs = nil
        end
    end
    changed = PruneHeroTalentMapToClass(entity, classKey) or changed

    local loadConditions = entity.loadConditions
    if type(loadConditions) == "table" then
        if loadConditions.classAllowlist ~= nil then
            loadConditions.classAllowlist = nil
            changed = true
        end
        if PruneSpecMapToClass(self, entity, loadConditions.specAllowlist, classKey) then
            changed = true
            if type(loadConditions.specAllowlist) == "table" and not next(loadConditions.specAllowlist) then
                loadConditions.specAllowlist = nil
            end
        end
        if PruneCharacterMapToClass(self, loadConditions.characterAllowlist, classKey, ownerCharKey) then
            changed = true
            if type(loadConditions.characterAllowlist) == "table"
                and not next(loadConditions.characterAllowlist)
            then
                loadConditions.characterAllowlist = nil
            end
        end
        ClearEmptyCoreLoadConditions(entity)
    end

    return changed
end

function CooldownCompanion:NormalizeContainerEligibilityForCharacterScope(containerId, opts)
    local db = self.db and self.db.profile
    if not (db and db.groupContainers) then return false end
    local container = db.groupContainers[containerId]
    if not container then return false end
    opts = WithOwnerCharKey(opts, container.createdBy or (self.db and self.db.keys and self.db.keys.char))

    local changed = self:NormalizeEligibilityForCharacterScope(container, opts)
    for _, group in pairs(db.groups or {}) do
        if type(group) == "table" and group.parentContainerId == containerId then
            changed = self:NormalizeEligibilityForCharacterScope(group, opts) or changed
        end
    end
    return changed
end

function CooldownCompanion:GetDefaultLoadConditions()
    return CopyTable(LOAD_CONDITION_DEFAULTS)
end

function CooldownCompanion:GetLocalLoadConditionDefaults()
    return CopyTable(LOCAL_LOAD_CONDITION_DEFAULTS)
end

function CooldownCompanion:HasLocalLoadConditions(entity)
    if not (type(entity) == "table" and type(entity.loadConditions) == "table") then
        return false
    end
    for key, value in pairs(entity.loadConditions) do
        if value == true then
            return true
        end
        if LOAD_CONDITION_ALLOWLIST_KEYS[key] and type(value) == "table" and next(value) then
            return true
        end
    end
    return false
end

function CooldownCompanion:EvaluateLoadConditions(loadConditions, defaults)
    local lc = loadConditions
    if not lc then return true end
    defaults = defaults or LOAD_CONDITION_DEFAULTS

    local instanceType = self._currentInstanceType

    -- Map instance type to load condition key
    local conditionKey
    if instanceType == "raid" then
        conditionKey = "raid"
    elseif instanceType == "party" then
        conditionKey = "dungeon"
    elseif instanceType == "pvp" then
        conditionKey = "battleground"
    elseif instanceType == "arena" then
        conditionKey = "arena"
    elseif instanceType == "delve" then
        conditionKey = "delve"
    else
        conditionKey = "openWorld"  -- "none" or "scenario"
    end

    -- If the matching instance condition is enabled, unload
    if lc[conditionKey] then return false end

    -- If rested condition is enabled and player is resting, unload
    if lc.rested and self._isResting then return false end

    -- If pet battle condition is enabled and player is in a pet battle, unload.
    -- Group/panel scopes default this on; entry scopes default it off.
    local petBattle = lc.petBattle
    if petBattle == nil then petBattle = defaults.petBattle or false end
    if petBattle and self._inPetBattle then return false end

    -- If vehicle/override UI condition is enabled and player is in a vehicle or
    -- override bar, unload. Defaults follow the same scope rules as pet battles.
    local vehicleUI = lc.vehicleUI
    if vehicleUI == nil then vehicleUI = defaults.vehicleUI or false end
    if vehicleUI and self._inVehicleUI then return false end

    return true
end

function CooldownCompanion:GetCurrentEligibilityIdentity()
    local classFilename = self._playerClassFilename
    if not classFilename and UnitClass then
        classFilename = select(2, UnitClass("player"))
    end
    return {
        classFilename = NormalizeClassKey(classFilename),
        specId = self._currentSpecId,
        charKey = self.db and self.db.keys and self.db.keys.char or nil,
    }
end

local function AddLoadConditionSource(sources, label, entity, defaults, allowClassEligibility)
    if type(entity) == "table" and type(entity.loadConditions) == "table" then
        sources[#sources + 1] = {
            label = label,
            loadConditions = entity.loadConditions,
            defaults = defaults,
            allowClassEligibility = allowClassEligibility == true,
        }
    end
end

local function HasEligibilityAllowlist(loadConditions, allowClassEligibility)
    if type(loadConditions) ~= "table" then return false end
    if allowClassEligibility and loadConditions.classAllowlist ~= nil then
        return true
    end
    return loadConditions.specAllowlist ~= nil
        or loadConditions.characterAllowlist ~= nil
end

local function IsContainerGlobalScope(container)
    return type(container) == "table" and container.isGlobal == true
end

function CooldownCompanion:GetInheritedLoadConditionSources(group)
    local sources = {}
    local db = self.db and self.db.profile
    if not (db and group) then return sources end

    local container = self:GetParentContainer(group)
    if container then
        AddLoadConditionSource(sources, "Group", container, LOAD_CONDITION_DEFAULTS, IsContainerGlobalScope(container))
        return sources
    end
    return sources
end

function CooldownCompanion:GetLoadConditionSourcesForGroup(group)
    local sources = self:GetInheritedLoadConditionSources(group)
    if group then
        local container = self:GetParentContainer(group)
        local allowClassEligibility
        if container then
            allowClassEligibility = IsContainerGlobalScope(container)
        else
            allowClassEligibility = group.isGlobal == true
        end
        AddLoadConditionSource(sources, group.parentContainerId and "Panel" or "Group", group, LOAD_CONDITION_DEFAULTS, allowClassEligibility)
    end
    return sources
end

function CooldownCompanion:GetLoadConditionSourcesForEntry(buttonData, group)
    local sources = self:GetLoadConditionSourcesForGroup(group)
    AddLoadConditionSource(sources, "Entry", buttonData, LOCAL_LOAD_CONDITION_DEFAULTS, false)
    return sources
end

function CooldownCompanion:EvaluateLoadConditionSources(sources, opts)
    opts = opts or {}
    local eligibility
    local identity

    for _, source in ipairs(sources or {}) do
        if opts.eligibilityOnly ~= true
            and not self:EvaluateLoadConditions(source.loadConditions, source.defaults)
        then
            return false, source.label
        end
        local loadConditions = source.loadConditions
        if HasEligibilityAllowlist(loadConditions, source.allowClassEligibility) then
            if not eligibility then
                eligibility = {}
                identity = self:GetCurrentEligibilityIdentity()
            end
            if source.allowClassEligibility then
                MergeEligibilityAllowlist(eligibility, "class", loadConditions.classAllowlist, NormalizeClassKey)
            end
            MergeEligibilityAllowlist(eligibility, "spec", loadConditions.specAllowlist, NormalizeSpecKey)
            MergeEligibilityAllowlist(eligibility, "character", loadConditions.characterAllowlist, NormalizeCharacterKey)
            if not AllowlistMatches(eligibility, "class", identity.classFilename)
                or not AllowlistMatches(eligibility, "spec", identity.specId)
                or not AllowlistMatches(eligibility, "character", identity.charKey)
            then
                return false, source.label
            end
        end
    end
    return true, nil
end

function CooldownCompanion:IsGroupLoadConditionMet(group)
    return self:EvaluateLoadConditionSources(self:GetLoadConditionSourcesForGroup(group))
end

function CooldownCompanion:IsGroupEligibilityMet(group)
    return self:EvaluateLoadConditionSources(self:GetLoadConditionSourcesForGroup(group), {
        eligibilityOnly = true,
    })
end

function CooldownCompanion:IsButtonLoadConditionMet(buttonData, group)
    return self:EvaluateLoadConditionSources(self:GetLoadConditionSourcesForEntry(buttonData, group))
end

function CooldownCompanion:IsCustomBarLoadConditionMet(customBar)
    local sources = {}
    AddLoadConditionSource(sources, "Custom Bar", customBar, LOCAL_LOAD_CONDITION_DEFAULTS, true)
    return self:EvaluateLoadConditionSources(sources)
end

function CooldownCompanion:IsCustomBarRuntimeEligible(customBar)
    if type(customBar) ~= "table" then return false end
    if customBar.enabled ~= true or not customBar.spellID then return false end
    if not self:IsTalentConditionMet(customBar) then return false end
    return self:IsCustomBarLoadConditionMet(customBar)
end


-- ToggleGroupGlobal is defined in GroupManagement.lua (container-aware version)

function CooldownCompanion:GroupHasPetSpells(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    for _, buttonData in ipairs(group.buttons) do
        if buttonData.isPetSpell then return true end
    end
    return false
end

local function SpellIDsMatchCanonicalForm(storedSpellID, resolvedSpellID)
    if not storedSpellID or not resolvedSpellID then
        return false
    end
    if storedSpellID == resolvedSpellID then
        return true
    end

    local storedBaseSpellID = C_Spell.GetBaseSpell(storedSpellID)
    local resolvedBaseSpellID = C_Spell.GetBaseSpell(resolvedSpellID)

    return storedBaseSpellID ~= nil
        and resolvedBaseSpellID ~= nil
        and storedBaseSpellID == resolvedBaseSpellID
end

function CooldownCompanion:IsButtonUsable(buttonData, group, opts)
    opts = opts or {}
    if buttonData.enabled == false then return false end

    if opts.checkLoadConditions ~= false and not self:IsButtonLoadConditionMet(buttonData, group) then return false end

    -- Per-button talent condition: gate visibility on a specific talent node.
    if not opts.ignoreTalentConditions and not self:IsTalentConditionMet(buttonData) then return false end

    if opts.ignoreSpellAvailability and buttonData.type == "spell" then
        return true
    end
    if opts.ignoreItemAvailability
        and (
            buttonData.type == "item"
            or (CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData))
        ) then
        return true
    end

    -- Passive/proc spells are tracked via aura, not spellbook presence.
    -- Multi-CDM-child buttons: verify their specific slot still exists in the CDM
    -- (spell may not be available on the current spec/talent loadout).
    if buttonData.isPassive then
        if buttonData.cdmChildSlot then
            local allChildren = self.viewerAuraAllChildren[buttonData.id]
            if not allChildren or not allChildren[buttonData.cdmChildSlot] then
                return false
            end
        end
        return true
    end

    if buttonData.type == "spell" then
        local bank = buttonData.isPetSpell
            and Enum.SpellBookSpellBank.Pet
            or Enum.SpellBookSpellBank.Player

        -- Pet spells: retain direct known/spellbook check.
        if buttonData.isPetSpell then
            return C_SpellBook.IsSpellKnownOrInSpellBook(buttonData.id, bank, false)
        end

        -- Player spells: require exact active-spec spellbook presence for this
        -- tracked spell ID (not an override/sibling form). This keeps loadability
        -- aligned with current-spec spellbook addability semantics.
        local slot, slotBank = C_SpellBook.FindSpellBookSlotForSpell(
            buttonData.id, false, true, false, false
        )
        if slot and slotBank == Enum.SpellBookSpellBank.Player then
            local itemType, _, spellID = C_SpellBook.GetSpellBookItemType(slot, slotBank)
            if spellID
                and not C_SpellBook.IsSpellBookItemOffSpec(slot, slotBank)
                and itemType ~= Enum.SpellBookItemType.FutureSpell
                and SpellIDsMatchCanonicalForm(buttonData.id, spellID)
            then
                return true
            end
        end

        -- Flyout child spells can be valid even when they don't resolve to a
        -- direct spell slot via FindSpellBookSlotForSpell.
        local flyoutSlot = C_SpellBook.FindFlyoutSlotBySpellID(buttonData.id)
        if not flyoutSlot then
            return false
        end

        local flyoutBank = Enum.SpellBookSpellBank.Player
        local flyoutType = C_SpellBook.GetSpellBookItemType(flyoutSlot, flyoutBank)
        if flyoutType ~= Enum.SpellBookItemType.Flyout then
            return false
        end
        if C_SpellBook.IsSpellBookItemOffSpec(flyoutSlot, flyoutBank) then
            return false
        end

        return true
    elseif CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
            and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
        return effectiveItem and effectiveItem.trackable == true
    elseif buttonData.type == "item" then
        if buttonData.hasCharges then return true end
        if not CooldownCompanion.IsItemEquippable(buttonData) then return true end
        return C_Item.GetItemCount(buttonData.id) > 0
    end
    return true
end

-- TALENT NODE CACHE (for per-button talent conditions)
------------------------------------------------------------------------

function CooldownCompanion:GetHeroSubTreeRootNode(configID, treeID, heroSubTreeID)
    if not configID or not treeID or not heroSubTreeID then
        return nil, nil
    end

    local nodeIDs = C_Traits.GetTreeNodes(treeID)
    if not nodeIDs then
        return nil, nil
    end

    local bestNodeID, bestNodeInfo = nil, nil
    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        if nodeInfo
            and nodeInfo.subTreeID == heroSubTreeID
            and nodeInfo.type ~= Enum.TraitNodeType.SubTreeSelection then
            if not bestNodeInfo
                or nodeInfo.posY < bestNodeInfo.posY
                or (nodeInfo.posY == bestNodeInfo.posY and nodeInfo.posX < bestNodeInfo.posX) then
                bestNodeID = nodeID
                bestNodeInfo = nodeInfo
            end
        end
    end

    return bestNodeID, bestNodeInfo
end

-- Rebuild the runtime talent node cache from the active talent config.
-- Called on TRAIT_CONFIG_UPDATED, PLAYER_ENTERING_WORLD, spec changes.
function CooldownCompanion:RebuildTalentNodeCache()
    if not self._talentNodeCache then
        self._talentNodeCache = {}
    else
        wipe(self._talentNodeCache)
    end

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    local specID = self._currentSpecId
    if not specID then return end
    -- Which spec this cache describes; a pass that would otherwise keep the
    -- cache rebuilds when the current spec no longer matches.
    self._talentNodeCacheSpecId = specID

    local treeID = C_ClassTalents.GetTraitTreeForSpec(specID)
    if not treeID then return end

    local activeHeroSubTreeID = self._currentHeroSpecId or C_ClassTalents.GetActiveHeroTalentSpec()
    local heroRootNodeID = nil
    if activeHeroSubTreeID then
        heroRootNodeID = self:GetHeroSubTreeRootNode(configID, treeID, activeHeroSubTreeID)
    end

    local nodeIDs = C_Traits.GetTreeNodes(treeID)
    if not nodeIDs then return end

    for _, nodeID in ipairs(nodeIDs) do
        local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
        local includeNode = nodeInfo
            and nodeInfo.isVisible
            and nodeInfo.type ~= Enum.TraitNodeType.SubTreeSelection
            and (
                not nodeInfo.subTreeID
                or (
                    activeHeroSubTreeID
                    and nodeInfo.subTreeID == activeHeroSubTreeID
                    and (
                        nodeInfo.type == Enum.TraitNodeType.Selection
                        or nodeID == heroRootNodeID
                    )
                )
            )
        if includeNode then
            self._talentNodeCache[nodeID] = {
                activeRank = nodeInfo.activeRank or 0,
                activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID or nil,
            }
        end
    end
end

-- Check whether per-button talent conditions are satisfied.
-- Returns true if no conditions set. All conditions use AND logic.
-- Missing nodes are treated as not taken.
function CooldownCompanion:IsTalentConditionMet(buttonData)
    local conditions = buttonData.talentConditions
    if not conditions or #conditions == 0 then return true end

    local needsNormalization = #conditions > 1 or IsLegacyChoiceRowCondition(conditions[1])
    if needsNormalization then
        local normalized, changed = self:NormalizeTalentConditions(conditions)
        if changed then
            buttonData.talentConditions = normalized
            conditions = normalized
            if not conditions or #conditions == 0 then return true end
        end
    end

    local cache = self._talentNodeCache
    if not cache then
        self:RebuildTalentNodeCache()
        cache = self._talentNodeCache
    end

    for _, cond in ipairs(conditions) do
        if cond.classID and self._playerClassID and cond.classID ~= self._playerClassID then
            return false
        end

        if cond.specID and cond.specID ~= self._currentSpecId then
            return false
        end

        local activeHeroSubTreeID = nil
        if cond.heroSubTreeID then
            activeHeroSubTreeID = self._currentHeroSpecId or C_ClassTalents.GetActiveHeroTalentSpec()
        end

        if IsHeroSpecProxyCondition(cond) then
            local show = cond.show or "taken"
            local heroIsActive = activeHeroSubTreeID ~= nil and cond.heroSubTreeID == activeHeroSubTreeID
            if show == "not_taken" then
                if heroIsActive then
                    return false
                end
            else
                if not heroIsActive then
                    return false
                end
            end
        elseif cond.heroSubTreeID then
            if cond.heroSubTreeID ~= activeHeroSubTreeID then
                return false
            end
        end

        if not IsHeroSpecProxyCondition(cond) then
            local entry = cache and cache[cond.nodeID] or nil
            local isTaken = entry and entry.activeRank > 0 or false

            -- For choice nodes: if a specific entryID is required, verify it matches
            if isTaken and cond.entryID then
                isTaken = (entry.activeEntryID == cond.entryID)
            end

            local show = cond.show or "taken"
            if show == "not_taken" then
                if isTaken then return false end
            else
                if not isTaken then return false end
            end
        end
    end

    return true
end
