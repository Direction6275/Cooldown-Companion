local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local CreateRevertButton = ST._CreateRevertButton
local CreateInfoButton = ST._CreateInfoButton
local ApplyCheckboxIndent = ST._ApplyCheckboxIndent
local HasTooltipCooldown = ST.HasTooltipCooldown
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior

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
local BuildAuraDurationSwipeControls = ST._BuildAuraDurationSwipeControls
local BuildReadyGlowControls = ST._BuildReadyGlowControls
local BuildKeyPressHighlightControls = ST._BuildKeyPressHighlightControls
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildBarAuraPulseControls = ST._BuildBarAuraPulseControls
local BuildPandemicBarPulseControls = ST._BuildPandemicBarPulseControls
local BuildBarColorsControls = ST._BuildBarColorsControls
local BuildBarNameTextControls = ST._BuildBarNameTextControls
local BuildBarReadyTextControls = ST._BuildBarReadyTextControls
local BuildTextFontControls = ST._BuildTextFontControls
local BuildTextColorsControls = ST._BuildTextColorsControls
local BuildTextBackgroundControls = ST._BuildTextBackgroundControls
local AddConditionalPreviewButton = ST._AddConditionalPreviewButton

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

local function AddTextOverrideSection(scroll, buttonData, group, infoButtons)
    local fmtHeading = AceGUI:Create("Heading")
    fmtHeading:SetText("Format Override")
    ColorHeading(fmtHeading)
    fmtHeading:SetFullWidth(true)
    scroll:AddChild(fmtHeading)

    local fmtInfo = CreateInfoButton(fmtHeading.frame, fmtHeading.label, "LEFT", "RIGHT", 4, 0, {
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
        defaultNote:SetText("|cff888888Using group default|r")
        defaultNote:SetFullWidth(true)
        defaultNote:SetFontObject(GameFontHighlightSmall)
        scroll:AddChild(defaultNote)
    else
        for _, line in ipairs(ST._BuildFormatSummary(effectiveFmt)) do
            local fmtSummary = AceGUI:Create("Label")
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

    if AddConditionalPreviewButton then
        local target = { buttonIndex = function() return CS.selectedButton end, requireButton = true }
        AddConditionalPreviewButton(scroll, "Preview Cooldown State (3s)", "cooldown", target)
        AddConditionalPreviewButton(scroll, "Preview Aura State (3s)", "aura", target)
        AddConditionalPreviewButton(scroll, "Preview Pandemic State (3s)", "pandemic", target)
        AddConditionalPreviewButton(scroll, "Preview Missing Charges (3s)", "charge_missing", target)
        AddConditionalPreviewButton(scroll, "Preview Zero Charges (3s)", "charge_zero", target)
        AddConditionalPreviewButton(scroll, "Preview Unusable State (3s)", "unusable", target)
        AddConditionalPreviewButton(scroll, "Preview Out of Range State (3s)", "out_of_range", target)
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
            noOverridesLabel:SetText("|cff888888No appearance overrides are currently set.\n\nIf you want to override a setting for this specific button, click the |A:Crosshair_VehichleCursor_32:0:0|a badge next to the associated panel level setting while this button is selected.|r")
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
        "auraDurationSwipe", "keybindText", "chargeText", "desaturation", "cooldownSwipe", "showGCDSwipe", "showOutOfRange", "showTooltips",
        "lossOfControl", "unusableDimming", "iconTint", "assistedHighlight", "procGlow", "auraIndicator", "pandemicGlow", "readyGlow", "keyPressHighlight",
        "barColors", "barNameText", "barReadyText", "pandemicBar", "barActiveAura",
        "textFont", "textColors", "textBackground",
    }

    local sectionBuilders = {
        borderSettings = BuildBorderControls,
        cooldownText = BuildCooldownTextControls,
        auraText = BuildAuraTextControls,
        auraStackText = BuildAuraStackTextControls,
        keybindText = BuildKeybindTextControls,
        chargeText = BuildChargeTextControls,
        desaturation = BuildDesaturationControls,
        cooldownSwipe = BuildCooldownSwipeControls,
        showGCDSwipe = BuildShowGCDSwipeControls,
        showOutOfRange = BuildShowOutOfRangeControls,
        showTooltips = BuildShowTooltipsControls,
        lossOfControl = BuildLossOfControlControls,
        unusableDimming = BuildUnusableDimmingControls,
        iconTint = function(container, styleTable, onChange)
            BuildIconTintControls(container, styleTable, onChange)
            BuildBackgroundColorControls(container, styleTable, onChange)
        end,
        assistedHighlight = BuildAssistedHighlightControls,
        procGlow = BuildProcGlowControls,
        pandemicGlow = BuildPandemicGlowControls,
        auraIndicator = BuildAuraIndicatorControls,
        auraDurationSwipe = function(container, styleTable, onChange)
            BuildAuraDurationSwipeControls(container, styleTable, function()
                onChange()
                CooldownCompanion:UpdateAllCooldowns()
            end)
        end,
        readyGlow = BuildReadyGlowControls,
        keyPressHighlight = BuildKeyPressHighlightControls,
        barColors = BuildBarColorsControls,
        barNameText = BuildBarNameTextControls,
        barReadyText = BuildBarReadyTextControls,
        pandemicBar = function(container, styleTable, onChange, opts)
            BuildPandemicBarControls(container, styleTable, onChange, opts)
            local panEnabled = styleTable.showPandemicGlow
            if panEnabled == nil and opts and opts.fallbackStyle then
                panEnabled = opts.fallbackStyle.showPandemicGlow
            end
            if panEnabled ~= false then
                BuildPandemicBarPulseControls(container, styleTable, onChange, opts)
            end
        end,
        barActiveAura = function(container, styleTable, onChange, opts)
            BuildBarActiveAuraControls(container, styleTable, onChange, opts)
            local auraEffect = styleTable.barAuraEffect
            if auraEffect == nil and opts and opts.fallbackStyle then
                auraEffect = opts.fallbackStyle.barAuraEffect
            end
            if (auraEffect or "none") ~= "none" then
                BuildBarAuraPulseControls(container, styleTable, onChange, opts)
            end
        end,
        textFont = BuildTextFontControls,
        textColors = BuildTextColorsControls,
        textBackground = BuildTextBackgroundControls,
    }

    local isNoCooldownSpell = false
    if buttonData.type == "spell" and not buttonData.isPassive and not UsesChargeBehavior(buttonData) then
        local baseCd = GetSpellBaseCooldown(buttonData.id)
        isNoCooldownSpell = (not baseCd or baseCd == 0) and not HasTooltipCooldown(buttonData.id)
    end

    for _, sectionId in ipairs(sectionOrder) do
        if buttonData.overrideSections[sectionId] and not (isNoCooldownSpell and (sectionId == "readyGlow" or sectionId == "desaturation")) then
            local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
            if sectionDef and sectionDef.modes[displayMode] then
                local heading = AceGUI:Create("Heading")
                heading:SetText(sectionDef.label)
                ColorHeading(heading)
                heading:SetFullWidth(true)
                scroll:AddChild(heading)

                local overrideKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_override_" .. sectionId
                local overrideCollapsed = CS.collapsedSections[overrideKey]
                AttachCollapseButton(heading, overrideCollapsed, function()
                    CS.collapsedSections[overrideKey] = not CS.collapsedSections[overrideKey]
                    CooldownCompanion:RefreshConfigPanel()
                end)

                table.insert(infoButtons, CreateRevertButton(heading, buttonData, sectionId))
                if not overrideCollapsed then
                    local builder = sectionBuilders[sectionId]
                    if builder then
                        local combatOnlyKey
                        if sectionId == "procGlow" then
                            combatOnlyKey = "procGlowCombatOnly"
                        elseif sectionId == "auraIndicator" or sectionId == "barActiveAura" then
                            combatOnlyKey = "auraGlowCombatOnly"
                        elseif sectionId == "pandemicGlow" or sectionId == "pandemicBar" then
                            combatOnlyKey = "pandemicGlowCombatOnly"
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

                                if sectionId == "auraIndicator" then
                                    local auraInvertCb = AceGUI:Create("CheckBox")
                                    auraInvertCb:SetLabel("Show When Missing")
                                    auraInvertCb:SetValue(overrides.auraGlowInvert or false)
                                    auraInvertCb:SetFullWidth(true)
                                    auraInvertCb:SetCallback("OnValueChanged", function(_, _, val)
                                        overrides.auraGlowInvert = val
                                        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                                    end)
                                    cont:AddChild(auraInvertCb)
                                    ApplyCheckboxIndent(auraInvertCb, 20)

                                end

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
                        })

                        if sectionId == "procGlow" and overrides.procGlowStyle ~= "none" then
                            local btn = AceGUI:Create("Button")
                            btn:SetText("Preview Proc Glow (3s)")
                            btn:SetFullWidth(true)
                            btn:SetCallback("OnClick", function()
                                if CS.selectedGroup and CS.selectedButton then
                                    CooldownCompanion:PlayProcGlowPreview(CS.selectedGroup, CS.selectedButton, 3)
                                end
                            end)
                            scroll:AddChild(btn)
                        elseif sectionId == "auraIndicator" and overrides.auraGlowStyle ~= "none" then
                            local btn = AceGUI:Create("Button")
                            btn:SetText("Preview Aura Glow (3s)")
                            btn:SetFullWidth(true)
                            btn:SetCallback("OnClick", function()
                                if CS.selectedGroup and CS.selectedButton then
                                    CooldownCompanion:PlayAuraGlowPreview(CS.selectedGroup, CS.selectedButton, 3)
                                end
                            end)
                            scroll:AddChild(btn)
                        elseif sectionId == "pandemicGlow" and GetEffectiveOverrideValue("showPandemicGlow") ~= false then
                            local btn = AceGUI:Create("Button")
                            btn:SetText("Preview Pandemic Glow (3s)")
                            btn:SetFullWidth(true)
                            btn:SetCallback("OnClick", function()
                                if CS.selectedGroup and CS.selectedButton then
                                    CooldownCompanion:PlayPandemicPreview(CS.selectedGroup, CS.selectedButton, 3)
                                end
                            end)
                            scroll:AddChild(btn)
                        elseif sectionId == "barActiveAura" then
                            local btn = AceGUI:Create("Button")
                            btn:SetText("Preview Active Aura Effects (3s)")
                            btn:SetFullWidth(true)
                            btn:SetCallback("OnClick", function()
                                if CS.selectedGroup and CS.selectedButton then
                                    CooldownCompanion:PlayBarAuraActivePreview(CS.selectedGroup, CS.selectedButton, 3)
                                end
                            end)
                            scroll:AddChild(btn)
                        elseif sectionId == "pandemicBar" then
                            local btn = AceGUI:Create("Button")
                            btn:SetText("Preview Pandemic Effects (3s)")
                            btn:SetFullWidth(true)
                            btn:SetCallback("OnClick", function()
                                if CS.selectedGroup and CS.selectedButton then
                                    CooldownCompanion:PlayPandemicPreview(CS.selectedGroup, CS.selectedButton, 3)
                                end
                            end)
                            scroll:AddChild(btn)
                        elseif sectionId == "readyGlow" and overrides.readyGlowStyle and overrides.readyGlowStyle ~= "none" then
                            local btn = AceGUI:Create("Button")
                            btn:SetText("Preview Ready Glow Style (3s)")
                            btn:SetFullWidth(true)
                            btn:SetCallback("OnClick", function()
                                if CS.selectedGroup and CS.selectedButton then
                                    CooldownCompanion:PlayReadyGlowPreview(CS.selectedGroup, CS.selectedButton, 3)
                                end
                            end)
                            scroll:AddChild(btn)
                        end

                        if AddConditionalPreviewButton then
                            local target = { buttonIndex = function() return CS.selectedButton end, requireButton = true }
                            if sectionId == "cooldownText" or sectionId == "cooldownSwipe" or sectionId == "desaturation" then
                                AddConditionalPreviewButton(scroll, "Preview Cooldown State (3s)", "cooldown", target)
                            elseif sectionId == "auraText" or sectionId == "auraStackText" or sectionId == "auraDurationSwipe" then
                                AddConditionalPreviewButton(scroll, "Preview Aura State (3s)", "aura", target)
                            elseif sectionId == "chargeText" then
                                AddConditionalPreviewButton(scroll, "Preview Missing Charges (3s)", "charge_missing", target)
                                AddConditionalPreviewButton(scroll, "Preview Zero Charges (3s)", "charge_zero", target)
                            elseif sectionId == "showOutOfRange" then
                                AddConditionalPreviewButton(scroll, "Preview Out of Range State (3s)", "out_of_range", target)
                            elseif sectionId == "unusableDimming" then
                                AddConditionalPreviewButton(scroll, "Preview Unusable State (3s)", "unusable", target)
                            elseif sectionId == "iconTint" then
                                AddConditionalPreviewButton(scroll, "Preview Cooldown Tint (3s)", "cooldown", target)
                                AddConditionalPreviewButton(scroll, "Preview Aura Tint (3s)", "aura", target)
                                AddConditionalPreviewButton(scroll, "Preview Unusable Tint (3s)", "unusable", target)
                                AddConditionalPreviewButton(scroll, "Preview Out of Range Tint (3s)", "out_of_range", target)
                            end
                        end
                    end
                end
            end
        end
    end
end
