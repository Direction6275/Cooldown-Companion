--[[
    CooldownCompanion - ResourceBarPanelsCustomBars
    Config panel builders for the Custom Bars list, editor, tabs,
    badges, row actions, and preview toggles.
    Query helpers and shared builders live in ResourceBarPanelsHelpers.lua.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local IsPassiveOrProc = ST._IsPassiveOrProc
local ShowPopupAboveConfig = CS.ShowPopupAboveConfig
local SelectConfigCustomBar = ST._SelectConfigCustomBar
local ClearConfigCustomBarSelection = ST._ClearConfigCustomBarSelection

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local AddColorPicker = ST._AddColorPicker
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown

-- Imports from RowWidgets.lua (the row grammar). The rules every row-grammar
-- section follows are stated once, in the recipe comment at the top of
-- BuildAppearanceTab's icons path (GroupTabs.lua); this file conforms to them
-- rather than restating them.
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddColorRow = ST._AddColorRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddLabelRow = ST._AddLabelRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- Sound option labels read "Category - Name" and run well past the 140px
-- control column, and a dropdown sizes its menu from the control.
local SOUND_PULLOUT_WIDTH = 300

local function RefreshLayoutOrderPreview()
    -- Both the Resources home and the Cast Bar & Unit Frames home pin the
    -- preview in the workspace; the helper self-gates on view state.
    if ST._RefreshResourcesLayoutPreview then
        ST._RefreshResourcesLayoutPreview()
    end
end

local function BlockCustomBarExportForResourceBarConflict()
    if CooldownCompanion.GetCurrentResourceBarConflictExportMessage then
        local message = CooldownCompanion:GetCurrentResourceBarConflictExportMessage()
        if message then
            CooldownCompanion:Print(message)
            return true
        end
    end
    return false
end

-- Shared constants from ResourceBarConstants
local RB = ST._RB
local DEFAULT_RESOURCE_TEXT_FONT = RB.DEFAULT_RESOURCE_TEXT_FONT
local DEFAULT_RESOURCE_TEXT_SIZE = RB.DEFAULT_RESOURCE_TEXT_SIZE
local DEFAULT_RESOURCE_TEXT_OUTLINE = RB.DEFAULT_RESOURCE_TEXT_OUTLINE
local DEFAULT_RESOURCE_TEXT_COLOR = RB.DEFAULT_RESOURCE_TEXT_COLOR
local GetCustomBarEntryType = RB.GetCustomBarEntryType
local EnsureCustomBarId = RB.EnsureCustomBarId
local EnsureCustomBarLayout = RB.EnsureCustomBarLayout
local GetCustomBarLayout = RB.GetCustomBarLayout
local resourceSpecCopyButton
local resourceSpecCopyMenu

local function IsHeroSpecProxyCondition(cond)
    return type(cond) == "table"
        and cond.nodeID ~= nil
        and cond.heroSubTreeID ~= nil
        and cond.entryID == nil
        and type(cond.name) == "string"
        and type(cond.heroName) == "string"
        and cond.name == cond.heroName
end
local function IsSpellCustomBarConfig(cab)
    if RB.IsSpellCustomBarConfig then
        return RB.IsSpellCustomBarConfig(cab)
    end
    return GetCustomBarEntryType and GetCustomBarEntryType(cab) == "spell"
end

-- Imports from ResourceBarPanelsHelpers
local RBP = ST._RBP
local resourceBarCollapsedSections = RBP.collapsedSections
local BuildResourceBarConflictGate = RBP.BuildResourceBarConflictGate
local GetCurrentConfigSpecID = RBP.GetCurrentConfigSpecID
local ResolveAuraColorSpellIDFromText = RBP.ResolveAuraColorSpellIDFromText
local GetAuraBarAutocompleteDisplayName = RBP.GetAuraBarAutocompleteDisplayName
local GetAuraBarAutocompleteDisplayIcon = RBP.GetAuraBarAutocompleteDisplayIcon
local GetAuraBarAutocompleteEntryName = RBP.GetAuraBarAutocompleteEntryName
local ResolveAuraBarAutocompleteEntry = RBP.ResolveAuraBarAutocompleteEntry
local ShowAuraBarAutocompleteResults = RBP.ShowAuraBarAutocompleteResults
local BuildAuraBarAutocompleteCache = RBP.BuildAuraBarAutocompleteCache
local GetResourceThicknessFieldConfig = RBP.GetResourceThicknessFieldConfig
local CopyTableValue = RBP.CopyTableValue

------------------------------------------------------------------------
-- Custom Bars detail panel
------------------------------------------------------------------------

local function ApplyCustomAuraBarPanelChanges(opts)
    CooldownCompanion:ApplyResourceBars()
    if opts and opts.updateAnchors then
        CooldownCompanion:UpdateAnchorStacking()
    end
    if opts and opts.refreshConfig then
        CooldownCompanion:RefreshConfigPanel()
    end
    if opts and opts.refreshLayoutPreview then
        RefreshLayoutOrderPreview()
    end
end

local function FindCustomBarIndexById(customBars, customBarId)
    if type(customBars) ~= "table" or type(customBarId) ~= "string" then
        return nil
    end
    for index, entry in ipairs(customBars) do
        if type(entry) == "table" and entry.customBarId == customBarId then
            return index
        end
    end
    return nil
end

local function GetCustomBarSpecOptions()
    local specs = {}
    local _, _, classID = UnitClass("player")
    local numSpecs = classID
        and C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
        or 0
    for specIndex = 1, numSpecs do
        local specID, specName, _, specIcon = C_SpecializationInfo.GetSpecializationInfo(
            specIndex,
            false,
            false,
            nil,
            nil,
            nil,
            classID
        )
        if specID then
            specs[#specs + 1] = {
                id = specID,
                name = specName or ("Spec " .. tostring(specID)),
                icon = specIcon,
            }
        end
    end
    return specs
end

-- Every collapsible section on a Custom Bar's tabs is keyed per bar, so
-- collapsing one bar's section leaves the next bar's alone.
local function GetCustomBarCollapseKey(cab)
    return tostring((type(cab) == "table" and cab.customBarId) or "")
end

local function AddCustomBarSection(container, title, name, key)
    return BuildCollapsibleSection(container, title, "cab_" .. name .. "_" .. key,
        resourceBarCollapsedSections, nil, ROW_SECTION)
end

-- One CDC-CheckBoxRow per spec this class can play, split down the middle of
-- the caller's grid. The store writes are untouched: this path deliberately
-- does NOT go through SetSpecFilterValue/SetSpecAllowlistValue, it drives
-- RB.AddCustomBarToSpec/RB.RemoveCustomBarFromSpec directly.
local function AddCustomBarSpecFilterControls(specLeft, specRight, settings, entry, currentSpecID)
    local specs = GetCustomBarSpecOptions()
    local splitAt = math.ceil(#specs / 2)
    for index, spec in ipairs(specs) do
        local capturedSpec = spec
        -- The spec icon rides an inline texture escape in the label text: a
        -- row label is a FontString, so there is no SetImage to hang it off
        -- the way the stock checkbox did.
        local label = capturedSpec.name
        if capturedSpec.icon then
            label = ("|T%s:16:16:0:0|t %s"):format(tostring(capturedSpec.icon), label)
        end
        AddCheckboxRow(index <= splitAt and specLeft or specRight, {
            label = label,
            value = RB.CustomBarHasExplicitSpec and RB.CustomBarHasExplicitSpec(entry, capturedSpec.id) or false,
            onChange = function(value)
                if value then
                    if RB.AddCustomBarToSpec then
                        RB.AddCustomBarToSpec(settings, entry, capturedSpec.id, currentSpecID)
                    end
                else
                    if RB.RemoveCustomBarFromSpec then
                        RB.RemoveCustomBarFromSpec(settings, entry, capturedSpec.id)
                    end
                end
                ApplyCustomAuraBarPanelChanges({
                    updateAnchors = true,
                    refreshConfig = true,
                    refreshLayoutPreview = true,
                })
            end,
        })
    end
end

local function ConfigureCustomBarAddInstructions(addBox, placeholderText)
    local editFrame = addBox and addBox.editbox
    if not editFrame then
        return function() end
    end

    local instructions = editFrame._cdcCustomBarAddInstructions
    if not instructions then
        instructions = editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        instructions:SetPoint("LEFT", editFrame, "LEFT", 6, 0)
        instructions:SetPoint("RIGHT", editFrame, "RIGHT", -6, 0)
        instructions:SetJustifyH("LEFT")
        instructions:SetTextColor(0.5, 0.5, 0.5)
        editFrame._cdcCustomBarAddInstructions = instructions
    end
    instructions:SetText(placeholderText)

    local function Update(text)
        instructions:SetShown((text or "") == "")
    end

    local prevOnRelease = addBox.events and addBox.events["OnRelease"]
    addBox:SetCallback("OnRelease", function(widget)
        if prevOnRelease then
            prevOnRelease(widget, "OnRelease")
        end
        instructions:Hide()
        instructions:SetText("")
    end)

    Update(editFrame:GetText())
    return Update
end

local function DeleteCustomBarById(settings, specID, customBars, customBarId)
    if RB.DeleteCustomBar then
        return RB.DeleteCustomBar(settings, customBarId)
    end

    return false
end

local function DuplicateCustomBarById(settings, specID, customBars, customBarId)
    local sourceIndex = FindCustomBarIndexById(customBars, customBarId)
    local sourceEntry = sourceIndex and customBars[sourceIndex]
    if type(settings) ~= "table" or type(sourceEntry) ~= "table" then
        return nil
    end

    local fallbackOrder = 1000 + sourceIndex + 1
    local newId
    if RB.DuplicateCustomBar then
        newId = RB.DuplicateCustomBar(settings, sourceEntry, specID, fallbackOrder)
    elseif RB.AddCustomBar then
        local sourceLayout = GetCustomBarLayout(settings, specID, sourceEntry, false)
        local copy = CopyTable(sourceEntry)
        copy.customBarId = nil
        newId = RB.AddCustomBar(settings, copy, specID, fallbackOrder)
        if newId then
            local targetLayout = EnsureCustomBarLayout(settings, specID, newId, fallbackOrder)
            if type(sourceLayout) == "table" and type(targetLayout) == "table" then
                for key, value in pairs(sourceLayout) do
                    targetLayout[key] = CopyTableValue(value)
                end
                if sourceLayout.order ~= nil then
                    targetLayout.order = (tonumber(sourceLayout.order) or 1000) + 1
                end
                if sourceLayout.verticalOrder ~= nil then
                    targetLayout.verticalOrder = (tonumber(sourceLayout.verticalOrder) or 1000) + 1
                end
            end
        end
    else
        local copy = CopyTable(sourceEntry)
        copy.customBarId = nil
        newId = EnsureCustomBarId(settings, copy)
        table.insert(customBars, sourceIndex + 1, copy)
    end
    if not newId then
        return nil
    end

    return newId
end

local function OpenCustomBarRowMenu(customBars, specID, customBarId, entry)
    if not CS.customBarContextMenu then
        CS.customBarContextMenu = CreateFrame("Frame", "CDCCustomBarContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.customBarContextMenu, function(_, level)
        if level ~= 1 then return end

        local toggleInfo = UIDropDownMenu_CreateInfo()
        toggleInfo.text = (entry.enabled == true) and "Disable" or "Enable"
        toggleInfo.notCheckable = true
        toggleInfo.func = function()
            CloseDropDownMenus()
            entry.enabled = entry.enabled ~= true
            if entry.enabled and not entry.trackingMode then
                entry.trackingMode = "active"
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(toggleInfo, level)

        local duplicateInfo = UIDropDownMenu_CreateInfo()
        duplicateInfo.text = "Duplicate"
        duplicateInfo.notCheckable = true
        duplicateInfo.func = function()
            CloseDropDownMenus()
            local newId = DuplicateCustomBarById(CooldownCompanion:GetResourceBarSettings(), specID, customBars, customBarId)
            if newId then
                SelectConfigCustomBar(newId, {
                    resetTab = true,
                })
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(duplicateInfo, level)

        local exportInfo = UIDropDownMenu_CreateInfo()
        exportInfo.text = "Export"
        exportInfo.notCheckable = true
        exportInfo.func = function()
            CloseDropDownMenus()
            if BlockCustomBarExportForResourceBarConflict() then
                return
            end
            local exportSettings = CooldownCompanion:GetResourceBarSettings()
            local payload = RB.BuildCustomBarsExportPayload and RB.BuildCustomBarsExportPayload(exportSettings, { entry })
            local exportString = payload and ST._EncodeExportData and ST._EncodeExportData(payload)
            if exportString then
                ShowPopupAboveConfig("CDC_EXPORT_CUSTOM_BARS", nil, { exportString = exportString })
            else
                CooldownCompanion:Print("Export failed: Custom Bar data was unavailable.")
            end
        end
        UIDropDownMenu_AddButton(exportInfo, level)

        local removeInfo = UIDropDownMenu_CreateInfo()
        removeInfo.text = "Remove"
        removeInfo.notCheckable = true
        removeInfo.func = function()
            CloseDropDownMenus()
            local settings = CooldownCompanion:GetResourceBarSettings()
            if DeleteCustomBarById(settings, specID, customBars, customBarId) then
                if CS.selectedCustomBarId == customBarId then
                    ClearConfigCustomBarSelection()
                end
                if CS.customBarSpecExpandedId == customBarId then
                    CS.customBarSpecExpandedId = nil
                end
            end
            ApplyCustomAuraBarPanelChanges({
                updateAnchors = true,
                refreshConfig = true,
            })
        end
        UIDropDownMenu_AddButton(removeInfo, level)
    end, "MENU")

    CS.customBarContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.customBarContextMenu, "cursor", 0, 0)
end

local function OpenConfigCustomBarMenu(customBarId)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local customBars = RB.GetAllCustomBars and RB.GetAllCustomBars(settings)
        or CooldownCompanion:GetSpecCustomAuraBars()
    local index = FindCustomBarIndexById(customBars, customBarId)
    local entry = index and customBars[index]
    if not entry then return false end
    OpenCustomBarRowMenu(customBars, RBP.GetCurrentConfigSpecID(), customBarId, entry)
    return true
end

local function BuildSortedCustomBarSoundOptionOrder(soundOptions)
    local order = {}
    for optionKey in pairs(soundOptions or {}) do
        order[#order + 1] = optionKey
    end
    table.sort(order, function(a, b)
        if a == "None" then return true end
        if b == "None" then return false end
        local aLabel = soundOptions[a] or tostring(a)
        local bLabel = soundOptions[b] or tostring(b)
        if aLabel == bLabel then
            return tostring(a) < tostring(b)
        end
        return aLabel < bLabel
    end)
    return order
end

local function BuildCustomBarSoundAlertsTab(container, cab, infoButtons)
    local soundHeading, soundCollapsed =
        AddCustomBarSection(container, "Sound Alerts", "sound", GetCustomBarCollapseKey(cab))

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Sound alerts are played through the Master channel and follow your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    AnchorLeftAlignedHeadingRule(soundHeading, soundInfoBtn)

    if soundCollapsed then return end

    local validEvents = CooldownCompanion:GetScopedValidSoundAlertEventsForCustomBar(cab)
    if not validEvents then
        local noEvents = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(noEvents)
        noEvents:SetText("|cff888888No alertable sound events are available for this Custom Bar entry.|r")
        noEvents:SetFullWidth(true)
        container:AddChild(noEvents)
        return
    end

    local soundOptions = CooldownCompanion:GetSoundAlertOptions()
    local soundOptionOrder = BuildSortedCustomBarSoundOptionOrder(soundOptions)
    local eventOrder = CooldownCompanion:GetSoundAlertEventOrder()

    -- This row set is FILTERED (see the fill rule in the recipe comment): a
    -- Custom Bar carries only the event families its entry type allows, and an
    -- aura bar has no cooldown events at all. So the family split - LEFT the
    -- cooldown-side events, RIGHT the aura-side ones (the native C_UnitAuras
    -- triggers, the same split the runtime keeps) - only runs when BOTH
    -- families survive the filter. When one family is all that is left it
    -- splits itself across the columns left-first, so the left column is never
    -- the empty one.
    local cooldownEvents, auraEvents = {}, {}
    for _, eventKey in ipairs(eventOrder) do
        if validEvents[eventKey] then
            local family = CooldownCompanion:IsAuraSoundAlertEvent(eventKey) and auraEvents or cooldownEvents
            family[#family + 1] = eventKey
        end
    end

    local soundLeft, soundRight = BeginRowGrid(container)

    local function AddSoundEventRow(column, eventKey)
        AddDropdownRow(column, {
            label = CooldownCompanion:GetCustomBarSoundAlertEventLabel(cab, eventKey),
            pulloutWidth = SOUND_PULLOUT_WIDTH,
            list = soundOptions,
            order = soundOptionOrder,
            value = CooldownCompanion:GetCustomBarSoundAlertSelection(cab, eventKey),
            onChange = function(val)
                CooldownCompanion:SetCustomBarSoundAlertEvent(cab, eventKey, val)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end

    if #cooldownEvents > 0 and #auraEvents > 0 then
        for _, eventKey in ipairs(cooldownEvents) do
            AddSoundEventRow(soundLeft, eventKey)
        end
        for _, eventKey in ipairs(auraEvents) do
            AddSoundEventRow(soundRight, eventKey)
        end
    else
        -- ceil(n/2) left, the rest right - the per-resource Colors precedent.
        local survivors = (#cooldownEvents > 0) and cooldownEvents or auraEvents
        local splitAt = math.ceil(#survivors / 2)
        for index, eventKey in ipairs(survivors) do
            AddSoundEventRow(index <= splitAt and soundLeft or soundRight, eventKey)
        end
    end
end

local function BuildCustomBarLoadConditionsTab(container, cab, infoButtons)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local currentSpecID = GetCurrentConfigSpecID()

    -- The who-half of this tab: which specs the bar belongs to. The
    -- where-half is the shared toggles below.
    local _, specsCollapsed =
        AddCustomBarSection(container, "Specializations", "specs", GetCustomBarCollapseKey(cab))

    if not specsCollapsed then
        local specLeft, specRight = BeginRowGrid(container)
        AddCustomBarSpecFilterControls(specLeft, specRight, settings, cab, currentSpecID)
    end

    -- ButtonConditions.lua loads after this file, so both helpers are read at
    -- call time rather than captured at file scope.
    local addScopedLoadConditionToggles = ST._AddScopedLoadConditionToggles
    local buildWhereToHideTooltip = ST._BuildWhereToHideTooltip
    if type(addScopedLoadConditionToggles) ~= "function" then
        local unavailable = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(unavailable)
        unavailable:SetText("|cff888888Visibility controls are not available yet.|r")
        unavailable:SetFullWidth(true)
        container:AddChild(unavailable)
        return
    end

    local _, togglesRight = addScopedLoadConditionToggles(container, {
        target = cab,
        defaults = CooldownCompanion:GetLocalLoadConditionDefaults(),
        inheritedSources = {},
        headingText = "Where To Hide It",
        inheritedCollapsedKey = "loadconditions_custombar_inherited",
        localCollapsedKey = "loadconditions_custombar_local",
        preserveMissing = true,
        row = true,
        infoTooltipLines = type(buildWhereToHideTooltip) == "function"
            and buildWhereToHideTooltip("bar", false) or nil,
        infoButtons = infoButtons,
        onChanged = function()
            if cab.loadConditions and not next(cab.loadConditions) then
                cab.loadConditions = nil
            end
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if CooldownCompanion:HasLocalLoadConditions(cab) then
        -- Compact and flush left, filling the shorter (4-row) right column's
        -- tail. With the section collapsed there is no grid to sit in, so it
        -- falls back to the tab surface - still reachable, still compact.
        local clearHost = togglesRight or container
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Bar Visibility Rules")
        clearBtn:SetAutoWidth(true)
        clearBtn:SetCallback("OnClick", function()
            cab.loadConditions = nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end)
        clearHost:AddChild(clearBtn)
    end
end

-- A collapsible row-grammar section header with the optional "?" chained off
-- the end of its label; the fading rule restarts after that badge.
local function AddCustomBarSettingsHeading(container, text, name, key, infoButtons, tooltip)
    local heading, collapsed = AddCustomBarSection(container, text, name, key)

    if tooltip then
        local tooltipLines = { text }
        if type(tooltip) == "table" then
            for _, line in ipairs(tooltip) do
                tooltipLines[#tooltipLines + 1] = { line, 1, 1, 1, true }
            end
        else
            tooltipLines[#tooltipLines + 1] = { tooltip, 1, 1, 1, true }
        end
        local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
            unpack(tooltipLines)
        }, infoButtons)
        AnchorLeftAlignedHeadingRule(heading, infoBtn)
    end

    return heading, collapsed
end

local function AddResourceBarsDisabledLabel(container, text)
    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText(text)
    label:SetFullWidth(true)
    container:AddChild(label)
end
ST._AddResourceBarsDisabledLabel = AddResourceBarsDisabledLabel

------------------------------------------------------------------------
-- Aura tracking section (the aura pass): the panel Aura-tab vocabulary on
-- custom bars. The tracked unit is auto-derived from spell polarity and
-- never user-set (Blizzard's anti-cheat gate makes illegal configurations
-- unrepresentable); max stacks is automatic from game data. Every change
-- goes through ApplyResourceBars, which requests the OOC aura rebind.
------------------------------------------------------------------------

local function RefreshCustomBarAuraConfig()
    CooldownCompanion:ApplyResourceBars()
    CooldownCompanion:RefreshConfigPanel()
end

-- Shared tracked-aura list rules (SectionBuilders.lua), the same ones the
-- panel Aura tab runs on.
local ClassifyAuraSpellUnit = ST._ClassifyAuraSpellUnit
local GetAuraCandidateList = ST._GetAuraCandidateList
local TryAddAuraCandidate = ST._TryAddAuraCandidate
local RemoveAuraCandidate = ST._RemoveAuraCandidate
local GetAuraStackMaxStatusText = ST._GetAuraStackMaxStatusText

-- Candidate-resolution probe: the buttonData shape Core/Aura.lua reads,
-- synthesized from cabConfig (the same mapping the runtime adapter uses).
local function BuildCustomBarAuraProbe(cab)
    return {
        type = "spell",
        id = tonumber(cab.spellID),
        addedAs = (not IsSpellCustomBarConfig(cab)) and "aura" or nil,
        auraTracking = true,
        auraSpellID = cab.auraSpellID,
        auraUnit = cab.auraUnit,
    }
end

local function GetCustomBarAuraUnit(cab)
    local resolved = CooldownCompanion:ResolveAuraSpellID(BuildCustomBarAuraProbe(cab))
    return ClassifyAuraSpellUnit(resolved) or cab.auraUnit or "player"
end

-- Store the derived unit whenever tracking config changes, so the runtime
-- fallback (uncached spells at login) starts from the right value.
local function SyncCustomBarDerivedAuraUnit(cab)
    local unit = ClassifyAuraSpellUnit(CooldownCompanion:ResolveAuraSpellID(BuildCustomBarAuraProbe(cab)))
    if unit then
        cab.auraUnit = unit
        cab.auraUnitExplicit = nil
    end
end

-- A tracked aura presents an ITEM, not a setting: a CDC-LabelRow with the
-- spell's icon inlined into the label text (the row's label is a FontString,
-- so the icon rides an inline texture escape) and a Remove link owned by the
-- row's control column. The shared ST._AddAuraCandidateRow is a 22px Flow row
-- and would break the rhythm inside a grid column.
local function AddCustomBarCandidateRow(container, cab, spellID)
    local info = C_Spell.GetSpellInfo(spellID)
    local name = info and info.name or ("Spell " .. spellID)
    local icon = C_Spell.GetSpellTexture(spellID) or 134400
    local row = AddLabelRow(container, {
        label = ("|T%d:16:16:0:0|t %s |cff999999(%d)|r"):format(icon, name, spellID),
        indent = true,
    })

    -- Right-justified so the word lands on the control column's right edge
    -- like every other row's control. SetJustifyH is public API and the stock
    -- Label resets it to LEFT in OnAcquire, so the pool stays clean.
    local removeLabel = AceGUI:Create("InteractiveLabel")
    removeLabel:SetText("|cffff5555Remove|r")
    removeLabel:SetWidth(60)
    removeLabel:SetJustifyH("RIGHT")
    removeLabel:SetCallback("OnClick", function()
        if RemoveAuraCandidate(cab, spellID, SyncCustomBarDerivedAuraUnit) then
            RefreshCustomBarAuraConfig()
        end
    end)
    row:SetControlWidget(removeLabel)
end

local function BuildCustomBarAuraTrackingSection(container, cab, infoButtons, sectionKey)
    local isSpellBar = IsSpellCustomBarConfig(cab)

    local _, collapsed = AddCustomBarSettingsHeading(container, "Aura Tracking", "aura", sectionKey, infoButtons, {
        "Blizzard tracks the aura and drives the bar directly; the addon never reads aura state in combat.",
        "Buffs can only be tracked on yourself, and your own debuffs only on your target. This is a Blizzard restriction. The tracked unit is set automatically from the aura.",
        "With no auras listed, the bar tracks its own aura. Added aura IDs override that; for spell bars the spell's own aura is always kept as a fallback.",
    })

    if collapsed then return end

    -- LEFT column: which aura is tracked, and on whom. RIGHT column: how the
    -- bar draws it. Both halves are gated on the toggle at the head of the
    -- left one, so the right side is empty until tracking is on.
    local auraLeft, auraRight = BeginRowGrid(container)

    if isSpellBar then
        AddCheckboxRow(auraLeft, {
            label = "Track an Aura",
            value = cab.auraTracking == true,
            onChange = function(value)
                cab.auraTracking = value and true or nil
                if value then
                    SyncCustomBarDerivedAuraUnit(cab)
                end
                RefreshCustomBarAuraConfig()
            end,
        })
        if cab.auraTracking ~= true then
            return
        end
    end

    -- Derived unit line (read-only by design; the "?" heading explains why).
    local unit = GetCustomBarAuraUnit(cab)
    AddLabelRow(auraLeft, {
        label = "Tracked on",
        indent = isSpellBar,
        controlText = unit == "target" and "Target" or "You",
    })

    for _, spellID in ipairs(GetAuraCandidateList(cab)) do
        AddCustomBarCandidateRow(auraLeft, cab, spellID)
    end

    AddEditBoxRow(auraLeft, {
        label = "Add aura by name or ID",
        indent = true,
        value = "",
        onEnterPressed = function(text, widget)
            if TryAddAuraCandidate(cab, text, GetCustomBarAuraUnit(cab), SyncCustomBarDerivedAuraUnit) then
                widget:SetText("")
                RefreshCustomBarAuraConfig()
            end
        end,
    })

    -- Bar fill mode: duration drain or stack count. Max stacks is automatic
    -- (game data); the status line shows what resolved.
    local mode = cab.trackingMode
    if mode ~= "active" and mode ~= "stacks" then
        mode = isSpellBar and "active" or "stacks"
    end
    local stacksRow = AddCheckboxRow(auraRight, {
        label = "Bar Shows Stacks",
        value = mode == "stacks",
        onChange = function(value)
            cab.trackingMode = value and "stacks" or "active"
            RefreshCustomBarAuraConfig()
        end,
    })
    -- Anchor args are a placeholder - AnchorRowBadge re-points the button onto
    -- the end of the row's label.
    AnchorRowBadge(stacksRow, CreateInfoButton(stacksRow.frame, stacksRow.frame, "LEFT", "LEFT", 0, 0, {
        "Bar Shows Stacks",
        {"The bar shows the stack count instead of draining with time. Blizzard drives the fill and the maximum comes from the game's spell data — nothing to configure.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Stack Style picks the look: Segmented renders each stack as its own bordered piece with real gaps; Continuous is one plain bar that fills as stacks build. Segment gap and smoothing follow the Resource Bars settings.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"If the tracked aura doesn't stack, the bar keeps the normal duration fill.", 1, 1, 1, true},
    }, infoButtons))

    if mode == "stacks" then
        local maxStacks = CooldownCompanion:GetAuraStackBarMax(BuildCustomBarAuraProbe(cab))
        if maxStacks then
            AddDropdownRow(auraRight, {
                label = "Stack Style",
                indent = true,
                list = { segmented = "Segmented", continuous = "Continuous" },
                order = { "segmented", "continuous" },
                value = cab.displayMode == "continuous" and "continuous" or "segmented",
                onChange = function(value)
                    cab.displayMode = value
                    RefreshCustomBarAuraConfig()
                end,
            })
        end

        -- What the game resolved (or that combat is hiding it), reported as a
        -- child of the toggle it explains. It was a stock wrapped Label, which
        -- is 1-3 lines of unpredictable height between two rows and shoved
        -- everything below it out of rhythm; as a label row it occupies
        -- exactly one row slot whether it is there or not. Same three texts,
        -- same colors, same conditions - the row is just the shape. Row labels
        -- never wrap, so the sentence also says its piece on hover, the same
        -- treatment the long locked visibility labels get.
        local statusText = GetAuraStackMaxStatusText(maxStacks)
        AddLabelRow(auraRight, {
            label = statusText,
            indent = true,
            tooltip = { { statusText, 1, 1, 1, true } },
        })
    end

    -- Pandemic marker per-entry switch. The auto default follows the tracked
    -- unit (on for target debuffs, off for player buffs); only an explicit
    -- override is stored.
    local pandemicDefault = unit == "target"
    local pandemicValue = cab.pandemicMarker
    if pandemicValue == nil then pandemicValue = pandemicDefault end
    local pandemicRow = AddCheckboxRow(auraRight, {
        label = "Pandemic Marker",
        value = pandemicValue == true,
        onChange = function(value)
            if value == pandemicDefault then
                cab.pandemicMarker = nil
            else
                cab.pandemicMarker = value and true or false
            end
            RefreshCustomBarAuraConfig()
        end,
    })
    AnchorRowBadge(pandemicRow, CreateInfoButton(pandemicRow.frame, pandemicRow.frame, "LEFT", "LEFT", 0, 0, {
        "Pandemic Marker",
        {"Marks the aura duration text during the last 30% of the aura's duration — the refresh window where recasting extends the remaining time instead of wasting it. Blizzard evaluates the timing; the addon never reads combat values.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"On by default for debuffs on your target, off by default for your own buffs.", 1, 1, 1, true},
    }, infoButtons))

    local shellRow = AddCheckboxRow(auraRight, {
        label = "Show Only While Aura Active",
        value = cab.hideWhenInactive == true,
        onChange = function(value)
            cab.hideWhenInactive = value or nil
            RefreshCustomBarAuraConfig()
        end,
    })
    AnchorRowBadge(shellRow, CreateInfoButton(shellRow.frame, shellRow.frame, "LEFT", "LEFT", 0, 0, {
        "Show Only While Aura Active",
        {"The bar renders only while the aura is running. Its slot in the bar stack stays reserved — bars cannot reflow around it in combat.", 1, 1, 1, true},
    }, infoButtons))
end

local function BuildCustomBarWorkspaceAddBox(container)
    if BuildResourceBarConflictGate(container, "Custom Bars", false) then
        return
    end

    local settings = CooldownCompanion:GetResourceBarSettings()
    if not (settings and settings.enabled) then
        return
    end

    local customBarsSpecID = ST._RBP.GetCurrentConfigSpecID()
    local customBars = RB.GetAllCustomBars and RB.GetAllCustomBars(settings) or CooldownCompanion:GetSpecCustomAuraBars()
    ST._PruneConfigCustomBarSelection(function(customBarId)
        return FindCustomBarIndexById(customBars, customBarId) ~= nil
    end)
    local addBox = AceGUI:Create("EditBox")
    if addBox.editbox.Instructions then addBox.editbox.Instructions:Hide() end
    addBox:SetLabel("")
    addBox:SetFullWidth(true)
    addBox:DisableButton(true)
    local updatePlaceholder = ConfigureCustomBarAddInstructions(addBox, "Add spell by name or ID")

    local function GetCustomBarEntryTypeForAutocomplete(entry)
        if type(entry) ~= "table" then
            return "spell"
        end
        if entry.forceAura == true or entry.isPassive == true then
            return "aura"
        end
        if entry.forceAura == false then
            return "spell"
        end
        if IsPassiveOrProc and entry.id and IsPassiveOrProc(entry.id) then
            return "aura"
        end
        return "spell"
    end

    local function StripExplicitCustomBarEntryTypeSuffix(text)
        local cleaned = text and text:gsub("^%s+", ""):gsub("%s+$", ""):lower() or ""
        if cleaned:match("%s%((buff)%)$") or cleaned:match("%s%((aura)%)$") then
            return (text or ""):gsub("%s+%([Bb][Uu][Ff][Ff]%)%s*$", ""):gsub("%s+%([Aa][Uu][Rr][Aa]%)%s*$", ""), "aura"
        end
        if cleaned:match("%s%((cooldown)%)$") then
            return (text or ""):gsub("%s+%([Cc][Oo][Oo][Ll][Dd][Oo][Ww][Nn]%)%s*$", ""), "spell"
        end
        return text, nil
    end

    local function GetCustomBarEntryTypeForSpellID(spellId, explicitType)
        if explicitType then
            return explicitType
        end
        if not spellId or not C_Spell.GetSpellInfo(spellId) then
            return "aura"
        end
        local sawAuraEntry = false
        local sawSpellEntry = false
        local cache = ST._RBP.BuildAuraBarAutocompleteCache and ST._RBP.BuildAuraBarAutocompleteCache() or nil
        for _, entry in ipairs(cache or {}) do
            if entry.id == spellId then
                if GetCustomBarEntryTypeForAutocomplete(entry) == "aura" then
                    sawAuraEntry = true
                else
                    sawSpellEntry = true
                end
            end
        end
        if sawAuraEntry and not sawSpellEntry then
            return "aura"
        elseif sawSpellEntry and not sawAuraEntry then
            return "spell"
        end
        if IsPassiveOrProc and IsPassiveOrProc(spellId) then
            return "aura"
        end
        return "spell"
    end

    local function AddCustomBarFromSpell(spellId, labelOverride, entryType)
        if not spellId then return false end
        local entry
        if entryType == "aura" then
            -- Aura-driven Custom Bar (the aura pass): duration bar by
            -- default; stacks are the "Bar Shows Stacks" opt-in. The unit
            -- seed derives from spell polarity (never user-set).
            entry = {
                entryType = "aura",
                enabled = true,
                spellID = spellId,
                trackingMode = "active",
                showDurationText = true,
                auraUnit = ClassifyAuraSpellUnit(spellId) or "player",
                label = labelOverride or GetAuraBarAutocompleteDisplayName(spellId) or C_Spell.GetSpellName(spellId) or "",
            }
        else
            entry = {
                entryType = "spell",
                enabled = true,
                spellID = spellId,
                label = labelOverride or GetAuraBarAutocompleteDisplayName(spellId) or C_Spell.GetSpellName(spellId) or "",
            }
            local charges = C_Spell.GetSpellCharges(spellId)
            local maxCharges = charges and tonumber(charges.maxCharges)
            if maxCharges and maxCharges > 1 then
                entry.hasCharges = true
                entry.maxCharges = maxCharges
            end
        end
        local id = RB.AddCustomBar
            and RB.AddCustomBar(settings, entry, customBarsSpecID, 1000 + #CooldownCompanion:GetSpecCustomAuraBars() + 1)
            or EnsureCustomBarId(settings, entry)
        if not RB.AddCustomBar then
            customBars[#customBars + 1] = entry
            EnsureCustomBarLayout(settings, nil, id, 1000 + #customBars)
        end
        ST._SelectConfigCustomBar(id)
        ApplyCustomAuraBarPanelChanges({
            updateAnchors = true,
            refreshConfig = true,
        })
        return true
    end

    local function CommitCustomBarText(widget, text)
        local lookupText, explicitType = StripExplicitCustomBarEntryTypeSuffix(text)
        local autocompleteEntry = ResolveAuraBarAutocompleteEntry and (
            ResolveAuraBarAutocompleteEntry(text)
            or (lookupText ~= text and ResolveAuraBarAutocompleteEntry(lookupText))
        )
        if autocompleteEntry and AddCustomBarFromSpell(
            autocompleteEntry.id,
            GetAuraBarAutocompleteEntryName(autocompleteEntry),
            explicitType or GetCustomBarEntryTypeForAutocomplete(autocompleteEntry)
        ) then
            widget:SetText("")
            return true
        end

        local id, explicitClear = ResolveAuraColorSpellIDFromText(lookupText)
        if explicitClear then
            widget:SetText("")
            return true
        end
        if AddCustomBarFromSpell(id, nil, GetCustomBarEntryTypeForSpellID(id, explicitType)) then
            widget:SetText("")
            return true
        end

        local cleaned = text and text:gsub("^%s+", ""):gsub("%s+$", "") or ""
        if cleaned ~= "" then
            CooldownCompanion:Print("Custom Bar spell not found: " .. cleaned)
        end
        return false
    end

    local function onAuraBarSelect(entry)
        CS.HideAutocomplete()
        if entry and AddCustomBarFromSpell(
            entry.id,
            GetAuraBarAutocompleteEntryName(entry),
            GetCustomBarEntryTypeForAutocomplete(entry)
        ) then
            addBox._cdcCustomBarAutocompleteCommitted = true
            addBox:SetText("")
        end
    end

    addBox:SetCallback("OnTextChanged", function(widget, event, text)
        updatePlaceholder(text)
        ShowAuraBarAutocompleteResults(text, widget, onAuraBarSelect)
    end)
    addBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter then
            CS.ConsumeAutocompleteEnter()
        end
        if widget._cdcCustomBarAutocompleteCommitted then
            widget._cdcCustomBarAutocompleteCommitted = nil
            return
        end
        CS.HideAutocomplete()
        CommitCustomBarText(widget, text)
    end)
    CS.SetupAutocompleteKeyHandler(addBox)
    addBox.editbox:SetPoint("BOTTOMRIGHT", 1, 0)

    local actionControls = AceGUI:Create("SimpleGroup")
    actionControls:SetFullWidth(true)
    actionControls.noAutoHeight = true
    actionControls:SetHeight(28)
    actionControls:SetLayout("Fill")
    actionControls:AddChild(addBox)
    container:AddChild(actionControls)
    return actionControls, addBox
end

local function BuildCustomAuraBarPanel(container, customBarId, activeTab)
    if BuildResourceBarConflictGate(container, "Custom Bars", false) then
        return
    end

    local settings = CooldownCompanion:GetResourceBarSettings()
    if not (settings and settings.enabled) then
        AddResourceBarsDisabledLabel(container, "Enable Resource Bars to configure Custom Bar settings.")
        return
    end

    local customBars = RB.GetAllCustomBars and RB.GetAllCustomBars(settings) or CooldownCompanion:GetSpecCustomAuraBars()
    local rbCabTextAdvBtns = {}
    local selectedIndex = FindCustomBarIndexById(customBars, customBarId)
    local infoButtons = CS.customBarInfoButtons
    if not infoButtons then
        infoButtons = {}
        CS.customBarInfoButtons = infoButtons
    end

    if not selectedIndex then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Select a Custom Bar to configure it.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end
    local cab = customBars[selectedIndex]
    local capturedIdx = selectedIndex
    local capturedId = EnsureCustomBarId(settings, cab)
    local capturedKey = capturedId or tostring(capturedIdx)
    local currentConfigSpecID = GetCurrentConfigSpecID()
    local function resolveLayoutSpecID(entry, fallbackSpecID)
        fallbackSpecID = tonumber(fallbackSpecID) or fallbackSpecID
        if RB.CustomBarHasSpec and fallbackSpecID and RB.CustomBarHasSpec(entry, fallbackSpecID) then
            return fallbackSpecID
        end
        if RB.CustomBarHasExplicitSpec then
            for _, spec in ipairs(GetCustomBarSpecOptions()) do
                if RB.CustomBarHasExplicitSpec(entry, spec.id) then
                    return spec.id
                end
            end
        end

        local entryCustomBarId = type(entry) == "table" and entry.customBarId or nil
        local layoutOrder = type(settings) == "table" and settings.layoutOrder or nil
        if type(entryCustomBarId) == "string" and type(layoutOrder) == "table" then
            local layoutSpecIDs = {}
            for specID, specLayout in pairs(layoutOrder) do
                if type(specLayout) == "table"
                    and type(specLayout.customBars) == "table"
                    and type(specLayout.customBars[entryCustomBarId]) == "table" then
                    layoutSpecIDs[#layoutSpecIDs + 1] = tonumber(specID) or specID
                end
            end
            table.sort(layoutSpecIDs, function(a, b) return tostring(a) < tostring(b) end)
            if layoutSpecIDs[1] then
                return layoutSpecIDs[1]
            end
        end

        return fallbackSpecID
    end

    local layoutSpecID = resolveLayoutSpecID(cab, currentConfigSpecID)
    local layout = RB.GetSpecLayoutOrder and RB.GetSpecLayoutOrder(settings, layoutSpecID) or CooldownCompanion:GetSpecLayoutOrder()
    local thicknessField, thicknessLabel = GetResourceThicknessFieldConfig(settings, layout)
    local isSpellCustomBar = IsSpellCustomBarConfig(cab)
    activeTab = activeTab or "appearance"

    if activeTab == "settings" or activeTab == "layout" or activeTab == "anchor" or activeTab == "alpha" then
        activeTab = "appearance"
    end

    if activeTab == "soundalerts" then
        ST._BuildCustomBarSoundAlertsTab(container, cab, infoButtons)
        return
    end

    if activeTab == "loadconditions" then
        ST._BuildCustomBarLoadConditionsTab(container, cab, infoButtons)
        return
    end

    -- Aura tab (the aura pass): the tracking section plus the active-aura
    -- effects, the same shape as the panel entry Aura tab. Aura-look
    -- colors and texts stay on Appearance with the rest of the bar style.
    if activeTab == "aura" then
        if cab.spellID then
            BuildCustomBarAuraTrackingSection(container, cab, infoButtons, capturedKey)

            -- Shared builder (SectionBuilders): the cabConfig speaks the
            -- same barAura* key family as the panel bar style tables. Its
            -- opts.row branch opens its own grid on this container - LEFT the
            -- border effect, RIGHT the two fill effects - so this section
            -- reads like every other one on the tab. The bar-mode advanced
            -- panel and the entry override tab omit opts.row and keep the
            -- stock full-width widgets.
            local isAuraTracked = (not isSpellCustomBar) or cab.auraTracking == true
            if isAuraTracked and ST._BuildBarActiveAuraControls then
                local _, effectsCollapsed = AddCustomBarSettingsHeading(container, "Effects",
                    "aura_effects", capturedKey, infoButtons, {
                        "Effects the bar plays while the tracked aura is active: a border effect, a fill pulse, and a fill color shift.",
                        "Use the preview in the command center below the bar list to see them without a live aura.",
                    })
                if not effectsCollapsed then
                    ST._BuildBarActiveAuraControls(container, cab, function() CooldownCompanion:ApplyResourceBars() end, {
                        row = true,
                        infoButtons = infoButtons,
                    })
                end
            end
        end
        return
    end

            -- Per-slot bar thickness override
            if layout and layout.customBarHeights then
                local _, sizeCollapsed = AddCustomBarSettingsHeading(container, "Size", "size", capturedKey)

                if not sizeCollapsed then
                    -- One setting with nothing to pair it against, so the left
                    -- column carries it alone.
                    local sizeLeft = BeginRowGrid(container)

                    local slotLayout = EnsureCustomBarLayout(settings, layoutSpecID, capturedId, 1000 + capturedIdx) or {}
                    local thicknessValue
                    if thicknessField == "barWidth" then
                        thicknessValue = slotLayout.barWidth or slotLayout.barHeight or layout.barWidth or layout.barHeight or settings.barWidth or settings.barHeight or 12
                    else
                        thicknessValue = slotLayout.barHeight or slotLayout.barWidth or layout.barHeight or layout.barWidth or settings.barHeight or settings.barWidth or 12
                    end
                    local cabIdx = capturedIdx
                    AddSliderRow(sizeLeft, {
                        label = thicknessLabel,
                        min = 4, max = 40, step = 0.1,
                        value = thicknessValue,
                        onChange = function(val)
                            local customBar = customBars[cabIdx]
                            local customLayout = EnsureCustomBarLayout(settings, layoutSpecID, customBar and customBar.customBarId, 1000 + cabIdx)
                            if customLayout then
                                customLayout[thicknessField] = val
                            end
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:RepositionCastBar()
                            CooldownCompanion:UpdateAnchorStacking()
                        end,
                    })
                end
            end

            -- ---- Colors / Texts sections ----
            if cab.spellID then
                local cabIdx = capturedIdx
                -- Commit path: apply to the live bars AND repaint the config
                -- canvas, so a confirmed color shows on both surfaces at once.
                local cabApplyBars = function()
                    CooldownCompanion:ApplyResourceBars()
                    RefreshLayoutOrderPreview()
                end
                -- Drag path: uncommitted edits belong to the config canvas
                -- only — the live display keeps its committed style until the
                -- picker closes.
                local cabPreviewOnly = RefreshLayoutOrderPreview
                local isAuraTracked = (not isSpellCustomBar) or cab.auraTracking == true

                local _, colorsCollapsed = AddCustomBarSettingsHeading(container, "Colors", "colors", capturedKey)

                if not colorsCollapsed then
                -- LEFT column: the two base fills - what the bar shows when it
                -- is ready, and what it shows while the cooldown runs. RIGHT
                -- column: the conditional fills layered over those. Aura bars
                -- have only the first, so the right side is empty for them.
                local colorsLeft, colorsRight = BeginRowGrid(container)

                -- deferCommit is true on every picker here: the Layout & Order
                -- canvas re-reads these tables on every repaint, so a drag
                -- value may only exist in them while that repaint runs.
                --
                -- Standalone aura bars: the fill IS the aura, so the label
                -- says so — "Bar Color" stays the spell-cooldown verbiage.
                -- Same barColor key either way; label only.
                AddColorRow(colorsLeft, {
                    label = isSpellCustomBar and "Bar Color" or "Aura Bar Color",
                    tbl = customBars[cabIdx],
                    key = "barColor",
                    default = {0.5, 0.5, 1},
                    onConfirm = cabApplyBars,
                    onChange = cabPreviewOnly,
                    deferCommit = true,
                })

                if isSpellCustomBar then
                    AddColorRow(colorsLeft, {
                        label = "Bar Cooldown Color",
                        tbl = customBars[cabIdx],
                        key = "barCooldownColor",
                        default = {0.6, 0.13, 0.18, 1},
                        hasAlpha = true,
                        onConfirm = cabApplyBars,
                        onChange = cabPreviewOnly,
                        deferCommit = true,
                    })

                    AddColorRow(colorsRight, {
                        label = "Bar Recharging Color",
                        tbl = customBars[cabIdx],
                        key = "barChargeColor",
                        default = {1.0, 0.82, 0.0, 1},
                        hasAlpha = true,
                        onConfirm = cabApplyBars,
                        onChange = cabPreviewOnly,
                        deferCommit = true,
                    })

                    if isAuraTracked then
                        -- The kit's aura-drain fill while the tracked aura
                        -- runs (pure aura bars use Bar Color — the fill IS
                        -- the bar there).
                        AddColorRow(colorsRight, {
                            label = "Aura Bar Color",
                            tbl = customBars[cabIdx],
                            key = "barAuraColor",
                            default = {0.2, 1.0, 0.2, 1},
                            hasAlpha = true,
                            onConfirm = cabApplyBars,
                            onChange = cabPreviewOnly,
                            deferCommit = true,
                        })
                    end
                end
                end -- not colorsCollapsed

                -- ---- Text / Duration controls ----
                local _, textsCollapsed = AddCustomBarSettingsHeading(container, "Texts", "texts", capturedKey)

                if not textsCollapsed then
                    -- One text per column: each carries its own gear, and the
                    -- two are independent, so neither has to stay adjacent to
                    -- anything.
                    local textsLeft, textsRight = BeginRowGrid(container)

                    local showDurationControls = true
                    local durationTextRow
                    if showDurationControls then
                        durationTextRow = AddCheckboxRow(textsLeft, {
                            label = "Show Duration Text",
                            value = cab.showDurationText == true,
                            onChange = function(val)
                                customBars[cabIdx].showDurationText = val or nil
                                CooldownCompanion:ApplyResourceBars()
                                CooldownCompanion:RefreshConfigPanel()
                            end,
                        })
                    end

                    -- Show Stack Text
                    local stackVal = cab.showStackText

                    local stackTextLabel = isSpellCustomBar
                        and "Show Count Text (Charges/Uses)"
                        or "Show Stack Text"
                    local stackTextRow = AddCheckboxRow(textsRight, {
                        label = stackTextLabel,
                        value = stackVal == true,
                        onChange = function(val)
                            customBars[cabIdx].showStackText = val or nil
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:RefreshConfigPanel()
                        end,
                    })

                    local showDuration = showDurationControls and cab.showDurationText == true
                    local showStack = (stackVal == true)
                    local function BuildDurationTextAdvanced(panel)
                        local fontDrop = AceGUI:Create("Dropdown")
                        fontDrop:SetLabel("Duration Font")
                        CS.SetupFontDropdown(fontDrop)
                        fontDrop:SetValue(cab.durationTextFont or DEFAULT_RESOURCE_TEXT_FONT)
                        fontDrop:SetFullWidth(true)
                        CS.SetFontDropdownCallback(fontDrop, function(widget, event, val)
                            customBars[cabIdx].durationTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        sizeDrop:SetLabel("Duration Font Size")
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.durationTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].durationTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        outlineDrop:SetLabel("Duration Outline")
                        CS.SetupFontOutlineDropdown(outlineDrop)
                        outlineDrop:SetValue(cab.durationTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
                        outlineDrop:SetFullWidth(true)
                        CS.SetFontOutlineDropdownCallback(outlineDrop, function(widget, event, val)
                            customBars[cabIdx].durationTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(outlineDrop)

                        AddColorPicker(panel, customBars[cabIdx], "durationTextFontColor", "Duration Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars, cabPreviewOnly, true)

                        AddDurationFormatDropdown(panel, customBars[cabIdx], cabApplyBars)
                    end

                    if showDurationControls then
                        AddAdvancedToggle(durationTextRow, "rbCabDurationText_" .. capturedKey, rbCabTextAdvBtns, showDuration, {
                            title = "Duration Text Advanced",
                            build = BuildDurationTextAdvanced,
                        })
                    end

                    local function BuildStackTextAdvanced(panel)
                        local fontDrop = AceGUI:Create("Dropdown")
                        fontDrop:SetLabel("Charge Font")
                        CS.SetupFontDropdown(fontDrop)
                        fontDrop:SetValue(cab.stackTextFont or DEFAULT_RESOURCE_TEXT_FONT)
                        fontDrop:SetFullWidth(true)
                        CS.SetFontDropdownCallback(fontDrop, function(widget, event, val)
                            customBars[cabIdx].stackTextFont = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(fontDrop)

                        local sizeDrop = AceGUI:Create("Slider")
                        sizeDrop:SetLabel("Charge Font Size")
                        sizeDrop:SetSliderValues(6, 24, 1)
                        sizeDrop:SetValue(cab.stackTextFontSize or DEFAULT_RESOURCE_TEXT_SIZE)
                        sizeDrop:SetFullWidth(true)
                        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].stackTextFontSize = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(sizeDrop)

                        local outlineDrop = AceGUI:Create("Dropdown")
                        outlineDrop:SetLabel("Charge Outline")
                        CS.SetupFontOutlineDropdown(outlineDrop)
                        outlineDrop:SetValue(cab.stackTextFontOutline or DEFAULT_RESOURCE_TEXT_OUTLINE)
                        outlineDrop:SetFullWidth(true)
                        CS.SetFontOutlineDropdownCallback(outlineDrop, function(widget, event, val)
                            customBars[cabIdx].stackTextFontOutline = val
                            CooldownCompanion:ApplyResourceBars()
                        end)
                        panel:AddChild(outlineDrop)

                        AddColorPicker(panel, customBars[cabIdx], "stackTextFontColor", "Stack Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars, cabPreviewOnly, true)
                    end

                    AddAdvancedToggle(stackTextRow, "rbCabStackText_" .. capturedKey, rbCabTextAdvBtns, showStack, {
                        title = stackTextLabel .. " Advanced",
                        build = BuildStackTextAdvanced,
                    })
                end -- not textsCollapsed

                -- ---- Talent Conditions section ----
                -- Key unchanged from the pre-row tab, so a bar's collapse
                -- state survives this conversion.
                local talentHeading, talentCollapsed =
                    AddCustomBarSection(container, "Talent Conditions", "talent", capturedKey)

                local talentInfoBtn = CreateInfoButton(talentHeading.frame, talentHeading.label, "LEFT", "RIGHT", 4, 0, {
                    "Talent Conditions",
                    {"Show or hide this Custom Bar based on which talents you have selected. If you add multiple conditions, all of them must pass.", 1, 1, 1, true},
                }, infoButtons)
                AnchorLeftAlignedHeadingRule(talentHeading, talentInfoBtn)

                local conditions = cab.talentConditions
                local condCount = conditions and #conditions or 0

                if talentCollapsed then
                    local summaryLabel = AceGUI:Create("Label")
                    ST._ConfigureWrappedHelperLabel(summaryLabel)
                    if condCount > 0 then
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
                            summaryLabel:SetText(ST._GetConditionDisplayName(firstCond) .. showText)
                        else
                            summaryLabel:SetText(condCount .. " conditions" .. ST._GetConditionListContextSuffix(conditions))
                        end
                    else
                        summaryLabel:SetText("|cff888888None|r")
                    end
                    summaryLabel:SetFullWidth(true)
                    container:AddChild(summaryLabel)
                end

                if not talentCollapsed then

                -- LEFT column: the conditions themselves, ending in the Clear
                -- that empties them - meaning wins over balance for a control
                -- this destructive. RIGHT column: the picker that adds to
                -- them, at the head so it lands beside the first condition.
                local talentLeft, talentRight = BeginRowGrid(container)

                -- Condition list display. Each condition presents an ITEM, not
                -- a setting: a CDC-LabelRow with the talent icon inlined into
                -- the label text and the taken/not-taken state as the row's
                -- right-aligned status word.
                if condCount > 0 then
                    local cache = CooldownCompanion._talentNodeCache
                    local currentSpecID = layoutSpecID or CooldownCompanion._currentSpecId
                    local currentHeroSubTreeID = CooldownCompanion._currentHeroSpecId
                    for _, cond in ipairs(conditions) do
                        local displayIcon = not IsHeroSpecProxyCondition(cond)
                            and cond.spellID
                            and C_Spell.GetSpellTexture(cond.spellID)
                        local nameText = ST._GetConditionDisplayName(cond)
                        if displayIcon then
                            nameText = ("|T%s:16:16:0:0|t %s"):format(tostring(displayIcon), nameText)
                        end
                        AddLabelRow(talentLeft, {
                            label = "|cffFFFFFF" .. nameText .. "|r",
                            controlText = (cond.show == "not_taken")
                                and "|cffff4d4d(not taken)|r"
                                or "|cff33dd33(taken)|r",
                        })

                        -- Per-condition stale node warning. A wrapped sentence
                        -- rather than a setting, so it keeps its stock Label
                        -- shape and sits directly under the row it warns about.
                        local matchesCurrentScope = (not cond.specID or cond.specID == currentSpecID)
                            and (not cond.heroSubTreeID or cond.heroSubTreeID == currentHeroSubTreeID)
                        if matchesCurrentScope and cache and not cache[cond.nodeID] then
                            local warnLabel = AceGUI:Create("Label")
                            ST._ConfigureWrappedHelperLabel(warnLabel)
                            warnLabel:SetText("|cffff8800This talent is not in your current active tree, so it behaves as not taken right now.|r")
                            warnLabel:SetFullWidth(true)
                            talentLeft:AddChild(warnLabel)
                        end
                    end
                else
                    local emptyLabel = AceGUI:Create("Label")
                    ST._ConfigureWrappedHelperLabel(emptyLabel)
                    emptyLabel:SetText("|cff888888No talent conditions set.|r")
                    emptyLabel:SetFullWidth(true)
                    talentLeft:AddChild(emptyLabel)
                end

                -- Compact and flush left, inside the grid: a page-wide button
                -- is louder than every row it sits under.
                local pickBtn = AceGUI:Create("Button")
                pickBtn:SetText(condCount > 0 and "Edit" or "Pick Talents")
                pickBtn:SetAutoWidth(true)
                pickBtn:SetCallback("OnClick", function()
                    local initialConditions = cab.talentConditions
                    local specID = layoutSpecID or CooldownCompanion._currentSpecId
                    local specHint = specID and { specs = { [specID] = true } } or nil
                    CooldownCompanion:OpenTalentPicker(function(results)
                        if results then
                            local normalized, changed = CooldownCompanion:NormalizeTalentConditions(results)
                            if changed then
                                results = normalized
                            end
                            customBars[cabIdx].talentConditions = results
                        else
                            customBars[cabIdx].talentConditions = nil
                        end
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end, initialConditions, specHint)
                end)
                talentRight:AddChild(pickBtn)

                -- Clear button (only when conditions exist)
                if condCount > 0 then
                    local clearBtn = AceGUI:Create("Button")
                    clearBtn:SetText("Clear")
                    clearBtn:SetAutoWidth(true)
                    clearBtn:SetCallback("OnClick", function()
                        customBars[cabIdx].talentConditions = nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    talentLeft:AddChild(clearBtn)
                end

                end -- not talentCollapsed
            end

end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildCustomBarWorkspaceAddBox = BuildCustomBarWorkspaceAddBox
ST._OpenConfigCustomBarMenu = OpenConfigCustomBarMenu
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
ST._BuildCustomBarSoundAlertsTab = BuildCustomBarSoundAlertsTab
ST._BuildCustomBarLoadConditionsTab = BuildCustomBarLoadConditionsTab
