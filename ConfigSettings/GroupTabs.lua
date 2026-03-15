local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreatePromoteButton = ST._CreatePromoteButton
local CreateCheckboxPromoteButton = ST._CreateCheckboxPromoteButton
local CreateInfoButton = ST._CreateInfoButton
local BuildCompactModeControls = ST._BuildCompactModeControls
local BuildGroupSettingPresetControls = ST._BuildGroupSettingPresetControls
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent

-- Imports from SectionBuilders.lua
local BuildCooldownTextControls = ST._BuildCooldownTextControls
local BuildAuraTextControls = ST._BuildAuraTextControls
local BuildAuraStackTextControls = ST._BuildAuraStackTextControls
local BuildKeybindTextControls = ST._BuildKeybindTextControls
local BuildChargeTextControls = ST._BuildChargeTextControls
local BuildBorderControls = ST._BuildBorderControls
local BuildBackgroundColorControls = ST._BuildBackgroundColorControls
local BuildDesaturationControls = ST._BuildDesaturationControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls
local BuildShowOutOfRangeControls = ST._BuildShowOutOfRangeControls
local BuildShowGCDSwipeControls = ST._BuildShowGCDSwipeControls
local BuildCooldownSwipeControls = ST._BuildCooldownSwipeControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildAssistedHighlightControls = ST._BuildAssistedHighlightControls
local BuildProcGlowControls = ST._BuildProcGlowControls
local BuildPandemicGlowControls = ST._BuildPandemicGlowControls
local BuildPandemicBarControls = ST._BuildPandemicBarControls
local BuildAuraIndicatorControls = ST._BuildAuraIndicatorControls
local BuildReadyGlowControls = ST._BuildReadyGlowControls
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildBarColorsControls = ST._BuildBarColorsControls
local BuildBarNameTextControls = ST._BuildBarNameTextControls
local BuildBarReadyTextControls = ST._BuildBarReadyTextControls

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

-- Imports from BarModeTabs.lua
local BuildBarAppearanceTab = ST._BuildBarAppearanceTab
local BuildBarEffectsTab = ST._BuildBarEffectsTab

-- Imports from TextModeTabs.lua
local BuildTextAppearanceTab = ST._BuildTextAppearanceTab

local function BuildLayoutTab(container)
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style

    -- ================================================================
    -- Anchor to Frame (editbox + pick button row)
    -- ================================================================
    local anchorRow = AceGUI:Create("SimpleGroup")
    anchorRow:SetFullWidth(true)
    anchorRow:SetLayout("Flow")

    local anchorBox = AceGUI:Create("EditBox")
    if anchorBox.editbox.Instructions then anchorBox.editbox.Instructions:Hide() end
    local isPanel = group.parentContainerId ~= nil
    local panelContainerFrame = isPanel and ("CooldownCompanionContainer" .. group.parentContainerId) or nil
    anchorBox:SetLabel("Anchor to Frame")
    local currentAnchor = group.anchor.relativeTo
    if currentAnchor == "UIParent" then currentAnchor = "" end
    if isPanel and currentAnchor == panelContainerFrame then currentAnchor = "" end
    anchorBox:SetText(currentAnchor)
    anchorBox:SetRelativeWidth(0.68)
    anchorBox:SetCallback("OnEnterPressed", function(widget, event, text)
        local defaultFrame = isPanel and panelContainerFrame or "UIParent"
        local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= defaultFrame
        if text == "" then
            CooldownCompanion:SetGroupAnchor(CS.selectedGroup, isPanel and panelContainerFrame or "UIParent", wasAnchored)
        else
            CooldownCompanion:SetGroupAnchor(CS.selectedGroup, text)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    anchorRow:AddChild(anchorBox)

    local pickBtn = AceGUI:Create("Button")
    pickBtn:SetText("Pick")
    pickBtn:SetRelativeWidth(0.24)
    pickBtn:SetCallback("OnClick", function()
        local grp = CS.selectedGroup
        CS.StartPickFrame(function(name)
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if name then
                CooldownCompanion:SetGroupAnchor(grp, name)
            end
            CooldownCompanion:RefreshConfigPanel()
        end, grp)
    end)
    anchorRow:AddChild(pickBtn)

    -- (?) tooltip for anchor picking
    CreateInfoButton(pickBtn.frame, pickBtn.frame, "LEFT", "RIGHT", 2, 0, {
        "Pick Frame",
        {"Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this group to it, or right-click to cancel.", 1, 1, 1, true},
        " ",
        {"You can also type a frame name directly into the editbox.", 1, 1, 1, true},
        " ",
        {"Middle-click the draggable header to toggle lock/unlock.", 1, 1, 1, true},
    }, tabInfoButtons)

    container:AddChild(anchorRow)
    pickBtn.frame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local p, rel, rp, xOfs, yOfs = self:GetPoint(1)
        if yOfs then
            self:SetPoint(p, rel, rp, xOfs, yOfs - 2)
        end
    end)

    -- Anchor Point dropdown
    local pointValues = {}
    for _, pt in ipairs(CS.anchorPoints) do
        pointValues[pt] = CS.anchorPointLabels[pt]
    end

    local anchorPt = AceGUI:Create("Dropdown")
    anchorPt:SetLabel("Anchor Point")
    anchorPt:SetList(pointValues)
    anchorPt:SetValue(group.anchor.point or "CENTER")
    anchorPt:SetFullWidth(true)
    anchorPt:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.point = val
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    container:AddChild(anchorPt)

    -- Relative Point dropdown
    local relPt = AceGUI:Create("Dropdown")
    relPt:SetLabel("Relative Point")
    relPt:SetList(pointValues)
    relPt:SetValue(group.anchor.relativePoint or "CENTER")
    relPt:SetFullWidth(true)
    relPt:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.relativePoint = val
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    container:AddChild(relPt)

    -- Allow decimal input from editbox while keeping slider/wheel at 1px steps
    local function HookSliderEditBox(sliderWidget)
        sliderWidget.editbox:SetScript("OnEnterPressed", function(editbox)
            local widget = editbox.obj
            local value = tonumber(editbox:GetText())
            if value then
                value = math.floor(value * 10 + 0.5) / 10
                value = math.max(widget.min, math.min(widget.max, value))
                PlaySound(856)
                widget:SetValue(value)
                widget:Fire("OnValueChanged", value)
                widget:Fire("OnMouseUp", value)
            end
        end)
    end

    -- X Offset
    local xSlider = AceGUI:Create("Slider")
    xSlider:SetLabel("X Offset")
    xSlider:SetSliderValues(-2000, 2000, 0.1)
    xSlider:SetValue(group.anchor.x or 0)
    xSlider:SetFullWidth(true)
    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.x = val
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    HookSliderEditBox(xSlider)
    container:AddChild(xSlider)

    -- Y Offset
    local ySlider = AceGUI:Create("Slider")
    ySlider:SetLabel("Y Offset")
    ySlider:SetSliderValues(-2000, 2000, 0.1)
    ySlider:SetValue(group.anchor.y or 0)
    ySlider:SetFullWidth(true)
    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.y = val
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    HookSliderEditBox(ySlider)
    container:AddChild(ySlider)

    -- ================================================================
    -- Orientation / Layout controls (mode-dependent)
    -- ================================================================
    if group.displayMode == "text" then
        local orientDrop = AceGUI:Create("Dropdown")
        orientDrop:SetLabel("Orientation")
        orientDrop:SetList({ horizontal = "Horizontal", vertical = "Vertical" })
        orientDrop:SetValue(style.orientation or "vertical")
        orientDrop:SetFullWidth(true)
        orientDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.orientation = val
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(orientDrop)

        if #group.buttons > 1 then
            local bprSlider = AceGUI:Create("Slider")
            bprSlider:SetLabel("Entries per Row/Column")
            local numEntries = math.max(1, #group.buttons)
            bprSlider:SetSliderValues(1, numEntries, 1)
            bprSlider:SetValue(math.min(style.buttonsPerRow or 12, numEntries))
            bprSlider:SetFullWidth(true)
            bprSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.buttonsPerRow = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            container:AddChild(bprSlider)
        end
    elseif group.displayMode == "bars" then
        local vertFillCheck = AceGUI:Create("CheckBox")
        vertFillCheck:SetLabel("Vertical Bar Fill")
        vertFillCheck:SetValue(style.barFillVertical or false)
        vertFillCheck:SetFullWidth(true)
        vertFillCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barFillVertical = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(vertFillCheck)

        local reverseFillCheck = AceGUI:Create("CheckBox")
        reverseFillCheck:SetLabel("Flip Fill/Drain Direction")
        reverseFillCheck:SetValue(style.barReverseFill or false)
        reverseFillCheck:SetFullWidth(true)
        reverseFillCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barReverseFill = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        container:AddChild(reverseFillCheck)

        if #group.buttons > 1 then
            local horzLayoutCheck = AceGUI:Create("CheckBox")
            horzLayoutCheck:SetLabel("Horizontal Bar Layout")
            horzLayoutCheck:SetValue((style.orientation or "vertical") == "horizontal")
            horzLayoutCheck:SetFullWidth(true)
            horzLayoutCheck:SetCallback("OnValueChanged", function(widget, event, val)
                style.orientation = val and "horizontal" or "vertical"
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(horzLayoutCheck)
        end
    else
        local orientDrop = AceGUI:Create("Dropdown")
        orientDrop:SetLabel("Orientation")
        orientDrop:SetList({ horizontal = "Horizontal", vertical = "Vertical" })
        orientDrop:SetValue(style.orientation or "horizontal")
        orientDrop:SetFullWidth(true)
        orientDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.orientation = val
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(orientDrop)
    end

    -- Buttons Per Row/Column (icon/bar modes only; text mode has its own slider)
    if group.displayMode ~= "text" then
        local numButtons = math.max(1, #group.buttons)
        local bprSlider = AceGUI:Create("Slider")
        bprSlider:SetLabel("Buttons Per Row/Column")
        bprSlider:SetSliderValues(1, numButtons, 1)
        bprSlider:SetValue(math.min(style.buttonsPerRow or 12, numButtons))
        bprSlider:SetFullWidth(true)
        bprSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonsPerRow = val
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        container:AddChild(bprSlider)
    end

    -- ================================================================
    -- ADVANCED: Alpha (from Extras)
    -- ================================================================
    local alphaHeading = AceGUI:Create("Heading")
    alphaHeading:SetText("Alpha")
    ColorHeading(alphaHeading)
    alphaHeading:SetFullWidth(true)
    container:AddChild(alphaHeading)

    local alphaCollapsed = CS.collapsedSections["layout_alpha"]
    AttachCollapseButton(alphaHeading, alphaCollapsed, function()
        CS.collapsedSections["layout_alpha"] = not CS.collapsedSections["layout_alpha"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not alphaCollapsed then
    local baseAlphaSlider = AceGUI:Create("Slider")
    baseAlphaSlider:SetLabel("Baseline Alpha")
    baseAlphaSlider:SetSliderValues(0, 1, 0.1)
    baseAlphaSlider:SetValue(group.baselineAlpha or 1)
    baseAlphaSlider:SetFullWidth(true)
    baseAlphaSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.baselineAlpha = val
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame and frame:IsShown() then
            frame:SetAlpha(val)
        end
        local state = CooldownCompanion.alphaState and CooldownCompanion.alphaState[CS.selectedGroup]
        if state then
            state.currentAlpha = val
            state.desiredAlpha = val
            state.lastAlpha = val
            state.fadeDuration = 0
        end
    end)
    container:AddChild(baseAlphaSlider)

    CreateInfoButton(baseAlphaSlider.frame, baseAlphaSlider.label, "LEFT", "CENTER", baseAlphaSlider.label:GetStringWidth() / 2 + 4, 0, {
        "Alpha",
        {"Controls the transparency of this group. Alpha = 1 is fully visible. Alpha = 0 means completely hidden.\n\nThe first four options (In Combat, Out of Combat, Regular Mount, Skyriding) are 3-way toggles — click to cycle through Disabled, |cff00ff00Fully Visible|r, and |cffff0000Fully Hidden|r.\n\n|cff00ff00Fully Visible|r overrides alpha to 1 when the condition is met.\n\n|cffff0000Fully Hidden|r overrides alpha to 0 when the condition is met.\n\nIf both apply simultaneously, |cff00ff00Fully Visible|r takes priority.", 1, 1, 1, true},
    }, tabInfoButtons)

    do
        local function GetTriState(visibleKey, hiddenKey)
            if group[hiddenKey] then return nil end
            if group[visibleKey] then return true end
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
            cb:SetCallback("OnValueChanged", function(widget, event, newVal)
                group[visibleKey] = (newVal == true)
                group[hiddenKey] = (newVal == nil)
                CooldownCompanion:RefreshConfigPanel()
            end)
            return cb
        end

        container:AddChild(CreateTriStateToggle("In Combat", "forceAlphaInCombat", "forceHideInCombat"))
        container:AddChild(CreateTriStateToggle("Out of Combat", "forceAlphaOutOfCombat", "forceHideOutOfCombat"))
        container:AddChild(CreateTriStateToggle("Regular Mount", "forceAlphaRegularMounted", "forceHideRegularMounted"))
        container:AddChild(CreateTriStateToggle("Skyriding", "forceAlphaDragonriding", "forceHideDragonriding"))

        local mountedActive = group.forceAlphaRegularMounted
            or group.forceHideRegularMounted
            or group.forceAlphaDragonriding
            or group.forceHideDragonriding
        local isDruid = CooldownCompanion._playerClassID == 11
        if mountedActive and (group.isGlobal or isDruid) then
            local travelVal = group.treatTravelFormAsMounted or false
            local travelCb = AceGUI:Create("CheckBox")
            travelCb:SetLabel("Include Druid Travel Form (applies to both)")
            travelCb:SetValue(travelVal)
            travelCb:SetFullWidth(true)
            travelCb:SetCallback("OnValueChanged", function(widget, event, val)
                group.treatTravelFormAsMounted = val
            end)
            container:AddChild(travelCb)
        end

        local targetVal = group.forceAlphaTargetExists or false
        local targetCb = AceGUI:Create("CheckBox")
        targetCb:SetLabel(targetVal and "Target Exists - |cff00ff00Fully Visible|r" or "Target Exists")
        targetCb:SetValue(targetVal)
        targetCb:SetFullWidth(true)
        targetCb:SetCallback("OnValueChanged", function(widget, event, val)
            group.forceAlphaTargetExists = val
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(targetCb)

        local mouseoverVal = group.forceAlphaMouseover or false
        local mouseoverCb = AceGUI:Create("CheckBox")
        mouseoverCb:SetLabel(mouseoverVal and "Mouseover - |cff00ff00Fully Visible|r" or "Mouseover")
        mouseoverCb:SetValue(mouseoverVal)
        mouseoverCb:SetFullWidth(true)
        mouseoverCb:SetCallback("OnValueChanged", function(widget, event, val)
            group.forceAlphaMouseover = val
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(mouseoverCb)

        CreateInfoButton(mouseoverCb.frame, mouseoverCb.text, "LEFT", "RIGHT", 4, 0, {
            "Mouseover",
            {"When enabled, mousing over the group forces it to full visibility. Like all |cff00ff00Force Visible|r conditions, this overrides |cffff0000Force Hidden|r.", 1, 1, 1, true},
        }, tabInfoButtons)

        local fadeCb = AceGUI:Create("CheckBox")
        fadeCb:SetLabel("Custom Fade Settings")
        fadeCb:SetValue(group.customFade or false)
        fadeCb:SetFullWidth(true)
        fadeCb:SetCallback("OnValueChanged", function(widget, event, val)
            group.customFade = val or nil
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(fadeCb)

        if group.customFade then
        local fadeDelaySlider = AceGUI:Create("Slider")
        fadeDelaySlider:SetLabel("Fade Delay (seconds)")
        fadeDelaySlider:SetSliderValues(0, 5, 0.1)
        fadeDelaySlider:SetValue(group.fadeDelay or 1)
        fadeDelaySlider:SetFullWidth(true)
        fadeDelaySlider:SetCallback("OnValueChanged", function(widget, event, val)
            group.fadeDelay = val
        end)
        container:AddChild(fadeDelaySlider)

        local fadeInSlider = AceGUI:Create("Slider")
        fadeInSlider:SetLabel("Fade In Duration (seconds)")
        fadeInSlider:SetSliderValues(0, 5, 0.1)
        fadeInSlider:SetValue(group.fadeInDuration or 0.2)
        fadeInSlider:SetFullWidth(true)
        fadeInSlider:SetCallback("OnValueChanged", function(widget, event, val)
            group.fadeInDuration = val
        end)
        container:AddChild(fadeInSlider)

        local fadeOutSlider = AceGUI:Create("Slider")
        fadeOutSlider:SetLabel("Fade Out Duration (seconds)")
        fadeOutSlider:SetSliderValues(0, 5, 0.1)
        fadeOutSlider:SetValue(group.fadeOutDuration or 0.2)
        fadeOutSlider:SetFullWidth(true)
        fadeOutSlider:SetCallback("OnValueChanged", function(widget, event, val)
            group.fadeOutDuration = val
        end)
        container:AddChild(fadeOutSlider)
        end -- group.customFade
    end
    end -- not alphaCollapsed

    -- ================================================================
    -- ADVANCED: Strata — Frame Strata (all modes) + Custom Strata (icon mode only)
    -- ================================================================
    local strataHeading = AceGUI:Create("Heading")
    strataHeading:SetText("Strata")
    ColorHeading(strataHeading)
    strataHeading:SetFullWidth(true)
    container:AddChild(strataHeading)

    local strataCollapsed = CS.collapsedSections["layout_strata"]
    AttachCollapseButton(strataHeading, strataCollapsed, function()
        CS.collapsedSections["layout_strata"] = not CS.collapsedSections["layout_strata"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not strataCollapsed then

    -- Frame Strata dropdown (available for both icon and bar mode)
    do
        local frameStrataOrder = {"BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG"}
        local frameStrataLabels = {
            BACKGROUND = "Background",
            LOW = "Low",
            MEDIUM = "Default",
            HIGH = "High",
            DIALOG = "Highest",
        }

        local frameStrataDrop = AceGUI:Create("Dropdown")
        frameStrataDrop:SetLabel("Frame Strata")
        frameStrataDrop:SetList(frameStrataLabels, frameStrataOrder)
        frameStrataDrop:SetValue(group.frameStrata or "MEDIUM")
        frameStrataDrop:SetFullWidth(true)
        frameStrataDrop:SetCallback("OnValueChanged", function(widget, event, val)
            group.frameStrata = (val ~= "MEDIUM") and val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        container:AddChild(frameStrataDrop)

        CreateInfoButton(frameStrataDrop.frame, frameStrataDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Frame Strata",
            {"Sets the rendering layer for this group.", 1, 1, 1, true},
            " ",
            {"Higher strata groups fully overlap lower ones.", 1, 1, 1, true},
            " ",
            {"Only change this if you need one group to overlap another.", 1, 1, 1, true},
        }, tabInfoButtons)
    end

    -- Custom Icon Strata (sub-element ordering) — icon mode only
    if group.displayMode == "icons" then
    local customStrataEnabled = type(style.strataOrder) == "table"

    local strataToggle = AceGUI:Create("CheckBox")
    strataToggle:SetLabel("Custom Icon Strata")
    strataToggle:SetValue(customStrataEnabled)
    strataToggle:SetFullWidth(true)
    strataToggle:SetCallback("OnValueChanged", function(widget, event, val)
        if not val then
            style.strataOrder = nil
            CS.pendingStrataOrder = nil
            CS.pendingStrataGroup = nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        else
            style.strataOrder = style.strataOrder or {}
            CS.pendingStrataOrder = nil
            CS.InitPendingStrataOrder(CS.selectedGroup)
        end
        if CS.col4Container and CS.col4Container.tabGroup then
            CS.col4Container.tabGroup:SelectTab(CS.selectedTab)
        end
    end)
    container:AddChild(strataToggle)

    CreateInfoButton(strataToggle.frame, strataToggle.checkbg, "LEFT", "RIGHT", strataToggle.text:GetStringWidth() + 4, 0, {
        "Custom Icon Strata",
        {"Controls the draw order of visual layers on each icon: Cooldown Swipe, Aura/Pandemic Glow, Ready Glow, Text Overlay, Assisted Highlight, and Proc Glow.", 1, 1, 1, true},
        {"Layer 6 draws on top, Layer 1 on the bottom. When disabled, the default order is used.", 1, 1, 1, true},
    }, tabInfoButtons)

    if customStrataEnabled then
        CS.InitPendingStrataOrder(CS.selectedGroup)

        local ELEMENT_COUNT = #ST.DEFAULT_STRATA_ORDER

        -- Build dropdown list with unassigned entries highlighted in green
        local function BuildStrataList()
            local assigned = {}
            for i = 1, ELEMENT_COUNT do
                if CS.pendingStrataOrder[i] then
                    assigned[CS.pendingStrataOrder[i]] = true
                end
            end
            local list = {}
            for _, key in ipairs(CS.strataElementKeys) do
                if not assigned[key] then
                    list[key] = "|cff40ff40" .. CS.strataElementLabels[key] .. "|r"
                else
                    list[key] = CS.strataElementLabels[key]
                end
            end
            return list
        end

        local strataDropdowns = {}

        -- Refresh all dropdown lists and values
        local function RefreshAllDropdowns()
            local list = BuildStrataList()
            for i = 1, ELEMENT_COUNT do
                if strataDropdowns[i] then
                    strataDropdowns[i]:SetList(list)
                    strataDropdowns[i]:SetValue(CS.pendingStrataOrder[i])
                end
            end
        end

        for displayIdx = 1, ELEMENT_COUNT do
            local pos = ELEMENT_COUNT + 1 - displayIdx
            local label
            if pos == ELEMENT_COUNT then
                label = "Layer " .. pos .. " (Top)"
            elseif pos == 1 then
                label = "Layer " .. pos .. " (Bottom)"
            else
                label = "Layer " .. pos
            end

            local drop = AceGUI:Create("Dropdown")
            drop:SetLabel(label)
            drop:SetList(BuildStrataList())
            drop:SetValue(CS.pendingStrataOrder[pos])
            drop:SetFullWidth(true)
            drop:SetCallback("OnValueChanged", function(widget, event, val)
                for i = 1, ELEMENT_COUNT do
                    if i ~= pos and CS.pendingStrataOrder[i] == val then
                        CS.pendingStrataOrder[i] = nil
                    end
                end
                CS.pendingStrataOrder[pos] = val

                if CS.IsStrataOrderComplete(CS.pendingStrataOrder) then
                    style.strataOrder = {}
                    for i = 1, ELEMENT_COUNT do
                        style.strataOrder[i] = CS.pendingStrataOrder[i]
                    end
                else
                    style.strataOrder = {}
                end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)

                RefreshAllDropdowns()
            end)
            container:AddChild(drop)
            strataDropdowns[pos] = drop
        end
    end
    end -- not bars (custom strata)

    end -- not strataCollapsed

    -- Apply "Hide CDC Tooltips" to tab info buttons (skip advanced toggles)
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            if not btn._isAdvancedToggle then btn:Hide() end
        end
    end
end


local function BuildEffectsTab(container)
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

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style

    -- Branch for bar mode
    if group.displayMode == "bars" then
        CooldownCompanion:SetGroupProcGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupPandemicPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupReadyGlowPreview(CS.selectedGroup, false)
        BuildBarEffectsTab(container, group, style)
        return
    end

    -- ================================================================
    -- Proc Glow enable toggle
    -- ================================================================
    local procEnableCb = AceGUI:Create("CheckBox")
    procEnableCb:SetLabel("Show Proc Glow")
    procEnableCb:SetValue(style.procGlowStyle ~= "none")
    procEnableCb:SetFullWidth(true)
    procEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.procGlowStyle = val and "glow" or "none"
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(procEnableCb)

    local procAdvExpanded, procAdvBtn = AddAdvancedToggle(procEnableCb, "procGlow", tabInfoButtons, style.procGlowStyle ~= "none")
    -- Skip promote for aura-tracked buttons (Show Active Aura Glow covers this)
    local procBtnData = CS.selectedButton and group.buttons[CS.selectedButton]
    if not (procBtnData and procBtnData.isPassive) then
        CreateCheckboxPromoteButton(procEnableCb, procAdvBtn, "procGlow", group, style)
    end

    if procAdvExpanded and style.procGlowStyle ~= "none" then
    local procCombatCb = AceGUI:Create("CheckBox")
    procCombatCb:SetLabel("Show Only In Combat")
    procCombatCb:SetValue(style.procGlowCombatOnly or false)
    procCombatCb:SetFullWidth(true)
    procCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.procGlowCombatOnly = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(procCombatCb)
    ApplyCheckboxIndent(procCombatCb, 20)

    BuildProcGlowControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    local procPreviewBtn = AceGUI:Create("Button")
    procPreviewBtn:SetText("Preview Proc Glow (3s)")
    procPreviewBtn:SetFullWidth(true)
    procPreviewBtn:SetCallback("OnClick", function()
        CooldownCompanion:PlayGroupProcGlowPreview(CS.selectedGroup, 3)
    end)
    container:AddChild(procPreviewBtn)
    else
    CooldownCompanion:SetGroupProcGlowPreview(CS.selectedGroup, false)
    end -- procAdvExpanded

    -- ================================================================
    -- Show Aura Glow enable toggle
    -- ================================================================
    local auraEnableCb = AceGUI:Create("CheckBox")
    auraEnableCb:SetLabel("Show Aura Glow")
    auraEnableCb:SetValue(style.auraGlowStyle ~= "none")
    auraEnableCb:SetFullWidth(true)
    auraEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.auraGlowStyle = val and "pixel" or "none"
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraEnableCb)

    local auraAdvExpanded, auraAdvBtn = AddAdvancedToggle(auraEnableCb, "auraGlow", tabInfoButtons, style.auraGlowStyle ~= "none")
    CreateCheckboxPromoteButton(auraEnableCb, auraAdvBtn, "auraIndicator", group, style)

    if auraAdvExpanded and style.auraGlowStyle ~= "none" then
    local auraCombatCb = AceGUI:Create("CheckBox")
    auraCombatCb:SetLabel("Show Only In Combat")
    auraCombatCb:SetValue(style.auraGlowCombatOnly or false)
    auraCombatCb:SetFullWidth(true)
    auraCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.auraGlowCombatOnly = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(auraCombatCb)
    ApplyCheckboxIndent(auraCombatCb, 20)

    local auraInvertCb = AceGUI:Create("CheckBox")
    auraInvertCb:SetLabel("Show When Missing")
    auraInvertCb:SetValue(style.auraGlowInvert or false)
    auraInvertCb:SetFullWidth(true)
    auraInvertCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.auraGlowInvert = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(auraInvertCb)
    ApplyCheckboxIndent(auraInvertCb, 20)

    BuildAuraIndicatorControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    local auraPreviewBtn = AceGUI:Create("Button")
    auraPreviewBtn:SetText("Preview Aura Glow (3s)")
    auraPreviewBtn:SetFullWidth(true)
    auraPreviewBtn:SetCallback("OnClick", function()
        CooldownCompanion:PlayGroupAuraGlowPreview(CS.selectedGroup, 3)
    end)
    container:AddChild(auraPreviewBtn)
    else
    CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
    end -- auraAdvExpanded

    -- ================================================================
    -- Pandemic Glow
    -- ================================================================
    local pandemicGlowCb = AceGUI:Create("CheckBox")
    pandemicGlowCb:SetLabel("Show Pandemic Glow")
    pandemicGlowCb:SetValue(style.showPandemicGlow ~= false)
    pandemicGlowCb:SetFullWidth(true)
    pandemicGlowCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showPandemicGlow = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(pandemicGlowCb)

    local pandemicAdvExpanded, pandemicAdvBtn = AddAdvancedToggle(pandemicGlowCb, "pandemicGlow", tabInfoButtons, style.showPandemicGlow ~= false)
    CreateCheckboxPromoteButton(pandemicGlowCb, pandemicAdvBtn, "pandemicGlow", group, style)

    if pandemicAdvExpanded and style.showPandemicGlow ~= false then
    local pandemicCombatCb = AceGUI:Create("CheckBox")
    pandemicCombatCb:SetLabel("Show Only In Combat")
    pandemicCombatCb:SetValue(style.pandemicGlowCombatOnly or false)
    pandemicCombatCb:SetFullWidth(true)
    pandemicCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.pandemicGlowCombatOnly = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(pandemicCombatCb)
    ApplyCheckboxIndent(pandemicCombatCb, 20)

    BuildPandemicGlowControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    local pandemicPreviewBtn = AceGUI:Create("Button")
    pandemicPreviewBtn:SetText("Preview Pandemic Glow (3s)")
    pandemicPreviewBtn:SetFullWidth(true)
    pandemicPreviewBtn:SetCallback("OnClick", function()
        CooldownCompanion:PlayGroupPandemicPreview(CS.selectedGroup, 3)
    end)
    container:AddChild(pandemicPreviewBtn)
    else
    CooldownCompanion:SetGroupPandemicPreview(CS.selectedGroup, false)
    end -- pandemicAdvExpanded

    -- ================================================================
    -- Ready Glow (glow while off cooldown)
    -- ================================================================
    local readyEnableCb = AceGUI:Create("CheckBox")
    readyEnableCb:SetLabel("Show Ready Glow")
    readyEnableCb:SetValue(style.readyGlowStyle and style.readyGlowStyle ~= "none")
    readyEnableCb:SetFullWidth(true)
    readyEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.readyGlowStyle = val and "solid" or "none"
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(readyEnableCb)

    local readyAdvExpanded, readyAdvBtn = AddAdvancedToggle(readyEnableCb, "readyGlow", tabInfoButtons, style.readyGlowStyle and style.readyGlowStyle ~= "none")
    local readyPromoteBtn = CreateCheckboxPromoteButton(readyEnableCb, readyAdvBtn, "readyGlow", group, style)
    CreateInfoButton(readyEnableCb.frame, readyPromoteBtn, "LEFT", "RIGHT", 4, 0, {
        "Ready Glow",
        {"Adds a glow effect around buttons whose spells or items are off cooldown and ready to use.", 1, 1, 1, true},
    }, tabInfoButtons)

    if readyAdvExpanded and style.readyGlowStyle and style.readyGlowStyle ~= "none" then
    local readyCombatCb = AceGUI:Create("CheckBox")
    readyCombatCb:SetLabel("Show Only In Combat")
    readyCombatCb:SetValue(style.readyGlowCombatOnly or false)
    readyCombatCb:SetFullWidth(true)
    readyCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.readyGlowCombatOnly = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(readyCombatCb)
    ApplyCheckboxIndent(readyCombatCb, 20)

    local readyDurCb = AceGUI:Create("CheckBox")
    readyDurCb:SetLabel("Auto-Hide After Duration")
    readyDurCb:SetValue((style.readyGlowDuration or 0) > 0)
    readyDurCb:SetFullWidth(true)
    readyDurCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.readyGlowDuration = val and 3 or 0
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(readyDurCb)
    ApplyCheckboxIndent(readyDurCb, 20)

    if (style.readyGlowDuration or 0) > 0 then
        local readyDurSlider = AceGUI:Create("Slider")
        readyDurSlider:SetLabel("Duration (seconds)")
        readyDurSlider:SetSliderValues(0.5, 5, 0.5)
        readyDurSlider:SetValue(style.readyGlowDuration or 3)
        readyDurSlider:SetFullWidth(true)
        readyDurSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.readyGlowDuration = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyDurSlider)
    end

    BuildReadyGlowControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    local readyPreviewBtn = AceGUI:Create("Button")
    readyPreviewBtn:SetText("Preview Ready Glow (3s)")
    readyPreviewBtn:SetFullWidth(true)
    readyPreviewBtn:SetCallback("OnClick", function()
        CooldownCompanion:PlayGroupReadyGlowPreview(CS.selectedGroup, 3)
    end)
    container:AddChild(readyPreviewBtn)
    else
    CooldownCompanion:SetGroupReadyGlowPreview(CS.selectedGroup, false)
    end -- readyAdvExpanded

    -- ================================================================
    -- Desaturate on Cooldown
    -- ================================================================
    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Show Desaturate On Cooldown")
    desatCb:SetValue(style.desaturateOnCooldown or false)
    desatCb:SetFullWidth(true)
    desatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.desaturateOnCooldown = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(desatCb)
    CreateCheckboxPromoteButton(desatCb, nil, "desaturation", group, style)

    -- ================================================================
    -- Cooldown Swipe
    -- ================================================================
    local swipeCb = AceGUI:Create("CheckBox")
    swipeCb:SetLabel("Show Cooldown/Duration Swipe")
    swipeCb:SetValue(style.showCooldownSwipe ~= false)
    swipeCb:SetFullWidth(true)
    swipeCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showCooldownSwipe = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(swipeCb)

    local swipeAdvExpanded, swipeAdvBtn = AddAdvancedToggle(swipeCb, "cooldownSwipe", tabInfoButtons, style.showCooldownSwipe ~= false)
    CreateCheckboxPromoteButton(swipeCb, swipeAdvBtn, "cooldownSwipe", group, style)

    if swipeAdvExpanded and style.showCooldownSwipe ~= false then
        -- Reverse Swipe
        local reverseCb = AceGUI:Create("CheckBox")
        reverseCb:SetLabel("Reverse Swipe")
        reverseCb:SetValue(style.cooldownSwipeReverse or false)
        reverseCb:SetFullWidth(true)
        reverseCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownSwipeReverse = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(reverseCb)
        ApplyCheckboxIndent(reverseCb, 20)

        -- Show Swipe Fill
        local fillCb = AceGUI:Create("CheckBox")
        fillCb:SetLabel("Show Swipe Fill")
        fillCb:SetValue(style.showCooldownSwipeFill ~= false)
        fillCb:SetFullWidth(true)
        fillCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.showCooldownSwipeFill = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(fillCb)
        ApplyCheckboxIndent(fillCb, 20)

        -- Show Swipe Edge
        local edgeCb = AceGUI:Create("CheckBox")
        edgeCb:SetLabel("Show Swipe Edge")
        edgeCb:SetValue(style.showCooldownSwipeEdge ~= false)
        edgeCb:SetFullWidth(true)
        edgeCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.showCooldownSwipeEdge = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(edgeCb)
        ApplyCheckboxIndent(edgeCb, 20)
    end -- swipeAdvExpanded

    -- ================================================================
    -- GCD Swipe
    -- ================================================================
    local gcdCb = AceGUI:Create("CheckBox")
    gcdCb:SetLabel("Show GCD Swipe")
    gcdCb:SetValue(style.showGCDSwipe == true)
    gcdCb:SetFullWidth(true)
    gcdCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showGCDSwipe = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(gcdCb)
    CreateCheckboxPromoteButton(gcdCb, nil, "showGCDSwipe", group, style)

    -- Out of Range
    local oorCb = BuildShowOutOfRangeControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    CreateCheckboxPromoteButton(oorCb, nil, "showOutOfRange", group, style)

    -- Loss of Control
    local locCb = BuildLossOfControlControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    CreateCheckboxPromoteButton(locCb, nil, "lossOfControl", group, style)

    -- Unusable Dimming
    local unusableCb = BuildUnusableDimmingControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    CreateCheckboxPromoteButton(unusableCb, nil, "unusableDimming", group, style)

    -- Show Tooltips
    local tooltipCb = BuildShowTooltipsControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    CreateCheckboxPromoteButton(tooltipCb, nil, "showTooltips", group, style)

    -- ================================================================
    -- Assisted Highlight (icon-only)
    -- ================================================================
    local assistedCb = AceGUI:Create("CheckBox")
    assistedCb:SetLabel("Show Assisted Highlight")
    assistedCb:SetValue(style.showAssistedHighlight or false)
    assistedCb:SetFullWidth(true)
    assistedCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showAssistedHighlight = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(assistedCb)

    local assistedAdvExpanded = AddAdvancedToggle(assistedCb, "assistedHighlight", tabInfoButtons, style.showAssistedHighlight or false)

    if assistedAdvExpanded and style.showAssistedHighlight then
    local assistedCombatCb = AceGUI:Create("CheckBox")
    assistedCombatCb:SetLabel("Show Only In Combat")
    assistedCombatCb:SetValue(style.assistedHighlightCombatOnly or false)
    assistedCombatCb:SetFullWidth(true)
    assistedCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.assistedHighlightCombatOnly = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(assistedCombatCb)
    ApplyCheckboxIndent(assistedCombatCb, 20)

    BuildAssistedHighlightControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    end -- assistedAdvExpanded

    -- Apply "Hide CDC Tooltips" to tab info buttons (skip advanced toggles)
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            if not btn._isAdvancedToggle then btn:Hide() end
        end
    end
end

local function BuildAppearanceTab(container)
    -- Clean up elements from previous build
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style

    -- Branch for text mode
    if group.displayMode == "text" then
        BuildTextAppearanceTab(container, group, style)
        return
    end

    -- Branch for bar mode
    if group.displayMode == "bars" then
        BuildBarAppearanceTab(container, group, style)
        return
    end

    -- ================================================================
    -- Icon Settings (size, spacing)
    -- ================================================================
    local iconHeading = AceGUI:Create("Heading")
    iconHeading:SetText("Icon Settings")
    ColorHeading(iconHeading)
    iconHeading:SetFullWidth(true)
    container:AddChild(iconHeading)

    local iconSettingsCollapsed = CS.collapsedSections["appearance_icons"]
    AttachCollapseButton(iconHeading, iconSettingsCollapsed, function()
        CS.collapsedSections["appearance_icons"] = not CS.collapsedSections["appearance_icons"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not iconSettingsCollapsed then
    local squareCb = AceGUI:Create("CheckBox")
    squareCb:SetLabel("Square Icons")
    squareCb:SetValue(style.maintainAspectRatio or false)
    squareCb:SetFullWidth(true)
    if group.masqueEnabled then
        squareCb:SetDisabled(true)
        local masqueLabel = squareCb.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        masqueLabel:SetPoint("LEFT", squareCb.checkbg, "RIGHT", squareCb.text:GetStringWidth() + 8, 0)
        masqueLabel:SetText("|cff00ff00(Masque skinning is active)|r")
        table.insert(appearanceTabElements, masqueLabel)
    end
    squareCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.maintainAspectRatio = val
        if not val then
            local size = style.buttonSize or ST.BUTTON_SIZE
            style.iconWidth = style.iconWidth or size
            style.iconHeight = style.iconHeight or size
        end
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(squareCb)

    -- Size sliders — always visible
    if style.maintainAspectRatio then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Button Size")
        sizeSlider:SetSliderValues(10, 150, 0.1)
        sizeSlider:SetValue(style.buttonSize or ST.BUTTON_SIZE)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(sizeSlider)
    else
        local wSlider = AceGUI:Create("Slider")
        wSlider:SetLabel("Icon Width")
        wSlider:SetSliderValues(10, 150, 0.1)
        wSlider:SetValue(style.iconWidth or style.buttonSize or ST.BUTTON_SIZE)
        wSlider:SetFullWidth(true)
        wSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.iconWidth = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(wSlider)

        local hSlider = AceGUI:Create("Slider")
        hSlider:SetLabel("Icon Height")
        hSlider:SetSliderValues(10, 150, 0.1)
        hSlider:SetValue(style.iconHeight or style.buttonSize or ST.BUTTON_SIZE)
        hSlider:SetFullWidth(true)
        hSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.iconHeight = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(hSlider)
    end

    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(style.borderSize or ST.DEFAULT_BORDER_SIZE)
    borderSlider:SetFullWidth(true)
    if group.masqueEnabled then
        borderSlider:SetDisabled(true)
    end
    borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.borderSize = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderSlider)

    if group.buttons and #group.buttons > 1 then
        local spacingSlider = AceGUI:Create("Slider")
        spacingSlider:SetLabel("Button Spacing")
        spacingSlider:SetSliderValues(0, 10, 0.1)
        spacingSlider:SetValue(style.buttonSpacing or ST.BUTTON_SPACING)
        spacingSlider:SetFullWidth(true)
        spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSpacing = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(spacingSlider)
    end
    end -- not iconSettingsCollapsed

    -- Show Cooldown Text toggle
    local cdTextCb = AceGUI:Create("CheckBox")
    cdTextCb:SetLabel("Show Cooldown Text")
    cdTextCb:SetValue(style.showCooldownText or false)
    cdTextCb:SetFullWidth(true)
    cdTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showCooldownText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(cdTextCb)

    local cdTextAdvExpanded, cdTextAdvBtn = AddAdvancedToggle(cdTextCb, "cooldownText", tabInfoButtons, style.showCooldownText)
    CreateCheckboxPromoteButton(cdTextCb, cdTextAdvBtn, "cooldownText", group, style)

    if cdTextAdvExpanded and style.showCooldownText then
        local fontSizeSlider = AceGUI:Create("Slider")
        fontSizeSlider:SetLabel("Font Size")
        fontSizeSlider:SetSliderValues(8, 32, 1)
        fontSizeSlider:SetValue(style.cooldownFontSize or 12)
        fontSizeSlider:SetFullWidth(true)
        fontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(fontSizeSlider)

        local fontDrop = AceGUI:Create("Dropdown")
        fontDrop:SetLabel("Font")
        CS.SetupFontDropdown(fontDrop)
        fontDrop:SetValue(style.cooldownFont or "Friz Quadrata TT")
        fontDrop:SetFullWidth(true)
        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(fontDrop)

        local outlineDrop = AceGUI:Create("Dropdown")
        outlineDrop:SetLabel("Font Outline")
        outlineDrop:SetList(CS.outlineOptions)
        outlineDrop:SetValue(style.cooldownFontOutline or "OUTLINE")
        outlineDrop:SetFullWidth(true)
        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(outlineDrop)

        local cdFontColor = AceGUI:Create("ColorPicker")
        cdFontColor:SetLabel("Font Color")
        cdFontColor:SetHasAlpha(false)
        local cdc = style.cooldownFontColor or {1, 1, 1, 1}
        cdFontColor:SetColor(cdc[1], cdc[2], cdc[3], cdc[4])
        cdFontColor:SetFullWidth(true)
        cdFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        cdFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdFontColor)

        local cdAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            cdAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local cdAnchorDrop = AceGUI:Create("Dropdown")
        cdAnchorDrop:SetLabel("Anchor")
        cdAnchorDrop:SetList(cdAnchorValues, CS.anchorPoints)
        cdAnchorDrop:SetValue(style.cooldownTextAnchor or "CENTER")
        cdAnchorDrop:SetFullWidth(true)
        cdAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownTextAnchor = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdAnchorDrop)

        -- (?) tooltip for shared positioning
        CreateInfoButton(cdAnchorDrop.frame, cdAnchorDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Shared Position",
            {"Position is shared with Aura Duration Text by default. Enable 'Separate Text Positions' in the Aura Duration Text section to use independent positions.", 1, 1, 1, true},
        }, cdAnchorDrop)

        local cdXSlider = AceGUI:Create("Slider")
        cdXSlider:SetLabel("X Offset")
        cdXSlider:SetSliderValues(-20, 20, 0.1)
        cdXSlider:SetValue(style.cooldownTextXOffset or 0)
        cdXSlider:SetFullWidth(true)
        cdXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownTextXOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdXSlider)

        local cdYSlider = AceGUI:Create("Slider")
        cdYSlider:SetLabel("Y Offset")
        cdYSlider:SetSliderValues(-20, 20, 0.1)
        cdYSlider:SetValue(style.cooldownTextYOffset or 0)
        cdYSlider:SetFullWidth(true)
        cdYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownTextYOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdYSlider)

    end -- cdTextAdvExpanded + showCooldownText

    -- Show Charge Text toggle
    local chargeTextCb = AceGUI:Create("CheckBox")
    chargeTextCb:SetLabel("Show Charge Text")
    chargeTextCb:SetValue(style.showChargeText ~= false)
    chargeTextCb:SetFullWidth(true)
    chargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showChargeText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(chargeTextCb)

    local chargeAdvExpanded, chargeAdvBtn = AddAdvancedToggle(chargeTextCb, "chargeText", tabInfoButtons, style.showChargeText ~= false)
    CreateCheckboxPromoteButton(chargeTextCb, chargeAdvBtn, "chargeText", group, style)

    if chargeAdvExpanded and style.showChargeText ~= false then
        local chargeFontSizeSlider = AceGUI:Create("Slider")
        chargeFontSizeSlider:SetLabel("Font Size")
        chargeFontSizeSlider:SetSliderValues(8, 32, 1)
        chargeFontSizeSlider:SetValue(style.chargeFontSize or 12)
        chargeFontSizeSlider:SetFullWidth(true)
        chargeFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontSizeSlider)

        local chargeFontDrop = AceGUI:Create("Dropdown")
        chargeFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(chargeFontDrop)
        chargeFontDrop:SetValue(style.chargeFont or "Friz Quadrata TT")
        chargeFontDrop:SetFullWidth(true)
        chargeFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontDrop)

        local chargeOutlineDrop = AceGUI:Create("Dropdown")
        chargeOutlineDrop:SetLabel("Font Outline")
        chargeOutlineDrop:SetList(CS.outlineOptions)
        chargeOutlineDrop:SetValue(style.chargeFontOutline or "OUTLINE")
        chargeOutlineDrop:SetFullWidth(true)
        chargeOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeOutlineDrop)

        local chargeFontColor = AceGUI:Create("ColorPicker")
        chargeFontColor:SetLabel("Font Color (Max Charges)")
        chargeFontColor:SetHasAlpha(true)
        local cfc = style.chargeFontColor or {1, 1, 1, 1}
        chargeFontColor:SetColor(cfc[1], cfc[2], cfc[3], cfc[4])
        chargeFontColor:SetFullWidth(true)
        chargeFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.chargeFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        chargeFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.chargeFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontColor)

        local chargeFontColorMissing = AceGUI:Create("ColorPicker")
        chargeFontColorMissing:SetLabel("Font Color (Missing Charges)")
        chargeFontColorMissing:SetHasAlpha(true)
        local cfcm = style.chargeFontColorMissing or {1, 1, 1, 1}
        chargeFontColorMissing:SetColor(cfcm[1], cfcm[2], cfcm[3], cfcm[4])
        chargeFontColorMissing:SetFullWidth(true)
        chargeFontColorMissing:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.chargeFontColorMissing = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        chargeFontColorMissing:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.chargeFontColorMissing = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontColorMissing)

        local chargeFontColorZero = AceGUI:Create("ColorPicker")
        chargeFontColorZero:SetLabel("Font Color (Zero Charges)")
        chargeFontColorZero:SetHasAlpha(true)
        local cfcz = style.chargeFontColorZero or {1, 1, 1, 1}
        chargeFontColorZero:SetColor(cfcz[1], cfcz[2], cfcz[3], cfcz[4])
        chargeFontColorZero:SetFullWidth(true)
        chargeFontColorZero:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.chargeFontColorZero = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        chargeFontColorZero:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.chargeFontColorZero = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontColorZero)

        local chargeAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            chargeAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local chargeAnchorDrop = AceGUI:Create("Dropdown")
        chargeAnchorDrop:SetLabel("Anchor")
        chargeAnchorDrop:SetList(chargeAnchorValues, CS.anchorPoints)
        chargeAnchorDrop:SetValue(style.chargeAnchor or "BOTTOMRIGHT")
        chargeAnchorDrop:SetFullWidth(true)
        chargeAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeAnchor = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeAnchorDrop)

        local chargeXSlider = AceGUI:Create("Slider")
        chargeXSlider:SetLabel("X Offset")
        chargeXSlider:SetSliderValues(-20, 20, 0.1)
        chargeXSlider:SetValue(style.chargeXOffset or -2)
        chargeXSlider:SetFullWidth(true)
        chargeXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeXOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeXSlider)

        local chargeYSlider = AceGUI:Create("Slider")
        chargeYSlider:SetLabel("Y Offset")
        chargeYSlider:SetSliderValues(-20, 20, 0.1)
        chargeYSlider:SetValue(style.chargeYOffset or 2)
        chargeYSlider:SetFullWidth(true)
        chargeYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeYOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeYSlider)
    end -- chargeAdvExpanded + showChargeText

    -- Show Aura Duration Text toggle
    local auraTextCb = AceGUI:Create("CheckBox")
    auraTextCb:SetLabel("Show Aura Duration Text")
    auraTextCb:SetValue(style.showAuraText ~= false)
    auraTextCb:SetFullWidth(true)
    auraTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showAuraText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraTextCb)

    local auraTextAdvExpanded, auraTextAdvBtn = AddAdvancedToggle(auraTextCb, "auraText", tabInfoButtons, style.showAuraText ~= false)
    local auraTextPromoteBtn = CreateCheckboxPromoteButton(auraTextCb, auraTextAdvBtn, "auraText", group, style)

    local auraPosInfo = CreateInfoButton(auraTextCb.frame, auraTextPromoteBtn, "LEFT", "RIGHT", 4, 0, {
        "Shared Position",
        {"Position is shared with Cooldown Text by default. Enable 'Separate Text Positions' in advanced settings to use independent positions.", 1, 1, 1, true},
    }, auraTextCb)
    if style.showAuraText == false then
        auraPosInfo:Hide()
    end

    if style.showAuraText ~= false and auraTextAdvExpanded then
        local auraFontSizeSlider = AceGUI:Create("Slider")
        auraFontSizeSlider:SetLabel("Font Size")
        auraFontSizeSlider:SetSliderValues(8, 32, 1)
        auraFontSizeSlider:SetValue(style.auraTextFontSize or 12)
        auraFontSizeSlider:SetFullWidth(true)
        auraFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontSizeSlider)

        local auraFontDrop = AceGUI:Create("Dropdown")
        auraFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(auraFontDrop)
        auraFontDrop:SetValue(style.auraTextFont or "Friz Quadrata TT")
        auraFontDrop:SetFullWidth(true)
        auraFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontDrop)

        local auraOutlineDrop = AceGUI:Create("Dropdown")
        auraOutlineDrop:SetLabel("Font Outline")
        auraOutlineDrop:SetList(CS.outlineOptions)
        auraOutlineDrop:SetValue(style.auraTextFontOutline or "OUTLINE")
        auraOutlineDrop:SetFullWidth(true)
        auraOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraOutlineDrop)

        local auraFontColor = AceGUI:Create("ColorPicker")
        auraFontColor:SetLabel("Font Color")
        auraFontColor:SetHasAlpha(false)
        local ac = style.auraTextFontColor or {0, 0.925, 1, 1}
        auraFontColor:SetColor(ac[1], ac[2], ac[3], ac[4])
        auraFontColor:SetFullWidth(true)
        auraFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.auraTextFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        auraFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.auraTextFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontColor)

        local sepPosCb = AceGUI:Create("CheckBox")
        sepPosCb:SetLabel("Separate Text Positions")
        sepPosCb:SetValue(style.separateTextPositions or false)
        sepPosCb:SetFullWidth(true)
        sepPosCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.separateTextPositions = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(sepPosCb)

        CreateInfoButton(sepPosCb.frame, sepPosCb.checkbg, "LEFT", "RIGHT", sepPosCb.text:GetStringWidth() + 4, 0, {
            "Separate Text Positions",
            {"When enabled, aura duration text and cooldown text use independent positions. Aura text position controls appear below when toggled on; cooldown text position is in the Cooldown Text section.", 1, 1, 1, true},
        }, sepPosCb)

        if style.separateTextPositions then
            local atAnchorValues = {}
            for _, pt in ipairs(CS.anchorPoints) do
                atAnchorValues[pt] = CS.anchorPointLabels[pt]
            end
            local atAnchorDrop = AceGUI:Create("Dropdown")
            atAnchorDrop:SetLabel("Anchor")
            atAnchorDrop:SetList(atAnchorValues, CS.anchorPoints)
            atAnchorDrop:SetValue(style.auraTextAnchor or "TOPLEFT")
            atAnchorDrop:SetFullWidth(true)
            atAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
                style.auraTextAnchor = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            container:AddChild(atAnchorDrop)

            local atXSlider = AceGUI:Create("Slider")
            atXSlider:SetLabel("X Offset")
            atXSlider:SetSliderValues(-20, 20, 0.1)
            atXSlider:SetValue(style.auraTextXOffset or 2)
            atXSlider:SetFullWidth(true)
            atXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.auraTextXOffset = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            container:AddChild(atXSlider)

            local atYSlider = AceGUI:Create("Slider")
            atYSlider:SetLabel("Y Offset")
            atYSlider:SetSliderValues(-20, 20, 0.1)
            atYSlider:SetValue(style.auraTextYOffset or -2)
            atYSlider:SetFullWidth(true)
            atYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.auraTextYOffset = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            container:AddChild(atYSlider)
        end
    end -- auraTextAdvExpanded + showAuraText

    -- Show Aura Stack Text toggle
    local auraStackCb = AceGUI:Create("CheckBox")
    auraStackCb:SetLabel("Show Aura Stack Text")
    auraStackCb:SetValue(style.showAuraStackText ~= false)
    auraStackCb:SetFullWidth(true)
    auraStackCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showAuraStackText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraStackCb)

    local auraStackAdvExpanded, auraStackAdvBtn = AddAdvancedToggle(auraStackCb, "auraStackText", tabInfoButtons, style.showAuraStackText ~= false)
    CreateCheckboxPromoteButton(auraStackCb, auraStackAdvBtn, "auraStackText", group, style)

    if style.showAuraStackText ~= false and auraStackAdvExpanded then
        local asFontSizeSlider = AceGUI:Create("Slider")
        asFontSizeSlider:SetLabel("Font Size")
        asFontSizeSlider:SetSliderValues(8, 32, 1)
        asFontSizeSlider:SetValue(style.auraStackFontSize or 12)
        asFontSizeSlider:SetFullWidth(true)
        asFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asFontSizeSlider)

        local asFontDrop = AceGUI:Create("Dropdown")
        asFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(asFontDrop)
        asFontDrop:SetValue(style.auraStackFont or "Friz Quadrata TT")
        asFontDrop:SetFullWidth(true)
        asFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asFontDrop)

        local asOutlineDrop = AceGUI:Create("Dropdown")
        asOutlineDrop:SetLabel("Font Outline")
        asOutlineDrop:SetList(CS.outlineOptions)
        asOutlineDrop:SetValue(style.auraStackFontOutline or "OUTLINE")
        asOutlineDrop:SetFullWidth(true)
        asOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asOutlineDrop)

        local asFontColor = AceGUI:Create("ColorPicker")
        asFontColor:SetLabel("Font Color")
        asFontColor:SetHasAlpha(true)
        local asc = style.auraStackFontColor or {1, 1, 1, 1}
        asFontColor:SetColor(asc[1], asc[2], asc[3], asc[4])
        asFontColor:SetFullWidth(true)
        asFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.auraStackFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        asFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.auraStackFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asFontColor)

        local asAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            asAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local asAnchorDrop = AceGUI:Create("Dropdown")
        asAnchorDrop:SetLabel("Anchor")
        asAnchorDrop:SetList(asAnchorValues, CS.anchorPoints)
        asAnchorDrop:SetValue(style.auraStackAnchor or "BOTTOMLEFT")
        asAnchorDrop:SetFullWidth(true)
        asAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackAnchor = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asAnchorDrop)

        local asXSlider = AceGUI:Create("Slider")
        asXSlider:SetLabel("X Offset")
        asXSlider:SetSliderValues(-20, 20, 0.1)
        asXSlider:SetValue(style.auraStackXOffset or 2)
        asXSlider:SetFullWidth(true)
        asXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackXOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asXSlider)

        local asYSlider = AceGUI:Create("Slider")
        asYSlider:SetLabel("Y Offset")
        asYSlider:SetSliderValues(-20, 20, 0.1)
        asYSlider:SetValue(style.auraStackYOffset or 2)
        asYSlider:SetFullWidth(true)
        asYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraStackYOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(asYSlider)
    end -- auraStackAdvExpanded + showAuraStackText

    -- Show Keybind Text toggle
    local kbCb = AceGUI:Create("CheckBox")
    kbCb:SetLabel("Show Keybind Text")
    kbCb:SetValue(style.showKeybindText or false)
    kbCb:SetFullWidth(true)
    kbCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showKeybindText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(kbCb)

    local kbAdvExpanded, kbAdvBtn = AddAdvancedToggle(kbCb, "keybindText", tabInfoButtons, style.showKeybindText)
    CreateCheckboxPromoteButton(kbCb, kbAdvBtn, "keybindText", group, style)

    if style.showKeybindText and kbAdvExpanded then
        local kbAnchorDrop = AceGUI:Create("Dropdown")
        kbAnchorDrop:SetLabel("Anchor")
        kbAnchorDrop:SetList({
            TOPRIGHT = "Top Right",
            TOPLEFT = "Top Left",
            BOTTOMRIGHT = "Bottom Right",
            BOTTOMLEFT = "Bottom Left",
        })
        kbAnchorDrop:SetValue(style.keybindAnchor or "TOPRIGHT")
        kbAnchorDrop:SetFullWidth(true)
        kbAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindAnchor = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbAnchorDrop)

        local kbXSlider = AceGUI:Create("Slider")
        kbXSlider:SetLabel("X Offset")
        kbXSlider:SetSliderValues(-20, 20, 0.1)
        kbXSlider:SetValue(style.keybindXOffset or -2)
        kbXSlider:SetFullWidth(true)
        kbXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindXOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbXSlider)

        local kbYSlider = AceGUI:Create("Slider")
        kbYSlider:SetLabel("Y Offset")
        kbYSlider:SetSliderValues(-20, 20, 0.1)
        kbYSlider:SetValue(style.keybindYOffset or -2)
        kbYSlider:SetFullWidth(true)
        kbYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindYOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbYSlider)

        local kbFontSizeSlider = AceGUI:Create("Slider")
        kbFontSizeSlider:SetLabel("Font Size")
        kbFontSizeSlider:SetSliderValues(6, 24, 1)
        kbFontSizeSlider:SetValue(style.keybindFontSize or 10)
        kbFontSizeSlider:SetFullWidth(true)
        kbFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbFontSizeSlider)

        local kbFontDrop = AceGUI:Create("Dropdown")
        kbFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(kbFontDrop)
        kbFontDrop:SetValue(style.keybindFont or "Friz Quadrata TT")
        kbFontDrop:SetFullWidth(true)
        kbFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbFontDrop)

        local kbOutlineDrop = AceGUI:Create("Dropdown")
        kbOutlineDrop:SetLabel("Font Outline")
        kbOutlineDrop:SetList(CS.outlineOptions)
        kbOutlineDrop:SetValue(style.keybindFontOutline or "OUTLINE")
        kbOutlineDrop:SetFullWidth(true)
        kbOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbOutlineDrop)

        local kbFontColor = AceGUI:Create("ColorPicker")
        kbFontColor:SetLabel("Font Color")
        kbFontColor:SetHasAlpha(true)
        local kbc = style.keybindFontColor or {1, 1, 1, 1}
        kbFontColor:SetColor(kbc[1], kbc[2], kbc[3], kbc[4])
        kbFontColor:SetFullWidth(true)
        kbFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.keybindFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        kbFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.keybindFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbFontColor)
    end -- showKeybindText + kbAdvExpanded

    -- Compact Mode toggle + Max Visible Buttons slider
    BuildCompactModeControls(container, group, tabInfoButtons)

    -- Border heading
    local borderHeading = AceGUI:Create("Heading")
    borderHeading:SetText("Border")
    ColorHeading(borderHeading)
    borderHeading:SetFullWidth(true)
    container:AddChild(borderHeading)

    local borderCollapsed = CS.collapsedSections["appearance_border"]
    AttachCollapseButton(borderHeading, borderCollapsed, function()
        CS.collapsedSections["appearance_border"] = not CS.collapsedSections["appearance_border"]
        CooldownCompanion:RefreshConfigPanel()
    end)
    CreatePromoteButton(borderHeading, "borderSettings", CS.selectedButton and group.buttons[CS.selectedButton], style)

    if not borderCollapsed then
    local borderColor = AceGUI:Create("ColorPicker")
    borderColor:SetLabel("Border Color")
    borderColor:SetHasAlpha(true)
    local bc = style.borderColor or {0, 0, 0, 1}
    borderColor:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColor:SetFullWidth(true)
    if group.masqueEnabled then
        borderColor:SetDisabled(true)
    end
    borderColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    borderColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderColor)
    end -- not borderCollapsed

    -- Masque skinning (icon-only)
    if CooldownCompanion.Masque then
        local masqueHeading = AceGUI:Create("Heading")
        masqueHeading:SetText("Masque")
        ColorHeading(masqueHeading)
        masqueHeading:SetFullWidth(true)
        container:AddChild(masqueHeading)

        local masqueCollapsed = CS.collapsedSections["appearance_masque"]
        AttachCollapseButton(masqueHeading, masqueCollapsed, function()
            CS.collapsedSections["appearance_masque"] = not CS.collapsedSections["appearance_masque"]
            CooldownCompanion:RefreshConfigPanel()
        end)

        if not masqueCollapsed then
        local masqueCb = AceGUI:Create("CheckBox")
        masqueCb:SetLabel("Enable Masque Skinning")
        masqueCb:SetValue(group.masqueEnabled or false)
        masqueCb:SetFullWidth(true)
        masqueCb:SetCallback("OnValueChanged", function(widget, event, val)
            CooldownCompanion:ToggleGroupMasque(CS.selectedGroup, val)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(masqueCb)

        CreateInfoButton(masqueCb.frame, masqueCb.checkbg, "LEFT", "RIGHT", masqueCb.text:GetStringWidth() + 4, 0, {
            "Masque Skinning",
            {"Uses the Masque addon to apply custom button skins to this group. Configure skins via /masque or the Masque config panel.", 1, 1, 1, true},
            " ",
            {"Overridden Settings:", 1, 0.82, 0},
            {"Border Size, Border Color, Square Icons (forced on)", 0.7, 0.7, 0.7, true},
        }, tabInfoButtons)
        end -- not masqueCollapsed
    end

    BuildGroupSettingPresetControls(container, group, "icons", tabInfoButtons)

    -- Apply "Hide CDC Tooltips" to tab info buttons (skip advanced toggles)
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            if not btn._isAdvancedToggle then btn:Hide() end
        end
    end
end

------------------------------------------------------------------------
-- CONTAINER TAB BUILDERS (for groupContainers settings in Column 4)
------------------------------------------------------------------------

local function BuildContainerGeneralTab(scroll, containerId)
    local db = CooldownCompanion.db.profile
    local container = db.groupContainers and db.groupContainers[containerId]
    if not container then return end

    local function RefreshPanels()
        CooldownCompanion:RefreshContainerPanels(containerId)
    end

    -- Enabled
    local enabledCb = AceGUI:Create("CheckBox")
    enabledCb:SetLabel("Enabled")
    enabledCb:SetFullWidth(true)
    enabledCb:SetValue(container.enabled ~= false)
    enabledCb:SetCallback("OnValueChanged", function(widget, event, value)
        container.enabled = value
        RefreshPanels()
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(enabledCb)

    -- Locked
    local lockedCb = AceGUI:Create("CheckBox")
    lockedCb:SetLabel("Locked")
    lockedCb:SetFullWidth(true)
    lockedCb:SetValue(container.locked == true)
    lockedCb:SetCallback("OnValueChanged", function(widget, event, value)
        container.locked = value
        CooldownCompanion:UpdateContainerDragHandle(containerId, value)
        RefreshPanels()
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(lockedCb)

    -- ================================================================
    -- Layout
    -- ================================================================
    local layoutHeading = AceGUI:Create("Heading")
    layoutHeading:SetText("Layout")
    ColorHeading(layoutHeading)
    layoutHeading:SetFullWidth(true)
    scroll:AddChild(layoutHeading)

    local layoutCollapsed = CS.collapsedSections["container_layout"]
    AttachCollapseButton(layoutHeading, layoutCollapsed, function()
        CS.collapsedSections["container_layout"] = not CS.collapsedSections["container_layout"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not layoutCollapsed then

    -- ================================================================
    -- Anchor to Frame (editbox + pick button row)
    -- ================================================================
    local anchorRow = AceGUI:Create("SimpleGroup")
    anchorRow:SetFullWidth(true)
    anchorRow:SetLayout("Flow")

    local anchorBox = AceGUI:Create("EditBox")
    if anchorBox.editbox.Instructions then anchorBox.editbox.Instructions:Hide() end
    anchorBox:SetLabel("Anchor to Frame")
    local currentAnchor = container.anchor.relativeTo
    if currentAnchor == "UIParent" then currentAnchor = "" end
    anchorBox:SetText(currentAnchor)
    anchorBox:SetRelativeWidth(0.68)
    anchorBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if text == "" then
            local wasAnchored = container.anchor.relativeTo and container.anchor.relativeTo ~= "UIParent"
            if wasAnchored then
                container.anchor = {
                    point = "CENTER",
                    relativeTo = "UIParent",
                    relativePoint = "CENTER",
                    x = 0,
                    y = 0,
                }
            else
                container.anchor.relativeTo = "UIParent"
            end
        else
            local targetFrame = _G[text]
            if not targetFrame then
                CooldownCompanion:Print("Frame '" .. text .. "' not found.")
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            container.anchor.relativeTo = text
        end
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
        if containerFrame then
            CooldownCompanion:AnchorContainerFrame(containerFrame, container.anchor)
        end
        RefreshPanels()
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
                container.anchor = {
                    point = "TOPLEFT",
                    relativeTo = name,
                    relativePoint = "BOTTOMLEFT",
                    x = 0,
                    y = -5,
                }
                local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
                if containerFrame then
                    CooldownCompanion:AnchorContainerFrame(containerFrame, container.anchor)
                end
                RefreshPanels()
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
    end)
    anchorRow:AddChild(pickBtn)

    scroll:AddChild(anchorRow)
    pickBtn.frame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local p, rel, rp, xOfs, yOfs = self:GetPoint(1)
        if yOfs then
            self:SetPoint(p, rel, rp, xOfs, yOfs - 2)
        end
    end)

    -- Anchor Point dropdown
    local pointValues = {}
    for _, pt in ipairs(CS.anchorPoints) do
        pointValues[pt] = CS.anchorPointLabels[pt]
    end

    local anchorPt = AceGUI:Create("Dropdown")
    anchorPt:SetLabel("Anchor Point")
    anchorPt:SetList(pointValues)
    anchorPt:SetValue(container.anchor.point or "CENTER")
    anchorPt:SetFullWidth(true)
    anchorPt:SetCallback("OnValueChanged", function(widget, event, val)
        container.anchor.point = val
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
        if containerFrame then
            CooldownCompanion:AnchorContainerFrame(containerFrame, container.anchor)
        end
    end)
    scroll:AddChild(anchorPt)

    -- Relative Point dropdown
    local relPt = AceGUI:Create("Dropdown")
    relPt:SetLabel("Relative Point")
    relPt:SetList(pointValues)
    relPt:SetValue(container.anchor.relativePoint or "CENTER")
    relPt:SetFullWidth(true)
    relPt:SetCallback("OnValueChanged", function(widget, event, val)
        container.anchor.relativePoint = val
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
        if containerFrame then
            CooldownCompanion:AnchorContainerFrame(containerFrame, container.anchor)
        end
    end)
    scroll:AddChild(relPt)

    -- Allow decimal input from editbox while keeping slider/wheel at 1px steps
    local function HookSliderEditBox(sliderWidget)
        sliderWidget.editbox:SetScript("OnEnterPressed", function(editbox)
            local widget = editbox.obj
            local value = tonumber(editbox:GetText())
            if value then
                value = math.floor(value * 10 + 0.5) / 10
                value = math.max(widget.min, math.min(widget.max, value))
                PlaySound(856)
                widget:SetValue(value)
                widget:Fire("OnValueChanged", value)
                widget:Fire("OnMouseUp", value)
            end
        end)
    end

    -- X Offset
    local xSlider = AceGUI:Create("Slider")
    xSlider:SetLabel("X Offset")
    xSlider:SetSliderValues(-2000, 2000, 0.1)
    xSlider:SetValue(container.anchor.x or 0)
    xSlider:SetFullWidth(true)
    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
        container.anchor.x = val
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
        if containerFrame then
            CooldownCompanion:AnchorContainerFrame(containerFrame, container.anchor)
        end
    end)
    HookSliderEditBox(xSlider)
    scroll:AddChild(xSlider)

    -- Y Offset
    local ySlider = AceGUI:Create("Slider")
    ySlider:SetLabel("Y Offset")
    ySlider:SetSliderValues(-2000, 2000, 0.1)
    ySlider:SetValue(container.anchor.y or 0)
    ySlider:SetFullWidth(true)
    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
        container.anchor.y = val
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
        if containerFrame then
            CooldownCompanion:AnchorContainerFrame(containerFrame, container.anchor)
        end
    end)
    HookSliderEditBox(ySlider)
    scroll:AddChild(ySlider)

    end -- if not layoutCollapsed

    -- ================================================================
    -- Frame Strata
    -- ================================================================
    local strataHeading = AceGUI:Create("Heading")
    strataHeading:SetText("Frame Strata")
    strataHeading:SetFullWidth(true)
    scroll:AddChild(strataHeading)

    local strataCollapsed = CS.collapsedSections["container_strata"]
    AttachCollapseButton(strataHeading, strataCollapsed, function()
        CS.collapsedSections["container_strata"] = not CS.collapsedSections["container_strata"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not strataCollapsed then
    local strataOptions = {
        ["BACKGROUND"] = "Background",
        ["LOW"] = "Low",
        ["MEDIUM"] = "Medium (Default)",
        ["HIGH"] = "High",
    }
    local strataDrop = AceGUI:Create("Dropdown")
    strataDrop:SetLabel("Container Frame Strata")
    strataDrop:SetList(strataOptions)
    strataDrop:SetValue(container.frameStrata or "MEDIUM")
    strataDrop:SetFullWidth(true)
    strataDrop:SetCallback("OnValueChanged", function(widget, event, value)
        container.frameStrata = value
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
        if containerFrame then
            containerFrame:SetFrameStrata(value)
        end
        RefreshPanels()
    end)
    scroll:AddChild(strataDrop)
    end -- if not strataCollapsed
end

local function BuildContainerLoadConditionsTab(scroll, containerId)
    local db = CooldownCompanion.db.profile
    local container = db.groupContainers and db.groupContainers[containerId]
    if not container then return end

    local function RefreshPanels()
        CooldownCompanion:RefreshContainerPanels(containerId)
    end

    if not container.loadConditions then
        container.loadConditions = {}
    end
    local loadConditions = container.loadConditions

    local function CreateLoadConditionToggle(label, key, defaultVal)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        local val = loadConditions[key]
        if val == nil then val = defaultVal or false end
        cb:SetValue(val)
        cb:SetFullWidth(true)
        cb:SetCallback("OnValueChanged", function(widget, event, newVal)
            loadConditions[key] = newVal
            RefreshPanels()
            CooldownCompanion:RefreshConfigPanel()
        end)
        return cb
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Do Not Load When In")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local instanceCollapsed = CS.collapsedSections["container_loadconditions_instance"]
    AttachCollapseButton(heading, instanceCollapsed, function()
        CS.collapsedSections["container_loadconditions_instance"] = not CS.collapsedSections["container_loadconditions_instance"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not instanceCollapsed then
    local conditions = {
        { key = "raid",          label = "Raid" },
        { key = "dungeon",       label = "Dungeon" },
        { key = "delve",         label = "Delve" },
        { key = "battleground",  label = "Battleground" },
        { key = "arena",         label = "Arena" },
        { key = "openWorld",     label = "Open World" },
        { key = "rested",        label = "Rested Area" },
        { key = "petBattle",     label = "Pet Battle", default = true },
        { key = "vehicleUI",     label = "Vehicle / Override UI", default = true },
    }

    for _, cond in ipairs(conditions) do
        scroll:AddChild(CreateLoadConditionToggle(cond.label, cond.key, cond.default))
    end
    end -- not instanceCollapsed

    -- Spec filter section
    local specHeading = AceGUI:Create("Heading")
    specHeading:SetText("Specialization Filter")
    ColorHeading(specHeading)
    specHeading:SetFullWidth(true)
    scroll:AddChild(specHeading)

    local specCollapsed = CS.collapsedSections["container_loadconditions_spec"]
    AttachCollapseButton(specHeading, specCollapsed, function()
        CS.collapsedSections["container_loadconditions_spec"] = not CS.collapsedSections["container_loadconditions_spec"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not specCollapsed then
    -- Folder spec inheritance: folder-level spec/hero filters are shown as
    -- disabled (locked) on child containers, but children can still toggle
    -- specs that the folder does NOT set.
    local folder = container.folderId and db.folders and db.folders[container.folderId]
    local folderSpecs = folder and folder.specs
    local folderHeroTalents = folder and folder.heroTalents
    local hasFolderSpecs = folderSpecs and next(folderSpecs)

    -- Effective specs for hero talent rendering (union of folder + container specs)
    local effectiveSpecs
    if folderSpecs or container.specs then
        effectiveSpecs = {}
        if folderSpecs then for k in pairs(folderSpecs) do effectiveSpecs[k] = true end end
        if container.specs then for k in pairs(container.specs) do effectiveSpecs[k] = true end end
        if not next(effectiveSpecs) then effectiveSpecs = nil end
    end

    if hasFolderSpecs then
        local inheritedLabel = AceGUI:Create("Label")
        inheritedLabel:SetText("|cff888888Specs set by the parent folder cannot be changed here.|r")
        inheritedLabel:SetFullWidth(true)
        scroll:AddChild(inheritedLabel)
    end

    local numSpecs = GetNumSpecializations()
    local configID = C_ClassTalents.GetActiveConfigID()
    for i = 1, numSpecs do
        local specId, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
        if specId then
            local lockedByFolder = folderSpecs and folderSpecs[specId]
            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel(name)
            if icon then cb:SetImage(icon, 0.08, 0.92, 0.08, 0.92) end
            cb:SetFullWidth(true)
            cb:SetValue(lockedByFolder or (container.specs and container.specs[specId]) or false)
            if hasFolderSpecs then
                cb:SetDisabled(true)
            else
                cb:SetCallback("OnValueChanged", function(widget, event, value)
                    if value then
                        if not container.specs then container.specs = {} end
                        container.specs[specId] = true
                    else
                        if container.specs then
                            container.specs[specId] = nil
                            if not next(container.specs) then
                                container.specs = nil
                            end
                        end
                        CooldownCompanion:CleanHeroTalentsForSpec(container, specId)
                    end
                    RefreshPanels()
                    CooldownCompanion:RefreshConfigPanel()
                end)
            end
            scroll:AddChild(cb)

            -- Hero talent sub-tree checkboxes
            local specActive = lockedByFolder or (container.specs and container.specs[specId])
            if configID and specActive then
                local htOpts
                if folderHeroTalents and next(folderHeroTalents) then
                    htOpts = {
                        heroTalentsSource = folderHeroTalents,
                        useHeroTalentsSource = true,
                        disableToggles = true,
                        specsSource = effectiveSpecs,
                    }
                else
                    htOpts = {
                        heroTalentsSource = container.heroTalents,
                        specsSource = effectiveSpecs,
                        onChanged = function()
                            RefreshPanels()
                            CooldownCompanion:RefreshConfigPanel()
                        end,
                    }
                end
                ST._BuildHeroTalentSubTreeCheckboxes(scroll, container, configID, specId, 20, containerId, htOpts)
            end
        end
    end

    -- Only show Clear All when container has specs/hero-talents beyond folder cascade
    local hasOwnSpecs = false
    if container.specs then
        for specId in pairs(container.specs) do
            if not (folderSpecs and folderSpecs[specId]) then
                hasOwnSpecs = true
                break
            end
        end
    end
    if not hasOwnSpecs and container.heroTalents and next(container.heroTalents) then
        hasOwnSpecs = true
    end
    if hasOwnSpecs then
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear All Spec Filters")
        clearBtn:SetFullWidth(true)
        clearBtn:SetCallback("OnClick", function()
            if folderSpecs then
                container.specs = CopyTable(folderSpecs)
            else
                container.specs = nil
            end
            container.heroTalents = nil
            RefreshPanels()
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(clearBtn)
    end
    end -- not specCollapsed
end

-- Expose for Config.lua
ST._BuildLayoutTab = BuildLayoutTab
ST._BuildAppearanceTab = BuildAppearanceTab
ST._BuildEffectsTab = BuildEffectsTab
ST._BuildContainerGeneralTab = BuildContainerGeneralTab
ST._BuildContainerLoadConditionsTab = BuildContainerLoadConditionsTab
