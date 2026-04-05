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

-- Set preview on a single button.
-- cacheValue: false forces cache miss on next tick; nil forces re-evaluate.
local function SetButtonPreview(self, groupId, buttonIndex, show, previewFlag, cacheFlag, cacheValue, buttonTokenStore, onToggle, updateCooldown)
    if buttonTokenStore and not show then
        BumpButtonPreviewToken(buttonTokenStore, groupId, buttonIndex)
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
local function SetGroupPreview(self, groupId, show, previewFlag, cacheFlag, cacheValue, groupTokenStore, buttonTokenStore, onToggle, updateCooldown)
    if buttonTokenStore then buttonTokenStore[groupId] = nil end
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
-- Aura Texture Picker Preview
--------------------------------------------------------------------------------

function CooldownCompanion:SetAuraTexturePickerPreview(groupId, buttonIndex, selection)
    local frame = self.groupFrames[groupId]
    if not frame then
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
