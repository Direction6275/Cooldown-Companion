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
local wipe = wipe

-- Some talent swaps briefly report pre-final spell charge state. Coalesce a
-- delayed second pass so charge flags settle without duplicate refresh storms.
local pendingTalentChargeRefreshToken = 0

-- Coalesce rapid-fire ACTIONBAR_SLOT_CHANGED events (e.g. modifier-reactive
-- macros changing many slots simultaneously) into a single rebuild pass.
-- Same token pattern as QueueTalentChargeRefresh.
local pendingSlotChangeToken = 0
local pendingSlotChangedSlots = {}

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
                -- Base spell may lack charges when the override has them
                -- (e.g. Primal Strike base → Stormstrike with 2 charges).
                local chargeQueryID = buttonData.id
                if not chargeInfo then
                    local overrideID = C_Spell.GetOverrideSpell(buttonData.id)
                    if overrideID and overrideID ~= 0 and overrideID ~= buttonData.id then
                        chargeInfo = C_Spell.GetSpellCharges(overrideID)
                        chargeQueryID = overrideID
                    end
                end
                local hasRealCharges = buttonData.hasCharges and true or nil
                local hadDisplayCountBehavior = (buttonData._hasDisplayCount == true or hasRealCharges == true)
                buttonData._castCountCandidate = nil
                buttonData._castCountConfirmed = nil
                buttonData._castCountSeeded = nil
                buttonData._castCountSelf = nil
                buttonData._castCountEventSpellID = nil
                if chargeInfo then
                    buttonData._hasDisplayCount = nil
                    local mc = chargeInfo.maxCharges
                    if mc > 1 then
                        hasRealCharges = true
                        if mc > (buttonData.maxCharges or 0) then
                            buttonData.maxCharges = mc
                        end
                        -- Auto-enable charge text when first promoted to charge-based.
                        if buttonData.showChargeText == nil then
                            buttonData.showChargeText = true
                        end

                        -- Secondary source: display count
                        local rawDisplayCount = C_Spell.GetSpellDisplayCount(chargeQueryID)
                        if not issecretvalue(rawDisplayCount) then
                            local displayCount = tonumber(rawDisplayCount)
                            if displayCount and displayCount > (buttonData.maxCharges or 0) then
                                buttonData.maxCharges = displayCount
                            end
                        end
                    else
                        hasRealCharges = nil
                        -- Reset stored maxCharges to reflect the current API value
                        -- (e.g. after Strafing Run buff fades, maxCharges returns from 2 to 1).
                        buttonData.maxCharges = mc
                    end
                else
                    -- chargeInfo nil: check if spell has "use count" (brez shared
                    -- pool, etc.). GetSpellDisplayCount returns "" when inactive,
                    -- "N" when the pool is active.
                    hasRealCharges = nil
                    self._hasDisplayCountCandidates = true
                    local rawDisplayCount = C_Spell.GetSpellDisplayCount(chargeQueryID)
                    if not issecretvalue(rawDisplayCount) then
                        local displayCount = tonumber(rawDisplayCount)
                        if displayCount ~= nil then
                            buttonData._hasDisplayCount = true
                            if displayCount > (buttonData.maxCharges or 0) then
                                buttonData.maxCharges = displayCount
                            end
                        else
                            buttonData._hasDisplayCount = nil
                        end
                    elseif hadDisplayCountBehavior then
                        -- Preserve legacy display-count classification when the
                        -- API is secret during refresh (e.g. /reload into combat)
                        -- so the button does not temporarily fall out of the
                        -- count-bearing path until the value becomes readable.
                        buttonData._hasDisplayCount = true
                    end
                    -- Auto-enable count text when a spell exposes a readable display count.
                    if buttonData._hasDisplayCount and buttonData.showChargeText == nil then
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
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnRestingChanged()
    self._isResting = IsResting()
    self:RefreshAllGroupsVisibilityOnly()
    self:RefreshConfigPanel()
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
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnPetBattleEnd()
    self._inPetBattle = false
    self:RefreshAllGroupsVisibilityOnly()
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnVehicleUIChanged(event, unit)
    if unit and unit ~= "player" then return end
    self._inVehicleUI = UnitHasVehicleUI("player")
        or C_ActionBar.HasVehicleActionBar()
        or C_ActionBar.HasOverrideActionBar()
    self:RefreshAllGroupsVisibilityOnly()
    self:RefreshConfigPanel()
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
        self:BuildViewerAuraMap()
        if isFullInit then
            self:RefreshAllGroups()
        else
            self:RefreshAllGroupsVisibilityOnly()
        end
        self:ApplyCdmAlpha()
        if isFullInit then
            self:RebuildSlotMapping()
            self:RebuildItemSlotCache()
            self:OnKeybindsChanged()
        end
        -- Delayed second pass: talent-dependent charge data (e.g. Hover,
        -- Keg Smash) may not be resolved when RefreshChargeFlags runs
        -- above.  A coalesced recheck catches late-loading talent state.
        -- Only on full init — zone transitions use the visibility-only
        -- fast path and must not schedule a full button repopulation.
        if isFullInit then
            QueueTalentChargeRefresh(self)
        end
    end)
    -- Post-login sweep: clear buttons falsely stuck as aura-active from stale
    -- CDM viewer data during the first seconds after login/reload.
    if isFullInit then
        C_Timer.After(2, function()
            self:ForEachButton(function(button, bd)
                if bd.auraTracking and button._auraActive and not bd.isPassive then
                    -- Mirror the tick code's viewer resolution order:
                    -- cdmChildSlot → ResolveBuffViewerFrameForSpell
                    local vf
                    if bd.cdmChildSlot then
                        local allChildren = self.viewerAuraAllChildren[bd.id]
                        if allChildren then
                            vf = allChildren[bd.cdmChildSlot]
                        end
                    end
                    if not vf and button._auraSpellID then
                        vf = self:ResolveBuffViewerFrameForSpell(button._auraSpellID)
                    end
                    -- Confirm via auraInstanceID, viewer cooldown widget, or totem slot
                    local viewerConfirms = vf and (vf.auraInstanceID ~= nil)
                    if not viewerConfirms and vf then
                        local vc = vf.Cooldown
                        if vc and vc:IsShown() then
                            viewerConfirms = true
                        elseif vf.preferredTotemUpdateSlot and vf:IsVisible() then
                            viewerConfirms = true
                        end
                    end
                    if not viewerConfirms then
                        local unit = button._auraUnit or "player"
                        local apiConfirms = false
                        if unit == "player" and button._auraSpellID then
                            apiConfirms = C_UnitAuras.GetPlayerAuraBySpellID(button._auraSpellID) ~= nil
                        elseif unit == "target" and UnitExists("target") and button._auraInstanceID then
                            apiConfirms = C_UnitAuras.GetAuraDuration("target", button._auraInstanceID) ~= nil
                        end
                        if not apiConfirms then
                            button._auraActive = false
                            button._auraInstanceID = nil
                            button._auraUnit = bd.auraUnit or "player"
                            button._inPandemic = false
                            button._durationObj = nil
                            button.cooldown:SetCooldown(0, 0)
                            button.cooldown:Hide()
                        end
                    end
                end
            end)
            self._cooldownsDirty = true
        end)
    end
end

function CooldownCompanion:OnBindingsChanged()
    self:RebuildAddonSlotBindings()
    self:OnKeybindsChanged()
end

function CooldownCompanion:OnActionBarSlotChanged(_, slot)
    -- Coalesce: modifier-reactive macros fire this event per affected slot in
    -- the same frame. Accumulate slots and defer the rebuild to next frame so
    -- N simultaneous changes collapse into one pass.
    if slot then
        pendingSlotChangedSlots[slot] = true
    else
        pendingSlotChangedSlots._fullRebuild = true
    end
    pendingSlotChangeToken = pendingSlotChangeToken + 1
    local token = pendingSlotChangeToken
    C_Timer.After(0, function()
        if pendingSlotChangeToken ~= token then return end
        self:RebuildSlotMapping()
        if pendingSlotChangedSlots._fullRebuild then
            self:RebuildItemSlotCache()
        else
            for s in pairs(pendingSlotChangedSlots) do
                self:UpdateItemSlotCache(s)
            end
        end
        wipe(pendingSlotChangedSlots)
        self:RebuildAddonSlotBindings()
        self:OnKeybindsChanged()
    end)
end

function CooldownCompanion:OnActionBarLayoutChanged()
    self:RebuildSlotMapping()
    self:RebuildItemSlotCache()
    self:RebuildAddonSlotBindings()
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
