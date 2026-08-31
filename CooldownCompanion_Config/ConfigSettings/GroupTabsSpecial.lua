local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local math_abs = math.abs
local math_max = math.max
local math_min = math.min
local tonumber = tonumber

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateInfoButton = ST._CreateInfoButton
local AddFontControls = ST._AddFontControls
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddColorRow = ST._AddColorRow
local BeginRowGrid = ST._BeginRowGrid

-- Imports from GroupTabsShared.lua
local WireMirrorFirstSlider = ST._WireMirrorFirstSlider

local tabInfoButtons = CS.tabInfoButtons

-- A dropdown sizes its menu from the 140px control it hangs under, which is
-- too narrow for user-named panels and the longer worded options below.
-- Captured in this file by BuildTextureIndicatorSection and
-- BuildTexturePanelAppearanceTab.
local WIDE_PULLOUT_WIDTH = 300

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- Populated at module load near the exports. The builders close over the
-- descriptor tables so custom AceGUI controls and duplicate effect labels can
-- bind exact Settings Finder targets.
local SPECIAL_FINDER = {
    trigger = {},
    triggerEffects = {},
    textureEffects = {},
    texture = {},
}

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

local function UpdateTexturePanelPreview(preview, settings, boxWidth, boxHeight)
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
    local maxWidth = tonumber(boxWidth) or (TEXTURE_PREVIEW_WIDTH - 8)
    local maxHeight = tonumber(boxHeight) or (TEXTURE_PREVIEW_HEIGHT - 8)
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

-- Exported so the pinned Live Preview mirror (ButtonPanelPreview.lua) can draw
-- a texture panel's real texture with the same fit-to-box renderer the in-tab
-- canvas uses. Called at runtime only (ButtonPanelPreview loads before this
-- file, so it must not be captured as an upvalue there).
ST._UpdateTexturePanelPreview = UpdateTexturePanelPreview

-- Texture-slider wiring keeps the config preview smooth without continuously
-- redrawing the runtime panel. The value is staged and previewed during drag;
-- the runtime visual applies once on mouse release (or edit-box confirmation).
local function AttachTexturePreviewSliderRefresh(sliderWidget, applyValue, previewFn, confirmFn, cancelFn)
    if not sliderWidget or not sliderWidget.slider or type(applyValue) ~= "function" then
        return
    end

    local sliderFrame = sliderWidget.slider
    sliderWidget._ccApplyLiveTextureValue = applyValue
    sliderWidget._ccRefreshTexturePreview = previewFn
    sliderWidget._ccConfirmTextureValue = confirmFn
    sliderWidget._ccCancelTextureValue = cancelFn
    sliderWidget._ccLastLiveTextureValue = nil
    -- AceGUI wheel changes have no release/confirm event, so these staged
    -- texture sliders intentionally accept drag or edit-box input only.
    sliderWidget._ccDisableTextureMouseWheel = true
    sliderFrame:EnableMouseWheel(false)

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
        local refreshPreview = widget._ccRefreshTexturePreview
        if type(refreshPreview) == "function" then
            refreshPreview()
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
        local confirmValue = widget._ccConfirmTextureValue
        if type(confirmValue) == "function" then
            confirmValue(value)
        end
    end)

    local prevOnRelease = sliderWidget.events and sliderWidget.events["OnRelease"]
    sliderWidget:SetCallback("OnRelease", function(widget, event)
        local cancelValue = widget._ccCancelTextureValue
        if type(cancelValue) == "function" then
            cancelValue(widget)
        end
        sliderFrame:SetScript("OnUpdate", nil)
        sliderFrame._ccLiveTextureSliderActive = nil
        widget._ccApplyLiveTextureValue = nil
        widget._ccRefreshTexturePreview = nil
        widget._ccConfirmTextureValue = nil
        widget._ccCancelTextureValue = nil
        widget._ccLastLiveTextureValue = nil
        widget._ccDisableTextureMouseWheel = nil
        sliderFrame:EnableMouseWheel(false)
        if prevOnRelease then
            prevOnRelease(widget, event)
        end
    end)

    local widgetFrame = sliderWidget.frame
    if widgetFrame and not widgetFrame._ccTextureMouseWheelHooked then
        widgetFrame._ccTextureMouseWheelHooked = true
        widgetFrame:HookScript("OnMouseDown", function(frame)
            local widget = frame.obj
            if widget and widget._ccDisableTextureMouseWheel and widget.slider then
                widget.slider:EnableMouseWheel(false)
            end
        end)
    end

    if sliderFrame._ccLiveTextureSliderHooked then
        return
    end

    sliderFrame._ccLiveTextureSliderHooked = true

    -- The row's track is a stock AceGUI Slider's frame, so frame.obj is that
    -- stock child, not the row. RowWidgets publishes the row as frame.cdcRow;
    -- the frame.obj fallback covers any plain slider widget.
    sliderFrame:HookScript("OnMouseDown", function(frame)
        frame._ccLiveTextureSliderActive = true
        frame:SetScript("OnUpdate", function(self)
            if not self._ccLiveTextureSliderActive then
                self:SetScript("OnUpdate", nil)
                return
            end

            local widget = self.cdcRow or self.obj
            if widget then
                pushValue(widget, widget:GetValue())
            end
        end)
    end)

    sliderFrame:HookScript("OnMouseUp", function(frame)
        frame._ccLiveTextureSliderActive = nil
        frame:SetScript("OnUpdate", nil)
        local widget = frame.cdcRow or frame.obj
        if widget then
            widget._ccLastLiveTextureValue = nil
        end
    end)

    sliderFrame:HookScript("OnHide", function(frame)
        frame._ccLiveTextureSliderActive = nil
        frame:SetScript("OnUpdate", nil)
        local widget = frame.cdcRow or frame.obj
        if widget then
            local cancelValue = widget._ccCancelTextureValue
            if type(cancelValue) == "function" then
                cancelValue(widget)
            end
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

local function RequestTexturePanelAuraRestyle(group, groupId)
    local buttonData = group and group.buttons and group.buttons[1] or nil
    if CooldownCompanion:IsTexturePanelAuraDisplayEnabled(group, buttonData) then
        CooldownCompanion:RequestAuraRebind("style", groupId)
    end
end

-- The only restyle seam for the Aura-controlled Texture kit is a full aura
-- rebind, which parks and re-binds EVERY slot in the profile and releases then
-- re-registers every native aura sound. RequestAuraRebind coalesces to one
-- frame, which is right for a discrete commit but not for the indicator's
-- colour picker and duration slider - those fire per drag tick, so the frame
-- coalesce still buys a whole-profile rebuild every frame. Trailing-throttle
-- them instead: the last edit always gets a flush within the window, and the
-- kit is invisible behind the config's force-visible render the whole time, so
-- nothing on screen waits on it. A throttle rather than a release callback
-- because a wheel step on an AceGUI slider commits through OnValueChanged with
-- no OnMouseUp, and would otherwise never restyle at all.
local TEXTURE_AURA_RESTYLE_THROTTLE = 0.25
local pendingTextureAuraRestyleGroupId

local function FlushTexturePanelAuraRestyle()
    local groupId = pendingTextureAuraRestyleGroupId
    pendingTextureAuraRestyleGroupId = nil
    if not groupId then
        return
    end
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId] or nil
    RequestTexturePanelAuraRestyle(group, groupId)
end

-- The rebind is profile-wide, so a second panel edited inside the window
-- overwriting the pending id costs nothing: either id flushes both.
local function ThrottleTexturePanelAuraRestyle(group, groupId)
    local buttonData = group and group.buttons and group.buttons[1] or nil
    if not (groupId and CooldownCompanion:IsTexturePanelAuraDisplayEnabled(group, buttonData)) then
        return
    end
    local alreadyArmed = pendingTextureAuraRestyleGroupId ~= nil
    pendingTextureAuraRestyleGroupId = groupId
    if not alreadyArmed then
        C_Timer.After(TEXTURE_AURA_RESTYLE_THROTTLE, FlushTexturePanelAuraRestyle)
    end
end

local function GetStandaloneTextureCommitCallback(group, groupId)
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
        RequestTexturePanelAuraRestyle(group, groupId)
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
    local groupId = CS.selectedGroup
    local pickerOpts = {
        groupId = groupId,
        buttonIndex = buttonIndex,
        initialSelection = settings and settings.sourceType and settings or nil,
        callback = GetStandaloneTextureCommitCallback(group, groupId),
    }

    if forceOpen or not (CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen()) then
        CS.StartPickAuraTexture(pickerOpts)
    elseif CS.RebindPickAuraTexture then
        CS.RebindPickAuraTexture(pickerOpts)
    end
end

-- Open the inline texture browser for a standalone texture/trigger panel by id.
-- Used by the big-preview click-to-browse affordance, which only has the
-- panel id at click time. Resolves the group + its texture settings and forces
-- the browser open.
function ST._OpenStandaloneTexturePicker(groupId)
    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
    if not group then
        return
    end
    local settings = GetStandaloneTextureSettings(group, true)
    OpenOrRebindStandaloneTexturePicker(group, settings, true)
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

-- Repaint the pinned Live Preview after a trigger display setting changes.
-- Prefers the display-only repaint: these callbacks fire on every tick of a
-- slider drag, and a full mirror rebuild would re-run per-entry usability and
-- load-condition queries and re-wire every selection-strip slot each frame.
-- Falls back to the full rebuild when there is no live mirror yet (the first
-- build of a tab, or a preview that is not showing).
local function RefreshTriggerPreviewMirror(groupId)
    if ST._RefreshTriggerDisplayVisual and ST._RefreshTriggerDisplayVisual(groupId) then
        return
    end
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(groupId)
    end
end

local function AddTriggerDisplayTypeDropdown(container, group)
    local displayDrop = AceGUI:Create("Dropdown")
    displayDrop:SetLabel("Display Type")
    if SPECIAL_FINDER.trigger.displayType and ST._BindSettingWidget then
        ST._BindSettingWidget(displayDrop, SPECIAL_FINDER.trigger.displayType, "Display Type")
    end
    displayDrop:SetList(TRIGGER_DISPLAY_TYPE_OPTIONS, TRIGGER_DISPLAY_TYPE_ORDER)
    displayDrop:SetValue(CooldownCompanion:GetTriggerPanelDisplayType(group, true))
    displayDrop:SetFullWidth(true)
    displayDrop:SetCallback("OnValueChanged", function(_, _, value)
        local triggerSettings = group.triggerSettings or {}
        group.triggerSettings = triggerSettings
        triggerSettings.displayType = value or "texture"
        RefreshStandaloneTriggerDisplay(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(displayDrop)
end

-- Row grammar (RowWidgets.lua): one collapsible section. The icon itself is
-- shown and picked in the Live Preview above, so the tab is settings rows only.
local function BuildTriggerIconAppearanceTab(container, group)
    local settings = CooldownCompanion:GetTriggerPanelIconSettings(group, true)
    local groupId = CS.selectedGroup

    local _, iconCollapsed = BuildCollapsibleSection(container, "Trigger Icon",
        "appearance_triggerIcon", nil, nil, ROW_SECTION)

    -- The icon renders in the Live Preview, which is also the picker: clicking
    -- it opens the icon picker and right-click clears. This tab holds only the
    -- settings rows, so a refresh repaints the runtime panel and that mirror.
    local function RefreshIconPreview()
        RefreshStandaloneTriggerDisplay(groupId)
        RefreshTriggerPreviewMirror(groupId)
    end

    if not ST._IsValidIconTexture(settings.manualIcon) then
        local emptyLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(emptyLabel)
        emptyLabel:SetFullWidth(true)
        emptyLabel:SetText("|cff888888Click the preview above to choose an icon.|r")
        container:AddChild(emptyLabel)
    end

    if not iconCollapsed then
    -- LEFT column: the icon itself - its shape, its size, and the two colors
    -- painted on it. RIGHT column: the border drawn around it.
    local iconLeft, iconRight = BeginRowGrid(container)

    AddCheckboxRow(iconLeft, {
        label = "Square Icons",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.square,
        value = settings.maintainAspectRatio ~= false,
        onChange = function(value)
            settings.maintainAspectRatio = value ~= false
            if settings.maintainAspectRatio then
                local size = settings.buttonSize or ST.BUTTON_SIZE
                settings.iconWidth = size
                settings.iconHeight = size
            end
            RefreshIconPreview()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if settings.maintainAspectRatio ~= false then
        local sizeRow = AddSliderRow(iconLeft, {
            label = "Button Size",
            setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.size,
            min = 10, max = 150, step = 0.1,
            value = settings.buttonSize or ST.BUTTON_SIZE,
        })
        WireMirrorFirstSlider(sizeRow, function(value)
            settings.buttonSize = value
            settings.iconWidth = value
            settings.iconHeight = value
        end, function()
            RefreshStandaloneTriggerDisplay(groupId)
        end, function()
            RefreshTriggerPreviewMirror(groupId)
        end, settings, { "buttonSize", "iconWidth", "iconHeight" })
    else
        local widthRow = AddSliderRow(iconLeft, {
            label = "Icon Width",
            setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.width,
            min = 10, max = 150, step = 0.1,
            value = settings.iconWidth or settings.buttonSize or ST.BUTTON_SIZE,
        })
        WireMirrorFirstSlider(widthRow, function(value)
            settings.iconWidth = value
        end, function()
            RefreshStandaloneTriggerDisplay(groupId)
        end, function()
            RefreshTriggerPreviewMirror(groupId)
        end, settings, "iconWidth")

        local heightRow = AddSliderRow(iconLeft, {
            label = "Icon Height",
            setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.height,
            min = 10, max = 150, step = 0.1,
            value = settings.iconHeight or settings.buttonSize or ST.BUTTON_SIZE,
        })
        WireMirrorFirstSlider(heightRow, function(value)
            settings.iconHeight = value
        end, function()
            RefreshStandaloneTriggerDisplay(groupId)
        end, function()
            RefreshTriggerPreviewMirror(groupId)
        end, settings, "iconHeight")
    end

    ST._BuildIconZoomControls(iconLeft, settings, RefreshIconPreview, {
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.zoom,
        previewRefresh = function()
            RefreshTriggerPreviewMirror(groupId)
        end,
    })

    -- deferCommit is deliberately absent throughout, matching the
    -- stock color pickers these rows replace: the callbacks repaint the
    -- canvas, they do not re-read the bound table every tick.
    AddColorRow(iconLeft, {
        label = "Base Icon Color",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.baseColor,
        tbl = settings, key = "iconTintColor",
        default = { 1, 1, 1, 1 }, hasAlpha = true,
        onConfirm = RefreshIconPreview, onChange = RefreshIconPreview,
    })

    AddColorRow(iconLeft, {
        label = "Background Color",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.background,
        tbl = settings, key = "backgroundColor",
        default = { 0, 0, 0, 0.5 }, hasAlpha = true,
        onConfirm = RefreshIconPreview, onChange = RefreshIconPreview,
    })

    local renderMode = AddBorderRenderModeDropdown(iconRight, settings, "borderRenderMode", function()
        RefreshIconPreview()
        CooldownCompanion:RefreshConfigPanel()
    end, nil, {
        row = true,
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.borderThickness,
    })
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderRow = AddSliderRow(iconRight, {
            label = "Border Size",
            setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.borderSize,
            indent = true,
            min = 0, max = 5, step = 0.1,
            value = settings.borderSize or ST.DEFAULT_BORDER_SIZE,
            disabled = borderThicknessLocked and true or false,
        })
        WireMirrorFirstSlider(borderRow, function(value)
            if borderThicknessLocked then return end
            settings.borderSize = value
        end, function()
            if borderThicknessLocked then return end
            RefreshStandaloneTriggerDisplay(groupId)
        end, function()
            if borderThicknessLocked then return end
            RefreshTriggerPreviewMirror(groupId)
        end, settings, "borderSize")
    end

    AddColorRow(iconRight, {
        label = "Border Color",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.borderColor,
        tbl = settings, key = "borderColor",
        default = { 0, 0, 0, 1 }, hasAlpha = true,
        onConfirm = RefreshIconPreview, onChange = RefreshIconPreview,
    })
    end -- not iconCollapsed

    RefreshTriggerPreviewMirror(groupId)
end

-- Row grammar (RowWidgets.lua): one collapsible section. The rendered text is
-- shown in the Live Preview above; the multi-line text box stays full-width on
-- the container because the text itself is prose-shaped, not a row form.
local function BuildTriggerTextAppearanceTab(container, group)
    local settings = CooldownCompanion:GetTriggerPanelTextSettings(group, true)
    local groupId = CS.selectedGroup
    local maxTextLength = CooldownCompanion.TRIGGER_PANEL_TEXT_MAX_LENGTH or 120
    local maxTextLines = CooldownCompanion.TRIGGER_PANEL_TEXT_MAX_LINES or 4

    local _, textCollapsed = BuildCollapsibleSection(container, "Trigger Text",
        "appearance_triggerText", nil, nil, ROW_SECTION)

    local function RefreshTextPreview()
        RefreshStandaloneTriggerDisplay(groupId)
        RefreshTriggerPreviewMirror(groupId)
    end

    local textBox = AceGUI:Create("MultiLineEditBox")
    textBox:SetLabel("Display Text")
    if SPECIAL_FINDER.trigger.text and SPECIAL_FINDER.trigger.text.value
        and ST._BindSettingWidget
    then
        ST._BindSettingWidget(textBox, SPECIAL_FINDER.trigger.text.value, "Display Text")
    end
    textBox:SetFullWidth(true)
    textBox:SetNumLines(maxTextLines)
    textBox.button:Hide()
    textBox:SetText(settings.value or "")
    local pendingTextValue = settings.value
    local textDirty = false
    local function CommitTriggerText()
        if textDirty then
            settings.value = pendingTextValue
            textDirty = false
            RefreshStandaloneTriggerDisplay(groupId)
        end
    end
    local function HandleTextChanged(widget, _, value)
        local sanitized = CooldownCompanion.SanitizeTriggerPanelTextValue and CooldownCompanion.SanitizeTriggerPanelTextValue(value) or (value or "")
        pendingTextValue = sanitized
        textDirty = true
        if widget and widget.SetText and widget:GetText() ~= sanitized and not widget._ccSyncingText then
            widget._ccSyncingText = true
            widget:SetText(sanitized)
            widget._ccSyncingText = nil
        end
        local committed = settings.value
        settings.value = sanitized
        RefreshTriggerPreviewMirror(groupId)
        settings.value = committed
    end
    textBox:SetCallback("OnTextChanged", HandleTextChanged)
    textBox:SetCallback("OnEditFocusLost", CommitTriggerText)
    textBox:SetCallback("OnRelease", CommitTriggerText)
    container:AddChild(textBox)

    local limitLabel = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(limitLabel)
    limitLabel:SetFullWidth(true)
    limitLabel:SetText("Up to " .. maxTextLines .. " lines and " .. maxTextLength .. " total characters.")
    limitLabel:SetColor(0.7, 0.7, 0.7)
    container:AddChild(limitLabel)

    if not textCollapsed then
    -- LEFT column: what the text is drawn WITH - size, face, outline.
    -- RIGHT column: what it looks like and where it lands.
    local textLeft, textRight = BeginRowGrid(container)

    AddFontControls(textLeft, settings, "text", {
        size = 12,
        sizeMin = 6,
        sizeMax = 72,
        font = "Friz Quadrata TT",
        outline = "OUTLINE",
    }, RefreshTextPreview, {
        row = true,
        settings = SPECIAL_FINDER.trigger.text and {
            size = SPECIAL_FINDER.trigger.text.fontSize,
            font = SPECIAL_FINDER.trigger.text.font,
            outline = SPECIAL_FINDER.trigger.text.outline,
        },
        previewRefresh = function()
            RefreshTriggerPreviewMirror(groupId)
        end,
    })

    -- The stock Dropdown had no order table and drew these three in whatever
    -- order pairs() produced; the row states the reading order outright.
    AddDropdownRow(textRight, {
        label = "Alignment",
        setting = SPECIAL_FINDER.trigger.text and SPECIAL_FINDER.trigger.text.alignment,
        list = { LEFT = "Left", CENTER = "Center", RIGHT = "Right" },
        order = { "LEFT", "CENTER", "RIGHT" },
        value = settings.textAlignment or "CENTER",
        onChange = function(value)
            settings.textAlignment = value
            RefreshTextPreview()
        end,
    })

    -- deferCommit is deliberately absent, matching the stock color pickers
    -- these rows replace.
    AddColorRow(textRight, {
        label = "Text Color",
        setting = SPECIAL_FINDER.trigger.text and SPECIAL_FINDER.trigger.text.color,
        tbl = settings, key = "textFontColor",
        default = { 1, 1, 1, 1 }, hasAlpha = true,
        onConfirm = RefreshTextPreview, onChange = RefreshTextPreview,
    })

    AddColorRow(textRight, {
        label = "Background Color",
        setting = SPECIAL_FINDER.trigger.text and SPECIAL_FINDER.trigger.text.background,
        tbl = settings, key = "textBgColor",
        default = { 0, 0, 0, 0 }, hasAlpha = true,
        onConfirm = RefreshTextPreview, onChange = RefreshTextPreview,
    })
    end -- not textCollapsed

    RefreshTriggerPreviewMirror(groupId)
end

local function RefreshTextureIndicatorRuntime(group, requestAuraRestyle)
    CooldownCompanion:RefreshAllAuraTextureVisuals()
    local refreshedMirror = ST._RefreshTextureIndicatorMirrorEffect
        and ST._RefreshTextureIndicatorMirrorEffect(CS.selectedGroup)
    if not refreshedMirror and ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
    end
    if requestAuraRestyle then
        ThrottleTexturePanelAuraRestyle(group, CS.selectedGroup)
    end
end

local function RefreshTextureIndicatorConfig(group, requestAuraRestyle)
    RefreshTextureIndicatorRuntime(group, requestAuraRestyle)
    CooldownCompanion:RefreshConfigPanel()
end

-- Row grammar (RowWidgets.lua): a CDC-SliderRow. The row's own value box
-- already accepts one decimal place, which is the whole job the pre-redesign
-- editbox hook it replaced did. Aura-controlled Texture effects also use this
-- inline on the Indicators tab, so the caller decides whether it is indented.
local function BuildTextureIndicatorSpeedSlider(container, config, label, onChange, indent, setting)
    local function RefreshSpeedPreview()
        local refreshedMirror = ST._RefreshTextureIndicatorMirrorEffect
            and ST._RefreshTextureIndicatorMirrorEffect(CS.selectedGroup)
        if not refreshedMirror and ST._RefreshButtonsPreviewMirror then
            ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
        end
    end
    AddSliderRow(container, {
        label = label,
        setting = setting,
        indent = indent == true,
        min = 0.1, max = 2.0, step = 0.05,
        value = config.speed or 0.5,
        onChange = function(value)
            ST._PreviewScalarSetting(config, "speed", value, RefreshSpeedPreview)
        end,
        onRelease = function(value)
            config.speed = value
            if onChange then
                onChange()
            else
                CooldownCompanion:RefreshAllAuraTextureVisuals()
            end
        end,
    })
end

-- Row grammar (RowWidgets.lua): one CDC-CheckBoxRow per indicator. Standard
-- Texture indicators retain their established advanced gear. Aura-controlled
-- Texture effects show their small option set directly in the 12.1 two-column
-- Indicators section instead: toggle and effect on the left, effect-specific
-- color/timing on the right.
--
-- `container` is nil when there is nothing to draw into - the section is
-- collapsed. The preview reconciliation at the foot still has to run in that
-- case (the same shape BuildBarActiveAuraSection uses in BarModeTabs): an
-- indicator that is no longer on must not leave its preview playing.
local function BuildTextureIndicatorSection(container, group, indicators, sectionKey, opts)
    local config = indicators and indicators[sectionKey]
    local sectionDef = TEXTURE_INDICATOR_SECTION_DEFS[sectionKey]
    if not config or not sectionDef then
        return
    end
    local auraControlled = opts and opts.auraControlled == true
    local finder = SPECIAL_FINDER.textureEffects[sectionKey]
    local function RefreshRuntime()
        RefreshTextureIndicatorRuntime(group, auraControlled)
    end

    if container then
    local enableCb = AddCheckboxRow(container, {
        label = sectionDef.label,
        setting = finder and finder.enabled,
        value = config.enabled,
        onChange = function(value)
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
                        RefreshTextureIndicatorConfig(group, auraControlled)
                        return
                    end
                end
            end

            config.enabled = value == true
            RefreshTextureIndicatorConfig(group, auraControlled)
        end,
    })

    local function BuildTextureIndicatorOptions(primary, details, inline)
        details = details or primary
        -- Aura-controlled Texture effects inherit Blizzard's aura visibility.
        -- A combat-only transition would require touching the forbidden child
        -- when combat changes, so that live-only refinement is intentionally
        -- absent here.
        if not auraControlled then
            AddCheckboxRow(primary, {
                label = "Show Only In Combat",
                setting = finder and finder.combatOnly,
                value = config.combatOnly or false,
                onChange = function(value)
                    config.combatOnly = value == true
                    CooldownCompanion:RefreshAllAuraTextureVisuals()
                end,
            })
        end

        local effectList, effectOrder = GetTextureIndicatorEffectList(indicators, sectionKey)
        AddDropdownRow(primary, {
            label = "Effect Type",
            setting = finder and finder.effectType,
            indent = inline == true,
            pulloutWidth = WIDE_PULLOUT_WIDTH,
            list = effectList,
            order = effectOrder,
            value = config.effectType,
            onChange = function(value)
                config.effectType = value or "none"
                RefreshTextureIndicatorConfig(group, auraControlled)
            end,
        })

        -- deferCommit is deliberately absent, matching the stock color picker
        -- this row replaced.
        if config.effectType == "colorShift" then
            AddColorRow(details, {
                label = "Shift Color",
                setting = finder and finder.shiftColor,
                indent = inline == true,
                tbl = config,
                key = "color",
                default = { 1, 1, 1, 1 },
                hasAlpha = true,
                onConfirm = RefreshRuntime,
                onChange = RefreshRuntime,
            })
            BuildTextureIndicatorSpeedSlider(details, config, "Shift Duration", RefreshRuntime, inline,
                finder and finder.shiftDuration)
        elseif config.effectType == "pulse" then
            BuildTextureIndicatorSpeedSlider(details, config, "Pulse Duration", RefreshRuntime, inline,
                finder and finder.pulseDuration)
        elseif config.effectType == "shrinkExpand" then
            BuildTextureIndicatorSpeedSlider(details, config, "Cycle Duration", RefreshRuntime, inline,
                finder and finder.cycleDuration)
        elseif config.effectType == "bounce" then
            BuildTextureIndicatorSpeedSlider(details, config, "Bounce Duration", RefreshRuntime, inline,
                finder and finder.bounceDuration)
        end
    end

    if auraControlled then
        if config.enabled then
            BuildTextureIndicatorOptions(container, opts and opts.detailsContainer, true)
        end
    else
        local advKey = "textureIndicator_" .. sectionKey
        AddAdvancedToggle(enableCb, advKey, tabInfoButtons, config.enabled, {
            title = sectionDef.label .. " Advanced",
            build = function(panel)
                BuildTextureIndicatorOptions(panel)
            end,
        })
    end
    end -- container

    if not config.enabled and CS.selectedGroup then
        CooldownCompanion:SetGroupTextureIndicatorPreview(CS.selectedGroup, sectionKey, false)
    end
end

-- Row grammar (RowWidgets.lua): one CDC-CheckBoxRow per effect, its advanced
-- gear chained off the label. Called exactly once per effect from the trigger
-- Effects tab below, so it was converted outright rather than growing an
-- opts.row mode. `container` is the grid column the row belongs to.
local function BuildTriggerPanelEffectSection(container, effects, effectKey)
    local config = effects and effects[effectKey]
    local def = TRIGGER_PANEL_EFFECT_DEFS[effectKey]
    local finder = SPECIAL_FINDER.triggerEffects[effectKey]
    if not config or not def then
        return
    end

    local enableCb = AddCheckboxRow(container, {
        label = def.label,
        setting = finder and finder.enabled,
        value = config.enabled,
        onChange = function(value)
            config.enabled = value == true
            CooldownCompanion:RefreshAllAuraTextureVisuals()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- both rows go straight onto the panel scroll.
    local function BuildTriggerEffectAdvanced(panel)
        -- deferCommit is deliberately absent, matching the stock color picker
        -- this row replaced.
        if effectKey == "colorShift" then
            AddColorRow(panel, {
                label = "Shift Color",
                setting = finder and finder.shiftColor,
                tbl = config,
                key = "color",
                default = { 1, 1, 1, 1 },
                hasAlpha = true,
                onConfirm = function() CooldownCompanion:RefreshAllAuraTextureVisuals() end,
                onChange = function()
                    local refreshedMirror = ST._RefreshTextureIndicatorMirrorEffect
                        and ST._RefreshTextureIndicatorMirrorEffect(CS.selectedGroup)
                    if not refreshedMirror then
                        ST._RefreshSelectedButtonsPreview()
                    end
                end,
            })
        end

        BuildTextureIndicatorSpeedSlider(panel, config, def.speedLabel, nil, false,
            finder and finder.duration)

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

    -- One row-grammar section. The gears inside it are safe behind a collapse:
    -- the preview command center's trigger route is tab-only (it plays every
    -- enabled effect at once, so it names no single advanced key), and nothing
    -- else queues a `triggerEffect_*` key.
    local _, effectsCollapsed = BuildCollapsibleSection(container, "Trigger Panel Effects",
        "effects_triggerEffects", nil, nil, ROW_SECTION)

    if not effectsCollapsed then
        -- The offered set is FILTERED (text displays drop Shrink / Expand), so
        -- the rows fill the left column first: ceil(n/2) left, the rest right.
        local effectLeft, effectRight = BeginRowGrid(container)
        local splitAt = math.ceil(#effectOrder / 2)
        for index, effectKey in ipairs(effectOrder) do
            BuildTriggerPanelEffectSection(index <= splitAt and effectLeft or effectRight, effects, effectKey)
        end
    end

    if not anyEnabled and CS.selectedGroup then
        CooldownCompanion:SetTriggerPanelEffectsPreview(CS.selectedGroup, false)
    end
end

-- Declared here rather than beside the icons tab's three section constants
-- below, because the builder that reads it comes first; the gear-to-section map
-- further down still sees it.
local EFFECTS_TEXTURE_INDICATORS_SECTION = "effects_textureIndicators"
local STANDARD_TEXTURE_INDICATOR_SECTION_ORDER = { "proc", "ready", "unusable" }

local function BuildTextureEffectsTab(container, group)
    local indicators = GetTextureIndicatorStore(group)
    if not indicators then
        return
    end

    local buttonData = group.buttons and group.buttons[1] or nil
    if CooldownCompanion:IsTexturePanelAuraDisplayEnabled(group, buttonData) then
        for _, sectionKey in ipairs(STANDARD_TEXTURE_INDICATOR_SECTION_ORDER) do
            CooldownCompanion:SetGroupTextureIndicatorPreview(CS.selectedGroup, sectionKey, false)
        end
        local _, indicatorsCollapsed = BuildCollapsibleSection(container, "Texture Indicators",
            EFFECTS_TEXTURE_INDICATORS_SECTION, nil, nil, ROW_SECTION)
        local indicatorLeft, indicatorRight
        if not indicatorsCollapsed then
            indicatorLeft, indicatorRight = BeginRowGrid(container)
        end
        -- Pass only the visible section into the uniqueness helper. Dormant
        -- Proc/Ready/Unusable settings cannot reserve an effect that will not
        -- run while Blizzard owns active-only visibility.
        BuildTextureIndicatorSection(indicatorLeft, group, { aura = indicators.aura }, "aura", {
            auraControlled = true,
            detailsContainer = indicatorRight,
        })
        return
    end

    CooldownCompanion:SetGroupTextureIndicatorPreview(CS.selectedGroup, "aura", false)

    -- One row-grammar section. Its three gears queue advanced keys, so the
    -- collapse key is declared in ST._INDICATORS_SECTION_BY_ADVANCED_KEY below
    -- and the preview command center clears it on the way past - a collapsed
    -- section builds no checkbox, and a queued key with no gear left to consume
    -- it expires silently.
    local _, indicatorsCollapsed = BuildCollapsibleSection(container, "Texture Indicators",
        EFFECTS_TEXTURE_INDICATORS_SECTION, nil, nil, ROW_SECTION)

    -- Three rows, so the fill-LEFT-first rule puts all of them in the left
    -- column; the right column is deliberately empty. The loop runs even while
    -- the section is collapsed, with a nil host: each indicator still has to
    -- reconcile its own preview.
    local indicatorLeft
    if not indicatorsCollapsed then
        indicatorLeft = BeginRowGrid(container)
    end
    local standardIndicators = {
        proc = indicators.proc,
        ready = indicators.ready,
        unusable = indicators.unusable,
    }
    for _, sectionKey in ipairs(STANDARD_TEXTURE_INDICATOR_SECTION_ORDER) do
        BuildTextureIndicatorSection(indicatorLeft, group, standardIndicators, sectionKey)
    end
end

-- Row grammar (RowWidgets.lua): one collapsible section of display rows. The
-- texture itself is shown and picked in the Live Preview above for both panel
-- kinds, so the tab holds no preview canvas or picker buttons.
--
-- Reached from BOTH paths that used to fall into the inline branch: a texture
-- panel, and a trigger panel whose display type is "texture".
--
-- The staging machinery below - the config-only settings copy, the
-- stage/refresh/cancel closures and AttachTextureValueSlider - moved verbatim.
-- It is owner-validated behaviour: runtime refreshes read the SAVED table, so a
-- texture panel edits a copy until the interaction is confirmed, and the row
-- conversion only changes which widget holds the control.
local function BuildTexturePanelAppearanceTab(container, group)
    local isTriggerPanel = group.displayMode == "trigger"
    local settings = GetStandaloneTextureSettings(group, true)
    if not settings then
        return
    end

    local groupId = CS.selectedGroup
    if CS.textureConfigPreviewStage and CS.textureConfigPreviewStage.groupId == groupId then
        CS.textureConfigPreviewStage = nil
    end
    local buttonData = group.buttons and group.buttons[1] or nil

    -- Runtime refreshes read the saved settings table directly, so texture
    -- panels need a separate config-only copy while an interaction is in
    -- progress. Otherwise a normal cooldown refresh could repaint the live
    -- display before the user releases the slider or confirms the color.
    local previewSettings = {}
    for key, value in pairs(settings) do
        if type(value) == "table" then
            local valueCopy = {}
            for nestedKey, nestedValue in pairs(value) do
                valueCopy[nestedKey] = nestedValue
            end
            previewSettings[key] = valueCopy
        else
            previewSettings[key] = value
        end
    end

    local function ClearTextureConfigPreviewStage()
        local staged = CS.textureConfigPreviewStage
        if staged and staged.groupId == groupId then
            CS.textureConfigPreviewStage = nil
            return true
        end
        return false
    end

    local function RefreshTexturePreview()
        CS.textureConfigPreviewStage = {
            groupId = groupId,
            settings = previewSettings,
        }
        if isTriggerPanel then
            RefreshTriggerPreviewMirror(groupId)
        elseif ST._RefreshButtonsPreviewMirror then
            ST._RefreshButtonsPreviewMirror(groupId)
        end
    end

    local function RefreshTextureRuntime(requestAuraRestyle)
        local groupFrame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
        local button = groupFrame and groupFrame.buttons and groupFrame.buttons[1] or nil
        if button then
            CooldownCompanion:UpdateAuraTextureVisual(button)
        else
            CooldownCompanion:RefreshAllAuraTextureVisuals()
        end
        if requestAuraRestyle and not isTriggerPanel then
            RequestTexturePanelAuraRestyle(group, groupId)
        end
    end

    local function RefreshTextureVisual(requestAuraRestyle)
        ClearTextureConfigPreviewStage()
        -- Both panel kinds repaint the pinned mirror after the saved value has
        -- been committed. Trigger panels can reuse their display-only repaint;
        -- texture panels rebuild the mirror outright.
        if isTriggerPanel then
            RefreshTriggerPreviewMirror(groupId)
        elseif ST._RefreshButtonsPreviewMirror then
            ST._RefreshButtonsPreviewMirror(groupId)
        end
        RefreshTextureRuntime(requestAuraRestyle ~= false)
    end

    local function CancelTexturePreviewChange()
        if ClearTextureConfigPreviewStage()
            and ST._RefreshButtonsPreviewMirror
        then
            ST._RefreshButtonsPreviewMirror(groupId)
        end
    end

    local textureValueChanged = RefreshTexturePreview

    local function AttachTextureValueSlider(slider, key)
        local confirmValue = function(value)
            settings[key] = value
            previewSettings[key] = value
            RefreshTextureVisual()
        end
        local cancelValue = function(widget)
            previewSettings[key] = settings[key]
            if widget and widget.SetValue then
                widget:SetValue(settings[key])
            end
            CancelTexturePreviewChange()
        end

        AttachTexturePreviewSliderRefresh(slider, function(value)
            previewSettings[key] = value
        end, textureValueChanged, confirmValue, cancelValue)
    end

    local heading, textureCollapsed = BuildCollapsibleSection(container,
        isTriggerPanel and "Trigger Texture" or "Texture Panel",
        "appearance_texture", nil, nil, ROW_SECTION)

    if not isTriggerPanel then
        -- The "?" chains off the end of the heading's label and the fading
        -- rule restarts after it.
        local textureInfoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
            "Texture Panel",
            {"This panel shows one standalone texture on your screen.", 1, 1, 1, true},
            " ",
            {"Its single entry decides when that texture appears.", 1, 1, 1, true},
        }, tabInfoButtons)
        AnchorLeftAlignedHeadingRule(heading, textureInfoBtn)
    end

    if not buttonData and not isTriggerPanel then
        local emptyLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(emptyLabel)
        emptyLabel:SetFullWidth(true)
        emptyLabel:SetText("|cff888888Add one entry to this panel first. The texture browser will open after that.|r")
        container:AddChild(emptyLabel)

        if CS.pendingTexturePickerOpen == CS.selectedGroup then
            CS.pendingTexturePickerOpen = nil
        end
        return
    end

    local selectionLabel = GetStandaloneTextureSelectionLabel(group, settings)

    if not selectionLabel then
        local emptyStateLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(emptyStateLabel)
        emptyStateLabel:SetFullWidth(true)
        emptyStateLabel:SetText(isTriggerPanel
            and "|cff888888Click the preview above to choose a texture.|r"
            or "|cff888888Select a texture from the Live Preview to show the display controls.|r")
        container:AddChild(emptyStateLabel)

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

        RefreshTexturePreview()
        return
    end

    if not textureCollapsed then
    -- LEFT column: what is drawn and how it is painted. RIGHT column: the
    -- geometry applied to it. Every slider on both sides is staged - the
    -- value is previewed during the drag and written for real on release.
    local textureLeft, textureRight = BeginRowGrid(container)

    local locationOptions, locationOrder = CooldownCompanion:GetTexturePanelLocationOptions()
    local selectedLayoutValue = CooldownCompanion:GetTexturePanelLayoutSelectionValue(settings.locationType or 0)
    AddDropdownRow(textureLeft, {
        label = "Texture Layout",
        setting = SPECIAL_FINDER.texture.layout,
        list = locationOptions,
        order = locationOrder,
        value = selectedLayoutValue,
        onChange = function(value)
            value = tonumber(value) or 0
            settings.locationType = value
            previewSettings.locationType = value
            RefreshTextureVisual()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if selectedLayoutValue == PREVIEW_LOCATION_LEFTRIGHT or selectedLayoutValue == PREVIEW_LOCATION_TOPBOTTOM then
        -- Only the paired layouts have a gap to set, so it reads as a child
        -- of the layout above it.
        local spacingRow = AddSliderRow(textureLeft, {
            label = "Pair Spacing",
            setting = SPECIAL_FINDER.texture.spacing,
            indent = true,
            min = MIN_TEXTURE_PAIR_SPACING, max = MAX_TEXTURE_PAIR_SPACING, step = 0.01,
            value = settings.pairSpacing or 0,
        })
        AttachTextureValueSlider(spacingRow, "pairSpacing")
    end

    AddDropdownRow(textureLeft, {
        label = "Texture Look",
        setting = SPECIAL_FINDER.texture.look,
        pulloutWidth = WIDE_PULLOUT_WIDTH,
        list = TEXTURE_BLEND_OPTIONS,
        order = TEXTURE_BLEND_ORDER,
        value = settings.blendMode or "BLEND",
        onChange = function(value)
            value = value or "BLEND"
            settings.blendMode = value
            previewSettings.blendMode = value
            RefreshTextureVisual()
        end,
    })

    local scaleRow = AddSliderRow(textureRight, {
        label = "Texture Scale",
        setting = SPECIAL_FINDER.texture.scale,
        min = 0.25, max = 4, step = 0.05,
        value = settings.scale or 1,
    })
    AttachTextureValueSlider(scaleRow, "scale")

    local rotationRow = AddSliderRow(textureRight, {
        label = "Rotation",
        setting = SPECIAL_FINDER.texture.rotation,
        min = MIN_TEXTURE_ROTATION, max = MAX_TEXTURE_ROTATION, step = 1,
        value = settings.rotation or 0,
    })
    AttachTextureValueSlider(rotationRow, "rotation")

    local stretchXRow = AddSliderRow(textureRight, {
        label = "Horizontal Stretch / Compress",
        setting = SPECIAL_FINDER.texture.stretchX,
        min = MIN_TEXTURE_STRETCH, max = MAX_TEXTURE_STRETCH, step = 0.05,
        value = settings.stretchX or 0,
    })
    AttachTextureValueSlider(stretchXRow, "stretchX")

    local stretchYRow = AddSliderRow(textureRight, {
        label = "Vertical Stretch / Compress",
        setting = SPECIAL_FINDER.texture.stretchY,
        min = MIN_TEXTURE_STRETCH, max = MAX_TEXTURE_STRETCH, step = 0.05,
        value = settings.stretchY or 0,
    })
    AttachTextureValueSlider(stretchYRow, "stretchY")

    local alphaRow = AddSliderRow(textureLeft, {
        label = "Texture Alpha",
        setting = SPECIAL_FINDER.texture.alpha,
        min = 0.05, max = 1, step = 0.05,
        value = settings.alpha or 1,
    })
    AttachTextureValueSlider(alphaRow, "alpha")

    local function ConfirmTextureColor()
        local color = previewSettings.color or { 1, 1, 1, 1 }
        settings.color = { color[1], color[2], color[3], color[4] }
        RefreshTextureVisual()
    end

    -- Bound to the STAGED table, exactly as the stock picker was: the drag
    -- writes previewSettings.color and only ConfirmTextureColor copies it
    -- across to the saved settings. deferCommit stays absent for the same
    -- reason it was absent before - the staging copy already keeps the live
    -- renderers off the uncommitted value.
    local colorRow = AddColorRow(textureLeft, {
        label = "Texture Color",
        setting = SPECIAL_FINDER.texture.color,
        tbl = previewSettings,
        key = "color",
        default = { 1, 1, 1, 1 },
        hasAlpha = true,
        onConfirm = ConfirmTextureColor,
        onChange = textureValueChanged,
    })

    -- The cancel triad hangs on the row's embedded stock ColorPicker - the
    -- same widget SetupColorCallbacks was pointed at - so releasing the row
    -- (which releases the child) and hiding the tab both roll the staged color
    -- back.
        local colorPicker = colorRow.colorPicker
        colorPicker._ccCancelTextureValue = function(widget)
            local color = settings.color or { 1, 1, 1, 1 }
            previewSettings.color = { color[1], color[2], color[3], color[4] }
            widget:SetColor(color[1], color[2], color[3], color[4])
            CancelTexturePreviewChange()
        end

        local prevOnRelease = colorPicker.events and colorPicker.events["OnRelease"]
        colorPicker:SetCallback("OnRelease", function(widget, event)
            local cancelValue = widget._ccCancelTextureValue
            if type(cancelValue) == "function" then
                cancelValue(widget)
            end
            widget._ccCancelTextureValue = nil
            if prevOnRelease then
                prevOnRelease(widget, event)
            end
        end)

        if not colorPicker.frame._ccTexturePreviewHideHooked then
            colorPicker.frame._ccTexturePreviewHideHooked = true
            colorPicker.frame:HookScript("OnHide", function(frame)
                local widget = frame.obj
                local cancelValue = widget and widget._ccCancelTextureValue
                if type(cancelValue) == "function" then
                    cancelValue(widget)
                end
            end)
        end
    end -- not textureCollapsed

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

    RefreshTexturePreview()
end

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

local SPECIAL_FINDER_SCOPE = { "panel", "entry" }

local function SpecialFinderTrigger(context)
    return context and context.group and context.displayMode == "trigger"
end

local function SpecialFinderTriggerDisplayType(context)
    local settings = context and context.group and context.group.triggerSettings
    local displayType = settings and settings.displayType
    if displayType == "icon" or displayType == "text" then
        return displayType
    end
    return "texture"
end

local function SpecialFinderTriggerType(displayType)
    return function(context)
        return SpecialFinderTrigger(context)
            and SpecialFinderTriggerDisplayType(context) == displayType
    end
end

local function SpecialFinderTexture(context)
    return context and context.group and context.displayMode == "textures"
end

local function SpecialFinderTriggerIconSettings(context)
    local trigger = context and context.group and context.group.triggerSettings
    return trigger and trigger.icon or nil
end

local function SpecialFinderTriggerTextSettings(context)
    local trigger = context and context.group and context.group.triggerSettings
    return trigger and trigger.text or nil
end

local function SpecialFinderTriggerEffects(context)
    local trigger = context and context.group and context.group.triggerSettings
    return trigger and trigger.effects or nil
end

local function SpecialFinderTextureIndicators(context)
    local style = context and context.group and context.group.style
    return style and style.textureIndicators or nil
end

local function SpecialFinderTextureAuraControlled(context)
    local group = context and context.group
    local buttonData = group and group.buttons and group.buttons[1]
    return SpecialFinderTexture(context)
        and CooldownCompanion:IsTexturePanelAuraDisplayEnabled(group, buttonData)
end

local function SpecialFinderTextureStandard(context)
    return SpecialFinderTexture(context) and not SpecialFinderTextureAuraControlled(context)
end

local function SpecialFinderTextureSettings(context)
    local group = context and context.group
    if not group then return nil end
    if group.displayMode == "trigger" then
        local trigger = group.triggerSettings
        return trigger and trigger.signal or nil
    end
    return group.textureSettings
end

local function SpecialFinderTextureAppearance(context)
    local group = context and context.group
    local rightMode = SpecialFinderTexture(context)
        or (SpecialFinderTrigger(context) and SpecialFinderTriggerDisplayType(context) == "texture")
    if not rightMode or (group.displayMode == "textures" and not (group.buttons and group.buttons[1])) then
        return false
    end
    local settings = SpecialFinderTextureSettings(context)
    return settings and settings.sourceType ~= nil and settings.sourceValue ~= nil
end

local function SpecialFinderTexturePair(context)
    if not SpecialFinderTextureAppearance(context) then return false end
    local settings = SpecialFinderTextureSettings(context)
    local layout = CooldownCompanion:GetTexturePanelLayoutSelectionValue(settings.locationType or 0)
    return layout == PREVIEW_LOCATION_LEFTRIGHT or layout == PREVIEW_LOCATION_TOPBOTTOM
end

local function SpecialFinderTriggerIconSquare(context)
    if not SpecialFinderTriggerType("icon")(context) then return false end
    local settings = SpecialFinderTriggerIconSettings(context)
    return not settings or settings.maintainAspectRatio ~= false
end

local function SpecialFinderTriggerIconFreeform(context)
    if not SpecialFinderTriggerType("icon")(context) then return false end
    local settings = SpecialFinderTriggerIconSettings(context)
    return settings and settings.maintainAspectRatio == false
end

local function SpecialFinderTriggerIconCustomBorder(context)
    if not SpecialFinderTriggerType("icon")(context) then return false end
    local settings = SpecialFinderTriggerIconSettings(context) or {}
    return ST.GetBorderRenderMode(settings, "borderRenderMode") ~= ST.BORDER_RENDER_MODE_CRISP
end

local function SpecialFinderTriggerEffectOffered(context, effectKey)
    if not SpecialFinderTrigger(context) then return false end
    return effectKey ~= "shrinkExpand" or SpecialFinderTriggerDisplayType(context) ~= "text"
end

local function SpecialFinderTriggerEffectEnabled(context, effectKey)
    if not SpecialFinderTriggerEffectOffered(context, effectKey) then return false end
    local effects = SpecialFinderTriggerEffects(context)
    return effects and effects[effectKey] and effects[effectKey].enabled == true
end

local function SpecialFinderTextureEffectShown(context, sectionKey)
    if sectionKey == "aura" then
        return SpecialFinderTextureAuraControlled(context)
    end
    return SpecialFinderTextureStandard(context)
end

local function SpecialFinderTextureEffectEnabled(context, sectionKey)
    if not SpecialFinderTextureEffectShown(context, sectionKey) then return false end
    local indicators = SpecialFinderTextureIndicators(context)
    return indicators and indicators[sectionKey] and indicators[sectionKey].enabled == true
end

local function SpecialFinderTextureEffectType(context, sectionKey, effectType)
    if not SpecialFinderTextureEffectEnabled(context, sectionKey) then return false end
    local indicators = SpecialFinderTextureIndicators(context)
    return indicators[sectionKey].effectType == effectType
end

if ST._DefineSettingRoute then
    SPECIAL_FINDER.trigger.displayType = ST._DefineSettingRoute({
        idPrefix = "panel.trigger.appearance.display",
        scope = SPECIAL_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "display",
        sectionLabel = "Trigger Display",
        rowScope = "primary",
        applies = SpecialFinderTrigger,
    }):Setting({ key = "type", label = "Display Type", aliases = { "trigger type" } })

    SPECIAL_FINDER.trigger.icon = ST._DefineSettingRoute({
        idPrefix = "panel.trigger.appearance.icon",
        scope = SPECIAL_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "triggerIcon",
        sectionLabel = "Trigger Icon",
        collapseKeys = { "appearance_triggerIcon" },
        rowScope = "primary",
        applies = SpecialFinderTriggerType("icon"),
    }):Settings({
        square = { label = "Square Icons" },
        size = { label = "Button Size", applies = SpecialFinderTriggerIconSquare },
        width = { label = "Icon Width", applies = SpecialFinderTriggerIconFreeform },
        height = { label = "Icon Height", applies = SpecialFinderTriggerIconFreeform },
        zoom = { label = "Icon Zoom" },
        baseColor = { label = "Base Icon Color" },
        background = { label = "Background Color" },
        borderThickness = { label = "Border Thickness" },
        borderSize = { label = "Border Size", applies = SpecialFinderTriggerIconCustomBorder },
        borderColor = { label = "Border Color" },
    })

    SPECIAL_FINDER.trigger.text = ST._DefineSettingRoute({
        idPrefix = "panel.trigger.appearance.text",
        scope = SPECIAL_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "triggerText",
        sectionLabel = "Trigger Text",
        collapseKeys = { "appearance_triggerText" },
        rowScope = "primary",
        applies = SpecialFinderTriggerType("text"),
    }):Settings({
        value = { label = "Display Text", aliases = { "trigger text" } },
        fontSize = { label = "Font Size" },
        font = { label = "Font" },
        outline = { label = "Font Outline" },
        alignment = { label = "Alignment" },
        color = { label = "Text Color" },
        background = { label = "Background Color" },
    })

    for _, effectKey in ipairs(TEXTURE_INDICATOR_EFFECT_ORDER) do
        local key = effectKey
        local def = TRIGGER_PANEL_EFFECT_DEFS[key]
        local top = ST._DefineSettingRoute({
            idPrefix = "panel.trigger.effects." .. key,
            scope = SPECIAL_FINDER_SCOPE,
            tab = "effects",
            tabLabel = "Indicators",
            section = "triggerEffects",
            sectionLabel = "Trigger Panel Effects",
            collapseKeys = { "effects_triggerEffects" },
            rowScope = "primary",
            applies = function(context) return SpecialFinderTriggerEffectOffered(context, key) end,
        })
        local finder = {
            enabled = top:Setting({ key = "enabled", label = def.label }),
        }
        local advanced = ST._DefineSettingRoute({
            idPrefix = "panel.trigger.effects." .. key .. ".advanced",
            scope = SPECIAL_FINDER_SCOPE,
            tab = "effects",
            tabLabel = "Indicators",
            section = "triggerEffects",
            sectionLabel = def.label .. " Effect",
            collapseKeys = { "effects_triggerEffects" },
            rowScope = "primary",
            advancedKey = "triggerEffect_" .. key,
            applies = function(context) return SpecialFinderTriggerEffectEnabled(context, key) end,
        })
        finder.duration = advanced:Setting({ key = "duration", label = def.speedLabel })
        if key == "colorShift" then
            finder.shiftColor = advanced:Setting({ key = "color", label = "Shift Color" })
        end
        SPECIAL_FINDER.triggerEffects[key] = finder
    end

    for _, sectionKey in ipairs({ "proc", "aura", "ready", "unusable" }) do
        local key = sectionKey
        local sectionDef = TEXTURE_INDICATOR_SECTION_DEFS[key]
        local top = ST._DefineSettingRoute({
            idPrefix = "panel.texture.effects." .. key,
            scope = SPECIAL_FINDER_SCOPE,
            tab = "effects",
            tabLabel = "Indicators",
            section = "textureIndicators",
            sectionLabel = "Texture Indicators",
            collapseKeys = { EFFECTS_TEXTURE_INDICATORS_SECTION },
            rowScope = "primary",
            applies = function(context) return SpecialFinderTextureEffectShown(context, key) end,
        })
        local finder = {
            enabled = top:Setting({ key = "enabled", label = sectionDef.label }),
        }
        local options = ST._DefineSettingRoute({
            idPrefix = "panel.texture.effects." .. key .. ".options",
            scope = SPECIAL_FINDER_SCOPE,
            tab = "effects",
            tabLabel = "Indicators",
            section = "textureIndicators",
            sectionLabel = sectionDef.label:gsub("^Show ", ""),
            collapseKeys = { EFFECTS_TEXTURE_INDICATORS_SECTION },
            rowScope = "primary",
            advancedKey = key == "aura" and nil or ("textureIndicator_" .. key),
            applies = function(context) return SpecialFinderTextureEffectEnabled(context, key) end,
        })
        finder.combatOnly = options:Setting({
            key = "combatOnly", label = "Show Only In Combat",
            applies = function(context) return key ~= "aura" and SpecialFinderTextureEffectEnabled(context, key) end,
        })
        finder.effectType = options:Setting({ key = "type", label = "Effect Type" })
        finder.shiftColor = options:Setting({
            key = "shiftColor", label = "Shift Color",
            applies = function(context) return SpecialFinderTextureEffectType(context, key, "colorShift") end,
        })
        finder.shiftDuration = options:Setting({
            key = "shiftDuration", label = "Shift Duration",
            applies = function(context) return SpecialFinderTextureEffectType(context, key, "colorShift") end,
        })
        finder.pulseDuration = options:Setting({
            key = "pulseDuration", label = "Pulse Duration",
            applies = function(context) return SpecialFinderTextureEffectType(context, key, "pulse") end,
        })
        finder.cycleDuration = options:Setting({
            key = "cycleDuration", label = "Cycle Duration",
            applies = function(context) return SpecialFinderTextureEffectType(context, key, "shrinkExpand") end,
        })
        finder.bounceDuration = options:Setting({
            key = "bounceDuration", label = "Bounce Duration",
            applies = function(context) return SpecialFinderTextureEffectType(context, key, "bounce") end,
        })
        SPECIAL_FINDER.textureEffects[key] = finder
    end

    SPECIAL_FINDER.texture = ST._DefineSettingRoute({
        idPrefix = "panel.texture.appearance",
        scope = SPECIAL_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "texture",
        sectionLabel = "Texture",
        collapseKeys = { "appearance_texture" },
        rowScope = "primary",
        applies = SpecialFinderTextureAppearance,
    }):Settings({
        layout = { label = "Texture Layout" },
        spacing = { label = "Pair Spacing", applies = SpecialFinderTexturePair },
        look = { label = "Texture Look", aliases = { "blend mode" } },
        scale = { label = "Texture Scale" },
        rotation = { label = "Rotation" },
        stretchX = { label = "Horizontal Stretch / Compress", aliases = { "horizontal stretch" } },
        stretchY = { label = "Vertical Stretch / Compress", aliases = { "vertical stretch" } },
        alpha = { label = "Texture Alpha", aliases = { "opacity" } },
        color = { label = "Texture Color" },
    })
end

ST._AddTriggerDisplayTypeDropdown = AddTriggerDisplayTypeDropdown
ST._BuildTriggerIconAppearanceTab = BuildTriggerIconAppearanceTab
ST._BuildTriggerTextAppearanceTab = BuildTriggerTextAppearanceTab
ST._BuildTriggerEffectsTab = BuildTriggerEffectsTab
ST._BuildTextureEffectsTab = BuildTextureEffectsTab
ST._BuildTexturePanelAppearanceTab = BuildTexturePanelAppearanceTab
ST._GetStandaloneTextureSettings = GetStandaloneTextureSettings
ST._OpenOrRebindStandaloneTexturePicker = OpenOrRebindStandaloneTexturePicker
ST._EFFECTS_TEXTURE_INDICATORS_SECTION = EFFECTS_TEXTURE_INDICATORS_SECTION
