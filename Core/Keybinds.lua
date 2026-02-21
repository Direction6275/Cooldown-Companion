--[[
    CooldownCompanion - Core/Keybinds.lua: Keybind text system — display action bar keybinds on buttons
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local pairs = pairs
local wipe = wipe

------------------------------------------------------------------------
-- KEYBIND TEXT SUPPORT
------------------------------------------------------------------------

-- Known action bar button frames: {framePrefix, bindingPrefix, count}
-- Frame names come from Blizzard_ActionBar/Shared/ActionBar.lua:
--   MainActionBar → "ActionButton"..i (special case)
--   All others    → barFrameName.."Button"..i
-- Binding prefixes come from buttonType in MultiActionBars.xml templates.
local ACTION_BAR_BUTTONS = {
    {"ActionButton",              "ACTIONBUTTON",            12},
    {"MultiBarBottomLeftButton",  "MULTIACTIONBAR1BUTTON",   12},
    {"MultiBarBottomRightButton", "MULTIACTIONBAR2BUTTON",   12},
    {"MultiBarRightButton",       "MULTIACTIONBAR3BUTTON",   12},
    {"MultiBarLeftButton",        "MULTIACTIONBAR4BUTTON",   12},
    {"MultiBar5Button",           "MULTIACTIONBAR5BUTTON",   12},
    {"MultiBar6Button",           "MULTIACTIONBAR6BUTTON",   12},
    {"MultiBar7Button",           "MULTIACTIONBAR7BUTTON",   12},
}

-- slot → {bindingAction, frameName} reverse lookup, rebuilt on events
local slotToButtonInfo = {}

-- Item ID → action bar slot reverse lookup cache
CooldownCompanion._itemSlotCache = {}

-- Rebuild the slot → button info mapping by reading .action from actual frames.
-- This correctly handles page-based slot numbering without hardcoded ranges.
function CooldownCompanion:RebuildSlotMapping()
    wipe(slotToButtonInfo)
    for _, barInfo in ipairs(ACTION_BAR_BUTTONS) do
        local framePrefix, bindingPrefix, count = barInfo[1], barInfo[2], barInfo[3]
        for i = 1, count do
            local frameName = framePrefix .. i
            local frame = _G[frameName]
            if frame and frame.action then
                slotToButtonInfo[frame.action] = {
                    bindingAction = bindingPrefix .. i,
                    frameName = frameName,
                }
            end
        end
    end
end

-- Map verbose localized keybind names to short abbreviations.
-- Built from KEY_ GlobalStrings so it works on any WoW locale.
local keybindMap = {}
do
    -- Middle mouse button
    keybindMap[KEY_BUTTON3] = "M3"
    -- Mouse buttons 4-31
    for i = 4, 31 do
        local text = _G["KEY_BUTTON" .. i]
        if text then keybindMap[text] = "M" .. i end
    end
    -- Mouse wheel
    keybindMap[KEY_MOUSEWHEELUP] = "MWU"
    keybindMap[KEY_MOUSEWHEELDOWN] = "MWD"
    -- Numpad digits
    for i = 0, 9 do
        local text = _G["KEY_NUMPAD" .. i]
        if text then keybindMap[text] = "N" .. i end
    end
    -- Numpad operators
    keybindMap[KEY_NUMPADDECIMAL] = "N."
    keybindMap[KEY_NUMPADDIVIDE] = "N/"
    keybindMap[KEY_NUMPADMINUS] = "N-"
    keybindMap[KEY_NUMPADMULTIPLY] = "N*"
    keybindMap[KEY_NUMPADPLUS] = "N+"
end

-- Shorten verbose keybind display text to fit inside icon corners.
local function AbbreviateKeybind(text)
    -- Exact match (key with no modifiers — common case)
    if keybindMap[text] then return keybindMap[text] end
    -- Substring match (key with modifier prefixes like "c-", "s-", "a-")
    for long, short in pairs(keybindMap) do
        local s, e = text:find(long, 1, true)
        if s then
            return text:sub(1, s - 1) .. short .. text:sub(e + 1)
        end
    end
    return text
end

-- Return the formatted keybind string for a given action bar slot, or nil.
-- Uses both the named binding AND the CLICK fallback (matching Blizzard logic).
local function GetKeybindForSlot(slot)
    local info = slotToButtonInfo[slot]
    if not info then return nil end
    local key = GetBindingKey(info.bindingAction) or
                GetBindingKey("CLICK " .. info.frameName .. ":LeftButton")
    if key then
        return AbbreviateKeybind(GetBindingText(key, 1))
    end
    return nil
end

-- Rebuild the entire item→slot reverse lookup cache by scanning action button frames.
function CooldownCompanion:RebuildItemSlotCache()
    wipe(self._itemSlotCache)
    for slot, info in pairs(slotToButtonInfo) do
        if C_ActionBar.HasAction(slot) and C_ActionBar.IsItemAction(slot) then
            local actionType, id = GetActionInfo(slot)
            if actionType == "item" and id then
                if not self._itemSlotCache[id] then
                    self._itemSlotCache[id] = slot
                end
            end
        end
    end
end

-- Update item slot cache for a single changed slot.
function CooldownCompanion:UpdateItemSlotCache(slot)
    -- Remove old entry pointing to this slot
    for itemId, cachedSlot in pairs(self._itemSlotCache) do
        if cachedSlot == slot then
            self._itemSlotCache[itemId] = nil
            break
        end
    end
    -- Add new entry if slot now has an item
    if C_ActionBar.HasAction(slot) and C_ActionBar.IsItemAction(slot) then
        local actionType, id = GetActionInfo(slot)
        if actionType == "item" and id then
            if not self._itemSlotCache[id] then
                self._itemSlotCache[id] = slot
            end
        end
    end
end

-- Return the formatted keybind text for a button, or nil if none found.
function CooldownCompanion:GetKeybindText(buttonData)
    if not buttonData then return nil end

    if buttonData.type == "spell" then
        local slots = C_ActionBar.FindSpellActionButtons(buttonData.id)
        if slots then
            for _, slot in ipairs(slots) do
                local text = GetKeybindForSlot(slot)
                if text and text ~= "" then
                    return text
                end
            end
        end
    elseif buttonData.type == "item" then
        local slot = self._itemSlotCache[buttonData.id]
        if slot then
            return GetKeybindForSlot(slot)
        end
    end

    return nil
end

-- Refresh keybind text on all icon-mode buttons.
function CooldownCompanion:OnKeybindsChanged()
    self:ForEachButton(function(button, buttonData)
        if button.keybindText then
            local text = CooldownCompanion:GetKeybindText(buttonData)
            button.keybindText:SetText(text or "")
            button.keybindText:SetShown(button.style.showKeybindText and text ~= nil)
        end
    end)
end
