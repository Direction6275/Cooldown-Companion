local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local ShowPopupAboveConfig = CS.ShowPopupAboveConfig

-- Helper: tint AceGUI Heading labels with player class color
local function ColorHeading(heading)
    local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if cc then
        heading.label:SetTextColor(cc.r, cc.g, cc.b)
    end
end

-- Helper: attach a reusable collapse/expand arrow button to an AceGUI Heading.
-- Stores the button on heading.frame._cdcCollapseBtn so it survives widget
-- recycling without creating duplicate textures or stale handlers.
local COLLAPSE_ARROW_ATLAS = "glues-characterSelect-icon-arrowDown-small"
local COLLAPSE_ROTATION_RIGHT = math.pi / 2   -- collapsed: arrow points right
local COLLAPSE_ROTATION_DOWN  = 0              -- expanded:  arrow points down

local function AttachCollapseButton(heading, isCollapsed, onClickFn)
    local frame = heading.frame
    local btn = frame._cdcCollapseBtn

    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(16, 16)
        btn._arrow = btn:CreateTexture(nil, "ARTWORK")
        btn._arrow:SetSize(12, 12)
        btn._arrow:SetPoint("CENTER")
        btn._arrow:SetAtlas(COLLAPSE_ARROW_ATLAS)
        frame._cdcCollapseBtn = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", heading.label, "RIGHT", 4, 0)
    btn:Show()
    btn._arrow:Show()

    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", btn, "RIGHT", 4, 0)

    btn._arrow:SetRotation(isCollapsed and COLLAPSE_ROTATION_RIGHT or COLLAPSE_ROTATION_DOWN)

    btn:SetScript("OnClick", onClickFn)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(isCollapsed and "Expand" or "Collapse")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    heading:SetCallback("OnRelease", function()
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end)

    return btn
end

-- Helper: add an inline advanced-toggle button on a parent widget (CheckBox or Heading).
-- Returns isExpanded (boolean) and the button frame reference.
local ADVANCED_TOGGLE_ATLAS = "QuestLog-icon-setting"

local function AddAdvancedToggle(parentWidget, settingKey, tabInfoBtns, isEnabled)
    local db = CooldownCompanion.db.profile.showAdvanced
    local isExpanded = db and db[settingKey] or false

    local frame = parentWidget.frame
    local btn = frame._cdcAdvancedBtn

    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(14, 14)
        btn._icon = btn:CreateTexture(nil, "ARTWORK")
        btn._icon:SetSize(13, 13)
        btn._icon:SetPoint("CENTER")
        btn._icon:SetAtlas(ADVANCED_TOGGLE_ATLAS, false)
        frame._cdcAdvancedBtn = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn._isAdvancedToggle = true

    -- Clean up on widget release (prevent leaking into recycled widgets).
    -- Also covers any collapse button on the same frame, since AddAdvancedToggle
    -- is always called after AttachCollapseButton and overwrites its OnRelease.
    parentWidget:SetCallback("OnRelease", function()
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
        local colBtn = frame._cdcCollapseBtn
        if colBtn then
            colBtn:ClearAllPoints()
            colBtn:Hide()
            colBtn:SetParent(nil)
        end
    end)

    -- Hide when parent setting is disabled
    if isEnabled == false then
        btn:Hide()
        btn._icon:Hide()
        table.insert(tabInfoBtns, btn)
        return false, btn
    end

    btn:Show()
    btn._icon:Show()

    -- Position for CheckBox widgets (has checkbg and text)
    if parentWidget.checkbg then
        btn:SetPoint("LEFT", parentWidget.checkbg, "RIGHT", parentWidget.text:GetStringWidth() + 6, 0)
    end
    -- For headings, caller positions manually (use returned btn reference)

    if isExpanded then
        btn._icon:SetVertexColor(1, 0.82, 0, 1)
    else
        btn._icon:SetVertexColor(0.5, 0.5, 0.5, 0.7)
    end

    btn:SetScript("OnClick", function()
        CooldownCompanion.db.profile.showAdvanced[settingKey] = not isExpanded
        CooldownCompanion:RefreshConfigPanel()
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(isExpanded and "Hide advanced settings" or "Show advanced settings")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    table.insert(tabInfoBtns, btn)

    return isExpanded, btn
end

local tabInfoButtons = CS.tabInfoButtons

local function CreatePromoteButton(headingWidget, sectionId, buttonData, groupStyle)
    local promoteBtn = CreateFrame("Button", nil, headingWidget.frame)
    promoteBtn:SetSize(16, 16)
    local anchorAfter = headingWidget.frame._cdcCollapseBtn or headingWidget.label
    promoteBtn:SetPoint("LEFT", anchorAfter, "RIGHT", 4, 0)
    headingWidget.right:ClearAllPoints()
    headingWidget.right:SetPoint("RIGHT", headingWidget.frame, "RIGHT", -3, 0)
    headingWidget.right:SetPoint("LEFT", promoteBtn, "RIGHT", 4, 0)

    local icon = promoteBtn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")

    -- Determine if promote is available
    local multiCount = 0
    if CS.selectedButtons then
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
    end
    local canPromote = CS.selectedButton ~= nil and multiCount < 2
        and buttonData ~= nil
        and not (buttonData.overrideSections and buttonData.overrideSections[sectionId])

    if canPromote then
        icon:SetAtlas("Crosshair_VehichleCursor_32")
        promoteBtn:Enable()
    else
        icon:SetAtlas("Crosshair_unableVehichleCursor_32")
        promoteBtn:Disable()
    end

    local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
    local sectionLabel = sectionDef and sectionDef.label or sectionId

    promoteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if canPromote then
            GameTooltip:AddLine("Override " .. sectionLabel .. " for this button")
        else
            GameTooltip:AddLine("Select a button to add an override", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    promoteBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    promoteBtn:SetScript("OnClick", function()
        if not canPromote then return end
        CooldownCompanion:PromoteSection(buttonData, groupStyle, sectionId)
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)

    table.insert(tabInfoButtons, promoteBtn)
    return promoteBtn
end

------------------------------------------------------------------------
-- REVERT BUTTON HELPER (for Overrides tab headings)
------------------------------------------------------------------------
local function CreateRevertButton(headingWidget, buttonData, sectionId)
    local revertBtn = CreateFrame("Button", nil, headingWidget.frame)
    revertBtn:SetSize(16, 16)
    local anchorAfter = headingWidget.frame._cdcCollapseBtn or headingWidget.label
    revertBtn:SetPoint("LEFT", anchorAfter, "RIGHT", 4, 0)
    headingWidget.right:ClearAllPoints()
    headingWidget.right:SetPoint("RIGHT", headingWidget.frame, "RIGHT", -3, 0)
    headingWidget.right:SetPoint("LEFT", revertBtn, "RIGHT", 4, 0)

    local icon = revertBtn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")
    icon:SetAtlas("common-search-clearbutton")

    revertBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
        GameTooltip:AddLine("Revert " .. (sectionDef and sectionDef.label or sectionId) .. " to group defaults")
        GameTooltip:Show()
    end)
    revertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    revertBtn:SetScript("OnClick", function()
        CooldownCompanion:RevertSection(buttonData, sectionId)
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)

    return revertBtn
end

local function CreateCheckboxPromoteButton(cbWidget, anchorAfterFrame, sectionId, group, groupStyle)
    local btnData = CS.selectedButton and group.buttons[CS.selectedButton]
    local promoteBtn = CreateFrame("Button", nil, cbWidget.frame)
    promoteBtn:SetSize(16, 16)

    -- Anchor: right of anchorAfterFrame if visible, else right of checkbox text
    if anchorAfterFrame and anchorAfterFrame:IsShown() then
        promoteBtn:SetPoint("LEFT", anchorAfterFrame, "RIGHT", 4, 0)
    else
        promoteBtn:SetPoint("LEFT", cbWidget.checkbg, "RIGHT", cbWidget.text:GetStringWidth() + 6, 0)
    end

    local icon = promoteBtn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")

    local multiCount = 0
    if CS.selectedButtons then
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
    end
    local canPromote = CS.selectedButton ~= nil and multiCount < 2
        and btnData ~= nil
        and not (btnData.overrideSections and btnData.overrideSections[sectionId])

    if canPromote then
        icon:SetAtlas("Crosshair_VehichleCursor_32")
        promoteBtn:Enable()
    else
        icon:SetAtlas("Crosshair_unableVehichleCursor_32")
        promoteBtn:Disable()
    end

    local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
    local sectionLabel = sectionDef and sectionDef.label or sectionId

    promoteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if canPromote then
            GameTooltip:AddLine("Override " .. sectionLabel .. " for this button")
        else
            GameTooltip:AddLine("Select a button to add an override", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    promoteBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    promoteBtn:SetScript("OnClick", function()
        if not canPromote then return end
        CooldownCompanion:PromoteSection(btnData, groupStyle, sectionId)
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)

    table.insert(tabInfoButtons, promoteBtn)
    return promoteBtn
end

------------------------------------------------------------------------
-- INFO BUTTON HELPER
------------------------------------------------------------------------
-- Creates a (?) info button anchored to a frame. Replaces the repeated
-- CreateFrame→SetSize→SetPoint→CreateTexture→SetAtlas→tooltip pattern.
--
-- tooltipLines: array of entries. Strings become title lines (AddLine).
--   Tables {text, r, g, b, wrap} become body lines with color/wrapping.
--
-- cleanup: determines lifecycle management.
--   If it's a table:  button is inserted and hideInfoButtons is applied.
--   If it's an AceGUI widget: button is cleaned up via OnRelease callback.
local function CreateInfoButton(parentFrame, anchorFrame, anchorPoint, anchorRelPoint, xOff, yOff, tooltipLines, cleanup)
    local btn = CreateFrame("Button", nil, parentFrame)
    btn:SetSize(16, 16)
    btn:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, xOff, yOff)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")
    icon:SetAtlas("QuestRepeatableTurnin")
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, line in ipairs(tooltipLines) do
            if type(line) == "table" then
                GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5])
            else
                GameTooltip:AddLine(line)
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if cleanup.SetCallback then
        -- AceGUI widget: wire OnRelease cleanup
        cleanup:SetCallback("OnRelease", function()
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
        end)
    else
        -- Array of buttons: insert and apply hideInfoButtons
        table.insert(cleanup, btn)
        if CooldownCompanion.db.profile.hideInfoButtons then
            btn:Hide()
        end
    end

    return btn
end

------------------------------------------------------------------------
-- COMPACT MODE CONTROLS
------------------------------------------------------------------------
-- Builds the compact mode section shared by icon mode (GroupTabs) and
-- bar mode (BarModeTabs): checkbox → advanced toggle → info button →
-- conditional max-visible-buttons slider + its info button.
local function BuildCompactModeControls(container, group, tabInfoButtons)
    local compactCb = AceGUI:Create("CheckBox")
    compactCb:SetLabel("Compact Mode")
    compactCb:SetValue(group.compactLayout or false)
    compactCb:SetFullWidth(true)
    compactCb:SetCallback("OnValueChanged", function(widget, event, val)
        group.compactLayout = val or false
        CooldownCompanion:PopulateGroupButtons(CS.selectedGroup)
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then frame._layoutDirty = true end
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(compactCb)

    local compactAdvExpanded, compactAdvBtn = AddAdvancedToggle(compactCb, "compactLayout", tabInfoButtons, group.compactLayout)

    -- (?) tooltip for compact mode — anchor shifts when advanced toggle is visible
    local compactAnchor, compactRelPoint, compactXOff
    if group.compactLayout then
        compactAnchor = compactAdvBtn
        compactRelPoint = "RIGHT"
        compactXOff = 4
    else
        compactAnchor = compactCb.checkbg
        compactRelPoint = "RIGHT"
        compactXOff = compactCb.text:GetStringWidth() + 6
    end
    CreateInfoButton(compactCb.frame, compactAnchor, "LEFT", compactRelPoint, compactXOff, 0, {
        "Compact Mode",
        {"When per-button visibility rules hide a button, shift remaining buttons to fill the gap and resize the group frame to fit visible buttons only.", 1, 1, 1, true},
    }, tabInfoButtons)

    if compactAdvExpanded and group.compactLayout then
        local totalButtons = #group.buttons
        local maxVisSlider = AceGUI:Create("Slider")
        maxVisSlider:SetLabel("Max Visible Buttons")
        maxVisSlider:SetSliderValues(1, math.max(totalButtons, 1), 1)
        maxVisSlider:SetValue(group.maxVisibleButtons == 0 and totalButtons or group.maxVisibleButtons)
        maxVisSlider:SetFullWidth(true)
        maxVisSlider:SetCallback("OnValueChanged", function(widget, event, val)
            val = math.floor(val + 0.5)
            if val >= totalButtons then
                group.maxVisibleButtons = 0
            else
                group.maxVisibleButtons = val
            end
            local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
            if frame then frame._layoutDirty = true end
        end)
        container:AddChild(maxVisSlider)

        CreateInfoButton(maxVisSlider.frame, maxVisSlider.label, "LEFT", "CENTER", maxVisSlider.label:GetStringWidth() / 2 + 4, 0, {
            "Max Visible Buttons",
            {"Limits how many buttons can appear at once. The first buttons (by group order) that pass visibility checks are shown; the rest are hidden.", 1, 1, 1, true},
        }, tabInfoButtons)
    end
end

local function BuildGroupSettingPresetControls(container, group, mode, tabInfoButtons)
    if not group then return end
    if mode ~= "bars" then
        mode = "icons"
    end

    local presetList, presetOrder = CooldownCompanion:GetGroupSettingPresetList(mode)
    if not CS.groupPresetSelection then
        CS.groupPresetSelection = { icons = nil, bars = nil }
    end

    local selectedPreset = CS.groupPresetSelection[mode]
    if selectedPreset and not presetList[selectedPreset] then
        selectedPreset = nil
        CS.groupPresetSelection[mode] = nil
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText(mode == "bars" and "Bar Group Preset" or "Icon Group Preset")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local presetModeLabel = mode == "bars" and "Bar Group Presets" or "Icon Group Presets"
    local modeSpecificLine = mode == "bars"
        and "Bar presets only work on bar groups."
        or "Icon presets only work on icon groups."
    local headingInfoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        presetModeLabel,
        {"Click Save to store this group's settings as a preset.", 1, 1, 1},
        " ",
        {"Presets only use Group Settings from this column.", 1, 1, 1},
        {"Presets do not include Columns 1, 2, or 3.", 1, 1, 1},
        {"Anchors are not saved or changed.", 1, 1, 1},
        " ",
        {"Apply resets preset settings first, then applies the preset.", 1, 1, 1},
        " ",
        {modeSpecificLine, 1, 1, 1},
    }, tabInfoButtons)

    -- Keep the info icon inside the heading line by shifting the right segment.
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", headingInfoBtn, "RIGHT", 4, 0)

    local presetDrop = AceGUI:Create("Dropdown")
    presetDrop:SetLabel("Preset")
    presetDrop:SetList(presetList, presetOrder)
    presetDrop:SetValue(selectedPreset)
    presetDrop:SetFullWidth(true)
    local applyBtn
    local deleteBtn
    presetDrop:SetCallback("OnValueChanged", function(widget, event, value)
        CS.groupPresetSelection[mode] = value
        local hasSelection = value ~= nil
        if applyBtn then
            applyBtn:SetDisabled(not hasSelection)
        end
        if deleteBtn then
            deleteBtn:SetDisabled(not hasSelection)
        end
    end)
    container:AddChild(presetDrop)

    if #presetOrder == 0 then
        local hintLabel = AceGUI:Create("Label")
        hintLabel:SetText("|cff888888No presets saved for this group mode yet.|r")
        hintLabel:SetFullWidth(true)
        container:AddChild(hintLabel)
    end

    local buttonRow = AceGUI:Create("SimpleGroup")
    buttonRow:SetFullWidth(true)
    buttonRow:SetLayout("Flow")

    applyBtn = AceGUI:Create("Button")
    applyBtn:SetText("Apply")
    applyBtn:SetRelativeWidth(0.32)
    applyBtn:SetCallback("OnClick", function()
        local presetName = CS.groupPresetSelection and CS.groupPresetSelection[mode]
        if not presetName then return end

        local ok, err = CooldownCompanion:ApplyGroupSettingPreset(mode, presetName, CS.selectedGroup)
        if not ok then
            if err == "missing_preset" and CS.groupPresetSelection then
                CS.groupPresetSelection[mode] = nil
            end
            CooldownCompanion:Print("Preset apply failed.")
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    buttonRow:AddChild(applyBtn)

    local saveBtn = AceGUI:Create("Button")
    saveBtn:SetText("Save")
    saveBtn:SetRelativeWidth(0.32)
    saveBtn:SetCallback("OnClick", function()
        if not ShowPopupAboveConfig then
            CooldownCompanion:Print("Preset save is unavailable.")
            return
        end
        ShowPopupAboveConfig("CDC_SAVE_GROUP_SETTINGS_PRESET", nil, {
            mode = mode,
            groupId = CS.selectedGroup,
            suggestedName = CS.groupPresetSelection and CS.groupPresetSelection[mode] or nil,
        })
    end)
    buttonRow:AddChild(saveBtn)

    deleteBtn = AceGUI:Create("Button")
    deleteBtn:SetText("Delete")
    deleteBtn:SetRelativeWidth(0.32)
    deleteBtn:SetCallback("OnClick", function()
        local presetName = CS.groupPresetSelection and CS.groupPresetSelection[mode]
        if not presetName then return end
        if not ShowPopupAboveConfig then
            CooldownCompanion:Print("Preset delete is unavailable.")
            return
        end
        ShowPopupAboveConfig("CDC_DELETE_GROUP_SETTINGS_PRESET", presetName, {
            mode = mode,
            presetName = presetName,
        })
    end)
    buttonRow:AddChild(deleteBtn)

    local hasSelection = selectedPreset ~= nil
    applyBtn:SetDisabled(not hasSelection)
    deleteBtn:SetDisabled(not hasSelection)

    -- Add the row after children are populated so List-layout parent containers
    -- compute scroll height correctly on first render.
    container:AddChild(buttonRow)
end

-- Shared bar texture option builder (used by CastBarPanels and BarModeTabs)
local LSM = LibStub("LibSharedMedia-3.0")
local function GetBarTextureOptions()
    local t = {}
    for _, name in ipairs(LSM:List("statusbar")) do
        t[name] = name
    end
    return t
end

-- Expose helpers for other ConfigSettings files
ST._ColorHeading = ColorHeading
ST._AttachCollapseButton = AttachCollapseButton
ST._AddAdvancedToggle = AddAdvancedToggle
ST._CreatePromoteButton = CreatePromoteButton
ST._CreateRevertButton = CreateRevertButton
ST._CreateCheckboxPromoteButton = CreateCheckboxPromoteButton
ST._CreateInfoButton = CreateInfoButton
ST._BuildCompactModeControls = BuildCompactModeControls
ST._BuildGroupSettingPresetControls = BuildGroupSettingPresetControls
ST._GetBarTextureOptions = GetBarTextureOptions
