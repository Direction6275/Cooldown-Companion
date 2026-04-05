local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local C_Texture_GetAtlasExists = C_Texture.GetAtlasExists
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local tonumber = tonumber

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
local HookSliderEditBox = ST._HookSliderEditBox
local BuildAlphaControls = ST._BuildAlphaControls

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
local KEYBIND_CUSTOM_LABEL = "Show Keybind/Custom Text"
local KEYBIND_CUSTOM_TOOLTIP = {
    "Show Keybind/Custom Text",
    {"Shows detected keybind text on icon buttons by default.", 1, 1, 1, true},
    " ",
    {"When enabled for a button, that button's settings can also provide custom text to replace the detected bind until cleared.", 1, 1, 1, true},
}

-- Imports from BarModeTabs.lua
local BuildBarAppearanceTab = ST._BuildBarAppearanceTab
local BuildBarEffectsTab = ST._BuildBarEffectsTab

-- Imports from TextModeTabs.lua
local BuildTextAppearanceTab = ST._BuildTextAppearanceTab

local TEXTURE_BLEND_OPTIONS = {
    ADD = "Add",
    BLEND = "Blend",
}

local TEXTURE_BLEND_ORDER = {
    "ADD",
    "BLEND",
}

local TEXTURE_PREVIEW_WIDTH = 240
local TEXTURE_PREVIEW_HEIGHT = 132
local DEFAULT_TEXTURE_PREVIEW_SIZE = 128
local MIN_TEXTURE_PAIR_SPACING = -5
local MAX_TEXTURE_PAIR_SPACING = 5

local SCREEN_LOCATION = Enum and Enum.ScreenLocationType or {}
local PREVIEW_LOCATION_CENTER = SCREEN_LOCATION.Center or 0
local PREVIEW_LOCATION_LEFTRIGHT = SCREEN_LOCATION.LeftRight or 9
local PREVIEW_LOCATION_TOPBOTTOM = SCREEN_LOCATION.TopBottom or 10

local TEXTURE_PREVIEW_LAYOUTS = {
    [PREVIEW_LOCATION_CENTER] = { width = 1.0, height = 1.0, layout = "single", point = "CENTER", relPoint = "CENTER" },
    [PREVIEW_LOCATION_LEFTRIGHT] = { width = 0.5, height = 1.0, layout = "pair_horizontal" },
    [PREVIEW_LOCATION_TOPBOTTOM] = { width = 1.0, height = 0.5, layout = "pair_vertical" },
}

local function ApplyTexturePreviewSource(texture, settings)
    if not texture or type(settings) ~= "table" then
        return false
    end

    if settings.sourceType == "atlas" then
        if type(settings.sourceValue) ~= "string" or not C_Texture_GetAtlasExists(settings.sourceValue) then
            texture:Hide()
            return false
        end
        texture:SetAtlas(settings.sourceValue, false)
        texture:Show()
        return true
    end

    if settings.sourceType == "file" and settings.sourceValue ~= nil then
        texture:SetTexture(settings.sourceValue)
        texture:Show()
        return true
    end

    texture:Hide()
    return false
end

local function ApplyTexturePreviewVisual(texture, settings, alpha, flipH, flipV)
    if not texture or type(settings) ~= "table" then
        return
    end

    local color = settings.color or { 1, 1, 1, 1 }
    texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha or 1)
    texture:SetBlendMode(settings.blendMode or "ADD")

    local left = flipH and 1 or 0
    local right = flipH and 0 or 1
    local top = flipV and 1 or 0
    local bottom = flipV and 0 or 1
    texture:SetTexCoord(left, right, top, bottom)
end

local function UpdateTexturePanelPreview(preview, settings)
    if type(preview) ~= "table" then
        return
    end

    local hasTexture = type(settings) == "table"
        and settings.sourceType ~= nil
        and settings.sourceValue ~= nil

    preview.nameLabel:SetText(hasTexture and (settings.label or tostring(settings.sourceValue)) or "No texture selected")
    preview.placeholder:SetShown(not hasTexture)
    preview.primary:Hide()
    preview.secondary:Hide()

    if not hasTexture then
        return
    end

    local layout = TEXTURE_PREVIEW_LAYOUTS[settings.locationType or PREVIEW_LOCATION_CENTER]
        or TEXTURE_PREVIEW_LAYOUTS[PREVIEW_LOCATION_CENTER]
    local scale = tonumber(settings.scale) or 1
    local baseWidth = (tonumber(settings.width) or DEFAULT_TEXTURE_PREVIEW_SIZE) * scale
    local baseHeight = (tonumber(settings.height) or DEFAULT_TEXTURE_PREVIEW_SIZE) * scale
    local pieceWidth = baseWidth * (layout.width or 1)
    local pieceHeight = baseHeight * (layout.height or 1)
    local pairSpacing = tonumber(settings.pairSpacing) or 0
    local gap = 0
    local totalWidth = pieceWidth
    local totalHeight = pieceHeight

    local function GetHorizontalSpan(width, offsetGap)
        local primaryLeft = (-(offsetGap / 2)) - width
        local primaryRight = -(offsetGap / 2)
        local secondaryLeft = offsetGap / 2
        local secondaryRight = secondaryLeft + width
        return math_max(primaryRight, secondaryRight) - math_min(primaryLeft, secondaryLeft)
    end

    local function GetVerticalSpan(height, offsetGap)
        local bottomBottom = (-(offsetGap / 2)) - height
        local bottomTop = -(offsetGap / 2)
        local topBottom = offsetGap / 2
        local topTop = topBottom + height
        return math_max(bottomTop, topTop) - math_min(bottomBottom, topBottom)
    end

    if layout.layout == "pair_horizontal" then
        gap = pieceWidth * pairSpacing
        totalWidth = GetHorizontalSpan(pieceWidth, gap)
    elseif layout.layout == "pair_vertical" then
        gap = pieceHeight * pairSpacing
        totalHeight = GetVerticalSpan(pieceHeight, gap)
    end

    local maxWidth = TEXTURE_PREVIEW_WIDTH - 20
    local maxHeight = TEXTURE_PREVIEW_HEIGHT - 20
    local fit = math_min(maxWidth / math_max(totalWidth, 1), maxHeight / math_max(totalHeight, 1), 1)
    pieceWidth = math_max(8, pieceWidth * fit)
    pieceHeight = math_max(8, pieceHeight * fit)
    gap = gap * fit

    local color = settings.color or { 1, 1, 1, 1 }
    local alpha = math_min(math_max((color[4] or 1) * (settings.alpha or 1), 0.05), 1)
    local primary = preview.primary
    local secondary = preview.secondary
    local shownPrimary = false
    local shownSecondary = false

    primary:ClearAllPoints()
    secondary:ClearAllPoints()
    primary:SetSize(pieceWidth, pieceHeight)
    secondary:SetSize(pieceWidth, pieceHeight)

    if layout.layout == "pair_horizontal" then
        primary:SetPoint("RIGHT", preview.anchor, "CENTER", -(gap / 2), 0)
        secondary:SetPoint("LEFT", preview.anchor, "CENTER", gap / 2, 0)

        if ApplyTexturePreviewSource(primary, settings) then
            ApplyTexturePreviewVisual(primary, settings, alpha, false, false)
            shownPrimary = true
        end
        if ApplyTexturePreviewSource(secondary, settings) then
            ApplyTexturePreviewVisual(secondary, settings, alpha, true, false)
            shownSecondary = true
        end
        preview.placeholder:SetShown(not (shownPrimary or shownSecondary))
        return
    end

    if layout.layout == "pair_vertical" then
        primary:SetPoint("BOTTOM", preview.anchor, "CENTER", 0, -(gap / 2))
        secondary:SetPoint("TOP", preview.anchor, "CENTER", 0, gap / 2)

        if ApplyTexturePreviewSource(primary, settings) then
            ApplyTexturePreviewVisual(primary, settings, alpha, false, false)
            shownPrimary = true
        end
        if ApplyTexturePreviewSource(secondary, settings) then
            ApplyTexturePreviewVisual(secondary, settings, alpha, false, true)
            shownSecondary = true
        end
        preview.placeholder:SetShown(not (shownPrimary or shownSecondary))
        return
    end

    primary:SetPoint(layout.point or "CENTER", preview.anchor, layout.relPoint or "CENTER", 0, 0)
    if ApplyTexturePreviewSource(primary, settings) then
        ApplyTexturePreviewVisual(primary, settings, alpha, layout.flipH, layout.flipV)
        shownPrimary = true
    end
    preview.placeholder:SetShown(not shownPrimary)
end

local function AttachLiveTextureSliderRefresh(sliderWidget, applyValue)
    if not sliderWidget or not sliderWidget.slider or type(applyValue) ~= "function" then
        return
    end

    local sliderFrame = sliderWidget.slider
    sliderWidget._ccApplyLiveTextureValue = applyValue
    sliderWidget._ccLastLiveTextureValue = nil

    local function pushValue(widget, value)
        if not widget then
            return
        end

        value = tonumber(value)
        if value == nil then
            return
        end

        local lastValue = widget._ccLastLiveTextureValue
        if lastValue ~= nil and math_abs(lastValue - value) < 0.0001 then
            return
        end

        widget._ccLastLiveTextureValue = value

        local liveApply = widget._ccApplyLiveTextureValue
        if type(liveApply) == "function" then
            liveApply(value)
        end
    end

    sliderWidget:SetCallback("OnValueChanged", function(widget, _, value)
        pushValue(widget, value)
    end)

    sliderWidget:SetCallback("OnMouseUp", function(widget, _, value)
        pushValue(widget, value)
        sliderFrame:SetScript("OnUpdate", nil)
        sliderFrame._ccLiveTextureSliderActive = nil
        widget._ccLastLiveTextureValue = nil
    end)

    local prevOnRelease = sliderWidget.events and sliderWidget.events["OnRelease"]
    sliderWidget:SetCallback("OnRelease", function(widget, event)
        sliderFrame:SetScript("OnUpdate", nil)
        sliderFrame._ccLiveTextureSliderActive = nil
        widget._ccApplyLiveTextureValue = nil
        widget._ccLastLiveTextureValue = nil
        if prevOnRelease then
            prevOnRelease(widget, event)
        end
    end)

    if sliderFrame._ccLiveTextureSliderHooked then
        return
    end

    sliderFrame._ccLiveTextureSliderHooked = true

    sliderFrame:HookScript("OnMouseDown", function(frame)
        frame._ccLiveTextureSliderActive = true
        frame:SetScript("OnUpdate", function(self)
            if not self._ccLiveTextureSliderActive then
                self:SetScript("OnUpdate", nil)
                return
            end

            local widget = self.obj
            if widget then
                pushValue(widget, widget:GetValue())
            end
        end)
    end)

    sliderFrame:HookScript("OnMouseUp", function(frame)
        frame._ccLiveTextureSliderActive = nil
        frame:SetScript("OnUpdate", nil)
        local widget = frame.obj
        if widget then
            widget._ccLastLiveTextureValue = nil
        end
    end)

    sliderFrame:HookScript("OnHide", function(frame)
        frame._ccLiveTextureSliderActive = nil
        frame:SetScript("OnUpdate", nil)
        local widget = frame.obj
        if widget then
            widget._ccLastLiveTextureValue = nil
        end
    end)
end

local function GetTexturePanelCommitCallback(group)
    return function(selection)
        local liveSettings = CooldownCompanion:GetTexturePanelSettings(group, true)
        if not liveSettings then
            return
        end

        if selection then
            CooldownCompanion:ApplyTexturePanelEntry(liveSettings, selection)
        else
            liveSettings.sourceType = nil
            liveSettings.sourceValue = nil
            liveSettings.label = nil
            liveSettings.width = nil
            liveSettings.height = nil
        end

        liveSettings.enabled = nil

        CooldownCompanion:RefreshAllAuraTextureVisuals()
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function OpenOrRebindTexturePanelPicker(group, settings, forceOpen)
    if not (group and group.buttons and group.buttons[1] and CS.StartPickAuraTexture) then
        return
    end

    local pickerOpts = {
        groupId = CS.selectedGroup,
        buttonIndex = 1,
        initialSelection = settings and settings.sourceType and settings or nil,
        callback = GetTexturePanelCommitCallback(group),
    }

    if forceOpen or not (CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen()) then
        CS.StartPickAuraTexture(pickerOpts)
    elseif CS.RebindPickAuraTexture then
        CS.RebindPickAuraTexture(pickerOpts)
    end
end

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

    if group.displayMode == "textures" then
        local settings = CooldownCompanion:GetTexturePanelSettings(group, true)
        if not settings then
            return
        end

        local function RefreshTextureVisual()
            CooldownCompanion:RefreshAllAuraTextureVisuals()
        end

        local heading = AceGUI:Create("Heading")
        heading:SetText("Texture Position")
        ColorHeading(heading)
        heading:SetFullWidth(true)
        container:AddChild(heading)

        local intro = AceGUI:Create("Label")
        intro:SetFullWidth(true)
        intro:SetText("This panel's texture is a standalone screen element. Drag it directly while this tab is open, or use the controls below for exact placement.")
        container:AddChild(intro)

        AddAnchorDropdown(container, settings, "point", "CENTER", RefreshTextureVisual, "Texture Point")
        AddAnchorDropdown(container, settings, "relativePoint", "CENTER", RefreshTextureVisual, "Screen Point")
        AddOffsetSliders(container, settings, "x", "y", {
            x = 0,
            y = 0,
            range = 2000,
            step = 1,
        }, RefreshTextureVisual)

        local resetBtn = AceGUI:Create("Button")
        resetBtn:SetText("Reset Position")
        resetBtn:SetFullWidth(true)
        resetBtn:SetCallback("OnClick", function()
            settings.point = "CENTER"
            settings.relativePoint = "CENTER"
            settings.relativeTo = "UIParent"
            settings.x = 0
            settings.y = 0
            CooldownCompanion:RefreshAllAuraTextureVisuals()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(resetBtn)

        if CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
            OpenOrRebindTexturePanelPicker(group, settings, false)
        end
        RefreshTextureVisual()
        return
    end

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
    BuildAlphaControls(container, group, function()
        CooldownCompanion:RefreshConfigPanel()
    end, "layout_alpha", {
        isGlobal = group.isGlobal,
        onBaselineChanged = function(val)
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
        end,
    })

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

    if group.displayMode == "textures" then
        local label = AceGUI:Create("Label")
        label:SetText("|cff888888Texture Panels do not use the Indicators tab. Their trigger rules live on the single entry, and their visual controls live in Appearance and Layout.|r")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

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
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(fillCb)
        ApplyCheckboxIndent(fillCb, 20)

        -- Swipe Fill Opacity (only when fill is visible)
        if style.showCooldownSwipeFill ~= false then
            local alphaSlider = AceGUI:Create("Slider")
            alphaSlider:SetLabel("Swipe Fill Opacity")
            alphaSlider:SetSliderValues(0, 1, 0.05)
            alphaSlider:SetIsPercent(true)
            alphaSlider:SetValue(style.cooldownSwipeAlpha or 0.8)
            alphaSlider:SetFullWidth(true)
            alphaSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.cooldownSwipeAlpha = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            container:AddChild(alphaSlider)
        end

        -- Show Swipe Edge
        local edgeCb = AceGUI:Create("CheckBox")
        edgeCb:SetLabel("Show Swipe Edge")
        edgeCb:SetValue(style.showCooldownSwipeEdge ~= false)
        edgeCb:SetFullWidth(true)
        edgeCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.showCooldownSwipeEdge = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(edgeCb)
        ApplyCheckboxIndent(edgeCb, 20)

        -- Swipe Edge Color (only when edge is visible)
        if style.showCooldownSwipeEdge ~= false then
            local swipeRefresh = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
            AddColorPicker(container, style, "cooldownSwipeEdgeColor", "Swipe Edge Color", {1, 1, 1, 1}, true, swipeRefresh, swipeRefresh)
        end
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

    if group.displayMode == "textures" then
        local settings = CooldownCompanion:GetTexturePanelSettings(group, true)
        if not settings then
            return
        end

        local groupId = CS.selectedGroup
        local buttonData = group.buttons and group.buttons[1] or nil
        local previewWidget = nil
        local function RefreshTextureVisual()
            if previewWidget then
                UpdateTexturePanelPreview(previewWidget, settings)
            end
            local groupFrame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
            local button = groupFrame and groupFrame.buttons and groupFrame.buttons[1] or nil
            if button then
                CooldownCompanion:UpdateAuraTextureVisual(button)
            else
                CooldownCompanion:RefreshAllAuraTextureVisuals()
            end
        end

        local heading = AceGUI:Create("Heading")
        heading:SetText("Texture Panel")
        ColorHeading(heading)
        heading:SetFullWidth(true)
        container:AddChild(heading)

        CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
            "Texture Panel",
            {"This panel shows one standalone texture on your screen.", 1, 1, 1, true},
            " ",
            {"Its single entry decides when that texture appears.", 1, 1, 1, true},
        }, tabInfoButtons)

        if not buttonData then
            local emptyLabel = AceGUI:Create("Label")
            emptyLabel:SetFullWidth(true)
            emptyLabel:SetText("|cff888888Add one entry in Column 2 first. The texture browser will open after that.|r")
            container:AddChild(emptyLabel)

            if CS.pendingTexturePickerOpen == CS.selectedGroup then
                CS.pendingTexturePickerOpen = nil
            end
            return
        end

        local selectionLabel = CooldownCompanion:GetTexturePanelSelectionLabel(group)

        local previewGroup = AceGUI:Create("SimpleGroup")
        previewGroup:SetFullWidth(true)
        previewGroup:SetHeight(TEXTURE_PREVIEW_HEIGHT + 10)
        previewGroup:SetLayout("Fill")
        container:AddChild(previewGroup)

        local previewFrame = CreateFrame("Frame", nil, previewGroup.frame, "BackdropTemplate")
        previewFrame:SetPoint("TOP", previewGroup.frame, "TOP", 0, -2)
        previewFrame:SetSize(TEXTURE_PREVIEW_WIDTH, TEXTURE_PREVIEW_HEIGHT)
        previewFrame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        previewFrame:SetBackdropColor(0.05, 0.08, 0.10, 0.95)
        previewFrame:SetBackdropBorderColor(0.18, 0.35, 0.45, 0.95)
        appearanceTabElements[#appearanceTabElements + 1] = previewFrame

        local previewInset = CreateFrame("Frame", nil, previewFrame)
        previewInset:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 8, -8)
        previewInset:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", -8, 8)

        local previewShade = previewInset:CreateTexture(nil, "BACKGROUND")
        previewShade:SetAllPoints()
        previewShade:SetColorTexture(0, 0, 0, 0.42)

        local previewAnchor = CreateFrame("Frame", nil, previewInset)
        previewAnchor:SetPoint("CENTER")
        previewAnchor:SetSize(TEXTURE_PREVIEW_WIDTH - 20, TEXTURE_PREVIEW_HEIGHT - 20)

        local previewPrimary = previewInset:CreateTexture(nil, "ARTWORK")
        local previewSecondary = previewInset:CreateTexture(nil, "ARTWORK")

        local placeholder = previewInset:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        placeholder:SetPoint("CENTER")
        placeholder:SetJustifyH("CENTER")
        placeholder:SetText("No texture selected")
        placeholder:SetTextColor(0.65, 0.65, 0.65, 1)

        local previewName = AceGUI:Create("Label")
        previewName:SetFullWidth(true)
        previewName.label:SetFontObject(GameFontHighlight)
        previewName.label:SetJustifyH("CENTER")
        container:AddChild(previewName)

        previewWidget = {
            primary = previewPrimary,
            secondary = previewSecondary,
            placeholder = placeholder,
            anchor = previewAnchor,
            nameLabel = previewName,
        }
        UpdateTexturePanelPreview(previewWidget, settings)

        local helpLabel = AceGUI:Create("Label")
        helpLabel:SetFullWidth(true)
        helpLabel:SetText("|cff888888The entry controls when this shows. These controls only change the texture itself.|r")
        container:AddChild(helpLabel)

        local actionRow = AceGUI:Create("SimpleGroup")
        actionRow:SetFullWidth(true)
        actionRow:SetLayout("Flow")
        container:AddChild(actionRow)

        local browseBtn = AceGUI:Create("Button")
        browseBtn:SetText("Browse / Change")
        browseBtn:SetRelativeWidth(0.49)
        browseBtn:SetCallback("OnClick", function()
            OpenOrRebindTexturePanelPicker(group, settings, true)
        end)
        actionRow:AddChild(browseBtn)

        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear")
        clearBtn:SetDisabled(not selectionLabel)
        clearBtn:SetRelativeWidth(0.49)
        clearBtn:SetCallback("OnClick", function()
            CooldownCompanion:ClearAllAuraTexturePickerPreviews()
            GetTexturePanelCommitCallback(group)(nil)
        end)
        actionRow:AddChild(clearBtn)

        if not selectionLabel then
            local emptyStateLabel = AceGUI:Create("Label")
            emptyStateLabel:SetFullWidth(true)
            emptyStateLabel:SetText("|cff888888Pick a texture to show the rest of the display controls.|r")
            container:AddChild(emptyStateLabel)

            local shouldOpenPicker = CS.pendingTexturePickerOpen == CS.selectedGroup
            if shouldOpenPicker then
                CS.pendingTexturePickerOpen = nil
                C_Timer.After(0, function()
                    if CS.selectedGroup == groupId and CS.panelSettingsTab == "appearance" then
                        OpenOrRebindTexturePanelPicker(group, settings, true)
                    end
                end)
            elseif CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
                OpenOrRebindTexturePanelPicker(group, settings, false)
            end

            RefreshTextureVisual()
            return
        end

        local locationOptions, locationOrder = CooldownCompanion:GetTexturePanelLocationOptions()
        local locationDrop = AceGUI:Create("Dropdown")
        locationDrop:SetLabel("Texture Layout")
        locationDrop:SetList(locationOptions, locationOrder)
        locationDrop:SetValue(settings.locationType or 0)
        locationDrop:SetFullWidth(true)
        locationDrop:SetCallback("OnValueChanged", function(_, _, value)
            settings.locationType = tonumber(value) or 0
            RefreshTextureVisual()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(locationDrop)

        if settings.locationType == PREVIEW_LOCATION_LEFTRIGHT or settings.locationType == PREVIEW_LOCATION_TOPBOTTOM then
            local spacingSlider = AceGUI:Create("Slider")
            spacingSlider:SetLabel("Pair Spacing")
            spacingSlider:SetSliderValues(MIN_TEXTURE_PAIR_SPACING, MAX_TEXTURE_PAIR_SPACING, 0.01)
            spacingSlider:SetValue(settings.pairSpacing or 0)
            spacingSlider:SetFullWidth(true)
            AttachLiveTextureSliderRefresh(spacingSlider, function(value)
                settings.pairSpacing = value
                RefreshTextureVisual()
            end)
            HookSliderEditBox(spacingSlider)
            container:AddChild(spacingSlider)
        end

        local blendDrop = AceGUI:Create("Dropdown")
        blendDrop:SetLabel("Blend Mode")
        blendDrop:SetList(TEXTURE_BLEND_OPTIONS, TEXTURE_BLEND_ORDER)
        blendDrop:SetValue(settings.blendMode or "ADD")
        blendDrop:SetFullWidth(true)
        blendDrop:SetCallback("OnValueChanged", function(_, _, value)
            settings.blendMode = value or "ADD"
            RefreshTextureVisual()
        end)
        container:AddChild(blendDrop)

        local scaleSlider = AceGUI:Create("Slider")
        scaleSlider:SetLabel("Texture Scale")
        scaleSlider:SetSliderValues(0.25, 4, 0.05)
        scaleSlider:SetValue(settings.scale or 1)
        scaleSlider:SetFullWidth(true)
        AttachLiveTextureSliderRefresh(scaleSlider, function(value)
            settings.scale = value
            RefreshTextureVisual()
        end)
        HookSliderEditBox(scaleSlider)
        container:AddChild(scaleSlider)

        local alphaSlider = AceGUI:Create("Slider")
        alphaSlider:SetLabel("Texture Alpha")
        alphaSlider:SetSliderValues(0.05, 1, 0.05)
        alphaSlider:SetValue(settings.alpha or 1)
        alphaSlider:SetFullWidth(true)
        AttachLiveTextureSliderRefresh(alphaSlider, function(value)
            settings.alpha = value
            RefreshTextureVisual()
        end)
        HookSliderEditBox(alphaSlider)
        container:AddChild(alphaSlider)

        AddColorPicker(container, settings, "color", "Texture Color", { 1, 1, 1, 1 }, true, RefreshTextureVisual, RefreshTextureVisual)

        local shouldOpenPicker = CS.pendingTexturePickerOpen == CS.selectedGroup
        if shouldOpenPicker then
            CS.pendingTexturePickerOpen = nil
            C_Timer.After(0, function()
                if CS.selectedGroup == groupId and CS.panelSettingsTab == "appearance" then
                    OpenOrRebindTexturePanelPicker(group, settings, true)
                end
            end)
        elseif CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
            OpenOrRebindTexturePanelPicker(group, settings, false)
        end

        RefreshTextureVisual()
        return
    end

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
    chargeTextCb:SetLabel("Show Count Text (Charges/Uses)")
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

    -- Show Keybind/Custom Text toggle
    local kbCb = AceGUI:Create("CheckBox")
    kbCb:SetLabel(KEYBIND_CUSTOM_LABEL)
    kbCb:SetValue(style.showKeybindText or false)
    kbCb:SetFullWidth(true)
    kbCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showKeybindText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(kbCb)

    local kbAdvExpanded, kbAdvBtn = AddAdvancedToggle(kbCb, "keybindText", tabInfoButtons, style.showKeybindText)
    local kbPromoteBtn = CreateCheckboxPromoteButton(kbCb, kbAdvBtn, "keybindText", group, style)
    local kbInfoAnchor = kbCb.checkbg
    local kbInfoXOff = kbCb.text:GetStringWidth() + 4
    if kbPromoteBtn and kbPromoteBtn:IsShown() then
        kbInfoAnchor = kbPromoteBtn
        kbInfoXOff = 4
    elseif kbAdvBtn and kbAdvBtn:IsShown() then
        kbInfoAnchor = kbAdvBtn
        kbInfoXOff = 4
    end
    CreateInfoButton(kbCb.frame, kbInfoAnchor, "LEFT", "RIGHT", kbInfoXOff, 0, KEYBIND_CUSTOM_TOOLTIP, kbCb)

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
        {"Unusable Dimming Tint:", 1, 0.82, 0},
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
        resetTintBtn:SetText("Reset Colors to Default")
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
