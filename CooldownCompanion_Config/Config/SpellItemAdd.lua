--[[
    CooldownCompanion - Config/SpellItemAdd
    Spell/item addition + autocomplete system.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Imports from earlier Config/ files
local ResolveCDMAuraSpellID = ST.ResolveCDMAuraSpellID
local ResolveCDMAppliedAuraSpellID = ST.ResolveCDMAppliedAuraSpellID
local IsPassiveOrProc = ST._IsPassiveOrProc
local IsPassiveCooldownSpell = ST.IsPassiveCooldownSpell
local IsNeverTrackableSpell = ST._IsNeverTrackableSpell
local ShouldSuppressSpellbookEntry = ST._ShouldSuppressSpellbookEntry
local NotifyTutorialAction = ST._NotifyTutorialAction
local SelectConfigPanel = ST._SelectConfigPanel
local SelectConfigButton = ST._SelectConfigButton

-- After a successful add, set selection state to the new button so the
-- next RefreshConfigPanel shows its settings in the editing workspace.
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
    -- scope: an entry that was just added is a named destination, so its own
    -- Settings tab wins over whatever panel tab happened to be open.
    SelectConfigButton(panelId, buttonIndex, { force = true, scope = "detail" })
end

local function GetTargetGroup(groupId)
    groupId = groupId or CS.addingToPanelId or CS.selectedGroup
    return groupId and CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[groupId]
end

local function IsTriggerPanelTarget(groupId)
    local group = GetTargetGroup(groupId)
    return group and group.displayMode == "trigger"
end

local function TargetPanelAcceptsAuraEntries(groupId)
    local group = GetTargetGroup(groupId)
    local displayMode = group and (group.displayMode or "icons")
    return displayMode == "icons" or displayMode == "bars" or displayMode == "textures"
        or displayMode == "text"
end

-- An Aura Panel takes aura entries only, and only for the one unit it derived
-- from its first entry. Both answers come from Core so this surface cannot
-- drift from the rule the move paths and AddButtonToGroup enforce.
local function TargetPanelIsAuraOnly(groupId)
    return CooldownCompanion:IsAuraPanel(GetTargetGroup(groupId)) == true
end

local function GetTargetAuraPanelUnit(groupId)
    return CooldownCompanion:GetAuraPanelUnit(GetTargetGroup(groupId))
end

-- Nothing an Aura Panel can hold, in the shape the central predicate reads.
-- Shared rather than rebuilt per call: the predicate only ever reads it.
local AURA_PANEL_ITEM_PROBE = { type = "item" }

-- Prints the one central reject line and answers "stop here" when a non-aura
-- add is pointed at an Aura Panel. Answering at the surface keeps the message
-- to a single line: the core add paths print their own notices, and an item
-- add would otherwise announce an async load before refusing.
local function RejectNonAuraPanelAdd(groupId, probe)
    local group = GetTargetGroup(groupId)
    if not CooldownCompanion:IsAuraPanel(group) then
        return false
    end
    local rejectMessage = CooldownCompanion:GetPanelManualEntryRejectMessage(group, probe)
    if not rejectMessage then
        return false
    end
    CooldownCompanion:Print(rejectMessage)
    return true
end

-- File-local state
local autocompleteDropdown
local canPlayerEverCastSpellMemoByCache = setmetatable({}, { __mode = "k" })
-- Same shape, same reason: keyed on the autocomplete cache table so a rebuilt
-- cache (SPELLS_CHANGED - spec and talent changes) starts from a clean memo, and
-- the discarded one is collectable. Aura polarity is resolved through the CDM
-- and buff-viewer frames, which are spec-dependent, so it is NOT static for the
-- session and must not outlive the cache it was resolved against.
local auraUnitMemoByCache = setmetatable({}, { __mode = "k" })

local function CanPlayerEverCastSpellCached(spellId)
    local cache = CS.autocompleteCache
    if not cache then
        return CooldownCompanion:CanPlayerEverCastSpell(spellId)
    end

    local memo = canPlayerEverCastSpellMemoByCache[cache]
    if not memo then
        memo = {}
        canPlayerEverCastSpellMemoByCache[cache] = memo
    end
    local canCast = memo[spellId]
    if canCast == nil then
        canCast = CooldownCompanion:CanPlayerEverCastSpell(spellId) and true or false
        memo[spellId] = canCast
    end
    return canCast
end

-- Autocomplete constants
local AUTOCOMPLETE_MAX_ROWS = 8
local AUTOCOMPLETE_ROW_HEIGHT = 22
local AUTOCOMPLETE_ICON_SIZE = 16
local AUTOCOMPLETE_TYPE_BADGE_SIZE = 13
local AUTOCOMPLETE_TYPE_LABEL_WIDTH = 68
local AUTOCOMPLETE_TYPE_RIGHT_PAD = 6
local AUTOCOMPLETE_TYPE_GAP = 4

-- Player-owned auras applied indirectly by a passive can lack their own
-- spellbook or Cooldown Manager suggestion row.
local INDIRECT_AURA_AUTOCOMPLETE = {
    { ownerSpellID = 1246769, auraSpellID = 1221389 }, -- Shatter -> Freezing
}

local function IsHeatingUpHotStreakRow(cooldownInfo)
    local hasHeatingUp, hasHotStreak
    for _, linkedID in ipairs(cooldownInfo and cooldownInfo.linkedSpellIDs or {}) do
        if linkedID == 48107 then
            hasHeatingUp = true
        elseif linkedID == 48108 then
            hasHotStreak = true
        end
    end
    return hasHeatingUp and hasHotStreak
end

local ADD_BOX_TRACKABILITY_TOOLTIP = {
    "What Can Be Tracked",
    {"Spells: anything your class can cast or learn. Tracks cooldowns and charges.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Auras: anything that can appear as a buff on you, including other players' buffs, trinket procs, and encounter effects. Your own damage-over-time effects are tracked on your target.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Suggestions only offer what can actually work. An aura that isn't suggested can still be added by typing its spell ID.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Debuffs that enemies put on you can't be tracked; the game hides those from addons.", 1, 1, 1, true},
}

-- Prepended to the tooltip above while the add box points at an Aura Panel, so
-- the panel's one rule leads what the box says it will take. Read at hover time
-- rather than baked in: one info button serves whichever panel is selected.
local ADD_BOX_AURA_PANEL_TOOLTIP = {
    {"This panel takes aura entries only, for one unit.", 1, 0.82, 0.2, true},
    {" ", 1, 1, 1, true},
}

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

local function CreateAddBoxInfoButton(parentFrame, anchorFrame, cleanup, customBar)
    local btn = parentFrame._cdcAddBoxInfoButton
    if not btn then
        btn = CreateFrame("Button", nil, parentFrame)
        btn:SetSize(16, 16)
        local icon = btn:CreateTexture(nil, "OVERLAY")
        icon:SetSize(12, 12)
        icon:SetPoint("CENTER")
        icon:SetAtlas("QuestRepeatableTurnin")
        btn:SetScript("OnEnter", function(self)
            GameTooltip:SetMinimumWidth(0)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ADD_BOX_TRACKABILITY_TOOLTIP[1])
            if self._cdcCustomBarAdd then
                GameTooltip:AddLine("Add a spell or aura to Resources as a Custom Bar.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
            end
            -- The workspace add box always targets the SELECTED panel (its
            -- submit path clears any stale inline-add target), so the panel
            -- rule is asked of that panel and no other.
            local auraLines = not self._cdcCustomBarAdd and TargetPanelIsAuraOnly(CS.selectedGroup)
                and ADD_BOX_AURA_PANEL_TOOLTIP or nil
            for _, line in ipairs(auraLines or {}) do
                GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5])
            end
            for index = 2, #ADD_BOX_TRACKABILITY_TOOLTIP do
                local line = ADD_BOX_TRACKABILITY_TOOLTIP[index]
                if type(line) == "table" then
                    GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5])
                else
                    GameTooltip:AddLine(line)
                end
            end
            GameTooltip:SetMinimumWidth(270)
            GameTooltip:Show()
        end)
        btn:SetScript("OnLeave", function()
            GameTooltip:SetMinimumWidth(0)
            GameTooltip:Hide()
        end)
        parentFrame._cdcAddBoxInfoButton = btn
    end

    btn._cdcCustomBarAdd = customBar == true
    btn:SetParent(parentFrame)
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", anchorFrame, "RIGHT", -1, 0)
    btn:Show()

    if cleanup and cleanup.SetCallback then
        local prevOnRelease = cleanup.events and cleanup.events["OnRelease"]
        cleanup:SetCallback("OnRelease", function(widget)
            if prevOnRelease then
                prevOnRelease(widget, "OnRelease")
            end
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
            if widget.editbox then
                widget.editbox:SetPoint("BOTTOMRIGHT")
            end
        end)
    end
    return btn
end

local function IsBlockedSpellForTracking(spellId)
    return spellId and IsNeverTrackableSpell(spellId)
end

local function ResolveNonBlockedSpellInput(input, skipTalentSearch)
    if not input or input == "" then return nil end

    local spellId = tonumber(input)
    local spellInfo
    local spellName

    if spellId then
        spellInfo = C_Spell.GetSpellInfo(spellId)
        spellName = spellInfo and spellInfo.name
    else
        spellInfo = C_Spell.GetSpellInfo(input)
        if spellInfo then
            spellId = spellInfo.spellID
            spellName = spellInfo.name
        elseif not skipTalentSearch then
            spellId, spellName = CooldownCompanion:FindTalentSpellByName(input)
            spellInfo = spellId and C_Spell.GetSpellInfo(spellId)
        end
    end

    if not spellId or not spellName or IsBlockedSpellForTracking(spellId) then
        return nil
    end
    return spellId, spellName, spellInfo
end

local function PrintBlockedSpellMessage(spellName)
    local shownName = spellName or "that spell"
    CooldownCompanion:Print("Cannot track " .. shownName .. ".")
end

local function PrintCannotTrackAsAura(spellName)
    CooldownCompanion:Print("Cannot track " .. spellName .. " as an aura.")
end

local function PrintAuraPanelUnsupported()
    CooldownCompanion:Print("Use an icon, bar or text panel for Aura tracking.")
end

local function IsExactNumericSpellInput(input, spellId)
    local exactID = input and input:match("^%s*(%d+)%s*$")
    return exactID and tonumber(exactID) == spellId or false
end

local function GetSpellOfferability(input, spellId)
    local canEverCast = CanPlayerEverCastSpellCached(spellId)
    local isHarmful = CooldownCompanion.ClassifyAuraSpellUnit(spellId) == "target"
    local canOfferSpell = canEverCast and not IsPassiveOrProc(spellId)
    -- Exact numeric entry is explicit Aura intent. Some player-applied
    -- harmful auras (for example, passive/proc effects) are not themselves
    -- castable spells; runtime target tracking still filters to PLAYER auras.
    local canOfferAura = not isHarmful
        or IsExactNumericSpellInput(input, spellId)
    return canOfferSpell, canOfferAura
end

------------------------------------------------------------------------
-- Helper: Add spell to selected group
------------------------------------------------------------------------
-- opts.section (cursor drops only): the section anchor the new entry lands
-- in. A drop near one of the Live Preview's section landings, or onto a
-- section's own cluster, adds the entry AND places it, and the anchor rides into
-- AddButtonToGroup as its last argument: Core assigns the section ahead of
-- its own keeper pass and refresh, so the entry is drawn in place the first
-- time instead of landing in the base grid and moving. Core judges the anchor
-- against the panel as it is THEN rather than at the drop (an item add can
-- finish later, from its load callback).
-- The add's routing for a spell, decided ONCE and read by two callers: the
-- add itself (TryAddSpell) and the Live Preview ghost that promises it
-- (CS.ResolveProspectiveAdd). What the entry will be born as, or why the add
-- will refuse it, so the ghost can never show a landing the add will not
-- make, nor a cooldown look for an entry the add turns into an aura.
-- Returns the route (one reused table: addAsAura, forceAura, routedToAura)
-- or nil plus a reason ("blocked", "target-aura", "aura-unsupported",
-- "aura-panel") and, for the last, the panel's own reject line.
local spellAddRoute = {}
local function ResolveSpellAddRoute(spellId, spellName, forceAura, groupId)
    if IsBlockedSpellForTracking(spellId) then
        return nil, "blocked"
    end
    -- An Aura Panel holds aura entries only, so a spell arriving here is
    -- aura intent by destination: route it rather than refuse it for the
    -- shape it was typed in. This also takes the castability branch below
    -- out of play, which would otherwise announce the routing twice.
    local isAuraOnlyTarget = TargetPanelIsAuraOnly(groupId)
    if isAuraOnlyTarget then
        forceAura = true
    end
    -- 12.1: passives/procs add directly as aura-tracking entries -- the new
    -- AuraContainer backend needs no Cooldown Manager setup. forceAura=true
    -- comes from "Aura" autocomplete suggestions (tracked buff/bar rows).
    local addAsAura = forceAura == true or IsPassiveOrProc(spellId)
    local routedToAura
    if not addAsAura and not CanPlayerEverCastSpellCached(spellId) then
        if CooldownCompanion.ClassifyAuraSpellUnit(spellId) == "target" then
            return nil, "target-aura"
        end
        addAsAura = true
        forceAura = true
        routedToAura = true
    end
    -- AuraDisplay binds primary Aura entries in icon, bar, and Texture
    -- panels; refuse aura adds elsewhere instead of creating a dead entry.
    if addAsAura and not TargetPanelAcceptsAuraEntries(groupId) then
        return nil, "aura-unsupported"
    end
    -- An Aura Panel also judges WHICH aura, against its derived unit. Asked
    -- here, before the add, so the refusal is the only thing printed:
    -- AddButtonToGroup can emit a transform notice on its way to the same
    -- verdict, which would put a stray line ahead of the reject.
    if isAuraOnlyTarget then
        local probe = {
            type = "spell",
            id = spellId,
            name = spellName,
            addedAs = "aura",
        }
        probe.auraUnit = CooldownCompanion:ResolveStandaloneAuraDefaultUnit(probe)
        local rejectMessage = CooldownCompanion:GetPanelManualEntryRejectMessage(
            GetTargetGroup(groupId), probe)
        if rejectMessage then
            return nil, "aura-panel", rejectMessage
        end
    end
    local route = spellAddRoute
    route.addAsAura = addAsAura or nil
    route.forceAura = forceAura
    route.routedToAura = routedToAura
    return route
end

--- The ghost's half of that decision: fill `stub` (type, id, name,
--- isPetSpell, forceAura) with what the entry will be born as, in the
--- fields AddButtonToGroup stamps (isPassive, addedAs,
--- hideWhileAuraNotActive), or answer false when the add would refuse it.
--- Items are refused where TryAddItem refuses them: an Aura Panel, or an
--- item with no usable effect (judged only once its data is cached).
function CS.ResolveProspectiveAdd(stub, groupId)
    groupId = groupId or CS.selectedGroup
    local group = GetTargetGroup(groupId)
    if not group then return false end
    if stub.type == "item" then
        if CooldownCompanion:IsAuraPanel(group)
            and CooldownCompanion:GetPanelManualEntryRejectMessage(group, AURA_PANEL_ITEM_PROBE) then
            return false
        end
        local itemId = tonumber(stub.id)
        if itemId and C_Item.IsItemDataCachedByID(itemId) and not C_Item.GetItemSpell(itemId) then
            return false
        end
        return true
    end
    if stub.type ~= "spell" then return true end
    local spellId = tonumber(stub.id)
    if not spellId then return true end
    local route = ResolveSpellAddRoute(spellId, stub.name, stub.forceAura, groupId)
    if not route then return false end
    stub.isPassive = route.addAsAura
    if route.forceAura == true or (stub.isPassive and route.forceAura ~= false) then
        stub.addedAs = "aura"
        local displayMode = group.displayMode or "icons"
        if route.forceAura == true and (displayMode == "icons" or displayMode == "bars") then
            stub.hideWhileAuraNotActive = true
        end
    else
        stub.addedAs = "spell"
    end
    return true
end

local function TryAddSpell(input, isPetSpell, forceAura, opts)
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
        local route, reason, detail = ResolveSpellAddRoute(spellId, spellName, forceAura,
            CS.selectedGroup)
        if not route then
            if reason == "blocked" then
                PrintBlockedSpellMessage(spellName)
            elseif reason == "target-aura" then
                PrintCannotTrackAsAura(spellName)
            elseif reason == "aura-unsupported" then
                PrintAuraPanelUnsupported()
            elseif detail then
                CooldownCompanion:Print(detail)
            end
            return false
        end
        local addAsAura, routedToAura = route.addAsAura, route.routedToAura
        forceAura = route.forceAura
        local idx, notified = CooldownCompanion:AddButtonToGroup(CS.selectedGroup, "spell", spellId, spellName,
            isPetSpell, addAsAura or nil, forceAura, nil, nil, opts and opts.section)
        if not idx then
            return false
        end
        SelectNewButton(CS.selectedGroup, idx)
        if routedToAura then
            CooldownCompanion:Print("You can't cast " .. spellName .. ", so it's tracked as a buff on you.")
        elseif not notified then
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
-- `section` (cursor drops only): the anchor the new entry lands in, handed
-- to AddButtonToGroup exactly as TryAddSpell hands its own.
local function FinalizeAddItem(itemId, groupId, autoSelect, section)
    local itemName = C_Item.GetItemNameByID(itemId) or "Unknown Item"
    local spellName = C_Item.GetItemSpell(itemId)
    if not spellName then
        CooldownCompanion:Print("Item has no usable effect: " .. itemName)
        return false
    end
    local idx = CooldownCompanion:AddButtonToGroup(groupId, "item", itemId, itemName,
        nil, nil, nil, nil, nil, section)
    if not idx then
        return false
    end
    if autoSelect ~= false then
        SelectNewButton(groupId, idx)
    end
    CooldownCompanion:Print("Added item: " .. itemName)
    return true
end

local function TryAddItem(input, opts)
    if input == "" or not CS.selectedGroup then return false end
    if RejectNonAuraPanelAdd(CS.selectedGroup, AURA_PANEL_ITEM_PROBE) then return false end
    local section = opts and opts.section

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
        return FinalizeAddItem(itemId, CS.selectedGroup, nil, section)
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
        -- The section rides the closure like the group does: the drop named a
        -- place in THAT panel, and the entry lands there whether or not the
        -- selection has moved on since.
        if FinalizeAddItem(itemId, capturedGroup, stillOnGroup, section) then
            if ST._ClearWideAddBoxAfterAdd then
                ST._ClearWideAddBoxAfterAdd(input)
            end
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
    if RejectNonAuraPanelAdd(CS.selectedGroup, slotData) then return false end

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

    -- An Aura Panel takes aura entries only, so this resolver narrows to the
    -- spell door: every spell hand-off goes through TryAddSpell, which owns the
    -- aura routing and the reject, and the item doors refuse before they start.
    local isAuraOnlyTarget = TargetPanelIsAuraOnly(CS.selectedGroup)

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
            if isAuraOnlyTarget or not CanPlayerEverCastSpellCached(id) then
                return TryAddSpell(tostring(id))
            end
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
        if RejectNonAuraPanelAdd(CS.selectedGroup, AURA_PANEL_ITEM_PROBE) then return false end
        local itemName = C_Item.GetItemNameByID(id)
        local itemId = C_Item.GetItemIDForItemInfo(id)
        if itemId then
            if C_Item.IsItemDataCachedByID(itemId) then
                local result = FinalizeAddItem(itemId, CS.selectedGroup)
                if result then return true end
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
                    CooldownCompanion:Print("Not found: " .. input)
                    return
                end
                -- Skip auto-select if the user navigated away during async load
                local stillOnGroup = CS.selectedGroup == capturedGroup
                if FinalizeAddItem(itemId, capturedGroup, stillOnGroup) then
                    if ST._ClearWideAddBoxAfterAdd then
                        ST._ClearWideAddBoxAfterAdd(input)
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end
            end)
            return false
        end

        -- No item match
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
                if isAuraOnlyTarget or not CanPlayerEverCastSpellCached(spellId) then
                    return TryAddSpell(tostring(spellId))
                end
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
        if RejectNonAuraPanelAdd(CS.selectedGroup, AURA_PANEL_ITEM_PROBE) then return false end
        local itemId = C_Item.GetItemIDForItemInfo(input)
        if itemId and C_Item.IsItemDataCachedByID(itemId) then
            return FinalizeAddItem(itemId, CS.selectedGroup)
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
-- opts.section (the Live Preview's drop overlay): the section anchor the new
-- entry is placed in. Every other caller passes nothing and gets the plain add.
local function TryReceiveCursorDrop(opts)
    local cursorType, cursorID, _, cursorSpellID = GetCursorInfo()
    if not cursorType then return false end

    if not CS.selectedGroup then
        CooldownCompanion:Print("Select a group first before dropping spells or items.")
        ClearCursor()
        return false
    end

    local added = false
    if cursorType == "spell" and cursorSpellID then
        added = TryAddSpell(tostring(cursorSpellID), nil, nil, opts)
    elseif cursorType == "petaction" and cursorID then
        added = TryAddSpell(tostring(cursorID), true, nil, opts)
    elseif cursorType == "item" and cursorID then
        added = TryAddItem(tostring(cursorID), opts)
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
    -- Heating Up and Hot Streak share one legacy multi-stage row, but are
    -- offered as independent auras now that runtime tracking uses AuraContainer.
    --
    -- trackedAuraID is the spellID the APPLIED aura carries (shared rule:
    -- ST.ResolveCDMAppliedAuraSpellID, SpellQueries.lua). Unambiguous applied
    -- auras keep the row identity and expand to trackedAuraID at bind time.
    -- The Fire Mage pair stores each aura identity directly so selecting one
    -- can never inherit its sibling.
    local seenAuras = {}
    local auraRows = {}
    for _, cat in ipairs({ Enum.CooldownViewerCategory.TrackedBuff, Enum.CooldownViewerCategory.TrackedBar }) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local cdInfo = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                local id = cdInfo and cdInfo.spellID and ResolveCDMAuraSpellID(cdInfo)
                if id and IsHeatingUpHotStreakRow(cdInfo) then
                    local linkedSeen = {}
                    for _, linkedID in ipairs(cdInfo.linkedSpellIDs or {}) do
                        local numericLinkedID = tonumber(linkedID)
                        if numericLinkedID
                            and (numericLinkedID == 48107 or numericLinkedID == 48108)
                            and not linkedSeen[numericLinkedID] then
                            linkedSeen[numericLinkedID] = true
                            local linkedInfo = not seenAuras[numericLinkedID]
                                and not IsNeverTrackableSpell(numericLinkedID)
                                and C_Spell.GetSpellInfo(numericLinkedID)
                            if linkedInfo and linkedInfo.name then
                                seenAuras[numericLinkedID] = true
                                local searchLower = linkedInfo.name:lower()
                                    .. " " .. numericLinkedID
                                table.insert(cache, {
                                    id = numericLinkedID,
                                    trackedAuraID = numericLinkedID,
                                    name = linkedInfo.name,
                                    displayName = ("%s |cff999999(%d)|r"):format(
                                        linkedInfo.name, numericLinkedID),
                                    nameLower = linkedInfo.name:lower(),
                                    searchLower = searchLower,
                                    icon = linkedInfo.iconID or 134400,
                                    category = "Aura",
                                    autocompleteKind = "aura",
                                    isItem = false,
                                    forceAura = true,
                                })
                                auraRows[numericLinkedID] = true
                            end
                        end
                    end
                    id = nil
                end
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
                        -- Display the applied-aura identity (what actually
                        -- gets tracked); the stored row identity stays `id`
                        -- for pairing and candidate expansion. When the two
                        -- differ UNAMBIGUOUSLY (one linked aura), the visible
                        -- label carries the applied aura's name, and the
                        -- search key answers to the owner name, the applied
                        -- name, and the applied ID (Nature's Grace links
                        -- Dreamstate: both names and 450346 must find the
                        -- row). Multi-stage rows keep the row's own label —
                        -- naming one stage would misdescribe the row.
                        local trackedAuraID, ambiguousAura = ResolveCDMAppliedAuraSpellID(cdInfo, id)
                        local appliedName, searchLower
                        if trackedAuraID ~= id and not ambiguousAura then
                            local appliedInfo = C_Spell.GetSpellInfo(trackedAuraID)
                            appliedName = appliedInfo and appliedInfo.name
                            searchLower = spellInfo.name:lower()
                                .. (appliedName and (" " .. appliedName:lower()) or "")
                                .. " " .. trackedAuraID
                        end
                        local displayAuraID = (not ambiguousAura) and trackedAuraID or id
                        table.insert(cache, {
                            id = id,
                            trackedAuraID = trackedAuraID,
                            name = spellInfo.name,
                            displayName = ("%s |cff999999(%d)|r"):format(appliedName or spellInfo.name, displayAuraID),
                            nameLower = spellInfo.name:lower(),
                            searchLower = searchLower,
                            icon = spellInfo.iconID or 134400,
                            category = "Aura",
                            autocompleteKind = "aura",
                            isItem = false,
                            forceAura = true,
                        })
                        auraRows[id] = true
                    end
                end
            end
        end
    end

    for _, suggestion in ipairs(INDIRECT_AURA_AUTOCOMPLETE) do
        local auraID = suggestion.auraSpellID
        if not auraRows[auraID]
            and CanPlayerEverCastSpellCached(suggestion.ownerSpellID)
            and not IsNeverTrackableSpell(auraID) then
            local spellInfo = C_Spell.GetSpellInfo(auraID)
            if spellInfo and spellInfo.name then
                table.insert(cache, {
                    id = auraID,
                    trackedAuraID = auraID,
                    name = spellInfo.name,
                    displayName = ("%s |cff999999(%d)|r"):format(spellInfo.name, auraID),
                    nameLower = spellInfo.name:lower(),
                    icon = spellInfo.iconID or 134400,
                    category = "Aura",
                    autocompleteKind = "aura",
                    isItem = false,
                    forceAura = true,
                })
                auraRows[auraID] = true
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

local function CreateSynthesizedAuraRow(spellId, spellName, icon)
    return {
        id = spellId,
        name = spellName,
        displayName = ("%s |cff999999(%d)|r"):format(spellName, spellId),
        nameLower = spellName:lower(),
        icon = icon or 134400,
        category = "Aura",
        autocompleteKind = "aura",
        isItem = false,
        forceAura = true,
    }
end

-- The polarity the row will resolve to once it is an entry, answered by the SAME
-- resolver the add door asks: OnAutocompleteSelect adds `entry.id`, and TryAddSpell
-- probes it as { type = "spell", id = entry.id, addedAs = "aura" } through
-- ResolveStandaloneAuraDefaultUnit. That resolver walks GetBaseSpell, the CDM row
-- and its linkedSpellIDs to the APPLIED aura before asking polarity, which a raw
-- IsSpellHarmful on the row id does not: CDM rows carry CAST ids while the aura
-- they apply lives in linkedSpellIDs, and the two can disagree. Asking the raw id
-- here let the filter offer a row the panel then refused (and hide one it would
-- have taken).
--
-- Memoized because that walk is far more than one API call and this runs for
-- every cached row on every keystroke. Cost stays flat after the first pass.
local function ResolveAutocompleteAuraUnit(entry)
    local spellId = tonumber(entry.id) or tonumber(entry.trackedAuraID)
    if not spellId then return nil end

    local cache = CS.autocompleteCache
    local memo = cache and auraUnitMemoByCache[cache]
    if cache and not memo then
        memo = {}
        auraUnitMemoByCache[cache] = memo
    end

    -- `false` stands in for "unresolvable", so a nil answer is still a cache hit.
    local unit = memo and memo[spellId]
    if unit == nil then
        unit = CooldownCompanion:ResolveAuraEntryUnit({
            type = "spell",
            id = spellId,
            addedAs = "aura",
        }) or false
        if memo then
            memo[spellId] = unit
        end
    end
    return unit or nil
end

-- Would this row survive the panel's unit rule? Unknown polarity stays
-- PERMISSIVE, exactly as GetPanelManualEntryRejectMessage treats it: the
-- resolver answers nil when neither source can decide, and the add door lets
-- such an entry through rather than guessing, so the filter must not hide a row
-- the door would take. An Aura Panel with no unit yet (auraPanelUnit nil) takes
-- either polarity.
local function AutocompleteRowFitsAuraPanel(entry, auraPanelUnit)
    if not auraPanelUnit then return true end
    local rowUnit = ResolveAutocompleteAuraUnit(entry)
    return rowUnit == nil or rowUnit == auraPanelUnit
end

local function AddUniqueSpellAuraTwin(results, targetAcceptsAuraEntries)
    local uniqueSpell
    for _, entry in ipairs(results) do
        if entry.autocompleteKind == "spell" then
            if uniqueSpell then return end
            uniqueSpell = entry
        end
    end
    if not uniqueSpell or not targetAcceptsAuraEntries then return end

    local spellId = tonumber(uniqueSpell.id)
    if not spellId or CooldownCompanion.ClassifyAuraSpellUnit(spellId) == "target" then return end
    for _, entry in ipairs(results) do
        if entry.autocompleteKind == "aura" and tonumber(entry.id) == spellId then
            return
        end
    end

    while #results >= AUTOCOMPLETE_MAX_ROWS do
        local removeIndex = #results
        while removeIndex > 0 and results[removeIndex] == uniqueSpell do
            removeIndex = removeIndex - 1
        end
        if removeIndex == 0 then return end
        table.remove(results, removeIndex)
    end
    results[#results + 1] = CreateSynthesizedAuraRow(spellId, uniqueSpell.name, uniqueSpell.icon)
end

local function SearchAutocomplete(query, allowTalentSearch)
    local cache = CS.autocompleteCache or BuildAutocompleteCache()
    local groupId = CS.addingToPanelId or CS.selectedGroup
    local isTriggerTarget = IsTriggerPanelTarget(groupId)
    local targetAcceptsAuraEntries = TargetPanelAcceptsAuraEntries(groupId)
    local isAuraOnlyTarget = TargetPanelIsAuraOnly(groupId)
    -- nil while the panel is empty, which is when it accepts either polarity.
    local auraPanelUnit = isAuraOnlyTarget and GetTargetAuraPanelUnit(groupId) or nil
    if isTriggerTarget or not targetAcceptsAuraEntries or isAuraOnlyTarget then
        local filtered = {}
        for _, entry in ipairs(cache) do
            local keep
            if isAuraOnlyTarget then
                -- Only rows the panel could actually accept: aura rows, and
                -- once a unit is derived, only that unit's polarity.
                -- Sole polarity gate on this path: stripping every "spell" row
                -- here also leaves AddUniqueSpellAuraTwin with no unique spell
                -- to synthesize a twin from.
                keep = entry.autocompleteKind == "aura"
                    and AutocompleteRowFitsAuraPanel(entry, auraPanelUnit)
            else
                keep = (not isTriggerTarget or not entry.isEquipmentSlot)
                    and (targetAcceptsAuraEntries or entry.autocompleteKind ~= "aura")
            end
            if keep then
                filtered[#filtered + 1] = entry
            end
        end
        cache = filtered
    end

    local results = SearchAutocompleteInCache(query, cache) or {}
    local spellId, spellName, spellInfo = ResolveNonBlockedSpellInput(query, not allowTalentSearch)
    if not spellId then
        AddUniqueSpellAuraTwin(results, targetAcceptsAuraEntries)
        return #results > 0 and results or nil
    end

    local canOfferSpell, canOfferAura = GetSpellOfferability(query, spellId)
    local canSynthesizeAura = targetAcceptsAuraEntries and canOfferAura
    -- An Aura Panel offers no plain-spell row at all, and once it has a unit it
    -- offers no aura of the other polarity either.
    local canSynthesizeSpell = canOfferSpell and not isAuraOnlyTarget
    if canSynthesizeAura and isAuraOnlyTarget then
        canSynthesizeAura = AutocompleteRowFitsAuraPanel({ id = spellId }, auraPanelUnit)
    end
    local seenExactKinds = {}
    local filteredResults = {}
    for _, entry in ipairs(results) do
        local kind = entry.autocompleteKind
        -- An aura row whose APPLIED identity matches the typed ID is an
        -- exact aura match too — without this, typing the applied ID would
        -- show the CDM row and a synthesized duplicate side by side.
        local isExactID = tonumber(entry.id) == spellId
            or (kind == "aura" and tonumber(entry.trackedAuraID) == spellId)
        if isExactID and (kind == "spell" or kind == "aura") then
            -- Cached aura rows are Blizzard-curated evidence. Polarity gates
            -- only the synthesized row below, never a cached match.
            local keep = kind == "aura" or canOfferSpell
            if keep and not seenExactKinds[kind] then
                seenExactKinds[kind] = true
                filteredResults[#filteredResults + 1] = entry
            end
        else
            filteredResults[#filteredResults + 1] = entry
        end
    end
    results = filteredResults

    local synthesized = {}
    local icon = spellInfo and spellInfo.iconID or 134400
    if canSynthesizeSpell and not seenExactKinds.spell then
        synthesized[#synthesized + 1] = {
            id = spellId,
            name = spellName,
            nameLower = spellName:lower(),
            icon = icon,
            category = "Spell",
            autocompleteKind = "spell",
            isItem = false,
        }
    end
    if canSynthesizeAura and not seenExactKinds.aura then
        synthesized[#synthesized + 1] = CreateSynthesizedAuraRow(spellId, spellName, icon)
    end

    local normalLimit = AUTOCOMPLETE_MAX_ROWS - #synthesized
    while #results > normalLimit do
        local removeIndex = #results
        while removeIndex > 0 and tonumber(results[removeIndex].id) == spellId do
            removeIndex = removeIndex - 1
        end
        table.remove(results, removeIndex > 0 and removeIndex or #results)
    end
    for _, entry in ipairs(synthesized) do
        results[#results + 1] = entry
    end

    return #results > 0 and results or nil
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
-- Autocomplete: Live Preview ghost for the row under consideration
------------------------------------------------------------------------
-- Only the panel add box asks for this: its ShowAutocompleteResults options
-- carry previewGhostHost (ButtonsWideColumn's EnsureAddBox), and every other
-- field's dropdown, naming no host, stays silent. The ghost draws the row
-- Enter would add and nothing else: the list has ONE selection (the
-- highlight), which the arrow keys and the mouse both move, so the
-- highlight bar, the ghost and Enter can never name three different rows.
-- Index 0 (no explicit choice yet) shows nothing. The preview draws the cell
-- where the pick will land (ST._ShowPreviewDropGhost).
--
-- One stub table, refilled: the text metrics cache would otherwise key a
-- fresh table per hover. Nil when the add would refuse the row
-- (CS.ResolveProspectiveAdd), which is also where the stub learns what the
-- entry will be born as.
local autocompleteGhostSpec = {}
local function AutocompleteGhostSpec(entry)
    local spec = autocompleteGhostSpec
    wipe(spec)
    -- The row's own icon, through the manual-icon door both preview icon
    -- resolvers already honor, so the ghost never re-resolves it.
    spec.manualIcon = entry.icon
    spec.name = entry.name
    if entry.isEquipmentSlot then
        -- Name and icon only: all a trinket-slot ghost can claim before the
        -- slot resolves to an item.
        return spec
    end
    spec.type = entry.isItem and "item" or "spell"
    spec.id = tonumber(entry.id) or entry.id
    spec.isPetSpell = entry.isPetSpell or nil
    spec.forceAura = entry.forceAura or nil
    if not CS.ResolveProspectiveAdd(spec, CS.addingToPanelId or CS.selectedGroup) then
        return nil
    end
    return spec
end

local function UpdateAutocompleteGhost()
    local dropdown = autocompleteDropdown
    local host = dropdown and dropdown._ghostHost
    if not host then return end
    local idx = dropdown._highlightIndex or 0
    local row = dropdown:IsShown() and idx > 0 and dropdown.rows[idx] or nil
    local entry = row and row.entry
    local spec = entry and AutocompleteGhostSpec(entry)
    if spec and ST._ShowPreviewDropGhost
        and ST._ShowPreviewDropGhost(host, spec, nil, "autocomplete") then
        return
    end
    if ST._HidePreviewDropGhost then
        ST._HidePreviewDropGhost(host, "autocomplete")
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
    UpdateAutocompleteGhost()
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
    -- Callers with persistent edit boxes (the wide add box) clear their
    -- widget on success; the workspace inline box rebuilds from CS.newInput.
    return added and true or false
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
    })
    dropdown:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    ST.CreatePixelBorders(dropdown, 0, 0, 0, 1)
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
        selectionBg:SetPoint("TOPLEFT", row, "TOPLEFT", -1, i == 1 and 1 or 0)
        selectionBg:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 1, 0)
        selectionBg:SetColorTexture(0.2, 0.4, 0.7, 0.4)
        selectionBg:Hide()
        row.selectionBg = selectionBg

        -- Mouse hover highlight
        local highlight = row:CreateTexture(nil, "HIGHLIGHT")
        highlight:SetPoint("TOPLEFT", row, "TOPLEFT", -1, i == 1 and 1 or 0)
        highlight:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 1, 0)
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

        -- The mouse moves the selection exactly as the arrow keys do, and
        -- counts as the explicit choice requireExplicitChoice waits for: the
        -- bar sits on the row, the ghost shows it, Enter adds it.
        row:SetScript("OnEnter", function()
            if dropdown._highlightIndex ~= i then
                dropdown._highlightIndex = i
                dropdown._userNavigated = true
                UpdateAutocompleteHighlight()
            end
        end)

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
    -- However the list goes (a pick, Escape, the field cleared or blurred),
    -- the ghost goes with it.
    dropdown:SetScript("OnHide", function(self)
        if self._ghostHost and ST._HidePreviewDropGhost then
            ST._HidePreviewDropGhost(self._ghostHost, "autocomplete")
        end
    end)

    autocompleteDropdown = dropdown
    return dropdown
end

------------------------------------------------------------------------
-- Autocomplete: Show results anchored to an edit box widget
------------------------------------------------------------------------
local function ShowAutocompleteResults(results, anchorWidget, onSelect, options)
    if CS.HideSettingsFinderResults then
        CS.HideSettingsFinderResults()
    end
    local dropdown = GetOrCreateAutocompleteDropdown()
    dropdown._onSelect = onSelect
    dropdown._anchorWidget = anchorWidget
    dropdown._options = options
    dropdown._editbox = anchorWidget.editbox
    dropdown._requireExactNumericEnter = options and options.requireExactNumericEnter == true
    dropdown._requireExplicitChoice = options and options.requireExplicitChoice == true
    -- One dropdown serves every field. A ghost the previous owner left up
    -- (the list stayed open while another field took over) goes with the
    -- owner, since the hider below only ever knows the current one.
    local ghostHost = options and options.previewGhostHost or nil
    if dropdown._ghostHost and dropdown._ghostHost ~= ghostHost and ST._HidePreviewDropGhost then
        ST._HidePreviewDropGhost(dropdown._ghostHost, "autocomplete")
    end
    dropdown._ghostHost = ghostHost

    if not results then
        dropdown:Hide()
        return
    end

    -- Anchor below the edit box widget's frame (parented to UIParent, so it draws above the config panel).
    -- Narrow row controls may request a wider centered popup without changing
    -- the edit box or the default sizing used by other autocomplete callers.
    local anchorFrame = anchorWidget.frame or anchorWidget
    dropdown:ClearAllPoints()
    local widthMultiplier = options and tonumber(options.widthMultiplier)
    if widthMultiplier and widthMultiplier > 0 then
        dropdown:SetPoint("TOP", anchorFrame, "BOTTOM", 0, -2)
        dropdown:SetWidth(anchorFrame:GetWidth() * widthMultiplier)
    else
        dropdown:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -2)
        dropdown:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", 0, -2)
    end

    local numResults = #results
    dropdown._highlightIndex = dropdown._requireExplicitChoice and numResults > 1 and 0 or 1
    dropdown._userNavigated = nil
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

    -- The rows are retexted in place, so a row already under a resting
    -- cursor gets no OnEnter of its own; it is read here instead, so the
    -- selection (and the ghost) stay on the row the mouse is on.
    for i = 1, numResults do
        if dropdown.rows[i]:IsMouseOver() then
            dropdown._highlightIndex = i
            dropdown._userNavigated = true
            break
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
        autocompleteDropdown._userNavigated = true
        UpdateAutocompleteHighlight()
    elseif key == "UP" then
        local idx = (autocompleteDropdown._highlightIndex or 0) - 1
        if idx < 1 then idx = maxIdx end
        autocompleteDropdown._highlightIndex = idx
        autocompleteDropdown._userNavigated = true
        UpdateAutocompleteHighlight()
    elseif key == "ENTER" then
        local idx
        local editText = autocompleteDropdown._editbox and autocompleteDropdown._editbox:GetText()
        local exactID = editText and editText:match("^%s*(%d+)%s*$")
        exactID = exactID and tonumber(exactID) or nil
        if autocompleteDropdown._requireExactNumericEnter and exactID then
            local exactIndex
            local exactCount = 0
            for rowIndex = 1, maxIdx do
                local row = autocompleteDropdown.rows[rowIndex]
                if row and row.entry and tonumber(row.entry.id) == exactID then
                    if not exactIndex then
                        exactIndex = rowIndex
                    end
                    exactCount = exactCount + 1
                end
            end
            if autocompleteDropdown._requireExplicitChoice then
                if exactCount == 1 then
                    idx = exactIndex
                end
            elseif exactIndex then
                idx = exactIndex
            else
                autocompleteDropdown:Hide()
                return
            end
        elseif autocompleteDropdown._requireExplicitChoice then
            if maxIdx == 1 then
                idx = 1
            elseif autocompleteDropdown._userNavigated then
                idx = autocompleteDropdown._highlightIndex or 0
            end
        else
            idx = autocompleteDropdown._highlightIndex or 0
        end
        if idx and idx > 0 and autocompleteDropdown.rows[idx] and autocompleteDropdown.rows[idx].entry then
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

local function HasPendingAutocompleteSpellChoice(resolvedSpellId)
    if not autocompleteDropdown or not autocompleteDropdown:IsShown() then
        return false
    end
    for rowIndex = 1, autocompleteDropdown._numResults or 0 do
        local row = autocompleteDropdown.rows[rowIndex]
        local kind = row and row.entry and row.entry.autocompleteKind
        local entryId = row and row.entry and tonumber(row.entry.id)
        if (kind == "spell" or kind == "aura")
            and (not resolvedSpellId or entryId == resolvedSpellId) then
            return true
        end
    end
    return false
end

local function ShouldSubmitRawAddOnEnter(input)
    local spellId, spellName = ResolveNonBlockedSpellInput(input)
    if HasPendingAutocompleteSpellChoice(spellId) then return false end
    if not spellId then return true end

    local canOfferSpell, canOfferAura = GetSpellOfferability(input, spellId)
    if not canOfferSpell and not canOfferAura then
        PrintCannotTrackAsAura(spellName)
        return false
    end
    if not canOfferSpell and canOfferAura and not TargetPanelAcceptsAuraEntries() then
        PrintAuraPanelUnsupported()
        return false
    end

    local results = SearchAutocomplete(input, true)
    if results and autocompleteDropdown and autocompleteDropdown._anchorWidget then
        ShowAutocompleteResults(
            results,
            autocompleteDropdown._anchorWidget,
            autocompleteDropdown._onSelect,
            autocompleteDropdown._options
        )
        return false
    end
    return true
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
ST._ShouldSubmitRawAddOnEnter = ShouldSubmitRawAddOnEnter
ST._CreateAddBoxInfoButton = CreateAddBoxInfoButton
