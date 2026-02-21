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

-- Set or clear proc glow preview on a specific button.
-- Used by the config panel to show what the glow looks like.
function CooldownCompanion:SetProcGlowPreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._procGlowPreview = show or nil
            return
        end
    end
end

-- Clear all proc glow previews across every group.
function CooldownCompanion:ClearAllProcGlowPreviews()
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._procGlowPreview = nil
        end
    end
end

-- Set or clear aura glow preview on a specific button.
function CooldownCompanion:SetAuraGlowPreview(groupId, buttonIndex, show)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._auraGlowPreview = show or nil
            return
        end
    end
end

-- Clear all aura glow previews across every group.
function CooldownCompanion:ClearAllAuraGlowPreviews()
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._auraGlowPreview = nil
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
    local frame = self.groupFrames[groupId]
    if not frame then return end
    for _, button in ipairs(frame.buttons) do
        if button.index == buttonIndex then
            button._pandemicPreview = show or nil
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

-- Clear all pandemic previews across every group.
function CooldownCompanion:ClearAllPandemicPreviews()
    for _, frame in pairs(self.groupFrames) do
        for _, button in ipairs(frame.buttons) do
            button._pandemicPreview = nil
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
