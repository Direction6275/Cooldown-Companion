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

-- Set preview on a single button.
-- cacheValue: false forces cache miss on next tick; nil forces re-evaluate.
local function SetButtonPreview(self, groupId, buttonIndex, show, previewFlag, cacheFlag, cacheValue, onToggle, updateCooldown)
    SetActiveButtonPreviewFlag(groupId, buttonIndex, previewFlag, show)
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
    charge_full = { kind = "charge_full" },
    charge_missing = { kind = "charge_missing" },
    charge_zero = { kind = "charge_zero" },
    unusable = { kind = "unusable" },
    out_of_range = { kind = "out_of_range" },
    -- 12.1 aura previews render CC-side stand-ins from the same style keys
    -- the slot kit consumes; they never touch the aura slot subtree.
    aura_duration_text = { kind = "aura_duration_text", duration = 12, remaining = 8, loop = true },
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
    if button._isBar and ST._ApplyBarAuraShellVisuals then
        ST._ApplyBarAuraShellVisuals(button, button.buttonData)
    elseif not button._isBar and ST._ApplyAuraShellVisuals then
        ST._ApplyAuraShellVisuals(button, button.buttonData)
    end
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
        SetConditionalVisualPreview(self, groupId, buttonIndex, state)
        return
    end

    activeConditionalButtonPreviews[groupId] = nil
    activeConditionalGroupPreviews[groupId] = CopyPreviewState(state)
    SetGroupConditionalVisualPreview(self, groupId, state)
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
-- Pandemic/BarAuraEffect toggle callback
--------------------------------------------------------------------------------

local function pandemicOnToggle(button, show)
    if not show then
        SetBarAuraEffect(button, button._auraActive)
    else
        button._barAuraEffectActive = nil
    end
end

local function pandemicOnClear(button)
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
local function auraGlowShellReapply(button)
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
-- Pandemic Preview
-- (12.1 aura teardown: config entry-point setters removed; ClearAll* kept for
-- recycled-frame safety until the aura rebuild.)
--------------------------------------------------------------------------------

function CooldownCompanion:ClearAllPandemicPreviews()
    ClearAllPreviews(self, "_pandemicPreview", "_auraGlowActive", false, pandemicOnClear, true)
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
        SetBarAuraEffect(button, true)
    else
        SetBarAuraEffect(button, button._auraActive)
    end
end

function CooldownCompanion:SetBarAuraEffectPreview(groupId, buttonIndex, show)
    self:SetConditionalVisualPreviewActive(groupId, buttonIndex, "aura_duration_bar", show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_barAuraEffectPreview", "_barAuraEffectActive", false, barAuraEffectOnToggle, true)
end

function CooldownCompanion:SetGroupBarAuraEffectPreview(groupId, show)
    self:SetConditionalVisualPreviewActive(groupId, nil, "aura_duration_bar", show)
    SetGroupPreview(self, groupId, show, "_barAuraEffectPreview", "_barAuraEffectActive", false, barAuraEffectOnToggle, true)
end

-- The fake drain is cleared by ClearAllConditionalVisualPreviews; every
-- caller of this (ClearAllConfigPreviews) runs both.
function CooldownCompanion:ClearAllBarAuraEffectPreviews()
    ClearAllPreviews(self, "_barAuraEffectPreview", "_barAuraEffectActive", false, pandemicOnClear, true)
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
    pandemic = "_texturePandemicPreview",
    ready = "_textureReadyPreview",
    unusable = "_textureUnusablePreview",
}

function CooldownCompanion:SetGroupTextureIndicatorPreview(groupId, indicatorKey, show)
    local previewFlag = TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey]
    if not previewFlag then
        return
    end

    SetGroupPreview(
        self,
        groupId,
        show,
        previewFlag,
        "_textureIndicatorPreviewDirty",
        false,
        nil,
        true
    )
end

function CooldownCompanion:IsGroupTextureIndicatorPreviewActive(groupId, indicatorKey)
    local previewFlag = TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey]
    return previewFlag and self:IsPreviewFlagActive(groupId, nil, previewFlag) or false
end

function CooldownCompanion:ClearAllTextureIndicatorPreviews()
    for indicatorKey in pairs(TEXTURE_INDICATOR_PREVIEW_FLAGS) do
        ClearActivePreviewFlag(TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey])
    end

    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._textureProcPreview = nil
            button._textureAuraPreview = nil
            button._texturePandemicPreview = nil
            button._textureReadyPreview = nil
            button._textureUnusablePreview = nil
            button._textureIndicatorPreviewDirty = false
            if button.UpdateCooldown then
                button:UpdateCooldown()
            else
                self:UpdateAuraTextureVisual(button)
            end
        end
    end
end

function CooldownCompanion:SetTriggerPanelEffectsPreview(groupId, show)
    if not groupId then
        return
    end
    local frame = self.groupFrames[groupId]
    activeTriggerPanelEffectPreviews[groupId] = show or nil
    if not frame then
        return
    end

    for _, button in ipairs(frame.buttons) do
        button._triggerEffectsPreview = show or nil
        if button.UpdateCooldown then
            button:UpdateCooldown()
        else
            self:UpdateAuraTextureVisual(button)
        end
    end
end

function CooldownCompanion:IsTriggerPanelEffectsPreviewActive(groupId)
    if activeTriggerPanelEffectPreviews[groupId] then
        return true
    end
    return self:IsPreviewFlagActive(groupId, nil, "_triggerEffectsPreview")
end

function CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    wipe(activeTriggerPanelEffectPreviews)
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._triggerEffectsPreview = nil
            if button.UpdateCooldown then
                button:UpdateCooldown()
            else
                self:UpdateAuraTextureVisual(button)
            end
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
    button[previewFlag] = true
    if previewFlag == "_procGlowPreview" then
        button._procGlowActive = false
    elseif previewFlag == "_auraGlowPreview" or previewFlag == "_pandemicPreview" then
        button._auraGlowActive = false
        if previewFlag == "_auraGlowPreview" then
            -- Repopulated buttons re-hid their icon shell before this flag
            -- was restored; reapply so the preview stays visible.
            auraGlowShellReapply(button)
        end
        if previewFlag == "_pandemicPreview" then
            pandemicOnToggle(button, true)
        end
    elseif previewFlag == "_barAuraEffectPreview" then
        button._barAuraEffectActive = false
        barAuraEffectOnToggle(button, true)
    elseif previewFlag == "_readyGlowPreview" then
        button._readyGlowActive = false
    elseif previewFlag == "_keyPressHighlightPreview" then
        RefreshKeyPressHighlightPreview(button)
    elseif previewFlag == "_textureProcPreview"
        or previewFlag == "_textureAuraPreview"
        or previewFlag == "_texturePandemicPreview"
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

    local groupFlags = activeGroupPreviewFlags[groupId]
    if groupFlags then
        for _, button in ipairs(frame.buttons) do
            for previewFlag in pairs(groupFlags) do
                ApplyPreviewFlagToButton(button, previewFlag)
            end
        end
    end

    local buttonFlagsByIndex = activeButtonPreviewFlags[groupId]
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

    if activeTriggerPanelEffectPreviews[groupId] then
        for _, button in ipairs(frame.buttons) do
            button._triggerEffectsPreview = true
        end
    end

    local groupConditionalPreview = activeConditionalGroupPreviews[groupId]
    if groupConditionalPreview then
        for _, button in ipairs(frame.buttons) do
            SetConditionalVisualPreviewOnButton(self, button, CopyPreviewState(groupConditionalPreview))
        end
    end

    local conditionalButtons = activeConditionalButtonPreviews[groupId]
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
    if self.StopResourceBarPreview then
        self:StopResourceBarPreview()
    end
    if ST._ClearActivePreviewBadgeButton then
        ST._ClearActivePreviewBadgeButton()
    end
    if ST._RefreshAdvancedSettingsPreviewButtons then
        ST._RefreshAdvancedSettingsPreviewButtons()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end
