--[[
    CooldownCompanion - Config/SpellItemAdd
    Spell/item addition + autocomplete system.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Imports from earlier Config/ files
local IsSpellInCDMBuffBar = ST._IsSpellInCDMBuffBar
local IsSpellInCDMCooldown = ST._IsSpellInCDMCooldown
local IsPassiveOrProc = ST._IsPassiveOrProc
local GetButtonIcon = ST._GetButtonIcon
local CDM_VIEWER_NAMES = ST._CDM_VIEWER_NAMES

-- File-local state
local autocompleteDropdown

-- Autocomplete constants
local AUTOCOMPLETE_MAX_ROWS = 8
local AUTOCOMPLETE_ROW_HEIGHT = 22
local AUTOCOMPLETE_ICON_SIZE = 16

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
        local passiveOrProc = IsPassiveOrProc(spellId)
        -- forceAura overrides passive/proc classification for dual-CDM spells
        if forceAura == false then
            passiveOrProc = false   -- Cooldown mode: treat as normal spell
        elseif forceAura == true then
            passiveOrProc = true    -- Buff mode: treat as passive/proc
        end
        if passiveOrProc and not IsSpellInCDMBuffBar(spellId) then
            CooldownCompanion:Print("Passive/proc spell " .. spellName .. " is not tracked in the Cooldown Manager.")
            return false
        end
        -- Multi-CDM-child: if passive/proc spell has multiple CDM entries, auto-add one button per child
        if passiveOrProc then
            local allChildren = CooldownCompanion.viewerAuraAllChildren[spellId]
            if allChildren and #allChildren > 1 then
                local count = #allChildren
                for i = 1, count do
                    CooldownCompanion:AddButtonToGroup(
                        CS.selectedGroup, "spell", spellId, spellName,
                        isPetSpell, true, forceAura, i)
                end
                CooldownCompanion:Print("Added " .. count .. " buttons for "
                    .. spellName .. " (one per CDM entry). Their icons will "
                    .. "update during combat to show the active variant.")
                return true
            end
        end
        CooldownCompanion:AddButtonToGroup(CS.selectedGroup, "spell", spellId, spellName, isPetSpell, passiveOrProc or nil, forceAura)
        CooldownCompanion:Print("Added spell: " .. spellName)
        return true
    else
        CooldownCompanion:Print("Spell not found: " .. input .. ". Try using the spell ID or drag from spellbook.")
        return false
    end
end

------------------------------------------------------------------------
-- Helper: Add item to selected group
------------------------------------------------------------------------
local function FinalizeAddItem(itemId, groupId)
    local itemName = C_Item.GetItemNameByID(itemId) or "Unknown Item"
    local spellName = C_Item.GetItemSpell(itemId)
    if not spellName then
        CooldownCompanion:Print("Item has no usable effect: " .. itemName)
        return false
    end
    CooldownCompanion:AddButtonToGroup(groupId, "item", itemId, itemName)
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
        if FinalizeAddItem(itemId, capturedGroup) then
            CooldownCompanion:RefreshConfigPanel()
        end
    end)
    return false
end

------------------------------------------------------------------------
-- Unified add: resolve input as spell or item automatically
------------------------------------------------------------------------
local function TryAdd(input)
    if input == "" or not CS.selectedGroup then return false end

    local id = tonumber(input)

    if id then
        -- ID-based input: check both spell and item
        local spellInfo = C_Spell.GetSpellInfo(id)
        local spellFound = spellInfo and spellInfo.name
        local passiveOrProc = spellFound and IsPassiveOrProc(id)

        -- Passive/proc spell: require CDM presence
        if spellFound and passiveOrProc then
            if IsSpellInCDMBuffBar(id) then
                CooldownCompanion:AddButtonToGroup(CS.selectedGroup, "spell", id, spellInfo.name, nil, true)
                CooldownCompanion:Print("Added spell: " .. spellInfo.name)
                return true
            end
            -- Not in CDM — fall through to try as item, then report error
        end

        -- Non-passive spell → add it
        if spellFound and not passiveOrProc then
            local forceAura = nil
            if IsSpellInCDMCooldown(id) and IsSpellInCDMBuffBar(id) then
                forceAura = false  -- dual-CDM: default to cooldown mode
            end
            CooldownCompanion:AddButtonToGroup(CS.selectedGroup, "spell", id, spellInfo.name, nil, nil, forceAura)
            CooldownCompanion:Print("Added spell: " .. spellInfo.name)
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
                if FinalizeAddItem(itemId, capturedGroup) then
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
            local passiveOrProc = IsPassiveOrProc(spellId)
            if passiveOrProc then
                if IsSpellInCDMBuffBar(spellId) then
                    CooldownCompanion:AddButtonToGroup(CS.selectedGroup, "spell", spellId, spellName, nil, true)
                    CooldownCompanion:Print("Added spell: " .. spellName)
                    return true
                end
                -- Not in CDM — fall through to try as item, then report error
            else
                CooldownCompanion:AddButtonToGroup(CS.selectedGroup, "spell", spellId, spellName)
                CooldownCompanion:Print("Added spell: " .. spellName)
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

------------------------------------------------------------------------
-- Autocomplete: Build cache of player spells + usable bag items
------------------------------------------------------------------------
local function BuildAutocompleteCache()
    local cache = {}
    local seen = {}

    -- Pre-compute dual-CDM spell set (spells in both cooldown and buff CDM categories)
    local cdmCooldownSet = {}
    for _, cat in ipairs({Enum.CooldownViewerCategory.Essential, Enum.CooldownViewerCategory.Utility}) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info and info.spellID then
                    cdmCooldownSet[info.spellID] = true
                    if info.overrideSpellID then cdmCooldownSet[info.overrideSpellID] = true end
                    if info.overrideTooltipSpellID then cdmCooldownSet[info.overrideTooltipSpellID] = true end
                end
            end
        end
    end
    local cdmBuffSet = {}
    for _, cat in ipairs({Enum.CooldownViewerCategory.TrackedBuff, Enum.CooldownViewerCategory.TrackedBar}) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info and info.spellID then
                    cdmBuffSet[info.spellID] = true
                    if info.overrideSpellID then cdmBuffSet[info.overrideSpellID] = true end
                    if info.overrideTooltipSpellID then cdmBuffSet[info.overrideTooltipSpellID] = true end
                end
            end
        end
    end
    local dualCDMSet = {}
    for id in pairs(cdmCooldownSet) do
        if cdmBuffSet[id] then
            dualCDMSet[id] = true
        end
    end

    -- Iterate spellbook skill lines
    local numLines = C_SpellBook.GetNumSpellBookSkillLines()
    for lineIdx = 1, numLines do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIdx)
        if lineInfo and not lineInfo.shouldHide then
            local category = lineInfo.name or "Spells"
            for slotOffset = 1, lineInfo.numSpellBookItems do
                local slotIdx = lineInfo.itemIndexOffset + slotOffset
                local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIdx, Enum.SpellBookSpellBank.Player)
                if itemInfo and itemInfo.spellID
                    and not itemInfo.isPassive
                    and not itemInfo.isOffSpec
                    and itemInfo.itemType ~= Enum.SpellBookItemType.Flyout
                    and itemInfo.itemType ~= Enum.SpellBookItemType.FutureSpell
                then
                    local id = itemInfo.spellID
                    if not seen[id] then
                        seen[id] = true
                        if dualCDMSet[id] then
                            -- Dual-CDM spell: insert separate Cooldown and Buff entries
                            table.insert(cache, {
                                id = id,
                                name = itemInfo.name .. " (Cooldown)",
                                nameLower = itemInfo.name:lower(),
                                icon = itemInfo.iconID or 134400,
                                category = category,
                                isItem = false,
                                forceAura = false,
                            })
                            table.insert(cache, {
                                id = id,
                                name = itemInfo.name .. " (Buff)",
                                nameLower = itemInfo.name:lower(),
                                icon = itemInfo.iconID or 134400,
                                category = "Tracked Buff",
                                isItem = false,
                                forceAura = true,
                            })
                        else
                            table.insert(cache, {
                                id = id,
                                name = itemInfo.name,
                                nameLower = itemInfo.name:lower(),
                                icon = itemInfo.iconID or 134400,
                                category = category,
                                isItem = false,
                            })
                        end
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
            if itemInfo and itemInfo.spellID
                and not itemInfo.isPassive
            then
                local id = itemInfo.spellID
                if not seen[id] then
                    seen[id] = true
                    table.insert(cache, {
                        id = id,
                        name = itemInfo.name,
                        nameLower = itemInfo.name:lower(),
                        icon = itemInfo.iconID or 134400,
                        category = "Pet",
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
                            isItem = true,
                        })
                    end
                end
            end
        end
    end

    -- Iterate CDM TrackedBuff + TrackedBar for passive/proc spells
    for _, cat in ipairs({Enum.CooldownViewerCategory.TrackedBuff, Enum.CooldownViewerCategory.TrackedBar}) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if cdInfo and cdInfo.spellID then
                    local id = cdInfo.spellID
                    if not seen[id] then
                        local spellInfo = C_Spell.GetSpellInfo(id)
                        if spellInfo and spellInfo.name and IsPassiveOrProc(id) then
                            seen[id] = true
                            table.insert(cache, {
                                id = id,
                                name = spellInfo.name,
                                nameLower = spellInfo.name:lower(),
                                icon = spellInfo.iconID or 134400,
                                category = "Cooldown Manager",
                                isItem = false,
                                isPassive = true,
                            })
                        end
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
            local pos = entry.nameLower:find(queryLower, 1, true)
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
    return SearchAutocompleteInCache(query, CS.autocompleteCache or BuildAutocompleteCache())
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
    if not CS.selectedGroup then return end
    local added
    if entry.isItem then
        added = TryAddItem(tostring(entry.id))
    else
        added = TryAddSpell(tostring(entry.id), entry.isPetSpell, entry.forceAura)
    end
    if added then
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
        nameText:SetPoint("RIGHT", row, "RIGHT", -80, 0)
        nameText:SetJustifyH("LEFT")
        nameText:SetWordWrap(false)
        row.nameText = nameText

        -- Category text
        local categoryText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        categoryText:SetPoint("RIGHT", row, "RIGHT", -6, 0)
        categoryText:SetJustifyH("RIGHT")
        categoryText:SetTextColor(0.5, 0.5, 0.5, 1)
        row.categoryText = categoryText

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
local function ShowAutocompleteResults(results, anchorWidget, onSelect)
    local dropdown = GetOrCreateAutocompleteDropdown()
    dropdown._onSelect = onSelect
    dropdown._editbox = anchorWidget.editbox

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
            row.nameText:SetText(entry.name)
            row.categoryText:SetText(entry.category)
            row:Show()
        else
            row.entry = nil
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

------------------------------------------------------------------------
-- ST._ exports (consumed by later Config/ files)
------------------------------------------------------------------------
ST._TryAdd = TryAdd
ST._TryReceiveCursorDrop = TryReceiveCursorDrop
ST._BuildAutocompleteCache = BuildAutocompleteCache
ST._OnAutocompleteSelect = OnAutocompleteSelect
ST._SearchAutocomplete = SearchAutocomplete
