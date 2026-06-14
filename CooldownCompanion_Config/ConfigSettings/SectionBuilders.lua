local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreatePromoteButton = ST._CreatePromoteButton
local CreateRevertButton = ST._CreateRevertButton
local CreateCheckboxPromoteButton = ST._CreateCheckboxPromoteButton
local CreateInfoButton = ST._CreateInfoButton
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown

-- Module-level aliases
local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

------------------------------------------------------------------------
-- REUSABLE SECTION BUILDER FUNCTIONS
------------------------------------------------------------------------
-- Each builder takes (container, styleTable, refreshCallback) and adds
-- AceGUI widgets to the container, reading/writing values from styleTable.

local KEYBIND_CUSTOM_LABEL = "Show Keybind/Custom Text"
local KEYBIND_CUSTOM_TOOLTIP = {
    "Show Keybind/Custom Text",
    {"Shows detected keybind text on icon buttons by default.", 1, 1, 1, true},
    " ",
    {"When enabled for a button, that button's settings can also provide custom text to replace the detected bind until cleared.", 1, 1, 1, true},
}
local function ResolvePreviewOption(value)
    if type(value) == "function" then
        return value()
    end
    return value
end

local function RefreshConfigPanelForPreviewToggle()
    if not CooldownCompanion.RefreshConfigPanel then
        return false
    end

    local wasPreviewRefresh = CS.previewToggleRefreshActive
    CS.previewToggleRefreshActive = true
    CooldownCompanion:RefreshConfigPanel()
    CS.previewToggleRefreshActive = wasPreviewRefresh
    return true
end

local function IsAdvancedSettingsPanelContainer(container)
    return container and container._isAdvancedSettingsPanel == true
end

local ClearActivePreviewBadgeButton

local function RefreshStructuralControls(container)
    if IsAdvancedSettingsPanelContainer(container) and CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    elseif CooldownCompanion.RefreshConfigPanel then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function RefreshPreviewToggleButtons(container)
    local buttons = container and container._previewToggleButtons
    if type(buttons) ~= "table" then
        return
    end

    for _, previewBtn in ipairs(buttons) do
        if previewBtn and previewBtn._isActiveFn and previewBtn._offLabel then
            previewBtn:SetText(previewBtn._isActiveFn() and "Preview: ON" or previewBtn._offLabel)
        end
    end
end

local function RefreshActiveAdvancedPreviewToggleButtons()
    RefreshPreviewToggleButtons({ _previewToggleButtons = CS.advancedSettingsPreviewToggleButtons })
end

local function ApplyOverrideCheckboxIndent(checkbox, opts)
    if opts and opts.isOverride then
        ApplyCheckboxIndent(checkbox, 20)
    end
end

local function AddDurationFormatDropdown(container, settings, refreshCallback, opts)
    if not (container and settings and CooldownCompanion.GetDurationFormatOptions) then
        return nil
    end

    local formatOptions, formatOrder = CooldownCompanion:GetDurationFormatOptions()
    local durationDrop = AceGUI:Create("Dropdown")
    durationDrop:SetLabel("Duration Format")
    durationDrop:SetList(formatOptions, formatOrder)
    durationDrop:SetValue(CooldownCompanion.GetDurationFormat(settings))
    durationDrop:SetFullWidth(true)
    durationDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.durationFormat = CooldownCompanion.NormalizeDurationFormat(val)
        settings.decimalTimers = nil
        if refreshCallback then
            refreshCallback()
        end
    end)
    container:AddChild(durationDrop)
    return durationDrop
end

local function AddPreviewToggleButton(container, offLabel, isActiveFn, setActiveFn)
    if not (container and isActiveFn and setActiveFn) then
        return nil
    end

    local btn = AceGUI:Create("Button")
    btn:SetText(isActiveFn() and "Preview: ON" or offLabel)
    btn:SetFullWidth(true)
    if IsAdvancedSettingsPanelContainer(container) then
        container._previewToggleButtons = container._previewToggleButtons or {}
        CS.advancedSettingsPreviewToggleButtons = container._previewToggleButtons
        btn._isActiveFn = isActiveFn
        btn._offLabel = offLabel
        table.insert(container._previewToggleButtons, btn)
    end
    btn:SetCallback("OnClick", function()
        local showPreview = not isActiveFn()
        if showPreview and CooldownCompanion.ClearAllConfigPreviews then
            CooldownCompanion:ClearAllConfigPreviews()
        elseif not showPreview and ClearActivePreviewBadgeButton then
            ClearActivePreviewBadgeButton()
        end
        setActiveFn(showPreview)
        if IsAdvancedSettingsPanelContainer(container) then
            RefreshPreviewToggleButtons(container)
        elseif not RefreshConfigPanelForPreviewToggle() then
            btn:SetText(isActiveFn() and "Preview: ON" or offLabel)
        end
    end)
    container:AddChild(btn)
    return btn
end

local function SetPreviewBadgeActive(btn, active)
    if btn then
        if not btn._activeHighlight then
            local activeHighlight = btn:CreateTexture(nil, "BACKGROUND")
            activeHighlight:SetPoint("TOPLEFT", -1, 1)
            activeHighlight:SetPoint("BOTTOMRIGHT", 1, -1)
            activeHighlight:SetColorTexture(0.85, 0.65, 0.0, 0.6)
            activeHighlight:Hide()
            btn._activeHighlight = activeHighlight
        end

        if active then
            btn._activeHighlight:Show()
        else
            btn._activeHighlight:Hide()
        end
    end

    if btn and btn._icon then
        if active then
            btn._icon:SetVertexColor(1, 0.82, 0, 1)
        else
            btn._icon:SetVertexColor(0.72, 0.72, 0.72, 0.85)
        end
    end
end

function ClearActivePreviewBadgeButton()
    local btn = CS.activePreviewBadgeButton
    if btn then
        SetPreviewBadgeActive(btn, false)
    end
    CS.activePreviewBadgeButton = nil
end

local function SetActivePreviewBadgeButton(btn, active)
    SetPreviewBadgeActive(btn, active)

    if active then
        local previousBtn = CS.activePreviewBadgeButton
        if previousBtn and previousBtn ~= btn then
            SetPreviewBadgeActive(previousBtn, false)
        end
        CS.activePreviewBadgeButton = btn
    elseif CS.activePreviewBadgeButton == btn then
        CS.activePreviewBadgeButton = nil
    end
end

local function AddPreviewBadge(parentWidget, anchorAfterFrame, label, isActiveFn, setActiveFn, enabled)
    local hasCheckboxAnchor = parentWidget and parentWidget.frame and parentWidget.checkbg and parentWidget.text
    local hasLabelAnchor = parentWidget and parentWidget.frame and parentWidget.label
    if not enabled
        or not (hasCheckboxAnchor or hasLabelAnchor)
        or type(isActiveFn) ~= "function"
        or type(setActiveFn) ~= "function"
    then
        return nil
    end

    local frame = parentWidget.frame
    local btn = frame._cdcPreviewBtn
    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(14, 14)
        btn._icon = btn:CreateTexture(nil, "ARTWORK")
        btn._icon:SetSize(13, 13)
        btn._icon:SetPoint("CENTER")
        btn._icon:SetAtlas("CreditsScreen-Assets-Buttons-Play", false)
        frame._cdcPreviewBtn = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    if anchorAfterFrame and anchorAfterFrame:IsShown() then
        btn:SetPoint("LEFT", anchorAfterFrame, "RIGHT", 4, 0)
    elseif hasCheckboxAnchor then
        btn:SetPoint("LEFT", parentWidget.checkbg, "RIGHT", parentWidget.text:GetStringWidth() + 6, 0)
    else
        btn:SetPoint("LEFT", parentWidget.label, "RIGHT", 4, 0)
    end
    btn:Show()
    btn._icon:Show()

    SetActivePreviewBadgeButton(btn, isActiveFn())
    btn:SetScript("OnClick", function()
        local showPreview = not isActiveFn()
        if showPreview and CooldownCompanion.ClearAllConfigPreviews then
            CooldownCompanion:ClearAllConfigPreviews()
        end
        setActiveFn(showPreview)
        SetActivePreviewBadgeButton(btn, isActiveFn())
        RefreshActiveAdvancedPreviewToggleButtons()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(label)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    local advancedBtn = frame._cdcAdvancedBtn
    if not (advancedBtn and advancedBtn:GetParent() == frame) then
        parentWidget:SetCallback("OnRelease", function()
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
            if CS.activePreviewBadgeButton == btn then
                CS.activePreviewBadgeButton = nil
            end
        end)
    end

    return btn
end

local function AddConditionalPreviewButton(container, label, previewKind, opts)
    if not (container and CooldownCompanion.SetConditionalVisualPreviewActive and CooldownCompanion.IsConditionalVisualPreviewActive) then
        return nil
    end

    local function ResolveTarget()
        local groupId = ResolvePreviewOption(opts and opts.groupId) or CS.selectedGroup
        local buttonIndex = ResolvePreviewOption(opts and opts.buttonIndex)
        if opts and opts.requireButton and not buttonIndex then
            return nil, nil
        end
        return groupId, buttonIndex
    end

    return AddPreviewToggleButton(container, label, function()
        local groupId, buttonIndex = ResolveTarget()
        if not groupId then
            return false
        end
        return CooldownCompanion:IsConditionalVisualPreviewActive(groupId, buttonIndex, previewKind)
    end, function(show)
        local groupId, buttonIndex = ResolveTarget()
        if groupId then
            CooldownCompanion:SetConditionalVisualPreviewActive(
                groupId,
                buttonIndex,
                previewKind,
                show,
                opts and opts.sampleState
            )
        end
    end)
end

local function AddConditionalPreviewBadge(parentWidget, anchorAfterFrame, label, previewKind, enabled, opts)
    if not (CooldownCompanion.SetConditionalVisualPreviewActive and CooldownCompanion.IsConditionalVisualPreviewActive) then
        return nil
    end

    local function ResolveTarget()
        local groupId = ResolvePreviewOption(opts and opts.groupId) or CS.selectedGroup
        local buttonIndex = ResolvePreviewOption(opts and opts.buttonIndex)
        if opts and opts.requireButton and not buttonIndex then
            return nil, nil
        end
        return groupId, buttonIndex
    end

    return AddPreviewBadge(parentWidget, anchorAfterFrame, label, function()
        local groupId, buttonIndex = ResolveTarget()
        if not groupId then
            return false
        end
        return CooldownCompanion:IsConditionalVisualPreviewActive(groupId, buttonIndex, previewKind)
    end, function(show)
        local groupId, buttonIndex = ResolveTarget()
        if groupId then
            CooldownCompanion:SetConditionalVisualPreviewActive(
                groupId,
                buttonIndex,
                previewKind,
                show,
                opts and opts.sampleState
            )
        end
    end, enabled)
end

local function BuildCooldownTextControls(container, styleTable, refreshCallback, opts)
    local fallbackStyle = opts and opts.fallbackStyle
    local showCooldownText = styleTable.showCooldownText
    if showCooldownText == nil and type(fallbackStyle) == "table" then
        showCooldownText = fallbackStyle.showCooldownText
    end
    local showAuraText = styleTable.showAuraText
    if showAuraText == nil and type(fallbackStyle) == "table" then
        showAuraText = fallbackStyle.showAuraText
    end

    local cdTextCb = AceGUI:Create("CheckBox")
    cdTextCb:SetLabel("Show Cooldown Text")
    cdTextCb:SetValue(showCooldownText or false)
    cdTextCb:SetFullWidth(true)
    cdTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showCooldownText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(cdTextCb)

    if not (opts and opts.isOverride) and (showCooldownText or showAuraText ~= false) then
        AddDurationFormatDropdown(container, styleTable, refreshCallback, opts)
    end

    if showCooldownText then
        AddFontControls(container, styleTable, "cooldown", {}, refreshCallback)
        AddColorPicker(container, styleTable, "cooldownFontColor", "Font Color", {1, 1, 1, 1}, false, refreshCallback, refreshCallback)

        local cdAnchorDrop = AddAnchorDropdown(container, styleTable, "cooldownTextAnchor", "CENTER", refreshCallback)

        -- (?) tooltip for shared positioning
        CreateInfoButton(cdAnchorDrop.frame, cdAnchorDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Shared Position",
            {"Position is shared with Aura Duration Text by default. Enable 'Separate Text Positions' in the Aura Duration Text section to use independent positions.", 1, 1, 1, true},
        }, cdAnchorDrop)

        AddOffsetSliders(container, styleTable, "cooldownTextXOffset", "cooldownTextYOffset", {}, refreshCallback)

    end
end

local function BuildAuraTextControls(container, styleTable, refreshCallback)
    local auraTextCb = AceGUI:Create("CheckBox")
    auraTextCb:SetLabel("Show Aura Duration Text")
    auraTextCb:SetValue(styleTable.showAuraText ~= false)
    auraTextCb:SetFullWidth(true)
    auraTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showAuraText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(auraTextCb)

    -- (?) tooltip for shared positioning note
    CreateInfoButton(auraTextCb.frame, auraTextCb.checkbg, "LEFT", "RIGHT", auraTextCb.text:GetStringWidth() + 4, 0, {
        "Shared Position",
        {"Position is shared with Cooldown Text by default. Enable 'Separate Text Positions' below to use independent positions.", 1, 1, 1, true},
    }, auraTextCb)

    if styleTable.showAuraText ~= false then
        AddFontControls(container, styleTable, "auraText", {}, refreshCallback)
        AddColorPicker(container, styleTable, "auraTextFontColor", "Font Color", {0, 0.925, 1, 1}, false, refreshCallback, refreshCallback)

        local sepPosCb = AceGUI:Create("CheckBox")
        sepPosCb:SetLabel("Separate Text Positions")
        sepPosCb:SetValue(styleTable.separateTextPositions or false)
        sepPosCb:SetFullWidth(true)
        sepPosCb:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.separateTextPositions = val
            refreshCallback()
            RefreshStructuralControls(container)
        end)
        container:AddChild(sepPosCb)

        CreateInfoButton(sepPosCb.frame, sepPosCb.checkbg, "LEFT", "RIGHT", sepPosCb.text:GetStringWidth() + 4, 0, {
            "Separate Text Positions",
            {"When enabled, aura duration text and cooldown text use independent positions. Aura text position controls appear below when toggled on; cooldown text position is in the Cooldown Text section.", 1, 1, 1, true},
        }, sepPosCb)

        if styleTable.separateTextPositions then
            AddAnchorDropdown(container, styleTable, "auraTextAnchor", "TOPLEFT", refreshCallback)
            AddOffsetSliders(container, styleTable, "auraTextXOffset", "auraTextYOffset", {x = 2, y = -2}, refreshCallback)
        end
    end
end

local function BuildAuraStackTextControls(container, styleTable, refreshCallback)
    local auraStackCb = AceGUI:Create("CheckBox")
    auraStackCb:SetLabel("Show Aura Stack Text")
    auraStackCb:SetValue(styleTable.showAuraStackText ~= false)
    auraStackCb:SetFullWidth(true)
    auraStackCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showAuraStackText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(auraStackCb)

    if styleTable.showAuraStackText ~= false then
        AddFontControls(container, styleTable, "auraStack", {}, refreshCallback)
        AddColorPicker(container, styleTable, "auraStackFontColor", "Font Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddAnchorDropdown(container, styleTable, "auraStackAnchor", "BOTTOMLEFT", refreshCallback)
        AddOffsetSliders(container, styleTable, "auraStackXOffset", "auraStackYOffset", {x = 2, y = 2}, refreshCallback)
    end
end

local function BuildKeybindTextControls(container, styleTable, refreshCallback)
    local kbCb = AceGUI:Create("CheckBox")
    kbCb:SetLabel(KEYBIND_CUSTOM_LABEL)
    kbCb:SetValue(styleTable.showKeybindText or false)
    kbCb:SetFullWidth(true)
    kbCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showKeybindText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(kbCb)

    CreateInfoButton(kbCb.frame, kbCb.checkbg, "LEFT", "RIGHT", kbCb.text:GetStringWidth() + 4, 0, KEYBIND_CUSTOM_TOOLTIP, kbCb)

    if styleTable.showKeybindText then
        AddAnchorDropdown(container, styleTable, "keybindAnchor", "TOPRIGHT", refreshCallback)
        AddOffsetSliders(container, styleTable, "keybindXOffset", "keybindYOffset", {x = -2, y = -2}, refreshCallback)
        AddFontControls(container, styleTable, "keybind", {size = 10, sizeMin = 6, sizeMax = 24}, refreshCallback)
        AddColorPicker(container, styleTable, "keybindFontColor", "Font Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    end
end

local function BuildChargeTextControls(container, styleTable, refreshCallback)
    local chargeTextCb = AceGUI:Create("CheckBox")
    chargeTextCb:SetLabel("Show Count Text (Charges/Uses)")
    chargeTextCb:SetValue(styleTable.showChargeText ~= false)
    chargeTextCb:SetFullWidth(true)
    chargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showChargeText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(chargeTextCb)

    if styleTable.showChargeText ~= false then
        AddFontControls(container, styleTable, "charge", {}, refreshCallback)
        AddColorPicker(container, styleTable, "chargeFontColor", "Font Color (Max Charges)", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddColorPicker(container, styleTable, "chargeFontColorMissing", "Font Color (Missing Charges)", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddColorPicker(container, styleTable, "chargeFontColorZero", "Font Color (Zero Charges)", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        AddAnchorDropdown(container, styleTable, "chargeAnchor", "BOTTOMRIGHT", refreshCallback)
        AddOffsetSliders(container, styleTable, "chargeXOffset", "chargeYOffset", {x = -2, y = 2}, refreshCallback)
    end
end

local function BuildBorderControls(container, styleTable, refreshCallback)
    local renderMode = AddBorderRenderModeDropdown(container, styleTable, "borderRenderMode", function()
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSlider = AceGUI:Create("Slider")
        borderSlider:SetLabel("Border Size")
        borderSlider:SetSliderValues(0, 5, 0.1)
        borderSlider:SetValue(styleTable.borderSize or ST.DEFAULT_BORDER_SIZE)
        borderSlider:SetFullWidth(true)
        borderSlider:SetDisabled(borderThicknessLocked)
        borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if borderThicknessLocked then return end
            styleTable.borderSize = val
            refreshCallback()
        end)
        container:AddChild(borderSlider)
    end

    AddColorPicker(container, styleTable, "borderColor", "Border Color", {0, 0, 0, 1}, true, refreshCallback, refreshCallback)
end

local function BuildBackgroundColorControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "backgroundColor", "Background Color", {0, 0, 0, 0.5}, true, refreshCallback, refreshCallback)
end

local function BuildDesaturationControls(container, styleTable, refreshCallback)
    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Show Desaturate On Cooldown")
    desatCb:SetValue(styleTable.desaturateOnCooldown or false)
    desatCb:SetFullWidth(true)
    desatCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.desaturateOnCooldown = val
        refreshCallback()
    end)
    container:AddChild(desatCb)
end

local function BuildShowTooltipsControls(container, styleTable, refreshCallback)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show Tooltips")
    cb:SetValue(styleTable.showTooltips == true)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showTooltips = val
        refreshCallback()
    end)
    container:AddChild(cb)
    return cb
end

local function BuildShowOutOfRangeControls(container, styleTable, refreshCallback)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show Out of Range")
    cb:SetValue(styleTable.showOutOfRange or false)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showOutOfRange = val
        refreshCallback()
    end)
    container:AddChild(cb)
    return cb
end

local function BuildIconTintControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "iconTintColor", "Base Icon Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)

    local cdTintCb = AceGUI:Create("CheckBox")
    cdTintCb:SetLabel("Use Separate Cooldown Tint")
    cdTintCb:SetValue(styleTable.iconCooldownTintEnabled or false)
    cdTintCb:SetFullWidth(true)
    cdTintCb:SetCallback("OnValueChanged", function(w, e, val)
        styleTable.iconCooldownTintEnabled = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(cdTintCb)

    if styleTable.iconCooldownTintEnabled then
        AddColorPicker(container, styleTable, "iconCooldownTintColor", "Cooldown Icon Color", {1, 0, 0.102, 1}, true, refreshCallback, refreshCallback)
    end

    local auraTintCb = AceGUI:Create("CheckBox")
    auraTintCb:SetLabel("Use Separate Aura Tint")
    auraTintCb:SetValue(styleTable.iconAuraTintEnabled or false)
    auraTintCb:SetFullWidth(true)
    auraTintCb:SetCallback("OnValueChanged", function(w, e, val)
        styleTable.iconAuraTintEnabled = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(auraTintCb)

    if styleTable.iconAuraTintEnabled then
        AddColorPicker(container, styleTable, "iconAuraTintColor", "Aura Active Icon Color", {0, 0.925, 1, 1}, true, refreshCallback, refreshCallback)
    end

    if styleTable.showUnusable and ST.UnusableVisualUsesDimTint(styleTable) then
        AddColorPicker(container, styleTable, "iconUnusableTintColor", "Unusable Dim Color", {0.4, 0.4, 0.4, 1}, true, refreshCallback, refreshCallback)
    end
end

local function BuildShowGCDSwipeControls(container, styleTable, refreshCallback)
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show GCD Swipe")
    cb:SetValue(styleTable.showGCDSwipe == true)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showGCDSwipe = val
        refreshCallback()
    end)
    container:AddChild(cb)
end

local function IsIconFillTimerEnabled(styleTable, opts)
    if opts and opts.masqueEnabled == true then
        return false
    end
    if styleTable and styleTable.iconFillEnabled ~= nil then
        return styleTable.iconFillEnabled == true
    end
    return opts and opts.fallbackStyle and opts.fallbackStyle.iconFillEnabled == true
end

local BuildIconFillTimerAdvancedControls

local function BuildCooldownSwipeControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local disabledByIconFill = IsIconFillTimerEnabled(styleTable, opts)

    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Show Cooldown/Duration Swipe")
    cb:SetValue(styleTable.showCooldownSwipe ~= false)
    cb:SetFullWidth(true)
    cb:SetDisabled(disabledByIconFill)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByIconFill then return end
        styleTable.showCooldownSwipe = val
        refreshCallback()
    end)
    container:AddChild(cb)

    local reverseCb = AceGUI:Create("CheckBox")
    reverseCb:SetLabel("Reverse Swipe")
    reverseCb:SetValue(styleTable.cooldownSwipeReverse or false)
    reverseCb:SetFullWidth(true)
    reverseCb:SetDisabled(disabledByIconFill)
    reverseCb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByIconFill then return end
        styleTable.cooldownSwipeReverse = val
        refreshCallback()
    end)
    container:AddChild(reverseCb)
    ApplyOverrideCheckboxIndent(reverseCb, opts)

    local fillCb = AceGUI:Create("CheckBox")
    fillCb:SetLabel("Show Swipe Fill")
    fillCb:SetValue(styleTable.showCooldownSwipeFill ~= false)
    fillCb:SetFullWidth(true)
    fillCb:SetDisabled(disabledByIconFill)
    fillCb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByIconFill then return end
        styleTable.showCooldownSwipeFill = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(fillCb)
    ApplyOverrideCheckboxIndent(fillCb, opts)

    -- Swipe Fill Opacity (only when fill is visible)
    if styleTable.showCooldownSwipeFill ~= false then
        local alphaSlider = AceGUI:Create("Slider")
        alphaSlider:SetLabel("Swipe Fill Opacity")
        alphaSlider:SetSliderValues(0, 1, 0.05)
        alphaSlider:SetIsPercent(true)
        alphaSlider:SetValue(styleTable.cooldownSwipeAlpha or 0.8)
        alphaSlider:SetFullWidth(true)
        if alphaSlider.SetDisabled then alphaSlider:SetDisabled(disabledByIconFill) end
        alphaSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if disabledByIconFill then return end
            styleTable.cooldownSwipeAlpha = val
            refreshCallback()
        end)
        container:AddChild(alphaSlider)
    end

    local edgeCb = AceGUI:Create("CheckBox")
    edgeCb:SetLabel("Show Swipe Edge")
    edgeCb:SetValue(styleTable.showCooldownSwipeEdge ~= false)
    edgeCb:SetFullWidth(true)
    edgeCb:SetDisabled(disabledByIconFill)
    edgeCb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByIconFill then return end
        styleTable.showCooldownSwipeEdge = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(edgeCb)
    ApplyOverrideCheckboxIndent(edgeCb, opts)

    -- Swipe Edge Color (only when edge is visible)
    if styleTable.showCooldownSwipeEdge ~= false then
        local edgeColor = AddColorPicker(container, styleTable, "cooldownSwipeEdgeColor", "Swipe Edge Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
        if edgeColor.SetDisabled then edgeColor:SetDisabled(disabledByIconFill) end
    end
end

local function BuildIconFillTimerControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local disabledByMasque = opts.masqueEnabled == true

    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Icon Fill Timer")
    cb:SetValue(styleTable.iconFillEnabled == true)
    cb:SetFullWidth(true)
    cb:SetDisabled(disabledByMasque)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByMasque then return end
        styleTable.iconFillEnabled = val == true
        if styleTable.iconFillEnabled and type(opts.onEnabled) == "function" then
            opts.onEnabled()
        end
        refreshCallback()
        CooldownCompanion:UpdateAllCooldowns()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(cb)

    if disabledByMasque then
        local note = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(note)
        note:SetText("|cff888888Unavailable while Masque skinning is enabled for this group.|r")
        note:SetFullWidth(true)
        container:AddChild(note)
        return cb
    end

    if opts.showAdvancedControlsInline ~= false then
        BuildIconFillTimerAdvancedControls(container, styleTable, refreshCallback)
    end

    return cb
end

BuildIconFillTimerAdvancedControls = function(container, styleTable, refreshCallback)
    if styleTable.iconFillEnabled ~= true then
        return
    end

    local iconFillOrientation = styleTable.iconFillOrientation == "horizontal" and "horizontal" or "vertical"

    local orientationDrop = AceGUI:Create("Dropdown")
    orientationDrop:SetLabel("Orientation")
    orientationDrop:SetList({
        vertical = "Vertical",
        horizontal = "Horizontal",
    }, { "vertical", "horizontal" })
    orientationDrop:SetValue(iconFillOrientation)
    orientationDrop:SetFullWidth(true)
    orientationDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.iconFillOrientation = val == "vertical" and "vertical" or "horizontal"
        refreshCallback()
        CooldownCompanion:UpdateAllCooldowns()
        RefreshStructuralControls(container)
    end)
    container:AddChild(orientationDrop)

    local anchorEdgeDrop = AceGUI:Create("Dropdown")
    anchorEdgeDrop:SetLabel("Anchor Edge")
    if iconFillOrientation == "vertical" then
        anchorEdgeDrop:SetList({
            default = "Bottom",
            reverse = "Top",
        }, { "default", "reverse" })
    else
        anchorEdgeDrop:SetList({
            default = "Left",
            reverse = "Right",
        }, { "default", "reverse" })
    end
    anchorEdgeDrop:SetValue(styleTable.iconFillReverse == true and "reverse" or "default")
    anchorEdgeDrop:SetFullWidth(true)
    anchorEdgeDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.iconFillReverse = val == "reverse"
        refreshCallback()
        CooldownCompanion:UpdateAllCooldowns()
    end)
    container:AddChild(anchorEdgeDrop)

    local timerMotionDrop = AceGUI:Create("Dropdown")
    timerMotionDrop:SetLabel("Timer Motion")
    timerMotionDrop:SetList({
        drain = "Starts Full (Drain)",
        fill = "Starts Empty (Fill)",
    }, { "drain", "fill" })
    timerMotionDrop:SetValue(styleTable.iconFillTimerBehavior == "fill" and "fill" or "drain")
    timerMotionDrop:SetFullWidth(true)
    timerMotionDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.iconFillTimerBehavior = val == "drain" and "drain" or "fill"
        refreshCallback()
        CooldownCompanion:UpdateAllCooldowns()
    end)
    container:AddChild(timerMotionDrop)

    AddColorPicker(container, styleTable, "iconFillCooldownColor", "Cooldown Fill Color", {0.6, 0.13, 0.18, 0.55}, true, refreshCallback, refreshCallback)
    AddColorPicker(container, styleTable, "iconFillAuraColor", "Aura Fill Color", {0.2, 1.0, 0.2, 0.55}, true, refreshCallback, refreshCallback)
end

local function BuildAuraDurationSwipeControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}
    local disabledByIconFill = IsIconFillTimerEnabled(styleTable, opts)

    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel("Blizzard CDM Aura Swipe Style")
    cb:SetValue(styleTable.auraUseBlizzardSwipe == true)
    cb:SetFullWidth(true)
    cb:SetDisabled(disabledByIconFill)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        if disabledByIconFill then return end
        styleTable.auraUseBlizzardSwipe = val == true
        refreshCallback()
    end)
    container:AddChild(cb)
    return cb
end

local function BuildLossOfControlControls(container, styleTable, refreshCallback)
    local locCb = AceGUI:Create("CheckBox")
    locCb:SetLabel("Show Loss of Control")
    locCb:SetValue(styleTable.showLossOfControl or false)
    locCb:SetFullWidth(true)
    locCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showLossOfControl = val
        refreshCallback()
    end)
    container:AddChild(locCb)
    return locCb
end

local function BuildUnusableVisualModeControls(container, styleTable, refreshCallback)
    local dimCb = AceGUI:Create("CheckBox")
    dimCb:SetLabel("Dim Icon")
    dimCb:SetValue(ST.UnusableVisualUsesDimTint(styleTable))
    dimCb:SetFullWidth(true)
    dimCb:SetCallback("OnValueChanged", function(widget, event, val)
        ST.SetUnusableVisualMode(styleTable, val == true, ST.UnusableVisualUsesDesaturation(styleTable))
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(dimCb)

    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Desaturate Icon")
    desatCb:SetValue(ST.UnusableVisualUsesDesaturation(styleTable))
    desatCb:SetFullWidth(true)
    desatCb:SetCallback("OnValueChanged", function(widget, event, val)
        ST.SetUnusableVisualMode(styleTable, ST.UnusableVisualUsesDimTint(styleTable), val == true)
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(desatCb)
end

local function BuildUnusableDimmingControls(container, styleTable, refreshCallback, opts)
    opts = opts or {}

    local unusableCb = AceGUI:Create("CheckBox")
    unusableCb:SetLabel("Show Unusable Visual")
    unusableCb:SetValue(styleTable.showUnusable == true)
    unusableCb:SetFullWidth(true)
    unusableCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showUnusable = val == true
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(unusableCb)

    local _, unusableAdvBtn = AddAdvancedToggle(unusableCb,
        opts.advancedKey or "unusableVisual",
        opts.infoButtons or tabInfoButtons,
        styleTable.showUnusable == true, {
            title = "Unusable Visual Advanced",
            build = function(panel)
                BuildUnusableVisualModeControls(panel, styleTable, refreshCallback)
            end,
        })

    return unusableCb, unusableAdvBtn
end

local function BuildAssistedHighlightControls(container, styleTable, refreshCallback, opts)
    local hostileOnlyCb = AceGUI:Create("CheckBox")
    hostileOnlyCb:SetLabel("Hostile Target Only")
    hostileOnlyCb:SetValue(styleTable.assistedHighlightHostileTargetOnly ~= false)
    hostileOnlyCb:SetFullWidth(true)
    hostileOnlyCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.assistedHighlightHostileTargetOnly = val
        refreshCallback()
    end)
    container:AddChild(hostileOnlyCb)
    ApplyOverrideCheckboxIndent(hostileOnlyCb, opts)

    local highlightStyles = {
        blizzard = "Blizzard (Marching Ants)",
        proc = "Proc Glow",
        solid = "Solid Border",
    }
    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Highlight Style")
    styleDrop:SetList(highlightStyles)
    styleDrop:SetValue(styleTable.assistedHighlightStyle or "blizzard")
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.assistedHighlightStyle = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(styleDrop)

    if styleTable.assistedHighlightStyle == "solid" then
        AddColorPicker(container, styleTable, "assistedHighlightColor", "Highlight Color", {0.3, 1, 0.3, 0.9}, true, refreshCallback, refreshCallback)

        local hlSizeSlider = AceGUI:Create("Slider")
        hlSizeSlider:SetLabel("Border Size")
        hlSizeSlider:SetSliderValues(1, 6, 0.1)
        hlSizeSlider:SetValue(styleTable.assistedHighlightBorderSize or 2)
        hlSizeSlider:SetFullWidth(true)
        hlSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.assistedHighlightBorderSize = val
            refreshCallback()
        end)
        container:AddChild(hlSizeSlider)
    elseif styleTable.assistedHighlightStyle == "blizzard" then
        local blizzSlider = AceGUI:Create("Slider")
        blizzSlider:SetLabel("Glow Size")
        blizzSlider:SetSliderValues(0, 60, 0.1)
        blizzSlider:SetValue(styleTable.assistedHighlightBlizzardOverhang or 32)
        blizzSlider:SetFullWidth(true)
        blizzSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.assistedHighlightBlizzardOverhang = val
            refreshCallback()
        end)
        container:AddChild(blizzSlider)
    elseif styleTable.assistedHighlightStyle == "proc" then
        AddColorPicker(container, styleTable, "assistedHighlightProcColor", "Glow Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)

        local procSlider = AceGUI:Create("Slider")
        procSlider:SetLabel("Glow Size")
        procSlider:SetSliderValues(0, 60, 0.1)
        procSlider:SetValue(styleTable.assistedHighlightProcOverhang or 32)
        procSlider:SetFullWidth(true)
        procSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.assistedHighlightProcOverhang = val
            refreshCallback()
        end)
        container:AddChild(procSlider)
    end
end

------------------------------------------------------------------------
-- GENERIC GLOW/EFFECT HELPERS
------------------------------------------------------------------------
-- Shared slider block used by both glow style controls and bar effect
-- controls. Builds conditional size/thickness/speed sliders based on
-- the current glow style.
--
-- keys = { size = "...", thickness = "...", speed = "...", lines = "..." }
-- pixelSizeMin: minimum for the pixel "Line Length" slider (1 for glow
--   style controls, 2 for bar effect controls)
local function BuildGlowSliders(container, styleTable, currentStyle, keys, refreshCallback, pixelSizeMin)
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or keys.solidSizeDefault or 5)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "pulsingBorder" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or keys.solidSizeDefault or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Pulse Duration")
        speedSlider:SetSliderValues(0.1, 2.0, 0.05)
        speedSlider:SetValue(styleTable[keys.speed] or 0.5)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "pixel" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Line Length")
        sizeSlider:SetSliderValues(pixelSizeMin, 12, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or 8)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 0.1)
        thicknessSlider:SetValue(styleTable[keys.thickness] or 4)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.thickness] = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable[keys.speed] or 50)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)

        if keys.lines then
            local linesSlider = AceGUI:Create("Slider")
            linesSlider:SetLabel("Number of Lines")
            linesSlider:SetSliderValues(1, 16, 1)
            linesSlider:SetValue(styleTable[keys.lines] or 8)
            linesSlider:SetFullWidth(true)
            linesSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable[keys.lines] = val
                refreshCallback()
            end)
            container:AddChild(linesSlider)
        end
    elseif currentStyle == "glow" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 0.1)
        sizeSlider:SetValue(styleTable[keys.size] or 30)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "lcgButton" then
        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Frequency")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable[keys.speed] or 50)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "lcgAutoCast" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Particle Scale")
        sizeSlider:SetSliderValues(0.2, 3, 0.05)
        local currentScale = styleTable[keys.size]
        if not currentScale or currentScale < 0.2 or currentScale > 3 then
            currentScale = 2
        end
        sizeSlider:SetValue(currentScale)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.size] = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Frequency")
        speedSlider:SetSliderValues(10, 200, 0.1)
        speedSlider:SetValue(styleTable[keys.speed] or 50)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[keys.speed] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    end
end

-- Legacy profile compatibility: lcgProc was removed because it duplicated Blizzard glow.
local function NormalizeLegacyGlowStyle(style)
    if style == "lcgProc" then
        return "glow"
    end
    return style
end

local LCG_GLOW_STYLE_OPTIONS = {
    ["solid"] = "Solid Border",
    ["pixel"] = "Pixel Glow",
    ["glow"] = "Glow (Blizzard)",
    ["lcgButton"] = "Action Button Glow",
    ["lcgAutoCast"] = "Autocast Shine",
}
local LCG_GLOW_STYLE_ORDER = {"solid", "pixel", "glow", "lcgButton", "lcgAutoCast"}

local BAR_BORDER_INDICATOR_OPTIONS = {
    none = "None",
    pixel = "Pixel Glow",
    solid = "Solid Border",
    pulsingBorder = "Pulsing Border",
}
local BAR_BORDER_INDICATOR_ORDER = {"none", "pixel", "solid", "pulsingBorder"}

local MAX_STACK_BORDER_INDICATOR_OPTIONS = {
    none = "None",
    pixelGlow = "Pixel Glow",
    solidBorder = "Solid Border",
    pulsingBorder = "Pulsing Border",
}
local MAX_STACK_BORDER_INDICATOR_ORDER = {"none", "pixelGlow", "solidBorder", "pulsingBorder"}

local function AddIndicatorSettingsHeading(container, text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)
end

local function NormalizeActiveAuraIndicatorSettings(styleTable)
    local style = styleTable and styleTable.barAuraEffect or "none"
    if style == "color" then
        return "none"
    elseif style == "pixel" or style == "solid" or style == "pulsingBorder" then
        return style
    end
    return "none"
end

local function NormalizeMaxStackIndicatorSettings(styleTable)
    local style = styleTable and styleTable.maxStacksGlowStyle or "solidBorder"
    if style == "pulsingOverlay" or style == "none" then
        return "none"
    elseif style == "pixelGlow" or style == "solidBorder" or style == "pulsingBorder" then
        return style
    end
    return "solidBorder"
end

local function MaxStacksBarEffectEnabledForSettings(styleTable)
    if not styleTable then return false end
    local colorShiftEnabled = styleTable.maxStacksBarColorShiftEnabled
    if colorShiftEnabled == nil then
        colorShiftEnabled = styleTable.maxStacksGlowStyle == "pulsingOverlay"
    end
    return styleTable.maxStacksBarPulseEnabled == true or colorShiftEnabled == true
end

local function IsSolidLikeBorderIndicator(style)
    return style == "solid" or style == "pulsingBorder"
        or style == "solidBorder"
end

local function IsPixelBorderIndicator(style)
    return style == "pixel" or style == "pixelGlow"
end

local function ApplyBorderIndicatorDefaultSize(styleTable, sizeKey, oldStyle, newStyle, solidDefault, pixelDefault)
    if not styleTable or not sizeKey then return end
    if IsSolidLikeBorderIndicator(newStyle) and not IsSolidLikeBorderIndicator(oldStyle) then
        styleTable[sizeKey] = solidDefault or 2
    elseif IsPixelBorderIndicator(newStyle) and not IsPixelBorderIndicator(oldStyle) then
        styleTable[sizeKey] = pixelDefault or 8
    end
end

local function ApplyBorderIndicatorDefaultSpeed(styleTable, speedKey, oldStyle, newStyle, pulseDefault, pixelDefault)
    if not styleTable or not speedKey then return end
    if newStyle == "pulsingBorder" and oldStyle ~= "pulsingBorder" then
        styleTable[speedKey] = pulseDefault or 0.5
    elseif IsPixelBorderIndicator(newStyle) and not IsPixelBorderIndicator(oldStyle) then
        styleTable[speedKey] = pixelDefault or 50
    end
end

-- Generic glow style builder (Group A): style dropdown + color picker +
-- conditional sliders. Replaces BuildProcGlowControls,
-- BuildPandemicGlowControls, BuildAuraIndicatorControls.
--
-- cfg = { styleKey, colorKey, colorLabel, sizeKey, thicknessKey,
--         speedKey, linesKey, defaultStyle, defaultColor }
local function BuildGlowStyleControls(container, styleTable, refreshCallback, cfg, opts)
    local isOverrideMode = opts and opts.isOverride == true
    local isEnabled
    if cfg.enableKey then
        local enabledVal = rawget(styleTable, cfg.enableKey)
        if enabledVal == nil and cfg.deriveEnableFromEffect and rawget(styleTable, cfg.effectKey) ~= nil then
            enabledVal = (styleTable[cfg.effectKey] or "none") ~= "none"
        end
        if enabledVal == nil and opts and opts.fallbackStyle then
            enabledVal = opts.fallbackStyle[cfg.enableKey]
            if enabledVal == nil and cfg.deriveEnableFromEffect then
                enabledVal = (opts.fallbackStyle[cfg.effectKey] or "none") ~= "none"
            end
        end
        isEnabled = enabledVal ~= false
    else
        isEnabled = styleTable[cfg.styleKey] ~= "none"
    end

    if isOverrideMode and cfg.enableLabel then
        local enableCb = AceGUI:Create("CheckBox")
        enableCb:SetLabel(cfg.enableLabel)
        enableCb:SetValue(isEnabled)
        enableCb:SetFullWidth(true)
        enableCb:SetCallback("OnValueChanged", function(widget, event, val)
            if cfg.enableKey then
                styleTable[cfg.enableKey] = val
                if val and styleTable[cfg.styleKey] == "none" then
                    styleTable[cfg.styleKey] = cfg.defaultStyle
                end
            else
                styleTable[cfg.styleKey] = val and cfg.defaultStyle or "none"
            end
            refreshCallback()
            RefreshStructuralControls(container)
        end)
        container:AddChild(enableCb)

        if not isEnabled then
            return
        end
    end

    if opts and opts.afterEnableCallback then
        opts.afterEnableCallback(container)
    end

    if styleTable[cfg.styleKey] == "lcgProc" then
        styleTable[cfg.styleKey] = "glow"
    end
    local currentStyle = NormalizeLegacyGlowStyle(styleTable[cfg.styleKey] or cfg.defaultStyle)
    if currentStyle == "none" then
        currentStyle = cfg.defaultStyle
    end

    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Glow Style")
    local styleOptions = cfg.styleOptions or {
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }
    local styleOrder = cfg.styleOrder or {"solid", "pixel", "glow"}
    styleDrop:SetList(styleOptions, styleOrder)
    styleDrop:SetValue(currentStyle)
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        if cfg.enableKey then
            styleTable[cfg.enableKey] = true
        end
        styleTable[cfg.styleKey] = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(styleDrop)

    if not (opts and opts.hidePrimaryColorPicker) then
        AddColorPicker(container, styleTable, cfg.colorKey, cfg.colorLabel, cfg.defaultColor, true, refreshCallback, refreshCallback)
    end

    BuildGlowSliders(container, styleTable, currentStyle, {
        size = cfg.sizeKey, thickness = cfg.thicknessKey, speed = cfg.speedKey, lines = cfg.linesKey,
    }, refreshCallback, 1)
end

-- Generic bar effect builder (Group B): primary color picker + effect
-- dropdown (none/pixel/solid) + conditional effect color +
-- conditional sliders. Replaces BuildPandemicBarControls,
-- BuildBarActiveAuraControls.
--
-- cfg = { colorKey, colorLabel, defaultColor, effectKey, effectLabel,
--         effectColorKey, effectColorLabel, defaultEffectColor,
--         effectSizeKey, effectThicknessKey, effectSpeedKey, effectLinesKey }
local function BuildBarEffectControls(container, styleTable, refreshCallback, cfg, opts)
    local isOverrideMode = opts and opts.isOverride == true
    local isEnabled
    if cfg.enableKey then
        local enabledVal = rawget(styleTable, cfg.enableKey)
        if enabledVal == nil and cfg.deriveEnableFromEffect and rawget(styleTable, cfg.effectKey) ~= nil then
            enabledVal = (styleTable[cfg.effectKey] or "none") ~= "none"
        end
        if enabledVal == nil and opts and opts.fallbackStyle then
            enabledVal = opts.fallbackStyle[cfg.enableKey]
            if enabledVal == nil and cfg.deriveEnableFromEffect then
                enabledVal = (opts.fallbackStyle[cfg.effectKey] or "none") ~= "none"
            end
        end
        isEnabled = enabledVal ~= false
    else
        isEnabled = (styleTable[cfg.effectKey] or "none") ~= "none"
    end

    if isOverrideMode and cfg.enableLabel then
        local enableCb = AceGUI:Create("CheckBox")
        enableCb:SetLabel(cfg.enableLabel)
        enableCb:SetValue(isEnabled)
        enableCb:SetFullWidth(true)
        enableCb:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[cfg.enableKey] = val
            refreshCallback()
            RefreshStructuralControls(container)
        end)
        container:AddChild(enableCb)

        if not isEnabled then
            return
        end
    end

    if opts and opts.afterEnableCallback then
        opts.afterEnableCallback(container)
    end

    if not (opts and opts.hidePrimaryColorPicker) then
        if cfg.primaryColorSectionLabel then
            AddIndicatorSettingsHeading(container, cfg.primaryColorSectionLabel)
        end
        AddColorPicker(container, styleTable, cfg.colorKey, cfg.colorLabel, cfg.defaultColor, true, refreshCallback, refreshCallback)
    end

    if cfg.effectSectionLabel then
        AddIndicatorSettingsHeading(container, cfg.effectSectionLabel)
    end

    local effectDrop = AceGUI:Create("Dropdown")
    effectDrop:SetLabel(cfg.effectLabel)
    effectDrop:SetList(cfg.effectOptions or {
        ["none"] = "None",
        ["pixel"] = "Pixel Glow",
        ["solid"] = "Solid Border",
    }, cfg.effectOrder or {"none", "pixel", "solid"})
    local currentEffect = styleTable[cfg.effectKey] or "none"
    local displayEffect = cfg.normalizeEffectForDisplay
        and cfg.normalizeEffectForDisplay(styleTable)
        or currentEffect
    effectDrop:SetValue(displayEffect)
    effectDrop:SetFullWidth(true)
    effectDrop:SetCallback("OnValueChanged", function(widget, event, val)
        local oldEffect = cfg.normalizeEffectForDisplay
            and cfg.normalizeEffectForDisplay(styleTable)
            or (styleTable[cfg.effectKey] or "none")
        styleTable[cfg.effectKey] = cfg.mapEffectSelection
            and cfg.mapEffectSelection(val)
            or val
        ApplyBorderIndicatorDefaultSize(
            styleTable,
            cfg.effectSizeKey,
            oldEffect,
            val,
            cfg.effectSolidSizeDefault,
            cfg.effectPixelSizeDefault
        )
        ApplyBorderIndicatorDefaultSpeed(
            styleTable,
            cfg.effectSpeedKey,
            oldEffect,
            val,
            cfg.effectPulseSpeedDefault,
            cfg.effectPixelSpeedDefault
        )
        refreshCallback()
        if val == "none" and IsAdvancedSettingsPanelContainer(container) and CS.CloseAdvancedSettingsPanel then
            RefreshStructuralControls(container)
        else
            RefreshStructuralControls(container)
        end
    end)
    container:AddChild(effectDrop)

    currentEffect = cfg.normalizeEffectForDisplay
        and cfg.normalizeEffectForDisplay(styleTable)
        or (styleTable[cfg.effectKey] or "none")
    if currentEffect ~= "none" then
        AddColorPicker(container, styleTable, cfg.effectColorKey, cfg.effectColorLabel, cfg.defaultEffectColor, true, refreshCallback, refreshCallback)

        BuildGlowSliders(container, styleTable, currentEffect, {
            size = cfg.effectSizeKey, thickness = cfg.effectThicknessKey, speed = cfg.effectSpeedKey, lines = cfg.effectLinesKey,
            solidSizeDefault = cfg.effectSolidSizeDefault,
        }, refreshCallback, 2)
    end
end

------------------------------------------------------------------------
-- PUBLIC GLOW/EFFECT WRAPPERS (same signatures as original functions)
------------------------------------------------------------------------
local function BuildProcGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "procGlowStyle", colorKey = "procGlowColor", colorLabel = "Glow Color",
        sizeKey = "procGlowSize", thicknessKey = "procGlowThickness", speedKey = "procGlowSpeed", linesKey = "procGlowLines",
        defaultStyle = "glow", defaultColor = {1, 1, 1, 1},
        enableLabel = "Show Proc Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildPandemicGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "pandemicGlowStyle", colorKey = "pandemicGlowColor", colorLabel = "Glow Color",
        sizeKey = "pandemicGlowSize", thicknessKey = "pandemicGlowThickness", speedKey = "pandemicGlowSpeed", linesKey = "pandemicGlowLines",
        defaultStyle = "solid", defaultColor = {1, 0.5, 0, 1},
        enableKey = "showPandemicGlow", enableLabel = "Show Pandemic Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildAuraIndicatorControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "auraGlowStyle", colorKey = "auraGlowColor", colorLabel = "Indicator Color",
        sizeKey = "auraGlowSize", thicknessKey = "auraGlowThickness", speedKey = "auraGlowSpeed", linesKey = "auraGlowLines",
        defaultStyle = "pixel", defaultColor = {1, 0.84, 0, 0.9},
        enableLabel = "Show Aura Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local function BuildReadyGlowControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "readyGlowStyle", colorKey = "readyGlowColor", colorLabel = "Glow Color",
        sizeKey = "readyGlowSize", thicknessKey = "readyGlowThickness", speedKey = "readyGlowSpeed", linesKey = "readyGlowLines",
        defaultStyle = "solid", defaultColor = {0.2, 1.0, 0.2, 1},
        enableLabel = "Show Ready Glow",
        styleOptions = LCG_GLOW_STYLE_OPTIONS,
        styleOrder = LCG_GLOW_STYLE_ORDER,
    }, opts)
end

local KPH_STYLE_OPTIONS = {["solid"] = "Solid Border", ["overlay"] = "Overlay"}
local KPH_STYLE_ORDER = {"solid", "overlay"}

local function BuildKeyPressHighlightControls(container, styleTable, refreshCallback, opts)
    BuildGlowStyleControls(container, styleTable, refreshCallback, {
        styleKey = "keyPressHighlightStyle", colorKey = "keyPressHighlightColor", colorLabel = "Highlight Color",
        sizeKey = "keyPressHighlightSize",
        defaultStyle = "solid", defaultColor = {1, 1, 1, 0.4},
        enableLabel = "Show Key Press Highlight",
        styleOptions = KPH_STYLE_OPTIONS,
        styleOrder = KPH_STYLE_ORDER,
    }, opts)
end

local function BuildPandemicBarControls(container, styleTable, refreshCallback, opts)
    BuildBarEffectControls(container, styleTable, refreshCallback, {
        colorKey = "barPandemicColor", colorLabel = "Pandemic Bar Color",
        defaultColor = {1, 0.5, 0, 1},
        enableKey = "showPandemicGlow", enableLabel = "Show Pandemic Indicator",
        effectKey = "pandemicBarEffect", effectLabel = "Pandemic Effect",
        effectColorKey = "pandemicBarEffectColor", effectColorLabel = "Pandemic Effect Color",
        defaultEffectColor = {1, 0.5, 0, 1},
        effectSizeKey = "pandemicBarEffectSize", effectThicknessKey = "pandemicBarEffectThickness",
        effectSpeedKey = "pandemicBarEffectSpeed", effectLinesKey = "pandemicBarEffectLines",
    }, opts)
end

local function BuildBarActiveAuraControls(container, styleTable, refreshCallback, opts)
    BuildBarEffectControls(container, styleTable, refreshCallback, {
        enableKey = "barAuraIndicatorEnabled", enableLabel = "Enable Active Aura Indicator",
        deriveEnableFromEffect = true,
        colorKey = "barAuraColor", colorLabel = "Active Aura Color",
        primaryColorSectionLabel = "Active Aura Color",
        defaultColor = {0.2, 1.0, 0.2, 1.0},
        effectKey = "barAuraEffect", effectLabel = "Border Indicator",
        effectSectionLabel = "Border Indicator",
        effectOptions = BAR_BORDER_INDICATOR_OPTIONS, effectOrder = BAR_BORDER_INDICATOR_ORDER,
        normalizeEffectForDisplay = NormalizeActiveAuraIndicatorSettings,
        mapEffectSelection = function(value) return value == "none" and "color" or value end,
        effectColorKey = "barAuraEffectColor", effectColorLabel = "Border Color",
        defaultEffectColor = {1, 0.84, 0, 0.9},
        effectSizeKey = "barAuraEffectSize", effectThicknessKey = "barAuraEffectThickness",
        effectSpeedKey = "barAuraEffectSpeed", effectLinesKey = "barAuraEffectLines",
        effectSolidSizeDefault = 2,
        effectPixelSizeDefault = 8,
        effectPulseSpeedDefault = 0.5,
        effectPixelSpeedDefault = 50,
    }, opts)
end

------------------------------------------------------------------------
-- BAR MODE PULSE / COLOR SHIFT CONTROLS
------------------------------------------------------------------------

-- cfg = { pulseKey, pulseSpeedKey,
--         colorShiftKey, colorShiftSpeedKey, colorShiftColorKey, defaultShiftColor }
local function BuildBarPulseControls(container, styleTable, refreshCallback, cfg, opts)
    local fb = opts and opts.fallbackStyle
    local function resolve(key, default)
        local v = styleTable[key]
        if v == nil and fb then v = fb[key] end
        if v == nil and cfg.legacyColorShiftStyleKey
            and styleTable[cfg.legacyColorShiftStyleKey] == cfg.legacyColorShiftStyleValue then
            if key == cfg.colorShiftKey then
                v = true
            elseif key == cfg.colorShiftSpeedKey then
                v = styleTable[cfg.legacyColorShiftSpeedKey]
            elseif key == cfg.colorShiftColorKey then
                v = styleTable[cfg.legacyColorShiftColorKey]
            end
        end
        if v ~= nil then return v end
        return default
    end

    if opts and opts.sectionLabel then
        AddIndicatorSettingsHeading(container, opts.sectionLabel)
    end

    -- Alpha Pulse
    local pulseCb = AceGUI:Create("CheckBox")
    pulseCb:SetLabel("Alpha Pulse")
    pulseCb:SetValue(resolve(cfg.pulseKey, false))
    pulseCb:SetFullWidth(true)
    pulseCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable[cfg.pulseKey] = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(pulseCb)

    if resolve(cfg.pulseKey, false) then
        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Pulse Duration")
        speedSlider:SetSliderValues(0.1, 2.0, 0.05)
        speedSlider:SetValue(resolve(cfg.pulseSpeedKey, 0.5))
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[cfg.pulseSpeedKey] = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    end

    -- Color Shift
    local shiftCb = AceGUI:Create("CheckBox")
    shiftCb:SetLabel("Color Shift")
    shiftCb:SetValue(resolve(cfg.colorShiftKey, false))
    shiftCb:SetFullWidth(true)
    shiftCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable[cfg.colorShiftKey] = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(shiftCb)

    if resolve(cfg.colorShiftKey, false) then
        AddColorPicker(container, styleTable, cfg.colorShiftColorKey, "Shift Color", resolve(cfg.colorShiftColorKey, cfg.defaultShiftColor), true, refreshCallback, refreshCallback)

        local shiftSpeedSlider = AceGUI:Create("Slider")
        shiftSpeedSlider:SetLabel("Shift Duration")
        shiftSpeedSlider:SetSliderValues(0.1, 2.0, 0.05)
        shiftSpeedSlider:SetValue(resolve(cfg.colorShiftSpeedKey, 0.5))
        shiftSpeedSlider:SetFullWidth(true)
        shiftSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable[cfg.colorShiftSpeedKey] = val
            refreshCallback()
        end)
        container:AddChild(shiftSpeedSlider)
    end
end

local function BuildBarAuraPulseControls(container, styleTable, refreshCallback, opts)
    BuildBarPulseControls(container, styleTable, refreshCallback, {
        pulseKey = "barAuraPulseEnabled", pulseSpeedKey = "barAuraPulseSpeed",
        colorShiftKey = "barAuraColorShiftEnabled", colorShiftSpeedKey = "barAuraColorShiftSpeed",
        colorShiftColorKey = "barAuraColorShiftColor", defaultShiftColor = {1, 1, 1, 1},
    }, opts or { sectionLabel = "Bar Effect" })
end

local function BuildPandemicBarPulseControls(container, styleTable, refreshCallback, opts)
    BuildBarPulseControls(container, styleTable, refreshCallback, {
        pulseKey = "pandemicBarPulseEnabled", pulseSpeedKey = "pandemicBarPulseSpeed",
        colorShiftKey = "pandemicBarColorShiftEnabled", colorShiftSpeedKey = "pandemicBarColorShiftSpeed",
        colorShiftColorKey = "pandemicBarColorShiftColor", defaultShiftColor = {1, 1, 1, 1},
    }, opts)
end

local function BuildMaxStacksIndicatorAdvancedControls(container, styleTable, refreshCallback, opts)
    AddIndicatorSettingsHeading(container, "Border Indicator")

    local currentStyle = NormalizeMaxStackIndicatorSettings(styleTable)
    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Border Indicator")
    styleDrop:SetList(MAX_STACK_BORDER_INDICATOR_OPTIONS, MAX_STACK_BORDER_INDICATOR_ORDER)
    styleDrop:SetValue(currentStyle)
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        local oldStyle = NormalizeMaxStackIndicatorSettings(styleTable)
        styleTable.maxStacksGlowStyle = val
        ApplyBorderIndicatorDefaultSize(styleTable, "maxStacksGlowSize", oldStyle, val, 2, 8)
        ApplyBorderIndicatorDefaultSpeed(styleTable, "maxStacksGlowSpeed", oldStyle, val, 0.5, 50)
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(styleDrop)

    if currentStyle ~= "none" then
        AddColorPicker(container, styleTable, "maxStacksGlowColor", "Border Color", {1, 0.84, 0, 0.9}, true,
            refreshCallback, refreshCallback)

        if currentStyle == "pixelGlow" then
            BuildGlowSliders(container, styleTable, "pixel", {
                size = "maxStacksGlowSize",
                thickness = "maxStacksGlowThickness",
                speed = "maxStacksGlowSpeed",
                lines = "maxStacksGlowLines",
            }, refreshCallback, 2)
        else
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Border Size")
            sizeSlider:SetSliderValues(1, 8, 0.1)
            sizeSlider:SetValue(styleTable.maxStacksGlowSize or 2)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.maxStacksGlowSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)
        end

        if currentStyle == "pulsingBorder" then
            local speedSlider = AceGUI:Create("Slider")
            speedSlider:SetLabel("Pulse Duration")
            speedSlider:SetSliderValues(0.1, 2.0, 0.05)
            speedSlider:SetValue(styleTable.maxStacksGlowSpeed or 0.5)
            speedSlider:SetFullWidth(true)
            speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.maxStacksGlowSpeed = val
                refreshCallback()
            end)
            container:AddChild(speedSlider)
        end
    end

    AddIndicatorSettingsHeading(container, "Bar Effect")
    if currentStyle == "none" and MaxStacksBarEffectEnabledForSettings(styleTable) then
        AddColorPicker(container, styleTable, "maxStacksGlowColor", "Bar Effect Color", {1, 0.84, 0, 0.9}, true,
            refreshCallback, refreshCallback)
    end

    BuildBarPulseControls(container, styleTable, refreshCallback, {
        pulseKey = "maxStacksBarPulseEnabled", pulseSpeedKey = "maxStacksBarPulseSpeed",
        colorShiftKey = "maxStacksBarColorShiftEnabled", colorShiftSpeedKey = "maxStacksBarColorShiftSpeed",
        colorShiftColorKey = "maxStacksBarColorShiftColor", defaultShiftColor = {1, 1, 1, 1},
        legacyColorShiftStyleKey = "maxStacksGlowStyle", legacyColorShiftStyleValue = "pulsingOverlay",
        legacyColorShiftSpeedKey = "maxStacksGlowSpeed", legacyColorShiftColorKey = "maxStacksGlowColor",
    })
end

local function BuildBarColorsControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "barColor", "Bar Color", {0.2, 0.6, 1.0, 1.0}, true, refreshCallback, refreshCallback)
    AddColorPicker(container, styleTable, "barCooldownColor", "Bar Cooldown Color", {0.6, 0.6, 0.6, 1.0}, true, refreshCallback, refreshCallback)
    AddColorPicker(container, styleTable, "barChargeColor", "Bar Recharging Color", {1.0, 0.82, 0.0, 1.0}, true, refreshCallback, refreshCallback)
    AddColorPicker(container, styleTable, "barBgColor", "Bar Background Color", {0.1, 0.1, 0.1, 0.8}, true, refreshCallback, refreshCallback)
end

local function BuildBarNameTextControls(container, styleTable, refreshCallback)
    local showNameCb = AceGUI:Create("CheckBox")
    showNameCb:SetLabel("Show Name Text")
    showNameCb:SetValue(styleTable.showBarNameText ~= false)
    showNameCb:SetFullWidth(true)
    showNameCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showBarNameText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(showNameCb)

    if styleTable.showBarNameText ~= false then
        local flipNameCheck = AceGUI:Create("CheckBox")
        flipNameCheck:SetLabel("Flip Name Text")
        flipNameCheck:SetValue(styleTable.barNameTextReverse or false)
        flipNameCheck:SetFullWidth(true)
        flipNameCheck:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameTextReverse = val
            refreshCallback()
        end)
        container:AddChild(flipNameCheck)

        AddFontControls(container, styleTable, "barName", {size = 10, sizeMin = 6, sizeMax = 24}, refreshCallback)
        AddColorPicker(container, styleTable, "barNameFontColor", "Font Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    end
end

local function BuildBarReadyTextControls(container, styleTable, refreshCallback)
    local showReadyCb = AceGUI:Create("CheckBox")
    showReadyCb:SetLabel("Show Ready Text")
    showReadyCb:SetValue(styleTable.showBarReadyText or false)
    showReadyCb:SetFullWidth(true)
    showReadyCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showBarReadyText = val
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    container:AddChild(showReadyCb)

    if styleTable.showBarReadyText then
        local readyTextBox = AceGUI:Create("EditBox")
        if readyTextBox.editbox.Instructions then readyTextBox.editbox.Instructions:Hide() end
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(styleTable.barReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            styleTable.barReadyText = val
            refreshCallback()
        end)
        container:AddChild(readyTextBox)

        AddColorPicker(container, styleTable, "barReadyTextColor", "Ready Text Color", {0.2, 1.0, 0.2, 1.0}, true, refreshCallback, refreshCallback)
        AddFontControls(container, styleTable, "barReady", {sizeMin = 6, sizeMax = 24}, refreshCallback)
    end
end

------------------------------------------------------------------------
-- Text Mode — Text Colors
------------------------------------------------------------------------
local function BuildTextBackgroundControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "textBgColor", "Background Color", {0, 0, 0, 0}, true, refreshCallback, refreshCallback)

    local renderMode = AddBorderRenderModeDropdown(container, styleTable, "textBorderRenderMode", function()
        refreshCallback()
        RefreshStructuralControls(container)
    end)
    local borderThicknessLocked = ST.IsBorderThicknessLocked()

    if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
        local borderSlider = AceGUI:Create("Slider")
        borderSlider:SetLabel("Border Size")
        borderSlider:SetSliderValues(0, 5, 0.1)
        borderSlider:SetValue(styleTable.textBorderSize or 0)
        borderSlider:SetFullWidth(true)
        borderSlider:SetDisabled(borderThicknessLocked)
        borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
            if borderThicknessLocked then return end
            styleTable.textBorderSize = val
            refreshCallback()
        end)
        container:AddChild(borderSlider)
    end

    AddColorPicker(container, styleTable, "textBorderColor", "Border Color", {0, 0, 0, 1}, true, refreshCallback, refreshCallback)
end

local function BuildTextFontControls(container, styleTable, refreshCallback)
    AddFontControls(container, styleTable, "text", {sizeMin = 6, sizeMax = 72}, refreshCallback)

    local alignDrop = AceGUI:Create("Dropdown")
    alignDrop:SetLabel("Alignment")
    alignDrop:SetList({LEFT = "Left", CENTER = "Center", RIGHT = "Right"})
    alignDrop:SetValue(styleTable.textAlignment or "LEFT")
    alignDrop:SetFullWidth(true)
    alignDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.textAlignment = val
        refreshCallback()
    end)
    container:AddChild(alignDrop)

    local shadowCb = AceGUI:Create("CheckBox")
    shadowCb:SetLabel("Text Shadow")
    shadowCb:SetValue(styleTable.textShadow == true)
    shadowCb:SetFullWidth(true)
    shadowCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.textShadow = val or false
        refreshCallback()
    end)
    container:AddChild(shadowCb)
end

local function BuildTextColorsControls(container, styleTable, refreshCallback)
    AddColorPicker(container, styleTable, "textFontColor", "Text Color", {1, 1, 1, 1}, true, refreshCallback, refreshCallback)
    AddColorPicker(container, styleTable, "textCooldownColor", "Cooldown Color", {1, 0.3, 0.3, 1}, true, refreshCallback, refreshCallback)

    local readyColorPicker = AddColorPicker(container, styleTable, "textReadyColor", "Ready Color", {0.2, 1.0, 0.2, 1}, true, refreshCallback, refreshCallback)

    local function BuildReadyTextAdvanced(panel)
        local readyTextBox = AceGUI:Create("EditBox")
        if readyTextBox.editbox.Instructions then readyTextBox.editbox.Instructions:Hide() end
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(styleTable.textReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            styleTable.textReadyText = val
            refreshCallback()
        end)
        panel:AddChild(readyTextBox)
    end

    local readyAdvExpanded, readyAdvBtn = AddAdvancedToggle(readyColorPicker, "textReadyText", tabInfoButtons, nil, {
        title = "Ready Color Advanced",
        build = BuildReadyTextAdvanced,
    })
    readyAdvBtn:SetPoint("LEFT", readyColorPicker.colorSwatch, "RIGHT", readyColorPicker.text:GetStringWidth() + 8, 0)

    AddColorPicker(container, styleTable, "textAuraColor", "Aura Color", {0, 0.925, 1, 1}, true, refreshCallback, refreshCallback)
end

------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._BuildCooldownTextControls = BuildCooldownTextControls
ST._AddDurationFormatDropdown = AddDurationFormatDropdown
ST._AddPreviewToggleButton = AddPreviewToggleButton
ST._AddPreviewBadge = AddPreviewBadge
ST._RefreshConfigPanelForPreviewToggle = RefreshConfigPanelForPreviewToggle
ST._ClearActivePreviewBadgeButton = ClearActivePreviewBadgeButton
ST._RefreshAdvancedSettingsPreviewButtons = RefreshActiveAdvancedPreviewToggleButtons
ST._AddConditionalPreviewButton = AddConditionalPreviewButton
ST._AddConditionalPreviewBadge = AddConditionalPreviewBadge
ST._BuildAuraTextControls = BuildAuraTextControls
ST._BuildAuraStackTextControls = BuildAuraStackTextControls
ST._BuildKeybindTextControls = BuildKeybindTextControls
ST._BuildChargeTextControls = BuildChargeTextControls
ST._BuildBorderControls = BuildBorderControls
ST._BuildBackgroundColorControls = BuildBackgroundColorControls
ST._BuildDesaturationControls = BuildDesaturationControls
ST._BuildShowTooltipsControls = BuildShowTooltipsControls
ST._BuildShowOutOfRangeControls = BuildShowOutOfRangeControls
ST._BuildShowGCDSwipeControls = BuildShowGCDSwipeControls
ST._BuildCooldownSwipeControls = BuildCooldownSwipeControls
ST._BuildIconFillTimerControls = BuildIconFillTimerControls
ST._BuildIconFillTimerAdvancedControls = BuildIconFillTimerAdvancedControls
ST._BuildAuraDurationSwipeControls = BuildAuraDurationSwipeControls
ST._BuildLossOfControlControls = BuildLossOfControlControls
ST._BuildUnusableDimmingControls = BuildUnusableDimmingControls
ST._BuildIconTintControls = BuildIconTintControls
ST._BuildAssistedHighlightControls = BuildAssistedHighlightControls
ST._BuildProcGlowControls = BuildProcGlowControls
ST._BuildPandemicGlowControls = BuildPandemicGlowControls
ST._BuildPandemicBarControls = BuildPandemicBarControls
ST._BuildAuraIndicatorControls = BuildAuraIndicatorControls
ST._BuildReadyGlowControls = BuildReadyGlowControls
ST._BuildKeyPressHighlightControls = BuildKeyPressHighlightControls
ST._BuildBarActiveAuraControls = BuildBarActiveAuraControls
ST._BuildBarAuraPulseControls = BuildBarAuraPulseControls
ST._BuildPandemicBarPulseControls = BuildPandemicBarPulseControls
ST._BuildMaxStacksIndicatorAdvancedControls = BuildMaxStacksIndicatorAdvancedControls
ST._NormalizeActiveAuraIndicatorSettings = NormalizeActiveAuraIndicatorSettings
ST._NormalizeMaxStackIndicatorSettings = NormalizeMaxStackIndicatorSettings
ST._BuildBarColorsControls = BuildBarColorsControls
ST._BuildBarNameTextControls = BuildBarNameTextControls
ST._BuildBarReadyTextControls = BuildBarReadyTextControls
ST._BuildTextFontControls = BuildTextFontControls
ST._BuildTextColorsControls = BuildTextColorsControls
ST._BuildTextBackgroundControls = BuildTextBackgroundControls
