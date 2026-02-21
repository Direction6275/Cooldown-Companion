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

    -- Zone/instance change events — load condition evaluation
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA", "OnZoneChanged")
    self:RegisterEvent("PLAYER_UPDATE_RESTING", "OnRestingChanged")

    -- Aura (buff/debuff) changes — drives aura tracking overlay
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")

    -- Target change — marks dirty so ticker reads fresh viewer data next pass
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")

    -- UNIT_TARGET requires RegisterUnitEvent (plain RegisterEvent does not
    -- receive it).  Marks dirty so the next ticker pass reads fresh CDM viewer
    -- data; catches pet/focus target changes that don't fire PLAYER_TARGET_CHANGED.
    local utFrame = CreateFrame("Frame")
    utFrame:RegisterUnitEvent("UNIT_TARGET", "player")
    utFrame:SetScript("OnEvent", function()
        self._cooldownsDirty = true
    end)

    -- Rebuild viewer aura map when Cooldown Manager layout changes (user rearranges spells)
    EventRegistry:RegisterCallback("CooldownViewerSettings.OnDataChanged", function()
        C_Timer.After(0.2, function()
            self:BuildViewerAuraMap()
            self:RefreshConfigPanel()
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
                if CooldownCompanion.db
                   and CooldownCompanion.db.profile.cdmHidden then
                    for _, child in pairs({frame:GetChildren()}) do
                        child:SetMouseMotionEnabled(false)
                    end
                end
            end)
        end
    end

    -- Keybind text events
    self:RegisterEvent("UPDATE_BINDINGS", "OnBindingsChanged")
    self:RegisterEvent("ACTIONBAR_SLOT_CHANGED", "OnActionBarSlotChanged")

    -- Cache player class for class-specific checks (e.g. Druid Travel Form)
    self._playerClassID = select(3, UnitClass("player"))

    -- Cache current spec before creating frames (visibility depends on it)
    self:CacheCurrentSpec()

    -- Migrate legacy groups to have ownership fields
    self:MigrateGroupOwnership()

    -- Migrate legacy folders to have ownership fields
    self:MigrateFolderOwnership()

    -- Reclaim orphaned groups/folders from realm renames
    self:MigrateOrphanedGroups()

    -- Migrate old hide-when fields to alpha system
    self:MigrateAlphaSystem()

    -- Migrate groups to have displayMode field
    self:MigrateDisplayMode()

    -- Migrate groups to have masqueEnabled field
    self:MigrateMasqueField()

    -- Remove orphaned barChargeMissingColor/barChargeSwipe fields (replaced by charge sub-bars)
    self:MigrateRemoveBarChargeOldFields()

    -- Migrate groups to have compactLayout field
    self:MigrateVisibility()

    -- Ensure folders table exists in profile
    self:MigrateFolders()

    -- Reverse-migrate: if MW was migrated to custom aura bar slot 1, restore it
    self:ReverseMigrateMW()

    -- Migrate flat custom aura bars to spec-keyed format
    self:MigrateCustomAuraBarsToSpecKeyed()

    -- Migrate font/texture paths to LibSharedMedia names
    self:MigrateLSMNames()

    -- Migrate per-button charge text to group style defaults + per-button overrides
    self:MigrateChargeTextToGroupStyle()

    -- Migrate per-button proc glow to style overrides
    self:MigrateProcGlowToStyleOverrides()

    -- Migrate glow appearance settings from per-button to group style
    self:MigrateGlowSettingsToGroupStyle()
    self:MigrateAuraIndicatorToGroupStyle()

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

    -- Hide all frames
    for _, frame in pairs(self.groupFrames) do
        frame:Hide()
    end
end

function CooldownCompanion:OnChargesChanged()
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
    -- Reopen config panel if it was open before combat
    if self._configWasOpen then
        self._configWasOpen = false
        self:ToggleConfig()
    end
end


function CooldownCompanion:SlashCommand(input)
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
        self:Print("/cdc lock - Toggle lock/unlock all group frames")
        self:Print("/cdc minimap - Toggle minimap icon")
        self:Print("/cdc reset - Reset profile to defaults")
    elseif input == "reset" then
        StaticPopup_Show("CDC_RESET_PROFILE", self.db:GetCurrentProfile(),
            nil, { profileName = self.db:GetCurrentProfile() })
    elseif input == "debugimport" then
        self:OpenDiagnosticDecodePanel()
    else
        self:ToggleConfig()
    end
end
