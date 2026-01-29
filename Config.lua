--[[
    CooldownCompanion - Config
    AceConfig-based configuration panel
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local AceDBOptions = LibStub("AceDBOptions-3.0")

-- Locals for new spell/item input
local newSpellInput = ""
local newItemInput = ""
local selectedGroup = nil

-- Font options for dropdown
local fontOptions = {
    ["Fonts\\FRIZQT__.TTF"] = "Friz Quadrata (Default)",
    ["Fonts\\ARIALN.TTF"] = "Arial Narrow",
    ["Fonts\\MORPHEUS.TTF"] = "Morpheus",
    ["Fonts\\SKURRI.TTF"] = "Skurri",
    ["Fonts\\2002.TTF"] = "2002",
    ["Fonts\\NIMROD.TTF"] = "Nimrod",
}

local outlineOptions = {
    [""] = "None",
    ["OUTLINE"] = "Outline",
    ["THICKOUTLINE"] = "Thick Outline",
    ["MONOCHROME"] = "Monochrome",
}

-- Helper function to add a spell to selected group
local function TryAddSpell(input)
    if input == "" or not selectedGroup then return false end

    local spellId = tonumber(input)
    local spellName

    if spellId then
        local info = C_Spell.GetSpellInfo(spellId)
        spellName = info and info.name
    else
        local info = C_Spell.GetSpellInfo(input)
        if info then
            spellId = info.spellID
            spellName = info.name
        end
    end

    if spellId and spellName then
        CooldownCompanion:AddButtonToGroup(selectedGroup, "spell", spellId, spellName)
        CooldownCompanion:Print("Added spell: " .. spellName)
        return true
    else
        CooldownCompanion:Print("Spell not found: " .. input)
        return false
    end
end

-- Helper function to add an item to selected group
local function TryAddItem(input)
    if input == "" or not selectedGroup then return false end

    local itemId = tonumber(input)
    local itemName

    if itemId then
        itemName = C_Item.GetItemNameByID(itemId)
    else
        itemName = input
        itemId = C_Item.GetItemIDForItemInfo(input)
    end

    if itemId then
        CooldownCompanion:AddButtonToGroup(selectedGroup, "item", itemId, itemName or "Unknown Item")
        CooldownCompanion:Print("Added item: " .. (itemName or itemId))
        return true
    else
        CooldownCompanion:Print("Item not found: " .. input)
        return false
    end
end

-- Helper function to get sorted group list
local function GetGroupList()
    local list = {}
    for groupId, group in pairs(CooldownCompanion.db.profile.groups) do
        list[groupId] = group.name
    end
    return list
end

-- Helper function to get button list for a group
local function GetButtonList(groupId)
    local list = {}
    if not groupId then return list end
    local group = CooldownCompanion.db.profile.groups[groupId]
    if group and group.buttons then
        for i, button in ipairs(group.buttons) do
            local name = button.name or ("Unknown " .. button.type)
            -- Use string keys for AceConfig dropdown compatibility
            list[tostring(i)] = string.format("%d. [%s] %s", i, button.type:upper(), name)
        end
    end
    return list
end

-- Helper to get selected button index as number
local function GetSelectedButtonIndex()
    if ST.selectedButton then
        return tonumber(ST.selectedButton)
    end
    return nil
end

function CooldownCompanion:SetupConfig()
    local options = {
        name = "Cooldown Companion",
        type = "group",
        args = {
            general = {
                name = "General",
                type = "group",
                order = 1,
                args = {
                    description = {
                        name = "Cooldown Companion allows you to create custom action bar style panels to track spell and item cooldowns.\n\n",
                        type = "description",
                        order = 1,
                        fontSize = "medium",
                    },
                    locked = {
                        name = "Lock Frames",
                        desc = "Lock all group frames in place",
                        type = "toggle",
                        order = 2,
                        width = "full",
                        get = function() return self.db.profile.locked end,
                        set = function(_, val)
                            self.db.profile.locked = val
                            if val then
                                self:LockAllFrames()
                            else
                                self:UnlockAllFrames()
                            end
                        end,
                    },
                    newGroupHeader = {
                        name = "Create New Group",
                        type = "header",
                        order = 10,
                    },
                    newGroupName = {
                        name = "Group Name",
                        desc = "Enter a name for the new group",
                        type = "input",
                        order = 11,
                        width = "double",
                        get = function() return ST.newGroupName or "" end,
                        set = function(_, val) ST.newGroupName = val end,
                    },
                    createGroup = {
                        name = "Create Group",
                        desc = "Create a new tracking group",
                        type = "execute",
                        order = 12,
                        func = function()
                            local name = ST.newGroupName or "New Group"
                            local groupId = self:CreateGroup(name)
                            ST.newGroupName = ""
                            self:Print("Created group: " .. name)
                            -- Refresh config
                            AceConfigRegistry:NotifyChange(ADDON_NAME)
                        end,
                    },
                },
            },
            groups = {
                name = "Groups",
                type = "group",
                order = 2,
                args = {
                    selectGroup = {
                        name = "Select Group",
                        desc = "Select a group to configure",
                        type = "select",
                        order = 1,
                        width = "double",
                        values = function() return GetGroupList() end,
                        get = function() return selectedGroup end,
                        set = function(_, val) selectedGroup = val end,
                    },
                    groupSettings = {
                        name = "Group Settings",
                        type = "group",
                        order = 2,
                        inline = true,
                        hidden = function() return selectedGroup == nil end,
                        args = {
                            enabled = {
                                name = "Enabled",
                                desc = "Show/hide this group",
                                type = "toggle",
                                order = 1,
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    return group and group.enabled
                                end,
                                set = function(_, val)
                                    local group = self.db.profile.groups[selectedGroup]
                                    if group then
                                        group.enabled = val
                                        self:RefreshGroupFrame(selectedGroup)
                                    end
                                end,
                            },
                            groupName = {
                                name = "Group Name",
                                desc = "Rename this group",
                                type = "input",
                                order = 2,
                                width = "double",
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    return group and group.name or ""
                                end,
                                set = function(_, val)
                                    local group = self.db.profile.groups[selectedGroup]
                                    if group then
                                        group.name = val
                                        self:RefreshGroupFrame(selectedGroup)
                                    end
                                end,
                            },
                            deleteGroup = {
                                name = "Delete Group",
                                desc = "Permanently delete this group",
                                type = "execute",
                                order = 3,
                                confirm = true,
                                confirmText = "Are you sure you want to delete this group?",
                                func = function()
                                    self:DeleteGroup(selectedGroup)
                                    selectedGroup = nil
                                    AceConfigRegistry:NotifyChange(ADDON_NAME)
                                end,
                            },
                            anchorHeader = {
                                name = "Anchoring",
                                type = "header",
                                order = 10,
                            },
                            anchorFrame = {
                                name = "Anchor to Frame",
                                desc = "Enter the frame name to anchor to (use /fstack to find frame names). Leave empty for free positioning.",
                                type = "input",
                                order = 11,
                                width = "double",
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    if group and group.anchor.relativeTo ~= "UIParent" then
                                        return group.anchor.relativeTo
                                    end
                                    return ""
                                end,
                                set = function(_, val)
                                    local wasAnchored = false
                                    local group = self.db.profile.groups[selectedGroup]
                                    if group and group.anchor.relativeTo and group.anchor.relativeTo ~= "UIParent" then
                                        wasAnchored = true
                                    end
                                    if val == "" then
                                        -- Un-anchoring from a frame - center it
                                        self:SetGroupAnchor(selectedGroup, "UIParent", wasAnchored)
                                    else
                                        self:SetGroupAnchor(selectedGroup, val)
                                    end
                                end,
                            },
                            anchorPoint = {
                                name = "Anchor Point",
                                desc = "Where on the group frame to anchor",
                                type = "select",
                                order = 12,
                                values = {
                                    TOPLEFT = "Top Left",
                                    TOP = "Top",
                                    TOPRIGHT = "Top Right",
                                    LEFT = "Left",
                                    CENTER = "Center",
                                    RIGHT = "Right",
                                    BOTTOMLEFT = "Bottom Left",
                                    BOTTOM = "Bottom",
                                    BOTTOMRIGHT = "Bottom Right",
                                },
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    return group and group.anchor.point or "CENTER"
                                end,
                                set = function(_, val)
                                    local group = self.db.profile.groups[selectedGroup]
                                    if group then
                                        group.anchor.point = val
                                        local frame = self.groupFrames[selectedGroup]
                                        if frame then
                                            self:AnchorGroupFrame(frame, group.anchor)
                                        end
                                    end
                                end,
                            },
                            relativePoint = {
                                name = "Relative Point",
                                desc = "Where on the target frame to attach",
                                type = "select",
                                order = 13,
                                values = {
                                    TOPLEFT = "Top Left",
                                    TOP = "Top",
                                    TOPRIGHT = "Top Right",
                                    LEFT = "Left",
                                    CENTER = "Center",
                                    RIGHT = "Right",
                                    BOTTOMLEFT = "Bottom Left",
                                    BOTTOM = "Bottom",
                                    BOTTOMRIGHT = "Bottom Right",
                                },
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    return group and group.anchor.relativePoint or "CENTER"
                                end,
                                set = function(_, val)
                                    local group = self.db.profile.groups[selectedGroup]
                                    if group then
                                        group.anchor.relativePoint = val
                                        local frame = self.groupFrames[selectedGroup]
                                        if frame then
                                            self:AnchorGroupFrame(frame, group.anchor)
                                        end
                                    end
                                end,
                            },
                            offsetX = {
                                name = "X Offset",
                                type = "range",
                                order = 14,
                                min = -500,
                                max = 500,
                                step = 1,
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    return group and group.anchor.x or 0
                                end,
                                set = function(_, val)
                                    local group = self.db.profile.groups[selectedGroup]
                                    if group then
                                        group.anchor.x = val
                                        local frame = self.groupFrames[selectedGroup]
                                        if frame then
                                            self:AnchorGroupFrame(frame, group.anchor)
                                        end
                                    end
                                end,
                            },
                            offsetY = {
                                name = "Y Offset",
                                type = "range",
                                order = 15,
                                min = -500,
                                max = 500,
                                step = 1,
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    return group and group.anchor.y or 0
                                end,
                                set = function(_, val)
                                    local group = self.db.profile.groups[selectedGroup]
                                    if group then
                                        group.anchor.y = val
                                        local frame = self.groupFrames[selectedGroup]
                                        if frame then
                                            self:AnchorGroupFrame(frame, group.anchor)
                                        end
                                    end
                                end,
                            },
                        },
                    },
                    addSpellsHeader = {
                        name = "Add Spells/Items",
                        type = "header",
                        order = 20,
                        hidden = function() return selectedGroup == nil end,
                    },
                    addSpellInput = {
                        name = "Spell Name or ID",
                        desc = "Enter a spell name or ID and press Enter to add",
                        type = "input",
                        order = 21,
                        width = "double",
                        hidden = function() return selectedGroup == nil end,
                        get = function() return newSpellInput end,
                        set = function(_, val)
                            if TryAddSpell(val) then
                                newSpellInput = ""
                            else
                                newSpellInput = val
                            end
                            AceConfigRegistry:NotifyChange(ADDON_NAME)
                        end,
                    },
                    addItemInput = {
                        name = "Item Name or ID",
                        desc = "Enter an item name or ID and press Enter to add",
                        type = "input",
                        order = 25,
                        width = "double",
                        hidden = function() return selectedGroup == nil end,
                        get = function() return newItemInput end,
                        set = function(_, val)
                            if TryAddItem(val) then
                                newItemInput = ""
                            else
                                newItemInput = val
                            end
                            AceConfigRegistry:NotifyChange(ADDON_NAME)
                        end,
                    },
                    buttonsHeader = {
                        name = "Current Buttons",
                        type = "header",
                        order = 30,
                        hidden = function() return selectedGroup == nil end,
                    },
                    buttonList = {
                        name = "Tracked Spells/Items",
                        desc = "Select a button to configure or remove",
                        type = "select",
                        order = 31,
                        width = "double",
                        hidden = function() return selectedGroup == nil end,
                        values = function() return GetButtonList(selectedGroup) end,
                        get = function() return ST.selectedButton end,
                        set = function(_, val) ST.selectedButton = val end,
                    },
                    removeButton = {
                        name = "Remove Selected",
                        type = "execute",
                        order = 32,
                        hidden = function() return selectedGroup == nil or ST.selectedButton == nil end,
                        confirm = true,
                        confirmText = "Remove this spell/item from tracking?",
                        func = function()
                            local btnIdx = GetSelectedButtonIndex()
                            if btnIdx then
                                self:RemoveButtonFromGroup(selectedGroup, btnIdx)
                                ST.selectedButton = nil
                                AceConfigRegistry:NotifyChange(ADDON_NAME)
                            end
                        end,
                    },
                    buttonSettings = {
                        name = "Button Settings",
                        type = "group",
                        order = 33,
                        inline = true,
                        hidden = function() return selectedGroup == nil or ST.selectedButton == nil end,
                        args = {
                            showGlow = {
                                name = "Show Glow",
                                desc = "Always show a glow effect on this button",
                                type = "toggle",
                                order = 1,
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    local btnIdx = GetSelectedButtonIndex()
                                    if group and btnIdx and group.buttons[btnIdx] then
                                        return group.buttons[btnIdx].showGlow
                                    end
                                    return false
                                end,
                                set = function(_, val)
                                    local group = self.db.profile.groups[selectedGroup]
                                    local btnIdx = GetSelectedButtonIndex()
                                    if group and btnIdx and group.buttons[btnIdx] then
                                        group.buttons[btnIdx].showGlow = val
                                        self:RefreshGroupFrame(selectedGroup)
                                    end
                                end,
                            },
                            glowType = {
                                name = "Glow Type",
                                desc = "Type of glow effect",
                                type = "select",
                                order = 2,
                                values = {
                                    pixel = "Pixel Glow",
                                    action = "Action Glow",
                                    proc = "Proc Glow",
                                },
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    local btnIdx = GetSelectedButtonIndex()
                                    if group and btnIdx and group.buttons[btnIdx] then
                                        return group.buttons[btnIdx].glowType or "pixel"
                                    end
                                    return "pixel"
                                end,
                                set = function(_, val)
                                    local group = self.db.profile.groups[selectedGroup]
                                    local btnIdx = GetSelectedButtonIndex()
                                    if group and btnIdx and group.buttons[btnIdx] then
                                        group.buttons[btnIdx].glowType = val
                                        self:RefreshGroupFrame(selectedGroup)
                                    end
                                end,
                            },
                            glowColor = {
                                name = "Glow Color",
                                desc = "Color of the glow effect",
                                type = "color",
                                order = 3,
                                hasAlpha = true,
                                get = function()
                                    local group = self.db.profile.groups[selectedGroup]
                                    local btnIdx = GetSelectedButtonIndex()
                                    if group and btnIdx and group.buttons[btnIdx] then
                                        local c = group.buttons[btnIdx].glowColor or {1, 1, 0, 1}
                                        return unpack(c)
                                    end
                                    return 1, 1, 0, 1
                                end,
                                set = function(_, r, g, b, a)
                                    local group = self.db.profile.groups[selectedGroup]
                                    local btnIdx = GetSelectedButtonIndex()
                                    if group and btnIdx and group.buttons[btnIdx] then
                                        group.buttons[btnIdx].glowColor = {r, g, b, a}
                                        self:RefreshGroupFrame(selectedGroup)
                                    end
                                end,
                            },
                        },
                    },
                },
            },
            style = {
                name = "Style",
                type = "group",
                order = 3,
                args = {
                    selectGroupStyle = {
                        name = "Select Group",
                        desc = "Select a group to style",
                        type = "select",
                        order = 1,
                        width = "double",
                        values = function() return GetGroupList() end,
                        get = function() return ST.styleSelectedGroup end,
                        set = function(_, val) ST.styleSelectedGroup = val end,
                    },
                    styleHeader = {
                        name = "Button Styling",
                        type = "header",
                        order = 10,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                    },
                    buttonSize = {
                        name = "Button Size",
                        desc = "Size of each button in pixels (square icons)",
                        type = "range",
                        order = 11,
                        min = 20,
                        max = 64,
                        step = 1,
                        hidden = function()
                            if ST.styleSelectedGroup == nil then return true end
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            -- Show when maintainAspectRatio is checked (square mode)
                            return group and not group.style.maintainAspectRatio
                        end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.buttonSize or ST.BUTTON_SIZE
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.buttonSize = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    -- Shown when maintainAspectRatio is UNCHECKED (non-square mode)
                    iconWidth = {
                        name = "Icon Width",
                        desc = "Width of icons in pixels",
                        type = "range",
                        order = 11,
                        min = 10,
                        max = 100,
                        step = 1,
                        hidden = function()
                            if ST.styleSelectedGroup == nil then return true end
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            -- Show when maintainAspectRatio is unchecked (non-square mode)
                            return group and group.style.maintainAspectRatio
                        end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                return group.style.iconWidth or (group.style.buttonSize or ST.BUTTON_SIZE)
                            end
                            return ST.BUTTON_SIZE
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.iconWidth = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    iconHeight = {
                        name = "Icon Height",
                        desc = "Height of icons in pixels",
                        type = "range",
                        order = 12,
                        min = 10,
                        max = 100,
                        step = 1,
                        hidden = function()
                            if ST.styleSelectedGroup == nil then return true end
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            -- Show when maintainAspectRatio is unchecked (non-square mode)
                            return group and group.style.maintainAspectRatio
                        end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                return group.style.iconHeight or (group.style.buttonSize or ST.BUTTON_SIZE)
                            end
                            return ST.BUTTON_SIZE
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.iconHeight = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    buttonSpacing = {
                        name = "Button Spacing",
                        desc = "Space between buttons in pixels",
                        type = "range",
                        order = 13,
                        min = 0,
                        max = 10,
                        step = 1,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.buttonSpacing or ST.BUTTON_SPACING
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.buttonSpacing = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    borderSize = {
                        name = "Border Size",
                        desc = "Width of button border in pixels",
                        type = "range",
                        order = 14,
                        min = 0,
                        max = 5,
                        step = 0.1,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.borderSize or ST.DEFAULT_BORDER_SIZE
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.borderSize = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    borderColor = {
                        name = "Border Color",
                        desc = "Color of button borders",
                        type = "color",
                        order = 15,
                        hasAlpha = true,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group and group.style.borderColor then
                                return unpack(group.style.borderColor)
                            end
                            return 0, 0, 0, 1
                        end,
                        set = function(_, r, g, b, a)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.borderColor = {r, g, b, a}
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    backgroundColor = {
                        name = "Background Color",
                        desc = "Color behind the button icon",
                        type = "color",
                        order = 16,
                        hasAlpha = true,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group and group.style.backgroundColor then
                                return unpack(group.style.backgroundColor)
                            end
                            return 0, 0, 0, 0.5
                        end,
                        set = function(_, r, g, b, a)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.backgroundColor = {r, g, b, a}
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    maintainAspectRatio = {
                        name = "Square Icons",
                        desc = "When checked, use a single size for square icons. When unchecked, set width and height independently.",
                        type = "toggle",
                        order = 17,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.maintainAspectRatio
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.maintainAspectRatio = val
                                -- Initialize width/height from buttonSize when switching to non-square mode
                                if not val then
                                    local size = group.style.buttonSize or ST.BUTTON_SIZE
                                    group.style.iconWidth = group.style.iconWidth or size
                                    group.style.iconHeight = group.style.iconHeight or size
                                end
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    layoutHeader = {
                        name = "Layout",
                        type = "header",
                        order = 20,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                    },
                    orientation = {
                        name = "Orientation",
                        desc = "Direction buttons flow",
                        type = "select",
                        order = 21,
                        values = {
                            horizontal = "Horizontal",
                            vertical = "Vertical",
                        },
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.orientation or "horizontal"
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.orientation = val
                                self:RefreshGroupFrame(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    buttonsPerRow = {
                        name = "Buttons Per Row/Column",
                        desc = "Maximum buttons before wrapping to next row/column",
                        type = "range",
                        order = 22,
                        min = 1,
                        max = 24,
                        step = 1,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.buttonsPerRow or 12
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.buttonsPerRow = val
                                self:RefreshGroupFrame(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    displayHeader = {
                        name = "Display Options",
                        type = "header",
                        order = 30,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                    },
                    showCooldownText = {
                        name = "Show Cooldown Text",
                        desc = "Display remaining cooldown time on buttons",
                        type = "toggle",
                        order = 31,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.showCooldownText
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.showCooldownText = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    cooldownFontSize = {
                        name = "Cooldown Font Size",
                        desc = "Size of the cooldown countdown text",
                        type = "range",
                        order = 32,
                        min = 8,
                        max = 32,
                        step = 1,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.cooldownFontSize or 12
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.cooldownFontSize = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    cooldownFont = {
                        name = "Cooldown Font",
                        desc = "Font face for cooldown countdown text",
                        type = "select",
                        order = 33,
                        values = fontOptions,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.cooldownFont or "Fonts\\FRIZQT__.TTF"
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.cooldownFont = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    cooldownFontOutline = {
                        name = "Cooldown Font Outline",
                        desc = "Outline style for cooldown countdown text",
                        type = "select",
                        order = 34,
                        values = outlineOptions,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.cooldownFontOutline or "OUTLINE"
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.cooldownFontOutline = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    desaturateOnCooldown = {
                        name = "Desaturate On Cooldown",
                        desc = "Make icon grayscale while the spell/item is on cooldown",
                        type = "toggle",
                        order = 35,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.desaturateOnCooldown
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.desaturateOnCooldown = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                    tooltipHeader = {
                        name = "Tooltips",
                        type = "header",
                        order = 50,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                    },
                    showTooltips = {
                        name = "Show Tooltips",
                        desc = "Display spell/item tooltips when hovering over buttons. When disabled, buttons are automatically click-through.",
                        type = "toggle",
                        order = 51,
                        hidden = function() return ST.styleSelectedGroup == nil end,
                        get = function()
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            return group and group.style.showTooltips ~= false
                        end,
                        set = function(_, val)
                            local group = self.db.profile.groups[ST.styleSelectedGroup]
                            if group then
                                group.style.showTooltips = val
                                self:UpdateGroupStyle(ST.styleSelectedGroup)
                            end
                        end,
                    },
                },
            },
            profiles = AceDBOptions:GetOptionsTable(self.db),
        },
    }
    
    -- Set profile tab order
    options.args.profiles.order = 100
    
    -- Register options
    AceConfig:RegisterOptionsTable(ADDON_NAME, options)
    AceConfigDialog:AddToBlizOptions(ADDON_NAME, "Cooldown Companion")
    
    -- Store AceConfigRegistry reference
    _G.AceConfigRegistry = LibStub("AceConfigRegistry-3.0")
end
