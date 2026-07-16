--[[
    CooldownCompanion - Config/SpellItemAdd
    Spell/item addition + autocomplete system.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Imports from earlier Config/ files
local ResolveCDMAuraSpellID = ST.ResolveCDMAuraSpellID
local IsPassiveOrProc = ST._IsPassiveOrProc
local IsPassiveCooldownSpell = ST.IsPassiveCooldownSpell
local IsNeverTrackableSpell = ST._IsNeverTrackableSpell
local ShouldSuppressSpellbookEntry = ST._ShouldSuppressSpellbookEntry
local NotifyTutorialAction = ST._NotifyTutorialAction
local SelectConfigPanel = ST._SelectConfigPanel
local SelectConfigButton = ST._SelectConfigButton

-- After a successful add, set selection state to the new button so the
-- next RefreshConfigPanel shows its settings in Column 3.
-- Precondition: CS.selectedContainer is already set by the caller's
-- panel/container selection flow.
local function SelectNewButton(panelId, buttonIndex)
    local group = panelId and CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[panelId]
    if group and group.displayMode == "textures" then
        SelectConfigPanel(panelId)
        CS.addingToPanelId = nil
        CS.pendingTexturePickerOpen = panelId
        return
    end
    if not buttonIndex then
        CooldownCompanion:ClearAllConfigPreviews()
        return
    end
    SelectConfigButton(panelId, buttonIndex, { force = true })
end

local function IsTriggerPanelTarget(groupId)
    local group = groupId and CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[groupId]
    return group and group.displayMode == "trigger"
end

-- File-local state
local autocompleteDropdown

-- Autocomplete constants
local AUTOCOMPLETE_MAX_ROWS = 8
local AUTOCOMPLETE_ROW_HEIGHT = 22
local AUTOCOMPLETE_ICON_SIZE = 16
local AUTOCOMPLETE_TYPE_BADGE_SIZE = 13
local AUTOCOMPLETE_TYPE_LABEL_WIDTH = 68
local AUTOCOMPLETE_TYPE_RIGHT_PAD = 6
local AUTOCOMPLETE_TYPE_GAP = 4

local AUTOCOMPLETE_TYPE_DISPLAY = {
    spell = { label = "Spell", atlas = "ui_adv_atk" },
    aura = { label = "Aura", atlas = "ui_adv_health" },
    equipment = { label = "Equipment", atlas = "Crosshair_repairnpc_32" },
    item = { label = "Item", atlas = "auctionhouse-icon-coin-gold" },
}

local function GetAutocompleteTypeDisplay(entry)
    local kind = entry and entry.autocompleteKind
    if kind ~= "spell" and kind ~= "aura" and kind ~= "equipment" and kind ~= "item" then
        if entry and entry.isEquipmentSlot then
            kind = "equipment"
        elseif entry and entry.isItem then
            kind = "item"
        else
            kind = "spell"
        end
    end
    return AUTOCOMPLETE_TYPE_DISPLAY[kind] or AUTOCOMPLETE_TYPE_DISPLAY.spell
end

local function IsBlockedSpellForTracking(spellId)
    return spellId and IsNeverTrackableSpell(spellId)
end

local function PrintBlockedSpellMessage(spellName)
    local shownName = spellName or "that spell"
    CooldownCompanion:Print("Cannot track " .. shownName .. ".")
end

------------------------------------------------------------------------
-- Helper: Add spell to selected group
------------------------------------------------------------------------
local function TryAddSpell(input, isPetSpell, forceAura)
    if input == "" or not CS.selectedGroup then return false end

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
        else
            -- Name lookup failed (spell may not be known); search talent tree
            spellId, spellName = CooldownCompanion:FindTalentSpellByName(input)
        end
    end

    if spellId and spellName then
        if spellName == "Single-Button Assistant" then
            CooldownCompanion:Print("Cannot track Single-Button Assistant")
            return false
        end
        if IsBlockedSpellForTracking(spellId) then
            PrintBlockedSpellMessage(spellName)
            return false
        end
        -- 12.1: passives/procs add directly as aura-tracking entries — the new
        -- AuraContainer backend needs no Cooldown Manager setup. forceAura=true
        -- comes from "Aura" autocomplete suggestions (tracked buff/bar rows).
        local addAsAura = forceAura == true or IsPassiveOrProc(spellId)
        local idx, notified = CooldownCompanion:AddButtonToGroup(CS.selectedGroup, "spell", spellId, spellName, isPetSpell, addAsAura or nil, forceAura)
        if not idx then
            return false
        end
        SelectNewButton(CS.selectedGroup, idx)
        if not notified then
            CooldownCompanion:Print((addAsAura and "Added aura: " or "Added spell: ") .. spellName)
        end
        return true
    else
        CooldownCompanion:Print("Spell not found: " .. input .. ". Try using the spell ID or drag from spellbook.")
        return false
    end
end

------------------------------------------------------------------------
-- Helper: Add item to selected group
------------------------------------------------------------------------
local function FinalizeAddItem(itemId, groupId, autoSelect)
    local itemName = C_Item.GetItemNameByID(itemId) or "Unknown Item"
    local spellName = C_Item.GetItemSpell(itemId)
    if not spellName then
        CooldownCompanion:Print("Item has no usable effect: " .. itemName)
        return false
    end
    local idx = CooldownCompanion:AddButtonToGroup(groupId, "item", itemId, itemName)
    if not idx then
        return false
    end
    if autoSelect ~= false then
        SelectNewButton(groupId, idx)
    end
    CooldownCompanion:Print("Added item: " .. itemName)
    return true
end

local function TryAddItem(input)
    if input == "" or not CS.selectedGroup then return false end

    local itemId = tonumber(input)
    local itemName

    if itemId then
        itemName = C_Item.GetItemNameByID(itemId)
    else
        itemName = input
        itemId = C_Item.GetItemIDForItemInfo(input)
    end

    if not itemId then
        CooldownCompanion:Print("Item not found: " .. input)
        return false
    end

    if C_Item.IsItemDataCachedByID(itemId) then
        return FinalizeAddItem(itemId, CS.selectedGroup)
    end

    -- Only do async loading for ID-based input (not name-based).
    -- Name lookups that aren't cached are almost certainly invalid items.
    if not tonumber(input) then
        CooldownCompanion:Print("Item not found: " .. input)
        return false
    end

    -- Item data not cached yet — request it and wait for callback.
    -- Cancel any pending item load listener before registering a new one.
    if CooldownCompanion.pendingItemLoad then
        CooldownCompanion:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        CooldownCompanion.pendingItemLoad = nil
    end
    local capturedGroup = CS.selectedGroup
    CooldownCompanion.pendingItemLoad = itemId
    CooldownCompanion:Print("Loading item data...")
    C_Item.RequestLoadItemDataByID(itemId)
    CooldownCompanion:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, loadedItemId, success)
        if loadedItemId ~= CooldownCompanion.pendingItemLoad then return end
        CooldownCompanion:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
        CooldownCompanion.pendingItemLoad = nil
        if not success then
            CooldownCompanion:Print("Item not found: " .. input)
            return
        end
        -- Skip auto-select if the user navigated away during async load
        local stillOnGroup = CS.selectedGroup == capturedGroup
        if FinalizeAddItem(itemId, capturedGroup, stillOnGroup) then
            CooldownCompanion:RefreshConfigPanel()
        end
    end)
    return false
end

local function TryAddEquipmentSlot(itemSlot)
    if not CS.selectedGroup then return false end
    if IsTriggerPanelTarget(CS.selectedGroup) then return false end

    local slotData = {
        type = CooldownCompanion.EQUIPMENT_SLOT_TYPE or "equipmentSlot",
        itemSlot = itemSlot,
        itemSlotKind = CooldownCompanion.EQUIPMENT_SLOT_KIND_TRINKET or "trinket",
    }
    if CooldownCompanion.IsEquipmentSlotEntry
        and not CooldownCompanion.IsEquipmentSlotEntry(slotData) then
        return false
    end

    local slotName = CooldownCompanion.GetEquipmentSlotDisplayName
        and CooldownCompanion.GetEquipmentSlotDisplayName(slotData) or "Trinket Slot"
    local idx = CooldownCompanion:AddEquipmentSlotToGroup(
        CS.selectedGroup,
        itemSlot,
        slotData.itemSlotKind
    )
    if not idx then
        return false
    end

    SelectNewButton(CS.selectedGroup, idx)
    CooldownCompanion:Print("Added equipment slot: " .. slotName)
    return true
end

local function ResolveEquipmentSlotInput(input)
    if type(input) ~= "string" then
        return nil
    end

    local query = input:lower():gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    if query == "trinket slot 1"
        or query == "trinket 1"
        or query == "slot 1"
        or query == "first trinket"
        or query == "top trinket" then
        return CooldownCompanion.TRINKET_SLOT_1 or 13
    end
    if query == "trinket slot 2"
        or query == "trinket 2"
        or query == "slot 2"
        or query == "second trinket"
        or query == "bottom trinket" then
        return CooldownCompanion.TRINKET_SLOT_2 or 14
    end
    return nil
end

------------------------------------------------------------------------
-- Unified add: resolve input as spell or item automatically
------------------------------------------------------------------------
local function TryAdd(input)
    if input == "" or not CS.selectedGroup then return false end

    local equipmentSlot = ResolveEquipmentSlotInput(input)
    if equipmentSlot then
        return TryAddEquipmentSlot(equipmentSlot)
    end

    local id = tonumber(input)

    if id then
        -- ID-based input: check both spell and item
        local spellInfo = C_Spell.GetSpellInfo(id)
        local spellFound = spellInfo and spellInfo.name
        if spellFound and IsBlockedSpellForTracking(id) then
            PrintBlockedSpellMessage(spellInfo.name)
            return false
        end
        local passiveOrProc = spellFound and IsPassiveOrProc(id)

        -- Passive/proc spell → aura-tracking entry (12.1: no CDM requirement)
        if spellFound and passiveOrProc then
            return TryAddSpell(tostring(id))
        end

        -- Non-passive spell → add it
        if spellFound and not passiveOrProc then
            local idx, notified = CooldownCompanion:AddButtonToGroup(CS.selectedGroup, "spell", id, spellInfo.name)
            if not idx then
                return false
            end
            SelectNewButton(CS.selectedGroup, idx)
            if not notified then
                CooldownCompanion:Print("Added spell: " .. spellInfo.name)
            end
            return true
        end

        -- Try as item
        local itemName = C_Item.GetItemNameByID(id)
        local itemId = C_Item.GetItemIDForItemInfo(id)
        if itemId then
            if C_Item.IsItemDataCachedByID(itemId) then
                local result = FinalizeAddItem(itemId, CS.selectedGroup)
                if result then return true end
                -- Item had no use effect; if spell was passive, report CDM error
                if passiveOrProc then
                    CooldownCompanion:Print("Passive/proc spell " .. spellInfo.name .. " is not tracked in the Cooldown Manager.")
                    return false
                end
                -- FinalizeAddItem already printed "no usable effect"
                return false
            end
            -- Item not cached — request async load
            if CooldownCompanion.pendingItemLoad then
                CooldownCompanion:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
                CooldownCompanion.pendingItemLoad = nil
            end
            local capturedGroup = CS.selectedGroup
            CooldownCompanion.pendingItemLoad = itemId
            CooldownCompanion:Print("Loading item data...")
            C_Item.RequestLoadItemDataByID(itemId)
            CooldownCompanion:RegisterEvent("ITEM_DATA_LOAD_RESULT", function(_, loadedItemId, success)
                if loadedItemId ~= CooldownCompanion.pendingItemLoad then return end
                CooldownCompanion:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
                CooldownCompanion.pendingItemLoad = nil
                if not success then
                    if passiveOrProc then
                        CooldownCompanion:Print("Passive/proc spell " .. spellInfo.name .. " is not tracked in the Cooldown Manager.")
                    else
                        CooldownCompanion:Print("Not found: " .. input)
                    end
                    return
                end
                -- Skip auto-select if the user navigated away during async load
                local stillOnGroup = CS.selectedGroup == capturedGroup
                if FinalizeAddItem(itemId, capturedGroup, stillOnGroup) then
                    CooldownCompanion:RefreshConfigPanel()
                elseif passiveOrProc then
                    CooldownCompanion:Print("Passive/proc spell " .. spellInfo.name .. " is not tracked in the Cooldown Manager.")
                end
            end)
            return false
        end

        -- No item match
        if passiveOrProc then
            CooldownCompanion:Print("Passive/proc spell " .. spellInfo.name .. " is not tracked in the Cooldown Manager.")
            return false
        end

        CooldownCompanion:Print("Not found: " .. input)
        return false
    else
        -- Name-based input: try spell first, then item
        local spellInfo = C_Spell.GetSpellInfo(input)
        local spellId, spellName
        if spellInfo then
            spellId = spellInfo.spellID
            spellName = spellInfo.name
        else
            spellId, spellName = CooldownCompanion:FindTalentSpellByName(input)
        end

        if spellId and spellName then
            if IsBlockedSpellForTracking(spellId) then
                PrintBlockedSpellMessage(spellName)
                return false
            end
            local passiveOrProc = IsPassiveOrProc(spellId)
            if passiveOrProc then
                return TryAddSpell(tostring(spellId))
            else
                local idx, notified = CooldownCompanion:AddButtonToGroup(CS.selectedGroup, "spell", spellId, spellName)
                if not idx then
                    return false
                end
                SelectNewButton(CS.selectedGroup, idx)
                if not notified then
                    CooldownCompanion:Print("Added spell: " .. spellName)
                end
                return true
            end
        end

        -- Try as item
        local itemId = C_Item.GetItemIDForItemInfo(input)
        if itemId and C_Item.IsItemDataCachedByID(itemId) then
            return FinalizeAddItem(itemId, CS.selectedGroup)
        end

        -- Passive/proc spell, no item match — report CDM error
        if spellId and spellName then
            CooldownCompanion:Print("Passive/proc spell " .. spellName .. " is not tracked in the Cooldown Manager.")
            return false
        end

        CooldownCompanion:Print("Not found: " .. input .. ". Try using the spell ID or drag from spellbook.")
        return false
    end
end

local function BuildEquipmentSlotAutocompleteEntry(itemSlot, aliases)
    local slotData = {
        type = CooldownCompanion.EQUIPMENT_SLOT_TYPE or "equipmentSlot",
        itemSlot = itemSlot,
        itemSlotKind = CooldownCompanion.EQUIPMENT_SLOT_KIND_TRINKET or "trinket",
    }
    local name = CooldownCompanion.GetEquipmentSlotDisplayName
        and CooldownCompanion.GetEquipmentSlotDisplayName(slotData)
        or ("Trinket Slot " .. tostring(itemSlot == (CooldownCompanion.TRINKET_SLOT_2 or 14) and 2 or 1))
    local effectiveItem = CooldownCompanion.ResolveEffectiveItem
        and CooldownCompanion.ResolveEffectiveItem(slotData)
        or nil
    local searchParts = { name:lower() }
    for _, alias in ipairs(aliases or {}) do
        searchParts[#searchParts + 1] = alias
    end
    return {
        id = CooldownCompanion.GetEntryStableKey and CooldownCompanion.GetEntryStableKey(slotData)
            or ("equipmentSlot:trinket:" .. tostring(itemSlot)),
        name = name,
        nameLower = name:lower(),
        searchLower = table.concat(searchParts, " "),
        icon = (effectiveItem and effectiveItem.trackable and effectiveItem.icon) or 134400,
        category = "Equipment",
        autocompleteKind = "equipment",
        isEquipmentSlot = true,
        itemSlot = itemSlot,
        itemSlotKind = slotData.itemSlotKind,
    }
end

local function AddEquipmentSlotAutocompleteEntries(cache)
    cache[#cache + 1] = BuildEquipmentSlotAutocompleteEntry(CooldownCompanion.TRINKET_SLOT_1 or 13, {
        "trinket 1",
        "slot 1",
        "first trinket",
        "top trinket",
        "equipment",
    })
    cache[#cache + 1] = BuildEquipmentSlotAutocompleteEntry(CooldownCompanion.TRINKET_SLOT_2 or 14, {
        "trinket 2",
        "slot 2",
        "second trinket",
        "bottom trinket",
        "equipment",
    })
end

------------------------------------------------------------------------
-- Helper: Receive a spell/item drop from the cursor
------------------------------------------------------------------------
local function TryReceiveCursorDrop()
    local cursorType, cursorID, _, cursorSpellID = GetCursorInfo()
    if not cursorType then return false end

    if not CS.selectedGroup then
        CooldownCompanion:Print("Select a group first before dropping spells or items.")
        ClearCursor()
        return false
    end

    local added = false
    if cursorType == "spell" and cursorSpellID then
        added = TryAddSpell(tostring(cursorSpellID))
    elseif cursorType == "petaction" and cursorID then
        added = TryAddSpell(tostring(cursorID), true)
    elseif cursorType == "item" and cursorID then
        added = TryAddItem(tostring(cursorID))
    end

    if added then
        ClearCursor()
        CooldownCompanion:RefreshConfigPanel()
    end
    return added
end

-- Autocomplete: Build cache of player spells + usable bag items
------------------------------------------------------------------------
local function BuildAutocompleteCache()
    local cache = {}
    local seen = {}

    AddEquipmentSlotAutocompleteEntries(cache)

    -- Iterate spellbook skill lines
    local numLines = C_SpellBook.GetNumSpellBookSkillLines()
    for lineIdx = 1, numLines do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIdx)
        if lineInfo and not lineInfo.shouldHide then
            local category = lineInfo.name or "Spells"
            for slotOffset = 1, lineInfo.numSpellBookItems do
                local slotIdx = lineInfo.itemIndexOffset + slotOffset
                local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIdx, Enum.SpellBookSpellBank.Player)
                local id = itemInfo and itemInfo.spellID
                local passiveCooldown = id and IsPassiveCooldownSpell(id)
                if itemInfo and id
                    and (not itemInfo.isPassive or passiveCooldown)
                    and not itemInfo.isOffSpec
                    and itemInfo.itemType ~= Enum.SpellBookItemType.Flyout
                    and itemInfo.itemType ~= Enum.SpellBookItemType.FutureSpell
                then
                    local isAura = IsPassiveOrProc(id)
                    if ShouldSuppressSpellbookEntry(id, lineIdx, isAura) then
                        -- Omit filtered entries to reduce autocomplete noise.
                    elseif not seen[id] then
                        seen[id] = true
                        table.insert(cache, {
                            id = id,
                            name = itemInfo.name,
                            nameLower = itemInfo.name:lower(),
                            icon = itemInfo.iconID or 134400,
                            category = category,
                            autocompleteKind = "spell",
                            isItem = false,
                        })
                    end
                end
            end
        end
    end

    -- Iterate pet spellbook
    local numPetSpells = C_SpellBook.HasPetSpells()
    if numPetSpells and numPetSpells > 0 then
        for slotIdx = 1, numPetSpells do
            local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIdx, Enum.SpellBookSpellBank.Pet)
            local id = itemInfo and itemInfo.spellID
            local passiveCooldown = id and IsPassiveCooldownSpell(id)
            if itemInfo and id
                and (not itemInfo.isPassive or passiveCooldown)
            then
                local isAura = IsPassiveOrProc(id)
                if not ShouldSuppressSpellbookEntry(id, itemInfo.skillLineIndex, isAura) and not seen[id] then
                    seen[id] = true
                    table.insert(cache, {
                        id = id,
                        name = itemInfo.name,
                        nameLower = itemInfo.name:lower(),
                        icon = itemInfo.iconID or 134400,
                        category = "Pet",
                        autocompleteKind = "spell",
                        isItem = false,
                        isPetSpell = true,
                    })
                end
            end
        end
    end

    -- Iterate bags for usable items
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
            if containerInfo and containerInfo.itemID then
                local itemID = containerInfo.itemID
                if not seen["item:" .. itemID] then
                    local spellName = C_Item.GetItemSpell(itemID)
                    if spellName then
                        seen["item:" .. itemID] = true
                        local itemName = containerInfo.itemName or C_Item.GetItemNameByID(itemID) or "Unknown"
                        table.insert(cache, {
                            id = itemID,
                            name = itemName,
                            nameLower = itemName:lower(),
                            icon = containerInfo.iconFileID or C_Item.GetItemIconByID(itemID) or 134400,
                            category = "Item",
                            autocompleteKind = "item",
                            isItem = true,
                        })
                    end
                end
            end
        end
    end

    -- Trackable auras, by their specific aura identity. Procs and applied
    -- auras (e.g. DoT debuffs) are not spellbook items, so this is the only
    -- discovery surface for standalone aura entries. Sourced from Blizzard's
    -- tracked buff/bar data (pure data API): membership there means Blizzard
    -- can track the aura, which is exactly what makes it addable here.
    -- Rows are deduped by underlying tracked aura: two data rows whose
    -- resolved/linked spellIDs overlap (e.g. an ability row and its applied
    -- DoT) would produce identical tracking entries, so only the first shows.
    local seenAuras = {}
    for _, cat in ipairs({ Enum.CooldownViewerCategory.TrackedBuff, Enum.CooldownViewerCategory.TrackedBar }) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                local id = cdInfo and cdInfo.spellID and ResolveCDMAuraSpellID(cdInfo)
                if id and not IsNeverTrackableSpell(id) then
                    local duplicate = seenAuras[id]
                    if not duplicate and cdInfo.linkedSpellIDs then
                        for _, linkedID in ipairs(cdInfo.linkedSpellIDs) do
                            if seenAuras[linkedID] then
                                duplicate = true
                                break
                            end
                        end
                    end
                    local spellInfo = not duplicate and C_Spell.GetSpellInfo(id)
                    if spellInfo and spellInfo.name then
                        seenAuras[id] = true
                        if cdInfo.linkedSpellIDs then
                            for _, linkedID in ipairs(cdInfo.linkedSpellIDs) do
                                seenAuras[linkedID] = true
                            end
                        end
                        table.insert(cache, {
                            id = id,
                            name = spellInfo.name,
                            displayName = ("%s |cff999999(%d)|r"):format(spellInfo.name, id),
                            nameLower = spellInfo.name:lower(),
                            icon = spellInfo.iconID or 134400,
                            category = "Aura",
                            autocompleteKind = "aura",
                            isItem = false,
                            forceAura = true,
                        })
                    end
                end
            end
        end
    end

    CS.autocompleteCache = cache
    return cache
end

------------------------------------------------------------------------
-- Autocomplete: Search cache for matches
------------------------------------------------------------------------
local function SearchAutocompleteInCache(query, cache)
    if not query or #query < 1 then return nil end

    local queryLower = query:lower()
    local queryNum = tonumber(query)
    local prefixMatches = {}
    local substringMatches = {}

    for _, entry in ipairs(cache) do
        local isMatch = false
        local isPrefix = false

        -- Match by numeric ID
        if queryNum and tostring(entry.id):find(query, 1, true) == 1 then
            isMatch = true
            isPrefix = true
        end

        -- Match by name substring
        if not isMatch then
            local searchable = entry.searchLower or entry.nameLower
            local pos = searchable and searchable:find(queryLower, 1, true)
            if pos then
                isMatch = true
                isPrefix = (pos == 1)
            end
        end

        if isMatch then
            if isPrefix then
                table.insert(prefixMatches, entry)
            else
                table.insert(substringMatches, entry)
            end
        end

        -- Early exit if we have enough prefix matches
        if #prefixMatches >= AUTOCOMPLETE_MAX_ROWS then break end
    end

    -- Combine: prefix matches first, then substring matches
    local results = {}
    for _, entry in ipairs(prefixMatches) do
        table.insert(results, entry)
        if #results >= AUTOCOMPLETE_MAX_ROWS then break end
    end
    if #results < AUTOCOMPLETE_MAX_ROWS then
        for _, entry in ipairs(substringMatches) do
            table.insert(results, entry)
            if #results >= AUTOCOMPLETE_MAX_ROWS then break end
        end
    end

    return #results > 0 and results or nil
end

local function SearchAutocomplete(query)
    local cache = CS.autocompleteCache or BuildAutocompleteCache()
    local groupId = CS.addingToPanelId or CS.selectedGroup
    if IsTriggerPanelTarget(groupId) then
        local filtered = {}
        for _, entry in ipairs(cache) do
            if not entry.isEquipmentSlot then
                filtered[#filtered + 1] = entry
            end
        end
        cache = filtered
    end
    return SearchAutocompleteInCache(query, cache)
end

------------------------------------------------------------------------
-- Autocomplete: Hide dropdown
------------------------------------------------------------------------
local function HideAutocomplete()
    if autocompleteDropdown then
        autocompleteDropdown:Hide()
    end
end

------------------------------------------------------------------------
-- Autocomplete: Update keyboard selection highlight
------------------------------------------------------------------------
local function UpdateAutocompleteHighlight()
    if not autocompleteDropdown then return end
    local idx = autocompleteDropdown._highlightIndex or 0
    for i, row in ipairs(autocompleteDropdown.rows) do
        if row.selectionBg then
            if i == idx then
                row.selectionBg:Show()
            else
                row.selectionBg:Hide()
            end
        end
    end
end

------------------------------------------------------------------------
-- Autocomplete: Select handler
------------------------------------------------------------------------
local function OnAutocompleteSelect(entry)
    HideAutocomplete()
    local addTargetGroupId = CS.addingToPanelId or CS.selectedGroup
    if not addTargetGroupId then return end

    CS.selectedGroup = addTargetGroupId
    local added
    if entry.isEquipmentSlot then
        added = TryAddEquipmentSlot(entry.itemSlot)
    elseif entry.isItem then
        added = TryAddItem(tostring(entry.id))
    else
        added = TryAddSpell(tostring(entry.id), entry.isPetSpell, entry.forceAura)
    end
    if added then
        if NotifyTutorialAction and CS.selectedGroup and CS.selectedButton then
            NotifyTutorialAction("inline_add_succeeded", {
                groupId = CS.selectedGroup,
                buttonIndex = CS.selectedButton,
                rawInput = entry.name,
            })
        end
        CS.newInput = ""
        CS.pendingEditBoxFocus = true
        CooldownCompanion:RefreshConfigPanel()
    end
end

------------------------------------------------------------------------
-- Autocomplete: Create or return the reusable dropdown frame
------------------------------------------------------------------------
local function GetOrCreateAutocompleteDropdown()
    if autocompleteDropdown then return autocompleteDropdown end

    local dropdown = CreateFrame("Frame", "CooldownCompanionAutocomplete", UIParent, "BackdropTemplate")
    dropdown:SetFrameStrata("TOOLTIP")
    dropdown:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    dropdown:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    dropdown:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    dropdown:Hide()

    dropdown.rows = {}
    for i = 1, AUTOCOMPLETE_MAX_ROWS do
        local row = CreateFrame("Button", nil, dropdown)
        row:RegisterForClicks("AnyUp")
        row:SetHeight(AUTOCOMPLETE_ROW_HEIGHT)
        row:SetPoint("TOPLEFT", dropdown, "TOPLEFT", 1, -((i - 1) * AUTOCOMPLETE_ROW_HEIGHT) - 1)
        row:SetPoint("TOPRIGHT", dropdown, "TOPRIGHT", -1, -((i - 1) * AUTOCOMPLETE_ROW_HEIGHT) - 1)

        -- Keyboard selection highlight (manually shown/hidden)
        local selectionBg = row:CreateTexture(nil, "BACKGROUND")
        selectionBg:SetAllPoints()
        selectionBg:SetColorTexture(0.2, 0.4, 0.7, 0.4)
        selectionBg:Hide()
        row.selectionBg = selectionBg

        -- Mouse hover highlight
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.3, 0.5, 0.8, 0.3)

        -- Icon
        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(AUTOCOMPLETE_ICON_SIZE, AUTOCOMPLETE_ICON_SIZE)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        row.icon = icon

        -- Name text
        local nameText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        nameText:SetPoint("LEFT", icon, "RIGHT", 6, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        row.nameText = nameText

        -- Type badge and label
        local categoryText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        categoryText:SetSize(AUTOCOMPLETE_TYPE_LABEL_WIDTH, AUTOCOMPLETE_ROW_HEIGHT)
        categoryText:SetJustifyH("RIGHT")
        categoryText:SetTextColor(0.5, 0.5, 0.5, 1)
        row.categoryText = categoryText

        local typeBadge = row:CreateTexture(nil, "ARTWORK")
        typeBadge:SetSize(AUTOCOMPLETE_TYPE_BADGE_SIZE, AUTOCOMPLETE_TYPE_BADGE_SIZE)
        typeBadge:SetPoint("RIGHT", row, "RIGHT", -AUTOCOMPLETE_TYPE_RIGHT_PAD, 0)
        row.typeBadge = typeBadge

        categoryText:SetPoint("RIGHT", typeBadge, "LEFT", -AUTOCOMPLETE_TYPE_GAP, 0)
        nameText:SetPoint("RIGHT", categoryText, "LEFT", -6, 0)

        row:SetScript("OnMouseDown", function()
            dropdown._clickInProgress = true
        end)

        row:SetScript("OnClick", function()
            dropdown._clickInProgress = false
            if row.entry and dropdown._onSelect then
                dropdown._onSelect(row.entry)
            end
        end)

        row:Hide()
        dropdown.rows[i] = row
    end

    -- Hide when edit box loses focus (checked via OnUpdate)
    dropdown:SetScript("OnUpdate", function(self)
        if self._clickInProgress then return end
        if self._editbox and not self._editbox:HasFocus() then
            self:Hide()
        end
    end)

    autocompleteDropdown = dropdown
    return dropdown
end

------------------------------------------------------------------------
-- Autocomplete: Show results anchored to an edit box widget
------------------------------------------------------------------------
local function ShowAutocompleteResults(results, anchorWidget, onSelect, options)
    local dropdown = GetOrCreateAutocompleteDropdown()
    dropdown._onSelect = onSelect
    dropdown._editbox = anchorWidget.editbox
    dropdown._requireExactNumericEnter = options and options.requireExactNumericEnter == true

    if not results then
        dropdown:Hide()
        return
    end

    -- Anchor below the edit box widget's frame (parented to UIParent, so it draws above the config panel)
    local anchorFrame = anchorWidget.frame or anchorWidget
    dropdown:ClearAllPoints()
    dropdown:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
    dropdown:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -2)

    local numResults = #results
    dropdown._highlightIndex = 1
    dropdown._numResults = numResults
    dropdown:SetHeight((numResults * AUTOCOMPLETE_ROW_HEIGHT) + 2)

    for i = 1, AUTOCOMPLETE_MAX_ROWS do
        local row = dropdown.rows[i]
        if i <= numResults then
            local entry = results[i]
            row.entry = entry
            row.icon:SetTexture(entry.icon)
            row.nameText:SetText(entry.displayName or entry.name)
            local typeDisplay = GetAutocompleteTypeDisplay(entry)
            row.typeBadge:SetAtlas(typeDisplay.atlas, false)
            row.typeBadge:Show()
            row.categoryText:SetText(typeDisplay.label)
            row:Show()
        else
            row.entry = nil
            row.typeBadge:Hide()
            row:Hide()
        end
    end

    dropdown:Show()
    UpdateAutocompleteHighlight()
end

------------------------------------------------------------------------
-- Autocomplete: Centralized keyboard handler for arrow/enter navigation
------------------------------------------------------------------------
local function HandleAutocompleteKeyDown(key)
    if not autocompleteDropdown or not autocompleteDropdown:IsShown() then return end
    local maxIdx = autocompleteDropdown._numResults or 0
    if maxIdx == 0 then return end
    if key == "DOWN" then
        local idx = (autocompleteDropdown._highlightIndex or 0) + 1
        if idx > maxIdx then idx = 1 end
        autocompleteDropdown._highlightIndex = idx
        UpdateAutocompleteHighlight()
    elseif key == "UP" then
        local idx = (autocompleteDropdown._highlightIndex or 0) - 1
        if idx < 1 then idx = maxIdx end
        autocompleteDropdown._highlightIndex = idx
        UpdateAutocompleteHighlight()
    elseif key == "ENTER" then
        local idx = autocompleteDropdown._highlightIndex or 0
        local editText = autocompleteDropdown._editbox and autocompleteDropdown._editbox:GetText()
        local exactID = editText and editText:match("^%s*(%d+)%s*$")
        exactID = exactID and tonumber(exactID) or nil
        if autocompleteDropdown._requireExactNumericEnter and exactID then
            local exactIndex
            for rowIndex = 1, maxIdx do
                local row = autocompleteDropdown.rows[rowIndex]
                if row and row.entry and tonumber(row.entry.id) == exactID then
                    exactIndex = rowIndex
                    break
                end
            end
            if not exactIndex then
                autocompleteDropdown:Hide()
                return
            end
            idx = exactIndex
        end
        if idx > 0 and autocompleteDropdown.rows[idx] and autocompleteDropdown.rows[idx].entry then
            autocompleteDropdown._enterConsumed = true
            if autocompleteDropdown._onSelect then
                autocompleteDropdown._onSelect(autocompleteDropdown.rows[idx].entry)
            end
        end
    end
end

------------------------------------------------------------------------
-- Autocomplete: Check and clear enter-consumed flag
------------------------------------------------------------------------
local function ConsumeAutocompleteEnter()
    if autocompleteDropdown and autocompleteDropdown._enterConsumed then
        autocompleteDropdown._enterConsumed = nil
        return true
    end
    return false
end

------------------------------------------------------------------------
-- CS.* exports (consumed by ConfigSettings/ files)
------------------------------------------------------------------------
CS.ShowAutocompleteResults = ShowAutocompleteResults
CS.HideAutocomplete = HideAutocomplete
CS.SearchAutocompleteInCache = SearchAutocompleteInCache
CS.HandleAutocompleteKeyDown = HandleAutocompleteKeyDown
CS.ConsumeAutocompleteEnter = ConsumeAutocompleteEnter

-- Install autocomplete keyboard navigation on an AceGUI EditBox widget.
-- Uses SetScript (not HookScript) so the handler is idempotent — calling
-- this again on the same underlying frame simply replaces the previous handler.
-- AceGUI EditBox does not set OnKeyDown, so there is no AceGUI handler to clobber.
-- Note: the handler persists if the widget is recycled. This is safe because
-- HandleAutocompleteKeyDown no-ops when the autocomplete dropdown is hidden.
function CS.SetupAutocompleteKeyHandler(editBoxWidget)
    editBoxWidget.editbox:SetScript("OnKeyDown", function(self, key)
        CS.HandleAutocompleteKeyDown(key)
    end)
end

------------------------------------------------------------------------
-- ST._ exports (consumed by later Config/ files)
------------------------------------------------------------------------
ST._TryAdd = TryAdd
ST._TryReceiveCursorDrop = TryReceiveCursorDrop
ST._BuildAutocompleteCache = BuildAutocompleteCache
ST._OnAutocompleteSelect = OnAutocompleteSelect
ST._SearchAutocomplete = SearchAutocomplete
