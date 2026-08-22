--[[
    CooldownCompanion - ButtonFrame/Preview
    Config panel preview methods for proc glow, aura glow, bar aura effect,
    bar aura active, bar pulse, bar color shift, pandemic, ready glow, and
    key press highlight.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local wipe = wipe
local GetTime = GetTime

local activeGroupPreviewFlags = {}
local activeButtonPreviewFlags = {}
local activeTriggerPanelEffectPreviews = {}
local activeConditionalGroupPreviews = {}
local activeConditionalButtonPreviews = {}

--------------------------------------------------------------------------------
-- Shared Helpers
--------------------------------------------------------------------------------

local function CopyPreviewState(state)
    if not state then
        return nil
    end
    local copy = {}
    for key, value in pairs(state) do
        copy[key] = value
    end
    return copy
end

local function SetActiveGroupPreviewFlag(groupId, previewFlag, show)
    if not (groupId and previewFlag) then return end
    local groupFlags = activeGroupPreviewFlags[groupId]
    if show then
        if not groupFlags then
            groupFlags = {}
            activeGroupPreviewFlags[groupId] = groupFlags
        end
        groupFlags[previewFlag] = true
    elseif groupFlags then
        groupFlags[previewFlag] = nil
        if not next(groupFlags) then
            activeGroupPreviewFlags[groupId] = nil
        end
    end
end

local function SetActiveButtonPreviewFlag(groupId, buttonIndex, previewFlag, show)
    if not (groupId and buttonIndex and previewFlag) then return end
    local groupButtons = activeButtonPreviewFlags[groupId]
    local buttonFlags = groupButtons and groupButtons[buttonIndex]
    if show then
        if not groupButtons then
            groupButtons = {}
            activeButtonPreviewFlags[groupId] = groupButtons
        end
        if not buttonFlags then
            buttonFlags = {}
            groupButtons[buttonIndex] = buttonFlags
        end
        buttonFlags[previewFlag] = true
    elseif buttonFlags then
        buttonFlags[previewFlag] = nil
        if not next(buttonFlags) then
            groupButtons[buttonIndex] = nil
            if not next(groupButtons) then
                activeButtonPreviewFlags[groupId] = nil
            end
        end
    end
end

local function ClearActiveButtonPreviewFlagForGroup(groupId, previewFlag)
    local groupButtons = activeButtonPreviewFlags[groupId]
    if not (groupButtons and previewFlag) then return end
    for buttonIndex, buttonFlags in pairs(groupButtons) do
        buttonFlags[previewFlag] = nil
        if not next(buttonFlags) then
            groupButtons[buttonIndex] = nil
        end
    end
    if not next(groupButtons) then
        activeButtonPreviewFlags[groupId] = nil
    end
end

local function ClearActivePreviewFlag(previewFlag)
    for groupId in pairs(activeGroupPreviewFlags) do
        SetActiveGroupPreviewFlag(groupId, previewFlag, false)
    end
    for groupId in pairs(activeButtonPreviewFlags) do
        ClearActiveButtonPreviewFlagForGroup(groupId, previewFlag)
    end
end

local function IsActivePreviewFlagStored(groupId, buttonIndex, previewFlag)
    if not (groupId and previewFlag) then
        return false
    end
    local groupFlags = activeGroupPreviewFlags[groupId]
    if groupFlags and groupFlags[previewFlag] then
        return true
    end
    local groupButtons = activeButtonPreviewFlags[groupId]
    if not groupButtons then
        return false
    end
    if buttonIndex then
        local buttonFlags = groupButtons[buttonIndex]
        return buttonFlags and buttonFlags[previewFlag] == true or false
    end
    for _, buttonFlags in pairs(groupButtons) do
        if buttonFlags[previewFlag] then
            return true
        end
    end
    return false
end

-- Stored-only mirror seam. Unlike IsPreviewFlagActive, this never falls
-- through to live button fields, so config mirrors remain independent of
-- runtime activity.
ST._IsStoredPreviewFlagActive = IsActivePreviewFlagStored

-- Config previews are state for the pinned mirror only. They never write to,
-- repaint, or enroll live runtime buttons.
local function SetButtonPreview(self, groupId, buttonIndex, show, previewFlag)
    SetActiveButtonPreviewFlag(groupId, buttonIndex, previewFlag, show)
end

local function SetGroupPreview(self, groupId, show, previewFlag)
    SetActiveGroupPreviewFlag(groupId, previewFlag, show)
    ClearActiveButtonPreviewFlagForGroup(groupId, previewFlag)
end

local function ClearAllPreviews(self, previewFlag)
    ClearActivePreviewFlag(previewFlag)
end

local CONDITIONAL_VISUAL_PREVIEW_DEFAULTS = {
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

local function BuildConditionalVisualPreviewState(previewKind, sampleState)
    local base = CONDITIONAL_VISUAL_PREVIEW_DEFAULTS[previewKind] or CONDITIONAL_VISUAL_PREVIEW_DEFAULTS.cooldown
    local state = {}
    for key, value in pairs(base) do
        state[key] = value
    end
    if sampleState then
        for key, value in pairs(sampleState) do
            state[key] = value
        end
    end

    local duration = tonumber(state.duration)
    local remaining = tonumber(state.remaining)
    local now = GetTime()
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

-- Shared timing contract for the config mirror's animated stand-ins. Exported
-- directly to avoid consuming another Lua 5.1 file-local in this large module.
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

-- Stored conditional-preview state for (group, button): the per-button
-- entry wins, else the group-wide entry (the setters keep the two
-- mutually exclusive per group). Read by the config mirror, which renders
-- CC-side stand-ins from the same state.
local function GetStoredConditionalPreviewState(groupId, buttonIndex)
    if not groupId then
        return nil
    end
    local groupButtons = activeConditionalButtonPreviews[groupId]
    local buttonState = groupButtons and buttonIndex and groupButtons[buttonIndex] or nil
    return buttonState or activeConditionalGroupPreviews[groupId]
end

ST._GetStoredConditionalPreviewState = GetStoredConditionalPreviewState

function CooldownCompanion:IsPreviewFlagActive(groupId, buttonIndex, previewFlag)
    return previewFlag ~= nil
        and IsActivePreviewFlagStored(groupId, buttonIndex, previewFlag)
        or false
end

--- Entry-scoped ONLY: true when this exact button carries its own conditional
--- preview of `previewKind`. The general query below deliberately answers true
--- for a panel-wide preview too, which is right for the chooser but wrong for
--- a per-entry setting deciding whether to cancel something — passing a
--- buttonIndex to SetConditionalVisualPreviewActive clears the panel-wide
--- preview as a side effect of the entry/panel exclusivity rule, so one entry
--- opting out would silently stop a preview covering the whole panel.
function CooldownCompanion:IsButtonConditionalVisualPreviewActive(groupId, buttonIndex, previewKind)
    if not (groupId and buttonIndex) then
        return false
    end
    local groupButtons = activeConditionalButtonPreviews[groupId]
    local buttonState = groupButtons and groupButtons[buttonIndex]
    return (buttonState and buttonState.kind == previewKind) and true or false
end

function CooldownCompanion:IsConditionalVisualPreviewActive(groupId, buttonIndex, previewKind)
    local groupState = activeConditionalGroupPreviews[groupId]
    if groupState and groupState.kind == previewKind then
        return true
    end
    local groupButtons = activeConditionalButtonPreviews[groupId]
    if groupButtons then
        if buttonIndex then
            local buttonState = groupButtons[buttonIndex]
            return buttonState and buttonState.kind == previewKind or false
        end
        for _, buttonState in pairs(groupButtons) do
            if buttonState and buttonState.kind == previewKind then
                return true
            end
        end
    end
    return false
end

function CooldownCompanion:SetConditionalVisualPreviewActive(groupId, buttonIndex, previewKind, show, sampleState)
    if not groupId then
        return
    end

    local state = show and BuildConditionalVisualPreviewState(previewKind, sampleState) or nil
    if buttonIndex then
        activeConditionalGroupPreviews[groupId] = nil
        if state then
            if not activeConditionalButtonPreviews[groupId] then
                activeConditionalButtonPreviews[groupId] = {}
            end
            activeConditionalButtonPreviews[groupId][buttonIndex] = CopyPreviewState(state)
        elseif activeConditionalButtonPreviews[groupId] then
            activeConditionalButtonPreviews[groupId][buttonIndex] = nil
            if not next(activeConditionalButtonPreviews[groupId]) then
                activeConditionalButtonPreviews[groupId] = nil
            end
        end
        return
    end

    activeConditionalButtonPreviews[groupId] = nil
    activeConditionalGroupPreviews[groupId] = CopyPreviewState(state)
end

function CooldownCompanion:ClearAllConditionalVisualPreviews()
    wipe(activeConditionalGroupPreviews)
    wipe(activeConditionalButtonPreviews)
end

--------------------------------------------------------------------------------
-- Proc Glow Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetProcGlowPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_procGlowPreview")
end

function CooldownCompanion:SetGroupProcGlowPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_procGlowPreview")
end

function CooldownCompanion:ClearAllProcGlowPreviews()
    ClearAllPreviews(self, "_procGlowPreview")
end

--------------------------------------------------------------------------------
-- Aura Glow Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetAuraGlowPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_auraGlowPreview")
end

function CooldownCompanion:SetGroupAuraGlowPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_auraGlowPreview")
end

function CooldownCompanion:ClearAllAuraGlowPreviews()
    ClearAllPreviews(self, "_auraGlowPreview")
end

--------------------------------------------------------------------------------
-- Missing Aura Preview
-- The absent-state presentation as one preview (owner ruling 2026-08-20):
-- ONE flag shows every configured missing-aura effect together — the missing
-- tint and the missing glow — and the mirror shows none of them at rest.
-- Rendered CC-side from the same style keys the live paths consume, without
-- touching live buttons.
--------------------------------------------------------------------------------

function CooldownCompanion:SetMissingAuraPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_missingAuraPreview")
end

function CooldownCompanion:SetGroupMissingAuraPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_missingAuraPreview")
end

function CooldownCompanion:ClearAllMissingAuraPreviews()
    ClearAllPreviews(self, "_missingAuraPreview")
end

--------------------------------------------------------------------------------
-- Pandemic Preview (PTR 8 visuals)
-- The config mirror renders icon and bar replicas from the same pandemic
-- style keys the live kit consumes, without touching live buttons or the
-- aura slot subtree.
--------------------------------------------------------------------------------

function CooldownCompanion:SetPandemicPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_pandemicPreview")
end

function CooldownCompanion:SetGroupPandemicPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_pandemicPreview")
end

-- Bar variants: same flag, plus the fake aura drain the barActiveAura
-- preview stages — the mirror's pandemic recolor rides the drained fill, so
-- without the conditional there would be nothing to recolor. Live bar
-- buttons render nothing from the flag (kit-fill-only feature).
--
-- The "aura_duration_bar" conditional store is SHARED with the barActiveAura
-- preview, so a clear may only touch it while this preview's own flag holds
-- it — reconciliation clears fire on every Effects-tab rebuild, and an
-- unconditional wipe here would kill a running barActiveAura drain while its
-- flag still reports the preview as playing (same gate on its setters).
-- The gate protects only the not-holding case; both-flags-at-once never
-- happens because the preview command center is globally mutually exclusive
-- (ClearAllConfigPreviews on every start). A future preview starter that
-- bypasses the command center must preserve that exclusivity.
function CooldownCompanion:SetBarPandemicPreview(groupId, buttonIndex, show)
    if show or self:IsPreviewFlagActive(groupId, buttonIndex, "_pandemicPreview") then
        self:SetConditionalVisualPreviewActive(groupId, buttonIndex, "aura_duration_bar", show)
    end
    SetButtonPreview(self, groupId, buttonIndex, show, "_pandemicPreview")
end

function CooldownCompanion:SetGroupBarPandemicPreview(groupId, show)
    if show or self:IsPreviewFlagActive(groupId, nil, "_pandemicPreview") then
        self:SetConditionalVisualPreviewActive(groupId, nil, "aura_duration_bar", show)
    end
    SetGroupPreview(self, groupId, show, "_pandemicPreview")
end

function CooldownCompanion:ClearAllPandemicPreviews()
    ClearAllPreviews(self, "_pandemicPreview")
end

--------------------------------------------------------------------------------
-- Bar Aura Effect Preview (barActiveAura)
--------------------------------------------------------------------------------

-- Same shared-conditional ownership rule as the bar pandemic setters below:
-- a clear may only wipe the "aura_duration_bar" store while this preview's
-- own flag holds it, or the sections' rebuild-time reconciliation clears
-- kill each other's running drain.
function CooldownCompanion:SetBarAuraEffectPreview(groupId, buttonIndex, show)
    if show or self:IsPreviewFlagActive(groupId, buttonIndex, "_barAuraEffectPreview") then
        self:SetConditionalVisualPreviewActive(groupId, buttonIndex, "aura_duration_bar", show)
    end
    SetButtonPreview(self, groupId, buttonIndex, show, "_barAuraEffectPreview")
end

function CooldownCompanion:SetGroupBarAuraEffectPreview(groupId, show)
    if show or self:IsPreviewFlagActive(groupId, nil, "_barAuraEffectPreview") then
        self:SetConditionalVisualPreviewActive(groupId, nil, "aura_duration_bar", show)
    end
    SetGroupPreview(self, groupId, show, "_barAuraEffectPreview")
end

-- The fake drain is cleared by ClearAllConditionalVisualPreviews; every
-- caller of this (ClearAllConfigPreviews) runs both.
function CooldownCompanion:ClearAllBarAuraEffectPreviews()
    ClearAllPreviews(self, "_barAuraEffectPreview")
end

--------------------------------------------------------------------------------
-- Ready Glow Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetReadyGlowPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_readyGlowPreview")
end

function CooldownCompanion:SetGroupReadyGlowPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_readyGlowPreview")
end

function CooldownCompanion:ClearAllReadyGlowPreviews()
    ClearAllPreviews(self, "_readyGlowPreview")
end

--------------------------------------------------------------------------------
-- Key Press Highlight Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetGroupKeyPressHighlightPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_keyPressHighlightPreview")
end

function CooldownCompanion:ClearAllKeyPressHighlightPreviews()
    ClearAllPreviews(self, "_keyPressHighlightPreview")
end

--------------------------------------------------------------------------------
-- Texture Indicator Previews
--------------------------------------------------------------------------------

local TEXTURE_INDICATOR_PREVIEW_FLAGS = {
    proc = "_textureProcPreview",
    aura = "_textureAuraPreview",
    ready = "_textureReadyPreview",
    unusable = "_textureUnusablePreview",
}

function CooldownCompanion:SetGroupTextureIndicatorPreview(groupId, indicatorKey, show)
    local previewFlag = TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey]
    if not previewFlag then
        return
    end

    -- Texture effects are config-mirror state even while the mirror is hidden.
    SetActiveGroupPreviewFlag(groupId, previewFlag, show)
    ClearActiveButtonPreviewFlagForGroup(groupId, previewFlag)
end

function CooldownCompanion:IsGroupTextureIndicatorPreviewActive(groupId, indicatorKey)
    local previewFlag = TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey]
    return previewFlag and IsActivePreviewFlagStored(groupId, nil, previewFlag) or false
end

function CooldownCompanion:ClearAllTextureIndicatorPreviews()
    local hadPreview = false
    for indicatorKey in pairs(TEXTURE_INDICATOR_PREVIEW_FLAGS) do
        local previewFlag = TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey]
        for groupId in pairs(activeGroupPreviewFlags) do
            if IsActivePreviewFlagStored(groupId, nil, previewFlag) then
                hadPreview = true
                break
            end
        end
        if not hadPreview then
            for groupId in pairs(activeButtonPreviewFlags) do
                if IsActivePreviewFlagStored(groupId, nil, previewFlag) then
                    hadPreview = true
                    break
                end
            end
        end
        ClearActivePreviewFlag(previewFlag)
    end

    if hadPreview and ST._StopTextureIndicatorPreviewMirror then
        ST._StopTextureIndicatorPreviewMirror()
    end
end

function CooldownCompanion:SetTriggerPanelEffectsPreview(groupId, show)
    if not groupId then
        return
    end
    activeTriggerPanelEffectPreviews[groupId] = show or nil
    -- Trigger effect previews belong exclusively to the pinned config mirror.
    -- Never write preview flags onto live/runtime buttons.
    if ST._RefreshTriggerDisplayVisual then
        ST._RefreshTriggerDisplayVisual(groupId)
    end
end

function CooldownCompanion:IsTriggerPanelEffectsPreviewActive(groupId)
    if activeTriggerPanelEffectPreviews[groupId] then
        return true
    end
    return false
end

function CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    local activeGroups = {}
    for groupId in pairs(activeTriggerPanelEffectPreviews) do
        activeGroups[#activeGroups + 1] = groupId
    end
    wipe(activeTriggerPanelEffectPreviews)
    for _, groupId in ipairs(activeGroups) do
        if ST._StopTriggerPanelEffectsPreviewMirror then
            ST._StopTriggerPanelEffectsPreviewMirror(groupId)
        elseif ST._RefreshTriggerDisplayVisual then
            ST._RefreshTriggerDisplayVisual(groupId)
        end
    end
end

function CooldownCompanion:ClearAllConfigPreviews()
    -- The editable mirror only needs to walk and reconcile every slot when
    -- this clear actually removed a panel visual. Preserve an already-issued
    -- ticket across duplicate clears until the config mirror consumes it.
    if next(activeGroupPreviewFlags)
        or next(activeButtonPreviewFlags)
        or next(activeConditionalGroupPreviews)
        or next(activeConditionalButtonPreviews)
        or next(activeTriggerPanelEffectPreviews) then
        local configState = ST._configState
        if configState then
            configState.panelPreviewVisualsNeedReconcile = true
        end
    end
    if self.ClearAllProcGlowPreviews then
        self:ClearAllProcGlowPreviews()
    end
    if self.ClearAllAuraGlowPreviews then
        self:ClearAllAuraGlowPreviews()
    end
    if self.ClearAllMissingAuraPreviews then
        self:ClearAllMissingAuraPreviews()
    end
    if self.ClearAllPandemicPreviews then
        self:ClearAllPandemicPreviews()
    end
    if self.ClearAllBarAuraEffectPreviews then
        self:ClearAllBarAuraEffectPreviews()
    end
    if self.ClearAllReadyGlowPreviews then
        self:ClearAllReadyGlowPreviews()
    end
    if self.ClearAllKeyPressHighlightPreviews then
        self:ClearAllKeyPressHighlightPreviews()
    end
    if self.ClearAllConditionalVisualPreviews then
        self:ClearAllConditionalVisualPreviews()
    end
    if self.ClearAllTextureIndicatorPreviews then
        self:ClearAllTextureIndicatorPreviews()
    end
    if self.ClearAllTriggerPanelEffectPreviews then
        self:ClearAllTriggerPanelEffectPreviews()
    end
    if self.ClearAllCustomAuraBarPreviews then
        self:ClearAllCustomAuraBarPreviews()
    end
    if self.ClearAllResourceAuraPreviews then
        self:ClearAllResourceAuraPreviews()
    end
    if self.ClearAllHealthEffectPreviews then
        self:ClearAllHealthEffectPreviews()
    end
    if self.ClearCursorAnchorLayoutPreview then
        self:ClearCursorAnchorLayoutPreview()
    end
    if self.StopCastBarPreview then
        self:StopCastBarPreview()
    end
    -- Unlock assists are explicit layout tools and are deliberately not
    -- cleared here.
end
