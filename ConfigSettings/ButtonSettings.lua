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

-- Imports from panel files (loaded before this file)
local BuildCastBarAnchoringPanel = ST._BuildCastBarAnchoringPanel
local BuildFrameAnchoringPlayerPanel = ST._BuildFrameAnchoringPlayerPanel

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
local BuildAssistedHighlightControls = ST._BuildAssistedHighlightControls
local BuildProcGlowControls = ST._BuildProcGlowControls
local BuildPandemicGlowControls = ST._BuildPandemicGlowControls
local BuildPandemicBarControls = ST._BuildPandemicBarControls
local BuildAuraIndicatorControls = ST._BuildAuraIndicatorControls
local BuildBarActiveAuraControls = ST._BuildBarActiveAuraControls
local BuildBarColorsControls = ST._BuildBarColorsControls
local BuildBarNameTextControls = ST._BuildBarNameTextControls
local BuildBarReadyTextControls = ST._BuildBarReadyTextControls

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

local function BuildSpellSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local isHarmful = buttonData.type == "spell" and C_Spell.IsSpellHarmful(buttonData.id)
    -- Look up viewer frame: for multi-slot buttons, use the slot-specific CDM child
    local viewerFrame
    if buttonData.cdmChildSlot then
        local allChildren = CooldownCompanion.viewerAuraAllChildren[buttonData.id]
        viewerFrame = allChildren and allChildren[buttonData.cdmChildSlot]
    end
    if not viewerFrame and buttonData.auraSpellID then
        for id in tostring(buttonData.auraSpellID):gmatch("%d+") do
            viewerFrame = CooldownCompanion.viewerAuraFrames[tonumber(id)]
            if viewerFrame then break end
        end
    end
    if not viewerFrame then
        local resolvedAuraId = buttonData.type == "spell"
            and C_UnitAuras.GetCooldownAuraBySpellID(buttonData.id)
        viewerFrame = (resolvedAuraId and resolvedAuraId ~= 0
                and CooldownCompanion.viewerAuraFrames[resolvedAuraId])
            or CooldownCompanion.viewerAuraFrames[buttonData.id]
    end

    -- Fallback scan for transforming spells whose override hasn't fired yet
    if not viewerFrame and buttonData.type == "spell" then
        local child = CooldownCompanion:FindViewerChildForSpell(buttonData.id)
        if child then
            CooldownCompanion.viewerAuraFrames[buttonData.id] = child
            viewerFrame = child
        end
    end
    -- Fallback for hardcoded overrides: try the buff IDs in the viewer map
    if not viewerFrame and buttonData.type == "spell" then
        local overrideBuffs = CooldownCompanion.ABILITY_BUFF_OVERRIDES[buttonData.id]
        if overrideBuffs then
            for id in overrideBuffs:gmatch("%d+") do
                viewerFrame = CooldownCompanion.viewerAuraFrames[tonumber(id)]
                if viewerFrame then break end
            end
        end
    end

    -- Only treat as aura-capable if CDM is enabled and viewer is from BuffIcon or BuffBar.
    -- When CDM is disabled, viewer children persist with stale data and cannot be trusted.
    -- (Essential and Utility viewers track cooldowns only, not auras)
    local hasViewerFrame = false
    if viewerFrame and GetCVarBool("cooldownViewerEnabled") then
        local parent = viewerFrame:GetParent()
        local parentName = parent and parent:GetName()
        hasViewerFrame = parentName == "BuffIconCooldownViewer" or parentName == "BuffBarCooldownViewer"
    end

    -- Determine if this spell could theoretically track a buff/debuff.
    -- Query the CDM's authoritative category lists for TrackedBuff and TrackedBar.
    local buffTrackableSpells = {}
    for _, cat in ipairs({Enum.CooldownViewerCategory.TrackedBuff, Enum.CooldownViewerCategory.TrackedBar}) do
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info then
                    buffTrackableSpells[info.spellID] = true
                    if info.overrideSpellID then
                        buffTrackableSpells[info.overrideSpellID] = true
                    end
                    if info.overrideTooltipSpellID then
                        buffTrackableSpells[info.overrideTooltipSpellID] = true
                    end
                end
            end
        end
    end

    local canTrackAura = hasViewerFrame
        or buffTrackableSpells[buttonData.id]
        or (buttonData.auraSpellID and buttonData.auraSpellID ~= "")

    if not canTrackAura and buttonData.type == "spell" then
        if CooldownCompanion.ABILITY_BUFF_OVERRIDES[buttonData.id] then
            canTrackAura = true
        end
    end

    -- Auto-enable aura tracking for viewer-backed spells
    if hasViewerFrame and buttonData.auraTracking == nil then
        buttonData.auraTracking = true
        local overrideBuffs = CooldownCompanion.ABILITY_BUFF_OVERRIDES[buttonData.id]
        if overrideBuffs and not buttonData.auraSpellID then
            buttonData.auraSpellID = overrideBuffs
        end
        if isHarmful then
            buttonData.auraUnit = "target"
        else
            buttonData.auraUnit = nil
        end
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end

    if buttonData.type == "spell" then
    local auraHeading = AceGUI:Create("Heading")
    auraHeading:SetText("Aura Tracking")
    ColorHeading(auraHeading)
    auraHeading:SetFullWidth(true)
    scroll:AddChild(auraHeading)

    local auraKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_aura"
    local auraCollapsed = CS.collapsedSections[auraKey]

    local auraCollapseBtn = AttachCollapseButton(auraHeading, auraCollapsed, function()
        CS.collapsedSections[auraKey] = not CS.collapsedSections[auraKey]
        CooldownCompanion:RefreshConfigPanel()
    end)


    if not auraCollapsed then

    -- CDM slot label for multi-entry spells (read-only info)
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

    -- Track buff/debuff duration toggle (hidden for passives — forced on)
    if not buttonData.isPassive then
    local auraCb = AceGUI:Create("CheckBox")
    local auraLabel = "Track Aura Duration"
    local auraActive = hasViewerFrame and buttonData.auraTracking == true
    auraLabel = auraLabel .. (auraActive and ": |cff00ff00Active|r" or ": |cffff0000Inactive|r")
    auraCb:SetLabel(auraLabel)
    auraCb:SetValue(buttonData.auraTracking == true)
    auraCb:SetFullWidth(true)
    if not hasViewerFrame then
        auraCb:SetDisabled(true)
    end
    auraCb:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.auraTracking = val and true or false
        if val then
            if isHarmful then
                if not buttonData.auraUnit or buttonData.auraUnit == "player" then
                    buttonData.auraUnit = "target"
                end
            elseif buttonData.type == "spell" then
                buttonData.auraUnit = nil
            end
        end
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(auraCb)

    -- (?) tooltip for aura tracking
    local auraWarn = CreateFrame("Button", nil, auraCb.frame)
    auraWarn:SetSize(16, 16)
    auraWarn:SetPoint("LEFT", auraCb.checkbg, "RIGHT", auraCb.text:GetStringWidth() + 4, 0)
    local auraWarnIcon = auraWarn:CreateTexture(nil, "OVERLAY")
    auraWarnIcon:SetSize(12, 12)
    auraWarnIcon:SetPoint("CENTER")
    auraWarnIcon:SetAtlas("QuestRepeatableTurnin")
    auraWarn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if isHarmful then
            GameTooltip:AddLine("Debuff Tracking")
            GameTooltip:AddLine("When enabled, the cooldown swipe shows the remaining debuff or DoT duration on your target instead of the spell's cooldown. When the debuff expires, the normal cooldown display resumes.\n\nThis spell must be tracked as a Buff or Debuff in the Blizzard Cooldown Manager (not just as a Cooldown). The CDM must be active but does not need to be visible.\n\nOnly player buffs and target debuffs are supported.", 1, 1, 1, true)
        else
            GameTooltip:AddLine("Buff Tracking")
            GameTooltip:AddLine("When enabled, the cooldown swipe shows the remaining buff duration on yourself instead of the spell's cooldown. When the buff expires, the normal cooldown display resumes.\n\nThis spell must be tracked as a Buff or Debuff in the Blizzard Cooldown Manager (not just as a Cooldown). The CDM must be active but does not need to be visible.\n\nOnly player buffs and target debuffs are supported.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    auraWarn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(infoButtons, auraWarn)
    if CooldownCompanion.db.profile.hideInfoButtons then
        auraWarn:Hide()
    end
    end -- not buttonData.isPassive

    -- Spell ID Override row (hidden for passive aura buttons)
    if not buttonData.isPassive then
    local overrideRow = AceGUI:Create("SimpleGroup")
    overrideRow:SetFullWidth(true)
    overrideRow:SetLayout("Flow")

    local auraEditBox = AceGUI:Create("EditBox")
    if auraEditBox.editbox.Instructions then auraEditBox.editbox.Instructions:Hide() end
    auraEditBox:SetLabel("Spell ID Override")
    auraEditBox:SetText(buttonData.auraSpellID and tostring(buttonData.auraSpellID) or "")
    auraEditBox:SetRelativeWidth(0.72)
    auraEditBox:SetCallback("OnEnterPressed", function(widget, event, text)
        text = text:gsub("%s", "")
        buttonData.auraSpellID = text ~= "" and text or nil
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    overrideRow:AddChild(auraEditBox)

    local pickCDMBtn = AceGUI:Create("Button")
    pickCDMBtn:SetText("Pick CDM")
    pickCDMBtn:SetRelativeWidth(0.28)
    pickCDMBtn:SetCallback("OnClick", function()
        local grp = CS.selectedGroup
        local btn = CS.selectedButton
        CS.StartPickCDM(function(spellID)
            -- Re-show config panel
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if spellID then
                local groups = CooldownCompanion.db.profile.groups
                local g = groups[grp]
                if g and g.buttons and g.buttons[btn] then
                    g.buttons[btn].auraSpellID = tostring(spellID)
                end
            end
            CooldownCompanion:RefreshGroupFrame(grp)
            CooldownCompanion:RefreshConfigPanel()
        end)
    end)
    pickCDMBtn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
        GameTooltip:AddLine("Pick from Cooldown Manager")
        GameTooltip:AddLine("Click a buff or debuff icon either from the on-screen Cooldown Manager viewer or from the Blizzard CDM Settings panel to populate the Spell ID Override.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pickCDMBtn:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    overrideRow:AddChild(pickCDMBtn)

    scroll:AddChild(overrideRow)

    -- (?) tooltip for override
    local overrideInfo = CreateFrame("Button", nil, auraEditBox.frame)
    overrideInfo:SetSize(16, 16)
    overrideInfo:SetPoint("TOPLEFT", auraEditBox.frame, "TOPLEFT", auraEditBox.label:GetStringWidth() + 4, -2)
    local overrideInfoIcon = overrideInfo:CreateTexture(nil, "OVERLAY")
    overrideInfoIcon:SetSize(12, 12)
    overrideInfoIcon:SetPoint("CENTER")
    overrideInfoIcon:SetAtlas("QuestRepeatableTurnin")
    overrideInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Spell ID Override")
        GameTooltip:AddLine("Most spells are tracked automatically, but some abilities apply a buff or debuff with a different spell ID than the ability itself. If tracking isn't working, enter the buff/debuff spell ID here. Use commas for multiple IDs (e.g. 48517,48518 for both Eclipse forms).\n\nYou can also click \"Pick CDM\" to visually select a spell from the Cooldown Manager.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    overrideInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(infoButtons, overrideInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        overrideInfo:Hide()
    end

    -- Nudge Pick CDM button down to align with editbox
    pickCDMBtn.frame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local p, rel, rp, xOfs, yOfs = self:GetPoint(1)
        if yOfs then
            self:SetPoint(p, rel, rp, xOfs, yOfs - 2)
        end
    end)

    local overrideCdmSpacer = AceGUI:Create("Label")
    overrideCdmSpacer:SetText(" ")
    overrideCdmSpacer:SetFullWidth(true)
    scroll:AddChild(overrideCdmSpacer)
    end -- not buttonData.isPassive (Spell ID Override)

    -- Cooldown Manager controls (always visible for spells)
    local cdmEnabled = GetCVarBool("cooldownViewerEnabled")
    local cdmToggleBtn = AceGUI:Create("Button")
    cdmToggleBtn:SetText(cdmEnabled and "Blizzard CDM: |cff00ff00Active|r" or "Blizzard CDM: |cffff0000Inactive|r")
    cdmToggleBtn:SetFullWidth(true)
    cdmToggleBtn:SetCallback("OnClick", function()
        local current = GetCVarBool("cooldownViewerEnabled")
        SetCVar("cooldownViewerEnabled", current and "0" or "1")
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
    openCdmBtn:SetRelativeWidth(0.5)
    openCdmBtn:SetCallback("OnClick", function()
        CooldownViewerSettings:TogglePanel()
    end)
    cdmRow:AddChild(openCdmBtn)

    local db = CooldownCompanion.db
    local hideCdmBtn = AceGUI:Create("Button")
    hideCdmBtn:SetText("CDM Display")
    hideCdmBtn:SetRelativeWidth(0.5)
    hideCdmBtn:SetCallback("OnClick", function()
        db.profile.cdmHidden = not db.profile.cdmHidden
        CooldownCompanion:ApplyCdmAlpha()
    end)
    hideCdmBtn:SetCallback("OnEnter", function(widget)
        GameTooltip:SetOwner(widget.frame, "ANCHOR_TOP")
        GameTooltip:AddLine("Toggle CDM Display")
        GameTooltip:AddLine("This only toggles the visibility of the Cooldown Manager on your screen. Aura tracking will continue to work regardless.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hideCdmBtn:SetCallback("OnLeave", function()
        GameTooltip:Hide()
    end)
    cdmRow:AddChild(hideCdmBtn)

    scroll:AddChild(cdmRow)

    -- Aura tracking status confirmation (always visible for spells)
    local auraStatusSpacer1 = AceGUI:Create("Label")
    auraStatusSpacer1:SetText(" ")
    auraStatusSpacer1:SetFullWidth(true)
    scroll:AddChild(auraStatusSpacer1)

    local auraStatusLabel = AceGUI:Create("Label")
    if buttonData.auraTracking and cdmEnabled and hasViewerFrame then
        auraStatusLabel:SetText("|cff00ff00Aura tracking is active and ready.|r")
    else
        auraStatusLabel:SetText("|cffff0000Aura tracking is not ready.|r")
    end
    auraStatusLabel:SetFullWidth(true)
    auraStatusLabel:SetJustifyH("CENTER")
    scroll:AddChild(auraStatusLabel)

    local auraStatusSpacer2 = AceGUI:Create("Label")
    auraStatusSpacer2:SetText(" ")
    auraStatusSpacer2:SetFullWidth(true)
    scroll:AddChild(auraStatusSpacer2)

    if not canTrackAura then
        local noAuraLabel = AceGUI:Create("Label")
        noAuraLabel:SetText("|cff888888No associated buff or debuff was found in the Cooldown Manager for this spell. Use the Spell ID Override above to link this spell to a CDM-trackable aura.|r")
        noAuraLabel:SetFullWidth(true)
        scroll:AddChild(noAuraLabel)
        local noAuraSpacer = AceGUI:Create("Label")
        noAuraSpacer:SetText(" ")
        noAuraSpacer:SetFullWidth(true)
        scroll:AddChild(noAuraSpacer)
    end

    if canTrackAura then

    if not hasViewerFrame then
        local auraDisabledLabel = AceGUI:Create("Label")
        auraDisabledLabel:SetText("|cff888888This spell has a trackable aura in the Cooldown Manager, but it has not been added as a tracked buff or debuff yet. Add it in the CDM to enable aura tracking.|r")
        auraDisabledLabel:SetFullWidth(true)
        scroll:AddChild(auraDisabledLabel)
        local auraDisabledSpacer = AceGUI:Create("Label")
        auraDisabledSpacer:SetText(" ")
        auraDisabledSpacer:SetFullWidth(true)
        scroll:AddChild(auraDisabledSpacer)
    end

    if hasViewerFrame and buttonData.auraTracking then
            -- Aura unit: harmful spells track on target, non-harmful track on player.
            -- Viewer only supports player + target, so no dropdown is needed for spells.
            if isHarmful then
                -- Migrate any legacy auraUnit to "target"
                if not buttonData.auraUnit or (buttonData.auraUnit ~= "player" and buttonData.auraUnit ~= "target") then
                    buttonData.auraUnit = "target"
                end
            elseif buttonData.type == "spell" then
                -- Non-harmful spell: always tracks on player
                buttonData.auraUnit = nil
            end

    end -- hasViewerFrame and auraTracking
    end -- canTrackAura
    end -- not auraCollapsed


    end -- buttonData.type == "spell"

    -- Charge text settings now live in group Appearance tab (with per-button overrides)
end

local function BuildItemSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    -- Charge text settings now live in group Appearance tab (with per-button overrides)
    if buttonData.hasCharges then return end

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
    local itemFontColor = AceGUI:Create("ColorPicker")
    itemFontColor:SetLabel("Font Color")
    itemFontColor:SetHasAlpha(true)
    local icc = buttonData.itemCountFontColor or {1, 1, 1, 1}
    itemFontColor:SetColor(icc[1], icc[2], icc[3], icc[4])
    itemFontColor:SetFullWidth(true)
    itemFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        buttonData.itemCountFontColor = {r, g, b, a}
    end)
    itemFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        buttonData.itemCountFontColor = {r, g, b, a}
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemFontColor)

    -- Item count anchor point
    local barNoIcon = group.displayMode == "bars" and not (group.style.showBarIcon ~= false)
    local defItemAnchor = barNoIcon and "BOTTOM" or "BOTTOMRIGHT"
    local defItemX = barNoIcon and 0 or -2
    local defItemY = 2

    local itemAnchorValues = {}
    for _, pt in ipairs(CS.anchorPoints) do
        itemAnchorValues[pt] = CS.anchorPointLabels[pt]
    end
    local itemAnchorDrop = AceGUI:Create("Dropdown")
    itemAnchorDrop:SetLabel("Anchor Point")
    itemAnchorDrop:SetList(itemAnchorValues)
    itemAnchorDrop:SetValue(buttonData.itemCountAnchor or defItemAnchor)
    itemAnchorDrop:SetFullWidth(true)
    itemAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountAnchor = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemAnchorDrop)

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
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
end

------------------------------------------------------------------------
-- BUTTON SETTINGS COLUMN: Refresh
------------------------------------------------------------------------
-- Multi-select content for button settings (delete/move selected)
local function RefreshButtonSettingsMultiSelect(scroll, multiCount, multiIndices)
    local heading = AceGUI:Create("Heading")
    heading:SetText(multiCount .. " Selected")
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local delBtn = AceGUI:Create("Button")
    delBtn:SetText("Delete Selected")
    delBtn:SetFullWidth(true)
    delBtn:SetCallback("OnClick", function()
        CS.ShowPopupAboveConfig("CDC_DELETE_SELECTED_BUTTONS", multiCount,
            { groupId = CS.selectedGroup, indices = multiIndices })
    end)
    scroll:AddChild(delBtn)

    local spacer = AceGUI:Create("Label")
    spacer:SetText(" ")
    spacer:SetFullWidth(true)
    local font, _, flags = spacer.label:GetFont()
    spacer:SetFont(font, 3, flags or "")
    scroll:AddChild(spacer)

    local moveBtn = AceGUI:Create("Button")
    moveBtn:SetText("Move Selected")
    moveBtn:SetFullWidth(true)
    moveBtn:SetCallback("OnClick", function()
        local moveMenuFrame = _G["CDCMoveMenu"]
        if not moveMenuFrame then
            moveMenuFrame = CreateFrame("Frame", "CDCMoveMenu", UIParent, "UIDropDownMenuTemplate")
        end
        local sourceGroupId = CS.selectedGroup
        local indices = multiIndices
        local db = CooldownCompanion.db.profile
        UIDropDownMenu_Initialize(moveMenuFrame, function(self, level)
            local groupIds = {}
            for id in pairs(db.groups) do
                if CooldownCompanion:IsGroupVisibleToCurrentChar(id) then
                    table.insert(groupIds, id)
                end
            end
            table.sort(groupIds)
            for _, gid in ipairs(groupIds) do
                if gid ~= sourceGroupId then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = db.groups[gid].name
                    info.func = function()
                        for _, idx in ipairs(indices) do
                            table.insert(db.groups[gid].buttons, db.groups[sourceGroupId].buttons[idx])
                        end
                        table.sort(indices, function(a, b) return a > b end)
                        for _, idx in ipairs(indices) do
                            table.remove(db.groups[sourceGroupId].buttons, idx)
                        end
                        CooldownCompanion:RefreshGroupFrame(gid)
                        CooldownCompanion:RefreshGroupFrame(sourceGroupId)
                        CS.selectedButton = nil
                        wipe(CS.selectedButtons)
                        CooldownCompanion:RefreshConfigPanel()
                        CloseDropDownMenus()
                    end
                    UIDropDownMenu_AddButton(info, level)
                end
            end
        end, "MENU")
        moveMenuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, moveMenuFrame, "cursor", 0, 0)
    end)
    scroll:AddChild(moveBtn)
end

local function RefreshButtonSettingsColumn()
    local cf = CS.configFrame
    if not cf then return end
    local bsCol = cf.buttonSettingsCol
    if not bsCol or not bsCol.bsTabGroup then return end

    -- Cast bar overlay: replace button settings with anchoring/FX panel
    if CS.castBarPanelActive then
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end
        if bsCol.multiSelectScroll then bsCol.multiSelectScroll.frame:Hide() end
        if bsCol.resourceBarScroll then bsCol.resourceBarScroll.frame:Hide() end
        if bsCol.frameAnchoringScroll then bsCol.frameAnchoringScroll.frame:Hide() end

        if not bsCol.castBarScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(bsCol.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", bsCol.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", bsCol.content, "BOTTOMRIGHT", 0, 0)
            bsCol.castBarScroll = scroll
        end
        bsCol.castBarScroll:ReleaseChildren()
        bsCol.castBarScroll.frame:Show()
        BuildCastBarAnchoringPanel(bsCol.castBarScroll)
        return
    end

    -- Hide cast bar scroll when not in cast bar mode
    if bsCol.castBarScroll then
        bsCol.castBarScroll.frame:Hide()
    end

    -- Resource bar overlay: replace button settings with resource styling panel
    if CS.resourceBarPanelActive then
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end
        if bsCol.multiSelectScroll then bsCol.multiSelectScroll.frame:Hide() end
        if bsCol.frameAnchoringScroll then bsCol.frameAnchoringScroll.frame:Hide() end

        if not bsCol.resourceBarScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(bsCol.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", bsCol.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", bsCol.content, "BOTTOMRIGHT", 0, 0)
            bsCol.resourceBarScroll = scroll
        end
        bsCol.resourceBarScroll:ReleaseChildren()
        bsCol.resourceBarScroll.frame:Show()
        ST._BuildResourceBarStylingPanel(bsCol.resourceBarScroll)
        return
    end

    -- Hide resource bar scroll when not in resource bar mode
    if bsCol.resourceBarScroll then
        bsCol.resourceBarScroll.frame:Hide()
    end

    -- Frame anchoring overlay: replace button settings with player frame panel
    if CS.frameAnchoringPanelActive then
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end
        if bsCol.multiSelectScroll then bsCol.multiSelectScroll.frame:Hide() end

        if not bsCol.frameAnchoringScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(bsCol.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", bsCol.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", bsCol.content, "BOTTOMRIGHT", 0, 0)
            bsCol.frameAnchoringScroll = scroll
        end
        bsCol.frameAnchoringScroll:ReleaseChildren()
        bsCol.frameAnchoringScroll.frame:Show()
        BuildFrameAnchoringPlayerPanel(bsCol.frameAnchoringScroll)
        return
    end

    -- Hide frame anchoring scroll when not in frame anchoring mode
    if bsCol.frameAnchoringScroll then
        bsCol.frameAnchoringScroll.frame:Hide()
    end

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
        RefreshButtonSettingsMultiSelect(bsCol.multiSelectScroll, multiCount, multiIndices)
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
        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end
        bsCol.bsTabGroup.frame:Show()
        bsCol.bsTabGroup:SelectTab(CS.buttonSettingsTab or "settings")
    else
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Show() end
    end
end

------------------------------------------------------------------------
-- OVERRIDES TAB (per-button style overrides)
------------------------------------------------------------------------
local function BuildOverridesTab(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local displayMode = group.displayMode or "icons"

    -- Check if any overrides exist
    if not buttonData.overrideSections or not next(buttonData.overrideSections) then
        local noOverridesLabel = AceGUI:Create("Label")
        noOverridesLabel:SetText("|cff888888No appearance overrides.\n\nTo customize this button's appearance, select it and click the |A:Crosshair_VehichleCursor_32:0:0|a icon next to a group settings section heading.|r")
        noOverridesLabel:SetFullWidth(true)
        scroll:AddChild(noOverridesLabel)
        return
    end

    local overrides = buttonData.styleOverrides
    if not overrides then return end

    local refreshCallback = function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end

    -- Ordered list of sections to display (maintain consistent ordering)
    local sectionOrder = {
        "borderSettings", "backgroundColor", "cooldownText", "auraText", "auraStackText",
        "keybindText", "chargeText", "desaturation", "cooldownSwipe", "showGCDSwipe", "showOutOfRange", "showTooltips",
        "lossOfControl", "unusableDimming", "assistedHighlight", "procGlow", "pandemicGlow", "auraIndicator",
        "barColors", "barNameText", "barReadyText", "pandemicBar", "barActiveAura",
    }

    -- Map of section IDs to builder functions
    local sectionBuilders = {
        borderSettings = BuildBorderControls,
        backgroundColor = BuildBackgroundColorControls,
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
        assistedHighlight = BuildAssistedHighlightControls,
        procGlow = BuildProcGlowControls,
        pandemicGlow = BuildPandemicGlowControls,
        auraIndicator = BuildAuraIndicatorControls,
        barColors = BuildBarColorsControls,
        barNameText = BuildBarNameTextControls,
        barReadyText = BuildBarReadyTextControls,
        pandemicBar = BuildPandemicBarControls,
        barActiveAura = BuildBarActiveAuraControls,
    }

    for _, sectionId in ipairs(sectionOrder) do
        if buttonData.overrideSections[sectionId] then
            local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
            -- Skip sections not applicable to current display mode
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

                local revertBtn = CreateRevertButton(heading, buttonData, sectionId)
                table.insert(infoButtons, revertBtn)

                if not overrideCollapsed then
                local builder = sectionBuilders[sectionId]
                if builder then
                    builder(scroll, overrides, refreshCallback)
                end
                end
            end
        end
    end
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

    local customNameCollapseBtn = AttachCollapseButton(customNameHeading, customNameCollapsed, function()
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

    local editFrame = customNameBox.editbox
    editFrame.Instructions = editFrame.Instructions or editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    editFrame.Instructions:SetPoint("LEFT", editFrame, "LEFT", 0, 0)
    editFrame.Instructions:SetPoint("RIGHT", editFrame, "RIGHT", 0, 0)
    editFrame.Instructions:SetText("add custom name here, leave blank for default")
    editFrame.Instructions:SetTextColor(0.5, 0.5, 0.5)
    if (buttonData.customName or "") ~= "" then
        editFrame.Instructions:Hide()
    else
        editFrame.Instructions:Show()
    end
    customNameBox:SetCallback("OnTextChanged", function(widget, event, text)
        if text == "" then
            editFrame.Instructions:Show()
        else
            editFrame.Instructions:Hide()
        end
    end)
    end -- not customNameCollapsed
end

-- Expose for Config.lua
ST._BuildSpellSettings = BuildSpellSettings
ST._BuildItemSettings = BuildItemSettings
ST._BuildEquipItemSettings = BuildEquipItemSettings
ST._RefreshButtonSettingsColumn = RefreshButtonSettingsColumn
ST._RefreshButtonSettingsMultiSelect = RefreshButtonSettingsMultiSelect
ST._BuildCustomNameSection = BuildCustomNameSection
ST._BuildOverridesTab = BuildOverridesTab
