--[[
    CooldownCompanion - Core/Lifecycle.lua: OnInitialize, OnEnable, OnDisable,
    ForEachButton, SlashCommand, simple event handlers, viewer frame constants
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local EntryRuntime = ST.EntryRuntime

-- Localize frequently-used globals for faster access
local InCombatLockdown = InCombatLockdown
local pairs = pairs
local wipe = wipe
local ipairs = ipairs
local select = select
local table_insert = table.insert
local type = type

-- Import cross-file variables
local defaults = ST._defaults
local LDBIcon = ST._LDBIcon
local minimapButton = ST._minimapButton

-- LibSharedMedia for font/texture selection
local LSM = LibStub("LibSharedMedia-3.0")

local SatisfyQueuedActionbarCooldownRefresh

-- Viewer frame list used by BuildViewerAuraMap, FindViewerChildForSpell, and OnEnable hooks.
local VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}
ST._VIEWER_NAMES = VIEWER_NAMES

-- Subset: cooldown-only viewers (Essential/Utility), used by FindCooldownViewerChild.
local COOLDOWN_VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
}
ST._COOLDOWN_VIEWER_NAMES = COOLDOWN_VIEWER_NAMES

-- Subset: buff-only viewers, used to scope multi-CDM-child duplicate detection.
local BUFF_VIEWER_SET = {
    ["BuffIconCooldownViewer"] = true,
    ["BuffBarCooldownViewer"] = true,
}
ST._BUFF_VIEWER_SET = BUFF_VIEWER_SET

local cdmAlphaGuard = {}
ST._cdmAlphaGuard = cdmAlphaGuard

function CooldownCompanion:OnInitialize()
    self._hadSavedVariables = type(_G.CooldownCompanionDB) == "table"
    if self.InspectSavedProfileCheckpoint then
        self._savedProfileCheckpointState = self:InspectSavedProfileCheckpoint(_G.CooldownCompanionDB, true)
    end

    -- Initialize database
    self.db = LibStub("AceDB-3.0"):New("CooldownCompanionDB", defaults, true)
    wipe(self.db.profile.showAdvanced)

    -- Initialize storage tables
    self.groupFrames = {}
    self.containerFrames = {}
    self.buttonFrames = {}

    -- Register minimap icon
    LDBIcon:Register(ADDON_NAME, minimapButton, self.db.profile.minimap)

    -- Register chat commands
    self:RegisterChatCommand("cdc", "SlashCommand")
    self:RegisterChatCommand("cooldowncompanion", "SlashCommand")

    -- Initialize config
    self:SetupConfig()

    -- Re-apply fonts/textures when shared media used elsewhere in the addon updates.
    LSM.RegisterCallback(self, "LibSharedMedia_Registered", function(event, mediatype, key)
        if mediatype == "font" then
            if ST._InvalidateFontCache then
                ST._InvalidateFontCache()
            end
            self:RefreshAllMedia()
        elseif mediatype == "statusbar" or mediatype == "background" or mediatype == "border" then
            self:RefreshAllMedia()
            self:RefreshConfigPanel()
            if ST._configState and ST._configState.RefreshAuraTexturePicker then
                ST._configState.RefreshAuraTexturePicker()
            end
        elseif mediatype == "sound" then
            self:RefreshConfigPanel()
        end
    end)

    self:Print("Cooldown Companion loaded. Use /cdc to open settings. Use /cdc help for commands.")
end

function CooldownCompanion:EnsureRuntimeInitialized()
    self.alphaState = self.alphaState or {}

    if not self.updateTicker then
        self.updateTicker = C_Timer.NewTicker(0.1, function()
            -- Read assisted combat recommended spell (plain table field, no API call)
            if AssistedCombatManager then
                self.assistedSpellID = AssistedCombatManager.lastNextCastSpellID
            end

            self:TickCooldownRefresh()
            self:UpdateAllGroupLayouts()
            self:ClearCooldownsDirty()
        end)
    end

    self:InitAlphaUpdateFrame()
end

function CooldownCompanion:OnEnable()
    -- Cooldown events can expose very short ready windows, so refresh them
    -- immediately instead of waiting for the ticker.
    for _, evt in ipairs({
        "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN",
    }) do
        self:RegisterEvent(evt, "OnCooldownStateChanged")
    end

    -- Broader state changes can wait for the regular ticker pass.
    for _, evt in ipairs({
        "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "ITEM_COUNT_CHANGED",
    }) do
        self:RegisterEvent(evt, "MarkCooldownsDirty")
    end
    self:RegisterEvent("PLAYER_EQUIPMENT_CHANGED", "OnEquipmentChanged")
    self:EnsureEquipmentSlotItemLoadFrame()

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

    -- High-frequency unit events. RegisterUnitEvent filters before dispatch,
    -- avoiding global UNIT_* traffic through AceEvent.
    if not self._unitEventFrame then
        self._unitEventFrame = CreateFrame("Frame")
        self._unitEventFrame:SetScript("OnEvent", function(_, event, ...)
            if event == "UNIT_POWER_FREQUENT" then
                self:OnUnitPowerFrequent(event, ...)
            elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
                self:OnSpellCast(event, ...)
            elseif event == "UNIT_AURA" then
                self:OnUnitAura(event, ...)
            end
        end)
    end
    self._unitEventFrame:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")
    self._unitEventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    self._unitEventFrame:RegisterUnitEvent("UNIT_AURA", "player", "target")

    -- Combat events
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")

    -- Charge change events (proc-granted charges, recharges, etc.)
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "OnChargesChanged")
    self:RegisterEvent("SPELL_UPDATE_USES", "OnChargesChanged")

    -- Spell activation overlay (proc glow) events
    -- Track state via events instead of polling IsSpellOverlayed
    -- (that API is AllowedWhenUntainted — calling from addon code causes taint)
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnProcGlowShow")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnProcGlowHide")

    -- Spell override icon changes (talents, procs morphing spells)
    self:RegisterEvent("SPELL_UPDATE_ICON", "OnSpellUpdateIcon")
    -- Spellbook rebuild — catches always-on talent transforms that resolve
    -- after init without firing SPELL_UPDATE_ICON (e.g. hero talent icon swaps).
    self:RegisterEvent("SPELLS_CHANGED", "OnSpellsChanged")

    -- Event-driven range checking (replaces per-tick IsSpellInRange polling)
    self:RegisterEvent("SPELL_RANGE_CHECK_UPDATE", "OnSpellRangeCheckUpdate")

    -- Inventory changes — refresh config panel (!) indicators for items
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnBagChanged")

    -- Talent change events — refresh group frames and config panel
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentsChanged")
    self:RegisterEvent("PLAYER_PVP_TALENT_UPDATE", "OnSpellAvailabilityChanged")
    self:RegisterEvent("WAR_MODE_STATUS_UPDATE", "OnSpellAvailabilityChanged")

    -- Pet summon/dismiss — show/hide pet spell buttons dynamically
    self:RegisterEvent("UNIT_PET", "OnPetChanged")

    -- Specialization change events — show/hide groups based on spec filter
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "OnSpecChanged")
    self:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED", "OnPlayerSpecializationChanged")
    self:RegisterEvent("TRAIT_SUB_TREE_CHANGED", "OnHeroTalentChanged")

    -- Zone/instance change events — load condition evaluation
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
    self:RegisterEvent("PLAYER_UPDATE_RESTING", "OnRestingChanged")
    self:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED", "OnMountDisplayChanged")
    self:RegisterEvent("NEW_MOUNT_ADDED", "OnNewMountAdded")

    -- Pet battle events — hide groups during pet battles
    self:RegisterEvent("PET_BATTLE_OPENING_START", "OnPetBattleStart")
    self:RegisterEvent("PET_BATTLE_OVER", "OnPetBattleEnd")

    -- Vehicle / override UI events — hide groups when normal bars are replaced.
    -- UPDATE_OVERRIDE_ACTIONBAR and UPDATE_VEHICLE_ACTIONBAR are already
    -- registered above for keybind rebuilds; OnActionBarLayoutChanged piggybacks
    -- the vehicle state check to avoid duplicate AceEvent registrations.
    self:RegisterEvent("UNIT_ENTERED_VEHICLE", "OnVehicleUIChanged")
    self:RegisterEvent("UNIT_EXITED_VEHICLE", "OnVehicleUIChanged")

    -- Target change — marks dirty so ticker reads fresh viewer data next pass
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")

    -- UNIT_TARGET requires RegisterUnitEvent (plain RegisterEvent does not
    -- receive it). PLAYER_TARGET_CHANGED is the authoritative player-target
    -- signal; this handler is kept for inherited unit-frame alpha resync
    -- without forcing a duplicate cooldown walk.
    if not self._unitTargetFrame then
        self._unitTargetFrame = CreateFrame("Frame")
        self._unitTargetFrame:SetScript("OnEvent", function()
            if ST._QueueInheritedUnitFrameAlphaResync then
                ST._QueueInheritedUnitFrameAlphaResync()
            end
        end)
    end
    self._unitTargetFrame:RegisterUnitEvent("UNIT_TARGET", "player")

    -- Rebuild viewer aura map when Cooldown Manager layout changes (user rearranges spells)
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        if ST._configState then
            ST._configState.autocompleteCache = nil
        end
        C_Timer.After(0.2, function()
            self:QueueBuildViewerAuraMap()
        end)
    end, self)

    -- Track spell overrides (transforming spells like Eclipse) to keep viewer map current
    self:RegisterEvent("COOLDOWN_VIEWER_SPELL_OVERRIDE_UPDATED", "OnViewerSpellOverrideUpdated")

    -- Hook SetAlpha on CDM viewers to re-enforce hidden state against
    -- Blizzard overrides (AnimInManagedFrames, EditMode opacity, etc.)
    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer then
            hooksecurefunc(viewer, "SetAlpha", function(frame, a)
                if cdmAlphaGuard[frame] then return end
                if not CooldownCompanion._cdmPickMode
                   and CooldownCompanion.db
                   and CooldownCompanion.db.profile.cdmHidden then
                    cdmAlphaGuard[frame] = true
                    frame:SetAlpha(0)
                    cdmAlphaGuard[frame] = nil
                end
            end)
            -- Hook RefreshLayout to re-disable mouse on newly pool-acquired children.
            -- Blizzard's OnAcquireItemFrame calls SetTooltipsShown(true) on new children.
            hooksecurefunc(viewer, "RefreshLayout", function(frame)
                if CooldownCompanion._cdmPickMode then return end
                CooldownCompanion:QueueBuildViewerAuraMap()
                if CooldownCompanion.db
                   and CooldownCompanion.db.profile.cdmHidden then
                    for _, child in pairs({frame:GetChildren()}) do
                        child:SetMouseMotionEnabled(false)
                    end
                end
            end)
        end
    end

    -- Enforce CDM hidden state immediately after hooks are installed.
    -- Without this, viewers flash visible for ~1s after /reload until
    -- the delayed ApplyCdmAlpha() in OnPlayerEnteringWorld fires.
    self:ApplyCdmAlpha()

    -- Keybind text events
    self:RegisterEvent("UPDATE_BINDINGS", "OnBindingsChanged")
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", "OnActionBarSlotChanged")
    self:RegisterEvent("ACTIONBAR_PAGE_CHANGED", "OnActionBarLayoutChanged")
    self:RegisterEvent("UPDATE_BONUS_ACTIONBAR", "OnActionBarLayoutChanged")
    self:RegisterEvent("UPDATE_OVERRIDE_ACTIONBAR", "OnActionBarLayoutChanged")
    self:RegisterEvent("UPDATE_VEHICLE_ACTIONBAR", "OnActionBarLayoutChanged")
    self:RegisterEvent("UPDATE_SHAPESHIFT_FORM", "OnActionBarLayoutChanged")
    self:RegisterEvent("PET_BAR_UPDATE", "OnActionBarLayoutChanged")

    -- Cache player identity for class/race-specific checks.
    self._playerClassID = select(3, UnitClass("player"))
    self._isDracthyr = (select(2, UnitRace("player")) == "Dracthyr")

    -- Store class info in global scope for cross-character browse mode
    self.db.global.characterInfo[self.db.keys.char] = {
        classFilename = select(2, UnitClass("player")),
        classID = self._playerClassID,
    }

    -- Cache current spec before creating frames (visibility depends on it)
    self:CacheCurrentSpec()

    -- Keep runtime scaffolding alive even if the active profile is unsupported.
    -- That lets the user switch to a supported profile in the same session
    -- without requiring /reload to recreate the ticker and alpha systems.
    self:EnsureRuntimeInitialized()

    -- Run all data migrations (ownership, alpha, display mode, style, etc.)
    if not self:RunAllMigrations() then
        return
    end

    -- Create all container frames, then group (panel) frames
    self:CreateAllContainerFrames()
    self:CreateAllGroupFrames()
    self:FinalizeContainerAnchorsToScreenOffsets()
end

function CooldownCompanion:OnCooldownStateChanged(event, spellID, baseSpellID, category, startRecoveryCategory)
    if self:ShouldSkipStartRecoveryOnlyCooldownEvent(event, spellID, category, startRecoveryCategory) then
        SatisfyQueuedActionbarCooldownRefresh(self)
        return
    end

    if event == "BAG_UPDATE_COOLDOWN" and self.UpdateItemCooldownButtonsForEvent then
        self:UpdateItemCooldownButtonsForEvent()
        return
    end

    if event == "ACTIONBAR_UPDATE_COOLDOWN" and not self:HasGCDSwipeRefreshConsumers() then
        if self.UpdateItemCooldownButtonsForEvent then
            self:UpdateItemCooldownButtonsForEvent()
        end
        if self.UpdateCooldownButtonsForActionbarEvent then
            self:UpdateCooldownButtonsForActionbarEvent()
        end
        return
    end

    local hadPendingDirty = self._cooldownsDirty == true
    self:MarkCooldownsDirty()
    if event == "SPELL_UPDATE_COOLDOWN"
            and spellID
            and (not category or category == 0)
            and not self:HasGCDSwipeRefreshConsumers()
            and self.UpdateCooldownButtonsForSpellEvent then
        if self:UpdateCooldownButtonsForSpellEvent(spellID, baseSpellID) then
            if not hadPendingDirty then
                if not SatisfyQueuedActionbarCooldownRefresh(self) then
                    self._cooldownRefreshSatisfiedSerial = self._cooldownDirtySerial or 0
                end
            end
        else
            if not hadPendingDirty then
                SatisfyQueuedActionbarCooldownRefresh(self)
            end
        end
        return
    end

    -- Preserve immediate cooldown-event accuracy. This refresh only suppresses
    -- the next ticker walk when no other dirty state appears afterward.
    if event == "SPELL_UPDATE_COOLDOWN" and spellID then
        self:RunImmediateCooldownRefresh("cooldown-event")
    else
        self:QueueCooldownRefresh("cooldown-event", event)
    end
end

function CooldownCompanion:HasGCDSwipeRefreshConsumers()
    local groups = self.db and self.db.profile and self.db.profile.groups
    local groupFrames = self.groupFrames
    if type(groups) ~= "table" or type(groupFrames) ~= "table" then
        return true
    end

    for groupId, frame in pairs(groupFrames) do
        if frame and frame.IsShown and frame:IsShown() then
            local group = groups[groupId]
            local style = group and group.style
            if style and style.showGCDSwipe == true then
                return true
            end
            for _, button in ipairs(frame.buttons or {}) do
                local buttonStyle = button and button.style
                if button and button._pooled ~= true
                        and buttonStyle and buttonStyle.showGCDSwipe == true then
                    return true
                end
            end
        end
    end
    return false
end

function CooldownCompanion:ShouldSkipStartRecoveryOnlyCooldownEvent(event, spellID, category, startRecoveryCategory)
    -- Conservatively keep these events on the normal spell refresh path. The
    -- payload alone does not prove that a start-recovery category excludes a
    -- real tracked spell cooldown, especially for no-category cooldowns.
    return false
end

function CooldownCompanion:OnUnitPowerFrequent(event, unitTarget, powerType)
    if self.RefreshPowerSensitiveButtonStates then
        self:RefreshPowerSensitiveButtonStates()
    else
        self:MarkCooldownsDirty()
    end
end

-- Iterate every button across all groups, calling callback(button, buttonData) for each.
-- Skips buttons without buttonData.
function CooldownCompanion:ForEachButton(callback)
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                if button.buttonData then
                    callback(button, button.buttonData)
                end
            end
        end
    end
end

function CooldownCompanion:InvalidateCastButtonIndex()
    self._castButtonIndexDirty = true
end

local function AddCastButtonIndexEntry(index, spellID, button)
    if not spellID then
        return
    end

    local buttons = index[spellID]
    if not buttons then
        buttons = {}
        index[spellID] = buttons
    end
    table_insert(buttons, button)
end

local function RebuildCastButtonIndex(addon)
    local index = {}
    for _, frame in pairs(addon.groupFrames or {}) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local buttonData = button and button.buttonData
                if buttonData and buttonData.type == "spell" and not buttonData.isPassive then
                    AddCastButtonIndexEntry(index, buttonData.id, button)
                    local overrideID = C_Spell
                        and C_Spell.GetOverrideSpell
                        and C_Spell.GetOverrideSpell(buttonData.id)
                    if overrideID and overrideID ~= 0 and overrideID ~= buttonData.id then
                        AddCastButtonIndexEntry(index, overrideID, button)
                    end
                    local baseID = C_Spell
                        and C_Spell.GetBaseSpell
                        and C_Spell.GetBaseSpell(buttonData.id)
                    if baseID and baseID ~= 0 and baseID ~= buttonData.id then
                        AddCastButtonIndexEntry(index, baseID, button)
                    end
                    if button._displaySpellId and button._displaySpellId ~= buttonData.id then
                        AddCastButtonIndexEntry(index, button._displaySpellId, button)
                    end
                end
            end
        end
    end
    addon._castButtonIndex = index
    addon._castButtonIndexDirty = nil
    return index
end

local function RecordChargeSpentForCastButton(addon, button, buttonData, spellID)
    if not (buttonData and buttonData.type == "spell" and not buttonData.isPassive) then
        return false
    end

    local displaySpellID = button._displaySpellId or buttonData.id
    if spellID ~= buttonData.id and spellID ~= displaySpellID then
        return false
    end

    if addon.UsesChargeBehavior(buttonData) and buttonData.hasCharges then
        -- Track charge consumption for restricted-mode color heuristic.
        -- _chargeRecharging at event time reflects the PRE-cast state:
        --   false = casting from full charges -> reset to 1
        --   true  = already recharging -> increment
        EntryRuntime.RecordChargeSpent(button)
        return true
    end
    return addon.HasCastCountText
        and addon.HasCastCountText(buttonData)
        or false
end

local function VisitIndexedCastButtons(addon, spellID, baseSpellID, callback)
    local index = addon._castButtonIndex
    if addon._castButtonIndexDirty or type(index) ~= "table" then
        index = RebuildCastButtonIndex(addon)
    end

    local seen = addon._castButtonVisitSeen
    if seen then
        wipe(seen)
    else
        seen = {}
        addon._castButtonVisitSeen = seen
    end

    local handled = false
    local foundStaleEntry = false

    local function visit(eventSpellID)
        local buttons = eventSpellID and index[eventSpellID]
        if not buttons then
            return
        end

        for _, button in ipairs(buttons) do
            if button and not seen[button] then
                seen[button] = true
                local groupId = button._groupId
                local frame = groupId and addon.groupFrames and addon.groupFrames[groupId] or nil
                local buttonData = button.buttonData
                if frame and frame.buttons and buttonData and button._pooled ~= true then
                    handled = callback(button, buttonData, frame, eventSpellID) or handled
                else
                    foundStaleEntry = true
                end
            end
        end
    end

    visit(spellID)
    if baseSpellID ~= spellID then
        visit(baseSpellID)
    end

    if foundStaleEntry then
        addon._castButtonIndexDirty = true
    end
    return handled
end

local function RecordIndexedCastButtons(addon, spellID)
    if not spellID then
        return false
    end

    return VisitIndexedCastButtons(addon, spellID, nil, function(button, buttonData)
        return RecordChargeSpentForCastButton(addon, button, buttonData, spellID)
    end)
end

function CooldownCompanion:CollectCooldownEventButtonsForSpell(spellID, baseSpellID)
    if not spellID and not baseSpellID then
        return nil
    end

    local collected = self._cooldownEventButtonsScratch
    if collected then
        wipe(collected)
    else
        collected = {}
        self._cooldownEventButtonsScratch = collected
    end

    VisitIndexedCastButtons(self, spellID, baseSpellID, function(button, _, frame)
        if frame and frame.IsShown and frame:IsShown() and button.UpdateCooldown then
            table_insert(collected, button)
            return true
        end
        return false
    end)

    return #collected > 0 and collected or nil
end

function CooldownCompanion:CollectCooldownEventButtonsForActionbar()
    local index = self._castButtonIndex
    if self._castButtonIndexDirty or type(index) ~= "table" then
        index = RebuildCastButtonIndex(self)
    end

    local collected = self._cooldownEventActionbarButtonsScratch
    if collected then
        wipe(collected)
    else
        collected = {}
        self._cooldownEventActionbarButtonsScratch = collected
    end

    local seen = self._cooldownEventActionbarButtonsSeen
    if seen then
        wipe(seen)
    else
        seen = {}
        self._cooldownEventActionbarButtonsSeen = seen
    end

    local foundStaleEntry = false
    for _, buttons in pairs(index) do
        for _, button in ipairs(buttons) do
            if button and not seen[button] then
                seen[button] = true
                local groupId = button._groupId
                local frame = groupId and self.groupFrames and self.groupFrames[groupId] or nil
                local buttonData = button.buttonData
                if frame and frame.IsShown and frame:IsShown()
                        and frame.buttons
                        and buttonData
                        and button.UpdateCooldown
                        and button._pooled ~= true then
                    table_insert(collected, button)
                else
                    foundStaleEntry = true
                end
            end
        end
    end

    if foundStaleEntry then
        self._castButtonIndexDirty = true
    end
    return #collected > 0 and collected or nil
end

function SatisfyQueuedActionbarCooldownRefresh(addon)
    local queuedEvent = addon._queuedCooldownRefreshEvent
    if queuedEvent == "ACTIONBAR_UPDATE_COOLDOWN"
            and addon.SatisfyQueuedCooldownRefresh then
        addon:SatisfyQueuedCooldownRefresh("cooldown-event")
        return true
    end
    return false
end

function CooldownCompanion:InvalidateCastCountEventIndex()
    self._castCountEventIndexDirty = true
end

local function AddCastCountEventIndexEntry(index, eventSpellID, buttonData)
    if not eventSpellID then
        return
    end

    local entries = index[eventSpellID]
    if not entries then
        entries = {}
        index[eventSpellID] = entries
    end
    table_insert(entries, buttonData)
end

local function RebuildCastCountEventIndex(addon)
    local index = {}
    local getEventSpells = addon.GetConditionalCastCountEventSpells
    local groups = addon.db and addon.db.profile and addon.db.profile.groups
    if getEventSpells and groups then
        for _, group in pairs(groups) do
            for _, buttonData in ipairs(group.buttons or {}) do
                if buttonData.type == "spell" and not buttonData.hasCharges then
                    local eventSpells = getEventSpells(buttonData)
                    if eventSpells then
                        for eventSpellID in pairs(eventSpells) do
                            AddCastCountEventIndexEntry(index, eventSpellID, buttonData)
                        end
                    end
                end
            end
        end
    end

    addon._castCountEventIndex = index
    addon._castCountEventIndexDirty = nil
    return index
end

local function MarkConditionalCastCountCandidates(addon, spellID, baseSpellID)
    local matchesConditionalCastCountEvent = addon.MatchesConditionalCastCountEvent
    if not matchesConditionalCastCountEvent then
        return false
    end

    local index = addon._castCountEventIndex
    if addon._castCountEventIndexDirty or type(index) ~= "table" then
        index = RebuildCastCountEventIndex(addon)
    end

    local seen = addon._castCountEventSeen
    if seen then
        wipe(seen)
    else
        seen = {}
        addon._castCountEventSeen = seen
    end

    local matched = false
    local function markEntriesFor(eventSpellID)
        local entries = eventSpellID and index[eventSpellID]
        if not entries then
            return
        end

        for _, buttonData in ipairs(entries) do
            if not seen[buttonData] then
                seen[buttonData] = true
                if buttonData.type == "spell"
                        and not buttonData.hasCharges
                        and matchesConditionalCastCountEvent(buttonData, spellID, baseSpellID) then
                    buttonData._castCountCandidate = true
                    buttonData._castCountEventSpellID = spellID
                    buttonData._castCountSelf = (buttonData.id == spellID) or nil
                    matched = true
                end
            end
        end
    end

    markEntriesFor(spellID)
    if baseSpellID ~= spellID then
        markEntriesFor(baseSpellID)
    end
    return matched
end

function CooldownCompanion:OnDisable()
    -- Cancel the ticker
    if self.updateTicker then
        self.updateTicker:Cancel()
        self.updateTicker = nil
    end

    -- Stop the alpha fade frame
    if self._alphaFrame then
        self._alphaFrame:SetScript("OnUpdate", nil)
        self._alphaFrame = nil
    end

    self:ResetCooldownRefreshState()

    -- Disable all range check registrations
    for spellId in pairs(self._rangeCheckSpells) do
        C_Spell.EnableSpellRangeCheck(spellId, false)
    end
    wipe(self._rangeCheckSpells)

    -- Unregister UNIT_TARGET frame (keep reference for reuse on re-enable)
    if self._unitTargetFrame then
        self._unitTargetFrame:UnregisterAllEvents()
    end

    -- Unregister filtered unit events (keep reference for reuse on re-enable)
    if self._unitEventFrame then
        self._unitEventFrame:UnregisterAllEvents()
    end

    -- Unregister EventRegistry callback (not managed by Ace3)
    EventRegistry:UnregisterCallback("CooldownViewerSettings.OnDataChanged", self)

    -- Hide all frames
    for _, frame in pairs(self.groupFrames) do
        frame:Hide()
    end
end

function CooldownCompanion:OnChargesChanged(event, spellID, baseSpellID)
    if event == "SPELL_UPDATE_USES" and spellID then
        if MarkConditionalCastCountCandidates(self, spellID, baseSpellID) then
            self._hasDisplayCountCandidates = true
        end
    end
    if self._hasDisplayCountCandidates then
        self:RefreshChargeFlags("spell")
    end
    self:QueueCooldownRefresh("charges-event")
end

function CooldownCompanion:OnProcGlowShow(event, spellID)
    self.procOverlaySpells[spellID] = true
    self:QueueCooldownRefresh("proc-event")
end

function CooldownCompanion:OnProcGlowHide(event, spellID)
    self.procOverlaySpells[spellID] = nil
    self:MarkCooldownsDirty()
    self:QueueCooldownRefresh("proc-event")
end

function CooldownCompanion:OnSpellCast(event, unit, castGUID, spellID)
    if unit == "player" then
        local recordedCastState = RecordIndexedCastButtons(self, spellID)
        local recordedCustomBarState = false
        if self.RecordCustomBarSpellCast then
            recordedCustomBarState = self:RecordCustomBarSpellCast(spellID) == true
        end
        if recordedCastState or recordedCustomBarState then
            self:QueueCooldownRefresh("cast-event")
        end
    end
end


function CooldownCompanion:OnCombatStart()
    self:BeginCombatForcedLock()
    self:QueueCooldownRefresh("combat-event")
    -- Close spellbook during combat to avoid Blizzard secret value errors
    if PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then
        HideUIPanel(PlayerSpellsFrame)
    end
    -- Hide config panel during combat to avoid protected frame errors
    local configFrame = self:GetConfigFrame()
    if configFrame and configFrame.frame:IsShown() then
        self._pendingConfigIntent = {
            action = "toggle",
            entryPoint = "combat reopen",
        }
        configFrame.frame:Hide()
        self:Print("Config closed for combat. It will reopen when combat ends.")
    end
end

function CooldownCompanion:OnCombatEnd()
    local combatLockSnapshot = self:EndCombatForcedLock()
    self:QueueCooldownRefresh("combat-event")
    self:ApplyCdmAlpha()
    if self._pendingUnsupportedLegacyHide or self._unsupportedLegacyProfile then
        self._pendingUnsupportedLegacyHide = nil
        self._pendingFullRefresh = nil
        self._pendingVisibilityRefresh = nil
        self:ClearUnsupportedProfileRuntime()
    end
    -- Full refresh supersedes visibility-only refresh
    if self._pendingFullRefresh then
        self._pendingFullRefresh = nil
        self._pendingVisibilityRefresh = nil
        self:RefreshAllGroups()
    elseif self._pendingVisibilityRefresh then
        self._pendingVisibilityRefresh = nil
        if combatLockSnapshot and combatLockSnapshot.hadUnlocked then
            self:RefreshAllGroups()
        else
            self:RefreshAllGroupsVisibilityOnly()
        end
    elseif combatLockSnapshot and combatLockSnapshot.hadUnlocked then
        self:RefreshAllGroups()
    end
    if combatLockSnapshot and combatLockSnapshot.hadUnlocked and self.containerFrames then
        for containerId in pairs(self.containerFrames) do
            local container = self.db.profile.groupContainers and self.db.profile.groupContainers[containerId]
            self:UpdateContainerDragHandle(containerId, not container or container.locked)
        end
    end
    -- Reopen or complete deferred config work after combat.
    if self._pendingConfigIntent then
        self:OpenPendingConfigIntent()
    end
end


function CooldownCompanion:SlashCommand(input)
    input = tostring(input or ""):lower()
    input = input:match("^%s*(.-)%s*$")

    local function SwitchPrimaryConfigMode(mode, entryPoint)
        self:ToggleConfig({
            action = "mode",
            mode = mode,
            entryPoint = entryPoint or ("/cdc " .. mode),
        })
    end

    if input == "lock" or input == "unlock" then
        -- Toggle: if any visible container is unlocked, lock all; otherwise unlock all
        local anyUnlocked = false
        for containerId, container in pairs(self.db.profile.groupContainers) do
            if self:IsContainerVisibleToCurrentChar(containerId) and not container.locked then
                anyUnlocked = true
                break
            end
        end
        if anyUnlocked then
            for containerId, container in pairs(self.db.profile.groupContainers) do
                if self:IsContainerVisibleToCurrentChar(containerId) then
                    container.locked = true
                end
            end
            self:LockAllFrames()
            self:RefreshConfigPanel()
            self:Print("All frames locked.")
        else
            for containerId, container in pairs(self.db.profile.groupContainers) do
                if self:IsContainerVisibleToCurrentChar(containerId) then
                    container.locked = false
                end
            end
            self:UnlockAllFrames()
            self:RefreshConfigPanel()
            self:Print("All frames unlocked. Drag to move.")
        end
    elseif input == "minimap" then
        self.db.profile.minimap.hide = not self.db.profile.minimap.hide
        if self.db.profile.minimap.hide then
            LDBIcon:Hide(ADDON_NAME)
            self:Print("Minimap icon hidden.")
        else
            LDBIcon:Show(ADDON_NAME)
            self:Print("Minimap icon shown.")
        end
    elseif input == "help" then
        self:Print("Cooldown Companion commands:")
        self:Print("/cdc - Open settings")
        self:Print("/cdc buttons - Open settings in Buttons mode")
        self:Print("/cdc bars - Open settings in Bars & Frames mode")
        self:Print("/cdc frames - Alias for /cdc bars")
        self:Print("/cdc lock - Toggle lock/unlock all group frames")
        self:Print("/cdc minimap - Toggle minimap icon")
        self:Print("/cdc reset - Reset profile to defaults")
    elseif input == "bars" or input == "frames" then
        SwitchPrimaryConfigMode("bars", "/cdc " .. input)
    elseif input == "buttons" then
        SwitchPrimaryConfigMode("buttons")
    elseif input == "reset" then
        self:ShowResetProfilePopup()
    elseif input == "debugimport" then
        self:OpenDiagnosticDecodePanel()
    else
        self:ToggleConfig({
            action = "toggle",
            entryPoint = "/cdc",
        })
    end
end
