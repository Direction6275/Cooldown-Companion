local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

local ColorHeading = ST._ColorHeading
local ApplyLeftAlignedHeading = ST._ApplyLeftAlignedHeading
local AnchorLeftAlignedHeadingRule = ST._AnchorLeftAlignedHeadingRule
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local CreateRevertButton = ST._CreateRevertButton
local CreateInfoButton = ST._CreateInfoButton
local CanButtonUseConfigOverrideSection = ST._CanButtonUseConfigOverrideSection

-- Imports from RowWidgets.lua (the row grammar). The rules every row-grammar
-- section follows are stated once, in the recipe comment at the top of
-- BuildAppearanceTab's icons path (GroupTabs.lua); this file conforms to them
-- rather than restating them.
--
-- These are for the file-local section builders below. _BuildOverridesTab
-- takes its own function-locals instead: it already carries ~45 upvalues of
-- Lua's 60 ceiling (28 shared builders plus the core imports), so nothing new
-- may be added to its upvalue set.
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddColorRow = ST._AddColorRow

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- Section actions sit on one grammar-height line (ButtonConditions.lua states
-- the idiom): compact SetAutoWidth buttons, flush left, never page-wide.
local ACTION_STRIP_HEIGHT = (ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT) or 30
local ACTION_STRIP_BUTTON_HEIGHT = 24
local ACTION_STRIP_GUTTER = 4

-- The override section labels run past what the 140px control column can size
-- a menu from ("Bar Recharging Color", "Aura Duration Text").
local PICKER_PULLOUT_WIDTH = 300

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
local BuildAuraGlowControls = ST._BuildAuraGlowControls
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildReadyGlowControls = ST._BuildReadyGlowControls
local BuildKeyPressHighlightControls = ST._BuildKeyPressHighlightControls
local BuildBarNameTextControls = ST._BuildBarNameTextControls
local BuildBarReadyTextControls = ST._BuildBarReadyTextControls
local BuildTextFontControls = ST._BuildTextFontControls
local BuildTextColorsControls = ST._BuildTextColorsControls
local BuildTextBackgroundControls = ST._BuildTextBackgroundControls

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

-- An inactive section has no rows to collapse, so it takes the caret-less
-- left-aligned header shape (the same one BuildGroupSettingPresetControls
-- uses) rather than a collapsible one, and its reason line stays full-width
-- prose on the tab surface.
local function AddHiddenOverrideSection(scroll, buttonData, hiddenSection, infoButtons)
    local heading = AceGUI:Create("Heading")
    heading:SetText(hiddenSection.sectionDef.label .. " (inactive)")
    -- ColorHeading first: it is what re-asserts the stock label/left/right
    -- anatomy on a recycled Heading, and the grey below is applied on top of
    -- the class tint it lays down.
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)
    ApplyLeftAlignedHeading(heading)

    if heading.label then
        heading.label:SetTextColor(0.55, 0.55, 0.55)
    end

    -- The grey outlives the widget otherwise: Heading:OnAcquire resets only
    -- text/width/height, and only CC's own ColorHeading re-asserts a label
    -- color - another addon pulling this Heading out of the shared pool would
    -- get a grey title. Restoring from the label's font object puts back
    -- exactly the stock appearance. Chain, don't replace: ApplyLeftAlignedHeading
    -- and the collapse button already installed their own restore handlers.
    local prevOnRelease = heading.events and heading.events["OnRelease"]
    heading:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then
            prevOnRelease(widget, event, ...)
        end
        local fontObject = heading.label and heading.label.GetFontObject and heading.label:GetFontObject()
        if fontObject then
            heading.label:SetTextColor(fontObject:GetTextColor())
        end
    end)

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

local FORMAT_OVERRIDE_TOOLTIP = {
    {"Per-Button Format Override", 1, 0.82, 0, true},
    " ",
    {"Overrides the group format string for this button only.", 1, 1, 1},
    {"Clear the override to revert to the group default.", 1, 1, 1},
}

-- Text mode's format string is a per-entry override like any other, so it
-- takes the same collapsible row-grammar header keyed the same way. Its body
-- is prose and two actions rather than settings rows: the rendered preview and
-- the token summary are wrapped sentences, which do not fit a grid cell, so
-- they stay full-width on the tab surface.
local function AddTextOverrideSection(scroll, buttonData, group, infoButtons)
    local fmtKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_override_textFormat"
    local fmtHeading, fmtCollapsed = BuildCollapsibleSection(scroll, "Format Override", fmtKey,
        nil, nil, ROW_SECTION)

    -- The cooldown / unusable / out-of-range previews this heading used to
    -- open now live on the preview command center.
    local fmtInfo = CreateInfoButton(fmtHeading.frame, fmtHeading.label, "LEFT", "RIGHT", 4, 0,
        FORMAT_OVERRIDE_TOOLTIP, infoButtons)
    AnchorLeftAlignedHeadingRule(fmtHeading, fmtInfo)

    if fmtCollapsed then return end

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

    -- Compact and flush left on one grammar-height line. The destructive Clear
    -- shares that line with the editor that owns what it clears.
    local btnRow = AceGUI:Create("SimpleGroup")
    btnRow:SetFullWidth(true)
    btnRow:SetLayout("Flow")
    btnRow:SetHeight(ACTION_STRIP_HEIGHT)
    btnRow.noAutoHeight = true

    local editBtn = AceGUI:Create("Button")
    editBtn:SetText("Edit Format Override")
    editBtn:SetAutoWidth(true)
    editBtn:SetCallback("OnClick", function()
        ST._OpenFormatEditor(group.style, CS.selectedGroup, {
            title = "Button Format Override",
            saveTarget = buttonData,
            defaultFormat = group.style.textFormat or "{name}  {status}",
        })
    end)
    btnRow:AddChild(editBtn)

    if buttonData.textFormat then
        -- Flow packs siblings at 0px, so the gutter is a fixed-size spacer
        -- group - the same idiom the preset trio and the talent strip use.
        local gutter = AceGUI:Create("SimpleGroup")
        gutter:SetWidth(ACTION_STRIP_GUTTER)
        gutter:SetHeight(ACTION_STRIP_BUTTON_HEIGHT)
        gutter.noAutoHeight = true
        btnRow:AddChild(gutter)

        local clearBtn = AceGUI:Create("Button")
        clearBtn:SetText("Clear Override")
        clearBtn:SetAutoWidth(true)
        clearBtn:SetCallback("OnClick", function()
            buttonData.textFormat = nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        btnRow:AddChild(clearBtn)
    end

    -- Added last so the List-layout parent measures a populated row.
    scroll:AddChild(btnRow)
end

-- One color, so the left column carries it alone. deferCommit is deliberately
-- absent, matching the AddColorPicker call this replaced.
local function BuildSingleBarColorControl(key, label, defaultColor)
    return function(container, styleTable, onChange)
        AddColorRow(container, {
            label = label,
            tbl = styleTable,
            key = key,
            default = defaultColor,
            hasAlpha = true,
            onConfirm = onChange,
            onChange = onChange,
        })
    end
end

-- LEFT column: whether the icon shows at all and where it sits. RIGHT: its
-- size override and the slider that override reveals. Everything gated on the
-- Show Icon toggle indents under it, except the row that heads the right
-- column - which owns its own child instead.
local function BuildBarIconControls(container, styleTable, onChange, opts)
    local right = (opts and opts.rightColumn) or container

    AddCheckboxRow(container, {
        label = "Show Icon",
        value = styleTable.showBarIcon ~= false,
        onChange = function(val)
            styleTable.showBarIcon = val
            onChange()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if styleTable.showBarIcon == false then
        return
    end

    AddCheckboxRow(container, {
        label = "Flip Icon Side",
        indent = true,
        value = styleTable.barIconReverse or false,
        onChange = function(val)
            styleTable.barIconReverse = val == true
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    AddSliderRow(container, {
        label = "Icon Offset",
        indent = true,
        min = -5, max = 50, step = 0.1,
        value = styleTable.barIconOffset or 0,
        onChange = function(val)
            styleTable.barIconOffset = val
            onChange()
        end,
    })

    AddCheckboxRow(right, {
        label = "Custom Icon Size",
        value = styleTable.barIconSizeOverride or false,
        onChange = function(val)
            styleTable.barIconSizeOverride = val
            onChange()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    if styleTable.barIconSizeOverride then
        AddSliderRow(right, {
            label = "Icon Size",
            indent = true,
            min = 5, max = 100, step = 0.1,
            value = styleTable.barIconSize or 20,
            onChange = function(val)
                styleTable.barIconSize = val
                onChange()
            end,
        })
    end
end

-- Shared by the section render loop and the Add Override picker.
local OVERRIDE_SECTION_ORDER = {
    "borderSettings", "cooldownText", "auraText", "auraStackText",
    "iconFillTimer", "cooldownSwipe", "auraDurationSwipe", "showGCDSwipe", "keybindText", "chargeText", "desaturation", "showOutOfRange", "showTooltips",
    "lossOfControl", "unusableDimming", "iconTint", "assistedHighlight", "procGlow", "auraIndicator", "readyGlow", "keyPressHighlight",
    "barIcon", "barActiveAura", "barColor", "barCooldownColor", "barChargeColor", "barBgColor", "barNameText", "barReadyText",
    "textFont", "textColors", "textBackground",
}

-- Zero-modal path to per-button overrides (owner ruling 2026-07-18):
-- pick an eligible section here to promote it for this entry directly,
-- without going through a panel-tab badge.
local function AddOverridePicker(scroll, buttonData, group, displayMode)
    local available, order = {}, {}
    for _, sectionId in ipairs(OVERRIDE_SECTION_ORDER) do
        local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
        if sectionDef and sectionDef.modes[displayMode]
            and not (buttonData.overrideSections and buttonData.overrideSections[sectionId])
            and (CanButtonUseConfigOverrideSection(buttonData, sectionId)) then
            available[sectionId] = sectionDef.label
            order[#order + 1] = sectionId
        end
    end
    if #order == 0 then return end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Add Override")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)
    -- No caret: this section has no collapse state, and the left-aligned shape
    -- indents the label as if it had one so it lines up with the sections above.
    ApplyLeftAlignedHeading(heading)

    -- One control with nothing to pair it against, so the left column carries
    -- it alone.
    local pickerLeft = ST._BeginRowGrid(scroll)

    local pickerRow = AddDropdownRow(pickerLeft, {
        label = "Setting to override",
        pulloutWidth = PICKER_PULLOUT_WIDTH,
        list = available,
        order = order,
        onChange = function(sectionId)
            if not sectionId then return end
            CooldownCompanion:PromoteSection(buttonData, group.style, sectionId)
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
    -- Set after SetList, which is what the displayed text is read from.
    pickerRow:SetText("Choose…")
end

function ST._BuildOverridesTab(scroll, buttonData, infoButtons)
    -- Function-locals, not upvalues: this function is already close to Lua's
    -- 60-upvalue ceiling (see the note by the row-grammar imports).
    local BeginRowGrid = ST._BeginRowGrid
    local AddRowCheckbox = ST._AddCheckboxRow
    local AddRowSlider = ST._AddSliderRow
    local AnchorRowBadge = ST._AnchorRowBadge

    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local displayMode = group.displayMode or "icons"
    if displayMode == "text" then
        AddTextOverrideSection(scroll, buttonData, group, infoButtons)
    end

    if not buttonData.overrideSections or not next(buttonData.overrideSections) then
        AddOverridePicker(scroll, buttonData, group, displayMode)
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
            local rowMode = builderOpts and builderOpts.row
            BuildIconTintControls(container, styleTable, onChange, {
                row = rowMode,
                isOverride = builderOpts and builderOpts.isOverride,
                fallbackStyle = builderOpts and builderOpts.fallbackStyle,
                showAuraTint = showAuraTint or nil,
            })
            -- The section's two halves: the icon's own tints and the toggles
            -- that reveal them on the left, the backdrop behind it on the right.
            local backgroundHost = (rowMode and builderOpts.rightColumn) or container
            BuildBackgroundColorControls(backgroundHost, styleTable, onChange, nil,
                rowMode and { row = true } or nil)
        end,
        assistedHighlight = BuildAssistedHighlightControls,
        procGlow = BuildProcGlowControls,
        auraIndicator = BuildAuraGlowControls,
        readyGlow = BuildReadyGlowControls,
        keyPressHighlight = BuildKeyPressHighlightControls,
        barIcon = BuildBarIconControls,
        barActiveAura = BuildBarActiveAuraControls,
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
    for _, sectionId in ipairs(OVERRIDE_SECTION_ORDER) do
        if buttonData.overrideSections[sectionId] then
            local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
            local sectionAllowed, sectionUnavailableReason = CanButtonUseConfigOverrideSection(buttonData, sectionId)
            if sectionDef and sectionAllowed and sectionDef.modes[displayMode] then
                visibleOverrideSections = visibleOverrideSections + 1
                local overrideKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_override_" .. sectionId
                local heading, overrideCollapsed = BuildCollapsibleSection(scroll, sectionDef.label, overrideKey,
                    nil, nil, ROW_SECTION)

                local revertBtn = CreateRevertButton(heading, buttonData, sectionId)
                table.insert(infoButtons, revertBtn)

                -- Every override section's preview popout is gone: the
                -- preview command center on the Live Preview surface is
                -- the single home for previews now.
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

                        local builderOpts = {
                            row = true,
                            isOverride = true,
                            fallbackStyle = group.style,
                            masqueEnabled = group.masqueEnabled == true,
                            infoButtons = infoButtons,
                            advancedKey = "overrideSetting_" .. sectionId,
                        }

                        if sectionId == "barActiveAura" then
                            -- This builder opens its OWN two-column grid on the
                            -- container it is handed and returns the columns, so
                            -- it is called on the tab surface directly - the same
                            -- way the custom-bar Effects section calls it.
                            builder(scroll, overrides, refreshCallback, builderOpts)
                        else
                            local left, right = BeginRowGrid(scroll)
                            builderOpts.rightColumn = right

                            if sectionId == "assistedHighlight" and combatOnlyKey then
                                AddRowCheckbox(left, {
                                    label = "Show Only In Combat",
                                    value = overrides[combatOnlyKey] or false,
                                    onChange = function(val)
                                        overrides[combatOnlyKey] = val
                                        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                                    end,
                                })
                            end

                            -- In row mode the glow builders hand this callback
                            -- the grid column the extras belong in (the right
                            -- one), so the when-it-shows rows sit beside the
                            -- what-it-looks-like rows instead of under them.
                            if combatOnlyKey and sectionId ~= "assistedHighlight" then
                                builderOpts.afterEnableCallback = function(cont)
                                    AddRowCheckbox(cont, {
                                        label = "Show Only In Combat",
                                        value = overrides[combatOnlyKey] or false,
                                        onChange = function(val)
                                            overrides[combatOnlyKey] = val
                                            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                                        end,
                                    })

                                    if sectionId == "readyGlow" then
                                        local cappedRow = AddRowCheckbox(cont, {
                                            label = "Glow When Charges Are Capped",
                                            value = GetEffectiveOverrideValue("readyGlowOnlyAtMaxCharges") or false,
                                            onChange = function(val)
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
                                            end,
                                        })
                                        -- Anchor args are a placeholder -
                                        -- AnchorRowBadge re-points the button onto
                                        -- the end of the row's label.
                                        AnchorRowBadge(cappedRow, CreateInfoButton(cappedRow.frame, cappedRow.frame, "LEFT", "LEFT", 0, 0, {
                                            "Glow When Charges Are Capped",
                                            {"When this toggle is enabled, the glow will only appear for charge based spells when at max charges.", 1, 1, 1, true},
                                        }, infoButtons))

                                        AddRowCheckbox(cont, {
                                            label = "Auto-Hide After Duration",
                                            value = (GetEffectiveOverrideValue("readyGlowDuration") or 0) > 0,
                                            onChange = function(val)
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
                                            end,
                                        })

                                        if (GetEffectiveOverrideValue("readyGlowDuration") or 0) > 0 then
                                            AddRowSlider(cont, {
                                                label = "Duration (seconds)",
                                                indent = true,
                                                min = 0.5, max = 5, step = 0.5,
                                                value = GetEffectiveOverrideValue("readyGlowDuration") or 3,
                                                onChange = function(val)
                                                    overrides.readyGlowDuration = val
                                                    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
                                                    CooldownCompanion:RefreshConfigPanel()
                                                end,
                                            })
                                        end
                                    end
                                end
                            end

                            builder(left, overrides, refreshCallback, builderOpts)
                        end

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

    AddOverridePicker(scroll, buttonData, group, displayMode)
end
