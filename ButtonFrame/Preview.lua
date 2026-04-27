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
local C_Timer_After = C_Timer.After

-- Token stores for each glow type (used to invalidate stale timed callbacks)
local procPreviewTokens = {}
local procButtonPreviewTokens = {}
local auraPreviewTokens = {}
local auraButtonPreviewTokens = {}
local pandemicPreviewTokens = {}
local pandemicButtonPreviewTokens = {}
local readyPreviewTokens = {}
local readyButtonPreviewTokens = {}
local kphPreviewTokens = {}
local textureIndicatorPreviewTokens = {}
local triggerEffectPreviewTokens = {}
local conditionalVisualGroupTokens = {}
local conditionalVisualButtonTokens = {}
local activeGroupPreviewFlags = {}
local activeButtonPreviewFlags = {}
local activeTriggerPanelEffectPreviews = {}
local activeConditionalGroupPreviews = {}
local activeConditionalButtonPreviews = {}

local function BumpButtonPreviewToken(tokenStore, groupId, buttonIndex)
    local groupTokens = tokenStore[groupId]
    if not groupTokens then
        groupTokens = {}
        tokenStore[groupId] = groupTokens
    end
    local token = (groupTokens[buttonIndex] or 0) + 1
    groupTokens[buttonIndex] = token
    return token
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
local function SetButtonPreview(self, groupId, buttonIndex, show, previewFlag, cacheFlag, cacheValue, buttonTokenStore, onToggle, updateCooldown)
    if buttonTokenStore and not show then
        BumpButtonPreviewToken(buttonTokenStore, groupId, buttonIndex)
    end
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
local function SetGroupPreview(self, groupId, show, previewFlag, cacheFlag, cacheValue, groupTokenStore, buttonTokenStore, onToggle, updateCooldown)
    if buttonTokenStore then buttonTokenStore[groupId] = nil end
    SetActiveGroupPreviewFlag(groupId, previewFlag, show)
    ClearActiveButtonPreviewFlagForGroup(groupId, previewFlag)
    if not show then
        groupTokenStore[groupId] = (groupTokenStore[groupId] or 0) + 1
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

-- Play a timed preview on a single button (default: 3 seconds).
local function PlayButtonPreview(self, groupId, buttonIndex, durationSeconds, buttonTokenStore, setPreviewFn)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then duration = 3 end

    local token = BumpButtonPreviewToken(buttonTokenStore, groupId, buttonIndex)
    setPreviewFn(self, groupId, buttonIndex, true)

    C_Timer_After(duration, function()
        local groupTokens = buttonTokenStore[groupId]
        if not groupTokens or groupTokens[buttonIndex] ~= token then return end
        setPreviewFn(self, groupId, buttonIndex, false)
    end)
end

-- Play a timed preview on a whole group (default: 3 seconds).
local function PlayGroupPreview(self, groupId, durationSeconds, groupTokenStore, setGroupPreviewFn)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then duration = 3 end

    local token = (groupTokenStore[groupId] or 0) + 1
    groupTokenStore[groupId] = token

    setGroupPreviewFn(self, groupId, true)

    C_Timer_After(duration, function()
        if groupTokenStore[groupId] ~= token then return end
        setGroupPreviewFn(self, groupId, false)
    end)
end

-- Clear all previews of a given type across every group.
local function ClearAllPreviews(self, previewFlag, cacheFlag, cacheValue, groupTokenStore, buttonTokenStore, onClear, updateCooldown)
    wipe(groupTokenStore)
    if buttonTokenStore then wipe(buttonTokenStore) end
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
    aura = { kind = "aura", duration = 12, remaining = 8, stackText = "3" },
    aura_duration_text = { kind = "aura_duration_text", duration = 12, remaining = 8, loop = true },
    aura_stack_text = { kind = "aura_stack_text", stackText = "3" },
    pandemic = { kind = "pandemic", duration = 12, remaining = 3, stackText = "3" },
    charge_full = { kind = "charge_full" },
    charge_missing = { kind = "charge_missing" },
    charge_zero = { kind = "charge_zero" },
    unusable = { kind = "unusable" },
    out_of_range = { kind = "out_of_range" },
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
    if button._conditionalAuraPreview then
        button._auraActive = false
        button._auraHasTimer = false
        button._auraStackText = ""
    end
    if button._conditionalAuraStackTextPreview then
        button._auraStackText = ""
        if button.auraStackCount then
            button.auraStackCount:SetText("")
        end
    end
    if button._conditionalPandemicPreview then
        button._inPandemic = false
        button._pandemicGraceStart = nil
    end
    button._conditionalPreviewKind = nil
    button._conditionalPreviewStartTime = nil
    button._conditionalPreviewDuration = nil
    button._conditionalPreviewRemaining = nil
    button._conditionalPreviewLoop = nil
    button._conditionalPreviewLoopStartTime = nil
    button._conditionalPreviewLoopDuration = nil
    button._conditionalPreviewDomain = nil
    button._conditionalAuraPreview = nil
    button._conditionalAuraDurationTextPreview = nil
    button._conditionalAuraStackTextPreview = nil
    button._conditionalPandemicPreview = nil
    button._conditionalUnusablePreview = nil
    button._conditionalOutOfRangePreview = nil
    button._conditionalReadyPreview = nil
    button._conditionalBarAuraActivePreview = nil
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
        BumpButtonPreviewToken(conditionalVisualButtonTokens, groupId, buttonIndex)
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

    conditionalVisualButtonTokens[groupId] = nil
    activeConditionalButtonPreviews[groupId] = nil
    activeConditionalGroupPreviews[groupId] = CopyPreviewState(state)
    conditionalVisualGroupTokens[groupId] = (conditionalVisualGroupTokens[groupId] or 0) + 1
    SetGroupConditionalVisualPreview(self, groupId, state)
end

function CooldownCompanion:PlayConditionalVisualPreview(groupId, buttonIndex, previewKind, durationSeconds, sampleState)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then duration = 3 end

    local state = BuildConditionalVisualPreviewState(previewKind, sampleState)
    if buttonIndex then
        local token = BumpButtonPreviewToken(conditionalVisualButtonTokens, groupId, buttonIndex)
        SetConditionalVisualPreview(self, groupId, buttonIndex, state)

        C_Timer_After(duration, function()
            local groupTokens = conditionalVisualButtonTokens[groupId]
            if not groupTokens or groupTokens[buttonIndex] ~= token then return end
            SetConditionalVisualPreview(self, groupId, buttonIndex, nil)
        end)
        return
    end

    conditionalVisualButtonTokens[groupId] = nil
    local token = (conditionalVisualGroupTokens[groupId] or 0) + 1
    conditionalVisualGroupTokens[groupId] = token
    SetGroupConditionalVisualPreview(self, groupId, state)

    C_Timer_After(duration, function()
        if conditionalVisualGroupTokens[groupId] ~= token then return end
        SetGroupConditionalVisualPreview(self, groupId, nil)
    end)
end

function CooldownCompanion:ClearAllConditionalVisualPreviews()
    wipe(conditionalVisualGroupTokens)
    wipe(conditionalVisualButtonTokens)
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
    SetButtonPreview(self, groupId, buttonIndex, show, "_procGlowPreview", "_procGlowActive", false, procButtonPreviewTokens, nil, true)
end

function CooldownCompanion:SetGroupProcGlowPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_procGlowPreview", "_procGlowActive", false, procPreviewTokens, procButtonPreviewTokens, nil, true)
end

function CooldownCompanion:PlayProcGlowPreview(groupId, buttonIndex, durationSeconds)
    PlayButtonPreview(self, groupId, buttonIndex, durationSeconds, procButtonPreviewTokens, self.SetProcGlowPreview)
end

function CooldownCompanion:PlayGroupProcGlowPreview(groupId, durationSeconds)
    PlayGroupPreview(self, groupId, durationSeconds, procPreviewTokens, self.SetGroupProcGlowPreview)
end

function CooldownCompanion:ClearAllProcGlowPreviews()
    ClearAllPreviews(self, "_procGlowPreview", "_procGlowActive", false, procPreviewTokens, procButtonPreviewTokens, nil, true)
end

--------------------------------------------------------------------------------
-- Aura Glow Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetAuraGlowPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_auraGlowPreview", "_auraGlowActive", false, auraButtonPreviewTokens, nil, true)
end

function CooldownCompanion:SetGroupAuraGlowPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_auraGlowPreview", "_auraGlowActive", false, auraPreviewTokens, auraButtonPreviewTokens, nil, true)
end

function CooldownCompanion:PlayAuraGlowPreview(groupId, buttonIndex, durationSeconds)
    PlayButtonPreview(self, groupId, buttonIndex, durationSeconds, auraButtonPreviewTokens, self.SetAuraGlowPreview)
end

function CooldownCompanion:PlayGroupAuraGlowPreview(groupId, durationSeconds)
    PlayGroupPreview(self, groupId, durationSeconds, auraPreviewTokens, self.SetGroupAuraGlowPreview)
end

function CooldownCompanion:ClearAllAuraGlowPreviews()
    ClearAllPreviews(self, "_auraGlowPreview", "_auraGlowActive", false, auraPreviewTokens, auraButtonPreviewTokens, nil, true)
end

--------------------------------------------------------------------------------
-- Bar Aura Effect Preview (unique — no tokens, no UpdateCooldown)
--------------------------------------------------------------------------------

function CooldownCompanion:SetBarAuraEffectPreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._barAuraEffectPreview = show or nil
            if not show then
                SetBarAuraEffect(button, button._auraActive)
            else
                button._barAuraEffectActive = nil
            end
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Bar Pulse Preview (unique — no tokens, no UpdateCooldown)
--------------------------------------------------------------------------------

function CooldownCompanion:SetBarPulsePreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._barPulsePreview = show or nil
            if not show then
                button._barPulseActive = nil
                if button.statusBar then button.statusBar:SetAlpha(1.0) end
            end
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Bar Color Shift Preview (unique — no tokens, no UpdateCooldown)
--------------------------------------------------------------------------------

function CooldownCompanion:SetBarColorShiftPreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._barColorShiftPreview = show or nil
            if not show then
                button._barColorShiftActive = nil
                button._barAuraColor = nil
                button._barCdColor = nil
            end
            return
        end
    end
end

--------------------------------------------------------------------------------
-- Bar Aura Active Preview (simulates full aura-active state: aura color,
-- bar glow, alpha pulse, color shift — everything the aura indicator shows)
-- Optional buttonIndex targets a single button (per-button override preview).
--------------------------------------------------------------------------------

local barAuraActiveGroupTokens = {}
local barAuraActiveButtonTokens = {}

function CooldownCompanion:SetBarAuraActivePreview(groupId, buttonIndex, show)
    if not groupId then return end
    if buttonIndex then
        BumpButtonPreviewToken(barAuraActiveButtonTokens, groupId, buttonIndex)
        SetActiveButtonPreviewFlag(groupId, buttonIndex, "_barAuraActivePreview", show)
    else
        barAuraActiveButtonTokens[groupId] = nil
        barAuraActiveGroupTokens[groupId] = (barAuraActiveGroupTokens[groupId] or 0) + 1
        SetActiveGroupPreviewFlag(groupId, "_barAuraActivePreview", show)
        ClearActiveButtonPreviewFlagForGroup(groupId, "_barAuraActivePreview")
    end

    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if not buttonIndex or button.index == buttonIndex then
            button._barAuraActivePreview = show or nil
            if button.UpdateCooldown then button:UpdateCooldown() end
        end
    end
end

function CooldownCompanion:IsBarAuraActivePreviewActive(groupId, buttonIndex)
    return self:IsPreviewFlagActive(groupId, buttonIndex, "_barAuraActivePreview")
end

function CooldownCompanion:PlayBarAuraActivePreview(groupId, buttonIndex, durationSeconds)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then duration = 3 end

    local token
    if buttonIndex then
        token = BumpButtonPreviewToken(barAuraActiveButtonTokens, groupId, buttonIndex)
    else
        barAuraActiveButtonTokens[groupId] = nil
        token = (barAuraActiveGroupTokens[groupId] or 0) + 1
        barAuraActiveGroupTokens[groupId] = token
    end

    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if not buttonIndex or button.index == buttonIndex then
            button._barAuraActivePreview = true
            if button.UpdateCooldown then button:UpdateCooldown() end
        end
    end

    C_Timer_After(duration, function()
        if buttonIndex then
            local groupTokens = barAuraActiveButtonTokens[groupId]
            if not groupTokens or groupTokens[buttonIndex] ~= token then return end
        else
            if barAuraActiveGroupTokens[groupId] ~= token then return end
        end
        local f = self.groupFrames[groupId]
        if not f then return end
        for _, btn in ipairs(f.buttons) do
            if not buttonIndex or btn.index == buttonIndex then
                btn._barAuraActivePreview = nil
                if btn.UpdateCooldown then btn:UpdateCooldown() end
            end
        end
    end)
end

function CooldownCompanion:ClearAllBarAuraActivePreviews()
    wipe(barAuraActiveGroupTokens)
    wipe(barAuraActiveButtonTokens)
    ClearActivePreviewFlag("_barAuraActivePreview")
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            if button._barAuraActivePreview then
                button._barAuraActivePreview = nil
                if button.UpdateCooldown then button:UpdateCooldown() end
            end
        end
    end
end

--------------------------------------------------------------------------------
-- Pandemic Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetPandemicPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_pandemicPreview", "_auraGlowActive", false, pandemicButtonPreviewTokens, pandemicOnToggle, true)
end

function CooldownCompanion:SetGroupPandemicPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_pandemicPreview", "_auraGlowActive", false, pandemicPreviewTokens, pandemicButtonPreviewTokens, pandemicOnToggle, true)
end

function CooldownCompanion:PlayPandemicPreview(groupId, buttonIndex, durationSeconds)
    PlayButtonPreview(self, groupId, buttonIndex, durationSeconds, pandemicButtonPreviewTokens, self.SetPandemicPreview)
end

function CooldownCompanion:PlayGroupPandemicPreview(groupId, durationSeconds)
    PlayGroupPreview(self, groupId, durationSeconds, pandemicPreviewTokens, self.SetGroupPandemicPreview)
end

function CooldownCompanion:ClearAllPandemicPreviews()
    ClearAllPreviews(self, "_pandemicPreview", "_auraGlowActive", false, pandemicPreviewTokens, pandemicButtonPreviewTokens, pandemicOnClear, true)
end

--------------------------------------------------------------------------------
-- Ready Glow Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetReadyGlowPreview(groupId, buttonIndex, show)
    SetButtonPreview(self, groupId, buttonIndex, show, "_readyGlowPreview", "_readyGlowActive", false, readyButtonPreviewTokens, nil, true)
end

function CooldownCompanion:SetGroupReadyGlowPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_readyGlowPreview", "_readyGlowActive", false, readyPreviewTokens, readyButtonPreviewTokens, nil, true)
end

function CooldownCompanion:PlayReadyGlowPreview(groupId, buttonIndex, durationSeconds)
    PlayButtonPreview(self, groupId, buttonIndex, durationSeconds, readyButtonPreviewTokens, self.SetReadyGlowPreview)
end

function CooldownCompanion:PlayGroupReadyGlowPreview(groupId, durationSeconds)
    PlayGroupPreview(self, groupId, durationSeconds, readyPreviewTokens, self.SetGroupReadyGlowPreview)
end

function CooldownCompanion:ClearAllReadyGlowPreviews()
    ClearAllPreviews(self, "_readyGlowPreview", "_readyGlowActive", false, readyPreviewTokens, readyButtonPreviewTokens, nil, true)
end

--------------------------------------------------------------------------------
-- Key Press Highlight Preview (no per-button methods, no UpdateCooldown)
-- KPH is rendered by the per-frame kphUpdateFrame OnUpdate handler, not by
-- UpdateCooldown — setting the flag and invalidating the cache is sufficient.
--------------------------------------------------------------------------------

function CooldownCompanion:SetGroupKeyPressHighlightPreview(groupId, show)
    SetGroupPreview(self, groupId, show, "_keyPressHighlightPreview", "_keyPressHighlightActive", nil, kphPreviewTokens, nil, nil, false)
end

function CooldownCompanion:PlayGroupKeyPressHighlightPreview(groupId, durationSeconds)
    PlayGroupPreview(self, groupId, durationSeconds, kphPreviewTokens, self.SetGroupKeyPressHighlightPreview)
end

function CooldownCompanion:ClearAllKeyPressHighlightPreviews()
    ClearAllPreviews(self, "_keyPressHighlightPreview", "_keyPressHighlightActive", nil, kphPreviewTokens, nil, nil, false)
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

local function GetTextureIndicatorTokenStore(indicatorKey)
    if not textureIndicatorPreviewTokens[indicatorKey] then
        textureIndicatorPreviewTokens[indicatorKey] = {}
    end
    return textureIndicatorPreviewTokens[indicatorKey]
end

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
        GetTextureIndicatorTokenStore(indicatorKey),
        nil,
        nil,
        true
    )
end

function CooldownCompanion:IsGroupTextureIndicatorPreviewActive(groupId, indicatorKey)
    local previewFlag = TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey]
    return previewFlag and self:IsPreviewFlagActive(groupId, nil, previewFlag) or false
end

function CooldownCompanion:PlayGroupTextureIndicatorPreview(groupId, indicatorKey, durationSeconds)
    local previewFlag = TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey]
    if not previewFlag then
        return
    end

    PlayGroupPreview(
        self,
        groupId,
        durationSeconds,
        GetTextureIndicatorTokenStore(indicatorKey),
        function(_, previewGroupId, show)
            self:SetGroupTextureIndicatorPreview(previewGroupId, indicatorKey, show)
        end
    )
end

function CooldownCompanion:ClearAllTextureIndicatorPreviews()
    for indicatorKey in pairs(TEXTURE_INDICATOR_PREVIEW_FLAGS) do
        ClearActivePreviewFlag(TEXTURE_INDICATOR_PREVIEW_FLAGS[indicatorKey])
        wipe(GetTextureIndicatorTokenStore(indicatorKey))
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

    if not show then
        triggerEffectPreviewTokens[groupId] = (triggerEffectPreviewTokens[groupId] or 0) + 1
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

function CooldownCompanion:PlayTriggerPanelEffectsPreview(groupId, durationSeconds)
    PlayGroupPreview(self, groupId, durationSeconds, triggerEffectPreviewTokens, self.SetTriggerPanelEffectsPreview)
end

function CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    wipe(triggerEffectPreviewTokens)
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
        if previewFlag == "_pandemicPreview" then
            pandemicOnToggle(button, true)
        end
    elseif previewFlag == "_readyGlowPreview" then
        button._readyGlowActive = false
    elseif previewFlag == "_keyPressHighlightPreview" then
        button._keyPressHighlightActive = nil
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
    if self.ClearAllReadyGlowPreviews then
        self:ClearAllReadyGlowPreviews()
    end
    if self.ClearAllKeyPressHighlightPreviews then
        self:ClearAllKeyPressHighlightPreviews()
    end
    if self.ClearAllBarAuraActivePreviews then
        self:ClearAllBarAuraActivePreviews()
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
    if self.ClearAllAuraTexturePickerPreviews then
        self:ClearAllAuraTexturePickerPreviews()
    end
    if self.StopCastBarPreview then
        self:StopCastBarPreview()
    end
    if self.StopResourceBarPreview then
        self:StopResourceBarPreview()
    end
end
