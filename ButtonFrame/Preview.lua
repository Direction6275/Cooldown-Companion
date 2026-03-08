--[[
    CooldownCompanion - ButtonFrame/Preview
    Config panel preview methods for proc glow, aura glow, bar aura effect, and pandemic
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Imports from Glows
local SetBarAuraEffect = ST._SetBarAuraEffect

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local C_Timer_After = C_Timer.After

-- Group-scoped token map used to invalidate older 3-second proc preview callbacks.
local procPreviewTokens = {}
-- Button-scoped token map used to invalidate older per-button proc preview callbacks.
local procButtonPreviewTokens = {}
local auraPreviewTokens = {}
local auraButtonPreviewTokens = {}
local pandemicPreviewTokens = {}
local pandemicButtonPreviewTokens = {}
local readyPreviewTokens = {}
local readyButtonPreviewTokens = {}

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

-- Set or clear proc glow preview on a specific button.
-- Used by the config panel to show what the glow looks like.
function CooldownCompanion:SetProcGlowPreview(groupId, buttonIndex, show)
    if not show then
        BumpButtonPreviewToken(procButtonPreviewTokens, groupId, buttonIndex)
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._procGlowPreview = show or nil
            button._procGlowActive = false -- force SetProcGlow cache miss (including off->off path)
            if button.UpdateCooldown then
                button:UpdateCooldown()
            end
            return
        end
    end
end

-- Clear all proc glow previews across every group.
function CooldownCompanion:ClearAllProcGlowPreviews()
    procPreviewTokens = {}
    procButtonPreviewTokens = {}
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._procGlowPreview = nil
            button._procGlowActive = false -- ensure HideGlowStyles runs on next update
            if button.UpdateCooldown then
                button:UpdateCooldown()
            end
        end
    end
end

-- Set or clear proc glow preview for every button in a group.
function CooldownCompanion:SetGroupProcGlowPreview(groupId, show)
    procButtonPreviewTokens[groupId] = nil
    if not show then
        procPreviewTokens[groupId] = (procPreviewTokens[groupId] or 0) + 1
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        button._procGlowPreview = show or nil
        button._procGlowActive = false -- force SetProcGlow cache miss (including off->off path)
        if button.UpdateCooldown then
            button:UpdateCooldown()
        end
    end
end

-- Trigger a timed proc glow preview for a specific button (default: 3 seconds).
function CooldownCompanion:PlayProcGlowPreview(groupId, buttonIndex, durationSeconds)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then
        duration = 3
    end

    local token = BumpButtonPreviewToken(procButtonPreviewTokens, groupId, buttonIndex)
    self:SetProcGlowPreview(groupId, buttonIndex, true)

    C_Timer_After(duration, function()
        local groupTokens = procButtonPreviewTokens[groupId]
        if not groupTokens or groupTokens[buttonIndex] ~= token then return end
        self:SetProcGlowPreview(groupId, buttonIndex, false)
    end)
end

-- Trigger a timed proc glow preview for a whole group (default: 3 seconds).
function CooldownCompanion:PlayGroupProcGlowPreview(groupId, durationSeconds)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then
        duration = 3
    end

    local token = (procPreviewTokens[groupId] or 0) + 1
    procPreviewTokens[groupId] = token

    self:SetGroupProcGlowPreview(groupId, true)

    C_Timer_After(duration, function()
        if procPreviewTokens[groupId] ~= token then return end
        self:SetGroupProcGlowPreview(groupId, false)
    end)
end

-- Set or clear aura glow preview on a specific button.
function CooldownCompanion:SetAuraGlowPreview(groupId, buttonIndex, show)
    if not show then
        BumpButtonPreviewToken(auraButtonPreviewTokens, groupId, buttonIndex)
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._auraGlowPreview = show or nil
            button._auraGlowActive = false
            if button.UpdateCooldown then
                button:UpdateCooldown()
            end
            return
        end
    end
end

-- Set or clear aura glow preview for every button in a group.
function CooldownCompanion:SetGroupAuraGlowPreview(groupId, show)
    auraButtonPreviewTokens[groupId] = nil
    if not show then
        auraPreviewTokens[groupId] = (auraPreviewTokens[groupId] or 0) + 1
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        button._auraGlowPreview = show or nil
        button._auraGlowActive = false
        if button.UpdateCooldown then
            button:UpdateCooldown()
        end
    end
end

-- Trigger a timed aura glow preview for a specific button (default: 3 seconds).
function CooldownCompanion:PlayAuraGlowPreview(groupId, buttonIndex, durationSeconds)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then
        duration = 3
    end

    local token = BumpButtonPreviewToken(auraButtonPreviewTokens, groupId, buttonIndex)
    self:SetAuraGlowPreview(groupId, buttonIndex, true)

    C_Timer_After(duration, function()
        local groupTokens = auraButtonPreviewTokens[groupId]
        if not groupTokens or groupTokens[buttonIndex] ~= token then return end
        self:SetAuraGlowPreview(groupId, buttonIndex, false)
    end)
end

-- Trigger a timed aura glow preview for a whole group (default: 3 seconds).
function CooldownCompanion:PlayGroupAuraGlowPreview(groupId, durationSeconds)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then
        duration = 3
    end

    local token = (auraPreviewTokens[groupId] or 0) + 1
    auraPreviewTokens[groupId] = token

    self:SetGroupAuraGlowPreview(groupId, true)

    C_Timer_After(duration, function()
        if auraPreviewTokens[groupId] ~= token then return end
        self:SetGroupAuraGlowPreview(groupId, false)
    end)
end

-- Clear all aura glow previews across every group.
function CooldownCompanion:ClearAllAuraGlowPreviews()
    auraPreviewTokens = {}
    auraButtonPreviewTokens = {}
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._auraGlowPreview = nil
            button._auraGlowActive = false
            if button.UpdateCooldown then
                button:UpdateCooldown()
            end
        end
    end
end

-- Set or clear bar aura effect preview on a specific button.
function CooldownCompanion:SetBarAuraEffectPreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._barAuraEffectPreview = show or nil
            if not show then
                -- Call directly — cache still holds old state so the
                -- mismatch will trigger the hide path inside SetBarAuraEffect
                SetBarAuraEffect(button, button._auraActive)
            else
                button._barAuraEffectActive = nil -- force re-evaluate on next tick
            end
            return
        end
    end
end

-- Set or clear pandemic preview on a specific button.
function CooldownCompanion:SetPandemicPreview(groupId, buttonIndex, show)
    if not show then
        BumpButtonPreviewToken(pandemicButtonPreviewTokens, groupId, buttonIndex)
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._pandemicPreview = show or nil
            button._auraGlowActive = false
            if not show then
                -- Call directly — cache still holds old state so the
                -- mismatch will trigger the hide path inside SetBarAuraEffect
                SetBarAuraEffect(button, button._auraActive)
            else
                button._barAuraEffectActive = nil -- force re-evaluate on next tick
            end
            if button.UpdateCooldown then
                button:UpdateCooldown()
            end
            return
        end
    end
end

-- Set or clear pandemic preview for every button in a group.
function CooldownCompanion:SetGroupPandemicPreview(groupId, show)
    pandemicButtonPreviewTokens[groupId] = nil
    if not show then
        pandemicPreviewTokens[groupId] = (pandemicPreviewTokens[groupId] or 0) + 1
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        button._pandemicPreview = show or nil
        button._auraGlowActive = false
        if not show then
            SetBarAuraEffect(button, button._auraActive)
        else
            button._barAuraEffectActive = nil
        end
        if button.UpdateCooldown then
            button:UpdateCooldown()
        end
    end
end

-- Trigger a timed pandemic preview for a specific button (default: 3 seconds).
function CooldownCompanion:PlayPandemicPreview(groupId, buttonIndex, durationSeconds)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then
        duration = 3
    end

    local token = BumpButtonPreviewToken(pandemicButtonPreviewTokens, groupId, buttonIndex)
    self:SetPandemicPreview(groupId, buttonIndex, true)

    C_Timer_After(duration, function()
        local groupTokens = pandemicButtonPreviewTokens[groupId]
        if not groupTokens or groupTokens[buttonIndex] ~= token then return end
        self:SetPandemicPreview(groupId, buttonIndex, false)
    end)
end

-- Trigger a timed pandemic preview for a whole group (default: 3 seconds).
function CooldownCompanion:PlayGroupPandemicPreview(groupId, durationSeconds)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then
        duration = 3
    end

    local token = (pandemicPreviewTokens[groupId] or 0) + 1
    pandemicPreviewTokens[groupId] = token

    self:SetGroupPandemicPreview(groupId, true)

    C_Timer_After(duration, function()
        if pandemicPreviewTokens[groupId] ~= token then return end
        self:SetGroupPandemicPreview(groupId, false)
    end)
end

-- Clear all pandemic previews across every group.
function CooldownCompanion:ClearAllPandemicPreviews()
    pandemicPreviewTokens = {}
    pandemicButtonPreviewTokens = {}
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._pandemicPreview = nil
            button._auraGlowActive = false
            SetBarAuraEffect(button, button._auraActive)
            if button.UpdateCooldown then
                button:UpdateCooldown()
            end
        end
    end
end

-- Set or clear ready glow preview on a specific button.
function CooldownCompanion:SetReadyGlowPreview(groupId, buttonIndex, show)
    if not show then
        BumpButtonPreviewToken(readyButtonPreviewTokens, groupId, buttonIndex)
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._readyGlowPreview = show or nil
            button._readyGlowActive = false
            if button.UpdateCooldown then
                button:UpdateCooldown()
            end
            return
        end
    end
end

-- Set or clear ready glow preview for every button in a group.
function CooldownCompanion:SetGroupReadyGlowPreview(groupId, show)
    readyButtonPreviewTokens[groupId] = nil
    if not show then
        readyPreviewTokens[groupId] = (readyPreviewTokens[groupId] or 0) + 1
    end
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        button._readyGlowPreview = show or nil
        button._readyGlowActive = false
        if button.UpdateCooldown then
            button:UpdateCooldown()
        end
    end
end

-- Trigger a timed ready glow preview for a specific button (default: 3 seconds).
function CooldownCompanion:PlayReadyGlowPreview(groupId, buttonIndex, durationSeconds)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then
        duration = 3
    end

    local token = BumpButtonPreviewToken(readyButtonPreviewTokens, groupId, buttonIndex)
    self:SetReadyGlowPreview(groupId, buttonIndex, true)

    C_Timer_After(duration, function()
        local groupTokens = readyButtonPreviewTokens[groupId]
        if not groupTokens or groupTokens[buttonIndex] ~= token then return end
        self:SetReadyGlowPreview(groupId, buttonIndex, false)
    end)
end

-- Trigger a timed ready glow preview for a whole group (default: 3 seconds).
function CooldownCompanion:PlayGroupReadyGlowPreview(groupId, durationSeconds)
    local duration = tonumber(durationSeconds) or 3
    if duration <= 0 then
        duration = 3
    end

    local token = (readyPreviewTokens[groupId] or 0) + 1
    readyPreviewTokens[groupId] = token

    self:SetGroupReadyGlowPreview(groupId, true)

    C_Timer_After(duration, function()
        if readyPreviewTokens[groupId] ~= token then return end
        self:SetGroupReadyGlowPreview(groupId, false)
    end)
end

-- Clear all ready glow previews across every group.
function CooldownCompanion:ClearAllReadyGlowPreviews()
    readyPreviewTokens = {}
    readyButtonPreviewTokens = {}
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._readyGlowPreview = nil
            button._readyGlowActive = false
            if button.UpdateCooldown then
                button:UpdateCooldown()
            end
        end
    end
end

-- Invalidate ready glow cache on all buttons in a group.
function CooldownCompanion:InvalidateGroupReadyGlow(groupId)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        button._readyGlowActive = nil
    end
end

-- Invalidate ready glow cache on a specific button so the next tick re-applies.
function CooldownCompanion:InvalidateReadyGlow(groupId, buttonIndex)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._readyGlowActive = nil
            return
        end
    end
end

-- Invalidate bar aura effect cache on a specific button so the next tick re-applies.
function CooldownCompanion:InvalidateBarAuraEffect(groupId, buttonIndex)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._barAuraEffectActive = nil
            return
        end
    end
end

-- Invalidate aura glow cache on a specific button so the next tick re-applies.
-- Used by config sliders to update glow appearance without recreating buttons.
function CooldownCompanion:InvalidateAuraGlow(groupId, buttonIndex)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._auraGlowActive = nil
            return
        end
    end
end

-- Invalidate proc glow cache on all buttons in a group.
-- Used by the proc glow size/color sliders to update without recreating buttons.
function CooldownCompanion:InvalidateGroupProcGlow(groupId)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        button._procGlowActive = nil
    end
end

-- Invalidate proc glow cache on a specific button so the next tick re-applies.
-- Used by per-button config sliders to update glow appearance without recreating buttons.
function CooldownCompanion:InvalidateProcGlow(groupId, buttonIndex)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._procGlowActive = nil
            return
        end
    end
end
