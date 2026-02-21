--[[
    CooldownCompanion - Core/GroupUtilities.lua: LSM helpers, group visibility/load conditions,
    alpha fade system, group frame operations, keybind text system
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals for faster access
local GetTime = GetTime
local InCombatLockdown = InCombatLockdown
local IsMounted = IsMounted
local UnitExists = UnitExists
local GetShapeshiftForm = GetShapeshiftForm
local GetShapeshiftFormInfo = GetShapeshiftFormInfo
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local select = select

-- LibSharedMedia for font/texture selection
local LSM = LibStub("LibSharedMedia-3.0")

-- LSM fetch helpers with fallback
function CooldownCompanion:FetchFont(name)
    return LSM:Fetch("font", name) or LSM:Fetch("font", "Friz Quadrata TT") or STANDARD_TEXT_FONT
end

function CooldownCompanion:FetchStatusBar(name)
    return LSM:Fetch("statusbar", name) or LSM:Fetch("statusbar", "Solid") or [[Interface\BUTTONS\WHITE8X8]]
end

-- Re-apply all media after a SharedMedia pack registers new fonts/textures
function CooldownCompanion:RefreshAllMedia()
    self:RefreshAllGroups()
    self:ApplyResourceBars()
    self:ApplyCastBarSettings()
end

function CooldownCompanion:IsGroupVisibleToCurrentChar(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if group.isGlobal then return true end
    return group.createdBy == self.db.keys.char
end

function CooldownCompanion:GetEffectiveSpecs(group)
    return group.specs, false
end

function CooldownCompanion:IsGroupAvailableForAnchoring(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if group.displayMode ~= "icons" then return false end
    if group.isGlobal then return false end
    if group.enabled == false then return false end
    if not self:IsGroupVisibleToCurrentChar(groupId) then return false end

    local effectiveSpecs = self:GetEffectiveSpecs(group)
    if effectiveSpecs and next(effectiveSpecs) then
        if not (self._currentSpecId and effectiveSpecs[self._currentSpecId]) then
            return false
        end
    end

    if not self:CheckLoadConditions(group) then return false end

    return true
end

function CooldownCompanion:GetFirstAvailableAnchorGroup()
    local groups = self.db.profile.groups
    if not groups then return nil end

    local candidates = {}
    for groupId in pairs(groups) do
        if self:IsGroupAvailableForAnchoring(groupId) then
            table.insert(candidates, groupId)
        end
    end
    if #candidates == 0 then return nil end

    table.sort(candidates, function(a, b)
        local orderA = groups[a].order or a
        local orderB = groups[b].order or b
        return orderA < orderB
    end)
    return candidates[1]
end

function CooldownCompanion:CheckLoadConditions(group)
    local lc = group.loadConditions
    if not lc then return true end

    local instanceType = self._currentInstanceType

    -- Map instance type to load condition key
    local conditionKey
    if instanceType == "raid" then
        conditionKey = "raid"
    elseif instanceType == "party" then
        conditionKey = "dungeon"
    elseif instanceType == "pvp" then
        conditionKey = "battleground"
    elseif instanceType == "arena" then
        conditionKey = "arena"
    elseif instanceType == "delve" then
        conditionKey = "delve"
    else
        conditionKey = "openWorld"  -- "none" or "scenario"
    end

    -- If the matching instance condition is enabled, unload
    if lc[conditionKey] then return false end

    -- If rested condition is enabled and player is resting, unload
    if lc.rested and self._isResting then return false end

    return true
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
            state.hoverExpire = now + (group.customFade and group.fadeDelay or 1)
        elseif state.hoverExpire and now < state.hoverExpire then
            forceFull = true
        end
    end

    local desired = forceFull and 1 or (forceHidden and 0 or group.baselineAlpha)
    local fadeIn = group.customFade and group.fadeInDuration or 0.2
    local fadeOut = group.customFade and group.fadeOutDuration or 0.2
    local alpha = UpdateFadedAlpha(state, desired, now, fadeIn, fadeOut)

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
            if frame and frame:IsShown() then
                local needsUpdate = GroupNeedsAlphaUpdate(group)
                -- Also process if the group has stale alpha state that needs cleanup
                if not needsUpdate then
                    local state = self.alphaState[groupId]
                    if state and state.currentAlpha and state.currentAlpha ~= 1 then
                        needsUpdate = true
                    end
                end
                if needsUpdate then
                    self:UpdateGroupAlpha(groupId, group, frame, now, inCombat, hasTarget, mounted, inTravelForm)
                end
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
    -- Clear folder assignment — the folder belongs to the old section
    group.folderId = nil
    self:RefreshAllGroups()
end

function CooldownCompanion:GroupHasPetSpells(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    for _, buttonData in ipairs(group.buttons) do
        if buttonData.isPetSpell then return true end
    end
    return false
end

function CooldownCompanion:IsButtonUsable(buttonData)
    -- Passive/proc spells are tracked via aura, not spellbook presence.
    -- Multi-CDM-child buttons: verify their specific slot still exists in the CDM
    -- (spell may not be available on the current spec/talent loadout).
    if buttonData.isPassive then
        if buttonData.cdmChildSlot then
            local allChildren = self.viewerAuraAllChildren[buttonData.id]
            if not allChildren or not allChildren[buttonData.cdmChildSlot] then
                return false
            end
        end
        return true
    end

    if buttonData.type == "spell" then
        local bank = buttonData.isPetSpell
            and Enum.SpellBookSpellBank.Pet
            or Enum.SpellBookSpellBank.Player
        if C_SpellBook.IsSpellKnownOrInSpellBook(buttonData.id, bank) then
            return true
        end
        -- Fallback: spell may be stored as an override form; check the base spell.
        -- Only relevant for player spells (pet spells don't have override forms).
        if not buttonData.isPetSpell then
            local baseID = C_Spell.GetBaseSpell(buttonData.id)
            if baseID and baseID ~= buttonData.id then
                return C_SpellBook.IsSpellKnownOrInSpellBook(baseID)
            end
        end
        return false
    elseif buttonData.type == "item" then
        if buttonData.hasCharges then return true end
        if not CooldownCompanion.IsItemEquippable(buttonData) then return true end
        return C_Item.GetItemCount(buttonData.id) > 0
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
    -- Fully deactivate frames for groups not in the current profile
    -- (e.g. after a profile switch). Removes from groupFrames so
    -- ForEachButton / event handlers skip them entirely.
    for groupId, frame in pairs(self.groupFrames) do
        if not self.db.profile.groups[groupId] then
            self:DeleteMasqueGroup(groupId)
            frame:Hide()
            self.groupFrames[groupId] = nil
            if self.alphaState then
                self.alphaState[groupId] = nil
            end
        end
    end

    -- Refresh current profile's groups
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
    self._gcdInfo = C_Spell.GetSpellCooldown(61304)
    -- Widget-level GCD activity signal (secret-safe, plain boolean)
    local gcdDuration = C_Spell.GetSpellCooldownDuration(61304)
    if gcdDuration then
        self._gcdScratch:Hide()
        self._gcdScratch:SetCooldownFromDurationObject(gcdDuration)
        self._gcdActive = self._gcdScratch:IsShown()
        self._gcdScratch:Hide()
    else
        self._gcdActive = false
    end
    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame.UpdateCooldowns and frame:IsShown() then
            frame:UpdateCooldowns()
        end
    end
end

function CooldownCompanion:UpdateAllGroupLayouts()
    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame:IsShown() and frame._layoutDirty then
            self:UpdateGroupLayout(groupId)
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
