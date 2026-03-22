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

-- Addon action bar binding fallback: slot → abbreviated key text.
-- Covers action bar addons (ElvUI, Bartender4, Dominos, etc.) whose keybinds
-- are not discoverable through Blizzard's standard binding-name lookup.
local addonSlotBindings = {}

-- Parallel raw key cache for addon bars: slot → raw key string from GetBindingKey.
-- Used by key press highlight detection (IsKeyDown needs raw key names, not display text).
local addonSlotRawBindings = {}

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
-- Tries Blizzard binding names and CLICK fallback first, then addon bar bindings.
local function GetKeybindForSlot(slot)
    local info = slotToButtonInfo[slot]
    if info then
        local key = GetBindingKey(info.bindingAction) or
                    GetBindingKey("CLICK " .. info.frameName .. ":LeftButton")
        if key then
            return AbbreviateKeybind(GetBindingText(key, 1))
        end
    end
    -- Fallback: addon bar bindings (e.g. Bartender4, Dominos, ElvUI)
    return addonSlotBindings[slot]
end

------------------------------------------------------------------------
-- KEY PRESS HIGHLIGHT SUPPORT
------------------------------------------------------------------------

local strsplit = strsplit

-- Parse a raw binding key string into a structured table for efficient per-tick checks.
-- "ALT-CTRL-SHIFT-F" → {mainKey="F", shift=true, ctrl=true, alt=true}
-- Handles the "-" key correctly: "CTRL--" → {mainKey="-", ctrl=true}, "-" → {mainKey="-"}.
-- Returns nil for nil input.
local function ParseBindingKey(rawKey)
    if not rawKey then return nil end
    local parts = {strsplit("-", rawKey)}
    -- Trailing "-" from strsplit means the key itself is "-" (e.g. "CTRL--" or bare "-")
    local mainKey = parts[#parts]
    if mainKey == "" then mainKey = "-" end
    local info = {mainKey = mainKey, shift = false, ctrl = false, alt = false}
    for i = 1, #parts - 1 do
        local mod = parts[i]
        if mod == "SHIFT" then info.shift = true
        elseif mod == "CTRL" then info.ctrl = true
        elseif mod == "ALT" then info.alt = true
        end
    end
    return info
end

-- Check if a parsed binding key is currently pressed (main key + exact modifier match).
local function IsBindingKeyPressed(info)
    if not info then return false end
    if not IsKeyDown(info.mainKey) then return false end
    -- Exact modifier match: prevent "1" from triggering when Shift+1 is held.
    -- "not not" normalizes to strict booleans for == comparison against info.shift/ctrl/alt,
    -- since Lua 5.1 equality does not coerce truthy values (1 ~= true, nil ~= false).
    if (not not IsShiftKeyDown()) ~= info.shift then return false end
    if (not not IsControlKeyDown()) ~= info.ctrl then return false end
    if (not not IsAltKeyDown()) ~= info.alt then return false end
    return true
end

-- Return an array of raw binding key strings for a slot (may be multiple per slot).
-- Falls back to addon bar raw key cache for third-party bar addons.
local function GetRawBindingKeysForSlot(slot)
    local keys = {}
    local info = slotToButtonInfo[slot]
    if info then
        local key1, key2 = GetBindingKey(info.bindingAction)
        if not key1 then
            key1, key2 = GetBindingKey("CLICK " .. info.frameName .. ":LeftButton")
        end
        if key1 then keys[#keys + 1] = key1 end
        if key2 then keys[#keys + 1] = key2 end
    end
    -- Fallback: addon bar raw bindings
    if #keys == 0 and addonSlotRawBindings[slot] then
        keys[#keys + 1] = addonSlotRawBindings[slot]
    end
    return keys
end

-- Resolve and cache parsed binding key info for a CC button.
-- Stores result as button._bindingKeyInfos (array of parsed structs, or empty table).
local function CacheButtonBindingKeys(button, buttonData)
    local infos = {}
    if not buttonData then
        button._bindingKeyInfos = infos
        return
    end
    local slots
    if buttonData.type == "spell" then
        slots = C_ActionBar.FindSpellActionButtons(buttonData.id)
    elseif buttonData.type == "item" then
        local slot = CooldownCompanion._itemSlotCache[buttonData.id]
        if slot then slots = {slot} end
    end
    if slots then
        local seen = {}
        for _, slot in ipairs(slots) do
            local rawKeys = GetRawBindingKeysForSlot(slot)
            for _, rawKey in ipairs(rawKeys) do
                if not seen[rawKey] then
                    seen[rawKey] = true
                    local parsed = ParseBindingKey(rawKey)
                    if parsed then
                        infos[#infos + 1] = parsed
                    end
                end
            end
        end
    end
    button._bindingKeyInfos = infos
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

-- Resolve the action bar slot from a button frame, or nil.
local function GetFrameActionSlot(frame)
    local action = frame.action
    if not action and frame.GetAttribute then
        action = tonumber(frame:GetAttribute("action"))
    end
    if action and type(action) == "number" then return action end
    return nil
end

-- Cache the abbreviated keybind text and raw key for a given slot, if not already cached.
local function CacheAddonBinding(slot, key)
    if not addonSlotBindings[slot] then
        addonSlotBindings[slot] = AbbreviateKeybind(GetBindingText(key, 1))
        addonSlotRawBindings[slot] = key
    end
end

-- Scan addon action bar frames and WoW's binding table to find keybinds that
-- the Blizzard binding-name lookup in GetKeybindForSlot cannot discover.
-- Handles ElvUI (custom ELVUIBAR commands), Bartender4 / Dominos (CLICK commands),
-- and any other addon that registers CLICK bindings for action button frames.
function CooldownCompanion:RebuildAddonSlotBindings()
    wipe(addonSlotBindings)
    wipe(addonSlotRawBindings)

    -- Strategy 1: Scan GetBinding() for CLICK commands.
    -- Covers Bartender4, Dominos, and any addon using CLICK binding format.
    for i = 1, GetNumBindings() do
        local command, category, key1 = GetBinding(i)
        if key1 and command then
            local frameName = command:match("^CLICK (.+):LeftButton$")
            if frameName then
                local frame = _G[frameName]
                if frame then
                    local slot = GetFrameActionSlot(frame)
                    if slot then CacheAddonBinding(slot, key1) end
                end
            end
        end
    end

    -- Strategy 2: ElvUI uses non-CLICK binding commands (ELVUIBAR{n}BUTTON{m}).
    -- Scan its frames directly and query the binding by constructed command name.
    if _G["ElvUI_Bar1Button1"] then
        for bar = 1, 15 do
            for btn = 1, 12 do
                local frame = _G["ElvUI_Bar" .. bar .. "Button" .. btn]
                if frame then
                    local slot = GetFrameActionSlot(frame)
                    if slot and not addonSlotBindings[slot] then
                        local key = GetBindingKey("ELVUIBAR" .. bar .. "BUTTON" .. btn)
                        if key then CacheAddonBinding(slot, key) end
                    end
                end
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

-- Refresh keybind text and binding key caches on all buttons.
function CooldownCompanion:OnKeybindsChanged()
    self:ForEachButton(function(button, buttonData)
        if button.keybindText then
            local text = CooldownCompanion:GetKeybindText(buttonData)
            button.keybindText:SetText(text or "")
            button.keybindText:SetShown(button.style.showKeybindText and text ~= nil)
        end
        -- Rebuild key press highlight binding cache
        CacheButtonBindingKeys(button, buttonData)
    end)
end

-- Exports for key press highlight
ST._IsBindingKeyPressed = IsBindingKeyPressed
ST._CacheButtonBindingKeys = CacheButtonBindingKeys
