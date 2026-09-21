-- Config-only command state. Renderers own their frames and animations; this
-- owner holds the one playing command, its targets and its sample clock.
-- Base-loaded so teardown and module queries work before the config addon loads.
local _, ST = ...
local Addon = ST.Addon
local Preview = {}
ST._ConfigPreview = Preview
local session, totemResume
local EMPTY_EFFECTS = {}

local function MarkVisualsChanged()
    if ST._configState then ST._configState.panelPreviewVisualsNeedReconcile = true end
end

local function OwnerIsCurrent(value)
    local profile = Addon.db and Addon.db.profile
    return value and value.profile == profile
        and (not value.groupId or (profile.groups and profile.groups[value.groupId] == value.group))
        and (not value.buttonIndex or not value.targets
            or value.group.buttons[value.buttonIndex] == value.targets[value.buttonIndex])
end

function Preview.Get()
    return OwnerIsCurrent(session) and session or nil
end

function Preview.IsCurrent(value)
    return value ~= nil and Preview.Get() == value
end

local function MatchesTarget(value, groupId, buttonIndex)
    if not value or value.groupId ~= groupId then return false end
    if not value.targets then return true end
    if buttonIndex then
        return value.targets[buttonIndex] ~= nil
            and value.group.buttons[buttonIndex] == value.targets[buttonIndex]
    end
    for index, entry in pairs(value.targets) do
        if value.group.buttons[index] == entry then return true end
    end
    return false
end

function Preview.IsCommand(command, groupId, buttonIndex)
    local value = Preview.Get()
    return value ~= nil and value.command.id == command.id
        and (value.command.object ~= nil or MatchesTarget(value, groupId, buttonIndex))
end

function Preview.GetSample(owner, groupId)
    local value = Preview.Get()
    return value and value.command.preview.owner == owner
        and (not groupId or value.groupId == groupId) and value.sample or nil
end

function Preview.GetTotemSample(groupId)
    local sample = Preview.GetSample("totem", groupId)
    if sample then return sample end
    return OwnerIsCurrent(totemResume) and totemResume.groupId == groupId and totemResume.sample or nil
end

function Preview.Stop()
    local previous = session
    if not previous then return end
    session = nil
    MarkVisualsChanged()
    local visual = previous.command.preview
    if visual.owner == "totem" then
        local sample = previous.sample
        totemResume = { profile = previous.profile, groupId = previous.groupId, group = previous.group,
            sample = { elapsed = (sample.elapsed + GetTime() - sample.startedAt) % sample.duration } }
        if ST._RefreshTotemPreviewPlayback then ST._RefreshTotemPreviewPlayback(previous.groupId) end
    elseif visual.textureIndicator and ST._StopTextureIndicatorPreviewMirror then
        ST._StopTextureIndicatorPreviewMirror(previous.groupId)
    elseif visual.triggerEffects and ST._StopTriggerPanelEffectsPreviewMirror then
        ST._StopTriggerPanelEffectsPreviewMirror(previous.groupId)
    end
end

function Preview.StopOwner(owner)
    if session and session.command.preview.owner == owner then Preview.Stop() end
end

-- Settings cancellation names the command, so a composite's effect and
-- duration always disappear together.
function Preview.StopCommand(commandId, groupId)
    local value = Preview.Get()
    if value and value.command.id == commandId
        and (not groupId or value.groupId == groupId) then Preview.Stop() end
end

-- Recompute targets at selection/committed-config boundaries, without restarting
-- the sample. Entry references prevent replacement data inheriting old indexes.
function Preview.Retarget(buttonIndex, targets)
    local value = Preview.Get()
    if not value then Preview.Stop(); return end
    if targets and not next(targets) then Preview.Stop(); return end
    local changed = value.buttonIndex ~= buttonIndex or (value.targets == nil) ~= (targets == nil)
    if not changed and targets then
        for index, entry in pairs(targets) do
            if value.targets[index] ~= entry then changed = true; break end
        end
        if not changed then
            for index, entry in pairs(value.targets) do
                if targets[index] ~= entry then changed = true; break end
            end
        end
    end
    if changed then
        value.buttonIndex, value.targets = buttonIndex, targets
        MarkVisualsChanged()
    end
end

-- Only a gear route for this exact running object may move its canvas owner.
function Preview.MoveHost(value, panelId)
    if Preview.IsCurrent(value) and value.command.object then value.hostPanelId = panelId end
end

local CONDITIONAL_VISUAL_PREVIEW_DEFAULTS = {
    aura_missing = { kind = "aura_missing", auraActive = false },
    cooldown = { kind = "cooldown", duration = 12, remaining = 8, loop = true },
    -- The icons/bars split of the cooldown state (owner ruling 2026-08-08):
    -- _text renders the countdown text alone on an otherwise resting button;
    -- _swipe renders everything else the state carries (swipe or icon fill,
    -- desaturation, cooldown tint) with the countdown numbers suppressed.
    -- Text and rotation assistant panels still run the plain "cooldown" kind.
    cooldown_text = { kind = "cooldown_text", duration = 12, remaining = 8, loop = true },
    cooldown_swipe = { kind = "cooldown_swipe", duration = 12, remaining = 8, loop = true },
    charge_full = { kind = "charge_full" },
    charge_missing = { kind = "charge_missing" },
    charge_zero = { kind = "charge_zero" },
    unusable = { kind = "unusable" },
    out_of_range = { kind = "out_of_range" },
    -- 12.1 aura previews render CC-side stand-ins from the same style keys
    -- the slot kit consumes; they never touch the aura slot subtree.
    aura_duration_text = { kind = "aura_duration_text", duration = 12, remaining = 8, loop = true },
    -- The marker rides the duration text, so this renders the same stand-in
    -- and only differs in dressing it. The loop is deliberately shorter than
    -- the plain text one: the marker appears below 30% of `duration` (3.6s
    -- here), so a 5s sweep spends most of itself inside the window while
    -- still crossing the threshold each cycle, which is what the setting
    -- actually does. An 8s sweep would leave it blank over half the time.
    pandemic_marker = { kind = "pandemic_marker", duration = 12, remaining = 5, loop = true },
    aura_duration_bar = { kind = "aura_duration_bar", duration = 12, remaining = 8, loop = true },
    aura_stack_text = { kind = "aura_stack_text", stackText = "3" },
    aura_duration_swipe = { kind = "aura_duration_swipe", duration = 12, remaining = 8, loop = true },
    loss_of_control = { kind = "loss_of_control", duration = 12, remaining = 8, loop = true },
}

local function BuildConditionalVisualPreviewState(previewKind)
    local base = CONDITIONAL_VISUAL_PREVIEW_DEFAULTS[previewKind] or CONDITIONAL_VISUAL_PREVIEW_DEFAULTS.cooldown
    local state = {}
    for key, value in pairs(base) do
        state[key] = value
    end

    local duration = tonumber(state.duration)
    local remaining = tonumber(state.remaining)
    local now = GetTime()
    state.startedAt = now
    if duration and duration > 0 then
        if not remaining or remaining <= 0 or remaining > duration then
            remaining = duration
        end
        state.duration = duration
        state.remaining = remaining
        state.startTime = now - (duration - remaining)
        if state.loop == true then
            state.loopDuration = remaining
            state.loopStartTime = now
        end
    end
    return state
end

-- Shared timing contract for the config mirror's animated stand-ins.
function ST._GetConditionalPreviewTiming(preview, now)
    local duration = tonumber(preview and preview.duration)
    local startTime = tonumber(preview and preview.startTime)
    if not duration or duration <= 0 then
        return nil, nil, nil
    end
    if not startTime then
        startTime = now
    end

    local loopDuration = tonumber(preview and preview.loopDuration)
    local loopStartTime = tonumber(preview and preview.loopStartTime)
    if preview and preview.loop == true and loopDuration and loopDuration > 0 then
        if loopDuration > duration then
            loopDuration = duration
        end
        if not loopStartTime then
            loopStartTime = startTime + (duration - loopDuration)
        end
        local elapsed = now - loopStartTime
        if elapsed < 0 then
            elapsed = 0
        end
        local cycleElapsed = elapsed % loopDuration
        local remaining = loopDuration - cycleElapsed
        if remaining > duration then
            remaining = duration
        end
        startTime = now - (duration - remaining)
        return startTime, duration, remaining, loopStartTime, loopDuration
    end

    local remaining = duration - (now - startTime)
    if remaining < 0 then
        remaining = 0
    end
    return startTime, duration, remaining
end

function Preview.Start(command, panelId, buttonIndex, targets)
    local profile = Addon.db and Addon.db.profile
    local groupId = not command.object and panelId or nil
    local group = groupId and profile and profile.groups[groupId]
    if not profile or (not command.object and not group) or (targets and not next(targets)) then return false end
    Addon:ClearAllConfigPreviews()
    local visual = command.preview
    local sample = visual.conditional and BuildConditionalVisualPreviewState(visual.conditional)
        or { startedAt = GetTime() }
    if visual.owner == "totem" then
        local resume = Preview.GetTotemSample(groupId)
        sample.elapsed, sample.duration = resume and resume.elapsed or visual.initialElapsed, visual.duration
    end
    session = { command = command, profile = profile, groupId = groupId, group = group,
        hostPanelId = panelId, buttonIndex = buttonIndex, targets = targets, sample = sample }
    if visual.healthEffect then session.healthEffects = { [visual.healthEffect] = true } end
    MarkVisualsChanged()
    if visual.owner == "totem" and ST._RefreshTotemPreviewPlayback then
        ST._RefreshTotemPreviewPlayback(groupId)
    end
    return true
end

local function IsStoredPreviewFlagActive(groupId, buttonIndex, flag)
    local value = Preview.Get()
    return value ~= nil and flag ~= nil and value.command.preview.flag == flag
        and MatchesTarget(value, groupId, buttonIndex)
end
ST._IsStoredPreviewFlagActive = IsStoredPreviewFlagActive

function Addon:IsPreviewFlagActive(groupId, buttonIndex, flag)
    return IsStoredPreviewFlagActive(groupId, buttonIndex, flag)
end

function ST._GetStoredConditionalPreviewState(groupId, buttonIndex)
    local value = Preview.Get()
    return value and value.command.preview.conditional and MatchesTarget(value, groupId, buttonIndex)
        and value.sample or nil
end

function Addon:IsConditionalVisualPreviewActive(groupId, buttonIndex, kind)
    local sample = ST._GetStoredConditionalPreviewState(groupId, buttonIndex)
    return sample ~= nil and sample.kind == kind
end

function Addon:IsGroupTextureIndicatorPreviewActive(groupId, key)
    local value = Preview.Get()
    return value ~= nil and value.groupId == groupId and value.command.preview.textureIndicator == key
end

function Addon:IsTriggerPanelEffectsPreviewActive(groupId)
    local value = Preview.Get()
    return value ~= nil and value.groupId == groupId and value.command.preview.triggerEffects == true
end

function Preview.GetHealthEffects()
    local value = Preview.Get()
    return value and value.healthEffects or EMPTY_EFFECTS
end

function Addon:ClearAllConfigPreviews(keepSession)
    if not Preview.IsCurrent(keepSession) then Preview.Stop() end
    -- Cursor positioning has a separate lifetime. Preserve its existing cleanup
    -- (including explicit unlock/Arrange retention) at broad clear boundaries.
    if self.ClearCursorAnchorLayoutPreview then self:ClearCursorAnchorLayoutPreview() end
end
