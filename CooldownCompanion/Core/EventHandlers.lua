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
local pendingSpellAvailabilityRefreshToken = 0

-- Coalesce rapid-fire ACTIONBAR_SLOT_CHANGED events (e.g. modifier-reactive
-- macros changing many slots simultaneously) into a single rebuild pass.
-- Same token pattern as QueueTalentChargeRefresh.
local pendingSlotChangeToken = 0
local pendingSlotChangedSlots = {}
local actionbarSlotSignatures = {}

local function GetActionbarSlotSignature(slot)
    if type(slot) ~= "number" then return nil end
    if not C_ActionBar.HasAction(slot) then return "empty" end
    local actionType, id, subType = GetActionInfo(slot)
    return tostring(actionType) .. "\001" .. tostring(id) .. "\001" .. tostring(subType)
end

local function ActionbarSlotContentChanged(slot)
    local signature = GetActionbarSlotSignature(slot)
    if actionbarSlotSignatures[slot] == signature then
        return false
    end
    actionbarSlotSignatures[slot] = signature
    return true
end

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

local function QueueSpellAvailabilitySettlingRefresh(addon)
    pendingSpellAvailabilityRefreshToken = pendingSpellAvailabilityRefreshToken + 1
    local token = pendingSpellAvailabilityRefreshToken
    C_Timer.After(0.2, function()
        if pendingSpellAvailabilityRefreshToken ~= token then return end
        addon:RefreshSpellAvailabilityState({ skipSettlingRefresh = true })
    end)
end

local function GroupHasEquipmentSlotEntries(group)
    if not (group and group.buttons and CooldownCompanion.IsEquipmentSlotEntry) then
        return false
    end
    for _, buttonData in ipairs(group.buttons) do
        if CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
            return true
        end
    end
    return false
end

function CooldownCompanion:RefreshEquipmentSlotEntries(reason, itemID)
    self:MarkCooldownsDirty()
    if self.db and self.db.profile and self.db.profile.groups then
        for groupId, group in pairs(self.db.profile.groups) do
            if GroupHasEquipmentSlotEntries(group) then
                self:RefreshGroupFrame(groupId)
            end
        end
    end
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnEquipmentChanged(event, equipmentSlot)
    local trinket1 = self.TRINKET_SLOT_1 or 13
    local trinket2 = self.TRINKET_SLOT_2 or 14
    if equipmentSlot == trinket1 or equipmentSlot == trinket2 then
        self:RefreshEquipmentSlotEntries("equipment", nil)
    else
        self:MarkCooldownsDirty()
    end
end

function CooldownCompanion:EnsureEquipmentSlotItemLoadFrame()
    if self._equipmentSlotItemLoadFrame then
        return
    end

    self._equipmentSlotItemLoadFrame = CreateFrame("Frame")
    self._equipmentSlotItemLoadFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    self._equipmentSlotItemLoadFrame:SetScript("OnEvent", function(_, _, itemID, success)
        local pendingLoads = CooldownCompanion._pendingEquipmentSlotItemLoads
        local locationLoadPending = CooldownCompanion._pendingEquipmentSlotLocationLoad == true
        if not locationLoadPending and not (pendingLoads and itemID and pendingLoads[itemID]) then
            return
        end
        if pendingLoads and itemID then
            pendingLoads[itemID] = nil
        end
        CooldownCompanion._pendingEquipmentSlotLocationLoad = nil
        CooldownCompanion:RefreshEquipmentSlotEntries("item-data", itemID)
    end)
end

local function PlayerHasTrackedAuraForButton(button, buttonData)
    if button._activeAuraSpellID and C_UnitAuras.GetPlayerAuraBySpellID(button._activeAuraSpellID) then
        return true
    end

    if buttonData.type == "spell" and buttonData.addedAs == "aura" then
        local orderedAuraIDs = CooldownCompanion:GetOrderedAuraCandidateIDs(buttonData)
        for _, spellID in ipairs(orderedAuraIDs) do
            if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
                return true
            end
        end
        return false
    end

    if buttonData.auraSpellID then
        local includesButtonID
        for id in tostring(buttonData.auraSpellID):gmatch("%d+") do
            local spellID = tonumber(id)
            if spellID then
                if spellID == buttonData.id then
                    includesButtonID = true
                end
                if C_UnitAuras.GetPlayerAuraBySpellID(spellID) then
                    return true
                end
            end
        end
        if not includesButtonID and buttonData.type == "spell" then
            local baseId = C_Spell.GetBaseSpell(buttonData.id)
            if baseId and baseId ~= button._auraSpellID and C_UnitAuras.GetPlayerAuraBySpellID(baseId) then
                return true
            end
        end
        return false
    end

    if buttonData.type ~= "spell" then
        return button._auraSpellID and C_UnitAuras.GetPlayerAuraBySpellID(button._auraSpellID) ~= nil
    end

    local baseId = C_Spell.GetBaseSpell(buttonData.id)
    if baseId and baseId ~= button._auraSpellID and C_UnitAuras.GetPlayerAuraBySpellID(baseId) then
        return true
    end

    return button._auraSpellID and C_UnitAuras.GetPlayerAuraBySpellID(button._auraSpellID) ~= nil
end

function CooldownCompanion:RefreshSpellAvailabilityState(opts)
    opts = opts or {}
    self:CachePlayerState()
    self:CacheCurrentSpec()
    self._currentHeroSpecId = C_ClassTalents.GetActiveHeroTalentSpec()
    self:RebuildTalentNodeCache()
    if opts.refreshAllChargeTypes then
        self:RefreshChargeFlags()
    else
        self:RefreshChargeFlags("spell")
    end
    self:RefreshAllGroupsForSpellAvailability()
    self:RefreshKeybindState()
    self:RefreshConfigPanel()

    if opts.applyResourceBars then
        self:EvaluateBarsAndFramesRuntime("spell-availability-apply")
    elseif opts.evaluateResourceBars then
        self:EvaluateBarsAndFramesRuntime("spell-availability-evaluate")
    end

    if opts.rebuildViewerMap then
        C_Timer.After(1, function()
            self:BuildViewerAuraMap()
        end)
    end

    if not opts.skipSettlingRefresh then
        QueueSpellAvailabilitySettlingRefresh(self)
    end
end

function CooldownCompanion:OnSpellAvailabilityChanged()
    self:RefreshSpellAvailabilityState()
end

function CooldownCompanion:OnPlayerSpecializationChanged(event, unit)
    if unit and unit ~= "player" then return end
    self:OnSpecChanged()
end

function CooldownCompanion:OnSpellsChanged()
    self:OnSpellUpdateIcon()
    self:RefreshSpellAvailabilityState()
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

local function GetRangeCheckSpellID(buttonData)
    if not buttonData then
        return nil
    end
    if buttonData._rotationAssistantVirtual == true then
        return buttonData._rotationAssistantSpellID
    end
    return buttonData.id
end

function CooldownCompanion:UpdateRangeCheckRegistrations()
    local newSet = {}
    self:ForEachButton(function(button, bd)
        local spellID = GetRangeCheckSpellID(bd)
        if spellID
            and bd.type == "spell"
            and not bd.isPassive
            and not bd.isPassiveCooldown
            and ((button.style and button.style.showOutOfRange)
                or (self.TriggerRowUsesCondition and self:TriggerRowUsesCondition(bd, "rangeActive"))) then
            newSet[spellID] = true
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
    local outOfRange = nil
    if checksRange then
        outOfRange = not isInRange
    end
    local changed = false
    self:ForEachButton(function(button, bd)
        local spellID = GetRangeCheckSpellID(bd)
        if bd.type == "spell" and spellID == spellIdentifier then
            if button._spellOutOfRange ~= outOfRange then
                button._spellOutOfRange = outOfRange
                changed = true
            end
        end
    end)
    if changed then
        self:MarkCooldownsDirty()
    end
end

function CooldownCompanion:OnBagChanged()
    self:MarkCooldownsDirty()
    self:RefreshChargeFlags("item")
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnTalentsChanged()
    self:RefreshSpellAvailabilityState({
        applyResourceBars = true,
        skipSettlingRefresh = true,
    })
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

function CooldownCompanion:UpdateSpellChargeMetadata(buttonData, spellID, opts)
    if not (buttonData and buttonData.type == "spell") then
        return
    end

    local chargeInfo, chargeQueryID, maxCharges = ST.ResolveSpellChargeInfo(spellID or buttonData.id)
    local hasRealCharges = buttonData.hasCharges and true or nil
    local hadDisplayCountBehavior = (buttonData._hasDisplayCount == true or hasRealCharges == true)
    local hadCastCountCandidate = (buttonData._castCountCandidate == true)
    local castCountSelf = buttonData._castCountSelf
    local castCountEventSpellID = buttonData._castCountEventSpellID
    buttonData._castCountConfirmed = nil
    buttonData._castCountSeeded = nil

    if chargeInfo then
        buttonData._castCountCandidate = nil
        buttonData._castCountSelf = nil
        buttonData._castCountEventSpellID = nil
        buttonData._hasDisplayCount = nil
        buttonData._displayCountFamily = nil
        local mc = maxCharges or chargeInfo.maxCharges
        if mc and mc > 1 then
            hasRealCharges = true
            if mc ~= buttonData.maxCharges then
                buttonData.maxCharges = mc
            end
            -- Auto-enable charge text when first promoted to charge-based.
            if buttonData.showChargeText == nil then
                buttonData.showChargeText = true
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
                buttonData._displayCountFamily = true
                if displayCount > (buttonData.maxCharges or 0) then
                    buttonData.maxCharges = displayCount
                end
            else
                buttonData._hasDisplayCount = nil
                if opts and opts.clearInactiveMaxCharges then
                    buttonData._displayCountFamily = nil
                end
            end
        elseif hadDisplayCountBehavior then
            -- Preserve legacy display-count classification when the
            -- API is secret during refresh (e.g. /reload into combat)
            -- so the button does not temporarily fall out of the
            -- count-bearing path until the value becomes readable.
            buttonData._hasDisplayCount = true
            buttonData._displayCountFamily = true
        end
        -- Auto-enable count text when a spell exposes a readable display count.
        if buttonData._hasDisplayCount and buttonData.showChargeText == nil then
            buttonData.showChargeText = true
        end
        if buttonData._hasDisplayCount then
            buttonData._castCountCandidate = nil
            buttonData._castCountSelf = nil
            buttonData._castCountEventSpellID = nil
        elseif hadCastCountCandidate then
            buttonData._castCountCandidate = true
            buttonData._castCountSelf = castCountSelf
            buttonData._castCountEventSpellID = castCountEventSpellID
        else
            buttonData._castCountCandidate = nil
            buttonData._castCountSelf = nil
            buttonData._castCountEventSpellID = nil
        end
        if opts and opts.clearInactiveMaxCharges
            and not buttonData._hasDisplayCount
            and not buttonData._displayCountFamily
        then
            buttonData.maxCharges = nil
        end
    end

    buttonData.hasCharges = hasRealCharges
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
                self:UpdateSpellChargeMetadata(buttonData, buttonData.id)
            elseif buttonData.type == "item" and typeFilter ~= "spell" then
                -- Never clear hasCharges for items; unavailable charged items can
                -- be indistinguishable from unowned items through count APIs.
                self.UpdateItemChargeMetadata(buttonData, buttonData.id)
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
    self:RefreshSpellAvailabilityState({
        evaluateResourceBars = true,
        refreshAllChargeTypes = true,
        rebuildViewerMap = true,
    })
end

function CooldownCompanion:CachePlayerState()
    local inInstance, instanceType = IsInInstance()
    local _, reportedInstanceType, difficultyID = GetInstanceInfo()
    local mapID = C_Map.GetBestMapForUnit("player")
    -- Outdoor delves can disagree across APIs, so treat any verified delve signal
    -- as authoritative before falling back to the generic instance classification.
    local isDelve = C_PartyInfo.IsDelveInProgress()
        or (reportedInstanceType == "scenario" and difficultyID == 208)
        or (mapID and C_DelvesUI.HasActiveDelve(mapID))
        or C_DelvesUI.HasActiveDelve()
    if isDelve then
        self._currentInstanceType = "delve"
    elseif inInstance and instanceType == "scenario" then
        self._currentInstanceType = "scenario"
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
    self:RefreshSpellAvailabilityState({ evaluateResourceBars = true })
end

function CooldownCompanion:OnRestingChanged()
    self._isResting = IsResting()
    self:RefreshAllGroupsVisibilityOnly()
    self:EvaluateBarsAndFramesRuntime("resting-changed")
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
    self:EvaluateBarsAndFramesRuntime("pet-battle-start")
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnPetBattleEnd()
    self._inPetBattle = false
    self:RefreshAllGroupsVisibilityOnly()
    self:EvaluateBarsAndFramesRuntime("pet-battle-end")
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnVehicleUIChanged(event, unit)
    if unit and unit ~= "player" then return end
    self._inVehicleUI = UnitHasVehicleUI("player")
        or C_ActionBar.HasVehicleActionBar()
        or C_ActionBar.HasOverrideActionBar()
    self:RefreshAllGroupsVisibilityOnly()
    self:EvaluateBarsAndFramesRuntime("vehicle-ui-changed")
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnHeroTalentChanged()
    self:RefreshSpellAvailabilityState({
        applyResourceBars = true,
        skipSettlingRefresh = true,
    })
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
            self:RefreshAllGroupsForSpellAvailability()
        end
        self:ApplyCdmAlpha()
        if isFullInit then
            self:RefreshKeybindState()
        end
        -- Delayed second pass: talent-dependent charge data (e.g. Hover,
        -- Keg Smash) may not be resolved when RefreshChargeFlags runs
        -- above.  A coalesced recheck catches late-loading talent state.
        -- Full init keeps the talent charge queue. Zone transitions get a
        -- lighter settling pass that rebuilds only if button availability changed.
        if isFullInit then
            QueueTalentChargeRefresh(self)
        else
            QueueSpellAvailabilitySettlingRefresh(self)
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
                            apiConfirms = PlayerHasTrackedAuraForButton(button, bd)
                        elseif unit == "target" and UnitExists("target") and button._auraInstanceID then
                            apiConfirms = C_UnitAuras.GetAuraDuration("target", button._auraInstanceID) ~= nil
                        end
                        if not apiConfirms then
                            button._auraActive = false
                            button._auraInstanceID = nil
                            button._auraUnit = bd.auraUnit or "player"
                            button._inPandemic = false
                            button._durationObj = nil
                            button._auraDurationObj = nil
                            button._auraCooldownStart = nil
                            button._auraCooldownDuration = nil
                            button._auraPrimarySwipeActive = nil
                            button.cooldown:SetCooldown(0, 0)
                            button.cooldown:Hide()
                        end
                    end
                end
            end)
            self:MarkCooldownsDirty()
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
        local slotContentChanged = pendingSlotChangedSlots._fullRebuild == true
        self:RebuildSlotMapping()
        if pendingSlotChangedSlots._fullRebuild then
            wipe(actionbarSlotSignatures)
            self:RebuildItemSlotCache()
        else
            for s in pairs(pendingSlotChangedSlots) do
                if ActionbarSlotContentChanged(s) then
                    slotContentChanged = true
                end
                self:UpdateItemSlotCache(s)
            end
        end
        wipe(pendingSlotChangedSlots)
        self:RebuildAddonSlotBindings()
        self:OnKeybindsChanged()
        if slotContentChanged and self.InvalidateCooldownRefreshEligibility then
            self:InvalidateCooldownRefreshEligibility("actionbar-slot-changed")
        end
    end)
end

function CooldownCompanion:OnActionBarLayoutChanged()
    self:RefreshKeybindState()
    if self.InvalidateCooldownRefreshEligibility then
        self:InvalidateCooldownRefreshEligibility("actionbar-layout-changed")
    end
    -- UPDATE_OVERRIDE_ACTIONBAR / UPDATE_VEHICLE_ACTIONBAR also route here for
    -- keybind rebuilds; piggyback vehicle UI state check to avoid duplicate
    -- AceEvent registrations (AceEvent allows only one handler per event).
    local wasInVehicleUI = self._inVehicleUI
    self._inVehicleUI = UnitHasVehicleUI("player")
        or C_ActionBar.HasVehicleActionBar()
        or C_ActionBar.HasOverrideActionBar()
    if self._inVehicleUI ~= wasInVehicleUI then
        self:RefreshAllGroupsVisibilityOnly()
        self:EvaluateBarsAndFramesRuntime("actionbar-layout-vehicle-state")
    end
end

------------------------------------------------------------------------
-- Stacking coordination (CastBar + ResourceBars on same anchor group)
------------------------------------------------------------------------
local pendingStackUpdate = false

function CooldownCompanion:UpdateAnchorStacking()
    local enabled, flags = self:RefreshBarsAndFramesRuntimeGate("anchor-stacking-check")
    if not enabled or not (flags.resourceBars or flags.castBar) then
        return
    end
    if pendingStackUpdate then return end
    pendingStackUpdate = true
    C_Timer.After(0, function()
        pendingStackUpdate = false
        CooldownCompanion:EvaluateBarsAndFramesStackingRuntime("anchor-stacking")
    end)
end
