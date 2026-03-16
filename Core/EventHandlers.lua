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

-- Some talent swaps briefly report pre-final spell charge state. Coalesce a
-- delayed second pass so charge flags settle without duplicate refresh storms.
local pendingTalentChargeRefreshToken = 0

local function QueueTalentChargeRefresh(addon)
    pendingTalentChargeRefreshToken = pendingTalentChargeRefreshToken + 1
    local token = pendingTalentChargeRefreshToken
    C_Timer.After(0.2, function()
        if pendingTalentChargeRefreshToken ~= token then return end
        addon:RefreshChargeFlags("spell")
        addon:RefreshAllGroups()
        addon:RefreshConfigPanel()
    end)
end

function CooldownCompanion:OnSpellUpdateIcon()
    self:ForEachButton(function(button, bd)
        if bd.cdmChildSlot then
            button._iconDirty = true
        else
            self:UpdateButtonIcon(button)
        end
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
    self:RebuildTalentNodeCache()
    self:RefreshChargeFlags("spell")
    self:RefreshAllGroups()
    self:ApplyResourceBars()
    self:UpdateAnchorStacking()
    self:RefreshConfigPanel()
    QueueTalentChargeRefresh(self)
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
-- Treat a spell as charge-based only when max charges is greater than 1.
function CooldownCompanion:RefreshChargeFlags(typeFilter)
    if typeFilter ~= "item" then
        self._hasDisplayCountCandidates = false
    end
    for _, group in pairs(self.db.profile.groups) do
        for _, buttonData in ipairs(group.buttons) do
            if buttonData.type == "spell" and typeFilter ~= "item" then
                local chargeInfo = C_Spell.GetSpellCharges(buttonData.id)
                local hasRealCharges = buttonData.hasCharges and true or nil
                if chargeInfo then
                    buttonData._castCountCandidate = nil
                    local mc = chargeInfo.maxCharges
                    if mc and not issecretvalue(mc) then
                        if mc > 1 then
                            hasRealCharges = true
                            if mc > (buttonData.maxCharges or 0) then
                                buttonData.maxCharges = mc
                            end

                            -- Secondary source: display count
                            local rawDisplayCount = C_Spell.GetSpellDisplayCount(buttonData.id)
                            if not issecretvalue(rawDisplayCount) then
                                local displayCount = tonumber(rawDisplayCount)
                                if displayCount and displayCount > (buttonData.maxCharges or 0) then
                                    buttonData.maxCharges = displayCount
                                end
                            end
                        else
                            hasRealCharges = nil
                        end
                    elseif issecretvalue(mc) then
                        -- maxCharges is secret: can't distinguish mc=1 (not charge-based)
                        -- from mc>1 (charge-based). Preserve existing classification from
                        -- the DB (line 102 initializes hasRealCharges from buttonData.hasCharges).
                        -- A later re-evaluation when values become readable
                        -- (OnTalentsChanged, OnSpecChanged, QueueTalentChargeRefresh)
                        -- will resolve this correctly.
                    end
                else
                    -- chargeInfo nil: check if spell has "use count" (brez shared
                    -- pool, etc.). GetSpellDisplayCount returns "" when inactive,
                    -- "N" when the pool is active.
                    self._hasDisplayCountCandidates = true
                    -- Promote or demote cast-count candidate based on readable
                    -- cast count.  SPELL_UPDATE_USES is the primary authority
                    -- for identification (Lifecycle.lua), but we clear stale
                    -- flags here when a readable zero is observed.  Clearing is
                    -- safe: at 0 stacks the display is suppressed anyway (gated
                    -- by IsSpellUsable), and SPELL_UPDATE_USES will re-flag
                    -- the spell when stacks return.
                    local castCount = C_Spell.GetSpellCastCount(buttonData.id)
                    if not issecretvalue(castCount) and castCount and castCount > 0 then
                        buttonData._castCountCandidate = true
                    elseif not issecretvalue(castCount) then
                        buttonData._castCountCandidate = nil
                    end
                    local rawDisplayCount = C_Spell.GetSpellDisplayCount(buttonData.id)
                    if not issecretvalue(rawDisplayCount) then
                        local displayCount = tonumber(rawDisplayCount)
                        if displayCount and displayCount > 0 then
                            hasRealCharges = true
                            if displayCount > (buttonData.maxCharges or 0) then
                                buttonData.maxCharges = displayCount
                            end
                        elseif displayCount == 0 then
                            -- Pool active but all charges spent; keep charge mode
                            -- so zero-state color/visibility still applies.
                            hasRealCharges = true
                        else
                            -- tonumber("") => nil: pool truly inactive.
                            hasRealCharges = nil
                        end
                    end
                    -- Auto-enable charge text when first detected as display-count.
                    if hasRealCharges and buttonData.showChargeText == nil then
                        buttonData.showChargeText = true
                    end
                end
                buttonData.hasCharges = hasRealCharges
            elseif buttonData.type == "item" and typeFilter ~= "spell" then
                -- Never clear hasCharges for items: at 0 charges both count APIs
                -- return 0, indistinguishable from "item not owned".
                local plainCount = C_Item.GetItemCount(buttonData.id)
                local chargeCount = C_Item.GetItemCount(buttonData.id, false, true)
                if not issecretvalue(plainCount) and not issecretvalue(chargeCount) then
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
    self:RebuildTalentNodeCache()
    self:RefreshChargeFlags()
    self:RefreshAllGroups()
    self:EvaluateResourceBars()
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
    self._inPetBattle = C_PetBattles.IsInBattle()
    self._inVehicleUI = UnitHasVehicleUI("player")
        or C_ActionBar.HasVehicleActionBar()
        or C_ActionBar.HasOverrideActionBar()
end

function CooldownCompanion:OnZoneChanged()
    self:CachePlayerState()
    self:RefreshAllGroupsVisibilityOnly()
end

function CooldownCompanion:OnRestingChanged()
    self._isResting = IsResting()
    self:RefreshAllGroupsVisibilityOnly()
end

function CooldownCompanion:OnMountDisplayChanged()
    self:InvalidateMountAlphaCache()
end

function CooldownCompanion:OnNewMountAdded()
    self:InvalidateMountAlphaCache()
end

function CooldownCompanion:OnPetBattleStart()
    self._inPetBattle = true
    self:RefreshAllGroupsVisibilityOnly()
end

function CooldownCompanion:OnPetBattleEnd()
    self._inPetBattle = false
    self:RefreshAllGroupsVisibilityOnly()
end

function CooldownCompanion:OnVehicleUIChanged(event, unit)
    if unit and unit ~= "player" then return end
    self._inVehicleUI = UnitHasVehicleUI("player")
        or C_ActionBar.HasVehicleActionBar()
        or C_ActionBar.HasOverrideActionBar()
    self:RefreshAllGroupsVisibilityOnly()
end

function CooldownCompanion:OnHeroTalentChanged()
    self._currentHeroSpecId = C_ClassTalents.GetActiveHeroTalentSpec()
    self:RebuildTalentNodeCache()
    self:RefreshChargeFlags("spell")
    self:RefreshAllGroups()
    self:ApplyResourceBars()
    self:UpdateAnchorStacking()
    self:RefreshConfigPanel()
    QueueTalentChargeRefresh(self)
end

function CooldownCompanion:OnPlayerEnteringWorld(event, isInitialLogin, isReloadingUi)
    local isFullInit = isInitialLogin or isReloadingUi
    C_Timer.After(1, function()
        self:CachePlayerState()
        self:CacheCurrentSpec()
        self:RebuildTalentNodeCache()
        self:InvalidateMountAlphaCache()
        self:RefreshChargeFlags()
        if isFullInit then
            self:RefreshAllGroups()
        else
            self:RefreshAllGroupsVisibilityOnly()
        end
        self:BuildViewerAuraMap()
        self:ApplyCdmAlpha()
        if isFullInit then
            self:RebuildSlotMapping()
            self:RebuildItemSlotCache()
            self:OnKeybindsChanged()
        end
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
    else
        self:RebuildItemSlotCache()
    end
    self:OnKeybindsChanged()
end

function CooldownCompanion:OnActionBarLayoutChanged()
    self:RebuildSlotMapping()
    self:RebuildItemSlotCache()
    self:OnKeybindsChanged()
    -- UPDATE_OVERRIDE_ACTIONBAR / UPDATE_VEHICLE_ACTIONBAR also route here for
    -- keybind rebuilds; piggyback vehicle UI state check to avoid duplicate
    -- AceEvent registrations (AceEvent allows only one handler per event).
    local wasInVehicleUI = self._inVehicleUI
    self._inVehicleUI = UnitHasVehicleUI("player")
        or C_ActionBar.HasVehicleActionBar()
        or C_ActionBar.HasOverrideActionBar()
    if self._inVehicleUI ~= wasInVehicleUI then
        self:RefreshAllGroupsVisibilityOnly()
    end
end

------------------------------------------------------------------------
-- Stacking coordination (CastBar + ResourceBars on same anchor group)
------------------------------------------------------------------------
local pendingStackUpdate = false

function CooldownCompanion:UpdateAnchorStacking()
    if pendingStackUpdate then return end
    pendingStackUpdate = true
    C_Timer.After(0, function()
        pendingStackUpdate = false
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:EvaluateCastBar()
    end)
end
