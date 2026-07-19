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
local ColorHeading = ST._ColorHeading
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent
local AddColorPicker = ST._AddColorPicker
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown

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

local function AddCustomBarSpecFilterControls(container, settings, entry, currentSpecID)
    local specs = GetCustomBarSpecOptions()
    for _, spec in ipairs(specs) do
        local capturedSpec = spec
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(capturedSpec.name)
        if capturedSpec.icon then
            cb:SetImage(capturedSpec.icon, 0.08, 0.92, 0.08, 0.92)
        end
        cb:SetFullWidth(true)
        cb:SetValue(RB.CustomBarHasExplicitSpec and RB.CustomBarHasExplicitSpec(entry, capturedSpec.id) or false)
        cb:SetCallback("OnValueChanged", function(widget, event, value)
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
        end)
        ApplyCheckboxIndent(cb, 12)
        container:AddChild(cb)
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
    local soundHeading = AceGUI:Create("Heading")
    soundHeading:SetText("Sound Alerts")
    ColorHeading(soundHeading)
    soundHeading:SetHeight(22)
    soundHeading:SetFullWidth(true)
    soundHeading.label:ClearAllPoints()
    soundHeading.label:SetPoint("CENTER", soundHeading.frame, "CENTER", 0, 2)
    soundHeading.left:ClearAllPoints()
    soundHeading.left:SetPoint("LEFT", soundHeading.frame, "LEFT", 3, 0)
    soundHeading.left:SetPoint("RIGHT", soundHeading.label, "LEFT", -5, 0)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundHeading.label, "RIGHT", 5, 0)
    container:AddChild(soundHeading)

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Sound alerts are played through the Master channel and follow your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundInfoBtn, "RIGHT", 4, 0)

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

    for _, eventKey in ipairs(eventOrder) do
        if validEvents[eventKey] then
            local soundDrop = AceGUI:Create("Dropdown")
            soundDrop:SetLabel(CooldownCompanion:GetCustomBarSoundAlertEventLabel(cab, eventKey))
            soundDrop:SetList(soundOptions, soundOptionOrder)
            soundDrop:SetValue(CooldownCompanion:GetCustomBarSoundAlertSelection(cab, eventKey))
            soundDrop:SetFullWidth(true)
            soundDrop:SetCallback("OnValueChanged", function(widget, event, val)
                CooldownCompanion:SetCustomBarSoundAlertEvent(cab, eventKey, val)
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(soundDrop)
        end
    end
end

local function BuildCustomBarLoadConditionsTab(container, cab, infoButtons)
    local settings = CooldownCompanion:GetResourceBarSettings()
    local currentSpecID = GetCurrentConfigSpecID()
    local specsHeading = AceGUI:Create("Heading")
    specsHeading:SetText("Specializations")
    ColorHeading(specsHeading)
    specsHeading:SetFullWidth(true)
    container:AddChild(specsHeading)
    AddCustomBarSpecFilterControls(container, settings, cab, currentSpecID)

    local addScopedLoadConditionToggles = ST._AddScopedLoadConditionToggles
    if type(addScopedLoadConditionToggles) ~= "function" then
        local unavailable = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(unavailable)
        unavailable:SetText("|cff888888Load condition controls are not available yet.|r")
        unavailable:SetFullWidth(true)
        container:AddChild(unavailable)
        return
    end

    addScopedLoadConditionToggles(container, {
        target = cab,
        defaults = CooldownCompanion:GetLocalLoadConditionDefaults(),
        inheritedSources = {},
        headingText = "Hide This Entry In",
        headingTextWhenInherited = "Also Hide This Entry In",
        inheritedCollapsedKey = "loadconditions_custombar_inherited",
        localCollapsedKey = "loadconditions_custombar_local",
        preserveMissing = true,
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
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Entry Load Conditions")
        clearBtn:SetFullWidth(true)
        clearBtn:SetCallback("OnClick", function()
            cab.loadConditions = nil
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(clearBtn)
    end
end

local function AddCustomBarSettingsHeading(container, text, infoButtons, tooltip)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

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
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)
    end
end

local function AddResourceBarsDisabledLabel(container, text)
    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText(text)
    label:SetFullWidth(true)
    container:AddChild(label)
end
ST._AddResourceBarsDisabledLabel = AddResourceBarsDisabledLabel

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
        if entryType == "aura" then
            -- Aura-driven Custom Bars are stubbed until the custom aura bars
            -- phase group rebuilds them. Treat as handled so the add box
            -- clears without a second "not found" message.
            CooldownCompanion:Print("Aura-driven Custom Bars return in a later update.")
            return true
        end
        local entry = {
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

    if not isSpellCustomBar then
        local dormantLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(dormantLabel)
        dormantLabel:SetText("|cffff8800This Custom Bar tracked an aura. It is inactive for now and returns in a later update.|r")
        dormantLabel:SetFullWidth(true)
        container:AddChild(dormantLabel)
    end

            -- Per-slot bar thickness override
            if layout and layout.customBarHeights then
                AddCustomBarSettingsHeading(container, "Size")

                local slotLayout = EnsureCustomBarLayout(settings, layoutSpecID, capturedId, 1000 + capturedIdx) or {}
                local cabHeightSlider = AceGUI:Create("Slider")
                cabHeightSlider:SetLabel(thicknessLabel)
                cabHeightSlider:SetSliderValues(4, 40, 0.1)
                if thicknessField == "barWidth" then
                    cabHeightSlider:SetValue(slotLayout.barWidth or slotLayout.barHeight or layout.barWidth or layout.barHeight or settings.barWidth or settings.barHeight or 12)
                else
                    cabHeightSlider:SetValue(slotLayout.barHeight or slotLayout.barWidth or layout.barHeight or layout.barWidth or settings.barHeight or settings.barWidth or 12)
                end
                cabHeightSlider:SetFullWidth(true)
                local cabIdx = capturedIdx
                cabHeightSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    local customBar = customBars[cabIdx]
                    local customLayout = EnsureCustomBarLayout(settings, layoutSpecID, customBar and customBar.customBarId, 1000 + cabIdx)
                    if customLayout then
                        customLayout[thicknessField] = val
                    end
                    CooldownCompanion:ApplyResourceBars()
                    CooldownCompanion:RepositionCastBar()
                    CooldownCompanion:UpdateAnchorStacking()
                end)
                container:AddChild(cabHeightSlider)
            end

            -- ---- Colors section (spell Custom Bars only) ----
            if cab.spellID then
                local cabIdx = capturedIdx
                local cabApplyBars = function() CooldownCompanion:ApplyResourceBars() end

                if isSpellCustomBar then
                local colorHeading = AceGUI:Create("Heading")
                colorHeading:SetText("Colors")
                ColorHeading(colorHeading)
                colorHeading:SetFullWidth(true)
                container:AddChild(colorHeading)

                AddColorPicker(container, customBars[cabIdx], "barColor", "Bar Color", {0.5, 0.5, 1}, false,
                    cabApplyBars, function() CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx]) end)

                AddColorPicker(container, customBars[cabIdx], "barCooldownColor", "Bar Cooldown Color", {0.6, 0.13, 0.18, 1}, true,
                    cabApplyBars, cabApplyBars)
                AddColorPicker(container, customBars[cabIdx], "barChargeColor", "Bar Recharging Color", {1.0, 0.82, 0.0, 1}, true,
                    cabApplyBars, cabApplyBars)

                -- ---- Text / Duration controls ----
                do
                    local textsHeading = AceGUI:Create("Heading")
                    textsHeading:SetText("Texts")
                    ColorHeading(textsHeading)
                    textsHeading:SetFullWidth(true)
                    container:AddChild(textsHeading)

                    local showDurationControls = true
                    local durationTextCb
                    if showDurationControls then
                        durationTextCb = AceGUI:Create("CheckBox")
                        durationTextCb:SetLabel("Show Duration Text")
                        durationTextCb:SetValue(cab.showDurationText == true)
                        durationTextCb:SetFullWidth(true)
                        durationTextCb:SetCallback("OnValueChanged", function(widget, event, val)
                            customBars[cabIdx].showDurationText = val or nil
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:RefreshConfigPanel()
                        end)
                        container:AddChild(durationTextCb)
                    end

                    -- Show Stack Text
                    local stackVal = cab.showStackText

                    local stackTextCb = AceGUI:Create("CheckBox")
                    local stackTextLabel = "Show Count Text (Charges/Uses)"
                    stackTextCb:SetLabel(stackTextLabel)
                    stackTextCb:SetValue(stackVal == true)
                    stackTextCb:SetFullWidth(true)
                    stackTextCb:SetCallback("OnValueChanged", function(widget, event, val)
                        customBars[cabIdx].showStackText = val or nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    container:AddChild(stackTextCb)

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

                        AddColorPicker(panel, customBars[cabIdx], "durationTextFontColor", "Duration Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars)

                        AddDurationFormatDropdown(panel, customBars[cabIdx], cabApplyBars)
                    end

                    if showDurationControls then
                        AddAdvancedToggle(durationTextCb, "rbCabDurationText_" .. capturedKey, rbCabTextAdvBtns, showDuration, {
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

                        AddColorPicker(panel, customBars[cabIdx], "stackTextFontColor", "Stack Text Color", DEFAULT_RESOURCE_TEXT_COLOR, true, cabApplyBars)
                    end

                    AddAdvancedToggle(stackTextCb, "rbCabStackText_" .. capturedKey, rbCabTextAdvBtns, showStack, {
                        title = stackTextLabel .. " Advanced",
                        build = BuildStackTextAdvanced,
                    })
                end
                end -- isSpellCustomBar

                -- ---- Talent Conditions section ----
                local talentKey = "cab_talent_" .. capturedKey
                local talentHeading, talentCollapsed, talentCollapseBtn = BuildCollapsibleSection(container, "Talent Conditions", talentKey, resourceBarCollapsedSections)

                local talentInfoBtn = CreateInfoButton(talentHeading.frame, talentCollapseBtn, "LEFT", "RIGHT", 2, 0, {
                    "Talent Conditions",
                    {"Show or hide this Custom Bar based on which talents you have selected. If you add multiple conditions, all of them must pass.", 1, 1, 1, true},
                }, infoButtons)
                talentHeading.right:ClearAllPoints()
                talentHeading.right:SetPoint("RIGHT", talentHeading.frame, "RIGHT", -3, 0)
                talentHeading.right:SetPoint("LEFT", talentInfoBtn, "RIGHT", 4, 0)

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

                -- Condition list display
                if condCount > 0 then
                    local cache = CooldownCompanion._talentNodeCache
                    local currentSpecID = layoutSpecID or CooldownCompanion._currentSpecId
                    local currentHeroSubTreeID = CooldownCompanion._currentHeroSpecId
                    for _, cond in ipairs(conditions) do
                        local condLabel = AceGUI:Create("Label")
                        ST._ConfigureWrappedHelperLabel(condLabel)
                        local displayIcon = not IsHeroSpecProxyCondition(cond)
                            and cond.spellID
                            and C_Spell.GetSpellTexture(cond.spellID)
                        if displayIcon then
                            condLabel:SetImage(displayIcon, 0.08, 0.92, 0.08, 0.92)
                            condLabel:SetImageSize(16, 16)
                        end
                        local nameText = ST._GetConditionDisplayName(cond)
                        local showText
                        if cond.show == "not_taken" then
                            showText = " |cffff4d4d(not taken)|r"
                        else
                            showText = " |cff33dd33(taken)|r"
                        end
                        condLabel:SetText("|cffFFFFFF" .. nameText .. "|r" .. showText)
                        condLabel:SetFullWidth(true)
                        container:AddChild(condLabel)

                        -- Per-condition stale node warning
                        local matchesCurrentScope = (not cond.specID or cond.specID == currentSpecID)
                            and (not cond.heroSubTreeID or cond.heroSubTreeID == currentHeroSubTreeID)
                        if matchesCurrentScope and cache and not cache[cond.nodeID] then
                            local warnLabel = AceGUI:Create("Label")
                            ST._ConfigureWrappedHelperLabel(warnLabel)
                            warnLabel:SetText("|cffff8800  This talent is not in your current active tree, so it behaves as not taken right now.|r")
                            warnLabel:SetFullWidth(true)
                            container:AddChild(warnLabel)
                        end
                    end
                else
                    local emptyLabel = AceGUI:Create("Label")
                    ST._ConfigureWrappedHelperLabel(emptyLabel)
                    emptyLabel:SetText("|cff888888No talent conditions set.|r")
                    emptyLabel:SetFullWidth(true)
                    container:AddChild(emptyLabel)
                end

                -- Button row: side-by-side Pick + Clear using Flow layout
                local talentBtnRow = AceGUI:Create("SimpleGroup")
                talentBtnRow:SetFullWidth(true)
                talentBtnRow:SetLayout("Flow")

                local pickBtn = AceGUI:Create("Button")
                pickBtn:SetText(condCount > 0 and "Edit" or "Pick Talents")
                pickBtn:SetRelativeWidth(condCount > 0 and 0.5 or 1)
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
                talentBtnRow:AddChild(pickBtn)

                -- Clear button (only when conditions exist)
                if condCount > 0 then
                    local clearBtn = AceGUI:Create("Button")
                    clearBtn:SetText("Clear")
                    clearBtn:SetRelativeWidth(0.5)
                    clearBtn:SetCallback("OnClick", function()
                        customBars[cabIdx].talentConditions = nil
                        CooldownCompanion:ApplyResourceBars()
                        CooldownCompanion:UpdateAnchorStacking()
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    talentBtnRow:AddChild(clearBtn)
                end

                container:AddChild(talentBtnRow)

                end -- not talentCollapsed
            end

end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildCustomBarWorkspaceAddBox = BuildCustomBarWorkspaceAddBox
ST._OpenConfigCustomBarMenu = OpenConfigCustomBarMenu
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
ST._BuildCustomBarSoundAlertsTab = BuildCustomBarSoundAlertsTab
ST._BuildCustomBarLoadConditionsTab = BuildCustomBarLoadConditionsTab
