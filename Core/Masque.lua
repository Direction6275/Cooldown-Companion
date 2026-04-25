--[[
    CooldownCompanion - Core/Masque.lua: All Masque skinning functions
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local MasqueGroups = CooldownCompanion.MasqueGroups

local ipairs = ipairs
local tostring = tostring

local function DeleteMasqueGroupByStaticId(staticId)
    local masqueGroup = MasqueGroups[staticId]
    if masqueGroup then
        masqueGroup:Delete()
        MasqueGroups[staticId] = nil
    end
end

-- Masque Helper Functions
function CooldownCompanion:GetMasqueStaticId(groupId)
    -- Keep the legacy panel ID so existing Masque settings continue to apply.
    return tostring(groupId)
end

function CooldownCompanion:IsGroupMasqueActive(groupId, group)
    if not self.Masque then return false end

    group = group or (self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId])
    return group and group.masqueEnabled == true and group.displayMode == "icons"
end

function CooldownCompanion:CreateMasqueGroup(groupId)
    if not self.Masque then return end
    local group = self.db.profile.groups[groupId]
    if not group then return end
    if group.style then
        group.style.maintainAspectRatio = true
    end

    local staticId = self:GetMasqueStaticId(groupId)
    self._masqueGroupKeys = self._masqueGroupKeys or {}

    local masqueGroup = self.Masque:Group(ADDON_NAME, group.name or ("Group " .. groupId), staticId)
    MasqueGroups[staticId] = masqueGroup
    self._masqueGroupKeys[groupId] = staticId
    return masqueGroup
end

function CooldownCompanion:DeleteMasqueGroup(groupId)
    if not self.Masque then return end
    local staticId = self:GetMasqueStaticId(groupId)
    local oldStaticId = self._masqueGroupKeys and self._masqueGroupKeys[groupId]

    DeleteMasqueGroupByStaticId(staticId)
    if oldStaticId and oldStaticId ~= staticId then
        DeleteMasqueGroupByStaticId(oldStaticId)
    end

    if self._masqueGroupKeys then
        self._masqueGroupKeys[groupId] = nil
    end
end

function CooldownCompanion:UnregisterMasqueGroup(groupId)
    if not self.Masque then return end
    local staticId = self:GetMasqueStaticId(groupId)
    local oldStaticId = self._masqueGroupKeys and self._masqueGroupKeys[groupId]

    MasqueGroups[staticId] = nil
    if oldStaticId and oldStaticId ~= staticId then
        MasqueGroups[oldStaticId] = nil
    end

    if self._masqueGroupKeys then
        self._masqueGroupKeys[groupId] = nil
    end
end

function CooldownCompanion:DeactivateGroupMasqueRuntime(groupId)
    if not self.Masque then return end
    local frame = self.groupFrames and self.groupFrames[groupId]
    if frame and frame.buttons then
        for _, button in ipairs(frame.buttons) do
            if button._masqueStaticId then
                self:RemoveButtonFromMasque(groupId, button)
            end
        end
    end
    self:UnregisterMasqueGroup(groupId)
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
    if not self:IsGroupMasqueActive(groupId) then return end
    local staticId = self:GetMasqueStaticId(groupId)
    local masqueGroup = MasqueGroups[staticId]
    if not masqueGroup then return end

    local regions = self:GetMasqueRegions(button)
    -- Type "Action" is standard for action-bar-like buttons
    -- Strict=true tells Masque to only use the regions we provide
    masqueGroup:AddButton(button, regions, "Action", true)
    button._masqueStaticId = staticId

    -- Hide CC's custom border/bg when Masque is active
    self:SetButtonBorderVisible(button, false)
end

function CooldownCompanion:RemoveButtonFromMasque(groupId, button)
    if not self.Masque or not button then return end
    local staticId = button._masqueStaticId or self:GetMasqueStaticId(groupId)
    local masqueGroup = MasqueGroups[staticId]

    if masqueGroup then
        masqueGroup:RemoveButton(button)
    end
    button._masqueStaticId = nil

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
    local group = self.db.profile.groups[groupId]
    if not group then return end

    group.masqueEnabled = enable

    if not self.Masque then return end

    if enable then
        if not self:IsGroupMasqueActive(groupId, group) then return end

        -- Masque skins assume square icon regions; non-square regions can stretch skin art.
        if group.style then
            group.style.maintainAspectRatio = true
        end

        -- Create Masque group if it doesn't exist
        if not MasqueGroups[self:GetMasqueStaticId(groupId)] then
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
