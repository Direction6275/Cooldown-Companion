local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local ShowPopupAboveConfig = CS.ShowPopupAboveConfig
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent

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
local COLLAPSE_ARROW_ATLAS = "glues-characterselect-icon-arrowdown-small"
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

-- Helper: add an advanced-settings button on a parent widget (CheckBox or Heading).
-- The button opens the shared side editor when options.build is provided.
local ADVANCED_TOGGLE_ATLAS = "QuestLog-icon-setting"

local function GetAdvancedToggleTitle(parentWidget, options)
    if options and options.title and options.title ~= "" then
        return options.title
    end

    local labelText
    if parentWidget.text and parentWidget.text.GetText then
        labelText = parentWidget.text:GetText()
    elseif parentWidget.label and parentWidget.label.GetText then
        labelText = parentWidget.label:GetText()
    end

    if labelText and labelText ~= "" then
        return labelText .. " Advanced"
    end

    return "Advanced Settings"
end

local function BuildAdvancedDescriptor(parentWidget, settingKey, options)
    return {
        settingKey = settingKey,
        title = GetAdvancedToggleTitle(parentWidget, options),
        build = options and options.build,
        isAvailable = options and options.isAvailable,
        context = options and options.context,
        deferBuild = options and options.deferBuild,
    }
end

local function SetAdvancedToggleActive(btn, active)
    if btn and btn._icon then
        if active then
            btn._icon:SetVertexColor(1, 0.82, 0, 1)
        else
            btn._icon:SetVertexColor(0.72, 0.72, 0.72, 0.85)
        end
    end
end

local function SetActiveAdvancedSettingsToggleButton(btn)
    local current = CS.activeAdvancedSettingsToggleButton
    if current and current ~= btn then
        SetAdvancedToggleActive(current, false)
    end

    CS.activeAdvancedSettingsToggleButton = btn
    SetAdvancedToggleActive(btn, true)
end

local function AddAdvancedToggle(parentWidget, settingKey, tabInfoBtns, isEnabled, options)
    local useSidePanel = options and type(options.build) == "function" and CS.OpenAdvancedSettingsPanel
    local isActive = false
    if useSidePanel then
        if CS.ConsumeQueuedAdvancedSettingsPanelOpen then
            CS.ConsumeQueuedAdvancedSettingsPanelOpen(BuildAdvancedDescriptor(parentWidget, settingKey, options))
        end
        isActive = CS.IsAdvancedSettingsPanelOpen and CS.IsAdvancedSettingsPanelOpen(settingKey, options.context) or false
        if isActive and CS.RebindAdvancedSettingsPanel then
            CS.RebindAdvancedSettingsPanel(BuildAdvancedDescriptor(parentWidget, settingKey, options))
        end
    end

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
    btn._advancedSettingKey = settingKey

    -- Clean up on widget release (prevent leaking into recycled widgets).
    -- Also covers any collapse button on the same frame, since AddAdvancedToggle
    -- is always called after AttachCollapseButton and overwrites its OnRelease.
    parentWidget:SetCallback("OnRelease", function()
        local activeSidePanelToggleReleased = useSidePanel and CS.activeAdvancedSettingsToggleButton == btn
        if activeSidePanelToggleReleased
            and not CS.configRefreshInProgress
            and not CS.advancedSettingsPanelRefreshing
            and CS.CloseAdvancedSettingsPanel
        then
            CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
        end

        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
        SetAdvancedToggleActive(btn, false)
        if CS.activeAdvancedSettingsToggleButton == btn then
            CS.activeAdvancedSettingsToggleButton = nil
        end
        local colBtn = frame._cdcCollapseBtn
        if colBtn then
            colBtn:ClearAllPoints()
            colBtn:Hide()
            colBtn:SetParent(nil)
        end
        local previewBtn = frame._cdcPreviewBtn
        if previewBtn then
            previewBtn:ClearAllPoints()
            previewBtn:Hide()
            previewBtn:SetParent(nil)
            if CS.activePreviewBadgeButton == previewBtn then
                CS.activePreviewBadgeButton = nil
            end
        end
    end)

    -- Hide when parent setting is disabled
    if isEnabled == false then
        if useSidePanel and isActive and CS.CloseAdvancedSettingsPanel then
            CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
        end
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

    SetAdvancedToggleActive(btn, isActive)
    if isActive then
        SetActiveAdvancedSettingsToggleButton(btn)
    elseif CS.activeAdvancedSettingsToggleButton == btn then
        CS.activeAdvancedSettingsToggleButton = nil
    end

    btn:SetScript("OnClick", function()
        if useSidePanel then
            if CS.IsAdvancedSettingsPanelOpen and CS.IsAdvancedSettingsPanelOpen(settingKey, options.context) then
                CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
            else
                local descriptor = BuildAdvancedDescriptor(parentWidget, settingKey, options)
                if CS.OpenAdvancedSettingsPanel(descriptor) and btn:GetParent() == frame then
                    SetActiveAdvancedSettingsToggleButton(btn)
                end
            end
        else
            CooldownCompanion:RefreshConfigPanel()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local active = CS.IsAdvancedSettingsPanelOpen and CS.IsAdvancedSettingsPanelOpen(settingKey, options and options.context)
        GameTooltip:AddLine(active and "Close advanced settings" or "Open advanced settings")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    table.insert(tabInfoBtns, btn)

    return isActive, btn
end

local tabInfoButtons = CS.tabInfoButtons
CS.SetActiveAdvancedSettingsToggleButton = SetActiveAdvancedSettingsToggleButton

local function GroupSupportsPerButtonOverrides(group)
    return group and (group.displayMode or "icons") ~= "textures"
end

local function CanButtonUseOverrideSection(buttonData, sectionId)
    if ST.CanButtonUseOverrideSection then
        return ST.CanButtonUseOverrideSection(buttonData, sectionId)
    end
    return not (buttonData and buttonData.type == "equipmentSlot"
        and ST.EQUIPMENT_SLOT_DENIED_OVERRIDE_SECTIONS
        and ST.EQUIPMENT_SLOT_DENIED_OVERRIDE_SECTIONS[sectionId])
end

local function CreatePromoteButton(headingWidget, sectionId, buttonData, groupStyle)
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not GroupSupportsPerButtonOverrides(group) then
        return nil
    end

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
    local sectionAllowed = CanButtonUseOverrideSection(buttonData, sectionId)
    local canPromote = CS.selectedButton ~= nil and multiCount < 2
        and buttonData ~= nil
        and sectionAllowed
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
        elseif buttonData and not sectionAllowed then
            GameTooltip:AddLine("This override is not available for equipment slots", 0.5, 0.5, 0.5)
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
        CS.buttonSettingsTab = "overrides"
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
    if not GroupSupportsPerButtonOverrides(group) then
        return nil
    end

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
    local sectionAllowed = CanButtonUseOverrideSection(btnData, sectionId)
    local canPromote = CS.selectedButton ~= nil and multiCount < 2
        and btnData ~= nil
        and sectionAllowed
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
        elseif btnData and not sectionAllowed then
            GameTooltip:AddLine("This override is not available for equipment slots", 0.5, 0.5, 0.5)
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
        CS.buttonSettingsTab = "overrides"
        CooldownCompanion:RefreshConfigPanel()
    end)

    table.insert(tabInfoButtons, promoteBtn)
    return promoteBtn
end

local function CreateColorPickerPromoteButton(colorPickerWidget, sectionId, group, groupStyle)
    if not GroupSupportsPerButtonOverrides(group) then
        return nil
    end

    local btnData = CS.selectedButton and group.buttons[CS.selectedButton]
    local frame = colorPickerWidget.frame
    local promoteBtn = frame._cdcColorPromoteBtn

    if not promoteBtn then
        promoteBtn = CreateFrame("Button", nil, frame)
        promoteBtn:SetSize(16, 16)
        promoteBtn.icon = promoteBtn:CreateTexture(nil, "OVERLAY")
        promoteBtn.icon:SetSize(12, 12)
        promoteBtn.icon:SetPoint("CENTER")
        frame._cdcColorPromoteBtn = promoteBtn
    end

    promoteBtn:SetParent(frame)
    promoteBtn:ClearAllPoints()
    promoteBtn:SetPoint("LEFT", colorPickerWidget.colorSwatch, "RIGHT", colorPickerWidget.text:GetStringWidth() + 8, 0)
    promoteBtn:Show()
    promoteBtn.icon:Show()

    local multiCount = 0
    if CS.selectedButtons then
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
    end
    local sectionAllowed = CanButtonUseOverrideSection(btnData, sectionId)
    local canPromote = CS.selectedButton ~= nil and multiCount < 2
        and btnData ~= nil
        and sectionAllowed
        and not (btnData.overrideSections and btnData.overrideSections[sectionId])

    if canPromote then
        promoteBtn.icon:SetAtlas("Crosshair_VehichleCursor_32")
        promoteBtn:Enable()
    else
        promoteBtn.icon:SetAtlas("Crosshair_unableVehichleCursor_32")
        promoteBtn:Disable()
    end

    local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
    local sectionLabel = sectionDef and sectionDef.label or sectionId

    promoteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if canPromote then
            GameTooltip:AddLine("Override " .. sectionLabel .. " for this button")
        elseif btnData and not sectionAllowed then
            GameTooltip:AddLine("This override is not available for equipment slots", 0.5, 0.5, 0.5)
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
        CS.buttonSettingsTab = "overrides"
        CooldownCompanion:RefreshConfigPanel()
    end)

    colorPickerWidget:SetCallback("OnRelease", function()
        promoteBtn:ClearAllPoints()
        promoteBtn:Hide()
        promoteBtn:SetParent(nil)
    end)

    table.insert(tabInfoButtons, promoteBtn)
    return promoteBtn
end

------------------------------------------------------------------------
-- INFO BUTTON HELPER
------------------------------------------------------------------------
local tooltipMeasureFrame = CreateFrame("Frame", nil, UIParent)
tooltipMeasureFrame:Hide()

local tooltipMeasureHeader = tooltipMeasureFrame:CreateFontString(nil, "ARTWORK", "GameTooltipHeaderText")
local tooltipMeasureBody = tooltipMeasureFrame:CreateFontString(nil, "ARTWORK", "GameTooltipText")

local function ResetInfoTooltipWidth()
    GameTooltip:SetMinimumWidth(0)
end

local function MeasureInfoTooltipLineWidth(text, isHeader)
    local fs = isHeader and tooltipMeasureHeader or tooltipMeasureBody
    fs:SetText(text or "")
    return fs:GetUnboundedStringWidth()
end

-- Creates a (?) info button anchored to a frame. Replaces the repeated
-- CreateFrame→SetSize→SetPoint→CreateTexture→SetAtlas→tooltip pattern.
--
-- tooltipLines: array of entries. Strings become title lines (AddLine).
--   Tables {text, r, g, b, wrap} become body lines with color/wrapping.
--
-- cleanup: determines lifecycle management.
--   If it's a table:  button is inserted for lifecycle cleanup.
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
        ResetInfoTooltipWidth()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, line in ipairs(tooltipLines) do
            if type(line) == "table" then
                GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5])
            else
                GameTooltip:AddLine(line)
            end
        end
        GameTooltip:Show()
        -- Expand tooltip width to fit the widest non-wrapping line.
        -- Wrapping lines don't drive width directly but enforce a
        -- comfortable minimum so wrapped text isn't cramped.
        local pad = 20
        local wrapFloor = 250
        local maxW = 0
        local hasWrap = false
        for i, entry in ipairs(tooltipLines) do
            local isWrapping = type(entry) == "table" and entry[5]
            if isWrapping then
                hasWrap = true
            else
                local text = type(entry) == "table" and entry[1] or entry
                local w = MeasureInfoTooltipLineWidth(text, i == 1)
                if w > maxW then maxW = w end
            end
        end
        if hasWrap and maxW < wrapFloor then maxW = wrapFloor end
        if maxW > 0 then
            GameTooltip:SetMinimumWidth(maxW + pad)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        ResetInfoTooltipWidth()
        GameTooltip:Hide()
    end)

    if cleanup and cleanup.SetCallback then
        -- AceGUI widget: chain OnRelease cleanup so existing handlers (e.g.
        -- collapse/advanced button detach) are preserved.
        local prevOnRelease = cleanup.events and cleanup.events["OnRelease"]
        cleanup:SetCallback("OnRelease", function()
            if prevOnRelease then
                prevOnRelease(cleanup, "OnRelease")
            end
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
        end)
    else
        -- Array of buttons: insert for lifecycle cleanup.
        if CS.advancedSettingsPanelRefreshing then
            CS.advancedSettingsInfoButtons = CS.advancedSettingsInfoButtons or {}
            cleanup = CS.advancedSettingsInfoButtons
        end
        if type(cleanup) ~= "table" then
            return btn
        end
        table.insert(cleanup, btn)
    end

    return btn
end

local function ResetIndependentAnchorToParent(anchor)
    anchor.point = "CENTER"
    anchor.relativeTo = nil
    anchor.relativePoint = "CENTER"
    anchor.x = 0
    anchor.y = 0
end

local function ValidateIndependentAnchorTarget(frameName)
    local options = { domain = "external" }
    local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(frameName, options)
    if not ok then
        CooldownCompanion:PrintInvalidAnchorTargetReason(frameName, options)
        return false
    end
    return true
end

local function BuildIndependentAnchorTargetRow(container, anchor, applyFn)
    local anchorRow = AceGUI:Create("SimpleGroup")
    anchorRow:SetFullWidth(true)
    anchorRow:SetLayout("Flow")

    local anchorBox = AceGUI:Create("EditBox")
    if anchorBox.editbox.Instructions then
        anchorBox.editbox.Instructions:Hide()
    end
    anchorBox:SetLabel("Anchor to Frame")
    local currentRelativeTo = anchor.relativeTo
    if not currentRelativeTo or currentRelativeTo == "UIParent" then
        currentRelativeTo = ""
    end
    anchorBox:SetText(currentRelativeTo)
    anchorBox:SetRelativeWidth(0.68)
    anchorBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if text == "" then
            local wasAnchored = anchor.relativeTo and anchor.relativeTo ~= "UIParent"
            if wasAnchored then
                ResetIndependentAnchorToParent(anchor)
            else
                anchor.relativeTo = nil
            end
        else
            local targetFrame = _G[text]
            if not targetFrame then
                CooldownCompanion:Print("Frame '" .. text .. "' not found.")
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            if not ValidateIndependentAnchorTarget(text) then
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            anchor.relativeTo = text
        end
        applyFn()
        CooldownCompanion:RefreshConfigPanel()
    end)
    anchorRow:AddChild(anchorBox)

    local pickBtn = AceGUI:Create("Button")
    pickBtn:SetText("Pick")
    pickBtn:SetRelativeWidth(0.24)
    pickBtn:SetCallback("OnClick", function()
        CS.StartPickFrame(function(name)
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if name then
                if not ValidateIndependentAnchorTarget(name) then
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                anchor.point = "TOPLEFT"
                anchor.relativeTo = name
                anchor.relativePoint = "BOTTOMLEFT"
                anchor.x = 0
                anchor.y = -5
                applyFn()
            end
            CooldownCompanion:RefreshConfigPanel()
        end, nil, { domain = "external" })
    end)
    anchorRow:AddChild(pickBtn)
    container:AddChild(anchorRow)

    pickBtn.frame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local p, rel, rp, xOfs, yOfs = self:GetPoint(1)
        if yOfs then
            self:SetPoint(p, rel, rp, xOfs, yOfs - 2)
        end
    end)
end

------------------------------------------------------------------------
-- COMPACT MODE CONTROLS
------------------------------------------------------------------------
local function NormalizeCompactGrowthDirection(growthDirection)
    if growthDirection == "start" or growthDirection == "left" or growthDirection == "top" then
        return "start"
    end
    if growthDirection == "end" or growthDirection == "right" or growthDirection == "bottom" then
        return "end"
    end
    return "center"
end

local function GetCompactGrowthDirectionLabels(group)
    local style = group.style or {}
    local isBarMode = group.displayMode == "bars"
    local orientation = style.orientation or (isBarMode and "vertical" or "horizontal")
    local growthOrigin = style.growthOrigin or "TOPLEFT"
    if orientation == "vertical" then
        local startIsTop = (growthOrigin == "TOPLEFT" or growthOrigin == "TOPRIGHT")
        return {
            start = startIsTop and "Top" or "Bottom",
            center = "Center",
            ["end"] = startIsTop and "Bottom" or "Top",
        }
    end
    local startIsLeft = (growthOrigin == "TOPLEFT" or growthOrigin == "BOTTOMLEFT")
    return {
        start = startIsLeft and "Left" or "Right",
        center = "Center",
        ["end"] = startIsLeft and "Right" or "Left",
    }
end

-- Builds the compact mode section shared by icon mode (GroupTabs) and
-- bar mode (BarModeTabs): checkbox → advanced toggle → info button →
-- conditional growth-direction + max-visible-buttons controls.
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

    local function BuildCompactAdvanced(panel)
        local growthDirectionDrop = AceGUI:Create("Dropdown")
        growthDirectionDrop:SetLabel("Growth Direction")
        growthDirectionDrop:SetList(GetCompactGrowthDirectionLabels(group), {"start", "center", "end"})
        growthDirectionDrop:SetValue(NormalizeCompactGrowthDirection(group.compactGrowthDirection))
        growthDirectionDrop:SetFullWidth(true)
        growthDirectionDrop:SetCallback("OnValueChanged", function(widget, event, val)
            group.compactGrowthDirection = NormalizeCompactGrowthDirection(val)
            local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
            if frame then
                frame._layoutDirty = true
                if frame:IsShown() then
                    CooldownCompanion:UpdateGroupLayout(CS.selectedGroup)
                end
            end
        end)
        panel:AddChild(growthDirectionDrop)

        CreateInfoButton(growthDirectionDrop.frame, growthDirectionDrop.label, "LEFT", "CENTER", growthDirectionDrop.label:GetStringWidth() / 2 + 4, 0, {
            "Growth Direction",
            {"Choose which edge acts as the compact anchor icon/bar as visibility changes. Horizontal uses Left/Center/Right, vertical uses Top/Center/Bottom.", 1, 1, 1, true},
        }, tabInfoButtons)

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
        panel:AddChild(maxVisSlider)

        CreateInfoButton(maxVisSlider.frame, maxVisSlider.label, "LEFT", "CENTER", maxVisSlider.label:GetStringWidth() / 2 + 4, 0, {
            "Max Visible Buttons",
            {"Limits how many buttons can appear at once. The first buttons (by group order) that pass visibility checks are shown; the rest are hidden.", 1, 1, 1, true},
        }, tabInfoButtons)
    end

    local compactAdvExpanded, compactAdvBtn = AddAdvancedToggle(compactCb, "compactLayout", tabInfoButtons, group.compactLayout, {
        title = "Compact Mode Advanced",
        build = BuildCompactAdvanced,
    })

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
    heading:SetText(mode == "bars" and "Bar Panel Preset" or "Icon Panel Preset")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local presetModeLabel = mode == "bars" and "Bar Panel Presets" or "Icon Panel Presets"
    local modeSpecificLine = mode == "bars"
        and "Bar presets only work on bar panels."
        or "Icon presets only work on icon panels."
    local headingInfoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        presetModeLabel,
        {"Click Save to store this panel's settings as a preset.", 1, 1, 1},
        " ",
        {"Presets save appearance, indicator, and text settings.", 1, 1, 1},
        {"Load Conditions (including Spec/Hero filters) are not saved or changed.", 1, 1, 1},
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
        ST._ConfigureWrappedHelperLabel(hintLabel)
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

local charCopyButtons = {}

local CHARACTER_COPY_TOOLTIP_DETAILS = {
    frameAnchoring = {
        "Copies: enable state, unit-frame addon/custom frame choices, player/target anchors, mirroring, and alpha inheritance.",
        "Does not copy: Resource Bars, Cast Bar, panels, or panel contents.",
    },
    castBar = {
        "Copies: enable state, anchor/position mode, styling, icon, text, and cast effects.",
        "Does not copy: Resource Bars, Unit Frames, panels, or panel contents.",
    },
    resourceBars = {
        "Copies broad Resource Bar defaults from another character without replacing this character's spec-specific setup.",
        "",
        "What is copied:",
        "- Enable state and panel anchor target",
        "- Shared appearance defaults, like texture, text, and default colors",
        "- Resource options that apply to this class",
        "",
        "What is not copied:",
        "- The current spec's Layout tab or bar order",
        "- Custom Bars",
        "- Aura overlays and per-spec resource overrides",
    },
}

local function CreateCharacterCopyButton(enableCb, systemKey, label, onCopied)
    local copyValues, copyOrder = CooldownCompanion:GetCharacterScopedSettingsCopyOptions(systemKey)
    if #copyOrder == 0 then return end

    -- Pool one button per systemKey to avoid frame leaks across panel rebuilds
    local btn = charCopyButtons[systemKey]
    if not btn then
        btn = CreateFrame("Button", nil, enableCb.frame)
        btn:SetSize(16, 16)

        local icon = btn:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetAtlas("BattleBar-SwapPetIcon", false)

        charCopyButtons[systemKey] = btn
    else
        btn:SetParent(enableCb.frame)
    end

    btn:ClearAllPoints()
    btn:SetPoint("LEFT", enableCb.checkbg, "RIGHT", enableCb.text:GetStringWidth() + 4, 0)
    btn:Show()

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Copy " .. label .. " Settings")
        local tooltipDetails = CHARACTER_COPY_TOOLTIP_DETAILS[systemKey]
        if tooltipDetails then
            for _, line in ipairs(tooltipDetails) do
                if line == "" then
                    GameTooltip:AddLine(" ")
                elseif line == "What is copied:" or line == "What is not copied:" then
                    GameTooltip:AddLine(line, 1, 0.82, 0, true)
                else
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            end
        else
            GameTooltip:AddLine("Copy settings from another character on this profile.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function()
        if not CS.charCopyMenu then
            CS.charCopyMenu = CreateFrame("Frame", "CDCCharCopyMenu", UIParent, "UIDropDownMenuTemplate")
        end
        local vals, order = CooldownCompanion:GetCharacterScopedSettingsCopyOptions(systemKey)
        if #order == 0 then return end

        UIDropDownMenu_Initialize(CS.charCopyMenu, function(self, level)
            for _, charKey in ipairs(order) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = vals[charKey]
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    if not ShowPopupAboveConfig then
                        CooldownCompanion:Print("Copy confirmation is unavailable.")
                        return
                    end
                    ShowPopupAboveConfig("CDC_CONFIRM_CHARACTER_SCOPED_COPY", label .. " settings from " .. (vals[charKey] or charKey) .. " to this character", {
                        systemKey = systemKey,
                        systemLabel = label,
                        sourceCharKey = charKey,
                        onCopied = onCopied,
                    })
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        CS.charCopyMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, CS.charCopyMenu, "cursor", 0, 0)
    end)

    -- Clean up on widget release (raw frame persists across AceGUI recycling)
    local prevOnRelease = enableCb.events and enableCb.events["OnRelease"]
    enableCb:SetCallback("OnRelease", function()
        if prevOnRelease then
            prevOnRelease(enableCb, "OnRelease")
        end
        btn:ClearAllPoints()
        btn:Hide()
    end)

    return btn
end

-- Helper: wire up OnValueChanged and OnValueConfirmed for a ColorPicker widget.
-- Stores {r,g,b,a} into tbl[key]. onConfirmedFn fires on release; onChangeFn
-- (optional) fires during drag for live preview.
local function SetupColorCallbacks(widget, tbl, key, onConfirmedFn, onChangeFn)
    widget:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
        tbl[key] = {r, g, b, a}
        if onChangeFn then onChangeFn() end
    end)
    widget:SetCallback("OnValueConfirmed", function(_, _, r, g, b, a)
        tbl[key] = {r, g, b, a}
        if onConfirmedFn then onConfirmedFn() end
    end)
end

------------------------------------------------------------------------
-- WIDGET FACTORIES
-- Composable builders that replace repeated AceGUI boilerplate.
-- Each creates, configures, and adds to container; single-widget factories return the widget.
------------------------------------------------------------------------

-- Create a ColorPicker, configure it, wire callbacks, add to container.
-- onConfirmFn fires on mouse release; onChangeFn (optional) fires during drag.
local function AddColorPicker(container, tbl, key, label, default, hasAlpha, onConfirmFn, onChangeFn)
    local picker = AceGUI:Create("ColorPicker")
    picker:SetLabel(label)
    picker:SetHasAlpha(hasAlpha)
    local c = tbl[key] or default
    picker:SetColor(c[1], c[2], c[3], c[4])
    picker:SetFullWidth(true)
    SetupColorCallbacks(picker, tbl, key, onConfirmFn, onChangeFn)
    container:AddChild(picker)
    return picker
end

-- Create an anchor-point Dropdown using the pre-built list from State.lua.
-- Optional label param overrides the default "Anchor" label.
local function AddAnchorDropdown(container, tbl, key, default, refreshFn, label)
    local drop = AceGUI:Create("Dropdown")
    drop:SetLabel(label or "Anchor")
    drop:SetList(CS.anchorDropdownList, CS.anchorPoints)
    drop:SetValue(tbl[key] or default)
    drop:SetFullWidth(true)
    drop:SetCallback("OnValueChanged", function(widget, event, val)
        tbl[key] = val
        refreshFn()
    end)
    container:AddChild(drop)
    return drop
end

-- Create Font Size slider + Font dropdown + Font Outline dropdown.
-- prefix: key prefix (e.g. "cooldown" reads cooldownFont, cooldownFontSize, cooldownFontOutline).
-- defaults: {size, sizeMin, sizeMax, sizeStep, font, outline} — all optional with sane fallbacks.
local function AddFontControls(container, tbl, prefix, defaults, refreshFn)
    local fontKey = prefix .. "Font"
    local sizeKey = prefix .. "FontSize"
    local outlineKey = prefix .. "FontOutline"

    local fontSizeSlider = AceGUI:Create("Slider")
    fontSizeSlider:SetLabel("Font Size")
    fontSizeSlider:SetSliderValues(defaults.sizeMin or 8, defaults.sizeMax or 32, defaults.sizeStep or 1)
    fontSizeSlider:SetValue(tbl[sizeKey] or defaults.size or 12)
    fontSizeSlider:SetFullWidth(true)
    fontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
        tbl[sizeKey] = val
        refreshFn()
    end)
    container:AddChild(fontSizeSlider)

    local fontDrop = AceGUI:Create("Dropdown")
    fontDrop:SetLabel("Font")
    CS.SetupFontDropdown(fontDrop)
    fontDrop:SetValue(tbl[fontKey] or defaults.font or "Friz Quadrata TT")
    fontDrop:SetFullWidth(true)
    CS.SetFontDropdownCallback(fontDrop, function(widget, event, val)
        tbl[fontKey] = val
        refreshFn()
    end)
    container:AddChild(fontDrop)

    local outlineDrop = AceGUI:Create("Dropdown")
    outlineDrop:SetLabel("Font Outline")
    CS.SetupFontOutlineDropdown(outlineDrop)
    outlineDrop:SetValue(tbl[outlineKey] or defaults.outline or "OUTLINE")
    outlineDrop:SetFullWidth(true)
    CS.SetFontOutlineDropdownCallback(outlineDrop, function(widget, event, val)
        tbl[outlineKey] = val
        refreshFn()
    end)
    container:AddChild(outlineDrop)
end

-- Create X Offset + Y Offset slider pair.
-- defaults: {x, y, range (default 20), step (default 0.1)}
local function AddOffsetSliders(container, tbl, xKey, yKey, defaults, refreshFn)
    local range = defaults.range or 20
    local step = defaults.step or 0.1

    local xSlider = AceGUI:Create("Slider")
    xSlider:SetLabel("X Offset")
    xSlider:SetSliderValues(-range, range, step)
    xSlider:SetValue(tbl[xKey] or defaults.x or 0)
    xSlider:SetFullWidth(true)
    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
        tbl[xKey] = val
        refreshFn()
    end)
    container:AddChild(xSlider)

    local ySlider = AceGUI:Create("Slider")
    ySlider:SetLabel("Y Offset")
    ySlider:SetSliderValues(-range, range, step)
    ySlider:SetValue(tbl[yKey] or defaults.y or 0)
    ySlider:SetFullWidth(true)
    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
        tbl[yKey] = val
        refreshFn()
    end)
    container:AddChild(ySlider)
end

local BORDER_THICKNESS_MODE_TOOLTIPS = {
    [ST.BORDER_RENDER_MODE_CUSTOM] = {
        "Custom Thickness",
        "Uses the Border Size slider, including fractional values.",
    },
    [ST.BORDER_RENDER_MODE_CRISP] = {
        "One-pixel",
        "Uses a stable one-pixel border for your current UI scale.",
    },
}

local function AddDropdownItemTooltips(dropdown, tooltipByValue)
    if not (dropdown and dropdown.pullout and tooltipByValue) then return end

    for _, item in dropdown.pullout:IterateItems() do
        local value = item.userdata and item.userdata.value
        local tooltip = tooltipByValue[value]
        if tooltip then
            item:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                GameTooltip:AddLine(tooltip[1], 1, 0.82, 0, true)
                GameTooltip:AddLine(tooltip[2], 1, 1, 1, true)
                GameTooltip:Show()
            end)
            item:SetCallback("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
    end
end

local function AddBorderRenderModeDropdown(container, tbl, key, refreshFn, disabled)
    key = key or "borderRenderMode"
    local controlsDisabled = disabled == true or ST.IsBorderThicknessLocked()

    local modeDrop = AceGUI:Create("Dropdown")
    modeDrop:SetLabel("Border Thickness")
    modeDrop:SetList({
        [ST.BORDER_RENDER_MODE_CUSTOM] = "Custom Thickness",
        [ST.BORDER_RENDER_MODE_CRISP] = "One-pixel",
    }, { ST.BORDER_RENDER_MODE_CUSTOM, ST.BORDER_RENDER_MODE_CRISP })
    AddDropdownItemTooltips(modeDrop, BORDER_THICKNESS_MODE_TOOLTIPS)
    modeDrop:SetValue(ST.GetBorderRenderMode(tbl, key))
    if modeDrop.SetDisabled then
        modeDrop:SetDisabled(controlsDisabled)
    end
    modeDrop:SetCallback("OnClosed", function()
        GameTooltip:Hide()
    end)
    modeDrop:SetFullWidth(true)
    modeDrop:SetCallback("OnValueChanged", function(widget, event, val)
        if controlsDisabled then return end
        tbl[key] = ST.GetBorderRenderMode(val)
        if refreshFn then
            refreshFn()
        end
    end)
    container:AddChild(modeDrop)

    return ST.GetBorderRenderMode(tbl, key)
end

-- Expose helpers for other ConfigSettings files
ST._ColorHeading = ColorHeading
ST._AttachCollapseButton = AttachCollapseButton
ST._AddAdvancedToggle = AddAdvancedToggle
ST._CreatePromoteButton = CreatePromoteButton
ST._CreateRevertButton = CreateRevertButton
ST._CreateCheckboxPromoteButton = CreateCheckboxPromoteButton
ST._CreateColorPickerPromoteButton = CreateColorPickerPromoteButton
ST._CreateInfoButton = CreateInfoButton
ST._BuildCompactModeControls = BuildCompactModeControls
ST._BuildGroupSettingPresetControls = BuildGroupSettingPresetControls
ST._CreateCharacterCopyButton = CreateCharacterCopyButton
ST._AddColorPicker = AddColorPicker
ST._AddAnchorDropdown = AddAnchorDropdown

-- Allow decimal input from editbox while keeping slider/wheel at 1px steps.
-- Reusable across any AceGUI Slider widget that needs sub-integer precision.
local function HookSliderEditBox(sliderWidget)
    local editbox = sliderWidget.editbox
    local origHandler = editbox:GetScript("OnEnterPressed")
    editbox:SetScript("OnEnterPressed", function(eb)
        local widget = eb.obj
        local value = tonumber(eb:GetText())
        if value then
            value = math.floor(value * 10 + 0.5) / 10
            value = math.max(widget.min, math.min(widget.max, value))
            PlaySound(856)
            widget:SetValue(value)
            widget:Fire("OnValueChanged", value)
            widget:Fire("OnMouseUp", value)
        end
    end)

    -- Restore original AceGUI handler on release so recycled sliders aren't permanently modified
    local prevOnRelease = sliderWidget.events and sliderWidget.events["OnRelease"]
    sliderWidget:SetCallback("OnRelease", function()
        if prevOnRelease then
            prevOnRelease(sliderWidget, "OnRelease")
        end
        editbox:SetScript("OnEnterPressed", origHandler)
    end)
end
ST._HookSliderEditBox = HookSliderEditBox

-- Shared alpha UI builder for groups, resource bars, and other shared alpha consumers.
-- container: AceGUI parent widget
-- config: table with alpha fields (baselineAlpha, forceAlpha*, forceHide*, fade*, etc.)
-- refreshFn: function called after value changes (typically RefreshConfigPanel)
-- collapseKey: string key for CS.collapsedSections
-- opts (optional): { onBaselineChanged = fn(val), isGlobal = bool, disabled = bool, disabledText = string, infoButtons = table }
local function BuildAlphaControls(container, config, refreshFn, collapseKey, opts)
    opts = opts or {}
    local tabInfoBtns = opts.infoButtons or CS.tabInfoButtons
    local controlsDisabled = opts.disabled == true

    local function ApplyAlphaSettingChange(refreshPanel)
        if CooldownCompanion.RefreshAlphaUpdateDriver then
            CooldownCompanion:RefreshAlphaUpdateDriver()
        end
        if refreshPanel and refreshFn then
            refreshFn()
        end
    end

    local alphaHeading = AceGUI:Create("Heading")
    alphaHeading:SetText("Alpha")
    ColorHeading(alphaHeading)
    alphaHeading:SetFullWidth(true)
    container:AddChild(alphaHeading)

    local alphaCollapsed = CS.collapsedSections[collapseKey]
    AttachCollapseButton(alphaHeading, alphaCollapsed, function()
        CS.collapsedSections[collapseKey] = not CS.collapsedSections[collapseKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if alphaCollapsed then return end

    if controlsDisabled and opts.disabledText and opts.disabledText ~= "" then
        local disabledLabel = AceGUI:Create("Label")
        if ST._ConfigureWrappedHelperLabel then
            ST._ConfigureWrappedHelperLabel(disabledLabel)
        end
        disabledLabel:SetText("|cff888888" .. opts.disabledText .. "|r")
        disabledLabel:SetFullWidth(true)
        container:AddChild(disabledLabel)
    end

    local baseAlphaSlider = AceGUI:Create("Slider")
    baseAlphaSlider:SetLabel("Baseline Alpha")
    baseAlphaSlider:SetSliderValues(0, 1, 0.1)
    baseAlphaSlider:SetValue(config.baselineAlpha or 1)
    baseAlphaSlider:SetFullWidth(true)
    baseAlphaSlider:SetDisabled(controlsDisabled)
    baseAlphaSlider:SetCallback("OnValueChanged", function(widget, event, val)
        if controlsDisabled then return end
        config.baselineAlpha = val
        if opts.onBaselineChanged then
            opts.onBaselineChanged(val)
        end
        ApplyAlphaSettingChange(false)
    end)
    container:AddChild(baseAlphaSlider)

    CreateInfoButton(baseAlphaSlider.frame, baseAlphaSlider.label, "LEFT", "CENTER", baseAlphaSlider.label:GetStringWidth() / 2 + 4, 0, {
        "Alpha",
        {"Controls transparency. Alpha = 1 is fully visible. Alpha = 0 means completely hidden.\n\nThe first four options (In Combat, Out of Combat, Regular Mount, Skyriding) are 3-way toggles — click to cycle through Disabled, |cff00ff00Fully Visible|r, and |cffff0000Fully Hidden|r.\n\n|cff00ff00Fully Visible|r overrides alpha to 1 when the condition is met.\n\n|cffff0000Fully Hidden|r overrides alpha to 0 when the condition is met.\n\nIf both apply simultaneously, |cff00ff00Fully Visible|r takes priority.", 1, 1, 1, true},
    }, tabInfoBtns)

    do
        local function GetTriState(visibleKey, hiddenKey)
            if config[hiddenKey] then return nil end
            if config[visibleKey] then return true end
            return false
        end

        local function TriStateLabel(base, value)
            if value == true then
                return base .. " - |cff00ff00Fully Visible|r"
            elseif value == nil then
                return base .. " - |cffff0000Fully Hidden|r"
            end
            return base
        end

        local function CreateTriStateToggle(label, visibleKey, hiddenKey)
            local val = GetTriState(visibleKey, hiddenKey)
            local cb = AceGUI:Create("CheckBox")
            cb:SetTriState(true)
            cb:SetLabel(TriStateLabel(label, val))
            cb:SetValue(val)
            cb:SetFullWidth(true)
            cb:SetDisabled(controlsDisabled)
            cb:SetCallback("OnValueChanged", function(widget, event, newVal)
                if controlsDisabled then return end
                config[visibleKey] = (newVal == true)
                config[hiddenKey] = (newVal == nil)
                ApplyAlphaSettingChange(true)
            end)
            return cb
        end

        container:AddChild(CreateTriStateToggle("In Combat", "forceAlphaInCombat", "forceHideInCombat"))
        container:AddChild(CreateTriStateToggle("Out of Combat", "forceAlphaOutOfCombat", "forceHideOutOfCombat"))
        container:AddChild(CreateTriStateToggle("Regular Mount", "forceAlphaRegularMounted", "forceHideRegularMounted"))
        container:AddChild(CreateTriStateToggle("Skyriding", "forceAlphaDragonriding", "forceHideDragonriding"))

        local mountedActive = config.forceAlphaRegularMounted
            or config.forceHideRegularMounted
            or config.forceAlphaDragonriding
            or config.forceHideDragonriding
        local isDruid = CooldownCompanion._playerClassID == 11
        if mountedActive and (opts.isGlobal or isDruid) then
            local travelVal = config.treatTravelFormAsMounted or false
            local travelCb = AceGUI:Create("CheckBox")
            travelCb:SetLabel("Include Druid Travel Form (applies to both)")
            travelCb:SetValue(travelVal)
            travelCb:SetFullWidth(true)
            travelCb:SetDisabled(controlsDisabled)
            travelCb:SetCallback("OnValueChanged", function(widget, event, val)
                if controlsDisabled then return end
                config.treatTravelFormAsMounted = val
                ApplyAlphaSettingChange(false)
            end)
            container:AddChild(travelCb)
        end

        local targetVal = config.forceAlphaTargetExists or false
        local targetCb = AceGUI:Create("CheckBox")
        targetCb:SetLabel(targetVal and "Target Exists - |cff00ff00Fully Visible|r" or "Target Exists")
        targetCb:SetValue(targetVal)
        targetCb:SetFullWidth(true)
        targetCb:SetDisabled(controlsDisabled)
        targetCb:SetCallback("OnValueChanged", function(widget, event, val)
            if controlsDisabled then return end
            config.forceAlphaTargetExists = val
            ApplyAlphaSettingChange(true)
        end)
        container:AddChild(targetCb)

        if targetVal then
            local enemyOnlyVal = config.forceAlphaTargetEnemyOnly or false
            local enemyOnlyCb = AceGUI:Create("CheckBox")
            enemyOnlyCb:SetLabel("Enemy Only")
            enemyOnlyCb:SetValue(enemyOnlyVal)
            enemyOnlyCb:SetFullWidth(true)
            enemyOnlyCb:SetDisabled(controlsDisabled)
            enemyOnlyCb:SetCallback("OnValueChanged", function(widget, event, val)
                if controlsDisabled then return end
                config.forceAlphaTargetEnemyOnly = val
                ApplyAlphaSettingChange(true)
            end)
            container:AddChild(enemyOnlyCb)
            ApplyCheckboxIndent(enemyOnlyCb, 20)
        end

        local focusVal = config.forceAlphaFocusExists or false
        local focusCb = AceGUI:Create("CheckBox")
        focusCb:SetLabel(focusVal and "Focus Exists - |cff00ff00Fully Visible|r" or "Focus Exists")
        focusCb:SetValue(focusVal)
        focusCb:SetFullWidth(true)
        focusCb:SetDisabled(controlsDisabled)
        focusCb:SetCallback("OnValueChanged", function(widget, event, val)
            if controlsDisabled then return end
            config.forceAlphaFocusExists = val
            ApplyAlphaSettingChange(true)
        end)
        container:AddChild(focusCb)

        local mouseoverVal = config.forceAlphaMouseover or false
        local mouseoverCb = AceGUI:Create("CheckBox")
        mouseoverCb:SetLabel(mouseoverVal and "Mouseover - |cff00ff00Fully Visible|r" or "Mouseover")
        mouseoverCb:SetValue(mouseoverVal)
        mouseoverCb:SetFullWidth(true)
        mouseoverCb:SetDisabled(controlsDisabled)
        mouseoverCb:SetCallback("OnValueChanged", function(widget, event, val)
            if controlsDisabled then return end
            config.forceAlphaMouseover = val
            ApplyAlphaSettingChange(true)
        end)
        container:AddChild(mouseoverCb)

        CreateInfoButton(mouseoverCb.frame, mouseoverCb.text, "LEFT", "RIGHT", 4, 0, {
            "Mouseover",
            {"When enabled, mousing over forces full visibility. Like all |cff00ff00Force Visible|r conditions, this overrides |cffff0000Force Hidden|r.", 1, 1, 1, true},
        }, tabInfoBtns)

        local fadeCb = AceGUI:Create("CheckBox")
        fadeCb:SetLabel("Custom Fade Settings")
        fadeCb:SetValue(config.customFade or false)
        fadeCb:SetFullWidth(true)
        fadeCb:SetDisabled(controlsDisabled)
        fadeCb:SetCallback("OnValueChanged", function(widget, event, val)
            if controlsDisabled then return end
            config.customFade = val or nil
            ApplyAlphaSettingChange(true)
        end)
        container:AddChild(fadeCb)

        if config.customFade then
        local fadeDelaySlider = AceGUI:Create("Slider")
        fadeDelaySlider:SetLabel("Fade Delay (seconds)")
        fadeDelaySlider:SetSliderValues(0, 5, 0.1)
        fadeDelaySlider:SetValue(config.fadeDelay or 1)
        fadeDelaySlider:SetFullWidth(true)
        fadeDelaySlider:SetDisabled(controlsDisabled)
        fadeDelaySlider:SetCallback("OnValueChanged", function(widget, event, val)
            if controlsDisabled then return end
            config.fadeDelay = val
            ApplyAlphaSettingChange(false)
        end)
        container:AddChild(fadeDelaySlider)

        local fadeInSlider = AceGUI:Create("Slider")
        fadeInSlider:SetLabel("Fade In Duration (seconds)")
        fadeInSlider:SetSliderValues(0, 5, 0.1)
        fadeInSlider:SetValue(config.fadeInDuration or 0.2)
        fadeInSlider:SetFullWidth(true)
        fadeInSlider:SetDisabled(controlsDisabled)
        fadeInSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if controlsDisabled then return end
            config.fadeInDuration = val
            ApplyAlphaSettingChange(false)
        end)
        container:AddChild(fadeInSlider)

        local fadeOutSlider = AceGUI:Create("Slider")
        fadeOutSlider:SetLabel("Fade Out Duration (seconds)")
        fadeOutSlider:SetSliderValues(0, 5, 0.1)
        fadeOutSlider:SetValue(config.fadeOutDuration or 0.2)
        fadeOutSlider:SetFullWidth(true)
        fadeOutSlider:SetDisabled(controlsDisabled)
        fadeOutSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if controlsDisabled then return end
            config.fadeOutDuration = val
            ApplyAlphaSettingChange(false)
        end)
        container:AddChild(fadeOutSlider)
        end -- config.customFade
    end
end
ST._BuildAlphaControls = BuildAlphaControls
ST._BuildIndependentAnchorTargetRow = BuildIndependentAnchorTargetRow

ST._AddFontControls = AddFontControls
ST._AddOffsetSliders = AddOffsetSliders
ST._AddBorderRenderModeDropdown = AddBorderRenderModeDropdown
