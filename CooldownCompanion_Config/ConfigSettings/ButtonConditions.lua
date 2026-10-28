--[[
    CooldownCompanion - ConfigSettings/ButtonConditions.lua: Per-button visibility settings and
    group-level load conditions
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua and State.lua
local ColorHeading = ST._ColorHeading
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local ApplyLeftAlignedHeading = ST._ApplyLeftAlignedHeading
local CreateInfoButton = ST._CreateInfoButton
local BuildAlphaControls = ST._BuildAlphaControls

-- Imports from RowWidgets.lua (the row grammar), used throughout this file.
-- Helper sentences and section action buttons remain stock Label/Button
-- widgets.
local AddCheckboxRow = ST._AddCheckboxRow
local AddDropdownRow = ST._AddDropdownRow
local AddLabelRow = ST._AddLabelRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

local IsNoCooldownSpellID = ST.IsNoCooldownSpell
local HasUsageRequirement = ST.HasUsageRequirement
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local HasItemFallbacks = CooldownCompanion.HasItemFallbacks

local tabInfoButtons = CS.tabInfoButtons

local LOAD_CONDITION_OPTIONS = ST.LOAD_CONDITION_OPTIONS
local ResolvePanelAlphaAnchorSourceMode
-- AceGUI sizes a dropdown's pullout from the dropdown frame itself
-- (AceGUIWidget-DropDown.lua:381), and the row grammar's control column is
-- 140px. Eligibility entries carry a spec/hero icon and can read
-- "Death Knight: Blood", so these four pickers widen their pullout past their
-- host. The pullout floats, so it may overhang the grid column it opens in.
local ELIGIBILITY_PULLOUT_WIDTH = 300
-- Same overhang for the same reason: "Inherit Target Frame Alpha" does not fit
-- the 140px control column.
local PANEL_ALPHA_PULLOUT_WIDTH = 300
local GetSpecHeroSubTreeIDs = ST._GetSpecHeroSubTreeIDs

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG (Visibility surfaces)
------------------------------------------------------------------------

local function DefineLoadConditionFinderSettings(idPrefix, scope, collapseKey)
    local route = ST._DefineSettingRoute({
        idPrefix = idPrefix,
        scope = scope,
        rowScope = "primary",
        tab = "loadconditions",
        section = "where_to_hide",
        sectionLabel = "Where To Hide It",
        collapseKeys = { collapseKey },
    })
    local settings = {}
    for _, option in ipairs(LOAD_CONDITION_OPTIONS) do
        settings[option.key] = route:Setting({
            key = option.key,
            label = option.label,
            aliases = option.key == "vehicleUI" and { "vehicle ui", "override ui" }
                or option.key == "openWorld" and { "open world", "outdoors" }
                or nil,
        })
    end
    return settings
end

local panelLoadConditionSettings = DefineLoadConditionFinderSettings(
    "panel.visibility.where", "panel", "loadconditions_panel_local")
local entryLoadConditionSettings = DefineLoadConditionFinderSettings(
    "entry.visibility.where", "entry", "loadconditions_entry_local")

local function HasSavedSourceRestrictions(source)
    return type(source.loadConditions) == "table" and next(source.loadConditions) ~= nil
        or type(source.talentConditions) == "table" and #source.talentConditions > 0
end

local indicatorSourceRestrictions = ST._DefineSettingRoute({
    idPrefix = "panel.indicator.visibility", scope = "panel", rowScope = "primary",
    tab = "loadconditions", tabLabel = "Visibility",
    section = "source_restrictions", sectionLabel = "Source Restrictions",
    applies = function(context)
        if not ST.IsIndicatorGroup(context.group) then return false end
        for _, source in ipairs(context.group.buttons or {}) do
            if HasSavedSourceRestrictions(source) then return true end
        end
        return false
    end,
}):Setting({key = "sources", label = "Source Restrictions",
    aliases = {"source load conditions", "entry load conditions", "source visibility",
        "source dungeon", "source raid", "source open world", "clear source restrictions",
        "source talents", "talent conditions"}})

local function PanelAlphaState(context)
    if context._ccPanelAlphaFinderState then
        return context._ccPanelAlphaFinderState
    end
    local group = context.group
    if not group then return nil end
    local state = {
        group = group,
        anchorSource = ResolvePanelAlphaAnchorSourceMode
            and ResolvePanelAlphaAnchorSourceMode(context.groupId, group) or nil,
        mountedActive = group.forceAlphaRegularMounted
            or group.forceHideRegularMounted
            or group.forceAlphaDragonriding
            or group.forceHideDragonriding,
    }
    context._ccPanelAlphaFinderState = state
    return state
end

local function PanelAlphaApplies(predicate)
    return function(context)
        local state = PanelAlphaState(context)
        return state and predicate(state) and true or false
    end
end

local panelAlphaSettings = ST._DefineSettingRoute({
    idPrefix = "panel.visibility.alpha",
    scope = "panel",
    rowScope = "primary",
    tab = "loadconditions",
    tabLabel = "Visibility",
    section = "alpha",
    sectionLabel = "Alpha",
    collapseKeys = { "loadconditions_alpha" },
}):Settings({
    source = {
        label = "Panel Alpha",
        aliases = { "inherit alpha", "custom alpha" },
        applies = PanelAlphaApplies(function(state) return state.anchorSource ~= nil end),
    },
    baseline = { label = "Baseline Alpha", aliases = { "opacity", "transparency" } },
    -- The hide and show words find these three-way rows, whose Fully Hidden
    -- and Fully Visible states are reached by clicking through them.
    combat = { label = "In Combat", aliases = { "combat alpha", "hide in combat", "show in combat" } },
    outOfCombat = { label = "Out of Combat", aliases = { "ooc alpha", "hide out of combat", "show out of combat" } },
    regularMount = { label = "Regular Mount", aliases = { "mounted alpha", "hide while mounted", "show while mounted" } },
    skyriding = { label = "Skyriding", aliases = { "dragonriding alpha", "hide while skyriding", "hide while dragonriding" } },
    travelForm = {
        label = "Include Druid Travel Form (applies to both)",
        aliases = { "travel form" },
        applies = PanelAlphaApplies(function(state)
            return state.mountedActive and (state.group.isGlobal or CooldownCompanion._playerClassID == 11)
        end),
    },
    target = { label = "Target Exists", aliases = { "target alpha" } },
    enemy = {
        label = "Enemy Only",
        aliases = { "hostile target" },
        applies = PanelAlphaApplies(function(state) return state.group.forceAlphaTargetExists == true end),
    },
    focus = { label = "Focus Exists", aliases = { "focus alpha" } },
    mouseover = { label = "Mouseover", aliases = { "hover alpha" } },
    customFade = { label = "Custom Fade Settings", aliases = { "fade" } },
    fadeDelay = {
        label = "Fade Delay (seconds)",
        applies = PanelAlphaApplies(function(state) return state.group.customFade == true end),
    },
    fadeIn = {
        label = "Fade In Duration (seconds)",
        applies = PanelAlphaApplies(function(state) return state.group.customFade == true end),
    },
    fadeOut = {
        label = "Fade Out Duration (seconds)",
        applies = PanelAlphaApplies(function(state) return state.group.customFade == true end),
    },
})

local function GetLoadConditionValue(loadConditions, key, defaults, optionDefault)
    if type(loadConditions) ~= "table" then return false end
    local val = loadConditions[key]
    if val == nil then
        if defaults and defaults[key] ~= nil then
            val = defaults[key]
        else
            val = optionDefault or false
        end
    end
    return val == true
end

local function SetLoadConditionValue(loadConditions, key, value, defaults, optionDefault)
    if type(loadConditions) ~= "table" then return end
    local defaultValue = optionDefault or false
    if defaults and defaults[key] ~= nil then
        defaultValue = defaults[key]
    end
    if value == defaultValue then
        loadConditions[key] = nil
    else
        loadConditions[key] = value == true
    end
end

local function EnsureLoadConditions(target)
    if type(target) ~= "table" then return nil end
    if type(target.loadConditions) ~= "table" then
        target.loadConditions = {}
    end
    return target.loadConditions
end

local function SetSpecFilterValue(target, specId, value)
    if type(target) ~= "table" or not specId then return end
    if value then
        if not target.specs then target.specs = {} end
        target.specs[specId] = true
        local loadConditions = EnsureLoadConditions(target)
        if type(loadConditions.specAllowlist) ~= "table" then
            loadConditions.specAllowlist = {}
            for existingSpecId in pairs(target.specs or {}) do
                loadConditions.specAllowlist[existingSpecId] = true
            end
        end
        loadConditions.specAllowlist[specId] = true
    else
        if target.specs then
            target.specs[specId] = nil
            if not next(target.specs) then
                target.specs = nil
            end
        end
        local loadConditions = target.loadConditions
        if type(loadConditions) == "table" and type(loadConditions.specAllowlist) == "table" then
            loadConditions.specAllowlist[specId] = nil
            if not next(loadConditions.specAllowlist) then
                loadConditions.specAllowlist = nil
            end
        end
    end
end

local function SetSpecAllowlistValue(target, specId, value)
    if type(target) ~= "table" or not specId then return end
    if value then
        local loadConditions = EnsureLoadConditions(target)
        if type(loadConditions.specAllowlist) ~= "table" then
            loadConditions.specAllowlist = {}
        end
        loadConditions.specAllowlist[specId] = true
        return
    end

    local loadConditions = target.loadConditions
    if type(loadConditions) == "table" and type(loadConditions.specAllowlist) == "table" then
        loadConditions.specAllowlist[specId] = nil
        if not next(loadConditions.specAllowlist) then
            loadConditions.specAllowlist = nil
        end
    end
end

local function SetHeroTalentValue(target, subTreeID, value)
    subTreeID = tonumber(subTreeID)
    if type(target) ~= "table" or not subTreeID then return end
    if value then
        if type(target.heroTalents) ~= "table" then
            target.heroTalents = {}
        end
        target.heroTalents[subTreeID] = true
        return
    end

    if type(target.heroTalents) == "table" then
        target.heroTalents[subTreeID] = nil
        if not next(target.heroTalents) then
            target.heroTalents = nil
        end
    end
end

local function GetActiveInheritedLabel(sources, key, optionDefault)
    for _, source in ipairs(sources or {}) do
        if GetLoadConditionValue(source.loadConditions, key, source.defaults, optionDefault) then
            return source.label
        end
    end
    return nil
end

-- Row grammar (RowWidgets.lua): a left-aligned collapsible header and the
-- environment toggles as CDC-CheckBoxRows in a row grid. Returns that grid's
-- two columns: the toggles fill the first, so a section action the caller
-- parks in the second comes last.
local function AddScopedLoadConditionToggles(container, opts)
    local target = opts.target
    if not target.loadConditions and not opts.preserveMissing then
        target.loadConditions = {}
    end
    local loadConditions = target.loadConditions or {}
    local defaults = opts.defaults
    local inheritedSources = opts.inheritedSources or {}
    local onChanged = opts.onChanged

    local headingText = opts.headingText or "Hide When In"
    local heading, localCollapsed = BuildCollapsibleSection(container, headingText,
        opts.localCollapsedKey, nil, nil, ROW_SECTION)

    -- opts.infoTooltipLines: the row-grammar header parks its caret to the LEFT
    -- of the label, so the "?" chains off the end of the label and the fading
    -- rule restarts after it.
    if opts.infoTooltipLines then
        local infoBtn = CreateInfoButton(
            heading.frame,
            heading.label,
            "LEFT",
            "RIGHT",
            4,
            0,
            opts.infoTooltipLines,
            opts.infoButtons
        )
        AnchorLeftAlignedHeadingRule(heading, infoBtn)
    end
    if localCollapsed then return end

    -- The one write every toggle performs.
    local function SetCondition(cond, newVal)
        if not target.loadConditions then
            target.loadConditions = {}
            loadConditions = target.loadConditions
        end
        SetLoadConditionValue(loadConditions, cond.key, newVal, defaults, cond.default)
        if onChanged then onChanged() end
    end

    -- The instanced content first, then everything else, ending with the two
    -- that ship pre-checked. Locked rows keep their long "(locked by ...)"
    -- suffix: a row label runs the full row width minus the 140px control
    -- column.
    local togglesLeft, togglesRight = BeginRowGrid(container)

    for _, cond in ipairs(LOAD_CONDITION_OPTIONS) do
        local inheritedLabel = GetActiveInheritedLabel(inheritedSources, cond.key, cond.default)
        local row = AddCheckboxRow(togglesLeft, {
            label = inheritedLabel
                and (cond.label .. " |cff888888(locked by " .. inheritedLabel .. ")|r")
                or cond.label,
            -- The locked suffix is the one label here long enough to clip
            -- against the control column, so it also says its piece on
            -- hover. Row labels do not word-wrap by design.
            tooltip = inheritedLabel and {
                cond.label,
                { "Locked by " .. inheritedLabel .. ".", 1, 1, 1, true },
            } or nil,
            value = inheritedLabel and true
                or GetLoadConditionValue(loadConditions, cond.key, defaults, cond.default),
            disabled = inheritedLabel ~= nil,
            onChange = not inheritedLabel and function(newVal)
                SetCondition(cond, newVal)
            end or nil,
        })
        local setting = opts.settings and opts.settings[cond.key]
        if setting and ST._BindSettingWidget then
            -- Keep the live "locked by ..." suffix; this is a custom binding
            -- because the descriptor's stable label intentionally omits it.
            ST._BindSettingWidget(row, setting)
        end
    end

    return togglesLeft, togglesRight
end

local NormalizeAllowlistKey = ST.NormalizeAllowlistKey
local CopyAllowlistMap = ST.CopyAllowlistMap

-- Same copy as the shared CopyAllowlistMap, plus a second return: whether the
-- source map had any entry at all (enabled or not).
local function CopyAllowlist(map, kind)
    local copy = CopyAllowlistMap(map, kind)
    if copy then return copy, true end
    return nil, (type(map) == "table" and next(map) ~= nil) or false
end

local IntersectTruthyMaps = ST.IntersectTruthyMaps

local function GetInheritedAllowlist(sources, field, kind)
    local inherited
    local restricted = false
    for _, source in ipairs(sources or {}) do
        local copied, hasRestriction = CopyAllowlist(source.loadConditions and source.loadConditions[field], kind)
        if hasRestriction then
            restricted = true
            if inherited == nil then
                inherited = copied or {}
            else
                inherited = IntersectTruthyMaps(inherited, copied or {})
            end
        end
    end
    return inherited, restricted
end

local function SetAllowlistValue(target, field, kind, key, value)
    local normalizedKey = NormalizeAllowlistKey(kind, key)
    if not (type(target) == "table" and normalizedKey ~= nil) then return end

    if value then
        local loadConditions = EnsureLoadConditions(target)
        if type(loadConditions[field]) ~= "table" then
            loadConditions[field] = {}
        end
        loadConditions[field][normalizedKey] = true
        return
    end

    local loadConditions = target.loadConditions
    if type(loadConditions) == "table" and type(loadConditions[field]) == "table" then
        loadConditions[field][normalizedKey] = nil
        if not next(loadConditions[field]) then
            loadConditions[field] = nil
        end
    end
end

local function AddChoice(choices, byKey, key, label, meta)
    if key == nil or byKey[key] then return end
    byKey[key] = true
    local choice = {
        key = key,
        label = label or tostring(key),
    }
    if type(meta) == "table" then
        for metaKey, metaValue in pairs(meta) do
            choice[metaKey] = metaValue
        end
    end
    choices[#choices + 1] = choice
end

local function AddAllowlistKeysAsChoices(choices, byKey, map, kind, labelPrefix)
    local copied = CopyAllowlist(map, kind)
    for key in pairs(copied or {}) do
        AddChoice(choices, byKey, key, (labelPrefix or "") .. tostring(key))
    end
end

local function SortChoices(choices)
    table.sort(choices, function(a, b)
        return tostring(a.sortLabel or a.label or a.key) < tostring(b.sortLabel or b.label or b.key)
    end)
end

local MAX_CLASS_SCAN_ID = 20
local GetClassInfoByID = ST._GetClassInfoByID

local function GetClassChoiceByID(classID)
    classID = tonumber(classID)
    if not classID then return nil end
    local className, classFilename = GetClassInfoByID(classID)
    local classKey = NormalizeAllowlistKey("class", classFilename)
    if not classKey then return nil end
    return {
        key = classKey,
        label = className or classKey,
        classID = classID,
        classFilename = classKey,
    }
end

local function GetClassChoiceByFilename(classFilename)
    local classKey = NormalizeAllowlistKey("class", classFilename)
    if not classKey then return nil end
    for classID = 1, MAX_CLASS_SCAN_ID do
        local choice = GetClassChoiceByID(classID)
        if choice and choice.key == classKey then
            return choice
        end
    end
    return {
        key = classKey,
        label = classKey,
        classFilename = classKey,
    }
end

local function GetCurrentClassChoice()
    local classFilename = CooldownCompanion._playerClassFilename
    local classID = CooldownCompanion._playerClassID
    local className
    if classID then
        className = GetClassInfoByID(classID)
    end
    if (not classFilename or not className) and UnitClass then
        local unitClassName, unitClassFilename, unitClassID = UnitClass("player")
        className = className or unitClassName
        classFilename = classFilename or unitClassFilename
        classID = classID or unitClassID
    end
    local classKey = NormalizeAllowlistKey("class", classFilename)
    if not classKey then return nil end
    return {
        key = classKey,
        label = className or classKey,
        classID = classID,
        classFilename = classKey,
    }
end

local function WrapClassColoredText(text, classFilename)
    if classFilename and C_ClassColor then
        local classColor = C_ClassColor.GetClassColor(classFilename)
        if classColor and classColor.WrapTextInColorCode then
            return classColor:WrapTextInColorCode(text)
        end
    end
    return text
end

local function GetClassDisplayLabel(classChoice)
    if not classChoice then return nil end
    return WrapClassColoredText(classChoice.label or classChoice.key, classChoice.classFilename or classChoice.key)
end

local function SplitCharacterKey(charKey)
    if type(charKey) ~= "string" then return "", nil end
    local name, realm = charKey:match("^(.-)%s+%-%s+(.+)$")
    if name and name ~= "" then
        return name, realm
    end
    return charKey, nil
end

local function GetCharacterEligibilityInfo(charKey, fallbackInfo)
    local db = CooldownCompanion.db
    local info = charKey
        and db and db.global and db.global.characterInfo
        and db.global.characterInfo[charKey]
    if type(info) == "table" then
        return info
    end
    if type(fallbackInfo) == "table" and fallbackInfo.charKey == charKey then
        return fallbackInfo
    end

    local characters = CooldownCompanion.EnumerateActiveProfileCharacters
        and CooldownCompanion:EnumerateActiveProfileCharacters()
        or {}
    for _, characterInfo in ipairs(characters) do
        if characterInfo.charKey == charKey then
            return characterInfo
        end
    end
    return nil
end

local function BuildCharacterChoice(charKey, fallbackInfo)
    local info = GetCharacterEligibilityInfo(charKey, fallbackInfo)
    local name, realm = SplitCharacterKey(charKey)
    local classFilename = info and NormalizeAllowlistKey("class", info.classFilename)
    local label = WrapClassColoredText(name, classFilename)
    return {
        key = charKey,
        label = label,
        sortLabel = name,
        tooltipTitle = label,
        tooltipText = realm,
        classFilename = classFilename,
        classID = info and info.classID or nil,
    }
end

-- Row-grammar tooltip payload for a selected-eligibility row: a title line
-- plus the wrapped body line, matching what the pre-row InteractiveLabel put
-- on GameTooltip. Returns nil when there is nothing to say, so the row stays
-- tooltip-less exactly as before.
local function BuildEligibilityRowTooltip(title, text)
    if not (text and text ~= "") then return nil end
    return { title or "", { text, 1, 1, 1, true } }
end

-- The picker's "?" is a badge on the row's label, chained off the end of the
-- label text like every other row-grammar badge. The anchor args are a
-- placeholder - AnchorRowBadge re-points the button. The row widget doubles as
-- the cleanup owner: CreateInfoButton chains its OnRelease.
local function AddDropdownInfoButton(dropdownRow, tooltipLines)
    if not (dropdownRow and dropdownRow.frame and tooltipLines) then return end
    AnchorRowBadge(dropdownRow, CreateInfoButton(
        dropdownRow.frame, dropdownRow.frame, "LEFT", "LEFT", 0, 0, tooltipLines, dropdownRow))
end

local function GetEligibilitySubjectLabel(opts)
    return opts and opts.eligibilitySubjectLabel or "selection"
end

local function GetEligibilitySubjectPluralLabel(subjectLabel)
    return (subjectLabel or "selection") .. "s"
end

local function BuildCharacterEligibilityTooltip(subjectLabel)
    local subjectPluralLabel = GetEligibilitySubjectPluralLabel(subjectLabel)
    return {
        "Character",
        {"Choose which characters can use this " .. subjectLabel .. ".", 1, 1, 1, true},
        " ",
        {"Leave empty for no character limit.", 1, 1, 1, true},
        " ",
        {"Class-scoped " .. subjectPluralLabel .. " only show same-class characters.", 1, 1, 1, true},
    }
end

local function BuildClassEligibilityTooltip(subjectLabel)
    local subjectPluralLabel = GetEligibilitySubjectPluralLabel(subjectLabel)
    return {
        "Class",
        {"Global " .. subjectPluralLabel .. " can be limited to selected classes.", 1, 1, 1, true},
        " ",
        {"Leave empty to allow all classes.", 1, 1, 1, true},
        " ",
        {"Pick a class first to add its specializations.", 1, 1, 1, true},
    }
end

local function BuildSpecializationEligibilityTooltip(subjectLabel)
    return {
        "Specialization",
        {"Limit this " .. subjectLabel .. " to selected specializations.", 1, 1, 1, true},
        " ",
        {"Specializations come from eligible classes.", 1, 1, 1, true},
        " ",
        {"Leave empty to allow all specs for those classes.", 1, 1, 1, true},
    }
end

local function BuildHeroTalentEligibilityTooltip(subjectLabel)
    return {
        "Hero Talent",
        {"Limit this " .. subjectLabel .. " to specific hero talent trees.", 1, 1, 1, true},
        " ",
        {"Hero talents come from selected specializations.", 1, 1, 1, true},
        " ",
        {"Leave empty to allow any hero talent for that spec.", 1, 1, 1, true},
    }
end

-- includePreCheckedNote: panel and group scopes ship with Pet Battle and
-- Vehicle / Override UI already ticked; entry scopes start fully unchecked.
--
-- includeInheritedNote: scopes that can inherit rules from a wider scope. The
-- locked rows say who locked them, so all that is left to say is what a lock
-- costs you. Scopes that inherit from nothing leave it out.
local function BuildWhereToHideTooltip(subjectLabel, includePreCheckedNote, includeInheritedNote)
    local lines = {
        "Where To Hide It",
        {"Checked places hide this " .. subjectLabel .. " there. Leave everything unchecked to show it everywhere.", 1, 1, 1, true},
        " ",
        {"Rested Area means inns and cities. It can change while you play, with no loading screen.", 1, 1, 1, true},
        " ",
        {"Open World also covers scenarios.", 1, 1, 1, true},
    }
    if includePreCheckedNote then
        lines[#lines + 1] = " "
        lines[#lines + 1] = {"Pet Battle and Vehicle / Override UI start checked because most players want cooldowns hidden there.", 1, 1, 1, true}
    end
    if includeInheritedNote then
        lines[#lines + 1] = " "
        lines[#lines + 1] = {"Locked places cannot be unchecked here. You can only add more.", 1, 1, 1, true}
    end
    return lines
end

local function ResolveOwnerClassChoice(opts)
    if opts.ownerClassChoice then
        return opts.ownerClassChoice
    end

    local db = CooldownCompanion.db
    local charKey = opts.ownerCharKey
        or (type(opts.target) == "table" and opts.target.createdBy)
    local info = charKey
        and db and db.global and db.global.characterInfo
        and db.global.characterInfo[charKey]
    if type(info) == "table" then
        if info.classID then
            local choice = GetClassChoiceByID(info.classID)
            if choice then return choice end
        end
        if info.classFilename then
            local choice = GetClassChoiceByFilename(info.classFilename)
            if choice then return choice end
        end
    end

    return GetCurrentClassChoice()
end

local function CharacterChoiceMatchesScopeClass(choice, scopeClassKey, ownerCharKey)
    if not scopeClassKey then return true end
    if choice and ownerCharKey and choice.key == ownerCharKey then
        return true
    end
    local classKey = choice and NormalizeAllowlistKey("class", choice.classFilename)
    return classKey == scopeClassKey
end

local function AddKnownScopeClassCharacterChoices(choices, byKey, scopeClassKey, ownerCharKey)
    if not scopeClassKey then return end
    local db = CooldownCompanion.db
    local characterInfo = db and db.global and db.global.characterInfo
    if type(characterInfo) ~= "table" then return end

    for charKey, info in pairs(characterInfo) do
        if type(charKey) == "string" and charKey ~= "" then
            local choice = BuildCharacterChoice(charKey, info)
            choice.classFilename = choice.classFilename or NormalizeAllowlistKey("class", info and info.classFilename)
            choice.classID = choice.classID or (info and info.classID) or nil
            if CharacterChoiceMatchesScopeClass(choice, scopeClassKey, ownerCharKey) then
                AddChoice(choices, byKey, choice.key, choice.label, choice)
            end
        end
    end
end

local function BuildClassChoices(target, inheritedMap)
    local choices, byKey = {}, {}
    for classID = 1, MAX_CLASS_SCAN_ID do
        local choice = GetClassChoiceByID(classID)
        if choice then
            AddChoice(choices, byKey, choice.key, choice.label, choice)
        end
    end
    local localMap = target.loadConditions and target.loadConditions.classAllowlist
    AddAllowlistKeysAsChoices(choices, byKey, localMap, "class")
    AddAllowlistKeysAsChoices(choices, byKey, inheritedMap, "class")
    table.sort(choices, function(a, b)
        if a.classID and b.classID then
            return a.classID < b.classID
        end
        if a.classID then return true end
        if b.classID then return false end
        return tostring(a.label or a.key) < tostring(b.label or b.key)
    end)
    return choices
end

local function BuildCharacterChoices(target, inheritedMap, scopeClassKey, ownerCharKey)
    local choices, byKey = {}, {}
    local characters = CooldownCompanion.EnumerateActiveProfileCharacters
        and CooldownCompanion:EnumerateActiveProfileCharacters()
        or {}
    for _, info in ipairs(characters) do
        local choice = BuildCharacterChoice(info.charKey, info)
        choice.classFilename = choice.classFilename or info.classFilename
        choice.classID = choice.classID or info.classID
        if CharacterChoiceMatchesScopeClass(choice, scopeClassKey, ownerCharKey) then
            AddChoice(choices, byKey, choice.key, choice.label, choice)
        end
    end
    AddKnownScopeClassCharacterChoices(choices, byKey, scopeClassKey, ownerCharKey)
    local localMap = target.loadConditions and target.loadConditions.characterAllowlist
    local copiedLocal = CopyAllowlist(localMap, "character")
    for key in pairs(copiedLocal or {}) do
        local choice = BuildCharacterChoice(key)
        if CharacterChoiceMatchesScopeClass(choice, scopeClassKey, ownerCharKey) then
            AddChoice(choices, byKey, choice.key, choice.label, choice)
        end
    end
    local copiedInherited = CopyAllowlist(inheritedMap, "character")
    for key in pairs(copiedInherited or {}) do
        local choice = BuildCharacterChoice(key)
        if CharacterChoiceMatchesScopeClass(choice, scopeClassKey, ownerCharKey) then
            AddChoice(choices, byKey, choice.key, choice.label, choice)
        end
    end
    SortChoices(choices)
    return choices
end

-- The shared small remove X (RowWidgets CDC-RowIconBadge), as the row's
-- control widget; the label row releases it.
local function CreateEligibilityRemoveBadge(onRemove)
    local removeBadge = AceGUI:Create("CDC-RowIconBadge")
    removeBadge:SetCallback("OnClick", function(widget, event, button)
        if button == "LeftButton" and onRemove then
            onRemove()
        end
    end)
    return removeBadge
end

-- One selected character / class / spec / hero talent, as a row-grammar row
-- INDENTED under the picker that added it: the name on the left, the remove X
-- right-aligned in the control column (or the word "locked" where the
-- selection is inherited and cannot be removed here).
local function AddEligibilitySelectedRow(container, rowInfo, onRemove)
    local row = AddLabelRow(container, {
        label = rowInfo.label,
        indent = true,
        tooltip = BuildEligibilityRowTooltip(rowInfo.tooltipTitle or rowInfo.label, rowInfo.tooltipText),
    })

    if rowInfo.disabled then
        row:SetControlText("|cff888888locked|r")
    else
        row:SetControlWidget(CreateEligibilityRemoveBadge(onRemove))
    end
end

local function AddEligibilitySelectedRows(container, rows)
    for _, row in ipairs(rows or {}) do
        AddEligibilitySelectedRow(container, row, row.onRemove)
    end
end

-- Forward declarations: the selected-row builders sit below the pickers, but
-- each picker renders its own removable rows beneath it.
local AddActiveCharacterEligibilityRows
local BuildActiveClassSpecEligibilityRows

local function AddCharacterEligibilityControls(container, opts)
    local target = opts.target
    if type(target) ~= "table" then return end
    local subjectLabel = GetEligibilitySubjectLabel(opts)

    local inheritedMap, inheritedRestricted = GetInheritedAllowlist(opts.inheritedSources, "characterAllowlist", "character")
    local scopeClassChoice
    if opts.allowClassEligibility == false then
        scopeClassChoice = ResolveOwnerClassChoice(opts)
    end
    local choices = BuildCharacterChoices(target, inheritedMap, scopeClassChoice and scopeClassChoice.key or nil, opts.ownerCharKey)
    if #choices == 0 then return end

    if inheritedRestricted then
        local inheritedLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(inheritedLabel)
        inheritedLabel:SetText("|cff888888Parent eligibility limits which characters can be picked here.|r")
        inheritedLabel:SetFullWidth(true)
        container:AddChild(inheritedLabel)
    end

    local localMap = target.loadConditions and target.loadConditions.characterAllowlist
    local selectedByKey = {}
    local dropdownValues = {}
    local dropdownOrder = {}
    local dropdownSortLabels = {}

    for _, choice in ipairs(choices) do
        local key = choice.key
        local localSelected = type(localMap) == "table" and localMap[key] == true
        local outsideInherited = inheritedRestricted and not (inheritedMap and inheritedMap[key])
        if localSelected then
            selectedByKey[key] = true
        elseif not outsideInherited then
            dropdownValues[key] = choice.label
            dropdownSortLabels[key] = choice.sortLabel or choice.label
            dropdownOrder[#dropdownOrder + 1] = key
        end
    end

    table.sort(dropdownOrder, function(a, b)
        return tostring(dropdownSortLabels[a] or a) < tostring(dropdownSortLabels[b] or b)
    end)

    local picker = AddDropdownRow(container, {
        label = "Add Character",
        pulloutWidth = ELIGIBILITY_PULLOUT_WIDTH,
        list = dropdownValues,
        order = dropdownOrder,
        disabled = #dropdownOrder == 0,
        onChange = #dropdownOrder > 0 and function(value)
            if value ~= nil and not selectedByKey[value] then
                SetAllowlistValue(target, "characterAllowlist", "character", value, true)
                if opts.onChanged then opts.onChanged() end
            end
        end or nil,
    })
    AddDropdownInfoButton(picker, BuildCharacterEligibilityTooltip(subjectLabel))

    local rows = {}
    AddActiveCharacterEligibilityRows(rows, opts, choices, localMap, inheritedMap, inheritedRestricted)
    AddEligibilitySelectedRows(container, rows)
end

local function AddClassForSpecId(classChoices, classByKey, specId)
    if not (C_SpecializationInfo and C_SpecializationInfo.GetClassIDFromSpecID) then
        return
    end
    local classID = C_SpecializationInfo.GetClassIDFromSpecID(tonumber(specId))
    local choice = GetClassChoiceByID(classID)
    if choice and not classByKey[choice.key] then
        classByKey[choice.key] = true
        classChoices[#classChoices + 1] = choice
    end
end

local function AddClassesForSpecMap(classChoices, classByKey, specMap)
    local copied = CopyAllowlist(specMap, "spec")
    for specId in pairs(copied or {}) do
        AddClassForSpecId(classChoices, classByKey, specId)
    end
end

local function AddSpecsForClass(specChoices, seenSpecs, classChoice)
    local classID = classChoice and classChoice.classID
    if not (classID and C_SpecializationInfo and C_SpecializationInfo.GetNumSpecializationsForClassID) then
        return
    end

    local currentClass = GetCurrentClassChoice()
    local currentClassKey = currentClass and currentClass.key
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID) or 0
    for specIndex = 1, numSpecs do
        local specId, specName, _, specIcon = C_SpecializationInfo.GetSpecializationInfo(
            specIndex,
            false,
            false,
            nil,
            nil,
            nil,
            classID
        )
        if specId and not seenSpecs[specId] then
            seenSpecs[specId] = true
            specChoices[#specChoices + 1] = {
                id = specId,
                name = specName or ("Spec " .. tostring(specId)),
                label = specName or ("Spec " .. tostring(specId)),
                icon = specIcon,
                classID = classID,
                classKey = classChoice.key,
                classLabel = classChoice.label,
                isCurrentClass = classChoice.key == currentClassKey,
            }
        end
    end
end

local function BuildEligibilitySpecChoices(opts)
    opts = opts or {}
    local target = opts.target
    if type(target) ~= "table" then return {} end

    local classChoices = {}
    local classByKey = {}

    if opts.allowClassEligibility then
        local inheritedMap, inheritedRestricted = GetInheritedAllowlist(opts.inheritedSources, "classAllowlist", "class")
        local localMap = CopyAllowlist(target.loadConditions and target.loadConditions.classAllowlist, "class")
        local seedMap = localMap and next(localMap) and localMap or nil
        if not seedMap and inheritedRestricted then
            seedMap = inheritedMap
        end

        for classKey in pairs(seedMap or {}) do
            local choice = GetClassChoiceByFilename(classKey)
            if choice and not classByKey[choice.key] then
                classByKey[choice.key] = true
                classChoices[#classChoices + 1] = choice
            end
        end

        AddClassesForSpecMap(classChoices, classByKey, target.specs)
        AddClassesForSpecMap(classChoices, classByKey, target.loadConditions and target.loadConditions.specAllowlist)
        AddClassesForSpecMap(classChoices, classByKey, opts.choiceSpecMap or opts.effectiveSpecs)
    else
        local choice = ResolveOwnerClassChoice(opts)
        if choice then
            classByKey[choice.key] = true
            classChoices[#classChoices + 1] = choice
        end
    end

    table.sort(classChoices, function(a, b)
        if a.classID and b.classID then
            return a.classID < b.classID
        end
        if a.classID then return true end
        if b.classID then return false end
        return tostring(a.label or a.key) < tostring(b.label or b.key)
    end)

    local specs = {}
    local seenSpecs = {}
    for _, classChoice in ipairs(classChoices) do
        AddSpecsForClass(specs, seenSpecs, classChoice)
    end

    local classCount = #classChoices
    for _, spec in ipairs(specs) do
        if opts.allowClassEligibility and classCount > 1 then
            spec.label = (spec.classLabel or spec.classKey or "Class") .. ": " .. spec.name
        end
    end
    return specs
end

local function GetSpecSelectionMap(target, useSpecAllowlist)
    if type(target) ~= "table" then return nil end
    if useSpecAllowlist then
        return target.loadConditions and target.loadConditions.specAllowlist
    end
    local specs = CopyAllowlist(target.specs, "spec")
    local loadConditionSpecs = CopyAllowlist(
        target.loadConditions and target.loadConditions.specAllowlist,
        "spec"
    )
    if not loadConditionSpecs then
        return specs
    end
    specs = specs or {}
    for specId in pairs(loadConditionSpecs) do
        specs[specId] = true
    end
    return next(specs) and specs or nil
end

local function SetSpecEligibilityValue(target, specId, value, useSpecAllowlist)
    if useSpecAllowlist then
        SetSpecAllowlistValue(target, specId, value)
    else
        SetSpecFilterValue(target, specId, value)
    end
end

local function BuildSpecChoiceIndex(specChoices)
    local bySpecId = {}
    local byClassKey = {}
    for _, specInfo in ipairs(specChoices or {}) do
        if specInfo.id then
            bySpecId[specInfo.id] = specInfo
            local classKey = specInfo.classKey
            if classKey then
                byClassKey[classKey] = byClassKey[classKey] or {}
                byClassKey[classKey][#byClassKey[classKey] + 1] = specInfo
            end
        end
    end
    return bySpecId, byClassKey
end

local function BuildHeroTalentChoicesForSpecs(specChoices, selectedSpecMap, configID)
    local choices = {}
    local bySubTreeID = {}

    for _, specInfo in ipairs(specChoices or {}) do
        local specId = specInfo.id
        if specId and selectedSpecMap and selectedSpecMap[specId] then
            local subTreeIDs, subTreeConfigID = GetSpecHeroSubTreeIDs(specId, configID)
            for _, subTreeID in ipairs(subTreeIDs or {}) do
                local subTreeInfo = subTreeConfigID and C_Traits and C_Traits.GetSubTreeInfo
                    and C_Traits.GetSubTreeInfo(subTreeConfigID, subTreeID) or nil
                local heroName = subTreeInfo and subTreeInfo.name or ("Hero " .. tostring(subTreeID))
                local heroChoice = {
                    id = subTreeID,
                    label = heroName,
                    sortLabel = heroName,
                    specId = specId,
                    specLabel = specInfo.name,
                    classKey = specInfo.classKey,
                    classLabel = specInfo.classLabel,
                    iconAtlas = subTreeInfo and subTreeInfo.iconElementID or nil,
                }
                choices[#choices + 1] = heroChoice
                bySubTreeID[subTreeID] = heroChoice
            end
        end
    end

    table.sort(choices, function(a, b)
        local aClass = tostring(a.classLabel or a.classKey or "")
        local bClass = tostring(b.classLabel or b.classKey or "")
        if aClass ~= bClass then return aClass < bClass end
        local aSpec = tostring(a.specLabel or a.specId or "")
        local bSpec = tostring(b.specLabel or b.specId or "")
        if aSpec ~= bSpec then return aSpec < bSpec end
        return tostring(a.sortLabel or a.label or a.id) < tostring(b.sortLabel or b.label or b.id)
    end)

    return choices, bySubTreeID
end

-- Every specInfo comes from AddSpecsForClass, which stamps classKey and
-- classLabel from the same class lookup.
local function FormatEligibilitySpecLabel(specInfo, includeClass)
    if not specInfo then return "" end
    local specLabel = WrapClassColoredText(specInfo.name or specInfo.label or tostring(specInfo.id), specInfo.classKey)
    if includeClass and specInfo.classLabel then
        return WrapClassColoredText(specInfo.classLabel, specInfo.classKey) .. ": " .. specLabel
    end
    return specLabel
end

local function FormatSpecIconPrefix(specInfo)
    local icon = specInfo and specInfo.icon
    if not icon then return "" end
    return ("|T%s:14:14:0:0:64:64:5:59:5:59|t "):format(tostring(icon))
end

local function FormatSpecDropdownLabel(specInfo)
    local label = specInfo and specInfo.label or ""
    if specInfo and specInfo.classKey then
        label = WrapClassColoredText(label, specInfo.classKey)
    end
    return FormatSpecIconPrefix(specInfo) .. label
end

local function FormatEligibilitySpecRowLabel(specInfo, includeClass)
    return FormatSpecIconPrefix(specInfo) .. FormatEligibilitySpecLabel(specInfo, includeClass)
end

local function FormatHeroTalentIconPrefix(heroInfo)
    local atlas = heroInfo and heroInfo.iconAtlas
    if not atlas then return "" end
    return ("|A:%s:14:14|a "):format(tostring(atlas))
end

local function FormatEligibilityHeroName(heroInfo)
    return FormatHeroTalentIconPrefix(heroInfo) .. (heroInfo and (heroInfo.label or tostring(heroInfo.id)) or "")
end

local function FormatEligibilityHeroLabel(heroInfo, specInfo, includeClass)
    local specLabel = FormatEligibilitySpecLabel(specInfo, includeClass)
    return specLabel .. " - " .. FormatEligibilityHeroName(heroInfo)
end

local function FormatEligibilityHeroChoiceLabel(heroInfo, specInfo, includeClass)
    return FormatSpecIconPrefix(specInfo) .. FormatEligibilityHeroLabel(heroInfo, specInfo, includeClass)
end

local function AddClassSpecEligibilityControls(container, opts)
    opts = opts or {}
    local target = opts.target
    if type(target) ~= "table" then return end
    local subjectLabel = GetEligibilitySubjectLabel(opts)

    -- Every picker and its removable rows read one resolved state, built
    -- before any widget. Neither consumer may mutate these tables.
    local allowClassEligibility = opts.allowClassEligibility == true
    local scopeClassChoice
    if not allowClassEligibility then
        scopeClassChoice = ResolveOwnerClassChoice(opts)
    end

    local inheritedClassMap, inheritedClassRestricted, classChoices, localClassMap
    if allowClassEligibility then
        inheritedClassMap, inheritedClassRestricted = GetInheritedAllowlist(opts.inheritedSources, "classAllowlist", "class")
        classChoices = BuildClassChoices(target, inheritedClassMap)
        localClassMap = target.loadConditions and target.loadConditions.classAllowlist
    end

    local useSpecAllowlist = opts.useSpecAllowlist == true
    local selectedSpecMap = GetSpecSelectionMap(target, useSpecAllowlist)
    local allowedSpecMap = opts.allowedSpecMap
    local allowedSpecRestricted = opts.allowedSpecRestricted == true
    local specChoices = BuildEligibilitySpecChoices({
        target = target,
        inheritedSources = opts.inheritedSources,
        allowClassEligibility = allowClassEligibility,
        ownerClassChoice = scopeClassChoice,
        ownerCharKey = opts.ownerCharKey,
        effectiveSpecs = opts.effectiveSpecs,
        choiceSpecMap = opts.choiceSpecMap,
    })
    local specById, specsByClassKey = BuildSpecChoiceIndex(specChoices)

    local configID = C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID()
    local heroTalentsSource = opts.useHeroTalentsSource and opts.heroTalentsSource or target.heroTalents
    if type(heroTalentsSource) ~= "table" then
        heroTalentsSource = nil
    end
    local heroChoices, heroById = BuildHeroTalentChoicesForSpecs(specChoices, selectedSpecMap, configID)

    local selectedClassRows, selectedSpecRows, selectedHeroRows = BuildActiveClassSpecEligibilityRows(opts, {
        allowClassEligibility = allowClassEligibility,
        classChoices = classChoices,
        localClassMap = localClassMap,
        useSpecAllowlist = useSpecAllowlist,
        selectedSpecMap = selectedSpecMap,
        allowedSpecMap = allowedSpecMap,
        allowedSpecRestricted = allowedSpecRestricted,
        specChoices = specChoices,
        specsByClassKey = specsByClassKey,
        heroTalentsSource = heroTalentsSource,
        heroById = heroById,
    })

    if allowClassEligibility then
        if inheritedClassRestricted then
            local inheritedLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(inheritedLabel)
            inheritedLabel:SetText("|cff888888Parent eligibility limits which classes can be picked here.|r")
            inheritedLabel:SetFullWidth(true)
            container:AddChild(inheritedLabel)
        end

        local classValues = {}
        local classOrder = {}
        local classSortLabels = {}
        for _, choice in ipairs(classChoices) do
            local key = choice.key
            local localSelected = type(localClassMap) == "table" and localClassMap[key] == true
            local outsideInherited = inheritedClassRestricted and not (inheritedClassMap and inheritedClassMap[key])
            if not localSelected and not outsideInherited then
                classValues[key] = GetClassDisplayLabel(choice) or choice.label
                classSortLabels[key] = choice.label or key
                classOrder[#classOrder + 1] = key
            end
        end
        table.sort(classOrder, function(a, b)
            return tostring(classSortLabels[a] or a) < tostring(classSortLabels[b] or b)
        end)

        local classPicker = AddDropdownRow(container, {
            label = "Add Class",
            pulloutWidth = ELIGIBILITY_PULLOUT_WIDTH,
            list = classValues,
            order = classOrder,
            disabled = #classOrder == 0,
            onChange = #classOrder > 0 and function(value)
                SetAllowlistValue(target, "classAllowlist", "class", value, true)
                if opts.onChanged then opts.onChanged() end
            end or nil,
        })
        AddDropdownInfoButton(classPicker, BuildClassEligibilityTooltip(subjectLabel))
        AddEligibilitySelectedRows(container, selectedClassRows)
    end

    local specValues = {}
    local specOrder = {}
    local specSortLabels = {}
    for _, specInfo in ipairs(specChoices) do
        local specId = specInfo.id
        local localSelected = type(selectedSpecMap) == "table" and selectedSpecMap[specId] == true
        local outsideAllowed = allowedSpecRestricted and not (allowedSpecMap and allowedSpecMap[specId])
        if specId and not localSelected and not outsideAllowed then
            specValues[specId] = FormatSpecDropdownLabel(specInfo)
            specSortLabels[specId] = (specInfo.classLabel or "") .. (specInfo.name or specInfo.label or tostring(specId))
            specOrder[#specOrder + 1] = specId
        end
    end
    table.sort(specOrder, function(a, b)
        return tostring(specSortLabels[a] or a) < tostring(specSortLabels[b] or b)
    end)

    if #specChoices > 0 then
        local specPicker = AddDropdownRow(container, {
            label = "Add Specialization",
            pulloutWidth = ELIGIBILITY_PULLOUT_WIDTH,
            list = specValues,
            order = specOrder,
            disabled = #specOrder == 0,
            onChange = #specOrder > 0 and function(value)
                SetSpecEligibilityValue(target, value, true, useSpecAllowlist)
                if opts.onChanged then opts.onChanged() end
            end or nil,
        })
        AddDropdownInfoButton(specPicker, BuildSpecializationEligibilityTooltip(subjectLabel))
        AddEligibilitySelectedRows(container, selectedSpecRows)
    end

    local mutableHeroTalents = opts.disableHeroTalents ~= true
    local heroValues = {}
    local heroOrder = {}
    local heroSortLabels = {}
    if mutableHeroTalents then
        for _, heroInfo in ipairs(heroChoices) do
            local selected = type(heroTalentsSource) == "table" and heroTalentsSource[heroInfo.id] == true
            if not selected then
                local specInfo = specById[heroInfo.specId]
                heroValues[heroInfo.id] = FormatEligibilityHeroChoiceLabel(heroInfo, specInfo, allowClassEligibility)
                heroSortLabels[heroInfo.id] = (heroInfo.classLabel or "") .. (heroInfo.specLabel or "") .. (heroInfo.label or "")
                heroOrder[#heroOrder + 1] = heroInfo.id
            end
        end
    end
    table.sort(heroOrder, function(a, b)
        return tostring(heroSortLabels[a] or a) < tostring(heroSortLabels[b] or b)
    end)

    if #heroChoices > 0 and mutableHeroTalents then
        local heroPicker = AddDropdownRow(container, {
            label = "Add Hero Talent",
            pulloutWidth = ELIGIBILITY_PULLOUT_WIDTH,
            list = heroValues,
            order = heroOrder,
            disabled = #heroOrder == 0,
            onChange = #heroOrder > 0 and function(value)
                SetHeroTalentValue(target, value, true)
                if opts.onChanged then opts.onChanged() end
            end or nil,
        })
        AddDropdownInfoButton(heroPicker, BuildHeroTalentEligibilityTooltip(subjectLabel))
    elseif opts.disableHeroTalents and type(heroTalentsSource) == "table" and next(heroTalentsSource) then
        local inheritedLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(inheritedLabel)
        inheritedLabel:SetText("|cff888888Hero talent eligibility is inherited here.|r")
        inheritedLabel:SetFullWidth(true)
        container:AddChild(inheritedLabel)
    end
    AddEligibilitySelectedRows(container, selectedHeroRows)

end

-- The picker's own resolved state comes in, so nothing is computed twice.
function AddActiveCharacterEligibilityRows(rows, opts, choices, localMap, inheritedMap, inheritedRestricted)
    local target = opts.target
    local characterRows = {}

    for _, choice in ipairs(choices) do
        local key = choice.key
        if type(localMap) == "table" and localMap[key] == true then
            local outsideInherited = inheritedRestricted and not (inheritedMap and inheritedMap[key])
            characterRows[#characterRows + 1] = {
                key = key,
                label = outsideInherited and (choice.label .. " |cff888888(unavailable from parent)|r") or choice.label,
                tooltipTitle = choice.tooltipTitle,
                tooltipText = choice.tooltipText,
                sortLabel = choice.sortLabel,
                onRemove = function()
                    SetAllowlistValue(target, "characterAllowlist", "character", key, false)
                    if opts.onChanged then opts.onChanged() end
                end,
            }
        end
    end

    SortChoices(characterRows)
    for _, row in ipairs(characterRows) do
        rows[#rows + 1] = row
    end
end

-- Returns the class, specialization and hero talent rows as three lists so the
-- pickers can each carry their own selections. A spec with hero talents chosen
-- contributes hero rows instead of a spec row: the hero row already names it.
-- `state` is AddClassSpecEligibilityControls' resolved picker state.
function BuildActiveClassSpecEligibilityRows(opts, state)
    local target = opts.target
    local allowClassEligibility = state.allowClassEligibility
    local classChoices = state.classChoices
    local localClassMap = state.localClassMap
    local useSpecAllowlist = state.useSpecAllowlist
    local selectedSpecMap = state.selectedSpecMap
    local allowedSpecMap = state.allowedSpecMap
    local allowedSpecRestricted = state.allowedSpecRestricted
    local specChoices = state.specChoices
    local specsByClassKey = state.specsByClassKey
    local heroTalentsSource = state.heroTalentsSource
    local heroById = state.heroById

    local selectedHeroBySpec = {}
    for subTreeID in pairs(heroTalentsSource or {}) do
        local heroInfo = heroById[subTreeID]
        if heroInfo then
            selectedHeroBySpec[heroInfo.specId] = selectedHeroBySpec[heroInfo.specId] or {}
            selectedHeroBySpec[heroInfo.specId][#selectedHeroBySpec[heroInfo.specId] + 1] = heroInfo
        end
    end

    local classRows = {}
    if allowClassEligibility then
        for _, classChoice in ipairs(classChoices) do
            local classKey = classChoice.key
            local classSelected = type(localClassMap) == "table" and localClassMap[classKey] == true
            if classSelected then
                local classSpecs = specsByClassKey[classKey] or {}
                local selectedSpecs = {}
                for _, specInfo in ipairs(classSpecs) do
                    if type(selectedSpecMap) == "table" and selectedSpecMap[specInfo.id] == true then
                        selectedSpecs[#selectedSpecs + 1] = specInfo
                    end
                end
                if #selectedSpecs == 0 then
                    classRows[#classRows + 1] = {
                        label = GetClassDisplayLabel(classChoice) or classChoice.label,
                        sortLabel = classChoice.label or classKey,
                        onRemove = function()
                            SetAllowlistValue(target, "classAllowlist", "class", classKey, false)
                            for _, specInfo in ipairs(classSpecs) do
                                SetSpecEligibilityValue(target, specInfo.id, false, useSpecAllowlist)
                                if CooldownCompanion.CleanHeroTalentsForSpec then
                                    CooldownCompanion:CleanHeroTalentsForSpec(target, specInfo.id)
                                end
                            end
                            if opts.onChanged then opts.onChanged() end
                        end,
                    }
                end
            end
        end
    end
    SortChoices(classRows)

    local specRows = {}
    local heroRows = {}
    for _, specInfo in ipairs(specChoices) do
        local specId = specInfo.id
        if type(selectedSpecMap) == "table" and selectedSpecMap[specId] == true then
            local specHeroes = selectedHeroBySpec[specId]
            if specHeroes and #specHeroes > 0 then
                table.sort(specHeroes, function(a, b)
                    return tostring(a.label or a.id) < tostring(b.label or b.id)
                end)
                for _, heroInfo in ipairs(specHeroes) do
                    heroRows[#heroRows + 1] = {
                        label = FormatEligibilityHeroChoiceLabel(heroInfo, specInfo, allowClassEligibility),
                        sortLabel = (specInfo.classLabel or "") .. (specInfo.name or "") .. (heroInfo.label or ""),
                        disabled = opts.disableHeroTalents == true,
                        onRemove = function()
                            SetHeroTalentValue(target, heroInfo.id, false)
                            if opts.onChanged then opts.onChanged() end
                        end,
                    }
                end
            else
                local outsideAllowed = allowedSpecRestricted and not (allowedSpecMap and allowedSpecMap[specId])
                specRows[#specRows + 1] = {
                    label = FormatEligibilitySpecRowLabel(specInfo, allowClassEligibility)
                        .. (outsideAllowed and " |cff888888(unavailable from parent)|r" or ""),
                    sortLabel = (specInfo.classLabel or "") .. (specInfo.name or specInfo.label or tostring(specId)),
                    onRemove = function()
                        SetSpecEligibilityValue(target, specId, false, useSpecAllowlist)
                        if CooldownCompanion.CleanHeroTalentsForSpec then
                            CooldownCompanion:CleanHeroTalentsForSpec(target, specId)
                        end
                        if opts.onChanged then opts.onChanged() end
                    end,
                }
            end
        end
    end

    SortChoices(specRows)
    SortChoices(heroRows)
    return classRows, specRows, heroRows
end

------------------------------------------------------------------------
-- BATCH HELPERS (multi-select visibility)
------------------------------------------------------------------------

-- Returns true if all selected have field truthy, false if all falsy, nil if mixed
local function GetBatchFieldValue(group, field)
    local anyTrue, anyFalse = false, false
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd then
            if bd[field] then anyTrue = true else anyFalse = true end
        end
    end
    if anyTrue and anyFalse then return nil end  -- mixed
    return anyTrue  -- true if all true, false if all false
end

-- A condition list's canonical form. Order does not matter: the talent
-- picker saves its picks in hash order.
local function ConditionListKey(list)
    local keys = {}
    for i, condition in ipairs(list) do
        keys[i] = ST.Fingerprint(condition)
    end
    table.sort(keys)
    return table.concat(keys, "|")
end

-- Like GetBatchFieldValue, but entries holding different condition lists
-- also read as mixed, so one entry's list never displays as shared.
local function GetBatchTalentConditionsValue(group)
    local hasValue = GetBatchFieldValue(group, "talentConditions")
    if not hasValue then return hasValue end
    local first, firstKey
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        local list = bd and bd.talentConditions
        if list then
            if not first then
                first = list
            elseif #list ~= #first then
                return nil
            else
                firstKey = firstKey or ConditionListKey(first)
                if ConditionListKey(list) ~= firstKey then
                    return nil
                end
            end
        end
    end
    return true
end

-- Scoped version: only reads from buttons matching filterFn(bd) → true.
-- Ensures read scope matches write scope for filtered apply functions.
local function GetBatchFieldValueFiltered(group, field, filterFn)
    local anyTrue, anyFalse = false, false
    local anyMatched = false
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and filterFn(bd) then
            anyMatched = true
            if bd[field] then anyTrue = true else anyFalse = true end
        end
    end
    if not anyMatched then return false end
    if anyTrue and anyFalse then return nil end
    return anyTrue
end

-- Filter predicates (matching the write scopes of ApplyTo* functions)
local function FilterNonEquippable(bd)
    return bd.type == "item" and not CooldownCompanion.IsItemEquippable(bd)
end
local function FilterEquippable(bd)
    return bd.type == "item" and CooldownCompanion.IsItemEquippable(bd)
end
local function FilterChargeCapable(bd)
    if bd.rotationAssistant then return true end
    if HasItemFallbacks(bd) then return false end
    if not UsesChargeBehavior(bd) then return false end
    if bd.type == "spell" then return true end
    if bd.type == "item" and not CooldownCompanion.IsItemEquippable(bd) then return true end
    return false
end
-- Hide Cooldown While Charges Remain hides an icon's swipe; bars draw none.
local function FilterChargeSwipe(group, bd)
    return FilterChargeCapable(bd) and ST.GetEntryPresentation(group, bd) ~= "bars"
end
local function FilterChargeSpell(bd)
    if bd.rotationAssistant then return true end
    if HasItemFallbacks(bd) then return false end
    return bd.type == "spell" and bd.hasCharges == true and UsesChargeBehavior(bd)
end
local function FilterChargeSpellNotOnCooldown(bd)
    return FilterChargeSpell(bd) and bd.hideWhileNotOnCooldown == true
end

-- Returns true if all selected buttons have field truthy
local function AllSelectedAre(group, field)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and not bd[field] then return false end
    end
    return true
end

-- Returns true if a button has no real cooldown (GCD-only spell)
local function IsNoCooldownSpell(bd)
    if bd and bd.rotationAssistant then return false end
    if not bd or bd.type ~= "spell" or bd.isPassive or UsesChargeBehavior(bd) then return false end
    return IsNoCooldownSpellID(bd.id)
end

-- Returns true if all selected buttons are no-cooldown spells
local function AllSelectedNoCooldown(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and not IsNoCooldownSpell(bd) then return false end
    end
    return true
end

-- Returns true if a button would never be affected by Unusable Visual.
-- Items can always be unusable (level, class, etc.), so only spells are checked.
-- A spell is "never unusable" only if it has no resource cost AND no usage
-- requirements (form/stance/etc). Spells like Mangle (zero cost, requires
-- Bear Form) correctly return false here — their toggle remains visible.
local WHIRLING_DRAGON_PUNCH_SPELL_ID = 152175
local HasCastCountText = CooldownCompanion.HasCastCountText

local function IsNeverUnusableButton(bd)
    if bd and bd.rotationAssistant then return false end
    if not bd or bd.type ~= "spell" then return false end
    -- An Aura entry is present or not; castability never applies to it, the
    -- rule Unusable Visual already follows (Tracking.lua).
    if bd.addedAs == "aura" then return true end
    if bd.id == WHIRLING_DRAGON_PUNCH_SPELL_ID then return false end
    if HasCastCountText(bd) then return false end
    local costs = C_Spell.GetSpellPowerCost(bd.id)
    if costs and #costs > 0 then return false end
    return not HasUsageRequirement(bd.id)
end

-- Returns true if all selected buttons would never be affected by Unusable Visual.
local function AllSelectedNeverUnusable(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and not IsNeverUnusableButton(bd) then return false end
    end
    return true
end

-- Returns true if any selected item button is equippable
local function AnySelectedEquippable(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and bd.type == "item" and CooldownCompanion.IsItemEquippable(bd) then return true end
    end
    return false
end

-- Returns true if any selected item button is non-equippable
local function AnySelectedNonEquippable(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and bd.type == "item" and not CooldownCompanion.IsItemEquippable(bd) then return true end
    end
    return false
end

local function AnySelectedHasItemFallbacks(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and HasItemFallbacks(bd) then return true end
    end
    return false
end

-- Returns true if any selected button is charge-capable (spells or non-equippable items with charges)
local function AnySelectedChargeCapable(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and FilterChargeCapable(bd) then return true end
    end
    return false
end

local function AllSelectedChargeCapable(group)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and not FilterChargeCapable(bd) then return false end
    end
    return true
end

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG (single-entry Show & Hide Rules)
------------------------------------------------------------------------

local function GetEntryVisibilityFinderState(context)
    if context._ccEntryVisibilityFinderState then
        return context._ccEntryVisibilityFinderState
    end
    local group, buttonData = context.group, context.buttonData
    if not (group and buttonData) then return nil end

    local isAuraPanel = CooldownCompanion:IsAuraPanel(group)
    local state = {
        group = group,
        buttonData = buttonData,
        visible = not isAuraPanel,
    }
    context._ccEntryVisibilityFinderState = state
    if isAuraPanel then return state end

    local isItem = buttonData.type == "item"
    local passive = buttonData.isPassive == true
    local noCooldown = IsNoCooldownSpell(buttonData)
    local neverUnusable = IsNeverUnusableButton(buttonData)
    local auraEntry = buttonData.type == "spell"
        and (buttonData.auraTracking or buttonData.addedAs == "aura")
        and not ST.IsAuraSectionEntry(group, buttonData)
    local displayMode = group.displayMode or "icons"
    local hasFallbacks = HasItemFallbacks(buttonData)
    local chargeCapable = FilterChargeCapable(buttonData)
    local nonEquippableItem = isItem and not CooldownCompanion.IsItemEquippable(buttonData)

    state.auraPair = auraEntry and (displayMode == "icons" or displayMode == "bars")
    state.cooldownFamily = not passive and not noCooldown
    state.unusableFamily = not passive and not neverUnusable
    state.noProcFamily = not passive and buttonData.type == "spell"
        and buttonData.addedAs ~= "aura" and not buttonData.isPassiveCooldown
    state.chargeFamily = chargeCapable
    state.chargeSwipeFamily = FilterChargeSwipe(group, buttonData)
    state.stackFamily = nonEquippableItem and (hasFallbacks or not UsesChargeBehavior(buttonData))
    state.fallbackItemUses = state.stackFamily and hasFallbacks
    state.equipFamily = isItem and CooldownCompanion.IsItemEquippable(buttonData)
    return state
end

local function EntryVisibilityApplies(predicate)
    return function(context)
        local state = GetEntryVisibilityFinderState(context)
        return state and state.visible and predicate(state) and true or false
    end
end

local entryVisibilitySettings = ST._DefineSettingRoute({
    idPrefix = "entry.visibility.show_hide",
    scope = "entry",
    rowScope = "primary",
    tab = "loadconditions",
    tabLabel = "Visibility",
    section = "show_hide_rules",
    sectionLabel = "Show & Hide Rules",
    collapseKeys = function(context)
        return tostring(context.groupId) .. "_" .. tostring(context.buttonIndex) .. "_visibility"
    end,
}):Settings({
    -- One descriptor per state dropdown. The aliases carry the retired
    -- checkbox labels so a search typed from memory of the old rows still
    -- lands on the row that replaced them.
    auraInactive = {
        label = "Aura Visibility",
        aliases = { "while aura inactive", "show only while aura active", "show while active", "show while inactive", "dim while aura inactive", "hide aura inactive", "aura inactive alpha" },
        applies = EntryVisibilityApplies(function(state) return state.auraPair end),
    },
    auraPandemic = {
        label = "Also During Pandemic",
        aliases = { "show while inactive or pandemic", "pandemic window", "refresh window" },
        -- The row's own eligibility (PandemicEligible): the runtime's
        -- presence predicate, inside the aura pair's panels.
        applies = EntryVisibilityApplies(function(state)
            return state.auraPair and CooldownCompanion:CanUseMissingPicturePandemic(state.buttonData)
        end),
    },
    cooldownVisibility = {
        label = "Cooldown Visibility",
        aliases = {
            "hide while on cooldown", "hide while not on cooldown", "hide while ready", "hide available",
            "dim instead of hide", "cooldown dim", "only show at zero charges", "zero charges only",
        },
        applies = EntryVisibilityApplies(function(state) return state.cooldownFamily end),
    },
    unusable = {
        label = "While Unusable",
        aliases = { "hide while unusable", "unusable dim" },
        applies = EntryVisibilityApplies(function(state) return state.unusableFamily end),
    },
    noProc = {
        label = "While No Proc",
        aliases = { "hide while no proc", "proc visibility", "no proc dim" },
        applies = EntryVisibilityApplies(function(state) return state.noProcFamily end),
    },
    zeroCharges = {
        label = "At Zero Charges",
        aliases = { "hide while at zero charges", "desaturate while at zero charges", "zero charges dim" },
        applies = EntryVisibilityApplies(function(state) return state.chargeFamily end),
    },
    chargeCooldown = {
        label = "Hide Cooldown While Charges Remain",
        aliases = { "charge cooldown swipe" },
        applies = EntryVisibilityApplies(function(state) return state.chargeSwipeFamily end),
    },
    zeroStacks = {
        label = "At Zero Stacks",
        aliases = { "hide while at zero stacks", "desaturate while at zero stacks", "zero stacks dim" },
        applies = EntryVisibilityApplies(function(state)
            return state.stackFamily and not state.fallbackItemUses
        end),
    },
    noUses = {
        label = "With No Uses Available",
        aliases = { "hide while no uses available", "desaturate while no uses available", "fallback item uses", "no uses dim" },
        applies = EntryVisibilityApplies(function(state)
            return state.stackFamily and state.fallbackItemUses
        end),
    },
    equipped = {
        label = "While Not Equipped",
        aliases = { "hide while not equipped", "not equipped dim" },
        applies = EntryVisibilityApplies(function(state) return state.equipFamily end),
    },
})

------------------------------------------------------------------------
-- Batch checkbox helper: set up tri-state display and click semantics
------------------------------------------------------------------------
local function SetupBatchCheckbox(cb, batchValue)
    cb:SetTriState(true)
    cb:SetValue(batchValue)
    -- Store pre-click value so callback can distinguish mixed→click from true→click
    cb._batchPrev = batchValue
end

-- Remap AceGUI tri-state cycling for batch UX:
--   mixed(nil) click → all ON, ON(true) click → all OFF, OFF(false) click → all ON
local function RemapBatchValue(widget, val)
    -- AceGUI tri-state cycles: true→nil, nil→false, false→true
    if widget._batchPrev == nil and val == false then
        -- Was mixed, AceGUI cycled nil→false. We want → ON.
        return true
    elseif val == nil then
        -- Was true, AceGUI cycled true→nil. We want → OFF.
        return false
    end
    -- Was false, AceGUI cycled false→true. Keep → ON.
    return val and true or false
end

------------------------------------------------------------------------
-- Talent condition display helpers (shared with the Live Preview)
------------------------------------------------------------------------

local function ResolveConditionClassName(cond)
    if not cond then
        return nil
    end

    if cond.className and cond.className ~= "" then
        return cond.className
    end

    if cond.classID then
        local name = GetClassInfoByID(cond.classID)
        return name or ("Class " .. cond.classID)
    end

    return nil
end

local function ResolveConditionSpecName(cond)
    if not cond then
        return nil
    end

    if cond.specName and cond.specName ~= "" then
        return cond.specName
    end

    if cond.specID then
        local _, name = GetSpecializationInfoForSpecID(cond.specID)
        return name or ("Spec " .. cond.specID)
    end

    return nil
end

local function ResolveConditionHeroName(cond)
    if not cond then
        return nil
    end

    if cond.heroName and cond.heroName ~= "" then
        return cond.heroName
    end

    if cond.heroSubTreeID then
        return "Hero " .. cond.heroSubTreeID
    end

    return nil
end

local IsHeroSpecProxyCondition = ST._IsHeroSpecProxyCondition

local function GetConditionContextSuffix(cond)
    local parts = {}
    local className = ResolveConditionClassName(cond)
    local specName = ResolveConditionSpecName(cond)
    local heroName = ResolveConditionHeroName(cond)
    local conditionName = cond and cond.name or nil

    if className then
        parts[#parts + 1] = className
    end
    if specName then
        parts[#parts + 1] = specName
    end
    if heroName and heroName ~= conditionName then
        parts[#parts + 1] = heroName
    end

    if #parts == 0 then
        return ""
    end

    return " [" .. table.concat(parts, ", ") .. "]"
end

local function GetConditionListContextSuffix(list)
    local scope = {}

    for _, cond in ipairs(list or {}) do
        if not scope.className then
            scope.className = ResolveConditionClassName(cond)
        end
        if not scope.specName then
            scope.specName = ResolveConditionSpecName(cond)
        end
        if not scope.heroName then
            scope.heroName = ResolveConditionHeroName(cond)
        end
    end

    if not scope.className and not scope.specName and not scope.heroName then
        return ""
    end

    local parts = {}
    if scope.className then
        parts[#parts + 1] = scope.className
    end
    if scope.specName then
        parts[#parts + 1] = scope.specName
    end
    if scope.heroName then
        parts[#parts + 1] = scope.heroName
    end
    return " [" .. table.concat(parts, ", ") .. "]"
end

local function GetConditionDisplayName(cond)
    return (cond.name or "Unknown Talent") .. GetConditionContextSuffix(cond)
end

------------------------------------------------------------------------
-- PER-BUTTON VISIBILITY SETTINGS
------------------------------------------------------------------------
-- Every state dropdown in the Show & Hide Rules section offers Dim and Hide,
-- so what those two do is stated once here and appended to each row's own
-- tooltip rather than repeated inside the builder. `lines` is the row's own
-- body.
local VISIBILITY_DIM_TOOLTIP_LINE = {"Dim shows the button dimmed and keeps its layout position.", 1, 1, 1, true}
local VISIBILITY_HIDE_TOOLTIP_LINE = {"Hide removes the button entirely.", 1, 1, 1, true}
local VISIBILITY_TOOLTIP_SPACER = { " ", 1, 1, 1, true }
local function BuildVisibilityModeTooltip(title, lines)
    local tooltip = { title }
    for _, line in ipairs(lines) do
        tooltip[#tooltip + 1] = line
    end
    if #lines > 0 then
        tooltip[#tooltip + 1] = VISIBILITY_TOOLTIP_SPACER
    end
    tooltip[#tooltip + 1] = VISIBILITY_DIM_TOOLTIP_LINE
    tooltip[#tooltip + 1] = VISIBILITY_TOOLTIP_SPACER
    tooltip[#tooltip + 1] = VISIBILITY_HIDE_TOOLTIP_LINE
    return tooltip
end

-- The Cooldown Visibility labels and tooltip are shared with the preview's
-- reason text (Helpers.lua owns them), so a rename lands on every surface at
-- once.
local COOLDOWN_VISIBILITY = ST._COOLDOWN_VISIBILITY

-- Apply a value to all selected buttons if multi-select, else just this one.
-- File scope because both sections below write entry fields this way; each one
-- wraps it in its own ApplyToSelected closure so its call sites stay short.
local function ApplyFieldToSelection(group, buttonData, field, value)
    if CS.selectedButtons then
        local count = 0
        for _ in pairs(CS.selectedButtons) do count = count + 1 end
        if count >= 2 then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then bd[field] = value end
            end
            return
        end
    end
    buttonData[field] = value
end

-- The entry's live show/hide rules: what it does on cooldown, while its aura
-- is inactive, while unusable, at zero charges or stacks, and while not
-- equipped, each stated as one Show / Dim / Hide style dropdown. Built on the Visibility tab for a single entry and on the
-- batch surface for a selection; both draw the row grammar, so this builder
-- was converted outright.
local function BuildShowHideRulesSection(scroll, buttonData, infoButtons, batchContext)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local isBatch = batchContext ~= nil
    local isItem
    if isBatch then
        isItem = batchContext.uniformType == "item"
    else
        isItem = buttonData.type == "item"
    end

    local function ApplyToSelected(field, value)
        ApplyFieldToSelection(group, buttonData, field, value)
    end

    -- Filtered apply: only write to non-equippable items (stack toggles).
    -- When clearing (value is falsy), write to ALL selected to clean stale data.
    local function ApplyToNonEquippable(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterNonEquippable(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

    -- Filtered apply: only write to charge-capable buttons (charge toggles),
    -- or to the narrower filter a row passes. When clearing (value is falsy),
    -- write to ALL selected to clean stale data.
    local function ApplyToChargeCapable(field, value, filter)
        filter = filter or FilterChargeCapable
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or filter(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

    -- Filtered apply: only write to charge-based spell buttons.
    -- When clearing (value is falsy), write to ALL selected to clean stale data.
    local function ApplyToChargeSpell(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterChargeSpell(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

    -- Filtered apply for the Cooldown Visibility row's Show Only At 0 Charges
    -- value, which only a charge spell hidden while ready can hold.
    local function ApplyToChargeSpellNotOnCooldownOnly(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd and FilterChargeSpellNotOnCooldown(bd) then
                    bd[field] = value
                end
            end
        elseif FilterChargeSpellNotOnCooldown(buttonData) then
            buttonData[field] = value
        end
    end

    -- Filtered apply: only write to equippable items (equip toggles).
    -- When clearing, write to ALL selected to clean stale data.
    local function ApplyToEquippable(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterEquippable(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

    -- Helper: set checkbox value (batch-aware tri-state or normal).
    -- Optional filterFn scopes the batch read to match the write filter.
    local function SetCheckboxValue(cb, field, filterFn)
        if isBatch then
            local batchVal
            if filterFn then
                batchVal = GetBatchFieldValueFiltered(group, field, filterFn)
            else
                batchVal = GetBatchFieldValue(group, field)
            end
            SetupBatchCheckbox(cb, batchVal)
        else
            cb:SetValue(buttonData[field] or false)
        end
    end

    -- Helper: wrap OnValueChanged callback with batch remapping
    local function WrapBatchCallback(cb, callback)
        cb:SetCallback("OnValueChanged", function(widget, event, val)
            if isBatch then
                val = RemapBatchValue(widget, val)
            end
            callback(widget, event, val)
            if isBatch then
                widget._batchPrev = val
                widget:SetValue(val)  -- sync visual state for non-refreshing callbacks
            end
        end)
    end

    local function AnySelectedMatch(predicate)
        for idx in pairs(CS.selectedButtons) do
            local bd = group.buttons[idx]
            if bd and predicate(bd) then
                return true
            end
        end
        return false
    end
    local function AllSelectedMatch(predicate)
        for idx in pairs(CS.selectedButtons) do
            local bd = group.buttons[idx]
            if bd and not predicate(bd) then
                return false
            end
        end
        return true
    end

    -- An Aura Panel entry has no Show & Hide Rules section. Every entry an
    -- Aura Panel holds is a pure aura entry: the show-while-active pair is
    -- inherent to the panel, and every remaining family here is keyed to a
    -- cooldown, a castability state, charges, item stacks or equipped state
    -- that a pure aura entry never has. The section would build its header and
    -- then pour no rows, so it does not build at all.
    local isAuraPanel = CooldownCompanion:IsAuraPanel(group)

    if not isAuraPanel then
    -- The families are collected BEFORE the heading is drawn. Which of them
    -- survive is an entry-type answer that can come out empty (a member of an
    -- Aura Only Section: its aura pair leaves with the section, and every other
    -- family here wants a cooldown, a usability state, charges or an item), and
    -- a heading with a collapse arrow over nothing is chrome with no section
    -- under it. Collection creates no widgets - every family defers its rows to
    -- a build closure - so nothing reaches `scroll` until the count is known.
    --
    -- Two row shapes for the whole section. The plain toggles (hiding the
    -- cooldown behind remaining charges) are CDC-CheckBoxRows reading and
    -- writing through the same batch-aware helpers the stock checkboxes used,
    -- so the store side is untouched. opts.filter scopes the batch read to the
    -- write filter, opts.indent marks a child row, and opts.tooltip chains a
    -- "?" badge off the end of the label.
    local function AddVisibilityRow(column, label, field, opts)
        local row = AddCheckboxRow(column, {
            label = label,
            setting = opts.setting,
            indent = opts.indent,
        })
        SetCheckboxValue(row, field, opts.filter)
        WrapBatchCallback(row, opts.onChanged)
        if opts.tooltip then
            -- Anchor args are a placeholder - AnchorRowBadge re-points the
            -- button onto the end of the row's label.
            AnchorRowBadge(row, CreateInfoButton(row.frame, row.frame, "LEFT", "LEFT", 0, 0,
                opts.tooltip, infoButtons))
        end
        return row
    end

    -- The state dropdowns: every hide/dim/desaturate family is one
    -- CDC-DropdownRow whose value is derived from the family's boolean keys
    -- (opts.read) and written back as a whole set (opts.write), so two keys
    -- that contradict each other can never both be on. The keys themselves are
    -- the ones the checkboxes wrote, so nothing migrates and the runtime reads
    -- exactly what it read before. In a batch the value is read per selected
    -- entry inside opts.filter's scope, and a disagreement shows as Mixed
    -- until one pick writes every entry the same. opts.disabledItems greys the
    -- values that would contradict another row's current state, which is what
    -- replaced the old rows' silent clearing of each other.
    local function AddVisibilityDropdown(column, opts)
        local value
        if isBatch then
            local anyMatched, mixed = false, false
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd and (not opts.filter or opts.filter(bd)) then
                    local entryValue = opts.read(bd)
                    if not anyMatched then
                        value = entryValue
                        anyMatched = true
                    elseif entryValue ~= value then
                        mixed = true
                    end
                end
            end
            if not anyMatched then value = opts.order[1] end
            if mixed then value = nil end
        else
            value = opts.read(buttonData)
        end
        local row = AddDropdownRow(column, {
            setting = opts.setting,
            indent = opts.indent,
            list = opts.list,
            order = opts.order,
            value = value,
            onChange = opts.write,
        })
        if value == nil then
            row:SetText("Mixed")
        end
        if opts.disabledItems then
            for _, item in ipairs(opts.disabledItems) do
                row:SetItemDisabled(item, true)
            end
        end
        if opts.tooltip then
            -- Anchor args are a placeholder - AnchorRowBadge re-points the
            -- button onto the end of the row's label.
            AnchorRowBadge(row, CreateInfoButton(row.frame, row.frame, "LEFT", "LEFT", 0, 0,
                opts.tooltip, infoButtons))
        end
        return row
    end

    -- The value list, reader and writer the hide/dim families share, so the
    -- value-to-keys mapping lives in one place.
    -- opts.desaturateKey is nil for the families without one.
    local function BuildStateList(withDesaturate)
        local list, order = { show = "Show" }, { "show" }
        if withDesaturate then
            list.desaturate = "Desaturate"
            order[#order + 1] = "desaturate"
        end
        list.dim = "Dim"
        order[#order + 1] = "dim"
        list.hide = "Hide"
        order[#order + 1] = "hide"
        return list, order
    end
    local function ReadHideDimState(bd, hideKey, dimKey, desaturateKey)
        if bd[hideKey] then
            if bd[dimKey] then return "dim" end
            return "hide"
        end
        if desaturateKey and bd[desaturateKey] then return "desaturate" end
        return "show"
    end
    local function WriteHideDimState(apply, value, hideKey, dimKey, desaturateKey)
        apply(hideKey, (value == "hide" or value == "dim") or nil)
        apply(dimKey, value == "dim" or nil)
        if desaturateKey then
            apply(desaturateKey, value == "desaturate" or nil)
        end
    end

    -- Every row here belongs to a FAMILY. Which families survive depends on
    -- the entry type, so this is a FILTERED row set: the families are
    -- collected first, then written into the grid in order. Every family is
    -- one row now: a state dropdown, or one of the two plain toggles that
    -- survived.
    local families = {}
    local function AddFamily(build)
        families[#families + 1] = build
    end

    -- One hide/dim state family: its list, reader and writer are built from
    -- the key names, so the five families below are declarations rather than
    -- five copies of the same mapping. spec.afterWrite runs the family's own
    -- extra clearing (the zero-charges row's cross-link) after the shared
    -- write and before the rebuild.
    local function AddStateFamily(spec)
        AddFamily(function(column)
            local list, order = BuildStateList(spec.desaturateKey ~= nil)
            AddVisibilityDropdown(column, {
                setting = spec.setting,
                filter = spec.filter,
                list = list,
                order = order,
                disabledItems = spec.disabledItems,
                read = function(bd)
                    return ReadHideDimState(bd, spec.hideKey, spec.dimKey, spec.desaturateKey)
                end,
                tooltip = BuildVisibilityModeTooltip(spec.title, spec.tooltipLines),
                write = function(value)
                    WriteHideDimState(spec.apply, value, spec.hideKey, spec.dimKey, spec.desaturateKey)
                    if spec.afterWrite then spec.afterWrite(value) end
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end)
    end

    -- While Aura Inactive (aura entries). 12.1: applied statically —
    -- the aura display composes the whole button over an invisible CC shell,
    -- so this needs a restyle + rebind, not the per-tick visibility bits.
    --
    -- Members of an Aura Only Section are excluded for the same reason the
    -- whole Aura Panel is: they render through Blizzard's packed container,
    -- which gives inactive auras no space and ignores the hide/dim keys.
    -- Clearing writes still reach them (see ApplyToAuraEntries) so an entry
    -- that later leaves the section is never stuck with a stale key.
    local function FilterAuraEntry(bd)
        return bd.type == "spell" and (bd.auraTracking or bd.addedAs == "aura")
            and not ST.IsAuraSectionEntry(group, bd)
    end
    local function ApplyToAuraEntries(field, value, eligible)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd and (not eligible or eligible(bd)) then
                    if not value or FilterAuraEntry(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end
    local anyAuraEntry
    if isBatch then anyAuraEntry = AnySelectedMatch(FilterAuraEntry)
    else anyAuraEntry = FilterAuraEntry(buttonData) end
    -- Icon and bar groups only (both compose a full shell); no other mode has
    -- a shell for an inactive state to hide or dim.
    local displayMode = group.displayMode or "icons"
    if anyAuraEntry and (displayMode == "icons" or displayMode == "bars") then
        local auraList = { show = "Normal", dim = "Dim While Inactive", hide = "Show While Active",
            missing = "Show While Inactive" }
        local auraOrder = { "show", "dim", "hide", "missing" }
        -- Visibility is independent of missing-aura effects.
        AddFamily(function(column)
            AddVisibilityDropdown(column, {
                setting = entryVisibilitySettings.auraInactive,
                filter = FilterAuraEntry,
                list = auraList,
                order = auraOrder,
                read = function(bd) return CooldownCompanion:GetAuraVisibilityMode(bd) end,
                tooltip = BuildVisibilityModeTooltip("Aura Visibility", {
                    {"Normal keeps the entry's usual presentation. Dim While Inactive dims a missing aura; Show While Active hides it.", 1, 1, 1, true},
                    VISIBILITY_TOOLTIP_SPACER,
                    {"Show While Inactive shows the entry only while the aura is missing. A target aura needs a hostile target. Tracked on your group, it shows while nobody has it.", 1, 1, 1, true},
                    VISIBILITY_TOOLTIP_SPACER,
                    {"Hidden auras still reserve their space, including in Compact Mode. An Aura entry shown as a bar beside icons collapses instead, unless it is tracked on your group or pet.", 1, 1, 1, true},
                }),
                write = function(value)
                    ApplyToAuraEntries("hideWhileAuraNotActive", value == "hide" or nil)
                    ApplyToAuraEntries("auraShellDim", value == "dim" or nil)
                    ApplyToAuraEntries("showWhileAuraMissing", value == "missing" or nil)
                    -- Its pandemic option goes with it, so a later pick never
                    -- brings it back unseen.
                    if value ~= "missing" then ApplyToAuraEntries("showWhileAuraPandemic", nil) end
                    CooldownCompanion:RefreshAllGroups()
                    CooldownCompanion:RequestAuraRebind("config", CS.selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
            -- Also During Pandemic: only under Show While Inactive, never with
            -- group tracking.
            local function PandemicEligible(bd)
                return FilterAuraEntry(bd) and CooldownCompanion:CanUseMissingPicturePandemic(bd)
            end
            local offerPandemic
            if isBatch then offerPandemic = AnySelectedMatch(PandemicEligible)
            else offerPandemic = PandemicEligible(buttonData) end
            if offerPandemic then
                AddVisibilityRow(column, "Also During Pandemic", "showWhileAuraPandemic", {
                    setting = entryVisibilitySettings.auraPandemic,
                    filter = PandemicEligible,
                    indent = true,
                    tooltip = { "Also During Pandemic",
                        {"Also shows the entry near the end of the aura, in the window where recasting keeps the leftover time.", 1, 1, 1, true},
                        VISIBILITY_TOOLTIP_SPACER,
                        {"Only auras with that window use it, mostly your own damage and healing over time. Leave it off for others.", 1, 1, 1, true},
                        VISIBILITY_TOOLTIP_SPACER,
                        {"In that window the entry looks as it does while the aura is up, timer included. Once the aura is gone, it shows the inactive look.", 1, 1, 1, true},
                    },
                    onChanged = function(widget, event, val)
                        if isBatch then
                            for idx in pairs(CS.selectedButtons) do
                                local bd = group.buttons[idx]
                                if bd and (not val or PandemicEligible(bd)) then
                                    bd.showWhileAuraPandemic = val or nil
                                end
                            end
                        else
                            buttonData.showWhileAuraPandemic = val or nil
                        end
                        CooldownCompanion:RequestAuraRebind("config", CS.selectedGroup)
                        -- The Live Preview reads this key too.
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })
            end
        end)
    end

    -- Cooldown family (skip for passives — no cooldown)
    -- Batch: show if not ALL selected are passive
    local allPassive
    if isBatch then allPassive = AllSelectedAre(group, "isPassive")
    else allPassive = buttonData.isPassive end
    local allNoCooldown
    if isBatch then allNoCooldown = AllSelectedNoCooldown(group)
    else allNoCooldown = IsNoCooldownSpell(buttonData) end
    local allNeverUnusable
    if isBatch then allNeverUnusable = AllSelectedNeverUnusable(group)
    else allNeverUnusable = IsNeverUnusableButton(buttonData) end

    if not allPassive and not allNoCooldown then
    -- One dropdown states the whole family. The five keys underneath are
    -- unchanged: the row derives one value from them and writes them back as
    -- a set, so the two directions can never both be on.
    --
    -- Show Only At 0 Charges only means anything on a charge spell, and its
    -- write sets hide-while-ready on every selected entry, so a batch offers
    -- it only when EVERY selected entry is a charge spell: a plain spell in
    -- the selection would otherwise be quietly set to Hide While Ready by a
    -- pick whose label says nothing of the sort.
    local offerZeroOnly
    if isBatch then offerZeroOnly = AllSelectedMatch(FilterChargeSpell)
    else offerZeroOnly = FilterChargeSpell(buttonData) end
    -- Showing only at zero charges contradicts hiding or dimming at zero
    -- charges (the At Zero Charges row below), so the option greys out while
    -- that row says so. A batch has no single state to grey against; its
    -- write keeps the clearing as a safety net instead.
    local zeroOnlyBlocked = not isBatch and buttonData.hideWhileZeroCharges == true
    local cooldownLabels = COOLDOWN_VISIBILITY.labels
    local cooldownList = {
        show = cooldownLabels.show,
        dim_cooldown = cooldownLabels.dim_cooldown,
        hide_cooldown = cooldownLabels.hide_cooldown,
        dim_ready = cooldownLabels.dim_ready,
        hide_ready = cooldownLabels.hide_ready,
    }
    local cooldownOrder = { "show", "dim_cooldown", "hide_cooldown", "dim_ready", "hide_ready" }
    if offerZeroOnly then
        cooldownList.zero_only = cooldownLabels.zero_only
        cooldownOrder[#cooldownOrder + 1] = "zero_only"
    end

    AddFamily(function(column)
        AddVisibilityDropdown(column, {
            setting = entryVisibilitySettings.cooldownVisibility,
            list = cooldownList,
            order = cooldownOrder,
            disabledItems = zeroOnlyBlocked and { "zero_only" } or nil,
            read = function(bd)
                if bd.hideWhileOnCooldown then
                    return bd.useBaselineAlphaFallbackOnCooldown and "dim_cooldown" or "hide_cooldown"
                elseif bd.hideWhileNotOnCooldown then
                    if bd.showOnlyAtZeroCharges and FilterChargeSpell(bd) then
                        return "zero_only"
                    end
                    return bd.useBaselineAlphaFallbackNotOnCooldown and "dim_ready" or "hide_ready"
                end
                return "show"
            end,
            tooltip = BuildVisibilityModeTooltip("Cooldown Visibility",
                COOLDOWN_VISIBILITY.tooltipLines),
            write = function(value)
                local hideOn = value == "hide_cooldown" or value == "dim_cooldown"
                local hideReady = value == "hide_ready" or value == "dim_ready" or value == "zero_only"
                ApplyToSelected("hideWhileOnCooldown", hideOn or nil)
                ApplyToSelected("useBaselineAlphaFallbackOnCooldown", value == "dim_cooldown" or nil)
                ApplyToSelected("hideWhileNotOnCooldown", hideReady or nil)
                ApplyToSelected("useBaselineAlphaFallbackNotOnCooldown", value == "dim_ready" or nil)
                ApplyToChargeSpell("showOnlyAtZeroCharges", value == "zero_only" or nil)
                if value == "zero_only" then
                    ApplyToChargeSpellNotOnCooldownOnly("hideWhileZeroCharges", nil)
                    ApplyToChargeSpellNotOnCooldownOnly("useBaselineAlphaFallbackZeroCharges", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end)

    end -- not allPassive and not allNoCooldown

    if not allPassive then
    if not allNeverUnusable then
    AddStateFamily({
        setting = entryVisibilitySettings.unusable,
        apply = ApplyToSelected,
        hideKey = "hideWhileUnusable",
        dimKey = "useBaselineAlphaFallbackUnusable",
        title = "While Unusable",
        tooltipLines = {
            {"Uses the same logic as Unusable Visual. Hide removes the button instead of changing the icon.", 1, 1, 1, true},
        },
    })
    end -- not allNeverUnusable

    -- No Proc (spell entries only, not aura entries)
    local showNoProcToggle
    if isBatch then
        showNoProcToggle = batchContext
            and batchContext.uniformType == "spell"
            and not AllSelectedAre(group, "isPassiveCooldown")
    else
        showNoProcToggle = buttonData.type == "spell"
            and buttonData.addedAs ~= "aura"
            and not buttonData.isPassiveCooldown
    end
    if showNoProcToggle then
        AddStateFamily({
            setting = entryVisibilitySettings.noProc,
            apply = ApplyToSelected,
            hideKey = "hideWhileNoProc",
            dimKey = "useBaselineAlphaFallbackNoProc",
            title = "While No Proc",
            tooltipLines = {
                {"What this entry does while the spell has no proc active.", 1, 1, 1, true},
            },
        })
    end

    end -- not allPassive (unusable + no proc)

    -- Desaturate is an icon treatment, so its sentence only belongs on rows
    -- whose list offers it.
    local DESATURATE_TOOLTIP_LINE = {"Desaturate grays the icon in place.", 1, 1, 1, true}
    local function ZeroStateTooltipLines(firstLine)
        local lines = { {firstLine, 1, 1, 1, true} }
        lines[#lines + 1] = VISIBILITY_TOOLTIP_SPACER
        lines[#lines + 1] = DESATURATE_TOOLTIP_LINE
        return lines
    end

    -- Charge-based visibility (spells + non-equippable items with charges)
    -- Batch: show if any selected button is charge-capable
    local showChargeSection
    if isBatch then showChargeSection = AnySelectedChargeCapable(group)
    else
        showChargeSection = FilterChargeCapable(buttonData)
    end
    if showChargeSection then
        -- Hiding or dimming at zero charges contradicts the Cooldown
        -- Visibility row's Show Only At 0 Charges, so both grey out while
        -- that row says so (single entry; a batch keeps the clearing write).
        local zeroChargesBlocked = not isBatch
            and buttonData.hideWhileNotOnCooldown == true
            and buttonData.showOnlyAtZeroCharges == true
            and FilterChargeSpell(buttonData)
        AddStateFamily({
            setting = entryVisibilitySettings.zeroCharges,
            filter = FilterChargeCapable,
            apply = ApplyToChargeCapable,
            hideKey = "hideWhileZeroCharges",
            dimKey = "useBaselineAlphaFallbackZeroCharges",
            desaturateKey = "desaturateWhileZeroCharges",
            disabledItems = zeroChargesBlocked and { "dim", "hide" } or nil,
            title = "At Zero Charges",
            tooltipLines = ZeroStateTooltipLines("What this entry does once every charge is spent."),
            afterWrite = function(value)
                if value == "hide" or value == "dim" then
                    ApplyToChargeSpell("showOnlyAtZeroCharges", nil)
                end
            end,
        })

        -- Hide Cooldown While Charges Remain: icon entries only.
        local function filterChargeSwipe(bd) return FilterChargeSwipe(group, bd) end
        local showChargeSwipe
        if isBatch then
            showChargeSwipe = AnySelectedMatch(filterChargeSwipe)
        else
            showChargeSwipe = filterChargeSwipe(buttonData)
        end
        if showChargeSwipe then
            AddFamily(function(column)
                AddVisibilityRow(column, "Hide Cooldown While Charges Remain", "hideCooldownWithCharges", {
                    setting = entryVisibilitySettings.chargeCooldown,
                    filter = filterChargeSwipe,
                    onChanged = function(widget, event, val)
                        ApplyToChargeCapable("hideCooldownWithCharges", val or nil, filterChargeSwipe)
                    end,
                })
            end)
        end
    end

    -- Stack-based visibility (non-equippable items without charges)
    -- Batch: show if any selected non-equippable item exists
    local showStackSection
    if isBatch then showStackSection = isItem and AnySelectedNonEquippable(group)
    else showStackSection = isItem and not CooldownCompanion.IsItemEquippable(buttonData) end
    if showStackSection then
        -- Batch: show stacks section if any selected lacks charges (stack-based items)
        local hasStacks
        if isBatch then hasStacks = AnySelectedHasItemFallbacks(group) or not AllSelectedChargeCapable(group)
        else hasStacks = HasItemFallbacks(buttonData) or not UsesChargeBehavior(buttonData) end
        if hasStacks then
            local fallbackItemUses = isBatch and AnySelectedHasItemFallbacks(group) or HasItemFallbacks(buttonData)
            AddStateFamily({
                setting = fallbackItemUses and entryVisibilitySettings.noUses
                    or entryVisibilitySettings.zeroStacks,
                filter = FilterNonEquippable,
                apply = ApplyToNonEquippable,
                hideKey = "hideWhileZeroStacks",
                dimKey = "useBaselineAlphaFallbackZeroStacks",
                desaturateKey = "desaturateWhileZeroStacks",
                title = fallbackItemUses and "With No Uses Available" or "At Zero Stacks",
                tooltipLines = ZeroStateTooltipLines(fallbackItemUses
                    and "What this entry does once the item has no uses left."
                    or "What this entry does once you hold none of the item."),
            })
        end
    end

    -- Not Equipped (equippable items only)
    -- Batch: show if any selected item is equippable
    local showEquipSection
    if isBatch then showEquipSection = isItem and AnySelectedEquippable(group)
    else showEquipSection = isItem and CooldownCompanion.IsItemEquippable(buttonData) end
    if showEquipSection then
        AddStateFamily({
            setting = entryVisibilitySettings.equipped,
            filter = FilterEquippable,
            apply = ApplyToEquippable,
            hideKey = "hideWhileNotEquipped",
            dimKey = "useBaselineAlphaFallbackNotEquipped",
            title = "While Not Equipped",
            tooltipLines = {
                {"What this entry does while the item is not equipped.", 1, 1, 1, true},
            },
        })
    end

    -- An entry type can filter every family away (a member of an Aura Only
    -- Section, for example), and both the
    -- heading and an empty grid are still widgets - so the section only builds
    -- when there is something to pour into it.
    if #families > 0 then
        local visKey = isBatch
            and (CS.selectedGroup .. "_batch_visibility")
            or  (CS.selectedGroup .. "_" .. CS.selectedButton .. "_visibility")
        local _, visCollapsed = BuildCollapsibleSection(scroll, "Show & Hide Rules", visKey, nil, nil, ROW_SECTION)
        if not visCollapsed then
            local visColumn = BeginRowGrid(scroll)
            for _, buildFamily in ipairs(families) do
                buildFamily(visColumn)
            end
        end
    end

    end -- not isAuraPanel
end

------------------------------------------------------------------------
-- TALENT CONDITIONS (its own section, independent of the show/hide rules)
------------------------------------------------------------------------
local function BuildEntryTalentConditionsSection(scroll, buttonData, infoButtons, batchContext, sourceIndex)
    local profile, groupId = CooldownCompanion.db.profile, CS.selectedGroup
    local group = profile.groups[groupId]
    if not group then return end

    local isBatch = batchContext ~= nil

    local function IsCurrentSource()
        return not sourceIndex or (CooldownCompanion.db.profile == profile
            and profile.groups[groupId] == group and group.buttons[sourceIndex] == buttonData)
    end

    local function ApplyToSelected(field, value)
        if sourceIndex then buttonData[field] = value
        else ApplyFieldToSelection(group, buttonData, field, value) end
    end

    -- The one write path for pick, batch and clear. A 2+ batch gets a copy
    -- per entry so later edits to one do not reach the others.
    local function WriteTalentConditions(results)
        if results and not sourceIndex and CS.selectedButtons then
            local count = 0
            for _ in pairs(CS.selectedButtons) do count = count + 1 end
            if count >= 2 then
                for idx in pairs(CS.selectedButtons) do
                    local bd = group.buttons[idx]
                    if bd then bd.talentConditions = CopyTable(results) end
                end
                return
            end
        end
        ApplyToSelected("talentConditions", results)
    end

    local talentKey = sourceIndex and (groupId .. "_indicator_source_" .. sourceIndex .. "_talentcondition")
        or isBatch
        and (groupId .. "_batch_talentcondition")
        or  (groupId .. "_" .. CS.selectedButton .. "_talentcondition")
    local headingText = sourceIndex and ("Talents: " .. (buttonData.name or tostring(buttonData.id or sourceIndex)))
        or "Talent Conditions"
    local talentHeading, talentCollapsed = BuildCollapsibleSection(scroll, headingText, talentKey,
        nil, nil, ROW_SECTION)

    -- The heading's "?" chains off the end of its label; the fading rule
    -- restarts after that badge.
    local talentInfoBtn = CreateInfoButton(talentHeading.frame, talentHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Talent Conditions",
        {"Show or hide this button based on which talents you have selected. If you add multiple conditions, all of them must pass.", 1, 1, 1, true},
    }, infoButtons)
    AnchorLeftAlignedHeadingRule(talentHeading, talentInfoBtn)

    -- Determine current talent condition state
    local conditions = buttonData.talentConditions
    local condCount = conditions and #conditions or 0
    local hasTalent
    if isBatch then
        hasTalent = GetBatchTalentConditionsValue(group)
    else
        hasTalent = condCount > 0
    end

    if talentCollapsed then
        local summaryLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(summaryLabel)
        if isBatch and hasTalent == nil then
            summaryLabel:SetText("|cff888888Multiple conditions|r")
        elseif hasTalent and condCount > 0 then
            local firstCond = conditions[1]
            local displayIcon = not IsHeroSpecProxyCondition(firstCond)
                and firstCond.spellID
                and C_Spell.GetSpellTexture(firstCond.spellID)
            if displayIcon then
                summaryLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                summaryLabel:SetImageSize(16, 16)
            end
            if condCount == 1 then
                local showText = (firstCond.show == "not_taken") and " (not taken)" or " (taken)"
                summaryLabel:SetText(GetConditionDisplayName(firstCond) .. showText)
            else
                summaryLabel:SetText(condCount .. " conditions" .. GetConditionListContextSuffix(conditions))
            end
        else
            summaryLabel:SetText("|cff888888None|r")
        end
        summaryLabel:SetFullWidth(true)
        scroll:AddChild(summaryLabel)
    end

    if not talentCollapsed then

    -- One-column row grid. Conditions are ITEM rows: a CDC-LabelRow with the
    -- talent icon inlined into the label text and the taken/not-taken state
    -- as the row's right-aligned status word.
    local talentLeft = BeginRowGrid(scroll)

    if condCount > 0 and not (isBatch and hasTalent == nil) then
        local cache = CooldownCompanion._talentNodeCache
        local currentSpecID = CooldownCompanion._currentSpecId
        local currentHeroSubTreeID = CooldownCompanion._currentHeroSpecId
        for _, cond in ipairs(conditions) do
            local displayIcon = not IsHeroSpecProxyCondition(cond)
                and cond.spellID
                and C_Spell.GetSpellTexture(cond.spellID)
            local nameText = GetConditionDisplayName(cond)
            if displayIcon then
                nameText = ("|T%s:16:16:0:0|t %s"):format(tostring(displayIcon), nameText)
            end
            AddLabelRow(talentLeft, {
                label = "|cffFFFFFF" .. nameText .. "|r",
                controlText = (cond.show == "not_taken")
                    and "|cffff4d4d(not taken)|r"
                    or "|cff33dd33(taken)|r",
            })

            -- Per-condition stale node warning. A wrapped sentence rather
            -- than a setting, so it keeps its stock Label shape and sits
            -- directly under the row it warns about.
            local matchesCurrentScope = (not cond.specID or cond.specID == currentSpecID)
                and (not cond.heroSubTreeID or cond.heroSubTreeID == currentHeroSubTreeID)
            if not isBatch and matchesCurrentScope and cache and not cache[cond.nodeID] then
                local warnLabel = AceGUI:Create("Label")
                ST._ConfigureWrappedHelperLabel(warnLabel)
                warnLabel:SetText("|cffff8800This talent is not in your current active tree, so it behaves as not taken right now.|r")
                warnLabel:SetFullWidth(true)
                talentLeft:AddChild(warnLabel)
            end
        end
    end

    -- The section's status prose and its actions share one closing grammar
    -- row: the buttons live in the row's control column, so the picker wears
    -- the same 140px right-aligned footprint as every control above it
    -- instead of floating compact on the tab surface.
    local talentStatusText
    if isBatch and hasTalent == nil then
        talentStatusText = "|cff888888Multiple conditions; pick or clear to unify.|r"
    elseif condCount > 0 then
        talentStatusText = ""
    else
        talentStatusText = "|cff888888No talent conditions set.|r"
    end

    -- A batch whose entries all hold the same list edits that list (the
    -- representative's copy; the picker copies it again). A mixed batch
    -- starts from nothing and offers Clear, as its status line says.
    local sharedList = not isBatch or hasTalent == true
    local pickBtn = AceGUI:Create("Button")
    pickBtn:SetText(condCount > 0 and sharedList and "Edit" or "Pick Talents")
    pickBtn:SetCallback("OnClick", function()
        local initialConditions = sharedList and buttonData.talentConditions or nil
        -- The picker's Accept already hands back normalized conditions.
        CooldownCompanion:OpenTalentPicker(function(results)
            if not IsCurrentSource() then return end
            WriteTalentConditions(results)
            CooldownCompanion:RefreshGroupFrame(groupId)
            CooldownCompanion:RefreshConfigPanel()
        end, initialConditions, group)
    end)

    local talentActionButtons = { pickBtn }
    if (not isBatch and hasTalent) or (isBatch and hasTalent ~= false) then
        -- Edit and Clear split the control column. Clear is destructive, so
        -- it shares the row with the picker that owns what it clears.
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear")
        clearBtn:SetCallback("OnClick", function()
            if not IsCurrentSource() then return end
            WriteTalentConditions(nil)
            CooldownCompanion:RefreshGroupFrame(groupId)
            CooldownCompanion:RefreshConfigPanel()
        end)
        talentActionButtons[2] = clearBtn
    end

    AddLabelRow(talentLeft, {
        label = talentStatusText,
        controlWidget = ST._CreateRowActionStrip(talentActionButtons),
    })

    end -- not talentCollapsed

end

-- Both sections in their ruled order, for the surfaces that draw the pair:
-- the entry lens on the Visibility tab composes them itself, but the batch
-- pane wants exactly this.
local function BuildVisibilitySettings(scroll, buttonData, infoButtons, batchContext)
    BuildShowHideRulesSection(scroll, buttonData, infoButtons, batchContext)
    BuildEntryTalentConditionsSection(scroll, buttonData, infoButtons, batchContext)
end

------------------------------------------------------------------------
-- VISIBILITY TAB (internal tab key stays "loadconditions")
------------------------------------------------------------------------

-- A plain scoping line naming the family of sections beneath it. It is not a
-- setting and not a section: no caret, no collapse state, no "?" badge. It
-- takes the entry identity heading's anatomy (Helpers.lua), gold label
-- included, so it reads as a label for what follows rather than as one more
-- collapsible section in the stack.
local FAMILY_HEADING_COLOR = { 1, 0.82, 0 }

local function AddFamilyHeading(container, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    -- Restores the stock label/left/right anatomy a recycled Heading can
    -- arrive with stale; the class tint it also applies is overwritten below.
    ColorHeading(heading)
    heading.label:SetTextColor(FAMILY_HEADING_COLOR[1], FAMILY_HEADING_COLOR[2],
        FAMILY_HEADING_COLOR[3])
    heading:SetFullWidth(true)
    container:AddChild(heading)
    -- Flush: with no caret and no icon the reserved caret column reads as a
    -- hole, so the label starts where the carets under it do.
    ApplyLeftAlignedHeading(heading, nil, true)
    return heading
end

ResolvePanelAlphaAnchorSourceMode = function(groupId, group)
    if CooldownCompanion.IsPanelAnchoredToPanel
        and CooldownCompanion:IsPanelAnchoredToPanel(groupId) then
        return "panel"
    end
    if not group.parentContainerId then return nil end

    local anchorSettings = CooldownCompanion.GetIndicatorAnchorSettings
        and CooldownCompanion:GetIndicatorAnchorSettings(group)
    local relativeTo = anchorSettings and anchorSettings.relativeTo
    if not relativeTo then
        local anchor = group.anchor
        relativeTo = type(anchor) == "table" and anchor.relativeTo or anchor
    end
    if type(relativeTo) == "string" and relativeTo ~= "" and relativeTo ~= "UIParent"
        and CooldownCompanion:ParseAddonAnchorFrameName(relativeTo) == nil then
        local target = _G[relativeTo]
        if type(target) == "table" and type(target.GetObjectType) == "function" then
            return "frame"
        end
    end
    return nil
end

local function BuildPanelAlphaControls(container, config, refreshFn, collapseKey, opts)
    opts = opts or {}
    opts.settings = panelAlphaSettings
    BuildAlphaControls(container, config, refreshFn, collapseKey, opts)
end

local function BuildLoadConditionsTab(container)
    if not CS.selectedGroup then return end
    local groupId = CS.selectedGroup
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end

    -- Ensure loadConditions table exists
    if not group.loadConditions then
        group.loadConditions = CooldownCompanion:GetDefaultLoadConditions()
    end
    local effectiveSpecs = CooldownCompanion:GetEffectiveSpecs(group)
    local inheritedSpecs, inheritedSpecFilter = CooldownCompanion:GetInheritedEffectiveSpecs(group)
    local effectiveHeroTalents, inheritedHeroFilter = CooldownCompanion:GetEffectiveHeroTalents(group)
    local inheritedSources = CooldownCompanion:GetInheritedLoadConditionSources(group)
    local parentContainer = CooldownCompanion:GetParentContainer(group)
    local scopeIsGlobal
    if parentContainer then
        scopeIsGlobal = parentContainer.isGlobal == true
    else
        scopeIsGlobal = group.isGlobal == true
    end
    local ownerCharKey = parentContainer and parentContainer.createdBy or group.createdBy
    local function RefreshPanelLoadConditions()
        CooldownCompanion:RefreshGroupFrame(groupId)
        CooldownCompanion:RefreshConfigPanel()
    end

    -- The tab reads as two halves under one family heading: who the panel is
    -- for, then where it stays hidden. Row grammar (RowWidgets.lua)
    -- throughout - see the recipe comment at the top of BuildAppearanceTab's
    -- icons path in GroupTabsAppearance.lua. Nothing on this tab carries a gear, so
    -- there is no advanced-panel queue to keep uncollapsed.
    AddFamilyHeading(container, "Load Conditions")

    local _, whoCollapsed = BuildCollapsibleSection(container, "Who Can Use This",
        "loadconditions_panel_who", nil, nil, ROW_SECTION)

    if not whoCollapsed then
        local eligibilityOpts = {
            target = group,
            inheritedSources = inheritedSources,
            eligibilitySubjectLabel = "panel",
            allowClassEligibility = scopeIsGlobal,
            ownerCharKey = ownerCharKey,
            useSpecAllowlist = inheritedSpecFilter,
            allowedSpecRestricted = inheritedSpecFilter,
            allowedSpecMap = inheritedSpecs,
            effectiveSpecs = effectiveSpecs,
            choiceSpecMap = inheritedSpecs,
            heroTalentsSource = effectiveHeroTalents,
            useHeroTalentsSource = inheritedHeroFilter,
            disableHeroTalents = inheritedHeroFilter,
            onChanged = RefreshPanelLoadConditions,
        }

        -- LEFT column: who, by person. RIGHT column: who, by what they play -
        -- class, spec and hero talent read as one chain (hero talents are only
        -- offered for a spec already picked), so they cannot be split off from
        -- each other. Each picker carries its own selections as indented rows
        -- directly beneath it.
        local whoLeft, whoRight = BeginRowGrid(container)
        AddCharacterEligibilityControls(whoLeft, eligibilityOpts)
        AddClassSpecEligibilityControls(whoRight, eligibilityOpts)
    end -- not whoCollapsed

    AddScopedLoadConditionToggles(container, {
        target = group,
        settings = panelLoadConditionSettings,
        defaults = CooldownCompanion:GetDefaultLoadConditions(),
        inheritedSources = inheritedSources,
        headingText = "Where To Hide It",
        localCollapsedKey = "loadconditions_panel_local",
        infoTooltipLines = BuildWhereToHideTooltip("panel", true, true),
        infoButtons = tabInfoButtons,
        onChanged = RefreshPanelLoadConditions,
    })

    -- ============================================================
    -- Alpha (moved here from the Layout tab: transparency behavior
    -- reads as visibility, not layout)
    -- ============================================================

    -- Where this panel's alpha comes from, when it hangs off something that
    -- has one to give: another panel, or a resolved external frame. Derived
    -- from stored anchors rather than the Layout tab's target-mode UI state;
    -- the two agree because an unresolved or addon-internal target never
    -- inherits. It drives both the source row below and the gating, so it is
    -- resolved once.
    local alphaAnchorSourceMode = ResolvePanelAlphaAnchorSourceMode(groupId, group)
    -- The panel half of this is exactly ShouldInheritPanelAnchorAlpha; both
    -- halves read the one inheritPanelAlpha key the source row writes.
    local inheritsAnchorAlpha = alphaAnchorSourceMode ~= nil
        and group.inheritPanelAlpha ~= false

    -- A panel whose alpha is owned elsewhere (Group Alpha, or an anchor it
    -- inherits from) shows the section disabled with the reason.
    local alphaControlsDisabled, alphaDisabledText = false, nil
    if CooldownCompanion.GetPanelContainerAlphaSource
        and CooldownCompanion:GetPanelContainerAlphaSource(groupId) then
        alphaControlsDisabled = true
        alphaDisabledText = "Group Alpha is enabled. This panel uses the group's Alpha settings."
    elseif inheritsAnchorAlpha then
        alphaControlsDisabled = true
        -- The source row sits directly above, so neither line has to say
        -- where the choice is made any more. The panel case keeps its
        -- pointer to the OTHER panel, which is elsewhere either way; an
        -- external frame has no Alpha settings of ours to send anyone to.
        alphaDisabledText = alphaAnchorSourceMode == "panel"
            and "This panel inherits alpha from the parent panel. Change the parent panel's Alpha settings to affect it."
            or "This panel inherits alpha from the target frame."
    end

    -- The alpha-source row leads the section (Helpers' leadingRows hook): it
    -- is the reason every row under it is live or greyed, so it reads first.
    -- It used to sit in the Layout tab's Anchor section, a tab away from what
    -- it gates.
    local alphaLeadingRows = nil
    if alphaAnchorSourceMode then
        alphaLeadingRows = function(alphaLeft)
            AddDropdownRow(alphaLeft, {
                setting = panelAlphaSettings.source,
                pulloutWidth = PANEL_ALPHA_PULLOUT_WIDTH,
                list = {
                    inherit = alphaAnchorSourceMode == "frame"
                        and "Inherit Target Frame Alpha"
                        or "Inherit Target Panel Alpha",
                    custom = "Custom Alpha",
                },
                order = { "inherit", "custom" },
                value = group.inheritPanelAlpha == false and "custom" or "inherit",
                onChange = function(val)
                    group.inheritPanelAlpha = val ~= "custom"
                    if ST.IsIndicatorGroup(group) then
                        -- An Indicator's alpha rides its display visuals,
                        -- not a group frame shell.
                        CooldownCompanion:RefreshAllAuraTextureVisuals()
                    else
                        local frame = CooldownCompanion.groupFrames[groupId]
                        if frame then
                            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
                        end
                        CooldownCompanion:RebuildPanelAlphaDependencyTargets()
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end
    end

    -- An Indicator's alpha rides its display visuals as well.
    local isIndicator = ST.IsIndicatorGroup(group)
    BuildPanelAlphaControls(container, group, function()
        if isIndicator then
            CooldownCompanion:RefreshAllAuraTextureVisuals()
        end
        CooldownCompanion:RefreshConfigPanel()
    end, "loadconditions_alpha", {
        isGlobal = group.isGlobal,
        disabled = alphaControlsDisabled,
        disabledText = alphaDisabledText,
        leadingRows = alphaLeadingRows,
        onBaselineCommitted = isIndicator and function()
            CooldownCompanion:RefreshAllAuraTextureVisuals()
        end or nil,
    })
end

local function BuildEntryLoadConditionsTab(container, buttonData, infoButtons, opts)
    if not (CS.selectedGroup and buttonData) then return end
    local groupId = CS.selectedGroup
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end
    opts = opts or {}

    -- Entry scope mirrors the panel tab, minus the eligibility half: an entry
    -- inherits who its panel is for and can only add places to hide.
    local _, togglesRight = AddScopedLoadConditionToggles(container, {
        target = buttonData,
        settings = opts.settings or entryLoadConditionSettings,
        defaults = CooldownCompanion:GetLocalLoadConditionDefaults(),
        inheritedSources = CooldownCompanion:GetLoadConditionSourcesForGroup(group),
        headingText = opts.headingText or "Where To Hide It",
        localCollapsedKey = opts.collapseKey or "loadconditions_entry_local",
        preserveMissing = true,
        infoTooltipLines = BuildWhereToHideTooltip("entry", false, true),
        infoButtons = infoButtons,
        onChanged = function()
            if buttonData.loadConditions and not next(buttonData.loadConditions) then
                buttonData.loadConditions = nil
            end
            CooldownCompanion:RefreshGroupFrame(groupId)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if opts.allowClear or CooldownCompanion:HasLocalLoadConditions(buttonData) then
        -- Compact and flush left, last, in the grid's second column under the
        -- toggles. With the section collapsed there is no grid to sit in, so it
        -- falls back to the tab surface - still reachable, still compact.
        local clearHost = togglesRight or container
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText(opts.clearLabel or "Clear Added Places")
        clearBtn:SetAutoWidth(true)
        clearBtn:SetCallback("OnClick", function()
            buttonData.loadConditions = nil
            CooldownCompanion:RefreshGroupFrame(groupId)
            CooldownCompanion:RefreshConfigPanel()
        end)
        clearHost:AddChild(clearBtn)
    end
end

local function BuildIndicatorSourceRestrictions(container, group)
    if not ST.IsIndicatorGroup(group) then return end
    local heading
    for index, source in ipairs(group.buttons or {}) do
        if HasSavedSourceRestrictions(source) then
            if not heading then
                heading = AddFamilyHeading(container, "Source Restrictions")
                ST._BindSettingWidget(heading, indicatorSourceRestrictions, "Source Restrictions")
                local onRelease = heading.events and heading.events.OnRelease
                heading:SetCallback("OnRelease", function(widget, event, ...)
                    widget._cdcSettingDescriptor = nil
                    if onRelease then onRelease(widget, event, ...) end
                end)
            end
            if type(source.loadConditions) == "table" and next(source.loadConditions) then
                BuildEntryLoadConditionsTab(container, source, tabInfoButtons, {
                    -- Repeated source rows belong to one searchable section, not
                    -- the entry-scope descriptors used by ordinary panels.
                    settings = {},
                    headingText = "Source: " .. (source.name or tostring(source.id or index)),
                    collapseKey = "loadconditions_indicator_source_" .. index,
                    allowClear = true,
                    clearLabel = "Clear Load Conditions",
                })
            end
            if type(source.talentConditions) == "table" and #source.talentConditions > 0 then
                BuildEntryTalentConditionsSection(container, source, tabInfoButtons, nil, index)
            end
        end
    end
end

-- There is one Visibility tab, and the selected object owns it: an entry edits
-- its rules, while a panel selection and multi-select edit the panel's.
--
-- The info buttons go into CS.tabInfoButtons, not the entry-tab host's
-- CS.buttonSettingsInfoButtons: this tab is built by the panel host, and
-- that is the list its tab callback cleans.
local function BuildVisibilityTab(container)
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]

    if group then
        local multiCount = 0
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end

        if multiCount < 2 then
            if CS.selectedButton then
                local buttonData = group.buttons and group.buttons[CS.selectedButton]
                if buttonData then
                    ST._BuildEntryIdentityHeading(container, buttonData)
                    -- Live rules first, then the static ones that decide
                    -- whether the entry loads at all.
                    BuildShowHideRulesSection(container, buttonData, tabInfoButtons)
                    AddFamilyHeading(container, "Load Conditions")
                    BuildEntryLoadConditionsTab(container, buttonData, tabInfoButtons)
                    BuildEntryTalentConditionsSection(container, buttonData, tabInfoButtons)
                    return
                end
            end
        end
    end

    BuildLoadConditionsTab(container)
    BuildIndicatorSourceRestrictions(container, group)
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._BuildVisibilitySettings = BuildVisibilitySettings
ST._BuildVisibilityTab = BuildVisibilityTab
ST._AddScopedLoadConditionToggles = AddScopedLoadConditionToggles
ST._BuildWhereToHideTooltip = BuildWhereToHideTooltip
ST._AddCharacterEligibilityControls = AddCharacterEligibilityControls
ST._AddClassSpecEligibilityControls = AddClassSpecEligibilityControls
ST._GetConditionDisplayName = GetConditionDisplayName
