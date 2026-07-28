local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local math_pi = math.pi

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local CreateInfoButton = ST._CreateInfoButton
local AddAnchorDropdown = ST._AddAnchorDropdown
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local BindConfigShiftTooltip = ST._BindConfigShiftTooltip
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local NormalizeItemFallbacks = CooldownCompanion.NormalizeItemFallbacks
local UpdateItemChargeMetadata = CooldownCompanion.UpdateItemChargeMetadata

-- Imports from RowWidgets.lua (the row grammar). Sound Alerts, Item Settings,
-- Custom Name and Custom Keybind Text are converted; the trigger-panel
-- surfaces and the fallback item rows still draw stock widgets.
-- ST._BeginRowGrid stays a function-local at each builder, the convention
-- every converted surface follows.
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddEditBoxRow = ST._AddEditBoxRow
local AddColorRow = ST._AddColorRow
local AnchorRowBadge = ST._AnchorRowBadge

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- Sound option labels read "Category - Name" and LibSharedMedia font names run
-- well past the 140px control column, and a dropdown sizes its menu from the
-- control.
local SOUND_PULLOUT_WIDTH = 300
local FONT_PULLOUT_WIDTH = 300

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
            { value = "loadconditions", text = "Visibility" },
        }
    end

    -- Sound Alerts and Item Fallbacks are not tabs: they live as bottom
    -- sections of this entry's Settings ("Condition" on trigger panels) tab.
    if GroupUsesTriggerPanelEntries(group) then
        return {
            { value = "settings", text = "Condition" },
            { value = "loadconditions", text = "Visibility" },
        }
    end

    local tabs = {
        { value = "settings", text = "Settings" },
    }
    if EntryOffersAuraTab(group, buttonData) then
        tabs[#tabs + 1] = { value = "aura", text = "Aura" }
    end

    -- Texture panels only ever manage a single texture entry, so the
    -- per-button Overrides tab does not apply there and just creates noise.
    if not GroupUsesTexturePanelEntries(group) then
        tabs[#tabs + 1] = { value = "overrides", text = "Overrides" }
    end
    tabs[#tabs + 1] = { value = "loadconditions", text = "Visibility" }

    return tabs
end

-- Entry tabs are appended to the panel tabs in one shared row. The gap in
-- front of the cluster, the entry's own icon on its first tab, and the
-- selection accent on every entry label are what separate the two scopes -
-- and what tells the two "Visibility" tabs apart without renaming
-- either of them.
local function EntryTabIconMarkup(icon)
    if not icon or icon == "" then return "" end
    return string.format("|T%s:13:13:0:0|t ", tostring(icon))
end

-- `text` stays untinted: it is what BuildTabs measures the tab against, and
-- what the tab shows while it is the selected one, so selection still reads
-- as a highlight. `accentText` is the tinted variant the row swaps in on
-- every other entry tab.
local function DecorateEntryTabs(tabs, iconMarkup)
    for index, tab in ipairs(tabs) do
        local prefix = (index == 1) and iconMarkup or ""
        tab.accentText = prefix .. ST._GetClassColoredText(tab.text)
        tab.text = prefix .. tab.text
    end
    return tabs
end

local function GetSelectedEntryIconMarkup(group, buttonData)
    if CooldownCompanion:IsRotationAssistantGroup(group) then
        return EntryTabIconMarkup(CooldownCompanion:GetRotationAssistantFallbackIcon())
    end
    if not buttonData then return "" end
    return EntryTabIconMarkup(ST._GetButtonIcon(buttonData))
end

-- Multi-select is one appended tab: a stacked marker built from the first
-- two selected entries' icons, plus the count.
local function BuildEntryMultiSelectTabs(group, multiCount, multiIndices)
    local sorted = {}
    for _, index in ipairs(multiIndices) do
        sorted[#sorted + 1] = index
    end
    table.sort(sorted)

    local marker = ""
    for position = 1, math.min(2, #sorted) do
        local entryData = group and group.buttons and group.buttons[sorted[position]]
        if entryData then
            marker = marker .. EntryTabIconMarkup(ST._GetButtonIcon(entryData))
        end
    end

    local label = multiCount .. " entries"
    return {
        {
            value = "multiselect",
            text = marker .. label,
            accentText = marker .. ST._GetClassColoredText(label),
        },
    }
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

local function SoundAlertsCollapseKey()
    return tostring(CS.selectedGroup) .. "_" .. tostring(CS.selectedButton) .. "_soundalerts"
end

-- Row grammar (RowWidgets.lua): one CDC-DropdownRow per alertable event in a
-- two-column grid. Expects the tab's ScrollFrame (a "List") directly.
local function BuildSpellSoundAlertsSection(scroll, buttonData, infoButtons)
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

    local soundHeading, soundCollapsed =
        BuildCollapsibleSection(scroll, "Sound Alerts", SoundAlertsCollapseKey(), nil, nil, ROW_SECTION)

    -- The heading's "?" chains off the end of its label; the fading rule
    -- restarts after that badge.
    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Sound alerts are played through the Master channel and follow your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    AnchorLeftAlignedHeadingRule(soundHeading, soundInfoBtn)

    if soundCollapsed then return end

    local validEvents = CooldownCompanion:GetScopedValidSoundAlertEventsForButton(buttonData)
    if not validEvents then
        -- A transient state of the entry's tracking, not a setting, so it stays
        -- a full-width wrapped label under the heading rather than a row.
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

    -- The aura sounds play through Blizzard's aura system, which accepts
    -- sound files only — offer the file-backed options.
    local auraSoundOptions, auraSoundOptionOrder
    if validEvents.onAuraApplied or validEvents.onAuraStackGained or validEvents.onAuraRemoved then
        auraSoundOptions = CooldownCompanion:GetAuraSoundAlertOptions()
        auraSoundOptionOrder = BuildSortedSoundOptionOrder(auraSoundOptions)
    end

    -- This row set is FILTERED (see the fill rule in the recipe comment): an
    -- entry carries only the event families its type and Cooldown Manager
    -- mapping allow. So the family split - LEFT the cooldown-side events, RIGHT
    -- the aura-side ones (the native C_UnitAuras triggers) - only runs when
    -- BOTH families survive. When one family is all that is left it splits
    -- itself across the columns left-first, so the left column is never the
    -- empty one. Same shape as the custom-bar Sound Alerts tab.
    local cooldownEvents, auraEvents = {}, {}
    for _, eventKey in ipairs(eventOrder) do
        if validEvents[eventKey] then
            local family = CooldownCompanion:IsAuraSoundAlertEvent(eventKey) and auraEvents or cooldownEvents
            family[#family + 1] = eventKey
        end
    end

    local soundLeft, soundRight = BeginRowGrid(scroll)

    local function AddSoundEventRow(column, eventKey)
        local isAuraEvent = CooldownCompanion:IsAuraSoundAlertEvent(eventKey)
        local row = AddDropdownRow(column, {
            label = CooldownCompanion:GetSoundAlertEventLabelForButton(buttonData, eventKey),
            pulloutWidth = SOUND_PULLOUT_WIDTH,
            list = isAuraEvent and auraSoundOptions or soundOptions,
            order = isAuraEvent and auraSoundOptionOrder or soundOptionOrder,
            value = CooldownCompanion:GetButtonSoundAlertSelection(buttonData, eventKey),
            onChange = function(val)
                CooldownCompanion:SetButtonSoundAlertEvent(buttonData, eventKey, val)
                if isAuraEvent then
                    -- The registration lives on the aura display binding.
                    CooldownCompanion:RequestAuraRebind("config")
                end
                -- Sound status feeds the mirror slot and identity strip badges.
                if ST._RefreshButtonsPreviewMirror then
                    ST._RefreshButtonsPreviewMirror()
                end
            end,
        })

        -- Inline preview: click the sound icon on a pullout row to test that
        -- sound without selecting it or closing the dropdown. CDC-DropdownRow
        -- forwards its embedded dropdown's OnOpened with self = the row and
        -- aliases row.pullout, so this registers on the ROW only - registering
        -- on the child as well would configure every item twice.
        row:SetCallback("OnOpened", function(widget)
            if not widget.pullout then return end
            for _, item in widget.pullout:IterateItems() do
                ConfigureSoundPreviewRow(item, buttonData)
            end
        end)

        if eventKey == "onAuraApplied" then
            -- Anchor args are a placeholder - AnchorRowBadge re-points the
            -- button onto the end of the row's label.
            AnchorRowBadge(row, CreateInfoButton(row.frame, row.frame, "LEFT", "LEFT", 0, 0, {
                "Aura Sounds",
                {"Aura Applied, Aura Stack Gained, and Aura Removed play when the tracked aura is gained, gains a stack, or is removed. Handled by the game so they work everywhere.", 1, 1, 1, true},
            }, infoButtons))
        end

        return row
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

local function BuildTriggerPanelSoundAlertsSection(scroll, group, buttonData, infoButtons)
    if not (group and group.displayMode == "trigger") then
        return
    end

    local soundHeading, soundCollapsed, soundCollapseBtn =
        BuildCollapsibleSection(scroll, "Sound Alerts", SoundAlertsCollapseKey())

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundCollapseBtn, "LEFT", "RIGHT", 2, 0, {
        "Sound Alerts",
        {"Plays when the trigger texture appears. This is panel-level and not tied to any one condition. Uses the Master channel and follows your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundInfoBtn, "RIGHT", 4, 0)

    if soundCollapsed then return end

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

-- Sound alerts sit at the foot of the entry's Settings tab ("Condition" on
-- trigger panels) on every panel type. Entries that never had a sound surface
-- (equipment slots, and anything that is not a spell outside trigger panels)
-- add nothing rather than a section that only says "not available".
local function BuildEntrySoundAlertsSection(scroll, group, buttonData, infoButtons)
    if CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        return
    end

    if group and group.displayMode == "trigger" then
        BuildTriggerPanelSoundAlertsSection(scroll, group, buttonData, infoButtons)
        return
    end

    if not (buttonData and buttonData.type == "spell") then return end

    -- Row grammar: the event rows sit in a BeginRowGrid the section opens on
    -- the scroll itself, so no Flow host is interposed any more.
    BuildSpellSoundAlertsSection(scroll, buttonData, infoButtons)
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
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    -- Charge text settings now live in group Appearance tab (with per-button overrides)
    if UsesChargeBehavior(buttonData) then return end

    local itemKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_itemsettings"
    local _, itemCollapsed = BuildCollapsibleSection(scroll, "Item Settings", itemKey, nil, nil, ROW_SECTION)
    if itemCollapsed then return end

    local refreshGroup = function() CooldownCompanion:RefreshGroupFrame(CS.selectedGroup) end

    -- LEFT column: what the stack count is drawn WITH - size, face, outline.
    -- RIGHT column: what it looks like and where it lands - color, anchor, and
    -- the two offsets that only mean anything once the anchor is picked.
    local itemLeft, itemRight = BeginRowGrid(scroll)

    AddSliderRow(itemLeft, {
        label = "Item Stack Font Size",
        min = 8, max = 32, step = 1,
        value = buttonData.itemCountFontSize or 12,
        onChange = function(val)
            buttonData.itemCountFontSize = val
            refreshGroup()
        end,
    })

    -- FONT ROW PILOT. The row is created with a label and a widened pullout but
    -- NO list and NO onChange, then handed to the shared font helpers exactly
    -- as a stock Dropdown would be: CDC-DropdownRow forwards SetList and
    -- SetDisabled to its embedded child and forwards the child's OnOpened with
    -- self = the row (aliasing row.pullout), which is everything
    -- CS.SetupFontDropdown touches. AddDropdownRow registers OnValueChanged
    -- only when opts.onChange is given, so SetFontDropdownCallback is the one
    -- registration and the profile-wide font lock still gates every write.
    -- The value is set AFTER SetupFontDropdown, because SetList rebuilds the
    -- list the displayed text is read from.
    local itemFontRow = AddDropdownRow(itemLeft, {
        label = "Font",
        pulloutWidth = FONT_PULLOUT_WIDTH,
    })
    CS.SetupFontDropdown(itemFontRow)
    itemFontRow:SetValue(buttonData.itemCountFont or "Friz Quadrata TT")
    CS.SetFontDropdownCallback(itemFontRow, function(widget, event, val)
        buttonData.itemCountFont = val
        refreshGroup()
    end)

    local itemOutlineRow = AddDropdownRow(itemLeft, {
        label = "Font Outline",
    })
    CS.SetupFontOutlineDropdown(itemOutlineRow)
    itemOutlineRow:SetValue(buttonData.itemCountFontOutline or "OUTLINE")
    CS.SetFontOutlineDropdownCallback(itemOutlineRow, function(widget, event, val)
        buttonData.itemCountFontOutline = val
        refreshGroup()
    end)

    -- Item count font color. No deferCommit: this call site never had one, and
    -- nothing here re-reads the bound table per tick.
    AddColorRow(itemRight, {
        label = "Font Color",
        tbl = buttonData,
        key = "itemCountFontColor",
        default = {1, 1, 1, 1},
        hasAlpha = true,
        onConfirm = refreshGroup,
    })

    -- Item count anchor point
    local barNoIcon = group.displayMode == "bars" and not (group.style.showBarIcon ~= false)
    local defItemAnchor = barNoIcon and "BOTTOM" or "BOTTOMRIGHT"
    local defItemX = barNoIcon and 0 or -2
    local defItemY = 2

    AddAnchorDropdown(itemRight, buttonData, "itemCountAnchor", defItemAnchor, refreshGroup,
        "Anchor Point", { row = true })

    AddSliderRow(itemRight, {
        label = "X Offset",
        min = -20, max = 20, step = 0.1,
        value = buttonData.itemCountXOffset or defItemX,
        onChange = function(val)
            buttonData.itemCountXOffset = val
            refreshGroup()
        end,
    })

    AddSliderRow(itemRight, {
        label = "Y Offset",
        min = -20, max = 20, step = 0.1,
        value = buttonData.itemCountYOffset or defItemY,
        onChange = function(val)
            buttonData.itemCountYOffset = val
            refreshGroup()
        end,
    })
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

local function ItemFallbacksCollapseKey()
    return tostring(CS.selectedGroup) .. "_" .. tostring(CS.selectedButton) .. "_itemfallbacks"
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
    else
        EnsureFallbackMoveButtons(row, buttonData, rowIndex, false)
        InstallFallbackRowMenu(row, buttonData, rowIndex)
    end

    scroll:AddChild(row)
    return row
end

-- Item fallbacks sit at the foot of the entry's Settings tab. Entries that
-- never had a fallbacks surface (non-items, equippable items) add nothing
-- rather than a section that only says "not available".
local function BuildItemFallbacksSection(scroll, buttonData, infoButtons)
    if not (buttonData and buttonData.type == "item") then return end
    if CooldownCompanion.IsItemEquippable(buttonData) then return end

    NormalizeItemFallbacks(buttonData)

    local heading, collapsed =
        BuildCollapsibleSection(scroll, "Item Fallbacks", ItemFallbacksCollapseKey(), nil, nil, ROW_SECTION)

    -- The heading's "?" chains off the end of its label; the fading rule
    -- restarts after that badge.
    local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        "Item Fallbacks",
        {"Use arrows to set item priority.", 1, 1, 1, true},
        {"If a higher-priority item is unavailable, the next available fallback can appear instead.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Settings apply to whichever item is currently shown from this priority list.", 1, 1, 1, true},
        {"This includes options like zero-use visibility and desaturation.", 1, 1, 1, true},
    }, infoButtons)
    AnchorLeftAlignedHeadingRule(heading, infoBtn)

    if collapsed then return end

    -- The fallback item rows below are ITEMS, not settings: an icon, a priority
    -- label, reorder arrows and a right-click menu. They stay full-width
    -- InteractiveLabels on the tab surface until that interaction set gets a
    -- row shape of its own.
    local primaryID = tonumber(buttonData.id)
    CreateFallbackItemRow(scroll, buttonData, primaryID, 0, true)

    local fallbackIDs = buttonData.itemFallbacks or {}
    if #fallbackIDs > 0 then
        for index, itemID in ipairs(fallbackIDs) do
            CreateFallbackItemRow(scroll, buttonData, itemID, index, false)
        end
    end

    -- Kept as a stock full-width EditBox: CS.ShowAutocompleteResults anchors its
    -- results popup to the widget's FRAME, which on a CDC-EditBoxRow is the
    -- whole cell, so the list would open under the label instead of under the
    -- 140px input. Converting it needs an anchor contract the row does not have
    -- yet, and hacking one in is not worth it here.
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

    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]

    -- Check if a valid single button is selected
    local hasSelection = false
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

    -- The entry cluster of the unified row: one tab for a multi-select,
    -- this entry's tab set for a single selection, nothing at all when the
    -- selection went away.
    local entryTabs, activeTab
    if multiCount >= 2 and group then
        entryTabs = BuildEntryMultiSelectTabs(group, multiCount, multiIndices)
        activeTab = "multiselect"
    elseif hasSelection then
        local buttonData = group and group.buttons and group.buttons[CS.selectedButton]

        if rotationAssistantSelection then
            CS.buttonSettingsTab = "loadconditions"
        elseif CS.buttonSettingsTab == "soundalerts" or CS.buttonSettingsTab == "fallbacks" then
            -- Both are sections of Settings now; migrate saved tab keys.
            CS.buttonSettingsTab = "settings"
        elseif GroupUsesTriggerPanelEntries(group)
            and CS.buttonSettingsTab ~= "settings"
            and CS.buttonSettingsTab ~= "loadconditions" then
            CS.buttonSettingsTab = "settings"
        elseif GroupUsesTexturePanelEntries(group) and CS.buttonSettingsTab == "overrides" then
            CS.buttonSettingsTab = "settings"
        elseif CS.buttonSettingsTab == "aura" and not EntryOffersAuraTab(group, buttonData) then
            CS.buttonSettingsTab = "settings"
        end

        entryTabs = DecorateEntryTabs(
            BuildButtonSettingsTabs(group, buttonData),
            GetSelectedEntryIconMarkup(group, buttonData)
        )
        activeTab = CS.buttonSettingsTab or (rotationAssistantSelection and "loadconditions" or "settings")
    end

    if not entryTabs then
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then
            bsCol.bsPlaceholder:SetText(GroupUsesTriggerPanelEntries(group) and "Select an entry to configure" or "Select a spell or item to configure")
            bsCol.bsPlaceholder:Show()
        end
        ST._UnifiedRowApply()
        return
    end

    if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end
    -- Shown before the tabs are built so the row lays out against its final
    -- state in one pass.
    bsCol.bsTabGroup.frame:Show()
    bsCol.bsTabGroup:SetTabs(entryTabs)

    -- A panel tab is showing its own content: the entry keeps its place in
    -- the row and its remembered tab, but selecting it here would pull the
    -- surface back to entry scope.
    if not ST._UnifiedRowPrimaryOwnsSurface() then
        bsCol.bsTabGroup:SelectTab(activeTab)
    end
    ST._UnifiedRowApply()
end

-- Content for the appended multi-select tab (the batch surface that used to
-- take the whole settings area over).
function ST._BuildEntryMultiSelectTab(scroll)
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local multiCount, multiIndices = 0, {}
    for index in pairs(CS.selectedButtons) do
        multiCount = multiCount + 1
        multiIndices[#multiIndices + 1] = index
    end
    if multiCount < 2 then return end

    RefreshButtonSettingsMultiSelect(scroll, multiCount, multiIndices, GetMultiSelectUniformType(group, multiIndices))
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
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

    if CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        return
    end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group or group.displayMode ~= "bars" then return end

    local customNameKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_customname"
    local _, customNameCollapsed =
        BuildCollapsibleSection(scroll, "Custom Name", customNameKey, nil, nil, ROW_SECTION)
    if customNameCollapsed then return end

    -- One setting, so the grid keeps its left column only.
    local customNameLeft = BeginRowGrid(scroll)
    local customNameRow = AddEditBoxRow(customNameLeft, {
        label = "Custom Name",
        value = buttonData.customName or "",
        onEnterPressed = function(text)
            text = strtrim(text)
            buttonData.customName = text ~= "" and text or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })

    -- The helper only touches the widget's .editbox frame and its own callback
    -- registry, both of which CDC-EditBoxRow exposes, so it composes as-is. The
    -- placeholder prose is shortened: the row's label already names the
    -- setting, and the old sentence cannot fit a 140px control.
    ConfigureInlineEditBoxInstructions(
        customNameRow,
        "leave blank for default",
        buttonData.customName
    )
end

local function BuildCustomKeybindSection(scroll, buttonData)
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group or group.displayMode ~= "icons" then return end

    local effectiveStyle = CooldownCompanion:GetEffectiveStyle(group.style or {}, buttonData)
    if not (effectiveStyle and effectiveStyle.showKeybindText) then
        return
    end

    local collapseKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_customkeybind"
    local _, isCollapsed =
        BuildCollapsibleSection(scroll, "Custom Keybind Text", collapseKey, nil, nil, ROW_SECTION)
    if isCollapsed then return end

    local keybindLeft = BeginRowGrid(scroll)
    local customKeybindRow = AddEditBoxRow(keybindLeft, {
        label = "Custom Keybind Text",
        value = buttonData.customKeybindText or "",
        onEnterPressed = function(text)
            text = strtrim(text)
            buttonData.customKeybindText = text ~= "" and text or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })

    ConfigureInlineEditBoxInstructions(
        customKeybindRow,
        "leave blank for default",
        buttonData.customKeybindText
    )
end

-- Expose for Config.lua
ST._BuildItemSettings = BuildItemSettings
ST._BuildEquipItemSettings = BuildEquipItemSettings
ST._BuildItemFallbacksSection = BuildItemFallbacksSection
ST._RefreshButtonSettingsColumn = RefreshButtonSettingsColumn
ST._RefreshButtonSettingsMultiSelect = RefreshButtonSettingsMultiSelect
ST._RefreshPanelMultiSelect = RefreshPanelMultiSelect
ST._BuildCustomNameSection = BuildCustomNameSection
ST._BuildCustomKeybindSection = BuildCustomKeybindSection
ST._BuildOverridesTab = BuildOverridesTab
ST._BuildEntrySoundAlertsSection = BuildEntrySoundAlertsSection
ST._BuildTriggerConditionSettings = BuildTriggerConditionSettings
