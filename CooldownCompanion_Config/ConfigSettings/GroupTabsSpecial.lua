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
local CreateInfoButton = ST._CreateInfoButton
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local AddAdvancedToggle = ST._AddAdvancedToggle
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
    aura = {label = "Show Aura Effect"},
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


local function TextureEffectOffered(group, effectKey)
    return not (ST.Indicator.IsAura(group) and group.indicatorSettings.displayType == "text" and effectKey == "colorShift")
end

local function GetTextureIndicatorEffectList(_, _, group)
    local list, order = {}, {}
    for _, key in ipairs(TEXTURE_INDICATOR_EFFECT_ORDER) do
        if TextureEffectOffered(group, key) then
            list[key], order[#order + 1] = TEXTURE_INDICATOR_EFFECT_OPTIONS[key], key
        end
    end
    return list, order
end


local SCREEN_LOCATION = Enum and Enum.ScreenLocationType or {}
local PREVIEW_LOCATION_LEFTRIGHT = SCREEN_LOCATION.LeftRight or 9
local PREVIEW_LOCATION_TOPBOTTOM = SCREEN_LOCATION.TopBottom or 10




-- Exported so the pinned Live Preview mirror (ButtonPanelPreview.lua) can draw
-- a texture panel's real texture with the same fit-to-box renderer the in-tab
-- canvas uses. Called at runtime only (ButtonPanelPreview loads before this
-- file, so it must not be captured as an upvalue there).

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

    local buttonIndex = nil
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
    local group = CooldownCompanion.db.profile.groups[groupId]
    if ST.Indicator.IsAura(group) then CooldownCompanion:RequestAuraRebind("style", groupId) end
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

-- Display selection and its content actions use the same section / row grid
-- as the styling controls below. Explanations live in the heading's help.

-- Row grammar (RowWidgets.lua): one collapsible section. The icon itself is
-- shown and picked in the Live Preview above, so the tab is settings rows only.
local function BuildTriggerIconAppearanceTab(container, group)
    local settings = CooldownCompanion:GetTriggerPanelIconSettings(group, true)
    local groupId = CS.selectedGroup

    local _, iconCollapsed = BuildCollapsibleSection(container, "Icon",
        "appearance_triggerIcon", nil, nil, ROW_SECTION)

    -- The icon renders in the Live Preview, which is also the picker: clicking
    -- it opens the icon picker and right-click clears. This tab holds only the
    -- settings rows, so a refresh repaints the runtime panel and that mirror.
    local function RefreshIconPreview()
        RefreshStandaloneTriggerDisplay(groupId)
        RefreshTriggerPreviewMirror(groupId)
    end

    if not iconCollapsed then
    -- LEFT column: the icon itself - its shape, its size, and the two colors
    -- painted on it. RIGHT column: the border drawn around it.
    local iconLeft, iconRight = BeginRowGrid(container)

    AddCheckboxRow(iconLeft, {
        label = "Square Icon",
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
            label = "Icon Size",
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

    AddColorRow(iconLeft, {
        label = "Icon Color",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.baseColor,
        tbl = settings, key = "iconTintColor",
        default = { 1, 1, 1, 1 }, hasAlpha = true,
        onConfirm = RefreshIconPreview,
    })

    AddColorRow(iconLeft, {
        label = "Background Color",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.background,
        tbl = settings, key = "backgroundColor",
        default = { 0, 0, 0, 0.5 }, hasAlpha = true,
        onConfirm = RefreshIconPreview,
    })

    local renderMode, borderModeRow = AddBorderRenderModeDropdown(iconRight, settings, "borderRenderMode", function()
        RefreshIconPreview()
        CooldownCompanion:RefreshConfigPanel()
    end, nil, {
        row = true,
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.borderThickness,
    })
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    ST._AddAdvancedToggle(borderModeRow, "triggerIconBorder", {}, renderMode ~= ST.BORDER_RENDER_MODE_CRISP, {
        build = function(panel)
            local borderRow = AddSliderRow(panel, {
                label = "Border Size",
                setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.borderSize,
                indent = false,
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
        end,
    })

    AddColorRow(iconRight, {
        label = "Border Color",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.borderColor,
        tbl = settings, key = "borderColor",
        default = { 0, 0, 0, 1 }, hasAlpha = true,
        onConfirm = RefreshIconPreview,
    })
    end -- not iconCollapsed

    RefreshTriggerPreviewMirror(groupId)
end

-- Row grammar (RowWidgets.lua): one collapsible section. The rendered text is
-- shown in the Live Preview above; the multi-line text box stays full-width on
-- the container because the text itself is prose-shaped, not a row form.

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
    local function SaveEffect()
        if ST.IsIndicatorGroup(group) then
            ST.Indicator.SelectNativeEffect(group, config.effectType, config.enabled)
        end
    end
    local function RefreshRuntime()
        RefreshTextureIndicatorRuntime(group, auraControlled)
    end
    local function RefreshConfig()
        SaveEffect()
        RefreshTextureIndicatorConfig(group, auraControlled)
    end

    if container then
    local function EnableTextureIndicator()
        if config.effectType == "none" then
            local _, order = GetTextureIndicatorEffectList(nil, nil, group)
            config.effectType = order[1]
        end
        config.enabled = true
        RefreshConfig()
    end

    local enableCb = AddCheckboxRow(container, {
        label = sectionDef.label,
        setting = finder and finder.enabled,
        value = config.enabled,
        onChange = function(value)
            if value then
                EnableTextureIndicator()
                return
            end
            config.enabled = false
            RefreshConfig()
        end,
    })

    local function BuildTextureIndicatorOptions(primary, details, inline)
        details = details or primary
        -- Timings/colors bind the saved owner directly so the shared temporary
        -- preview/restore transaction sees the same data as both renderers.
        local effectConfig = ST.IsIndicatorGroup(group) and ST.Indicator.Effects(group)[config.effectType] or config
        -- Aura-controlled Texture effects inherit Blizzard's aura visibility.
        -- A combat-only transition would require touching the forbidden child
        -- when combat changes, so that live-only refinement is intentionally
        -- absent here.

        local effectList, effectOrder = GetTextureIndicatorEffectList(indicators, sectionKey, group)
        local dormant = not TextureEffectOffered(group, config.effectType)
        if dormant then
            effectList.none = "No Artwork Effect"
            table.insert(effectOrder, 1, "none")
            ST._AddLabelRow(primary, {label="Color Shift is saved for icon and texture displays."})
        end
        AddDropdownRow(primary, {
            label = "Effect Type",
            setting = finder and finder.effectType,
            indent = inline == true,
            pulloutWidth = WIDE_PULLOUT_WIDTH,
            list = effectList,
            order = effectOrder,
            value = dormant and "none" or config.effectType,
            onChange = function(value)
                config.effectType = value or "none"
                RefreshConfig()
            end,
        })

        if config.effectType == "colorShift" and not dormant then
            AddColorRow(details, {
                label = "Shift Color",
                setting = finder and finder.shiftColor,
                indent = inline == true,
                tbl = effectConfig,
                key = "color",
                default = { 1, 1, 1, 1 },
                hasAlpha = true,
                onConfirm = RefreshRuntime,
            })
            BuildTextureIndicatorSpeedSlider(details, effectConfig, "Shift Duration", RefreshRuntime, inline,
                finder and finder.shiftDuration)
        elseif config.effectType == "pulse" then
            BuildTextureIndicatorSpeedSlider(details, effectConfig, "Pulse Duration", RefreshRuntime, inline,
                finder and finder.pulseDuration)
        elseif config.effectType == "shrinkExpand" then
            BuildTextureIndicatorSpeedSlider(details, effectConfig, "Cycle Duration", RefreshRuntime, inline,
                finder and finder.cycleDuration)
        elseif config.effectType == "bounce" then
            BuildTextureIndicatorSpeedSlider(details, effectConfig, "Bounce Duration", RefreshRuntime, inline,
                finder and finder.bounceDuration)
        end
    end

    if config.enabled then
        BuildTextureIndicatorOptions(container, opts and opts.detailsContainer, true)
    end
    end -- container

    if not config.enabled and CS.selectedGroup then
        ST._ConfigPreview.StopCommand("texture" .. sectionKey:gsub("^%l", string.upper), CS.selectedGroup)
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
        AddDropdownRow(panel, {
            label = "Animate When",
            list = {always="Indicator Is Shown",proc="Proc Active",ready="Ready",unusable="Unusable",aura="Aura (Unavailable)"},
            order = {"always","proc","ready","unusable"}, value = config.activation or "always",
            setting = finder and finder.activation,
            onChange = function(value)
                config.activation = value
                CooldownCompanion:RefreshAllAuraTextureVisuals()
            end,
        })
        AddCheckboxRow(panel, {label="Only In Combat", setting=finder and finder.combatOnly, value=config.combatOnly == true,
            onChange=function(value)
                config.combatOnly=value
                CooldownCompanion:RefreshAllAuraTextureVisuals()
            end})
        if effectKey == "colorShift" then
            AddColorRow(panel, {
                label = "Shift Color",
                setting = finder and finder.shiftColor,
                tbl = config,
                key = "color",
                default = { 1, 1, 1, 1 },
                hasAlpha = true,
                onConfirm = function() CooldownCompanion:RefreshAllAuraTextureVisuals() end,
                onPreview = function()
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
    AddAdvancedToggle(enableCb, advKey, tabInfoButtons, true, {
        title = def.label .. " Advanced",
        build = BuildTriggerEffectAdvanced,
        -- Non-lens lazy spec (ST._ResolveAdvancedUnlock): write-true plus
        -- the trigger effects' restyle-then-rebuild refresh sequence.
        unlock = not config.enabled and {
            target = config,
            enable = { label = "Enable " .. def.label, key = "enabled" },
            refreshKind = "auraTextures",
        } or nil,
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
    -- enabled effect at once, so it names no single advanced key), and the
    -- finder's structural trigger-effect routes DO queue `triggerEffect_*`
    -- keys but always force this section open first (collapseKeys names
    -- "effects_triggerEffects"), so the gear builds and consumes the queue.
    -- Any future entrance that queues one of these keys must do the same.
    local _, effectsCollapsed = BuildCollapsibleSection(container, "Visual Effects",
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
        ST._ConfigPreview.StopCommand("triggerEffects", CS.selectedGroup)
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
            ST._ConfigPreview.StopCommand("texture" .. sectionKey:gsub("^%l", string.upper), CS.selectedGroup)
        end
        local _, indicatorsCollapsed = BuildCollapsibleSection(container, "Visual Effects",
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


end

-- Row grammar (RowWidgets.lua): shape and color sections of display rows. The
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
    local isTriggerPanel = CooldownCompanion:IsTriggerPanelGroup(group)
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

    if not buttonData and not isTriggerPanel then
        local emptyLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(emptyLabel)
        emptyLabel:SetFullWidth(true)
        emptyLabel:SetText("|cff888888Add one entry to control when this texture appears. Use the add field or drag an entry into Live Preview.|r")
        container:AddChild(emptyLabel)

        if CS.pendingTexturePickerOpen == CS.selectedGroup then
            CS.pendingTexturePickerOpen = nil
        end
        return
    end

    local selectionLabel = GetStandaloneTextureSelectionLabel(group, settings)

    if not selectionLabel then
        if not isTriggerPanel then
            local emptyStateLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(emptyStateLabel)
            emptyStateLabel:SetFullWidth(true)
            emptyStateLabel:SetText("|cff888888Choose a texture in Live Preview to configure its appearance.|r")
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

        RefreshTexturePreview()
        return
    end

    local _, shapeCollapsed = BuildCollapsibleSection(container,
        "Shape & Arrangement", "appearance_textureShape", nil, nil, ROW_SECTION)
    if not shapeCollapsed then
    -- Geometry keeps the same staged values and commit boundaries as before.
    local textureLeft, textureRight = BeginRowGrid(container)

    local locationOptions, locationOrder = CooldownCompanion:GetTexturePanelLocationOptions()
    local selectedLayoutValue = CooldownCompanion:GetTexturePanelLayoutSelectionValue(settings.locationType or 0)
    AddDropdownRow(textureLeft, {
        label = "Arrangement",
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
        local spacingRow = AddSliderRow(textureLeft, {
            label = "Pair Spacing",
            setting = SPECIAL_FINDER.texture.spacing,
            indent = true,
            min = MIN_TEXTURE_PAIR_SPACING, max = MAX_TEXTURE_PAIR_SPACING, step = 0.01,
            value = settings.pairSpacing or 0,
        })
        AttachTextureValueSlider(spacingRow, "pairSpacing")
    end

    local scaleRow = AddSliderRow(textureLeft, {
        label = "Scale",
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
        label = "Horizontal Stretch",
        tooltip = { "Horizontal Stretch", { "Stretch or compress the texture horizontally. Zero keeps its original proportions.", 1, 1, 1, true } },
        setting = SPECIAL_FINDER.texture.stretchX,
        min = MIN_TEXTURE_STRETCH, max = MAX_TEXTURE_STRETCH, step = 0.05,
        value = settings.stretchX or 0,
    })
    AttachTextureValueSlider(stretchXRow, "stretchX")

    local stretchYRow = AddSliderRow(textureRight, {
        label = "Vertical Stretch",
        tooltip = { "Vertical Stretch", { "Stretch or compress the texture vertically. Zero keeps its original proportions.", 1, 1, 1, true } },
        setting = SPECIAL_FINDER.texture.stretchY,
        min = MIN_TEXTURE_STRETCH, max = MAX_TEXTURE_STRETCH, step = 0.05,
        value = settings.stretchY or 0,
    })
    AttachTextureValueSlider(stretchYRow, "stretchY")

    end -- not shapeCollapsed

    local _, colorCollapsed = BuildCollapsibleSection(container,
        "Color & Blending", "appearance_textureColor", nil, nil, ROW_SECTION)
    if not colorCollapsed then
    local textureLeft, textureRight = BeginRowGrid(container)

    AddDropdownRow(textureRight, {
        label = "Blend Mode",
        tooltip = { "Blend Mode", { "Choose how the texture blends with the scene behind it. Normal / Original preserves its original appearance.", 1, 1, 1, true } },
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

    local alphaRow = AddSliderRow(textureLeft, {
        label = "Opacity",
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

    -- Preview through the staging table; only ConfirmTextureColor copies
    -- the committed color across to the saved settings.
    local colorRow = AddColorRow(textureLeft, {
        label = "Color",
        setting = SPECIAL_FINDER.texture.color,
        tbl = previewSettings,
        key = "color",
        default = { 1, 1, 1, 1 },
        hasAlpha = true,
        onConfirm = ConfirmTextureColor,
        onPreview = textureValueChanged,
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
    end -- not colorCollapsed

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
    return context and context.group and ST.IsIndicatorGroup(context.group)
end

local function SpecialFinderTriggerDisplayType(context)
    local settings = context and context.group and context.group.indicatorSettings
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
    return context and context.group and ST.Indicator.IsAura(context.group)
end

local function SpecialFinderTriggerIconSettings(context)
    local trigger = context and context.group and context.group.indicatorSettings
    return trigger and trigger.icon or nil
end

local function SpecialFinderTextureIndicators(context)
    return context and context.group and CooldownCompanion:GetTexturePanelIndicatorSettings(context.group)
end

local function SpecialFinderTextureAuraControlled(context)
    local group = context and context.group
    local buttonData = group and group.buttons and group.buttons[1]
    return SpecialFinderTexture(context)
        and CooldownCompanion:IsTexturePanelAuraDisplayEnabled(group, buttonData)
end


local function SpecialFinderTextureSettings(context)
    local settings = context and ST.Indicator.Settings(context.group)
    return settings and settings.signal
end

local function SpecialFinderTextureAppearance(context)
    local group = context and context.group
    local rightMode = SpecialFinderTriggerType("texture")(context)
    if not rightMode then
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
    if not SpecialFinderTrigger(context) or ST.Indicator.IsAura(context.group) then return false end
    return effectKey ~= "shrinkExpand" or SpecialFinderTriggerDisplayType(context) ~= "text"
end

local function SpecialFinderTextureEffectShown(context)
    return SpecialFinderTextureAuraControlled(context)
end

local function SpecialFinderTextureEffectEnabled(context, sectionKey)
    if not SpecialFinderTextureEffectShown(context, sectionKey) then return false end
    local indicators = SpecialFinderTextureIndicators(context)
    return indicators and indicators[sectionKey] and indicators[sectionKey].enabled == true
end

local function SpecialFinderTextureEffectType(context, sectionKey, effectType)
    if not TextureEffectOffered(context and context.group, effectType) then return false end
    if not SpecialFinderTextureEffectEnabled(context, sectionKey) then return false end
    local indicators = SpecialFinderTextureIndicators(context)
    return indicators and indicators[sectionKey]
        and indicators[sectionKey].effectType == effectType
end

if ST._DefineSettingRoute then
    SPECIAL_FINDER.trigger.icon = ST._DefineSettingRoute({
        idPrefix = "panel.trigger.appearance.icon",
        scope = SPECIAL_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "triggerIcon",
        sectionLabel = "Icon",
        collapseKeys = { "appearance_triggerIcon" },
        rowScope = "primary",
        applies = SpecialFinderTriggerType("icon"),
    }):Settings({
        square = { label = "Square Icon", aliases = { "Square Icons" } },
        size = { label = "Icon Size", aliases = { "Button Size" }, applies = SpecialFinderTriggerIconSquare },
        width = { label = "Icon Width", applies = SpecialFinderTriggerIconFreeform },
        height = { label = "Icon Height", applies = SpecialFinderTriggerIconFreeform },
        zoom = { label = "Icon Zoom" },
        baseColor = { label = "Icon Color", aliases = { "Base Icon Color" } },
        background = { label = "Background Color" },
        borderThickness = { label = "Border Thickness" },
        borderSize = { advancedKey = "triggerIconBorder", label = "Border Size", applies = SpecialFinderTriggerIconCustomBorder },
        borderColor = { label = "Border Color" },
    })

    for _, effectKey in ipairs(TEXTURE_INDICATOR_EFFECT_ORDER) do
        local key = effectKey
        local def = TRIGGER_PANEL_EFFECT_DEFS[key]
        local top = ST._DefineSettingRoute({
            idPrefix = "panel.trigger.effects." .. key,
            scope = SPECIAL_FINDER_SCOPE,
            tab = "effects",
            tabLabel = "Effects",
            section = "triggerEffects",
            sectionLabel = "Visual Effects",
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
            tabLabel = "Effects",
            section = "triggerEffects",
            sectionLabel = def.label .. " Effect",
            collapseKeys = { "effects_triggerEffects" },
            rowScope = "primary",
            advancedKey = "triggerEffect_" .. key,
            -- Structural only: the gear exists with the effect off too, opening
            -- its panel read-only behind the unlock strip.
            applies = function(context) return SpecialFinderTriggerEffectOffered(context, key) end,
        })
        finder.duration = advanced:Setting({ key = "duration", label = def.speedLabel })
        finder.activation = advanced:Setting({key="activation",label="Animate When"})
        finder.combatOnly = advanced:Setting({key="combatOnly",label="Only In Combat"})
        if key == "colorShift" then
            finder.shiftColor = advanced:Setting({ key = "color", label = "Shift Color" })
        end
        SPECIAL_FINDER.triggerEffects[key] = finder
    end

    for _, sectionKey in ipairs({ "aura" }) do
        local key = sectionKey
        local sectionDef = TEXTURE_INDICATOR_SECTION_DEFS[key]
        local top = ST._DefineSettingRoute({
            idPrefix = "panel.texture.effects." .. key,
            scope = SPECIAL_FINDER_SCOPE,
            tab = "effects",
            tabLabel = "Effects",
            section = "textureIndicators",
            sectionLabel = "Visual Effects",
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
            tabLabel = "Effects",
            section = "textureIndicators",
            sectionLabel = sectionDef.label:gsub("^Show ", ""),
            collapseKeys = { EFFECTS_TEXTURE_INDICATORS_SECTION },
            rowScope = "primary",
            applies = function(context) return SpecialFinderTextureEffectEnabled(context, key) end,
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

    -- Stable IDs keep saved finder destinations valid; each control now reveals
    -- its own section, and paired spacing no longer opens a separate editor.
    local textureShape = ST._DefineSettingRoute({
        idPrefix = "panel.texture.appearance",
        scope = SPECIAL_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "textureShape",
        sectionLabel = "Shape & Arrangement",
        collapseKeys = { "appearance_textureShape" },
        rowScope = "primary",
        applies = SpecialFinderTextureAppearance,
    })
    SPECIAL_FINDER.texture = textureShape:Settings({
        layout = { label = "Arrangement", aliases = { "Texture Layout" } },
        spacing = { label = "Pair Spacing", applies = SpecialFinderTexturePair },
        scale = { label = "Scale", aliases = { "Texture Scale" } },
        rotation = { label = "Rotation" },
        stretchX = { label = "Horizontal Stretch", aliases = { "Horizontal Stretch / Compress" } },
        stretchY = { label = "Vertical Stretch", aliases = { "Vertical Stretch / Compress" } },
    })
    local textureColor = ST._DefineSettingRoute({
        idPrefix = "panel.texture.appearance",
        scope = SPECIAL_FINDER_SCOPE,
        tab = "appearance",
        tabLabel = "Appearance",
        section = "textureColor",
        sectionLabel = "Color & Blending",
        collapseKeys = { "appearance_textureColor" },
        rowScope = "primary",
        applies = SpecialFinderTextureAppearance,
    }):Settings({
        look = { label = "Blend Mode", aliases = { "Texture Look" } },
        alpha = { label = "Opacity", aliases = { "Texture Alpha" } },
        color = { label = "Color", aliases = { "Texture Color" } },
    })
    for key, descriptor in pairs(textureColor) do
        SPECIAL_FINDER.texture[key] = descriptor
    end
end

ST._BuildTriggerIconAppearanceTab = BuildTriggerIconAppearanceTab
ST._BuildTriggerEffectsTab = BuildTriggerEffectsTab
ST._BuildTextureEffectsTab = BuildTextureEffectsTab
ST._BuildTexturePanelAppearanceTab = BuildTexturePanelAppearanceTab
ST._GetStandaloneTextureSettings = GetStandaloneTextureSettings
ST._OpenOrRebindStandaloneTexturePicker = OpenOrRebindStandaloneTexturePicker
ST._EFFECTS_TEXTURE_INDICATORS_SECTION = EFFECTS_TEXTURE_INDICATORS_SECTION
