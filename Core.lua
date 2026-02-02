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

-- Constants
ST.BUTTON_SIZE = 36
ST.BUTTON_SPACING = 2
ST.DEFAULT_BORDER_SIZE = 1
ST.DEFAULT_STRATA_ORDER = {"cooldown", "assistedHighlight", "chargeText", "procGlow"}

-- Minimap icon setup using LibDataBroker and LibDBIcon
local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")

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
        },
        locked = false,
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

    self:Print("Cooldown Companion loaded. Type /cdc for options.")
end

-- Pre-defined at file scope to avoid creating a closure every tick
local function FetchAssistedSpell()
    return C_AssistedCombat and C_AssistedCombat.GetNextCastSpell()
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
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_SHOW", "OnProcGlowShow")
    self:RegisterEvent("SPELL_ACTIVATION_OVERLAY_GLOW_HIDE", "MarkCooldownsDirty")

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

    -- Cache current spec before creating frames (visibility depends on it)
    self:CacheCurrentSpec()

    -- Create all group frames
    self:CreateAllGroupFrames()

    -- Start a ticker to update cooldowns periodically
    -- This ensures cooldowns update even if events don't fire
    self.updateTicker = C_Timer.NewTicker(0.1, function()
        -- Fetch assisted combat recommended spell (may not exist on older clients)
        local ok, spellID = pcall(FetchAssistedSpell)
        self.assistedSpellID = ok and spellID or nil

        self:UpdateAllCooldowns()
        self._cooldownsDirty = false
    end)
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
    -- A proc overlay appeared for this spell. If it's a charged spell,
    -- increment the charge count — during combat we can't read charges
    -- from the API (secret values), so this is our signal that a charge
    -- was granted by a proc.
    if InCombatLockdown() then
        self:IncrementChargeOnProc(spellID)
    end
    self:UpdateAllCooldowns()
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
                    -- If now at max, no recharge in progress
                    if button._chargeCount >= button._chargeMax then
                        button._chargeCDStart = nil
                        button._chargeCDDuration = nil
                    end
                    -- Don't touch _chargeCDStart when not at max — the
                    -- existing recharge timer is still running and the
                    -- estimation loop should continue from where it was.
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
    if input == "lock" then
        for _, group in pairs(self.db.profile.groups) do
            group.locked = true
        end
        self:LockAllFrames()
        self:Print("All frames locked.")
    elseif input == "unlock" then
        for _, group in pairs(self.db.profile.groups) do
            group.locked = false
        end
        self:UnlockAllFrames()
        self:Print("All frames unlocked. Drag to move.")
    elseif input == "reset" then
        self.db:ResetProfile()
        self:RefreshAllGroups()
        self:Print("Profile reset.")
    else
        self:ToggleConfig()
    end
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
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
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
    self:RefreshAllGroups()
    self:RefreshConfigPanel()
end

function CooldownCompanion:OnPlayerEnteringWorld()
    C_Timer.After(1, function()
        self:CacheCurrentSpec()
        self:RefreshAllGroups()
    end)
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
    }

    self.db.profile.groups[groupId].style.orientation = "horizontal"
    self.db.profile.groups[groupId].style.buttonsPerRow = 12
    self.db.profile.groups[groupId].style.showCooldownText = true
    
    -- Create the frame for this group
    self:CreateGroupFrame(groupId)
    
    return groupId
end

function CooldownCompanion:DeleteGroup(groupId)
    if self.groupFrames[groupId] then
        self.groupFrames[groupId]:Hide()
        self.groupFrames[groupId] = nil
    end
    self.db.profile.groups[groupId] = nil
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


function CooldownCompanion:IsButtonUsable(buttonData)
    if buttonData.type == "spell" then
        return IsSpellKnownOrOverridesKnown(buttonData.id) or IsPlayerSpell(buttonData.id)
    elseif buttonData.type == "item" then
        return GetItemCount(buttonData.id) > 0
    end
    return true
end

function CooldownCompanion:CreateAllGroupFrames()
    for groupId, _ in pairs(self.db.profile.groups) do
        self:CreateGroupFrame(groupId)
    end
end

function CooldownCompanion:RefreshAllGroups()
    for groupId, _ in pairs(self.db.profile.groups) do
        self:RefreshGroupFrame(groupId)
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
