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
            local AceConfigDialog = LibStub("AceConfigDialog-3.0")
            if AceConfigDialog.OpenFrames[ADDON_NAME] then
                AceConfigDialog:Close(ADDON_NAME)
            else
                AceConfigDialog:Open(ADDON_NAME)
            end
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
                            showGlow = false,
                            glowType = "pixel", -- "pixel", "action", "proc"
                            glowColor = {1, 1, 0, 1},
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
                        enableClickthrough = false, -- Allow clicks to pass through buttons
                        desaturateOnCooldown = false, -- Desaturate icon while on cooldown
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
            enableClickthrough = false,
            desaturateOnCooldown = false,
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

function CooldownCompanion:OnEnable()
    -- Register events for cooldown updates
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN", "UpdateAllCooldowns")
    self:RegisterEvent("BAG_UPDATE_COOLDOWN", "UpdateAllCooldowns")
    self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN", "UpdateAllCooldowns")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    
    -- Combat events to trigger updates
    self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED", "OnSpellCast")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "UpdateAllCooldowns") -- Entering combat
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "UpdateAllCooldowns")  -- Leaving combat
    
    -- Create all group frames
    self:CreateAllGroupFrames()
    
    -- Start a ticker to update cooldowns periodically (backup for combat)
    -- This ensures cooldowns update even if events don't fire
    self.updateTicker = C_Timer.NewTicker(0.1, function()
        self:UpdateAllCooldowns()
    end)
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
    end
end

function CooldownCompanion:SlashCommand(input)
    if input == "lock" then
        self.db.profile.locked = true
        self:LockAllFrames()
        self:Print("Frames locked.")
    elseif input == "unlock" then
        self.db.profile.locked = false
        self:UnlockAllFrames()
        self:Print("Frames unlocked. Drag to move.")
    elseif input == "reset" then
        self.db:ResetProfile()
        self:RefreshAllGroups()
        self:Print("Profile reset.")
    else
        -- Open config using AceConfigDialog
        local AceConfigDialog = LibStub("AceConfigDialog-3.0")
        AceConfigDialog:Open(ADDON_NAME)
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
        showGlow = false,
        glowType = "pixel",
        glowColor = {1, 1, 0, 1},
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
    for _, frame in pairs(self.groupFrames) do
        if frame then
            frame:EnableMouse(false)
            if frame.dragHandle then
                frame.dragHandle:Hide()
            end
        end
    end
end

function CooldownCompanion:UnlockAllFrames()
    for _, frame in pairs(self.groupFrames) do
        if frame then
            frame:EnableMouse(true)
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
