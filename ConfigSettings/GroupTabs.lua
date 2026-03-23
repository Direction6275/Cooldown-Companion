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
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders

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
local BuildIconTintControls = ST._BuildIconTintControls
local BuildAssistedHighlightControls = ST._BuildAssistedHighlightControls
local BuildProcGlowControls = ST._BuildProcGlowControls
local BuildPandemicGlowControls = ST._BuildPandemicGlowControls
local BuildPandemicBarControls = ST._BuildPandemicBarControls
local BuildAuraIndicatorControls = ST._BuildAuraIndicatorControls
local BuildReadyGlowControls = ST._BuildReadyGlowControls
local BuildKeyPressHighlightControls = ST._BuildKeyPressHighlightControls
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
            local target = _G[text]
            if not target or type(target) ~= "table" or not target.GetObjectType then
                CooldownCompanion:Print("Frame not found: " .. text)
                widget:SetText(currentAnchor)
                return
            end
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

    -- Anchor Point / Relative Point dropdowns
    local function refreshGroupAnchor()
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end

    AddAnchorDropdown(container, group.anchor, "point", "CENTER", refreshGroupAnchor, "Anchor Point")
    AddAnchorDropdown(container, group.anchor, "relativePoint", "CENTER", refreshGroupAnchor, "Relative Point")

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

    -- Growth Direction (all display modes, 2+ buttons)
    if #group.buttons > 1 then
        local isBarMode = group.displayMode == "bars"
        local orient = style.orientation or (isBarMode and "vertical" or "horizontal")
        local labels, order
        if orient == "vertical" then
            labels = { TOPLEFT = "Down, Right", TOPRIGHT = "Down, Left", BOTTOMLEFT = "Up, Right", BOTTOMRIGHT = "Up, Left" }
        else
            labels = { TOPLEFT = "Right, Down", TOPRIGHT = "Left, Down", BOTTOMLEFT = "Right, Up", BOTTOMRIGHT = "Left, Up" }
        end
        order = {"TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT"}
        local growthDrop = AceGUI:Create("Dropdown")
        growthDrop:SetLabel("Growth Direction")
        growthDrop:SetList(labels, order)
        growthDrop:SetValue(style.growthOrigin or "TOPLEFT")
        growthDrop:SetFullWidth(true)
        growthDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.growthOrigin = val
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(growthDrop)
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
        CooldownCompanion:SetGroupKeyPressHighlightPreview(CS.selectedGroup, false)
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
    -- Key Press Highlight (glow while keybind is held)
    -- ================================================================
    local kphEnableCb = AceGUI:Create("CheckBox")
    kphEnableCb:SetLabel("Show Key Press Highlight")
    kphEnableCb:SetValue(style.keyPressHighlightStyle and style.keyPressHighlightStyle ~= "none")
    kphEnableCb:SetFullWidth(true)
    kphEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.keyPressHighlightStyle = val and "solid" or "none"
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(kphEnableCb)

    local kphAdvExpanded, kphAdvBtn = AddAdvancedToggle(kphEnableCb, "keyPressHighlight", tabInfoButtons, style.keyPressHighlightStyle and style.keyPressHighlightStyle ~= "none")
    local kphPromoteBtn = CreateCheckboxPromoteButton(kphEnableCb, kphAdvBtn, "keyPressHighlight", group, style)
    CreateInfoButton(kphEnableCb.frame, kphPromoteBtn, "LEFT", "RIGHT", 4, 0, {
        "Key Press Highlight",
        {"Shows a glow overlay on buttons while their action bar keybind is physically held down.", 1, 1, 1, true},
    }, tabInfoButtons)

    if kphAdvExpanded and style.keyPressHighlightStyle and style.keyPressHighlightStyle ~= "none" then
    local kphCombatCb = AceGUI:Create("CheckBox")
    kphCombatCb:SetLabel("Show Only In Combat")
    kphCombatCb:SetValue(style.keyPressHighlightCombatOnly or false)
    kphCombatCb:SetFullWidth(true)
    kphCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.keyPressHighlightCombatOnly = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(kphCombatCb)
    ApplyCheckboxIndent(kphCombatCb, 20)

    BuildKeyPressHighlightControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    local kphPreviewBtn = AceGUI:Create("Button")
    kphPreviewBtn:SetText("Preview Key Press Highlight (3s)")
    kphPreviewBtn:SetFullWidth(true)
    kphPreviewBtn:SetCallback("OnClick", function()
        CooldownCompanion:PlayGroupKeyPressHighlightPreview(CS.selectedGroup, 3)
    end)
    container:AddChild(kphPreviewBtn)
    else
    CooldownCompanion:SetGroupKeyPressHighlightPreview(CS.selectedGroup, false)
    end -- kphAdvExpanded

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
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end

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
        spacingSlider:SetSliderValues(0, 30, 0.1)
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
        AddFontControls(container, style, "cooldown", { size = 12 }, refreshStyle)
        AddColorPicker(container, style, "cooldownFontColor", "Font Color", {1, 1, 1, 1}, false, refreshStyle, refreshStyle)

        local cdAnchorDrop = AddAnchorDropdown(container, style, "cooldownTextAnchor", "CENTER", refreshStyle)

        -- (?) tooltip for shared positioning
        CreateInfoButton(cdAnchorDrop.frame, cdAnchorDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Shared Position",
            {"Position is shared with Aura Duration Text by default. Enable 'Separate Text Positions' in the Aura Duration Text section to use independent positions.", 1, 1, 1, true},
        }, cdAnchorDrop)

        AddOffsetSliders(container, style, "cooldownTextXOffset", "cooldownTextYOffset", { x = 0, y = 0 }, refreshStyle)

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
        AddFontControls(container, style, "charge", { size = 12 }, refreshStyle)
        AddColorPicker(container, style, "chargeFontColor", "Font Color (Max Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddColorPicker(container, style, "chargeFontColorMissing", "Font Color (Missing Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddColorPicker(container, style, "chargeFontColorZero", "Font Color (Zero Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddAnchorDropdown(container, style, "chargeAnchor", "BOTTOMRIGHT", refreshStyle)
        AddOffsetSliders(container, style, "chargeXOffset", "chargeYOffset", { x = -2, y = 2 }, refreshStyle)
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
        AddFontControls(container, style, "auraText", { size = 12 }, refreshStyle)
        AddColorPicker(container, style, "auraTextFontColor", "Font Color", {0, 0.925, 1, 1}, false, refreshStyle, refreshStyle)

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
            AddAnchorDropdown(container, style, "auraTextAnchor", "TOPLEFT", refreshStyle)
            AddOffsetSliders(container, style, "auraTextXOffset", "auraTextYOffset", { x = 2, y = -2 }, refreshStyle)
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
        AddFontControls(container, style, "auraStack", { size = 12 }, refreshStyle)
        AddColorPicker(container, style, "auraStackFontColor", "Font Color", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddAnchorDropdown(container, style, "auraStackAnchor", "BOTTOMLEFT", refreshStyle)
        AddOffsetSliders(container, style, "auraStackXOffset", "auraStackYOffset", { x = 2, y = 2 }, refreshStyle)
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
        -- Keybind uses a hardcoded 4-point anchor (not the full 9-point list)
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

        AddOffsetSliders(container, style, "keybindXOffset", "keybindYOffset", { x = -2, y = -2 }, refreshStyle)
        AddFontControls(container, style, "keybind", { size = 10, sizeMin = 6, sizeMax = 24 }, refreshStyle)
        AddColorPicker(container, style, "keybindFontColor", "Font Color", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
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
    local borderColor = AddColorPicker(container, style, "borderColor", "Border Color", {0, 0, 0, 1}, true, refreshStyle, refreshStyle)
    if group.masqueEnabled then
        borderColor:SetDisabled(true)
    end
    end -- not borderCollapsed

    -- Icon Tint
    local iconTintHeading = AceGUI:Create("Heading")
    iconTintHeading:SetText("Icon Tint")
    ColorHeading(iconTintHeading)
    iconTintHeading:SetFullWidth(true)
    container:AddChild(iconTintHeading)

    local iconTintCollapsed = CS.collapsedSections["appearance_iconTint"]
    AttachCollapseButton(iconTintHeading, iconTintCollapsed, function()
        CS.collapsedSections["appearance_iconTint"] = not CS.collapsedSections["appearance_iconTint"]
        CooldownCompanion:RefreshConfigPanel()
    end)
    local iconTintPromoteBtn = CreatePromoteButton(iconTintHeading, "iconTint", CS.selectedButton and group.buttons[CS.selectedButton], style)

    local iconTintInfoBtn = CreateInfoButton(iconTintHeading.frame, iconTintPromoteBtn, "LEFT", "RIGHT", 2, 0, {
        "Icon Tint",
        {"Recolor or fade icons without affecting cooldown text, glows, or borders.", 1, 1, 1, true},
        " ",
        {"Base Icon Color:", 1, 0.82, 0},
        {"The default color for your icons. Lower the alpha to make icons semi-transparent while everything else stays visible.", 1, 1, 1, true},
        " ",
        {"Cooldown Tint:", 1, 0.82, 0},
        {"A separate color used only while an ability is on cooldown. Great for dimming icons on cooldown while keeping ready abilities bright.", 1, 1, 1, true},
        " ",
        {"Aura Tint:", 1, 0.82, 0},
        {"A separate color applied while an aura-tracked ability's buff or debuff is active. Only affects buttons with aura tracking enabled.", 1, 1, 1, true},
        " ",
        {"Unusable Dimming Color:", 1, 0.82, 0},
        {"A color applied when an ability is not usable. Only appears when unusable dimming is enabled in the Indicators tab.", 1, 1, 1, true},
    }, tabInfoButtons)

    iconTintHeading.right:ClearAllPoints()
    iconTintHeading.right:SetPoint("RIGHT", iconTintHeading.frame, "RIGHT", -3, 0)
    iconTintHeading.right:SetPoint("LEFT", iconTintInfoBtn, "RIGHT", 4, 0)

    if not iconTintCollapsed then
        BuildIconTintControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        BuildBackgroundColorControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)

        local resetTintBtn = AceGUI:Create("Button")
        resetTintBtn:SetText("Reset Tint Settings to Default")
        resetTintBtn:SetFullWidth(true)
        resetTintBtn:SetCallback("OnClick", function()
            style.iconTintColor = {1, 1, 1, 1}
            style.iconCooldownTintColor = {1, 0, 0.102, 1}
            style.iconAuraTintColor = {0, 0.925, 1, 1}
            style.iconUnusableTintColor = {0.4, 0.4, 0.4, 1}
            style.backgroundColor = {0, 0, 0, 0.5}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(resetTintBtn)
    end -- not iconTintCollapsed

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

    -- Anchor Point / Relative Point dropdowns
    local function refreshContainerAnchor()
        local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
        if containerFrame then
            CooldownCompanion:AnchorContainerFrame(containerFrame, container.anchor)
        end
    end

    AddAnchorDropdown(scroll, container.anchor, "point", "CENTER", refreshContainerAnchor, "Anchor Point")
    AddAnchorDropdown(scroll, container.anchor, "relativePoint", "CENTER", refreshContainerAnchor, "Relative Point")

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
