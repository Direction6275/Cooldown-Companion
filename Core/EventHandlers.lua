--[[
    CooldownCompanion - Core/EventHandlers.lua: Remaining event handlers (OnSpellUpdateIcon,
    OnBagChanged, OnTalentsChanged, OnSpecChanged, etc.), anchor stacking
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local select = select

function CooldownCompanion:OnSpellUpdateIcon()
    self:ForEachButton(function(button)
        self:UpdateButtonIcon(button)
    end)
end

function CooldownCompanion:UpdateRangeCheckRegistrations()
    local newSet = {}
    self:ForEachButton(function(button, bd)
        if bd.type == "spell" and not bd.isPassive and button.style and button.style.showOutOfRange then
            newSet[bd.id] = true
        end
    end)
    -- Enable newly needed range checks
    for spellId in pairs(newSet) do
        if not self._rangeCheckSpells[spellId] then
            C_Spell.EnableSpellRangeCheck(spellId, true)
        end
    end
    -- Disable range checks no longer needed
    for spellId in pairs(self._rangeCheckSpells) do
        if not newSet[spellId] then
            C_Spell.EnableSpellRangeCheck(spellId, false)
        end
    end
    self._rangeCheckSpells = newSet
end

function CooldownCompanion:OnSpellRangeCheckUpdate(event, spellIdentifier, isInRange, checksRange)
    local outOfRange = checksRange and not isInRange
    self:ForEachButton(function(button, bd)
        if bd.type == "spell" and bd.id == spellIdentifier then
            button._spellOutOfRange = outOfRange
        end
    end)
end

function CooldownCompanion:OnBagChanged()
    self:RefreshChargeFlags("item")
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnTalentsChanged()
    self._currentHeroSpecId = C_ClassTalents.GetActiveHeroTalentSpec()
    self:RefreshChargeFlags("spell")
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnPetChanged()
    for groupId, _ in pairs(self.db.profile.groups) do
        if self:GroupHasPetSpells(groupId) then
            self:RefreshGroupFrame(groupId)
        end
    end
    self:RefreshConfigPanel()
end

-- Re-evaluate hasCharges on every spell button (talents can add/remove charges).
-- GetSpellCharges returns nil for non-charge spells, a table only for multi-charge spells.
function CooldownCompanion:RefreshChargeFlags(typeFilter)
    for _, group in pairs(self.db.profile.groups) do
        for _, buttonData in ipairs(group.buttons) do
            if buttonData.type == "spell" and typeFilter ~= "item" then
                local chargeInfo = C_Spell.GetSpellCharges(buttonData.id)
                buttonData.hasCharges = chargeInfo and true or nil
                if chargeInfo then
                    local mc = chargeInfo.maxCharges
                    if mc and mc > (buttonData.maxCharges or 0) then
                        buttonData.maxCharges = mc
                    end
                    -- Secondary source: display count
                    local displayCount = tonumber(C_Spell.GetSpellDisplayCount(buttonData.id))
                    if displayCount and displayCount > (buttonData.maxCharges or 0) then
                        buttonData.maxCharges = displayCount
                    end
                end
            elseif buttonData.type == "item" and typeFilter ~= "spell" then
                -- Never clear hasCharges for items: at 0 charges both count APIs
                -- return 0, indistinguishable from "item not owned".
                local plainCount = C_Item.GetItemCount(buttonData.id)
                local chargeCount = C_Item.GetItemCount(buttonData.id, false, true)
                if chargeCount > plainCount then
                    buttonData.hasCharges = true
                    if chargeCount > (buttonData.maxCharges or 0) then
                        buttonData.maxCharges = chargeCount
                    end
                end
            end
        end
    end
end

function CooldownCompanion:CacheCurrentSpec()
    local specIndex = C_SpecializationInfo.GetSpecialization()
    if specIndex then
        local specId = C_SpecializationInfo.GetSpecializationInfo(specIndex)
        self._currentSpecId = specId
    end
    self._currentHeroSpecId = C_ClassTalents.GetActiveHeroTalentSpec()
end

function CooldownCompanion:OnSpecChanged()
    self:CacheCurrentSpec()
    self:RefreshChargeFlags()
    self:EvaluateResourceBars()
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
    -- Rebuild viewer map after a short delay to let the viewer re-populate
    C_Timer.After(1, function()
        self:BuildViewerAuraMap()
    end)
end

function CooldownCompanion:CachePlayerState()
    local inInstance, instanceType = IsInInstance()
    if inInstance and instanceType == "scenario" then
        local _, _, difficultyID = GetInstanceInfo()
        self._currentInstanceType = (difficultyID == 208) and "delve" or "scenario"
    else
        self._currentInstanceType = inInstance and instanceType or "none"
    end
    self._isResting = IsResting()
end

function CooldownCompanion:OnZoneChanged()
    self:CachePlayerState()
    self:RefreshAllGroups()
end

function CooldownCompanion:OnRestingChanged()
    self._isResting = IsResting()
    self:RefreshAllGroups()
end

function CooldownCompanion:OnHeroTalentChanged()
    self._currentHeroSpecId = C_ClassTalents.GetActiveHeroTalentSpec()
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnPlayerEnteringWorld()
    C_Timer.After(1, function()
        self:CachePlayerState()
        self:CacheCurrentSpec()
        self:RefreshChargeFlags()
        self:RefreshAllGroups()
        self:BuildViewerAuraMap()
        self:ApplyCdmAlpha()
        self:RebuildSlotMapping()
        self:RebuildItemSlotCache()
        self:OnKeybindsChanged()
    end)
end

function CooldownCompanion:OnBindingsChanged()
    self:OnKeybindsChanged()
end

function CooldownCompanion:OnActionBarSlotChanged(_, slot)
    -- Rebuild slot mapping since frame .action fields may have changed
    self:RebuildSlotMapping()
    if slot then
        self:UpdateItemSlotCache(slot)
    end
    self:OnKeybindsChanged()
end

------------------------------------------------------------------------
-- Stacking coordination (CastBar + ResourceBars on same anchor group)
------------------------------------------------------------------------
local pendingStackUpdate = false

function CooldownCompanion:GetCastBarHeight()
    local s = self.db and self.db.profile and self.db.profile.castBar
    if not s or not s.enabled then return 0 end
    local groupId = s.anchorGroupId or self:GetFirstAvailableAnchorGroup()
    if not groupId then return 0 end
    local gf = self.groupFrames[groupId]
    if not gf or not gf:IsShown() then return 0 end
    local group = self.db.profile.groups[groupId]
    if not group or group.displayMode ~= "icons" then return 0 end
    return s.stylingEnabled and (s.height or 14) or 11
end

function CooldownCompanion:GetAnchorStackOffset(moduleId)
    local cb = self.db and self.db.profile and self.db.profile.castBar
    local rb = self.db and self.db.profile and self.db.profile.resourceBars
    if not cb or not rb then return 0 end
    if not cb.enabled or not rb.enabled then return 0 end
    local cbAnchor = cb.anchorGroupId or self:GetFirstAvailableAnchorGroup()
    local rbAnchor = rb.anchorGroupId or self:GetFirstAvailableAnchorGroup()
    if not cbAnchor or not rbAnchor then return 0 end
    if cbAnchor ~= rbAnchor then return 0 end

    local cbPos = cb.position or "below"
    local rbPos = rb.position or "below"
    if cbPos ~= rbPos then return 0 end

    local order = rb.stackOrder or "resource_first"

    if moduleId == "castBar" then
        if order == "resource_first" then
            return self:GetResourceBarsTotalHeight()
        end
        return 0
    elseif moduleId == "resourceBars" then
        if order == "cast_first" then
            local cbHeight = self:GetCastBarHeight()
            if cbHeight > 0 then
                return cbHeight + math.abs(cb.yOffset or 0)
            end
        end
        return 0
    end
    return 0
end

function CooldownCompanion:UpdateAnchorStacking()
    if pendingStackUpdate then return end
    pendingStackUpdate = true
    C_Timer.After(0, function()
        pendingStackUpdate = false
        CooldownCompanion:EvaluateCastBar()
        CooldownCompanion:EvaluateResourceBars()
    end)
end
