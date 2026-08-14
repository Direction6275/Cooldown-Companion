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
local AttachCollapseButton = ST._AttachCollapseButton
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local CreateInfoButton = ST._CreateInfoButton
local BuildAlphaControls = ST._BuildAlphaControls

-- Imports from RowWidgets.lua (the row grammar). The Visibility tabs and the
-- per-entry Show Conditions / Talent Conditions builder are converted; every
-- other builder in this file still draws stock widgets.
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
local appearanceTabElements = CS.appearanceTabElements

local LOAD_CONDITION_OPTIONS = ST.LOAD_CONDITION_OPTIONS
local REMOVE_BADGE_WIDGET_TYPE = "CDCEligibilityRemoveBadge"
-- AceGUI sizes a dropdown's pullout from the dropdown frame itself
-- (AceGUIWidget-DropDown.lua:381), and the row grammar's control column is
-- 140px. Eligibility entries carry a spec/hero icon and can read
-- "Death Knight: Blood", so these four pickers widen their pullout past their
-- host. The pullout floats, so it may overhang the grid column it opens in.
local ELIGIBILITY_PULLOUT_WIDTH = 300
-- Row-grammar action strip: compact buttons sharing one grammar-height line
-- (the preset-trio shape in Helpers.lua). Flow insets its single row by 3px
-- top and bottom, so 3 + 24 + 3 centres inside the 30px band. The gutter's
-- height MATCHES the buttons on purpose - Flow offsets each child by half its
-- own height, so a shorter spacer makes the line step.
local ACTION_STRIP_HEIGHT = (ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT) or 30
local ACTION_STRIP_BUTTON_HEIGHT = 24
local ACTION_STRIP_GUTTER = 4
local ROW_CONTROL_WIDTH = (ST._RowGrammar and ST._RowGrammar.CONTROL_COLUMN_WIDTH) or 140
local VIEW_TRAIT_CONFIG_ID = (Constants and Constants.TraitConsts and Constants.TraitConsts.VIEW_TRAIT_CONFIG_ID) or -3

if AceGUI and not AceGUI:GetWidgetVersion(REMOVE_BADGE_WIDGET_TYPE) then
    local function Badge_OnClick(frame, button)
        frame.obj:Fire("OnClick", button)
        AceGUI:ClearFocus()
    end

    local function Badge_OnEnter(frame)
        frame.obj:Fire("OnEnter")
    end

    local function Badge_OnLeave(frame)
        frame.obj:Fire("OnLeave")
    end

    local badgeMethods = {
        OnAcquire = function(self)
            self:SetWidth(19)
            self:SetHeight(19)
            self:SetDisabled(false)
            if self.icon then
                self.icon:SetAtlas("common-icon-redx", false)
                self.icon:ClearAllPoints()
                self.icon:SetSize(19, 19)
                self.icon:SetPoint("CENTER")
            end
            if self.frame.SetHighlightAtlas then
                self.frame:SetHighlightAtlas("common-icon-redx")
                if self.frame.GetHighlightTexture and self.frame:GetHighlightTexture() then
                    self.frame:GetHighlightTexture():SetAlpha(0.3)
                end
            end
        end,

        SetDisabled = function(self, disabled)
            if disabled then
                self.frame:Disable()
                if self.icon then self.icon:SetVertexColor(0.5, 0.5, 0.5, 0.5) end
            else
                self.frame:Enable()
                if self.icon then self.icon:SetVertexColor(1, 1, 1, 1) end
            end
        end,
    }

    local function BadgeConstructor()
        local frame = CreateFrame("Button", nil, UIParent)
        frame:Hide()
        frame:SetSize(19, 19)
        frame:EnableMouse(true)
        frame:RegisterForClicks("AnyUp")
        frame:SetScript("OnClick", Badge_OnClick)
        frame:SetScript("OnEnter", Badge_OnEnter)
        frame:SetScript("OnLeave", Badge_OnLeave)

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetAtlas("common-icon-redx", false)
        icon:SetSize(19, 19)
        icon:SetPoint("CENTER")

        if frame.SetHighlightAtlas then
            frame:SetHighlightAtlas("common-icon-redx")
            if frame.GetHighlightTexture and frame:GetHighlightTexture() then
                frame:GetHighlightTexture():SetAlpha(0.3)
            end
        end

        local widget = {
            frame = frame,
            icon = icon,
            type = REMOVE_BADGE_WIDGET_TYPE,
        }
        for method, func in pairs(badgeMethods) do
            widget[method] = func
        end

        return AceGUI:RegisterAsWidget(widget)
    end

    AceGUI:RegisterWidgetType(REMOVE_BADGE_WIDGET_TYPE, BadgeConstructor, 1)
end

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

-- The section header takes the row-grammar shape (caret far left, label, rule
-- fading right). The summary body stays a full-width wrapped prose label - it
-- is not a setting, so it is not a row, and it sits above the grids rather
-- than inside one.
local function AddInheritedLoadSummary(container, sources, collapsedKey)
    local labelsBySource = {}
    local hasAny = false

    local function AddLabel(sourceLabel, conditionLabel)
        if not labelsBySource[sourceLabel] then
            labelsBySource[sourceLabel] = {}
        end
        labelsBySource[sourceLabel][#labelsBySource[sourceLabel] + 1] = conditionLabel
        hasAny = true
    end

    for _, cond in ipairs(LOAD_CONDITION_OPTIONS) do
        local inheritedLabel = GetActiveInheritedLabel(sources, cond.key, cond.default)
        if inheritedLabel then
            AddLabel(inheritedLabel, cond.label)
        end
    end

    if not hasAny then return end

    if collapsedKey then
        local _, collapsed = BuildCollapsibleSection(container, "Inherited Visibility Rules",
            collapsedKey, nil, nil, ROW_SECTION)
        if collapsed then return end
    end

    local inherited = {}
    for _, source in ipairs(sources or {}) do
        local labels = labelsBySource[source.label]
        if labels then
            inherited[#inherited + 1] = "|cff888888From " .. source.label .. ":|r " .. table.concat(labels, ", ")
        end
    end

    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText(table.concat(inherited, "\n"))
    label:SetFullWidth(true)
    container:AddChild(label)
end

-- Row grammar (RowWidgets.lua): a left-aligned collapsible header and the
-- environment toggles as CDC-CheckBoxRows in a two-column grid. Returns that
-- grid's two columns so the caller can park a section action in the shorter
-- one. Every caller passes opts.row = true, which is why there is no stock
-- shape here any more.
local function AddScopedLoadConditionToggles(container, opts)
    local target = opts.target
    if not target.loadConditions and not opts.preserveMissing then
        target.loadConditions = {}
    end
    local loadConditions = target.loadConditions or {}
    local defaults = opts.defaults
    local inheritedSources = opts.inheritedSources or {}
    local onChanged = opts.onChanged

    local inheritedAny = false
    for _, cond in ipairs(LOAD_CONDITION_OPTIONS) do
        if GetActiveInheritedLabel(inheritedSources, cond.key, cond.default) then
            inheritedAny = true
            break
        end
    end

    -- opts.skipInheritedSummary: the caller already emitted the summary above
    -- its own sections (the panel/entry tabs lead with it).
    if not opts.skipInheritedSummary then
        AddInheritedLoadSummary(container, inheritedSources, opts.inheritedCollapsedKey)
    end

    local headingText = (inheritedAny and opts.headingTextWhenInherited) or opts.headingText or "Hide When In"
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

    if inheritedAny then
        local inheritedLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(inheritedLabel)
        inheritedLabel:SetText("|cff888888Inherited rules are locked here. You can only add more places to hide this.|r")
        inheritedLabel:SetFullWidth(true)
        container:AddChild(inheritedLabel)
    end

    -- The one write every toggle performs, shared so both shapes wire the
    -- identical behaviour onto the identical store.
    local function SetCondition(cond, newVal)
        if not target.loadConditions then
            target.loadConditions = {}
            loadConditions = target.loadConditions
        end
        SetLoadConditionValue(loadConditions, cond.key, newVal, defaults, cond.default)
        if onChanged then onChanged() end
    end

    -- LEFT column: the instanced content. RIGHT column: everything else,
    -- ending with the two that ship pre-checked. Nine options split 5/4, which
    -- is as even as an odd list gets. Locked rows keep their long "(locked by
    -- ...)" suffix: a row label runs the full width of its cell minus the
    -- 140px control column, which is far more room than the half-width
    -- checkbox they replaced had.
    local togglesLeft, togglesRight = BeginRowGrid(container)
    local splitAt = math.ceil(#LOAD_CONDITION_OPTIONS / 2)

    for index, cond in ipairs(LOAD_CONDITION_OPTIONS) do
        local inheritedLabel = GetActiveInheritedLabel(inheritedSources, cond.key, cond.default)
        AddCheckboxRow(index <= splitAt and togglesLeft or togglesRight, {
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
    end

    return togglesLeft, togglesRight
end

local function NormalizeAllowlistKey(kind, key)
    if kind == "class" then
        if type(key) ~= "string" or key == "" then return nil end
        return string.upper(key)
    elseif kind == "spec" then
        local specId = tonumber(key)
        if not specId then return nil end
        return specId
    elseif kind == "character" then
        if type(key) ~= "string" or key == "" then return nil end
        return key
    end
    return nil
end

local function CopyAllowlist(map, kind)
    if type(map) ~= "table" then return nil, false end
    local copy = {}
    local sawEntry = false
    for key, enabled in pairs(map) do
        sawEntry = true
        if enabled == true then
            local normalizedKey = NormalizeAllowlistKey(kind, key)
            if normalizedKey ~= nil then
                copy[normalizedKey] = true
            end
        end
    end
    if next(copy) then return copy, true end
    return nil, sawEntry
end

local function IntersectAllowlists(left, right)
    local intersection = {}
    for key in pairs(left or {}) do
        if right and right[key] then
            intersection[key] = true
        end
    end
    return intersection
end

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
                inherited = IntersectAllowlists(inherited, copied or {})
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

local function GetClassInfoByID(classID)
    classID = tonumber(classID)
    if not classID then return nil, nil, nil end
    if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local classInfo = C_CreatureInfo.GetClassInfo(classID)
        if type(classInfo) == "table" then
            return classInfo.className, classInfo.classFile, classInfo.classID
        end
    end
    if GetClassInfo then
        return GetClassInfo(classID)
    end
    return nil, nil, nil
end

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

local function GetSpecClassChoice(specId)
    if not (C_SpecializationInfo and C_SpecializationInfo.GetClassIDFromSpecID) then
        return nil
    end
    local classID = C_SpecializationInfo.GetClassIDFromSpecID(tonumber(specId))
    return GetClassChoiceByID(classID)
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
local function BuildWhereToHideTooltip(subjectLabel, includePreCheckedNote)
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
    return lines
end

local function ResolveOwnerClassChoice(opts)
    if opts.ownerClassChoice then
        return opts.ownerClassChoice
    end
    if opts.ownerClassID then
        local choice = GetClassChoiceByID(opts.ownerClassID)
        if choice then return choice end
    end
    if opts.ownerClassFilename then
        local choice = GetClassChoiceByFilename(opts.ownerClassFilename)
        if choice then return choice end
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

local function CreateEligibilityRemoveBadge(onRemove)
    local removeBadge = AceGUI:Create(REMOVE_BADGE_WIDGET_TYPE)
    removeBadge:SetWidth(19)
    removeBadge:SetHeight(19)
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

-- omitCategory: rows rendered directly under their own picker don't need the
-- category prefix, the dropdown above them already names the category.
local function FormatActiveEligibilityLabel(category, value, omitCategory)
    if omitCategory then
        return tostring(value or "")
    end
    return "|cffffd100" .. tostring(category or "Filter") .. ":|r " .. tostring(value or "")
end

local function AddEligibilitySelectedRows(container, rows)
    for _, row in ipairs(rows or {}) do
        AddEligibilitySelectedRow(container, row, row.onRemove)
    end
end

-- Forward declarations: the selected-row builders sit below the pickers, but
-- the pickers render their own rows when opts.showSelectedRows is set.
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

    -- opts.omitHeading: the caller already opened a section around the pickers.
    if not opts.omitHeading then
        local heading = AceGUI:Create("Heading")
        heading:SetText(opts.characterHeadingText or "Character Eligibility")
        ColorHeading(heading)
        heading:SetFullWidth(true)
        container:AddChild(heading)

        local collapsed = opts.characterCollapsedKey and CS.collapsedSections[opts.characterCollapsedKey]
        if opts.characterCollapsedKey then
            AttachCollapseButton(heading, collapsed, function()
                CS.collapsedSections[opts.characterCollapsedKey] = not CS.collapsedSections[opts.characterCollapsedKey]
                CooldownCompanion:RefreshConfigPanel()
            end)
        end
        if collapsed then return end
    end

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

    if opts.showSelectedRows then
        local rows = {}
        AddActiveCharacterEligibilityRows(rows, opts)
        AddEligibilitySelectedRows(container, rows)
    end
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

local function EnsureHeroTalentViewConfig(specId)
    if not (specId
        and C_ClassTalents
        and C_ClassTalents.InitializeViewLoadout
        and C_Traits
        and C_Traits.GetConfigInfo) then
        return nil
    end

    local playerLevel = UnitLevel and UnitLevel("player") or nil
    if not playerLevel or playerLevel < 1 then
        return nil
    end

    C_ClassTalents.InitializeViewLoadout(specId, playerLevel)
    if C_Traits.GetConfigInfo(VIEW_TRAIT_CONFIG_ID) then
        return VIEW_TRAIT_CONFIG_ID
    end

    return nil
end

local function GetHeroTalentSubTreesForSpec(specId, configID)
    if not (specId and C_ClassTalents and C_ClassTalents.GetHeroTalentSpecsForClassSpec) then
        return nil, configID
    end

    local subTreeIDs = configID and C_ClassTalents.GetHeroTalentSpecsForClassSpec(configID, specId) or nil
    if subTreeIDs and #subTreeIDs > 0 then
        return subTreeIDs, configID
    end

    subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
    if subTreeIDs and #subTreeIDs > 0 then
        return subTreeIDs, configID
    end

    local viewConfigID = EnsureHeroTalentViewConfig(specId)
    subTreeIDs = viewConfigID and C_ClassTalents.GetHeroTalentSpecsForClassSpec(viewConfigID, specId) or nil
    if subTreeIDs and #subTreeIDs > 0 then
        return subTreeIDs, viewConfigID
    end

    return nil, configID
end

local function BuildHeroTalentChoicesForSpecs(specChoices, selectedSpecMap, configID)
    local choices = {}
    local bySubTreeID = {}

    for _, specInfo in ipairs(specChoices or {}) do
        local specId = specInfo.id
        if specId and selectedSpecMap and selectedSpecMap[specId] then
            local subTreeIDs, subTreeConfigID = GetHeroTalentSubTreesForSpec(specId, configID)
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

local function FormatEligibilitySpecLabel(specInfo, includeClass)
    if not specInfo then return "" end
    local classKey = specInfo.classKey
    if not classKey then
        local classChoice = GetSpecClassChoice(specInfo.id)
        classKey = classChoice and classChoice.key or nil
    end
    local specLabel = WrapClassColoredText(specInfo.name or specInfo.label or tostring(specInfo.id), classKey)
    if includeClass and specInfo.classLabel then
        local classChoice = GetClassChoiceByFilename(specInfo.classKey)
        local classLabel = GetClassDisplayLabel(classChoice) or specInfo.classLabel
        return classLabel .. ": " .. specLabel
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

    local allowClassEligibility = opts.allowClassEligibility == true
    local scopeClassChoice
    if not allowClassEligibility then
        scopeClassChoice = ResolveOwnerClassChoice(opts)
    end

    local inheritedClassMap, inheritedClassRestricted = GetInheritedAllowlist(opts.inheritedSources, "classAllowlist", "class")
    local classChoices = BuildClassChoices(target, inheritedClassMap)
    local localClassMap = target.loadConditions and target.loadConditions.classAllowlist

    -- opts.showSelectedRows: each picker carries its own removable selections
    -- instead of a separate summary section further down the tab.
    local selectedClassRows, selectedSpecRows, selectedHeroRows
    if opts.showSelectedRows then
        selectedClassRows, selectedSpecRows, selectedHeroRows = BuildActiveClassSpecEligibilityRows(opts)
    end

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
        ownerClassID = opts.ownerClassID,
        ownerClassFilename = opts.ownerClassFilename,
        effectiveSpecs = opts.effectiveSpecs,
        choiceSpecMap = opts.choiceSpecMap,
    })
    local specById = BuildSpecChoiceIndex(specChoices)

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

    local configID = opts.configID or (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID())
    local mutableHeroTalents = opts.disableHeroTalents ~= true
    local heroTalentsSource = opts.useHeroTalentsSource and opts.heroTalentsSource or target.heroTalents
    if type(heroTalentsSource) ~= "table" then
        heroTalentsSource = nil
    end
    local heroChoices = BuildHeroTalentChoicesForSpecs(specChoices, selectedSpecMap, configID)
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

local function NotifyEligibilityChanged(opts, callbackName)
    local callback = opts and opts[callbackName]
    if not callback and opts then
        callback = opts.onChanged
    end
    if callback then callback() end
end

function AddActiveCharacterEligibilityRows(rows, opts)
    local target = opts.target
    if type(target) ~= "table" then return end
    local omitCategory = opts.showSelectedRows == true

    local inheritedMap, inheritedRestricted = GetInheritedAllowlist(opts.inheritedSources, "characterAllowlist", "character")
    local scopeClassChoice
    if opts.allowClassEligibility == false then
        scopeClassChoice = ResolveOwnerClassChoice(opts)
    end
    local choices = BuildCharacterChoices(target, inheritedMap, scopeClassChoice and scopeClassChoice.key or nil, opts.ownerCharKey)
    local localMap = target.loadConditions and target.loadConditions.characterAllowlist
    local characterRows = {}

    for _, choice in ipairs(choices) do
        local key = choice.key
        if type(localMap) == "table" and localMap[key] == true then
            local outsideInherited = inheritedRestricted and not (inheritedMap and inheritedMap[key])
            characterRows[#characterRows + 1] = {
                key = key,
                label = FormatActiveEligibilityLabel(
                    "Character",
                    outsideInherited and (choice.label .. " |cff888888(unavailable from parent)|r") or choice.label,
                    omitCategory
                ),
                tooltipTitle = choice.tooltipTitle,
                tooltipText = choice.tooltipText,
                sortLabel = choice.sortLabel,
                onRemove = function()
                    SetAllowlistValue(target, "characterAllowlist", "character", key, false)
                    NotifyEligibilityChanged(opts, "characterOnChanged")
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
function BuildActiveClassSpecEligibilityRows(opts)
    local target = opts.target
    if type(target) ~= "table" then return {}, {}, {} end
    local omitCategory = opts.showSelectedRows == true

    local allowClassEligibility = opts.allowClassEligibility == true
    local scopeClassChoice
    if not allowClassEligibility then
        scopeClassChoice = ResolveOwnerClassChoice(opts)
    end

    local inheritedClassMap = GetInheritedAllowlist(opts.inheritedSources, "classAllowlist", "class")
    local classChoices = BuildClassChoices(target, inheritedClassMap)
    local localClassMap = target.loadConditions and target.loadConditions.classAllowlist
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
        ownerClassID = opts.ownerClassID,
        ownerClassFilename = opts.ownerClassFilename,
        effectiveSpecs = opts.effectiveSpecs,
        choiceSpecMap = opts.choiceSpecMap,
    })
    local _, specsByClassKey = BuildSpecChoiceIndex(specChoices)
    local configID = opts.configID or (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID())
    local heroTalentsSource = opts.useHeroTalentsSource and opts.heroTalentsSource or target.heroTalents
    if type(heroTalentsSource) ~= "table" then
        heroTalentsSource = nil
    end
    local _, heroById = BuildHeroTalentChoicesForSpecs(specChoices, selectedSpecMap, configID)

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
                        label = FormatActiveEligibilityLabel("Class", GetClassDisplayLabel(classChoice) or classChoice.label, omitCategory),
                        sortLabel = classChoice.label or classKey,
                        onRemove = function()
                            SetAllowlistValue(target, "classAllowlist", "class", classKey, false)
                            for _, specInfo in ipairs(classSpecs) do
                                SetSpecEligibilityValue(target, specInfo.id, false, useSpecAllowlist)
                                if CooldownCompanion.CleanHeroTalentsForSpec then
                                    CooldownCompanion:CleanHeroTalentsForSpec(target, specInfo.id)
                                end
                            end
                            NotifyEligibilityChanged(opts, "specOnChanged")
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
                        label = FormatActiveEligibilityLabel(
                            "Hero Talent",
                            FormatEligibilityHeroChoiceLabel(heroInfo, specInfo, allowClassEligibility),
                            omitCategory
                        ),
                        sortLabel = (specInfo.classLabel or "") .. (specInfo.name or "") .. (heroInfo.label or ""),
                        disabled = opts.disableHeroTalents == true,
                        onRemove = function()
                            SetHeroTalentValue(target, heroInfo.id, false)
                            NotifyEligibilityChanged(opts, "specOnChanged")
                        end,
                    }
                end
            else
                local outsideAllowed = allowedSpecRestricted and not (allowedSpecMap and allowedSpecMap[specId])
                specRows[#specRows + 1] = {
                    label = FormatActiveEligibilityLabel(
                        "Specialization",
                        FormatEligibilitySpecRowLabel(specInfo, allowClassEligibility)
                            .. (outsideAllowed and " |cff888888(unavailable from parent)|r" or ""),
                        omitCategory
                    ),
                    sortLabel = (specInfo.classLabel or "") .. (specInfo.name or specInfo.label or tostring(specId)),
                    onRemove = function()
                        SetSpecEligibilityValue(target, specId, false, useSpecAllowlist)
                        if CooldownCompanion.CleanHeroTalentsForSpec then
                            CooldownCompanion:CleanHeroTalentsForSpec(target, specId)
                        end
                        NotifyEligibilityChanged(opts, "specOnChanged")
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
    if HasItemFallbacks(bd) then return false end
    if not UsesChargeBehavior(bd) then return false end
    if bd.type == "spell" then return true end
    if bd.type == "item" and not CooldownCompanion.IsItemEquippable(bd) then return true end
    return false
end
local function FilterChargeSpell(bd)
    if HasItemFallbacks(bd) then return false end
    return bd.type == "spell" and bd.hasCharges == true and UsesChargeBehavior(bd)
end
local function FilterChargeSpellNotOnCooldown(bd)
    return FilterChargeSpell(bd) and bd.hideWhileNotOnCooldown == true
end

-- Returns true if any selected button has field truthy
local function AnySelectedHas(group, field)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and bd[field] then return true end
    end
    return false
end

-- Scoped version: only checks buttons matching filterFn(bd) → true
local function AnySelectedHasFiltered(group, field, filterFn)
    for idx in pairs(CS.selectedButtons) do
        local bd = group.buttons[idx]
        if bd and filterFn(bd) and bd[field] then return true end
    end
    return false
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
    if not bd or bd.type ~= "spell" then return false end
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
-- Talent condition display helpers (shared with ResourceBarPanels)
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

local function IsHeroSpecProxyCondition(cond)
    return type(cond) == "table"
        and cond.nodeID ~= nil
        and cond.heroSubTreeID ~= nil
        and cond.entryID == nil
        and type(cond.name) == "string"
        and type(cond.heroName) == "string"
        and cond.name == cond.heroName
end

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
-- Seven of the Show Conditions toggles gate the same dim child, so its
-- tooltip is stated once here rather than seven times inside the builder.
local DIM_INSTEAD_OF_HIDE_TOOLTIP = {
    "Dim Instead Of Hide",
    {"Instead of fully hiding, shows the button dimmed. It keeps its layout position.", 1, 1, 1, true},
}

-- insertBeforeTalents: optional callback run between the Show Conditions and
-- Talent Conditions sections. Talent Conditions is the last section of the
-- entry Settings tab by owner ruling, so everything the caller wants above it
-- goes through here rather than after the call.
--
-- Both call sites (the entry Settings tab and the batch surface) draw the row
-- grammar, so this builder was converted outright rather than growing an
-- opts.row mode.
local function BuildVisibilitySettings(scroll, buttonData, infoButtons, batchContext, insertBeforeTalents)
    -- Function-local, not upvalues: see the note by the row-grammar imports.
    local AddCheckboxRow = ST._AddCheckboxRow
    local AnchorRowBadge = ST._AnchorRowBadge
    local BeginRowGrid = ST._BeginRowGrid
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local isTexturePanel = group.displayMode == "textures"

    local isBatch = batchContext ~= nil
    local isItem
    if isBatch then
        isItem = batchContext.uniformType == "item"
    else
        isItem = buttonData.type == "item"
    end

    -- Helper: apply a value to all selected buttons if multi-select, else just this one
    local function ApplyToSelected(field, value)
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

    -- Filtered apply: only write to charge-capable buttons (charge toggles).
    -- When clearing (value is falsy), write to ALL selected to clean stale data.
    local function ApplyToChargeCapable(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterChargeCapable(bd) then
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

    -- Filtered apply for the nested "Hide While Not On Cooldown" charge-spell option.
    -- When clearing, write to ALL selected to remove stale child values.
    local function ApplyToChargeSpellNotOnCooldown(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
                    if not value or FilterChargeSpellNotOnCooldown(bd) then
                        bd[field] = value
                    end
                end
            end
        else
            buttonData[field] = value
        end
    end

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

    -- A primary Aura entry in a Texture panel has exactly one visibility rule:
    -- Blizzard shows its texture while the aura is active. That rule is always
    -- on, so this entry has no configurable Show Conditions section.
    local hideShowConditions = not isBatch
        and isTexturePanel
        and buttonData.type == "spell"
        and buttonData.addedAs == "aura"

    if not hideShowConditions then
    local visKey = isBatch
        and (CS.selectedGroup .. "_batch_visibility")
        or  (CS.selectedGroup .. "_" .. CS.selectedButton .. "_visibility")
    local _, visCollapsed = BuildCollapsibleSection(scroll, "Show Conditions", visKey, nil, nil, ROW_SECTION)

    if not visCollapsed then
    -- One row shape for the whole section: a CDC-CheckBoxRow reading and
    -- writing through the same batch-aware helpers the stock checkboxes used,
    -- so the store side of this section is untouched. opts.filter scopes the
    -- batch read to the write filter, opts.indent marks a child row, and
    -- opts.tooltip chains a "?" badge off the end of the label.
    local function AddVisibilityRow(column, label, field, opts)
        local row = AddCheckboxRow(column, {
            label = label,
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

    -- Every toggle here belongs to a FAMILY: one parent condition plus the
    -- fallback/refinement children it gates. Which families survive depends on
    -- the entry type and on what is already checked, so this is a FILTERED row
    -- set (see the fill rule in the recipe comment at the top of
    -- BuildAppearanceTab's icons path): the families are collected first, then
    -- poured into the grid LEFT column first until it holds half the rows. A
    -- family is never split across the columns - a child that only exists
    -- while its parent is checked has to sit directly under it.
    local families, totalRows = {}, 0
    local function AddFamily(rows, build)
        families[#families + 1] = { rows = rows, build = build }
        totalRows = totalRows + rows
    end

    -- Ordinary Texture spell entries may layer presence-only Aura display onto
    -- their spell behavior. Primary Aura entries are always Aura-controlled,
    -- so only spell entries receive this opt-in.
    if not isBatch and isTexturePanel and buttonData.type == "spell"
        and buttonData.addedAs ~= "aura" then
        AddFamily(1, function(column)
            AddVisibilityRow(column, "Show Texture While Aura Active", "textureAuraDisplayEnabled", {
                tooltip = {
                    "Show Texture While Aura Active",
                    {"Blizzard tracks the aura and directly controls whether the configured texture is shown. The addon never reads aura state in combat.", 1, 1, 1, true},
                    {" ", 1, 1, 1, true},
                    {"This is presence-only: duration, stacks, and group-member tracking are not displayed. An optional active-aura effect can be configured in the Indicators tab.", 1, 1, 1, true},
                },
                onChanged = function(widget, event, val)
                    ST._SetTexturePanelAuraDisplayEnabled(group, buttonData, val, CS.selectedGroup)
                    CooldownCompanion:RefreshAllGroups()
                    CooldownCompanion:RequestAuraRebind("config")
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end)
    end

    -- Show Only While Aura Active (aura entries). 12.1: applied statically —
    -- the aura display composes the whole button over an invisible CC shell,
    -- so this needs a restyle + rebind, not the per-tick visibility bits.
    local function FilterAuraEntry(bd)
        return bd.type == "spell" and (bd.auraTracking or bd.addedAs == "aura")
    end
    local function ApplyToAuraEntries(field, value)
        if isBatch then
            for idx in pairs(CS.selectedButtons) do
                local bd = group.buttons[idx]
                if bd then
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
    -- Icon and bar groups (both compose a full shell); text mode has no aura
    -- display at all.
    local displayMode = group.displayMode or "icons"
    if anyAuraEntry and (displayMode == "icons" or displayMode == "bars") then
        -- Two mutually exclusive inactive-state presentations, stored as
        -- independent single keys. The dim key is auraShellDim, new in 12.1
        -- and deliberately not main's useBaselineAlphaFallback: that key's
        -- presence could not be told apart from residue, so the migration
        -- had to guess and guessed away live settings.
        AddFamily(2, function(column)
            AddVisibilityRow(column, "Show Only While Aura Active", "hideWhileAuraNotActive", {
                filter = FilterAuraEntry,
                tooltip = {
                    "Show Only While Aura Active",
                    {"Hides this entry until its tracked aura is active.", 1, 1, 1, true},
                    {" ", 1, 1, 1},
                    {"In Compact Mode panels the aura still reserves its space while hidden. The game hides whether auras are active from addons, so other entries cannot close the gap.", 1, 1, 1, true},
                },
                onChanged = function(widget, event, val)
                    ApplyToAuraEntries("hideWhileAuraNotActive", val or nil)
                    if val then
                        ApplyToAuraEntries("auraShellDim", nil)
                    end
                    CooldownCompanion:RefreshAllGroups()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })

            AddVisibilityRow(column, "Dim While Aura Inactive", "auraShellDim", {
                filter = FilterAuraEntry,
                tooltip = {
                    "Dim While Aura Inactive",
                    {"Shows this entry dimmed until its tracked aura is active, then at full strength while it runs.", 1, 1, 1, true},
                },
                onChanged = function(widget, event, val)
                    ApplyToAuraEntries("auraShellDim", val or nil)
                    if val then
                        ApplyToAuraEntries("hideWhileAuraNotActive", nil)
                    end
                    CooldownCompanion:RefreshAllGroups()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end)
    end

    -- Hide While On Cooldown (skip for passives — no cooldown)
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
    -- Dim Instead Of Hide (nested under hideWhileOnCooldown)
    local showFallbackOnCooldown
    if isBatch then showFallbackOnCooldown = AnySelectedHas(group, "hideWhileOnCooldown")
    else showFallbackOnCooldown = buttonData.hideWhileOnCooldown end
    showFallbackOnCooldown = showFallbackOnCooldown and not isTexturePanel

    AddFamily(showFallbackOnCooldown and 2 or 1, function(column)
        AddVisibilityRow(column, "Hide While On Cooldown", "hideWhileOnCooldown", {
            onChanged = function(widget, event, val)
                ApplyToSelected("hideWhileOnCooldown", val or nil)
                if val then
                    ApplyToSelected("hideWhileNotOnCooldown", nil)
                    ApplyToSelected("useBaselineAlphaFallbackNotOnCooldown", nil)
                    ApplyToChargeSpell("showOnlyAtZeroCharges", nil)
                else
                    ApplyToSelected("useBaselineAlphaFallbackOnCooldown", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if showFallbackOnCooldown then
            AddVisibilityRow(column, "Dim Instead Of Hide", "useBaselineAlphaFallbackOnCooldown", {
                indent = true,
                tooltip = DIM_INSTEAD_OF_HIDE_TOOLTIP,
                onChanged = function(widget, event, val)
                    ApplyToSelected("useBaselineAlphaFallbackOnCooldown", val or nil)
                end,
            })
        end
    end)

    -- Hide While Not On Cooldown, with its charge refinement and fallback
    local showOnlyAtZeroCharges
    if isBatch then
        showOnlyAtZeroCharges = AnySelectedMatch(FilterChargeSpellNotOnCooldown)
    else
        showOnlyAtZeroCharges = buttonData.hideWhileNotOnCooldown
            and FilterChargeSpell(buttonData)
    end
    local showFallbackNotOnCooldown
    if isBatch then showFallbackNotOnCooldown = AnySelectedHas(group, "hideWhileNotOnCooldown")
    else showFallbackNotOnCooldown = buttonData.hideWhileNotOnCooldown end
    showFallbackNotOnCooldown = showFallbackNotOnCooldown and not isTexturePanel

    local notOnCooldownRows = 1
    if showOnlyAtZeroCharges then notOnCooldownRows = notOnCooldownRows + 1 end
    if showFallbackNotOnCooldown then notOnCooldownRows = notOnCooldownRows + 1 end

    AddFamily(notOnCooldownRows, function(column)
        AddVisibilityRow(column, "Hide While Not On Cooldown", "hideWhileNotOnCooldown", {
            onChanged = function(widget, event, val)
                ApplyToSelected("hideWhileNotOnCooldown", val or nil)
                if val then
                    ApplyToSelected("hideWhileOnCooldown", nil)
                    ApplyToSelected("useBaselineAlphaFallbackOnCooldown", nil)
                else
                    ApplyToSelected("useBaselineAlphaFallbackNotOnCooldown", nil)
                    ApplyToChargeSpell("showOnlyAtZeroCharges", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if showOnlyAtZeroCharges then
            AddVisibilityRow(column, "Only Show At Zero Charges", "showOnlyAtZeroCharges", {
                indent = true,
                filter = FilterChargeSpellNotOnCooldown,
                onChanged = function(widget, event, val)
                    ApplyToChargeSpellNotOnCooldown("showOnlyAtZeroCharges", val or nil)
                    if val then
                        ApplyToChargeSpellNotOnCooldownOnly("useBaselineAlphaFallbackNotOnCooldown", nil)
                        ApplyToChargeSpellNotOnCooldownOnly("hideWhileZeroCharges", nil)
                        ApplyToChargeSpellNotOnCooldownOnly("useBaselineAlphaFallbackZeroCharges", nil)
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end

        if showFallbackNotOnCooldown then
            AddVisibilityRow(column, "Dim Instead Of Hide", "useBaselineAlphaFallbackNotOnCooldown", {
                indent = true,
                tooltip = DIM_INSTEAD_OF_HIDE_TOOLTIP,
                onChanged = function(widget, event, val)
                    ApplyToSelected("useBaselineAlphaFallbackNotOnCooldown", val or nil)
                    if val then
                        ApplyToChargeSpellNotOnCooldownOnly("showOnlyAtZeroCharges", nil)
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end
    end)

    end -- not allPassive and not allNoCooldown

    if not allPassive then
    if not allNeverUnusable then
    -- Hide While Unusable
    local showFallbackUnusable
    if isBatch then showFallbackUnusable = AnySelectedHas(group, "hideWhileUnusable")
    else showFallbackUnusable = buttonData.hideWhileUnusable end
    showFallbackUnusable = showFallbackUnusable and not isTexturePanel

    AddFamily(showFallbackUnusable and 2 or 1, function(column)
        AddVisibilityRow(column, "Hide While Unusable", "hideWhileUnusable", {
            tooltip = {
                "Hide While Unusable",
                {"Uses the same logic as Unusable Visual, but completely hides the button instead of changing the icon.", 1, 1, 1, true},
            },
            onChanged = function(widget, event, val)
                ApplyToSelected("hideWhileUnusable", val or nil)
                if not val then
                    ApplyToSelected("useBaselineAlphaFallbackUnusable", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if showFallbackUnusable then
            AddVisibilityRow(column, "Dim Instead Of Hide", "useBaselineAlphaFallbackUnusable", {
                indent = true,
                tooltip = DIM_INSTEAD_OF_HIDE_TOOLTIP,
                onChanged = function(widget, event, val)
                    ApplyToSelected("useBaselineAlphaFallbackUnusable", val or nil)
                end,
            })
        end
    end)
    end -- not allNeverUnusable

    -- Hide While No Proc (spell entries only, not aura entries)
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
        local showFallbackNoProc
        if isBatch then showFallbackNoProc = AnySelectedHas(group, "hideWhileNoProc")
        else showFallbackNoProc = buttonData.hideWhileNoProc end
        showFallbackNoProc = showFallbackNoProc and not isTexturePanel

        AddFamily(showFallbackNoProc and 2 or 1, function(column)
            AddVisibilityRow(column, "Hide While No Proc", "hideWhileNoProc", {
                onChanged = function(widget, event, val)
                    ApplyToSelected("hideWhileNoProc", val or nil)
                    if not val then
                        ApplyToSelected("useBaselineAlphaFallbackNoProc", nil)
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })

            if showFallbackNoProc then
                AddVisibilityRow(column, "Dim Instead Of Hide", "useBaselineAlphaFallbackNoProc", {
                    indent = true,
                    tooltip = DIM_INSTEAD_OF_HIDE_TOOLTIP,
                    onChanged = function(widget, event, val)
                        ApplyToSelected("useBaselineAlphaFallbackNoProc", val or nil)
                    end,
                })
            end
        end)
    end

    end -- not allPassive (unusable + no proc)

    -- Charge-based visibility toggles (spells + non-equippable items with charges)
    -- Batch: show if any selected button is charge-capable
    local showChargeSection
    if isBatch then showChargeSection = AnySelectedChargeCapable(group)
    else
        showChargeSection = UsesChargeBehavior(buttonData)
            and (buttonData.type == "spell" or (isItem and not CooldownCompanion.IsItemEquippable(buttonData)))
            and not HasItemFallbacks(buttonData)
    end
    if showChargeSection then
        -- Hide While At Zero Charges
        -- Batch: the nested fallback shows if any selected has it on
        local showFallbackZeroCharges
        if isBatch then showFallbackZeroCharges = AnySelectedHasFiltered(group, "hideWhileZeroCharges", FilterChargeCapable)
        else showFallbackZeroCharges = buttonData.hideWhileZeroCharges end
        showFallbackZeroCharges = showFallbackZeroCharges and not isTexturePanel

        AddFamily(showFallbackZeroCharges and 2 or 1, function(column)
            AddVisibilityRow(column, "Hide While At Zero Charges", "hideWhileZeroCharges", {
                filter = FilterChargeCapable,
                onChanged = function(widget, event, val)
                    ApplyToChargeCapable("hideWhileZeroCharges", val or nil)
                    if val then
                        ApplyToChargeCapable("desaturateWhileZeroCharges", nil)
                        ApplyToChargeSpell("showOnlyAtZeroCharges", nil)
                    else
                        ApplyToChargeCapable("useBaselineAlphaFallbackZeroCharges", nil)
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })

            if showFallbackZeroCharges then
                AddVisibilityRow(column, "Dim Instead Of Hide", "useBaselineAlphaFallbackZeroCharges", {
                    indent = true,
                    filter = FilterChargeCapable,
                    tooltip = DIM_INSTEAD_OF_HIDE_TOOLTIP,
                    onChanged = function(widget, event, val)
                        ApplyToChargeCapable("useBaselineAlphaFallbackZeroCharges", val or nil)
                    end,
                })
            end
        end)

        -- Desaturate While At Zero Charges
        if not isTexturePanel then
            AddFamily(1, function(column)
                AddVisibilityRow(column, "Desaturate While At Zero Charges", "desaturateWhileZeroCharges", {
                    filter = FilterChargeCapable,
                    onChanged = function(widget, event, val)
                        ApplyToChargeCapable("desaturateWhileZeroCharges", val or nil)
                        if val then
                            ApplyToChargeCapable("hideWhileZeroCharges", nil)
                            ApplyToChargeCapable("useBaselineAlphaFallbackZeroCharges", nil)
                        end
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })
            end)
        end

        -- Hide Cooldown While Charges Remain
        AddFamily(1, function(column)
            AddVisibilityRow(column, "Hide Cooldown While Charges Remain", "hideCooldownWithCharges", {
                filter = FilterChargeCapable,
                onChanged = function(widget, event, val)
                    ApplyToChargeCapable("hideCooldownWithCharges", val or nil)
                end,
            })
        end)
    end

    -- Stack-based visibility toggles (non-equippable items without charges)
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
            local zeroStacksLabel = fallbackItemUses and "Hide While No Uses Available" or "Hide While At Zero Stacks"
            local desatStacksLabel = fallbackItemUses and "Desaturate While No Uses Available" or "Desaturate While At Zero Stacks"

            -- Hide While At Zero Stacks
            local showFallbackZeroStacks
            if isBatch then showFallbackZeroStacks = AnySelectedHasFiltered(group, "hideWhileZeroStacks", FilterNonEquippable)
            else showFallbackZeroStacks = buttonData.hideWhileZeroStacks end
            showFallbackZeroStacks = showFallbackZeroStacks and not isTexturePanel

            AddFamily(showFallbackZeroStacks and 2 or 1, function(column)
                AddVisibilityRow(column, zeroStacksLabel, "hideWhileZeroStacks", {
                    filter = FilterNonEquippable,
                    onChanged = function(widget, event, val)
                        ApplyToNonEquippable("hideWhileZeroStacks", val or nil)
                        if val then
                            ApplyToNonEquippable("desaturateWhileZeroStacks", nil)
                        else
                            ApplyToNonEquippable("useBaselineAlphaFallbackZeroStacks", nil)
                        end
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                })

                if showFallbackZeroStacks then
                    AddVisibilityRow(column, "Dim Instead Of Hide", "useBaselineAlphaFallbackZeroStacks", {
                        indent = true,
                        filter = FilterNonEquippable,
                        tooltip = DIM_INSTEAD_OF_HIDE_TOOLTIP,
                        onChanged = function(widget, event, val)
                            ApplyToNonEquippable("useBaselineAlphaFallbackZeroStacks", val or nil)
                        end,
                    })
                end
            end)

            -- Desaturate While At Zero Stacks
            if not isTexturePanel then
                AddFamily(1, function(column)
                    AddVisibilityRow(column, desatStacksLabel, "desaturateWhileZeroStacks", {
                        filter = FilterNonEquippable,
                        onChanged = function(widget, event, val)
                            ApplyToNonEquippable("desaturateWhileZeroStacks", val or nil)
                            if val then
                                ApplyToNonEquippable("hideWhileZeroStacks", nil)
                                ApplyToNonEquippable("useBaselineAlphaFallbackZeroStacks", nil)
                            end
                            CooldownCompanion:RefreshConfigPanel()
                        end,
                    })
                end)
            end
        end
    end

    -- Hide While Not Equipped (equippable items only)
    -- Batch: show if any selected item is equippable
    local showEquipSection
    if isBatch then showEquipSection = isItem and AnySelectedEquippable(group)
    else showEquipSection = isItem and CooldownCompanion.IsItemEquippable(buttonData) end
    if showEquipSection then
        local showFallbackEquip
        if isBatch then showFallbackEquip = AnySelectedHasFiltered(group, "hideWhileNotEquipped", FilterEquippable)
        else showFallbackEquip = buttonData.hideWhileNotEquipped end
        showFallbackEquip = showFallbackEquip and not isTexturePanel

        AddFamily(showFallbackEquip and 2 or 1, function(column)
            AddVisibilityRow(column, "Hide While Not Equipped", "hideWhileNotEquipped", {
                filter = FilterEquippable,
                onChanged = function(widget, event, val)
                    ApplyToEquippable("hideWhileNotEquipped", val or nil)
                    if not val then
                        ApplyToEquippable("useBaselineAlphaFallbackNotEquipped", nil)
                    end
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })

            if showFallbackEquip then
                AddVisibilityRow(column, "Dim Instead Of Hide", "useBaselineAlphaFallbackNotEquipped", {
                    indent = true,
                    filter = FilterEquippable,
                    tooltip = DIM_INSTEAD_OF_HIDE_TOOLTIP,
                    onChanged = function(widget, event, val)
                        ApplyToEquippable("useBaselineAlphaFallbackNotEquipped", val or nil)
                    end,
                })
            end
        end)
    end

    -- An entry type can filter every family away (a passive with no cooldown
    -- in a texture panel), and an empty grid is still a widget - so only open
    -- one when there is something to pour into it.
    if totalRows > 0 then
        local visLeft, visRight = BeginRowGrid(scroll)
        local placed, half = 0, math.ceil(totalRows / 2)
        for _, family in ipairs(families) do
            family.build(placed < half and visLeft or visRight)
            placed = placed + family.rows
        end
    end

    end -- not visCollapsed
    end -- not hideShowConditions

    if insertBeforeTalents then
        insertBeforeTalents()
    end

    ------------------------------------------------------------------------
    -- TALENT CONDITIONS (independent section, not nested under Show Conditions)
    ------------------------------------------------------------------------

    local talentKey = isBatch
        and (CS.selectedGroup .. "_batch_talentcondition")
        or  (CS.selectedGroup .. "_" .. CS.selectedButton .. "_talentcondition")
    local talentHeading, talentCollapsed = BuildCollapsibleSection(scroll, "Talent Conditions", talentKey,
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
        hasTalent = GetBatchFieldValue(group, "talentConditions")
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

    -- One-column row grid, the same shape this section already has on the
    -- custom-bar tab. Conditions are ITEM rows: a CDC-LabelRow with the
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

    local pickBtn = AceGUI:Create("Button")
    pickBtn:SetText(condCount > 0 and "Edit" or "Pick Talents")
    pickBtn:SetHeight(ACTION_STRIP_BUTTON_HEIGHT)
    pickBtn:SetCallback("OnClick", function()
        local initialConditions = not isBatch and buttonData.talentConditions or nil
        CooldownCompanion:OpenTalentPicker(function(results)
            if results then
                local normalized, changed = CooldownCompanion:NormalizeTalentConditions(results)
                if changed then
                    results = normalized
                end
            end
            if results then
                -- Deep-copy each condition for batch mode safety
                if CS.selectedButtons then
                    local count = 0
                    for _ in pairs(CS.selectedButtons) do count = count + 1 end
                    if count >= 2 then
                        for idx in pairs(CS.selectedButtons) do
                            local bd = group.buttons[idx]
                            if bd then
                                local copy = {}
                                for i, cond in ipairs(results) do
                                    copy[i] = {
                                        nodeID  = cond.nodeID,
                                        entryID = cond.entryID,
                                        spellID = cond.spellID,
                                        name    = cond.name,
                                        show    = cond.show,
                                        classID = cond.classID,
                                        className = cond.className,
                                        specID = cond.specID,
                                        specName = cond.specName,
                                        heroSubTreeID = cond.heroSubTreeID,
                                        heroName = cond.heroName,
                                    }
                                end
                                bd.talentConditions = copy
                                -- Clean old fields for migration safety
                                bd.talentNodeID  = nil
                                bd.talentEntryID = nil
                                bd.talentSpellID = nil
                                bd.talentName    = nil
                                bd.talentShow    = nil
                            end
                        end
                    else
                        buttonData.talentConditions = results
                        buttonData.talentNodeID  = nil
                        buttonData.talentEntryID = nil
                        buttonData.talentSpellID = nil
                        buttonData.talentName    = nil
                        buttonData.talentShow    = nil
                    end
                else
                    buttonData.talentConditions = results
                    buttonData.talentNodeID  = nil
                    buttonData.talentEntryID = nil
                    buttonData.talentSpellID = nil
                    buttonData.talentName    = nil
                    buttonData.talentShow    = nil
                end
            else
                -- Clear all
                ApplyToSelected("talentConditions", nil)
                ApplyToSelected("talentNodeID", nil)
                ApplyToSelected("talentEntryID", nil)
                ApplyToSelected("talentSpellID", nil)
                ApplyToSelected("talentName", nil)
                ApplyToSelected("talentShow", nil)
            end
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, initialConditions, group)
    end)

    local talentActionControl
    if hasTalent then
        -- Edit and Clear split the control column. Clear is destructive, so
        -- it shares the row with the picker that owns what it clears. Flow
        -- packs siblings at 0px, so the gutter is a fixed-size spacer group -
        -- the same idiom the preset trio uses.
        local strip = AceGUI:Create("SimpleGroup")
        strip:SetLayout("Flow")
        strip:SetWidth(ROW_CONTROL_WIDTH)
        strip:SetHeight(ACTION_STRIP_HEIGHT)
        strip.noAutoHeight = true

        pickBtn:SetWidth((ROW_CONTROL_WIDTH - ACTION_STRIP_GUTTER) / 2)
        strip:AddChild(pickBtn)

        local gutter = AceGUI:Create("SimpleGroup")
        gutter:SetWidth(ACTION_STRIP_GUTTER)
        gutter:SetHeight(ACTION_STRIP_BUTTON_HEIGHT)
        gutter.noAutoHeight = true
        strip:AddChild(gutter)

        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear")
        clearBtn:SetHeight(ACTION_STRIP_BUTTON_HEIGHT)
        clearBtn:SetWidth((ROW_CONTROL_WIDTH - ACTION_STRIP_GUTTER) / 2)
        clearBtn:SetCallback("OnClick", function()
            ApplyToSelected("talentConditions", nil)
            ApplyToSelected("talentNodeID", nil)
            ApplyToSelected("talentEntryID", nil)
            ApplyToSelected("talentSpellID", nil)
            ApplyToSelected("talentName", nil)
            ApplyToSelected("talentShow", nil)
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        strip:AddChild(clearBtn)

        talentActionControl = strip
    else
        pickBtn:SetWidth(ROW_CONTROL_WIDTH)
        talentActionControl = pickBtn
    end

    AddLabelRow(talentLeft, {
        label = talentStatusText,
        controlWidget = talentActionControl,
    })

    end -- not talentCollapsed

end

------------------------------------------------------------------------
-- VISIBILITY TAB (internal tab key stays "loadconditions")
------------------------------------------------------------------------

-- Raw (non-AceGUI) frames the previous tab left parented to widgets AceGUI
-- is about to recycle. Cleared on the way in to whichever half of the
-- Visibility tab builds, so a leftover badge cannot ride a pooled frame.
local function ReleaseVisibilityTabScratch()
    for _, btn in ipairs(tabInfoButtons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(tabInfoButtons)
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)
end

local function BuildLoadConditionsTab(container)
    ReleaseVisibilityTabScratch()

    if not CS.selectedGroup then return end
    local groupId = CS.selectedGroup
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end

    -- Ensure loadConditions table exists
    if not group.loadConditions then
        group.loadConditions = {
            raid = false, dungeon = false, delve = false, battleground = false,
            arena = false, openWorld = false, rested = false, petBattle = true,
            vehicleUI = true,
        }
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

    -- The tab reads as two halves under an optional inherited summary: who the
    -- panel is for, then where it stays hidden. Row grammar (RowWidgets.lua)
    -- throughout - see the recipe comment at the top of BuildAppearanceTab's
    -- icons path in GroupTabsAppearance.lua. Nothing on this tab carries a gear, so
    -- there is no advanced-panel queue to keep uncollapsed.
    AddInheritedLoadSummary(container, inheritedSources, "loadconditions_panel_inherited")

    local _, whoCollapsed = BuildCollapsibleSection(container, "Who Can Use This",
        "loadconditions_panel_who", nil, nil, ROW_SECTION)

    if not whoCollapsed then
        if inheritedSpecFilter or inheritedHeroFilter then
            local inheritedLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(inheritedLabel)
            inheritedLabel:SetText("|cff888888Some rules are inherited from group settings.|r")
            inheritedLabel:SetFullWidth(true)
            container:AddChild(inheritedLabel)
        end

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
            omitHeading = true,
            showSelectedRows = true,
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
        defaults = CooldownCompanion:GetDefaultLoadConditions(),
        inheritedSources = inheritedSources,
        skipInheritedSummary = true,
        headingText = "Where To Hide It",
        localCollapsedKey = "loadconditions_panel_local",
        row = true,
        infoTooltipLines = BuildWhereToHideTooltip("panel", true),
        infoButtons = tabInfoButtons,
        onChanged = RefreshPanelLoadConditions,
    })

    -- ============================================================
    -- Alpha (moved here from the Layout tab: transparency behavior
    -- reads as visibility, not layout)
    -- ============================================================
    -- Same gating the Layout tab applied: a panel whose alpha is owned
    -- elsewhere (Group Alpha, or an anchor it inherits from) shows the
    -- section disabled with the reason. Derived from stored anchors
    -- rather than the Layout tab's target-mode UI state; the two agree
    -- because an unresolved or addon-internal target never inherits.
    local alphaControlsDisabled, alphaDisabledText = false, nil
    if CooldownCompanion.GetPanelContainerAlphaSource
        and CooldownCompanion:GetPanelContainerAlphaSource(groupId) then
        alphaControlsDisabled = true
        alphaDisabledText = "Group Alpha is enabled. This panel uses the group's Alpha settings."
    elseif CooldownCompanion.ShouldInheritPanelAnchorAlpha
        and CooldownCompanion:ShouldInheritPanelAnchorAlpha(groupId) then
        alphaControlsDisabled = true
        alphaDisabledText = "This panel inherits alpha from the parent panel. Change the parent panel's Alpha settings to affect it."
    elseif group.parentContainerId and group.inheritPanelAlpha ~= false then
        local anchorSettings = CooldownCompanion.GetStandaloneTextureAnchorSettings
            and CooldownCompanion:GetStandaloneTextureAnchorSettings(group)
        local relativeTo = anchorSettings and anchorSettings.relativeTo
        if not relativeTo then
            local anchor = group.anchor
            relativeTo = type(anchor) == "table" and anchor.relativeTo or anchor
        end
        if type(relativeTo) == "string" and relativeTo ~= "" and relativeTo ~= "UIParent"
            and CooldownCompanion:ParseAddonAnchorFrameName(relativeTo) == nil then
            local target = _G[relativeTo]
            if type(target) == "table" and type(target.GetObjectType) == "function" then
                alphaControlsDisabled = true
                alphaDisabledText = "This panel inherits alpha from the target frame. Change the Panel Alpha setting on the Layout tab to use custom alpha."
            end
        end
    end

    local isTexturePanel = group.displayMode == "textures" or group.displayMode == "trigger"
    if isTexturePanel then
        BuildAlphaControls(container, group, function()
            CooldownCompanion:RefreshAllAuraTextureVisuals()
            CooldownCompanion:RefreshConfigPanel()
        end, "loadconditions_alpha", {
            isGlobal = group.isGlobal,
            row = true,
            disabled = alphaControlsDisabled,
            disabledText = alphaDisabledText,
            onBaselineCommitted = function()
                CooldownCompanion:RefreshAllAuraTextureVisuals()
            end,
        })
    else
        BuildAlphaControls(container, group, function()
            CooldownCompanion:RefreshConfigPanel()
        end, "loadconditions_alpha", {
            isGlobal = group.isGlobal,
            row = true,
            disabled = alphaControlsDisabled,
            disabledText = alphaDisabledText,
        })
    end
end

local function BuildEntryLoadConditionsTab(container, buttonData, infoButtons)
    if not (CS.selectedGroup and buttonData) then return end
    local groupId = CS.selectedGroup
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end

    -- Entry scope mirrors the panel tab, minus the eligibility half: an entry
    -- inherits who its panel is for and can only add places to hide.
    local _, togglesRight = AddScopedLoadConditionToggles(container, {
        target = buttonData,
        defaults = CooldownCompanion:GetLocalLoadConditionDefaults(),
        inheritedSources = CooldownCompanion:GetLoadConditionSourcesForGroup(group),
        headingText = "Where To Hide It",
        inheritedCollapsedKey = "loadconditions_entry_inherited",
        localCollapsedKey = "loadconditions_entry_local",
        preserveMissing = true,
        row = true,
        infoTooltipLines = BuildWhereToHideTooltip("entry", false),
        infoButtons = infoButtons,
        onChanged = function()
            if buttonData.loadConditions and not next(buttonData.loadConditions) then
                buttonData.loadConditions = nil
            end
            CooldownCompanion:RefreshGroupFrame(groupId)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if CooldownCompanion:HasLocalLoadConditions(buttonData) then
        -- Compact and flush left, filling the shorter (4-row) right column's
        -- tail. With the section collapsed there is no grid to sit in, so it
        -- falls back to the tab surface - still reachable, still compact.
        local clearHost = togglesRight or container
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Entry Visibility Rules")
        clearBtn:SetAutoWidth(true)
        clearBtn:SetCallback("OnClick", function()
            buttonData.loadConditions = nil
            CooldownCompanion:RefreshGroupFrame(groupId)
            CooldownCompanion:RefreshConfigPanel()
        end)
        clearHost:AddChild(clearBtn)
    end
end

-- There is one Visibility tab, and it is a lens: with a single entry
-- selected it edits that entry's rules, and with nothing (or a multi-select)
-- selected it edits the panel's. The rotation assistant's virtual entry is
-- served here too - it has no entry tabs of its own.
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
            if CS.selectedRotationAssistantEntry == true
                and CooldownCompanion:IsRotationAssistantGroup(group) then
                local buttonData = CooldownCompanion:GetRotationAssistantConfigButtonData(group)
                if buttonData then
                    ReleaseVisibilityTabScratch()
                    BuildEntryLoadConditionsTab(container, buttonData, tabInfoButtons)
                    return
                end
            elseif CS.selectedButton then
                local buttonData = group.buttons and group.buttons[CS.selectedButton]
                if buttonData then
                    ReleaseVisibilityTabScratch()
                    BuildEntryLoadConditionsTab(container, buttonData, tabInfoButtons)
                    return
                end
            end
        end
    end

    BuildLoadConditionsTab(container)
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._BuildVisibilitySettings = BuildVisibilitySettings
ST._BuildLoadConditionsTab = BuildLoadConditionsTab
ST._BuildEntryLoadConditionsTab = BuildEntryLoadConditionsTab
ST._BuildVisibilityTab = BuildVisibilityTab
ST._AddScopedLoadConditionToggles = AddScopedLoadConditionToggles
ST._BuildWhereToHideTooltip = BuildWhereToHideTooltip
ST._AddCharacterEligibilityControls = AddCharacterEligibilityControls
ST._AddClassSpecEligibilityControls = AddClassSpecEligibilityControls
ST._GetConditionDisplayName = GetConditionDisplayName
ST._GetConditionListContextSuffix = GetConditionListContextSuffix
