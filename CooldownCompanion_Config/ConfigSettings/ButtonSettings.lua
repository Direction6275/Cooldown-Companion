local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local math_pi = math.pi
local RB = ST._RB or {}

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
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local BindConfigShiftTooltip = ST._BindConfigShiftTooltip
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior
local NormalizeItemFallbacks = CooldownCompanion.NormalizeItemFallbacks
local UpdateItemChargeMetadata = CooldownCompanion.UpdateItemChargeMetadata

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
local DEFAULT_CUSTOM_AURA_MAX_COLOR = RB.DEFAULT_CUSTOM_AURA_MAX_COLOR or { 1, 0.84, 0 }

local function GroupUsesTexturePanelEntries(group)
    return group and (group.displayMode or "icons") == "textures"
end

local function GroupUsesTriggerPanelEntries(group)
    return group and group.displayMode == "trigger"
end

local function BuildButtonSettingsTabs(group, buttonData)
    local isEquipmentSlot = CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData)
    if GroupUsesTriggerPanelEntries(group) then
        local tabs = {
            { value = "settings", text = "Condition" },
            { value = "loadconditions", text = "Load Conditions" },
        }
        if not isEquipmentSlot then
            tabs[#tabs + 1] = { value = "soundalerts", text = "Sound Alerts" }
        end
        return tabs
    end

    local tabs = {
        { value = "settings", text = "Settings" },
    }
    if buttonData and buttonData.type == "item" then
        tabs[#tabs + 1] = { value = "fallbacks", text = "Fallbacks" }
    elseif not isEquipmentSlot then
        tabs[#tabs + 1] = { value = "soundalerts", text = "Sound Alerts" }
    end

    -- Texture panels only ever manage a single texture entry, so the
    -- per-button Overrides tab does not apply there and just creates noise.
    if not GroupUsesTexturePanelEntries(group) then
        tabs[#tabs + 1] = { value = "overrides", text = "Overrides" }
    end
    tabs[#tabs + 1] = { value = "loadconditions", text = "Load Conditions" }

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

local function ConfigurePriorityMoveButton(button, rotation, tooltipTitle, tooltipBody, disabled, onClick)
    local isDisabled = disabled or CS.browseMode
    button:SetSize(18, 18)
    if button.text then
        button.text:Hide()
    end
    if not button.icon then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetPoint("TOPLEFT", 2, -2)
        button.icon:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    if button.highlight then
        button.highlight:Hide()
        button.highlight:SetAlpha(0)
    end
    button.icon:SetAtlas("arrow-short", false)
    button.icon:SetRotation(rotation)
    if button.icon.SetDesaturated then
        button.icon:SetDesaturated(isDisabled == true)
    end
    button.icon:SetVertexColor(1, 0.82, 0, isDisabled and 0.45 or 1)
    button.icon:Show()
    button:SetAlpha(isDisabled and 0.35 or 1)
    button:EnableMouse(true)
    button:SetScript("OnClick", isDisabled and nil or onClick)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipTitle)
        GameTooltip:AddLine(tooltipBody, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:Show()
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
        previewBtn:SetParent(nil)
    end

    item.text:ClearAllPoints()
    item.text:SetPoint("TOPLEFT", item.frame, "TOPLEFT", SOUND_PREVIEW_TEXT_LEFT_OFFSET, 0)
    item.text:SetPoint("BOTTOMRIGHT", item.frame, "BOTTOMRIGHT", SOUND_PREVIEW_TEXT_RIGHT_OFFSET, 0)
end

local function EnsureSoundPreviewRowCleanup(item)
    if not (item and item.SetCallback) then return end

    local releaseCallback = item._cdcSoundPreviewReleaseCallback
    if not releaseCallback then
        releaseCallback = function(widget, event)
            local prevOnRelease = widget._cdcSoundPreviewWrappedOnRelease
            widget._cdcSoundPreviewWrappedOnRelease = nil
            ResetSoundPreviewRow(widget)
            if prevOnRelease then
                prevOnRelease(widget, event)
            end
        end
        item._cdcSoundPreviewReleaseCallback = releaseCallback
    end

    local currentOnRelease = item.events and item.events["OnRelease"]
    if currentOnRelease == releaseCallback then
        return
    end

    item._cdcSoundPreviewWrappedOnRelease = currentOnRelease
    item:SetCallback("OnRelease", releaseCallback)
end

local function ConfigureSoundPreviewRow(item, buttonData, group)
    if not (item and item.frame and item.text) then return end

    EnsureSoundPreviewRowCleanup(item)

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
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText(text)
end

local function RefreshAuraTrackingEntry(groupId)
    if CS.HideAutocomplete then
        CS.HideAutocomplete()
    end
    CooldownCompanion:RefreshGroupFrame(groupId)
    CooldownCompanion:RefreshConfigPanel()
end

local function GetAuraTrackingIDList(buttonData, isAuraEntry)
    local rawIDs = buttonData and buttonData.auraSpellID
    if isAuraEntry then
        rawIDs = CooldownCompanion:GetStandaloneAuraFallbackSpellIDText(buttonData, rawIDs)
    end

    local ids = {}
    local seen = {}
    if rawIDs then
        for id in tostring(rawIDs):gmatch("%d+") do
            local spellID = tonumber(id)
            if spellID and spellID > 0 and not seen[spellID] then
                seen[spellID] = true
                ids[#ids + 1] = spellID
            end
        end
    end
    return ids
end

local function SetAuraTrackingIDList(buttonData, isAuraEntry, ids)
    local normalizedIDs = {}
    local seen = {}
    for _, id in ipairs(ids or {}) do
        local spellID = tonumber(id)
        if spellID and spellID > 0 and not seen[spellID] then
            seen[spellID] = true
            normalizedIDs[#normalizedIDs + 1] = tostring(spellID)
        end
    end

    local rawText = #normalizedIDs > 0 and table.concat(normalizedIDs, ",") or nil
    if isAuraEntry then
        buttonData.auraSpellID = rawText
            and CooldownCompanion:GetStandaloneAuraFallbackSpellIDText(buttonData, rawText)
            or nil
    else
        buttonData.auraSpellID = rawText
    end
end

local function AddAuraTrackingID(buttonData, isAuraEntry, spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then
        return false
    end

    local ids = GetAuraTrackingIDList(buttonData, isAuraEntry)
    for _, existingID in ipairs(ids) do
        if existingID == spellID then
            return false
        end
    end

    ids[#ids + 1] = spellID
    SetAuraTrackingIDList(buttonData, isAuraEntry, ids)
    return true
end

local function TrimAuraTrackingIDText(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function BuildAuraTrackingIDError(token, reason)
    if reason == "ambiguous" then
        return "Multiple CDM auras match " .. token .. ". Pick the specific aura from the dropdown, or enter its aura spell ID."
    end
    return token .. " is not a CDM Tracked Buff/Bar aura."
end

local function IsOriginalStandaloneAuraID(buttonData, spellID)
    spellID = tonumber(spellID)
    if not spellID or not (buttonData and buttonData.addedAs == "aura") then
        return false
    end
    if not CooldownCompanion.GetStandaloneAuraCandidateGroups then
        return false
    end

    local originalAuraIDs = CooldownCompanion:GetStandaloneAuraCandidateGroups(buttonData)
    for _, originalAuraID in ipairs(originalAuraIDs or {}) do
        if spellID == tonumber(originalAuraID) then
            return true
        end
    end
    return false
end

local function ResolveAuraTrackingIDText(rawText, shouldSkipToken)
    local text = TrimAuraTrackingIDText(rawText)
    if text == "" then
        return nil
    end
    if not CS.ResolveCDMAuraAutocompleteEntry then
        return nil, "CDM aura autocomplete is not ready. Try again in a moment."
    end

    local resolvedIDs = {}
    for token in text:gmatch("[^,]+") do
        local cleaned = TrimAuraTrackingIDText(token)
        if cleaned ~= "" then
            local skipToken = shouldSkipToken and shouldSkipToken(cleaned)
            if not skipToken then
                local entry, reason = CS.ResolveCDMAuraAutocompleteEntry(cleaned)
                local spellID = entry and tonumber(entry.id)
                if not spellID or spellID <= 0 then
                    return nil, BuildAuraTrackingIDError(cleaned, reason)
                end
                resolvedIDs[#resolvedIDs + 1] = spellID
            end
        end
    end

    return #resolvedIDs > 0 and resolvedIDs or nil
end

local function AddAuraTrackingIDText(buttonData, isAuraEntry, rawText)
    local resolvedIDs, errorText = ResolveAuraTrackingIDText(rawText, isAuraEntry and function(cleaned)
        local spellID = cleaned:match("^%d+$") and tonumber(cleaned) or nil
        return IsOriginalStandaloneAuraID(buttonData, spellID)
    end or nil)
    if not resolvedIDs then
        if errorText then
            CooldownCompanion:Print(errorText)
        end
        return false
    end

    local ids = GetAuraTrackingIDList(buttonData, isAuraEntry)
    local seen = {}
    for _, spellID in ipairs(ids) do
        seen[spellID] = true
    end

    local added = false
    for _, spellID in ipairs(resolvedIDs) do
        if spellID and spellID > 0 and not seen[spellID] then
            seen[spellID] = true
            ids[#ids + 1] = spellID
            added = true
        end
    end

    if added then
        SetAuraTrackingIDList(buttonData, isAuraEntry, ids)
    end
    return added
end

local function MoveAuraTrackingID(buttonData, isAuraEntry, sourceIndex, targetIndex)
    local ids = GetAuraTrackingIDList(buttonData, isAuraEntry)
    sourceIndex = tonumber(sourceIndex)
    targetIndex = tonumber(targetIndex)
    if not sourceIndex or not targetIndex or sourceIndex < 1 or sourceIndex > #ids then
        return false
    end
    if targetIndex < 1 then targetIndex = 1 end
    if targetIndex > #ids then targetIndex = #ids end
    if targetIndex == sourceIndex then
        return false
    end

    local movedID = table.remove(ids, sourceIndex)
    if not movedID then
        return false
    end
    table.insert(ids, targetIndex, movedID)
    SetAuraTrackingIDList(buttonData, isAuraEntry, ids)
    return true
end

local function RemoveAuraTrackingID(buttonData, isAuraEntry, rowIndex)
    local ids = GetAuraTrackingIDList(buttonData, isAuraEntry)
    rowIndex = tonumber(rowIndex)
    if not rowIndex or rowIndex < 1 or rowIndex > #ids then
        return false
    end
    table.remove(ids, rowIndex)
    SetAuraTrackingIDList(buttonData, isAuraEntry, ids)
    return true
end

local function GetAuraTrackingIDDisplayName(spellID)
    return C_Spell.GetSpellName(spellID) or ("Spell " .. tostring(spellID))
end

local function BuildAuraTrackingIDRowText(spellID, rowIndex)
    return ("%d. %s |cff888888%s|r"):format(
        rowIndex,
        GetAuraTrackingIDDisplayName(spellID),
        tostring(spellID)
    )
end

local function ShowAuraTrackingIDRowMenu(buttonData, isAuraEntry, rowIndex)
    if CS.browseMode then
        return
    end

    if not CS.auraIDContextMenu then
        CS.auraIDContextMenu = CreateFrame("Frame", "CDCAuraIDContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.auraIDContextMenu, function(_, level)
        if level ~= 1 then return end
        local info = UIDropDownMenu_CreateInfo()
        info.text = "|cffff4444Delete|r"
        info.notCheckable = true
        info.registerForAnyClick = true
        info.func = function()
            CloseDropDownMenus()
            if RemoveAuraTrackingID(buttonData, isAuraEntry, rowIndex) then
                RefreshAuraTrackingEntry(CS.selectedGroup)
            end
        end
        UIDropDownMenu_AddButton(info, level)
    end, "MENU")
    CS.auraIDContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.auraIDContextMenu, "cursor", 0, 0)
end

local function EnsureAuraTrackingIDMoveButtons(entry, buttonData, isAuraEntry, rowIndex, rowCount)
    local frame = entry.frame
    local upBtn = frame._cdcPriorityUpBtn
    if not upBtn then
        upBtn = CreateFrame("Button", nil, frame)
        frame._cdcPriorityUpBtn = upBtn
    end
    local downBtn = frame._cdcPriorityDownBtn
    if not downBtn then
        downBtn = CreateFrame("Button", nil, frame)
        frame._cdcPriorityDownBtn = downBtn
    end

    upBtn:ClearAllPoints()
    upBtn:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
    upBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
    ConfigurePriorityMoveButton(
        upBtn,
        math_pi / 2,
        "Move Up",
        "Move this spell ID one priority slot higher.",
        rowIndex <= 1,
        function()
            if MoveAuraTrackingID(buttonData, isAuraEntry, rowIndex, rowIndex - 1) then
                RefreshAuraTrackingEntry(CS.selectedGroup)
            end
        end
    )

    downBtn:ClearAllPoints()
    downBtn:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    downBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
    ConfigurePriorityMoveButton(
        downBtn,
        -math_pi / 2,
        "Move Down",
        "Move this spell ID one priority slot lower.",
        rowIndex >= rowCount,
        function()
            if MoveAuraTrackingID(buttonData, isAuraEntry, rowIndex, rowIndex + 1) then
                RefreshAuraTrackingEntry(CS.selectedGroup)
            end
        end
    )
end

local function InstallAuraTrackingIDRowMenu(entry, buttonData, isAuraEntry, rowIndex)
    entry.frame:SetScript("OnMouseUp", function(_, button)
        if CS.browseMode then
            return
        end
        if button == "RightButton" then
            ShowAuraTrackingIDRowMenu(buttonData, isAuraEntry, rowIndex)
        end
    end)
end

local function CreateAuraTrackingIDRow(scroll, buttonData, isAuraEntry, spellID, rowIndex, rowCount)
    local row = AceGUI:Create("InteractiveLabel")
    local icon = C_Spell.GetSpellTexture(spellID) or 134400
    CleanRecycledEntry(row)
    row:SetText(BuildAuraTrackingIDRowText(spellID, rowIndex))
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlightSmall)
    row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    ApplyConfigRowIcon(row, icon, { rightPad = 48 })
    if BindConfigShiftTooltip then
        BindConfigShiftTooltip(row, "spell", spellID, row.frame, "ANCHOR_RIGHT")
    end
    row._cdcAfterConfigRowLayout = function(self)
        local frame = self.frame
        local label = self.label
        local image = self.image
        self:SetHeight(22)
        frame:SetHeight(22)
        frame.height = 22
        if image then
            image:ClearAllPoints()
            image:SetTexture(icon)
            image:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            image:SetSize(18, 18)
            image:SetPoint("LEFT", frame, "LEFT", 2, 0)
            image:Show()
        end
        if label then
            label:ClearAllPoints()
            label:SetPoint("LEFT", frame, "LEFT", 24, 0)
            label:SetPoint("RIGHT", frame, "RIGHT", -48, 0)
            label:SetJustifyH("LEFT")
            label:SetJustifyV("MIDDLE")
            if label.SetWordWrap then
                label:SetWordWrap(false)
            end
            if label.SetNonSpaceWrap then
                label:SetNonSpaceWrap(false)
            end
            if label.SetMaxLines then
                label:SetMaxLines(1)
            end
        end
    end
    row:_cdcAfterConfigRowLayout()
    EnsureAuraTrackingIDMoveButtons(row, buttonData, isAuraEntry, rowIndex, rowCount)
    InstallAuraTrackingIDRowMenu(row, buttonData, isAuraEntry, rowIndex)
    scroll:AddChild(row)
    return row
end

local function EnsureButtonSettingsAuraBar(buttonData)
    if type(buttonData.auraBar) ~= "table" then
        buttonData.auraBar = {}
    end
    return buttonData.auraBar
end

local function RefreshSelectedBarPanelAuraDisplay(options)
    CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    if options and options.updateCooldowns then
        CooldownCompanion:UpdateAllCooldowns()
    end
    if options and options.refreshConfig then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function RefreshSelectedBarPanelAuraButton()
    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[CS.selectedGroup]
    local button = frame and frame.buttons and frame.buttons[CS.selectedButton]
    if not button then
        return
    end

    if CooldownCompanion.RefreshBarPanelAuraStackVisual then
        CooldownCompanion:RefreshBarPanelAuraStackVisual(button)
    end
    CooldownCompanion:UpdateButtonCooldown(button)
end

local function AddButtonSettingsSubHeading(scroll, text, infoButtons, tooltipLines)
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
    scroll:AddChild(heading)

    if tooltipLines then
        local tooltip = { text }
        for _, line in ipairs(tooltipLines) do
            tooltip[#tooltip + 1] = line
        end
        local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, tooltip, infoButtons)
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)
    end
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
    local isAuraEntry = buttonData.addedAs == "aura"
    local allowPassiveManualRecovery = options.allowPassiveManualRecovery == true
    local showAuraToggle = options.showAuraToggle == true
    local showAuraIconToggle = options.showAuraIconToggle == true
    local showAuraStateLabelWhenToggleHidden = options.showAuraStateLabelWhenToggleHidden == true
    local useCollapse = options.useCollapse == true
    local showHeading = options.showHeading ~= false
    local isIconGroup = group and (group.displayMode or "icons") == "icons"

    -- Auto-enable aura tracking for viewer-backed spells.
    if hasViewerFrame and buttonData.auraTracking == nil then
        buttonData.auraTracking = true
        local overrideBuffs = CooldownCompanion.ABILITY_BUFF_OVERRIDES[buttonData.id]
        if overrideBuffs and not isAuraEntry and not buttonData.auraSpellID then
            buttonData.auraSpellID = overrideBuffs
        end
        EnsureAuraUnitChoice(buttonData, isHarmful)
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end

    if isAuraEntry then
        buttonData.auraSpellID = CooldownCompanion:GetStandaloneAuraFallbackSpellIDText(buttonData)
        buttonData.auraKeepSpellCooldownSwipe = nil
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
    local auraIdFieldLabel = isAuraEntry and "Additional Auras" or "Tracked Auras"
    local auraIdFieldTooltip = isAuraEntry
        and "The original aura is checked first. Add CDM tracked auras here when another aura should also count for this entry.\n\nUse arrows to set additional aura priority. Right-click a row to delete it. Use \"Pick CDM\" below to visually select an aura from the Cooldown Manager."
        or "Most spells are tracked automatically, but some abilities apply a buff or debuff with a different aura ID than the spell itself. Search for CDM tracked auras by name, or enter CDM aura spell IDs, to choose which auras should count for this spell.\n\nUse arrows to set tracked aura priority. Right-click a row to delete it. Use \"Pick CDM\" below to visually select an aura from the Cooldown Manager."

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
        ST._ConfigureWrappedHelperLabel(slotLabel)
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
        ST._ConfigureWrappedHelperLabel(auraStateLabel)
        auraStateLabel:SetText(auraLabel)
        auraStateLabel:SetFullWidth(true)
        scroll:AddChild(auraStateLabel)
    end

    local showAuraDetails = buttonData.isPassive or isAuraEntry or buttonData.auraTracking == true
    if not showAuraDetails then
        return
    end

    local allowManualAuraConfig = isAuraEntry or not buttonData.isPassive or allowPassiveManualRecovery

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
                    local selectedButton = selectedGroup.buttons[btn]
                    AddAuraTrackingID(selectedButton, isAuraEntry, spellID)
                    if selectedButton.auraTracking then
                        EnsureAuraUnitChoice(selectedButton, isHarmful)
                    end
                end
            end
            CooldownCompanion:RefreshGroupFrame(grp)
            CooldownCompanion:RefreshConfigPanel()
        end)
    end

    if allowManualAuraConfig then
        local auraIDList = GetAuraTrackingIDList(buttonData, isAuraEntry)
        local auraEditBox = AceGUI:Create("EditBox")
        if auraEditBox.editbox.Instructions then
            auraEditBox.editbox.Instructions:Hide()
        end
        auraEditBox:SetLabel(auraIdFieldLabel)
        auraEditBox:SetText("")
        auraEditBox:DisableButton(true)
        auraEditBox:SetFullWidth(true)
        local function CommitAuraTrackingEntry(widget, entry)
            CS.HideAutocomplete()
            if not (entry and AddAuraTrackingIDText(buttonData, isAuraEntry, tostring(entry.id))) then
                return
            end
            widget:SetText("")
            if buttonData.auraTracking then
                EnsureAuraUnitChoice(buttonData, isHarmful)
            end
            RefreshAuraTrackingEntry(CS.selectedGroup)
        end
        auraEditBox:SetCallback("OnTextChanged", function(widget, _, text)
            if CS.browseMode then
                CS.HideAutocomplete()
                return
            end
            if text and #text >= 1 and CS.SearchCDMAuraAutocomplete then
                CS.ShowAutocompleteResults(CS.SearchCDMAuraAutocomplete(text), widget, function(entry)
                    CommitAuraTrackingEntry(widget, entry)
                end, { requireExactNumericEnter = true })
            else
                CS.HideAutocomplete()
            end
        end)
        auraEditBox:SetCallback("OnEnterPressed", function(widget, _, text)
            if CS.browseMode then
                CS.HideAutocomplete()
                return
            end
            if CS.ConsumeAutocompleteEnter and CS.ConsumeAutocompleteEnter() then
                return
            end
            CS.HideAutocomplete()
            if not AddAuraTrackingIDText(buttonData, isAuraEntry, text) then
                return
            end
            widget:SetText("")
            if buttonData.auraTracking then
                EnsureAuraUnitChoice(buttonData, isHarmful)
            end
            RefreshAuraTrackingEntry(CS.selectedGroup)
        end)
        if CS.SetupAutocompleteKeyHandler then
            CS.SetupAutocompleteKeyHandler(auraEditBox)
        end
        scroll:AddChild(auraEditBox)

        CreateInfoButton(auraEditBox.frame, auraEditBox.frame, "TOPLEFT", "TOPLEFT", auraEditBox.label:GetStringWidth() + 4, -2, {
            auraIdFieldLabel,
            {auraIdFieldTooltip, 1, 1, 1, true},
        }, infoButtons)

        for index, spellID in ipairs(auraIDList) do
            CreateAuraTrackingIDRow(scroll, buttonData, isAuraEntry, spellID, index, #auraIDList)
        end

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
            {"This is an entry-wide setting. It controls where every Tracked Aura or Additional Aura on this entry is expected to exist. Use Target for debuffs on your target, or Player for buffs/procs on yourself, even if the button's spell is something else.", 1, 1, 1, true},
        }, infoButtons)

        local auraUnitSpacer = AceGUI:Create("Label")
        auraUnitSpacer:SetText(" ")
        auraUnitSpacer:SetFullWidth(true)
        scroll:AddChild(auraUnitSpacer)
    end

    if not cdmEnabled then
        local cdmToggleBtn = AceGUI:Create("Button")
        cdmToggleBtn:SetText("Blizzard CDM: |cffff0000Inactive|r")
        cdmToggleBtn:SetFullWidth(true)
        cdmToggleBtn:SetCallback("OnClick", function()
            C_CVar.SetCVar("cooldownViewerEnabled", "1")
            CooldownCompanion:RefreshConfigPanel()
            C_Timer.After(0.2, function()
                CooldownCompanion:BuildViewerAuraMap()
                CooldownCompanion:RefreshConfigPanel()
            end)
        end)
        scroll:AddChild(cdmToggleBtn)
    end

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
            GameTooltip:AddLine("Shows a list of Tracked Buff/Tracked Bar auras currently tracked in the Cooldown Manager. Click one to add it to " .. auraIdFieldLabel .. ".", 1, 1, 1, true)
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
        local noAuraText = isAuraEntry
            and "|cff888888No associated aura was found. Add an additional aura above if another CDM-trackable aura should count for this entry.|r"
            or "|cff888888No associated aura was found for this spell. Use Tracked Auras above to link it to a specific CDM-trackable aura.|r"
        SetupWrappedStatusLabel(scroll, noAuraLabel, noAuraText)
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

        if isIconGroup and not isAuraEntry then
            local keepCooldownSwipeCb = AceGUI:Create("CheckBox")
            keepCooldownSwipeCb:SetLabel("Keep Spell Cooldown Swipe")
            keepCooldownSwipeCb:SetValue(buttonData.auraKeepSpellCooldownSwipe == true)
            keepCooldownSwipeCb:SetFullWidth(true)
            keepCooldownSwipeCb:SetCallback("OnValueChanged", function(_, _, value)
                buttonData.auraKeepSpellCooldownSwipe = value and true or nil
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            scroll:AddChild(keepCooldownSwipeCb)
            CreateInfoButton(keepCooldownSwipeCb.frame, keepCooldownSwipeCb.checkbg, "LEFT", "RIGHT",
                keepCooldownSwipeCb.text:GetStringWidth() + 4, 0, {
                "Keep Spell Cooldown Swipe",
                {"When checked, the icon keeps showing the spell's normal cooldown swipe while Aura Tracking is active. The tracked aura can still update aura-facing behavior like the aura icon, glow, visibility, and stack text.\n\nUnchecked keeps the current behavior where the tracked aura duration replaces the normal cooldown swipe.", 1, 1, 1, true},
            }, infoButtons)
        end
    end
end

local function BuildBarPanelAuraDisplaySection(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group or group.displayMode ~= "bars" then
        return
    end
    if not CooldownCompanion:IsBarPanelAuraDisplayEligible(buttonData) then
        return
    end

    local auraBar = type(buttonData.auraBar) == "table" and buttonData.auraBar or {}
    local displayKind = CooldownCompanion:GetBarPanelAuraDisplayKind(buttonData)
    local isStackDisplay = displayKind == "stacks"
    local stackDisplayMode = CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData)

    AddButtonSettingsSubHeading(scroll, "Aura Display Mode", infoButtons, {
        {"Determines how the tracked aura is displayed on this bar panel entry.", 1, 1, 1, true},
        " ",
        {"Active: shows the aura's remaining duration while it is active.", 1, 1, 1, true},
        " ",
        {"Stack Count: ignores duration and shows only the aura's current stack count.", 1, 1, 1, true},
    })

    local trackingDrop = AceGUI:Create("Dropdown")
    trackingDrop:SetList({
        active = "Active",
        stacks = "Stack Count",
    }, { "active", "stacks" })
    trackingDrop:SetValue(displayKind)
    trackingDrop:SetFullWidth(true)
    trackingDrop:SetCallback("OnValueChanged", function(_, _, value)
        CooldownCompanion:SetBarPanelAuraDisplayKind(buttonData, value)
        RefreshSelectedBarPanelAuraDisplay({ updateCooldowns = true, refreshConfig = true })
    end)
    scroll:AddChild(trackingDrop)

    if not isStackDisplay then
        return
    end
    auraBar = EnsureButtonSettingsAuraBar(buttonData)

    local maxStacksSlider = AceGUI:Create("Slider")
    maxStacksSlider:SetLabel("Max Stacks")
    maxStacksSlider:SetSliderValues(1, 99, 1)
    maxStacksSlider:SetValue(CooldownCompanion:GetBarPanelAuraMaxStacks(buttonData))
    maxStacksSlider:SetFullWidth(true)
    local pendingMaxStacks = CooldownCompanion:GetBarPanelAuraMaxStacks(buttonData)
    local function NormalizeMaxStacks(value)
        return math.max(1, math.min(99, math.floor((tonumber(value) or pendingMaxStacks or 1) + 0.5)))
    end
    local function CommitMaxStacks(value)
        local committedValue = NormalizeMaxStacks(value)
        if CooldownCompanion:GetBarPanelAuraMaxStacks(buttonData) == committedValue then
            return
        end
        CooldownCompanion:SetBarPanelAuraMaxStacks(buttonData, committedValue)
        RefreshSelectedBarPanelAuraButton()
    end
    maxStacksSlider:SetCallback("OnValueChanged", function(_, _, value)
        pendingMaxStacks = NormalizeMaxStacks(value)
    end)
    maxStacksSlider:SetCallback("OnMouseUp", function(_, _, value)
        CommitMaxStacks(value)
    end)
    HookSliderEditBox(maxStacksSlider)
    scroll:AddChild(maxStacksSlider)

    local displayModeDrop = AceGUI:Create("Dropdown")
    displayModeDrop:SetLabel("Display Mode")
    displayModeDrop:SetList({
        continuous = "Continuous",
        segmented = "Segmented",
        overlay = "Overlay",
    }, { "continuous", "segmented", "overlay" })
    displayModeDrop:SetValue(stackDisplayMode)
    displayModeDrop:SetFullWidth(true)
    displayModeDrop:SetCallback("OnValueChanged", function(_, _, value)
        CooldownCompanion:SetBarPanelAuraStackDisplayMode(buttonData, value)
        if value ~= "continuous" and auraBar.maxStacksGlowStyle == "pulsingOverlay" then
            auraBar.maxStacksGlowStyle = "solidBorder"
        end
        RefreshSelectedBarPanelAuraDisplay({ updateCooldowns = true, refreshConfig = true })
    end)
    scroll:AddChild(displayModeDrop)

    local stackTextFormatDrop = AceGUI:Create("Dropdown")
    stackTextFormatDrop:SetLabel("Stack Text Format")
    stackTextFormatDrop:SetList({
        current = "Current Value",
        current_max = "Current / Max",
    }, { "current", "current_max" })
    stackTextFormatDrop:SetValue(CooldownCompanion:GetBarPanelAuraStackTextFormat(buttonData))
    stackTextFormatDrop:SetFullWidth(true)
    stackTextFormatDrop:SetCallback("OnValueChanged", function(_, _, value)
        CooldownCompanion:SetBarPanelAuraStackTextFormat(buttonData, value)
        RefreshSelectedBarPanelAuraButton()
    end)
    scroll:AddChild(stackTextFormatDrop)

    if stackDisplayMode == "segmented" or stackDisplayMode == "overlay" then
        local segmentedSmoothingDrop = AceGUI:Create("Dropdown")
        segmentedSmoothingDrop:SetLabel("Segmented Smoothing")
        segmentedSmoothingDrop:SetList({
            [ST.SEGMENTED_SMOOTHING_ON] = "On",
            [ST.SEGMENTED_SMOOTHING_OFF] = "Off",
        }, { ST.SEGMENTED_SMOOTHING_ON, ST.SEGMENTED_SMOOTHING_OFF })
        segmentedSmoothingDrop:SetValue(CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(buttonData))
        segmentedSmoothingDrop:SetFullWidth(true)
        segmentedSmoothingDrop:SetCallback("OnValueChanged", function(_, _, value)
            CooldownCompanion:SetBarPanelAuraSegmentedSmoothing(buttonData, value)
            RefreshSelectedBarPanelAuraDisplay({ updateCooldowns = true })
        end)
        scroll:AddChild(segmentedSmoothingDrop)
        CreateInfoButton(segmentedSmoothingDrop.frame, segmentedSmoothingDrop.label, "LEFT", "RIGHT", 4, 0, {
            "Segmented Smoothing",
            {"Controls whether this entry's segmented or overlay Stack Count bar smooths changes or snaps immediately.", 1, 1, 1, true},
            " ",
            {"Continuous Stack Count bars are not affected.", 1, 1, 1, true},
        }, segmentedSmoothingDrop)

        local segmentGapSlider = AceGUI:Create("Slider")
        segmentGapSlider:SetLabel("Segment Gap")
        segmentGapSlider:SetSliderValues(0, 20, 0.1)
        segmentGapSlider:SetValue(CooldownCompanion:GetBarPanelAuraSegmentGap(buttonData))
        segmentGapSlider:SetFullWidth(true)
        segmentGapSlider:SetCallback("OnValueChanged", function(_, _, value)
            CooldownCompanion:SetBarPanelAuraSegmentGap(buttonData, value)
            RefreshSelectedBarPanelAuraButton()
        end)
        scroll:AddChild(segmentGapSlider)
    end

    if stackDisplayMode == "overlay" then
        AddButtonSettingsSubHeading(scroll, "Colors")
        AddColorPicker(scroll, auraBar, "overlayColor", "Overlay Color", {1, 0.84, 0, 1}, true,
            function() RefreshSelectedBarPanelAuraDisplay({ updateCooldowns = true }) end)
    end

    AddButtonSettingsSubHeading(scroll, "Max Stack Settings")
    local thresholdCb = AceGUI:Create("CheckBox")
    thresholdCb:SetLabel("Enable Max Stack Color")
    thresholdCb:SetValue(auraBar.thresholdColorEnabled == true)
    thresholdCb:SetFullWidth(true)
    thresholdCb:SetCallback("OnValueChanged", function(_, _, value)
        auraBar.thresholdColorEnabled = value and true or nil
        RefreshSelectedBarPanelAuraDisplay({ updateCooldowns = true, refreshConfig = true })
    end)
    scroll:AddChild(thresholdCb)

    if auraBar.thresholdColorEnabled == true then
        AddColorPicker(scroll, auraBar, "thresholdMaxColor", "Max Stack Color", DEFAULT_CUSTOM_AURA_MAX_COLOR, false,
            function() RefreshSelectedBarPanelAuraDisplay({ updateCooldowns = true }) end)
    end

    local indicatorCb = AceGUI:Create("CheckBox")
    indicatorCb:SetLabel("Max Stack Indicator")
    indicatorCb:SetValue(auraBar.maxStacksGlowEnabled == true)
    indicatorCb:SetFullWidth(true)
    indicatorCb:SetCallback("OnValueChanged", function(_, _, value)
        auraBar.maxStacksGlowEnabled = value and true or nil
        RefreshSelectedBarPanelAuraDisplay({ updateCooldowns = true, refreshConfig = true })
    end)
    scroll:AddChild(indicatorCb)

    local function BuildMaxStackIndicatorAdvanced(panel)
        local currentStyle = auraBar.maxStacksGlowStyle or "solidBorder"
        local isContinuousDisplay = stackDisplayMode == "continuous"
        if currentStyle == "pulsingOverlay" and not isContinuousDisplay then
            currentStyle = "solidBorder"
        end

        local styleList = {
            solidBorder = "Solid Border",
            pulsingBorder = "Pulsing Border",
        }
        local styleOrder = { "solidBorder", "pulsingBorder" }
        if isContinuousDisplay then
            styleList.pulsingOverlay = "Pulsing Overlay"
            styleOrder = { "solidBorder", "pulsingBorder", "pulsingOverlay" }
        end

        local indicatorStyleDrop = AceGUI:Create("Dropdown")
        indicatorStyleDrop:SetLabel("Indicator Style")
        indicatorStyleDrop:SetList(styleList, styleOrder)
        indicatorStyleDrop:SetValue(currentStyle)
        indicatorStyleDrop:SetFullWidth(true)
        indicatorStyleDrop:SetCallback("OnValueChanged", function(_, _, value)
            auraBar.maxStacksGlowStyle = value
            RefreshSelectedBarPanelAuraDisplay({ updateCooldowns = true, refreshConfig = true })
        end)
        panel:AddChild(indicatorStyleDrop)

        AddColorPicker(panel, auraBar, "maxStacksGlowColor", "Indicator Color", {1, 0.84, 0, 0.9}, true,
            function() RefreshSelectedBarPanelAuraDisplay({ updateCooldowns = true }) end)

        if currentStyle ~= "pulsingOverlay" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Border Size")
            sizeSlider:SetSliderValues(1, 8, 1)
            sizeSlider:SetValue(auraBar.maxStacksGlowSize or 2)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(_, _, value)
                auraBar.maxStacksGlowSize = value
                RefreshSelectedBarPanelAuraButton()
            end)
            panel:AddChild(sizeSlider)
        end

        if currentStyle == "pulsingBorder" or currentStyle == "pulsingOverlay" then
            local speedSlider = AceGUI:Create("Slider")
            speedSlider:SetLabel("Pulse Duration")
            speedSlider:SetSliderValues(0.1, 2.0, 0.1)
            speedSlider:SetValue(auraBar.maxStacksGlowSpeed or 0.5)
            speedSlider:SetFullWidth(true)
            speedSlider:SetCallback("OnValueChanged", function(_, _, value)
                auraBar.maxStacksGlowSpeed = value
                RefreshSelectedBarPanelAuraButton()
            end)
            panel:AddChild(speedSlider)
        end
    end

    local indicatorAdvExpanded, indicatorAdvBtn = AddAdvancedToggle(indicatorCb, "barPanelAuraMaxStacksIndicator_" .. CS.selectedGroup .. "_" .. CS.selectedButton, infoButtons, auraBar.maxStacksGlowEnabled == true, {
        title = "Max Stack Indicator Advanced",
        build = BuildMaxStackIndicatorAdvanced,
    })
    CreateInfoButton(indicatorCb.frame, indicatorAdvBtn, "LEFT", "RIGHT", 4, 0, {
        "Max Stack Indicator",
        {"Due to combat restrictions, individual bar segments cannot be highlighted independently.", 1, 1, 1, true},
        " ",
        {"The indicator covers the whole bar entry and appears automatically when the aura reaches its maximum stack count.", 1, 1, 1, true},
        " ",
        {"The Pulsing Overlay style is only available for continuous display mode.", 1, 1, 1, true},
    }, indicatorCb)

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
        ST._ConfigureWrappedHelperLabel(noEvents)
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
        ST._ConfigureWrappedHelperLabel(notSpellLabel)
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
        BuildBarPanelAuraDisplaySection(scroll, buttonData, infoButtons)
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
    CS.SetFontDropdownCallback(itemFontDrop, function(widget, event, val)
        buttonData.itemCountFont = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemFontDrop)

    -- Item count font outline
    local itemOutlineDrop = AceGUI:Create("Dropdown")
    itemOutlineDrop:SetLabel("Font Outline")
    CS.SetupFontOutlineDropdown(itemOutlineDrop)
    itemOutlineDrop:SetValue(buttonData.itemCountFontOutline or "OUTLINE")
    itemOutlineDrop:SetFullWidth(true)
    CS.SetFontOutlineDropdownCallback(itemOutlineDrop, function(widget, event, val)
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

local function RefreshFallbackEntry(groupId)
    if CS.HideAutocomplete then
        CS.HideAutocomplete()
    end
    CooldownCompanion:RefreshGroupFrame(groupId)
    CooldownCompanion:RefreshConfigPanel()
end

local function GetItemFallbackName(itemID)
    return C_Item.GetItemNameByID(itemID) or ("Item " .. tostring(itemID))
end

local function GetItemQualityAtlas(itemID)
    local qualityInfo = C_TradeSkillUI.GetItemCraftedQualityInfo(itemID)
        or C_TradeSkillUI.GetItemReagentQualityInfo(itemID)
    return qualityInfo and qualityInfo.iconSmall or nil
end

local function GetItemFallbackDisplayName(itemID)
    local itemName = GetItemFallbackName(itemID)
    local qualityAtlas = GetItemQualityAtlas(itemID)
    if qualityAtlas then
        return ("%s |A:%s:20:20|a"):format(itemName, qualityAtlas)
    end
    return itemName
end

local function IsExistingFallback(buttonData, itemID)
    if type(buttonData.itemFallbacks) ~= "table" then
        return false
    end
    for _, existingID in ipairs(buttonData.itemFallbacks) do
        if tonumber(existingID) == itemID then
            return true
        end
    end
    return false
end

local function ValidateFallbackItem(buttonData, itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return nil, "Enter a valid item ID."
    end
    if itemID == tonumber(buttonData.id) then
        return nil, "That item is already the primary item."
    end
    if IsExistingFallback(buttonData, itemID) then
        return nil, "That fallback is already listed."
    end

    if not C_Item.IsItemDataCachedByID(itemID) then
        C_Item.RequestLoadItemDataByID(itemID)
        return nil, "Loading item data. Try again in a moment."
    end

    if CooldownCompanion.IsItemEquippable({ id = itemID }) then
        return nil, "Fallbacks only support non-equippable consumable items."
    end

    if not C_Item.GetItemSpell(itemID) then
        return nil, "Fallback item must have a usable effect."
    end

    return itemID
end

local function IsFallbackAutocompleteCandidate(buttonData, itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then
        return false
    end
    if itemID == tonumber(buttonData.id) or IsExistingFallback(buttonData, itemID) then
        return false
    end
    if CooldownCompanion.IsItemEquippable({ id = itemID }) then
        return false
    end
    return C_Item.GetItemSpell(itemID) ~= nil
end

local function BuildFallbackAutocompleteCache(buttonData)
    local cache = {}
    local seen = {}
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local containerInfo = C_Container.GetContainerItemInfo(bag, slot)
            local itemID = containerInfo and containerInfo.itemID
            if itemID and not seen[itemID] and IsFallbackAutocompleteCandidate(buttonData, itemID) then
                seen[itemID] = true
                local itemName = containerInfo.itemName or C_Item.GetItemNameByID(itemID) or ("Item " .. tostring(itemID))
                local displayName = GetItemFallbackDisplayName(itemID)
                cache[#cache + 1] = {
                    id = itemID,
                    name = displayName,
                    nameLower = itemName:lower(),
                    icon = containerInfo.iconFileID or C_Item.GetItemIconByID(itemID) or 134400,
                    category = "Bag",
                    isItem = true,
                }
            end
        end
    end
    return cache
end

local function SearchFallbackAutocomplete(buttonData, query)
    if not (CS.SearchAutocompleteInCache and query and #query >= 1) then
        return nil
    end
    return CS.SearchAutocompleteInCache(query, BuildFallbackAutocompleteCache(buttonData))
end

local function AddItemFallback(buttonData, itemID)
    if CS.browseMode then
        return false
    end

    local validID, err = ValidateFallbackItem(buttonData, itemID)
    if not validID then
        CooldownCompanion:Print(err)
        return false
    end

    if not buttonData.itemFallbacks then
        buttonData.itemFallbacks = {}
    end
    buttonData.itemFallbacks[#buttonData.itemFallbacks + 1] = validID
    NormalizeItemFallbacks(buttonData)
    return true
end

local function TryReceiveFallbackItemDrop(buttonData)
    if CS.browseMode then
        return false
    end

    local cursorType, cursorID = GetCursorInfo()
    if cursorType ~= "item" or not cursorID then
        return false
    end

    local added = AddItemFallback(buttonData, cursorID)
    ClearCursor()
    if added then
        RefreshFallbackEntry(CS.selectedGroup)
    end
    return added
end

local function UpdatePrimaryFallbackItem(buttonData, itemID)
    buttonData.id = itemID
    buttonData.name = GetItemFallbackName(itemID)
    buttonData.hasCharges = nil
    buttonData.maxCharges = nil
    UpdateItemChargeMetadata(buttonData, itemID)
end

local function MoveFallbackPriorityItem(buttonData, sourceIndex, targetIndex)
    if CS.browseMode then
        return false
    end

    if not (buttonData and buttonData.type == "item") then
        return false
    end
    local fallbackIDs = buttonData.itemFallbacks
    if type(fallbackIDs) ~= "table" then
        fallbackIDs = {}
    end

    local count = #fallbackIDs
    sourceIndex = tonumber(sourceIndex)
    targetIndex = tonumber(targetIndex)
    if not sourceIndex or not targetIndex or sourceIndex < 0 or sourceIndex > count then
        return false
    end
    if targetIndex < 0 then targetIndex = 0 end
    if targetIndex > count then targetIndex = count end
    if targetIndex == sourceIndex then
        return false
    end

    local orderedIDs = { tonumber(buttonData.id) }
    for _, rawID in ipairs(fallbackIDs) do
        orderedIDs[#orderedIDs + 1] = tonumber(rawID)
    end

    local movedID = table.remove(orderedIDs, sourceIndex + 1)
    if not movedID then
        return false
    end
    table.insert(orderedIDs, targetIndex + 1, movedID)

    local newPrimaryID = orderedIDs[1]
    if not (newPrimaryID and newPrimaryID > 0) then
        return false
    end
    if newPrimaryID ~= tonumber(buttonData.id) then
        UpdatePrimaryFallbackItem(buttonData, newPrimaryID)
    end

    local newFallbacks = {}
    for index = 2, #orderedIDs do
        newFallbacks[#newFallbacks + 1] = orderedIDs[index]
    end
    buttonData.itemFallbacks = newFallbacks
    NormalizeItemFallbacks(buttonData)
    return true
end

local function InstallFallbackDropScript(frame, buttonData)
    if not frame or not frame.SetScript then
        return
    end

    if not frame._cdcFallbackDropWrapped and frame.GetScript then
        frame._cdcFallbackOriginalOnReceiveDrag = frame:GetScript("OnReceiveDrag")
        frame._cdcFallbackOriginalOnMouseUp = frame:GetScript("OnMouseUp")
        frame._cdcFallbackDropWrapped = true
    end
    frame._cdcFallbackDropButtonData = buttonData

    frame:SetScript("OnReceiveDrag", function(self, ...)
        local activeButtonData = self._cdcFallbackDropButtonData
        if CS.buttonSettingsTab == "fallbacks" and not CS.browseMode and activeButtonData then
            local cursorType = GetCursorInfo()
            if cursorType == "item" then
                TryReceiveFallbackItemDrop(activeButtonData)
                return
            end
        end
        local original = self._cdcFallbackOriginalOnReceiveDrag
        if original then
            return original(self, ...)
        end
    end)
    frame:SetScript("OnMouseUp", function(self, button, ...)
        local activeButtonData = self._cdcFallbackDropButtonData
        if CS.buttonSettingsTab ~= "fallbacks" or CS.browseMode or button ~= "LeftButton" then
            local original = self._cdcFallbackOriginalOnMouseUp
            if original then
                return original(self, button, ...)
            end
            return
        end
        if GetCursorInfo() and activeButtonData then
            TryReceiveFallbackItemDrop(activeButtonData)
            return
        end

        local original = self._cdcFallbackOriginalOnMouseUp
        if original then
            return original(self, button, ...)
        end
    end)
end

local function InstallFallbackColumnDropTargets(scroll, buttonData)
    local seen = {}
    local function addTarget(frame)
        if frame and not seen[frame] then
            seen[frame] = true
            InstallFallbackDropScript(frame, buttonData)
        end
    end

    addTarget(scroll and scroll.frame)
    addTarget(scroll and scroll.scrollframe)
    addTarget(scroll and scroll.content)

    local parent = scroll and scroll.frame and scroll.frame:GetParent()
    for _ = 1, 4 do
        if not parent then break end
        addTarget(parent)
        parent = parent.GetParent and parent:GetParent() or nil
    end
end

local function BuildFallbackRowText(itemID, rowIndex, isPrimary)
    local displayIndex = isPrimary and 1 or (rowIndex + 1)
    local prefix = tostring(displayIndex) .. ". "
    return ("%s%s"):format(
        prefix,
        GetItemFallbackDisplayName(itemID)
    )
end

local function EnsureFallbackMoveButtons(entry, buttonData, rowIndex, isPrimary)
    local frame = entry.frame
    local upBtn = frame._cdcPriorityUpBtn
    if not upBtn and not isPrimary then
        upBtn = CreateFrame("Button", nil, frame)
        frame._cdcPriorityUpBtn = upBtn
    end
    local downBtn = frame._cdcPriorityDownBtn
    if not downBtn then
        downBtn = CreateFrame("Button", nil, frame)
        frame._cdcPriorityDownBtn = downBtn
    end

    local fallbackIDs = buttonData.itemFallbacks or {}
    if isPrimary then
        if upBtn then
            upBtn:Hide()
        end

        downBtn:ClearAllPoints()
        downBtn:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
        downBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
        ConfigurePriorityMoveButton(
            downBtn,
            -math_pi / 2,
            "Move Down",
            "Swap this primary item with the first fallback.",
            #fallbackIDs == 0,
            function()
                if MoveFallbackPriorityItem(buttonData, 0, 1) then
                    RefreshFallbackEntry(CS.selectedGroup)
                end
            end
        )
        return
    end

    upBtn:ClearAllPoints()
    upBtn:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
    upBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
    ConfigurePriorityMoveButton(
        upBtn,
        math_pi / 2,
        "Move Up",
        rowIndex == 1 and "Make this fallback the primary item." or "Move this fallback one priority slot higher.",
        false,
        function()
            if MoveFallbackPriorityItem(buttonData, rowIndex, rowIndex - 1) then
                RefreshFallbackEntry(CS.selectedGroup)
            end
        end
    )

    downBtn:ClearAllPoints()
    downBtn:SetPoint("RIGHT", frame, "RIGHT", -4, 0)
    downBtn:SetFrameLevel(frame:GetFrameLevel() + 6)
    ConfigurePriorityMoveButton(
        downBtn,
        -math_pi / 2,
        "Move Down",
        "Move this fallback one priority slot lower.",
        rowIndex >= #fallbackIDs,
        function()
            if MoveFallbackPriorityItem(buttonData, rowIndex, rowIndex + 1) then
                RefreshFallbackEntry(CS.selectedGroup)
            end
        end
    )
end

local function ShowFallbackRowMenu(buttonData, rowIndex)
    if CS.browseMode then
        return
    end

    if not CS.fallbackContextMenu then
        CS.fallbackContextMenu = CreateFrame("Frame", "CDCFallbackContextMenu", UIParent, "UIDropDownMenuTemplate")
    end

    UIDropDownMenu_Initialize(CS.fallbackContextMenu, function(_, level)
        if level ~= 1 then return end
        local info = UIDropDownMenu_CreateInfo()
        info.text = "|cffff4444Delete|r"
        info.notCheckable = true
        info.func = function()
            CloseDropDownMenus()
            local fallbackIDs = buttonData.itemFallbacks
            if type(fallbackIDs) == "table" then
                table.remove(fallbackIDs, rowIndex)
                NormalizeItemFallbacks(buttonData)
                RefreshFallbackEntry(CS.selectedGroup)
            end
        end
        UIDropDownMenu_AddButton(info, level)
    end, "MENU")
    CS.fallbackContextMenu:SetFrameStrata("FULLSCREEN_DIALOG")
    ToggleDropDownMenu(1, nil, CS.fallbackContextMenu, "cursor", 0, 0)
end

local function InstallFallbackRowMenu(entry, buttonData, rowIndex)
    entry.frame:SetScript("OnMouseUp", function(_, button)
        if CS.browseMode then
            return
        end
        if button == "RightButton" then
            ShowFallbackRowMenu(buttonData, rowIndex)
            return
        end
        if button == "LeftButton" and GetCursorInfo() then
            TryReceiveFallbackItemDrop(buttonData)
        end
    end)
end

local function CreateFallbackItemRow(scroll, buttonData, itemID, rowIndex, isPrimary)
    local row = AceGUI:Create("InteractiveLabel")
    CleanRecycledEntry(row)
    row:SetText(BuildFallbackRowText(itemID, rowIndex, isPrimary))
    row:SetFullWidth(true)
    row:SetFontObject(GameFontHighlight)
    row:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    ApplyConfigRowIcon(row, C_Item.GetItemIconByID(itemID) or 134400, { rightPad = isPrimary and 28 or 48 })
    if BindConfigShiftTooltip then
        BindConfigShiftTooltip(row, "item", itemID, row.frame, "ANCHOR_RIGHT")
    end

    if isPrimary then
        row:SetColor(1, 1, 1)
        EnsureFallbackMoveButtons(row, buttonData, 0, true)
        InstallFallbackDropScript(row.frame, buttonData)
    else
        EnsureFallbackMoveButtons(row, buttonData, rowIndex, false)
        InstallFallbackRowMenu(row, buttonData, rowIndex)
    end

    scroll:AddChild(row)
    return row
end

local function BuildItemFallbacksTab(scroll, buttonData, infoButtons)
    if not (buttonData and buttonData.type == "item") then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Fallbacks are available for item entries only.")
        label:SetFullWidth(true)
        scroll:AddChild(label)
        return
    end

    if CooldownCompanion.IsItemEquippable(buttonData) then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Fallbacks are available for non-equippable consumable items only.")
        label:SetFullWidth(true)
        scroll:AddChild(label)
        return
    end

    NormalizeItemFallbacks(buttonData)
    InstallFallbackColumnDropTargets(scroll, buttonData)

    local heading = AceGUI:Create("Heading")
    heading:SetText("Item Fallbacks")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    InstallFallbackDropScript(heading.frame, buttonData)
    scroll:AddChild(heading)

    local infoBtn = CreateInfoButton(heading.frame, heading.label, "LEFT", "RIGHT", 4, 0, {
        "Item Fallbacks",
        {"Use arrows to set item priority.", 1, 1, 1, true},
        {"If a higher-priority item is unavailable, the next available fallback can appear instead.", 1, 1, 1, true},
        {" ", 1, 1, 1, true},
        {"Settings apply to whichever item is currently shown from this priority list.", 1, 1, 1, true},
        {"This includes options like zero-use visibility and desaturation.", 1, 1, 1, true},
    }, infoButtons)
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", infoBtn, "RIGHT", 4, 0)

    local primaryID = tonumber(buttonData.id)
    CreateFallbackItemRow(scroll, buttonData, primaryID, 0, true)

    local fallbackIDs = buttonData.itemFallbacks or {}
    if #fallbackIDs > 0 then
        for index, itemID in ipairs(fallbackIDs) do
            CreateFallbackItemRow(scroll, buttonData, itemID, index, false)
        end
    end

    local addBox = AceGUI:Create("EditBox")
    addBox:SetLabel("Search Bag Consumables")
    addBox:SetText("")
    addBox:DisableButton(true)
    addBox:SetFullWidth(true)
    addBox:SetCallback("OnTextChanged", function(widget, _, text)
        if CS.browseMode then
            CS.HideAutocomplete()
            return
        end
        if text and #text >= 1 then
            CS.ShowAutocompleteResults(SearchFallbackAutocomplete(buttonData, text), widget, function(entry)
                if entry and not CS.browseMode and AddItemFallback(buttonData, entry.id) then
                    RefreshFallbackEntry(CS.selectedGroup)
                else
                    CS.HideAutocomplete()
                end
            end)
        else
            CS.HideAutocomplete()
        end
    end)
    addBox:SetCallback("OnEnterPressed", function(widget, _, text)
        if CS.browseMode then
            CS.HideAutocomplete()
            return
        end
        if CS.ConsumeAutocompleteEnter and CS.ConsumeAutocompleteEnter() then
            return
        end
        CS.HideAutocomplete()
        if AddItemFallback(buttonData, text) then
            widget:SetText("")
            RefreshFallbackEntry(CS.selectedGroup)
        end
    end)
    if addBox.editbox and addBox.editbox.Instructions then
        addBox.editbox.Instructions:Hide()
    end
    InstallFallbackDropScript(addBox.frame, buttonData)
    InstallFallbackDropScript(addBox.editbox, buttonData)
    if CS.SetupAutocompleteKeyHandler then
        CS.SetupAutocompleteKeyHandler(addBox)
    end
    scroll:AddChild(addBox)
end

------------------------------------------------------------------------
-- TYPE CLASSIFICATION (for batch visibility)
------------------------------------------------------------------------
local function GetButtonEntryType(buttonData)
    if CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        return "equipmentSlot"
    end
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
        local buttonData = group and group.buttons and group.buttons[CS.selectedButton]
        bsCol.bsTabGroup:SetTabs(BuildButtonSettingsTabs(group, buttonData))
        local isEquipmentSlot = CooldownCompanion.IsEquipmentSlotEntry
            and CooldownCompanion.IsEquipmentSlotEntry(buttonData)

        if GroupUsesTriggerPanelEntries(group)
            and CS.buttonSettingsTab ~= "settings"
            and CS.buttonSettingsTab ~= "loadconditions"
            and (CS.buttonSettingsTab ~= "soundalerts" or isEquipmentSlot) then
            CS.buttonSettingsTab = "settings"
        elseif GroupUsesTexturePanelEntries(group) and CS.buttonSettingsTab == "overrides" then
            CS.buttonSettingsTab = "settings"
        elseif isEquipmentSlot
            and (CS.buttonSettingsTab == "soundalerts" or CS.buttonSettingsTab == "fallbacks") then
            CS.buttonSettingsTab = "settings"
        elseif buttonData and buttonData.type == "item" and CS.buttonSettingsTab == "soundalerts" then
            CS.buttonSettingsTab = "fallbacks"
        elseif buttonData and buttonData.type ~= "item" and CS.buttonSettingsTab == "fallbacks" then
            CS.buttonSettingsTab = "soundalerts"
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
    if CooldownCompanion.IsEquipmentSlotEntry and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        return
    end
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
ST._BuildItemFallbacksTab = BuildItemFallbacksTab
ST._RefreshButtonSettingsColumn = RefreshButtonSettingsColumn
ST._RefreshButtonSettingsMultiSelect = RefreshButtonSettingsMultiSelect
ST._RefreshPanelMultiSelect = RefreshPanelMultiSelect
ST._BuildCustomNameSection = BuildCustomNameSection
ST._BuildCustomKeybindSection = BuildCustomKeybindSection
ST._BuildOverridesTab = BuildOverridesTab
ST._BuildSpellSoundAlertsTab = BuildSpellSoundAlertsTab
ST._BuildTriggerPanelSoundAlertsTab = BuildTriggerPanelSoundAlertsTab
ST._BuildTriggerConditionSettings = BuildTriggerConditionSettings
