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

-- Constants
ST.BUTTON_SIZE = 36
ST.BUTTON_SPACING = 2
ST.DEFAULT_BORDER_SIZE = 1

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
                        iconWidthRatio = 1.0, -- 1.0 = square, <1 = taller, >1 = wider
                        maintainAspectRatio = false, -- Prevent icon image stretching
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
            iconWidthRatio = 1.0,
            maintainAspectRatio = false,
            showTooltips = true,
            desaturateOnCooldown = false,
            showGCDSwipe = true,
            showOutOfRange = false,
            showAssistedHighlight = false,
            assistedHighlightStyle = "blizzard",
            assistedHighlightColor = {0.3, 1, 0.3, 0.9},
            assistedHighlightBorderSize = 2,
            assistedHighlightBlizzardOverhang = 32,
            assistedHighlightProcOverhang = 32,
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
    
    -- Hide all frames
    for _, frame in pairs(self.groupFrames) do
        frame:Hide()
    end
end

function CooldownCompanion:OnSpellCast(event, unit, castGUID, spellID)
    if unit == "player" then
        self:UpdateAllCooldowns()
        -- During combat, secret values prevent cooldown comparison.
        -- Desaturate tracked spells known to have real cooldowns on cast.
        if InCombatLockdown() then
            self:DesaturateSpellOnCast(spellID)
        end
    end
end

function CooldownCompanion:DesaturateSpellOnCast(spellID)
    for _, frame in pairs(self.groupFrames) do
        if frame and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                if button.buttonData
                   and button.buttonData.type == "spell"
                   and button.buttonData.id == spellID
                   and button.style and button.style.desaturateOnCooldown then
                    button._desaturated = true
                    button.icon:SetDesaturated(true)
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
        self:Print("Config closed for combat.")
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

function CooldownCompanion:OnPlayerEnteringWorld()
    C_Timer.After(1, function()
        self:RefreshAllGroups()
    end)
end

-- Group Management Functions
function CooldownCompanion:CreateGroup(name)
    local groupId = self.db.profile.nextGroupId
    self.db.profile.nextGroupId = groupId + 1
    
    self.db.profile.groups[groupId] = {
        name = name or ("Group " .. groupId),
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
    return itemName, itemIcon
end
