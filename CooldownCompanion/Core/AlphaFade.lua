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
local wipe = wipe

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

-- Disarm contract (EnsureAlphaDriverArmed / EvaluateAlphaDriverNeedsWork): the
-- 30 Hz driver may stop only while every live alpha config has SETTLED
-- (currentAlpha == desiredAlpha, no fade running, no hover grace left) AND every
-- condition it reads arrives as an event that re-arms the driver. These three
-- force conditions are polled, not evented, so one live config using any of them
-- keeps the driver running for the session:
--   forceAlphaMouseover        geometric IsMouseOver, deliberately frame-polled
--                              so it still works on click-through panels
--   forceAlphaFocusExists      PLAYER_FOCUS_CHANGED is registered nowhere here
--   forceAlphaTargetEnemyOnly  a hostility flip on a RETAINED target fires no
--                              event this addon listens to
-- Every other condition input owes a re-arm hook: combat edges (OnCombatStart /
-- OnCombatEnd), mount and Soar (InvalidateMountAlphaCache), target existence
-- (OnTargetChanged), druid travel form (UPDATE_SHAPESHIFT_FORM), the
-- cursor-anchor layout preview, and the config / lock / panel-lifecycle paths
-- that already call RefreshAlphaUpdateDriver. A NEW force condition must either
-- bring its event hook or be listed above.
local function AlphaConfigNeedsDriverPolling(config)
    return config.forceAlphaMouseover == true
        or config.forceAlphaFocusExists == true
        or (config.forceAlphaTargetExists == true and config.forceAlphaTargetEnemyOnly == true)
end

-- Exact, no epsilon: UpdateFadedAlpha snaps currentAlpha onto desiredAlpha and
-- zeroes fadeDuration the moment a fade completes, and zero-duration targets snap
-- on the spot, so equality IS the end-of-fade test. A missing state has never
-- been written and still owes its first pass.
local function AlphaStateIsSettled(self, stateKey, now)
    local state = self.alphaState and self.alphaState[stateKey]
    if not state then
        return false
    end
    if state.currentAlpha == nil or state.currentAlpha ~= state.desiredAlpha then
        return false
    end
    if (state.fadeDuration or 0) ~= 0 then
        return false
    end
    if state.hoverExpire and now < state.hoverExpire then
        return false
    end
    return true
end

-- The config shape UpdateGroupAlpha's early-out serves: alpha is pinned at 1 for
-- every condition, so that path holds the frame at 1 and can return WITHOUT ever
-- writing runtime state. Keep in step with the hasForceHide test there.
local function AlphaConfigPinsFullAlpha(config)
    return (config.baselineAlpha or 1) == 1
        and not (config.forceHideInCombat or config.forceHideOutOfCombat
            or config.forceHideRegularMounted or config.forceHideDragonriding)
end

-- Probe-only branch of ConfigNeedsAlphaUpdate: a LIVE alpha config with nothing
-- left to do. probeFrame, where the caller owns exactly one, refuses to disarm
-- while the frame wears an alpha this state did not put there.
local function LiveAlphaConfigNeedsDriver(self, config, stateKey, now, probeFrame)
    if AlphaConfigNeedsDriverPolling(config) then
        return true
    end

    local state = self.alphaState and self.alphaState[stateKey]
    -- Blank state under a pinned-full config is settled, not unstarted: the
    -- frame alpha is the only thing that path promises, so read that instead.
    if probeFrame and (state == nil or state.currentAlpha == nil)
        and AlphaConfigPinsFullAlpha(config) then
        return FrameAlphaDiffers(probeFrame, 1)
    end

    if not AlphaStateIsSettled(self, stateKey, now) then
        return true
    end
    if probeFrame and FrameAlphaDiffers(probeFrame, state.currentAlpha) then
        return true
    end
    return false
end

-- probeNow (a GetTime() stamp) switches this from "is this config alpha-driven"
-- to "does this config still need the driver RUNNING". Only the arming
-- evaluation passes it; the 30 Hz pass itself keeps processing every live config
-- exactly as before.
local function ConfigNeedsAlphaUpdate(self, config, stateKey, probeNow, probeFrame)
    if ST.HasActiveAlphaSettings and ST.HasActiveAlphaSettings(config) then
        if not probeNow then
            return true
        end
        return LiveAlphaConfigNeedsDriver(self, config, stateKey, probeNow, probeFrame)
    end
    return AlphaStateNeedsCleanup(self, stateKey)
end

-- Cheap per-item trigger the 30 Hz pass uses to decide whether a full
-- RefreshAlphaUpdateDriver evaluation is worth paying for this tick. Wrong
-- either way it only skips or adds one evaluation: RefreshAlphaUpdateDriver
-- stays the sole authority on arming.
local function AlphaWorkMaySettle(self, config, stateKey, now)
    if type(config) ~= "table" or AlphaConfigNeedsDriverPolling(config) then
        return false
    end
    local state = self.alphaState and self.alphaState[stateKey]
    if (state == nil or state.currentAlpha == nil) and AlphaConfigPinsFullAlpha(config) then
        return true
    end
    return AlphaStateIsSettled(self, stateKey, now)
end

-- Composed once per container id and kept for the session: the ids are the small
-- stable integers the profile assigns, and this key is rebuilt several times per
-- container per 30 Hz alpha pass.
local containerAlphaStateKeys = {}

local function GetContainerAlphaStateKey(containerId)
    if containerId == nil then
        return "container_alpha:nil"
    end
    local key = containerAlphaStateKeys[containerId]
    if not key then
        key = "container_alpha:" .. tostring(containerId)
        containerAlphaStateKeys[containerId] = key
    end
    return key
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

local function GroupNeedsAlphaUpdate(self, group, groupId, frame, probeNow)
    if self.GetPanelContainerAlphaSource and self:GetPanelContainerAlphaSource(groupId) then
        return false
    end
    if self.ShouldInheritPanelAnchorAlpha and self:ShouldInheritPanelAnchorAlpha(groupId) then
        return false
    end
    if frame and frame._inheritsExternalAnchorAlpha then
        return false
    end
    if ST.IsGroupRuntimeLayoutPreviewActive
        and ST.IsGroupRuntimeLayoutPreviewActive(groupId) then
        return true
    end
    return ConfigNeedsAlphaUpdate(self, group, groupId, probeNow, frame)
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

local function GetUnlockedPanelAlpha(frame)
    return frame and frame._unlockGhost and 0.4 or 1
end

local function ContainerAlphaIsUnlocked(self, container)
    return container and container.locked == false and not self._combatForcedLock
end

local function ApplyContainerAlphaFrame(self, frame, groupId, alpha, naturalAlpha, unlocked, previewAlpha)
    if not frame then
        return
    end

    local layoutPreviewActive = ST.IsGroupRuntimeLayoutPreviewActive
        and ST.IsGroupRuntimeLayoutPreviewActive(groupId)
    local frameAlpha = alpha
    if previewAlpha then
        frame._naturalAlpha = naturalAlpha
        frameAlpha = GetFrameAlphaWithContainerMultiplier(frame, frameAlpha)
    elseif unlocked then
        frame._naturalAlpha = nil
        frameAlpha = GetUnlockedPanelAlpha(frame)
    elseif layoutPreviewActive then
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

-- Per-call-site scratch for the container-alpha entry maps, which the 30 Hz
-- driver rebuilds twice per pass. Nothing downstream retains the maps, the
-- per-container lists or the entry records: every consumer reads them inside the
-- calling pass and drops them. A pass CAN nest another builder call (the driver
-- refresh at the end of an alpha pass re-evaluates), so each call site owns its
-- own structures and can never wipe another's live maps. Re-entering the SAME
-- call site is unreachable: an OnUpdate handler cannot re-enter itself,
-- EvaluateAlphaDriverNeedsWork only reads state, and the preview is
-- config-driven. Anything that starts RETAINING a returned map must go back to
-- fresh tables for that call site.
local function NewEntryMapScratch()
    return { maps = {}, pool = {}, used = 0 }
end

local driverEntryScratch = NewEntryMapScratch()
local evaluateEntryScratch = NewEntryMapScratch()
local previewEntryScratch = NewEntryMapScratch()

-- The controlled-group SET is the one value that outlives its build:
-- AlphaUpdateOnUpdate publishes it on self and the next pass diffs against it.
-- Its two sets therefore alternate, so a build never writes the published one.
-- No other call site publishes, so each keeps a single set.
local driverControlledGroupsA, driverControlledGroupsB = {}, {}
local evaluateControlledGroups = {}
local previewControlledGroups = {}

local function AcquireContainerAlphaEntry(scratch, groupId, group, frame)
    local used = scratch.used + 1
    scratch.used = used
    local entry = scratch.pool[used]
    if not entry then
        entry = {}
        scratch.pool[used] = entry
    end
    entry.groupId = groupId
    entry.group = group
    entry.frame = frame
    return entry
end

local function AddContainerAlphaEntry(scratch, entriesByContainer, controlledGroups, containerId, groupId, group, frame)
    local entries = entriesByContainer[containerId]
    if not entries then
        entries = {}
        entriesByContainer[containerId] = entries
    end
    entries[#entries + 1] = AcquireContainerAlphaEntry(scratch, groupId, group, frame)

    controlledGroups[groupId] = true
end

local function BuildContainerAlphaEntryMaps(self, groups, panelAlphaAnchorTargets, scratch, controlledGroups)
    -- Emptied, not dropped: a container that contributes no entry this pass keeps
    -- a zero-length list, which every consumer reads the same way it read nil.
    local entriesByContainer = scratch.maps
    for _, entries in pairs(entriesByContainer) do
        wipe(entries)
    end
    scratch.used = 0
    wipe(controlledGroups)

    for groupId, group in pairs(groups or {}) do
        local sourceContainerId = self.GetPanelContainerAlphaSource
            and self:GetPanelContainerAlphaSource(groupId)
            or nil
        if sourceContainerId then
            local frame = GetGroupAlphaFrame(self, groupId)
            if FrameIsAlphaWorkTarget(frame, panelAlphaAnchorTargets and panelAlphaAnchorTargets[groupId]) then
                AddContainerAlphaEntry(scratch, entriesByContainer, controlledGroups, sourceContainerId, groupId, group, frame)
            end

            local host = GetStandaloneTextureHost(frame)
            if host and host.IsShown and host:IsShown() then
                AddContainerAlphaEntry(scratch, entriesByContainer, controlledGroups, sourceContainerId, groupId, group, host)
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

local function ContainerAlphaNeedsUpdate(self, containerId, container, entries, probeNow)
    local stateKey = GetContainerAlphaStateKey(containerId)
    if ConfigNeedsAlphaUpdate(self, container, stateKey, probeNow) then
        return true
    end

    -- Reaching here with a LIVE container config only happens on the disarm
    -- probe, and then the settled container alpha is what its locked entries
    -- should be wearing. The restore-to-1 comparison below belongs to the
    -- cleanup path (config switched off, entries owed their alpha back).
    local entryAlpha = 1
    if probeNow and ST.HasActiveAlphaSettings and ST.HasActiveAlphaSettings(container) then
        local state = self.alphaState and self.alphaState[stateKey]
        entryAlpha = state and state.currentAlpha or 1
    end

    for i = 1, #entries do
        local entry = entries[i]
        if ST.IsGroupRuntimeLayoutPreviewActive
            and ST.IsGroupRuntimeLayoutPreviewActive(entry.groupId) then
            return true
        end
        if ContainerAlphaEntryIsUnlocked(self, container, entry) then
            if entry.frame
                and (entry.frame._naturalAlpha ~= nil
                    or FrameAlphaDiffers(entry.frame, GetUnlockedPanelAlpha(entry.frame))) then
                return true
            end
        elseif FrameAlphaDiffers(entry.frame, GetFrameAlphaWithContainerMultiplier(entry.frame, entryAlpha)) then
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
    -- Cache first, so the aura reads below are skipped entirely on the common
    -- pass. Every input edge dirties the cache (player UNIT_AURA for Soar on
    -- Dracthyr, PLAYER_MOUNT_DISPLAY_CHANGED, NEW_MOUNT_ADDED, combat exit,
    -- world entry), so a clean entry for this mounted state already holds the
    -- answer. The short-circuit is deliberately limited to a cached-INACTIVE
    -- Soar: only a cached-ACTIVE Soar can read back differently without a dirty
    -- mark (the restricted-aura window documented below reads nothing for a
    -- present aura), and that state must keep re-reading so it still degrades to
    -- regular-mounted at exactly the same moment as before.
    if not self._mountAlphaDirty
       and self._mountAlphaCacheSoar == false
       and self._mountAlphaCacheMounted == (mounted == true) then
        return self._isRegularMounted == true, self._isDragonridingMounted == true
    end

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
        -- The two lookups above are the whole supported path. A full
        -- GetUnitAuras scan used to sit here as a fallback; it was removed
        -- because it could never help. It matched the same SOAR_SPELL_ID over
        -- a narrower set (player HELPFUL only), and the one documented state
        -- where the per-spell reads return nothing for a present aura is the
        -- aura being secret -- in which case the scan's own entries are secret
        -- too and its guard skips every one. It also carried
        -- RequiresUnitAuraAccess, which hard-errors without aura access, and
        -- the restriction windows are not limited to player combat (Encounter,
        -- ChallengeMode, PvPMatch and Map are separate restriction types, and
        -- no supported predicate exists to test access before calling).
        --
        -- Consequence: while auras are restricted, a Soaring Dracthyr reads as
        -- regular-mounted until the next aura change. OnCombatEnd re-dirties
        -- the cache so combat exits reclassify immediately.
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
    -- Mount display change, new mount, world entry, Soar reclassification and
    -- combat exit all land here, and every one of them can change a mounted
    -- force condition, so this is also the driver's mount re-arm hook.
    self:EnsureAlphaDriverArmed()
end

-- Re-arm hook for the condition inputs the driver polls each pass. Callers are
-- the events listed in the disarm contract above; several are hot, so an already
-- running driver costs one flag write and one script read. The flag matters on
-- its own: a settled state is settled on the conditions of the LAST pass, so
-- until a pass re-reads them, RefreshAlphaUpdateDriver must not disarm.
function CooldownCompanion:EnsureAlphaDriverArmed()
    self._alphaDriverConditionDirty = true

    local alphaFrame = self._alphaFrame
    if alphaFrame and alphaFrame:GetScript("OnUpdate") then
        return
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
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

    -- Keep unlocked panels fully visible, except unlock ghosts.
    if not locked then
        local unlockedAlpha = GetUnlockedPanelAlpha(frame)
        frame._naturalAlpha = nil
        if state.currentAlpha ~= unlockedAlpha
            or state.lastAlpha ~= unlockedAlpha
            or FrameAlphaDiffers(frame, unlockedAlpha) then
            frame:SetAlpha(unlockedAlpha)
            state.currentAlpha = unlockedAlpha
            state.desiredAlpha = unlockedAlpha
            state.fadeDuration = 0
            state.lastAlpha = unlockedAlpha
        end
        return
    end

    local layoutPreviewActive = ST.IsGroupRuntimeLayoutPreviewActive(groupId)

    -- Skip processing when feature is entirely unused (baseline=1, no forceHide toggles)
    local hasForceHide = group.forceHideInCombat or group.forceHideOutOfCombat
        or group.forceHideRegularMounted or group.forceHideDragonriding
    if group.baselineAlpha == 1 and not hasForceHide then
        if layoutPreviewActive then
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
        if layoutPreviewActive then
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

    -- The explicit cursor-layout preview stores natural alpha for downstream
    -- consumers, then forces the positioned frame itself fully visible.
    if layoutPreviewActive then
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
    local entriesByContainer = BuildContainerAlphaEntryMaps(self, groups, nil, previewEntryScratch, previewControlledGroups)
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

-- Answers "must the 30 Hz driver be RUNNING", not "is alpha configured": see the
-- disarm contract above AlphaConfigNeedsDriverPolling. Every existing reason to
-- stay armed still returns true here; the one case this narrows is a profile
-- whose alpha configs are all settled and all event-driven, which now disarms
-- until a re-arm hook fires. When in doubt, return true.
function CooldownCompanion:EvaluateAlphaDriverNeedsWork()
    local profile = self.db and self.db.profile
    if type(profile) ~= "table" then
        return false
    end

    -- A condition input flipped since the last pass, so the settled state below
    -- is settled on STALE conditions. One tick has to re-read them.
    if self._alphaDriverConditionDirty then
        return true
    end

    local probeNow = GetTime()
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
            BuildContainerAlphaEntryMaps(self, groups, panelAlphaAnchorTargets, evaluateEntryScratch, evaluateControlledGroups)
        if GroupSetHasMemberNotInCurrent(self._containerAlphaControlledGroups, containerAlphaControlledGroups) then
            return true
        end
        for containerId, container in pairs(containers) do
            local entries = entriesByContainer[containerId]
            local containerDrivesEntries = container
                and container.groupAlphaEnabled == true
                and entries
                and #entries > 0
                or false
            if containerDrivesEntries
                and ContainerAlphaNeedsUpdate(self, containerId, container, entries, probeNow) then
                return true
            end

            -- A live container driving entries owns its state: a non-1 alpha
            -- there is the applied value, not leftover work owed a cleanup pass.
            if not (containerDrivesEntries
                    and ST.HasActiveAlphaSettings
                    and ST.HasActiveAlphaSettings(container))
                and AlphaStateNeedsCleanup(self, GetContainerAlphaStateKey(containerId)) then
                return true
            end
        end
    end

    for groupId, group in pairs(groups) do
        local frame = groupFrames[groupId] or (dormantFrames and dormantFrames[groupId])
        if not containerAlphaControlledGroups[groupId]
            and FrameIsAlphaWorkTarget(frame, panelAlphaAnchorTargets and panelAlphaAnchorTargets[groupId]) then
            if GroupNeedsAlphaUpdate(self, group, groupId, frame, probeNow) then
                return true
            end
        end
    end

    if self._moduleAlphaTargets then
        for moduleId, entry in pairs(self._moduleAlphaTargets) do
            if entry and HasLiveAlphaFrames(entry.frames)
                and ConfigNeedsAlphaUpdate(self, entry.config, moduleId, probeNow) then
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

    -- Cleared before the snapshot below, so an input that flips after this line
    -- re-dirties for a further pass instead of being swallowed by this one.
    self._alphaDriverConditionDirty = nil

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
    -- Stays true only while every item this pass touched ended settled on an
    -- event-driven config: that is the one tick worth paying a full
    -- RefreshAlphaUpdateDriver evaluation for, so a settled profile can disarm.
    local passMaySettle = true
    local entriesByContainer, containerAlphaControlledGroups = EMPTY_TABLE, EMPTY_TABLE
    if NeedsContainerAlphaPass(self, containers) then
        local previousContainerAlphaGroups = self._containerAlphaControlledGroups
        -- Build into whichever set is NOT the published one, so the diff below
        -- still sees the previous pass's membership.
        local controlledGroupsTarget = (previousContainerAlphaGroups == driverControlledGroupsA)
            and driverControlledGroupsB
            or driverControlledGroupsA
        entriesByContainer, containerAlphaControlledGroups =
            BuildContainerAlphaEntryMaps(self, groups, panelAlphaAnchorTargets, driverEntryScratch, controlledGroupsTarget)

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
                    if passMaySettle
                        and not AlphaWorkMaySettle(self, container, GetContainerAlphaStateKey(containerId), now) then
                        passMaySettle = false
                    end
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
                if passMaySettle and not AlphaWorkMaySettle(self, group, groupId, now) then
                    passMaySettle = false
                end
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
                if passMaySettle and not AlphaWorkMaySettle(self, entry.config, moduleId, now) then
                    passMaySettle = false
                end
            end
        end
    end
    if needsPostPassRefresh or not processedAlphaWork or passMaySettle then
        self:RefreshAlphaUpdateDriver(true)
    end
end

-- fromAlphaPass marks the alpha pass's own tail, the ONLY place allowed to stop
-- the driver: it decides from conditions the same pass just re-read. Every other
-- caller is announcing that something the pass reads has changed — lock state,
-- panel or container lifecycle, anchor dependencies, config edits — and most of
-- those inputs are invisible to the settled test in EvaluateAlphaDriverNeedsWork
-- (a settled state is only settled on the LAST pass's conditions). So an
-- external refresh always arms and lets the pass re-decide, which is also
-- cheaper than the evaluation walk it used to run.
function CooldownCompanion:RefreshAlphaUpdateDriver(fromAlphaPass)
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

    local needsWork
    if fromAlphaPass then
        needsWork = self:EvaluateAlphaDriverNeedsWork()
    else
        self._alphaDriverConditionDirty = true
        needsWork = true
    end

    local handler = self._alphaUpdateHandler
    if needsWork then
        if not alphaFrame:GetScript("OnUpdate") then
            -- Arming from stopped: hand the next frame a full interval so the
            -- pass runs immediately instead of spending one re-accumulating.
            -- A re-armed condition flip must never land later than the
            -- always-running driver would have applied it.
            self._alphaUpdateAccumulator = self._alphaUpdateInterval or (1 / 30)
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
