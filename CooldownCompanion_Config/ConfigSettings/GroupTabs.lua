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
local BuildCompactModeControls = ST._BuildCompactModeControls
local BuildGroupSettingPresetControls = ST._BuildGroupSettingPresetControls
local AddPandemicMarkerControls = ST._AddPandemicMarkerControls
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local BuildAlphaControls = ST._BuildAlphaControls
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown
local AddScopedLoadConditionToggles = ST._AddScopedLoadConditionToggles
local BuildWhereToHideTooltip = ST._BuildWhereToHideTooltip
local AddCharacterEligibilityControls = ST._AddCharacterEligibilityControls
local AddClassSpecEligibilityControls = ST._AddClassSpecEligibilityControls

-- Imports from SectionBuilders.lua
local BuildKeybindTextControls = ST._BuildKeybindTextControls
local BuildBorderControls = ST._BuildBorderControls
local BuildDesaturationControls = ST._BuildDesaturationControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls
local BuildShowOutOfRangeControls = ST._BuildShowOutOfRangeControls
local BuildAllowPingsControls = ST._BuildAllowPingsControls
local BuildShowGCDSwipeControls = ST._BuildShowGCDSwipeControls
local BuildCooldownSwipeControls = ST._BuildCooldownSwipeControls
local BuildAuraDurationSwipeControls = ST._BuildAuraDurationSwipeControls
local BuildAuraDurationSwipeAdvancedControls = ST._BuildAuraDurationSwipeAdvancedControls
local BuildIconFillTimerControls = ST._BuildIconFillTimerControls
local BuildIconFillTimerAdvancedControls = ST._BuildIconFillTimerAdvancedControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildAssistedHighlightControls = ST._BuildAssistedHighlightControls
local BuildProcGlowControls = ST._BuildProcGlowControls
local BuildAuraGlowControls = ST._BuildAuraGlowControls
local BuildPandemicGlowControls = ST._BuildPandemicGlowControls
local BuildReadyGlowControls = ST._BuildReadyGlowControls
local BuildKeyPressHighlightControls = ST._BuildKeyPressHighlightControls

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddColorRow = ST._AddColorRow
local AnchorRowBadge = ST._AnchorRowBadge
-- ST._BeginRowGrid is deliberately NOT hoisted here: BuildAppearanceTab already
-- sits on Lua 5.1's hard 60-upvalue ceiling, and one more file-scope local makes
-- GroupTabs.lua fail to compile ("more than 60 upvalues"). Builders that need it
-- take a function-local copy instead.

-- A dropdown sizes its menu from the 140px control it hangs under, which is
-- too narrow for user-named panels and the longer worded options below.
-- Safe as a file-scope local: BuildLayoutTab, BuildTexturePanelAppearanceTab
-- and the texture indicator section capture it, never BuildAppearanceTab (the
-- builder sitting on the 60-upvalue ceiling noted above).
local WIDE_PULLOUT_WIDTH = 300

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- Slider wiring for edits the pinned mirror can stand in for: while the
-- slider is dragged the candidate value exists only for the mirror render;
-- the saved value and live panel update once on release. The slider's edit box fires
-- OnMouseUp on Enter too, so typed values also apply live.
--
-- stateOwner/stateKeys name the exact raw fields applyValue touches. They are
-- snapshotted on every preview tick instead of restoring slider:GetValue(): a
-- slider can display a fallback for an absent field, and writing that fallback
-- back would silently materialize an override before the user commits.
local NIL_SETTING = {}
local function WireMirrorFirstSlider(slider, applyValue, commitFn, previewFn, stateOwner, stateKeys)
    if type(stateKeys) == "string" then
        stateKeys = { stateKeys }
    end
    local function CaptureState()
        local state = {}
        for index, key in ipairs(stateKeys) do
            local value = stateOwner[key]
            state[index] = value == nil and NIL_SETTING or value
        end
        return state
    end
    local function RestoreState(state)
        for index, key in ipairs(stateKeys) do
            local value = state[index]
            stateOwner[key] = value == NIL_SETTING and nil or value
        end
    end

    slider:SetCallback("OnValueChanged", function(_, _, value)
        local state = CaptureState()
        applyValue(value)
        if previewFn == false then
            -- Some sliders change screen-space placement, which the pinned
            -- mirror intentionally does not represent.
        elseif previewFn then
            previewFn()
        elseif ST._RefreshButtonsPreviewMirror then
            ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
        end
        RestoreState(state)
    end)
    slider:SetCallback("OnMouseUp", function(_, _, value)
        applyValue(value)
        if commitFn then
            commitFn()
        else
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end
    end)
end

-- Both primers take an optional entry: the transition state they re-arm is
-- per-BUTTON runtime state, so an edit made through the entry lens re-arms
-- only the entry it changed. nil primes the whole panel (a panel-scope edit
-- changed every entry's config).
local function PrimeReadyGlowCappedChargeTransitions(groupId, onlyButtonData)
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if not (frame and frame.buttons) then
        return
    end

    for _, button in ipairs(frame.buttons) do
        local buttonData = button.buttonData
        if buttonData
           and (onlyButtonData == nil or buttonData == onlyButtonData)
           and buttonData.type == "spell"
           and buttonData.hasCharges == true
           and not buttonData._hasDisplayCount then
            button._readyGlowMaxChargesSpellID = button._displaySpellId or buttonData.id
            button._readyGlowMaxChargesStartTime = nil
            button._readyGlowMaxChargesActive = false
        end
    end
end

local function PrimeReadyGlowNormalTransitions(groupId, onlyButtonData)
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if not (frame and frame.buttons) then
        return
    end

    local now = GetTime()
    for _, button in ipairs(frame.buttons) do
        local buttonData = button.buttonData
        if buttonData
           and (onlyButtonData == nil or buttonData == onlyButtonData)
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

-- Owner ruling (aura rebuild plan): group-level aura style sections are shown
-- only while the group actually has an aura-tracking entry. Shared helper
-- (Helpers.lua) so BarModeTabs can gate its aura section too.
local GroupHasAuraTrackingEntry = ST._GroupHasAuraTrackingEntry

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

-- Row grammar (RowWidgets.lua): one collapsible section. The icon itself is
-- shown and picked in the Live Preview above, so the tab is settings rows only.
local function BuildTriggerIconAppearanceTab(container, group)
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

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
        previewRefresh = function()
            RefreshTriggerPreviewMirror(groupId)
        end,
    })

    -- deferCommit is deliberately absent throughout, matching the
    -- stock color pickers these rows replace: the callbacks repaint the
    -- canvas, they do not re-read the bound table every tick.
    AddColorRow(iconLeft, {
        label = "Base Icon Color",
        tbl = settings, key = "iconTintColor",
        default = { 1, 1, 1, 1 }, hasAlpha = true,
        onConfirm = RefreshIconPreview, onChange = RefreshIconPreview,
    })

    AddColorRow(iconLeft, {
        label = "Background Color",
        tbl = settings, key = "backgroundColor",
        default = { 0, 0, 0, 0.5 }, hasAlpha = true,
        onConfirm = RefreshIconPreview, onChange = RefreshIconPreview,
    })

    local renderMode = AddBorderRenderModeDropdown(iconRight, settings, "borderRenderMode", function()
        RefreshIconPreview()
        CooldownCompanion:RefreshConfigPanel()
    end, nil, { row = true })
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderRow = AddSliderRow(iconRight, {
            label = "Border Size",
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
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

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
        previewRefresh = function()
            RefreshTriggerPreviewMirror(groupId)
        end,
    })

    -- The stock Dropdown had no order table and drew these three in whatever
    -- order pairs() produced; the row states the reading order outright.
    AddDropdownRow(textRight, {
        label = "Alignment",
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
        tbl = settings, key = "textFontColor",
        default = { 1, 1, 1, 1 }, hasAlpha = true,
        onConfirm = RefreshTextPreview, onChange = RefreshTextPreview,
    })

    AddColorRow(textRight, {
        label = "Background Color",
        tbl = settings, key = "textBgColor",
        default = { 0, 0, 0, 0 }, hasAlpha = true,
        onConfirm = RefreshTextPreview, onChange = RefreshTextPreview,
    })
    end -- not textCollapsed

    RefreshTriggerPreviewMirror(groupId)
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
    CooldownCompanion:ClearAllTextureIndicatorPreviews()
    if CooldownCompanion.ClearAllTriggerPanelEffectPreviews then
        CooldownCompanion:ClearAllTriggerPanelEffectPreviews()
    end

    -- Function-locals, not upvalues: see the note by the row-grammar imports
    -- at the top of this file. Declared here because BOTH halves of this tab
    -- use them and the texture/trigger half returns before the other starts.
    local BeginRowGrid = ST._BeginRowGrid
    local AddEditBoxRow = ST._AddEditBoxRow

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
            if CooldownCompanion.ClearCursorAnchorLayoutPreviewOffset then
                CooldownCompanion:ClearCursorAnchorLayoutPreviewOffset(textureGroupId)
            end
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

        -- ============================================================
        -- The row grammar (RowWidgets.lua). Same shapes as the panel half
        -- below - the rules are stated once in the recipe comment atop
        -- BuildAppearanceTab's icons path and this half conforms to them.
        --
        -- A texture/trigger panel anchors ONE texture rather than a panel of
        -- entries, so it has no Arrangement and no per-icon strata; the three
        -- sections it does share (Anchor, Position, Alpha) reuse the same
        -- collapse keys, because they are the same sections on the same tab.
        -- ============================================================
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

        -- ============================================================
        -- Anchor (what this texture hangs off)
        -- ============================================================
        local _, anchorCollapsed = BuildCollapsibleSection(container, "Anchor", "layout_anchor", nil, nil, ROW_SECTION)

        if not anchorCollapsed then
        -- LEFT column: the target itself. RIGHT column: the one setting that
        -- belongs to the choice of target rather than to this panel - where
        -- its alpha comes from.
        local anchorLeft, anchorRight = BeginRowGrid(container)

        AddDropdownRow(anchorLeft, {
            label = "Anchor Target",
            list = anchorTargetList,
            order = anchorTargetOrder,
            value = targetMode,
            onChange = function(val, widget)
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
            end,
        })

        if targetMode == "panel" then
            local panelAnchorRow = AddDropdownRow(anchorLeft, {
                label = "Anchor to Panel",
                pulloutWidth = WIDE_PULLOUT_WIDTH,
                onChange = function(val, widget)
                    if not val or val == "" then return end
                    local targetGroupId = tonumber(val)
                    if targetGroupId and SetStandalonePanelAnchorTarget(targetGroupId) then
                        CooldownCompanion:RefreshAllAuraTextureVisuals()
                        CooldownCompanion:RefreshConfigPanel()
                    else
                        widget:SetValue(currentAnchorGroupId and tostring(currentAnchorGroupId) or nil)
                    end
                end,
            })
            -- The populator writes the stock Dropdown's own `list` table
            -- directly (container headers plus indented panel entries), so it
            -- takes the embedded child rather than the row wrapper.
            CooldownCompanion:PopulatePanelAnchorTargetDropdown(panelAnchorRow.dropdown, textureGroupId)
            panelAnchorRow:SetValue(currentAnchorGroupId and tostring(currentAnchorGroupId) or nil)
        end

        if isPanel and (targetMode == "panel" or hasFrameAnchorTarget) then
            AddDropdownRow(anchorRight, {
                label = "Panel Alpha",
                pulloutWidth = WIDE_PULLOUT_WIDTH,
                list = {
                    inherit = targetMode == "frame" and "Inherit Target Frame Alpha" or "Inherit Target Panel Alpha",
                    custom = "Custom Alpha",
                },
                order = { "inherit", "custom" },
                value = group.inheritPanelAlpha == false and "custom" or "inherit",
                onChange = function(val)
                    group.inheritPanelAlpha = val ~= "custom"
                    CooldownCompanion:RefreshAllAuraTextureVisuals()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end

        if targetMode == "frame" then
            -- A frame name needs the whole 140px control column to stay
            -- readable, so Pick does not share it: the editbox row takes a
            -- grid of its own and Pick sits at the head of that grid's right
            -- column.
            local frameLeft, frameRight = BeginRowGrid(container)

            local frameAnchorText = settings.relativeTo
            if frameAnchorText == "UIParent" or currentAnchorGroupId then frameAnchorText = "" end

            local anchorRow = AddEditBoxRow(frameLeft, {
                label = "Anchor to Frame",
                value = frameAnchorText,
                onEnterPressed = function(text, widget)
                    if SetStandaloneFrameAnchorTarget(text) then
                        CooldownCompanion:RefreshAllAuraTextureVisuals()
                        CooldownCompanion:RefreshConfigPanel()
                    else
                        widget:SetText(frameAnchorText)
                    end
                end,
            })
            if anchorRow.editbox.Instructions then anchorRow.editbox.Instructions:Hide() end

            -- Exactly one grammar row tall so the button's centre lands on the
            -- editbox's: Flow insets its single row by 3px and the button is
            -- 24 tall, so 3 + 24 + 3 fills the 30px band. noAutoHeight keeps
            -- Flow's own 27px report from shrinking it back.
            local pickRow = AceGUI:Create("SimpleGroup")
            pickRow:SetFullWidth(true)
            pickRow:SetLayout("Flow")
            pickRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
            pickRow.noAutoHeight = true

            local pickBtn = AceGUI:Create("Button")
            pickBtn:SetText("Pick")
            pickBtn:SetAutoWidth(true)
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
            pickRow:AddChild(pickBtn)

            CreateInfoButton(pickBtn.frame, pickBtn.frame, "LEFT", "RIGHT", 2, 0, {
                "Pick Frame",
                {"Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this panel to it, or right-click to cancel.", 1, 1, 1, true},
                " ",
                {"You can also type a frame name directly into the editbox.", 1, 1, 1, true},
            }, tabInfoButtons)

            -- Added last so the List-layout column measures a populated row.
            frameRight:AddChild(pickRow)
        end
        end -- not anchorCollapsed

        -- ============================================================
        -- Position (where the anchor point sits, and the offset from it)
        -- ============================================================
        -- Cursor anchoring pins the relative point; it is a stored setting,
        -- not a rendered control, so it is written whether or not the section
        -- below is expanded.
        if targetMode == "cursor" then
            group.anchor.relativePoint = "CENTER"
        end

        local _, positionCollapsed = BuildCollapsibleSection(container,
            targetMode == "cursor" and "Cursor Offset" or positionHeadingText,
            "layout_position", nil, nil, ROW_SECTION)

        if not positionCollapsed then
        -- LEFT column: the points that have to be read together (mine, then
        -- the target's). RIGHT column: the offset pair applied on top of them.
        -- Cursor mode has no relative point, so the left side ends early - and
        -- that is where its Reset goes, filling the shorter column's tail.
        local positionLeft, positionRight = BeginRowGrid(container)

        if targetMode == "cursor" then
            AddAnchorDropdown(positionLeft, group.anchor, "point", "BOTTOMLEFT",
                RefreshCursorAnchor, "Panel Point", { row = true })
            AddOffsetSliders(positionRight, group.anchor, "x", "y", {
                x = 16,
                y = 16,
                range = 2000,
                step = 1,
            }, RefreshCursorAnchor, {
                row = true,
                previewRefresh = function()
                    if CooldownCompanion.SetCursorAnchorLayoutPreviewOffset then
                        CooldownCompanion:SetCursorAnchorLayoutPreviewOffset(
                            textureGroupId,
                            group.anchor.x or 0,
                            group.anchor.y or 0
                        )
                    end
                end,
            })

            -- Destructive, and it replaces the whole anchor - the Panel Point
            -- above included - so it sits with what it clears.
            local resetBtn = AceGUI:Create("Button")
            resetBtn:SetText("Reset Cursor Offset")
            resetBtn:SetAutoWidth(true)
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
            positionLeft:AddChild(resetBtn)
        else
            AddAnchorDropdown(positionLeft, settings, "point", "CENTER",
                RefreshTextureVisual, anchorLabel, { row = true })
            AddAnchorDropdown(positionLeft, settings, "relativePoint", "CENTER",
                RefreshTextureVisual,
                (targetMode == "panel" or targetMode == "frame") and "Target Point" or "Screen Point",
                { row = true })
            AddOffsetSliders(positionRight, settings, "x", "y", {
                x = 0,
                y = 0,
                range = 2000,
                step = 1,
            }, RefreshTextureVisual, { row = true })

            -- Both columns are two rows here, so the Reset goes with the
            -- offsets it zeroes rather than with the points.
            local resetBtn = AceGUI:Create("Button")
            resetBtn:SetText("Reset Position")
            resetBtn:SetAutoWidth(true)
            resetBtn:SetCallback("OnClick", function()
                if (targetMode == "panel" or targetMode == "frame") and settings.relativeTo ~= "UIParent" then
                    ResetStandalonePosition(settings.relativeTo, "TOPLEFT", "BOTTOMLEFT", 0, -5)
                else
                    ResetStandalonePosition()
                end
                CooldownCompanion:RefreshAllAuraTextureVisuals()
                CooldownCompanion:RefreshConfigPanel()
            end)
            positionRight:AddChild(resetBtn)
        end
        end -- not positionCollapsed

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
    -- ================================================================
    -- The row grammar (RowWidgets.lua). The rules every row-grammar section
    -- follows are stated once, in the recipe comment at the top of
    -- BuildAppearanceTab's icons path; this tab conforms to them rather than
    -- restating them.
    --
    -- Every mode that reaches here shares this one layout: anchoring,
    -- position and frame strata are panel facts, not display-mode
    -- facts. (Alpha is a panel fact too, but it reads as visibility
    -- behavior, so it lives on the Visibility tab.)
    -- Only the Arrangement section and the icons-only strata block
    -- below vary, and each of those names its own mode gate. (Texture and
    -- trigger panels returned far above - they anchor a single texture rather
    -- than a panel of entries.)
    -- ================================================================
    -- nil displayMode means icons everywhere in the core, so it resolves to
    -- icons here too - the same fallback BuildAppearanceTab's dispatch makes.
    local displayMode = group.displayMode or "icons"
    local isIconsMode = displayMode == "icons"
    local isBarMode = displayMode == "bars"
    local isTextMode = displayMode == "text"

    local iconAnchorTargetList = isPanel
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
    local iconAnchorTargetOrder = isPanel
        and { "group", "panel", "frame", "cursor" }
        or { "group", "frame" }

    -- ============================================================
    -- Anchor (what this panel hangs off)
    -- ============================================================
    local _, anchorCollapsed = BuildCollapsibleSection(container, "Anchor", "layout_anchor", nil, nil, ROW_SECTION)

    if not anchorCollapsed then
    -- LEFT column: the target itself. RIGHT column: the one setting that
    -- belongs to the choice of target rather than to this panel - where
    -- its alpha comes from.
    local anchorLeft, anchorRight = BeginRowGrid(container)

    AddDropdownRow(anchorLeft, {
        label = "Anchor Target",
        list = iconAnchorTargetList,
        order = iconAnchorTargetOrder,
        value = targetMode,
        onChange = function(val, widget)
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
        end,
    })

    if isPanel and targetMode == "panel" then
        local panelAnchorRow = AddDropdownRow(anchorLeft, {
            label = "Anchor to Panel",
            onChange = function(val, widget)
                if not val or val == "" then return end
                local targetGroupId = tonumber(val)
                if not targetGroupId then return end
                local targetFrameName = "CooldownCompanionGroup" .. targetGroupId
                if CooldownCompanion:SetGroupAnchor(CS.selectedGroup, targetFrameName) then
                    CooldownCompanion:RefreshConfigPanel()
                else
                    widget:SetValue(nil)
                end
            end,
        })
        -- The populator writes the stock Dropdown's own `list` table
        -- directly (container headers plus indented panel entries), so it
        -- takes the embedded child rather than the row wrapper.
        CooldownCompanion:PopulatePanelAnchorTargetDropdown(panelAnchorRow.dropdown, CS.selectedGroup)
        if currentAnchorGroupId then
            panelAnchorRow:SetValue(tostring(currentAnchorGroupId))
        else
            panelAnchorRow:SetValue(nil)
        end
    end

    if isPanel and (targetMode == "panel" or hasFrameAnchorTarget) then
        AddDropdownRow(anchorRight, {
            label = "Panel Alpha",
            list = {
                inherit = targetMode == "frame" and "Inherit Target Frame Alpha" or "Inherit Target Panel Alpha",
                custom = "Custom Alpha",
            },
            order = { "inherit", "custom" },
            value = group.inheritPanelAlpha == false and "custom" or "inherit",
            onChange = function(val)
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
            end,
        })
    end

    if targetMode == "frame" then
        -- A frame name needs the whole 140px control column to stay
        -- readable, so Pick does not share it: the editbox row takes a
        -- grid of its own and Pick sits at the head of that grid's right
        -- column. The gutter between columns is 16px, so the button lands
        -- immediately right of the editbox, and both are on line one of
        -- their own grid, so nothing above them can knock them apart.
        local frameLeft, frameRight = BeginRowGrid(container)

        local frameAnchorText = currentAnchor
        if frameAnchorText == "UIParent" or isCursorAnchor or currentAnchorGroupId then frameAnchorText = "" end
        if isPanel and frameAnchorText == panelContainerFrame then frameAnchorText = "" end

        local anchorRow = AddEditBoxRow(frameLeft, {
            label = "Anchor to Frame",
            value = frameAnchorText,
            onEnterPressed = function(text, widget)
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
            end,
        })
        if anchorRow.editbox.Instructions then anchorRow.editbox.Instructions:Hide() end

        -- Exactly one grammar row tall so the button's centre lands on the
        -- editbox's: Flow insets its single row by 3px and the button is
        -- 24 tall, so 3 + 24 + 3 fills the 30px band. noAutoHeight keeps
        -- Flow's own 27px report from shrinking it back.
        local pickRow = AceGUI:Create("SimpleGroup")
        pickRow:SetFullWidth(true)
        pickRow:SetLayout("Flow")
        pickRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
        pickRow.noAutoHeight = true

        local pickBtn = AceGUI:Create("Button")
        pickBtn:SetText("Pick")
        pickBtn:SetAutoWidth(true)
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
        pickRow:AddChild(pickBtn)

        -- (?) tooltip for anchor picking
        CreateInfoButton(pickBtn.frame, pickBtn.frame, "LEFT", "RIGHT", 2, 0, {
            "Pick Frame",
            {"Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this group to it, or right-click to cancel.", 1, 1, 1, true},
            " ",
            {"You can also type a frame name directly into the editbox.", 1, 1, 1, true},
        }, tabInfoButtons)

        -- Added last so the List-layout column measures a populated row.
        frameRight:AddChild(pickRow)
    end
    end -- not anchorCollapsed

    -- ============================================================
    -- Position (where the anchor point sits, and the offset from it)
    -- ============================================================
    -- Cursor anchoring pins the relative point; it is a stored setting,
    -- not a rendered control, so it is written whether or not the section
    -- below is expanded.
    if targetMode == "cursor" then
        group.anchor.relativePoint = "CENTER"
    end

    local function refreshGroupAnchor()
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end

    local _, positionCollapsed = BuildCollapsibleSection(container,
        targetMode == "cursor" and "Cursor Offset" or "Position",
        "layout_position", nil, nil, ROW_SECTION)

    if not positionCollapsed then
    -- LEFT column: the two points that have to be read together (mine,
    -- then the target's). RIGHT column: the offset pair applied on top of
    -- them. Cursor mode has no relative point, so the left side ends early.
    local positionLeft, positionRight = BeginRowGrid(container)

    AddAnchorDropdown(positionLeft, group.anchor, "point",
        targetMode == "cursor" and "BOTTOMLEFT" or "CENTER",
        refreshGroupAnchor,
        targetMode == "cursor" and "Panel Point" or "Anchor Point",
        { row = true })

    if targetMode ~= "cursor" then
        AddAnchorDropdown(positionLeft, group.anchor, "relativePoint", "CENTER",
            refreshGroupAnchor, "Relative Point", { row = true })
    end

    -- Screen position is not represented inside the pinned mirror. Store the
    -- drag value and re-anchor the live panel once on release.
    local xOffsetRow = AddSliderRow(positionRight, {
        label = "X Offset",
        min = -2000, max = 2000, step = 0.1,
        value = group.anchor.x or 0,
    })
    local function PreviewCursorOffset()
        if targetMode == "cursor" and CooldownCompanion.SetCursorAnchorLayoutPreviewOffset then
            CooldownCompanion:SetCursorAnchorLayoutPreviewOffset(
                CS.selectedGroup,
                group.anchor.x or 0,
                group.anchor.y or 0
            )
        end
    end
    local function CommitGroupOffset()
        if CooldownCompanion.ClearCursorAnchorLayoutPreviewOffset then
            CooldownCompanion:ClearCursorAnchorLayoutPreviewOffset(CS.selectedGroup)
        end
        refreshGroupAnchor()
    end

    WireMirrorFirstSlider(xOffsetRow, function(val)
        group.anchor.x = val
    end, CommitGroupOffset, targetMode == "cursor" and PreviewCursorOffset or false,
        group.anchor, "x")

    local yOffsetRow = AddSliderRow(positionRight, {
        label = "Y Offset",
        min = -2000, max = 2000, step = 0.1,
        value = group.anchor.y or 0,
    })
    WireMirrorFirstSlider(yOffsetRow, function(val)
        group.anchor.y = val
    end, CommitGroupOffset, targetMode == "cursor" and PreviewCursorOffset or false,
        group.anchor, "y")
    end -- not positionCollapsed

    -- ============================================================
    -- Arrangement (how the entries sit relative to each other)
    -- ============================================================
    local _, arrangementCollapsed = BuildCollapsibleSection(container, "Arrangement", "layout_arrangement", nil, nil, ROW_SECTION)

    if not arrangementCollapsed then
    -- Two settings have to be read together here whatever the mode: growth
    -- direction is relabelled by the orientation above it, so they always
    -- share a column and always sit adjacent.
    --
    -- LEFT column (most modes): that pair. RIGHT column: the wrap count and
    -- the one setting that is about other panels rather than this one.
    --
    -- Bar panels invert it. They own two rows nothing else has - which way a
    -- single bar's own fill runs - and a bar's left column is about the bar
    -- itself, so the fill pair takes the left and the arrangement pair moves
    -- across to join the wrap count. Either way both columns are populated,
    -- including the single-bar case where the orientation row is gated away.
    local arrangeLeft, arrangeRight = BeginRowGrid(container)
    local arrangeHost = isBarMode and arrangeRight or arrangeLeft

    -- Orientation is remembered per display mode (bar and text panels own
    -- their keys, unset = vertical), so a mode swap keeps every mode's
    -- layout. Same helper GetCompactGrowthDirectionLabels uses, because the
    -- Growth Direction labels below have to agree with it.
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)

    if isBarMode then
        -- Which way a bar's own fill runs is independent of how the bars are
        -- arranged, so these lead the section rather than hanging off it.
        AddCheckboxRow(arrangeLeft, {
            label = "Vertical Bar Fill",
            value = style.barFillVertical or false,
            onChange = function(val)
                style.barFillVertical = val or nil
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        AddCheckboxRow(arrangeLeft, {
            label = "Flip Fill/Drain Direction",
            value = style.barReverseFill or false,
            onChange = function(val)
                style.barReverseFill = val or nil
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end,
        })

        -- A bar panel's orientation is one question ("do the bars sit in a
        -- row?"), so it is a checkbox rather than the horizontal/vertical
        -- dropdown the other modes show. With a single bar there is nothing
        -- to lay out.
        if #group.buttons > 1 then
            AddCheckboxRow(arrangeHost, {
                label = "Horizontal Bar Layout",
                value = orientation == "horizontal",
                onChange = function(val)
                    style.barOrientation = val and "horizontal" or "vertical"
                    CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end
    else
        AddDropdownRow(arrangeHost, {
            label = "Orientation",
            -- Owner ruling 2026-08-08 (supersedes 2026-07-28): the display
            -- reads the same per-mode helper the core lays out with, and
            -- text panels now default vertical like bars. Each mode writes
            -- its own key so swapping modes keeps every mode's layout.
            list = { horizontal = "Horizontal", vertical = "Vertical" },
            value = orientation,
            onChange = function(val)
                if isTextMode then
                    style.textOrientation = val
                else
                    style.orientation = val
                end
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end

    if #group.buttons > 1 then
        local labels
        if orientation == "vertical" then
            labels = { TOPLEFT = "Down, Right", TOPRIGHT = "Down, Left", BOTTOMLEFT = "Up, Right", BOTTOMRIGHT = "Up, Left" }
        else
            labels = { TOPLEFT = "Right, Down", TOPRIGHT = "Left, Down", BOTTOMLEFT = "Right, Up", BOTTOMRIGHT = "Left, Up" }
        end

        AddDropdownRow(arrangeHost, {
            label = "Growth Direction",
            list = labels,
            order = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" },
            value = style.growthOrigin or "TOPLEFT",
            onChange = function(val)
                style.growthOrigin = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end

    -- Text mode calls its entries entries, and offers the wrap count only
    -- once there is something to wrap.
    if not isTextMode or #group.buttons > 1 then
        local numButtons = math.max(1, #group.buttons)
        local wrapRow = AddSliderRow(arrangeRight, {
            label = isTextMode and "Entries per Row/Column" or "Buttons Per Row/Column",
            min = 1, max = numButtons, step = 1,
            value = math.min(style.buttonsPerRow or 12, numButtons),
        })
        WireMirrorFirstSlider(wrapRow, function(val)
            style.buttonsPerRow = val
        end, function()
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end, nil, style, "buttonsPerRow")
    end

    -- Auto-Anchoring eligibility (icon-like modes only - others are never eligible)
    if CooldownCompanion:IsIconLikeDisplayMode(group.displayMode) then
        local anchorEligibleRow = AddCheckboxRow(arrangeRight, {
            label = "Include in Auto-Anchoring",
            value = group.anchorEligible ~= false,
            onChange = function(val)
                if val then
                    group.anchorEligible = nil
                else
                    group.anchorEligible = false
                end
                CooldownCompanion:EvaluateResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:EvaluateCastBar()
                CooldownCompanion:EvaluateFrameAnchoring()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Badge chained off the end of the label; the anchor args below
        -- are a placeholder - AnchorRowBadge re-points the button.
        AnchorRowBadge(anchorEligibleRow, CreateInfoButton(anchorEligibleRow.frame, anchorEligibleRow.frame, "LEFT", "LEFT", 0, 0, {
            "Include in Auto-Anchoring",
            {"Resource Bars, the Cast Bar, and Unit Frames attach to the first available panel automatically. Uncheck this to skip this panel so they attach to the next eligible one instead.", 1, 1, 1, true},
        }, tabInfoButtons))
    end
    end -- not arrangementCollapsed

    -- ============================================================
    -- Strata
    -- ============================================================
    local _, strataCollapsed = BuildCollapsibleSection(container, "Strata", "layout_strata", nil, nil, ROW_SECTION)

    if not strataCollapsed then
    -- Per-icon layer ordering exists on icon panels only; the other modes
    -- have no stack of icon layers to reorder.
    local customStrataEnabled = isIconsMode and type(style.strataOrder) == "table"

    -- LEFT column: the per-icon layer switch. RIGHT column: the whole
    -- panel's draw layer. One row each - the layer dropdowns below
    -- are a block of their own so the indent cannot read as belonging to
    -- Frame Strata. Without the layer switch the section is a single row, so
    -- Frame Strata moves left rather than leaving the left column empty.
    local strataLeft, strataRight = BeginRowGrid(container)
    local frameStrataHost = isIconsMode and strataRight or strataLeft

    if isIconsMode then
    local strataToggleRow = AddCheckboxRow(strataLeft, {
        label = "Custom Icon Strata",
        value = customStrataEnabled,
        onChange = function(val)
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
            local host = CS.groupSettingsActiveHost
            if host and host.tabGroup then
                -- Rebuild in place, not a tab choice: the helper keeps the
                -- remembered-tab bookkeeping from reading it as one.
                ST._SelectPanelSettingsTabProgrammatic(host.tabGroup, CS.selectedTab)
            end
        end,
    })

    AnchorRowBadge(strataToggleRow, CreateInfoButton(strataToggleRow.frame, strataToggleRow.frame, "LEFT", "LEFT", 0, 0, {
        "Custom Icon Strata",
        {"Sets the draw order of each icon's visual layers.", 1, 1, 1, true},
        " ",
        {"Layer 8 draws on top, Layer 1 on the bottom.", 1, 1, 1, true},
        " ",
        {"Aura Display moves the aura glow, pandemic glow, aura swipe and aura text together.", 1, 1, 1, true},
        " ",
        {"Put Cooldown Swipe above Aura Display to keep a spell's own cooldown visible while its aura runs.", 1, 1, 1, true},
        " ",
        {"Loss of Control and keybind text always draw on top.", 1, 1, 1, true},
    }, tabInfoButtons))
    end -- isIconsMode (custom strata toggle)

    local frameStrataRow = AddDropdownRow(frameStrataHost, {
        label = "Frame Strata",
        list = {
            BACKGROUND = "Background",
            LOW = "Low",
            MEDIUM = "Default",
            HIGH = "High",
            DIALOG = "Highest",
        },
        order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG" },
        value = group.frameStrata or "MEDIUM",
        onChange = function(val)
            group.frameStrata = (val ~= "MEDIUM") and val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end,
    })

    AnchorRowBadge(frameStrataRow, CreateInfoButton(frameStrataRow.frame, frameStrataRow.frame, "LEFT", "LEFT", 0, 0, {
        "Frame Strata",
        {"Sets the rendering layer for this group.", 1, 1, 1, true},
        " ",
        {"Higher strata groups fully overlap lower ones.", 1, 1, 1, true},
        " ",
        {"Only change this if you need one group to overlap another.", 1, 1, 1, true},
    }, tabInfoButtons))

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

        -- The layers are one ordered stack, so they get their own grid and
        -- fill it top-down: the top half of the stack in the left column,
        -- the bottom half in the right.
        local layerLeft, layerRight = BeginRowGrid(container)
        local splitAt = math.ceil(ELEMENT_COUNT / 2)

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

            local drop = AddDropdownRow(displayIdx <= splitAt and layerLeft or layerRight, {
                label = label,
                indent = true,
                list = BuildStrataList(),
                value = CS.pendingStrataOrder[pos],
                onChange = function(val)
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
                end,
            })
            strataDropdowns[pos] = drop
        end
    end -- customStrataEnabled
    end -- not strataCollapsed

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
local function BuildTextureIndicatorSpeedSlider(container, config, label, onChange, indent)
    local function RefreshSpeedPreview()
        local refreshedMirror = ST._RefreshTextureIndicatorMirrorEffect
            and ST._RefreshTextureIndicatorMirrorEffect(CS.selectedGroup)
        if not refreshedMirror and ST._RefreshButtonsPreviewMirror then
            ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
        end
    end
    AddSliderRow(container, {
        label = label,
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
    local function RefreshRuntime()
        RefreshTextureIndicatorRuntime(group, auraControlled)
    end

    if container then
    local enableCb = AddCheckboxRow(container, {
        label = sectionDef.label,
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
                indent = inline == true,
                tbl = config,
                key = "color",
                default = { 1, 1, 1, 1 },
                hasAlpha = true,
                onConfirm = RefreshRuntime,
                onChange = RefreshRuntime,
            })
            BuildTextureIndicatorSpeedSlider(details, config, "Shift Duration", RefreshRuntime, inline)
        elseif config.effectType == "pulse" then
            BuildTextureIndicatorSpeedSlider(details, config, "Pulse Duration", RefreshRuntime, inline)
        elseif config.effectType == "shrinkExpand" then
            BuildTextureIndicatorSpeedSlider(details, config, "Cycle Duration", RefreshRuntime, inline)
        elseif config.effectType == "bounce" then
            BuildTextureIndicatorSpeedSlider(details, config, "Bounce Duration", RefreshRuntime, inline)
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
    if not config or not def then
        return
    end

    local enableCb = AddCheckboxRow(container, {
        label = def.label,
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

------------------------------------------------------------------------
-- Cooldown advanced panels, as descriptors
--
-- One cooldown drives the swipe and the cooldown text, and their gears sit on
-- two different tabs - only one of which is ever on screen. The preview
-- command center's gear opens BOTH panels at once (owner ruling 2026-07-26),
-- so their contents have to be reachable without the gear that normally
-- builds them. The tab builders below call these same factories, so each
-- panel still has exactly one definition.
--
-- The style table is resolved inside `build`, never captured. A panel the
-- command center opened for the tab you are NOT on has no gear on screen to
-- rebind its descriptor (RebindAdvancedSettingsPanel only fires from
-- AddAdvancedToggle, i.e. from a gear that actually builds), so a wholesale
-- style replacement that keeps the same context - Copy Style From Panel
-- assigns a fresh group.style outright - would leave a captured table
-- orphaned and every control in the panel writing into nothing. The tab
-- callers are unaffected either way: they rebuild and rebind every refresh.
--
-- A caller whose values do NOT live in the group style passes its own table
-- (`styleTable`): with an entry selected, the style lens hands the styling tabs
-- that entry's override store for the sections it owns, and there is no
-- resolver for those. Only a caller that rebinds every refresh may do this -
-- which the tab builders do, and the command center's tab-less opens do not.
------------------------------------------------------------------------

local function RefreshSelectedGroupStyle()
    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
end

local function ResolveSelectedGroupStyle()
    local groupId = CS.selectedGroup
    local profile = groupId and CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    return group and group.style or nil
end

local function MakeCooldownTextAdvancedDescriptor(styleTable)
    return {
        settingKey = "cooldownText",
        title = "Cooldown Text Advanced",
        build = function(panel)
            local style = styleTable or ResolveSelectedGroupStyle()
            if not style then
                return
            end

            -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow
            -- column, so every builder is called with { row = true } and no
            -- rightColumn, and each falls back to `container` for its extras.
            AddFontControls(panel, style, "cooldown", { size = 12 }, RefreshSelectedGroupStyle, { row = true })

            -- deferCommit is deliberately absent, matching the stock color picker
            -- this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = style,
                key = "cooldownFontColor",
                default = {1, 1, 1, 1},
                onConfirm = RefreshSelectedGroupStyle,
                onChange = RefreshSelectedGroupStyle,
            })

            AddAnchorDropdown(panel, style, "cooldownTextAnchor", "CENTER", RefreshSelectedGroupStyle, nil, { row = true })

            AddOffsetSliders(panel, style, "cooldownTextXOffset", "cooldownTextYOffset", { x = 0, y = 0 }, RefreshSelectedGroupStyle, { row = true })
        end,
    }
end

local function MakeCooldownSwipeAdvancedDescriptor(styleTable)
    return {
        settingKey = "cooldownSwipe",
        title = "Cooldown Swipe Advanced",
        build = function(panel)
            local style = styleTable or ResolveSelectedGroupStyle()
            if not style then
                return
            end

            -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow
            -- column, so the rows go straight onto the panel scroll and the two
            -- conditional rows indent under the toggles that gate them.
            --
            -- The two structural toggles keep calling
            -- RefreshActiveAdvancedSettingsPanel: this descriptor rebuilds ITS
            -- OWN panel rather than the whole config, and that is what makes the
            -- opacity slider and the edge color appear and disappear in place.

            -- Reverse Swipe
            AddCheckboxRow(panel, {
                label = "Reverse Swipe",
                value = style.cooldownSwipeReverse or false,
                onChange = function(val)
                    style.cooldownSwipeReverse = val
                    RefreshSelectedGroupStyle()
                end,
            })

            -- Show Swipe Fill
            AddCheckboxRow(panel, {
                label = "Show Swipe Fill",
                value = style.showCooldownSwipeFill ~= false,
                onChange = function(val)
                    style.showCooldownSwipeFill = val
                    RefreshSelectedGroupStyle()
                    RefreshActiveAdvancedSettingsPanel()
                end,
            })

            -- Swipe Fill Opacity (only when fill is visible). Row grammar has
            -- no percent readout, so this reads 0 - 1 rather than the stock
            -- slider's 0% - 100%; same store, same range.
            if style.showCooldownSwipeFill ~= false then
                local opacityRow = AddSliderRow(panel, {
                    label = "Swipe Fill Opacity",
                    indent = true,
                    min = 0, max = 1, step = 0.05,
                    value = style.cooldownSwipeAlpha or 0.8,
                })
                WireMirrorFirstSlider(opacityRow, function(val)
                    style.cooldownSwipeAlpha = val
                end, RefreshSelectedGroupStyle, nil, style, "cooldownSwipeAlpha")
            end

            -- Show Swipe Edge
            AddCheckboxRow(panel, {
                label = "Show Swipe Edge",
                value = style.cooldownSwipeEdgeEnabled == true,
                onChange = function(val)
                    style.cooldownSwipeEdgeEnabled = val
                    RefreshSelectedGroupStyle()
                    RefreshActiveAdvancedSettingsPanel()
                end,
            })

            -- Swipe Edge Color (only when edge is visible). deferCommit is
            -- deliberately absent, matching the stock color picker it replaced.
            if style.cooldownSwipeEdgeEnabled == true then
                AddColorRow(panel, {
                    label = "Swipe Edge Color",
                    indent = true,
                    tbl = style,
                    key = "cooldownSwipeEdgeColor",
                    default = {1, 1, 1, 1},
                    hasAlpha = true,
                    onConfirm = RefreshSelectedGroupStyle,
                    onChange = RefreshSelectedGroupStyle,
                })
            end
        end,
    }
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
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

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
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

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

-- Arriving at a different panel or display mode must not inherit the last
-- one's running glow preview. Rebuilds of the SAME tab must NOT stop it:
-- these previews are started from the preview command center, and
-- previewing is a "turn it on, then adjust until it looks right"
-- workflow - so any settings change that refreshes the config would
-- otherwise kill the preview mid-adjustment. Same context gate the
-- texture/trigger reset above uses.
local function BuildBarModeEffects(container, group, style, previewContextChanged)
    if previewContextChanged then
        CooldownCompanion:SetGroupProcGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupReadyGlowPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupKeyPressHighlightPreview(CS.selectedGroup, false)
        CooldownCompanion:SetGroupBarAuraEffectPreview(CS.selectedGroup, false)
        -- The bar variant also owns the staged aura drain conditional.
        CooldownCompanion:SetGroupBarPandemicPreview(CS.selectedGroup, false)
    end
    BuildBarEffectsTab(container, group, style)
end

-- The four glow sections below are icons-mode only and are each called exactly
-- once, from BuildEffectsTab's icons path, so they were converted to the row
-- grammar outright rather than growing an opts.row mode. `container` is the
-- grid column the row belongs to.
--
-- STYLE LENS (Helpers.lua): each takes the tab's lens, resolved ONCE in
-- BuildEffectsTab and handed down, and resolves its OWN section against it -
-- the same shape the bars twins use. With an entry selected the rows read that
-- entry's effective values and write only where the entry owns the section; a
-- nil write table is the inert marker, and the scope chrome attached last is
-- the only way back out of it.
--
-- The lens helpers are taken as function-locals rather than hoisted to file
-- scope: BuildAppearanceTab already sits on Lua 5.1's hard 60-upvalue ceiling
-- (see the note by the row-grammar imports), so this file adds no new
-- file-scope locals.
local function BuildProcGlowSection(container, group, style, lens)
    local ResolveLensSection = ST._ResolveLensSection
    local MarkInertRange = ST._MarkInertRange
    local ApplyInertRange = ST._ApplyInertRange
    local AttachRowScopeChrome = ST._AttachRowScopeChrome

    -- Passive entries are not special-cased here. The retired promote badge on
    -- this row skipped itself for them, which no other surface did:
    -- CanButtonUseConfigOverrideSection allows Proc Glow on a passive entry.
    -- The lens asks that same question, so an entry that genuinely cannot use
    -- the section resolves "denied" and renders inert with no Customize
    -- affordance.
    local _, procRead, procWrite = ResolveLensSection(lens, group, "procGlow")
    local procInertMark = (procWrite == nil) and MarkInertRange(container) or nil

    local procEnableCb = AddCheckboxRow(container, {
        label = "Show Proc Glow",
        value = procRead.procGlowStyle ~= "none",
        disabled = procWrite == nil,
        onChange = function(val)
            if not procWrite then return end
            procWrite.procGlowStyle = val and "glow" or "none"
            UpdateSelectedGroupStyle(true)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- the shared glow builder runs in row mode with NO rightColumn - its row
    -- path puts the extras in `container` when none is given.
    --
    -- The panel captures the section's WRITE table, which is the group style or
    -- the selected entry's override store depending on scope. Only built while
    -- there is one: an inert section has no gear to open it from.
    local function BuildProcGlowAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Show Only In Combat",
            value = procWrite.procGlowCombatOnly or false,
            onChange = function(val)
                procWrite.procGlowCombatOnly = val
                UpdateSelectedGroupStyle()
            end,
        })

        BuildProcGlowControls(panel, procWrite, UpdateSelectedGroupStyle, { row = true })

    end

    if procWrite then
        AddAdvancedToggle(procEnableCb, "procGlow", tabInfoButtons, procRead.procGlowStyle ~= "none", {
            title = "Proc Glow Advanced",
            build = BuildProcGlowAdvanced,
        })
    end
    AttachRowScopeChrome(procEnableCb, lens, group, "procGlow")

    if procInertMark then
        ApplyInertRange(container, procInertMark)
    end

    -- Preview reconciliation follows the same READ the row does, so a group
    -- preview is cleared whenever what is on screen would not render. Clearing
    -- is the safe direction; nothing here ever starts a preview.
    if procRead.procGlowStyle == "none" then
        CooldownCompanion:SetGroupProcGlowPreview(CS.selectedGroup, false)
    end
end

-- Aura glow: kit-rendered on the aura slot button, so it appears exactly
-- while the tracked aura is active. Shown only when the group has an
-- aura-tracking entry (Phase 3 gating pattern).
local function BuildAuraGlowSection(container, group, style, lens)
    local ResolveLensSection = ST._ResolveLensSection
    local MarkInertRange = ST._MarkInertRange
    local ApplyInertRange = ST._ApplyInertRange
    local AttachRowScopeChrome = ST._AttachRowScopeChrome

    -- The gate stays on the GROUP: with an entry selected that tracks no aura
    -- the row is still drawn and the lens resolves it "not available" for that
    -- entry, which states the reason rather than hiding it.
    if not GroupHasAuraTrackingEntry(group) then
        -- The section owning an active preview just disappeared (last aura
        -- entry removed); don't leave the preview glow orphaned.
        CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
        return
    end

    local _, auraRead, auraWrite = ResolveLensSection(lens, group, "auraIndicator")
    local auraInertMark = (auraWrite == nil) and MarkInertRange(container) or nil

    local auraGlowEnabled = (auraRead.auraGlowStyle or "pulse") ~= "none"
    local auraEnableCb = AddCheckboxRow(container, {
        label = "Show Aura Glow",
        value = auraGlowEnabled,
        disabled = auraWrite == nil,
        onChange = function(val)
            if not auraWrite then return end
            auraWrite.auraGlowStyle = val and "pulse" or "none"
            if val then
                -- Re-enabling forces the pulse style; reset its per-style keys
                -- so a leftover proc-scale size can't render as a 30px border.
                auraWrite.auraGlowSize = 2
                auraWrite.auraGlowSpeed = 0.5
            end
            UpdateSelectedGroupStyle(true)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
    -- panel captures the section's WRITE table and is only built while there is
    -- one - an inert section has no gear to open it from.
    local function BuildAuraGlowAdvanced(panel)
        BuildAuraGlowControls(panel, auraWrite, UpdateSelectedGroupStyle, { row = true })
    end

    if auraWrite then
        AddAdvancedToggle(auraEnableCb, "auraGlow", tabInfoButtons, auraGlowEnabled, {
            title = "Aura Glow Advanced",
            build = BuildAuraGlowAdvanced,
        })
    end
    -- Second badge in the chain: gear, then this, then the scope chrome the lens
    -- attaches last. The anchor args are a placeholder - AnchorRowBadge
    -- re-points the button onto the chain's end.
    AnchorRowBadge(auraEnableCb, CreateInfoButton(auraEnableCb.frame, auraEnableCb.frame, "LEFT", "LEFT", 0, 0, {
        "Aura Glow",
        {"Adds a glow to a button while its tracked aura is active.", 1, 1, 1, true},
    }, tabInfoButtons))
    AttachRowScopeChrome(auraEnableCb, lens, group, "auraIndicator")

    if auraInertMark then
        ApplyInertRange(container, auraInertMark)
    end

    if not auraGlowEnabled then
        CooldownCompanion:SetGroupAuraGlowPreview(CS.selectedGroup, false)
    end
end

-- Pandemic effect (PTR 8): a second kit glow the game reveals only while the
-- tracked aura sits inside its refresh window. It shares the Pandemic section,
-- and the "pandemic" OVERRIDE section, with the marker below — one feature,
-- two rows.
--
-- The section's ONE scope chrome sits on the Pandemic HEADING (owner ruling),
-- so neither half carries a row affordance of its own: both resolve the same
-- "pandemic" section and flip together, silently. The bars twin makes the same
-- ruling with the chrome on its enable row.
--
-- Nil-container contract, copied from the bars twin (BarModeTabs' Glows note):
-- the builder runs with whatever host it ends up with, because a glow left
-- running by a deleted aura entry - or by a collapsed section - still has to
-- be cleared. Guarding the CALL instead would strand the preview.
local function BuildPandemicGlowSection(container, group, style, lens)
    local ResolveLensSection = ST._ResolveLensSection
    local MarkInertRange = ST._MarkInertRange
    local ApplyInertRange = ST._ApplyInertRange

    local function ClearPandemicPreview()
        if CooldownCompanion.SetGroupPandemicPreview then
            CooldownCompanion:SetGroupPandemicPreview(CS.selectedGroup, false)
        end
    end
    if not GroupHasAuraTrackingEntry(group) then
        ClearPandemicPreview()
        return
    end

    local pandemicScope, pandemicRead, pandemicWrite = ResolveLensSection(lens, group, "pandemic")
    local pandemicEnabled = pandemicRead.pandemicEffectEnabled == true
    if container then
        local pandemicInertMark = (pandemicWrite == nil) and MarkInertRange(container) or nil

        local pandemicCb = AddCheckboxRow(container, {
            label = "Show Pandemic Effect",
            value = pandemicEnabled,
            disabled = pandemicWrite == nil,
            onChange = function(val)
                if not pandemicWrite then return end
                pandemicWrite.pandemicEffectEnabled = val and true or false
                UpdateSelectedGroupStyle(true)
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
        -- The panel captures the section's WRITE table with the panel style
        -- behind it: this glow family resolves its enable from an explicit-true
        -- key, so an override store that has not stored one yet reads the
        -- panel's. The section's enable toggle lives on the row above, never in
        -- the shared builder.
        local function BuildPandemicAdvanced(panel)
            BuildPandemicGlowControls(panel, pandemicWrite, UpdateSelectedGroupStyle, {
                row = true,
                fallbackStyle = (pandemicScope == "customized") and style or nil,
            })
        end

        if pandemicWrite then
            AddAdvancedToggle(pandemicCb, "pandemicGlow", tabInfoButtons, pandemicEnabled, {
                title = "Pandemic Effect Advanced",
                build = BuildPandemicAdvanced,
            })
        end
        AnchorRowBadge(pandemicCb, CreateInfoButton(pandemicCb.frame, pandemicCb.frame, "LEFT", "LEFT", 0, 0, {
            "Pandemic Effect",
            {"Glows a button while its tracked aura is in the refresh window, where recasting adds bonus time.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Auras that gain no time when refreshed never show it.", 1, 1, 1, true},
            {" ", 1, 1, 1, true},
            {"Draws over the Aura Glow when both are on.", 1, 1, 1, true},
        }, tabInfoButtons))

        if pandemicInertMark then
            ApplyInertRange(container, pandemicInertMark)
        end
    end

    if not pandemicEnabled then
        ClearPandemicPreview()
    end
end

-- Pandemic marker: the text half of the same window. Rows only — no preview
-- surface renders the marker in any mode (every duration-text stand-in writes
-- a bare countdown), so there is deliberately no command-center control to
-- reconcile here and no nil-container contract to honour.
--
-- The marker rides the aura duration text, which lives on the Appearance tab.
-- The rows stay visible when that text is off and the info tooltip says what
-- happens; a control that vanishes onto another tab is harder to find than an
-- inert one.
local function BuildPandemicMarkerSection(container, group, style, lens)
    local ResolveLensSection = ST._ResolveLensSection
    local MarkInertRange = ST._MarkInertRange
    local ApplyInertRange = ST._ApplyInertRange

    if not container or not GroupHasAuraTrackingEntry(group) then
        return
    end

    -- Same override section as the effect row in the left column, so this half
    -- FOLLOWS that section's scope silently: one feature, one affordance, and
    -- the chrome for it is on the section's heading.
    local _, markerRead, markerWrite = ResolveLensSection(lens, group, "pandemic")
    local markerInertMark = (markerWrite == nil) and MarkInertRange(container) or nil

    local applyStyle = function() UpdateSelectedGroupStyle(false) end
    local markerRow = AddPandemicMarkerControls(container, markerWrite or markerRead, applyStyle, function()
        CooldownCompanion:RefreshConfigPanel()
    end, { enableOnly = true })

    -- Single rail (AdvancedSettingsPanel.lua): the three styling rows fill the
    -- panel, so they carry no indent - childrenOnly drops it. The panel
    -- captures the section's WRITE table, and is only built while there is one.
    local function BuildPandemicMarkerAdvanced(panel)
        AddPandemicMarkerControls(panel, markerWrite, applyStyle, RefreshActiveAdvancedSettingsPanel,
            { childrenOnly = true })
    end

    if markerWrite then
        AddAdvancedToggle(markerRow, "pandemicMarker", tabInfoButtons,
            markerRead.pandemicMarkerEnabled ~= false, {
                title = "Pandemic Marker Advanced",
                build = BuildPandemicMarkerAdvanced,
            })
    end

    -- The shared helper takes no `disabled`, so the inert bracket is what makes
    -- this half read-only along with the rest of the section.
    if markerInertMark then
        ApplyInertRange(container, markerInertMark)
    end
end

local function BuildReadyGlowSection(container, group, style, lens)
    local ResolveLensSection = ST._ResolveLensSection
    local MarkInertRange = ST._MarkInertRange
    local ApplyInertRange = ST._ApplyInertRange
    local AttachRowScopeChrome = ST._AttachRowScopeChrome

    local _, readyRead, readyWrite = ResolveLensSection(lens, group, "readyGlow")
    local readyInertMark = (readyWrite == nil) and MarkInertRange(container) or nil

    local readyEnableCb = AddCheckboxRow(container, {
        label = "Show Ready Glow",
        value = readyRead.readyGlowStyle and readyRead.readyGlowStyle ~= "none",
        disabled = readyWrite == nil,
        onChange = function(val)
            if not readyWrite then return end
            readyWrite.readyGlowStyle = val and "solid" or "none"
            UpdateSelectedGroupStyle(true)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- every row goes straight onto the panel scroll and the shared glow builder
    -- runs in row mode with NO rightColumn.
    --
    -- The panel captures the section's WRITE table, which is the group style or
    -- the selected entry's override store depending on scope; the whole
    -- when-it-shows chain below follows the section it belongs to. Only built
    -- while there is a write table: an inert section has no gear to open it
    -- from. The Prime* calls follow the same scope: an entry-lens edit changed
    -- ONE entry's glow config, so only that entry's per-button transition
    -- state re-arms - re-priming the panel would restart auto-hide windows on
    -- entries the edit never touched.
    local primeTarget = (lens and lens.mode == "entry") and lens.buttonData or nil
    local function BuildReadyGlowAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Show Only In Combat",
            value = readyWrite.readyGlowCombatOnly or false,
            onChange = function(val)
                readyWrite.readyGlowCombatOnly = val
                UpdateSelectedGroupStyle()
            end,
        })

        -- The longest label in the panel: it fills the label half of a ~330px
        -- panel almost exactly, so the row also states it on hover rather than
        -- risking a silent truncation at a narrower config width.
        local readyChargesRow = AddCheckboxRow(panel, {
            label = "Glow When Charges Are Capped",
            value = readyWrite.readyGlowOnlyAtMaxCharges or false,
            tooltip = { "Glow When Charges Are Capped" },
            onChange = function(val)
                readyWrite.readyGlowOnlyAtMaxCharges = val == true
                UpdateSelectedGroupStyle()
                if (readyWrite.readyGlowDuration or 0) > 0 then
                    if val then
                        PrimeReadyGlowCappedChargeTransitions(CS.selectedGroup, primeTarget)
                    else
                        PrimeReadyGlowNormalTransitions(CS.selectedGroup, primeTarget)
                    end
                end
                CooldownCompanion:UpdateAllCooldowns()
            end,
        })
        -- Anchor args are a placeholder - AnchorRowBadge re-points the button
        -- onto the end of the row's label.
        AnchorRowBadge(readyChargesRow, CreateInfoButton(readyChargesRow.frame, readyChargesRow.frame, "LEFT", "LEFT", 0, 0, {
            "Glow When Charges Are Capped",
            {"When this toggle is enabled, the glow will only appear for charge based spells when at max charges.", 1, 1, 1, true},
        }, tabInfoButtons))

        AddCheckboxRow(panel, {
            label = "Auto-Hide After Duration",
            value = (readyWrite.readyGlowDuration or 0) > 0,
            onChange = function(val)
                readyWrite.readyGlowDuration = val and 3 or 0
                UpdateSelectedGroupStyle()
                if val then
                    if readyWrite.readyGlowOnlyAtMaxCharges then
                        PrimeReadyGlowCappedChargeTransitions(CS.selectedGroup, primeTarget)
                    else
                        PrimeReadyGlowNormalTransitions(CS.selectedGroup, primeTarget)
                    end
                end
                CooldownCompanion:UpdateAllCooldowns()
                -- Rebuilds THIS panel, not the whole config, which is what
                -- makes the duration slider below appear and disappear in place.
                RefreshActiveAdvancedSettingsPanel()
            end,
        })

        if (readyWrite.readyGlowDuration or 0) > 0 then
            local durationRow = AddSliderRow(panel, {
                label = "Duration (seconds)",
                indent = true,
                min = 0.5, max = 5, step = 0.5,
                value = readyWrite.readyGlowDuration or 3,
            })
            WireMirrorFirstSlider(durationRow, function(val)
                readyWrite.readyGlowDuration = val
            end, UpdateSelectedGroupStyle, nil, readyWrite, "readyGlowDuration")
        end

        BuildReadyGlowControls(panel, readyWrite, UpdateSelectedGroupStyle, { row = true })

    end

    if readyWrite then
        AddAdvancedToggle(readyEnableCb, "readyGlow", tabInfoButtons, readyRead.readyGlowStyle and readyRead.readyGlowStyle ~= "none", {
            title = "Ready Glow Advanced",
            build = BuildReadyGlowAdvanced,
        })
    end
    -- Second badge in the chain: gear, then this, then the scope chrome the lens
    -- attaches last. The anchor args are a placeholder.
    AnchorRowBadge(readyEnableCb, CreateInfoButton(readyEnableCb.frame, readyEnableCb.frame, "LEFT", "LEFT", 0, 0, {
        "Ready Glow",
        {"Adds a glow to spells/items that are not on cooldown.", 1, 1, 1, true},
    }, tabInfoButtons))
    AttachRowScopeChrome(readyEnableCb, lens, group, "readyGlow")

    if readyInertMark then
        ApplyInertRange(container, readyInertMark)
    end

    if not (readyRead.readyGlowStyle and readyRead.readyGlowStyle ~= "none") then
        CooldownCompanion:SetGroupReadyGlowPreview(CS.selectedGroup, false)
    end
end

local function BuildKeyPressHighlightSection(container, group, style, lens)
    local ResolveLensSection = ST._ResolveLensSection
    local MarkInertRange = ST._MarkInertRange
    local ApplyInertRange = ST._ApplyInertRange
    local AttachRowScopeChrome = ST._AttachRowScopeChrome

    local _, kphRead, kphWrite = ResolveLensSection(lens, group, "keyPressHighlight")
    local kphInertMark = (kphWrite == nil) and MarkInertRange(container) or nil

    local kphEnableCb = AddCheckboxRow(container, {
        label = "Show Key Press Highlight",
        value = kphRead.keyPressHighlightStyle and kphRead.keyPressHighlightStyle ~= "none",
        disabled = kphWrite == nil,
        onChange = function(val)
            if not kphWrite then return end
            kphWrite.keyPressHighlightStyle = val and "solid" or "none"
            UpdateSelectedGroupStyle(true)
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
    -- panel captures the section's WRITE table and is only built while there is
    -- one - an inert section has no gear to open it from.
    local function BuildKeyPressHighlightAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Show Only In Combat",
            value = kphWrite.keyPressHighlightCombatOnly or false,
            onChange = function(val)
                kphWrite.keyPressHighlightCombatOnly = val
                UpdateSelectedGroupStyle()
            end,
        })

        BuildKeyPressHighlightControls(panel, kphWrite, UpdateSelectedGroupStyle, { row = true })

    end

    if kphWrite then
        AddAdvancedToggle(kphEnableCb, "keyPressHighlight", tabInfoButtons, kphRead.keyPressHighlightStyle and kphRead.keyPressHighlightStyle ~= "none", {
            title = "Key Press Highlight Advanced",
            build = BuildKeyPressHighlightAdvanced,
        })
    end
    -- Second badge in the chain: gear, then this, then the scope chrome the lens
    -- attaches last. The anchor args are a placeholder.
    AnchorRowBadge(kphEnableCb, CreateInfoButton(kphEnableCb.frame, kphEnableCb.frame, "LEFT", "LEFT", 0, 0, {
        "Key Press Highlight",
        {"Shows a glow overlay on buttons while their action bar keybind is physically held down.", 1, 1, 1, true},
    }, tabInfoButtons))
    AttachRowScopeChrome(kphEnableCb, lens, group, "keyPressHighlight")

    if kphInertMark then
        ApplyInertRange(container, kphInertMark)
    end

    if not (kphRead.keyPressHighlightStyle and kphRead.keyPressHighlightStyle ~= "none") then
        CooldownCompanion:SetGroupKeyPressHighlightPreview(CS.selectedGroup, false)
    end
end

-- The Indicators tab's three row-grammar sections. They collapse like every
-- other row-grammar section, which means the advanced gears inside them only
-- build while their section is open - and a queued advanced key with no gear
-- left to consume it expires silently (ConsumeQueuedAdvancedSettingsPanelOpen).
--
-- So this file, which owns both the sections and the AddAdvancedToggle keys
-- below, also states which section each gear sits in. The preview command
-- center reads the map before it queues and clears that collapse key on the
-- way past (PreviewCommandCenter's ApplyGearRoute). Keep the two in step: a
-- gear added to one of these sections belongs here the same day.
--
-- BAR MODE SHARES THESE KEYS. BarModeTabs draws its own Glows / Timers /
-- States sections and deliberately reuses these three collapse keys, so one
-- entry per advanced key covers both tabs. That is why `barActiveAura` - a
-- bars-only gear - lives in this icons-owned map: the map is keyed by gear,
-- and a key reached in a mode that has no such section just clears a collapse
-- state nothing is reading.
local EFFECTS_GLOWS_SECTION = "effects_glows"
local EFFECTS_PANDEMIC_SECTION = "effects_pandemic"
local EFFECTS_TIMERS_SECTION = "effects_timers"
local EFFECTS_STATES_SECTION = "effects_states"

ST._INDICATORS_SECTION_BY_ADVANCED_KEY = {
    procGlow = EFFECTS_GLOWS_SECTION,
    readyGlow = EFFECTS_GLOWS_SECTION,
    keyPressHighlight = EFFECTS_GLOWS_SECTION,
    auraGlow = EFFECTS_GLOWS_SECTION,
    assistedHighlight = EFFECTS_GLOWS_SECTION,
    barActiveAura = EFFECTS_GLOWS_SECTION,

    -- The refresh window owns both its visuals, so both gears sit in the
    -- Pandemic section rather than beside unrelated glows and unrelated text.
    -- The bars route reaches this section by name instead of by key (it has
    -- no gear of its own): PreviewCommandCenter's barPandemic `uncollapse`.
    pandemicGlow = EFFECTS_PANDEMIC_SECTION,
    pandemicMarker = EFFECTS_PANDEMIC_SECTION,
    barPandemicMarker = EFFECTS_PANDEMIC_SECTION,

    iconFillTimer = EFFECTS_TIMERS_SECTION,
    cooldownSwipe = EFFECTS_TIMERS_SECTION,
    auraDurationSwipe = EFFECTS_TIMERS_SECTION,

    unusableVisual = EFFECTS_STATES_SECTION,
    tooltipBehavior = EFFECTS_STATES_SECTION,

    -- Textures mode's own section (BuildTextureEffectsTab above). Its constant
    -- is declared beside that builder because the builder reads it.
    textureIndicator_proc = EFFECTS_TEXTURE_INDICATORS_SECTION,
    textureIndicator_ready = EFFECTS_TEXTURE_INDICATORS_SECTION,
    textureIndicator_unusable = EFFECTS_TEXTURE_INDICATORS_SECTION,
}

-- The icons Indicators tab's advanced gears, by the OVERRIDE SECTION each one
-- belongs to. A SECOND map for the same gears, because it answers a different
-- question than the collapse map directly above: that one says "which
-- COLLAPSE section is this gear inside", this one says "which OVERRIDE section
-- owns this gear's values". Shaped and named after the appearance, bars and
-- text maps (ST._APPEARANCE_SECTION_BY_ADVANCED_KEY and friends) - never feed
-- one map's values to the other's consumer.
--
-- The style lens reads it at the foot of BOTH icons builders: a section the
-- selected entry only INHERITS builds no gear at all, so nothing rebinds or
-- closes an advanced panel that was already open on it, and that panel's
-- controls still point at the table the previous build handed them. Only one
-- panel tab is ever built at a time, so each icons builder sweeps this map AND
-- ST._APPEARANCE_SECTION_BY_ADVANCED_KEY below.
--
-- It lists every icons-mode gear on the tab. Bars-only gears (barActiveAura,
-- barPandemicMarker) are NOT here - BarModeTabs owns and sweeps its own map -
-- and neither are the textures gears, which have no override sections at all.
--
-- A gear added to any section on this tab belongs here the same day.
ST._INDICATORS_OVERRIDE_SECTION_BY_ADVANCED_KEY = {
    procGlow = "procGlow",
    readyGlow = "readyGlow",
    keyPressHighlight = "keyPressHighlight",
    auraGlow = "auraIndicator",
    assistedHighlight = "assistedHighlight",

    -- One section for the whole refresh window, so both gears name it.
    pandemicGlow = "pandemic",
    pandemicMarker = "pandemic",

    iconFillTimer = "iconFillTimer",
    cooldownSwipe = "cooldownSwipe",
    auraDurationSwipe = "auraDurationSwipe",

    -- Named by the shared builders themselves (SectionBuilders.lua), which is
    -- why these two keys read differently from their section ids.
    unusableVisual = "unusableDimming",
    tooltipBehavior = "showTooltips",
}

local function BuildEffectsTab(container)
    ClearEffectsTabWidgets()

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style

    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    -- Declared before the mode branches because the rotation assistant one
    -- needs it too, not just the icons path at the foot of this builder.
    local BeginRowGrid = ST._BeginRowGrid

    local displayMode = group.displayMode
    local previewContextChanged = CS.lastEffectsPreviewGroup ~= CS.selectedGroup
        or CS.lastEffectsPreviewMode ~= displayMode
    if previewContextChanged then
        ResetEffectsTabPreviews()
        CS.lastEffectsPreviewGroup = CS.selectedGroup
        CS.lastEffectsPreviewMode = displayMode
    end

    if displayMode == "trigger" then
        BuildTriggerEffectsTab(container, group)
        return
    end

    if displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        -- Row grammar, reusing the icons tab's own Timers/States collapse keys
        -- (the bar-mode precedent stated above the section map): one entry per
        -- advanced key covers every mode that draws the section, so the
        -- `unusableVisual` and `tooltipBehavior` gears in here are queue-safe
        -- for free. A rotation assistant panel has no per-entry style, so no
        -- section in here carries scope chrome.
        local _, raTimersCollapsed = BuildCollapsibleSection(container, "Timers", EFFECTS_TIMERS_SECTION, nil, nil, ROW_SECTION)

        if not raTimersCollapsed then
        -- LEFT column: the cooldown swipe and the chain hanging off it - one
        -- parent chain, so it never splits. RIGHT column: the GCD swipe.
        local raTimerLeft, raTimerRight = BeginRowGrid(container)

        BuildCooldownSwipeControls(raTimerLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        BuildShowGCDSwipeControls(raTimerRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        end -- not raTimersCollapsed

        local _, raStatesCollapsed = BuildCollapsibleSection(container, "States", EFFECTS_STATES_SECTION, nil, nil, ROW_SECTION)

        if not raStatesCollapsed then
        -- Same split the icons States section uses: LEFT the three looks an
        -- icon can take (on cooldown, unusable, out of range), RIGHT the
        -- situational state and the hover behavior.
        local raStateLeft, raStateRight = BeginRowGrid(container)

        BuildDesaturationControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        BuildUnusableDimmingControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, { row = true })
        BuildShowOutOfRangeControls(raStateLeft, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, { row = true })

        BuildLossOfControlControls(raStateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        BuildShowTooltipsControls(raStateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end, { row = true, advanced = true })
        BuildAllowPingsControls(raStateRight, style, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
        end -- not raStatesCollapsed
        return
    end

    if displayMode == "textures" then
        BuildTextureEffectsTab(container, group)
        return
    end

    if displayMode == "bars" then
        BuildBarModeEffects(container, group, style, previewContextChanged)
        return
    end

    -- ================================================================
    -- Row grammar (RowWidgets.lua) - icons mode only; every other display
    -- mode returned above. Each setting is a fixed-height row (label left,
    -- control right-aligned in a 140px column, gear/info/scope badges
    -- chained off the end of the label), and each section splits its rows
    -- into a curated two-column grid from BeginRowGrid.
    --
    -- All four sections collapse, like every other row-grammar section. The
    -- preview command center's quick-access gears queue advanced keys at the
    -- toggles below and a gear that never builds expires silently, so the
    -- collapse keys are declared alongside the gear-to-section map above and
    -- the gear route clears the right one before the rebuild.
    --
    -- Headers own the vertical air before their section, so nothing adds
    -- spacers of its own.
    --
    -- Every badge-bearing row here ends in a checkbox, so no badge had to
    -- move off a wide control.
    -- ================================================================

    -- STYLE LENS (Helpers.lua). With an entry selected these sections stop
    -- being the panel's settings and become a view of that entry's EFFECTIVE
    -- ones, with per-section scope deciding where - or whether - they write.
    -- Resolved ONCE here and handed to every section below, so one tab cannot
    -- disagree with itself about which entry it is showing.
    --
    -- Function-locals, not upvalues: see the note by the row-grammar imports.
    local ResolveLensSection = ST._ResolveLensSection
    local AttachRowScopeChrome = ST._AttachRowScopeChrome
    local AttachHeadingScopeChrome = ST._AttachHeadingScopeChrome
    local MarkInertRange = ST._MarkInertRange
    local ApplyInertRange = ST._ApplyInertRange
    local lens = ST._ResolveStyleLens(group)

    -- ================================================================
    -- Glows
    -- ================================================================
    local _, glowsCollapsed = BuildCollapsibleSection(container, "Glows", EFFECTS_GLOWS_SECTION, nil, nil, ROW_SECTION)

    if not glowsCollapsed then
    -- LEFT column: the glows every icon panel can show.
    -- RIGHT column: the conditional one (aura) and the Blizzard-driven extra.
    local glowLeft, glowRight = BeginRowGrid(container)

    BuildProcGlowSection(glowLeft, group, style, lens)
    BuildReadyGlowSection(glowLeft, group, style, lens)
    BuildKeyPressHighlightSection(glowLeft, group, style, lens)

    -- Gated on the group tracking an aura, so this column can run a row short;
    -- the grid top-aligns its columns, so a short side just ends early.
    BuildAuraGlowSection(glowRight, group, style, lens)

    -- Assisted Highlight is an override section like the four glows above, and
    -- gets its FIRST per-entry affordance here: it never carried a promote
    -- badge, so under the lens the scope chrome is the whole of it (the
    -- appearance tab's Icon Zoom row set the precedent).
    local _, assistedRead, assistedWrite = ResolveLensSection(lens, group, "assistedHighlight")
    local assistedInertMark = (assistedWrite == nil) and MarkInertRange(glowRight) or nil

    local assistedCb = AddCheckboxRow(glowRight, {
        label = "Show Assisted Highlight",
        value = assistedRead.showAssistedHighlight or false,
        disabled = assistedWrite == nil,
        onChange = function(val)
            if not assistedWrite then return end
            assistedWrite.showAssistedHighlight = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn - the
    -- builder's row path falls back to `container` for its right-hand rows. The
    -- panel captures the section's WRITE table and is only built while there is
    -- one - an inert section has no gear to open it from.
    local function BuildAssistedHighlightAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Show Only In Combat",
            value = assistedWrite.assistedHighlightCombatOnly or false,
            onChange = function(val)
                assistedWrite.assistedHighlightCombatOnly = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        BuildAssistedHighlightControls(panel, assistedWrite, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, { row = true })
    end

    if assistedWrite then
        AddAdvancedToggle(assistedCb, "assistedHighlight", tabInfoButtons, assistedRead.showAssistedHighlight or false, {
            title = "Assisted Highlight Advanced",
            build = BuildAssistedHighlightAdvanced,
        })
    end
    AttachRowScopeChrome(assistedCb, lens, group, "assistedHighlight")

    if assistedInertMark then
        ApplyInertRange(glowRight, assistedInertMark)
    end
    end -- not glowsCollapsed

    -- ================================================================
    -- Pandemic
    -- ================================================================
    -- Both halves are aura-only, so unlike Glows the whole header is gated -
    -- an empty "Pandemic" heading on a group with no aura entry would be a
    -- promise of nothing. The effect builder still runs with a nil host so it
    -- can reconcile its preview; the bars twin has carried that contract
    -- since PTR 8 and this side needs it for the same reason.
    local pandemicLeft, pandemicRight
    if GroupHasAuraTrackingEntry(group) then
        local pandemicHeading, pandemicCollapsed = BuildCollapsibleSection(container, "Pandemic",
            EFFECTS_PANDEMIC_SECTION, nil, nil, ROW_SECTION)
        -- ONE scope chrome for the whole feature, on the HEADING (owner ruling):
        -- the glow and the marker are two rows of one override section, so a
        -- per-row affordance would offer the same customize twice and revert
        -- from either would silently take the other with it. Both halves resolve
        -- "pandemic" and flip together, silently.
        AttachHeadingScopeChrome(pandemicHeading, lens, group, "pandemic")
        if not pandemicCollapsed then
            -- LEFT the glow half, RIGHT the text half.
            pandemicLeft, pandemicRight = BeginRowGrid(container)
        end
    end
    BuildPandemicGlowSection(pandemicLeft, group, style, lens)
    BuildPandemicMarkerSection(pandemicRight, group, style, lens)

    -- ================================================================
    -- Timers
    -- ================================================================
    local _, timersCollapsed = BuildCollapsibleSection(container, "Timers", EFFECTS_TIMERS_SECTION, nil, nil, ROW_SECTION)

    if not timersCollapsed then
    -- LEFT column: the two cooldown timers, adjacent because the fill timer
    -- disables the swipe.
    -- RIGHT column: the aura timer (gated on an aura-tracking entry) and the
    -- GCD swipe, which is ungated - on a group with no aura entry this column
    -- is the GCD swipe alone.
    local timerLeft, timerRight = BeginRowGrid(container)

    -- Each of the four sections below resolves its own scope against the lens.
    -- The write table is the whole gate: nil means the section is INERT, so its
    -- rows go in read-only, it builds no gear, and no callback of its own can
    -- reach a saved table. The scope chrome is attached LAST on the row (after
    -- the gear, after any info button, after the row's disabled state is
    -- final), because it is the one control that stays live in an inert section
    -- - the way back out of it.
    local fillScope, fillRead, fillWrite = ResolveLensSection(lens, group, "iconFillTimer")
    -- The shared builder takes no `disabled` option of its own, so an inert
    -- scope is applied by bracketing its rows instead - the same shape the bars
    -- States section uses for its two shared builders. The gear below is
    -- caller-built, so it is gated the ordinary way.
    local fillInertMark = (fillWrite == nil) and MarkInertRange(timerLeft) or nil

    -- The interlock derives from the RESOLVED READ table, not the panel style:
    -- an entry whose effective fill timer differs from the panel's has to see
    -- its own swipe row greyed (or not). Masque is GROUP data with no override
    -- section, so that half of the gate stays group-level.
    local iconFillTimerActive = fillRead.iconFillEnabled == true and group.masqueEnabled ~= true
    local iconFillCb = BuildIconFillTimerControls(timerLeft, fillWrite or fillRead, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end, {
        row = true,
        masqueEnabled = group.masqueEnabled == true,
        showAdvancedControlsInline = false,
        fallbackStyle = (fillScope == "customized") and style or nil,
        onEnabled = function()
            if CS.QueueAdvancedSettingsPanelOpen then
                CS.QueueAdvancedSettingsPanelOpen("iconFillTimer")
            end
        end,
    })
    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
    -- panel captures the section's WRITE table and is only built while there is
    -- one - an inert section has no gear to open it from.
    local function BuildIconFillAdvanced(panel)
        if BuildIconFillTimerAdvancedControls then
            BuildIconFillTimerAdvancedControls(panel, fillWrite, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, { row = true, indent = false })
        end
    end

    if fillWrite then
        AddAdvancedToggle(iconFillCb, "iconFillTimer", tabInfoButtons, iconFillTimerActive, {
            title = "Icon Fill Timer Advanced",
            build = BuildIconFillAdvanced,
        })
    end
    -- Second badge in the chain: gear, then this, then the scope chrome the
    -- lens attaches last. AnchorRowBadge appends to whatever the chain actually
    -- ends at (the gear is not chained while it is hidden or unbuilt), so the
    -- anchor args below are a placeholder.
    AnchorRowBadge(iconFillCb, CreateInfoButton(iconFillCb.frame, iconFillCb.frame, "LEFT", "LEFT", 0, 0, {
        "Icon Fill Timer",
        {"Shows cooldowns as a rectangular fill over the icon instead of radial swipes.", 1, 1, 1, true},
        " ",
        {"Does not work while Masque is enabled.", 1, 1, 1, true},
        " ",
        {"Show Cooldown Swipe is unavailable while Icon Fill Timer is active.", 0.7, 0.7, 0.7, true},
    }, tabInfoButtons))
    AttachRowScopeChrome(iconFillCb, lens, group, "iconFillTimer")

    if fillInertMark then
        ApplyInertRange(timerLeft, fillInertMark)
    end

    -- One row, no gear of its own to bracket: `disabled` is the whole gate, and
    -- the chrome that undoes it is attached after.
    local swipeScope, swipeRead, swipeWrite = ResolveLensSection(lens, group, "cooldownSwipe")
    local swipeCb = AddCheckboxRow(timerLeft, {
        label = "Show Cooldown Swipe",
        value = swipeRead.showCooldownSwipe ~= false,
        disabled = swipeWrite == nil or iconFillTimerActive,
        onChange = function(val)
            if not swipeWrite or iconFillTimerActive then return end
            swipeWrite.showCooldownSwipe = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if swipeWrite then
        -- Panel scope hands the descriptor NO table, so it keeps resolving the
        -- live group style itself (see the factory's note). An entry's override
        -- store has no such resolver, so that one is handed over explicitly.
        local swipeAdvanced = MakeCooldownSwipeAdvancedDescriptor(
            swipeScope == "customized" and swipeWrite or nil)

        AddAdvancedToggle(swipeCb, swipeAdvanced.settingKey, tabInfoButtons,
            swipeRead.showCooldownSwipe ~= false and not iconFillTimerActive, {
                title = swipeAdvanced.title,
                build = swipeAdvanced.build,
            })
    end
    AttachRowScopeChrome(swipeCb, lens, group, "cooldownSwipe")

    -- Aura duration swipe (shown only while the group has an aura-tracking
    -- entry). The gate stays on the GROUP: an entry that tracks no aura still
    -- sees the row, and the lens resolves it "not available" for that entry
    -- rather than hiding it.
    if GroupHasAuraTrackingEntry(group) then
        local auraSwipeScope, auraSwipeRead, auraSwipeWrite = ResolveLensSection(lens, group, "auraDurationSwipe")
        local auraSwipeInertMark = (auraSwipeWrite == nil) and MarkInertRange(timerRight) or nil

        local auraDurationCb = BuildAuraDurationSwipeControls(timerRight, auraSwipeWrite or auraSwipeRead, function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end, {
            row = true,
            showAdvancedControlsInline = false,
            fallbackStyle = (auraSwipeScope == "customized") and style or nil,
        })
        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn. The
        -- panel captures the section's WRITE table and is only built while there
        -- is one - an inert section has no gear to open it from.
        local function BuildAuraDurationSwipeAdvanced(panel)
            BuildAuraDurationSwipeAdvancedControls(panel, auraSwipeWrite, function()
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, { row = true })
        end
        if auraSwipeWrite then
            AddAdvancedToggle(auraDurationCb, "auraDurationSwipe", tabInfoButtons, auraSwipeRead.showAuraDurationSwipe ~= false, {
                title = "Aura Duration Swipe Advanced",
                build = BuildAuraDurationSwipeAdvanced,
            })
        end
        AttachRowScopeChrome(auraDurationCb, lens, group, "auraDurationSwipe")

        if auraSwipeInertMark then
            ApplyInertRange(timerRight, auraSwipeInertMark)
        end
    end

    -- One row, no gear: `disabled` is the whole gate, so no inert bracket is
    -- needed - the chrome that undoes it is attached after. Same shape the bars
    -- Timers section uses for this setting.
    local _, gcdRead, gcdWrite = ResolveLensSection(lens, group, "showGCDSwipe")
    local gcdCb = AddCheckboxRow(timerRight, {
        label = "Show GCD Swipe",
        value = gcdRead.showGCDSwipe == true,
        disabled = gcdWrite == nil,
        onChange = function(val)
            if not gcdWrite then return end
            gcdWrite.showGCDSwipe = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })
    AttachRowScopeChrome(gcdCb, lens, group, "showGCDSwipe")
    end -- not timersCollapsed

    -- ================================================================
    -- States
    -- ================================================================
    local _, statesCollapsed = BuildCollapsibleSection(container, "States", EFFECTS_STATES_SECTION, nil, nil, ROW_SECTION)

    if not statesCollapsed then
    -- LEFT column: the three looks every icon has (on cooldown, unusable,
    -- out of range).
    -- RIGHT column: the situational state and the hover behavior.
    local stateLeft, stateRight = BeginRowGrid(container)

    -- Same per-section resolve the Timers section above states: the write table
    -- is the whole gate, and the scope chrome goes on LAST.
    local _, desatRead, desatWrite = ResolveLensSection(lens, group, "desaturation")
    local desatCb = AddCheckboxRow(stateLeft, {
        label = "Show Desaturate On Cooldown",
        value = desatRead.desaturateOnCooldown or false,
        disabled = desatWrite == nil,
        onChange = function(val)
            if not desatWrite then return end
            desatWrite.desaturateOnCooldown = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })
    AttachRowScopeChrome(desatCb, lens, group, "desaturation")

    -- Unusable Visual. This shared builder owns its OWN gear, so an inert scope
    -- cannot skip building one the way the hand-written sections do: the inert
    -- pass gates the gear it finds on the row (_cdcAdvancedBtn), and the sweep
    -- at the foot of this builder closes a panel it rebound.
    local unusableScope, unusableRead, unusableWrite = ResolveLensSection(lens, group, "unusableDimming")
    local unusableInertMark = (unusableWrite == nil) and MarkInertRange(stateLeft) or nil
    local unusableCb = BuildUnusableDimmingControls(stateLeft, unusableWrite or unusableRead, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end, {
        row = true,
        fallbackStyle = (unusableScope == "customized") and style or nil,
    })
    AttachRowScopeChrome(unusableCb, lens, group, "unusableDimming")
    if unusableInertMark then
        ApplyInertRange(stateLeft, unusableInertMark)
    end

    -- Inlined rather than given an opts.row mode: BuildShowOutOfRangeControls
    -- is one checkbox with no file-private state, the same call the Duration
    -- Format dropdown made on the Appearance tab. The shared builder is
    -- untouched for the override editor and the other display modes.
    local _, oorRead, oorWrite = ResolveLensSection(lens, group, "showOutOfRange")
    local oorCb = AddCheckboxRow(stateLeft, {
        label = "Show Out of Range",
        value = oorRead.showOutOfRange or false,
        disabled = oorWrite == nil,
        onChange = function(val)
            if not oorWrite then return end
            oorWrite.showOutOfRange = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    AttachRowScopeChrome(oorCb, lens, group, "showOutOfRange")

    -- Loss of Control - inlined for the same reason as Out of Range.
    local _, locRead, locWrite = ResolveLensSection(lens, group, "lossOfControl")
    local locCb = AddCheckboxRow(stateRight, {
        label = "Show Loss of Control",
        value = locRead.showLossOfControl or false,
        disabled = locWrite == nil,
        onChange = function(val)
            if not locWrite then return end
            locWrite.showLossOfControl = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end,
    })
    AttachRowScopeChrome(locCb, lens, group, "lossOfControl")

    -- Show Tooltips (panel refresh: the advanced gear only shows while the
    -- toggle is on). Its gear is the builder's own, so it is bracketed rather
    -- than skipped - see the Unusable Visual note above.
    local tooltipScope, tooltipRead, tooltipWrite = ResolveLensSection(lens, group, "showTooltips")
    local tooltipInertMark = (tooltipWrite == nil) and MarkInertRange(stateRight) or nil
    local tooltipCb = BuildShowTooltipsControls(stateRight, tooltipWrite or tooltipRead, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end, {
        row = true,
        advanced = true,
        infoButtons = tabInfoButtons,
        fallbackStyle = (tooltipScope == "customized") and style or nil,
    })
    AttachRowScopeChrome(tooltipCb, lens, group, "showTooltips")
    if tooltipInertMark then
        ApplyInertRange(stateRight, tooltipInertMark)
    end

    -- Allow Pings is a PANEL setting with no override section of its own
    -- (ST.OVERRIDE_SECTIONS), so under an entry lens it goes read-only with the
    -- rest of the panel-only content instead of letting a panel-wide edit be
    -- made from an entry's page - no scope chrome, and its reads and writes
    -- stay on the group style. The shared builder takes no `disabled` option,
    -- so the bracket is what greys it. Its "?" badge stays readable: the inert
    -- walk only reaches AceGUI children and the gear.
    local pingsInertMark = (lens.mode == "entry") and MarkInertRange(stateRight) or nil
    BuildAllowPingsControls(stateRight, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end, { row = true })
    if pingsInertMark then
        ApplyInertRange(stateRight, pingsInertMark)
    end
    end -- not statesCollapsed

    -- Inert-section sweep, over BOTH icons gear maps. A section the lens
    -- resolved read-only builds no gear, so nothing rebound or closed an
    -- advanced panel that was already open on that gear - and its controls
    -- still write to the table the PREVIOUS build handed them. Close those here.
    --
    -- Scope-driven, not collapse-driven: a collapsed section builds no gear
    -- either, and a panel left over from before an entry was selected is just
    -- as live behind a closed section as behind an open one.
    --
    -- Both maps, not just this tab's: only one panel tab is ever built at a
    -- time, so a stale panel whose gear lives on the icons Appearance tab is
    -- just as live from here as one of this tab's own. The bars pair has swept
    -- across its two tabs the same way since they were converted.
    --
    -- OVERRIDE maps, never the collapse map beside them: they are keyed the
    -- same and answer different questions, and a collapse key handed to the lens
    -- would resolve as a section no entry can own and close every gear on the
    -- tab.
    if CS.CloseAdvancedSettingsPanel then
        local gearMaps = { ST._INDICATORS_OVERRIDE_SECTION_BY_ADVANCED_KEY, ST._APPEARANCE_SECTION_BY_ADVANCED_KEY }
        for i = 1, #gearMaps do
            for advancedKey, sectionId in pairs(gearMaps[i]) do
                local _, _, sectionWrite = ResolveLensSection(lens, group, sectionId)
                if sectionWrite == nil then
                    CS.CloseAdvancedSettingsPanel({ settingKey = advancedKey })
                end
            end
        end
    end
end

-- Row grammar (RowWidgets.lua): one collapsible section of display rows. The
-- texture itself is shown and picked in the Live Preview above for both panel
-- kinds, so the tab holds no preview canvas or picker buttons.
--
-- Lives at file scope rather than inline in BuildAppearanceTab because that
-- builder sits on Lua 5.1's hard 60-upvalue ceiling; the captures this branch
-- needed were most of the last ones left. Reached from BOTH paths that used to
-- fall into the inline branch: a texture panel, and a trigger panel whose
-- display type is "texture".
--
-- The staging machinery below - the config-only settings copy, the
-- stage/refresh/cancel closures and AttachTextureValueSlider - moved verbatim.
-- It is owner-validated behaviour: runtime refreshes read the SAVED table, so a
-- texture panel edits a copy until the interaction is confirmed, and the row
-- conversion only changes which widget holds the control.
local function BuildTexturePanelAppearanceTab(container, group)
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

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
            indent = true,
            min = MIN_TEXTURE_PAIR_SPACING, max = MAX_TEXTURE_PAIR_SPACING, step = 0.01,
            value = settings.pairSpacing or 0,
        })
        AttachTextureValueSlider(spacingRow, "pairSpacing")
    end

    AddDropdownRow(textureLeft, {
        label = "Texture Look",
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
        min = 0.25, max = 4, step = 0.05,
        value = settings.scale or 1,
    })
    AttachTextureValueSlider(scaleRow, "scale")

    local rotationRow = AddSliderRow(textureRight, {
        label = "Rotation",
        min = MIN_TEXTURE_ROTATION, max = MAX_TEXTURE_ROTATION, step = 1,
        value = settings.rotation or 0,
    })
    AttachTextureValueSlider(rotationRow, "rotation")

    local stretchXRow = AddSliderRow(textureRight, {
        label = "Horizontal Stretch / Compress",
        min = MIN_TEXTURE_STRETCH, max = MAX_TEXTURE_STRETCH, step = 0.05,
        value = settings.stretchX or 0,
    })
    AttachTextureValueSlider(stretchXRow, "stretchX")

    local stretchYRow = AddSliderRow(textureRight, {
        label = "Vertical Stretch / Compress",
        min = MIN_TEXTURE_STRETCH, max = MAX_TEXTURE_STRETCH, step = 0.05,
        value = settings.stretchY or 0,
    })
    AttachTextureValueSlider(stretchYRow, "stretchY")

    local alphaRow = AddSliderRow(textureLeft, {
        label = "Texture Alpha",
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

-- The icons Appearance tab's advanced gears, by the OVERRIDE SECTION each one
-- belongs to. Shaped and named after ST._INDICATORS_SECTION_BY_ADVANCED_KEY
-- above, with one deliberate difference: that map answers "which COLLAPSE
-- section is this gear inside", this one answers "which OVERRIDE section owns
-- this gear's values". Keep them apart - they are read for different reasons.
--
-- The style lens reads it at the foot of BOTH icons builders: a section the
-- selected entry only INHERITS builds no gear at all, so nothing rebinds or
-- closes an advanced panel that was already open on it, and that panel's
-- controls still point at the table the previous build handed them. The sweeps
-- close those, each over this map AND the indicators map above.
--
-- A gear added to one of these five sections belongs here the same day. The
-- tab's other lens sections (Border, Icon Tint, Icon Zoom) carry no gear at
-- all, and Compact Mode's gear is not listed because compact mode is group
-- data with no override section - see the note at its call site.
ST._APPEARANCE_SECTION_BY_ADVANCED_KEY = {
    cooldownText = "cooldownText",
    chargeText = "chargeText",
    auraText = "auraText",
    auraStackText = "auraStackText",
    keybindText = "keybindText",
}

-- Where each override section is EDITED, now that the panel tabs are the lens
-- onto a selected entry: the tab that draws it and the collapse key of the
-- section it is drawn in.
--
-- Keyed by DISPLAY MODE first. The same section id is drawn in different
-- places depending on the mode - borderSettings sits under "Border" on the
-- icons Appearance tab and somewhere else entirely on a bar panel - so a flat
-- map could only ever describe one mode. Later packets add the `bars` and
-- `text` axes beside this one; a lookup that misses its mode has no home yet
-- rather than the wrong one.
ST._SECTION_HOME = ST._SECTION_HOME or {}
ST._SECTION_HOME.icons = {
    cooldownText = { tab = "appearance", collapseKey = "appearance_text" },
    chargeText = { tab = "appearance", collapseKey = "appearance_text" },
    auraText = { tab = "appearance", collapseKey = "appearance_text" },
    auraStackText = { tab = "appearance", collapseKey = "appearance_text" },
    keybindText = { tab = "appearance", collapseKey = "appearance_text" },
    borderSettings = { tab = "appearance", collapseKey = "appearance_border" },
    iconTint = { tab = "appearance", collapseKey = "appearance_iconTint" },
    -- Icon Zoom is one row inside the panel's own Icon Settings section, which
    -- is where its collapse key comes from.
    iconZoom = { tab = "appearance", collapseKey = "appearance_icons" },
    -- Indicators tab. The collapse keys come from the section constants
    -- declared with the gear-to-section maps above, never from literals: the
    -- bar tab shares those same constants, and a copy could drift from them.
    procGlow = { tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION },
    auraIndicator = { tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION },
    readyGlow = { tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION },
    keyPressHighlight = { tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION },
    assistedHighlight = { tab = "effects", collapseKey = EFFECTS_GLOWS_SECTION },
    -- Both halves of the refresh window live in one section, so the feature has
    -- one home whichever half a consumer was looking for.
    pandemic = { tab = "effects", collapseKey = EFFECTS_PANDEMIC_SECTION },
    iconFillTimer = { tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION },
    cooldownSwipe = { tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION },
    auraDurationSwipe = { tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION },
    showGCDSwipe = { tab = "effects", collapseKey = EFFECTS_TIMERS_SECTION },
    desaturation = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    unusableDimming = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    showOutOfRange = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    lossOfControl = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
    showTooltips = { tab = "effects", collapseKey = EFFECTS_STATES_SECTION },
}

local function BuildAppearanceTab(container)
    local refreshStyle = function() CooldownCompanion:UpdateGroupStyle(CS.selectedGroup) end
    -- Function-local, not an upvalue: see the note by the row-grammar imports.
    local BeginRowGrid = ST._BeginRowGrid

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
        -- Row grammar. A rotation assistant panel shows one recommendation at
        -- a time, so its whole Appearance tab is a single section.
        local _, assistantCollapsed = BuildCollapsibleSection(container, "Assistant Panel",
            "appearance_assistant", nil, nil, ROW_SECTION)

        if not assistantCollapsed then
        -- LEFT column: how the one icon is shaped and sized, then the keybind
        -- text drawn on it and what that text is drawn WITH.
        -- RIGHT column: the border around it, then where the keybind text
        -- lands and what colour it takes.
        local assistLeft, assistRight = BeginRowGrid(container)

        AddCheckboxRow(assistLeft, {
            label = "Square Icons",
            value = style.maintainAspectRatio ~= false,
            onChange = function(value)
                style.maintainAspectRatio = value ~= false
                style.buttonsPerRow = 1
                if not style.maintainAspectRatio then
                    local size = style.buttonSize or ST.BUTTON_SIZE
                    style.iconWidth = style.iconWidth or size
                    style.iconHeight = style.iconHeight or size
                end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if style.maintainAspectRatio ~= false then
            local sizeRow = AddSliderRow(assistLeft, {
                label = "Button Size",
                min = 10, max = 150, step = 0.1,
                value = style.buttonSize or ST.BUTTON_SIZE,
            })
            WireMirrorFirstSlider(sizeRow, function(value)
                style.buttonSize = value
                style.buttonsPerRow = 1
            end, nil, nil, style, { "buttonSize", "buttonsPerRow" })
        else
            local widthRow = AddSliderRow(assistLeft, {
                label = "Icon Width",
                min = 10, max = 150, step = 0.1,
                value = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE,
            })
            WireMirrorFirstSlider(widthRow, function(value)
                style.iconWidth = value
                style.buttonsPerRow = 1
            end, nil, nil, style, { "iconWidth", "buttonsPerRow" })

            local heightRow = AddSliderRow(assistLeft, {
                label = "Icon Height",
                min = 10, max = 150, step = 0.1,
                value = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE,
            })
            WireMirrorFirstSlider(heightRow, function(value)
                style.iconHeight = value
                style.buttonsPerRow = 1
            end, nil, nil, style, { "iconHeight", "buttonsPerRow" })
        end

        ST._BuildIconZoomControls(assistLeft, style, refreshStyle, {
            previewRefresh = function()
                if ST._RefreshButtonsPreviewMirror then
                    ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
                end
            end,
        })

        -- The border builder has no second-column split of its own, so its
        -- whole block heads the right column.
        BuildBorderControls(assistRight, style, refreshStyle, { row = true })

        BuildKeybindTextControls(assistLeft, style, refreshStyle, {
            row = true,
            rightColumn = assistRight,
            label = "Show Keybind Text",
            tooltip = {
                "Show Keybind Text",
                {"Shows detected keybind text for the current recommendation.", 1, 1, 1, true},
            },
        })
        end -- not assistantCollapsed
        return
    end

    if group.displayMode == "textures" or group.displayMode == "trigger" then
        BuildTexturePanelAppearanceTab(container, group)
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
    -- Row grammar (RowWidgets.lua): every setting below is a fixed-height row
    -- - label left, control right-aligned in a 140px control column,
    -- gear/info/scope badges chained off the end of the label. Rows sit in
    -- curated two-column grids from BeginRowGrid, each section splitting its
    -- rows along whatever line reads naturally for that section. Sections with
    -- too little to split keep the left column only.
    --
    -- Standing ruling (owner, 2026-07-27) - the two rules every row-grammar
    -- section on every tab follows:
    --
    -- 1. Split the rows so the columns run as even as the semantics allow.
    --    Meaning still wins where the two disagree: rows that must stay
    --    adjacent (one disables the next) stay adjacent, and a gated row can
    --    leave its column short, because the grid top-aligns its columns and
    --    a short side just ends early.
    -- 2. Every section is collapsible (BuildCollapsibleSection with a
    --    ROW_SECTION header). A collapsed section builds none of its rows, so
    --    any gear inside one needs queue-safe uncollapse wiring: whatever
    --    queues an advanced-panel open for that gear must clear the section's
    --    collapse key first, or the queued key expires against a gear that
    --    never built. The Indicators tab does this with a gear-to-section map
    --    (ST._INDICATORS_SECTION_BY_ADVANCED_KEY) read by the preview command
    --    center; bar mode's text section names its key on the route itself
    --    (`uncollapse`). Either shape is fine; having neither is not.
    -- 3. When a section's row set comes out of a FILTER - event families, a
    --    gate, anything that can delete whole groups of rows before they are
    --    assigned - fill the LEFT column first. A populated right column
    --    beside an empty left one is never acceptable. A semantic split that
    --    survives the filter intact still wins (both halves populated), but
    --    the moment the filter leaves only one of them the survivors split
    --    themselves across the columns left-first, ceil(n/2) left. The
    --    custom-bar Sound Alerts tab is the worked example: it splits
    --    cooldown-family left / aura-family right when a bar has both, and an
    --    aura-only bar's three dropdowns 2/1 instead of 0/3.
    --
    -- Section headers are left-aligned (ROW_SECTION) and own the vertical air
    -- BEFORE their section, so sections never butt together and nothing here
    -- adds spacers of its own.
    --
    -- Section-level action buttons ("Reset Colors to Default", the preset
    -- Apply/Save/Delete trio) are compact and flush left: SetAutoWidth(true),
    -- never SetFullWidth. A page-wide button is louder than every setting it
    -- sits under, and both List and Flow anchor their children from the left,
    -- so no alignment wrapper is needed. They go INSIDE the grid, filling the
    -- shorter column's empty tail, rather than below it - a lopsided section
    -- with a lone button hanging off the bottom reads as unfinished.
    -- ================================================================
    local groupHasAuraEntry = GroupHasAuraTrackingEntry(group)

    -- STYLE LENS (Helpers.lua). With an entry selected these sections stop
    -- being the panel's settings and become a view of that entry's EFFECTIVE
    -- ones, with per-section scope deciding where - or whether - they write.
    -- Resolved ONCE here and handed to every section below, so one tab cannot
    -- disagree with itself about which entry it is showing.
    --
    -- Function-locals, not upvalues: see the note by the row-grammar imports.
    local ResolveLensSection = ST._ResolveLensSection
    local AttachRowScopeChrome = ST._AttachRowScopeChrome
    local AttachHeadingScopeChrome = ST._AttachHeadingScopeChrome
    local ChainHeadingBadges = ST._ChainHeadingBadges
    local MarkInertRange = ST._MarkInertRange
    local ApplyInertRange = ST._ApplyInertRange
    local lens = ST._ResolveStyleLens(group)

    -- Sections with NO override identity of their own (the panel's layout, its
    -- Masque skinning): an entry cannot own them, so under an entry lens they
    -- say "Applies to all entries" and go read-only rather than quietly letting
    -- a panel-wide edit be made from an entry's page.
    local panelOnlyInert = lens.mode == "entry"

    -- ================================================================
    -- Icon Settings (shape, size, spacing, packing)
    -- ================================================================
    local iconHeading, iconSettingsCollapsed = BuildCollapsibleSection(container, "Icon Settings", "appearance_icons", nil, nil, ROW_SECTION)
    -- Panel-only (sectionId nil): shape, size and packing belong to the panel.
    -- Icon Zoom is the one exception inside this section - it IS an override
    -- section, so it resolves its own scope further down.
    AttachHeadingScopeChrome(iconHeading, lens, group, nil)

    if not iconSettingsCollapsed then
    -- LEFT column: how a single icon is shaped and sized.
    -- RIGHT column: how the icons sit together as a group.
    local iconLeft, iconRight = BeginRowGrid(container)

    local iconLeftInertMark = panelOnlyInert and MarkInertRange(iconLeft) or nil

    local squareRow = AddCheckboxRow(iconLeft, {
        label = "Square Icons",
        value = style.maintainAspectRatio or false,
        disabled = panelOnlyInert or group.masqueEnabled == true,
        onChange = function(val)
            style.maintainAspectRatio = val
            if not val then
                local size = style.buttonSize or ST.BUTTON_SIZE
                style.iconWidth = style.iconWidth or size
                style.iconHeight = style.iconHeight or size
            end
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- The note belongs to the label, so it hangs off badgeAnchor like a badge
    -- would. Label + note runs ~230px inside a ~360px cell, so it can reach a
    -- little past the control column's left edge - harmless here because the
    -- control is a 24px checkbox pinned to the cell's far right. Do not copy
    -- this onto a slider row, whose track starts at that same edge.
    if group.masqueEnabled then
        local masqueLabel = squareRow.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        masqueLabel:SetPoint("LEFT", squareRow.badgeAnchor, "RIGHT", 8, 0)
        masqueLabel:SetText("|cff00ff00(Masque skinning is active)|r")
        table.insert(appearanceTabElements, masqueLabel)
    end

    -- Size sliders — always visible
    if style.maintainAspectRatio then
        local sizeRow = AddSliderRow(iconLeft, {
            label = "Button Size",
            min = 10, max = 150, step = 0.1,
            value = style.buttonSize or ST.BUTTON_SIZE,
            disabled = panelOnlyInert,
        })
        WireMirrorFirstSlider(sizeRow, function(val)
            style.buttonSize = val
        end, nil, nil, style, "buttonSize")
    else
        local wRow = AddSliderRow(iconLeft, {
            label = "Icon Width",
            min = 10, max = 150, step = 0.1,
            value = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE,
            disabled = panelOnlyInert,
        })
        WireMirrorFirstSlider(wRow, function(val)
            style.iconWidth = val
        end, nil, nil, style, "iconWidth")

        local hRow = AddSliderRow(iconLeft, {
            label = "Icon Height",
            min = 10, max = 150, step = 0.1,
            value = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE,
            disabled = panelOnlyInert,
        })
        WireMirrorFirstSlider(hRow, function(val)
            style.iconHeight = val
        end, nil, nil, style, "iconHeight")
    end

    -- Closed BEFORE the zoom row goes in. An inert range covers the children
    -- already in the column, and Icon Zoom is not one of the panel's own
    -- settings: it is an override section that follows the lens like any other.
    if iconLeftInertMark then
        ApplyInertRange(iconLeft, iconLeftInertMark)
    end

    -- Icon Zoom - an override section living inside a panel-only one. The
    -- shared builder reads and writes one table, so it is handed the section's
    -- WRITE table where there is one and the lens' detached snapshot where
    -- there is not (an inert row is disabled, and a write into the snapshot
    -- would go nowhere anyway).
    local _, zoomRead, zoomWrite = ResolveLensSection(lens, group, "iconZoom")
    local zoomInertMark = (zoomWrite == nil) and MarkInertRange(iconLeft) or nil

    local zoomRow = ST._BuildIconZoomControls(iconLeft, zoomWrite or zoomRead, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end, {
        disabled = group.masqueEnabled == true or zoomWrite == nil,
        previewRefresh = function()
            if ST._RefreshButtonsPreviewMirror then
                ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
            end
        end,
    })
    AttachRowScopeChrome(zoomRow, lens, group, "iconZoom")

    if zoomInertMark then
        ApplyInertRange(iconLeft, zoomInertMark)
    end

    local iconRightInertMark = panelOnlyInert and MarkInertRange(iconRight) or nil

    if group.buttons and #group.buttons > 1 then
        local spacingRow = AddSliderRow(iconRight, {
            label = "Button Spacing",
            min = 0, max = 30, step = 0.1,
            value = style.buttonSpacing or ST.BUTTON_SPACING,
            disabled = panelOnlyInert,
        })
        WireMirrorFirstSlider(spacingRow, function(val)
            style.buttonSpacing = val
        end, nil, nil, style, "buttonSpacing")
    end

    -- Compact Mode toggle + advanced (growth direction, max visible buttons).
    -- Its gear is not skipped under an entry lens the way the Text sections'
    -- are: compact mode is group data with no override section, so there is no
    -- second table to bind it to. The inert walk disables and dims it instead,
    -- and an advanced panel left open from before the selection closes itself
    -- on the next refresh (its descriptor context carries selectedButton).
    BuildCompactModeControls(iconRight, group, tabInfoButtons)

    if iconRightInertMark then
        ApplyInertRange(iconRight, iconRightInertMark)
    end
    end -- not iconSettingsCollapsed

    -- ================================================================
    -- Text (the optional text drawn on top of the icons)
    -- ================================================================
    local textHeading, textCollapsed = BuildCollapsibleSection(container, "Text", "appearance_text", nil, nil, ROW_SECTION)

    if not textCollapsed then
    -- LEFT column: the text every group can show (cooldown, count).
    -- RIGHT column: the conditional text (aura, keybind). The aura rows are
    -- gated on the group tracking an aura, so this column can run short - the
    -- grid top-aligns its columns, so a short side just ends early.
    local textLeft, textRight = BeginRowGrid(container)

    -- Each of the five sections below resolves its own scope against the lens.
    -- The write table is the whole gate: nil means the section is INERT, so its
    -- rows go in read-only, it builds no gear, and no callback of its own can
    -- reach a saved table. The scope chrome is attached LAST on the row (after
    -- the gear, after any info button, after the row's disabled state is
    -- final), because it is the one control that stays live in an inert
    -- section - the way back out of it.

    -- Show Cooldown Text toggle
    local cdTextScope, cdTextRead, cdTextWrite = ResolveLensSection(lens, group, "cooldownText")
    local cdTextInertMark = (cdTextWrite == nil) and MarkInertRange(textLeft) or nil

    local cdTextRow = AddCheckboxRow(textLeft, {
        label = "Show Cooldown Text",
        value = cdTextRead.showCooldownText or false,
        disabled = cdTextWrite == nil,
        onChange = function(val)
            if not cdTextWrite then return end
            cdTextWrite.showCooldownText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if cdTextWrite then
        -- Panel scope hands the descriptor NO table, so it keeps resolving the
        -- live group style itself (see the factory's note). An entry's override
        -- store has no such resolver, so that one is handed over explicitly.
        local cdTextAdvanced = MakeCooldownTextAdvancedDescriptor(
            cdTextScope == "customized" and cdTextWrite or nil)

        AddAdvancedToggle(cdTextRow, cdTextAdvanced.settingKey, tabInfoButtons, cdTextRead.showCooldownText, {
            title = cdTextAdvanced.title,
            build = cdTextAdvanced.build,
        })
    end
    AttachRowScopeChrome(cdTextRow, lens, group, "cooldownText")

    -- Duration Format — an indented child of Show Cooldown Text.
    --
    -- Never shown once an entry OWNS this section: the format is not one of the
    -- section's keys, so an override would store a key revert could not clear.
    -- The bars tab draws it the same way (BarModeTabs.lua).
    if cdTextScope ~= "customized" and cdTextRead.showCooldownText and CooldownCompanion.GetDurationFormatOptions then
        local formatOptions, formatOrder = CooldownCompanion:GetDurationFormatOptions()
        AddDropdownRow(textLeft, {
            label = "Duration Format",
            indent = true,
            disabled = cdTextWrite == nil,
            list = formatOptions,
            order = formatOrder,
            value = CooldownCompanion.GetDurationFormat(cdTextRead),
            onChange = function(val)
                if not cdTextWrite then return end
                cdTextWrite.durationFormat = CooldownCompanion.NormalizeDurationFormat(val)
                cdTextWrite.decimalTimers = nil
                refreshStyle()
            end,
        })
    end

    if cdTextInertMark then
        ApplyInertRange(textLeft, cdTextInertMark)
    end

    -- Show Charge Text toggle
    local _, chargeRead, chargeWrite = ResolveLensSection(lens, group, "chargeText")
    local chargeInertMark = (chargeWrite == nil) and MarkInertRange(textLeft) or nil

    local chargeTextRow = AddCheckboxRow(textLeft, {
        label = "Show Count Text (Charges/Uses)",
        value = chargeRead.showChargeText ~= false,
        disabled = chargeWrite == nil,
        onChange = function(val)
            if not chargeWrite then return end
            chargeWrite.showChargeText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- every builder runs with { row = true } and no rightColumn.
    --
    -- The three count colors are the panel's longest labels. They end in a 19px
    -- swatch, which is the narrow control the row grammar reserves long labels
    -- for, and each states itself on hover so a narrower config column cannot
    -- silently swallow which charge state it names.
    --
    -- deferCommit is deliberately absent throughout, matching the
    -- stock color pickers these rows replaced.
    --
    -- The panel captures the section's WRITE table, which is the group style or
    -- the selected entry's override store depending on scope. Only built while
    -- there is one: an inert section has no gear to open it from.
    local function BuildChargeTextAdvanced(panel)
        AddFontControls(panel, chargeWrite, "charge", { size = 12 }, refreshStyle, { row = true })

        local function ChargeColorRow(rowLabel, key)
            AddColorRow(panel, {
                label = rowLabel,
                tooltip = { rowLabel },
                tbl = chargeWrite,
                key = key,
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
        end
        ChargeColorRow("Font Color (Max Charges)", "chargeFontColor")
        ChargeColorRow("Font Color (Missing Charges)", "chargeFontColorMissing")
        ChargeColorRow("Font Color (Zero Charges)", "chargeFontColorZero")

        AddAnchorDropdown(panel, chargeWrite, "chargeAnchor", "BOTTOMRIGHT", refreshStyle, nil, { row = true })
        AddOffsetSliders(panel, chargeWrite, "chargeXOffset", "chargeYOffset", { x = -2, y = 2 }, refreshStyle, { row = true })
    end

    if chargeWrite then
        AddAdvancedToggle(chargeTextRow, "chargeText", tabInfoButtons, chargeRead.showChargeText ~= false, {
            title = "Count Text Advanced",
            build = BuildChargeTextAdvanced,
        })
    end
    AttachRowScopeChrome(chargeTextRow, lens, group, "chargeText")

    if chargeInertMark then
        ApplyInertRange(textLeft, chargeInertMark)
    end

    -- Aura text sections (shown only while the group has an aura-tracking entry)
    if groupHasAuraEntry then
        -- Show Aura Duration Text toggle
        local _, auraTextRead, auraTextWrite = ResolveLensSection(lens, group, "auraText")
        local auraTextInertMark = (auraTextWrite == nil) and MarkInertRange(textRight) or nil

        local auraTextRow = AddCheckboxRow(textRight, {
            label = "Show Aura Duration Text",
            value = auraTextRead.showAuraText ~= false,
            disabled = auraTextWrite == nil,
            onChange = function(val)
                if not auraTextWrite then return end
                auraTextWrite.showAuraText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): every builder runs with
        -- { row = true } and no rightColumn, and the position rows the separate
        -- -positions toggle owns indent as its children.
        local function BuildAuraDurationTextAdvanced(panel)
            AddFontControls(panel, auraTextWrite, "auraText", { size = 12 }, refreshStyle, { row = true })

            -- deferCommit is deliberately absent, matching the stock color picker
            -- this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = auraTextWrite,
                key = "auraTextFontColor",
                default = {0, 0.925, 1, 1},
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })

            local sepPosRow = AddCheckboxRow(panel, {
                label = "Separate Text Positions",
                value = auraTextWrite.separateTextPositions or false,
                onChange = function(val)
                    auraTextWrite.separateTextPositions = val
                    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                    -- Rebuilds THIS panel, not the whole config, which is what
                    -- makes the two position rows appear in place.
                    RefreshActiveAdvancedSettingsPanel()
                end,
            })
            -- Anchor args are a placeholder - AnchorRowBadge re-points the
            -- button onto the end of the row's label.
            AnchorRowBadge(sepPosRow, CreateInfoButton(sepPosRow.frame, sepPosRow.frame, "LEFT", "LEFT", 0, 0, {
                "Separate Text Positions",
                {"Gives the aura duration text and the cooldown text independent positions.", 1, 1, 1, true},
                " ",
                {"The cooldown text also draws above the aura display, so both timers stay visible while the aura runs.", 1, 1, 1, true},
            }, sepPosRow))

            if auraTextWrite.separateTextPositions then
                AddAnchorDropdown(panel, auraTextWrite, "auraTextAnchor", "TOPLEFT", refreshStyle, nil, { row = true, indent = true })
                AddOffsetSliders(panel, auraTextWrite, "auraTextXOffset", "auraTextYOffset", { x = 2, y = -2 }, refreshStyle, { row = true, indent = true })
            end
        end

        if auraTextWrite then
            AddAdvancedToggle(auraTextRow, "auraText", tabInfoButtons, auraTextRead.showAuraText ~= false, {
                title = "Aura Duration Text Advanced",
                build = BuildAuraDurationTextAdvanced,
            })
        end
        -- Second badge in the chain: gear, then this, then the scope chrome the
        -- lens attaches last. The anchor args below are a placeholder -
        -- AnchorRowBadge re-points the button onto the end of the chain.
        local auraPosInfo = AnchorRowBadge(auraTextRow, CreateInfoButton(auraTextRow.frame, auraTextRow.frame, "LEFT", "LEFT", 0, 0, {
            "Shared Position",
            {"Position is shared with Cooldown Text by default. Enable 'Separate Text Positions' in advanced settings to use independent positions.", 1, 1, 1, true},
        }, auraTextRow))
        if auraTextRead.showAuraText == false then
            auraPosInfo:Hide()
        end
        AttachRowScopeChrome(auraTextRow, lens, group, "auraText")

        if auraTextInertMark then
            ApplyInertRange(textRight, auraTextInertMark)
        end

        -- Show Aura Stack Text toggle
        local _, auraStackRead, auraStackWrite = ResolveLensSection(lens, group, "auraStackText")
        local auraStackInertMark = (auraStackWrite == nil) and MarkInertRange(textRight) or nil

        local auraStackRow = AddCheckboxRow(textRight, {
            label = "Show Aura Stack Text",
            value = auraStackRead.showAuraStackText ~= false,
            disabled = auraStackWrite == nil,
            onChange = function(val)
                if not auraStackWrite then return end
                auraStackWrite.showAuraStackText = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
        local function BuildAuraStackTextAdvanced(panel)
            AddFontControls(panel, auraStackWrite, "auraStack", { size = 12 }, refreshStyle, { row = true })
            -- deferCommit is deliberately absent, matching the stock color picker
            -- this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = auraStackWrite,
                key = "auraStackFontColor",
                default = {1, 1, 1, 1},
                hasAlpha = true,
                onConfirm = refreshStyle,
                onChange = refreshStyle,
            })
            AddAnchorDropdown(panel, auraStackWrite, "auraStackAnchor", "BOTTOMLEFT", refreshStyle, nil, { row = true })
            AddOffsetSliders(panel, auraStackWrite, "auraStackXOffset", "auraStackYOffset", { x = 2, y = 2 }, refreshStyle, { row = true })
        end

        if auraStackWrite then
            AddAdvancedToggle(auraStackRow, "auraStackText", tabInfoButtons, auraStackRead.showAuraStackText ~= false, {
                title = "Aura Stack Text Advanced",
                build = BuildAuraStackTextAdvanced,
            })
        end
        AttachRowScopeChrome(auraStackRow, lens, group, "auraStackText")

        if auraStackInertMark then
            ApplyInertRange(textRight, auraStackInertMark)
        end
    end

    -- Show Keybind/Custom Text toggle
    local _, kbRead, kbWrite = ResolveLensSection(lens, group, "keybindText")
    local kbInertMark = (kbWrite == nil) and MarkInertRange(textRight) or nil

    local kbRow = AddCheckboxRow(textRight, {
        label = KEYBIND_CUSTOM_LABEL,
        value = kbRead.showKeybindText or false,
        disabled = kbWrite == nil,
        onChange = function(val)
            if not kbWrite then return end
            kbWrite.showKeybindText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): row mode, no rightColumn.
    local function BuildKeybindTextAdvanced(panel)
        -- Keybind uses a hardcoded 4-point anchor (not the full 9-point list),
        -- so this is a dropdown row of its own rather than AddAnchorDropdown.
        AddDropdownRow(panel, {
            label = "Anchor",
            list = {
                TOPRIGHT = "Top Right",
                TOPLEFT = "Top Left",
                BOTTOMRIGHT = "Bottom Right",
                BOTTOMLEFT = "Bottom Left",
            },
            value = kbWrite.keybindAnchor or "TOPRIGHT",
            onChange = function(val)
                kbWrite.keybindAnchor = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end,
        })

        AddOffsetSliders(panel, kbWrite, "keybindXOffset", "keybindYOffset", { x = -2, y = -2 }, refreshStyle, { row = true })
        AddFontControls(panel, kbWrite, "keybind", { size = 10, sizeMin = 6, sizeMax = 24 }, refreshStyle, { row = true })
        -- deferCommit is deliberately absent, matching the stock color picker
        -- this row replaced.
        AddColorRow(panel, {
            label = "Font Color",
            tbl = kbWrite,
            key = "keybindFontColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = refreshStyle,
            onChange = refreshStyle,
        })
    end

    if kbWrite then
        AddAdvancedToggle(kbRow, "keybindText", tabInfoButtons, kbRead.showKeybindText, {
            title = KEYBIND_CUSTOM_LABEL .. " Advanced",
            build = BuildKeybindTextAdvanced,
        })
    end
    -- The gear is already chained off the label; this info button lands to its
    -- right, and the lens' scope chrome after that. Anchor args are a placeholder.
    AnchorRowBadge(kbRow, CreateInfoButton(kbRow.frame, kbRow.frame, "LEFT", "LEFT", 0, 0, KEYBIND_CUSTOM_TOOLTIP, kbRow))
    AttachRowScopeChrome(kbRow, lens, group, "keybindText")

    if kbInertMark then
        ApplyInertRange(textRight, kbInertMark)
    end
    end -- not textCollapsed

    -- ================================================================
    -- Border
    -- ================================================================
    local borderHeading, borderCollapsed = BuildCollapsibleSection(container, "Border", "appearance_border", nil, nil, ROW_SECTION)
    -- The lens' section scope: with an entry selected the heading says whose
    -- border this is and offers the one action that changes that.
    local _, borderRead, borderWrite = ResolveLensSection(lens, group, "borderSettings")
    AttachHeadingScopeChrome(borderHeading, lens, group, "borderSettings")

    if not borderCollapsed then
    -- Three related rows, so they stay in one column rather than splitting a
    -- parent from its children. The right column is deliberately empty.
    local borderLeft = BeginRowGrid(container)

    local borderInertMark = (borderWrite == nil) and MarkInertRange(borderLeft) or nil

    -- Masque gating stays on the GROUP flag, not the lens: skinning owns the
    -- border art for the whole panel, and no entry can override that.
    --
    -- Border Color owns the section; thickness and size are its children.
    AddColorRow(borderLeft, {
        label = "Border Color",
        tbl = borderWrite or borderRead,
        key = "borderColor",
        default = {0, 0, 0, 1},
        hasAlpha = true,
        disabled = borderWrite == nil or group.masqueEnabled == true,
        onConfirm = refreshStyle,
        onChange = refreshStyle,
    })

    local renderMode = AddBorderRenderModeDropdown(borderLeft, borderWrite or borderRead, "borderRenderMode", function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end, group.masqueEnabled or borderWrite == nil, { row = true, indent = true })
    local borderThicknessLocked = group.masqueEnabled or ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSizeRow = AddSliderRow(borderLeft, {
            label = "Border Size",
            indent = true,
            min = 0, max = 5, step = 0.1,
            value = borderRead.borderSize or ST.DEFAULT_BORDER_SIZE,
            disabled = (borderWrite == nil or borderThicknessLocked) and true or false,
        })
        -- Not wired at all while the section is inert. The mirror-first path
        -- SNAPSHOTS AND RESTORES its state owner on every drag tick, so wiring
        -- it to anything is wiring a write path; the read-only lens has no
        -- table for one, so it gets no wiring instead of a harmless-looking one.
        if borderWrite then
            WireMirrorFirstSlider(borderSizeRow, function(val)
                if borderThicknessLocked then return end
                borderWrite.borderSize = val
            end, function()
                if borderThicknessLocked then return end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end, nil, borderWrite, "borderSize")
        end
    end

    if borderInertMark then
        ApplyInertRange(borderLeft, borderInertMark)
    end
    end -- not borderCollapsed

    -- ================================================================
    -- Icon Tint
    -- ================================================================
    local iconTintHeading, iconTintCollapsed = BuildCollapsibleSection(container, "Icon Tint", "appearance_iconTint", nil, nil, ROW_SECTION)
    local _, tintRead, tintWrite = ResolveLensSection(lens, group, "iconTint")

    local iconTintTooltip = {
        "Icon Tint",
        {"Recolor or fade icons without affecting cooldown text, glows, or borders.", 1, 1, 1, true},
        " ",
        {"Base Icon Color:", 1, 0.82, 0},
        {"The default color for your icons. Lower the alpha to make icons semi-transparent while everything else stays visible.", 1, 1, 1, true},
        " ",
        {"Cooldown Tint:", 1, 0.82, 0},
        {"A separate color used only while an ability is on cooldown. Great for dimming icons on cooldown while keeping ready abilities bright.", 1, 1, 1, true},
        " ",
        {"Unusable Dim Color:", 1, 0.82, 0},
        {"A color applied when an ability is not usable and Unusable Visual uses dimming in the Indicators tab.", 1, 1, 1, true},
    }
    if groupHasAuraEntry then
        table.insert(iconTintTooltip, " ")
        table.insert(iconTintTooltip, {"Aura Tint:", 1, 0.82, 0})
        table.insert(iconTintTooltip, {"A separate color used only while a tracked aura is active.", 1, 1, 1, true})
    end
    -- The (?) badge chains off the heading label, and the lens' scope chrome
    -- lands after it: label -> (?) -> scope. Chaining also keeps the fading
    -- rule behind whichever decoration ends up last.
    ChainHeadingBadges(iconTintHeading, CreateInfoButton(iconTintHeading.frame,
        iconTintHeading.label, "LEFT", "RIGHT", 4, 0, iconTintTooltip, tabInfoButtons))

    AttachHeadingScopeChrome(iconTintHeading, lens, group, "iconTint")

    if not iconTintCollapsed then
        local tintRefresh = function()
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end

        -- LEFT column: the always-on colors plus the cooldown tint pair.
        -- RIGHT column: the conditional state tints.
        local tintLeft, tintRight = BeginRowGrid(container)

        -- Both columns bracket separately: an inert range is a contiguous slice
        -- of ONE column's children, and this section fills two. The right
        -- column's bracket is taken further down, after the Unusable Dim
        -- Color row: that row belongs to another section and must not be
        -- gated by this one's scope.
        local tintLeftInertMark = (tintWrite == nil) and MarkInertRange(tintLeft) or nil
        -- A color row binds its picker to one table for both reading and
        -- writing, so it gets the write table where the section has one and the
        -- lens' detached snapshot where it does not.
        local tintTbl = tintWrite or tintRead

        AddColorRow(tintLeft, {
            label = "Base Icon Color",
            tbl = tintTbl, key = "iconTintColor",
            default = {1, 1, 1, 1}, hasAlpha = true,
            disabled = tintWrite == nil,
            onConfirm = tintRefresh, onChange = tintRefresh,
        })

        AddColorRow(tintLeft, {
            label = "Background Color",
            tbl = tintTbl, key = "backgroundColor",
            default = {0, 0, 0, 0.5}, hasAlpha = true,
            disabled = tintWrite == nil,
            onConfirm = tintRefresh, onChange = tintRefresh,
        })

        AddCheckboxRow(tintLeft, {
            label = "Use Separate Cooldown Tint",
            value = tintRead.iconCooldownTintEnabled or false,
            disabled = tintWrite == nil,
            onChange = function(val)
                if not tintWrite then return end
                tintWrite.iconCooldownTintEnabled = val
                tintRefresh()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if tintRead.iconCooldownTintEnabled then
            AddColorRow(tintLeft, {
                label = "Cooldown Icon Color",
                indent = true,
                tbl = tintTbl, key = "iconCooldownTintColor",
                default = {1, 0, 0.102, 1}, hasAlpha = true,
                disabled = tintWrite == nil,
                onConfirm = tintRefresh, onChange = tintRefresh,
            })
        end

        -- Unusable Dim Color is an Unusable Visual key (ST.OVERRIDE_SECTIONS
        -- lists iconUnusableTintColor under unusableDimming), shown here only
        -- because it reads as one of the icon's tints. So it resolves and
        -- follows THAT section's scope silently - writing it through Icon
        -- Tint's store would leave a key Icon Tint's revert cannot clear. Its
        -- chrome lives on the Indicators tab's Unusable Visual row; the
        -- lens-resolved read decides whether the dim mode has it on show.
        local _, dimRead, dimWrite = ResolveLensSection(lens, group, "unusableDimming")
        if dimRead.showUnusable and ST.UnusableVisualUsesDimTint(dimRead) then
            AddColorRow(tintRight, {
                label = "Unusable Dim Color",
                tbl = dimWrite or dimRead, key = "iconUnusableTintColor",
                default = {0.4, 0.4, 0.4, 1}, hasAlpha = true,
                disabled = dimWrite == nil,
                onConfirm = tintRefresh, onChange = tintRefresh,
            })
        end

        -- Taken AFTER the dim row so the Icon Tint bracket never reaches a row
        -- another section owns; everything below is this section's own.
        local tintRightInertMark = (tintWrite == nil) and MarkInertRange(tintRight) or nil

        -- Aura tint applies to the slot-kit aura layer (consumed at bind time
        -- by AuraDisplay.StyleSlotKit); only offered where an aura display
        -- exists.
        if groupHasAuraEntry then
            AddCheckboxRow(tintRight, {
                label = "Use Separate Aura Tint",
                value = tintRead.iconAuraTintEnabled or false,
                disabled = tintWrite == nil,
                onChange = function(val)
                    if not tintWrite then return end
                    tintWrite.iconAuraTintEnabled = val
                    tintRefresh()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })

            if tintRead.iconAuraTintEnabled then
                AddColorRow(tintRight, {
                    label = "Aura Active Icon Color",
                    indent = true,
                    tbl = tintTbl, key = "iconAuraTintColor",
                    default = {0, 0.925, 1, 1}, hasAlpha = true,
                    disabled = tintWrite == nil,
                    onConfirm = tintRefresh, onChange = tintRefresh,
                })
            end
        end

        -- The right column runs 2-3 rows short of the left one, so the section
        -- action fills its empty tail instead of hanging off the bottom of the
        -- grid. No wrapper needed: SetAutoWidth leaves widget.width nil, so the
        -- column's List layout neither stretches nor right-anchors it and it
        -- sits flush left under the last row.
        --
        -- Not built at all while the section is inert: a section with nowhere
        -- to write has no defaults to restore, and a greyed-out button under a
        -- read-only section is one more thing to explain.
        if tintWrite then
            local resetTintBtn = AceGUI:Create("Button")
            resetTintBtn:SetText("Reset Colors to Default")
            resetTintBtn:SetAutoWidth(true)
            resetTintBtn:SetCallback("OnClick", function()
                tintWrite.iconTintColor = {1, 1, 1, 1}
                tintWrite.iconCooldownTintColor = {1, 0, 0.102, 1}
                tintWrite.iconAuraTintColor = {0, 0.925, 1, 1}
                tintWrite.backgroundColor = {0, 0, 0, 0.5}
                -- The dim color is Unusable Visual's key, so it resets through
                -- that section's own write table - and only while it has one,
                -- never into a store that section does not own.
                if dimWrite then
                    dimWrite.iconUnusableTintColor = {0.4, 0.4, 0.4, 1}
                end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            tintRight:AddChild(resetTintBtn)
        end

        if tintLeftInertMark then
            ApplyInertRange(tintLeft, tintLeftInertMark)
        end
        if tintRightInertMark then
            ApplyInertRange(tintRight, tintRightInertMark)
        end
    end -- not iconTintCollapsed

    -- ================================================================
    -- Masque skinning (icon-only)
    -- ================================================================
    if CooldownCompanion.Masque then
        local masqueHeading, masqueCollapsed = BuildCollapsibleSection(container, "Masque", "appearance_masque", nil, nil, ROW_SECTION)
        -- Panel-only (sectionId nil): skinning is switched on for the whole
        -- panel, and there is no per-entry form of it to offer.
        AttachHeadingScopeChrome(masqueHeading, lens, group, nil)

        if not masqueCollapsed then
        -- One setting; the right column stays empty.
        local masqueLeft = BeginRowGrid(container)

        local masqueInertMark = panelOnlyInert and MarkInertRange(masqueLeft) or nil

        local masqueRow = AddCheckboxRow(masqueLeft, {
            label = "Enable Masque Skinning",
            value = group.masqueEnabled or false,
            disabled = panelOnlyInert,
            onChange = function(val)
                CooldownCompanion:ToggleGroupMasque(CS.selectedGroup, val)
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        -- Anchor args are a placeholder: AnchorRowBadge re-points the button
        -- onto the end of the label's badge chain.
        AnchorRowBadge(masqueRow, CreateInfoButton(masqueRow.frame, masqueRow.frame, "LEFT", "LEFT", 0, 0, {
            "Masque Skinning",
            {"Uses the Masque addon to apply custom button skins to this group. Configure skins via /masque or the Masque config panel.", 1, 1, 1, true},
            " ",
            {"Overridden Settings:", 1, 0.82, 0},
            {"Border Thickness, Border Size, Border Color, Square Icons (forced on)", 0.7, 0.7, 0.7, true},
        }, tabInfoButtons))

        if masqueInertMark then
            ApplyInertRange(masqueLeft, masqueInertMark)
        end
        end -- not masqueCollapsed
    end

    BuildGroupSettingPresetControls(container, group, "icons", tabInfoButtons)

    -- Inert-section sweep, over BOTH icons gear maps. A section the lens
    -- resolved read-only builds no gear, so nothing rebound or closed an
    -- advanced panel that was already open on that gear - and its controls
    -- still write to the table the PREVIOUS build handed them. Close those here.
    --
    -- Scope-driven, not collapse-driven: a collapsed section builds no gear
    -- either, and a panel left over from before an entry was selected is just
    -- as live behind a closed section as behind an open one.
    --
    -- Both maps, not just this tab's: only one panel tab is ever built at a
    -- time, so a stale panel whose gear lives on the icons Indicators tab is
    -- just as live from here as one of this tab's own. See the twin sweep at
    -- the foot of BuildEffectsTab.
    if CS.CloseAdvancedSettingsPanel then
        local gearMaps = { ST._APPEARANCE_SECTION_BY_ADVANCED_KEY, ST._INDICATORS_OVERRIDE_SECTION_BY_ADVANCED_KEY }
        for i = 1, #gearMaps do
            for advancedKey, sectionId in pairs(gearMaps[i]) do
                local _, _, sectionWrite = ResolveLensSection(lens, group, sectionId)
                if sectionWrite == nil then
                    CS.CloseAdvancedSettingsPanel({ settingKey = advancedKey })
                end
            end
        end
    end
end

------------------------------------------------------------------------
-- CONTAINER TAB BUILDERS (for Group settings in the workspace)
------------------------------------------------------------------------

local function BuildContainerGeneralTab(scroll, containerId)
    -- Function-local, not an upvalue: see the note by the row-grammar imports
    -- at the top of this file.
    local BeginRowGrid = ST._BeginRowGrid

    local db = CooldownCompanion.db.profile
    local container = db.groupContainers and db.groupContainers[containerId]
    if not container then return end

    local function RefreshPanels()
        CooldownCompanion:RefreshContainerPanels(containerId)
    end

    -- Row grammar (RowWidgets.lua). The two master switches lead the tab with
    -- no header of their own: they are what the whole group IS, not one aspect
    -- of it, and every section below them is a facet they gate. Everything
    -- else is a collapsible row-grammar section. Nothing here carries an
    -- advanced gear, so there is no queued advanced key to keep uncollapsed.
    local masterLeft, masterRight = BeginRowGrid(scroll)

    AddCheckboxRow(masterLeft, {
        label = "Enabled",
        value = container.enabled ~= false,
        onChange = function(value)
            container.enabled = value
            RefreshPanels()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    AddCheckboxRow(masterRight, {
        label = "Locked",
        value = container.locked ~= false,
        onChange = function(value)
            CooldownCompanion:SetContainerLocked(containerId, value)
            CooldownCompanion:RefreshConfigPanel()
            if not value and ST.CollapseConfigForUnlock then
                ST.CollapseConfigForUnlock()
            elseif value then
                CooldownCompanion:CheckArrangeModeAutoExit()
            end
        end,
    })

    -- ================================================================
    -- Layout
    -- ================================================================
    local _, layoutCollapsed = BuildCollapsibleSection(scroll, "Layout", "container_layout", nil, nil, ROW_SECTION)

    if not layoutCollapsed then
        container.anchor = CooldownCompanion:NormalizeContainerAnchor(container.anchor)
        local committedOffsets = {
            x = tonumber(container.anchor.x) or 0,
            y = tonumber(container.anchor.y) or 0,
        }
        local function ApplyContainerOffset(axis, value)
            local oldValue = committedOffsets[axis] or 0
            container.anchor[axis] = value
            committedOffsets[axis] = value

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

        -- One offset each side: the pair is the whole section, so splitting it
        -- across the grid keeps both columns populated.
        local layoutLeft, layoutRight = BeginRowGrid(scroll)

        AddSliderRow(layoutLeft, {
            label = "X Offset",
            min = -2000, max = 2000, step = 0.1,
            value = container.anchor.x or 0,
            onRelease = function(val)
                ApplyContainerOffset("x", val)
            end,
        })

        AddSliderRow(layoutRight, {
            label = "Y Offset",
            min = -2000, max = 2000, step = 0.1,
            value = container.anchor.y or 0,
            onRelease = function(val)
                ApplyContainerOffset("y", val)
            end,
        })
    end -- if not layoutCollapsed

    -- ================================================================
    -- Group Alpha
    -- ================================================================
    local _, alphaCollapsed = BuildCollapsibleSection(scroll, "Group Alpha", "container_alpha", nil, nil, ROW_SECTION)

    if not alphaCollapsed then
        local function RefreshContainerAlphaSettings()
            RefreshPanels()
            CooldownCompanion:RefreshConfigPanel()
        end

        -- The switch that gates everything else in this section, in a grid of
        -- its own so the alpha builder below can open its own two columns.
        local switchLeft = BeginRowGrid(scroll)

        local groupAlphaRow = AddCheckboxRow(switchLeft, {
            label = "Enable Group Alpha",
            value = container.groupAlphaEnabled == true,
            onChange = function(value)
                container.groupAlphaEnabled = value == true
                if CooldownCompanion.RefreshAlphaUpdateDriver then
                    CooldownCompanion:RefreshAlphaUpdateDriver()
                end
                RefreshContainerAlphaSettings()
            end,
        })

        -- Anchor args are a placeholder: AnchorRowBadge re-points the button
        -- onto the end of the label's badge chain.
        AnchorRowBadge(groupAlphaRow, CreateInfoButton(groupAlphaRow.frame, groupAlphaRow.frame, "LEFT", "LEFT", 0, 0, {
            "Group Alpha",
            {"When enabled, applies these alpha settings to panels anchored directly to this group. Panels anchored elsewhere keep their own alpha behavior.", 1, 1, 1, true},
        }, tabInfoButtons))

        if container.groupAlphaEnabled == true then
            BuildAlphaControls(scroll, container, RefreshContainerAlphaSettings, nil, {
                row = true,
                isGlobal = container.isGlobal,
                hideHeading = true,
                onBaselineCommitted = function(val)
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
    local _, strataCollapsed = BuildCollapsibleSection(scroll, "Frame Strata", "container_strata", nil, nil, ROW_SECTION)

    if not strataCollapsed then
    -- One setting; the right column stays empty.
    local strataLeft = BeginRowGrid(scroll)

    AddDropdownRow(strataLeft, {
        label = "Container Frame Strata",
        list = {
            BACKGROUND = "Background",
            LOW = "Low",
            MEDIUM = "Medium (Default)",
            HIGH = "High",
        },
        order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" },
        value = container.frameStrata or "MEDIUM",
        onChange = function(value)
            container.frameStrata = value
            local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
            if containerFrame then
                containerFrame:SetFrameStrata(value)
            end
            RefreshPanels()
        end,
    })
    end -- if not strataCollapsed
end

local function BuildContainerLoadConditionsTab(scroll, containerId)
    -- Function-local, not an upvalue: see the note by the row-grammar imports
    -- at the top of this file.
    local BeginRowGrid = ST._BeginRowGrid

    local db = CooldownCompanion.db.profile
    local container = db.groupContainers and db.groupContainers[containerId]
    if not container then return end

    local function RefreshPanels()
        CooldownCompanion:RefreshContainerPanels(containerId)
    end
    local inheritedSources = CooldownCompanion:GetInheritedLoadConditionSources(container)
    local function RefreshContainerLoadConditions()
        RefreshPanels()
        CooldownCompanion:RefreshConfigPanel()
    end

    -- Two halves, same shape as the panel tab: who the group is for, then
    -- where it stays hidden. Groups sit at the top of the inheritance chain,
    -- so there is never an inherited summary to lead with. Row grammar
    -- throughout, and nothing here carries a gear, so there is no
    -- advanced-panel queue to keep uncollapsed.
    local _, whoCollapsed = BuildCollapsibleSection(scroll, "Who Can Use This",
        "container_loadconditions_who", nil, nil, ROW_SECTION)

    if not whoCollapsed then
        local eligibilityOpts = {
            target = container,
            inheritedSources = inheritedSources,
            eligibilitySubjectLabel = "group",
            allowClassEligibility = container.isGlobal == true,
            ownerCharKey = container.createdBy,
            omitHeading = true,
            showSelectedRows = true,
            onChanged = RefreshContainerLoadConditions,
        }

        -- Same split as the panel tab: person on the left, class/spec/hero
        -- chain on the right, each picker carrying its own selections.
        local whoLeft, whoRight = BeginRowGrid(scroll)
        AddCharacterEligibilityControls(whoLeft, eligibilityOpts)
        AddClassSpecEligibilityControls(whoRight, eligibilityOpts)

        local hasOwnSpecs = (type(container.specs) == "table" and next(container.specs) ~= nil)
            or (type(container.loadConditions) == "table"
                and type(container.loadConditions.specAllowlist) == "table"
                and next(container.loadConditions.specAllowlist) ~= nil)
            or (type(container.heroTalents) == "table" and next(container.heroTalents) ~= nil)
        if hasOwnSpecs then
            -- Compact and inside the grid. It clears exactly what the right
            -- column holds, so it sits at that column's tail even though the
            -- left one is usually shorter - meaning wins over balance for a
            -- control this destructive.
            local clearBtn = AceGUI:Create("Button")
            clearBtn:SetText("Clear All Spec Filters")
            clearBtn:SetAutoWidth(true)
            clearBtn:SetCallback("OnClick", function()
                container.specs = nil
                if type(container.loadConditions) == "table" then
                    container.loadConditions.specAllowlist = nil
                end
                container.heroTalents = nil
                RefreshPanels()
                CooldownCompanion:RefreshConfigPanel()
            end)
            whoRight:AddChild(clearBtn)
        end
    end -- not whoCollapsed

    AddScopedLoadConditionToggles(scroll, {
        target = container,
        defaults = CooldownCompanion:GetDefaultLoadConditions(),
        inheritedSources = inheritedSources,
        skipInheritedSummary = true,
        headingText = "Where To Hide It",
        localCollapsedKey = "container_loadconditions_local",
        row = true,
        infoTooltipLines = BuildWhereToHideTooltip("group", true),
        infoButtons = tabInfoButtons,
        onChanged = RefreshContainerLoadConditions,
    })
end

-- Expose for Config.lua
ST._BuildLayoutTab = BuildLayoutTab
ST._BuildAppearanceTab = BuildAppearanceTab
ST._BuildEffectsTab = BuildEffectsTab
ST._BuildContainerGeneralTab = BuildContainerGeneralTab
ST._BuildContainerLoadConditionsTab = BuildContainerLoadConditionsTab
