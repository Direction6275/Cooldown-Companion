local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
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
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local HookSliderEditBox = ST._HookSliderEditBox
local BuildAlphaControls = ST._BuildAlphaControls
local OpenTriggerPanelIconPicker = ST._OpenTriggerPanelIconPicker
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local ApplyIconTexCoord = ST._ApplyIconTexCoord
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown
local AddScopedLoadConditionToggles = ST._AddScopedLoadConditionToggles
local AddActiveEligibilitySummary = ST._AddActiveEligibilitySummary
local AddCharacterEligibilityControls = ST._AddCharacterEligibilityControls
local AddClassSpecEligibilityControls = ST._AddClassSpecEligibilityControls
local BuildEligibilityBadgeMap = ST._BuildEligibilityBadgeMap

-- Imports from SectionBuilders.lua
local BuildKeybindTextControls = ST._BuildKeybindTextControls
local BuildBorderControls = ST._BuildBorderControls
local BuildBackgroundColorControls = ST._BuildBackgroundColorControls
local BuildDesaturationControls = ST._BuildDesaturationControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls
local BuildShowOutOfRangeControls = ST._BuildShowOutOfRangeControls
local BuildShowGCDSwipeControls = ST._BuildShowGCDSwipeControls
local BuildCooldownSwipeControls = ST._BuildCooldownSwipeControls
local BuildIconFillTimerControls = ST._BuildIconFillTimerControls
local BuildIconFillTimerAdvancedControls = ST._BuildIconFillTimerAdvancedControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildIconTintControls = ST._BuildIconTintControls
local BuildAssistedHighlightControls = ST._BuildAssistedHighlightControls
local BuildProcGlowControls = ST._BuildProcGlowControls
local BuildPandemicGlowControls = ST._BuildPandemicGlowControls
local BuildAuraIndicatorControls = ST._BuildAuraIndicatorControls
local AddConditionalPreviewButton = ST._AddConditionalPreviewButton
local AddPreviewBadge = ST._AddPreviewBadge
local AddConditionalPreviewBadge = ST._AddConditionalPreviewBadge
local AddDurationFormatDropdown = ST._AddDurationFormatDropdown
local BuildAuraDurationSwipeControls = ST._BuildAuraDurationSwipeControls
local BuildAuraDurationSwipeAdvancedControls = ST._BuildAuraDurationSwipeAdvancedControls
local BuildReadyGlowControls = ST._BuildReadyGlowControls
local BuildKeyPressHighlightControls = ST._BuildKeyPressHighlightControls

local function PrimeReadyGlowCappedChargeTransitions(groupId)
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if not (frame and frame.buttons) then
        return
    end

    for _, button in ipairs(frame.buttons) do
        local buttonData = button.buttonData
        if buttonData
           and buttonData.type == "spell"
           and buttonData.hasCharges == true
           and not buttonData._hasDisplayCount then
            button._readyGlowMaxChargesSpellID = button._displaySpellId or buttonData.id
            button._readyGlowMaxChargesStartTime = nil
            button._readyGlowMaxChargesActive = false
        end
    end
end

local function PrimeReadyGlowNormalTransitions(groupId)
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if not (frame and frame.buttons) then
        return
    end

    local now = GetTime()
    for _, button in ipairs(frame.buttons) do
        local buttonData = button.buttonData
        if buttonData
           and not buttonData.isPassive
           and button._noCooldown ~= true
           and button._visibilityHidden ~= true
           and button._desatCooldownActive ~= true then
            button._readyGlowStartTime = now
        end
    end
end

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements
local KEYBIND_CUSTOM_LABEL = "Show Keybind/Custom Text"
local KEYBIND_CUSTOM_TOOLTIP = {
    "Show Keybind/Custom Text",
    {"Shows detected keybind text on icon buttons by default.", 1, 1, 1, true},
    " ",
    {"When enabled for a button, that button's settings can also provide custom text to replace the detected bind until cleared.", 1, 1, 1, true},
}

local function RefreshActiveAdvancedSettingsPanel()
    if CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    end
end

local function AddIndicatorsHeading(container, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)
    return heading
end

-- Imports from BarModeTabs.lua
local BuildBarAppearanceTab = ST._BuildBarAppearanceTab
local BuildBarEffectsTab = ST._BuildBarEffectsTab

-- Imports from TextModeTabs.lua
local BuildTextAppearanceTab = ST._BuildTextAppearanceTab

local TEXTURE_BLEND_OPTIONS = {
    BLEND = "Normal / Original",
    ADD = "Soft / Transparent",
}

local TEXTURE_BLEND_ORDER = {
    "BLEND",
    "ADD",
}

local TEXTURE_PREVIEW_WIDTH = 240
local TEXTURE_PREVIEW_HEIGHT = 170
local DEFAULT_TEXTURE_PREVIEW_SIZE = 128
local MIN_TEXTURE_PAIR_SPACING = -5
local MAX_TEXTURE_PAIR_SPACING = 5
local MIN_TEXTURE_ROTATION = -180
local MAX_TEXTURE_ROTATION = 180
local MIN_TEXTURE_STRETCH = -0.75
local MAX_TEXTURE_STRETCH = 2
local TEXTURE_INDICATOR_EFFECT_OPTIONS = {
    pulse = "Pulse",
    colorShift = "Color Shift",
    shrinkExpand = "Shrink / Expand",
    bounce = "Bounce",
}
local TEXTURE_INDICATOR_EFFECT_ORDER = {
    "pulse",
    "colorShift",
    "shrinkExpand",
    "bounce",
}
local TEXTURE_INDICATOR_SECTION_DEFS = {
    proc = {
        label = "Show Proc Effect",
        previewText = "Preview Proc Effect",
    },
    aura = {
        label = "Show Aura Effect",
        previewText = "Preview Aura Effect",
    },
    pandemic = {
        label = "Show Pandemic Effect",
        previewText = "Preview Pandemic Effect",
    },
    ready = {
        label = "Show Ready Effect",
        previewText = "Preview Ready Effect",
    },
    unusable = {
        label = "Show Unusable Effect",
        previewText = "Preview Unusable Effect",
    },
}

local function GetTextureIndicatorStore(group)
    return CooldownCompanion:GetTexturePanelIndicatorSettings(group, true)
end

local TRIGGER_PANEL_EFFECT_DEFS = {
    pulse = {
        label = "Pulse",
        speedLabel = "Pulse Duration",
    },
    colorShift = {
        label = "Color Shift",
        speedLabel = "Shift Duration",
    },
    shrinkExpand = {
        label = "Shrink / Expand",
        speedLabel = "Cycle Duration",
    },
    bounce = {
        label = "Bounce",
        speedLabel = "Bounce Duration",
    },
}

local function GetTriggerPanelEffectStore(group)
    return CooldownCompanion:GetTriggerPanelEffectSettings(group, true)
end

local function GetTextureIndicatorUsedEffects(indicators, currentSectionKey)
    local used = {}
    if type(indicators) ~= "table" then
        return used
    end

    for sectionKey, sectionData in pairs(indicators) do
        if sectionKey ~= currentSectionKey and type(sectionData) == "table" and sectionData.enabled and type(sectionData.effectType) == "string" and sectionData.effectType ~= "none" then
            used[sectionData.effectType] = true
        end
    end

    return used
end

local function GetTextureIndicatorEffectList(indicators, currentSectionKey)
    local used = GetTextureIndicatorUsedEffects(indicators, currentSectionKey)
    local list = {}
    local order = {}
    local current = indicators and indicators[currentSectionKey] and indicators[currentSectionKey].effectType or nil

    for _, effectKey in ipairs(TEXTURE_INDICATOR_EFFECT_ORDER) do
        if effectKey == current or not used[effectKey] then
            list[effectKey] = TEXTURE_INDICATOR_EFFECT_OPTIONS[effectKey]
            order[#order + 1] = effectKey
        end
    end

    return list, order
end

local function GetFirstAvailableTextureIndicatorEffect(indicators, currentSectionKey)
    local _, order = GetTextureIndicatorEffectList(indicators, currentSectionKey)
    return order[1]
end

local SCREEN_LOCATION = Enum and Enum.ScreenLocationType or {}
local PREVIEW_LOCATION_LEFTRIGHT = SCREEN_LOCATION.LeftRight or 9
local PREVIEW_LOCATION_TOPBOTTOM = SCREEN_LOCATION.TopBottom or 10

local function ApplyTexturePreviewSource(texture, settings)
    if not texture or type(settings) ~= "table" then
        return false
    end

    local resolvedSourceType, resolvedSourceValue = CooldownCompanion:ResolveAuraTextureAsset(
        settings.sourceType,
        settings.sourceValue,
        settings.mediaType
    )

    if resolvedSourceType == "atlas" then
        texture:SetAtlas(resolvedSourceValue, false)
        texture:Show()
        return true
    end

    if resolvedSourceType == "file" and resolvedSourceValue ~= nil then
        texture:SetTexture(resolvedSourceValue)
        texture:Show()
        return true
    end

    texture:Hide()
    return false
end

local function ApplyTexturePreviewVisual(texture, settings, alpha, flipH, flipV, rotationRadians)
    if not texture or type(settings) ~= "table" then
        return
    end

    local color = settings.color or { 1, 1, 1, 1 }
    texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha or 1)
    texture:SetBlendMode(settings.blendMode or "BLEND")

    local left = flipH and 1 or 0
    local right = flipH and 0 or 1
    local top = flipV and 1 or 0
    local bottom = flipV and 0 or 1
    texture:SetTexCoord(left, right, top, bottom)
    texture:SetRotation(rotationRadians or 0)
end

local function UpdateTexturePanelPreview(preview, settings)
    if type(preview) ~= "table" then
        return
    end

    local hasTexture = type(settings) == "table"
        and settings.sourceType ~= nil
        and settings.sourceValue ~= nil

    if preview.nameLabel and preview.nameLabel.SetText then
        preview.nameLabel:SetText(hasTexture and (settings.label or tostring(settings.sourceValue)) or "No texture selected")
    end
    preview.placeholder:SetShown(not hasTexture)
    preview.primary:Hide()
    preview.secondary:Hide()

    if not hasTexture then
        return
    end

    local scale = tonumber(settings.scale) or 1
    local baseWidth = (tonumber(settings.width) or DEFAULT_TEXTURE_PREVIEW_SIZE) * scale
    local baseHeight = (tonumber(settings.height) or DEFAULT_TEXTURE_PREVIEW_SIZE) * scale
    local geometry = CooldownCompanion:BuildTexturePanelGeometry(settings, baseWidth, baseHeight)
    local maxWidth = TEXTURE_PREVIEW_WIDTH - 8
    local maxHeight = TEXTURE_PREVIEW_HEIGHT - 8
    local fit = math_min(maxWidth / math_max(geometry.boundsWidth, 1), maxHeight / math_max(geometry.boundsHeight, 1), 1)

    local color = settings.color or { 1, 1, 1, 1 }
    local alpha = math_min(math_max((color[4] or 1) * (settings.alpha or 1), 0.05), 1)
    local primary = preview.primary
    local secondary = preview.secondary
    local shown = false
    local textures = { primary, secondary }

    for index, texture in ipairs(textures) do
        local piece = geometry.pieces[index]
        texture:ClearAllPoints()
        if not piece then
            texture:Hide()
        else
            texture:SetSize(math_max(8, geometry.pieceWidth * fit), math_max(8, geometry.pieceHeight * fit))
            texture:SetPoint("CENTER", preview.anchor, "CENTER", piece.centerX * fit, piece.centerY * fit)
            if ApplyTexturePreviewSource(texture, settings) then
                ApplyTexturePreviewVisual(texture, settings, alpha, piece.flipH, piece.flipV, geometry.rotationRadians)
                shown = true
            else
                texture:Hide()
            end
        end
    end

    preview.placeholder:SetShown(not shown)
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

local function GetStandaloneTextureSettings(group, createIfMissing)
    if not group then
        return nil
    end
    if group.displayMode == "trigger" then
        return CooldownCompanion:GetTriggerPanelSignalSettings(group, createIfMissing)
    end
    return CooldownCompanion:GetTexturePanelSettings(group, createIfMissing)
end

local function GetStandaloneTextureSelectionLabel(group, settings)
    if not settings or not settings.sourceType then
        return nil
    end
    return settings.label or tostring(settings.sourceValue)
end

local function GetStandaloneTextureCommitCallback(group)
    return function(selection)
        local liveSettings = GetStandaloneTextureSettings(group, true)
        if not liveSettings then
            return
        end

        if selection then
            CooldownCompanion:ApplyTexturePanelEntry(liveSettings, selection)
        else
            liveSettings.libraryKey = nil
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

local function OpenOrRebindStandaloneTexturePicker(group, settings, forceOpen)
    if not (group and CS.StartPickAuraTexture) then
        return
    end

    local buttonIndex
    if group.displayMode == "trigger" then
        buttonIndex = nil
    else
        buttonIndex = group.buttons and group.buttons[1] and 1 or nil
    end
    local pickerOpts = {
        groupId = CS.selectedGroup,
        buttonIndex = buttonIndex,
        initialSelection = settings and settings.sourceType and settings or nil,
        callback = GetStandaloneTextureCommitCallback(group),
    }

    if forceOpen or not (CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen()) then
        CS.StartPickAuraTexture(pickerOpts)
    elseif CS.RebindPickAuraTexture then
        CS.RebindPickAuraTexture(pickerOpts)
    end
end

local TRIGGER_DISPLAY_TYPE_OPTIONS = {
    texture = "Texture",
    icon = "Icon",
    text = "Text",
}

local TRIGGER_DISPLAY_TYPE_ORDER = {
    "texture",
    "icon",
    "text",
}

local function RefreshStandaloneTriggerDisplay(groupId)
    local groupFrame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    local button = groupFrame and groupFrame.buttons and groupFrame.buttons[1] or nil
    if button then
        CooldownCompanion:UpdateAuraTextureVisual(button)
    else
        CooldownCompanion:RefreshAllAuraTextureVisuals()
    end
end

local function AddTriggerDisplayTypeDropdown(container, group)
    local displayDrop = AceGUI:Create("Dropdown")
    displayDrop:SetLabel("Display Type")
    displayDrop:SetList(TRIGGER_DISPLAY_TYPE_OPTIONS, TRIGGER_DISPLAY_TYPE_ORDER)
    displayDrop:SetValue(CooldownCompanion:GetTriggerPanelDisplayType(group, true))
    displayDrop:SetFullWidth(true)
    displayDrop:SetCallback("OnValueChanged", function(_, _, value)
        local triggerSettings = group.triggerSettings or {}
        group.triggerSettings = triggerSettings
        triggerSettings.displayType = value or "texture"
        CooldownCompanion:ClearAllAuraTexturePickerPreviews()
        RefreshStandaloneTriggerDisplay(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(displayDrop)
end

local function CreateTriggerPreviewCanvas(container, height)
    local previewGroup = AceGUI:Create("SimpleGroup")
    previewGroup:SetFullWidth(true)
    previewGroup:SetHeight(height)
    previewGroup:SetLayout("Fill")
    container:AddChild(previewGroup)

    local previewFrame = CreateFrame("Frame", nil, previewGroup.frame)
    previewFrame:SetPoint("TOP", previewGroup.frame, "TOP", 0, -2)
    previewFrame:SetSize(TEXTURE_PREVIEW_WIDTH, height - 4)
    appearanceTabElements[#appearanceTabElements + 1] = previewFrame

    local previewShade = previewFrame:CreateTexture(nil, "BACKGROUND")
    previewShade:SetAllPoints()
    previewShade:SetColorTexture(0, 0, 0, 0.42)

    return previewFrame
end

local function FitPreviewContentToCanvas(contentFrame, canvasFrame, contentWidth, contentHeight, padding)
    if not contentFrame or not canvasFrame then
        return
    end

    padding = padding or 8
    local canvasWidth = canvasFrame:GetWidth() or TEXTURE_PREVIEW_WIDTH
    local canvasHeight = canvasFrame:GetHeight() or 0
    local availableWidth = math_max(1, canvasWidth - (padding * 2))
    local availableHeight = math_max(1, canvasHeight - (padding * 2))
    local widthScale = availableWidth / math_max(1, contentWidth or 1)
    local heightScale = availableHeight / math_max(1, contentHeight or 1)
    local scale = math_min(1, widthScale, heightScale)
    contentFrame:SetScale(scale)
end

local function BuildTriggerIconAppearanceTab(container, group)
    local settings = CooldownCompanion:GetTriggerPanelIconSettings(group, true)
    local groupId = CS.selectedGroup

    local heading = AceGUI:Create("Heading")
    heading:SetText("Trigger Icon")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local previewFrame = CreateTriggerPreviewCanvas(container, TEXTURE_PREVIEW_HEIGHT + 4)
    local iconHolder = CreateFrame("Frame", nil, previewFrame)
    iconHolder:SetPoint("CENTER")
    iconHolder:SetSize(DEFAULT_TEXTURE_PREVIEW_SIZE, DEFAULT_TEXTURE_PREVIEW_SIZE)

    local previewBg = iconHolder:CreateTexture(nil, "BACKGROUND")
    previewBg:SetAllPoints()

    local previewIcon = iconHolder:CreateTexture(nil, "ARTWORK")
    local previewBorders = {}
    for index = 1, 4 do
        previewBorders[index] = iconHolder:CreateTexture(nil, "OVERLAY")
    end
    local clearBtn

    local placeholder = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    placeholder:SetPoint("CENTER")
    placeholder:SetJustifyH("CENTER")
    placeholder:SetText("No icon selected")
    placeholder:SetTextColor(0.65, 0.65, 0.65, 1)

    local function RefreshIconPreview()
        local width = settings.maintainAspectRatio and (settings.buttonSize or ST.BUTTON_SIZE)
            or (settings.iconWidth or settings.buttonSize or ST.BUTTON_SIZE)
        local height = settings.maintainAspectRatio and (settings.buttonSize or ST.BUTTON_SIZE)
            or (settings.iconHeight or settings.buttonSize or ST.BUTTON_SIZE)
        local borderSize = settings.borderSize or ST.DEFAULT_BORDER_SIZE
        local borderRenderMode = ST.GetBorderRenderMode(settings)
        local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(iconHolder, borderSize, borderRenderMode)
        local bgColor = settings.backgroundColor or { 0, 0, 0, 0.5 }
        local borderColor = settings.borderColor or { 0, 0, 0, 1 }
        local tintColor = settings.iconTintColor or { 1, 1, 1, 1 }
        local hasIcon = ST._IsValidIconTexture(settings.manualIcon)

        iconHolder:SetSize(width, height)
        previewIcon:ClearAllPoints()
        previewIcon:SetPoint("TOPLEFT", borderLayoutSize, -borderLayoutSize)
        previewIcon:SetPoint("BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)

        if hasIcon then
            previewBg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] ~= nil and bgColor[4] or 0.5)
            previewBg:Show()
            for _, border in ipairs(previewBorders) do
                border:SetColorTexture(borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0, borderColor[4] ~= nil and borderColor[4] or 1)
                border:Show()
            end
            ApplyBorderEdgePositions(previewBorders, iconHolder, borderSize, borderRenderMode)
            previewIcon:SetTexture(settings.manualIcon)
            previewIcon:SetVertexColor(tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1, tintColor[4] ~= nil and tintColor[4] or 1)
            ApplyIconTexCoord(previewIcon, width, height)
            previewIcon:Show()
            placeholder:Hide()
        else
            previewBg:Hide()
            for _, border in ipairs(previewBorders) do
                border:Hide()
            end
            previewIcon:Hide()
            placeholder:Show()
        end

        if clearBtn then
            clearBtn:SetDisabled(not hasIcon)
        end

        RefreshStandaloneTriggerDisplay(groupId)
    end

    local actionRow = AceGUI:Create("SimpleGroup")
    actionRow:SetFullWidth(true)
    actionRow:SetLayout("Flow")
    container:AddChild(actionRow)

    local browseBtn = AceGUI:Create("Button")
    browseBtn:SetText("Choose Icon")
    browseBtn:SetRelativeWidth(0.49)
    browseBtn:SetCallback("OnClick", function()
        OpenTriggerPanelIconPicker(groupId)
    end)
    actionRow:AddChild(browseBtn)

    clearBtn = AceGUI:Create("Button")
    clearBtn:SetText("Clear")
    clearBtn:SetRelativeWidth(0.49)
    clearBtn:SetDisabled(not ST._IsValidIconTexture(settings.manualIcon))
    clearBtn:SetCallback("OnClick", function()
        settings.manualIcon = nil
        RefreshIconPreview()
        CooldownCompanion:RefreshConfigPanel()
    end)
    actionRow:AddChild(clearBtn)

    local squareCb = AceGUI:Create("CheckBox")
    squareCb:SetLabel("Square Icons")
    squareCb:SetValue(settings.maintainAspectRatio ~= false)
    squareCb:SetFullWidth(true)
    squareCb:SetCallback("OnValueChanged", function(_, _, value)
        settings.maintainAspectRatio = value ~= false
        if settings.maintainAspectRatio then
            local size = settings.buttonSize or ST.BUTTON_SIZE
            settings.iconWidth = size
            settings.iconHeight = size
        end
        RefreshIconPreview()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(squareCb)

    if settings.maintainAspectRatio ~= false then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Button Size")
        sizeSlider:SetSliderValues(10, 150, 0.1)
        sizeSlider:SetValue(settings.buttonSize or ST.BUTTON_SIZE)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(_, _, value)
            settings.buttonSize = value
            settings.iconWidth = value
            settings.iconHeight = value
            RefreshIconPreview()
        end)
        HookSliderEditBox(sizeSlider)
        container:AddChild(sizeSlider)
    else
        local widthSlider = AceGUI:Create("Slider")
        widthSlider:SetLabel("Icon Width")
        widthSlider:SetSliderValues(10, 150, 0.1)
        widthSlider:SetValue(settings.iconWidth or settings.buttonSize or ST.BUTTON_SIZE)
        widthSlider:SetFullWidth(true)
        widthSlider:SetCallback("OnValueChanged", function(_, _, value)
            settings.iconWidth = value
            RefreshIconPreview()
        end)
        HookSliderEditBox(widthSlider)
        container:AddChild(widthSlider)

        local heightSlider = AceGUI:Create("Slider")
        heightSlider:SetLabel("Icon Height")
        heightSlider:SetSliderValues(10, 150, 0.1)
        heightSlider:SetValue(settings.iconHeight or settings.buttonSize or ST.BUTTON_SIZE)
        heightSlider:SetFullWidth(true)
        heightSlider:SetCallback("OnValueChanged", function(_, _, value)
            settings.iconHeight = value
            RefreshIconPreview()
        end)
        HookSliderEditBox(heightSlider)
        container:AddChild(heightSlider)
    end

    local renderMode = AddBorderRenderModeDropdown(container, settings, "borderRenderMode", function()
        RefreshIconPreview()
        CooldownCompanion:RefreshConfigPanel()
    end)
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSlider = AceGUI:Create("Slider")
        borderSlider:SetLabel("Border Size")
        borderSlider:SetSliderValues(0, 5, 0.1)
        borderSlider:SetValue(settings.borderSize or ST.DEFAULT_BORDER_SIZE)
        borderSlider:SetFullWidth(true)
        borderSlider:SetDisabled(borderThicknessLocked)
        borderSlider:SetCallback("OnValueChanged", function(_, _, value)
            if borderThicknessLocked then return end
            settings.borderSize = value
            RefreshIconPreview()
        end)
        HookSliderEditBox(borderSlider)
        container:AddChild(borderSlider)
    end

    AddColorPicker(container, settings, "borderColor", "Border Color", { 0, 0, 0, 1 }, true, RefreshIconPreview, RefreshIconPreview)
    AddColorPicker(container, settings, "iconTintColor", "Base Icon Color", { 1, 1, 1, 1 }, true, RefreshIconPreview, RefreshIconPreview)
    AddColorPicker(container, settings, "backgroundColor", "Background Color", { 0, 0, 0, 0.5 }, true, RefreshIconPreview, RefreshIconPreview)

    RefreshIconPreview()
end

local function BuildTriggerTextAppearanceTab(container, group)
    local settings = CooldownCompanion:GetTriggerPanelTextSettings(group, true)
    local groupId = CS.selectedGroup
    local maxTextLength = CooldownCompanion.TRIGGER_PANEL_TEXT_MAX_LENGTH or 120
    local maxTextLines = CooldownCompanion.TRIGGER_PANEL_TEXT_MAX_LINES or 4

    local heading = AceGUI:Create("Heading")
    heading:SetText("Trigger Text")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local previewFrame = CreateTriggerPreviewCanvas(container, 120)
    local textHolder = CreateFrame("Frame", nil, previewFrame)
    textHolder:SetPoint("CENTER")
    textHolder:SetSize(1, 1)

    local previewBg = textHolder:CreateTexture(nil, "BACKGROUND")
    previewBg:SetAllPoints()

    local previewBorders = {}
    for index = 1, 4 do
        previewBorders[index] = textHolder:CreateTexture(nil, "OVERLAY")
    end

    local previewText = textHolder:CreateFontString(nil, "OVERLAY")
    previewText:SetJustifyV("MIDDLE")
    previewText:SetJustifyH("CENTER")
    previewText:SetWordWrap(false)
    previewText:SetMaxLines(0)

    local placeholder = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    placeholder:SetPoint("CENTER")
    placeholder:SetJustifyH("CENTER")
    placeholder:SetText("No text entered")
    placeholder:SetTextColor(0.65, 0.65, 0.65, 1)

    local function RefreshTextPreview()
        local bgColor = settings.textBgColor or { 0, 0, 0, 0 }
        local fontColor = settings.textFontColor or { 1, 1, 1, 1 }
        local textAlignment = settings.textAlignment or "CENTER"
        local hasText = CooldownCompanion.HasTriggerTextValue(settings)
        local insetX = 2
        local insetY = 1

        textHolder:SetScale(1)
        if hasText then
            local frameWidth, frameHeight, textWidth, textHeight, lineCount
            frameWidth, frameHeight, insetX, insetY, textWidth, textHeight, lineCount = CooldownCompanion.GetTriggerTextDisplayMetrics(previewText, settings)
            textHolder:SetSize(frameWidth, frameHeight)
            textHolder:ClearAllPoints()
            textHolder:SetPoint("CENTER", previewFrame, "CENTER", 0, 0)
            previewText:SetSize(textWidth or math_max(1, frameWidth - (insetX * 2)), textHeight or math_max(1, frameHeight - (insetY * 2)))
            previewText:SetWordWrap((lineCount or 1) > 1)
            previewText:SetJustifyV((lineCount or 1) > 1 and "TOP" or "MIDDLE")
            FitPreviewContentToCanvas(textHolder, previewFrame, frameWidth, frameHeight, 8)
        else
            textHolder:SetSize(1, 1)
            textHolder:ClearAllPoints()
            textHolder:SetPoint("CENTER", previewFrame, "CENTER", 0, 0)
            previewText:SetSize(1, 1)
            previewText:SetWordWrap(false)
            previewText:SetJustifyV("MIDDLE")
        end
        previewBg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] ~= nil and bgColor[4] or 0)
        for _, border in ipairs(previewBorders) do
            border:Hide()
        end

        previewText:ClearAllPoints()
        previewText:SetPoint("TOPLEFT", textHolder, "TOPLEFT", insetX, -insetY)
        previewText:SetPoint("BOTTOMRIGHT", textHolder, "BOTTOMRIGHT", -insetX, insetY)
        previewText:SetJustifyH(textAlignment)
        previewText:SetTextColor(fontColor[1] or 1, fontColor[2] or 1, fontColor[3] or 1, fontColor[4] ~= nil and fontColor[4] or 1)
        previewText:SetShown(hasText)
        placeholder:SetShown(not hasText)

        RefreshStandaloneTriggerDisplay(groupId)
    end

    local textBox = AceGUI:Create("MultiLineEditBox")
    textBox:SetLabel("Display Text")
    textBox:SetFullWidth(true)
    textBox:SetNumLines(maxTextLines)
    textBox.button:Hide()
    textBox:SetText(settings.value or "")
    local function HandleTextChanged(widget, _, value)
        local sanitized = CooldownCompanion.SanitizeTriggerPanelTextValue and CooldownCompanion.SanitizeTriggerPanelTextValue(value) or (value or "")
        settings.value = sanitized
        if widget and widget.SetText and widget:GetText() ~= sanitized and not widget._ccSyncingText then
            widget._ccSyncingText = true
            widget:SetText(sanitized)
            widget._ccSyncingText = nil
        end
        RefreshTextPreview()
    end
    textBox:SetCallback("OnTextChanged", HandleTextChanged)
    container:AddChild(textBox)

    local limitLabel = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(limitLabel)
    limitLabel:SetFullWidth(true)
    limitLabel:SetText("Up to " .. maxTextLines .. " lines and " .. maxTextLength .. " total characters.")
    limitLabel:SetColor(0.7, 0.7, 0.7)
    container:AddChild(limitLabel)

    AddFontControls(container, settings, "text", {
        size = 12,
        sizeMin = 6,
        sizeMax = 72,
        font = "Friz Quadrata TT",
        outline = "OUTLINE",
    }, RefreshTextPreview)

    local alignDrop = AceGUI:Create("Dropdown")
    alignDrop:SetLabel("Alignment")
    alignDrop:SetList({ LEFT = "Left", CENTER = "Center", RIGHT = "Right" })
    alignDrop:SetValue(settings.textAlignment or "CENTER")
    alignDrop:SetFullWidth(true)
    alignDrop:SetCallback("OnValueChanged", function(_, _, value)
        settings.textAlignment = value
        RefreshTextPreview()
    end)
    container:AddChild(alignDrop)

    AddColorPicker(container, settings, "textFontColor", "Text Color", { 1, 1, 1, 1 }, true, RefreshTextPreview, RefreshTextPreview)
    AddColorPicker(container, settings, "textBgColor", "Background Color", { 0, 0, 0, 0 }, true, RefreshTextPreview, RefreshTextPreview)

    RefreshTextPreview()
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
    local function IsResolvedExternalFrameAnchorTarget(frameName)
        if type(frameName) ~= "string" or frameName == "" or frameName == "UIParent" then
            return false
        end
        if CooldownCompanion.ParseAddonAnchorFrameName
            and CooldownCompanion:ParseAddonAnchorFrameName(frameName) ~= nil then
            return false
        end
        local target = _G[frameName]
        return type(target) == "table" and type(target.GetObjectType) == "function"
    end
    local function GetPanelAlphaControlDisabledState(groupId, targetMode, panelAlphaInherited)
        if CooldownCompanion.GetPanelContainerAlphaSource
            and CooldownCompanion:GetPanelContainerAlphaSource(groupId) then
            return true, "Group Alpha is enabled. This panel uses the group's Alpha settings."
        end

        if panelAlphaInherited then
            if targetMode == "frame" then
                return true, "This panel inherits alpha from the target frame. Change the Panel Alpha setting to use custom alpha."
            end
            return true, "This panel inherits alpha from the parent panel. Change the parent panel's Alpha settings to affect it."
        end

        return false, nil
    end

    CooldownCompanion:ClearAllTextureIndicatorPreviews()
    if CooldownCompanion.ClearAllTriggerPanelEffectPreviews then
        CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    end

    if group.displayMode == "textures" or group.displayMode == "trigger" then
        local settings = GetStandaloneTextureSettings(group, true)
        if not settings then
            return
        end
        local textureGroupId = CS.selectedGroup
        local isTriggerPanel = group.displayMode == "trigger"
        local positionHeadingText = isTriggerPanel and "Trigger Display Position" or "Texture Position"
        local anchorLabel = isTriggerPanel and "Display Point" or "Texture Point"
        local defaultFrame = group.parentContainerId and ("CooldownCompanionContainer" .. group.parentContainerId) or "UIParent"
        local cursorAnchorTarget = CooldownCompanion.GetCursorAnchorTargetName
            and CooldownCompanion:GetCursorAnchorTargetName()
            or ST.CURSOR_ANCHOR_TARGET
            or "CooldownCompanionCursor"
        local isCursorAnchor = CooldownCompanion.IsCursorAnchor
            and CooldownCompanion:IsCursorAnchor(group.anchor)
            or false
        local canUseCursorAnchor = CooldownCompanion:CanGroupUseCursorAnchor(group)
        if isCursorAnchor and not canUseCursorAnchor then
            isCursorAnchor = false
        end

        settings.relativeTo = type(settings.relativeTo) == "string" and settings.relativeTo ~= "" and settings.relativeTo or "UIParent"
        local isPanel = group.parentContainerId ~= nil
        local function ResetStandalonePosition(relativeTo, point, relativePoint, x, y)
            settings.point = point or "CENTER"
            settings.relativeTo = relativeTo or "UIParent"
            settings.relativePoint = relativePoint or "CENTER"
            settings.x = x or 0
            settings.y = y or 0
        end
        local function GetStandaloneAnchorValidationOptions()
            return CooldownCompanion:GetGroupAnchorValidationOptions(textureGroupId)
        end
        local function SetStandalonePanelAnchorTarget(targetGroupId)
            local targetFrameName = "CooldownCompanionGroup" .. tostring(targetGroupId)
            local options = GetStandaloneAnchorValidationOptions()
            local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(targetFrameName, options)
            if not ok then
                CooldownCompanion:PrintInvalidAnchorTargetReason(targetFrameName, options)
                return false
            end
            ResetStandalonePosition(targetFrameName, "TOPLEFT", "BOTTOMLEFT", 0, -5)
            group.inheritPanelAlpha = group.inheritPanelAlpha ~= false
            return true
        end
        local function SetStandaloneFrameAnchorTarget(targetFrameName)
            if type(targetFrameName) ~= "string" or targetFrameName == "" then
                ResetStandalonePosition()
                return true
            end
            local target = _G[targetFrameName]
            if not target or type(target) ~= "table" or not target.GetObjectType then
                CooldownCompanion:Print("Frame not found: " .. targetFrameName)
                return false
            end
            local options = GetStandaloneAnchorValidationOptions()
            local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(targetFrameName, options)
            if not ok then
                CooldownCompanion:PrintInvalidAnchorTargetReason(targetFrameName, options)
                return false
            end
            ResetStandalonePosition(targetFrameName, "TOPLEFT", "BOTTOMLEFT", 0, -5)
            return true
        end
        local anchorKind, currentAnchorGroupId
        anchorKind, currentAnchorGroupId = CooldownCompanion:ParseAddonAnchorFrameName(settings.relativeTo)
        local currentAnchorIsPanel = anchorKind == "group"
            and isPanel
            and CooldownCompanion.IsPanelAnchoredToPanel
            and CooldownCompanion:IsPanelAnchoredToPanel(textureGroupId)
            or false
        if not currentAnchorIsPanel then
            currentAnchorGroupId = nil
        end
        CS.layoutAnchorTargetMode = CS.layoutAnchorTargetMode or {}
        local storedTargetMode = CS.layoutAnchorTargetMode[textureGroupId]
        local targetMode
        if isCursorAnchor then
            targetMode = "cursor"
        elseif currentAnchorIsPanel then
            targetMode = "panel"
        elseif settings.relativeTo ~= "UIParent" then
            targetMode = "frame"
        elseif storedTargetMode == "panel" and isPanel then
            targetMode = "panel"
        elseif storedTargetMode == "frame" then
            targetMode = "frame"
        else
            targetMode = "group"
        end
        local hasFrameAnchorTarget = isPanel
            and targetMode == "frame"
            and IsResolvedExternalFrameAnchorTarget(settings.relativeTo)

        local function RefreshTextureVisual()
            CooldownCompanion:RefreshAllAuraTextureVisuals()
        end

        local function RefreshCursorAnchor()
            local frame = CooldownCompanion.groupFrames[textureGroupId]
            if frame then
                CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
            end
            RefreshTextureVisual()
        end

        if targetMode == "cursor" then
            CooldownCompanion:ShowCursorAnchorLayoutPreview(textureGroupId)
        else
            CooldownCompanion:ClearCursorAnchorLayoutPreview()
        end

        local anchorTargetDrop = AceGUI:Create("Dropdown")
        anchorTargetDrop:SetLabel("Anchor Target")
        local anchorTargetList = isPanel
            and {
                group = "Group",
                panel = "Panel",
                frame = "Frame",
                cursor = "Cursor",
            }
            or {
                group = group.parentContainerId and "Group" or "Screen",
                frame = "Frame",
            }
        local anchorTargetOrder = isPanel
            and (canUseCursorAnchor and { "group", "panel", "frame", "cursor" } or { "group", "panel", "frame" })
            or { "group", "frame" }
        if not canUseCursorAnchor then
            anchorTargetList.cursor = nil
        end
        anchorTargetDrop:SetList(anchorTargetList, anchorTargetOrder)
        anchorTargetDrop:SetValue(targetMode)
        anchorTargetDrop:SetFullWidth(true)
        anchorTargetDrop:SetCallback("OnValueChanged", function(widget, event, val)
            if val == targetMode then return end
            if val == "cursor" then
                if not canUseCursorAnchor then
                    widget:SetValue("group")
                    return
                end
                if CooldownCompanion:SetGroupAnchor(CS.selectedGroup, cursorAnchorTarget) then
                    CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
                    ResetStandalonePosition()
                    CooldownCompanion:RefreshConfigPanel()
                else
                    widget:SetValue(targetMode)
                end
            elseif val == "group" then
                CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
                ResetStandalonePosition()
                CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, true)
                CooldownCompanion:RefreshConfigPanel()
            elseif val == "panel" then
                if isCursorAnchor and not CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, true) then
                    widget:SetValue(targetMode)
                    return
                end
                ResetStandalonePosition()
                CS.layoutAnchorTargetMode[CS.selectedGroup] = "panel"
                CooldownCompanion:RefreshConfigPanel()
            elseif val == "frame" then
                if isCursorAnchor and not CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, true) then
                    widget:SetValue(targetMode)
                    return
                end
                ResetStandalonePosition()
                CS.layoutAnchorTargetMode[CS.selectedGroup] = "frame"
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
        container:AddChild(anchorTargetDrop)

        if targetMode == "frame" then
            local anchorRow = AceGUI:Create("SimpleGroup")
            anchorRow:SetFullWidth(true)
            anchorRow:SetLayout("Flow")

            local anchorBox = AceGUI:Create("EditBox")
            if anchorBox.editbox.Instructions then anchorBox.editbox.Instructions:Hide() end
            anchorBox:SetLabel("Anchor to Frame")
            local frameAnchorText = settings.relativeTo
            if frameAnchorText == "UIParent" or currentAnchorGroupId then frameAnchorText = "" end
            anchorBox:SetText(frameAnchorText)
            anchorBox:SetRelativeWidth(0.68)
            anchorBox:SetCallback("OnEnterPressed", function(widget, event, text)
                if SetStandaloneFrameAnchorTarget(text) then
                    CooldownCompanion:RefreshAllAuraTextureVisuals()
                    CooldownCompanion:RefreshConfigPanel()
                else
                    widget:SetText(frameAnchorText)
                end
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
                        SetStandaloneFrameAnchorTarget(name)
                    end
                    CooldownCompanion:RefreshAllAuraTextureVisuals()
                    CooldownCompanion:RefreshConfigPanel()
                end, grp)
            end)
            anchorRow:AddChild(pickBtn)

            CreateInfoButton(pickBtn.frame, pickBtn.frame, "LEFT", "RIGHT", 2, 0, {
                "Pick Frame",
                {"Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this panel to it, or right-click to cancel.", 1, 1, 1, true},
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
        end

        if targetMode == "panel" then
            local panelAnchorDrop = AceGUI:Create("Dropdown")
            panelAnchorDrop:SetLabel("Anchor to Panel")
            CooldownCompanion:PopulatePanelAnchorTargetDropdown(panelAnchorDrop, textureGroupId)
            panelAnchorDrop:SetFullWidth(true)
            panelAnchorDrop:SetValue(currentAnchorGroupId and tostring(currentAnchorGroupId) or nil)
            panelAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
                if not val or val == "" then return end
                local targetGroupId = tonumber(val)
                if targetGroupId and SetStandalonePanelAnchorTarget(targetGroupId) then
                    CooldownCompanion:RefreshAllAuraTextureVisuals()
                    CooldownCompanion:RefreshConfigPanel()
                else
                    widget:SetValue(currentAnchorGroupId and tostring(currentAnchorGroupId) or nil)
                end
            end)
            container:AddChild(panelAnchorDrop)
        end

        if isPanel and (targetMode == "panel" or hasFrameAnchorTarget) then
            local panelAlphaDrop = AceGUI:Create("Dropdown")
            panelAlphaDrop:SetLabel("Panel Alpha")
            panelAlphaDrop:SetList({
                inherit = targetMode == "frame" and "Inherit Target Frame Alpha" or "Inherit Target Panel Alpha",
                custom = "Custom Alpha",
            }, { "inherit", "custom" })
            panelAlphaDrop:SetValue(group.inheritPanelAlpha == false and "custom" or "inherit")
            panelAlphaDrop:SetFullWidth(true)
            panelAlphaDrop:SetCallback("OnValueChanged", function(widget, event, val)
                group.inheritPanelAlpha = val ~= "custom"
                CooldownCompanion:RefreshAllAuraTextureVisuals()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(panelAlphaDrop)
        end

        local heading = AceGUI:Create("Heading")
        heading:SetText(targetMode == "cursor" and "Cursor Offset" or positionHeadingText)
        ColorHeading(heading)
        heading:SetFullWidth(true)
        container:AddChild(heading)

        if targetMode == "cursor" then
            AddAnchorDropdown(container, group.anchor, "point", "BOTTOMLEFT", RefreshCursorAnchor, "Panel Point")
            group.anchor.relativePoint = "CENTER"
            AddOffsetSliders(container, group.anchor, "x", "y", {
                x = 16,
                y = 16,
                range = 2000,
                step = 1,
            }, RefreshCursorAnchor)

            local resetBtn = AceGUI:Create("Button")
            resetBtn:SetText("Reset Cursor Offset")
            resetBtn:SetFullWidth(true)
            resetBtn:SetCallback("OnClick", function()
                group.anchor = CooldownCompanion.GetDefaultCursorPanelAnchor
                    and CooldownCompanion:GetDefaultCursorPanelAnchor()
                    or {
                        point = "BOTTOMLEFT",
                        relativeTo = cursorAnchorTarget,
                        relativePoint = "CENTER",
                        x = 16,
                        y = 16,
                    }
                RefreshCursorAnchor()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(resetBtn)
        else
            AddAnchorDropdown(container, settings, "point", "CENTER", RefreshTextureVisual, anchorLabel)
            AddAnchorDropdown(container, settings, "relativePoint", "CENTER", RefreshTextureVisual, (targetMode == "panel" or targetMode == "frame") and "Target Point" or "Screen Point")
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
                if (targetMode == "panel" or targetMode == "frame") and settings.relativeTo ~= "UIParent" then
                    ResetStandalonePosition(settings.relativeTo, "TOPLEFT", "BOTTOMLEFT", 0, -5)
                else
                    ResetStandalonePosition()
                end
                CooldownCompanion:RefreshAllAuraTextureVisuals()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(resetBtn)
        end

        local panelAlphaInherited = false
        if targetMode == "panel"
            and currentAnchorGroupId
            and CooldownCompanion.ShouldInheritPanelAnchorAlpha then
            panelAlphaInherited = CooldownCompanion:ShouldInheritPanelAnchorAlpha(textureGroupId)
        elseif hasFrameAnchorTarget then
            panelAlphaInherited = group.inheritPanelAlpha ~= false
        end
        local alphaControlsDisabled, alphaDisabledText = GetPanelAlphaControlDisabledState(textureGroupId, targetMode, panelAlphaInherited)

        BuildAlphaControls(container, group, function()
            CooldownCompanion:RefreshAllAuraTextureVisuals()
            CooldownCompanion:RefreshConfigPanel()
        end, "layout_alpha", {
            isGlobal = group.isGlobal,
            disabled = alphaControlsDisabled,
            disabledText = alphaDisabledText,
            onBaselineChanged = function(val)
                CS.texturePanelAlphaPreview = CS.texturePanelAlphaPreview or {}
                CS.texturePanelAlphaPreview[textureGroupId] = val

                local alphaModuleId = "texture_panel_" .. tostring(textureGroupId)
                CooldownCompanion.alphaState = CooldownCompanion.alphaState or {}
                local state = CooldownCompanion.alphaState[alphaModuleId]
                if not state then
                    state = {}
                    CooldownCompanion.alphaState[alphaModuleId] = state
                end
                state.currentAlpha = val
                state.desiredAlpha = val
                state.lastAlpha = val
                state.fadeDuration = 0
                state.fadeStartAlpha = val

                local frame = CooldownCompanion.groupFrames[textureGroupId]
                local button = frame and frame.buttons and frame.buttons[1] or nil
                local host = button and button.auraTextureHost or nil
                if host and host:IsShown() then
                    host:SetAlpha(val)
                end
            end,
        })

        if CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
            OpenOrRebindStandaloneTexturePicker(group, settings, false)
        end
        RefreshTextureVisual()
        return
    end

    local isPanel = group.parentContainerId ~= nil
    local panelContainerFrame = isPanel and ("CooldownCompanionContainer" .. group.parentContainerId) or nil
    local currentAnchor = group.anchor.relativeTo
    local cursorAnchorTarget = CooldownCompanion.GetCursorAnchorTargetName
        and CooldownCompanion:GetCursorAnchorTargetName()
        or ST.CURSOR_ANCHOR_TARGET
        or "CooldownCompanionCursor"
    local isCursorAnchor = isPanel
        and CooldownCompanion.IsCursorAnchor
        and CooldownCompanion:IsCursorAnchor(group.anchor)
        or false
    local defaultFrame = isPanel and panelContainerFrame or "UIParent"
    local currentAnchorGroupId = type(currentAnchor) == "string"
        and currentAnchor:match("^CooldownCompanionGroup(%d+)$")
        or nil
    local targetMode
    if isCursorAnchor then
        targetMode = "cursor"
    elseif currentAnchorGroupId and isPanel then
        targetMode = "panel"
    elseif currentAnchor == nil or currentAnchor == "UIParent" or (isPanel and currentAnchor == panelContainerFrame) then
        targetMode = "group"
    else
        targetMode = "frame"
    end
    CS.layoutAnchorTargetMode = CS.layoutAnchorTargetMode or {}
    local preferredTargetMode = CS.layoutAnchorTargetMode[CS.selectedGroup]
    if (targetMode == "group" or targetMode == "cursor")
        and (preferredTargetMode == "frame" or (isPanel and preferredTargetMode == "panel")) then
        targetMode = preferredTargetMode
    end
    CS.layoutAnchorTargetMode[CS.selectedGroup] = targetMode
    local hasFrameAnchorTarget = isPanel
        and targetMode == "frame"
        and IsResolvedExternalFrameAnchorTarget(currentAnchor)
    if targetMode == "cursor" and isCursorAnchor then
        CooldownCompanion:ShowCursorAnchorLayoutPreview(CS.selectedGroup)
    else
        CooldownCompanion:ClearCursorAnchorLayoutPreview()
    end
    local panelAlphaInherited = false
    if isPanel
        and targetMode == "panel"
        and currentAnchorGroupId
        and CooldownCompanion.ShouldInheritPanelAnchorAlpha then
        panelAlphaInherited = CooldownCompanion:ShouldInheritPanelAnchorAlpha(CS.selectedGroup)
    elseif hasFrameAnchorTarget then
        panelAlphaInherited = group.inheritPanelAlpha ~= false
    end
    local alphaControlsDisabled, alphaDisabledText = GetPanelAlphaControlDisabledState(CS.selectedGroup, targetMode, panelAlphaInherited)

    local anchorTargetDrop = AceGUI:Create("Dropdown")
    anchorTargetDrop:SetLabel("Anchor Target")
    local anchorTargetList = isPanel
        and {
            group = "Group",
            panel = "Panel",
            frame = "Frame",
            cursor = "Cursor",
        }
        or {
            group = "Screen",
            frame = "Frame",
        }
    local anchorTargetOrder = isPanel
        and { "group", "panel", "frame", "cursor" }
        or { "group", "frame" }
    anchorTargetDrop:SetList(anchorTargetList, anchorTargetOrder)
    anchorTargetDrop:SetValue(targetMode)
    anchorTargetDrop:SetFullWidth(true)
    anchorTargetDrop:SetCallback("OnValueChanged", function(widget, event, val)
        if val == targetMode then return end
        if val == "group" then
            CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
            local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= defaultFrame
            CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, wasAnchored)
            CooldownCompanion:RefreshConfigPanel()
        elseif val == "cursor" then
            CS.layoutAnchorTargetMode[CS.selectedGroup] = nil
            if CooldownCompanion:SetGroupAnchor(CS.selectedGroup, cursorAnchorTarget) then
                CooldownCompanion:RefreshConfigPanel()
            else
                widget:SetValue(targetMode)
            end
        elseif val == "frame" or val == "panel" then
            CS.layoutAnchorTargetMode[CS.selectedGroup] = val
            CooldownCompanion:RefreshConfigPanel()
        end
    end)
    container:AddChild(anchorTargetDrop)

    if targetMode == "frame" then
        -- ================================================================
        -- Anchor to Frame (editbox + pick button row)
        -- ================================================================
        local anchorRow = AceGUI:Create("SimpleGroup")
        anchorRow:SetFullWidth(true)
        anchorRow:SetLayout("Flow")

        local anchorBox = AceGUI:Create("EditBox")
        if anchorBox.editbox.Instructions then anchorBox.editbox.Instructions:Hide() end
        anchorBox:SetLabel("Anchor to Frame")
        local frameAnchorText = currentAnchor
        if frameAnchorText == "UIParent" or isCursorAnchor or currentAnchorGroupId then frameAnchorText = "" end
        if isPanel and frameAnchorText == panelContainerFrame then frameAnchorText = "" end
        anchorBox:SetText(frameAnchorText)
        anchorBox:SetRelativeWidth(0.68)
        anchorBox:SetCallback("OnEnterPressed", function(widget, event, text)
            local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= defaultFrame
            if text == "" then
                CooldownCompanion:SetGroupAnchor(CS.selectedGroup, defaultFrame, wasAnchored)
            else
                local target = _G[text]
                if not target or type(target) ~= "table" or not target.GetObjectType then
                    CooldownCompanion:Print("Frame not found: " .. text)
                    widget:SetText(frameAnchorText)
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
    end

    if isPanel and targetMode == "panel" then
        local panelAnchorDrop = AceGUI:Create("Dropdown")
        panelAnchorDrop:SetLabel("Anchor to Panel")
        CooldownCompanion:PopulatePanelAnchorTargetDropdown(panelAnchorDrop, CS.selectedGroup)
        panelAnchorDrop:SetFullWidth(true)
        if currentAnchorGroupId then
            panelAnchorDrop:SetValue(tostring(currentAnchorGroupId))
        else
            panelAnchorDrop:SetValue(nil)
        end
        panelAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            if not val or val == "" then return end
            local targetGroupId = tonumber(val)
            if not targetGroupId then return end
            local targetFrameName = "CooldownCompanionGroup" .. targetGroupId
            if CooldownCompanion:SetGroupAnchor(CS.selectedGroup, targetFrameName) then
                CooldownCompanion:RefreshConfigPanel()
            else
                widget:SetValue(nil)
            end
        end)
        container:AddChild(panelAnchorDrop)
    end

    if isPanel and (targetMode == "panel" or hasFrameAnchorTarget) then
        local panelAlphaDrop = AceGUI:Create("Dropdown")
        panelAlphaDrop:SetLabel("Panel Alpha")
        panelAlphaDrop:SetList({
            inherit = targetMode == "frame" and "Inherit Target Frame Alpha" or "Inherit Target Panel Alpha",
            custom = "Custom Alpha",
        }, { "inherit", "custom" })
        panelAlphaDrop:SetValue(group.inheritPanelAlpha == false and "custom" or "inherit")
        panelAlphaDrop:SetFullWidth(true)
        panelAlphaDrop:SetCallback("OnValueChanged", function(widget, event, val)
            if val == "custom" then
                group.inheritPanelAlpha = false
            else
                group.inheritPanelAlpha = true
            end

            local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
            if frame then
                CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
            end
            CooldownCompanion:RebuildPanelAlphaDependencyTargets()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(panelAlphaDrop)
    end

    if targetMode == "cursor" then
        local heading = AceGUI:Create("Heading")
        heading:SetText("Cursor Offset")
        ColorHeading(heading)
        heading:SetFullWidth(true)
        container:AddChild(heading)
    end

    -- Anchor Point / Relative Point dropdowns
    local function refreshGroupAnchor()
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end

    AddAnchorDropdown(container, group.anchor, "point", targetMode == "cursor" and "BOTTOMLEFT" or "CENTER", refreshGroupAnchor, targetMode == "cursor" and "Panel Point" or "Anchor Point")
    if targetMode == "cursor" then
        group.anchor.relativePoint = "CENTER"
    else
        AddAnchorDropdown(container, group.anchor, "relativePoint", "CENTER", refreshGroupAnchor, "Relative Point")
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
    BuildAlphaControls(container, group, function()
        CooldownCompanion:RefreshConfigPanel()
    end, "layout_alpha", {
        isGlobal = group.isGlobal,
        disabled = alphaControlsDisabled,
        disabledText = alphaDisabledText,
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

end


local function RefreshTextureIndicatorConfig()
    CooldownCompanion:RefreshAllAuraTextureVisuals()
    CooldownCompanion:RefreshConfigPanel()
end

local function BuildTextureIndicatorSpeedSlider(container, config, label)
    local slider = AceGUI:Create("Slider")
    slider:SetLabel(label)
    slider:SetSliderValues(0.1, 2.0, 0.05)
    slider:SetValue(config.speed or 0.5)
    slider:SetFullWidth(true)
    slider:SetCallback("OnValueChanged", function(_, _, value)
        config.speed = value
        CooldownCompanion:RefreshAllAuraTextureVisuals()
    end)
    HookSliderEditBox(slider)
    container:AddChild(slider)
end

local function BuildTextureIndicatorSection(container, group, indicators, sectionKey)
    local config = indicators and indicators[sectionKey]
    local sectionDef = TEXTURE_INDICATOR_SECTION_DEFS[sectionKey]
    if not config or not sectionDef then
        return
    end

    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel(sectionDef.label)
    enableCb:SetValue(config.enabled)
    enableCb:SetFullWidth(true)
    enableCb:SetCallback("OnValueChanged", function(_, _, value)
        if value then
            local usedEffects = GetTextureIndicatorUsedEffects(indicators, sectionKey)
            local firstAvailable = GetFirstAvailableTextureIndicatorEffect(indicators, sectionKey)
            local currentEffect = config.effectType
            if currentEffect == "none" or usedEffects[currentEffect] then
                if firstAvailable then
                    config.effectType = firstAvailable
                else
                    config.enabled = false
                    CooldownCompanion:Print("All texture indicator effects are already in use by other sections.")
                    RefreshTextureIndicatorConfig()
                    return
                end
            end
        end

        config.enabled = value == true
        RefreshTextureIndicatorConfig()
    end)
    container:AddChild(enableCb)

    local function BuildTextureIndicatorAdvanced(panel)
        local combatCb = AceGUI:Create("CheckBox")
        combatCb:SetLabel("Show Only In Combat")
        combatCb:SetValue(config.combatOnly or false)
        combatCb:SetFullWidth(true)
        combatCb:SetCallback("OnValueChanged", function(_, _, value)
            config.combatOnly = value == true
            CooldownCompanion:RefreshAllAuraTextureVisuals()
        end)
        panel:AddChild(combatCb)

        if sectionKey == "aura" then
            local invertCb = AceGUI:Create("CheckBox")
            invertCb:SetLabel("Show When Missing")
            invertCb:SetValue(config.invert or false)
            invertCb:SetFullWidth(true)
            invertCb:SetCallback("OnValueChanged", function(_, _, value)
                config.invert = value == true
                CooldownCompanion:RefreshAllAuraTextureVisuals()
            end)
            panel:AddChild(invertCb)
        end

        local effectList, effectOrder = GetTextureIndicatorEffectList(indicators, sectionKey)
        local effectDrop = AceGUI:Create("Dropdown")
        effectDrop:SetLabel("Effect Type")
        effectDrop:SetList(effectList, effectOrder)
        effectDrop:SetValue(config.effectType)
        effectDrop:SetFullWidth(true)
        effectDrop:SetCallback("OnValueChanged", function(_, _, value)
            config.effectType = value or "none"
            RefreshTextureIndicatorConfig()
        end)
        panel:AddChild(effectDrop)

        if config.effectType == "colorShift" then
            AddColorPicker(panel, config, "color", "Shift Color", { 1, 1, 1, 1 }, true,
                function() CooldownCompanion:RefreshAllAuraTextureVisuals() end,
                function() CooldownCompanion:RefreshAllAuraTextureVisuals() end)
            BuildTextureIndicatorSpeedSlider(panel, config, "Shift Duration")
        elseif config.effectType == "pulse" then
            BuildTextureIndicatorSpeedSlider(panel, config, "Pulse Duration")
        elseif config.effectType == "shrinkExpand" then
            BuildTextureIndicatorSpeedSlider(panel, config, "Cycle Duration")
        elseif config.effectType == "bounce" then
            BuildTextureIndicatorSpeedSlider(panel, config, "Bounce Duration")
        end

    end

    local advKey = "textureIndicator_" .. sectionKey
    local _, advBtn = AddAdvancedToggle(enableCb, advKey, tabInfoButtons, config.enabled, {
        title = sectionDef.label .. " Advanced",
        build = BuildTextureIndicatorAdvanced,
    })
    AddPreviewBadge(enableCb, advBtn, sectionDef.previewText, function()
        return CS.selectedGroup
            and CooldownCompanion:IsGroupTextureIndicatorPreviewActive(CS.selectedGroup, sectionKey)
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetGroupTextureIndicatorPreview(CS.selectedGroup, sectionKey, show)
        end
    end, config.enabled)

    if not config.enabled and CS.selectedGroup then
        CooldownCompanion:SetGroupTextureIndicatorPreview(CS.selectedGroup, sectionKey, false)
    end
end

local function BuildTriggerPanelEffectSection(container, effects, effectKey)
    local config = effects and effects[effectKey]
    local def = TRIGGER_PANEL_EFFECT_DEFS[effectKey]
    if not config or not def then
        return
    end

    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel(def.label)
    enableCb:SetValue(config.enabled)
    enableCb:SetFullWidth(true)
    enableCb:SetCallback("OnValueChanged", function(_, _, value)
        config.enabled = value == true
        CooldownCompanion:RefreshAllAuraTextureVisuals()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(enableCb)

    local function BuildTriggerEffectAdvanced(panel)
        if effectKey == "colorShift" then
            AddColorPicker(
                panel,
                config,
                "color",
                "Shift Color",
                { 1, 1, 1, 1 },
                true,
                function() CooldownCompanion:RefreshAllAuraTextureVisuals() end,
                function() CooldownCompanion:RefreshAllAuraTextureVisuals() end
            )
        end

        BuildTextureIndicatorSpeedSlider(panel, config, def.speedLabel)

    end

    local advKey = "triggerEffect_" .. effectKey
    AddAdvancedToggle(enableCb, advKey, tabInfoButtons, config.enabled, {
        title = def.label .. " Advanced",
        build = BuildTriggerEffectAdvanced,
    })
end

local function GetTriggerPanelEffectOrderForDisplayType(group)
    local displayType = CooldownCompanion:GetTriggerPanelDisplayType(group, true)
    if displayType ~= "text" then
        return TEXTURE_INDICATOR_EFFECT_ORDER
    end

    local order = {}
    for _, effectKey in ipairs(TEXTURE_INDICATOR_EFFECT_ORDER) do
        if effectKey ~= "shrinkExpand" then
            order[#order + 1] = effectKey
        end
    end
    return order
end

local function UpdateSelectedGroupStyle(refreshConfig)
    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    if refreshConfig then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function ClearEffectsTabWidgets()
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
end

local function ResetEffectsTabPreviews()
    CooldownCompanion:ClearAllTextureIndicatorPreviews()
    if CooldownCompanion.ClearAllTriggerPanelEffectPreviews then
        CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    end
end

local function BuildTriggerEffectsTab(container, group)
    local effects = GetTriggerPanelEffectStore(group)
    if not effects then
        return
    end

    local anyEnabled = false
    local effectOrder = GetTriggerPanelEffectOrderForDisplayType(group)
    for _, effectKey in ipairs(effectOrder) do
        if effects[effectKey] and effects[effectKey].enabled then
            anyEnabled = true
            break
        end
    end

    local heading = AddIndicatorsHeading(container, "Trigger Panel Effects")
    AddPreviewBadge(heading, nil, "Preview Effects", function()
        return CS.selectedGroup and CooldownCompanion:IsTriggerPanelEffectsPreviewActive(CS.selectedGroup)
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetTriggerPanelEffectsPreview(CS.selectedGroup, show)
        end
    end, anyEnabled)

    for _, effectKey in ipairs(effectOrder) do
        BuildTriggerPanelEffectSection(container, effects, effectKey)
    end

    if not anyEnabled and CS.selectedGroup then
        CooldownCompanion:SetTriggerPanelEffectsPreview(CS.selectedGroup, false)
    end
end

local function BuildTextureEffectsTab(container, group)
    local indicators = GetTextureIndicatorStore(group)
    if not indicators then
        return
    end

    for _, sectionKey in ipairs(CooldownCompanion:GetTextureIndicatorSectionOrder()) do
        BuildTextureIndicatorSection(container, group, indicators, sectionKey)
    end
end

local function BuildBarModeEffects(container, group, style)
    if not CS.previewToggleRefreshActive then
        CooldownCompanion:SetGroupProcGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupReadyGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupKeyPressHighlightPreview(CS.selectedGroup, false)
    end
    BuildBarEffectsTab(container, group, style)
end

local function BuildProcGlowSection(container, group, style)
    local procEnableCb = AceGUI:Create("CheckBox")
    procEnableCb:SetLabel("Show Proc Glow")
    procEnableCb:SetValue(style.procGlowStyle ~= "none")
    procEnableCb:SetFullWidth(true)
    procEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.procGlowStyle = val and "glow" or "none"
        UpdateSelectedGroupStyle(true)
    end)
    container:AddChild(procEnableCb)

    local function BuildProcGlowAdvanced(panel)
        local procCombatCb = AceGUI:Create("CheckBox")
        procCombatCb:SetLabel("Show Only In Combat")
        procCombatCb:SetValue(style.procGlowCombatOnly or false)
        procCombatCb:SetFullWidth(true)
        procCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.procGlowCombatOnly = val
            UpdateSelectedGroupStyle()
        end)
        panel:AddChild(procCombatCb)

        BuildProcGlowControls(panel, style, UpdateSelectedGroupStyle)

    end

    local _, procAdvBtn = AddAdvancedToggle(procEnableCb, "procGlow", tabInfoButtons, style.procGlowStyle ~= "none", {
        title = "Proc Glow Advanced",
        build = BuildProcGlowAdvanced,
    })
    local procBtnData = CS.selectedButton and group.buttons[CS.selectedButton]
    local procPromoteBtn
    if not (procBtnData and procBtnData.isPassive) then
        procPromoteBtn = CreateCheckboxPromoteButton(procEnableCb, procAdvBtn, "procGlow", group, style)
    end
    AddPreviewBadge(procEnableCb, procPromoteBtn or procAdvBtn, "Preview Proc Glow", function()
        return CS.selectedGroup and CooldownCompanion:IsPreviewFlagActive(CS.selectedGroup, nil, "_procGlowPreview")
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetGroupProcGlowPreview(CS.selectedGroup, show)
        end
    end, style.procGlowStyle ~= "none")

    if style.procGlowStyle == "none" then
        CooldownCompanion:SetGroupProcGlowPreview(CS.selectedGroup, false)
        return
    end
end

local function BuildAuraGlowSection(container, group, style)
    local auraEnableCb = AceGUI:Create("CheckBox")
    auraEnableCb:SetLabel("Show Aura Glow")
    auraEnableCb:SetValue(style.auraGlowStyle ~= "none")
    auraEnableCb:SetFullWidth(true)
    auraEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.auraGlowStyle = val and "pixel" or "none"
        UpdateSelectedGroupStyle(true)
    end)
    container:AddChild(auraEnableCb)

    local function BuildAuraGlowAdvanced(panel)
        local auraCombatCb = AceGUI:Create("CheckBox")
        auraCombatCb:SetLabel("Show Only In Combat")
        auraCombatCb:SetValue(style.auraGlowCombatOnly or false)
        auraCombatCb:SetFullWidth(true)
        auraCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraGlowCombatOnly = val
            UpdateSelectedGroupStyle()
        end)
        panel:AddChild(auraCombatCb)

        local auraInvertCb = AceGUI:Create("CheckBox")
        auraInvertCb:SetLabel("Show When Missing")
        auraInvertCb:SetValue(style.auraGlowInvert or false)
        auraInvertCb:SetFullWidth(true)
        auraInvertCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraGlowInvert = val
            UpdateSelectedGroupStyle()
        end)
        panel:AddChild(auraInvertCb)

        BuildAuraIndicatorControls(panel, style, UpdateSelectedGroupStyle)

    end

    local _, auraAdvBtn = AddAdvancedToggle(auraEnableCb, "auraGlow", tabInfoButtons, style.auraGlowStyle ~= "none", {
        title = "Aura Glow Advanced",
        build = BuildAuraGlowAdvanced,
    })
    local auraPromoteBtn = CreateCheckboxPromoteButton(auraEnableCb, auraAdvBtn, "auraIndicator", group, style)
    AddPreviewBadge(auraEnableCb, auraPromoteBtn or auraAdvBtn, "Preview Aura Glow", function()
        return CS.selectedGroup and CooldownCompanion:IsPreviewFlagActive(CS.selectedGroup, nil, "_auraGlowPreview")
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, show)
        end
    end, style.auraGlowStyle ~= "none")

    if style.auraGlowStyle == "none" then
        CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
        return
    end
end

local function BuildPandemicGlowSection(container, group, style)
    local pandemicGlowCb = AceGUI:Create("CheckBox")
    pandemicGlowCb:SetLabel("Show Pandemic Glow")
    pandemicGlowCb:SetValue(style.showPandemicGlow ~= false)
    pandemicGlowCb:SetFullWidth(true)
    pandemicGlowCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showPandemicGlow = val
        UpdateSelectedGroupStyle(true)
    end)
    container:AddChild(pandemicGlowCb)

    local function BuildPandemicGlowAdvanced(panel)
        local pandemicCombatCb = AceGUI:Create("CheckBox")
        pandemicCombatCb:SetLabel("Show Only In Combat")
        pandemicCombatCb:SetValue(style.pandemicGlowCombatOnly or false)
        pandemicCombatCb:SetFullWidth(true)
        pandemicCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.pandemicGlowCombatOnly = val
            UpdateSelectedGroupStyle()
        end)
        panel:AddChild(pandemicCombatCb)

        BuildPandemicGlowControls(panel, style, UpdateSelectedGroupStyle)

    end

    local _, pandemicAdvBtn = AddAdvancedToggle(pandemicGlowCb, "pandemicGlow", tabInfoButtons, style.showPandemicGlow ~= false, {
        title = "Pandemic Glow Advanced",
        build = BuildPandemicGlowAdvanced,
    })
    local pandemicPromoteBtn = CreateCheckboxPromoteButton(pandemicGlowCb, pandemicAdvBtn, "pandemicGlow", group, style)
    AddPreviewBadge(pandemicGlowCb, pandemicPromoteBtn or pandemicAdvBtn, "Preview Pandemic Glow", function()
        return CS.selectedGroup and CooldownCompanion:IsPreviewFlagActive(CS.selectedGroup, nil, "_pandemicPreview")
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetGroupPandemicPreview(CS.selectedGroup, show)
        end
    end, style.showPandemicGlow ~= false)

    if style.showPandemicGlow == false then
        CooldownCompanion:SetGroupPandemicPreview(CS.selectedGroup, false)
        return
    end
end

local function BuildReadyGlowSection(container, group, style)
    local readyEnableCb = AceGUI:Create("CheckBox")
    readyEnableCb:SetLabel("Show Ready Glow")
    readyEnableCb:SetValue(style.readyGlowStyle and style.readyGlowStyle ~= "none")
    readyEnableCb:SetFullWidth(true)
    readyEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.readyGlowStyle = val and "solid" or "none"
        UpdateSelectedGroupStyle(true)
    end)
    container:AddChild(readyEnableCb)

    local function BuildReadyGlowAdvanced(panel)
        local readyCombatCb = AceGUI:Create("CheckBox")
        readyCombatCb:SetLabel("Show Only In Combat")
        readyCombatCb:SetValue(style.readyGlowCombatOnly or false)
        readyCombatCb:SetFullWidth(true)
        readyCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.readyGlowCombatOnly = val
            UpdateSelectedGroupStyle()
        end)
        panel:AddChild(readyCombatCb)

        local readyChargesCb = AceGUI:Create("CheckBox")
        readyChargesCb:SetLabel("Glow When Charges Are Capped")
        readyChargesCb:SetValue(style.readyGlowOnlyAtMaxCharges or false)
        readyChargesCb:SetFullWidth(true)
        readyChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.readyGlowOnlyAtMaxCharges = val == true
            UpdateSelectedGroupStyle()
            if (style.readyGlowDuration or 0) > 0 then
                if val then
                    PrimeReadyGlowCappedChargeTransitions(CS.selectedGroup)
                else
                    PrimeReadyGlowNormalTransitions(CS.selectedGroup)
                end
            end
            CooldownCompanion:UpdateAllCooldowns()
        end)
        panel:AddChild(readyChargesCb)
        CreateInfoButton(readyChargesCb.frame, readyChargesCb.checkbg, "LEFT", "RIGHT", readyChargesCb.text:GetStringWidth() + 6, 0, {
            "Glow When Charges Are Capped",
            {"When this toggle is enabled, the glow will only appear for charge based spells when at max charges.", 1, 1, 1, true},
        }, tabInfoButtons)

        local readyDurCb = AceGUI:Create("CheckBox")
        readyDurCb:SetLabel("Auto-Hide After Duration")
        readyDurCb:SetValue((style.readyGlowDuration or 0) > 0)
        readyDurCb:SetFullWidth(true)
        readyDurCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.readyGlowDuration = val and 3 or 0
            UpdateSelectedGroupStyle()
            if val then
                if style.readyGlowOnlyAtMaxCharges then
                    PrimeReadyGlowCappedChargeTransitions(CS.selectedGroup)
                else
                    PrimeReadyGlowNormalTransitions(CS.selectedGroup)
                end
            end
            CooldownCompanion:UpdateAllCooldowns()
            RefreshActiveAdvancedSettingsPanel()
        end)
        panel:AddChild(readyDurCb)

        if (style.readyGlowDuration or 0) > 0 then
            local readyDurSlider = AceGUI:Create("Slider")
            readyDurSlider:SetLabel("Duration (seconds)")
            readyDurSlider:SetSliderValues(0.5, 5, 0.5)
            readyDurSlider:SetValue(style.readyGlowDuration or 3)
            readyDurSlider:SetFullWidth(true)
            readyDurSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.readyGlowDuration = val
                UpdateSelectedGroupStyle()
            end)
            panel:AddChild(readyDurSlider)
        end

        BuildReadyGlowControls(panel, style, UpdateSelectedGroupStyle)

    end

    local _, readyAdvBtn = AddAdvancedToggle(readyEnableCb, "readyGlow", tabInfoButtons, style.readyGlowStyle and style.readyGlowStyle ~= "none", {
        title = "Ready Glow Advanced",
        build = BuildReadyGlowAdvanced,
    })
    local readyPromoteBtn = CreateCheckboxPromoteButton(readyEnableCb, readyAdvBtn, "readyGlow", group, style)
    local readyPreviewBtn = AddPreviewBadge(readyEnableCb, readyPromoteBtn or readyAdvBtn, "Preview Ready Glow Style", function()
        return CS.selectedGroup and CooldownCompanion:IsPreviewFlagActive(CS.selectedGroup, nil, "_readyGlowPreview")
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetGroupReadyGlowPreview(CS.selectedGroup, show)
        end
    end, style.readyGlowStyle and style.readyGlowStyle ~= "none")
    CreateInfoButton(readyEnableCb.frame, readyPreviewBtn or readyPromoteBtn or readyAdvBtn, "LEFT", "RIGHT", 4, 0, {
        "Ready Glow",
        {"Adds a glow to spells/items that are not on cooldown.", 1, 1, 1, true},
    }, tabInfoButtons)

    if not (style.readyGlowStyle and style.readyGlowStyle ~= "none") then
        CooldownCompanion:SetGroupReadyGlowPreview(CS.selectedGroup, false)
        return
    end
end

local function BuildKeyPressHighlightSection(container, group, style)
    local kphEnableCb = AceGUI:Create("CheckBox")
    kphEnableCb:SetLabel("Show Key Press Highlight")
    kphEnableCb:SetValue(style.keyPressHighlightStyle and style.keyPressHighlightStyle ~= "none")
    kphEnableCb:SetFullWidth(true)
    kphEnableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.keyPressHighlightStyle = val and "solid" or "none"
        UpdateSelectedGroupStyle(true)
    end)
    container:AddChild(kphEnableCb)

    local function BuildKeyPressHighlightAdvanced(panel)
        local kphCombatCb = AceGUI:Create("CheckBox")
        kphCombatCb:SetLabel("Show Only In Combat")
        kphCombatCb:SetValue(style.keyPressHighlightCombatOnly or false)
        kphCombatCb:SetFullWidth(true)
        kphCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.keyPressHighlightCombatOnly = val
            UpdateSelectedGroupStyle()
        end)
        panel:AddChild(kphCombatCb)

        BuildKeyPressHighlightControls(panel, style, UpdateSelectedGroupStyle)

    end

    local _, kphAdvBtn = AddAdvancedToggle(kphEnableCb, "keyPressHighlight", tabInfoButtons, style.keyPressHighlightStyle and style.keyPressHighlightStyle ~= "none", {
        title = "Key Press Highlight Advanced",
        build = BuildKeyPressHighlightAdvanced,
    })
    local kphPromoteBtn = CreateCheckboxPromoteButton(kphEnableCb, kphAdvBtn, "keyPressHighlight", group, style)
    local kphPreviewBtn = AddPreviewBadge(kphEnableCb, kphPromoteBtn or kphAdvBtn, "Preview Key Press Highlight", function()
        return CS.selectedGroup and CooldownCompanion:IsPreviewFlagActive(CS.selectedGroup, nil, "_keyPressHighlightPreview")
    end, function(show)
        if CS.selectedGroup then
            CooldownCompanion:SetGroupKeyPressHighlightPreview(CS.selectedGroup, show)
        end
    end, style.keyPressHighlightStyle and style.keyPressHighlightStyle ~= "none")
    CreateInfoButton(kphEnableCb.frame, kphPreviewBtn or kphPromoteBtn or kphAdvBtn, "LEFT", "RIGHT", 4, 0, {
        "Key Press Highlight",
        {"Shows a glow overlay on buttons while their action bar keybind is physically held down.", 1, 1, 1, true},
    }, tabInfoButtons)

    if not (style.keyPressHighlightStyle and style.keyPressHighlightStyle ~= "none") then
        CooldownCompanion:SetGroupKeyPressHighlightPreview(CS.selectedGroup, false)
        return
    end
end

local function BuildEffectsTab(container)
    ClearEffectsTabWidgets()

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style

    local displayMode = group.displayMode
    if not CS.previewToggleRefreshActive
        and (CS.lastEffectsPreviewGroup ~= CS.selectedGroup or CS.lastEffectsPreviewMode ~= displayMode) then
        ResetEffectsTabPreviews()
        CS.lastEffectsPreviewGroup = CS.selectedGroup
        CS.lastEffectsPreviewMode = displayMode
    end

    if displayMode == "trigger" then
        BuildTriggerEffectsTab(container, group)
        return
    end

    if displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        AddIndicatorsHeading(container, "Timers")
        BuildCooldownSwipeControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        BuildShowGCDSwipeControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)

        AddIndicatorsHeading(container, "States")
        BuildDesaturationControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        BuildShowOutOfRangeControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        BuildLossOfControlControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        BuildUnusableDimmingControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        BuildShowTooltipsControls(container, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        return
    end

    if displayMode == "textures" then
        BuildTextureEffectsTab(container, group)
        return
    end

    if displayMode == "bars" then
        BuildBarModeEffects(container, group, style)
        return
    end

    AddIndicatorsHeading(container, "Glows")
    BuildProcGlowSection(container, group, style)
    BuildAuraGlowSection(container, group, style)
    BuildPandemicGlowSection(container, group, style)
    BuildReadyGlowSection(container, group, style)
    BuildKeyPressHighlightSection(container, group, style)

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

    local function BuildAssistedHighlightAdvanced(panel)
        local assistedCombatCb = AceGUI:Create("CheckBox")
        assistedCombatCb:SetLabel("Show Only In Combat")
        assistedCombatCb:SetValue(style.assistedHighlightCombatOnly or false)
        assistedCombatCb:SetFullWidth(true)
        assistedCombatCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.assistedHighlightCombatOnly = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        panel:AddChild(assistedCombatCb)

        BuildAssistedHighlightControls(panel, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
    end

    AddAdvancedToggle(assistedCb, "assistedHighlight", tabInfoButtons, style.showAssistedHighlight or false, {
        title = "Assisted Highlight Advanced",
        build = BuildAssistedHighlightAdvanced,
    })

    AddIndicatorsHeading(container, "Timers")
    local iconFillTimerActive = style.iconFillEnabled == true and group.masqueEnabled ~= true
    local iconFillCb = BuildIconFillTimerControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end, {
        masqueEnabled = group.masqueEnabled == true,
        showAdvancedControlsInline = false,
        onEnabled = function()
            if CS.QueueAdvancedSettingsPanelOpen then
                CS.QueueAdvancedSettingsPanelOpen("iconFillTimer")
            end
        end,
    })
    local function BuildIconFillAdvanced(panel)
        if BuildIconFillTimerAdvancedControls then
            BuildIconFillTimerAdvancedControls(panel, style, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
        end
        if AddConditionalPreviewButton then
            AddConditionalPreviewButton(panel, "Preview Cooldown Fill", "cooldown")
            AddConditionalPreviewButton(panel, "Preview Aura Fill", "aura_duration_text")
        end
    end

    local _, iconFillAdvBtn = AddAdvancedToggle(iconFillCb, "iconFillTimer", tabInfoButtons, iconFillTimerActive, {
        title = "Icon Fill Timer Advanced",
        build = BuildIconFillAdvanced,
    })
    local iconFillPromoteBtn
    if not group.masqueEnabled then
        iconFillPromoteBtn = CreateCheckboxPromoteButton(iconFillCb, iconFillAdvBtn, "iconFillTimer", group, style)
    end
    local iconFillInfoAnchor = iconFillCb.checkbg
    local iconFillInfoXOff = iconFillCb.text:GetStringWidth() + 4
    if iconFillPromoteBtn and iconFillPromoteBtn:IsShown() then
        iconFillInfoAnchor = iconFillPromoteBtn
        iconFillInfoXOff = 4
    elseif iconFillAdvBtn and iconFillAdvBtn:IsShown() then
        iconFillInfoAnchor = iconFillAdvBtn
        iconFillInfoXOff = 4
    end
    CreateInfoButton(iconFillCb.frame, iconFillInfoAnchor, "LEFT", "RIGHT", iconFillInfoXOff, 0, {
        "Icon Fill Timer",
        {"Shows cooldowns and tracked aura durations as a rectangular fill over the icon instead of radial swipes.", 1, 1, 1, true},
        " ",
        {"Does not work while Masque is enabled.", 1, 1, 1, true},
        " ",
        {"Show Cooldown Swipe, Show Aura Duration Swipe, and Blizzard CDM Aura Swipe Style are unavailable while Icon Fill Timer is active.", 0.7, 0.7, 0.7, true},
    }, tabInfoButtons)

    local swipeCb = AceGUI:Create("CheckBox")
    swipeCb:SetLabel("Show Cooldown Swipe")
    swipeCb:SetValue(style.showCooldownSwipe ~= false)
    swipeCb:SetFullWidth(true)
    swipeCb:SetDisabled(iconFillTimerActive)
    swipeCb:SetCallback("OnValueChanged", function(widget, event, val)
        if iconFillTimerActive then return end
        style.showCooldownSwipe = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(swipeCb)

    local function BuildCooldownSwipeAdvanced(panel)
        -- Reverse Swipe
        local reverseCb = AceGUI:Create("CheckBox")
        reverseCb:SetLabel("Reverse Swipe")
        reverseCb:SetValue(style.cooldownSwipeReverse or false)
        reverseCb:SetFullWidth(true)
        reverseCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownSwipeReverse = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        panel:AddChild(reverseCb)

        -- Show Swipe Fill
        local fillCb = AceGUI:Create("CheckBox")
        fillCb:SetLabel("Show Swipe Fill")
        fillCb:SetValue(style.showCooldownSwipeFill ~= false)
        fillCb:SetFullWidth(true)
        fillCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.showCooldownSwipeFill = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            RefreshActiveAdvancedSettingsPanel()
        end)
        panel:AddChild(fillCb)

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
            panel:AddChild(alphaSlider)
        end

        -- Show Swipe Edge
        local edgeCb = AceGUI:Create("CheckBox")
        edgeCb:SetLabel("Show Swipe Edge")
        edgeCb:SetValue(style.showCooldownSwipeEdge ~= false)
        edgeCb:SetFullWidth(true)
        edgeCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.showCooldownSwipeEdge = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            RefreshActiveAdvancedSettingsPanel()
        end)
        panel:AddChild(edgeCb)

        -- Swipe Edge Color (only when edge is visible)
        if style.showCooldownSwipeEdge ~= false then
            local swipeRefresh = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
            AddColorPicker(panel, style, "cooldownSwipeEdgeColor", "Swipe Edge Color", {1, 1, 1, 1}, true, swipeRefresh, swipeRefresh)
        end
    end

    local _, swipeAdvBtn = AddAdvancedToggle(swipeCb, "cooldownSwipe", tabInfoButtons, style.showCooldownSwipe ~= false and not iconFillTimerActive, {
        title = "Cooldown Swipe Advanced",
        build = BuildCooldownSwipeAdvanced,
    })
    if not iconFillTimerActive then
        CreateCheckboxPromoteButton(swipeCb, swipeAdvBtn, "cooldownSwipe", group, style)
    end


    local auraDurationCb = BuildAuraDurationSwipeControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:UpdateAllCooldowns()
    end, {
        masqueEnabled = group.masqueEnabled == true,
        showAdvancedControlsInline = false,
    })
    local function BuildAuraDurationSwipeAdvanced(panel)
        if BuildAuraDurationSwipeAdvancedControls then
            BuildAuraDurationSwipeAdvancedControls(panel, style, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:UpdateAllCooldowns()
            end, {
                masqueEnabled = group.masqueEnabled == true,
            })
        end
    end
    local _, auraDurationAdvBtn = AddAdvancedToggle(auraDurationCb, "auraDurationSwipe", tabInfoButtons, style.showAuraDurationSwipe ~= false and not iconFillTimerActive, {
        title = "Aura Duration Swipe Advanced",
        build = BuildAuraDurationSwipeAdvanced,
    })
    if not iconFillTimerActive then
        CreateCheckboxPromoteButton(auraDurationCb, auraDurationAdvBtn, "auraDurationSwipe", group, style)
    end

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

    AddIndicatorsHeading(container, "States")
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

    local oorCb = BuildShowOutOfRangeControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    local oorPromoteBtn = CreateCheckboxPromoteButton(oorCb, nil, "showOutOfRange", group, style)
    AddConditionalPreviewBadge(oorCb, oorPromoteBtn, "Preview Out of Range State", "out_of_range", style.showOutOfRange)

    -- Loss of Control
    local locCb = BuildLossOfControlControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    CreateCheckboxPromoteButton(locCb, nil, "lossOfControl", group, style)

    -- Unusable Visual
    local unusableCb, unusableAdvBtn = BuildUnusableDimmingControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    local unusablePromoteBtn = CreateCheckboxPromoteButton(unusableCb, unusableAdvBtn, "unusableDimming", group, style)
    AddConditionalPreviewBadge(unusableCb, unusablePromoteBtn or unusableAdvBtn, "Preview Unusable State", "unusable", style.showUnusable)

    -- Show Tooltips
    local tooltipCb = BuildShowTooltipsControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    CreateCheckboxPromoteButton(tooltipCb, nil, "showTooltips", group, style)

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

    CooldownCompanion:ClearAllTextureIndicatorPreviews()
    if CooldownCompanion.ClearAllTriggerPanelEffectPreviews then
        CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    end

    if group.displayMode == "trigger" then
        AddTriggerDisplayTypeDropdown(container, group)
        local displayType = CooldownCompanion:GetTriggerPanelDisplayType(group, true)
        if displayType == "icon" then
            BuildTriggerIconAppearanceTab(container, group)
            return
        elseif displayType == "text" then
            BuildTriggerTextAppearanceTab(container, group)
            return
        end
    end

    if group.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        local heading = AceGUI:Create("Heading")
        heading:SetText("Assistant Panel")
        ColorHeading(heading)
        heading:SetFullWidth(true)
        container:AddChild(heading)

        local squareCb = AceGUI:Create("CheckBox")
        squareCb:SetLabel("Square Icons")
        squareCb:SetValue(style.maintainAspectRatio ~= false)
        squareCb:SetFullWidth(true)
        squareCb:SetCallback("OnValueChanged", function(widget, event, value)
            style.maintainAspectRatio = value ~= false
            style.buttonsPerRow = 1
            if not style.maintainAspectRatio then
                local size = style.buttonSize or ST.BUTTON_SIZE
                style.iconWidth = style.iconWidth or size
                style.iconHeight = style.iconHeight or size
            end
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(squareCb)

        if style.maintainAspectRatio ~= false then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Button Size")
            sizeSlider:SetSliderValues(10, 150, 0.1)
            sizeSlider:SetValue(style.buttonSize or ST.BUTTON_SIZE)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, value)
                style.buttonSize = value
                style.buttonsPerRow = 1
                refreshStyle()
            end)
            HookSliderEditBox(sizeSlider)
            container:AddChild(sizeSlider)
        else
            local widthSlider = AceGUI:Create("Slider")
            widthSlider:SetLabel("Icon Width")
            widthSlider:SetSliderValues(10, 150, 0.1)
            widthSlider:SetValue(style.iconWidth or style.buttonSize or ST.BUTTON_SIZE)
            widthSlider:SetFullWidth(true)
            widthSlider:SetCallback("OnValueChanged", function(widget, event, value)
                style.iconWidth = value
                style.buttonsPerRow = 1
                refreshStyle()
            end)
            HookSliderEditBox(widthSlider)
            container:AddChild(widthSlider)

            local heightSlider = AceGUI:Create("Slider")
            heightSlider:SetLabel("Icon Height")
            heightSlider:SetSliderValues(10, 150, 0.1)
            heightSlider:SetValue(style.iconHeight or style.buttonSize or ST.BUTTON_SIZE)
            heightSlider:SetFullWidth(true)
            heightSlider:SetCallback("OnValueChanged", function(widget, event, value)
                style.iconHeight = value
                style.buttonsPerRow = 1
                refreshStyle()
            end)
            HookSliderEditBox(heightSlider)
            container:AddChild(heightSlider)
        end

        BuildBorderControls(container, style, refreshStyle)
        BuildKeybindTextControls(container, style, refreshStyle, {
            label = "Show Keybind Text",
            tooltip = {
                "Show Keybind Text",
                {"Shows detected keybind text for the current recommendation.", 1, 1, 1, true},
            },
        })
        return
    end

    if group.displayMode == "textures" or group.displayMode == "trigger" then
        local isTriggerPanel = group.displayMode == "trigger"
        local settings = GetStandaloneTextureSettings(group, true)
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
        heading:SetText(isTriggerPanel and "Trigger Texture" or "Texture Panel")
        ColorHeading(heading)
        heading:SetFullWidth(true)
        container:AddChild(heading)

        if not isTriggerPanel then
            CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
                "Texture Panel",
                {"This panel shows one standalone texture on your screen.", 1, 1, 1, true},
                " ",
                {"Its single entry decides when that texture appears.", 1, 1, 1, true},
            }, tabInfoButtons)
        end

        if not buttonData and not isTriggerPanel then
            local emptyLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(emptyLabel)
            emptyLabel:SetFullWidth(true)
            emptyLabel:SetText("|cff888888Add one entry in Column 2 first. The texture browser will open after that.|r")
            container:AddChild(emptyLabel)

            if CS.pendingTexturePickerOpen == CS.selectedGroup then
                CS.pendingTexturePickerOpen = nil
            end
            return
        end

        local selectionLabel = GetStandaloneTextureSelectionLabel(group, settings)

        local previewGroup = AceGUI:Create("SimpleGroup")
        previewGroup:SetFullWidth(true)
        previewGroup:SetHeight(TEXTURE_PREVIEW_HEIGHT + 4)
        previewGroup:SetLayout("Fill")
        container:AddChild(previewGroup)

        local previewFrame = CreateFrame("Frame", nil, previewGroup.frame)
        previewFrame:SetPoint("TOP", previewGroup.frame, "TOP", 0, -2)
        previewFrame:SetSize(TEXTURE_PREVIEW_WIDTH, TEXTURE_PREVIEW_HEIGHT)
        appearanceTabElements[#appearanceTabElements + 1] = previewFrame

        local previewShade = previewFrame:CreateTexture(nil, "BACKGROUND")
        previewShade:SetAllPoints()
        previewShade:SetColorTexture(0, 0, 0, 0.42)

        local previewAnchor = CreateFrame("Frame", nil, previewFrame)
        previewAnchor:SetPoint("CENTER")
        previewAnchor:SetSize(TEXTURE_PREVIEW_WIDTH - 8, TEXTURE_PREVIEW_HEIGHT - 8)

        local previewPrimary = previewFrame:CreateTexture(nil, "ARTWORK")
        local previewSecondary = previewFrame:CreateTexture(nil, "ARTWORK")

        local placeholder = previewFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        placeholder:SetPoint("CENTER")
        placeholder:SetJustifyH("CENTER")
        placeholder:SetText("No texture selected")
        placeholder:SetTextColor(0.65, 0.65, 0.65, 1)

        previewWidget = {
            primary = previewPrimary,
            secondary = previewSecondary,
            placeholder = placeholder,
            anchor = previewAnchor,
        }
        UpdateTexturePanelPreview(previewWidget, settings)

        local actionRow = AceGUI:Create("SimpleGroup")
        actionRow:SetFullWidth(true)
        actionRow:SetLayout("Flow")
        container:AddChild(actionRow)

        local browseBtn = AceGUI:Create("Button")
        browseBtn:SetText("Browse / Change")
        browseBtn:SetRelativeWidth(0.49)
        browseBtn:SetCallback("OnClick", function()
            OpenOrRebindStandaloneTexturePicker(group, settings, true)
        end)
        actionRow:AddChild(browseBtn)

        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear")
        clearBtn:SetDisabled(not selectionLabel)
        clearBtn:SetRelativeWidth(0.49)
        clearBtn:SetCallback("OnClick", function()
            CooldownCompanion:ClearAllAuraTexturePickerPreviews()
            GetStandaloneTextureCommitCallback(group)(nil)
        end)
        actionRow:AddChild(clearBtn)

        if not selectionLabel then
            if not isTriggerPanel then
                local emptyStateLabel = AceGUI:Create("Label")
                ST._ConfigureWrappedHelperLabel(emptyStateLabel)
                emptyStateLabel:SetFullWidth(true)
                emptyStateLabel:SetText("|cff888888Pick a texture to show the rest of the display controls.|r")
                container:AddChild(emptyStateLabel)
            end

            local shouldOpenPicker = CS.pendingTexturePickerOpen == CS.selectedGroup
            if shouldOpenPicker then
                CS.pendingTexturePickerOpen = nil
                C_Timer.After(0, function()
                    if CS.selectedGroup == groupId and CS.panelSettingsTab == "appearance" then
                        OpenOrRebindStandaloneTexturePicker(group, settings, true)
                    end
                end)
            elseif CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
                OpenOrRebindStandaloneTexturePicker(group, settings, false)
            end

            RefreshTextureVisual()
            return
        end

        local locationOptions, locationOrder = CooldownCompanion:GetTexturePanelLocationOptions()
        local selectedLayoutValue = CooldownCompanion:GetTexturePanelLayoutSelectionValue(settings.locationType or 0)
        local locationDrop = AceGUI:Create("Dropdown")
        locationDrop:SetLabel("Texture Layout")
        locationDrop:SetList(locationOptions, locationOrder)
        locationDrop:SetValue(selectedLayoutValue)
        locationDrop:SetFullWidth(true)
        locationDrop:SetCallback("OnValueChanged", function(_, _, value)
            settings.locationType = tonumber(value) or 0
            RefreshTextureVisual()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(locationDrop)

        if selectedLayoutValue == PREVIEW_LOCATION_LEFTRIGHT or selectedLayoutValue == PREVIEW_LOCATION_TOPBOTTOM then
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
        blendDrop:SetLabel("Texture Look")
        blendDrop:SetList(TEXTURE_BLEND_OPTIONS, TEXTURE_BLEND_ORDER)
        blendDrop:SetValue(settings.blendMode or "BLEND")
        blendDrop:SetFullWidth(true)
        blendDrop:SetCallback("OnValueChanged", function(_, _, value)
            settings.blendMode = value or "BLEND"
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

        local rotationSlider = AceGUI:Create("Slider")
        rotationSlider:SetLabel("Rotation")
        rotationSlider:SetSliderValues(MIN_TEXTURE_ROTATION, MAX_TEXTURE_ROTATION, 1)
        rotationSlider:SetValue(settings.rotation or 0)
        rotationSlider:SetFullWidth(true)
        AttachLiveTextureSliderRefresh(rotationSlider, function(value)
            settings.rotation = value
            RefreshTextureVisual()
        end)
        HookSliderEditBox(rotationSlider)
        container:AddChild(rotationSlider)

        local stretchXSlider = AceGUI:Create("Slider")
        stretchXSlider:SetLabel("Horizontal Stretch / Compress")
        stretchXSlider:SetSliderValues(MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH, 0.05)
        stretchXSlider:SetValue(settings.stretchX or 0)
        stretchXSlider:SetFullWidth(true)
        AttachLiveTextureSliderRefresh(stretchXSlider, function(value)
            settings.stretchX = value
            RefreshTextureVisual()
        end)
        HookSliderEditBox(stretchXSlider)
        container:AddChild(stretchXSlider)

        local stretchYSlider = AceGUI:Create("Slider")
        stretchYSlider:SetLabel("Vertical Stretch / Compress")
        stretchYSlider:SetSliderValues(MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH, 0.05)
        stretchYSlider:SetValue(settings.stretchY or 0)
        stretchYSlider:SetFullWidth(true)
        AttachLiveTextureSliderRefresh(stretchYSlider, function(value)
            settings.stretchY = value
            RefreshTextureVisual()
        end)
        HookSliderEditBox(stretchYSlider)
        container:AddChild(stretchYSlider)

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
                    OpenOrRebindStandaloneTexturePicker(group, settings, true)
                end
            end)
        elseif CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
            OpenOrRebindStandaloneTexturePicker(group, settings, false)
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

    local renderMode = AddBorderRenderModeDropdown(container, style, "borderRenderMode", function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end, group.masqueEnabled)
    local borderThicknessLocked = group.masqueEnabled or ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSlider = AceGUI:Create("Slider")
        borderSlider:SetLabel("Border Size")
        borderSlider:SetSliderValues(0, 5, 0.1)
        borderSlider:SetValue(style.borderSize or ST.DEFAULT_BORDER_SIZE)
        borderSlider:SetFullWidth(true)
        if borderThicknessLocked then
            borderSlider:SetDisabled(true)
        end
        borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if borderThicknessLocked then return end
            style.borderSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(borderSlider)
    end

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

    local function BuildCooldownTextAdvanced(panel)
        AddFontControls(panel, style, "cooldown", { size = 12 }, refreshStyle)
        AddColorPicker(panel, style, "cooldownFontColor", "Font Color", {1, 1, 1, 1}, false, refreshStyle, refreshStyle)

        local cdAnchorDrop = AddAnchorDropdown(panel, style, "cooldownTextAnchor", "CENTER", refreshStyle)

        -- (?) tooltip for shared positioning
        CreateInfoButton(cdAnchorDrop.frame, cdAnchorDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Shared Position",
            {"Position is shared with Aura Duration Text by default. Enable 'Separate Text Positions' in the Aura Duration Text section to use independent positions.", 1, 1, 1, true},
        }, cdAnchorDrop)

        AddOffsetSliders(panel, style, "cooldownTextXOffset", "cooldownTextYOffset", { x = 0, y = 0 }, refreshStyle)

    end

    local _, cdTextAdvBtn = AddAdvancedToggle(cdTextCb, "cooldownText", tabInfoButtons, style.showCooldownText, {
        title = "Cooldown Text Advanced",
        build = BuildCooldownTextAdvanced,
    })
    local cdTextPromoteBtn = CreateCheckboxPromoteButton(cdTextCb, cdTextAdvBtn, "cooldownText", group, style)
    AddConditionalPreviewBadge(cdTextCb, cdTextPromoteBtn or cdTextAdvBtn, "Preview Cooldown Text", "cooldown", style.showCooldownText)

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

    local function BuildChargeTextAdvanced(panel)
        AddFontControls(panel, style, "charge", { size = 12 }, refreshStyle)
        AddColorPicker(panel, style, "chargeFontColor", "Font Color (Max Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddColorPicker(panel, style, "chargeFontColorMissing", "Font Color (Missing Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddColorPicker(panel, style, "chargeFontColorZero", "Font Color (Zero Charges)", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddAnchorDropdown(panel, style, "chargeAnchor", "BOTTOMRIGHT", refreshStyle)
        AddOffsetSliders(panel, style, "chargeXOffset", "chargeYOffset", { x = -2, y = 2 }, refreshStyle)
    end

    local _, chargeAdvBtn = AddAdvancedToggle(chargeTextCb, "chargeText", tabInfoButtons, style.showChargeText ~= false, {
        title = "Count Text Advanced",
        build = BuildChargeTextAdvanced,
    })
    CreateCheckboxPromoteButton(chargeTextCb, chargeAdvBtn, "chargeText", group, style)

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

    local function BuildAuraDurationTextAdvanced(panel)
        AddFontControls(panel, style, "auraText", { size = 12 }, refreshStyle)
        AddColorPicker(panel, style, "auraTextFontColor", "Font Color", {0, 0.925, 1, 1}, false, refreshStyle, refreshStyle)

        local sepPosCb = AceGUI:Create("CheckBox")
        sepPosCb:SetLabel("Separate Text Positions")
        sepPosCb:SetValue(style.separateTextPositions or false)
        sepPosCb:SetFullWidth(true)
        sepPosCb:SetCallback("OnValueChanged", function(widget, event, val)
            style.separateTextPositions = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            RefreshActiveAdvancedSettingsPanel()
        end)
        panel:AddChild(sepPosCb)

        CreateInfoButton(sepPosCb.frame, sepPosCb.checkbg, "LEFT", "RIGHT", sepPosCb.text:GetStringWidth() + 4, 0, {
            "Separate Text Positions",
            {"When enabled, aura duration text and cooldown text use independent positions. Aura text position controls appear below when toggled on; cooldown text position is in the Cooldown Text section.", 1, 1, 1, true},
        }, sepPosCb)

        if style.separateTextPositions then
            AddAnchorDropdown(panel, style, "auraTextAnchor", "TOPLEFT", refreshStyle)
            AddOffsetSliders(panel, style, "auraTextXOffset", "auraTextYOffset", { x = 2, y = -2 }, refreshStyle)
        end

    end

    local _, auraTextAdvBtn = AddAdvancedToggle(auraTextCb, "auraText", tabInfoButtons, style.showAuraText ~= false, {
        title = "Aura Duration Text Advanced",
        build = BuildAuraDurationTextAdvanced,
    })
    local auraTextPromoteBtn = CreateCheckboxPromoteButton(auraTextCb, auraTextAdvBtn, "auraText", group, style)
    local auraTextPreviewBtn = AddConditionalPreviewBadge(auraTextCb, auraTextPromoteBtn or auraTextAdvBtn, "Preview Aura Duration Text", "aura_duration_text", style.showAuraText ~= false)

    local auraPosInfo = CreateInfoButton(auraTextCb.frame, auraTextPreviewBtn or auraTextPromoteBtn or auraTextAdvBtn, "LEFT", "RIGHT", 4, 0, {
        "Shared Position",
        {"Position is shared with Cooldown Text by default. Enable 'Separate Text Positions' in advanced settings to use independent positions.", 1, 1, 1, true},
    }, auraTextCb)
    if style.showAuraText == false then
        auraPosInfo:Hide()
    end


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

    local function BuildAuraStackTextAdvanced(panel)
        AddFontControls(panel, style, "auraStack", { size = 12 }, refreshStyle)
        AddColorPicker(panel, style, "auraStackFontColor", "Font Color", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
        AddAnchorDropdown(panel, style, "auraStackAnchor", "BOTTOMLEFT", refreshStyle)
        AddOffsetSliders(panel, style, "auraStackXOffset", "auraStackYOffset", { x = 2, y = 2 }, refreshStyle)

    end

    local _, auraStackAdvBtn = AddAdvancedToggle(auraStackCb, "auraStackText", tabInfoButtons, style.showAuraStackText ~= false, {
        title = "Aura Stack Text Advanced",
        build = BuildAuraStackTextAdvanced,
    })
    local auraStackPromoteBtn = CreateCheckboxPromoteButton(auraStackCb, auraStackAdvBtn, "auraStackText", group, style)
    AddConditionalPreviewBadge(auraStackCb, auraStackPromoteBtn or auraStackAdvBtn, "Preview Aura Stack Text", "aura_stack_text", style.showAuraStackText ~= false)

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

    local function BuildKeybindTextAdvanced(panel)
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
        panel:AddChild(kbAnchorDrop)

        AddOffsetSliders(panel, style, "keybindXOffset", "keybindYOffset", { x = -2, y = -2 }, refreshStyle)
        AddFontControls(panel, style, "keybind", { size = 10, sizeMin = 6, sizeMax = 24 }, refreshStyle)
        AddColorPicker(panel, style, "keybindFontColor", "Font Color", {1, 1, 1, 1}, true, refreshStyle, refreshStyle)
    end

    local _, kbAdvBtn = AddAdvancedToggle(kbCb, "keybindText", tabInfoButtons, style.showKeybindText, {
        title = KEYBIND_CUSTOM_LABEL .. " Advanced",
        build = BuildKeybindTextAdvanced,
    })
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


    -- Compact Mode toggle + Max Visible Buttons slider
    BuildCompactModeControls(container, group, tabInfoButtons)

    if style.showCooldownText or style.showAuraText ~= false then
        AddDurationFormatDropdown(container, style, refreshStyle)
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
        {"Unusable Dim Color:", 1, 0.82, 0},
        {"A color applied when an ability is not usable and Unusable Visual uses dimming in the Indicators tab.", 1, 1, 1, true},
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
            {"Border Thickness, Border Size, Border Color, Square Icons (forced on)", 0.7, 0.7, 0.7, true},
        }, tabInfoButtons)
        end -- not masqueCollapsed
    end

    BuildGroupSettingPresetControls(container, group, "icons", tabInfoButtons)

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
        container.anchor = CooldownCompanion:NormalizeContainerAnchor(container.anchor)
        local function ApplyContainerOffset(axis, value)
            local oldValue = tonumber(container.anchor[axis]) or 0
            container.anchor[axis] = value

            local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
            if containerFrame then
                CooldownCompanion:AnchorContainerFrame(containerFrame, container.anchor)
            end

            if CooldownCompanion.SyncGroupedStandalonePreviewSettings then
                local deltaX, deltaY = 0, 0
                if axis == "x" then
                    deltaX = value - oldValue
                else
                    deltaY = value - oldValue
                end
                CooldownCompanion:SyncGroupedStandalonePreviewSettings(containerId, deltaX, deltaY)
            end

            if containerFrame and CooldownCompanion.RefreshContainerWrapper then
                CooldownCompanion:RefreshContainerWrapper(containerId)
            end
        end

        -- X Offset
        local xSlider = AceGUI:Create("Slider")
        xSlider:SetLabel("X Offset")
        xSlider:SetSliderValues(-2000, 2000, 0.1)
        xSlider:SetValue(container.anchor.x or 0)
        xSlider:SetFullWidth(true)
        xSlider:SetCallback("OnValueChanged", function(_, _, val)
            ApplyContainerOffset("x", val)
        end)
        HookSliderEditBox(xSlider)
        scroll:AddChild(xSlider)

        -- Y Offset
        local ySlider = AceGUI:Create("Slider")
        ySlider:SetLabel("Y Offset")
        ySlider:SetSliderValues(-2000, 2000, 0.1)
        ySlider:SetValue(container.anchor.y or 0)
        ySlider:SetFullWidth(true)
        ySlider:SetCallback("OnValueChanged", function(_, _, val)
            ApplyContainerOffset("y", val)
        end)
        HookSliderEditBox(ySlider)
        scroll:AddChild(ySlider)

    end -- if not layoutCollapsed

    -- ================================================================
    -- Group Alpha
    -- ================================================================
    local alphaHeading = AceGUI:Create("Heading")
    alphaHeading:SetText("Group Alpha")
    ColorHeading(alphaHeading)
    alphaHeading:SetFullWidth(true)
    scroll:AddChild(alphaHeading)

    local alphaCollapsed = CS.collapsedSections["container_alpha"]
    AttachCollapseButton(alphaHeading, alphaCollapsed, function()
        CS.collapsedSections["container_alpha"] = not CS.collapsedSections["container_alpha"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not alphaCollapsed then
        local function RefreshContainerAlphaSettings()
            RefreshPanels()
            CooldownCompanion:RefreshConfigPanel()
        end

        local groupAlphaCb = AceGUI:Create("CheckBox")
        groupAlphaCb:SetLabel("Enable Group Alpha")
        groupAlphaCb:SetFullWidth(true)
        groupAlphaCb:SetValue(container.groupAlphaEnabled == true)
        groupAlphaCb:SetCallback("OnValueChanged", function(widget, event, value)
            container.groupAlphaEnabled = value == true
            if CooldownCompanion.RefreshAlphaUpdateDriver then
                CooldownCompanion:RefreshAlphaUpdateDriver()
            end
            RefreshContainerAlphaSettings()
        end)
        scroll:AddChild(groupAlphaCb)

        CreateInfoButton(groupAlphaCb.frame, groupAlphaCb.checkbg, "LEFT", "RIGHT", groupAlphaCb.text:GetStringWidth() + 4, 0, {
            "Group Alpha",
            {"When enabled, applies these alpha settings to panels anchored directly to this group. Panels anchored elsewhere keep their own alpha behavior.", 1, 1, 1, true},
        }, tabInfoButtons)

        if container.groupAlphaEnabled == true then
            BuildAlphaControls(scroll, container, RefreshContainerAlphaSettings, nil, {
                isGlobal = container.isGlobal,
                hideHeading = true,
                onBaselineChanged = function(val)
                    if CooldownCompanion.ApplyContainerAlphaPreview then
                        CooldownCompanion:ApplyContainerAlphaPreview(containerId, val)
                    end
                end,
            })
        end
    end -- if not alphaCollapsed

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
    local inheritedSources = CooldownCompanion:GetInheritedLoadConditionSources(container)
    local folder = container.folderId and db.folders and db.folders[container.folderId]
    local folderSpecs = folder and BuildEligibilityBadgeMap(
        folder.specs,
        folder.loadConditions and folder.loadConditions.specAllowlist
    )
    local folderHeroTalents = folder and folder.heroTalents
    local hasFolderSpecs = folderSpecs and next(folderSpecs)
    local hasFolderHeroTalents = folderHeroTalents and next(folderHeroTalents) ~= nil
    local function RefreshContainerLoadConditions()
        RefreshPanels()
        CooldownCompanion:RefreshConfigPanel()
    end

    AddScopedLoadConditionToggles(scroll, {
        target = container,
        defaults = CooldownCompanion:GetDefaultLoadConditions(),
        inheritedSources = inheritedSources,
        headingText = "Hide This Group In",
        headingTextWhenInherited = "Also Hide This Group In",
        inheritedCollapsedKey = "container_loadconditions_inherited",
        localCollapsedKey = "container_loadconditions_local",
        onChanged = RefreshContainerLoadConditions,
    })

    AddActiveEligibilitySummary(scroll, {
        target = container,
        inheritedSources = inheritedSources,
        eligibilitySubjectLabel = "group",
        allowClassEligibility = container.isGlobal == true,
        ownerCharKey = container.createdBy,
        useSpecAllowlist = hasFolderSpecs,
        allowedSpecRestricted = hasFolderSpecs,
        allowedSpecMap = folderSpecs,
        effectiveSpecs = folderSpecs,
        heroTalentsSource = folderHeroTalents,
        useHeroTalentsSource = hasFolderHeroTalents,
        disableHeroTalents = hasFolderHeroTalents,
        onChanged = RefreshContainerLoadConditions,
    })

    AddCharacterEligibilityControls(scroll, {
        target = container,
        inheritedSources = inheritedSources,
        eligibilitySubjectLabel = "group",
        allowClassEligibility = container.isGlobal == true,
        ownerCharKey = container.createdBy,
        characterCollapsedKey = "container_loadconditions_character",
        onChanged = RefreshContainerLoadConditions,
    })

    -- Class/spec eligibility section
    local specHeading = AceGUI:Create("Heading")
    specHeading:SetText("Class & Specialization Eligibility")
    ColorHeading(specHeading)
    specHeading:SetFullWidth(true)
    scroll:AddChild(specHeading)

    local specCollapsed = CS.collapsedSections["container_loadconditions_spec"]
    AttachCollapseButton(specHeading, specCollapsed, function()
        CS.collapsedSections["container_loadconditions_spec"] = not CS.collapsedSections["container_loadconditions_spec"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not specCollapsed then
        if hasFolderSpecs then
            local inheritedLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(inheritedLabel)
            inheritedLabel:SetText("|cff888888Specs set by the parent folder cannot be changed here.|r")
            inheritedLabel:SetFullWidth(true)
            scroll:AddChild(inheritedLabel)
        end

        AddClassSpecEligibilityControls(scroll, {
            target = container,
            inheritedSources = inheritedSources,
            eligibilitySubjectLabel = "group",
            allowClassEligibility = container.isGlobal == true,
            ownerCharKey = container.createdBy,
            useSpecAllowlist = hasFolderSpecs,
            allowedSpecRestricted = hasFolderSpecs,
            allowedSpecMap = folderSpecs,
            effectiveSpecs = folderSpecs,
            heroTalentsSource = folderHeroTalents,
            useHeroTalentsSource = hasFolderHeroTalents,
            disableHeroTalents = hasFolderHeroTalents,
            onChanged = RefreshContainerLoadConditions,
        })

        -- Only show Clear All when container has specs/hero-talents beyond folder cascade
        local hasOwnSpecs = false
        local function CheckOwnSpecs(specs)
            if type(specs) ~= "table" then
                return specs ~= nil
            end
            for specId in pairs(specs) do
                if not (folderSpecs and folderSpecs[tonumber(specId) or specId]) then
                    return true
                end
            end
            return false
        end
        if CheckOwnSpecs(container.specs)
            or CheckOwnSpecs(container.loadConditions and container.loadConditions.specAllowlist)
        then
            hasOwnSpecs = true
        end
        if not hasOwnSpecs and container.heroTalents and next(container.heroTalents) then
            hasOwnSpecs = true
        end
        if hasOwnSpecs then
            local clearBtn = AceGUI:Create("Button")
            clearBtn:SetText("Clear All Spec Filters")
            clearBtn:SetFullWidth(true)
            clearBtn:SetCallback("OnClick", function()
                if folder and type(folder.specs) == "table" and next(folder.specs) then
                    container.specs = CopyTable(folder.specs)
                else
                    container.specs = nil
                end
                if type(container.loadConditions) == "table" then
                    container.loadConditions.specAllowlist = nil
                end
                container.heroTalents = nil
                RefreshPanels()
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(clearBtn)
        end
    end -- not specCollapsed
end

local function BuildFolderLoadConditionsTab(scroll, folderId)
    local db = CooldownCompanion.db.profile
    local folder = db.folders and db.folders[folderId]
    if not folder then return end

    local function RefreshFolderOnly()
        CooldownCompanion:RefreshAllGroups()
        CooldownCompanion:RefreshConfigPanel()
    end

    local function RefreshFolderSpecDependents()
        CooldownCompanion:ApplyFolderSpecFilterToChildren(folderId)
        RefreshFolderOnly()
    end

    AddScopedLoadConditionToggles(scroll, {
        target = folder,
        defaults = CooldownCompanion:GetLocalLoadConditionDefaults(),
        inheritedSources = {},
        headingText = "Hide This Folder In",
        localCollapsedKey = "folder_loadconditions_local",
        preserveMissing = true,
        onChanged = function()
            if folder.loadConditions and not next(folder.loadConditions) then
                folder.loadConditions = nil
            end
            CooldownCompanion:RefreshAllGroups()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    AddActiveEligibilitySummary(scroll, {
        target = folder,
        inheritedSources = {},
        eligibilitySubjectLabel = "folder",
        allowClassEligibility = folder.section == "global",
        ownerCharKey = folder.createdBy,
        characterOnChanged = RefreshFolderOnly,
        specOnChanged = RefreshFolderSpecDependents,
    })

    AddCharacterEligibilityControls(scroll, {
        target = folder,
        inheritedSources = {},
        eligibilitySubjectLabel = "folder",
        allowClassEligibility = folder.section == "global",
        ownerCharKey = folder.createdBy,
        characterCollapsedKey = "folder_loadconditions_character",
        onChanged = RefreshFolderOnly,
    })

    local specHeading = AceGUI:Create("Heading")
    specHeading:SetText("Class & Specialization Eligibility")
    ColorHeading(specHeading)
    specHeading:SetFullWidth(true)
    scroll:AddChild(specHeading)

    local specCollapsed = CS.collapsedSections["folder_loadconditions_spec"]
    AttachCollapseButton(specHeading, specCollapsed, function()
        CS.collapsedSections["folder_loadconditions_spec"] = not CS.collapsedSections["folder_loadconditions_spec"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not specCollapsed then
        AddClassSpecEligibilityControls(scroll, {
            target = folder,
            inheritedSources = {},
            eligibilitySubjectLabel = "folder",
            allowClassEligibility = folder.section == "global",
            ownerCharKey = folder.createdBy,
            onChanged = RefreshFolderSpecDependents,
        })

        if folder.specs or folder.heroTalents then
            local clearSpecsBtn = AceGUI:Create("Button")
            clearSpecsBtn:SetText("Clear Folder Spec Filters")
            clearSpecsBtn:SetFullWidth(true)
            clearSpecsBtn:SetCallback("OnClick", function()
                folder.specs = nil
                folder.heroTalents = nil
                if type(folder.loadConditions) == "table" then
                    folder.loadConditions.specAllowlist = nil
                end
                RefreshFolderSpecDependents()
            end)
            scroll:AddChild(clearSpecsBtn)
        end
    end

    if CooldownCompanion:HasLocalLoadConditions(folder) then
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Folder Load Conditions")
        clearBtn:SetFullWidth(true)
        clearBtn:SetCallback("OnClick", function()
            folder.loadConditions = nil
            CooldownCompanion:RefreshAllGroups()
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(clearBtn)
    end
end

-- Expose for Config.lua
ST._BuildLayoutTab = BuildLayoutTab
ST._BuildAppearanceTab = BuildAppearanceTab
ST._BuildEffectsTab = BuildEffectsTab
ST._BuildContainerGeneralTab = BuildContainerGeneralTab
ST._BuildContainerLoadConditionsTab = BuildContainerLoadConditionsTab
ST._BuildFolderLoadConditionsTab = BuildFolderLoadConditionsTab
