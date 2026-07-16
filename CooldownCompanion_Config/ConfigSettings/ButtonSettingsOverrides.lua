local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local ColorHeading = ST._ColorHeading
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateRevertButton = ST._CreateRevertButton
local CreateInfoButton = ST._CreateInfoButton
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent
local AddColorPicker = ST._AddColorPicker
local CanButtonUseConfigOverrideSection = ST._CanButtonUseConfigOverrideSection

local BuildCooldownTextControls = ST._BuildCooldownTextControls
local BuildAuraTextControls = ST._BuildAuraTextControls
local BuildAuraStackTextControls = ST._BuildAuraStackTextControls
local BuildAuraDurationSwipeControls = ST._BuildAuraDurationSwipeControls
local BuildKeybindTextControls = ST._BuildKeybindTextControls
local BuildChargeTextControls = ST._BuildChargeTextControls
local BuildBorderControls = ST._BuildBorderControls
local BuildBackgroundColorControls = ST._BuildBackgroundColorControls
local BuildDesaturationControls = ST._BuildDesaturationControls
local BuildShowTooltipsControls = ST._BuildShowTooltipsControls
local BuildShowOutOfRangeControls = ST._BuildShowOutOfRangeControls
local BuildShowGCDSwipeControls = ST._BuildShowGCDSwipeControls
local BuildCooldownSwipeControls = ST._BuildCooldownSwipeControls
local BuildIconFillTimerControls = ST._BuildIconFillTimerControls
local BuildLossOfControlControls = ST._BuildLossOfControlControls
local BuildUnusableDimmingControls = ST._BuildUnusableDimmingControls
local BuildIconTintControls = ST._BuildIconTintControls
local BuildAssistedHighlightControls = ST._BuildAssistedHighlightControls
local BuildProcGlowControls = ST._BuildProcGlowControls
local BuildReadyGlowControls = ST._BuildReadyGlowControls
local BuildKeyPressHighlightControls = ST._BuildKeyPressHighlightControls
local BuildBarNameTextControls = ST._BuildBarNameTextControls
local BuildBarReadyTextControls = ST._BuildBarReadyTextControls
local BuildTextFontControls = ST._BuildTextFontControls
local BuildTextColorsControls = ST._BuildTextColorsControls
local BuildTextBackgroundControls = ST._BuildTextBackgroundControls
local AddPreviewToggleButton = ST._AddPreviewToggleButton
local AddConditionalPreviewButton = ST._AddConditionalPreviewButton

local function GetHiddenOverrideReasonText(reason)
    if reason == "noCooldown" then
        return "Saved for this button, but inactive because this spell does not have a real cooldown."
    elseif reason == "entryType" then
        return "Saved for this button, but inactive because this entry type cannot use it."
    elseif reason == "displayMode" then
        return "Saved for this button, but inactive in the current display mode."
    elseif reason == "auraTracking" then
        return "Saved for this button, but inactive because this entry is not tracking an aura."
    end
    return "Saved for this button, but inactive for this entry right now."
end

local function AddHiddenOverrideSection(scroll, buttonData, hiddenSection, infoButtons)
    local heading = AceGUI:Create("Heading")
    heading:SetText(hiddenSection.sectionDef.label .. " (inactive)")
    if heading.label then
        heading.label:SetTextColor(0.55, 0.55, 0.55)
    end
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local revertBtn = CreateRevertButton(heading, buttonData, hiddenSection.sectionId)
    table.insert(infoButtons, revertBtn)

    local reasonLabel = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(reasonLabel)
    reasonLabel:SetText("|cff888888" .. GetHiddenOverrideReasonText(hiddenSection.reason) .. "|r")
    reasonLabel:SetFullWidth(true)
    scroll:AddChild(reasonLabel)
end

local function PrimeSelectedReadyGlowCappedChargeTransition(groupId, buttonIndex)
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    local button = frame and frame.buttons and frame.buttons[buttonIndex]
    local buttonData = button and button.buttonData
    if not (button and buttonData) then
        return
    end
    if buttonData.type ~= "spell" or buttonData.hasCharges ~= true or buttonData._hasDisplayCount then
        return
    end
    button._readyGlowMaxChargesSpellID = button._displaySpellId or buttonData.id
    button._readyGlowMaxChargesStartTime = nil
    button._readyGlowMaxChargesActive = false
end

local function PrimeSelectedReadyGlowNormalTransition(groupId, buttonIndex)
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    local button = frame and frame.buttons and frame.buttons[buttonIndex]
    local buttonData = button and button.buttonData
    if not (button and buttonData) then
        return
    end
    if buttonData.isPassive or button._noCooldown == true or button._desatCooldownActive == true then
        return
    end
    button._readyGlowStartTime = GetTime()
end

local PREVIEWABLE_OVERRIDE_SECTIONS = {
    cooldownText = true,
    auraText = true,
    auraStackText = true,
    chargeText = true,
    cooldownSwipe = true,
    auraDurationSwipe = true,
    lossOfControl = true,
    iconFillTimer = true,
    desaturation = true,
    showOutOfRange = true,
    unusableDimming = true,
    iconTint = true,
    procGlow = true,
    readyGlow = true,
}

local function AddSelectedButtonPreviewToggle(container, label, previewFlag, setPreviewFn)
    if not AddPreviewToggleButton then
        return
    end

    AddPreviewToggleButton(container, label, function()
        return CS.selectedGroup
            and CS.selectedButton
            and CooldownCompanion:IsPreviewFlagActive(CS.selectedGroup, CS.selectedButton, previewFlag)
    end, function(show)
        if CS.selectedGroup and CS.selectedButton then
            setPreviewFn(CooldownCompanion, CS.selectedGroup, CS.selectedButton, show)
        end
    end)
end

local function AddTextOverrideSection(scroll, buttonData, group, infoButtons)
    local fmtHeading = AceGUI:Create("Heading")
    fmtHeading:SetText("Format Override")
    ColorHeading(fmtHeading)
    fmtHeading:SetFullWidth(true)
    scroll:AddChild(fmtHeading)

    local function BuildFormatOverridePreviewAdvanced(panel)
        if AddConditionalPreviewButton then
            local target = { buttonIndex = function() return CS.selectedButton end, requireButton = true }
            AddConditionalPreviewButton(panel, "Preview Cooldown State", "cooldown", target)
            AddConditionalPreviewButton(panel, "Preview Unusable State", "unusable", target)
            AddConditionalPreviewButton(panel, "Preview Out of Range State", "out_of_range", target)
        end
    end

    local _, fmtPreviewAdvBtn = AddAdvancedToggle(fmtHeading, "buttonTextFormatPreview", infoButtons, nil, {
        title = "Format Override Advanced",
        build = BuildFormatOverridePreviewAdvanced,
    })
    fmtPreviewAdvBtn:SetPoint("LEFT", fmtHeading.label, "RIGHT", 4, 0)

    local fmtInfo = CreateInfoButton(fmtHeading.frame, fmtPreviewAdvBtn, "LEFT", "RIGHT", 4, 0, {
        {"Per-Button Format Override", 1, 0.82, 0, true},
        " ",
        {"Overrides the group format string for this button only.", 1, 1, 1},
        {"Clear the override to revert to the group default.", 1, 1, 1},
    }, infoButtons)
    fmtHeading.right:ClearAllPoints()
    fmtHeading.right:SetPoint("RIGHT", fmtHeading.frame, "RIGHT", -3, 0)
    fmtHeading.right:SetPoint("LEFT", fmtInfo, "RIGHT", 4, 0)

    local effectiveFmt = buttonData.textFormat or group.style.textFormat or "{name}  {status}"

    local preSpacer = AceGUI:Create("Label")
    preSpacer:SetText(" ")
    preSpacer:SetFullWidth(true)
    scroll:AddChild(preSpacer)

    local fmtPreview = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(fmtPreview)
    fmtPreview:SetText(ST._RenderFormatPreview(effectiveFmt, group.style))
    fmtPreview:SetFullWidth(true)
    fmtPreview:SetFontObject(GameFontHighlight)
    fmtPreview:SetJustifyH("CENTER")
    scroll:AddChild(fmtPreview)

    local postSpacer = AceGUI:Create("Label")
    postSpacer:SetText(" ")
    postSpacer:SetFullWidth(true)
    scroll:AddChild(postSpacer)

    if not buttonData.textFormat then
        local defaultNote = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(defaultNote)
        defaultNote:SetText("|cff888888Using group default|r")
        defaultNote:SetFullWidth(true)
        defaultNote:SetFontObject(GameFontHighlightSmall)
        scroll:AddChild(defaultNote)
    else
        for _, line in ipairs(ST._BuildFormatSummary(effectiveFmt)) do
            local fmtSummary = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(fmtSummary)
            fmtSummary:SetText(line)
            fmtSummary:SetFullWidth(true)
            fmtSummary:SetFontObject(GameFontHighlightSmall)
            scroll:AddChild(fmtSummary)
        end
    end

    local btnSpacer = AceGUI:Create("Label")
    btnSpacer:SetText(" ")
    btnSpacer:SetFullWidth(true)
    scroll:AddChild(btnSpacer)

    local editBtn = AceGUI:Create("Button")
    editBtn:SetText("Edit Format Override")
    editBtn:SetFullWidth(true)
    editBtn:SetCallback("OnClick", function()
        ST._OpenFormatEditor(group.style, CS.selectedGroup, {
            title = "Button Format Override",
            saveTarget = buttonData,
            defaultFormat = group.style.textFormat or "{name}  {status}",
        })
    end)
    scroll:AddChild(editBtn)

    if buttonData.textFormat then
        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Override")
        clearBtn:SetFullWidth(true)
        clearBtn:SetCallback("OnClick", function()
            buttonData.textFormat = nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(clearBtn)
    end

end

local function BuildSingleBarColorControl(key, label, defaultColor)
    return function(container, styleTable, onChange)
        AddColorPicker(container, styleTable, key, label, defaultColor, true, onChange, onChange)
    end
end

local function BuildBarIconControls(container, styleTable, onChange)
    local showIconCb = AceGUI:Create("CheckBox")
    showIconCb:SetLabel("Show Icon")
    showIconCb:SetValue(styleTable.showBarIcon ~= false)
    showIconCb:SetFullWidth(true)
    showIconCb:SetCallback("OnValueChanged", function(_, _, val)
        styleTable.showBarIcon = val
        onChange()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showIconCb)

    if styleTable.showBarIcon == false then
        return
    end

    local flipIconCheck = AceGUI:Create("CheckBox")
    flipIconCheck:SetLabel("Flip Icon Side")
    flipIconCheck:SetValue(styleTable.barIconReverse or false)
    flipIconCheck:SetFullWidth(true)
    flipIconCheck:SetCallback("OnValueChanged", function(_, _, val)
        styleTable.barIconReverse = val == true
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(flipIconCheck)

    local iconOffsetSlider = AceGUI:Create("Slider")
    iconOffsetSlider:SetLabel("Icon Offset")
    iconOffsetSlider:SetSliderValues(-5, 50, 0.1)
    iconOffsetSlider:SetValue(styleTable.barIconOffset or 0)
    iconOffsetSlider:SetFullWidth(true)
    iconOffsetSlider:SetCallback("OnValueChanged", function(_, _, val)
        styleTable.barIconOffset = val
        onChange()
    end)
    container:AddChild(iconOffsetSlider)

    local customIconSizeCb = AceGUI:Create("CheckBox")
    customIconSizeCb:SetLabel("Custom Icon Size")
    customIconSizeCb:SetValue(styleTable.barIconSizeOverride or false)
    customIconSizeCb:SetFullWidth(true)
    customIconSizeCb:SetCallback("OnValueChanged", function(_, _, val)
        styleTable.barIconSizeOverride = val
        onChange()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(customIconSizeCb)

    if styleTable.barIconSizeOverride then
        local iconSizeSlider = AceGUI:Create("Slider")
        iconSizeSlider:SetLabel("Icon Size")
        iconSizeSlider:SetSliderValues(5, 100, 0.1)
        iconSizeSlider:SetValue(styleTable.barIconSize or 20)
        iconSizeSlider:SetFullWidth(true)
        iconSizeSlider:SetCallback("OnValueChanged", function(_, _, val)
            styleTable.barIconSize = val
            onChange()
        end)
        container:AddChild(iconSizeSlider)
    end
end

function ST._BuildOverridesTab(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local displayMode = group.displayMode or "icons"
    if displayMode == "text" then
        AddTextOverrideSection(scroll, buttonData, group, infoButtons)
    end

    if not buttonData.overrideSections or not next(buttonData.overrideSections) then
        if displayMode ~= "text" then
            local noOverridesLabel = AceGUI:Create("Label")
            ST._ConfigureWrappedHelperLabel(noOverridesLabel)
            noOverridesLabel:SetText("|cff888888No appearance overrides are currently set.\n\nAppearance overrides still come from the |A:Crosshair_VehichleCursor_32:0:0|a badge next to panel-level appearance settings while this button is selected.|r")
            noOverridesLabel:SetFullWidth(true)
            scroll:AddChild(noOverridesLabel)
        end
        return
    end

    local overrides = buttonData.styleOverrides
    if not overrides then return end

    local function GetEffectiveOverrideValue(key)
        local val = overrides[key]
        if val ~= nil then
            return val
        end
        return group.style and group.style[key]
    end

    local refreshCallback = function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end

    local sectionOrder = {
        "borderSettings", "cooldownText", "auraText", "auraStackText",
        "iconFillTimer", "cooldownSwipe", "auraDurationSwipe", "showGCDSwipe", "keybindText", "chargeText", "desaturation", "showOutOfRange", "showTooltips",
        "lossOfControl", "unusableDimming", "iconTint", "assistedHighlight", "procGlow", "readyGlow", "keyPressHighlight",
        "barIcon", "barColor", "barCooldownColor", "barChargeColor", "barBgColor", "barNameText", "barReadyText",
        "textFont", "textColors", "textBackground",
    }

    local sectionBuilders = {
        borderSettings = BuildBorderControls,
        cooldownText = BuildCooldownTextControls,
        auraText = BuildAuraTextControls,
        auraStackText = BuildAuraStackTextControls,
        auraDurationSwipe = BuildAuraDurationSwipeControls,
        keybindText = BuildKeybindTextControls,
        chargeText = BuildChargeTextControls,
        desaturation = BuildDesaturationControls,
        iconFillTimer = BuildIconFillTimerControls,
        cooldownSwipe = BuildCooldownSwipeControls,
        showGCDSwipe = BuildShowGCDSwipeControls,
        showOutOfRange = BuildShowOutOfRangeControls,
        showTooltips = BuildShowTooltipsControls,
        lossOfControl = BuildLossOfControlControls,
        unusableDimming = BuildUnusableDimmingControls,
        iconTint = function(container, styleTable, onChange, builderOpts)
            local showAuraTint = buttonData.auraTracking or buttonData.addedAs == "aura"
            BuildIconTintControls(container, styleTable, onChange, {
                isOverride = builderOpts and builderOpts.isOverride,
                fallbackStyle = builderOpts and builderOpts.fallbackStyle,
                showAuraTint = showAuraTint or nil,
            })
            BuildBackgroundColorControls(container, styleTable, onChange)
        end,
        assistedHighlight = BuildAssistedHighlightControls,
        procGlow = BuildProcGlowControls,
        readyGlow = BuildReadyGlowControls,
        keyPressHighlight = BuildKeyPressHighlightControls,
        barIcon = BuildBarIconControls,
        barColor = BuildSingleBarColorControl("barColor", "Bar Color", {0.2, 0.6, 1.0, 1.0}),
        barCooldownColor = BuildSingleBarColorControl("barCooldownColor", "Bar Cooldown Color", {0.6, 0.6, 0.6, 1.0}),
        barChargeColor = BuildSingleBarColorControl("barChargeColor", "Bar Recharging Color", {1.0, 0.82, 0.0, 1.0}),
        barBgColor = BuildSingleBarColorControl("barBgColor", "Bar Background Color", {0.1, 0.1, 0.1, 0.8}),
        barNameText = BuildBarNameTextControls,
        barReadyText = BuildBarReadyTextControls,
        textFont = BuildTextFontControls,
        textColors = BuildTextColorsControls,
        textBackground = BuildTextBackgroundControls,
    }

    local visibleOverrideSections = 0
    local hiddenOverrideSections = {}
    for _, sectionId in ipairs(sectionOrder) do
        if buttonData.overrideSections[sectionId] then
            local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
            local sectionAllowed, sectionUnavailableReason = CanButtonUseConfigOverrideSection(buttonData, sectionId)
            if sectionDef and sectionAllowed and sectionDef.modes[displayMode] then
                visibleOverrideSections = visibleOverrideSections + 1
                local overrideKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_override_" .. sectionId
                local heading, overrideCollapsed = BuildCollapsibleSection(scroll, sectionDef.label, overrideKey)

                local revertBtn = CreateRevertButton(heading, buttonData, sectionId)
                table.insert(infoButtons, revertBtn)

                local previewAdvExpanded
                if PREVIEWABLE_OVERRIDE_SECTIONS[sectionId] then
                    local previewAdvBtn
                    local function BuildOverridePreviewAdvanced(panel)
                        if sectionId == "procGlow" and overrides.procGlowStyle ~= "none" then
                            AddSelectedButtonPreviewToggle(panel, "Preview Proc Glow", "_procGlowPreview", CooldownCompanion.SetProcGlowPreview)
                        elseif sectionId == "readyGlow" and overrides.readyGlowStyle and overrides.readyGlowStyle ~= "none" then
                            AddSelectedButtonPreviewToggle(panel, "Preview Ready Glow Style", "_readyGlowPreview", CooldownCompanion.SetReadyGlowPreview)
                        end

                        if AddConditionalPreviewButton then
                            local target = { buttonIndex = function() return CS.selectedButton end, requireButton = true }
                            if sectionId == "cooldownText" or sectionId == "cooldownSwipe" or sectionId == "desaturation" then
                                AddConditionalPreviewButton(panel, "Preview Cooldown State", "cooldown", target)
                            elseif sectionId == "auraText" then
                                AddConditionalPreviewButton(panel, "Preview Aura Duration Text", "aura_duration_text", target)
                            elseif sectionId == "auraStackText" then
                                AddConditionalPreviewButton(panel, "Preview Aura Stack Text", "aura_stack_text", target)
                            elseif sectionId == "chargeText" then
                                AddConditionalPreviewButton(panel, "Preview Max Charges", "charge_full", target)
                                AddConditionalPreviewButton(panel, "Preview Missing Charges", "charge_missing", target)
                                AddConditionalPreviewButton(panel, "Preview Zero Charges", "charge_zero", target)
                            elseif sectionId == "auraDurationSwipe" then
                                AddConditionalPreviewButton(panel, "Preview Aura Duration Swipe", "aura_duration_swipe", target)
                            elseif sectionId == "lossOfControl" then
                                AddConditionalPreviewButton(panel, "Preview Loss of Control", "loss_of_control", target)
                            elseif sectionId == "iconFillTimer" and overrides.iconFillEnabled == true and group.masqueEnabled ~= true then
                                AddConditionalPreviewButton(panel, "Preview Cooldown Fill", "cooldown", target)
                            elseif sectionId == "showOutOfRange" then
                                AddConditionalPreviewButton(panel, "Preview Out of Range State", "out_of_range", target)
                            elseif sectionId == "unusableDimming" then
                                AddConditionalPreviewButton(panel, "Preview Unusable State", "unusable", target)
                            elseif sectionId == "iconTint" then
                                AddConditionalPreviewButton(panel, "Preview Cooldown Tint", "cooldown", target)
                                AddConditionalPreviewButton(panel, "Preview Unusable State", "unusable", target)
                                AddConditionalPreviewButton(panel, "Preview Out of Range Tint", "out_of_range", target)
                            end
                        end
                    end

                    previewAdvExpanded, previewAdvBtn = AddAdvancedToggle(heading, "overridePreview_" .. sectionId, infoButtons, nil, {
                        title = sectionDef.label .. " Advanced",
                        build = BuildOverridePreviewAdvanced,
                        isAvailable = function()
                            return buttonData.overrideSections and buttonData.overrideSections[sectionId]
                        end,
                    })
                    previewAdvBtn:SetPoint("LEFT", revertBtn, "RIGHT", 4, 0)
                    heading.right:ClearAllPoints()
                    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
                    heading.right:SetPoint("LEFT", previewAdvBtn, "RIGHT", 4, 0)
                end

                if not overrideCollapsed then
                    local builder = sectionBuilders[sectionId]
                    if builder then
                        local combatOnlyKey
                        if sectionId == "procGlow" then
                            combatOnlyKey = "procGlowCombatOnly"
                        elseif sectionId == "readyGlow" then
                            combatOnlyKey = "readyGlowCombatOnly"
                        elseif sectionId == "assistedHighlight" then
                            combatOnlyKey = "assistedHighlightCombatOnly"
                        elseif sectionId == "keyPressHighlight" then
                            combatOnlyKey = "keyPressHighlightCombatOnly"
                        end

                        if sectionId == "assistedHighlight" and combatOnlyKey then
                            local combatCb = AceGUI:Create("CheckBox")
                            combatCb:SetLabel("Show Only In Combat")
                            combatCb:SetValue(overrides[combatOnlyKey] or false)
                            combatCb:SetFullWidth(true)
                            combatCb:SetCallback("OnValueChanged", function(_, _, val)
                                overrides[combatOnlyKey] = val
                                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                            end)
                            scroll:AddChild(combatCb)
                            ApplyCheckboxIndent(combatCb, 20)
                        end

                        local afterEnableCallback
                        if combatOnlyKey and sectionId ~= "assistedHighlight" then
                            afterEnableCallback = function(cont)
                                local combatCb = AceGUI:Create("CheckBox")
                                combatCb:SetLabel("Show Only In Combat")
                                combatCb:SetValue(overrides[combatOnlyKey] or false)
                                combatCb:SetFullWidth(true)
                                combatCb:SetCallback("OnValueChanged", function(_, _, val)
                                    overrides[combatOnlyKey] = val
                                    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                                end)
                                cont:AddChild(combatCb)
                                ApplyCheckboxIndent(combatCb, 20)

                                if sectionId == "readyGlow" then
                                    local cappedCb = AceGUI:Create("CheckBox")
                                    cappedCb:SetLabel("Glow When Charges Are Capped")
                                    cappedCb:SetValue(GetEffectiveOverrideValue("readyGlowOnlyAtMaxCharges") or false)
                                    cappedCb:SetFullWidth(true)
                                    cappedCb:SetCallback("OnValueChanged", function(_, _, val)
                                        overrides.readyGlowOnlyAtMaxCharges = val == true
                                        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                                        if (GetEffectiveOverrideValue("readyGlowDuration") or 0) > 0 then
                                            if val then
                                                PrimeSelectedReadyGlowCappedChargeTransition(CS.selectedGroup, CS.selectedButton)
                                            else
                                                PrimeSelectedReadyGlowNormalTransition(CS.selectedGroup, CS.selectedButton)
                                            end
                                        end
                                        CooldownCompanion:UpdateAllCooldowns()
                                    end)
                                    cont:AddChild(cappedCb)
                                    ApplyCheckboxIndent(cappedCb, 20)
                                    CreateInfoButton(cappedCb.frame, cappedCb.checkbg, "LEFT", "RIGHT", cappedCb.text:GetStringWidth() + 6, 0, {
                                        "Glow When Charges Are Capped",
                                        {"When this toggle is enabled, the glow will only appear for charge based spells when at max charges.", 1, 1, 1, true},
                                    }, infoButtons)

                                    local durCb = AceGUI:Create("CheckBox")
                                    durCb:SetLabel("Auto-Hide After Duration")
                                    durCb:SetValue((GetEffectiveOverrideValue("readyGlowDuration") or 0) > 0)
                                    durCb:SetFullWidth(true)
                                    durCb:SetCallback("OnValueChanged", function(_, _, val)
                                        overrides.readyGlowDuration = val and 3 or 0
                                        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                                        if val then
                                            if GetEffectiveOverrideValue("readyGlowOnlyAtMaxCharges") then
                                                PrimeSelectedReadyGlowCappedChargeTransition(CS.selectedGroup, CS.selectedButton)
                                            else
                                                PrimeSelectedReadyGlowNormalTransition(CS.selectedGroup, CS.selectedButton)
                                            end
                                        end
                                        CooldownCompanion:UpdateAllCooldowns()
                                        CooldownCompanion:RefreshConfigPanel()
                                    end)
                                    cont:AddChild(durCb)
                                    ApplyCheckboxIndent(durCb, 20)

                                    if (GetEffectiveOverrideValue("readyGlowDuration") or 0) > 0 then
                                        local durSlider = AceGUI:Create("Slider")
                                        durSlider:SetLabel("Duration (seconds)")
                                        durSlider:SetSliderValues(0.5, 5, 0.5)
                                        durSlider:SetValue(GetEffectiveOverrideValue("readyGlowDuration") or 3)
                                        durSlider:SetFullWidth(true)
                                        durSlider:SetCallback("OnValueChanged", function(_, _, val)
                                            overrides.readyGlowDuration = val
                                            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                                            CooldownCompanion:RefreshConfigPanel()
                                        end)
                                        cont:AddChild(durSlider)
                                    end
                                end
                            end
                        end

                        builder(scroll, overrides, refreshCallback, {
                            isOverride = true,
                            fallbackStyle = group.style,
                            afterEnableCallback = afterEnableCallback,
                            masqueEnabled = group.masqueEnabled == true,
                            infoButtons = infoButtons,
                            advancedKey = "overrideSetting_" .. sectionId,
                        })

                    end
                end
            elseif sectionDef then
                table.insert(hiddenOverrideSections, {
                    sectionId = sectionId,
                    sectionDef = sectionDef,
                    reason = sectionAllowed and "displayMode" or sectionUnavailableReason,
                })
            end
        end
    end

    if visibleOverrideSections == 0 and displayMode ~= "text" then
        local noVisibleOverridesLabel = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(noVisibleOverridesLabel)
        noVisibleOverridesLabel:SetText("|cff888888No appearance overrides are currently available for this entry.\n\nSome saved overrides may be hidden because they do not apply to this entry type or spell cooldown behavior.|r")
        noVisibleOverridesLabel:SetFullWidth(true)
        scroll:AddChild(noVisibleOverridesLabel)
    end

    for _, hiddenSection in ipairs(hiddenOverrideSections) do
        AddHiddenOverrideSection(scroll, buttonData, hiddenSection, infoButtons)
    end
end
