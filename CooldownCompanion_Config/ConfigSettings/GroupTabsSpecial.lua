local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local math_abs = math.abs
local tonumber = tonumber

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
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
-- Captured in this file by BuildIndicatorTextureAppearance.
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
    pandemicEffects = {},
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

local MIN_TEXTURE_PAIR_SPACING = -5
local MAX_TEXTURE_PAIR_SPACING = 5
local MIN_TEXTURE_ROTATION = -180
local MAX_TEXTURE_ROTATION = 180
local MIN_TEXTURE_STRETCH = -0.75
local MAX_TEXTURE_STRETCH = 2
local INDICATOR_EFFECT_DEFS = {
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

local function GetIndicatorEffectStore(group)
    return CooldownCompanion:GetIndicatorEffectSettings(group, true)
end

-- The effect Text Only cannot run: Color Shift for native aura sources (the
-- renderer tints artwork only), Shrink / Expand for everything CC draws
-- (spell, item and While Missing).
local function TextOnlyUnavailableEffect(group)
    local I = ST.Indicator
    return (I.IsNativeAura(group) or I.IsNameplate(group)) and "colorShift" or "shrinkExpand"
end


local SCREEN_LOCATION = Enum and Enum.ScreenLocationType or {}
local PREVIEW_LOCATION_LEFTRIGHT = SCREEN_LOCATION.LeftRight or 9
local PREVIEW_LOCATION_TOPBOTTOM = SCREEN_LOCATION.TopBottom or 10

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

local function GetIndicatorTextureSelectionLabel(group, settings)
    if not settings or not settings.sourceType then
        return nil
    end
    return settings.label or tostring(settings.sourceValue)
end

-- Native aura kits restyle only through a rebind; a presence tracker's
-- cell follows the saved design size the same way.
local function NeedsAuraRestyle(group, buttonData)
    return CooldownCompanion:IsIndicatorAuraDisplayEnabled(group, buttonData)
        or ST.Indicator.UsesPresence(group)
end

local function RequestAuraIndicatorRestyle(group, groupId)
    local buttonData = group and group.buttons and group.buttons[1] or nil
    if NeedsAuraRestyle(group, buttonData) then
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

local function FlushAuraIndicatorRestyle()
    local groupId = pendingTextureAuraRestyleGroupId
    pendingTextureAuraRestyleGroupId = nil
    if not groupId then
        return
    end
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId] or nil
    RequestAuraIndicatorRestyle(group, groupId)
end

-- The rebind is profile-wide, so a second panel edited inside the window
-- overwriting the pending id costs nothing: either id flushes both.
local function ThrottleAuraIndicatorRestyle(group, groupId)
    local buttonData = group and group.buttons and group.buttons[1] or nil
    if not (groupId and NeedsAuraRestyle(group, buttonData)) then
        return
    end
    local alreadyArmed = pendingTextureAuraRestyleGroupId ~= nil
    pendingTextureAuraRestyleGroupId = groupId
    if not alreadyArmed then
        C_Timer.After(TEXTURE_AURA_RESTYLE_THROTTLE, FlushAuraIndicatorRestyle)
    end
end

local function GetIndicatorTextureCommitCallback(group, groupId)
    return function(selection)
        local liveSettings = CooldownCompanion:GetIndicatorTextureSettings(group)
        if not liveSettings then
            return
        end

        if selection then
            CooldownCompanion:ApplyIndicatorTextureEntry(liveSettings, selection)
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
        RequestAuraIndicatorRestyle(group, groupId)
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function OpenOrRebindIndicatorTexturePicker(group, settings, forceOpen)
    if not (group and CS.StartPickAuraTexture) then
        return
    end

    local buttonIndex = nil
    local groupId = CS.selectedGroup
    local pickerOpts = {
        groupId = groupId,
        buttonIndex = buttonIndex,
        initialSelection = settings and settings.sourceType and settings or nil,
        callback = GetIndicatorTextureCommitCallback(group, groupId),
    }

    if forceOpen or not (CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen()) then
        CS.StartPickAuraTexture(pickerOpts)
    elseif CS.RebindPickAuraTexture then
        CS.RebindPickAuraTexture(pickerOpts)
    end
end

-- Open the inline texture browser for an Indicator by id.
-- Used by the big-preview click-to-browse affordance, which only has the
-- panel id at click time. Resolves the group + its texture settings and forces
-- the browser open.
function ST._OpenIndicatorTexturePicker(groupId)
    local group = groupId and CooldownCompanion.db.profile.groups[groupId]
    if not group then
        return
    end
    local settings = CooldownCompanion:GetIndicatorTextureSettings(group)
    OpenOrRebindIndicatorTexturePicker(group, settings, true)
end

local function RefreshIndicatorDisplay(groupId)
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
local function RefreshIndicatorPreviewMirror(groupId)
    if ST._RefreshIndicatorDisplayVisual and ST._RefreshIndicatorDisplayVisual(groupId) then
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
local function BuildIndicatorIconAppearance(container, group)
    local settings = CooldownCompanion:GetIndicatorIconSettings(group, true)
    local groupId = CS.selectedGroup

    -- The icon renders in the Live Preview, which is also the picker: clicking
    -- it opens the icon picker and right-click clears. This tab holds only the
    -- settings rows, so a refresh repaints the runtime panel and that mirror.
    local function RefreshIconPreview()
        RefreshIndicatorDisplay(groupId)
        RefreshIndicatorPreviewMirror(groupId)
    end

    -- The same three sections as a panel's icons: Icon Settings, Border,
    -- then Icon Tint.
    local _, iconCollapsed = BuildCollapsibleSection(container, "Icon Settings",
        "appearance_triggerIcon", nil, nil, ROW_SECTION)

    if not iconCollapsed then
    local iconLeft = BeginRowGrid(container)

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
            RefreshIndicatorDisplay(groupId)
        end, function()
            RefreshIndicatorPreviewMirror(groupId)
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
            RefreshIndicatorDisplay(groupId)
        end, function()
            RefreshIndicatorPreviewMirror(groupId)
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
            RefreshIndicatorDisplay(groupId)
        end, function()
            RefreshIndicatorPreviewMirror(groupId)
        end, settings, "iconHeight")
    end

    ST._BuildIconZoomControls(iconLeft, settings, RefreshIconPreview, {
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.zoom,
        previewRefresh = function()
            RefreshIndicatorPreviewMirror(groupId)
        end,
    })
    end -- not iconCollapsed

    local _, borderCollapsed = BuildCollapsibleSection(container, "Border",
        "appearance_triggerIconBorder", nil, nil, ROW_SECTION)

    if not borderCollapsed then
    -- Drawn inline in the panel order: color, mode, then thickness.
    local borderLeft = BeginRowGrid(container)

    AddColorRow(borderLeft, {
        label = "Border Color",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.borderColor,
        tbl = settings, key = "borderColor",
        default = { 0, 0, 0, 1 }, hasAlpha = true,
        onConfirm = RefreshIconPreview,
    })

    local renderMode = AddBorderRenderModeDropdown(borderLeft, settings, "borderRenderMode", function()
        RefreshIconPreview()
        CooldownCompanion:RefreshConfigPanel()
    end, nil, {
        row = true,
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.borderThickness,
    })
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderRow = AddSliderRow(borderLeft, {
            label = "Border Thickness",
            setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.borderSize,
            min = 0, max = 5, step = 0.1,
            value = settings.borderSize or ST.DEFAULT_BORDER_SIZE,
            disabled = borderThicknessLocked and true or false,
        })
        WireMirrorFirstSlider(borderRow, function(value)
            if borderThicknessLocked then return end
            settings.borderSize = value
        end, function()
            if borderThicknessLocked then return end
            RefreshIndicatorDisplay(groupId)
        end, function()
            if borderThicknessLocked then return end
            RefreshIndicatorPreviewMirror(groupId)
        end, settings, "borderSize")
    end
    end -- not borderCollapsed

    local _, tintCollapsed = BuildCollapsibleSection(container, "Icon Tint",
        "appearance_triggerIconTint", nil, nil, ROW_SECTION)

    if not tintCollapsed then
    local tintLeft = BeginRowGrid(container)

    AddColorRow(tintLeft, {
        label = "Base Icon Color",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.baseColor,
        tbl = settings, key = "iconTintColor",
        default = { 1, 1, 1, 1 }, hasAlpha = true,
        onConfirm = RefreshIconPreview,
    })

    AddColorRow(tintLeft, {
        label = "Background Color",
        setting = SPECIAL_FINDER.trigger.icon and SPECIAL_FINDER.trigger.icon.background,
        tbl = settings, key = "backgroundColor",
        default = { 0, 0, 0, 0.5 }, hasAlpha = true,
        onConfirm = RefreshIconPreview,
    })
    end -- not tintCollapsed

    RefreshIndicatorPreviewMirror(groupId)
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
        ThrottleAuraIndicatorRestyle(group, CS.selectedGroup)
    end
end

-- Row grammar (RowWidgets.lua): a CDC-SliderRow. The row's own value box
-- already accepts one decimal place, which is the whole job the pre-redesign
-- editbox hook it replaced did. The effect gears draw it unindented.
local function BuildTextureIndicatorSpeedSlider(container, config, label, onChange, setting)
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

-- Row grammar (RowWidgets.lua): one CDC-CheckBoxRow per effect, its advanced
-- gear chained off the label. Called exactly once per effect from the
-- Indicator Effects tab below, so it was converted outright rather than
-- growing an opts.row mode. `container` is the grid column the row belongs to.
--
-- Native aura sources draw the same rows without Animate When and Only In
-- Combat: their effects always run while Blizzard shows the aura, since
-- nothing in the aura slot may start or stop once bound, and their edits
-- reach the native kit only through an aura restyle. While Missing keeps Only
-- In Combat (CC draws it) but never Animate When, which the store drops on
-- read (Indicator.NormalizeEffectsForFamily).
-- `opts` (nameplate refresh-window rows): `finder`, the rows' finder table,
-- and `advPrefix`, their own gear keys.
local function BuildIndicatorEffectSection(container, group, effects, effectKey, opts)
    local config = effects and effects[effectKey]
    local def = INDICATOR_EFFECT_DEFS[effectKey]
    local finder = opts and opts.finder or SPECIAL_FINDER.triggerEffects[effectKey]
    if not config or not def then
        return
    end
    local auraSource = ST.Indicator.IsNativeAura(group)
    -- Nameplate reminders: each look has its own effects, with no Animate
    -- When or Only In Combat; their watchers restyle at the aura rebind.
    local nameplate = ST.Indicator.IsNameplate(group)
    -- While Missing and aura lists are drawn by CC: they keep Only In Combat, but Animate When
    -- would follow the aura entry's own spell state, so the row is hidden.
    local missingSource = ST.Indicator.UsesPresence(group)
    -- An aura effect runs as Always outside combat too. Enabling one clears
    -- any rule it kept from a condition source, which it could not run and
    -- would otherwise refuse to copy with no visible control to fix it.
    local function SetEnabled(value)
        config.enabled = value == true
        if auraSource and config.enabled then
            config.activation, config.combatOnly = nil, nil
        end
    end
    local function RefreshRuntime()
        if auraSource or nameplate then
            RefreshTextureIndicatorRuntime(group, true)
        else
            CooldownCompanion:RefreshAllAuraTextureVisuals()
        end
    end

    local enableCb = AddCheckboxRow(container, {
        label = def.label,
        setting = finder and finder.enabled,
        value = config.enabled,
        onChange = function(value)
            SetEnabled(value)
            RefreshRuntime()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- both rows go straight onto the panel scroll.
    local function BuildIndicatorEffectAdvanced(panel)
        if not auraSource and not nameplate then
        if not missingSource then
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
        end -- not missingSource
        AddCheckboxRow(panel, {label="Only In Combat", setting=finder and finder.combatOnly, value=config.combatOnly == true,
            onChange=function(value)
                config.combatOnly=value
                CooldownCompanion:RefreshAllAuraTextureVisuals()
            end})
        end -- not auraSource
        if effectKey == "colorShift" then
            AddColorRow(panel, {
                label = "Shift Color",
                setting = finder and finder.shiftColor,
                tbl = config,
                key = "color",
                default = { 1, 1, 1, 1 },
                hasAlpha = true,
                onConfirm = RefreshRuntime,
                onPreview = function()
                    local refreshedMirror = ST._RefreshTextureIndicatorMirrorEffect
                        and ST._RefreshTextureIndicatorMirrorEffect(CS.selectedGroup)
                    if not refreshedMirror then
                        ST._RefreshSelectedButtonsPreview()
                    end
                end,
            })
        end

        BuildTextureIndicatorSpeedSlider(panel, config, def.speedLabel, RefreshRuntime,
            finder and finder.duration)

    end

    local advKey = (opts and opts.advPrefix or "triggerEffect_") .. effectKey
    AddAdvancedToggle(enableCb, advKey, tabInfoButtons, true, {
        title = def.label .. " Advanced",
        build = BuildIndicatorEffectAdvanced,
        -- Non-lens lazy spec (ST._ResolveAdvancedUnlock): write-true plus
        -- the trigger effects' restyle-then-rebuild refresh sequence. Aura
        -- sources also restyle the native kit, so they run the row's own path.
        unlock = not config.enabled and ((auraSource or nameplate) and {
            enable = { label = "Enable " .. def.label, run = function()
                SetEnabled(true)
                RefreshRuntime()
                CooldownCompanion:RefreshConfigPanel()
            end },
        } or {
            target = config,
            enable = { label = "Enable " .. def.label, key = "enabled" },
            refreshKind = "auraTextures",
        }) or nil,
    })
end

local function GetIndicatorEffectOrderForDisplayType(group)
    local displayType = CooldownCompanion:GetIndicatorDisplayType(group, true)
    -- Nameplate reminders never offer Shrink / Expand (a per-frame script).
    local nameplate = ST.Indicator.IsNameplate(group)
    if displayType ~= "text" and not nameplate then
        return ST.Indicator.EffectOrder
    end

    local unavailable = displayType == "text" and TextOnlyUnavailableEffect(group) or nil
    local order = {}
    for _, effectKey in ipairs(ST.Indicator.EffectOrder) do
        if effectKey ~= unavailable and not (nameplate and effectKey == "shrinkExpand") then
            order[#order + 1] = effectKey
        end
    end
    return order
end

local function BuildIndicatorEffectsTab(container, group)
    local effects = GetIndicatorEffectStore(group)
    if not effects then
        return
    end

    local anyEnabled = false
    local effectOrder = GetIndicatorEffectOrderForDisplayType(group)
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
    -- A nameplate reminder's effects here are its missing look's; the
    -- refresh window's sit in the Pandemic Window section below.
    local _, effectsCollapsed = BuildCollapsibleSection(container,
        ST.Indicator.IsNameplate(group) and "While Missing" or "Visual Effects",
        "effects_triggerEffects", nil, nil, ROW_SECTION)

    if not effectsCollapsed then
        -- The offered set is FILTERED (Text Only drops one effect), so
        -- the rows fill the left column first: ceil(n/2) left, the rest right.
        local effectLeft, effectRight = BeginRowGrid(container)
        local splitAt = math.ceil(#effectOrder / 2)
        for index, effectKey in ipairs(effectOrder) do
            BuildIndicatorEffectSection(index <= splitAt and effectLeft or effectRight, group, effects, effectKey)
        end
    end

    if not anyEnabled and CS.selectedGroup then
        ST._ConfigPreview.StopCommand("triggerEffects", CS.selectedGroup)
        ST._ConfigPreview.StopCommand("textureAura", CS.selectedGroup)
    end
end

-- Row grammar (RowWidgets.lua): shape and color sections of display rows. The
-- texture itself is shown and picked in the Live Preview above, so the tab
-- holds no preview canvas or picker buttons. Reached for Indicators whose
-- display type is "texture" (aura or conditions tracking).
--
-- The staging machinery below - the config-only settings copy, the
-- stage/refresh/cancel closures and AttachTextureValueSlider - moved verbatim.
-- It is owner-validated behaviour: runtime refreshes read the SAVED table, so a
-- Texture Indicator edits a copy until the interaction is confirmed, and the row
-- conversion only changes which widget holds the control.
local function BuildIndicatorTextureAppearance(container, group)
    local isConditionsIndicator = CooldownCompanion:IsConditionsIndicatorGroup(group)
    local settings = CooldownCompanion:GetIndicatorTextureSettings(group)
    if not settings then
        return
    end

    local groupId = CS.selectedGroup
    if CS.textureConfigPreviewStage and CS.textureConfigPreviewStage.groupId == groupId then
        CS.textureConfigPreviewStage = nil
    end

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
        if isConditionsIndicator then
            RefreshIndicatorPreviewMirror(groupId)
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
        if requestAuraRestyle and not isConditionsIndicator then
            RequestAuraIndicatorRestyle(group, groupId)
        end
    end

    local function RefreshTextureVisual(requestAuraRestyle)
        ClearTextureConfigPreviewStage()
        -- Both tracking kinds repaint the pinned mirror after the saved value
        -- has been committed. Conditions Indicators can reuse their
        -- display-only repaint; aura Indicators rebuild the mirror outright.
        if isConditionsIndicator then
            RefreshIndicatorPreviewMirror(groupId)
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

    local selectionLabel = GetIndicatorTextureSelectionLabel(group, settings)

    if not selectionLabel then
        if not isConditionsIndicator then
            local emptyStateLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(emptyStateLabel)
            emptyStateLabel:SetFullWidth(true)
            emptyStateLabel:SetText("|cff888888Choose a texture in Live Preview to configure its appearance.|r")
            container:AddChild(emptyStateLabel)
        end

        if CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
            OpenOrRebindIndicatorTexturePicker(group, settings, false)
        end

        RefreshTexturePreview()
        return
    end

    local _, shapeCollapsed = BuildCollapsibleSection(container,
        "Shape & Arrangement", "appearance_textureShape", nil, nil, ROW_SECTION)
    if not shapeCollapsed then
    -- Geometry keeps the same staged values and commit boundaries as before.
    local textureLeft, textureRight = BeginRowGrid(container)

    local locationOptions, locationOrder = CooldownCompanion:GetIndicatorTextureLayoutOptions()
    local selectedLayoutValue = CooldownCompanion:GetIndicatorTextureLayoutValue(settings.locationType or 0)
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

    if CS.IsAuraTexturePickerOpen and CS.IsAuraTexturePickerOpen() then
        OpenOrRebindIndicatorTexturePicker(group, settings, false)
    end

    RefreshTexturePreview()
end

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

local SPECIAL_FINDER_SCOPE = { "panel", "entry" }

local function SpecialFinderIndicator(context)
    return context and context.group and ST.IsIndicatorGroup(context.group)
end

local function SpecialFinderIndicatorDisplayType(context)
    local settings = context and context.group and context.group.indicatorSettings
    local displayType = settings and settings.displayType
    if displayType == "icon" or displayType == "text" then
        return displayType
    end
    return "texture"
end

local function SpecialFinderIndicatorType(displayType)
    return function(context)
        return SpecialFinderIndicator(context)
            and SpecialFinderIndicatorDisplayType(context) == displayType
    end
end

local function SpecialFinderIndicatorIconSettings(context)
    local trigger = context and context.group and context.group.indicatorSettings
    return trigger and trigger.icon or nil
end


local function SpecialFinderTextureSettings(context)
    local settings = context and ST.Indicator.Settings(context.group)
    return settings and settings.signal
end

local function SpecialFinderTextureAppearance(context)
    local group = context and context.group
    local rightMode = SpecialFinderIndicatorType("texture")(context)
    if not rightMode then
        return false
    end
    local settings = SpecialFinderTextureSettings(context)
    return settings and settings.sourceType ~= nil and settings.sourceValue ~= nil
end

local function SpecialFinderTexturePair(context)
    if not SpecialFinderTextureAppearance(context) then return false end
    local settings = SpecialFinderTextureSettings(context)
    local layout = CooldownCompanion:GetIndicatorTextureLayoutValue(settings.locationType or 0)
    return layout == PREVIEW_LOCATION_LEFTRIGHT or layout == PREVIEW_LOCATION_TOPBOTTOM
end

local function SpecialFinderIndicatorIconSquare(context)
    if not SpecialFinderIndicatorType("icon")(context) then return false end
    local settings = SpecialFinderIndicatorIconSettings(context)
    return not settings or settings.maintainAspectRatio ~= false
end

local function SpecialFinderIndicatorIconFreeform(context)
    if not SpecialFinderIndicatorType("icon")(context) then return false end
    local settings = SpecialFinderIndicatorIconSettings(context)
    return settings and settings.maintainAspectRatio == false
end

local function SpecialFinderIndicatorIconCustomBorder(context)
    if not SpecialFinderIndicatorType("icon")(context) then return false end
    local settings = SpecialFinderIndicatorIconSettings(context) or {}
    return ST.GetDrawnBorderRenderMode(settings) ~= ST.BORDER_RENDER_MODE_CRISP
end

local function SpecialFinderIndicatorEffectOffered(context, effectKey)
    if not SpecialFinderIndicator(context) then return false end
    -- Nameplate reminders: Pulse, Bounce and Color Shift (owner ruling 2026-10-04).
    if ST.Indicator.IsNameplate(context.group) and effectKey == "shrinkExpand" then return false end
    return effectKey ~= TextOnlyUnavailableEffect(context.group) or SpecialFinderIndicatorDisplayType(context) ~= "text"
end

-- Only In Combat: everything CC draws (not native auras). Animate When also
-- leaves While Missing, which has no spell state of its own to follow.
local function SpecialFinderConditionEffect(context)
    return not ST.Indicator.IsNativeAura(context.group) and not ST.Indicator.IsNameplate(context.group)
end
local function SpecialFinderActivationEffect(context)
    return ST.Indicator.EffectFamily(context.group) == "conditions"
end
-- A nameplate reminder's refresh-window effect rows (Pandemic Window).
local function SpecialFinderPandemicLookEffect(context, effectKey)
    local group = context.group
    return ST.IsIndicatorGroup(group) and ST.Indicator.Primary(group) ~= nil
        and ST.Indicator.IsNameplate(group) and ST.Indicator.ShowsLiveDisplay(group)
        and effectKey ~= "shrinkExpand"
        and not (effectKey == "colorShift" and SpecialFinderIndicatorDisplayType(context) == "text")
end

if ST._DefineSettingRoute then
    -- One stable id prefix; each row reveals the section it now sits in.
    local function IconRoute(section, sectionLabel, collapseKey)
        return ST._DefineSettingRoute({
            idPrefix = "panel.trigger.appearance.icon",
            scope = SPECIAL_FINDER_SCOPE,
            tab = "appearance",
            tabLabel = "Appearance",
            section = section,
            sectionLabel = sectionLabel,
            collapseKeys = { collapseKey },
            rowScope = "primary",
            applies = SpecialFinderIndicatorType("icon"),
        })
    end
    SPECIAL_FINDER.trigger.icon = IconRoute("triggerIcon", "Icon Settings", "appearance_triggerIcon"):Settings({
        square = { label = "Square Icon", aliases = { "Square Icons" } },
        size = { label = "Icon Size", aliases = { "Button Size" }, applies = SpecialFinderIndicatorIconSquare },
        width = { label = "Icon Width", applies = SpecialFinderIndicatorIconFreeform },
        height = { label = "Icon Height", applies = SpecialFinderIndicatorIconFreeform },
        zoom = { label = "Icon Zoom" },
    })
    local iconBorder = IconRoute("triggerIconBorder", "Border", "appearance_triggerIconBorder"):Settings({
        borderColor = { label = "Border Color" },
        borderThickness = { label = "Border Thickness Mode" },
        borderSize = { label = "Border Thickness", aliases = { "border size" }, applies = SpecialFinderIndicatorIconCustomBorder },
    })
    local iconTint = IconRoute("triggerIconTint", "Icon Tint", "appearance_triggerIconTint"):Settings({
        baseColor = { label = "Base Icon Color", aliases = { "Icon Color" } },
        background = { label = "Background Color" },
    })
    for key, descriptor in pairs(iconBorder) do SPECIAL_FINDER.trigger.icon[key] = descriptor end
    for key, descriptor in pairs(iconTint) do SPECIAL_FINDER.trigger.icon[key] = descriptor end

    for _, effectKey in ipairs(ST.Indicator.EffectOrder) do
        local key = effectKey
        local def = INDICATOR_EFFECT_DEFS[key]
        local top = ST._DefineSettingRoute({
            idPrefix = "panel.trigger.effects." .. key,
            scope = SPECIAL_FINDER_SCOPE,
            tab = "effects",
            tabLabel = "Effects",
            section = "triggerEffects",
            sectionLabel = "Visual Effects",
            collapseKeys = { "effects_triggerEffects" },
            rowScope = "primary",
            applies = function(context) return SpecialFinderIndicatorEffectOffered(context, key) end,
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
            applies = function(context) return SpecialFinderIndicatorEffectOffered(context, key) end,
        })
        finder.duration = advanced:Setting({ key = "duration", label = def.speedLabel })
        finder.activation = advanced:Setting({key="activation",label="Animate When",applies=SpecialFinderActivationEffect})
        finder.combatOnly = advanced:Setting({key="combatOnly",label="Only In Combat",applies=SpecialFinderConditionEffect})
        if key == "colorShift" then
            finder.shiftColor = advanced:Setting({ key = "color", label = "Shift Color" })
        end
        SPECIAL_FINDER.triggerEffects[key] = finder

        -- The same effect in a nameplate reminder's Pandemic Window section.
        if key ~= "shrinkExpand" then
            local applies = function(context) return SpecialFinderPandemicLookEffect(context, key) end
            local pandemicTop = ST._DefineSettingRoute({
                idPrefix = "panel.indicator.pandemicEffects." .. key,
                scope = SPECIAL_FINDER_SCOPE,
                tab = "effects",
                tabLabel = "Effects",
                section = "pandemic",
                sectionLabel = "Pandemic Window",
                collapseKeys = { "indicator_pandemic" },
                rowScope = "primary",
                applies = applies,
            })
            local pandemicFinder = {
                enabled = pandemicTop:Setting({ key = "enabled", label = def.label }),
            }
            local pandemicAdvanced = ST._DefineSettingRoute({
                idPrefix = "panel.indicator.pandemicEffects." .. key .. ".advanced",
                scope = SPECIAL_FINDER_SCOPE,
                tab = "effects",
                tabLabel = "Effects",
                section = "pandemic",
                sectionLabel = def.label .. " Effect (Pandemic Window)",
                collapseKeys = { "indicator_pandemic" },
                rowScope = "primary",
                advancedKey = "pandemicEffect_" .. key,
                applies = applies,
            })
            pandemicFinder.duration = pandemicAdvanced:Setting({ key = "duration", label = def.speedLabel })
            if key == "colorShift" then
                pandemicFinder.shiftColor = pandemicAdvanced:Setting({ key = "color", label = "Shift Color" })
            end
            SPECIAL_FINDER.pandemicEffects[key] = pandemicFinder
        end
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

ST._BuildIndicatorIconAppearance = BuildIndicatorIconAppearance
ST._BuildIndicatorEffectsTab = BuildIndicatorEffectsTab

-- A nameplate reminder's refresh-window effects (IndicatorTabs' Pandemic
-- Window section): the same rows, on their own store and gear keys.
function ST._BuildNameplatePandemicEffects(column, group)
    local effects = ST.Indicator.PandemicLookEffectStore(group)
    if not effects then return end
    local text = CooldownCompanion:GetIndicatorDisplayType(group, true) == "text"
    for _, effectKey in ipairs(ST.Indicator.EffectOrder) do
        if effectKey ~= "shrinkExpand" and not (text and effectKey == "colorShift") then
            BuildIndicatorEffectSection(column, group, effects, effectKey, {
                finder = SPECIAL_FINDER.pandemicEffects[effectKey],
                advPrefix = "pandemicEffect_",
            })
        end
    end
end
ST._BuildIndicatorTextureAppearance = BuildIndicatorTextureAppearance
ST._OpenOrRebindIndicatorTexturePicker = OpenOrRebindIndicatorTexturePicker
