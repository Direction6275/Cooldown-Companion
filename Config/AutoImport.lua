--[[
    CooldownCompanion - Config/AutoImport
    Auto-add import flow for selected group (Action Bars 1-6 / Spellbook / CDM Auras).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local IsPassiveOrProc = ST._IsPassiveOrProc
local IsSpellInCDMBuffBar = ST._IsSpellInCDMBuffBar
local IsSpellInCDMCooldown = ST._IsSpellInCDMCooldown
local IsNeverTrackableSpell = ST._IsNeverTrackableSpell
local ShouldSuppressSpellbookEntry = ST._ShouldSuppressSpellbookEntry

local ICON_FALLBACK = 134400
local ACTION_BAR_COUNT = 6
local BUTTONS_PER_BAR = 12

local SOURCE_ACTION_BARS = "actionbars"
local SOURCE_SPELLBOOK = "spellbook"
local SOURCE_CDM_AURAS = "cdm_auras"
local SORT_SOURCE_THEN_NAME = "source_then_name"
local AUTO_ADD_STEP_SOURCE = 1
local AUTO_ADD_STEP_OPTIONS = 2
local AUTO_ADD_STEP_REVIEW = 3

local function CreateAutoAddPrefDefaults()
    local selectedBars = {}
    for i = 1, ACTION_BAR_COUNT do
        selectedBars[i] = true
    end
    return {
        lastSource = SOURCE_ACTION_BARS,
        selectedBars = selectedBars,
        showSkipped = false,
        showSources = true,
        sortMode = SORT_SOURCE_THEN_NAME,
    }
end

local function NormalizeSource(source)
    if source == SOURCE_ACTION_BARS or source == SOURCE_SPELLBOOK or source == SOURCE_CDM_AURAS then
        return source
    end
    return SOURCE_ACTION_BARS
end

local function NormalizeSortMode(sortMode)
    if sortMode == SORT_SOURCE_THEN_NAME then
        return sortMode
    end
    return SORT_SOURCE_THEN_NAME
end

local function NormalizeBarSelection(selectedBars)
    local normalized = {}
    for i = 1, ACTION_BAR_COUNT do
        normalized[i] = selectedBars and selectedBars[i] == true or false
    end
    return normalized
end

local function EnsureAutoAddPrefs()
    local profile = CooldownCompanion and CooldownCompanion.db and CooldownCompanion.db.profile
    local defaults = CreateAutoAddPrefDefaults()
    if not profile then
        return defaults
    end

    local stored = profile.autoAddPrefs or {}
    local normalized = {
        lastSource = NormalizeSource(stored.lastSource or defaults.lastSource),
        selectedBars = NormalizeBarSelection(stored.selectedBars or defaults.selectedBars),
        showSkipped = stored.showSkipped == true,
        showSources = stored.showSources ~= false,
        sortMode = NormalizeSortMode(stored.sortMode or defaults.sortMode),
    }
    profile.autoAddPrefs = normalized
    return normalized
end

local function PersistAutoAddPrefs(state)
    if not state then return end
    local profile = CooldownCompanion and CooldownCompanion.db and CooldownCompanion.db.profile
    if not profile then return end

    local prefs = EnsureAutoAddPrefs()
    prefs.lastSource = NormalizeSource(state.source)
    prefs.selectedBars = NormalizeBarSelection(state.selectedBars)
    prefs.showSkipped = state.showSkipped == true
    prefs.showSources = state.showSources ~= false
    prefs.sortMode = NormalizeSortMode(state.sortMode)
    profile.autoAddPrefs = prefs
end

local function CreateDefaultBarSelection()
    local selectedBars = {}
    for i = 1, ACTION_BAR_COUNT do
        selectedBars[i] = true
    end
    return selectedBars
end

local function CreatePreviewResult()
    return {
        spells = {},
        auras = {},
        items = {},
        skipped = {},
    }
end

local function AddSkipped(result, sourceLabel, reason, name)
    result.skipped[#result.skipped + 1] = {
        source = sourceLabel,
        reason = reason,
        name = name or "Unknown",
    }
end

local function TryAddEntry(result, seen, bucketKey, entry, sourceLabel)
    local dedupeKey
    if bucketKey == "items" then
        dedupeKey = "item:" .. tostring(entry.id)
    elseif bucketKey == "auras" then
        dedupeKey = "spell:" .. tostring(entry.id) .. ":aura"
    else
        dedupeKey = "spell:" .. tostring(entry.id) .. ":spell"
    end

    if seen[dedupeKey] then
        AddSkipped(result, sourceLabel, "Duplicate entry in this import selection.", entry.name)
        return
    end

    seen[dedupeKey] = true
    entry.importKey = dedupeKey
    result[bucketKey][#result[bucketKey] + 1] = entry
end

local function BuildActionBarPreview(selectedBars)
    local result = CreatePreviewResult()
    local seen = {}
    local hasSelectedBar = false

    for barIndex = 1, ACTION_BAR_COUNT do
        if selectedBars[barIndex] then
            hasSelectedBar = true
            for buttonIndex = 1, BUTTONS_PER_BAR do
                local slot = ((barIndex - 1) * BUTTONS_PER_BAR) + buttonIndex
                local sourceLabel = "Bar " .. barIndex .. " Slot " .. buttonIndex

                if C_ActionBar.HasAction(slot) then
                    if C_ActionBar.IsItemAction(slot) then
                        -- C_ActionBar has no GetActionInfo API in 12.0.x; GetActionInfo
                        -- remains the supported way to read item action IDs from slots.
                        local actionType, id = GetActionInfo(slot)
                        local itemID = tonumber(id)
                        if actionType ~= "item" or not itemID then
                            local shownType = actionType or "unknown"
                            AddSkipped(result, sourceLabel, "Unsupported action type: " .. shownType .. ".", "Unknown")
                        else
                            local itemName = C_Item.GetItemNameByID(itemID) or ("Item " .. itemID)
                            if not C_Item.GetItemSpell(itemID) then
                                AddSkipped(result, sourceLabel, "Item has no usable effect.", itemName)
                            else
                                TryAddEntry(result, seen, "items", {
                                    type = "item",
                                    id = itemID,
                                    name = itemName,
                                    icon = C_Item.GetItemIconByID(itemID) or C_ActionBar.GetActionTexture(slot) or ICON_FALLBACK,
                                    source = sourceLabel,
                                }, sourceLabel)
                            end
                        end
                    else
                        local spellID = C_ActionBar.GetSpell(slot)
                        if spellID and spellID ~= 0 then
                            local spellInfo = C_Spell.GetSpellInfo(spellID)
                            local spellName = spellInfo and spellInfo.name
                            if not spellName then
                                AddSkipped(result, sourceLabel, "Spell data is unavailable.", "Spell " .. spellID)
                            elseif IsNeverTrackableSpell(spellID) then
                                -- Omit known non-trackable spells from preview.
                            else
                                local isAura = IsPassiveOrProc(spellID)
                                if isAura and not IsSpellInCDMBuffBar(spellID) then
                                    AddSkipped(result, sourceLabel, "Passive/proc spell is not tracked in CDM.", spellName)
                                else
                                    local bucketKey = isAura and "auras" or "spells"
                                    TryAddEntry(result, seen, bucketKey, {
                                        type = "spell",
                                        id = spellID,
                                        name = spellName,
                                        icon = spellInfo.iconID or C_ActionBar.GetActionTexture(slot) or ICON_FALLBACK,
                                        source = sourceLabel,
                                    }, sourceLabel)
                                end
                            end
                        else
                            local actionType = GetActionInfo(slot)
                            local shownType = actionType or "unknown"
                            AddSkipped(result, sourceLabel, "Unsupported action type: " .. shownType .. ".", "Unknown")
                        end
                    end
                end
            end
        end
    end

    if not hasSelectedBar then
        AddSkipped(result, "Action Bars", "No action bars selected.", "None")
    end

    return result
end

local function BuildSpellbookPreview()
    local result = CreatePreviewResult()
    local seen = {}

    local function AddSpellbookEntry(itemInfo, sourceLabel, skillLineIndex)
        if not itemInfo or not itemInfo.spellID then return end
        if itemInfo.isOffSpec then return end
        if itemInfo.itemType == Enum.SpellBookItemType.Flyout then return end
        if itemInfo.itemType == Enum.SpellBookItemType.FutureSpell then return end

        local spellID = itemInfo.spellID
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        local spellName = (spellInfo and spellInfo.name) or itemInfo.name
        if not spellName then
            AddSkipped(result, sourceLabel, "Spell data is unavailable.", "Spell " .. spellID)
            return
        end

        local isAura = IsPassiveOrProc(spellID)
        if isAura then
            -- Spellbook Auto Add no longer imports aura entries.
            return
        end
        if ShouldSuppressSpellbookEntry(spellID, skillLineIndex, isAura) then
            -- Omit filtered spellbook entries silently to reduce preview noise.
            return
        end
        local bucketKey = isAura and "auras" or "spells"
        TryAddEntry(result, seen, bucketKey, {
            type = "spell",
            id = spellID,
            name = spellName,
            icon = itemInfo.iconID or (spellInfo and spellInfo.iconID) or ICON_FALLBACK,
            source = sourceLabel,
        }, sourceLabel)
    end

    local numLines = C_SpellBook.GetNumSpellBookSkillLines()
    for lineIdx = 1, numLines do
        local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(lineIdx)
        if lineInfo and not lineInfo.shouldHide then
            local sourceLabel = lineInfo.name or "Spellbook"
            for slotOffset = 1, lineInfo.numSpellBookItems do
                local slotIdx = lineInfo.itemIndexOffset + slotOffset
                local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIdx, Enum.SpellBookSpellBank.Player)
                AddSpellbookEntry(itemInfo, sourceLabel, lineIdx)
            end
        end
    end

    local numPetSpells = C_SpellBook.HasPetSpells()
    if numPetSpells and numPetSpells > 0 then
        for slotIdx = 1, numPetSpells do
            local itemInfo = C_SpellBook.GetSpellBookItemInfo(slotIdx, Enum.SpellBookSpellBank.Pet)
            AddSpellbookEntry(itemInfo, "Pet", itemInfo and itemInfo.skillLineIndex)
        end
    end

    return result
end

local CDM_AURA_CATEGORY_INFO = {
    { category = Enum.CooldownViewerCategory.TrackedBuff, label = "CDM Tracked Buff" },
    { category = Enum.CooldownViewerCategory.TrackedBar, label = "CDM Tracked Bar" },
}

local function BuildCDMAuraPreview()
    local result = CreatePreviewResult()
    local seen = {}

    for _, catInfo in ipairs(CDM_AURA_CATEGORY_INFO) do
        local cooldownIDs = C_CooldownViewer.GetCooldownViewerCategorySet(catInfo.category, false)
        if cooldownIDs then
            for _, cooldownID in ipairs(cooldownIDs) do
                local cooldownInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cooldownID)
                if not cooldownInfo then
                    AddSkipped(result, catInfo.label, "Missing cooldown info.", "Cooldown " .. cooldownID)
                elseif not cooldownInfo.spellID then
                    AddSkipped(result, catInfo.label, "Entry has no spell ID.", "Cooldown " .. cooldownID)
                elseif not cooldownInfo.isKnown then
                    -- Known/current-spec only; omit unknown entries silently.
                else
                    local spellInfo = C_Spell.GetSpellInfo(cooldownInfo.spellID)
                    if not spellInfo or not spellInfo.name then
                        AddSkipped(result, catInfo.label, "Spell data is unavailable.", "Spell " .. cooldownInfo.spellID)
                    else
                        TryAddEntry(result, seen, "auras", {
                            type = "spell",
                            id = cooldownInfo.spellID,
                            name = spellInfo.name,
                            icon = spellInfo.iconID or ICON_FALLBACK,
                            source = catInfo.label,
                        }, catInfo.label)
                    end
                end
            end
        end
    end

    return result
end

local function CountPreviewEntries(preview)
    local spellCount = #preview.spells
    local auraCount = #preview.auras
    local itemCount = #preview.items
    return spellCount, auraCount, itemCount, spellCount + auraCount + itemCount
end

local function LowerText(value)
    if value == nil then
        return ""
    end
    return tostring(value):lower()
end

local function SortEntriesBySourceThenName(entries)
    table.sort(entries, function(a, b)
        local sourceA = LowerText(a and a.source)
        local sourceB = LowerText(b and b.source)
        if sourceA ~= sourceB then
            return sourceA < sourceB
        end

        local nameA = LowerText(a and a.name)
        local nameB = LowerText(b and b.name)
        if nameA ~= nameB then
            return nameA < nameB
        end

        local reasonA = LowerText(a and a.reason)
        local reasonB = LowerText(b and b.reason)
        if reasonA ~= reasonB then
            return reasonA < reasonB
        end

        return (a and a.id or 0) < (b and b.id or 0)
    end)
end

local function SortPreview(preview, sortMode)
    local mode = NormalizeSortMode(sortMode)
    if mode == SORT_SOURCE_THEN_NAME then
        SortEntriesBySourceThenName(preview.spells)
        SortEntriesBySourceThenName(preview.auras)
        SortEntriesBySourceThenName(preview.items)
        SortEntriesBySourceThenName(preview.skipped)
    end
end

local function IteratePreviewEntries(preview, callback)
    for _, entry in ipairs(preview.spells) do
        callback(entry, "spells")
    end
    for _, entry in ipairs(preview.auras) do
        callback(entry, "auras")
    end
    for _, entry in ipairs(preview.items) do
        callback(entry, "items")
    end
end

local function NormalizeSelectionState(preview, selectedEntries)
    local active = {}
    IteratePreviewEntries(preview, function(entry)
        if entry.importKey then
            active[entry.importKey] = true
            if selectedEntries[entry.importKey] == nil then
                selectedEntries[entry.importKey] = true
            end
        end
    end)
    for key in pairs(selectedEntries) do
        if not active[key] then
            selectedEntries[key] = nil
        end
    end
end

local function CountSelectedEntries(preview, selectedEntries)
    local spellCount, auraCount, itemCount = 0, 0, 0
    for _, entry in ipairs(preview.spells) do
        if selectedEntries[entry.importKey] then
            spellCount = spellCount + 1
        end
    end
    for _, entry in ipairs(preview.auras) do
        if selectedEntries[entry.importKey] then
            auraCount = auraCount + 1
        end
    end
    for _, entry in ipairs(preview.items) do
        if selectedEntries[entry.importKey] then
            itemCount = itemCount + 1
        end
    end
    return spellCount, auraCount, itemCount, spellCount + auraCount + itemCount
end

local function SetAllEntriesSelected(preview, selectedEntries, value)
    IteratePreviewEntries(preview, function(entry)
        if entry.importKey then
            selectedEntries[entry.importKey] = value and true or false
        end
    end)
end

local function AddSectionHeading(scroll, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)
end

local function AddSelectableEntryRow(state, scroll, entry, onValueChanged)
    local row = AceGUI:Create("CheckBox")
    local icon = tonumber(entry.icon) or ICON_FALLBACK
    local label = "|T" .. icon .. ":15:15:0:0|t " .. (entry.name or "Unknown")
    if state.showSources ~= false then
        label = label .. "  |cff9d9d9d[" .. (entry.source or "Unknown Source") .. "]|r"
    end
    row:SetLabel(label)
    row:SetValue(state.selectedEntries[entry.importKey] ~= false)
    row:SetFullWidth(true)
    row:SetCallback("OnValueChanged", function(_, _, value)
        state.selectedEntries[entry.importKey] = value and true or false
        if onValueChanged then
            onValueChanged()
        end
    end)
    scroll:AddChild(row)
end

local function AddEmptyRow(scroll, text)
    local row = AceGUI:Create("Label")
    row:SetText(text or "None")
    row:SetFullWidth(true)
    scroll:AddChild(row)
end

local function AddSkippedRow(state, scroll, skipped)
    local row = AceGUI:Create("Label")
    local sourceLabel = state.showSources ~= false and (" [" .. (skipped.source or "Unknown Source") .. "]") or ""
    local line = "- " .. (skipped.name or "Unknown") .. sourceLabel .. ": " .. (skipped.reason or "Skipped.")
    row:SetText(line)
    row:SetFullWidth(true)
    scroll:AddChild(row)
end

local function ApplyPreviewToGroup(groupID, preview, selectedEntries, suppressRefresh)
    selectedEntries = selectedEntries or {}
    local group = CooldownCompanion.db.profile.groups[groupID]
    if not group then
        CooldownCompanion:Print("Selected group no longer exists.")
        return false
    end

    local addedSpells, addedAuras, addedItems = 0, 0, 0
    local applySkipped = 0

    for _, entry in ipairs(preview.spells) do
        if selectedEntries[entry.importKey] then
            local spellInfo = C_Spell.GetSpellInfo(entry.id)
            if spellInfo and spellInfo.name then
                local forceAura = nil
                if IsSpellInCDMCooldown(entry.id) and IsSpellInCDMBuffBar(entry.id) then
                    forceAura = false
                end
                CooldownCompanion:AddButtonToGroup(groupID, "spell", entry.id, spellInfo.name, nil, nil, forceAura)
                addedSpells = addedSpells + 1
            else
                applySkipped = applySkipped + 1
            end
        end
    end

    for _, entry in ipairs(preview.auras) do
        if selectedEntries[entry.importKey] then
            local spellInfo = C_Spell.GetSpellInfo(entry.id)
            if spellInfo and spellInfo.name then
                local isPassive = IsPassiveOrProc(entry.id) and true or nil
                CooldownCompanion:AddButtonToGroup(groupID, "spell", entry.id, spellInfo.name, nil, isPassive, true)
                addedAuras = addedAuras + 1
            else
                applySkipped = applySkipped + 1
            end
        end
    end

    for _, entry in ipairs(preview.items) do
        if selectedEntries[entry.importKey] then
            if C_Item.GetItemSpell(entry.id) then
                local itemName = C_Item.GetItemNameByID(entry.id) or entry.name or ("Item " .. entry.id)
                CooldownCompanion:AddButtonToGroup(groupID, "item", entry.id, itemName)
                addedItems = addedItems + 1
            else
                applySkipped = applySkipped + 1
            end
        end
    end

    if not suppressRefresh then
        CooldownCompanion:RefreshConfigPanel()
    end
    local totalAdded = addedSpells + addedAuras + addedItems
    CooldownCompanion:Print(
        "Auto Add complete: "
        .. totalAdded .. " added ("
        .. addedSpells .. " spells, "
        .. addedAuras .. " auras, "
        .. addedItems .. " items). "
        .. applySkipped .. " skipped during apply."
    )
    return true
end

local function CountSelectedBars(selectedBars)
    local count = 0
    for i = 1, ACTION_BAR_COUNT do
        if selectedBars and selectedBars[i] then
            count = count + 1
        end
    end
    return count
end

local function CancelAutoAddFlow()
    CS.autoAddFlowActive = false
    CS.autoAddFlowState = nil
end

local function NormalizeFlowState(state)
    state.source = NormalizeSource(state.source)
    state.step = tonumber(state.step) or AUTO_ADD_STEP_SOURCE
    if state.step < AUTO_ADD_STEP_SOURCE or state.step > AUTO_ADD_STEP_REVIEW then
        state.step = AUTO_ADD_STEP_SOURCE
    end
    if state.source ~= SOURCE_ACTION_BARS and state.step == AUTO_ADD_STEP_OPTIONS then
        state.step = AUTO_ADD_STEP_REVIEW
    end
    state.selectedBars = NormalizeBarSelection(state.selectedBars or CreateDefaultBarSelection())
    state.selectedEntries = state.selectedEntries or {}
    state.hasInteractedStep2 = state.hasInteractedStep2 == true
    state.showSkipped = state.showSkipped == true
    state.showSources = true
    state.sortMode = SORT_SOURCE_THEN_NAME
end

local function GetActiveFlowState()
    if not CS.autoAddFlowActive then return nil end
    local state = CS.autoAddFlowState
    if not state then return nil end
    NormalizeFlowState(state)

    local group = state.groupID and CooldownCompanion.db.profile.groups[state.groupID]
    if not group or CS.selectedGroup ~= state.groupID or next(CS.selectedGroups) then
        CancelAutoAddFlow()
        return nil
    end
    return state
end

local function BuildPreviewForFlowState(state)
    local preview
    if state.source == SOURCE_ACTION_BARS then
        preview = BuildActionBarPreview(state.selectedBars)
    elseif state.source == SOURCE_SPELLBOOK then
        preview = BuildSpellbookPreview()
    else
        preview = BuildCDMAuraPreview()
    end
    SortPreview(preview, state.sortMode)
    state.preview = preview
    NormalizeSelectionState(preview, state.selectedEntries)
    return preview
end

local function RefreshFlowUI()
    CooldownCompanion:RefreshConfigPanel()
end

local function AdvanceToReview(state)
    state.step = AUTO_ADD_STEP_REVIEW
    state.selectedEntries = {}
    state.preview = nil
end

local function RenderStep1(container, state)
    local heading = AceGUI:Create("Heading")
    heading:SetText("Step 1: Choose Source")
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local sourceRow = AceGUI:Create("SimpleGroup")
    sourceRow:SetFullWidth(true)
    sourceRow:SetLayout("Flow")

    local function SetSourceAndAdvance(source)
        state.source = NormalizeSource(source)
        state.selectedEntries = {}
        state.preview = nil
        state.hasInteractedStep2 = false
        if state.source == SOURCE_ACTION_BARS then
            state.step = AUTO_ADD_STEP_OPTIONS
        else
            AdvanceToReview(state)
        end
        PersistAutoAddPrefs(state)
        RefreshFlowUI()
    end

    local actionBtn = AceGUI:Create("Button")
    actionBtn:SetText("Action Bars")
    actionBtn:SetRelativeWidth(0.33)
    actionBtn:SetCallback("OnClick", function()
        SetSourceAndAdvance(SOURCE_ACTION_BARS)
    end)
    sourceRow:AddChild(actionBtn)

    local spellbookBtn = AceGUI:Create("Button")
    spellbookBtn:SetText("Spellbook")
    spellbookBtn:SetRelativeWidth(0.33)
    spellbookBtn:SetCallback("OnClick", function()
        SetSourceAndAdvance(SOURCE_SPELLBOOK)
    end)
    sourceRow:AddChild(spellbookBtn)

    local cdmBtn = AceGUI:Create("Button")
    cdmBtn:SetText("CDM Auras")
    cdmBtn:SetRelativeWidth(0.33)
    cdmBtn:SetCallback("OnClick", function()
        SetSourceAndAdvance(SOURCE_CDM_AURAS)
    end)
    sourceRow:AddChild(cdmBtn)

    container:AddChild(sourceRow)

    local hint = AceGUI:Create("Label")
    hint:SetText("Select a source to continue.")
    hint:SetFullWidth(true)
    container:AddChild(hint)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetFullWidth(true)
    cancelBtn:SetCallback("OnClick", function()
        CancelAutoAddFlow()
        RefreshFlowUI()
    end)
    container:AddChild(cancelBtn)
end

local function RenderStep2(container, state)
    local heading = AceGUI:Create("Heading")
    heading:SetText("Step 2: Choose Action Bars")
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local info = AceGUI:Create("Label")
    info:SetText("Adjust bars to import. First valid change advances automatically.")
    info:SetFullWidth(true)
    container:AddChild(info)

    local function HandleStep2Interaction()
        state.hasInteractedStep2 = true
        PersistAutoAddPrefs(state)
        if CountSelectedBars(state.selectedBars) > 0 then
            AdvanceToReview(state)
        end
        RefreshFlowUI()
    end

    local barsRow = AceGUI:Create("SimpleGroup")
    barsRow:SetFullWidth(true)
    barsRow:SetLayout("Flow")
    for barIndex = 1, ACTION_BAR_COUNT do
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel("Bar " .. barIndex)
        cb:SetWidth(65)
        cb:SetValue(state.selectedBars[barIndex] == true)
        cb:SetCallback("OnValueChanged", function(_, _, value)
            state.selectedBars[barIndex] = value and true or false
            HandleStep2Interaction()
        end)
        barsRow:AddChild(cb)
    end
    container:AddChild(barsRow)

    local actionsRow = AceGUI:Create("SimpleGroup")
    actionsRow:SetFullWidth(true)
    actionsRow:SetLayout("Flow")

    local allBtn = AceGUI:Create("Button")
    allBtn:SetText("All")
    allBtn:SetRelativeWidth(0.5)
    allBtn:SetCallback("OnClick", function()
        for i = 1, ACTION_BAR_COUNT do
            state.selectedBars[i] = true
        end
        HandleStep2Interaction()
    end)
    actionsRow:AddChild(allBtn)

    local noneBtn = AceGUI:Create("Button")
    noneBtn:SetText("None")
    noneBtn:SetRelativeWidth(0.5)
    noneBtn:SetCallback("OnClick", function()
        for i = 1, ACTION_BAR_COUNT do
            state.selectedBars[i] = false
        end
        HandleStep2Interaction()
    end)
    actionsRow:AddChild(noneBtn)

    container:AddChild(actionsRow)

    if CountSelectedBars(state.selectedBars) == 0 then
        local warn = AceGUI:Create("Label")
        warn:SetText("|cffff5555Select at least one bar to continue.|r")
        warn:SetFullWidth(true)
        container:AddChild(warn)
    end

    local navRow = AceGUI:Create("SimpleGroup")
    navRow:SetFullWidth(true)
    navRow:SetLayout("Flow")

    local backBtn = AceGUI:Create("Button")
    backBtn:SetText("Back")
    backBtn:SetRelativeWidth(0.5)
    backBtn:SetCallback("OnClick", function()
        state.step = AUTO_ADD_STEP_SOURCE
        RefreshFlowUI()
    end)
    navRow:AddChild(backBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetRelativeWidth(0.5)
    cancelBtn:SetCallback("OnClick", function()
        CancelAutoAddFlow()
        RefreshFlowUI()
    end)
    navRow:AddChild(cancelBtn)

    container:AddChild(navRow)
end

local function RenderStep3(container, state)
    local heading = AceGUI:Create("Heading")
    heading:SetText("Step 3: Review and Confirm")
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local preview = BuildPreviewForFlowState(state)
    local spellCount, auraCount, itemCount, totalCount = CountPreviewEntries(preview)
    local selectedSpellCount, selectedAuraCount, selectedItemCount, selectedTotalCount =
        CountSelectedEntries(preview, state.selectedEntries)

    local summary1 = AceGUI:Create("Label")
    if totalCount > 0 then
        summary1:SetText("Selected " .. selectedTotalCount .. " of " .. totalCount .. " addable entries.")
    else
        summary1:SetText("No addable entries found for this source.")
    end
    summary1:SetFullWidth(true)
    container:AddChild(summary1)

    local summary2 = AceGUI:Create("Label")
    summary2:SetText(
        "Spells " .. selectedSpellCount .. "/" .. spellCount
        .. " | Auras " .. selectedAuraCount .. "/" .. auraCount
        .. " | Items " .. selectedItemCount .. "/" .. itemCount
    )
    summary2:SetFullWidth(true)
    container:AddChild(summary2)

    local selectRow = AceGUI:Create("SimpleGroup")
    selectRow:SetFullWidth(true)
    selectRow:SetLayout("Flow")

    local selectAllBtn = AceGUI:Create("Button")
    selectAllBtn:SetText("Select All")
    selectAllBtn:SetRelativeWidth(0.5)
    selectAllBtn:SetCallback("OnClick", function()
        SetAllEntriesSelected(preview, state.selectedEntries, true)
        RefreshFlowUI()
    end)
    selectRow:AddChild(selectAllBtn)

    local selectNoneBtn = AceGUI:Create("Button")
    selectNoneBtn:SetText("Select None")
    selectNoneBtn:SetRelativeWidth(0.5)
    selectNoneBtn:SetCallback("OnClick", function()
        SetAllEntriesSelected(preview, state.selectedEntries, false)
        RefreshFlowUI()
    end)
    selectRow:AddChild(selectNoneBtn)

    container:AddChild(selectRow)

    if spellCount > 0 then
        AddSectionHeading(container, "Spells (" .. spellCount .. ")")
        for _, entry in ipairs(preview.spells) do
            AddSelectableEntryRow(state, container, entry, RefreshFlowUI)
        end
    end

    if auraCount > 0 then
        AddSectionHeading(container, "Auras (" .. auraCount .. ")")
        for _, entry in ipairs(preview.auras) do
            AddSelectableEntryRow(state, container, entry, RefreshFlowUI)
        end
    end

    if itemCount > 0 then
        AddSectionHeading(container, "Items (" .. itemCount .. ")")
        for _, entry in ipairs(preview.items) do
            AddSelectableEntryRow(state, container, entry, RefreshFlowUI)
        end
    end

    if totalCount == 0 then
        AddEmptyRow(container, "No entries are currently addable from this source.")
    end

    if #preview.skipped > 0 then
        local showSkippedCb = AceGUI:Create("CheckBox")
        showSkippedCb:SetLabel("Show Skipped Details (" .. #preview.skipped .. ")")
        showSkippedCb:SetValue(state.showSkipped == true)
        showSkippedCb:SetFullWidth(true)
        showSkippedCb:SetCallback("OnValueChanged", function(_, _, value)
            state.showSkipped = value and true or false
            PersistAutoAddPrefs(state)
            RefreshFlowUI()
        end)
        container:AddChild(showSkippedCb)

        if state.showSkipped then
            AddSectionHeading(container, "Skipped")
            for _, skipped in ipairs(preview.skipped) do
                AddSkippedRow(state, container, skipped)
            end
        end
    end

    local navRow = AceGUI:Create("SimpleGroup")
    navRow:SetFullWidth(true)
    navRow:SetLayout("Flow")

    local backBtn = AceGUI:Create("Button")
    backBtn:SetText("Back")
    backBtn:SetRelativeWidth(0.33)
    backBtn:SetCallback("OnClick", function()
        if state.source == SOURCE_ACTION_BARS then
            state.step = AUTO_ADD_STEP_OPTIONS
        else
            state.step = AUTO_ADD_STEP_SOURCE
        end
        RefreshFlowUI()
    end)
    navRow:AddChild(backBtn)

    local cancelBtn = AceGUI:Create("Button")
    cancelBtn:SetText("Cancel")
    cancelBtn:SetRelativeWidth(0.33)
    cancelBtn:SetCallback("OnClick", function()
        PersistAutoAddPrefs(state)
        CancelAutoAddFlow()
        RefreshFlowUI()
    end)
    navRow:AddChild(cancelBtn)

    local confirmBtn = AceGUI:Create("Button")
    confirmBtn:SetText("Add Selected")
    confirmBtn:SetRelativeWidth(0.34)
    confirmBtn:SetCallback("OnClick", function()
        local _, _, _, selectedCount = CountSelectedEntries(preview, state.selectedEntries)
        if selectedCount == 0 then
            CooldownCompanion:Print("No selected entries to add from this preview.")
            return
        end

        if ApplyPreviewToGroup(state.groupID, preview, state.selectedEntries, true) then
            PersistAutoAddPrefs(state)
            CancelAutoAddFlow()
            RefreshFlowUI()
        end
    end)
    navRow:AddChild(confirmBtn)

    container:AddChild(navRow)
end

local function RenderAutoAddFlow(container)
    if not container then return end
    local state = GetActiveFlowState()
    if not state then return end

    container:ReleaseChildren()
    if state.step == AUTO_ADD_STEP_SOURCE then
        RenderStep1(container, state)
    elseif state.step == AUTO_ADD_STEP_OPTIONS then
        RenderStep2(container, state)
    else
        RenderStep3(container, state)
    end
end

local function OpenAutoAddFlow()
    local groupID = CS.selectedGroup
    if not groupID or not CooldownCompanion.db.profile.groups[groupID] then
        CooldownCompanion:Print("Select a group first.")
        return
    end

    local prefs = EnsureAutoAddPrefs()
    CS.autoAddFlowActive = true
    CS.autoAddFlowState = {
        groupID = groupID,
        step = AUTO_ADD_STEP_SOURCE,
        source = NormalizeSource(prefs.lastSource),
        selectedBars = NormalizeBarSelection(prefs.selectedBars),
        selectedEntries = {},
        preview = nil,
        hasInteractedStep2 = false,
        showSkipped = prefs.showSkipped == true,
        showSources = true,
        sortMode = SORT_SOURCE_THEN_NAME,
    }
    RefreshFlowUI()
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._OpenAutoAddFlow = OpenAutoAddFlow
ST._RenderAutoAddFlow = RenderAutoAddFlow
ST._CancelAutoAddFlow = CancelAutoAddFlow
