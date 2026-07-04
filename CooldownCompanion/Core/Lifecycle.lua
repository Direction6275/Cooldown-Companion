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

-- Import cross-file variables
local defaults = ST._defaults
local LDBIcon = ST._LDBIcon
local minimapButton = ST._minimapButton

-- LibSharedMedia for font/texture selection
local LSM = LibStub("LibSharedMedia-3.0")

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
            -- Read assisted combat recommended spell (plain table field, no API
            -- call). A skipped tick doesn't walk, so a changed recommendation
            -- must mark dirty to force a walk. Conservative: a new dirty source
            -- only ever adds walks, never removes them.
            if AssistedCombatManager then
                local nextCast = AssistedCombatManager.lastNextCastSpellID
                if nextCast ~= self.assistedSpellID then
                    self.assistedSpellID = nextCast
                    self:MarkCooldownsDirty("assisted")
                end
            end

            self:TickCooldownRefresh()
            self:UpdateAllGroupLayouts()
            self:ClearCooldownsDirty()
        end)
    end

    self:InitAlphaUpdateFrame()
end

function CooldownCompanion:OnEnable()
    -- F3: seed the cooldown-done kill-switch runtime flag from saved state
    -- (absent key = signal enabled).
    self._cooldownDoneSignalOff = self.db.global.cooldownDoneSignalDisabled == true

    -- Combat ticker floor: ON by default (the shipped behavior). Seeds enabled
    -- unless the hidden kill switch (SetCombatTickerFloorDisabled) has forced the
    -- legacy path; absent key = ON. Gates the mode-aware classifier, the pandemic
    -- edge-hook, and the power-mark demotion. Drop the earlier default-OFF opt-in
    -- key from any prior build.
    self.db.global.combatTickerFloor = nil
    self._combatTickerFloorOn = self.db.global.combatTickerFloorDisabled ~= true

    -- F1 3a: seed the broadcast-demotion runtime flag from saved state (absent
    -- key = OFF; today's immediate-broad path for every cooldown event).
    self._cooldownBroadcastDemotionOn = self.db.global.cooldownBroadcastDemotion == true

    -- F1 3b: seed the cooldown-routing runtime flag from saved state (absent key
    -- = OFF; today's broad path for every readable-arg SPELL_UPDATE_COOLDOWN).
    self._cooldownRoutingOn = self.db.global.cooldownRouting == true

    -- F6: render-layer flattening is now permanent (applied unconditionally at
    -- button creation); drop the saved switch key from any earlier build.
    self.db.global.renderFlattenEnabled = nil

    -- F2: seed the combat flag read by the idle-skip predicate (the skip is
    -- out-of-combat only). Maintained by OnCombatStart/OnCombatEnd; one
    -- InCombatLockdown() read here covers /reload-in-combat. No per-tick probe.
    self._inCombatForTicker = InCombatLockdown() and true or false

    -- F2: reset the idle-skip safety-walk streak.
    self._tickerSkipStreak = 0

    -- Cooldown events can expose very short ready windows, so refresh them
    -- immediately instead of waiting for the ticker.
    for _, evt in ipairs({
        "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN",
    }) do
        self:RegisterEvent(evt, "OnCooldownStateChanged")
    end

    -- Broader state changes can wait for the regular ticker pass.
    -- PLAYER_SOFT_ENEMY_CHANGED refreshes the assisted-highlight hostile gate
    -- when there is no hard target and the softenemy fallback changes.
    for _, evt in ipairs({
        "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE", "ITEM_COUNT_CHANGED",
        "PLAYER_SOFT_ENEMY_CHANGED",
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
                -- Combat ticker floor: power updates (~14/sec in combat) are the
                -- ticker's dirty floor and their only consumer is the castability
                -- tint. While the floor is on, stop marking dirty here so the
                -- ticker can idle-skip; the tint then rides walk cadence (safety
                -- walk ~1s worst case -- the owner-signed-off latency trade).
                -- Switch OFF restores the immediate mark verbatim. The power
                -- dirtyCount dropping toward 0 is the telemetry signal.
                if not self._combatTickerFloorOn then
                    self:MarkCooldownsDirty("power")
                end
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
    -- receive it).  Marks dirty so the next ticker pass reads fresh CDM viewer
    -- data; catches pet/focus target changes that don't fire PLAYER_TARGET_CHANGED.
    if not self._unitTargetFrame then
        self._unitTargetFrame = CreateFrame("Frame")
        self._unitTargetFrame:SetScript("OnEvent", function(_, event, unitToken)
            if ST._QueueInheritedUnitFrameAlphaResync then
                ST._QueueInheritedUnitFrameAlphaResync()
            end
            self:MarkCooldownsDirty("unit-target")
            ST.TagRefreshPass("unit-target-direct")
            self:UpdateAllCooldowns()
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
    local _, classFilename, classID = UnitClass("player")
    self._playerClassFilename = classFilename
    self._playerClassID = classID
    self._isDracthyr = (select(2, UnitRace("player")) == "Dracthyr")

    -- Store class info in global scope for cross-character browse mode
    self.db.global.characterInfo[self.db.keys.char] = {
        classFilename = classFilename,
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

function CooldownCompanion:OnCooldownStateChanged(event, ...)
    -- D1 shadow-parity tap (dev-gated, observe-only). Event args pass through
    -- unread here; the harness issecretvalue-checks before any read.
    local SP = ST.ShadowParity
    if SP and SP.enabled then
        SP:NoteCooldownEvent(event, ...)
    end
    -- F1 3b: readable-identity SPELL fires route to their index-matched buttons
    -- (mini-pass) or drop (no tracked button). Anything the router cannot fully
    -- classify -- secret/nil arg, panel-matched button, generation churn --
    -- returns false and falls through to the broad path below unchanged.
    if self._cooldownRoutingOn and event == "SPELL_UPDATE_COOLDOWN" then
        if self:RouteCooldownEventFire(...) then
            return
        end
    end
    if self._cooldownBroadcastDemotionOn
        and (event == "ACTIONBAR_UPDATE_COOLDOWN" or event == "BAG_UPDATE_COOLDOWN")
    then
        -- F1 3a: identity-less broadcast events carry no data CC consumes
        -- (D2 + demotion trace); everything they signal is re-polled by the
        -- next walk. Dirty-only: the next tick walks (<=0.1s), in combat and
        -- OOC alike. SPELL_UPDATE_COOLDOWN keeps immediate accuracy below.
        self:MarkCooldownsDirty(event == "BAG_UPDATE_COOLDOWN"
            and "bag-cd-broadcast" or "actionbar-cd-broadcast")
        return
    end
    self:MarkCooldownsDirty("cooldown-event")
    -- Preserve immediate cooldown-event accuracy. This refresh only suppresses
    -- the next ticker walk when no other dirty state appears afterward.
    self:RunImmediateCooldownRefresh("cooldown-event")
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

    local T = ST.RefreshTelemetry
    if self._queuedCooldownRefreshSource and T and T.enabled then
        T:ClearQueueHistory()
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
    -- D1 shadow-parity tap (dev-gated, observe-only).
    local SP = ST.ShadowParity
    if SP and SP.enabled then
        SP:NoteChargesEvent(event, spellID, baseSpellID)
    end
    if event == "SPELL_UPDATE_USES" and spellID then
        local matchesConditionalCastCountEvent = CooldownCompanion.MatchesConditionalCastCountEvent
        local matchedCastCountButton = false
        for _, group in pairs(self.db.profile.groups) do
            for _, bd in ipairs(group.buttons) do
                if bd.type == "spell"
                        and not bd.hasCharges
                        and matchesConditionalCastCountEvent
                        and matchesConditionalCastCountEvent(bd, spellID, baseSpellID) then
                    bd._castCountCandidate = true
                    bd._castCountEventSpellID = spellID
                    bd._castCountSelf = (bd.id == spellID) or nil
                    matchedCastCountButton = true
                end
            end
        end
        if matchedCastCountButton then
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
    self:MarkCooldownsDirty("proc-hide")
    self:QueueCooldownRefresh("proc-event")
end

function CooldownCompanion:OnSpellCast(event, unit, castGUID, spellID)
    if unit == "player" then
        self:ForEachButton(function(button, buttonData)
            if buttonData.type == "spell"
                and not buttonData.isPassive then
                local displaySpellID = button._displaySpellId or buttonData.id
                if spellID == buttonData.id or spellID == displaySpellID then
                    if self.UsesChargeBehavior(buttonData) and buttonData.hasCharges then
                        -- Track charge consumption for restricted-mode color heuristic.
                        -- _chargeRecharging at event time reflects the PRE-cast state:
                        --   false = casting from full charges → reset to 1
                        --   true  = already recharging → increment
                        EntryRuntime.RecordChargeSpent(button)
                    end
                end
            end
        end)
        if self.RecordCustomBarSpellCast then
            self:RecordCustomBarSpellCast(spellID)
        end
        self:QueueCooldownRefresh("cast-event")
    end
end


function CooldownCompanion:OnCombatStart()
    self._inCombatForTicker = true  -- F2: disarms the idle ticker skip in combat
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
    self._inCombatForTicker = false  -- F2: re-arms idle ticker skip eligibility
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
