--[[
    CooldownCompanion - Track spells and items with customizable action bar style panels
]]

local ADDON_NAME, ST = ...

-- Create the main addon using Ace3
local CooldownCompanion = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
ST.Addon = CooldownCompanion
_G.CooldownCompanion = CooldownCompanion

-- Expose the private table for other modules
CooldownCompanion.ST = ST

-- Event-driven range check registry (spellID -> true)
CooldownCompanion._rangeCheckSpells = {}

-- Viewer-based aura tracking: spellID → cooldown viewer child frame
CooldownCompanion.viewerAuraFrames = {}

-- Event-driven proc glow tracking: spellID → true when overlay active
-- Replaces per-tick C_SpellActivationOverlay.IsSpellOverlayed polling
-- (that API is AllowedWhenUntainted and cannot be called from addon code in combat)
CooldownCompanion.procOverlaySpells = {}

-- Constants
ST.BUTTON_SIZE = 36
ST.BUTTON_SPACING = 2
ST.DEFAULT_BORDER_SIZE = 1
ST.DEFAULT_STRATA_ORDER = {"cooldown", "assistedHighlight", "chargeText", "procGlow"}

-- Minimap icon setup using LibDataBroker and LibDBIcon
local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

-- Masque skinning support (optional)
local Masque = LibStub("Masque", true)
local MasqueGroups = {} -- Maps groupId -> Masque Group object

CooldownCompanion.Masque = Masque
CooldownCompanion.MasqueGroups = MasqueGroups

local minimapButton = LDB:NewDataObject(ADDON_NAME, {
    type = "launcher",
    text = "Cooldown Companion",
    icon = "Interface\\AddOns\\CooldownCompanion\\Media\\cdcminimap",
    OnClick = function(self, button)
        if button == "LeftButton" then
            CooldownCompanion:ToggleConfig()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Cooldown Companion")
        tooltip:AddLine("|cffeda55fLeft-Click|r to open options", 0.2, 1, 0.2)
    end,
})

-- Default database structure
local defaults = {
    profile = {
        minimap = {
            hide = false,
        },
        hideInfoButtons = false,
        escClosesConfig = true,
        groups = {
            --[[
                [groupId] = {
                    name = "Group Name",
                    anchor = {
                        point = "CENTER",
                        relativeTo = "UIParent",
                        relativePoint = "CENTER",
                        x = 0,
                        y = 0,
                    },
                    buttons = {
                        [index] = {
                            type = "spell" or "item",
                            id = spellId or itemId,
                            name = "Spell/Item Name",
                        }
                    },
                    style = {
                        buttonSize = 36,
                        buttonSpacing = 2,
                        borderSize = 1,
                        borderColor = {0, 0, 0, 1},
                        backgroundColor = {0, 0, 0, 0.5},
                        orientation = "horizontal", -- "horizontal" or "vertical"
                        buttonsPerRow = 12,
                        showCooldownText = true,
                        cooldownFontSize = 12,
                        cooldownFontOutline = "OUTLINE",
                        cooldownFont = "Fonts\\FRIZQT__.TTF",
                        cooldownFontColor = {1, 1, 1, 1},
                        showAuraText = true, -- nil defaults to true via ~= false
                        auraTextFont = "Fonts\\FRIZQT__.TTF",
                        auraTextFontSize = 12,
                        auraTextFontOutline = "OUTLINE",
                        auraTextFontColor = {1, 1, 1, 1},
                        iconWidthRatio = 1.0, -- 1.0 = square, <1 = taller, >1 = wider
                        maintainAspectRatio = true, -- Prevent icon image stretching
                        showTooltips = true,
                        desaturateOnCooldown = false, -- Desaturate icon while on cooldown
                        showGCDSwipe = true, -- Show GCD swipe animation on icons
                        showOutOfRange = false, -- Red-tint icons when target is out of range
                        showAssistedHighlight = false, -- Highlight the assisted combat recommended spell
                        assistedHighlightStyle = "blizzard", -- "blizzard", "solid", or "proc"
                        assistedHighlightColor = {0.3, 1, 0.3, 0.9},
                        assistedHighlightBorderSize = 2,
                        assistedHighlightBlizzardOverhang = 32, -- % overhang for blizzard style
                        assistedHighlightProcOverhang = 32, -- % overhang for proc style
                        assistedHighlightProcColor = {1, 1, 1, 1},
                        showUnusable = true,
                        unusableColor = {0.3, 0.3, 0.6},
                        showLossOfControl = true,
                        lossOfControlColor = {1, 0, 0, 0.5},
                        procGlowOverhang = 32,
                        procGlowColor = {1, 1, 1, 1},
                        strataOrder = nil, -- custom layer order (array of 4 keys) or nil for default
                    },
                    enabled = true,
                    displayMode = "icons",    -- "icons" or "bars"
                    -- Alpha fade system
                    baselineAlpha = 1,        -- alpha when no force conditions met (0-1)
                    forceAlphaInCombat = false,
                    forceAlphaOutOfCombat = false,
                    forceAlphaMounted = false,
                    forceAlphaTargetExists = false,
                    forceAlphaMouseover = false,
                    -- Force-hidden conditions (drive alpha to 0)
                    forceHideInCombat = false,
                    forceHideOutOfCombat = false,
                    forceHideMounted = false,
                    fadeDelay = 1,            -- seconds before fading after mouseover ends
                    fadeInDuration = 0.2,     -- fade-in animation seconds
                    fadeOutDuration = 0.2,    -- fade-out animation seconds
                }
            ]]
        },
        nextGroupId = 1,
        globalStyle = {
            buttonSize = 36,
            buttonSpacing = 2,
            borderSize = 1,
            borderColor = {0, 0, 0, 1},
            cooldownFontSize = 12,
            cooldownFontOutline = "OUTLINE",
            cooldownFont = "Fonts\\FRIZQT__.TTF",
            cooldownFontColor = {1, 1, 1, 1},
            iconWidthRatio = 1.0,
            maintainAspectRatio = true,
            showTooltips = false,
            desaturateOnCooldown = false,
            showGCDSwipe = false,
            showOutOfRange = false,
            showAssistedHighlight = false,
            assistedHighlightStyle = "blizzard",
            assistedHighlightColor = {0.3, 1, 0.3, 0.9},
            assistedHighlightBorderSize = 2,
            assistedHighlightBlizzardOverhang = 32,
            assistedHighlightProcOverhang = 32,
            showUnusable = false,
            unusableColor = {0.3, 0.3, 0.6},
            showLossOfControl = false,
            lossOfControlColor = {1, 0, 0, 0.5},
            procGlowOverhang = 32,
            procGlowColor = {1, 1, 1, 1},
            assistedHighlightProcColor = {1, 1, 1, 1},
            strataOrder = nil,
            -- Bar display mode defaults
            barLength = 180,
            barHeight = 20,
            barColor = {0.2, 0.6, 1.0, 1.0},
            barCooldownColor = {0.6, 0.13, 0.18, 1.0},
            barBgColor = {0.1, 0.1, 0.1, 0.8},
            showBarIcon = true,
            showBarNameText = true,
            barNameFont = "Fonts\\FRIZQT__.TTF",
            barNameFontSize = 10,
            barNameFontOutline = "OUTLINE",
            barNameFontColor = {1, 1, 1, 1},
            showBarReadyText = false,
            barReadyText = "Ready",
            barReadyTextColor = {0.2, 1.0, 0.2, 1.0},
            barUpdateInterval = 0.025,  -- seconds between bar fill updates (~40Hz default)
        },
        locked = false,
        auraDurationCache = {},
        cdmHidden = false,
    },
}

function CooldownCompanion:OnInitialize()
    -- Initialize database
    self.db = LibStub("AceDB-3.0"):New("CooldownCompanionDB", defaults, true)

    -- Initialize storage tables
    self.groupFrames = {}
    self.buttonFrames = {}

    -- Register minimap icon
    LDBIcon:Register(ADDON_NAME, minimapButton, self.db.profile.minimap)

    -- Register chat commands
    self:RegisterChatCommand("cdc", "SlashCommand")
    self:RegisterChatCommand("cooldowncompanion", "SlashCommand")

    -- Initialize config
    self:SetupConfig()

    self:Print("Cooldown Companion loaded. Use /cdc to open settings. Use /cdc help for commands.")
end

function CooldownCompanion:OnEnable()
    -- Register cooldown events — set dirty flag, let ticker do the actual update.
    -- The 0.1s ticker runs regardless, so latency is at most ~100ms for
    -- event-triggered updates — indistinguishable visually since the cooldown
    -- frame animates independently. This prevents redundant full-update passes
    -- during event storms.
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "MarkCooldownsDirty")
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", "MarkCooldownsDirty")
    self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", "MarkCooldownsDirty")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")

    -- Combat events to trigger updates
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")

    -- Power updates for usability dimming
    self:RegisterEvent("UNIT_POWER_FREQUENT", "MarkCooldownsDirty")

    -- Loss of control events
    self:RegisterEvent("LOSS_OF_CONTROL_ADDED", "MarkCooldownsDirty")
    self:RegisterEvent("LOSS_OF_CONTROL_UPDATE", "MarkCooldownsDirty")

    -- Charge change events (proc-granted charges, recharges, etc.)
    self:RegisterEvent("SPELL_UPDATE_CHARGES", "OnChargesChanged")

    -- Spell activation overlay (proc glow) events
    -- Track state via events instead of polling IsSpellOverlayed
    -- (that API is AllowedWhenUntainted — calling from addon code causes taint)
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnProcGlowShow")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "OnProcGlowHide")

    -- Item count changes (inventory updates for tracked items)
    self:RegisterEvent("ITEM_COUNT_CHANGED", "MarkCooldownsDirty")

    -- Spell override icon changes (talents, procs morphing spells)
    self:RegisterEvent("SPELL_UPDATE_ICON", "OnSpellUpdateIcon")

    -- Event-driven range checking (replaces per-tick IsSpellInRange polling)
    self:RegisterEvent("SPELL_RANGE_CHECK_UPDATE", "OnSpellRangeCheckUpdate")

    -- Inventory changes — refresh config panel (!) indicators for items
    self:RegisterEvent("BAG_UPDATE_DELAYED", "OnBagChanged")

    -- Talent change events — refresh group frames and config panel
    self:RegisterEvent("TRAIT_CONFIG_UPDATED", "OnTalentsChanged")

    -- Specialization change events — show/hide groups based on spec filter
    self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED", "OnSpecChanged")

    -- Aura (buff/debuff) changes — drives aura tracking overlay
    self:RegisterEvent("UNIT_AURA", "OnUnitAura")

    -- Target change — marks dirty so ticker reads fresh viewer data next pass
    self:RegisterEvent("PLAYER_TARGET_CHANGED", "OnTargetChanged")

    -- UNIT_TARGET requires RegisterUnitEvent (plain RegisterEvent does not
    -- receive it).  CDM also uses this event to refresh target aura frames.
    local utFrame = CreateFrame("Frame")
    utFrame:RegisterUnitEvent("UNIT_TARGET", "player")
    utFrame:SetScript("OnEvent", function()
        self:UpdateAllCooldowns()
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

    -- Cache player class for class-specific checks (e.g. Druid Travel Form)
    self._playerClassID = select(3, UnitClass("player"))

    -- Cache current spec before creating frames (visibility depends on it)
    self:CacheCurrentSpec()

    -- Migrate legacy groups to have ownership fields
    self:MigrateGroupOwnership()

    -- Migrate old hide-when fields to alpha system
    self:MigrateAlphaSystem()

    -- Migrate groups to have displayMode field
    self:MigrateDisplayMode()

    -- Migrate groups to have masqueEnabled field
    self:MigrateMasqueField()

    -- Remove orphaned barChargeMissingColor/barChargeSwipe fields (replaced by charge sub-bars)
    self:MigrateRemoveBarChargeOldFields()

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
        self._cooldownsDirty = false
    end)

    -- Start the alpha fade OnUpdate frame (~30Hz for smooth fading)
    self:InitAlphaUpdateFrame()
end

function CooldownCompanion:MarkCooldownsDirty()
    self._cooldownsDirty = true
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
    -- A proc overlay appeared for this spell. If it's a charged spell,
    -- increment the charge count — during combat we can't read charges
    -- from the API (secret values), so this is our signal that a charge
    -- was granted by a proc.
    if InCombatLockdown() then
        self:IncrementChargeOnProc(spellID)
    end
    self:UpdateAllCooldowns()
end

function CooldownCompanion:OnProcGlowHide(event, spellID)
    self.procOverlaySpells[spellID] = nil
    self._cooldownsDirty = true
end

function CooldownCompanion:IncrementChargeOnProc(spellID)
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                if button.buttonData
                   and button.buttonData.type == "spell"
                   and button.buttonData.id == spellID
                   and button.buttonData.hasCharges
                   and button._chargeCount ~= nil
                   and button._chargeMax
                   and button._chargeCount < button._chargeMax then
                    button._chargeCount = button._chargeCount + 1
                    if button._chargeCount >= button._chargeMax then
                        -- At max: no recharge in progress
                        button._chargeCDStart = nil
                        button._chargeCDDuration = nil
                    else
                        -- Mark approximate new-recharge start so the catch-up
                        -- loop in DecrementChargeOnCast doesn't re-detect this
                        -- recovery. The ticker readback corrects to the real
                        -- value on the same UpdateAllCooldowns pass.
                        button._chargeCDStart = GetTime()
                    end
                    button._chargeText = button._chargeCount
                    button.count:SetText(button._chargeCount)
                end
            end
        end
    end
end

function CooldownCompanion:OnSpellCast(event, unit, castGUID, spellID)
    if unit == "player" then
        if InCombatLockdown() then
            self:DecrementChargeOnCast(spellID)
        end
        self:UpdateAllCooldowns()
    end
end

function CooldownCompanion:DecrementChargeOnCast(spellID)
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                if button.buttonData
                   and button.buttonData.type == "spell"
                   and button.buttonData.id == spellID
                   and button.buttonData.hasCharges
                   and button._chargeCount ~= nil then
                    -- Catch up on any charges that recovered since the last
                    -- ticker estimation (up to 0.1s stale). Without this, a
                    -- cast right after a recharge completes would see the old
                    -- count, skip the decrement, and desync.
                    if button._chargeCount < (button._chargeMax or 0)
                       and button._chargeCDStart and button._chargeCDDuration
                       and button._chargeCDDuration > 0 then
                        local now = GetTime()
                        while button._chargeCount < button._chargeMax
                              and now >= button._chargeCDStart + button._chargeCDDuration do
                            button._chargeCount = button._chargeCount + 1
                            button._chargeCDStart = button._chargeCDStart + button._chargeCDDuration
                        end
                    end
                    -- Decrement the charge count.
                    if button._chargeCount > 0 then
                        button._chargeCount = button._chargeCount - 1
                        -- If we were at max charges, a recharge just started now
                        if button._chargeCount == (button._chargeMax or 0) - 1 then
                            button._chargeCDStart = GetTime()
                            -- If _chargeCDDuration is 0 (spell was at max charges
                            -- pre-combat), use the persisted recharge duration
                            if not button._chargeCDDuration or button._chargeCDDuration == 0 then
                                button._chargeCDDuration = button.buttonData
                                    and button.buttonData.chargeCooldownDuration or 0
                            end
                        end
                    else
                        -- Estimation says 0 but the cast succeeded, so WoW
                        -- must have recovered a charge that our timing missed
                        -- (floating-point imprecision). Net result: 0 charges
                        -- (one recovered, one consumed). New recharge starts now.
                        button._chargeCDStart = GetTime()
                        if not button._chargeCDDuration or button._chargeCDDuration == 0 then
                            button._chargeCDDuration = button.buttonData
                                and button.buttonData.chargeCooldownDuration or 0
                        end
                    end
                    button._chargeText = button._chargeCount
                    button.count:SetText(button._chargeCount)
                end
            end
        end
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
        self.db:ResetProfile()
        self:RefreshAllGroups()
        self:Print("Profile reset.")
    else
        self:ToggleConfig()
    end
end

function CooldownCompanion:OnUnitAura(event, unit, updateInfo)
    self._cooldownsDirty = true
    if not updateInfo then return end

    -- Process removals first so refreshed auras (remove + add in same event) work
    if updateInfo.removedAuraInstanceIDs then
        for _, instId in ipairs(updateInfo.removedAuraInstanceIDs) do
            for _, frame in pairs(self.groupFrames) do
                if frame and frame.buttons then
                    for _, button in ipairs(frame.buttons) do
                        if button._auraInstanceID == instId
                           and button._auraUnit == unit then
                            button._auraInstanceID = nil
                            button._auraActive = false
                            button._inPandemic = false
                        end
                    end
                end
            end
        end
    end

    -- Update immediately — CDM viewer frames registered their event handlers
    -- before our addon loaded, so by the time this handler fires the CDM has
    -- already refreshed its children with fresh auraInstanceID data.
    if unit == "target" or unit == "player" then
        self:UpdateAllCooldowns()
    end
end

-- Clear aura state on buttons tracking a unit when that unit changes (target/focus switch).
-- The viewer will re-evaluate on its next tick; this ensures stale data is cleared promptly.
function CooldownCompanion:ClearAuraUnit(unitToken)
    local vf = self.viewerAuraFrames
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                if button.buttonData and button.buttonData.auraTracking then
                    local shouldClear = button._auraUnit == unitToken
                    -- _auraUnit defaults to "player" even for debuff-tracking buttons
                    -- whose viewer frame has auraDataUnit == "target".  Check the viewer
                    -- map as a fallback so target-switch clears actually reach them.
                    if not shouldClear and unitToken == "target" and vf then
                        local f = (button._auraSpellID and vf[button._auraSpellID])
                            or vf[button.buttonData.id]
                        shouldClear = f and f.auraDataUnit == "target"
                    end
                    if shouldClear then
                        button._auraInstanceID = nil
                        button._auraActive = false
                        button._inPandemic = false
                    end
                end
            end
        end
    end
    self._cooldownsDirty = true
end

function CooldownCompanion:OnTargetChanged()
    self._cooldownsDirty = true
end


function CooldownCompanion:ResolveAuraSpellID(buttonData)
    if not buttonData.auraTracking then return nil end
    if buttonData.auraSpellID then
        local first = tostring(buttonData.auraSpellID):match("%d+")
        return first and tonumber(first)
    end
    if buttonData.type == "spell" then
        local auraId = C_UnitAuras.GetCooldownAuraBySpellID(buttonData.id)
        if auraId and auraId ~= 0 then return auraId end
        -- Many spells share the same ID for cast and buff; fall back to the spell's own ID
        return buttonData.id
    end
    return nil
end

-- Hardcoded ability → buff overrides for spells whose ability ID and buff IDs
-- are completely unlinked by any API (GetCooldownAuraBySpellID returns 0).
-- Both Eclipse forms map to both buff IDs so whichever buff is active gets tracked.
-- Format: [abilitySpellID] = "comma-separated buff spell IDs"
CooldownCompanion.ABILITY_BUFF_OVERRIDES = {
    [1233346] = "48517,48518",  -- Solar Eclipse → Eclipse (Solar) + Eclipse (Lunar) buffs
    [1233272] = "48517,48518",  -- Lunar Eclipse → Eclipse (Solar) + Eclipse (Lunar) buffs
}

-- Viewer frame list used by BuildViewerAuraMap and FindViewerChildForSpell.
local VIEWER_NAMES = {
    "EssentialCooldownViewer",
    "UtilityCooldownViewer",
    "BuffIconCooldownViewer",
    "BuffBarCooldownViewer",
}

function CooldownCompanion:ApplyCdmAlpha()
    local alpha = self.db.profile.cdmHidden and 0 or 1
    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer then
            viewer:SetAlpha(alpha)
        end
    end
end

-- Build a mapping from spellID → Blizzard cooldown viewer child frame.
-- The viewer frames (EssentialCooldownViewer, UtilityCooldownViewer, etc.)
-- run untainted code that reads secret aura data and stores the result
-- (auraInstanceID, auraDataUnit) as plain frame properties we can read.
function CooldownCompanion:BuildViewerAuraMap()
    wipe(self.viewerAuraFrames)
    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer then
            for _, child in pairs({viewer:GetChildren()}) do
                if child.cooldownInfo then
                    local spellID = child.cooldownInfo.spellID
                    if spellID then
                        self.viewerAuraFrames[spellID] = child
                    end
                    local override = child.cooldownInfo.overrideSpellID
                    if override then
                        self.viewerAuraFrames[override] = child
                    end
                    local tooltipOverride = child.cooldownInfo.overrideTooltipSpellID
                    if tooltipOverride then
                        self.viewerAuraFrames[tooltipOverride] = child
                    end
                end
            end
        end
    end
    -- Ensure tracked buttons can find their viewer child even if
    -- buttonData.id is a non-current override form of a transforming spell.
    self:MapButtonSpellsToViewers()

    -- Map hardcoded overrides: ability IDs and buff IDs → viewer child.
    -- Group by buff string so sibling abilities (e.g. Solar/Lunar Eclipse)
    -- cross-map to the same viewer child even if only one form is current.
    local groupsByBuffs = {}
    for abilityID, buffIDStr in pairs(self.ABILITY_BUFF_OVERRIDES) do
        if not groupsByBuffs[buffIDStr] then
            groupsByBuffs[buffIDStr] = {}
        end
        groupsByBuffs[buffIDStr][#groupsByBuffs[buffIDStr] + 1] = abilityID
    end
    for buffIDStr, abilityIDs in pairs(groupsByBuffs) do
        -- Prefer a BuffIcon/BuffBar child (tracks aura duration) over
        -- Essential/Utility (tracks cooldown only). Check buff IDs first
        -- since the initial scan maps them to the correct viewer type.
        local child
        for id in buffIDStr:gmatch("%d+") do
            local c = self.viewerAuraFrames[tonumber(id)]
            if c then
                local p = c:GetParent()
                local pn = p and p:GetName()
                if pn == "BuffIconCooldownViewer" or pn == "BuffBarCooldownViewer" then
                    child = c
                    break
                end
            end
        end
        if not child then
            for _, abilityID in ipairs(abilityIDs) do
                child = self.viewerAuraFrames[abilityID]
                if child then break end
            end
        end
        if not child then
            for _, abilityID in ipairs(abilityIDs) do
                child = self:FindViewerChildForSpell(abilityID)
                if child then break end
            end
        end
        if child then
            for _, abilityID in ipairs(abilityIDs) do
                self.viewerAuraFrames[abilityID] = child
            end
            -- Map buff IDs only if they aren't already mapped by the initial scan.
            -- Each buff may have its own viewer child (e.g. Solar vs Lunar Eclipse).
            for id in buffIDStr:gmatch("%d+") do
                local numID = tonumber(id)
                if not self.viewerAuraFrames[numID] then
                    self.viewerAuraFrames[numID] = child
                end
            end
        end
    end
end

-- For each tracked button, ensure viewerAuraFrames contains an entry
-- for buttonData.id. Handles the case where the spell was added while
-- in one form (e.g. Solar Eclipse) but the map was rebuilt while the
-- spell is in a different form (e.g. Lunar Eclipse).
function CooldownCompanion:MapButtonSpellsToViewers()
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local id = button.buttonData.id
                if id and button.buttonData.type == "spell" and not self.viewerAuraFrames[id] then
                    local child = self:FindViewerChildForSpell(id)
                    if child then
                        self.viewerAuraFrames[id] = child
                    end
                end
            end
        end
    end
end

-- Scan viewer children to find one that tracks a given spellID.
-- Checks spellID, overrideSpellID, overrideTooltipSpellID on each child,
-- then uses GetBaseSpell to resolve override forms back to their base spell.
-- Returns the child frame if found, nil otherwise.
function CooldownCompanion:FindViewerChildForSpell(spellID)
    for _, name in ipairs(VIEWER_NAMES) do
        local viewer = _G[name]
        if viewer then
            for _, child in pairs({viewer:GetChildren()}) do
                if child.cooldownInfo then
                    if child.cooldownInfo.spellID == spellID
                       or child.cooldownInfo.overrideSpellID == spellID
                       or child.cooldownInfo.overrideTooltipSpellID == spellID then
                        return child
                    end
                end
            end
        end
    end
    -- GetBaseSpell (AllowedWhenTainted): resolve override → base, then check map.
    local baseSpellID = C_Spell.GetBaseSpell(spellID)
    if baseSpellID and baseSpellID ~= spellID then
        local child = self.viewerAuraFrames[baseSpellID]
        if child then
            return child
        end
    end
    -- Override table: check buff IDs and sibling abilities
    local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[spellID]
    if overrideBuffs then
        -- Check buff IDs in the map (viewer children may be keyed by buff spell ID)
        for id in overrideBuffs:gmatch("%d+") do
            local child = self.viewerAuraFrames[tonumber(id)]
            if child then return child end
        end
        -- Check sibling abilities that share the same viewer
        for sibID, sibBuffs in pairs(self.ABILITY_BUFF_OVERRIDES) do
            if sibBuffs == overrideBuffs and sibID ~= spellID then
                local child = self.viewerAuraFrames[sibID]
                if child then return child end
            end
        end
    end
    return nil
end

-- Find a cooldown viewer child (Essential/Utility only) for a spell.
-- Used by UpdateButtonIcon to get dynamic icon/name from the cooldown tracker
-- rather than the buff tracker (BuffIcon/BuffBar), which uses static buff spell IDs.
function CooldownCompanion:FindCooldownViewerChild(spellID)
    local cdViewers = {"EssentialCooldownViewer", "UtilityCooldownViewer"}
    for _, name in ipairs(cdViewers) do
        local viewer = _G[name]
        if viewer then
            for _, child in pairs({viewer:GetChildren()}) do
                if child.cooldownInfo then
                    if child.cooldownInfo.spellID == spellID
                       or child.cooldownInfo.overrideSpellID == spellID
                       or child.cooldownInfo.overrideTooltipSpellID == spellID then
                        return child
                    end
                end
            end
        end
    end
    -- Try base spell resolution
    local baseSpellID = C_Spell.GetBaseSpell(spellID)
    if baseSpellID and baseSpellID ~= spellID then
        return self:FindCooldownViewerChild(baseSpellID)
    end
    -- Try sibling abilities from override table
    local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[spellID]
    if overrideBuffs then
        for sibID, sibBuffs in pairs(self.ABILITY_BUFF_OVERRIDES) do
            if sibBuffs == overrideBuffs and sibID ~= spellID then
                for _, name in ipairs(cdViewers) do
                    local viewer = _G[name]
                    if viewer then
                        for _, child in pairs({viewer:GetChildren()}) do
                            if child.cooldownInfo then
                                if child.cooldownInfo.spellID == sibID
                                   or child.cooldownInfo.overrideSpellID == sibID
                                   or child.cooldownInfo.overrideTooltipSpellID == sibID then
                                    return child
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- When a spell transforms (e.g. Solar Eclipse → Lunar Eclipse), map the new
-- override spell ID to the same viewer child frame so lookups work for both forms.
function CooldownCompanion:OnViewerSpellOverrideUpdated(event, baseSpellID, overrideSpellID)
    if not baseSpellID then return end
    local child = self.viewerAuraFrames[baseSpellID]
    if child and overrideSpellID then
        self.viewerAuraFrames[overrideSpellID] = child
    end
    -- Refresh icons/names now that the viewer child's overrideSpellID is current
    self:OnSpellUpdateIcon()
    -- Update config panel if open (name, icon, usability may have changed)
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnSpellUpdateIcon()
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                self:UpdateButtonIcon(button)
            end
        end
    end
end

function CooldownCompanion:UpdateRangeCheckRegistrations()
    local newSet = {}
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                if button.buttonData.type == "spell"
                   and button.style and button.style.showOutOfRange then
                    newSet[button.buttonData.id] = true
                end
            end
        end
    end
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
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                if button.buttonData.type == "spell"
                   and button.buttonData.id == spellIdentifier then
                    button._spellOutOfRange = outOfRange
                end
            end
        end
    end
end

function CooldownCompanion:OnBagChanged()
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnTalentsChanged()
    self:RefreshChargeFlags()
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
end

-- Re-evaluate hasCharges on every spell button (talents can add/remove charges).
function CooldownCompanion:RefreshChargeFlags()
    for _, group in pairs(self.db.profile.groups) do
        for _, buttonData in ipairs(group.buttons) do
            if buttonData.type == "spell" then
                local charges = C_Spell.GetSpellCharges(buttonData.id)
                buttonData.hasCharges = (charges and charges.maxCharges and charges.maxCharges > 1) or nil
            end
        end
    end
end

function CooldownCompanion:CacheCurrentSpec()
    local specIndex = GetSpecialization()
    if specIndex then
        local specId = GetSpecializationInfo(specIndex)
        self._currentSpecId = specId
    end
end

function CooldownCompanion:OnSpecChanged()
    self:CacheCurrentSpec()
    self:RefreshChargeFlags()
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
    -- Rebuild viewer map after a short delay to let the viewer re-populate
    C_Timer.After(1, function()
        self:BuildViewerAuraMap()
    end)
end

function CooldownCompanion:OnPlayerEnteringWorld()
    C_Timer.After(1, function()
        self:CacheCurrentSpec()
        self:RefreshChargeFlags()
        self:RefreshAllGroups()
        self:BuildViewerAuraMap()
        self:ApplyCdmAlpha()
    end)
end

-- Masque Helper Functions
function CooldownCompanion:CreateMasqueGroup(groupId)
    if not Masque then return end
    local group = self.db.profile.groups[groupId]
    if not group then return end

    -- Use groupId as the static ID so Masque settings persist across sessions
    local masqueGroup = Masque:Group(ADDON_NAME, group.name or ("Group " .. groupId), tostring(groupId))
    MasqueGroups[groupId] = masqueGroup
    return masqueGroup
end

function CooldownCompanion:DeleteMasqueGroup(groupId)
    if not Masque then return end
    local masqueGroup = MasqueGroups[groupId]
    if masqueGroup then
        masqueGroup:Delete()
        MasqueGroups[groupId] = nil
    end
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
    if not Masque then return end
    local masqueGroup = MasqueGroups[groupId]
    if not masqueGroup then return end

    local regions = self:GetMasqueRegions(button)
    -- Type "Action" is standard for action-bar-like buttons
    -- Strict=true tells Masque to only use the regions we provide
    masqueGroup:AddButton(button, regions, "Action", true)

    -- Hide CC's custom border/bg when Masque is active
    self:SetButtonBorderVisible(button, false)
end

function CooldownCompanion:RemoveButtonFromMasque(groupId, button)
    if not Masque then return end
    local masqueGroup = MasqueGroups[groupId]
    if not masqueGroup then return end

    masqueGroup:RemoveButton(button)

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
    if not Masque then return end

    local group = self.db.profile.groups[groupId]
    if not group then return end

    group.masqueEnabled = enable

    if enable then
        -- Force square icons when Masque is enabled (non-square causes stretching)
        group.style.maintainAspectRatio = true

        -- Create Masque group if it doesn't exist
        if not MasqueGroups[groupId] then
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

-- Group Management Functions
function CooldownCompanion:CreateGroup(name)
    local groupId = self.db.profile.nextGroupId
    self.db.profile.nextGroupId = groupId + 1
    
    self.db.profile.groups[groupId] = {
        name = name or "New Group",
        anchor = {
            point = "CENTER",
            relativeTo = "UIParent",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
        buttons = {},
        style = CopyTable(self.db.profile.globalStyle),
        enabled = true,
        locked = false,
        order = groupId,
        createdBy = self.db.keys.char,
        isGlobal = false,
    }

    self.db.profile.groups[groupId].style.orientation = "horizontal"
    self.db.profile.groups[groupId].style.buttonsPerRow = 12
    self.db.profile.groups[groupId].style.showCooldownText = true

    -- Alpha fade defaults
    self.db.profile.groups[groupId].baselineAlpha = 1
    self.db.profile.groups[groupId].fadeDelay = 1
    self.db.profile.groups[groupId].fadeInDuration = 0.2
    self.db.profile.groups[groupId].fadeOutDuration = 0.2

    -- Display mode default
    self.db.profile.groups[groupId].displayMode = "icons"

    -- Masque defaults
    self.db.profile.groups[groupId].masqueEnabled = false

    -- Create the frame for this group
    self:CreateGroupFrame(groupId)
    
    return groupId
end

function CooldownCompanion:DeleteGroup(groupId)
    -- Clean up Masque group before deleting
    self:DeleteMasqueGroup(groupId)

    if self.groupFrames[groupId] then
        self.groupFrames[groupId]:Hide()
        self.groupFrames[groupId] = nil
    end
    self.db.profile.groups[groupId] = nil
end

function CooldownCompanion:DuplicateGroup(groupId)
    local sourceGroup = self.db.profile.groups[groupId]
    if not sourceGroup then return nil end

    local newGroupId = self.db.profile.nextGroupId
    self.db.profile.nextGroupId = newGroupId + 1

    -- Deep copy the entire group
    local newGroup = CopyTable(sourceGroup)

    -- Change the name
    newGroup.name = sourceGroup.name .. " (Copy)"

    -- Assign new order (place after source group)
    newGroup.order = newGroupId

    -- Set ownership to current character
    newGroup.createdBy = self.db.keys.char
    newGroup.isGlobal = false

    self.db.profile.groups[newGroupId] = newGroup

    -- Create the frame for the new group
    self:CreateGroupFrame(newGroupId)

    return newGroupId
end

function CooldownCompanion:AddButtonToGroup(groupId, buttonType, id, name)
    local group = self.db.profile.groups[groupId]
    if not group then return end
    
    local buttonIndex = #group.buttons + 1
    group.buttons[buttonIndex] = {
        type = buttonType,
        id = id,
        name = name,
    }

    -- Auto-detect charges for spells
    if buttonType == "spell" then
        local charges = C_Spell.GetSpellCharges(id)
        if charges and charges.maxCharges and charges.maxCharges > 1 then
            group.buttons[buttonIndex].hasCharges = true
        end
    end

    self:RefreshGroupFrame(groupId)
    return buttonIndex
end

function CooldownCompanion:RemoveButtonFromGroup(groupId, buttonIndex)
    local group = self.db.profile.groups[groupId]
    if not group then return end
    
    table.remove(group.buttons, buttonIndex)
    self:RefreshGroupFrame(groupId)
end

-- Walk the class talent tree using the active config, calling visitor(defInfo)
-- for each definition. The tree is shared across all specs, so the active config
-- can query nodes for every specialization.
-- If visitor returns a truthy value, stop and return that value.
local function WalkTalentTree(visitor)
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return nil end
    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo or not configInfo.treeIDs then return nil end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        if nodes then
            for _, nodeID in ipairs(nodes) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo and nodeInfo.entryIDs then
                    for _, entryID in ipairs(nodeInfo.entryIDs) do
                        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                        if entryInfo and entryInfo.definitionID then
                            local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                            if defInfo then
                                local result = visitor(defInfo)
                                if result then return result end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Search spec display spells (key abilities shown on the spec selection screen)
-- across all specs for the player's class.
local function FindDisplaySpell(matcher)
    local _, _, classID = UnitClass("player")
    if not classID then return nil end
    local numSpecs = GetNumSpecializationsForClassID(classID)
    for specIndex = 1, numSpecs do
        local specID = GetSpecializationInfoForClassID(classID, specIndex)
        if specID then
            local ids = C_SpecializationInfo.GetSpellsDisplay(specID)
            if ids then
                for _, spellID in ipairs(ids) do
                    local result = matcher(spellID)
                    if result then return result end
                end
            end
        end
    end
    return nil
end

-- Search the off-spec spellbook for a spell by name or ID.
-- Returns spellID, name if found; nil otherwise.
local function FindOffSpecSpell(spellIdentifier)
    local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(spellIdentifier, false, true, false, true)
    if not slot then return nil end
    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
    if info and info.spellID then
        return info.spellID, info.name
    end
    return nil
end

function CooldownCompanion:FindTalentSpellByName(name)
    local lowerName = name:lower()

    -- 1) Search talent tree (covers all talent choices across specs)
    local result = WalkTalentTree(function(defInfo)
        if defInfo.spellID then
            if C_Spell.IsSpellPassive(defInfo.spellID) then return nil end
            local spellInfo = C_Spell.GetSpellInfo(defInfo.spellID)
            if spellInfo and spellInfo.name and spellInfo.name:lower() == lowerName then
                return { defInfo.spellID, spellInfo.name }
            end
        end
    end)
    if result then return result[1], result[2] end

    -- 2) Search spec display spells (key baseline abilities per spec)
    result = FindDisplaySpell(function(spellID)
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.name and spellInfo.name:lower() == lowerName then
            if not C_Spell.IsSpellPassive(spellID) then
                return { spellID, spellInfo.name }
            end
        end
    end)
    if result then return result[1], result[2] end

    -- 3) Search off-spec spellbook (covers previously activated specs)
    local spellID, spellName = FindOffSpecSpell(name)
    if spellID and spellName then return spellID, spellName end

    return nil
end


function CooldownCompanion:MigrateGroupOwnership()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.createdBy == nil and group.isGlobal == nil then
            group.isGlobal = true
            group.createdBy = "migrated"
        end
    end
end

function CooldownCompanion:MigrateAlphaSystem()
    for groupId, group in pairs(self.db.profile.groups) do
        -- Remove old hide fields
        group.hideWhileMounted = nil
        group.hideInCombat = nil
        group.hideOutOfCombat = nil
        group.hideNoTarget = nil
        -- Remove deprecated force-hide fields (replaced by force-visible-only checkboxes)
        group.forceHideTargetExists = nil
        group.forceHideMouseover = nil
        -- Ensure new defaults exist
        if group.baselineAlpha == nil then group.baselineAlpha = 1 end
        if group.fadeDelay == nil then group.fadeDelay = 1 end
        if group.fadeInDuration == nil then group.fadeInDuration = 0.2 end
        if group.fadeOutDuration == nil then group.fadeOutDuration = 0.2 end
    end
end

function CooldownCompanion:MigrateDisplayMode()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.displayMode == nil then
            group.displayMode = "icons"
        end
    end
end

function CooldownCompanion:MigrateMasqueField()
    for groupId, group in pairs(self.db.profile.groups) do
        if group.masqueEnabled == nil then
            group.masqueEnabled = false
        end
        -- If Masque addon is not available but group had it enabled, disable it
        if group.masqueEnabled and not Masque then
            group.masqueEnabled = false
        end
    end
end

function CooldownCompanion:MigrateRemoveBarChargeOldFields()
    for _, group in pairs(self.db.profile.groups) do
        if group.style then
            group.style.barChargeGap = nil
        end
        if group.buttons then
            for _, bd in ipairs(group.buttons) do
                bd.barChargeMissingColor = nil
                bd.barChargeSwipe = nil
            end
        end
    end
end

function CooldownCompanion:IsGroupVisibleToCurrentChar(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if group.isGlobal then return true end
    return group.createdBy == self.db.keys.char
end

-- Alpha fade system: per-group runtime state
-- self.alphaState[groupId] = {
--     currentAlpha   - current interpolated alpha
--     desiredAlpha   - target alpha (1.0 or baselineAlpha)
--     fadeStartAlpha - alpha at start of current fade
--     fadeDuration   - duration of current fade
--     fadeStartTime  - GetTime() when current fade began
--     hoverExpire    - GetTime() when mouseover grace period ends
-- }

local function UpdateFadedAlpha(state, desired, now, fadeInDur, fadeOutDur)
    -- Initialize on first call
    if state.currentAlpha == nil then
        state.currentAlpha = 1.0
        state.desiredAlpha = 1.0
        state.fadeDuration = 0
    end

    -- Start a new fade when desired target changes
    if state.desiredAlpha ~= desired then
        state.fadeStartAlpha = state.currentAlpha
        state.desiredAlpha = desired
        state.fadeStartTime = now

        local dur = 0
        if desired > state.currentAlpha then
            dur = fadeInDur or 0
        else
            dur = fadeOutDur or 0
        end
        state.fadeDuration = dur or 0

        -- Instant snap when duration is zero
        if state.fadeDuration <= 0 then
            state.currentAlpha = desired
            return desired
        end
    end

    -- Actively fading
    if state.fadeDuration and state.fadeDuration > 0 then
        local t = (now - (state.fadeStartTime or now)) / state.fadeDuration
        if t >= 1 then
            state.currentAlpha = state.desiredAlpha
            state.fadeDuration = 0
        elseif t < 0 then
            t = 0
        end

        if state.fadeDuration > 0 then
            local startAlpha = state.fadeStartAlpha or state.currentAlpha
            state.currentAlpha = startAlpha + (state.desiredAlpha - startAlpha) * t
        end
    else
        state.currentAlpha = desired
    end

    return state.currentAlpha
end

function CooldownCompanion:UpdateGroupAlpha(groupId, group, frame, now, inCombat, hasTarget, mounted, inTravelForm)
    local state = self.alphaState[groupId]
    if not state then
        state = {}
        self.alphaState[groupId] = state
    end

    -- Force 100% alpha while group is unlocked for easier positioning
    if not group.locked then
        if state.currentAlpha ~= 1 or state.lastAlpha ~= 1 then
            frame:SetAlpha(1)
            state.currentAlpha = 1
            state.desiredAlpha = 1
            state.fadeDuration = 0
            state.lastAlpha = 1
        end
        return
    end

    -- Skip processing when feature is entirely unused (baseline=1, no forceHide toggles)
    local hasForceHide = group.forceHideInCombat or group.forceHideOutOfCombat
        or group.forceHideMounted
    if group.baselineAlpha == 1 and not hasForceHide then
        -- Reset state so it doesn't carry stale values if settings change later
        if state.currentAlpha and state.currentAlpha ~= 1 then
            frame:SetAlpha(1)
            state.currentAlpha = 1
            state.desiredAlpha = 1
            state.fadeDuration = 0
        end
        return
    end

    -- Effective mounted state: real mount OR travel form (if opted in)
    local effectiveMounted = mounted or (group.treatTravelFormAsMounted and inTravelForm)

    -- Check force-hidden conditions
    local forceHidden = false
    if group.forceHideInCombat and inCombat then
        forceHidden = true
    elseif group.forceHideOutOfCombat and not inCombat then
        forceHidden = true
    elseif group.forceHideMounted and effectiveMounted then
        forceHidden = true
    end

    -- Check force-visible conditions (priority: visible > hidden > baseline)
    local forceFull = false
    if group.forceAlphaInCombat and inCombat then
        forceFull = true
    elseif group.forceAlphaOutOfCombat and not inCombat then
        forceFull = true
    elseif group.forceAlphaMounted and effectiveMounted then
        forceFull = true
    elseif group.forceAlphaTargetExists and hasTarget then
        forceFull = true
    end

    -- Mouseover check (geometric, works even when click-through)
    if not forceFull and group.forceAlphaMouseover then
        local isHovering = frame:IsMouseOver()
        if isHovering then
            forceFull = true
            state.hoverExpire = now + (group.fadeDelay or 1)
        elseif state.hoverExpire and now < state.hoverExpire then
            forceFull = true
        end
    end

    local desired = forceFull and 1 or (forceHidden and 0 or group.baselineAlpha)
    local alpha = UpdateFadedAlpha(state, desired, now, group.fadeInDuration, group.fadeOutDuration)

    -- Only call SetAlpha when value actually changes
    if state.lastAlpha ~= alpha then
        frame:SetAlpha(alpha)
        state.lastAlpha = alpha
    end
end

function CooldownCompanion:InitAlphaUpdateFrame()
    if self._alphaFrame then return end

    local alphaFrame = CreateFrame("Frame")
    self._alphaFrame = alphaFrame
    local accumulator = 0
    local UPDATE_INTERVAL = 1 / 30 -- ~30Hz for smooth fading

    local function GroupNeedsAlphaUpdate(group)
        if group.baselineAlpha < 1 then return true end
        return group.forceHideInCombat or group.forceHideOutOfCombat
            or group.forceHideMounted
    end

    alphaFrame:SetScript("OnUpdate", function(_, dt)
        accumulator = accumulator + (dt or 0)
        if accumulator < UPDATE_INTERVAL then return end
        accumulator = 0

        local now = GetTime()
        local inCombat = InCombatLockdown()
        local hasTarget = UnitExists("target")
        local mounted = IsMounted()

        local inTravelForm = false
        if self._playerClassID == 11 then -- Druid
            local fi = GetShapeshiftForm()
            if fi and fi > 0 then
                local _, _, _, spellID = GetShapeshiftFormInfo(fi)
                if spellID == 783 then inTravelForm = true end
            end
        end

        for groupId, group in pairs(self.db.profile.groups) do
            local frame = self.groupFrames[groupId]
            if frame and frame:IsShown() and GroupNeedsAlphaUpdate(group) then
                self:UpdateGroupAlpha(groupId, group, frame, now, inCombat, hasTarget, mounted, inTravelForm)
            end
        end
    end)
end

function CooldownCompanion:ToggleGroupGlobal(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return end
    group.isGlobal = not group.isGlobal
    if not group.isGlobal then
        group.createdBy = self.db.keys.char
    end
    self:RefreshAllGroups()
end

function CooldownCompanion:IsButtonUsable(buttonData)
    if buttonData.type == "spell" then
        if IsSpellKnownOrOverridesKnown(buttonData.id) or IsPlayerSpell(buttonData.id) then
            return true
        end
        -- Safety net for override forms (pre-existing data before add-time normalization).
        local baseID = C_Spell.GetBaseSpell(buttonData.id)
        if baseID and baseID ~= buttonData.id then
            return IsSpellKnownOrOverridesKnown(baseID) or IsPlayerSpell(baseID)
        end
        return false
    elseif buttonData.type == "item" then
        return GetItemCount(buttonData.id) > 0
    end
    return true
end

function CooldownCompanion:CreateAllGroupFrames()
    for groupId, _ in pairs(self.db.profile.groups) do
        if self:IsGroupVisibleToCurrentChar(groupId) then
            self:CreateGroupFrame(groupId)
        end
    end
end

function CooldownCompanion:RefreshAllGroups()
    for groupId, _ in pairs(self.db.profile.groups) do
        if self:IsGroupVisibleToCurrentChar(groupId) then
            self:RefreshGroupFrame(groupId)
        else
            if self.groupFrames[groupId] then
                self.groupFrames[groupId]:Hide()
            end
        end
    end
end

function CooldownCompanion:UpdateAllCooldowns()
    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame.UpdateCooldowns then
            frame:UpdateCooldowns()
        end
    end
end

function CooldownCompanion:LockAllFrames()
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            if frame.dragHandle then
                frame.dragHandle:Hide()
            end
        end
    end
end

function CooldownCompanion:UnlockAllFrames()
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            if frame.dragHandle then
                frame.dragHandle:Show()
            end
            -- Force 100% alpha while unlocked for easier positioning
            frame:SetAlpha(1)
        end
    end
end

-- Utility functions
function CooldownCompanion:GetSpellInfo(spellId)
    local spellInfo = C_Spell.GetSpellInfo(spellId)
    if spellInfo then
        return spellInfo.name, spellInfo.iconID, spellInfo.castTime
    end
    return nil
end

function CooldownCompanion:GetItemInfo(itemId)
    local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemId)
    if not itemName then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemId)
        return nil, icon
    end
    return itemName, itemIcon
end
