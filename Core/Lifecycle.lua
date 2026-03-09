--[[
    CooldownCompanion - Core/Lifecycle.lua: OnInitialize, OnEnable, OnDisable, ForEachButton,
    MarkCooldownsDirty, SlashCommand, simple event handlers, viewer frame constants
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals for faster access
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
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
    -- Initialize database
    self.db = LibStub("AceDB-3.0"):New("CooldownCompanionDB", defaults, true)

    -- Initialize storage tables
    self.groupFrames = {}
    self.buttonFrames = {}

    -- Hidden scratch CooldownFrame for secret-safe GCD activity detection
    local gcdScratchParent = CreateFrame("Frame")
    gcdScratchParent:Hide()
    self._gcdScratch = CreateFrame("Cooldown", nil, gcdScratchParent, "CooldownFrameTemplate")

    -- Register minimap icon
    LDBIcon:Register(ADDON_NAME, minimapButton, self.db.profile.minimap)

    -- Register chat commands
    self:RegisterChatCommand("cdc", "SlashCommand")
    self:RegisterChatCommand("cooldowncompanion", "SlashCommand")

    -- Initialize config
    self:SetupConfig()

    -- Re-apply fonts/textures when a SharedMedia pack registers new media
    LSM.RegisterCallback(self, "LibSharedMedia_Registered", function(event, mediatype, key)
        if mediatype == "font" or mediatype == "statusbar" then
            self:RefreshAllMedia()
        elseif mediatype == "sound" then
            self:RefreshConfigPanel()
        end
    end)

    self:Print("Cooldown Companion loaded. Use /cdc to open settings. Use /cdc help for commands.")
end

function CooldownCompanion:OnEnable()
    -- Register cooldown events — set dirty flag, let ticker do the actual update.
    -- The 0.1s ticker runs regardless, so latency is at most ~100ms for
    -- event-triggered updates — indistinguishable visually since the cooldown
    -- frame animates independently. This prevents redundant full-update passes
    -- during event storms.
    -- Cooldown/state change events that trigger a dirty-flag update pass
    for _, evt in ipairs({
        "SPELL_UPDATE_COOLDOWN", "BAG_UPDATE_COOLDOWN", "ACTIONBAR_UPDATE_COOLDOWN",
        "UNIT_POWER_FREQUENT", "LOSS_OF_CONTROL_ADDED", "LOSS_OF_CONTROL_UPDATE",
        "ITEM_COUNT_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
    }) do
        self:RegisterEvent(evt, "MarkCooldownsDirty")
    end

    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

    -- Combat events
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")

    -- Charge change events (proc-granted charges, recharges, etc.)
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "OnChargesChanged")

    -- Spell activation overlay (proc glow) events
    -- Track state via events instead of polling IsSpellOverlayed
    -- (that API is AllowedWhenUntainted — calling from addon code causes taint)
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnProcGlowShow")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnProcGlowHide")

    -- Spell override icon changes (talents, procs morphing spells)
    self:RegisterEvent("SPELL_UPDATE_ICON", "OnSpellUpdateIcon")

    -- Event-driven range checking (replaces per-tick IsSpellInRange polling)
    self:RegisterEvent("SPELL_RANGE_CHECK_UPDATE", "OnSpellRangeCheckUpdate")

    -- Inventory changes — refresh config panel (!) indicators for items
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnBagChanged")

    -- Talent change events — refresh group frames and config panel
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentsChanged")

    -- Pet summon/dismiss — show/hide pet spell buttons dynamically
    self:RegisterEvent("UNIT_PET", "OnPetChanged")

    -- Specialization change events — show/hide groups based on spec filter
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "OnSpecChanged")
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

    -- Aura (buff/debuff) changes — drives aura tracking overlay
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")

    -- Target change — marks dirty so ticker reads fresh viewer data next pass
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")

    -- UNIT_TARGET requires RegisterUnitEvent (plain RegisterEvent does not
    -- receive it).  Marks dirty so the next ticker pass reads fresh CDM viewer
    -- data; catches pet/focus target changes that don't fire PLAYER_TARGET_CHANGED.
    if not self._unitTargetFrame then
        self._unitTargetFrame = CreateFrame("Frame")
        self._unitTargetFrame:SetScript("OnEvent", function()
            self._cooldownsDirty = true
            self:UpdateAllCooldowns()
        end)
    end
    self._unitTargetFrame:RegisterUnitEvent("UNIT_TARGET", "player")

    -- Rebuild viewer aura map when Cooldown Manager layout changes (user rearranges spells)
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
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

    -- Cache current spec before creating frames (visibility depends on it)
    self:CacheCurrentSpec()

    -- Run all data migrations (ownership, alpha, display mode, style, etc.)
    self:RunAllMigrations()

    -- Initialize alpha fade state (runtime only, not saved)
    self.alphaState = {}

    -- Create all group frames
    self:CreateAllGroupFrames()

    -- Start a ticker to update cooldowns periodically
    -- This ensures cooldowns update even if events don't fire
    self.updateTicker = C_Timer.NewTicker(0.1, function()
        -- Read assisted combat recommended spell (plain table field, no API call)
        if AssistedCombatManager then
            self.assistedSpellID = AssistedCombatManager.lastNextCastSpellID
        end

        self:UpdateAllCooldowns()
        self:UpdateAllGroupLayouts()
        self._cooldownsDirty = false
    end)

    -- Start the alpha fade OnUpdate frame (~30Hz for smooth fading)
    self:InitAlphaUpdateFrame()
end

function CooldownCompanion:MarkCooldownsDirty()
    self._cooldownsDirty = true
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

    -- Disable all range check registrations
    for spellId in pairs(self._rangeCheckSpells) do
        C_Spell.EnableSpellRangeCheck(spellId, false)
    end
    wipe(self._rangeCheckSpells)

    -- Unregister UNIT_TARGET frame (keep reference for reuse on re-enable)
    if self._unitTargetFrame then
        self._unitTargetFrame:UnregisterAllEvents()
    end

    -- Unregister EventRegistry callback (not managed by Ace3)
    EventRegistry:UnregisterCallback("CooldownViewerSettings.OnDataChanged", self)

    -- Hide all frames
    for _, frame in pairs(self.groupFrames) do
        frame:Hide()
    end
end

function CooldownCompanion:OnChargesChanged()
    if self._hasDisplayCountCandidates then
        self:RefreshChargeFlags("spell")
    end
    self:UpdateAllCooldowns()
end

function CooldownCompanion:OnProcGlowShow(event, spellID)
    self.procOverlaySpells[spellID] = true
    self:UpdateAllCooldowns()
end

function CooldownCompanion:OnProcGlowHide(event, spellID)
    self.procOverlaySpells[spellID] = nil
    self._cooldownsDirty = true
end

function CooldownCompanion:OnSpellCast(event, unit, castGUID, spellID)
    if unit == "player" then
        -- Mark the cast spell's buttons so ContextuallySecret cooldown logic can
        -- treat only this cast-start GCD as a potential false GCD-only window.
        local holdUntil = GetTime() + 2
        self:ForEachButton(function(button, buttonData)
            if buttonData.type == "spell"
               and not buttonData.isPassive then
                local displaySpellID = button._displaySpellId or buttonData.id
                if spellID == buttonData.id or spellID == displaySpellID then
                    if buttonData.hasCharges then
                        -- Track charge consumption for restricted-mode color heuristic.
                        -- _chargeRecharging at event time reflects the PRE-cast state:
                        --   false = casting from full charges → reset to 1
                        --   true  = already recharging → increment
                        if not button._chargeRecharging then
                            button._chargesSpent = 1
                        else
                            button._chargesSpent = (button._chargesSpent or 0) + 1
                        end
                    else
                        button._postCastGCDHold = true
                        button._postCastGCDHoldUntil = holdUntil
                    end
                end
            end
        end)
        self:UpdateAllCooldowns()
    end
end


function CooldownCompanion:OnCombatStart()
    self:UpdateAllCooldowns()
    -- Close spellbook during combat to avoid Blizzard secret value errors
    if PlayerSpellsFrame and PlayerSpellsFrame:IsShown() then
        HideUIPanel(PlayerSpellsFrame)
    end
    -- Hide config panel during combat to avoid protected frame errors
    if self._configWasOpen == nil then
        self._configWasOpen = false
    end
    local configFrame = self:GetConfigFrame()
    if configFrame and configFrame.frame:IsShown() then
        self._configWasOpen = true
        configFrame.frame:Hide()
        self:Print("Config closed for combat. It will reopen when combat ends.")
    end
end

function CooldownCompanion:OnCombatEnd()
    self:UpdateAllCooldowns()
    self:ApplyCdmAlpha()
    -- Reopen config panel if it was open before combat
    if self._configWasOpen then
        self._configWasOpen = false
        self:ToggleConfig()
    end
end


function CooldownCompanion:SlashCommand(input)
    input = tostring(input or ""):lower()
    input = input:match("^%s*(.-)%s*$")

    local function OpenConfigIfNeeded()
        local configFrame = self:GetConfigFrame()
        if configFrame and configFrame._miniFrame and configFrame._miniFrame:IsShown() then
            configFrame._miniFrame:Hide()
            return
        end
        if not configFrame or not configFrame.frame:IsShown() then
            self:ToggleConfig()
        end
    end

    local function SwitchPrimaryConfigMode(mode)
        if ST._SetConfigPrimaryMode then
            ST._SetConfigPrimaryMode(mode)
            return
        end
        if ST._configState then
            ST._configState.resourceBarPanelActive = (mode == "bars")
        end
        self:RefreshConfigPanel()
    end

    if input == "lock" or input == "unlock" then
        -- Toggle: if any visible group is unlocked, lock all; otherwise unlock all
        local anyUnlocked = false
        for groupId, group in pairs(self.db.profile.groups) do
            if self:IsGroupVisibleToCurrentChar(groupId) and not group.locked then
                anyUnlocked = true
                break
            end
        end
        if anyUnlocked then
            for groupId, group in pairs(self.db.profile.groups) do
                if self:IsGroupVisibleToCurrentChar(groupId) then
                    group.locked = true
                end
            end
            self:LockAllFrames()
            self:RefreshConfigPanel()
            self:Print("All frames locked.")
        else
            for groupId, group in pairs(self.db.profile.groups) do
                if self:IsGroupVisibleToCurrentChar(groupId) then
                    group.locked = false
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
        if InCombatLockdown() then
            self:ToggleConfig()
            return
        end
        OpenConfigIfNeeded()
        SwitchPrimaryConfigMode("bars")
    elseif input == "buttons" then
        if InCombatLockdown() then
            self:ToggleConfig()
            return
        end
        OpenConfigIfNeeded()
        SwitchPrimaryConfigMode("buttons")
    elseif input == "reset" then
        StaticPopup_Show("CDC_RESET_PROFILE", self.db:GetCurrentProfile(),
            nil, { profileName = self.db:GetCurrentProfile() })
    elseif input == "debugimport" then
        self:OpenDiagnosticDecodePanel()
    else
        self:ToggleConfig()
    end
end
