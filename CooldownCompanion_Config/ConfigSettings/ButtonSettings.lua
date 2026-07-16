local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local math_pi = math.pi

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local CreateInfoButton = ST._CreateInfoButton
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local BindConfigShiftTooltip = ST._BindConfigShiftTooltip
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local NormalizeItemFallbacks = CooldownCompanion.NormalizeItemFallbacks
local UpdateItemChargeMetadata = CooldownCompanion.UpdateItemChargeMetadata

local RefreshButtonSettingsMultiSelect = ST._RefreshButtonSettingsMultiSelect
local RefreshPanelMultiSelect = ST._RefreshPanelMultiSelect
local BuildOverridesTab = ST._BuildOverridesTab
local SOUND_ALERT_NONE_OPTION_KEY = "None" -- Keep in sync with Core/SoundAlerts.lua SOUND_NONE_KEY.

local function GroupUsesTexturePanelEntries(group)
    return group and (group.displayMode or "icons") == "textures"
end

local function GroupUsesTriggerPanelEntries(group)
    return group and group.displayMode == "trigger"
end

-- 12.1 aura tracking is offered on spell entries in icon/bar groups only:
-- text mode has no compliant aura display (aura numbers can't enter format
-- strings), and trigger/texture panels lost aura conditions by design.
local function EntryOffersAuraTab(group, buttonData)
    if not (buttonData and buttonData.type == "spell") then return false end
    if CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        return false
    end
    local displayMode = group and group.displayMode or "icons"
    return displayMode == "icons" or displayMode == "bars"
end

local function BuildButtonSettingsTabs(group, buttonData)
    if CooldownCompanion:IsRotationAssistantGroup(group) then
        return {
            { value = "loadconditions", text = "Load Conditions" },
        }
    end

    local isEquipmentSlot = CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData)
    if GroupUsesTriggerPanelEntries(group) then
        local tabs = {
            { value = "settings", text = "Condition" },
            { value = "loadconditions", text = "Load Conditions" },
        }
        if not isEquipmentSlot then
            tabs[#tabs + 1] = { value = "soundalerts", text = "Sound Alerts" }
        end
        return tabs
    end

    local tabs = {
        { value = "settings", text = "Settings" },
    }
    if EntryOffersAuraTab(group, buttonData) then
        tabs[#tabs + 1] = { value = "aura", text = "Aura" }
    end
    if buttonData and buttonData.type == "item" then
        tabs[#tabs + 1] = { value = "fallbacks", text = "Fallbacks" }
    elseif not isEquipmentSlot then
        tabs[#tabs + 1] = { value = "soundalerts", text = "Sound Alerts" }
    end

    -- Texture panels only ever manage a single texture entry, so the
    -- per-button Overrides tab does not apply there and just creates noise.
    if not GroupUsesTexturePanelEntries(group) then
        tabs[#tabs + 1] = { value = "overrides", text = "Overrides" }
    end
    tabs[#tabs + 1] = { value = "loadconditions", text = "Load Conditions" }

    return tabs
end

local function BuildSortedSoundOptionOrder(soundOptions)
    local order = {}
    for optionKey in pairs(soundOptions) do
        order[#order + 1] = optionKey
    end

    table.sort(order, function(a, b)
        if a == SOUND_ALERT_NONE_OPTION_KEY then return true end
        if b == SOUND_ALERT_NONE_OPTION_KEY then return false end

        local aLabel = soundOptions[a] or tostring(a)
        local bLabel = soundOptions[b] or tostring(b)
        if aLabel == bLabel then
            return tostring(a) < tostring(b)
        end
        return aLabel < bLabel
    end)

    return order
end

local function ConfigurePriorityMoveButton(button, rotation, tooltipTitle, tooltipBody, disabled, onClick)
    local isDisabled = disabled
    button:SetSize(18, 18)
    if button.text then
        button.text:Hide()
    end
    if not button.icon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    if button.highlight then
        button.highlight:Hide()
        button.highlight:SetAlpha(0)
    end
    button.icon:SetAtlas("arrow-short", false)
    button.icon:SetRotation(rotation)
    if button.icon.SetDesaturated then
        button.icon:SetDesaturated(isDisabled == true)
    end
    button.icon:SetVertexColor(1, 0.82, 0, isDisabled and 0.45 or 1)
    button.icon:Show()
    button:SetAlpha(isDisabled and 0.35 or 1)
    button:EnableMouse(true)
    button:SetScript("OnClick", isDisabled and nil or onClick)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipTitle)
        GameTooltip:AddLine(tooltipBody, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:Show()
end

local SOUND_PREVIEW_ICON_ATLAS = "chatframe-button-icon-voicechat"
local SOUND_PREVIEW_TEXT_LEFT_OFFSET = 18
local SOUND_PREVIEW_TEXT_RIGHT_OFFSET = -8
local SOUND_PREVIEW_TEXT_GAP = -4
local SOUND_PREVIEW_BUTTON_RIGHT_OFFSET = -18

local function ResetSoundPreviewRow(item)
    if not (item and item.frame and item.text) then return end

    local previewBtn = item._cdcSoundPreviewBtn
    if previewBtn then
        previewBtn:SetShown(false)
        previewBtn._cdcButtonData = nil
        previewBtn._cdcGroup = nil
        previewBtn._cdcSoundValue = nil
        previewBtn:ClearAllPoints()
        previewBtn:SetParent(nil)
    end

    item.text:ClearAllPoints()
    item.text:SetPoint("TOPLEFT", item.frame, "TOPLEFT", SOUND_PREVIEW_TEXT_LEFT_OFFSET, 0)
    item.text:SetPoint("BOTTOMRIGHT", item.frame, "BOTTOMRIGHT", SOUND_PREVIEW_TEXT_RIGHT_OFFSET, 0)
end

local function EnsureSoundPreviewRowCleanup(item)
    if not (item and item.SetCallback) then return end

    local releaseCallback = item._cdcSoundPreviewReleaseCallback
    if not releaseCallback then
        releaseCallback = function(widget, event)
            local prevOnRelease = widget._cdcSoundPreviewWrappedOnRelease
            widget._cdcSoundPreviewWrappedOnRelease = nil
            ResetSoundPreviewRow(widget)
            if prevOnRelease then
                prevOnRelease(widget, event)
            end
        end
        item._cdcSoundPreviewReleaseCallback = releaseCallback
    end

    local currentOnRelease = item.events and item.events["OnRelease"]
    if currentOnRelease == releaseCallback then
        return
    end

    item._cdcSoundPreviewWrappedOnRelease = currentOnRelease
    item:SetCallback("OnRelease", releaseCallback)
end

local function ConfigureSoundPreviewRow(item, buttonData, group)
    if not (item and item.frame and item.text) then return end

    EnsureSoundPreviewRowCleanup(item)

    local previewBtn = item._cdcSoundPreviewBtn
    if not previewBtn then
        previewBtn = CreateFrame("Button", nil, item.frame)
        previewBtn:SetSize(16, 16)
        previewBtn:SetHighlightAtlas(SOUND_PREVIEW_ICON_ATLAS)
        if previewBtn:GetHighlightTexture() then
            previewBtn:GetHighlightTexture():SetAlpha(0.3)
        end
        local icon = previewBtn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("CENTER")
        icon:SetAtlas(SOUND_PREVIEW_ICON_ATLAS, false)
        previewBtn._cdcSoundPreviewIcon = icon
        previewBtn:SetScript("OnClick", function(self)
            local previewValue = self._cdcSoundValue
            local previewButtonData = self._cdcButtonData
            local previewGroup = self._cdcGroup
            if previewValue and previewValue ~= SOUND_ALERT_NONE_OPTION_KEY and previewGroup then
                CooldownCompanion:PreviewTriggerPanelSoundAlertSelection(previewGroup, previewValue)
            elseif previewValue and previewValue ~= SOUND_ALERT_NONE_OPTION_KEY and previewButtonData then
                CooldownCompanion:PreviewSoundAlertSelection(previewButtonData, previewValue)
            end
        end)
        item._cdcSoundPreviewBtn = previewBtn
    end

    previewBtn:SetParent(item.frame)
    previewBtn:SetFrameLevel(item.frame:GetFrameLevel() + 1)
    previewBtn:ClearAllPoints()
    previewBtn:SetPoint("RIGHT", item.frame, "RIGHT", SOUND_PREVIEW_BUTTON_RIGHT_OFFSET, 0)
    previewBtn._cdcButtonData = buttonData
    previewBtn._cdcGroup = group

    local previewValue = item.userdata and item.userdata.value
    local hasPreview = previewValue and previewValue ~= SOUND_ALERT_NONE_OPTION_KEY
    previewBtn._cdcSoundValue = hasPreview and previewValue or nil
    previewBtn:SetShown(hasPreview)

    item.text:ClearAllPoints()
    item.text:SetPoint("TOPLEFT", item.frame, "TOPLEFT", SOUND_PREVIEW_TEXT_LEFT_OFFSET, 0)
    if hasPreview then
        item.text:SetPoint("BOTTOMRIGHT", previewBtn, "LEFT", SOUND_PREVIEW_TEXT_GAP, 0)
    else
        item.text:SetPoint("BOTTOMRIGHT", item.frame, "BOTTOMRIGHT", SOUND_PREVIEW_TEXT_RIGHT_OFFSET, 0)
    end
end

local function BuildSpellSoundAlertsSection(scroll, buttonData, infoButtons)
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
    scroll:AddChild(soundHeading)

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Sound alerts are played through the Master channel and follow your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundInfoBtn, "RIGHT", 4, 0)

    local validEvents = CooldownCompanion:GetScopedValidSoundAlertEventsForButton(buttonData)
    if not validEvents then
        local noEvents = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(noEvents)
        noEvents:SetText("|cff888888No alertable sound events are available for this button under its current entry type, tracking mode, and Blizzard Cooldown Manager mapping.|r")
        noEvents:SetFullWidth(true)
        scroll:AddChild(noEvents)
        return
    end

    local soundOptions = CooldownCompanion:GetSoundAlertOptions()
    local soundOptionOrder = BuildSortedSoundOptionOrder(soundOptions)
    local eventOrder = CooldownCompanion:GetSoundAlertEventOrder()

    -- The aura-applied sound plays through Blizzard's aura system, which
    -- accepts sound files only — offer the file-backed options.
    local auraSoundOptions, auraSoundOptionOrder
    if validEvents.onAuraApplied then
        auraSoundOptions = CooldownCompanion:GetAuraAppliedSoundAlertOptions()
        auraSoundOptionOrder = BuildSortedSoundOptionOrder(auraSoundOptions)
    end

    for _, eventKey in ipairs(eventOrder) do
        if validEvents[eventKey] then
            local isAuraEvent = eventKey == "onAuraApplied"
            local row = AceGUI:Create("SimpleGroup")
            row:SetFullWidth(true)
            row:SetLayout("Flow")

            local soundDrop = AceGUI:Create("Dropdown")
            soundDrop:SetLabel(CooldownCompanion:GetSoundAlertEventLabelForButton(buttonData, eventKey))
            if isAuraEvent then
                soundDrop:SetList(auraSoundOptions, auraSoundOptionOrder)
            else
                soundDrop:SetList(soundOptions, soundOptionOrder)
            end
            soundDrop:SetValue(CooldownCompanion:GetButtonSoundAlertSelection(buttonData, eventKey))
            soundDrop:SetFullWidth(true)
            soundDrop:SetCallback("OnOpened", function(widget)
                if not widget.pullout then return end

                -- Inline preview: click the sound icon on a row to test that sound
                -- without selecting it or closing the dropdown.
                for _, item in widget.pullout:IterateItems() do
                    ConfigureSoundPreviewRow(item, buttonData)
                end
            end)

            soundDrop:SetCallback("OnValueChanged", function(widget, event, val)
                CooldownCompanion:SetButtonSoundAlertEvent(buttonData, eventKey, val)
                if isAuraEvent then
                    -- The registration lives on the aura display binding.
                    CooldownCompanion:RequestAuraRebind("config")
                end
                if ST._RefreshColumn2 then
                    ST._RefreshColumn2()
                end
            end)

            if isAuraEvent then
                CreateInfoButton(soundDrop.frame, soundDrop.label, "LEFT", "RIGHT", 4, 0, {
                    "Aura Applied",
                    {"Plays when the tracked aura is applied, handled by the game so it works everywhere. A sound on aura removal is not possible for addons; the Cooldown Manager's own alert settings offer one if needed.", 1, 1, 1, true},
                }, infoButtons)
            end

            row:AddChild(soundDrop)
            scroll:AddChild(row)
        end
    end
end

local function BuildSpellSoundAlertsTab(scroll, buttonData, infoButtons)
    if buttonData.type ~= "spell" then
        local notSpellLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(notSpellLabel)
        notSpellLabel:SetText("|cff888888Sound alerts are available for spell buttons only.|r")
        notSpellLabel:SetFullWidth(true)
        scroll:AddChild(notSpellLabel)
        return
    end

    BuildSpellSoundAlertsSection(scroll, buttonData, infoButtons)
end

local function BuildTriggerPanelSoundAlertsTab(scroll, group, buttonData, infoButtons)
    if not (group and group.displayMode == "trigger") then
        return
    end

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
    scroll:AddChild(soundHeading)

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Plays when the trigger texture appears. This is panel-level and not tied to any one condition. Uses the Master channel and follows your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundInfoBtn, "RIGHT", 4, 0)

    local soundOptions = CooldownCompanion:GetSoundAlertOptions()
    local soundOptionOrder = BuildSortedSoundOptionOrder(soundOptions)

    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")

    local soundDrop = AceGUI:Create("Dropdown")
    soundDrop:SetLabel(CooldownCompanion:GetTriggerPanelSoundAlertEventLabel("onShow"))
    soundDrop:SetList(soundOptions, soundOptionOrder)
    soundDrop:SetValue(CooldownCompanion:GetTriggerPanelSoundAlertSelection(group, "onShow"))
    soundDrop:SetFullWidth(true)
    soundDrop:SetCallback("OnOpened", function(widget)
        if not widget.pullout then return end
        for _, item in widget.pullout:IterateItems() do
            ConfigureSoundPreviewRow(item, buttonData, group)
        end
    end)
    soundDrop:SetCallback("OnValueChanged", function(_, _, value)
        CooldownCompanion:SetTriggerPanelSoundAlertEvent(group, "onShow", value)
    end)

    row:AddChild(soundDrop)
    scroll:AddChild(row)
end

local function CreateCenteredSubHeading(text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetHeight(22)
    heading:SetFullWidth(true)
    heading.label:ClearAllPoints()
    heading.label:SetPoint("CENTER", heading.frame, "CENTER", 0, 2)
    heading.left:ClearAllPoints()
    heading.left:SetPoint("LEFT", heading.frame, "LEFT", 3, 0)
    heading.left:SetPoint("RIGHT", heading.label, "LEFT", -5, 0)
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", heading.label, "RIGHT", 5, 0)
    return heading
end

local function BuildTriggerConditionSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then
        return
    end

    CooldownCompanion:NormalizeTriggerConditionRowData(buttonData)
    local clauses = CooldownCompanion:GetTriggerConditionClauses(buttonData)

    for clauseIndex, clause in ipairs(clauses) do
        scroll:AddChild(CreateCenteredSubHeading("Condition " .. clauseIndex))

        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")

        local excludedKeys = {}
        for otherIndex, otherClause in ipairs(clauses) do
            if otherIndex ~= clauseIndex then
                excludedKeys[#excludedKeys + 1] = otherClause.key
            end
        end

        local checkOptions, checkOrder = CooldownCompanion:GetTriggerConditionTypeOptions(buttonData, excludedKeys)
        local checkDrop = AceGUI:Create("Dropdown")
        checkDrop:SetLabel("Check")
        checkDrop:SetList(checkOptions, checkOrder)
        checkDrop:SetValue(clause.key)
        checkDrop:SetFullWidth(true)
        checkDrop:SetCallback("OnValueChanged", function(_, _, value)
            CooldownCompanion:SetTriggerConditionKey(buttonData, clauseIndex, value)
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        row:AddChild(checkDrop)

        local expectedOptions, expectedOrder = CooldownCompanion:GetTriggerConditionExpectedOptions(clause.key)
        local stateDrop = AceGUI:Create("Dropdown")
        stateDrop:SetLabel("State")
        stateDrop:SetList(expectedOptions, expectedOrder)
        stateDrop:SetValue(CooldownCompanion:GetTriggerConditionStateValue(buttonData, clauseIndex))
        stateDrop:SetFullWidth(true)
        stateDrop:SetCallback("OnValueChanged", function(_, _, value)
            CooldownCompanion:SetTriggerConditionStateValue(buttonData, value, clauseIndex)
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        row:AddChild(stateDrop)

        scroll:AddChild(row)

        local function AddRemoveConditionRow()
            local removeRow = AceGUI:Create("SimpleGroup")
            removeRow:SetFullWidth(true)
            removeRow:SetLayout("Flow")

            local removeBtn = AceGUI:Create("Button")
            removeBtn:SetText("Remove Condition")
            removeBtn:SetFullWidth(true)
            removeBtn:SetCallback("OnClick", function()
                if CooldownCompanion:RemoveTriggerConditionClause(buttonData, clauseIndex) then
                    CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end
            end)
            removeRow:AddChild(removeBtn)
            scroll:AddChild(removeRow)
        end

        if #clauses > 1 then
            AddRemoveConditionRow()
        end

        local conditionSpacer = AceGUI:Create("Label")
        conditionSpacer:SetText(" ")
        conditionSpacer:SetFullWidth(true)
        scroll:AddChild(conditionSpacer)
    end

    local usedKeys = {}
    for _, clause in ipairs(clauses) do
        usedKeys[#usedKeys + 1] = clause.key
    end
    local addOptions, addOrder = CooldownCompanion:GetTriggerConditionTypeOptions(buttonData, usedKeys)
    if #addOrder > 0 then
        scroll:AddChild(CreateCenteredSubHeading("Add Condition"))

        local addRow = AceGUI:Create("SimpleGroup")
        addRow:SetFullWidth(true)
        addRow:SetLayout("Flow")

        local addDrop = AceGUI:Create("Dropdown")
        addDrop:SetLabel("New Condition")
        addDrop:SetList(addOptions, addOrder)
        addDrop:SetValue(addOrder[1])
        addDrop:SetFullWidth(true)
        addRow:AddChild(addDrop)

        local addBtn = AceGUI:Create("Button")
        addBtn:SetText("Add Condition")
        addBtn:SetFullWidth(true)
        addBtn:SetCallback("OnClick", function()
            if CooldownCompanion:AddTriggerConditionClause(buttonData, addDrop:GetValue()) then
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
        addRow:AddChild(addBtn)

        scroll:AddChild(addRow)
    end

end

local function BuildItemSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    -- Charge text settings now live in group Appearance tab (with per-button overrides)
    if UsesChargeBehavior(buttonData) then return end

    local itemKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_itemsettings"
    local itemHeading, itemCollapsed = BuildCollapsibleSection(scroll, "Item Settings", itemKey)


    if not itemCollapsed then
    -- Item count font size
    local itemFontSizeSlider = AceGUI:Create("Slider")
    itemFontSizeSlider:SetLabel("Item Stack Font Size")
    itemFontSizeSlider:SetSliderValues(8, 32, 1)
    itemFontSizeSlider:SetValue(buttonData.itemCountFontSize or 12)
    itemFontSizeSlider:SetFullWidth(true)
    itemFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountFontSize = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemFontSizeSlider)

    -- Item count font
    local itemFontDrop = AceGUI:Create("Dropdown")
    itemFontDrop:SetLabel("Font")
    CS.SetupFontDropdown(itemFontDrop)
    itemFontDrop:SetValue(buttonData.itemCountFont or "Friz Quadrata TT")
    itemFontDrop:SetFullWidth(true)
    CS.SetFontDropdownCallback(itemFontDrop, function(widget, event, val)
        buttonData.itemCountFont = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemFontDrop)

    -- Item count font outline
    local itemOutlineDrop = AceGUI:Create("Dropdown")
    itemOutlineDrop:SetLabel("Font Outline")
    CS.SetupFontOutlineDropdown(itemOutlineDrop)
    itemOutlineDrop:SetValue(buttonData.itemCountFontOutline or "OUTLINE")
    itemOutlineDrop:SetFullWidth(true)
    CS.SetFontOutlineDropdownCallback(itemOutlineDrop, function(widget, event, val)
        buttonData.itemCountFontOutline = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemOutlineDrop)

    -- Item count font color
    local refreshGroup = function() CooldownCompanion:RefreshGroupFrame(CS.selectedGroup) end
    AddColorPicker(scroll, buttonData, "itemCountFontColor", "Font Color", {1, 1, 1, 1}, true, refreshGroup)

    -- Item count anchor point
    local barNoIcon = group.displayMode == "bars" and not (group.style.showBarIcon ~= false)
    local defItemAnchor = barNoIcon and "BOTTOM" or "BOTTOMRIGHT"
    local defItemX = barNoIcon and 0 or -2
    local defItemY = 2

    AddAnchorDropdown(scroll, buttonData, "itemCountAnchor", defItemAnchor, refreshGroup, "Anchor Point")

    -- Item count X offset
    local itemXSlider = AceGUI:Create("Slider")
    itemXSlider:SetLabel("X Offset")
    itemXSlider:SetSliderValues(-20, 20, 0.1)
    itemXSlider:SetValue(buttonData.itemCountXOffset or defItemX)
    itemXSlider:SetFullWidth(true)
    itemXSlider:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountXOffset = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemXSlider)

    -- Item count Y offset
    local itemYSlider = AceGUI:Create("Slider")
    itemYSlider:SetLabel("Y Offset")
    itemYSlider:SetSliderValues(-20, 20, 0.1)
    itemYSlider:SetValue(buttonData.itemCountYOffset or defItemY)
    itemYSlider:SetFullWidth(true)
    itemYSlider:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountYOffset = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemYSlider)

    end -- not itemCollapsed

end

local function BuildEquipItemSettings(scroll, buttonData, infoButtons)
    -- Currently no equip-item-specific settings
end

local function RefreshFallbackEntry(groupId)
    if CS.HideAutocomplete then
        CS.HideAutocomplete()
    end
    CooldownCompanion:RefreshGroupFrame(groupId)
    CooldownCompanion:RefreshConfigPanel()
end

local function GetItemFallbackName(itemID)
    return C_Item.GetItemNameByID(itemID) or ("Item " .. tostring(itemID))
end

local function GetItemQualityAtlas(itemID)
    local qualityInfo = C_TradeSkillUI.GetItemCraftedQualityInfo(itemID)
        or C_TradeSkillUI.GetItemReagentQualityInfo(itemID)
    return qualityInfo and qualityInfo.iconSmall or nil
end

local function GetItemFallbackDisplayName(itemID)
    local itemName = GetItemFallbackName(itemID)
    local qualityAtlas = GetItemQualityAtlas(itemID)
    if qualityAtlas then
        return ("%s |A:%s:20:20|a"):format(itemName, qualityAtlas)
    end
    return itemName
end

local function IsExistingFallback(buttonData, itemID)
    if type(buttonData.itemFallbacks) ~= "table" then
        return false
    end
    for _, existingID in ipairs(buttonData.itemFallbacks) do
        if tonumber(existingID) == itemID then
            return true
        end
    end
    return false
end

local function ValidateFallbackItem(buttonData, itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return nil, "Enter a valid item ID."
    end
    if itemID == tonumber(buttonData.id) then
        return nil, "That item is already the primary item."
    end
    if IsExistingFallback(buttonData, itemID) then
        return nil, "That fallback is already listed."
    end

    if not C_Item.IsItemDataCachedByID(itemID) then
        C_Item.RequestLoadItemDataByID(itemID)
        return nil, "Loading item data. Try again in a moment."
    end

    if CooldownCompanion.IsItemEquippable({ id = itemID }) then
        return nil, "Fallbacks only support non-equippable consumable items."
    end

    if not C_Item.GetItemSpell(itemID) then
        return nil, "Fallback item must have a usable effect."
    end

    return itemID
end

local function IsFallbackAutocompleteCandidate(buttonData, itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return false
    end
    if itemID == tonumber(buttonData.id) or IsExistingFallback(buttonData, itemID) then
        return false
    end
    if CooldownCompanion.IsItemEquippable({ id = itemID }) then
        return false
    end
    return C_Item.GetItemSpell(itemID) ~= nil
end

local function BuildFallbackAutocompleteCache(buttonData)
    local cache = {}
    local seen = {}
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = containerInfo and containerInfo.itemID
            if itemID and not seen[itemID] and IsFallbackAutocompleteCandidate(buttonData, itemID) then
                seen[itemID] = true
                local itemName = containerInfo.itemName or C_Item.GetItemNameByID(itemID) or ("Item " .. tostring(itemID))
                local displayName = GetItemFallbackDisplayName(itemID)
                cache[#cache + 1] = {
                    id = itemID,
                    name = displayName,
                    nameLower = itemName:lower(),
                    icon = containerInfo.iconFileID or C_Item.GetItemIconByID(itemID) or 134400,
                    category = "Bag",
                    isItem = true,
                }
            end
        end
    end
    return cache
end

local function SearchFallbackAutocomplete(buttonData, query)
    if not (CS.SearchAutocompleteInCache and query and #query >= 1) then
        return nil
    end
    return CS.SearchAutocompleteInCache(query, BuildFallbackAutocompleteCache(buttonData))
end

local function AddItemFallback(buttonData, itemID)
    local validID, err = ValidateFallbackItem(buttonData, itemID)
    if not validID then
        CooldownCompanion:Print(err)
        return false
    end

    if not buttonData.itemFallbacks then
        buttonData.itemFallbacks = {}
    end
    buttonData.itemFallbacks[#buttonData.itemFallbacks + 1] = validID
    NormalizeItemFallbacks(buttonData)
    return true
end

local function TryReceiveFallbackItemDrop(buttonData)
    local cursorType, cursorID = GetCursorInfo()
    if cursorType ~= "item" or not cursorID then
        return false
    end

    local added = AddItemFallback(buttonData, cursorID)
    ClearCursor()
    if added then
        RefreshFallbackEntry(CS.selectedGroup)
    end
    return added
end

local function UpdatePrimaryFallbackItem(buttonData, itemID)
    buttonData.id = itemID
    buttonData.name = GetItemFallbackName(itemID)
    buttonData.hasCharges = nil
    buttonData.maxCharges = nil
    UpdateItemChargeMetadata(buttonData, itemID)
end

local function MoveFallbackPriorityItem(buttonData, sourceIndex, targetIndex)
    if not (buttonData and buttonData.type == "item") then
        return false
    end
    local fallbackIDs = buttonData.itemFallbacks
    if type(fallbackIDs) ~= "table" then
        fallbackIDs = {}
    end

    local count = #fallbackIDs
    sourceIndex = tonumber(sourceIndex)
    targetIndex = tonumber(targetIndex)
    if not sourceIndex or not targetIndex or sourceIndex < 0 or sourceIndex > count then
        return false
    end
    if targetIndex < 0 then targetIndex = 0 end
    if targetIndex > count then targetIndex = count end
    if targetIndex == sourceIndex then
        return false
    end

    local orderedIDs = { tonumber(buttonData.id) }
    for _, rawID in ipairs(fallbackIDs) do
        orderedIDs[#orderedIDs + 1] = tonumber(rawID)
    end

    local movedID = table.remove(orderedIDs, sourceIndex + 1)
    if not movedID then
        return false
    end
    table.insert(orderedIDs, targetIndex + 1, movedID)

    local newPrimaryID = orderedIDs[1]
    if not (newPrimaryID and newPrimaryID > 0) then
        return false
    end
    if newPrimaryID ~= tonumber(buttonData.id) then
        UpdatePrimaryFallbackItem(buttonData, newPrimaryID)
    end

    local newFallbacks = {}
    for index = 2, #orderedIDs do
        newFallbacks[#newFallbacks + 1] = orderedIDs[index]
    end
    buttonData.itemFallbacks = newFallbacks
    NormalizeItemFallbacks(buttonData)
    return true
end

local function InstallFallbackDropScript(frame, buttonData)
    if not frame or not frame.SetScript then
        return
    end

    if not frame._cdcFallbackDropWrapped and frame.GetScript then
        frame._cdcFallbackOriginalOnReceiveDrag = frame:GetScript("OnReceiveDrag")
        frame._cdcFallbackOriginalOnMouseUp = frame:GetScript("OnMouseUp")
        frame._cdcFallbackDropWrapped = true
    end
    frame._cdcFallbackDropButtonData = buttonData

    frame:SetScript("OnReceiveDrag", function(self, ...)
        local activeButtonData = self._cdcFallbackDropButtonData
        if CS.buttonSettingsTab == "fallbacks" and activeButtonData then
            local cursorType = GetCursorInfo()
            if cursorType == "item" then
                TryReceiveFallbackItemDrop(activeButtonData)
                return
            end
        end
        local original = self._cdcFallbackOriginalOnReceiveDrag
        if original then
            return original(self, ...)
        end
    end)
    frame:SetScript("OnMouseUp", function(self, button, ...)
        local activeButtonData = self._cdcFallbackDropButtonData
        if CS.buttonSettingsTab ~= "fallbacks" or button ~= "LeftButton" then
            local original = self._cdcFallbackOriginalOnMouseUp
            if original then
                return original(self, button, ...)
            end
            return
        end
        if GetCursorInfo() and activeButtonData then
            TryReceiveFallbackItemDrop(activeButtonData)
            return
        end

        local original = self._cdcFallbackOriginalOnMouseUp
        if original then
            return original(self, button, ...)
        end
    end)
end

local function InstallFallbackColumnDropTargets(scroll, buttonData)
    local seen = {}
    local function addTarget(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            InstallFallbackDropScript(frame, buttonData)
        end
    end

    addTarget(scroll and scroll.frame)
    addTarget(scroll and scroll.scrollframe)
    addTarget(scroll and scroll.content)

    local parent = scroll and scroll.frame and scroll.frame:GetParent()
    for _ = 1, 4 do
        if not parent then break end
        addTarget(parent)
        parent = parent.GetParent and parent:GetParent() or nil
    end
end

local function BuildFallbackRowText(itemID, rowIndex, isPrimary)
    local displayIndex = isPrimary and 1 or (rowIndex + 1)
    local prefix = tostring(displayIndex) .. ". "
    return ("%s%s"):format(
        prefix,
        GetItemFallbackDisplayName(itemID)
    )
end

local function EnsureFallbackMoveButtons(entry, buttonData, rowIndex, isPrimary)
    local frame = entry.frame
    local upBtn = frame._cdcPriorityUpBtn
    if not upBtn and not isPrimary then
        upBtn = CreateFrame("Button", nil, frame)
        frame._cdcPriorityUpBtn = upBtn
    end
    local downBtn = frame._cdcPriorityDownBtn
    if not downBtn then
        downBtn = CreateFrame("Button", nil, frame)
        frame._cdcPriorityDownBtn = downBtn
    end

    local fallbackIDs = buttonData.itemFallbacks or {}
    if isPrimary then
        if upBtn then
            upBtn:Hide()
        end

        downBtn:ClearAllPoints()
        downBtn:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        downBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
        ConfigurePriorityMoveButton(
            downBtn,
            -math_pi / 2,
            "Move Down",
            "Swap this primary item with the first fallback.",
            #fallbackIDs == 0,
            function()
                if MoveFallbackPriorityItem(buttonData, 0, 1) then
                    RefreshFallbackEntry(CS.selectedGroup)
                end
            end
        )
        return
    end

    upBtn:ClearAllPoints()
    upBtn:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
    upBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
    ConfigurePriorityMoveButton(
        upBtn,
        math_pi / 2,
        "Move Up",
        rowIndex == 1 and "Make this fallback the primary item." or "Move this fallback one priority slot higher.",
        false,
        function()
            if MoveFallbackPriorityItem(buttonData, rowIndex, rowIndex - 1) then
                RefreshFallbackEntry(CS.selectedGroup)
            end
        end
    )

    downBtn:ClearAllPoints()
    downBtn:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    downBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
    ConfigurePriorityMoveButton(
        downBtn,
        -math_pi / 2,
        "Move Down",
        "Move this fallback one priority slot lower.",
        rowIndex >= #fallbackIDs,
        function()
            if MoveFallbackPriorityItem(buttonData, rowIndex, rowIndex + 1) then
                RefreshFallbackEntry(CS.selectedGroup)
            end
        end
    )
end

local function ShowFallbackRowMenu(buttonData, rowIndex)
    if not CS.fallbackContextMenu then
        CS.fallbackContextMenu = CreateFrame("Frame", "CDCFallbackContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.fallbackContextMenu, function(_, level)
        if level ~= 1 then return end
        local info = UIDropDownMenu_CreateInfo()
        info.text = "|cffff4444Delete|r"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            local fallbackIDs = buttonData.itemFallbacks
            if type(fallbackIDs) == "table" then
                table.remove(fallbackIDs, rowIndex)
                NormalizeItemFallbacks(buttonData)
                RefreshFallbackEntry(CS.selectedGroup)
            end
        end
        UIDropDownMenu_AddButton(info, level)
    end, "MENU")
    CS.fallbackContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.fallbackContextMenu, "cursor", 0, 0)
end

local function InstallFallbackRowMenu(entry, buttonData, rowIndex)
    entry.frame:SetScript("OnMouseUp", function(_, button)
        if button == "RightButton" then
            ShowFallbackRowMenu(buttonData, rowIndex)
            return
        end
        if button == "LeftButton" and GetCursorInfo() then
            TryReceiveFallbackItemDrop(buttonData)
        end
    end)
end

local function CreateFallbackItemRow(scroll, buttonData, itemID, rowIndex, isPrimary)
    local row = AceGUI:Create("InteractiveLabel")
    CleanRecycledEntry(row)
    row:SetText(BuildFallbackRowText(itemID, rowIndex, isPrimary))
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlight)
    row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    ApplyConfigRowIcon(row, C_Item.GetItemIconByID(itemID) or 134400, { rightPad = isPrimary and 28 or 48 })
    if BindConfigShiftTooltip then
        BindConfigShiftTooltip(row, "item", itemID, row.frame, "ANCHOR_RIGHT")
    end

    if isPrimary then
        row:SetColor(1, 1, 1)
        EnsureFallbackMoveButtons(row, buttonData, 0, true)
        InstallFallbackDropScript(row.frame, buttonData)
    else
        EnsureFallbackMoveButtons(row, buttonData, rowIndex, false)
        InstallFallbackRowMenu(row, buttonData, rowIndex)
    end

    scroll:AddChild(row)
    return row
end

local function BuildItemFallbacksTab(scroll, buttonData, infoButtons)
    if not (buttonData and buttonData.type == "item") then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Fallbacks are available for item entries only.")
        label:SetFullWidth(true)
        scroll:AddChild(label)
        return
    end

    if CooldownCompanion.IsItemEquippable(buttonData) then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Fallbacks are available for non-equippable consumable items only.")
        label:SetFullWidth(true)
        scroll:AddChild(label)
        return
    end

    NormalizeItemFallbacks(buttonData)
    InstallFallbackColumnDropTargets(scroll, buttonData)

    local heading = AceGUI:Create("Heading")
    heading:SetText("Item Fallbacks")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    InstallFallbackDropScript(heading.frame, buttonData)
    scroll:AddChild(heading)

    local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        "Item Fallbacks",
        {"Use arrows to set item priority.", 1, 1, 1, true},
        {"If a higher-priority item is unavailable, the next available fallback can appear instead.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Settings apply to whichever item is currently shown from this priority list.", 1, 1, 1, true},
        {"This includes options like zero-use visibility and desaturation.", 1, 1, 1, true},
    }, infoButtons)
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)

    local primaryID = tonumber(buttonData.id)
    CreateFallbackItemRow(scroll, buttonData, primaryID, 0, true)

    local fallbackIDs = buttonData.itemFallbacks or {}
    if #fallbackIDs > 0 then
        for index, itemID in ipairs(fallbackIDs) do
            CreateFallbackItemRow(scroll, buttonData, itemID, index, false)
        end
    end

    local addBox = AceGUI:Create("EditBox")
    addBox:SetLabel("Search Bag Consumables")
    addBox:SetText("")
    addBox:DisableButton(true)
    addBox:SetFullWidth(true)
    addBox:SetCallback("OnTextChanged", function(widget, _, text)
        if text and #text >= 1 then
            CS.ShowAutocompleteResults(SearchFallbackAutocomplete(buttonData, text), widget, function(entry)
                if entry and AddItemFallback(buttonData, entry.id) then
                    RefreshFallbackEntry(CS.selectedGroup)
                else
                    CS.HideAutocomplete()
                end
            end)
        else
            CS.HideAutocomplete()
        end
    end)
    addBox:SetCallback("OnEnterPressed", function(widget, _, text)
        if CS.ConsumeAutocompleteEnter and CS.ConsumeAutocompleteEnter() then
            return
        end
        CS.HideAutocomplete()
        if AddItemFallback(buttonData, text) then
            widget:SetText("")
            RefreshFallbackEntry(CS.selectedGroup)
        end
    end)
    if addBox.editbox and addBox.editbox.Instructions then
        addBox.editbox.Instructions:Hide()
    end
    InstallFallbackDropScript(addBox.frame, buttonData)
    InstallFallbackDropScript(addBox.editbox, buttonData)
    if CS.SetupAutocompleteKeyHandler then
        CS.SetupAutocompleteKeyHandler(addBox)
    end
    scroll:AddChild(addBox)
end

------------------------------------------------------------------------
-- TYPE CLASSIFICATION (for batch visibility)
------------------------------------------------------------------------
local function GetButtonEntryType(buttonData)
    if CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        return "equipmentSlot"
    end
    if buttonData.type == "item" then return "item" end
    if buttonData.addedAs == "aura" then return "aura" end
    if buttonData.addedAs == "spell" then return "spell" end
    return buttonData.isPassive and "aura" or "spell"
end

local function GetMultiSelectUniformType(group, multiIndices)
    local firstType
    for _, idx in ipairs(multiIndices) do
        local bd = group.buttons[idx]
        if not bd then return nil end
        local t = GetButtonEntryType(bd)
        if not firstType then
            firstType = t
        elseif t ~= firstType then
            return nil
        end
    end
    return firstType
end

------------------------------------------------------------------------
-- BUTTON SETTINGS COLUMN: Refresh
------------------------------------------------------------------------

local function RefreshButtonSettingsColumn()
    local cf = CS.configFrame
    if not cf then return end
    local bsCol = cf.col3
    if not bsCol or not bsCol.bsTabGroup then return end

    -- Check for multiselect
    local multiCount = 0
    local multiIndices = {}
    if CS.selectedGroup then
        for idx in pairs(CS.selectedButtons) do
            multiCount = multiCount + 1
            table.insert(multiIndices, idx)
        end
    end

    if multiCount >= 2 then
        -- Multiselect: hide tabs and placeholder, show dedicated scroll
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end

        if not bsCol.multiSelectScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(bsCol.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", bsCol.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", bsCol.content, "BOTTOMRIGHT", 0, 0)
            bsCol.multiSelectScroll = scroll
        end
        bsCol.multiSelectScroll:ReleaseChildren()
        bsCol.multiSelectScroll.frame:Show()
        local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
        local uniformType = group and GetMultiSelectUniformType(group, multiIndices) or nil
        RefreshButtonSettingsMultiSelect(bsCol.multiSelectScroll, multiCount, multiIndices, uniformType)
        return
    end

    -- Hide multiselect scroll when not in multiselect mode
    if bsCol.multiSelectScroll then
        bsCol.multiSelectScroll.frame:Hide()
    end

    -- Check if a valid single button is selected
    local hasSelection = false
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local rotationAssistantSelection = group
        and CooldownCompanion:IsRotationAssistantGroup(group)
        and CS.selectedRotationAssistantEntry == true
    if rotationAssistantSelection then
        hasSelection = true
    elseif CS.selectedGroup and CS.selectedButton then
        if group and group.buttons[CS.selectedButton] then
            hasSelection = true
        end
    end

    if hasSelection then
        local buttonData = group and group.buttons and group.buttons[CS.selectedButton]
        bsCol.bsTabGroup:SetTabs(BuildButtonSettingsTabs(group, buttonData))
        local isEquipmentSlot = CooldownCompanion.IsEquipmentSlotEntry
            and CooldownCompanion.IsEquipmentSlotEntry(buttonData)

        if rotationAssistantSelection then
            CS.buttonSettingsTab = "loadconditions"
        elseif GroupUsesTriggerPanelEntries(group)
            and CS.buttonSettingsTab ~= "settings"
            and CS.buttonSettingsTab ~= "loadconditions"
            and (CS.buttonSettingsTab ~= "soundalerts" or isEquipmentSlot) then
            CS.buttonSettingsTab = "settings"
        elseif GroupUsesTexturePanelEntries(group) and CS.buttonSettingsTab == "overrides" then
            CS.buttonSettingsTab = "settings"
        elseif isEquipmentSlot
            and (CS.buttonSettingsTab == "soundalerts" or CS.buttonSettingsTab == "fallbacks") then
            CS.buttonSettingsTab = "settings"
        elseif buttonData and buttonData.type == "item" and CS.buttonSettingsTab == "soundalerts" then
            CS.buttonSettingsTab = "fallbacks"
        elseif buttonData and buttonData.type ~= "item" and CS.buttonSettingsTab == "fallbacks" then
            CS.buttonSettingsTab = "soundalerts"
        elseif CS.buttonSettingsTab == "aura" and not EntryOffersAuraTab(group, buttonData) then
            CS.buttonSettingsTab = "settings"
        end

        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end
        bsCol.bsTabGroup.frame:Show()
        bsCol.bsTabGroup:SelectTab(CS.buttonSettingsTab or (rotationAssistantSelection and "loadconditions" or "settings"))
    else
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then
            local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
            bsCol.bsPlaceholder:SetText(GroupUsesTriggerPanelEntries(group) and "Select an entry to configure" or "Select a spell or item to configure")
            bsCol.bsPlaceholder:Show()
        end
    end
end

local function ConfigureInlineEditBoxInstructions(editBoxWidget, placeholderText, currentValue)
    local editFrame = editBoxWidget.editbox
    local instructions = editFrame._cdcInstructions
    if not instructions then
        instructions = editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        instructions:SetPoint("LEFT", editFrame, "LEFT", 0, 0)
        instructions:SetPoint("RIGHT", editFrame, "RIGHT", 0, 0)
        instructions:SetTextColor(0.5, 0.5, 0.5)
        editFrame._cdcInstructions = instructions
    end

    instructions:SetText(placeholderText)
    if (currentValue or "") ~= "" then
        instructions:Hide()
    else
        instructions:Show()
    end

    local prevOnRelease = editBoxWidget.events and editBoxWidget.events["OnRelease"]
    editBoxWidget:SetCallback("OnRelease", function(widget)
        if prevOnRelease then
            prevOnRelease(widget, "OnRelease")
        end
        instructions:Hide()
        instructions:SetText("")
    end)

    editBoxWidget:SetCallback("OnTextChanged", function(widget, event, text)
        if text == "" then
            instructions:Show()
        else
            instructions:Hide()
        end
    end)
end

local function BuildCustomNameSection(scroll, buttonData)
    if CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        return
    end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group or group.displayMode ~= "bars" then return end

    local customNameKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_customname"
    local customNameHeading, customNameCollapsed = BuildCollapsibleSection(scroll, "Custom Name", customNameKey)

    if not customNameCollapsed then
        local customNameBox = AceGUI:Create("EditBox")
        customNameBox:SetLabel("")
        customNameBox:SetText(buttonData.customName or "")
        customNameBox:SetFullWidth(true)
        customNameBox:SetCallback("OnEnterPressed", function(widget, event, text)
            text = strtrim(text)
            buttonData.customName = text ~= "" and text or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        scroll:AddChild(customNameBox)

        ConfigureInlineEditBoxInstructions(
            customNameBox,
            "add custom name here, leave blank for default",
            buttonData.customName
        )
    end -- not customNameCollapsed
end

local function BuildCustomKeybindSection(scroll, buttonData)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group or group.displayMode ~= "icons" then return end

    local effectiveStyle = CooldownCompanion:GetEffectiveStyle(group.style or {}, buttonData)
    if not (effectiveStyle and effectiveStyle.showKeybindText) then
        return
    end

    local collapseKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_customkeybind"
    local heading, isCollapsed = BuildCollapsibleSection(scroll, "Custom Keybind Text", collapseKey)

    if not isCollapsed then
        local customKeybindBox = AceGUI:Create("EditBox")
        customKeybindBox:SetLabel("")
        customKeybindBox:SetText(buttonData.customKeybindText or "")
        customKeybindBox:SetFullWidth(true)
        customKeybindBox:SetCallback("OnEnterPressed", function(widget, event, text)
            text = strtrim(text)
            buttonData.customKeybindText = text ~= "" and text or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        scroll:AddChild(customKeybindBox)

        ConfigureInlineEditBoxInstructions(
            customKeybindBox,
            "add custom keybind text here, leave blank for default",
            buttonData.customKeybindText
        )
    end
end

-- Expose for Config.lua
ST._BuildItemSettings = BuildItemSettings
ST._BuildEquipItemSettings = BuildEquipItemSettings
ST._BuildItemFallbacksTab = BuildItemFallbacksTab
ST._RefreshButtonSettingsColumn = RefreshButtonSettingsColumn
ST._RefreshButtonSettingsMultiSelect = RefreshButtonSettingsMultiSelect
ST._RefreshPanelMultiSelect = RefreshPanelMultiSelect
ST._BuildCustomNameSection = BuildCustomNameSection
ST._BuildCustomKeybindSection = BuildCustomKeybindSection
ST._BuildOverridesTab = BuildOverridesTab
ST._BuildSpellSoundAlertsTab = BuildSpellSoundAlertsTab
ST._BuildTriggerPanelSoundAlertsTab = BuildTriggerPanelSoundAlertsTab
ST._BuildTriggerConditionSettings = BuildTriggerConditionSettings
