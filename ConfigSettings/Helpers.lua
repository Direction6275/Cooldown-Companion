local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

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
ST._GetBarTextureOptions = GetBarTextureOptions
