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

local function IsPlayerInVehicleUI()
    return UnitInVehicle("player")
        or UnitHasVehicleUI("player")
        or C_ActionBar.HasVehicleActionBar()
        or C_ActionBar.HasOverrideActionBar()
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

-- The settle exists for late-resolving charge data and entry usability. It
-- re-reads exactly those and rebuilds only the panels whose entry set moved;
-- the talent cache, the keybind pass and the every-panel escalation belong to
-- the first pass, and repeating them 0.2s later was the second hitch of a
-- shapeshift (every form change fires SPELLS_CHANGED).
local function QueueSpellAvailabilitySettlingRefresh(addon)
    pendingSpellAvailabilityRefreshToken = pendingSpellAvailabilityRefreshToken + 1
    local token = pendingSpellAvailabilityRefreshToken
    C_Timer.After(0.2, function()
        if pendingSpellAvailabilityRefreshToken ~= token then return end
        addon:RefreshSpellAvailabilityState({
            skipSettlingRefresh = true,
            skipTalentCache = true,
            skipKeybindRefresh = true,
            perGroupRebuild = true,
        })
    end)
end

-- One next-frame keybind rebuild per frame, however many action bar events
-- land in it. A shapeshift fires UPDATE_SHAPESHIFT_FORM, UPDATE_BONUS_ACTIONBAR,
-- ACTIONBAR_PAGE_CHANGED and a slot-0 ACTIONBAR_SLOT_CHANGED together, and the
-- spell-availability pass adds one more; each used to run the full rebuild
-- synchronously. `slot` narrows the item cache update. nil and 0 (Blizzard's
-- "every slot" payload on a bonus bar swap) both mean a full rebuild.
local function QueueKeybindStateRefresh(addon, slot)
    if slot and slot ~= 0 then
        pendingSlotChangedSlots[slot] = true
    else
        pendingSlotChangedSlots._fullRebuild = true
    end
    pendingSlotChangeToken = pendingSlotChangeToken + 1
    local token = pendingSlotChangeToken
    C_Timer.After(0, function()
        if pendingSlotChangeToken ~= token then return end
        if pendingSlotChangedSlots._fullRebuild then
            wipe(pendingSlotChangedSlots)
            addon:RefreshKeybindState()
            return
        end
        addon:RebuildSlotMapping()
        for s in pairs(pendingSlotChangedSlots) do
            addon:UpdateItemSlotCache(s)
        end
        wipe(pendingSlotChangedSlots)
        addon:RebuildAddonSlotBindings()
        addon:OnKeybindsChanged()
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
    self:MarkCooldownsDirty("equipment-slots")
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
        self:MarkCooldownsDirty("equipment-changed")
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

function CooldownCompanion:RefreshSpellAvailabilityState(opts)
    opts = opts or {}
    self:CachePlayerState()
    self:CacheCurrentSpec()
    self._currentHeroSpecId = C_ClassTalents.GetActiveHeroTalentSpec()
    -- Talent and spec events rebuild the node cache themselves; a caller
    -- that knows no talent moved (SPELLS_CHANGED, the settling pass) skips
    -- the per-node C_Traits walk. A cache built for another spec is never
    -- kept: on a spec swap SPELLS_CHANGED can land before the spec events,
    -- and this pass must not evaluate talent conditions against the old tree.
    if not opts.skipTalentCache or self._talentNodeCacheSpecId ~= self._currentSpecId then
        self:RebuildTalentNodeCache()
    end
    if opts.refreshAllChargeTypes then
        self:RefreshChargeFlags()
    else
        self:RefreshChargeFlags("spell")
    end
    self:RefreshAllGroupsForSpellAvailability({ perGroupRebuild = opts.perGroupRebuild })
    -- Coalesced with the action bar events of the same frame (see
    -- QueueKeybindStateRefresh). Freshly populated buttons stamp their own
    -- keybind text at populate time; this pass re-stamps every button once.
    if not opts.skipKeybindRefresh then
        QueueKeybindStateRefresh(self)
    end
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

-- SPELLS_CHANGED fires on every shapeshift (druid forms, Stealth), not only
-- on spellbook rebuilds. No talent moved, so the node cache stands, and a
-- panel whose entry set changed refreshes on its own rather than escalating
-- to a rebuild of every panel in the profile.
function CooldownCompanion:OnSpellsChanged()
    self:OnSpellUpdateIcon()
    self:RefreshSpellAvailabilityState({
        skipTalentCache = true,
        perGroupRebuild = true,
    })
end

-- Coalesce icon passes to one per frame. A shapeshift delivers SPELLS_CHANGED,
-- SPELL_UPDATE_ICON and one COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED per
-- transforming spell in the same frame, and every one resolves every entry's
-- icon. Same token pattern as QueueTalentChargeRefresh.
local pendingIconRefreshToken = 0

function CooldownCompanion:OnSpellUpdateIcon()
    pendingIconRefreshToken = pendingIconRefreshToken + 1
    local token = pendingIconRefreshToken
    C_Timer.After(0, function()
        if pendingIconRefreshToken ~= token then return end
        self:RunSpellUpdateIconPass()
    end)
end

function CooldownCompanion:RunSpellUpdateIconPass()
    local anyDeferred = false
    self:ForEachButton(function(button, bd)
        if bd.cdmChildSlot then
            button._iconDirty = true
            anyDeferred = true
        else
            self:UpdateButtonIcon(button)
        end
    end)
    -- A skipped idle tick doesn't walk, so a deferred cdmChildSlot icon refresh
    -- (_iconDirty, consumed in UpdateButtonCooldown) must mark dirty to force a
    -- walk; otherwise it waits for the ~1s idle-skip safety walk. Conservative:
    -- only ever adds a walk. Mirrors the assisted-spell dirty-mark in Lifecycle.
    if anyDeferred then
        self:MarkCooldownsDirty("icon")
    end
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
        self:MarkCooldownsDirty("range-check")
    end
end

function CooldownCompanion:OnReadyGlowUsabilityChanged()
    -- A pending broad pass already re-reads usability. Ignore the action-slot
    -- payload: tracked entries need not live on an action bar.
    if self._queuedCooldownRefreshSource then return end

    for _, frame in pairs(self.groupFrames) do
        if frame and frame:IsShown() and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local style, bd = button.style, button.buttonData
                -- Include individually hidden entries so hide-while-unusable
                -- can recover. Only an enabled icon Ready Glow needs this pass.
                if button.readyGlow and not button._isBar and not button._isText
                        and style and style.readyGlowOnlyWhileUsable == true
                        and style.readyGlowStyle and style.readyGlowStyle ~= "none"
                        and bd and not bd.isPassive and not bd.isPassiveCooldown
                        and bd.addedAs ~= "aura" and not bd._rotationAssistantVirtual then
                    self:QueueCooldownRefresh("ready-glow-usability")
                    return
                end
            end
        end
    end
end

function CooldownCompanion:OnBagChanged()
    self:MarkCooldownsDirty("bag-changed")
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
    self._inVehicleUI = IsPlayerInVehicleUI()
end

function CooldownCompanion:OnZoneChanged()
    self:RefreshSpellAvailabilityState({ evaluateResourceBars = true })
end

-- PLAYER_UPDATE_RESTING also fires on login and loading screens without the
-- resting state actually flipping, so only do work on a real change. Bars
-- are evaluated explicitly: a custom bar's rested load condition can flip
-- with no panel loading or unloading, which is the case the visibility
-- pass's hooks skip.
function CooldownCompanion:OnRestingChanged()
    local isResting = IsResting()
    if isResting == self._isResting then return end
    self._isResting = isResting
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
    self._inVehicleUI = IsPlayerInVehicleUI()
    self:RefreshAuraIdentityVisibility()
    self:RequestAuraRebind("vehicle-ui")
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
    -- Post-login settle repaint (12.1 demolition: the false-aura-active sweep
    -- is gone with the aura backend; keep the 2s settle dirty mark).
    if isFullInit then
        C_Timer.After(2, function()
            self:MarkCooldownsDirty("player-entering-world")
        end)
    end
end

function CooldownCompanion:OnBindingsChanged()
    self:RebuildAddonSlotBindings()
    self:OnKeybindsChanged()
end

function CooldownCompanion:OnActionBarSlotChanged(_, slot)
    -- Modifier-reactive macros fire this event per affected slot in the same
    -- frame; the queue collapses them into one pass and treats slot 0 as a
    -- full rebuild.
    QueueKeybindStateRefresh(self, slot)
end

function CooldownCompanion:OnActionBarLayoutChanged(event)
    QueueKeybindStateRefresh(self)
    -- UPDATE_SHAPESHIFT_FORM also routes here, and druid travel form is an alpha
    -- force-condition input the alpha pass reads fresh. That pass resolves the
    -- form only for druids, so no other class can need the re-arm.
    if event == "UPDATE_SHAPESHIFT_FORM" and self._playerClassID == 11 then
        self:EnsureAlphaDriverArmed()
    end
    -- UPDATE_OVERRIDE_ACTIONBAR / UPDATE_VEHICLE_ACTIONBAR also route here for
    -- keybind rebuilds; piggyback vehicle UI state check to avoid duplicate
    -- AceEvent registrations (AceEvent allows only one handler per event).
    local wasInVehicleUI = self._inVehicleUI
    self._inVehicleUI = IsPlayerInVehicleUI()
    if self._inVehicleUI ~= wasInVehicleUI then
        self:RefreshAuraIdentityVisibility()
        self:RequestAuraRebind("vehicle-actionbar")
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

-- Cast-bar-only stacking leg, for the aura rebind pass. The pass moves the
-- block chain TAIL the cast bar hangs from, and the cast bar is pinned to the
-- stack end, so resource bars never move in response to a tail change. The
-- pass must NOT run the full stacking evaluation: EvaluateResourceBars
-- re-applies unconditionally and ApplyResourceBars ends in
-- RequestAuraRebind("custom-bars"), so pass -> stacking -> apply -> request
-- cycled a full park-and-rebind pass at frame rate for as long as the bars
-- were enabled (diagnosed 2026-08-10; the churn also raced Blizzard's
-- deferred container rebuilds, which is what left displays dark).
local pendingCastBarStackUpdate = false

function CooldownCompanion:UpdateCastBarStackAnchor()
    local enabled, flags = self:RefreshBarsAndFramesRuntimeGate("castbar-stack-anchor-check")
    if not enabled or not flags.castBar then
        return
    end
    if pendingCastBarStackUpdate then return end
    pendingCastBarStackUpdate = true
    C_Timer.After(0, function()
        pendingCastBarStackUpdate = false
        -- Re-check at fire time, mirroring EvaluateBarsAndFramesStackingRuntime:
        -- the gate can flip between the queue and the callback.
        local enabledNow, flagsNow = CooldownCompanion:RefreshBarsAndFramesRuntimeGate("castbar-stack-anchor")
        if not enabledNow or not flagsNow.castBar then return end
        if CooldownCompanion.EvaluateCastBar then
            CooldownCompanion:EvaluateCastBar({ skipRuntimeGate = true })
        end
    end)
end
