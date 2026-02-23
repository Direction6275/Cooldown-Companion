--[[
    CooldownCompanion - Core/AlphaFade.lua: Alpha fade system — per-group smooth visibility transitions
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsMounted = IsMounted
local UnitExists = UnitExists
local GetShapeshiftForm = GetShapeshiftForm
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local pairs = pairs

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

function CooldownCompanion:UpdateGroupAlpha(groupId, group, frame, now, inCombat, hasTarget, mounted, inTravelForm)
    local state = self.alphaState[groupId]
    if not state then
        state = {}
        self.alphaState[groupId] = state
    end

    -- Force 100% alpha while group is unlocked for easier positioning
    if not group.locked then
        if state.currentAlpha ~= 1 or state.lastAlpha ~= 1 then
            frame:SetAlpha(1)
            state.currentAlpha = 1
            state.desiredAlpha = 1
            state.fadeDuration = 0
            state.lastAlpha = 1
        end
        return
    end

    -- Skip processing when feature is entirely unused (baseline=1, no forceHide toggles)
    local hasForceHide = group.forceHideInCombat or group.forceHideOutOfCombat
        or group.forceHideMounted
    if group.baselineAlpha == 1 and not hasForceHide then
        -- Reset state so it doesn't carry stale values if settings change later
        if state.currentAlpha and state.currentAlpha ~= 1 then
            frame:SetAlpha(1)
            state.currentAlpha = 1
            state.desiredAlpha = 1
            state.fadeDuration = 0
        end
        return
    end

    -- Effective mounted state: real mount OR travel form (if opted in)
    local effectiveMounted = mounted or (group.treatTravelFormAsMounted and inTravelForm)

    -- Check force-hidden conditions
    local forceHidden = false
    if group.forceHideInCombat and inCombat then
        forceHidden = true
    elseif group.forceHideOutOfCombat and not inCombat then
        forceHidden = true
    elseif group.forceHideMounted and effectiveMounted then
        forceHidden = true
    end

    -- Check force-visible conditions (priority: visible > hidden > baseline)
    local forceFull = false
    if group.forceAlphaInCombat and inCombat then
        forceFull = true
    elseif group.forceAlphaOutOfCombat and not inCombat then
        forceFull = true
    elseif group.forceAlphaMounted and effectiveMounted then
        forceFull = true
    elseif group.forceAlphaTargetExists and hasTarget then
        forceFull = true
    end

    -- Mouseover check (geometric, works even when click-through)
    if not forceFull and group.forceAlphaMouseover then
        local isHovering = frame:IsMouseOver()
        if isHovering then
            forceFull = true
            state.hoverExpire = now + (group.customFade and group.fadeDelay or 1)
        elseif state.hoverExpire and now < state.hoverExpire then
            forceFull = true
        end
    end

    local desired = forceFull and 1 or (forceHidden and 0 or group.baselineAlpha)
    local fadeIn = group.customFade and group.fadeInDuration or 0.2
    local fadeOut = group.customFade and group.fadeOutDuration or 0.2
    local alpha = UpdateFadedAlpha(state, desired, now, fadeIn, fadeOut)

    -- Only call SetAlpha when value actually changes
    if state.lastAlpha ~= alpha then
        frame:SetAlpha(alpha)
        state.lastAlpha = alpha
    end

end

function CooldownCompanion:InitAlphaUpdateFrame()
    if self._alphaFrame then return end

    local alphaFrame = CreateFrame("Frame")
    self._alphaFrame = alphaFrame
    local accumulator = 0
    local UPDATE_INTERVAL = 1 / 30 -- ~30Hz for smooth fading

    local function GroupNeedsAlphaUpdate(group)
        if group.baselineAlpha < 1 then return true end
        return group.forceHideInCombat or group.forceHideOutOfCombat
            or group.forceHideMounted
    end

    alphaFrame:SetScript("OnUpdate", function(_, dt)
        accumulator = accumulator + (dt or 0)
        if accumulator < UPDATE_INTERVAL then return end
        accumulator = 0

        local now = GetTime()
        local inCombat = InCombatLockdown()
        local hasTarget = UnitExists("target")
        local mounted = IsMounted()

        local inTravelForm = false
        if self._playerClassID == 11 then -- Druid
            local fi = GetShapeshiftForm()
            if fi and fi > 0 then
                local _, _, _, spellID = GetShapeshiftFormInfo(fi)
                if spellID == 783 then inTravelForm = true end
            end
        end

        for groupId, group in pairs(self.db.profile.groups) do
            local frame = self.groupFrames[groupId]
            if frame and frame:IsShown() then
                local needsUpdate = GroupNeedsAlphaUpdate(group)
                -- Also process if the group has stale alpha state that needs cleanup
                if not needsUpdate then
                    local state = self.alphaState[groupId]
                    if state and state.currentAlpha and state.currentAlpha ~= 1 then
                        needsUpdate = true
                    end
                end
                if needsUpdate then
                    self:UpdateGroupAlpha(groupId, group, frame, now, inCombat, hasTarget, mounted, inTravelForm)
                end
            end
        end
    end)
end
