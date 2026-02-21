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
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildBarColorsControls = ST._BuildBarColorsControls
local BuildBarNameTextControls = ST._BuildBarNameTextControls
local BuildBarReadyTextControls = ST._BuildBarReadyTextControls

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

-- Imports from BarModeTabs.lua
local BuildBarAppearanceTab = ST._BuildBarAppearanceTab
local BuildBarEffectsTab = ST._BuildBarEffectsTab

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
    anchorBox:SetLabel("Anchor to Frame")
    local currentAnchor = group.anchor.relativeTo
    if currentAnchor == "UIParent" then currentAnchor = "" end
    anchorBox:SetText(currentAnchor)
    anchorBox:SetRelativeWidth(0.68)
    anchorBox:SetCallback("OnEnterPressed", function(widget, event, text)
        local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= "UIParent"
        if text == "" then
            CooldownCompanion:SetGroupAnchor(CS.selectedGroup, "UIParent", wasAnchored)
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
    local pickInfo = CreateFrame("Button", nil, pickBtn.frame)
    pickInfo:SetSize(16, 16)
    pickInfo:SetPoint("LEFT", pickBtn.frame, "RIGHT", 2, 0)
    local pickInfoIcon = pickInfo:CreateTexture(nil, "OVERLAY")
    pickInfoIcon:SetSize(12, 12)
    pickInfoIcon:SetPoint("CENTER")
    pickInfoIcon:SetAtlas("QuestRepeatableTurnin")
    pickInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Pick Frame")
        GameTooltip:AddLine("Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this group to it, or right-click to cancel.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("You can also type a frame name directly into the editbox.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Middle-click the draggable header to toggle lock/unlock.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pickInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, pickInfo)

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
    if group.displayMode == "bars" then
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
        end)
        container:AddChild(orientDrop)
    end

    -- Buttons Per Row/Column
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

    local alphaInfo = CreateFrame("Button", nil, baseAlphaSlider.frame)
    alphaInfo:SetSize(16, 16)
    alphaInfo:SetPoint("LEFT", baseAlphaSlider.label, "CENTER", baseAlphaSlider.label:GetStringWidth() / 2 + 4, 0)
    local alphaInfoIcon = alphaInfo:CreateTexture(nil, "OVERLAY")
    alphaInfoIcon:SetSize(12, 12)
    alphaInfoIcon:SetPoint("CENTER")
    alphaInfoIcon:SetAtlas("QuestRepeatableTurnin")
    alphaInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Alpha")
        GameTooltip:AddLine("Controls the transparency of this group. Alpha = 1 is fully visible. Alpha = 0 means completely hidden.\n\nThe first three options (In Combat, Out of Combat, Mounted) are 3-way toggles — click to cycle through Disabled, |cff00ff00Fully Visible|r, and |cffff0000Fully Hidden|r.\n\n|cff00ff00Fully Visible|r overrides alpha to 1 when the condition is met.\n\n|cffff0000Fully Hidden|r overrides alpha to 0 when the condition is met.\n\nIf both apply simultaneously, |cff00ff00Fully Visible|r takes priority.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    alphaInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(tabInfoButtons, alphaInfo)

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
        container:AddChild(CreateTriStateToggle("Mounted", "forceAlphaMounted", "forceHideMounted"))

        local mountedActive = group.forceAlphaMounted or group.forceHideMounted
        local isDruid = CooldownCompanion._playerClassID == 11
        if mountedActive and (group.isGlobal or isDruid) then
            local travelVal = group.treatTravelFormAsMounted or false
            local travelCb = AceGUI:Create("CheckBox")
            travelCb:SetLabel("Include Druid Travel Form")
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

        local mouseoverInfo = CreateFrame("Button", nil, mouseoverCb.frame)
        mouseoverInfo:SetSize(16, 16)
        mouseoverInfo:SetPoint("LEFT", mouseoverCb.text, "RIGHT", 4, 0)
        local mouseoverInfoIcon = mouseoverInfo:CreateTexture(nil, "OVERLAY")
        mouseoverInfoIcon:SetSize(12, 12)
        mouseoverInfoIcon:SetPoint("CENTER")
        mouseoverInfoIcon:SetAtlas("QuestRepeatableTurnin")
        mouseoverInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Mouseover")
            GameTooltip:AddLine("When enabled, mousing over the group forces it to full visibility. Like all |cff00ff00Force Visible|r conditions, this overrides |cffff0000Force Hidden|r.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        mouseoverInfo:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        table.insert(tabInfoButtons, mouseoverInfo)

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
    -- ADVANCED: Strata (Layer Order) — hidden for bar mode
    -- ================================================================
    if group.displayMode ~= "bars" then
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
    local customStrataEnabled = type(style.strataOrder) == "table"

    local strataToggle = AceGUI:Create("CheckBox")
    strataToggle:SetLabel("Custom Strata")
    strataToggle:SetValue(customStrataEnabled)
    strataToggle:SetFullWidth(true)
    strataToggle:SetCallback("OnValueChanged", function(widget, event, val)
        if not val then
            style.strataOrder = nil
            CS.pendingStrataOrder = {nil, nil, nil, nil}
            CS.pendingStrataGroup = CS.selectedGroup
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        else
            style.strataOrder = style.strataOrder or {}
            CS.pendingStrataOrder = nil
            CS.InitPendingStrataOrder(CS.selectedGroup)
        end
        if CS.col3Container and CS.col3Container.tabGroup then
            CS.col3Container.tabGroup:SelectTab(CS.selectedTab)
        end
    end)
    container:AddChild(strataToggle)

    local strataInfo = CreateFrame("Button", nil, strataToggle.frame)
    strataInfo:SetSize(16, 16)
    strataInfo:SetPoint("LEFT", strataToggle.checkbg, "RIGHT", strataToggle.text:GetStringWidth() + 4, 0)
    local strataInfoIcon = strataInfo:CreateTexture(nil, "OVERLAY")
    strataInfoIcon:SetSize(12, 12)
    strataInfoIcon:SetPoint("CENTER")
    strataInfoIcon:SetAtlas("QuestRepeatableTurnin")
    strataInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Custom Strata")
        GameTooltip:AddLine("Controls the draw order of overlays on each icon: Cooldown Swipe, Charge Text, Proc Glow, and Assisted Highlight.", 1, 1, 1, true)
        GameTooltip:AddLine("Layer 4 draws on top, Layer 1 on the bottom. When disabled, the default order is used.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    strataInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, strataInfo)

    if customStrataEnabled then
        CS.InitPendingStrataOrder(CS.selectedGroup)

        local strataDropdownList = {}
        for _, key in ipairs(CS.strataElementKeys) do
            strataDropdownList[key] = CS.strataElementLabels[key]
        end

        local strataDropdowns = {}
        for displayIdx = 1, 4 do
            local pos = 5 - displayIdx
            local label
            if pos == 4 then
                label = "Layer 4 (Top)"
            elseif pos == 1 then
                label = "Layer 1 (Bottom)"
            else
                label = "Layer " .. pos
            end

            local drop = AceGUI:Create("Dropdown")
            drop:SetLabel(label)
            drop:SetList(strataDropdownList)
            drop:SetValue(CS.pendingStrataOrder[pos])
            drop:SetFullWidth(true)
            drop:SetCallback("OnValueChanged", function(widget, event, val)
                for i = 1, 4 do
                    if i ~= pos and CS.pendingStrataOrder[i] == val then
                        CS.pendingStrataOrder[i] = nil
                    end
                end
                CS.pendingStrataOrder[pos] = val

                if CS.IsStrataOrderComplete(CS.pendingStrataOrder) then
                    style.strataOrder = {}
                    for i = 1, 4 do
                        style.strataOrder[i] = CS.pendingStrataOrder[i]
                    end
                else
                    style.strataOrder = {}
                end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)

                for i = 1, 4 do
                    if strataDropdowns[i] then
                        strataDropdowns[i]:SetValue(CS.pendingStrataOrder[i])
                    end
                end
            end)
            container:AddChild(drop)
            strataDropdowns[pos] = drop
        end
    end
    end -- not strataCollapsed
    end -- not bars (strata)

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
    BuildProcGlowControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    end -- procAdvExpanded

    -- ================================================================
    -- Active Aura Glow enable toggle
    -- ================================================================
    local auraEnableCb = AceGUI:Create("CheckBox")
    auraEnableCb:SetLabel("Show Active Aura Glow")
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
    BuildAuraIndicatorControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
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
    BuildPandemicGlowControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    end -- pandemicAdvExpanded

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
        sizeSlider:SetSliderValues(10, 100, 0.1)
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
        wSlider:SetSliderValues(10, 100, 0.1)
        wSlider:SetValue(style.iconWidth or style.buttonSize or ST.BUTTON_SIZE)
        wSlider:SetFullWidth(true)
        wSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.iconWidth = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(wSlider)

        local hSlider = AceGUI:Create("Slider")
        hSlider:SetLabel("Icon Height")
        hSlider:SetSliderValues(10, 100, 0.1)
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
        cdFontColor:SetHasAlpha(true)
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
        local cdPosInfo = CreateFrame("Button", nil, cdAnchorDrop.frame)
        cdPosInfo:SetSize(16, 16)
        cdPosInfo:SetPoint("LEFT", cdAnchorDrop.label, "RIGHT", 4, 0)
        local cdPosInfoIcon = cdPosInfo:CreateTexture(nil, "OVERLAY")
        cdPosInfoIcon:SetSize(12, 12)
        cdPosInfoIcon:SetPoint("CENTER")
        cdPosInfoIcon:SetAtlas("QuestRepeatableTurnin")
        cdPosInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Shared Position")
            GameTooltip:AddLine("Anchor and offset settings are shared between Cooldown Text and Aura Text since they use the same text element.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cdPosInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        cdAnchorDrop:SetCallback("OnRelease", function()
            cdPosInfo:ClearAllPoints()
            cdPosInfo:Hide()
            cdPosInfo:SetParent(nil)
        end)

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

    local auraPosInfo = CreateFrame("Button", nil, auraTextCb.frame)
    auraPosInfo:SetSize(16, 16)
    auraPosInfo:SetPoint("LEFT", auraTextPromoteBtn, "RIGHT", 4, 0)
    local auraPosInfoIcon = auraPosInfo:CreateTexture(nil, "OVERLAY")
    auraPosInfoIcon:SetSize(12, 12)
    auraPosInfoIcon:SetPoint("CENTER")
    auraPosInfoIcon:SetAtlas("QuestRepeatableTurnin")
    auraPosInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Shared Position")
        GameTooltip:AddLine("Position (anchor, X/Y offset) is controlled in the Cooldown Text section above. Cooldown Text and Aura Duration Text share the same text element.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    auraPosInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    if style.showAuraText == false then
        auraPosInfo:Hide()
    end
    auraTextCb:SetCallback("OnRelease", function()
        auraPosInfo:ClearAllPoints()
        auraPosInfo:Hide()
        auraPosInfo:SetParent(nil)
    end)

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
        auraFontColor:SetHasAlpha(true)
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

    -- Compact Mode toggle
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

    -- (?) tooltip for compact mode
    local compactInfo = CreateFrame("Button", nil, compactCb.frame)
    compactInfo:SetSize(16, 16)
    if group.compactLayout then
        compactInfo:SetPoint("LEFT", compactAdvBtn, "RIGHT", 4, 0)
    else
        compactInfo:SetPoint("LEFT", compactCb.checkbg, "RIGHT", compactCb.text:GetStringWidth() + 6, 0)
    end
    local compactInfoIcon = compactInfo:CreateTexture(nil, "OVERLAY")
    compactInfoIcon:SetSize(12, 12)
    compactInfoIcon:SetPoint("CENTER")
    compactInfoIcon:SetAtlas("QuestRepeatableTurnin")
    compactInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Compact Mode")
        GameTooltip:AddLine("When per-button visibility rules hide a button, shift remaining buttons to fill the gap and resize the group frame to fit visible buttons only.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    compactInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(tabInfoButtons, compactInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        compactInfo:Hide()
    end

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

        local maxVisInfo = CreateFrame("Button", nil, maxVisSlider.frame)
        maxVisInfo:SetSize(16, 16)
        maxVisInfo:SetPoint("LEFT", maxVisSlider.label, "CENTER", maxVisSlider.label:GetStringWidth() / 2 + 4, 0)
        local maxVisInfoIcon = maxVisInfo:CreateTexture(nil, "OVERLAY")
        maxVisInfoIcon:SetSize(12, 12)
        maxVisInfoIcon:SetPoint("CENTER")
        maxVisInfoIcon:SetAtlas("QuestRepeatableTurnin")
        maxVisInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Max Visible Buttons")
            GameTooltip:AddLine("Limits how many buttons can appear at once. The first buttons (by group order) that pass visibility checks are shown; the rest are hidden.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        maxVisInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(tabInfoButtons, maxVisInfo)
        if CooldownCompanion.db.profile.hideInfoButtons then
            maxVisInfo:Hide()
        end
    end

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

        local masqueInfo = CreateFrame("Button", nil, masqueCb.frame)
        masqueInfo:SetSize(16, 16)
        masqueInfo:SetPoint("LEFT", masqueCb.checkbg, "RIGHT", masqueCb.text:GetStringWidth() + 4, 0)
        local masqueInfoIcon = masqueInfo:CreateTexture(nil, "OVERLAY")
        masqueInfoIcon:SetSize(12, 12)
        masqueInfoIcon:SetPoint("CENTER")
        masqueInfoIcon:SetAtlas("QuestRepeatableTurnin")
        masqueInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Masque Skinning")
            GameTooltip:AddLine("Uses the Masque addon to apply custom button skins to this group. Configure skins via /masque or the Masque config panel.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Overridden Settings:", 1, 0.82, 0)
            GameTooltip:AddLine("Border Size, Border Color, Square Icons (forced on)", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        masqueInfo:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        table.insert(tabInfoButtons, masqueInfo)

        if CooldownCompanion.db.profile.hideInfoButtons then
            masqueInfo:Hide()
        end
        end -- not masqueCollapsed
    end

    -- Apply "Hide CDC Tooltips" to tab info buttons (skip advanced toggles)
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            if not btn._isAdvancedToggle then btn:Hide() end
        end
    end
end

-- Expose for Config.lua
ST._BuildLayoutTab = BuildLayoutTab
ST._BuildAppearanceTab = BuildAppearanceTab
ST._BuildEffectsTab = BuildEffectsTab
