--[[
    CooldownCompanion - ButtonFrame/Preview
    Config panel preview methods for proc glow, aura glow, bar aura effect,
    bar aura active, bar pulse, bar color shift, pandemic, ready glow, and
    key press highlight.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Imports from Glows
local SetBarAuraEffect = ST._SetBarAuraEffect

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

local function RefreshKeyPressHighlightEnrollment(button)
    local refresh = ST._RefreshKeyPressHighlightEnrollment
    if refresh then
        refresh(button)
    end
end

local function UnregisterKeyPressHighlightButton(button)
    local unregister = ST._UnregisterKeyPressHighlightButton
    if unregister then
        unregister(button)
    end
end

local function RefreshKeyPressHighlightPreview(button)
    button._keyPressHighlightActive = false
    RefreshKeyPressHighlightEnrollment(button)
end

local function ClearDormantKeyPressHighlightPreviewFrame(frame)
    if not (frame and frame.buttons) then return end
    for _, button in ipairs(frame.buttons) do
        if button._keyPressHighlightPreview or button._keyPressHighlightActive ~= nil then
            button._keyPressHighlightPreview = nil
            button._keyPressHighlightActive = false
            UnregisterKeyPressHighlightButton(button)
        end
    end
end

local function ClearDormantKeyPressHighlightPreviews(self, groupId)
    local dormantFrames = self and self._dormantFrames
    if not dormantFrames then return end

    if groupId then
        ClearDormantKeyPressHighlightPreviewFrame(dormantFrames[groupId])
        return
    end

    for _, frame in pairs(dormantFrames) do
        ClearDormantKeyPressHighlightPreviewFrame(frame)
    end
end

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

-- Preview-first config: panels the config mirror renders (icon, bar, text,
-- and texture panels) show their config previews ONLY on the mirror - the
-- setters store the preview state for the mirror to read and skip the
-- live world buttons entirely. Preview families that do not opt into this
-- routing (trigger and rotation assistant) keep their established surface.
-- The mirror
-- must also actually be the active surface for this panel (wide buttons
-- view, panel selected) - that includes Other Class browsing, which
-- shares the full workspace and its pinned mirror. Clear paths stay
-- unconditional: clearing a live button is always safe.
local function IsMirrorPreviewSurface(groupId)
    local isMirrorActive = ST._IsPanelMirrorPreviewActive
    if not (isMirrorActive and isMirrorActive(groupId)) then
        return false
    end
    local db = CooldownCompanion.db
    local group = db and db.profile and db.profile.groups and db.profile.groups[groupId]
    if not group then
        return false
    end
    local mode = group.displayMode or "icons"
    if mode == "bars" or mode == "text" or mode == "textures" then
        return true
    end
    if mode ~= "icons" then
        return false
    end
    if CooldownCompanion.IsStandaloneTexturePanelGroup
        and CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        return false
    end
    return true
end

-- Set preview on a single button.
-- cacheValue: false forces cache miss on next tick; nil forces re-evaluate.
local function SetButtonPreview(self, groupId, buttonIndex, show, previewFlag, cacheFlag, cacheValue, onToggle, updateCooldown)
    SetActiveButtonPreviewFlag(groupId, buttonIndex, previewFlag, show)
    if IsMirrorPreviewSurface(groupId) then
        return
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button[previewFlag] = show or nil
            button[cacheFlag] = cacheValue
            if onToggle then onToggle(button, show) end
            if updateCooldown and button.UpdateCooldown then
                button:UpdateCooldown()
            end
            return
        end
    end
end

-- Set preview on all buttons in a group.
local function SetGroupPreview(self, groupId, show, previewFlag, cacheFlag, cacheValue, onToggle, updateCooldown)
    SetActiveGroupPreviewFlag(groupId, previewFlag, show)
    ClearActiveButtonPreviewFlagForGroup(groupId, previewFlag)
    if IsMirrorPreviewSurface(groupId) then
        return
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        button[previewFlag] = show or nil
        button[cacheFlag] = cacheValue
        if onToggle then onToggle(button, show) end
        if updateCooldown and button.UpdateCooldown then
            button:UpdateCooldown()
        end
    end
end

-- Clear all previews of a given type across every group.
local function ClearAllPreviews(self, previewFlag, cacheFlag, cacheValue, onClear, updateCooldown)
    ClearActivePreviewFlag(previewFlag)
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button[previewFlag] = nil
            button[cacheFlag] = cacheValue
            if onClear then onClear(button) end
            if updateCooldown and button.UpdateCooldown then
                button:UpdateCooldown()
            end
        end
    end
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

local function ClearConditionalVisualPreviewDerivedFields(button)
    -- Aura and loss-of-control previews write CC-side visuals that nothing
    -- else rewrites per tick (the live aura visuals are Blizzard-driven on
    -- the slot kit; live LoC skips the widget while the preview flag is up),
    -- so ending the preview must clear them explicitly.
    if button._conditionalPreviewKind == "aura_stack_text" and button.auraStackCount then
        button.auraStackCount:SetText("")
    end
    if button._auraTextPreviewFS then
        button._auraTextPreviewFS:Hide()
    end
    if button._auraSwipePreviewCooldown then
        button._auraSwipePreviewCooldown:SetCooldown(0, 0)
        button._auraSwipePreviewCooldown:Hide()
    end
    if button._conditionalPreviewKind == "loss_of_control" and button.locCooldown then
        button.locCooldown:SetCooldown(0, 0)
    end
    -- Aura previews expose a show-only-while-active shell while running
    -- (CooldownUpdate); re-hide it now that the preview state is gone.
    ST._ApplyShellVisualsForButton(button, button.buttonData)
    button._conditionalLocPreview = nil
    button._conditionalPreviewKind = nil
    button._conditionalPreviewStartTime = nil
    button._conditionalPreviewDuration = nil
    button._conditionalPreviewRemaining = nil
    button._conditionalPreviewLoop = nil
    button._conditionalPreviewLoopStartTime = nil
    button._conditionalPreviewLoopDuration = nil
    button._conditionalPreviewDomain = nil
    button._conditionalUnusablePreview = nil
    button._conditionalOutOfRangePreview = nil
    button._conditionalReadyPreview = nil
end

local function RefreshConditionalVisualPreviewButton(self, button)
    if button.UpdateCooldown then
        button:UpdateCooldown()
    elseif type(self.UpdateAuraTextureVisual) == "function" then
        self:UpdateAuraTextureVisual(button)
    end
end

local function SetConditionalVisualPreviewOnButton(self, button, state)
    button._conditionalVisualPreview = state
    if not state then
        ClearConditionalVisualPreviewDerivedFields(button)
    end
    RefreshConditionalVisualPreviewButton(self, button)
end

local function SetConditionalVisualPreview(self, groupId, buttonIndex, state)
    if not self.groupFrames then return end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            SetConditionalVisualPreviewOnButton(self, button, state)
            return
        end
    end
end

local function SetGroupConditionalVisualPreview(self, groupId, state)
    if not self.groupFrames then return end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        SetConditionalVisualPreviewOnButton(self, button, state)
    end
end

local function IsGroupButtonPreviewActive(self, groupId, buttonIndex, predicate)
    if not (self.groupFrames and groupId and predicate) then
        return false
    end
    local frame = self.groupFrames[groupId]
    if not frame then
        return false
    end

    for _, button in ipairs(frame.buttons) do
        if not buttonIndex or button.index == buttonIndex then
            if predicate(button) then
                return true
            end
            if buttonIndex then
                return false
            end
        end
    end
    return false
end

local function GetConditionalVisualPreview(button)
    return button and button._conditionalVisualPreview or nil
end

ST._GetConditionalVisualPreview = GetConditionalVisualPreview

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
    if not previewFlag then
        return false
    end
    if IsActivePreviewFlagStored(groupId, buttonIndex, previewFlag) then
        return true
    end
    return IsGroupButtonPreviewActive(self, groupId, buttonIndex, function(button)
        return button[previewFlag] == true
    end)
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
    return IsGroupButtonPreviewActive(self, groupId, buttonIndex, function(button)
        local state = GetConditionalVisualPreview(button)
        return state and state.kind == previewKind
    end)
end

function CooldownCompanion:SetConditionalVisualPreviewActive(groupId, buttonIndex, previewKind, show, sampleState)
    if not groupId then
        return
    end

    local state = show and BuildConditionalVisualPreviewState(previewKind, sampleState) or nil
    local mirrorSurface = IsMirrorPreviewSurface(groupId)
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
        -- A clear (state == nil) still reaches the live button so panels
        -- that just changed display mode can't strand a rendered preview.
        if not mirrorSurface or not state then
            SetConditionalVisualPreview(self, groupId, buttonIndex, state)
        end
        return
    end

    activeConditionalButtonPreviews[groupId] = nil
    activeConditionalGroupPreviews[groupId] = CopyPreviewState(state)
    if not mirrorSurface or not state then
        SetGroupConditionalVisualPreview(self, groupId, state)
    end
end

function CooldownCompanion:ClearAllConditionalVisualPreviews()
    wipe(activeConditionalGroupPreviews)
    wipe(activeConditionalButtonPreviews)
    if not self.groupFrames then return end
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            if button._conditionalVisualPreview then
                SetConditionalVisualPreviewOnButton(self, button, nil)
            else
                ClearConditionalVisualPreviewDerivedFields(button)
            end
        end
    end
end

--------------------------------------------------------------------------------
-- BarAuraEffect clear reconciliation (sole consumer:
-- ClearAllBarAuraEffectPreviews; the old bar pandemic toggle that shared it
-- died with the read-the-state pandemic model).
--------------------------------------------------------------------------------

local function barAuraEffectOnClear(button)
    SetBarAuraEffect(button, button._auraActive)
end

--------------------------------------------------------------------------------
-- Proc Glow Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetProcGlowPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_procGlowPreview", "_procGlowActive", false, nil, true)
end

function CooldownCompanion:SetGroupProcGlowPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_procGlowPreview", "_procGlowActive", false, nil, true)
end

function CooldownCompanion:ClearAllProcGlowPreviews()
    ClearAllPreviews(self, "_procGlowPreview", "_procGlowActive", false, nil, true)
end

--------------------------------------------------------------------------------
-- Aura Glow Preview
-- Renders through the CC-side glow container (SetAuraGlow) with the kit
-- style names mapped to their legacy renderers, so the preview matches the
-- live slot-kit glow without ever touching the aura slot subtree.
--------------------------------------------------------------------------------

-- Show-only-while-active icon shells hide the glow containers this preview
-- renders through; reapply the shell helper on every toggle and clear (the
-- flag is already set/cleared when these hooks run, so the exposure
-- predicate sees the current state).
-- `show` is passed by the set paths and omitted by the clear paths, which is
-- what keeps the container build on-demand: turning a preview ON is the only
-- moment CC's aura glow container is needed, and ClearAllPreviews walks every
-- button in every group, so building there would defeat the point entirely.
local function auraGlowShellReapply(button, show)
    if show and not button._isBar and ST._EnsureAuraGlowContainer then
        ST._EnsureAuraGlowContainer(button)
    end
    if not button._isBar and ST._ApplyAuraShellVisuals then
        ST._ApplyAuraShellVisuals(button, button.buttonData)
    end
end

function CooldownCompanion:SetAuraGlowPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_auraGlowPreview", "_auraGlowActive", false, auraGlowShellReapply, true)
end

function CooldownCompanion:SetGroupAuraGlowPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_auraGlowPreview", "_auraGlowActive", false, auraGlowShellReapply, true)
end

function CooldownCompanion:ClearAllAuraGlowPreviews()
    ClearAllPreviews(self, "_auraGlowPreview", "_auraGlowActive", false, auraGlowShellReapply, true)
end

--------------------------------------------------------------------------------
-- Pandemic Preview (PTR 8 visuals)
-- Icons render through the CC-side glow container: VisualState's
-- pandemic-preview branch routes SetAuraGlow's pandemic override, which
-- reads the same pandemicGlow* keys the live kit rig consumes — preview
-- parity without touching the aura slot subtree. Bars render nothing on
-- live buttons: the fill recolor exists only on the kit fill, so bar
-- previews live on the wide-buttons mirror alone (the same convention as
-- the bar fill pulse/color-shift effects).
--------------------------------------------------------------------------------

function CooldownCompanion:SetPandemicPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_pandemicPreview", "_auraGlowActive", false, auraGlowShellReapply, true)
end

function CooldownCompanion:SetGroupPandemicPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_pandemicPreview", "_auraGlowActive", false, auraGlowShellReapply, true)
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
    SetButtonPreview(self, groupId, buttonIndex, show, "_pandemicPreview", "_auraGlowActive", false, nil, true)
end

function CooldownCompanion:SetGroupBarPandemicPreview(groupId, show)
    if show or self:IsPreviewFlagActive(groupId, nil, "_pandemicPreview") then
        self:SetConditionalVisualPreviewActive(groupId, nil, "aura_duration_bar", show)
    end
    SetGroupPreview(self, groupId, show, "_pandemicPreview", "_auraGlowActive", false, nil, true)
end

function CooldownCompanion:ClearAllPandemicPreviews()
    ClearAllPreviews(self, "_pandemicPreview", "_auraGlowActive", false, auraGlowShellReapply, true)
end

--------------------------------------------------------------------------------
-- Bar Aura Effect Preview (barActiveAura)
-- Renders through the CC-side glow container (SetBarAuraEffect) with the kit
-- style names mapped to their legacy renderers (Glows.lua
-- NormalizeBarAuraEffectStyle), so the preview matches the live kit bar glow
-- without touching the aura slot subtree. The toggle also runs the
-- aura_duration_bar conditional preview — a fake looping aura drain in the
-- aura color, with shell exposure for show-only-while-active bars — so the
-- bar looks exactly as if the aura were live; the fill pulse/color-shift
-- effects ride that simulation (BarMode.lua UpdateBarDisplay, keyed off
-- _barAuraEffectPreview).
--------------------------------------------------------------------------------

-- Group bar buttons build the barAuraEffect container lazily: only the
-- dormant custom-aura-bar path creates it eagerly, and previews are the
-- first consumer on ordinary bars.
local function barAuraEffectOnToggle(button, show)
    if show then
        if button._isBar and not button.barAuraEffect and ST._CreateGlowContainer then
            button.barAuraEffect = ST._CreateGlowContainer(button, 32, false)
        end
        -- Live parity: the kit renders nothing while the indicator is
        -- disabled, so a preview on a disabled button must not either (and
        -- passing false here clears a border left by a just-disabled one).
        SetBarAuraEffect(button, ST.IsBarAuraIndicatorEnabled(button.style) == true)
    else
        SetBarAuraEffect(button, button._auraActive)
    end
end

-- Same shared-conditional ownership rule as the bar pandemic setters below:
-- a clear may only wipe the "aura_duration_bar" store while this preview's
-- own flag holds it, or the sections' rebuild-time reconciliation clears
-- kill each other's running drain.
function CooldownCompanion:SetBarAuraEffectPreview(groupId, buttonIndex, show)
    if show or self:IsPreviewFlagActive(groupId, buttonIndex, "_barAuraEffectPreview") then
        self:SetConditionalVisualPreviewActive(groupId, buttonIndex, "aura_duration_bar", show)
    end
    SetButtonPreview(self, groupId, buttonIndex, show, "_barAuraEffectPreview", "_barAuraEffectActive", false, barAuraEffectOnToggle, true)
end

function CooldownCompanion:SetGroupBarAuraEffectPreview(groupId, show)
    if show or self:IsPreviewFlagActive(groupId, nil, "_barAuraEffectPreview") then
        self:SetConditionalVisualPreviewActive(groupId, nil, "aura_duration_bar", show)
    end
    SetGroupPreview(self, groupId, show, "_barAuraEffectPreview", "_barAuraEffectActive", false, barAuraEffectOnToggle, true)
end

-- The fake drain is cleared by ClearAllConditionalVisualPreviews; every
-- caller of this (ClearAllConfigPreviews) runs both.
function CooldownCompanion:ClearAllBarAuraEffectPreviews()
    ClearAllPreviews(self, "_barAuraEffectPreview", "_barAuraEffectActive", false, barAuraEffectOnClear, true)
end

--------------------------------------------------------------------------------
-- Ready Glow Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetReadyGlowPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_readyGlowPreview", "_readyGlowActive", false, nil, true)
end

function CooldownCompanion:SetGroupReadyGlowPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_readyGlowPreview", "_readyGlowActive", false, nil, true)
end

function CooldownCompanion:ClearAllReadyGlowPreviews()
    ClearAllPreviews(self, "_readyGlowPreview", "_readyGlowActive", false, nil, true)
end

--------------------------------------------------------------------------------
-- Key Press Highlight Preview (no per-button methods, no UpdateCooldown)
-- KPH is rendered by the idle enrollment driver, not by UpdateCooldown.
--------------------------------------------------------------------------------

function CooldownCompanion:SetGroupKeyPressHighlightPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_keyPressHighlightPreview", "_keyPressHighlightActive", false, RefreshKeyPressHighlightPreview, false)
    if not show then
        ClearDormantKeyPressHighlightPreviews(self, groupId)
    end
end

function CooldownCompanion:ClearAllKeyPressHighlightPreviews()
    ClearAllPreviews(self, "_keyPressHighlightPreview", "_keyPressHighlightActive", false, RefreshKeyPressHighlightPreview, false)
    ClearDormantKeyPressHighlightPreviews(self)
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
local TEXTURE_INDICATOR_PREVIEW_FLAG_SET = {}
for _, previewFlag in pairs(TEXTURE_INDICATOR_PREVIEW_FLAGS) do
    TEXTURE_INDICATOR_PREVIEW_FLAG_SET[previewFlag] = true
end

local function ClearTextureIndicatorPreviewFieldsFromFrame(self, frame)
    if not (frame and frame.buttons) then
        return
    end

    for _, button in ipairs(frame.buttons) do
        local hadPreview = false
        for _, previewFlag in pairs(TEXTURE_INDICATOR_PREVIEW_FLAGS) do
            if button[previewFlag] ~= nil then
                button[previewFlag] = nil
                hadPreview = true
            end
        end
        button._textureIndicatorPreviewDirty = false

        -- Only touch the runtime renderer when retiring a stale flag from the
        -- old live-preview path. Normal preview toggles remain stored-only and
        -- never ask the world panel to repaint.
        if hadPreview then
            if button.UpdateCooldown then
                button:UpdateCooldown()
            else
                self:UpdateAuraTextureVisual(button)
            end
        end
    end
end

local function ClearTextureIndicatorPreviewFields(self, groupId)
    local frame = self.groupFrames and self.groupFrames[groupId]
    ClearTextureIndicatorPreviewFieldsFromFrame(self, frame)

    local dormantFrame = self._dormantFrames and self._dormantFrames[groupId]
    if dormantFrame ~= frame then
        ClearTextureIndicatorPreviewFieldsFromFrame(self, dormantFrame)
    end
end

function CooldownCompanion:SetGroupTextureIndicatorPreview(groupId, indicatorKey, show)
    local previewFlag = TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey]
    if not previewFlag then
        return
    end

    -- Texture effects are a config-mirror feature. Keep their state in the
    -- config-owned store even while the pinned mirror is not visible, and
    -- proactively retire any fields left on live buttons by older builds.
    SetActiveGroupPreviewFlag(groupId, previewFlag, show)
    ClearActiveButtonPreviewFlagForGroup(groupId, previewFlag)
    ClearTextureIndicatorPreviewFields(self, groupId)
end

function CooldownCompanion:IsGroupTextureIndicatorPreviewActive(groupId, indicatorKey)
    local previewFlag = TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey]
    return previewFlag and IsActivePreviewFlagStored(groupId, nil, previewFlag) or false
end

function CooldownCompanion:ClearAllTextureIndicatorPreviews()
    for indicatorKey in pairs(TEXTURE_INDICATOR_PREVIEW_FLAGS) do
        ClearActivePreviewFlag(TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey])
    end

    for groupId in pairs(self.groupFrames or {}) do
        ClearTextureIndicatorPreviewFields(self, groupId)
    end
    for groupId in pairs(self._dormantFrames or {}) do
        if not (self.groupFrames and self.groupFrames[groupId]) then
            ClearTextureIndicatorPreviewFields(self, groupId)
        end
    end

    if ST._StopTextureIndicatorPreviewMirror then
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

--------------------------------------------------------------------------------
-- Aura Texture Picker Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetAuraTexturePickerPreview(groupId, buttonIndex, selection)
    local frame = self.groupFrames[groupId]
    if not frame then
        return
    end

    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if group and group.displayMode == "trigger" and buttonIndex == nil then
        for _, button in ipairs(frame.buttons) do
            button._auraTexturePreviewSelection = selection and CopyTable(selection) or nil
        end
        local driverButton = frame.buttons and frame.buttons[1] or nil
        if driverButton then
            if driverButton.UpdateCooldown then
                driverButton:UpdateCooldown()
            else
                self:UpdateAuraTextureVisual(driverButton)
            end
        end
        return
    end

    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._auraTexturePreviewSelection = selection and CopyTable(selection) or nil
            if button.UpdateCooldown then
                button:UpdateCooldown()
            else
                self:UpdateAuraTextureVisual(button)
            end
            return
        end
    end
end

function CooldownCompanion:ClearAllAuraTexturePickerPreviews()
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            local hadPreview = button._auraTexturePreviewSelection ~= nil
            if hadPreview then
                button._auraTexturePreviewSelection = nil
            end
            if button.UpdateCooldown then
                button:UpdateCooldown()
            else
                self:UpdateAuraTextureVisual(button)
            end
        end
    end
end

local function ApplyPreviewFlagToButton(button, previewFlag)
    -- Texture indicator preview state belongs exclusively to the config
    -- mirror, including after a live group frame is rebuilt.
    if TEXTURE_INDICATOR_PREVIEW_FLAG_SET[previewFlag] then
        return
    end

    button[previewFlag] = true
    if previewFlag == "_procGlowPreview" then
        button._procGlowActive = false
    elseif previewFlag == "_auraGlowPreview" or previewFlag == "_pandemicPreview" then
        button._auraGlowActive = false
        -- Repopulated buttons re-hid their icon shell before this flag was
        -- restored; reapply so the preview stays visible (both flags render
        -- through the same CC-side glow container). A repopulated button is a
        -- fresh frame with no container yet, so this must pass show.
        auraGlowShellReapply(button, true)
    elseif previewFlag == "_barAuraEffectPreview" then
        button._barAuraEffectActive = false
        barAuraEffectOnToggle(button, true)
    elseif previewFlag == "_readyGlowPreview" then
        button._readyGlowActive = false
    elseif previewFlag == "_keyPressHighlightPreview" then
        RefreshKeyPressHighlightPreview(button)
    elseif previewFlag == "_textureProcPreview"
        or previewFlag == "_textureAuraPreview"
        or previewFlag == "_textureReadyPreview"
        or previewFlag == "_textureUnusablePreview" then
        button._textureIndicatorPreviewDirty = false
    end
end

function CooldownCompanion:ApplyConfigPreviewsToGroup(groupId)
    if not (self.groupFrames and groupId) then
        return
    end
    local frame = self.groupFrames[groupId]
    if not frame then
        return
    end

    -- Mirror-surface panels never reapply previews to rebuilt live
    -- frames - the stored state lives on for the mirror alone.
    local mirrorSurface = IsMirrorPreviewSurface(groupId)

    local groupFlags = not mirrorSurface and activeGroupPreviewFlags[groupId] or nil
    if groupFlags then
        for _, button in ipairs(frame.buttons) do
            for previewFlag in pairs(groupFlags) do
                ApplyPreviewFlagToButton(button, previewFlag)
            end
        end
    end

    local buttonFlagsByIndex = not mirrorSurface and activeButtonPreviewFlags[groupId] or nil
    if buttonFlagsByIndex then
        for _, button in ipairs(frame.buttons) do
            local buttonFlags = buttonFlagsByIndex[button.index]
            if buttonFlags then
                for previewFlag in pairs(buttonFlags) do
                    ApplyPreviewFlagToButton(button, previewFlag)
                end
            end
        end
    end

    local groupConditionalPreview = not mirrorSurface and activeConditionalGroupPreviews[groupId] or nil
    if groupConditionalPreview then
        for _, button in ipairs(frame.buttons) do
            SetConditionalVisualPreviewOnButton(self, button, CopyPreviewState(groupConditionalPreview))
        end
    end

    local conditionalButtons = not mirrorSurface and activeConditionalButtonPreviews[groupId] or nil
    if conditionalButtons then
        for _, button in ipairs(frame.buttons) do
            local preview = conditionalButtons[button.index]
            if preview then
                SetConditionalVisualPreviewOnButton(self, button, CopyPreviewState(preview))
            end
        end
    end
end

function CooldownCompanion:ClearAllConfigPreviews()
    if self.ClearAllProcGlowPreviews then
        self:ClearAllProcGlowPreviews()
    end
    if self.ClearAllAuraGlowPreviews then
        self:ClearAllAuraGlowPreviews()
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
    if self.ClearAllAuraTexturePickerPreviews then
        self:ClearAllAuraTexturePickerPreviews()
    end
    if self.ClearCursorAnchorLayoutPreview then
        self:ClearCursorAnchorLayoutPreview()
    end
    if self.StopCastBarPreview then
        self:StopCastBarPreview()
    end
    -- The resource-bar unlock assist is deliberately NOT cleared here: it is
    -- visibility for dragging, not a preview, and it belongs to whether the
    -- stack is unlocked.
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end
