--[[
    CooldownCompanion_Config - ConfigSettings/ButtonSettingsAura.lua
    Per-entry Aura Tracking section (12.1 rebuild, fresh design — no CDM
    concepts). It was its own entry tab until the entry cluster collapsed to
    one Settings tab; it now renders into that pane directly below Show
    Conditions, whose aura toggles depend on the setup made here.
    Scope: enable toggle, tracked-aura list + add box, derived unit line,
    display toggles and style rows.
    The tracked unit is auto-derived from spell polarity and never user-set:
    Blizzard's anti-cheat gate allows only buffs-on-player and own-debuffs-
    on-target, so illegal configurations are unrepresentable here.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local CreateInfoButton = ST._CreateInfoButton
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule

-- Imports from RowWidgets.lua (the row grammar). The rules every row-grammar
-- section follows are stated once, in the recipe comment at the top of
-- BuildAppearanceTab's icons path (GroupTabsAppearance.lua); this file conforms to them
-- rather than restating them.
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddLabelRow = ST._AddLabelRow
local AnchorRowBadge = ST._AnchorRowBadge

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- Shared tracked-aura list rules (SectionBuilders.lua): the CSV shape, the
-- polarity guard, and the row/status widgets are common to this tab and the
-- custom-bar Aura tab.
local ClassifyAuraSpellUnit = ST._ClassifyAuraSpellUnit
local GetAuraCandidateList = ST._GetAuraCandidateList
local TryAddAuraCandidate = ST._TryAddAuraCandidate
local RemoveAuraCandidate = ST._RemoveAuraCandidate
local AddAuraCandidateRow = ST._AddAuraCandidateRow
local AddAuraStackMaxStatusLabel = ST._AddAuraStackMaxStatusLabel
-- Shared with the resource overlay's aura field, so both tracked-aura
-- surfaces suggest the same list (it used to be defined here alone).
local BuildTrackedAuraAutocompleteCache = ST._RBP.BuildTrackedAuraAutocompleteCache

-- Full group refresh, not just a rebind: aura config changes can flip the
-- CC-side static composition too (shell alpha, countdown text hosting),
-- which only UpdateButtonStyle applies.
local function RefreshAuraConfig()
    CooldownCompanion:RefreshAllGroups()
    CooldownCompanion:RequestAuraRebind("config")
    CooldownCompanion:RefreshConfigPanel()
end

local function ResolveConfiguredAuraSpellID(buttonData)
    return CooldownCompanion:ResolveAuraSpellID(buttonData)
        or CooldownCompanion:ResolveTexturePanelAuraSpellID(buttonData)
end

local function GetExplicitAuraCandidateUnit(buttonData)
    if buttonData.addedAs == "aura" then
        local resolved = ResolveConfiguredAuraSpellID(buttonData)
        return ClassifyAuraSpellUnit(resolved) or buttonData.auraUnit or "player"
    end
    local candidates = GetAuraCandidateList(buttonData)
    if #candidates == 0 then
        -- The first explicit Aura owns the entry's polarity. Do not compare it
        -- against the implicit base spell; the post-change sync below derives
        -- and stores the new player/target unit from the chosen Aura.
        return nil
    end
    for _, spellID in ipairs(candidates) do
        local unit = ClassifyAuraSpellUnit(spellID)
        if unit then
            return unit
        end
    end
    return buttonData.auraUnit
end

local function EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID)
    if type(buttonData) == "table"
        and buttonData.addedAs ~= "aura"
        and #GetAuraCandidateList(buttonData) > 0 then
        local baseUnit = ClassifyAuraSpellUnit(buttonData.id)
        local explicitUnit = ClassifyAuraSpellUnit(primaryAuraSpellID)
        if baseUnit and explicitUnit and baseUnit ~= explicitUnit then
            -- The base spell remains the ownership proof for same-polarity
            -- applied Aura IDs. An opposite-polarity Aura is an independent
            -- override, so the base spell cannot make it group-trackable.
            return false, true
        end
    end
    return CooldownCompanion:EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID)
end

-- Store the derived unit whenever tracking config changes, so the runtime's
-- fallback (uncached spells at login) starts from the right value.
local function SyncDerivedAuraUnit(buttonData)
    local primaryAuraSpellID = ResolveConfiguredAuraSpellID(buttonData)
    local unit = ClassifyAuraSpellUnit(primaryAuraSpellID)
    if unit then
        buttonData.auraUnit = unit
        -- Group scope is limited to buffs the player can cast: debuffs resolve
        -- to your target and ignore the flag, while foreign buffs are own-cast
        -- filtered on every unit, including you. Drop a stored setting that
        -- would silently do nothing or make the entry match nowhere.
        if unit == "target" or not EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID) then
            buttonData.auraTrackGroup = nil
        end
        -- Pet scope normalizes through the CORE ownership rule, not the
        -- wrapper above: the wrapper's opposite-polarity veto is group-only,
        -- and clearing pet scope through it would strip the harmful-base/
        -- helpful-pet-aura shape pet tracking exists for (Barbed Shot ->
        -- Frenzy).
        if unit == "target"
            or CooldownCompanion:EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID) ~= true then
            buttonData.auraTrackPet = nil
        end
    end
end

-- Pet-command capability, LEARNED per character: HasPetSpells reflects the
-- CURRENT pet spellbook, which empties while the pet is dismissed
-- (owner-observed 2026-08-21: a DK with no ghoul out gets nothing back), so
-- gating on the live value alone hides the pet-scope row exactly when a pet
-- class is between summons. Once the character has ever shown pet spells the
-- answer sticks (db.global keyed by AceDB char key, the totem-links
-- convention); a fresh character self-heals the first time this row is built
-- while a pet is out.
local function CharacterCanCommandPets()
    local db = CooldownCompanion.db
    local charKey = db and db.keys and db.keys.char
    if not charKey then
        return C_SpellBook.HasPetSpells() ~= nil
    end
    local store = db.global.petCapableChars
    if store[charKey] then
        return true
    end
    if C_SpellBook.HasPetSpells() ~= nil then
        store[charKey] = true
        return true
    end
    return false
end

-- Shared with the Visibility tab's Show & Hide Rules row for ordinary spell
-- entries. Primary Aura entries are always enabled in Texture panels; layered
-- spell entries retain the explicit opt-in so legacy nil placements stay
-- dormant.
local TEXTURE_INDICATOR_PREVIEW_KEYS = { "proc", "aura", "ready", "unusable" }
local STANDARD_TEXTURE_INDICATOR_ADVANCED_KEYS = {
    "textureIndicator_proc",
    "textureIndicator_ready",
    "textureIndicator_unusable",
}

local function SetTexturePanelAuraDisplayEnabled(group, buttonData, value, groupId)
    local enabled = buttonData.addedAs == "aura" or value == true
    buttonData.textureAuraDisplayEnabled = enabled
    if groupId then
        -- The applicable preview family changes with this toggle. Clear every
        -- Texture preview flag now so a hidden command-center control cannot
        -- leave the config-mirror animation armed or resume it later.
        for _, indicatorKey in ipairs(TEXTURE_INDICATOR_PREVIEW_KEYS) do
            CooldownCompanion:SetGroupTextureIndicatorPreview(groupId, indicatorKey, false)
        end
    end
    if enabled then
        -- Aura control replaces the standard Texture indicator rows with one
        -- inline Aura section. Retire any standard advanced popout that was
        -- left open across the entry/panel scope switch so it cannot keep
        -- editing settings that are now dormant.
        if CS.CloseAdvancedSettingsPanel then
            for _, settingKey in ipairs(STANDARD_TEXTURE_INDICATOR_ADVANCED_KEYS) do
                CS.CloseAdvancedSettingsPanel({ settingKey = settingKey })
            end
        end
        CooldownCompanion:NormalizeTexturePanelAuraIndicatorSettings(group, true)
        if not buttonData.auraSpellID then
            local inferred = CooldownCompanion:InferConfirmedAuraSpellIDString(buttonData)
            if inferred then
                buttonData.auraSpellID = inferred
            end
        end
        SyncDerivedAuraUnit(buttonData)
    end
end

-- Post-change hook for the shared list writers: keep the stored (derived)
-- unit in sync with the list's polarity, then re-normalize standalone
-- entries (whose implicit aura is rebuilt from the entry itself).
local function OnCandidateListChanged(buttonData)
    SyncDerivedAuraUnit(buttonData)
    if buttonData.addedAs == "aura" and CooldownCompanion.NormalizeStandaloneAuraButtonData then
        CooldownCompanion:NormalizeStandaloneAuraButtonData(buttonData)
    end
end

local function AddCandidateRow(container, buttonData, spellID)
    AddAuraCandidateRow(container, spellID, function(removedID)
        if RemoveAuraCandidate(buttonData, removedID, OnCandidateListChanged) then
            RefreshAuraConfig()
        end
    end, { row = true })
end

local AURA_TRACKING_TOOLTIP = {
    "Aura Tracking",
    {"Blizzard tracks the aura and drives the display; the addon never reads aura state in combat.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Buffs are tracked on you. A buff tied to a helpful spell you can cast can also follow your group, or be tracked only on your pet; a buff overriding a harmful spell stays on you. Your own debuffs are tracked on your target.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Whether an entry is a buff or a debuff is detected automatically.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"With no auras listed, the entry tracks its own aura. Added aura IDs take priority; its own aura remains a fallback only when both are buffs or both are debuffs.", 1, 1, 1, true},
}

local TEXTURE_AURA_TRACKING_TOOLTIP = {
    "Aura-controlled Texture",
    {"Blizzard tracks the aura and directly controls whether the configured texture is shown. The addon never reads aura state in combat.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Buffs are tracked on you. Your own debuffs are tracked on your target. Group-member tracking is not available for Texture panels.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"With no auras listed, the entry tracks its own aura. Added aura IDs take priority; its own aura remains a fallback only when both are buffs or both are debuffs.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"This is presence-only: duration and stacks are not displayed. An optional active-aura effect can be configured in the Indicators tab.", 1, 1, 1, true},
}

local GROUP_SCOPE_TOOLTIP = {
    "Track on Group Members",
    {"Follows the buff onto anyone in your party or raid, like a healer's Lifebloom on a tank.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Group members only. The game gives the addon no way to track buffs on friendly players outside your group.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Best for buffs that sit on one person at a time. The addon is never told who holds the aura, so a buff on several people draws overlapping displays, one per person.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Aura sounds only work while you're ungrouped. In a group they fire per person, so moving the buff would sound like it dropped.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Group size is read out of combat, so someone joining mid-fight is picked up at the next quiet moment.", 1, 1, 1, true},
}

local PET_SCOPE_TOOLTIP = {
    "Track on Your Pet",
    {"Tracks the buff on your summoned pet instead of on you, like Dark Transformation on a ghoul.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Covers buffs you cast on the pet and buffs the pet gains on its own.", 1, 1, 1, true},
}

local BAR_SHOWS_STACKS_TOOLTIP = {
    "Bar Shows Stacks",
    {"The bar fills by stack count instead of draining with time. Blizzard drives the fill, and the maximum comes from the game's spell data.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Stack Style picks the look. Segmented shows one piece per stack; on spell entries the pieces are painted dividers, so the cooldown bar underneath needs a solid backdrop. Continuous is one plain bar that fills as stacks build.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"If the aura doesn't stack, the bar keeps the normal duration fill.", 1, 1, 1, true},
}

local SEGMENTED_SMOOTHING_TOOLTIP = {
    "Segmented Smoothing",
    {"Segmented stack bars animate smoothly between stack counts, or snap instantly. Same control as the resource bar option.", 1, 1, 1, true},
    " ",
    {"Continuous stack bars always animate smoothly.", 1, 1, 1, true},
    " ",
    {"Gaining or losing the aura entirely always snaps; the game only animates stack changes.", 1, 1, 1, true},
}

local function BuildAuraTrackingSection(scroll, group, buttonData, infoButtons)
    local BeginRowGrid = ST._BeginRowGrid

    local isStandalone = buttonData.addedAs == "aura"
    local isTexturePanel = group and group.displayMode == "textures"
    -- An Aura Panel cell is structurally SINGLE-UNIT: BindPanelGroup never
    -- passes groupScoped, so the group-scope rows below have nothing to act on
    -- there (owner ruling 2026-08-15).
    local isAuraPanel = ST.IsAuraPanelGroup(group)

    -- One collapsible row-grammar section, emitted into the entry Settings
    -- pane's ScrollFrame (already a "List"; Panel.lua re-lays it once the
    -- whole pane is built). No gear and no preview-command-center route
    -- reaches this section, so nothing has to uncollapse it from the outside.
    -- The key is unchanged from when this was its own tab, so an expand state
    -- set before the merge survives it.
    local sectionKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_aura_tracking"
    local heading, collapsed = BuildCollapsibleSection(scroll, "Aura Tracking", sectionKey,
        nil, nil, ROW_SECTION)

    -- The heading's "?" chains off the end of its label; the fading rule
    -- restarts after that badge.
    local auraInfoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0,
        isTexturePanel and TEXTURE_AURA_TRACKING_TOOLTIP or AURA_TRACKING_TOOLTIP, infoButtons)
    AnchorLeftAlignedHeadingRule(heading, auraInfoBtn)

    if collapsed then return end

    -- LEFT column: which aura is tracked, and on whom. RIGHT column: how the
    -- entry draws it. Both halves are gated on the toggle at the head of the
    -- left one, so the right side is empty until tracking is on.
    local auraLeft, auraRight = BeginRowGrid(scroll)

    if not isTexturePanel and not isStandalone then
        AddCheckboxRow(auraLeft, {
            label = "Track an Aura",
            value = buttonData.auraTracking == true,
            onChange = function(value)
                buttonData.auraTracking = value and true or nil
                if value then
                    if not buttonData.auraSpellID then
                        local inferred = CooldownCompanion:InferConfirmedAuraSpellIDString(buttonData)
                        if inferred then
                            buttonData.auraSpellID = inferred
                        end
                    end
                    SyncDerivedAuraUnit(buttonData)
                end
                RefreshAuraConfig()
            end,
        })
    end

    if (isTexturePanel
            and not CooldownCompanion:IsTexturePanelAuraDisplayEnabled(group, buttonData))
        or (not isTexturePanel and not (isStandalone or buttonData.auraTracking)) then
        return
    end

    -- Derived polarity line (read-only by design; the heading's "?" explains
    -- why). Only the buff/debuff split is automatic — a buff's scope is the
    -- one part the user chooses, in the row below.
    local primaryAuraSpellID = ResolveConfiguredAuraSpellID(buttonData)
    local classifiedUnit = ClassifyAuraSpellUnit(primaryAuraSpellID)
    local unit = classifiedUnit or buttonData.auraUnit or "player"
    local isBuff = unit ~= "target"
    -- The derived unit falls back to the stored auraUnit (then "player") when
    -- the spell's data is not cached yet, so `isBuff` can be a guess. The scope
    -- row is gated on a CONFIRMED polarity: offering it off the fallback lets
    -- the user tick a box on what turns out to be a debuff, where the runtime
    -- resolves to the target unconditionally and the setting does nothing.
    local polarityKnown = classifiedUnit ~= nil
    local canTrackGroup = not isTexturePanel and not isAuraPanel and isBuff and polarityKnown
        and EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID)
    -- The read-only line exists to state the SCOPE the checkbox below sets. An
    -- Aura Panel cell has one unit and no checkbox, so the line has nothing left
    -- to report and goes with it.
    if not isAuraPanel then
        local scopeText
        if not isBuff then
            scopeText = "Target"
        elseif isTexturePanel then
            scopeText = "You"
        elseif buttonData.auraTrackPet then
            scopeText = "Your pet"
        elseif buttonData.auraTrackGroup then
            scopeText = "You and your group"
        else
            scopeText = "You"
        end
        AddLabelRow(auraLeft, {
            label = "Tracked on",
            indent = not isStandalone,
            controlText = scopeText,
        })
    end

    -- Read-only: the aura ID(s) that can actually appear on a unit for this
    -- entry — NOT the bind's full match filter, which also registers
    -- cast/base insurance IDs that never exist as auras once the linked
    -- data names a distinct applied identity (owner ruling 2026-08-16:
    -- report the player-meaningful auras, not the filter's insurance).
    -- Built positively: the resolved applied-aura identity plus the user's
    -- explicit adds. Texture panels bind exactly one aura (the same read
    -- ResolveTexturePanelAuraSpellID makes), so they show only that.
    local trackedAuraIDs = {}
    local trackedAuraIDSeen = {}
    local function AppendTrackedAuraID(id)
        if id and not trackedAuraIDSeen[id] then
            trackedAuraIDSeen[id] = true
            trackedAuraIDs[#trackedAuraIDs + 1] = id
        end
    end
    if isTexturePanel then
        AppendTrackedAuraID(primaryAuraSpellID)
    elseif isStandalone then
        -- The resolver's head is the entry's applied-aura identity; the
        -- candidate list holds the user's added fallbacks.
        AppendTrackedAuraID(primaryAuraSpellID)
        for _, id in ipairs(GetAuraCandidateList(buttonData)) do
            AppendTrackedAuraID(id)
        end
    else
        for _, id in ipairs(GetAuraCandidateList(buttonData)) do
            AppendTrackedAuraID(id)
        end
        -- The entry's own aura stays a fallback beside explicit adds only
        -- when polarities match (the constrained bind drops it otherwise).
        local implicitID = CooldownCompanion:ResolveImplicitAuraSpellID(buttonData)
        if implicitID then
            local implicitUnit = ClassifyAuraSpellUnit(implicitID)
            local explicitUnit = #trackedAuraIDs > 0
                and GetExplicitAuraCandidateUnit(buttonData) or nil
            if not explicitUnit or not implicitUnit or implicitUnit == explicitUnit then
                AppendTrackedAuraID(implicitID)
            end
        end
    end
    local trackedAuraIDParts = {}
    for i, id in ipairs(trackedAuraIDs) do
        trackedAuraIDParts[i] = tostring(id)
    end
    AddLabelRow(auraLeft, {
        label = #trackedAuraIDs > 1 and "Tracked Aura IDs" or "Tracked Aura ID",
        indent = not isStandalone,
        controlText = #trackedAuraIDParts > 0
            and table.concat(trackedAuraIDParts, ", ") or "None",
    })

    -- Castable buffs only. Blizzard permits spell-ID matching for helpful auras
    -- across the group, but group scope applies its own-cast filter on every
    -- unit, including you. A foreign buff would never match anywhere; debuffs
    -- resolve to your target and ignore the flag, so offering either would lie.
    if canTrackGroup then
        AddCheckboxRow(auraLeft, {
            label = "Track on group members",
            indent = not isStandalone,
            value = buttonData.auraTrackGroup == true,
            tooltip = GROUP_SCOPE_TOOLTIP,
            onChange = function(value)
                buttonData.auraTrackGroup = value and true or nil
                -- Scopes are exclusive: pet tracking watches ONLY the pet.
                if value then buttonData.auraTrackPet = nil end
                RefreshAuraConfig()
            end,
        })
    end

    -- Pet eligibility is deliberately NOT canTrackGroup: the local wrapper's
    -- opposite-polarity veto above is a group-only rule, but a harmful base
    -- spell applying a helpful pet aura is exactly the shape pet tracking
    -- exists for (Barbed Shot -> Frenzy), so pet uses the CORE ownership
    -- rule alone — the base spell is player-castable, which is what lets
    -- the own-or-pet caster filter match pet self-buffs. The extra gate is
    -- character capability (learned sticky, see CharacterCanCommandPets):
    -- per-spell "lands on the pet" knowledge does not exist in any API, so
    -- character level is the finest honest cut. A stored flag shows the row
    -- regardless of every gate, so retained or imported pet state always
    -- has a clearing path.
    local canTrackPet = not isTexturePanel and not isAuraPanel and isBuff and polarityKnown
        and CharacterCanCommandPets()
        and CooldownCompanion:EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID) == true
    if canTrackPet or buttonData.auraTrackPet == true then
        AddCheckboxRow(auraLeft, {
            label = "Track on your pet",
            indent = not isStandalone,
            value = buttonData.auraTrackPet == true,
            tooltip = PET_SCOPE_TOOLTIP,
            onChange = function(value)
                buttonData.auraTrackPet = value and true or nil
                if value then buttonData.auraTrackGroup = nil end
                RefreshAuraConfig()
            end,
        })
    end

    -- Tracked aura list (empty = tracking the entry's own aura; the heading's
    -- "?" explains the default and override behavior).
    for _, spellID in ipairs(GetAuraCandidateList(buttonData)) do
        AddCandidateRow(auraLeft, buttonData, spellID)
    end

    local auraAddBox
    local function OnAuraAutocompleteSelect(entry)
        CS.HideAutocomplete()
        if entry and TryAddAuraCandidate(
            buttonData,
            tostring(entry.id),
            GetExplicitAuraCandidateUnit(buttonData),
            OnCandidateListChanged
        ) then
            auraAddBox:SetText("")
            RefreshAuraConfig()
        end
    end

    auraAddBox = AddEditBoxRow(auraLeft, {
        label = "Add aura by name or ID",
        indent = true,
        value = "",
        onEnterPressed = function(text, widget)
            if CS.ConsumeAutocompleteEnter() then return end
            CS.HideAutocomplete()
            if TryAddAuraCandidate(buttonData, text, GetExplicitAuraCandidateUnit(buttonData), OnCandidateListChanged) then
                widget:SetText("")
                RefreshAuraConfig()
            end
        end,
    })
    auraAddBox:SetCallback("OnTextChanged", function(widget, _, text)
        if text and #text >= 1 then
            local results = CS.SearchAutocompleteInCache(text, BuildTrackedAuraAutocompleteCache())
            CS.ShowAutocompleteResults(results, widget.editBoxWidget, OnAuraAutocompleteSelect, {
                requireExactNumericEnter = true,
                widthMultiplier = 2,
            })
        else
            CS.HideAutocomplete()
        end
    end)
    CS.SetupAutocompleteKeyHandler(auraAddBox)

    if isTexturePanel then
        -- Texture Aura display intentionally exposes presence only. The
        -- selected artwork and its optional native animation are children of
        -- Blizzard's AuraButton; no duration, stacks, or readable aura state
        -- crosses back out of that forbidden subtree.
        AddLabelRow(auraRight, {
            label = "Display",
            controlText = "Texture while active",
        })
        AddLabelRow(auraRight, {
            label = "Duration / Stacks",
            controlText = "Not shown",
        })
        AddLabelRow(auraRight, {
            label = "Texture Indicators",
            controlText = "Indicators tab",
        })
        return
    end

    -- Bar fill mode (tracker C2): bar hosts can fill the aura bar by stack
    -- count instead of draining with time. Max stacks is automatic (game
    -- data); the status row below shows what resolved.
    if (group.displayMode or "icons") == "bars" then
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        local stacksRow = AddCheckboxRow(auraRight, {
            label = "Bar Shows Stacks",
            value = CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData),
            onChange = function(value)
                CooldownCompanion:SetBarPanelAuraStackDisplay(buttonData, value)
                RefreshAuraConfig()
            end,
        })
        AnchorRowBadge(stacksRow, CreateInfoButton(stacksRow.frame, stacksRow.frame, "LEFT", "LEFT", 0, 0,
            BAR_SHOWS_STACKS_TOOLTIP, infoButtons))

        if CooldownCompanion:IsBarPanelAuraStackDisplay(buttonData) then
            local maxStacks = CooldownCompanion:GetAuraStackBarMax(buttonData, true)
            local stackStyle = CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData)

            -- Stack style (live parity): segmented per-stack rendering or a
            -- plain continuous fill. Live's stored style was wiped by the
            -- aura-rebuild migration, so this is a fresh 12.1 choice.
            if maxStacks then
                AddDropdownRow(auraRight, {
                    label = "Stack Style",
                    indent = true,
                    list = { segmented = "Segmented", continuous = "Continuous" },
                    order = { "segmented", "continuous" },
                    value = stackStyle,
                    onChange = function(value)
                        CooldownCompanion:SetBarPanelAuraStackDisplayMode(buttonData, value)
                        CooldownCompanion:RequestAuraRebind("config")
                        RefreshAuraConfig()
                    end,
                })

                -- Segmented style only: Continuous always animates smoothly
                -- (resource-bar parity), so the toggle would be dead there.
                if stackStyle == "segmented" then
                    local smoothRow = AddDropdownRow(auraRight, {
                        label = "Segmented Smoothing",
                        indent = true,
                        list = {
                            [ST.SEGMENTED_SMOOTHING_ON] = "On",
                            [ST.SEGMENTED_SMOOTHING_OFF] = "Off",
                        },
                        order = { ST.SEGMENTED_SMOOTHING_ON, ST.SEGMENTED_SMOOTHING_OFF },
                        value = CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(buttonData),
                        onChange = function(value)
                            CooldownCompanion:SetBarPanelAuraSegmentedSmoothing(buttonData, value)
                            -- Rebind only: the option re-registers the stack bar
                            -- in the next OOC bind pass; no panel rebuild needed.
                            CooldownCompanion:RequestAuraRebind("config")
                        end,
                    })
                    AnchorRowBadge(smoothRow, CreateInfoButton(smoothRow.frame, smoothRow.frame, "LEFT", "LEFT", 0, 0,
                        SEGMENTED_SMOOTHING_TOOLTIP, infoButtons))
                end
            end

            -- Widget-mode blocks (standalone aura entries): the gap lives
            -- in the bundled fill atlas, so the control is a preset
            -- dropdown picking an atlas set, capped at the block-atlas
            -- max (a larger bound runs painted dividers instead).
            if isStandalone and maxStacks and stackStyle == "segmented"
                and maxStacks <= ST.STACK_SEGMENT_ATLAS_MAX then
                ST._AddStackBlockGapRow(auraRight, buttonData, {
                    maxStacks = maxStacks,
                    commit = function()
                        ST._RefreshSelectedButtonsPreview()
                        CooldownCompanion:RequestAuraRebind("config")
                        CooldownCompanion:RefreshAllGroups()
                    end,
                })
            end

            -- Painted-divider mode only: spell entries keep the free pixel
            -- slider (their stripes are CC-painted, not atlas artwork).
            -- Hidden too when the aura doesn't stack (duration fallback —
            -- there are no segments for a gap to sit between) and for the
            -- continuous style (no segments at all).
            if not isStandalone and maxStacks and stackStyle == "segmented" then
                AddSliderRow(auraRight, {
                    label = "Segment Gap",
                    indent = true,
                    min = 0, max = 20, step = 1,
                    value = CooldownCompanion:GetBarPanelAuraSegmentGap(buttonData),
                    onChange = function(value)
                        local previousAuraBar = buttonData.auraBar
                        local hadAuraBar = type(previousAuraBar) == "table"
                        local previous = hadAuraBar and previousAuraBar.segmentGap or nil
                        CooldownCompanion:SetBarPanelAuraSegmentGap(buttonData, value)
                        ST._RefreshSelectedButtonsPreview()
                        if hadAuraBar then
                            buttonData.auraBar.segmentGap = previous
                        else
                            buttonData.auraBar = previousAuraBar
                        end
                    end,
                    onRelease = function(value)
                        CooldownCompanion:SetBarPanelAuraSegmentGap(buttonData, value)
                        -- Rebind only: the gap is pure slot-kit styling, so no
                        -- group refresh or panel rebuild is needed.
                        CooldownCompanion:RequestAuraRebind("config")
                    end,
                })
            end

            AddAuraStackMaxStatusLabel(auraRight, maxStacks, { row = true })
        end
    end

    -- Effective style for the text-visibility gates below and the
    -- pandemic-effect default: the same resolution the display renders
    -- with — the panel style, or this entry's customized section when one
    -- is promoted (owner ruling 2026-08-16: settings for a hidden text
    -- hide with it, following whichever scope currently applies).
    local effectiveStyle = group and group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        effectiveStyle = CooldownCompanion:GetEffectiveStyle(effectiveStyle, buttonData) or effectiveStyle
    end

    -- Stack text formatter options: the count can begin at one, recolor at a
    -- chosen stack count, and recolor again at max stacks. Mode-agnostic
    -- (icons and bars both show the count text), so this sits outside the
    -- bars gate. The shared builder emits nothing for auras the game reports
    -- as non-stacking unless a saved one-stack option needs to remain editable.
    -- The comparison against the live count is engine-side (formatter
    -- breakpoints); nothing here ever reads the secret count. Rows shared
    -- with the custom-bar Aura section (SectionBuilders.lua). Gated on the
    -- stack text actually showing, the same ~= false read the display
    -- gates the fontstring with.
    if effectiveStyle.showAuraStackText ~= false then
        ST._BuildStackThresholdColorRows(auraRight, buttonData,
            CooldownCompanion:GetAuraStackBarMax(buttonData, true), {
                infoButtons = infoButtons,
                refresh = RefreshAuraConfig,
                commit = function()
                    ST._RefreshSelectedButtonsPreview()
                    CooldownCompanion:RequestAuraRebind("config")
                end,
            })
    end

    -- How the aura display itself LOOKS is not configured here any more:
    -- keeping this entry's own cooldown swipe while its aura runs, swapping in
    -- the live aura icon, and desaturating the aura layer are all style keys in
    -- the panel's While Aura Active section (Appearance tab), reachable per
    -- entry by customizing that section through the style lens. Only what the
    -- CC icon does in the aura's ABSENCE stays below.

    if buttonData.isPassive then
        -- Passives desaturate while the aura is missing by default; the invert
        -- switch is the While Aura Active section's Desaturate Icon row.
        AddCheckboxRow(auraRight, {
            label = "Never Desaturate",
            value = buttonData.neverDesaturate == true,
            onChange = function(value)
                buttonData.neverDesaturate = value and true or nil
                RefreshAuraConfig()
            end,
        })
    end
    -- Desaturate-while-MISSING is NOT a row here any more: it is a style key
    -- in the panel's Desaturation section (Indicators tab, States), beside
    -- Desaturate On Cooldown, reachable per entry through the style lens.
    -- Only passives keep an entry-side desat switch (Never Desaturate above):
    -- their default-on missing desat is entry-shaped, and the Desaturation
    -- section is aura-entry-denied so it could not carry their key.

    -- The refresh window is NOT configured here any more (owner ruling
    -- 2026-08-16): the marker and the pandemic effect are style keys in the
    -- panel's Pandemic section (Indicators tab), reachable per entry by
    -- customizing that section through the style lens. The marker's old
    -- unit-dependent default survives as that section's "Auto" mode.
end

ST._BuildAuraTrackingSection = BuildAuraTrackingSection
ST._SetTexturePanelAuraDisplayEnabled = SetTexturePanelAuraDisplayEnabled
