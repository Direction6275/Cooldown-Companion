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
local function EvaluateDesiredAlpha(config, inCombat, hasTarget, hasEnemyTarget, regularMounted, dragonridingMounted, inTravelForm)
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
    end

    return forceFull, forceHidden, config.baselineAlpha or 1
end

function CooldownCompanion:UpdateGroupAlpha(groupId, group, locked, frame, now, inCombat, hasTarget, hasEnemyTarget, regularMounted, dragonridingMounted, inTravelForm)
    local state = self.alphaState[groupId]
    if not state then
        state = {}
        self.alphaState[groupId] = state
    end

    -- Force 100% alpha while group is unlocked for easier positioning
    if not locked then
        frame._naturalAlpha = nil
        if state.currentAlpha ~= 1 or state.lastAlpha ~= 1 then
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
        if state.currentAlpha and state.currentAlpha ~= 1 then
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

    local forceFull, forceHidden, baseline = EvaluateDesiredAlpha(group, inCombat, hasTarget, hasEnemyTarget, regularMounted, dragonridingMounted, inTravelForm)

    -- Mouseover check (geometric, works even when click-through)
    if not forceFull and group.forceAlphaMouseover then
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
        if state.lastAlpha ~= 1 then
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

    if state.lastAlpha ~= alpha then
        frame:SetAlpha(alpha)
        state.lastAlpha = alpha
    end
end

-- Module alpha: evaluates alpha for non-group frames (resource bars, cast bar).
-- moduleId: unique string key (e.g., "rb", "cb")
-- config: table with the same alpha fields as group (baselineAlpha, forceAlpha*, etc.)
-- frames: list of frames to apply alpha to
function CooldownCompanion:UpdateModuleAlpha(moduleId, config, frames, now, inCombat, hasTarget, hasEnemyTarget, regularMounted, dragonridingMounted, inTravelForm)
    local state = self.alphaState[moduleId]
    if not state then
        state = {}
        self.alphaState[moduleId] = state
    end

    local forceFull, forceHidden, baseline = EvaluateDesiredAlpha(config, inCombat, hasTarget, hasEnemyTarget, regularMounted, dragonridingMounted, inTravelForm)

    -- Mouseover check across all frames
    if not forceFull and config.forceAlphaMouseover then
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
    self._moduleAlphaTargets[moduleId] = { config = config, frames = frames }
end

function CooldownCompanion:UnregisterModuleAlpha(moduleId, preserveState)
    if self._moduleAlphaTargets then
        self._moduleAlphaTargets[moduleId] = nil
    end
    if not preserveState and self.alphaState then
        self.alphaState[moduleId] = nil
    end
end

function CooldownCompanion:InitAlphaUpdateFrame()
    if self._alphaFrame then return end

    local alphaFrame = CreateFrame("Frame")
    self._alphaFrame = alphaFrame
    local accumulator = 0
    local UPDATE_INTERVAL = 1 / 30 -- ~30Hz for smooth fading

    local function ConfigNeedsAlphaUpdate(config, stateKey)
        if (config.baselineAlpha or 1) < 1 then return true end
        if config.forceAlphaInCombat or config.forceAlphaOutOfCombat
            or config.forceAlphaRegularMounted or config.forceAlphaDragonriding
            or config.forceAlphaTargetExists or config.forceAlphaMouseover then
            return true
        end
        if config.forceHideInCombat or config.forceHideOutOfCombat
            or config.forceHideRegularMounted or config.forceHideDragonriding then
            return true
        end
        -- Check for stale alpha state that needs cleanup
        local state = self.alphaState[stateKey]
        if state and state.currentAlpha and state.currentAlpha ~= 1 then
            return true
        end
        return false
    end

    local function GroupNeedsAlphaUpdate(group, groupId)
        if ST.IsGroupConfigSelected(groupId) then return true end
        return ConfigNeedsAlphaUpdate(group, groupId)
    end

    alphaFrame:SetScript("OnUpdate", function(_, dt)
        accumulator = accumulator + (dt or 0)
        if accumulator < UPDATE_INTERVAL then return end
        accumulator = 0

        local now = GetTime()
        local inCombat = InCombatLockdown()
        local hasTarget = UnitExists("target")
        local hasEnemyTarget = hasTarget and UnitCanAttack("player", "target") and true or false
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
        for groupId, group in pairs(self.db.profile.groups) do
            local frame = self.groupFrames[groupId]
            if frame and frame:IsShown() then
                if GroupNeedsAlphaUpdate(group, groupId) then
                    local locked = true
                    if group.parentContainerId then
                        local c = containers[group.parentContainerId]
                        if c then locked = c.locked ~= false end
                    else
                        locked = group.locked
                    end
                    self:UpdateGroupAlpha(groupId, group, locked, frame, now, inCombat, hasTarget, hasEnemyTarget, regularMounted, dragonridingMounted, inTravelForm)
                end
            end
        end

        -- Process registered module alpha targets (resource bars, custom aura bars, texture panels)
        if self._moduleAlphaTargets then
            for moduleId, entry in pairs(self._moduleAlphaTargets) do
                if ConfigNeedsAlphaUpdate(entry.config, moduleId) then
                    self:UpdateModuleAlpha(moduleId, entry.config, entry.frames, now, inCombat, hasTarget, hasEnemyTarget, regularMounted, dragonridingMounted, inTravelForm)
                end
            end
        end
    end)
end
