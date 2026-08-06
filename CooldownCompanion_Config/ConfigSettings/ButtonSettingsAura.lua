--[[
    CooldownCompanion_Config - ConfigSettings/ButtonSettingsAura.lua
    Per-entry Aura tab (12.1 rebuild, fresh design — no CDM concepts).
    Phase 1 scope: enable toggle, tracked-aura list + add box, derived unit
    line. Display toggles and style sections arrive in later phases.
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
-- BuildAppearanceTab's icons path (GroupTabs.lua); this file conforms to them
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

local function GetEntryAuraUnit(buttonData)
    local resolved = CooldownCompanion:ResolveAuraSpellID(buttonData)
    return ClassifyAuraSpellUnit(resolved) or buttonData.auraUnit or "player"
end

local function EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID)
    return CooldownCompanion:EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID)
end

-- Store the derived unit whenever tracking config changes, so the runtime's
-- fallback (uncached spells at login) starts from the right value.
local function SyncDerivedAuraUnit(buttonData)
    local primaryAuraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
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
    {"Buffs are tracked on you, or on you and your group. Your own debuffs are tracked on your target. This is a Blizzard restriction.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Whether an entry is a buff or a debuff is detected automatically.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"With no auras listed, the entry tracks its own aura. Added aura IDs override that; spell entries always keep their own aura as a fallback.", 1, 1, 1, true},
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

local PANDEMIC_MARKER_TOOLTIP = {
    "Pandemic Marker",
    {"Marks the duration text during the last 30% of the aura. Recasting in that window adds to the remaining time instead of wasting it.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"On by default for debuffs on your target, off for your own buffs.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Marker text and color are in the group's Aura Duration Text settings.", 1, 1, 1, true},
}

local PANDEMIC_EFFECT_TOOLTIP = {
    "Pandemic Effect",
    {"Shows the group's pandemic visual on this entry while the aura is in its refresh window.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Only appears for auras that gain bonus time when refreshed. The game decides the window.", 1, 1, 1, true},
    {" ", 1, 1, 1, true},
    {"Style and color are in the group's Effects settings.", 1, 1, 1, true},
}

local function BuildAuraTab(scroll, group, buttonData, infoButtons)
    -- Function-local, not a file upvalue: the same convention every converted
    -- surface follows (GroupTabs.lua's icons path states it).
    local BeginRowGrid = ST._BeginRowGrid

    local isStandalone = buttonData.addedAs == "aura"

    -- One collapsible row-grammar section. The tab's ScrollFrame is already a
    -- "List" and Panel.lua re-lays it once this builder returns. No gear and
    -- no preview-command-center route reaches this tab, so nothing has to
    -- uncollapse it from the outside.
    local sectionKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_aura_tracking"
    local heading, collapsed = BuildCollapsibleSection(scroll, "Aura Tracking", sectionKey,
        nil, nil, ROW_SECTION)

    -- The heading's "?" chains off the end of its label; the fading rule
    -- restarts after that badge.
    local auraInfoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0,
        AURA_TRACKING_TOOLTIP, infoButtons)
    AnchorLeftAlignedHeadingRule(heading, auraInfoBtn)

    if collapsed then return end

    -- LEFT column: which aura is tracked, and on whom. RIGHT column: how the
    -- entry draws it. Both halves are gated on the toggle at the head of the
    -- left one, so the right side is empty until tracking is on.
    local auraLeft, auraRight = BeginRowGrid(scroll)

    if not isStandalone then
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

    if not (isStandalone or buttonData.auraTracking) then
        return
    end

    -- Derived polarity line (read-only by design; the heading's "?" explains
    -- why). Only the buff/debuff split is automatic — a buff's scope is the
    -- one part the user chooses, in the row below.
    local primaryAuraSpellID = CooldownCompanion:ResolveAuraSpellID(buttonData)
    local classifiedUnit = ClassifyAuraSpellUnit(primaryAuraSpellID)
    local unit = classifiedUnit or buttonData.auraUnit or "player"
    local isBuff = unit ~= "target"
    -- The derived unit falls back to the stored auraUnit (then "player") when
    -- the spell's data is not cached yet, so `isBuff` can be a guess. The scope
    -- row is gated on a CONFIRMED polarity: offering it off the fallback lets
    -- the user tick a box on what turns out to be a debuff, where the runtime
    -- resolves to the target unconditionally and the setting does nothing.
    local polarityKnown = classifiedUnit ~= nil
    local canTrackGroup = isBuff and polarityKnown
        and EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID)
    AddLabelRow(auraLeft, {
        label = "Tracked on",
        indent = not isStandalone,
        controlText = (not isBuff) and "Target"
            or (buttonData.auraTrackGroup and "You and your group" or "You"),
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
            GetEntryAuraUnit(buttonData),
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
            if TryAddAuraCandidate(buttonData, text, GetEntryAuraUnit(buttonData), OnCandidateListChanged) then
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
            local maxStacks = CooldownCompanion:GetAuraStackBarMax(buttonData)
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

            -- Painted-divider mode only: widget-mode blocks (aura entries)
            -- have the gap proportion baked into the bundled fill atlas.
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
                        CooldownCompanion:SetBarPanelAuraSegmentGap(buttonData, value)
                        -- Rebind only: the gap is pure slot-kit styling, so no group
                        -- refresh and no panel rebuild (which would break the drag).
                        CooldownCompanion:RequestAuraRebind("config")
                    end,
                })
            end

            AddAuraStackMaxStatusLabel(auraRight, maxStacks, { row = true })
        end
    end

    -- Display toggles. Standalone and passive entries always show the live
    -- aura icon (it exists to display the aura), so the opt-in only appears
    -- on ordinary spell entries.
    if not (isStandalone or buttonData.isPassive) then
        AddCheckboxRow(auraRight, {
            label = "Show Aura Icon While Active",
            value = buttonData.auraShowAuraIcon == true,
            onChange = function(value)
                buttonData.auraShowAuraIcon = value and true or nil
                RefreshAuraConfig()
            end,
        })
    end

    if buttonData.isPassive then
        -- Passives desaturate while the aura is missing by default.
        AddCheckboxRow(auraRight, {
            label = "Desaturate While Active Instead",
            value = buttonData.invertAuraDesaturationLogic == true,
            onChange = function(value)
                buttonData.invertAuraDesaturationLogic = value and true or nil
                RefreshAuraConfig()
            end,
        })

        AddCheckboxRow(auraRight, {
            label = "Never Desaturate",
            value = buttonData.neverDesaturate == true,
            onChange = function(value)
                buttonData.neverDesaturate = value and true or nil
                RefreshAuraConfig()
            end,
        })
    else
        AddCheckboxRow(auraRight, {
            label = "Desaturate Icon While Aura Missing",
            value = buttonData.desaturateWhileAuraNotActive == true,
            onChange = function(value)
                buttonData.desaturateWhileAuraNotActive = value and true or nil
                RefreshAuraConfig()
            end,
        })
    end

    -- Pandemic marker per-entry switch. The auto default follows the tracked
    -- unit (on for target debuffs, off for player buffs); only an explicit
    -- override is stored, so unchanged entries keep tracking the default.
    local pandemicDefault = unit == "target"
    local pandemicValue = buttonData.pandemicMarker
    if pandemicValue == nil then pandemicValue = pandemicDefault end
    local pandemicRow = AddCheckboxRow(auraRight, {
        label = "Pandemic Marker",
        value = pandemicValue == true,
        onChange = function(value)
            if value == pandemicDefault then
                buttonData.pandemicMarker = nil
            else
                buttonData.pandemicMarker = value and true or false
            end
            RefreshAuraConfig()
        end,
    })
    AnchorRowBadge(pandemicRow, CreateInfoButton(pandemicRow.frame, pandemicRow.frame, "LEFT", "LEFT", 0, 0,
        PANDEMIC_MARKER_TOOLTIP, infoButtons))

    -- Pandemic effect per-entry switch (PTR 8 visuals). The default follows
    -- the EFFECTIVE explicit-true enable — a promoted pandemicGlow override
    -- can carry its own pandemicEffectEnabled — so the checkbox reflects
    -- what this entry actually resolves; only an explicit override is
    -- stored, so unchanged entries keep tracking that resolution.
    local effectStyle = group and group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        effectStyle = CooldownCompanion:GetEffectiveStyle(effectStyle, buttonData) or effectStyle
    end
    local effectDefault = effectStyle.pandemicEffectEnabled == true
    local effectValue = buttonData.pandemicEffect
    if effectValue == nil then effectValue = effectDefault end
    local effectRow = AddCheckboxRow(auraRight, {
        label = "Pandemic Effect",
        value = effectValue == true,
        onChange = function(value)
            if value == effectDefault then
                buttonData.pandemicEffect = nil
            else
                buttonData.pandemicEffect = value and true or false
            end
            RefreshAuraConfig()
        end,
    })
    AnchorRowBadge(effectRow, CreateInfoButton(effectRow.frame, effectRow.frame, "LEFT", "LEFT", 0, 0,
        PANDEMIC_EFFECT_TOOLTIP, infoButtons))
end

ST._BuildAuraTab = BuildAuraTab
