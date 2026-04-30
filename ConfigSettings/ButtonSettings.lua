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
local HasTooltipCooldown = ST.HasTooltipCooldown
local AddColorPicker = ST._AddColorPicker
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddOffsetSliders = ST._AddOffsetSliders
local HookSliderEditBox = ST._HookSliderEditBox
local BuildGroupExportData = ST._BuildGroupExportData
local BuildContainerExportData = ST._BuildContainerExportData
local EncodeExportData = ST._EncodeExportData
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior

-- Imports from SectionBuilders.lua (used by BuildOverridesTab)
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
local BuildBarAuraPulseControls = ST._BuildBarAuraPulseControls
local BuildPandemicBarPulseControls = ST._BuildPandemicBarPulseControls
local BuildBarColorsControls = ST._BuildBarColorsControls
local BuildBarNameTextControls = ST._BuildBarNameTextControls
local BuildBarReadyTextControls = ST._BuildBarReadyTextControls
local BuildTextFontControls = ST._BuildTextFontControls
local BuildTextColorsControls = ST._BuildTextColorsControls
local BuildTextBackgroundControls = ST._BuildTextBackgroundControls

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements
local RefreshButtonSettingsMultiSelect = ST._RefreshButtonSettingsMultiSelect
local RefreshPanelMultiSelect = ST._RefreshPanelMultiSelect
local BuildOverridesTab = ST._BuildOverridesTab
local SOUND_ALERT_NONE_OPTION_KEY = "None" -- Keep in sync with Core/SoundAlerts.lua SOUND_NONE_KEY.

local function GroupUsesTexturePanelEntries(group)
    return group and (group.displayMode or "icons") == "textures"
end

local function GroupUsesTriggerPanelEntries(group)
    return group and group.displayMode == "trigger"
end

local function BuildButtonSettingsTabs(group)
    if GroupUsesTriggerPanelEntries(group) then
        return {
            { value = "settings", text = "Condition" },
            { value = "soundalerts", text = "Sound Alerts" },
        }
    end

    local tabs = {
        { value = "settings", text = "Settings" },
        { value = "soundalerts", text = "Sound Alerts" },
    }

    -- Texture panels only ever manage a single texture entry, so the
    -- per-button Overrides tab does not apply there and just creates noise.
    if not GroupUsesTexturePanelEntries(group) then
        tabs[#tabs + 1] = { value = "overrides", text = "Overrides" }
    end

    return tabs
end

local function BuildSortedSoundOptionOrder(soundOptions)
    local order = {}
    for optionKey in pairs(soundOptions) do
        order[#order + 1] = optionKey
    end

    table.sort(order, function(a, b)
        if a == SOUND_ALERT_NONE_OPTION_KEY then return true end
        if b == SOUND_ALERT_NONE_OPTION_KEY then return false end

        local aLabel = soundOptions[a] or tostring(a)
        local bLabel = soundOptions[b] or tostring(b)
        if aLabel == bLabel then
            return tostring(a) < tostring(b)
        end
        return aLabel < bLabel
    end)

    return order
end

local SOUND_PREVIEW_ICON_ATLAS = "chatframe-button-icon-voicechat"
local SOUND_PREVIEW_TEXT_LEFT_OFFSET = 18
local SOUND_PREVIEW_TEXT_RIGHT_OFFSET = -8
local SOUND_PREVIEW_TEXT_GAP = -4
local SOUND_PREVIEW_BUTTON_RIGHT_OFFSET = -18

local function ResetSoundPreviewRow(item)
    if not (item and item.frame and item.text) then return end

    local previewBtn = item._cdcSoundPreviewBtn
    if previewBtn then
        previewBtn:SetShown(false)
        previewBtn._cdcButtonData = nil
        previewBtn._cdcGroup = nil
        previewBtn._cdcSoundValue = nil
        previewBtn:ClearAllPoints()
    end

    item.text:ClearAllPoints()
    item.text:SetPoint("TOPLEFT", item.frame, "TOPLEFT", SOUND_PREVIEW_TEXT_LEFT_OFFSET, 0)
    item.text:SetPoint("BOTTOMRIGHT", item.frame, "BOTTOMRIGHT", SOUND_PREVIEW_TEXT_RIGHT_OFFSET, 0)
end

local function ConfigureSoundPreviewRow(item, buttonData, group)
    if not (item and item.frame and item.text) then return end

    if not item._cdcSoundPreviewCleanupInstalled then
        item._cdcSoundPreviewCleanupInstalled = true
        local prevOnRelease = item.events and item.events["OnRelease"]
        item:SetCallback("OnRelease", function(widget, event)
            if prevOnRelease then
                prevOnRelease(widget, event)
            end
            ResetSoundPreviewRow(widget)
        end)
    end

    local previewBtn = item._cdcSoundPreviewBtn
    if not previewBtn then
        previewBtn = CreateFrame("Button", nil, item.frame)
        previewBtn:SetSize(16, 16)
        previewBtn:SetHighlightAtlas(SOUND_PREVIEW_ICON_ATLAS)
        if previewBtn:GetHighlightTexture() then
            previewBtn:GetHighlightTexture():SetAlpha(0.3)
        end
        local icon = previewBtn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(12, 12)
        icon:SetPoint("CENTER")
        icon:SetAtlas(SOUND_PREVIEW_ICON_ATLAS, false)
        previewBtn._cdcSoundPreviewIcon = icon
        previewBtn:SetScript("OnClick", function(self)
            local previewValue = self._cdcSoundValue
            local previewButtonData = self._cdcButtonData
            local previewGroup = self._cdcGroup
            if previewValue and previewValue ~= SOUND_ALERT_NONE_OPTION_KEY and previewGroup then
                CooldownCompanion:PreviewTriggerPanelSoundAlertSelection(previewGroup, previewValue)
            elseif previewValue and previewValue ~= SOUND_ALERT_NONE_OPTION_KEY and previewButtonData then
                CooldownCompanion:PreviewSoundAlertSelection(previewButtonData, previewValue)
            end
        end)
        item._cdcSoundPreviewBtn = previewBtn
    end

    previewBtn:SetParent(item.frame)
    previewBtn:SetFrameLevel(item.frame:GetFrameLevel() + 1)
    previewBtn:ClearAllPoints()
    previewBtn:SetPoint("RIGHT", item.frame, "RIGHT", SOUND_PREVIEW_BUTTON_RIGHT_OFFSET, 0)
    previewBtn._cdcButtonData = buttonData
    previewBtn._cdcGroup = group

    local previewValue = item.userdata and item.userdata.value
    local hasPreview = previewValue and previewValue ~= SOUND_ALERT_NONE_OPTION_KEY
    previewBtn._cdcSoundValue = hasPreview and previewValue or nil
    previewBtn:SetShown(hasPreview)

    item.text:ClearAllPoints()
    item.text:SetPoint("TOPLEFT", item.frame, "TOPLEFT", SOUND_PREVIEW_TEXT_LEFT_OFFSET, 0)
    if hasPreview then
        item.text:SetPoint("BOTTOMRIGHT", previewBtn, "LEFT", SOUND_PREVIEW_TEXT_GAP, 0)
    else
        item.text:SetPoint("BOTTOMRIGHT", item.frame, "BOTTOMRIGHT", SOUND_PREVIEW_TEXT_RIGHT_OFFSET, 0)
    end
end

local function IsValidAuraUnit(unit)
    return unit == "player" or unit == "target"
end

local function GetDefaultAuraUnit(isHarmful)
    return isHarmful and "target" or "player"
end

local function PrimeSelectedReadyGlowCappedChargeTransition(groupId, buttonIndex)
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    local button = frame and frame.buttons and frame.buttons[buttonIndex]
    local buttonData = button and button.buttonData
    if not (button and buttonData) then
        return
    end

    if buttonData.type ~= "spell"
       or buttonData.hasCharges ~= true
       or buttonData._hasDisplayCount then
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

local function EnsureAuraUnitChoice(buttonData, isHarmful, unit)
    if IsValidAuraUnit(unit) then
        buttonData.auraUnit = unit
    elseif not IsValidAuraUnit(buttonData.auraUnit) then
        buttonData.auraUnit = GetDefaultAuraUnit(isHarmful)
    end
end

local function SetupWrappedStatusLabel(scroll, label, text, justifyH)
    label:SetFullWidth(true)
    label:SetJustifyH(justifyH or "LEFT")
    local contentWidth = scroll.content and scroll.content:GetWidth()
    if contentWidth and contentWidth > 0 then
        label:SetWidth(math.max(1, contentWidth - 20))
    end
    label:SetText(text)
end

local function BuildAuraTrackingSettingsSection(scroll, buttonData, infoButtons, options)
    options = options or {}
    if buttonData.type ~= "spell" then
        return
    end

    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then
        return
    end

    local isHarmful = C_Spell.IsSpellHarmful(buttonData.id)
    local cdmEnabled = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
    local viewerFrame = cdmEnabled and CooldownCompanion:ResolveButtonAuraViewerFrame(buttonData) or nil
    local hasViewerFrame = viewerFrame ~= nil
    local allowPassiveManualRecovery = options.allowPassiveManualRecovery == true
    local showAuraToggle = options.showAuraToggle == true
    local showAuraIconToggle = options.showAuraIconToggle == true
    local showAuraStateLabelWhenToggleHidden = options.showAuraStateLabelWhenToggleHidden == true
    local useCollapse = options.useCollapse == true
    local showHeading = options.showHeading ~= false

    -- Auto-enable aura tracking for viewer-backed spells.
    if hasViewerFrame and buttonData.auraTracking == nil then
        buttonData.auraTracking = true
        local overrideBuffs = CooldownCompanion.ABILITY_BUFF_OVERRIDES[buttonData.id]
        if overrideBuffs and not buttonData.auraSpellID then
            buttonData.auraSpellID = overrideBuffs
        end
        EnsureAuraUnitChoice(buttonData, isHarmful)
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end

    local auraStatus = CooldownCompanion:ResolveAuraTrackingConfigStatus(
        buttonData,
        cdmEnabled,
        viewerFrame
    )
    local auraConfigReady = auraStatus.ready == true
    local auraFoundButUntracked = auraStatus.state == "associatedAuraNotTracked"
    local auraTrackedButUnavailable = auraStatus.state == "trackedAuraUnavailable"
    local auraInactiveColorCode = auraFoundButUntracked and "|cffffff00" or "|cffff0000"
    local isAuraEntry = buttonData.addedAs == "aura"

    if showHeading then
        local auraHeading = AceGUI:Create("Heading")
        auraHeading:SetText("Aura Tracking")
        ColorHeading(auraHeading)
        auraHeading:SetFullWidth(true)
        scroll:AddChild(auraHeading)

        local auraHeadingInfoBtn = CreateInfoButton(auraHeading.frame, auraHeading.label, "LEFT", "RIGHT", 4, 0, {
            "Aura Tracking",
            {"Shows the tracked aura's remaining duration on the cooldown swipe instead of the spell's normal cooldown.", 1, 1, 1, true},
            " ",
            "Requires:",
            {"- Blizzard Cooldown Manager (CDM) must be enabled.", 1, 1, 1, true},
            {"- In Edit Mode, the CDM Buffs/Debuffs visibility setting must be set to Always Visible.", 1, 1, 1, true},
            {"- The aura you want must be tracked in CDM as a Tracked Buff or Tracked Bar, not only as a cooldown.", 1, 1, 1, true},
            " ",
            "Can:",
            {"- Read aura data only from Player or Target.", 1, 1, 1, true},
            " ",
            "Cannot:",
            {"- Track auras that are not present in Blizzard CDM.", 1, 1, 1, true},
            " ",
            {"If you do not want CDM visible on your screen, use the CDM hide toggle in the top-right of the config.", 1, 1, 1, true},
            " ",
            {"Using other CDM-related addons alongside Cooldown Companion may interfere with aura tracking.", 1, 1, 1, true},
        }, infoButtons)

        if useCollapse then
            local auraCollapsed = CS.collapsedSections[options.collapsedKey]
            local auraCollapseBtn = AttachCollapseButton(auraHeading, auraCollapsed, function()
                CS.collapsedSections[options.collapsedKey] = not CS.collapsedSections[options.collapsedKey]
                CooldownCompanion:RefreshConfigPanel()
            end)
            auraCollapseBtn:ClearAllPoints()
            auraCollapseBtn:SetPoint("LEFT", auraHeadingInfoBtn, "RIGHT", 4, 0)
            auraHeading.right:ClearAllPoints()
            auraHeading.right:SetPoint("RIGHT", auraHeading.frame, "RIGHT", -3, 0)
            auraHeading.right:SetPoint("LEFT", auraCollapseBtn, "RIGHT", 4, 0)
            if auraCollapsed then
                return
            end
        else
            auraHeading.right:ClearAllPoints()
            auraHeading.right:SetPoint("RIGHT", auraHeading.frame, "RIGHT", -3, 0)
            auraHeading.right:SetPoint("LEFT", auraHeadingInfoBtn, "RIGHT", 4, 0)
        end
    end

    if buttonData.cdmChildSlot then
        local slotLabel = AceGUI:Create("Label")
        local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
        local slotChild = allChildren and allChildren[buttonData.cdmChildSlot]
        local oid = slotChild and slotChild.cooldownInfo and slotChild.cooldownInfo.overrideSpellID
        local slotText = "|cff88bbddCDM Slot: " .. buttonData.cdmChildSlot .. "|r"
        if oid and oid ~= buttonData.id then
            local info = C_Spell.GetSpellInfo(oid)
            if info and info.name then
                slotText = slotText .. " (" .. info.name .. ")"
            end
        end
        slotLabel:SetText(slotText)
        slotLabel:SetFullWidth(true)
        scroll:AddChild(slotLabel)
    end

    local auraLabel = "Aura Tracking"
    auraLabel = auraLabel .. (auraConfigReady and ": |cff00ff00Active|r" or ": " .. auraInactiveColorCode .. "Inactive|r")

    if showAuraToggle and not buttonData.isPassive and not isAuraEntry then
        local auraCb = AceGUI:Create("CheckBox")
        auraCb:SetLabel(auraLabel)
        auraCb:SetValue(buttonData.auraTracking == true)
        auraCb:SetFullWidth(true)
        auraCb:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.auraTracking = value and true or false
            if value then
                EnsureAuraUnitChoice(buttonData, isHarmful)
            end
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(auraCb)
    elseif showAuraStateLabelWhenToggleHidden then
        local auraStateLabel = AceGUI:Create("Label")
        auraStateLabel:SetText(auraLabel)
        auraStateLabel:SetFullWidth(true)
        scroll:AddChild(auraStateLabel)
    end

    local showAuraDetails = buttonData.isPassive or isAuraEntry or buttonData.auraTracking == true
    if not showAuraDetails then
        return
    end

    local allowManualAuraConfig = not buttonData.isPassive or allowPassiveManualRecovery

    local function StartAuraSpellOverridePicker()
        local grp = CS.selectedGroup
        local btn = CS.selectedButton
        CS.StartPickCDM(function(spellID)
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if spellID then
                local groups = CooldownCompanion.db.profile.groups
                local selectedGroup = groups[grp]
                if selectedGroup and selectedGroup.buttons and selectedGroup.buttons[btn] then
                    selectedGroup.buttons[btn].auraSpellID = tostring(spellID)
                    if selectedGroup.buttons[btn].auraTracking then
                        EnsureAuraUnitChoice(selectedGroup.buttons[btn], isHarmful)
                    end
                end
            end
            CooldownCompanion:RefreshGroupFrame(grp)
            CooldownCompanion:RefreshConfigPanel()
        end)
    end

    if allowManualAuraConfig then
        local auraEditBox = AceGUI:Create("EditBox")
        if auraEditBox.editbox.Instructions then
            auraEditBox.editbox.Instructions:Hide()
        end
        auraEditBox:SetLabel("Spell ID Override")
        auraEditBox:SetText(buttonData.auraSpellID and tostring(buttonData.auraSpellID) or "")
        auraEditBox:SetFullWidth(true)
        auraEditBox:SetCallback("OnEnterPressed", function(widget, _, text)
            text = text:gsub("%s", "")
            if text ~= "" then
                for token in text:gmatch("[^,]+") do
                    if not tonumber(token) then
                        CooldownCompanion:Print("Invalid spell ID: " .. token)
                        widget:SetText(buttonData.auraSpellID and tostring(buttonData.auraSpellID) or "")
                        return
                    end
                end
            end
            buttonData.auraSpellID = text ~= "" and text or nil
            if buttonData.auraTracking then
                EnsureAuraUnitChoice(buttonData, isHarmful)
            end
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(auraEditBox)

        CreateInfoButton(auraEditBox.frame, auraEditBox.frame, "TOPLEFT", "TOPLEFT", auraEditBox.label:GetStringWidth() + 4, -2, {
            "Spell ID Override",
            {"Most spells are tracked automatically, but some abilities apply a buff or debuff with a different spell ID than the ability itself. If tracking isn't working, enter the buff/debuff spell ID here. Use commas only when one entry should intentionally watch multiple IDs.\n\nUse \"Pick CDM\" below to visually select a spell from the Cooldown Manager.", 1, 1, 1, true},
        }, infoButtons)

        local overrideCdmSpacer = AceGUI:Create("Label")
        overrideCdmSpacer:SetText(" ")
        overrideCdmSpacer:SetFullWidth(true)
        scroll:AddChild(overrideCdmSpacer)

        if not IsValidAuraUnit(buttonData.auraUnit) then
            buttonData.auraUnit = GetDefaultAuraUnit(isHarmful)
        end

        local auraUnitDrop = AceGUI:Create("Dropdown")
        auraUnitDrop:SetLabel("Aura Unit")
        auraUnitDrop:SetList({
            player = "Player",
            target = "Target",
        }, { "player", "target" })
        auraUnitDrop:SetValue(buttonData.auraUnit)
        auraUnitDrop:SetFullWidth(true)
        auraUnitDrop:SetCallback("OnValueChanged", function(_, _, value)
            if value ~= "player" and value ~= "target" then
                return
            end
            EnsureAuraUnitChoice(buttonData, isHarmful, value)
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(auraUnitDrop)
        CreateInfoButton(auraUnitDrop.frame, auraUnitDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Aura Unit",
            {"This controls where the tracked aura is expected to exist. Use Target for debuffs on your target, or Player for buffs/procs on yourself, even if the button's spell is something else.", 1, 1, 1, true},
        }, infoButtons)

        local auraUnitSpacer = AceGUI:Create("Label")
        auraUnitSpacer:SetText(" ")
        auraUnitSpacer:SetFullWidth(true)
        scroll:AddChild(auraUnitSpacer)
    end

    local cdmToggleBtn = AceGUI:Create("Button")
    cdmToggleBtn:SetText(cdmEnabled and "Blizzard CDM: |cff00ff00Active|r" or "Blizzard CDM: |cffff0000Inactive|r")
    cdmToggleBtn:SetFullWidth(true)
    cdmToggleBtn:SetCallback("OnClick", function()
        local current = C_CVar.GetCVarBool("cooldownViewerEnabled") == true
        C_CVar.SetCVar("cooldownViewerEnabled", current and "0" or "1")
        CooldownCompanion:RefreshConfigPanel()
        if not current then
            C_Timer.After(0.2, function()
                CooldownCompanion:BuildViewerAuraMap()
                CooldownCompanion:RefreshConfigPanel()
            end)
        end
    end)
    scroll:AddChild(cdmToggleBtn)

    local cdmRow = AceGUI:Create("SimpleGroup")
    cdmRow:SetFullWidth(true)
    cdmRow:SetLayout("Flow")

    local openCdmBtn = AceGUI:Create("Button")
    openCdmBtn:SetText("CDM Settings")
    openCdmBtn:SetRelativeWidth(allowManualAuraConfig and 0.5 or 1.0)
    openCdmBtn:SetCallback("OnClick", function()
        if CooldownViewerSettings then
            CooldownViewerSettings:TogglePanel()
        end
    end)
    cdmRow:AddChild(openCdmBtn)

    if allowManualAuraConfig then
        local pickCDMBtn = AceGUI:Create("Button")
        pickCDMBtn:SetText("Pick CDM")
        pickCDMBtn:SetRelativeWidth(0.5)
        pickCDMBtn:SetCallback("OnClick", StartAuraSpellOverridePicker)
        pickCDMBtn:SetCallback("OnEnter", function(widget)
            GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
            GameTooltip:AddLine("Pick from Cooldown Manager")
            GameTooltip:AddLine("Shows a list of Tracked Buff/Tracked Bar auras currently tracked in the Cooldown Manager. Click one to populate the Spell ID Override.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        pickCDMBtn:SetCallback("OnLeave", function()
            GameTooltip:Hide()
        end)
        cdmRow:AddChild(pickCDMBtn)
    end

    scroll:AddChild(cdmRow)

    local auraStatusSpacer1 = AceGUI:Create("Label")
    auraStatusSpacer1:SetText(" ")
    auraStatusSpacer1:SetFullWidth(true)
    scroll:AddChild(auraStatusSpacer1)

    local auraStatusLabel = AceGUI:Create("Label")
    if auraConfigReady then
        SetupWrappedStatusLabel(scroll, auraStatusLabel, "|cff00ff00Aura tracking is active and ready.|r", "CENTER")
    else
        SetupWrappedStatusLabel(scroll, auraStatusLabel, (auraFoundButUntracked and "|cffffff00" or "|cffff0000") .. "Aura tracking is not ready.|r", "CENTER")
    end
    scroll:AddChild(auraStatusLabel)

    local auraStatusSpacer2 = AceGUI:Create("Label")
    auraStatusSpacer2:SetText(" ")
    auraStatusSpacer2:SetFullWidth(true)
    scroll:AddChild(auraStatusSpacer2)

    if auraStatus.state == "cdmDisabled" then
        local cdmDisabledLabel = AceGUI:Create("Label")
        SetupWrappedStatusLabel(scroll, cdmDisabledLabel, "|cff888888Blizzard Cooldown Manager is disabled. Enable it above to allow aura tracking.|r")
        scroll:AddChild(cdmDisabledLabel)
        local cdmDisabledSpacer = AceGUI:Create("Label")
        cdmDisabledSpacer:SetText(" ")
        cdmDisabledSpacer:SetFullWidth(true)
        scroll:AddChild(cdmDisabledSpacer)
    elseif auraStatus.state == "noAssociatedAura" then
        local noAuraLabel = AceGUI:Create("Label")
        SetupWrappedStatusLabel(scroll, noAuraLabel, "|cff888888No associated aura was found for this spell. Use the Spell ID Override above if you want to link it to a specific CDM-trackable aura.|r")
        scroll:AddChild(noAuraLabel)
        local noAuraSpacer = AceGUI:Create("Label")
        noAuraSpacer:SetText(" ")
        noAuraSpacer:SetFullWidth(true)
        scroll:AddChild(noAuraSpacer)
    elseif auraTrackedButUnavailable then
        local viewerUnavailableLabel = AceGUI:Create("Label")
        SetupWrappedStatusLabel(
            scroll,
            viewerUnavailableLabel,
            "|cff888888An associated aura is tracked in Blizzard CDM, but its Buffs/Debuffs viewer is not currently readable. Set the CDM Buffs/Debuffs visibility to Always Visible.|r"
        )
        scroll:AddChild(viewerUnavailableLabel)
        local viewerUnavailableSpacer = AceGUI:Create("Label")
        viewerUnavailableSpacer:SetText(" ")
        viewerUnavailableSpacer:SetFullWidth(true)
        scroll:AddChild(viewerUnavailableSpacer)
    end

    if auraStatus.state == "associatedAuraNotTracked" then
        local auraDisabledLabel = AceGUI:Create("Label")
        SetupWrappedStatusLabel(scroll, auraDisabledLabel, "|cff888888An associated aura was found, but it is not being currently tracked in Blizzard CDM as a Tracked Buff or Tracked Bar.|r")
        scroll:AddChild(auraDisabledLabel)
        local auraDisabledSpacer = AceGUI:Create("Label")
        auraDisabledSpacer:SetText(" ")
        auraDisabledSpacer:SetFullWidth(true)
        scroll:AddChild(auraDisabledSpacer)
    end

    if hasViewerFrame and buttonData.auraTracking and not IsValidAuraUnit(buttonData.auraUnit) then
        -- Preserve explicit player/target choices, but repair legacy invalid values.
        buttonData.auraUnit = GetDefaultAuraUnit(isHarmful)
    end

    if showAuraIconToggle and buttonData.auraTracking and not buttonData.isPassive then
        local auraIconCb = AceGUI:Create("CheckBox")
        auraIconCb:SetLabel("Show Aura Icon")
        auraIconCb:SetValue(buttonData.auraShowAuraIcon == true)
        auraIconCb:SetFullWidth(true)
        auraIconCb:SetCallback("OnValueChanged", function(_, _, value)
            buttonData.auraShowAuraIcon = value and true or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        scroll:AddChild(auraIconCb)
        CreateInfoButton(auraIconCb.frame, auraIconCb.checkbg, "LEFT", "RIGHT",
            auraIconCb.text:GetStringWidth() + 4, 0, {
            "Show Aura Icon",
            {"When enabled, the button icon changes to show the tracked aura's icon while the aura is active. When the aura expires, the normal spell icon is restored.\n\nUseful when the tracked aura has a different icon than the ability itself.", 1, 1, 1, true},
        }, infoButtons)
    end
end

local function BuildSpellSoundAlertsSection(scroll, buttonData, infoButtons)
    local soundHeading = AceGUI:Create("Heading")
    soundHeading:SetText("Sound Alerts")
    ColorHeading(soundHeading)
    soundHeading:SetHeight(22)
    soundHeading:SetFullWidth(true)
    soundHeading.label:ClearAllPoints()
    soundHeading.label:SetPoint("CENTER", soundHeading.frame, "CENTER", 0, 2)
    soundHeading.left:ClearAllPoints()
    soundHeading.left:SetPoint("LEFT", soundHeading.frame, "LEFT", 3, 0)
    soundHeading.left:SetPoint("RIGHT", soundHeading.label, "LEFT", -5, 0)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundHeading.label, "RIGHT", 5, 0)
    scroll:AddChild(soundHeading)

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Sound alerts are played through the Master channel and follow your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundInfoBtn, "RIGHT", 4, 0)

    local validEvents = CooldownCompanion:GetScopedValidSoundAlertEventsForButton(buttonData)
    if not validEvents then
        local noEvents = AceGUI:Create("Label")
        noEvents:SetText("|cff888888No alertable sound events are available for this button under its current entry type, tracking mode, and Blizzard Cooldown Manager mapping.|r")
        noEvents:SetFullWidth(true)
        scroll:AddChild(noEvents)
        return
    end

    local soundOptions = CooldownCompanion:GetSoundAlertOptions()
    local soundOptionOrder = BuildSortedSoundOptionOrder(soundOptions)
    local eventOrder = CooldownCompanion:GetSoundAlertEventOrder()

    for _, eventKey in ipairs(eventOrder) do
        if validEvents[eventKey] then
            local row = AceGUI:Create("SimpleGroup")
            row:SetFullWidth(true)
            row:SetLayout("Flow")

            local soundDrop = AceGUI:Create("Dropdown")
            soundDrop:SetLabel(CooldownCompanion:GetSoundAlertEventLabelForButton(buttonData, eventKey))
            soundDrop:SetList(soundOptions, soundOptionOrder)
            soundDrop:SetValue(CooldownCompanion:GetButtonSoundAlertSelection(buttonData, eventKey))
            soundDrop:SetFullWidth(true)
            soundDrop:SetCallback("OnOpened", function(widget)
                if not widget.pullout then return end

                -- Inline preview: click the sound icon on a row to test that sound
                -- without selecting it or closing the dropdown.
                for _, item in widget.pullout:IterateItems() do
                    ConfigureSoundPreviewRow(item, buttonData)
                end
            end)

            soundDrop:SetCallback("OnValueChanged", function(widget, event, val)
                CooldownCompanion:SetButtonSoundAlertEvent(buttonData, eventKey, val)
                if ST._RefreshColumn2 then
                    ST._RefreshColumn2()
                end
            end)

            row:AddChild(soundDrop)
            scroll:AddChild(row)
        end
    end
end

local function BuildSpellSoundAlertsTab(scroll, buttonData, infoButtons)
    if buttonData.type ~= "spell" then
        local notSpellLabel = AceGUI:Create("Label")
        notSpellLabel:SetText("|cff888888Sound alerts are available for spell buttons only.|r")
        notSpellLabel:SetFullWidth(true)
        scroll:AddChild(notSpellLabel)
        return
    end

    BuildSpellSoundAlertsSection(scroll, buttonData, infoButtons)
end

local function BuildTriggerPanelSoundAlertsTab(scroll, group, buttonData, infoButtons)
    if not (group and group.displayMode == "trigger") then
        return
    end

    local soundHeading = AceGUI:Create("Heading")
    soundHeading:SetText("Sound Alerts")
    ColorHeading(soundHeading)
    soundHeading:SetHeight(22)
    soundHeading:SetFullWidth(true)
    soundHeading.label:ClearAllPoints()
    soundHeading.label:SetPoint("CENTER", soundHeading.frame, "CENTER", 0, 2)
    soundHeading.left:ClearAllPoints()
    soundHeading.left:SetPoint("LEFT", soundHeading.frame, "LEFT", 3, 0)
    soundHeading.left:SetPoint("RIGHT", soundHeading.label, "LEFT", -5, 0)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundHeading.label, "RIGHT", 5, 0)
    scroll:AddChild(soundHeading)

    local soundInfoBtn = CreateInfoButton(soundHeading.frame, soundHeading.label, "LEFT", "RIGHT", 4, 0, {
        "Sound Alerts",
        {"Plays when the trigger texture appears. This is panel-level and not tied to any one condition. Uses the Master channel and follows your game's Master volume setting.", 1, 1, 1, true},
    }, infoButtons)
    soundHeading.right:ClearAllPoints()
    soundHeading.right:SetPoint("RIGHT", soundHeading.frame, "RIGHT", -3, 0)
    soundHeading.right:SetPoint("LEFT", soundInfoBtn, "RIGHT", 4, 0)

    local soundOptions = CooldownCompanion:GetSoundAlertOptions()
    local soundOptionOrder = BuildSortedSoundOptionOrder(soundOptions)

    local row = AceGUI:Create("SimpleGroup")
    row:SetFullWidth(true)
    row:SetLayout("Flow")

    local soundDrop = AceGUI:Create("Dropdown")
    soundDrop:SetLabel(CooldownCompanion:GetTriggerPanelSoundAlertEventLabel("onShow"))
    soundDrop:SetList(soundOptions, soundOptionOrder)
    soundDrop:SetValue(CooldownCompanion:GetTriggerPanelSoundAlertSelection(group, "onShow"))
    soundDrop:SetFullWidth(true)
    soundDrop:SetCallback("OnOpened", function(widget)
        if not widget.pullout then return end
        for _, item in widget.pullout:IterateItems() do
            ConfigureSoundPreviewRow(item, buttonData, group)
        end
    end)
    soundDrop:SetCallback("OnValueChanged", function(_, _, value)
        CooldownCompanion:SetTriggerPanelSoundAlertEvent(group, "onShow", value)
    end)

    row:AddChild(soundDrop)
    scroll:AddChild(row)
end

local function CreateCenteredSubHeading(text)
    local heading = AceGUI:Create("Heading")
    heading:SetText(text)
    ColorHeading(heading)
    heading:SetHeight(22)
    heading:SetFullWidth(true)
    heading.label:ClearAllPoints()
    heading.label:SetPoint("CENTER", heading.frame, "CENTER", 0, 2)
    heading.left:ClearAllPoints()
    heading.left:SetPoint("LEFT", heading.frame, "LEFT", 3, 0)
    heading.left:SetPoint("RIGHT", heading.label, "LEFT", -5, 0)
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", heading.label, "RIGHT", 5, 0)
    return heading
end

local function BuildTriggerConditionSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then
        return
    end

    CooldownCompanion:NormalizeTriggerConditionRowData(buttonData)
    local clauses = CooldownCompanion:GetTriggerConditionClauses(buttonData)

    local auraSettingsAttached = false
    for clauseIndex, clause in ipairs(clauses) do
        scroll:AddChild(CreateCenteredSubHeading("Condition " .. clauseIndex))

        local row = AceGUI:Create("SimpleGroup")
        row:SetFullWidth(true)
        row:SetLayout("Flow")

        local excludedKeys = {}
        for otherIndex, otherClause in ipairs(clauses) do
            if otherIndex ~= clauseIndex then
                excludedKeys[#excludedKeys + 1] = otherClause.key
            end
        end

        local checkOptions, checkOrder = CooldownCompanion:GetTriggerConditionTypeOptions(buttonData, excludedKeys)
        local checkDrop = AceGUI:Create("Dropdown")
        checkDrop:SetLabel("Check")
        checkDrop:SetList(checkOptions, checkOrder)
        checkDrop:SetValue(clause.key)
        checkDrop:SetFullWidth(true)
        checkDrop:SetCallback("OnValueChanged", function(_, _, value)
            CooldownCompanion:SetTriggerConditionKey(buttonData, clauseIndex, value)
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        row:AddChild(checkDrop)

        local expectedOptions, expectedOrder = CooldownCompanion:GetTriggerConditionExpectedOptions(clause.key)
        local stateDrop = AceGUI:Create("Dropdown")
        stateDrop:SetLabel("State")
        stateDrop:SetList(expectedOptions, expectedOrder)
        stateDrop:SetValue(CooldownCompanion:GetTriggerConditionStateValue(buttonData, clauseIndex))
        stateDrop:SetFullWidth(true)
        stateDrop:SetCallback("OnValueChanged", function(_, _, value)
            CooldownCompanion:SetTriggerConditionStateValue(buttonData, value, clauseIndex)
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        row:AddChild(stateDrop)

        scroll:AddChild(row)

        local function AddRemoveConditionRow()
            local removeRow = AceGUI:Create("SimpleGroup")
            removeRow:SetFullWidth(true)
            removeRow:SetLayout("Flow")

            local removeBtn = AceGUI:Create("Button")
            removeBtn:SetText("Remove Condition")
            removeBtn:SetFullWidth(true)
            removeBtn:SetCallback("OnClick", function()
                if CooldownCompanion:RemoveTriggerConditionClause(buttonData, clauseIndex) then
                    CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end
            end)
            removeRow:AddChild(removeBtn)
            scroll:AddChild(removeRow)
        end

        local hasInlineAuraSettings = clause.key == "auraActive"
            and not auraSettingsAttached
            and buttonData.type == "spell"
            and (buttonData.auraTracking == true or buttonData.isPassive == true or buttonData.addedAs == "aura")

        if #clauses > 1 and not hasInlineAuraSettings then
            AddRemoveConditionRow()
        end

        if hasInlineAuraSettings then
            BuildAuraTrackingSettingsSection(scroll, buttonData, infoButtons, {
                allowPassiveManualRecovery = true,
                showAuraToggle = false,
                showAuraIconToggle = false,
                showAuraStateLabelWhenToggleHidden = false,
                showHeading = false,
                useCollapse = false,
            })
            auraSettingsAttached = true

            if #clauses > 1 then
                AddRemoveConditionRow()
            end
        end

        local conditionSpacer = AceGUI:Create("Label")
        conditionSpacer:SetText(" ")
        conditionSpacer:SetFullWidth(true)
        scroll:AddChild(conditionSpacer)
    end

    local usedKeys = {}
    for _, clause in ipairs(clauses) do
        usedKeys[#usedKeys + 1] = clause.key
    end
    local addOptions, addOrder = CooldownCompanion:GetTriggerConditionTypeOptions(buttonData, usedKeys)
    if #addOrder > 0 then
        scroll:AddChild(CreateCenteredSubHeading("Add Condition"))

        local addRow = AceGUI:Create("SimpleGroup")
        addRow:SetFullWidth(true)
        addRow:SetLayout("Flow")

        local addDrop = AceGUI:Create("Dropdown")
        addDrop:SetLabel("New Condition")
        addDrop:SetList(addOptions, addOrder)
        addDrop:SetValue(addOrder[1])
        addDrop:SetFullWidth(true)
        addRow:AddChild(addDrop)

        local addBtn = AceGUI:Create("Button")
        addBtn:SetText("Add Condition")
        addBtn:SetFullWidth(true)
        addBtn:SetCallback("OnClick", function()
            if CooldownCompanion:AddTriggerConditionClause(buttonData, addDrop:GetValue()) then
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
        addRow:AddChild(addBtn)

        scroll:AddChild(addRow)
    end

end

local function BuildSpellSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    if buttonData.type == "spell" then
        BuildAuraTrackingSettingsSection(scroll, buttonData, infoButtons, {
            allowPassiveManualRecovery = false,
            showAuraToggle = true,
            showAuraIconToggle = true,
            showAuraStateLabelWhenToggleHidden = false,
            useCollapse = true,
            collapsedKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_aura",
        })
    end -- buttonData.type == "spell"

    -- Charge text settings now live in group Appearance tab (with per-button overrides)
end

local function BuildItemSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    -- Charge text settings now live in group Appearance tab (with per-button overrides)
    if UsesChargeBehavior(buttonData) then return end

    local itemHeading = AceGUI:Create("Heading")
    itemHeading:SetText("Item Settings")
    ColorHeading(itemHeading)
    itemHeading:SetFullWidth(true)
    scroll:AddChild(itemHeading)

    local itemKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_itemsettings"
    local itemCollapsed = CS.collapsedSections[itemKey]
    local itemCollapseBtn = AttachCollapseButton(itemHeading, itemCollapsed, function()
        CS.collapsedSections[itemKey] = not CS.collapsedSections[itemKey]
        CooldownCompanion:RefreshConfigPanel()
    end)


    if not itemCollapsed then
    -- Item count font size
    local itemFontSizeSlider = AceGUI:Create("Slider")
    itemFontSizeSlider:SetLabel("Item Stack Font Size")
    itemFontSizeSlider:SetSliderValues(8, 32, 1)
    itemFontSizeSlider:SetValue(buttonData.itemCountFontSize or 12)
    itemFontSizeSlider:SetFullWidth(true)
    itemFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountFontSize = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemFontSizeSlider)

    -- Item count font
    local itemFontDrop = AceGUI:Create("Dropdown")
    itemFontDrop:SetLabel("Font")
    CS.SetupFontDropdown(itemFontDrop)
    itemFontDrop:SetValue(buttonData.itemCountFont or "Friz Quadrata TT")
    itemFontDrop:SetFullWidth(true)
    itemFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountFont = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemFontDrop)

    -- Item count font outline
    local itemOutlineDrop = AceGUI:Create("Dropdown")
    itemOutlineDrop:SetLabel("Font Outline")
    itemOutlineDrop:SetList(CS.outlineOptions)
    itemOutlineDrop:SetValue(buttonData.itemCountFontOutline or "OUTLINE")
    itemOutlineDrop:SetFullWidth(true)
    itemOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountFontOutline = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemOutlineDrop)

    -- Item count font color
    local refreshGroup = function() CooldownCompanion:RefreshGroupFrame(CS.selectedGroup) end
    AddColorPicker(scroll, buttonData, "itemCountFontColor", "Font Color", {1, 1, 1, 1}, true, refreshGroup)

    -- Item count anchor point
    local barNoIcon = group.displayMode == "bars" and not (group.style.showBarIcon ~= false)
    local defItemAnchor = barNoIcon and "BOTTOM" or "BOTTOMRIGHT"
    local defItemX = barNoIcon and 0 or -2
    local defItemY = 2

    AddAnchorDropdown(scroll, buttonData, "itemCountAnchor", defItemAnchor, refreshGroup, "Anchor Point")

    -- Item count X offset
    local itemXSlider = AceGUI:Create("Slider")
    itemXSlider:SetLabel("X Offset")
    itemXSlider:SetSliderValues(-20, 20, 0.1)
    itemXSlider:SetValue(buttonData.itemCountXOffset or defItemX)
    itemXSlider:SetFullWidth(true)
    itemXSlider:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountXOffset = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemXSlider)

    -- Item count Y offset
    local itemYSlider = AceGUI:Create("Slider")
    itemYSlider:SetLabel("Y Offset")
    itemYSlider:SetSliderValues(-20, 20, 0.1)
    itemYSlider:SetValue(buttonData.itemCountYOffset or defItemY)
    itemYSlider:SetFullWidth(true)
    itemYSlider:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountYOffset = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemYSlider)

    end -- not itemCollapsed

end

local function BuildEquipItemSettings(scroll, buttonData, infoButtons)
    -- Currently no equip-item-specific settings
end

------------------------------------------------------------------------
-- TYPE CLASSIFICATION (for batch visibility)
------------------------------------------------------------------------
local function GetButtonEntryType(buttonData)
    if buttonData.type == "item" then return "item" end
    if buttonData.addedAs == "aura" then return "aura" end
    if buttonData.addedAs == "spell" then return "spell" end
    return buttonData.isPassive and "aura" or "spell"
end

local function GetMultiSelectUniformType(group, multiIndices)
    local firstType
    for _, idx in ipairs(multiIndices) do
        local bd = group.buttons[idx]
        if not bd then return nil end
        local t = GetButtonEntryType(bd)
        if not firstType then
            firstType = t
        elseif t ~= firstType then
            return nil
        end
    end
    return firstType
end

------------------------------------------------------------------------
-- BUTTON SETTINGS COLUMN: Refresh
------------------------------------------------------------------------

local function RefreshButtonSettingsColumn()
    local cf = CS.configFrame
    if not cf then return end
    local bsCol = cf.col3
    if not bsCol or not bsCol.bsTabGroup then return end

    -- Check for multiselect
    local multiCount = 0
    local multiIndices = {}
    if CS.selectedGroup then
        for idx in pairs(CS.selectedButtons) do
            multiCount = multiCount + 1
            table.insert(multiIndices, idx)
        end
    end

    if multiCount >= 2 then
        -- Multiselect: hide tabs and placeholder, show dedicated scroll
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end

        if not bsCol.multiSelectScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(bsCol.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", bsCol.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", bsCol.content, "BOTTOMRIGHT", 0, 0)
            bsCol.multiSelectScroll = scroll
        end
        bsCol.multiSelectScroll:ReleaseChildren()
        bsCol.multiSelectScroll.frame:Show()
        local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
        local uniformType = group and GetMultiSelectUniformType(group, multiIndices) or nil
        RefreshButtonSettingsMultiSelect(bsCol.multiSelectScroll, multiCount, multiIndices, uniformType)
        return
    end

    -- Hide multiselect scroll when not in multiselect mode
    if bsCol.multiSelectScroll then
        bsCol.multiSelectScroll.frame:Hide()
    end

    -- Check if a valid single button is selected
    local hasSelection = false
    if CS.selectedGroup and CS.selectedButton then
        local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
        if group and group.buttons[CS.selectedButton] then
            hasSelection = true
        end
    end

    if hasSelection then
        local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
        bsCol.bsTabGroup:SetTabs(BuildButtonSettingsTabs(group))

        if GroupUsesTriggerPanelEntries(group)
            and CS.buttonSettingsTab ~= "settings"
            and CS.buttonSettingsTab ~= "soundalerts" then
            CS.buttonSettingsTab = "settings"
        elseif GroupUsesTexturePanelEntries(group) and CS.buttonSettingsTab == "overrides" then
            CS.buttonSettingsTab = "settings"
        end

        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end
        bsCol.bsTabGroup.frame:Show()
        bsCol.bsTabGroup:SelectTab(CS.buttonSettingsTab or "settings")
    else
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then
            local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
            bsCol.bsPlaceholder:SetText(GroupUsesTriggerPanelEntries(group) and "Select an entry to configure" or "Select a spell or item to configure")
            bsCol.bsPlaceholder:Show()
        end
    end
end

local function ConfigureInlineEditBoxInstructions(editBoxWidget, placeholderText, currentValue)
    local editFrame = editBoxWidget.editbox
    local instructions = editFrame._cdcInstructions
    if not instructions then
        instructions = editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        instructions:SetPoint("LEFT", editFrame, "LEFT", 0, 0)
        instructions:SetPoint("RIGHT", editFrame, "RIGHT", 0, 0)
        instructions:SetTextColor(0.5, 0.5, 0.5)
        editFrame._cdcInstructions = instructions
    end

    instructions:SetText(placeholderText)
    if (currentValue or "") ~= "" then
        instructions:Hide()
    else
        instructions:Show()
    end

    local prevOnRelease = editBoxWidget.events and editBoxWidget.events["OnRelease"]
    editBoxWidget:SetCallback("OnRelease", function(widget)
        if prevOnRelease then
            prevOnRelease(widget, "OnRelease")
        end
        instructions:Hide()
        instructions:SetText("")
    end)

    editBoxWidget:SetCallback("OnTextChanged", function(widget, event, text)
        if text == "" then
            instructions:Show()
        else
            instructions:Hide()
        end
    end)
end

local function BuildCustomNameSection(scroll, buttonData)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group or group.displayMode ~= "bars" then return end

    local customNameHeading = AceGUI:Create("Heading")
    customNameHeading:SetText("Custom Name")
    ColorHeading(customNameHeading)
    customNameHeading:SetFullWidth(true)
    scroll:AddChild(customNameHeading)

    local customNameKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_customname"
    local customNameCollapsed = CS.collapsedSections[customNameKey]

    AttachCollapseButton(customNameHeading, customNameCollapsed, function()
        CS.collapsedSections[customNameKey] = not CS.collapsedSections[customNameKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not customNameCollapsed then
        local customNameBox = AceGUI:Create("EditBox")
        customNameBox:SetLabel("")
        customNameBox:SetText(buttonData.customName or "")
        customNameBox:SetFullWidth(true)
        customNameBox:SetCallback("OnEnterPressed", function(widget, event, text)
            text = strtrim(text)
            buttonData.customName = text ~= "" and text or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        scroll:AddChild(customNameBox)

        ConfigureInlineEditBoxInstructions(
            customNameBox,
            "add custom name here, leave blank for default",
            buttonData.customName
        )
    end -- not customNameCollapsed
end

local function BuildCustomKeybindSection(scroll, buttonData)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group or group.displayMode ~= "icons" then return end

    local effectiveStyle = CooldownCompanion:GetEffectiveStyle(group.style or {}, buttonData)
    if not (effectiveStyle and effectiveStyle.showKeybindText) then
        return
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Custom Keybind Text")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local collapseKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_customkeybind"
    local isCollapsed = CS.collapsedSections[collapseKey]

    AttachCollapseButton(heading, isCollapsed, function()
        CS.collapsedSections[collapseKey] = not CS.collapsedSections[collapseKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not isCollapsed then
        local customKeybindBox = AceGUI:Create("EditBox")
        customKeybindBox:SetLabel("")
        customKeybindBox:SetText(buttonData.customKeybindText or "")
        customKeybindBox:SetFullWidth(true)
        customKeybindBox:SetCallback("OnEnterPressed", function(widget, event, text)
            text = strtrim(text)
            buttonData.customKeybindText = text ~= "" and text or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        scroll:AddChild(customKeybindBox)

        ConfigureInlineEditBoxInstructions(
            customKeybindBox,
            "add custom keybind text here, leave blank for default",
            buttonData.customKeybindText
        )
    end
end

-- Expose for Config.lua
ST._BuildSpellSettings = BuildSpellSettings
ST._BuildItemSettings = BuildItemSettings
ST._BuildEquipItemSettings = BuildEquipItemSettings
ST._RefreshButtonSettingsColumn = RefreshButtonSettingsColumn
ST._RefreshButtonSettingsMultiSelect = RefreshButtonSettingsMultiSelect
ST._RefreshPanelMultiSelect = RefreshPanelMultiSelect
ST._BuildCustomNameSection = BuildCustomNameSection
ST._BuildCustomKeybindSection = BuildCustomKeybindSection
ST._BuildOverridesTab = BuildOverridesTab
ST._BuildSpellSoundAlertsTab = BuildSpellSoundAlertsTab
ST._BuildTriggerPanelSoundAlertsTab = BuildTriggerPanelSoundAlertsTab
ST._BuildTriggerConditionSettings = BuildTriggerConditionSettings
