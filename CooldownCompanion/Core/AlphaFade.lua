--[[
    CooldownCompanion - Core/AlphaFade.lua: Alpha fade system — per-group smooth visibility transitions
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsMounted = IsMounted
local UnitCanAttack = UnitCanAttack
local UnitExists = UnitExists
local GetShapeshiftForm = GetShapeshiftForm
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local pairs = pairs
local ipairs = ipairs
local type = type
local issecretvalue = issecretvalue

local SOAR_SPELL_ID = 430747

local function FrameAlphaDiffers(frame, alpha)
    if not (frame and frame.GetAlpha) then
        return false
    end
    return frame:GetAlpha() ~= alpha
end

local function HasLiveAlphaFrames(frames)
    if type(frames) ~= "table" then
        return false
    end
    for i = 1, #frames do
        if frames[i] then
            return true
        end
    end
    return false
end

local function AlphaFrameListsEqual(left, right)
    if left == right then
        return true
    end
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end
    if #left ~= #right then
        return false
    end
    for i = 1, #left do
        if left[i] ~= right[i] then
            return false
        end
    end
    return true
end

local function RestoreAlphaFrames(frames)
    if type(frames) ~= "table" then
        return
    end
    for i = 1, #frames do
        local frame = frames[i]
        if frame and frame.SetAlpha then
            frame:SetAlpha(1)
        end
    end
end

local function AlphaStateNeedsCleanup(self, stateKey)
    local state = self.alphaState and self.alphaState[stateKey]
    return state and state.currentAlpha and state.currentAlpha ~= 1 or false
end

local function ConfigNeedsAlphaUpdate(self, config, stateKey)
    if ST.HasActiveAlphaSettings and ST.HasActiveAlphaSettings(config) then
        return true
    end
    return AlphaStateNeedsCleanup(self, stateKey)
end

local function GetContainerAlphaStateKey(containerId)
    return "container_alpha:" .. tostring(containerId)
end

local EMPTY_TABLE = {}

local function HasTableEntries(tbl)
    if type(tbl) ~= "table" then
        return false
    end
    for _ in pairs(tbl) do
        return true
    end
    return false
end

local function NeedsContainerAlphaPass(self, containers)
    for containerId, container in pairs(containers or {}) do
        if container and container.groupAlphaEnabled == true then
            return true
        end
        if AlphaStateNeedsCleanup(self, GetContainerAlphaStateKey(containerId)) then
            return true
        end
    end
    return HasTableEntries(self._containerAlphaControlledGroups)
end

local function GroupNeedsAlphaUpdate(self, group, groupId, frame)
    if self.GetPanelContainerAlphaSource and self:GetPanelContainerAlphaSource(groupId) then
        return false
    end
    if self.ShouldInheritPanelAnchorAlpha and self:ShouldInheritPanelAnchorAlpha(groupId) then
        return false
    end
    if frame and frame._inheritsExternalAnchorAlpha then
        return false
    end
    if ST.IsGroupConfigSelected and ST.IsGroupConfigSelected(groupId) then
        return true
    end
    return ConfigNeedsAlphaUpdate(self, group, groupId)
end

local function FrameIsAlphaWorkTarget(frame, isDependencyTarget)
    return frame
        and ((frame.IsShown and frame:IsShown()) or isDependencyTarget)
end

local function GetGroupAlphaFrame(self, groupId)
    return (self.groupFrames and self.groupFrames[groupId])
        or (self._dormantFrames and self._dormantFrames[groupId])
end

local function GetStandaloneTextureHost(groupFrame)
    return CooldownCompanion.GetAuraTextureHostForGroupFrame
        and CooldownCompanion:GetAuraTextureHostForGroupFrame(groupFrame)
        or nil
end

local function ClampAlpha(alpha)
    if alpha < 0 then return 0 end
    if alpha > 1 then return 1 end
    return alpha
end

local function GetFrameAlphaWithContainerMultiplier(frame, alpha)
    local multiplier = frame and frame._containerAlphaVisibilityAlpha
    if type(multiplier) == "number" then
        return ClampAlpha(alpha * multiplier)
    end
    return alpha
end

local function ContainerAlphaIsUnlocked(self, container)
    return container and container.locked == false and not self._combatForcedLock
end

local function ApplyContainerAlphaFrame(self, frame, groupId, alpha, naturalAlpha, unlocked, previewAlpha)
    if not frame then
        return
    end

    local configSelected = ST.IsGroupConfigSelected and ST.IsGroupConfigSelected(groupId)
    local frameAlpha = alpha
    if previewAlpha then
        frame._naturalAlpha = naturalAlpha
        frameAlpha = GetFrameAlphaWithContainerMultiplier(frame, frameAlpha)
    elseif unlocked then
        frame._naturalAlpha = nil
        frameAlpha = 1
    elseif configSelected then
        frame._naturalAlpha = naturalAlpha
        frameAlpha = 1
    else
        frame._naturalAlpha = nil
        frameAlpha = GetFrameAlphaWithContainerMultiplier(frame, frameAlpha)
    end

    if FrameAlphaDiffers(frame, frameAlpha) then
        frame:SetAlpha(frameAlpha)
    end
end

function CooldownCompanion:GetContainerAlphaValue(containerId, container)
    local alpha = container and container.baselineAlpha or 1
    local state = self.alphaState and self.alphaState[GetContainerAlphaStateKey(containerId)]
    if state and state.currentAlpha ~= nil then
        alpha = state.currentAlpha
    end
    return alpha
end

function CooldownCompanion:GetPanelCurrentAlphaValue(groupId, group)
    if self.GetPanelContainerAlphaSource then
        local containerId, container = self:GetPanelContainerAlphaSource(groupId)
        if container then
            return self:GetContainerAlphaValue(containerId, container), true, true
        end
    end

    local state = self.alphaState and self.alphaState[groupId]
    if state and state.currentAlpha ~= nil then
        return state.currentAlpha, false, true
    end
    return group and group.baselineAlpha or 1, false, false
end

function CooldownCompanion:SetContainerAlphaVisibilityMultiplier(frame, multiplier)
    if not frame then
        return
    end
    if type(multiplier) == "number" then
        frame._containerAlphaVisibilityAlpha = ClampAlpha(multiplier)
    else
        frame._containerAlphaVisibilityAlpha = nil
    end
end

function CooldownCompanion:ApplyContainerAlphaToFrame(frame, alpha, visibilityMultiplier)
    if not frame then
        return
    end
    if visibilityMultiplier ~= nil then
        self:SetContainerAlphaVisibilityMultiplier(frame, visibilityMultiplier)
    end
    frame:SetAlpha(GetFrameAlphaWithContainerMultiplier(frame, alpha))
end

function CooldownCompanion:ClearContainerAlphaRuntimeState(containerId)
    if self.alphaState then
        self.alphaState[GetContainerAlphaStateKey(containerId)] = nil
    end
    self._containerAlphaControlledGroups = nil
end

local function AddContainerAlphaEntry(entriesByContainer, controlledGroups, containerId, groupId, group, frame)
    local entries = entriesByContainer[containerId]
    if not entries then
        entries = {}
        entriesByContainer[containerId] = entries
    end
    entries[#entries + 1] = {
        groupId = groupId,
        group = group,
        frame = frame,
    }

    controlledGroups[groupId] = true
end

local function BuildContainerAlphaEntryMaps(self, groups, panelAlphaAnchorTargets)
    local entriesByContainer = {}
    local controlledGroups = {}
    for groupId, group in pairs(groups or {}) do
        local sourceContainerId = self.GetPanelContainerAlphaSource
            and self:GetPanelContainerAlphaSource(groupId)
            or nil
        if sourceContainerId then
            local frame = GetGroupAlphaFrame(self, groupId)
            if FrameIsAlphaWorkTarget(frame, panelAlphaAnchorTargets and panelAlphaAnchorTargets[groupId]) then
                AddContainerAlphaEntry(entriesByContainer, controlledGroups, sourceContainerId, groupId, group, frame)
            end

            local host = GetStandaloneTextureHost(frame)
            if host and host.IsShown and host:IsShown() then
                AddContainerAlphaEntry(entriesByContainer, controlledGroups, sourceContainerId, groupId, group, host)
            end
        end
    end
    return entriesByContainer, controlledGroups
end

local function GroupSetHasMemberNotInCurrent(previousSet, currentSet)
    if type(previousSet) ~= "table" then
        return false
    end
    for groupId in pairs(previousSet) do
        if not (currentSet and currentSet[groupId]) then
            return true
        end
    end
    return false
end

local function ContainerAlphaEntryIsUnlocked(self, container, entry)
    if ContainerAlphaIsUnlocked(self, container) then
        return true
    end
    if self._combatForcedLock then
        return false
    end

    local group = entry and entry.group
    if group and group.locked == false then
        if self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then
            return false
        end
        return true
    end
    return false
end

local function ContainerAlphaNeedsUpdate(self, containerId, container, entries)
    local stateKey = GetContainerAlphaStateKey(containerId)
    if ConfigNeedsAlphaUpdate(self, container, stateKey) then
        return true
    end

    for i = 1, #entries do
        local entry = entries[i]
        if ST.IsGroupConfigSelected and ST.IsGroupConfigSelected(entry.groupId) then
            return true
        end
        if ContainerAlphaEntryIsUnlocked(self, container, entry) then
            if entry.frame and (entry.frame._naturalAlpha ~= nil or FrameAlphaDiffers(entry.frame, 1)) then
                return true
            end
        elseif FrameAlphaDiffers(entry.frame, GetFrameAlphaWithContainerMultiplier(entry.frame, 1)) then
            return true
        end
        if AlphaStateNeedsCleanup(self, entry.groupId) then
            return true
        end
    end
    return false
end

local function RestoreReleasedContainerAlphaGroups(self, previousSet, currentSet, groups, containers, now, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)
    if type(previousSet) ~= "table" then
        return false
    end

    local restored = false
    for groupId in pairs(previousSet) do
        if not (currentSet and currentSet[groupId]) then
            local group = groups and groups[groupId]
            local frame = GetGroupAlphaFrame(self, groupId)
            if group and frame then
                if (self.ShouldInheritPanelAnchorAlpha and self:ShouldInheritPanelAnchorAlpha(groupId))
                    or frame._inheritsExternalAnchorAlpha then
                    if self.alphaState then
                        self.alphaState[groupId] = nil
                    end
                else
                    local locked = true
                    if group.parentContainerId then
                        local container = containers and containers[group.parentContainerId]
                        if container then
                            locked = container.locked ~= false
                        end
                    else
                        locked = group.locked
                    end
                    self:UpdateGroupAlpha(groupId, group, locked, frame, now, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)
                end
                restored = true
            end
        end
    end
    return restored
end

-- Alpha fade system: per-group runtime state
-- self.alphaState[groupId] = {
--     currentAlpha   - current interpolated alpha
--     desiredAlpha   - target alpha (1.0 or baselineAlpha)
--     fadeStartAlpha - alpha at start of current fade
--     fadeDuration   - duration of current fade
--     fadeStartTime  - GetTime() when current fade began
--     hoverExpire    - GetTime() when mouseover grace period ends
-- }

local function UpdateFadedAlpha(state, desired, now, fadeInDur, fadeOutDur)
    -- Initialize on first call
    if state.currentAlpha == nil then
        state.currentAlpha = 1.0
        state.desiredAlpha = 1.0
        state.fadeDuration = 0
    end

    -- Start a new fade when desired target changes
    if state.desiredAlpha ~= desired then
        state.fadeStartAlpha = state.currentAlpha
        state.desiredAlpha = desired
        state.fadeStartTime = now

        local dur = 0
        if desired > state.currentAlpha then
            dur = fadeInDur or 0
        else
            dur = fadeOutDur or 0
        end
        state.fadeDuration = dur or 0

        -- Instant snap when duration is zero
        if state.fadeDuration <= 0 then
            state.currentAlpha = desired
            return desired
        end
    end

    -- Actively fading
    if state.fadeDuration and state.fadeDuration > 0 then
        local t = (now - (state.fadeStartTime or now)) / state.fadeDuration
        if t >= 1 then
            state.currentAlpha = state.desiredAlpha
            state.fadeDuration = 0
        elseif t < 0 then
            t = 0
        end

        if state.fadeDuration > 0 then
            local startAlpha = state.fadeStartAlpha or state.currentAlpha
            state.currentAlpha = startAlpha + (state.desiredAlpha - startAlpha) * t
        end
    else
        state.currentAlpha = desired
    end

    return state.currentAlpha
end

function CooldownCompanion:ResolveMountedAlphaStates(mounted)
    local unitAuras = C_UnitAuras
    local soarAura
    if unitAuras then
        -- Fast path for direct lookup.
        if unitAuras.GetPlayerAuraBySpellID then
            soarAura = unitAuras.GetPlayerAuraBySpellID(SOAR_SPELL_ID)
        end
        if not soarAura and unitAuras.GetUnitAuraBySpellID then
            soarAura = unitAuras.GetUnitAuraBySpellID("player", SOAR_SPELL_ID)
        end
        -- Fallback: direct lookups can miss Soar in some runtime states.
        -- Restrict the full helpful-aura scan to dirty recomputes.
        if not soarAura and mounted and self._mountAlphaDirty and self._isDracthyr and unitAuras.GetUnitAuras then
            local helpfulAuras = unitAuras.GetUnitAuras("player", "HELPFUL")
            if type(helpfulAuras) == "table" then
                for _, auraData in ipairs(helpfulAuras) do
                    local auraSpellID = auraData and auraData.spellId
                    if issecretvalue then
                        if not issecretvalue(auraSpellID) and auraSpellID == SOAR_SPELL_ID then
                            soarAura = auraData
                            break
                        end
                    elseif auraSpellID == SOAR_SPELL_ID then
                        soarAura = auraData
                        break
                    end
                end
            end
        end
    end
    local soarActive = soarAura ~= nil
    if not mounted and not soarActive then
        self._mountAlphaDirty = false
        self._mountAlphaCacheMounted = false
        self._mountAlphaCacheSoar = false
        self._isRegularMounted = false
        self._isDragonridingMounted = false
        return false, false
    end

    if not self._mountAlphaDirty
       and self._mountAlphaCacheMounted == (mounted == true)
       and self._mountAlphaCacheSoar == (soarActive == true) then
        return self._isRegularMounted == true, self._isDragonridingMounted == true
    end

    local isRegularMounted = mounted == true -- Fallback while mounted if active mount cannot be resolved.
    local isDragonridingMounted = false
    if mounted then
        local mountJournal = C_MountJournal
        if mountJournal and mountJournal.GetCollectedDragonridingMounts and mountJournal.GetMountInfoByID then
            local dragonridingMountIDs = mountJournal.GetCollectedDragonridingMounts()
            if type(dragonridingMountIDs) == "table" then
                for _, mountID in ipairs(dragonridingMountIDs) do
                    local _, _, _, isActive, _, _, _, _, _, _, _, _, isSteadyFlight = mountJournal.GetMountInfoByID(mountID)
                    if isActive then
                        if not isSteadyFlight then
                            isRegularMounted = false
                            isDragonridingMounted = true
                        end
                        break
                    end
                end
            end
        end
    end

    -- Treat Dracthyr Soar as Skyriding for alpha conditions.
    if soarActive then
        isRegularMounted = false
        isDragonridingMounted = true
    end

    self._mountAlphaDirty = false
    self._mountAlphaCacheMounted = mounted == true
    self._mountAlphaCacheSoar = soarActive == true
    self._isRegularMounted = isRegularMounted
    self._isDragonridingMounted = isDragonridingMounted
    return isRegularMounted, isDragonridingMounted
end

function CooldownCompanion:InvalidateMountAlphaCache()
    self._mountAlphaDirty = true
end

-- Shared force-condition evaluation: returns forceFull (bool), forceHidden (bool), baselineAlpha (number).
-- Used by both UpdateGroupAlpha and UpdateModuleAlpha.
local function EvaluateDesiredAlpha(config, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)
    -- Effective mounted states: mounted subtype plus optional druid travel form.
    local effectiveRegularMounted = regularMounted
    local effectiveDragonridingMounted = dragonridingMounted
    if config.treatTravelFormAsMounted and inTravelForm then
        if inTravelForm == 783 then
            effectiveRegularMounted = false
            effectiveDragonridingMounted = true
        else
            effectiveRegularMounted = true
            effectiveDragonridingMounted = false
        end
    end

    -- Check force-hidden conditions
    local forceHidden = false
    if config.forceHideInCombat and inCombat then
        forceHidden = true
    elseif config.forceHideOutOfCombat and not inCombat then
        forceHidden = true
    elseif config.forceHideRegularMounted and effectiveRegularMounted then
        forceHidden = true
    elseif config.forceHideDragonriding and effectiveDragonridingMounted then
        forceHidden = true
    end

    -- Check force-visible conditions (priority: visible > hidden > baseline)
    local forceFull = false
    if config.forceAlphaInCombat and inCombat then
        forceFull = true
    elseif config.forceAlphaOutOfCombat and not inCombat then
        forceFull = true
    elseif config.forceAlphaRegularMounted and effectiveRegularMounted then
        forceFull = true
    elseif config.forceAlphaDragonriding and effectiveDragonridingMounted then
        forceFull = true
    elseif config.forceAlphaTargetExists
        and ((config.forceAlphaTargetEnemyOnly and hasEnemyTarget) or ((not config.forceAlphaTargetEnemyOnly) and hasTarget)) then
        forceFull = true
    elseif config.forceAlphaFocusExists and hasFocus then
        forceFull = true
    end

    return forceFull, forceHidden, config.baselineAlpha or 1
end

function CooldownCompanion:UpdateGroupAlpha(groupId, group, locked, frame, now, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)
    local state = self.alphaState[groupId]
    if not state then
        state = {}
        self.alphaState[groupId] = state
    end

    local cursorPreviewActive = self.IsCursorAnchorLayoutPreviewGroupActive
        and self:IsCursorAnchorLayoutPreviewGroupActive(groupId)
    if cursorPreviewActive then
        locked = false
    elseif not locked and self:IsGroupCursorAnchored(group) then
        locked = true
    end

    -- Force 100% alpha while group is unlocked for easier positioning
    if not locked then
        frame._naturalAlpha = nil
        if state.currentAlpha ~= 1 or state.lastAlpha ~= 1 or FrameAlphaDiffers(frame, 1) then
            frame:SetAlpha(1)
            state.currentAlpha = 1
            state.desiredAlpha = 1
            state.fadeDuration = 0
            state.lastAlpha = 1
        end
        return
    end

    local configSelected = ST.IsGroupConfigSelected(groupId)

    -- Skip processing when feature is entirely unused (baseline=1, no forceHide toggles)
    local hasForceHide = group.forceHideInCombat or group.forceHideOutOfCombat
        or group.forceHideRegularMounted or group.forceHideDragonriding
    if group.baselineAlpha == 1 and not hasForceHide then
        if configSelected then
            frame._naturalAlpha = 1
        else
            frame._naturalAlpha = nil
        end
        if (state.currentAlpha and state.currentAlpha ~= 1) or FrameAlphaDiffers(frame, 1) then
            frame:SetAlpha(1)
            state.currentAlpha = 1
            state.desiredAlpha = 1
            state.fadeDuration = 0
        end
        if configSelected then
            state.lastAlpha = 1
        end
        return
    end

    local forceFull, forceHidden, baseline = EvaluateDesiredAlpha(group, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)

    -- Mouseover check (geometric, works even when click-through)
    local ignoreSelfMouseover = CooldownCompanion:IsGroupCursorAnchored(group)
    if not forceFull and group.forceAlphaMouseover and not ignoreSelfMouseover then
        local isHovering = frame:IsMouseOver()
        if isHovering then
            forceFull = true
            state.hoverExpire = now + (group.fadeDelay or 1)
        elseif state.hoverExpire and now < state.hoverExpire then
            forceFull = true
        end
    end

    local desired = forceFull and 1 or (forceHidden and 0 or baseline)

    -- Config-selected override: store the natural alpha for downstream consumers,
    -- then force the frame itself to full alpha for config visibility.
    if configSelected then
        frame._naturalAlpha = desired
        if state.lastAlpha ~= 1 or FrameAlphaDiffers(frame, 1) then
            frame:SetAlpha(1)
            state.currentAlpha = 1
            state.desiredAlpha = 1
            state.fadeDuration = 0
            state.lastAlpha = 1
        end
        return
    end

    frame._naturalAlpha = nil
    local fadeIn = group.fadeInDuration or 0.2
    local fadeOut = group.fadeOutDuration or 0.2
    local alpha = UpdateFadedAlpha(state, desired, now, fadeIn, fadeOut)

    if state.lastAlpha ~= alpha or FrameAlphaDiffers(frame, alpha) then
        frame:SetAlpha(alpha)
        state.lastAlpha = alpha
    end
end

local function ResetAlphaState(state)
    if not state then
        return
    end
    state.currentAlpha = 1
    state.desiredAlpha = 1
    state.fadeDuration = 0
    state.lastAlpha = 1
    state.hoverExpire = nil
end

local function ResetOwnedGroupAlphaState(self, groupId)
    if self.alphaState then
        self.alphaState[groupId] = nil
    end
end

function CooldownCompanion:UpdateContainerAlpha(containerId, container, entries, now, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)
    local stateKey = GetContainerAlphaStateKey(containerId)
    local state = self.alphaState[stateKey]
    if not state then
        state = {}
        self.alphaState[stateKey] = state
    end

    local forceFull, forceHidden, baseline = EvaluateDesiredAlpha(container, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)

    if not forceFull and container.forceAlphaMouseover then
        local isHovering = false
        for i = 1, #entries do
            local frame = entries[i].frame
            if frame and frame.IsShown and frame:IsShown()
                and frame.IsMouseOver and frame:IsMouseOver() then
                isHovering = true
                break
            end
        end
        if isHovering then
            forceFull = true
            state.hoverExpire = now + (container.fadeDelay or 1)
        elseif state.hoverExpire and now < state.hoverExpire then
            forceFull = true
        end
    end

    local desired = forceFull and 1 or (forceHidden and 0 or baseline)
    local fadeIn = container.fadeInDuration or 0.2
    local fadeOut = container.fadeOutDuration or 0.2
    local alpha = UpdateFadedAlpha(state, desired, now, fadeIn, fadeOut)

    for i = 1, #entries do
        local entry = entries[i]
        local frame = entry.frame
        if frame then
            local unlocked = ContainerAlphaEntryIsUnlocked(self, container, entry)
            ApplyContainerAlphaFrame(self, frame, entry.groupId, alpha, desired, unlocked)
            ResetOwnedGroupAlphaState(self, entry.groupId)
        end
    end

    state.lastAlpha = alpha
end

function CooldownCompanion:ApplyContainerAlphaPreview(containerId, alpha)
    local profile = self.db and self.db.profile
    local container = profile and profile.groupContainers and profile.groupContainers[containerId] or nil
    local unlocked = ContainerAlphaIsUnlocked(self, container)
    local function applyPreviewAlpha(frame, groupId)
        if not (frame and frame.IsShown and frame:IsShown()) then
            return
        end
        ApplyContainerAlphaFrame(self, frame, groupId, alpha, alpha, unlocked, true)
    end

    local groups = profile and profile.groups or nil
    local entriesByContainer = BuildContainerAlphaEntryMaps(self, groups)
    local entries = entriesByContainer[containerId]
    for i = 1, #(entries or EMPTY_TABLE) do
        local entry = entries[i]
        applyPreviewAlpha(entry.frame, entry.groupId)
    end

    local stateKey = GetContainerAlphaStateKey(containerId)
    if self.alphaState then
        local state = self.alphaState[stateKey]
        if not state then
            state = {}
            self.alphaState[stateKey] = state
        end
        state.currentAlpha = alpha
        state.desiredAlpha = alpha
        state.fadeStartAlpha = alpha
        state.lastAlpha = alpha
        state.fadeDuration = 0
    end
end

-- Module alpha: evaluates alpha for non-group frames (resource bars, cast bar).
-- moduleId: unique string key (e.g., "rb", "cb")
-- config: table with the same alpha fields as group (baselineAlpha, forceAlpha*, etc.)
-- frames: list of frames to apply alpha to
function CooldownCompanion:UpdateModuleAlpha(moduleId, config, frames, now, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)
    local state = self.alphaState[moduleId]
    if not state then
        state = {}
        self.alphaState[moduleId] = state
    end

    local forceFull, forceHidden, baseline = EvaluateDesiredAlpha(config, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)

    -- Mouseover check across all frames
    local ignoreModuleSelfMouseover = self:IsGroupCursorAnchored(config)
    if not forceFull and config.forceAlphaMouseover and not ignoreModuleSelfMouseover then
        local isHovering = false
        for i = 1, #frames do
            local f = frames[i]
            if f and f:IsShown() and f:IsMouseOver() then
                isHovering = true
                break
            end
        end
        if isHovering then
            forceFull = true
            state.hoverExpire = now + (config.fadeDelay or 1)
        elseif state.hoverExpire and now < state.hoverExpire then
            forceFull = true
        end
    end

    local desired = forceFull and 1 or (forceHidden and 0 or baseline)
    local fadeIn = config.fadeInDuration or 0.2
    local fadeOut = config.fadeOutDuration or 0.2
    local alpha = UpdateFadedAlpha(state, desired, now, fadeIn, fadeOut)

    if state.lastAlpha ~= alpha then
        for i = 1, #frames do
            local f = frames[i]
            if f then f:SetAlpha(alpha) end
        end
        state.lastAlpha = alpha
    end
end

-- Registration for module alpha targets processed by the OnUpdate loop.
-- _moduleAlphaTargets[moduleId] = { config = table, frames = {frame, ...} }
function CooldownCompanion:RegisterModuleAlpha(moduleId, config, frames)
    if not self._moduleAlphaTargets then
        self._moduleAlphaTargets = {}
    end
    local hasActiveSettings = ST.HasActiveAlphaSettings and ST.HasActiveAlphaSettings(config) or false
    local entry = self._moduleAlphaTargets[moduleId]
    if entry and entry.config == config and AlphaFrameListsEqual(entry.frames, frames) then
        if entry.hasActiveSettings ~= hasActiveSettings then
            entry.hasActiveSettings = hasActiveSettings
            self:RefreshAlphaUpdateDriver()
            return
        end
        local alphaFrame = self._alphaFrame
        if alphaFrame and not alphaFrame:GetScript("OnUpdate")
            and HasLiveAlphaFrames(frames)
            and ConfigNeedsAlphaUpdate(self, config, moduleId) then
            self:RefreshAlphaUpdateDriver()
        end
        return
    end
    self._moduleAlphaTargets[moduleId] = { config = config, frames = frames, hasActiveSettings = hasActiveSettings }
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end

function CooldownCompanion:UnregisterModuleAlpha(moduleId, preserveState)
    local entry = self._moduleAlphaTargets and self._moduleAlphaTargets[moduleId] or nil
    local frames = entry and entry.frames or nil
    if not preserveState then
        RestoreAlphaFrames(frames)
    end
    if self._moduleAlphaTargets then
        self._moduleAlphaTargets[moduleId] = nil
    end
    if self.alphaState and ((not preserveState) or not HasLiveAlphaFrames(frames)) then
        self.alphaState[moduleId] = nil
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end

function CooldownCompanion:EvaluateAlphaDriverNeedsWork()
    local profile = self.db and self.db.profile
    if type(profile) ~= "table" then
        return false
    end

    local groups = profile.groups or {}
    local containers = profile.groupContainers or {}
    local groupFrames = self.groupFrames or {}
    local dormantFrames = self._dormantFrames
    local previousEvaluating = self._evaluatingAlphaDriverNeedsWork
    self._evaluatingAlphaDriverNeedsWork = true
    local panelAlphaAnchorTargets = self.GetPanelAlphaDependencyTargets
        and self:GetPanelAlphaDependencyTargets(groups)
        or nil
    self._evaluatingAlphaDriverNeedsWork = previousEvaluating

    local entriesByContainer, containerAlphaControlledGroups = EMPTY_TABLE, EMPTY_TABLE
    if NeedsContainerAlphaPass(self, containers) then
        entriesByContainer, containerAlphaControlledGroups =
            BuildContainerAlphaEntryMaps(self, groups, panelAlphaAnchorTargets)
        if GroupSetHasMemberNotInCurrent(self._containerAlphaControlledGroups, containerAlphaControlledGroups) then
            return true
        end
        for containerId, container in pairs(containers) do
            local entries = entriesByContainer[containerId]
            if container and container.groupAlphaEnabled == true
                and entries
                and #entries > 0
                and ContainerAlphaNeedsUpdate(self, containerId, container, entries) then
                return true
            end

            if AlphaStateNeedsCleanup(self, GetContainerAlphaStateKey(containerId)) then
                return true
            end
        end
    end

    for groupId, group in pairs(groups) do
        local frame = groupFrames[groupId] or (dormantFrames and dormantFrames[groupId])
        if not containerAlphaControlledGroups[groupId]
            and FrameIsAlphaWorkTarget(frame, panelAlphaAnchorTargets and panelAlphaAnchorTargets[groupId]) then
            if GroupNeedsAlphaUpdate(self, group, groupId, frame) then
                return true
            end
        end
    end

    if self._moduleAlphaTargets then
        for moduleId, entry in pairs(self._moduleAlphaTargets) do
            if entry and HasLiveAlphaFrames(entry.frames)
                and ConfigNeedsAlphaUpdate(self, entry.config, moduleId) then
                return true
            end
        end
    end

    return false
end

function CooldownCompanion:AlphaUpdateOnUpdate(dt)
    local updateInterval = self._alphaUpdateInterval or (1 / 30)
    self._alphaUpdateAccumulator = (self._alphaUpdateAccumulator or 0) + (dt or 0)
    if self._alphaUpdateAccumulator < updateInterval then return end
    self._alphaUpdateAccumulator = 0

    local now = GetTime()
    local inCombat = InCombatLockdown()
    local hasTarget = UnitExists("target")
    local hasEnemyTarget = hasTarget and UnitCanAttack("player", "target") and true or false
    local hasFocus = UnitExists("focus")
    local mounted = IsMounted()
    local regularMounted, dragonridingMounted = self:ResolveMountedAlphaStates(mounted)

    local inTravelForm = false
    if self._playerClassID == 11 then -- Druid
        local fi = GetShapeshiftForm()
        if fi and fi > 0 then
            local _, _, _, spellID = GetShapeshiftFormInfo(fi)
            if spellID == 783 or spellID == 210053 then
                inTravelForm = spellID
            end
        end
    end

    local containers = self.db.profile.groupContainers or {}
    local groups = self.db.profile.groups or {}
    local panelAlphaAnchorTargets = self:GetPanelAlphaDependencyTargets(groups)
    local needsPostPassRefresh = false
    local processedAlphaWork = false
    local entriesByContainer, containerAlphaControlledGroups = EMPTY_TABLE, EMPTY_TABLE
    if NeedsContainerAlphaPass(self, containers) then
        local previousContainerAlphaGroups = self._containerAlphaControlledGroups
        entriesByContainer, containerAlphaControlledGroups =
            BuildContainerAlphaEntryMaps(self, groups, panelAlphaAnchorTargets)

        if RestoreReleasedContainerAlphaGroups(self, previousContainerAlphaGroups, containerAlphaControlledGroups, groups, containers, now, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm) then
            processedAlphaWork = true
            needsPostPassRefresh = true
        end

        for containerId, container in pairs(containers) do
            local entries = entriesByContainer[containerId]

            if entries and #entries > 0 then
                if ContainerAlphaNeedsUpdate(self, containerId, container, entries) then
                    processedAlphaWork = true
                    if not (ST.HasActiveAlphaSettings and ST.HasActiveAlphaSettings(container)) then
                        needsPostPassRefresh = true
                    end
                    self:UpdateContainerAlpha(containerId, container, entries, now, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)
                end
            else
                local stateKey = GetContainerAlphaStateKey(containerId)
                local state = AlphaStateNeedsCleanup(self, stateKey)
                    and self.alphaState
                    and self.alphaState[stateKey]
                    or nil
                if state then
                    self.alphaState[stateKey] = nil
                    processedAlphaWork = true
                    needsPostPassRefresh = true
                end
            end
        end
    end
    self._containerAlphaControlledGroups = HasTableEntries(containerAlphaControlledGroups) and containerAlphaControlledGroups or nil

    for groupId, group in pairs(groups) do
        local frame = self.groupFrames[groupId] or (self._dormantFrames and self._dormantFrames[groupId])
        if not containerAlphaControlledGroups[groupId]
            and FrameIsAlphaWorkTarget(frame, panelAlphaAnchorTargets and panelAlphaAnchorTargets[groupId]) then
            if GroupNeedsAlphaUpdate(self, group, groupId, frame) then
                processedAlphaWork = true
                if not (ST.HasActiveAlphaSettings and ST.HasActiveAlphaSettings(group))
                    and AlphaStateNeedsCleanup(self, groupId) then
                    needsPostPassRefresh = true
                end
                local locked = true
                if group.parentContainerId then
                    local c = containers[group.parentContainerId]
                    if c then locked = c.locked ~= false end
                else
                    locked = group.locked
                end
                self:UpdateGroupAlpha(groupId, group, locked, frame, now, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)
            end
        end
    end

    -- Process registered module alpha targets (resource bars, custom aura bars, texture panels)
    if self._moduleAlphaTargets then
        for moduleId, entry in pairs(self._moduleAlphaTargets) do
            if entry and HasLiveAlphaFrames(entry.frames)
                and ConfigNeedsAlphaUpdate(self, entry.config, moduleId) then
                processedAlphaWork = true
                if not (ST.HasActiveAlphaSettings and ST.HasActiveAlphaSettings(entry.config))
                    and AlphaStateNeedsCleanup(self, moduleId) then
                    needsPostPassRefresh = true
                end
                self:UpdateModuleAlpha(moduleId, entry.config, entry.frames, now, inCombat, hasTarget, hasEnemyTarget, hasFocus, regularMounted, dragonridingMounted, inTravelForm)
            end
        end
    end
    if needsPostPassRefresh or not processedAlphaWork then
        self:RefreshAlphaUpdateDriver()
    end
end

function CooldownCompanion:RefreshAlphaUpdateDriver()
    if not self._alphaFrame then
        if self._initializingAlphaUpdateFrame then
            return false
        end
        if self.InitAlphaUpdateFrame then
            self:InitAlphaUpdateFrame()
        end
    end

    local alphaFrame = self._alphaFrame
    if not alphaFrame then
        return false
    end

    local needsWork = self:EvaluateAlphaDriverNeedsWork()
    local handler = self._alphaUpdateHandler
    if needsWork then
        if not alphaFrame:GetScript("OnUpdate") then
            alphaFrame:SetScript("OnUpdate", handler)
        end
    else
        if alphaFrame:GetScript("OnUpdate") then
            alphaFrame:SetScript("OnUpdate", nil)
        end
        self._alphaUpdateAccumulator = 0
    end
    return needsWork
end

function CooldownCompanion:InitAlphaUpdateFrame()
    if self._alphaFrame then
        self:RefreshAlphaUpdateDriver()
        return
    end

    self._initializingAlphaUpdateFrame = true
    self._alphaFrame = CreateFrame("Frame")
    self._alphaUpdateAccumulator = 0
    self._alphaUpdateInterval = 1 / 30 -- ~30Hz for smooth fading
    self._alphaUpdateHandler = function(_, dt)
        self:AlphaUpdateOnUpdate(dt)
    end
    self._initializingAlphaUpdateFrame = nil
    self:RefreshAlphaUpdateDriver()
end
