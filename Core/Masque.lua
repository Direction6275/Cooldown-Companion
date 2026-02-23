--[[
    CooldownCompanion - Core/Masque.lua: All Masque skinning functions
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local Masque = CooldownCompanion.Masque
local MasqueGroups = CooldownCompanion.MasqueGroups

local ipairs = ipairs
local tostring = tostring

-- Masque Helper Functions
function CooldownCompanion:CreateMasqueGroup(groupId)
    if not Masque then return end
    local group = self.db.profile.groups[groupId]
    if not group then return end

    -- Use groupId as the static ID so Masque settings persist across sessions
    local masqueGroup = Masque:Group(ADDON_NAME, group.name or ("Group " .. groupId), tostring(groupId))
    MasqueGroups[groupId] = masqueGroup
    return masqueGroup
end

function CooldownCompanion:DeleteMasqueGroup(groupId)
    if not Masque then return end
    local masqueGroup = MasqueGroups[groupId]
    if masqueGroup then
        masqueGroup:Delete()
        MasqueGroups[groupId] = nil
    end
end

function CooldownCompanion:GetMasqueRegions(button)
    -- Return the regions table Masque needs for skinning
    -- CC buttons are plain Frames, so we must explicitly pass regions
    return {
        Icon = button.icon,
        Cooldown = button.cooldown,
        Count = button.count,
    }
end

function CooldownCompanion:AddButtonToMasque(groupId, button)
    if not Masque then return end
    local masqueGroup = MasqueGroups[groupId]
    if not masqueGroup then return end

    local regions = self:GetMasqueRegions(button)
    -- Type "Action" is standard for action-bar-like buttons
    -- Strict=true tells Masque to only use the regions we provide
    masqueGroup:AddButton(button, regions, "Action", true)

    -- Hide CC's custom border/bg when Masque is active
    self:SetButtonBorderVisible(button, false)
end

function CooldownCompanion:RemoveButtonFromMasque(groupId, button)
    if not Masque then return end
    local masqueGroup = MasqueGroups[groupId]
    if not masqueGroup then return end

    masqueGroup:RemoveButton(button)

    -- Restore CC's custom border/bg
    self:SetButtonBorderVisible(button, true)
end

function CooldownCompanion:SetButtonBorderVisible(button, visible)
    if not button then return end

    -- Show/hide background
    if button.bg then
        if visible then
            button.bg:Show()
        else
            button.bg:Hide()
        end
    end

    -- Show/hide border textures
    if button.borderTextures then
        for _, tex in ipairs(button.borderTextures) do
            if visible then
                tex:Show()
            else
                tex:Hide()
            end
        end
    end
end

function CooldownCompanion:ToggleGroupMasque(groupId, enable)
    if not Masque then return end

    local group = self.db.profile.groups[groupId]
    if not group then return end

    group.masqueEnabled = enable

    if enable then
        -- Force square icons when Masque is enabled (non-square causes stretching)
        group.style.maintainAspectRatio = true

        -- Create Masque group if it doesn't exist
        if not MasqueGroups[groupId] then
            self:CreateMasqueGroup(groupId)
        end
        -- Add all existing buttons to Masque
        local frame = self.groupFrames[groupId]
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                self:AddButtonToMasque(groupId, button)
            end
        end
    else
        -- Remove all buttons from Masque and restore borders
        local frame = self.groupFrames[groupId]
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                self:RemoveButtonFromMasque(groupId, button)
            end
        end
        -- Delete the Masque group
        self:DeleteMasqueGroup(groupId)
    end
end
