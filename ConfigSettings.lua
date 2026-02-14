--[[
    CooldownCompanion - ConfigSettings
    Tab content builders and per-button settings panels (split from Config.lua)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")

-- Shared config state (populated by Config.lua before this file loads)
local CS = ST._configState

------------------------------------------------------------------------
-- BUTTON SETTINGS BUILDERS
------------------------------------------------------------------------
local function BuildSpellSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local isHarmful = buttonData.type == "spell" and C_Spell.IsSpellHarmful(buttonData.id)
    -- Look up viewer frame: try override IDs first, then resolved aura ID, then ability ID
    local viewerFrame
    if buttonData.auraSpellID then
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
        local ok, ids = pcall(C_CooldownViewer.GetCooldownViewerCategorySet, cat, true)
        if ok and ids then
            for _, cdID in ipairs(ids) do
                local ok2, info = pcall(C_CooldownViewer.GetCooldownViewerCooldownInfo, cdID)
                if ok2 and info then
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
    auraHeading:SetFullWidth(true)
    scroll:AddChild(auraHeading)

    local auraKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_aura"
    local auraCollapsed = CS.collapsedSections[auraKey]

    local auraCollapseBtn = CreateFrame("Button", nil, auraHeading.frame)
    table.insert(CS.buttonSettingsCollapseButtons, auraCollapseBtn)
    auraCollapseBtn:SetSize(16, 16)
    auraCollapseBtn:SetPoint("LEFT", auraHeading.label, "RIGHT", 4, 0)
    auraHeading.right:SetPoint("LEFT", auraCollapseBtn, "RIGHT", 4, 0)
    local auraCollapseArrow = auraCollapseBtn:CreateTexture(nil, "ARTWORK")
    auraCollapseArrow:SetSize(12, 12)
    auraCollapseArrow:SetPoint("CENTER")
    auraCollapseArrow:SetAtlas(auraCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    auraCollapseBtn:SetScript("OnClick", function()
        CS.collapsedSections[auraKey] = not CS.collapsedSections[auraKey]
        CooldownCompanion:RefreshConfigPanel()
    end)
    auraCollapseBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(auraCollapsed and "Expand" or "Collapse")
        GameTooltip:Show()
    end)
    auraCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if not auraCollapsed then

    -- Track buff/debuff duration toggle (always visible for spells)
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

    -- Spell ID Override row (always visible for spells, even without auto-detected aura)
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

            -- Color Settings collapsible section
            local colorHeading = AceGUI:Create("Heading")
            colorHeading:SetText("Color Settings")
            colorHeading:SetFullWidth(true)
            scroll:AddChild(colorHeading)

            local colorKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_colorSettings"
            local colorCollapsed = CS.collapsedSections[colorKey]

            local colorCollapseBtn = CreateFrame("Button", nil, colorHeading.frame)
            table.insert(CS.buttonSettingsCollapseButtons, colorCollapseBtn)
            colorCollapseBtn:SetSize(16, 16)
            colorCollapseBtn:SetPoint("LEFT", colorHeading.label, "RIGHT", 4, 0)
            colorHeading.right:SetPoint("LEFT", colorCollapseBtn, "RIGHT", 4, 0)
            local colorCollapseArrow = colorCollapseBtn:CreateTexture(nil, "ARTWORK")
            colorCollapseArrow:SetSize(12, 12)
            colorCollapseArrow:SetPoint("CENTER")
            colorCollapseArrow:SetAtlas(colorCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
            colorCollapseBtn:SetScript("OnClick", function()
                CS.collapsedSections[colorKey] = not CS.collapsedSections[colorKey]
                CooldownCompanion:RefreshConfigPanel()
            end)
            colorCollapseBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(colorCollapsed and "Expand" or "Collapse")
                GameTooltip:Show()
            end)
            colorCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            if not colorCollapsed then
            local auraNoDesatCb = AceGUI:Create("CheckBox")
            auraNoDesatCb:SetLabel("Don't Desaturate While Active")
            auraNoDesatCb:SetValue(buttonData.auraNoDesaturate == true)
            auraNoDesatCb:SetFullWidth(true)
            auraNoDesatCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraNoDesaturate = val or nil
            end)
            scroll:AddChild(auraNoDesatCb)

            -- Active buff/debuff indicator controls (hidden for bar mode)
            if group.displayMode ~= "bars" then
            local auraGlowDrop = AceGUI:Create("Dropdown")
            auraGlowDrop:SetLabel("Active Aura Indicator")
            auraGlowDrop:SetList({
                ["none"] = "None",
                ["solid"] = "Solid Border",
                ["pixel"] = "Pixel Glow",
                ["glow"] = "Glow",
            }, {"none", "solid", "pixel", "glow"})
            auraGlowDrop:SetValue(buttonData.auraGlowStyle or "none")
            auraGlowDrop:SetFullWidth(true)
            auraGlowDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraGlowStyle = (val ~= "none") and val or nil
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(auraGlowDrop)

            if buttonData.auraGlowStyle and buttonData.auraGlowStyle ~= "none" then
                local auraGlowColorPicker = AceGUI:Create("ColorPicker")
                auraGlowColorPicker:SetLabel("Indicator Color")
                local agc = buttonData.auraGlowColor or {1, 0.84, 0, 0.9}
                auraGlowColorPicker:SetColor(agc[1], agc[2], agc[3], agc[4] or 0.9)
                auraGlowColorPicker:SetHasAlpha(true)
                auraGlowColorPicker:SetFullWidth(true)
                auraGlowColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.auraGlowColor = {r, g, b, a}
                end)
                auraGlowColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.auraGlowColor = {r, g, b, a}
                    CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                end)
                scroll:AddChild(auraGlowColorPicker)

                if buttonData.auraGlowStyle == "solid" then
                    local auraGlowSizeSlider = AceGUI:Create("Slider")
                    auraGlowSizeSlider:SetLabel("Border Size")
                    auraGlowSizeSlider:SetSliderValues(1, 8, 1)
                    auraGlowSizeSlider:SetValue(buttonData.auraGlowSize or 2)
                    auraGlowSizeSlider:SetFullWidth(true)
                    auraGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(auraGlowSizeSlider)
                elseif buttonData.auraGlowStyle == "pixel" then
                    local auraGlowSizeSlider = AceGUI:Create("Slider")
                    auraGlowSizeSlider:SetLabel("Line Length")
                    auraGlowSizeSlider:SetSliderValues(1, 12, 1)
                    auraGlowSizeSlider:SetValue(buttonData.auraGlowSize or 4)
                    auraGlowSizeSlider:SetFullWidth(true)
                    auraGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(auraGlowSizeSlider)

                    local auraGlowThicknessSlider = AceGUI:Create("Slider")
                    auraGlowThicknessSlider:SetLabel("Line Thickness")
                    auraGlowThicknessSlider:SetSliderValues(1, 6, 1)
                    auraGlowThicknessSlider:SetValue(buttonData.auraGlowThickness or 2)
                    auraGlowThicknessSlider:SetFullWidth(true)
                    auraGlowThicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowThickness = val
                        CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(auraGlowThicknessSlider)

                    local auraGlowSpeedSlider = AceGUI:Create("Slider")
                    auraGlowSpeedSlider:SetLabel("Speed")
                    auraGlowSpeedSlider:SetSliderValues(10, 200, 5)
                    auraGlowSpeedSlider:SetValue(buttonData.auraGlowSpeed or 60)
                    auraGlowSpeedSlider:SetFullWidth(true)
                    auraGlowSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSpeed = val
                        -- Live-update the active pixel frame speed
                        local gf = CooldownCompanion.groupFrames[CS.selectedGroup]
                        if gf then
                            for _, btn in ipairs(gf.buttons) do
                                if btn.index == CS.selectedButton and btn.auraGlow and btn.auraGlow.pixelFrame then
                                    btn.auraGlow.pixelFrame._speed = val
                                end
                            end
                        end
                    end)
                    scroll:AddChild(auraGlowSpeedSlider)
                elseif buttonData.auraGlowStyle == "glow" then
                    local auraGlowSizeSlider = AceGUI:Create("Slider")
                    auraGlowSizeSlider:SetLabel("Glow Size")
                    auraGlowSizeSlider:SetSliderValues(0, 60, 1)
                    auraGlowSizeSlider:SetValue(buttonData.auraGlowSize or 32)
                    auraGlowSizeSlider:SetFullWidth(true)
                    auraGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.auraGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(auraGlowSizeSlider)
                end

                -- Preview toggle
                local auraGlowPreviewCb = AceGUI:Create("CheckBox")
                auraGlowPreviewCb:SetLabel("Preview")
                local auraGlowPreviewActive = false
                local gFrame = CooldownCompanion.groupFrames[CS.selectedGroup]
                if gFrame then
                    for _, btn in ipairs(gFrame.buttons) do
                        if btn.index == CS.selectedButton and btn._auraGlowPreview then
                            auraGlowPreviewActive = true
                            break
                        end
                    end
                end
                auraGlowPreviewCb:SetValue(auraGlowPreviewActive)
                auraGlowPreviewCb:SetFullWidth(true)
                auraGlowPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                    CooldownCompanion:SetAuraGlowPreview(CS.selectedGroup, CS.selectedButton, val)
                end)
                scroll:AddChild(auraGlowPreviewCb)
            end
            else -- bars: bar-specific aura effect controls
                local barAuraColorPicker = AceGUI:Create("ColorPicker")
                barAuraColorPicker:SetLabel(isHarmful and "Bar Color While Debuff Active" or "Bar Color While Buff Active")
                barAuraColorPicker:SetHasAlpha(true)
                local bac = buttonData.barAuraColor or {0.2, 1.0, 0.2, 1.0}
                barAuraColorPicker:SetColor(bac[1], bac[2], bac[3], bac[4])
                barAuraColorPicker:SetFullWidth(true)
                barAuraColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.barAuraColor = {r, g, b, a}
                end)
                barAuraColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.barAuraColor = {r, g, b, a}
                end)
                scroll:AddChild(barAuraColorPicker)

                local barAuraEffectDrop = AceGUI:Create("Dropdown")
                barAuraEffectDrop:SetLabel("Bar Active Effect")
                barAuraEffectDrop:SetList({
                    ["none"] = "None",
                    ["pixel"] = "Pixel Glow",
                    ["solid"] = "Solid Border",
                    ["glow"] = "Proc Glow",
                }, {"none", "pixel", "solid", "glow"})
                barAuraEffectDrop:SetValue(buttonData.barAuraEffect or "none")
                barAuraEffectDrop:SetFullWidth(true)
                barAuraEffectDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    buttonData.barAuraEffect = (val ~= "none") and val or nil
                    CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                scroll:AddChild(barAuraEffectDrop)

                if buttonData.barAuraEffect and buttonData.barAuraEffect ~= "none" then
                    local barAuraEffectColorPicker = AceGUI:Create("ColorPicker")
                    barAuraEffectColorPicker:SetLabel("Effect Color")
                    local baec = buttonData.barAuraEffectColor or {1, 0.84, 0, 0.9}
                    barAuraEffectColorPicker:SetColor(baec[1], baec[2], baec[3], baec[4] or 0.9)
                    barAuraEffectColorPicker:SetHasAlpha(true)
                    barAuraEffectColorPicker:SetFullWidth(true)
                    barAuraEffectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                        buttonData.barAuraEffectColor = {r, g, b, a}
                        CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                    end)
                    barAuraEffectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                        buttonData.barAuraEffectColor = {r, g, b, a}
                        CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(barAuraEffectColorPicker)

                    if buttonData.barAuraEffect == "solid" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Border Size")
                        barAuraEffectSizeSlider:SetSliderValues(1, 8, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 2)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                    elseif buttonData.barAuraEffect == "pixel" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Line Length")
                        barAuraEffectSizeSlider:SetSliderValues(2, 12, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 4)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                        local barAuraEffectThicknessSlider = AceGUI:Create("Slider")
                        barAuraEffectThicknessSlider:SetLabel("Line Thickness")
                        barAuraEffectThicknessSlider:SetSliderValues(1, 6, 1)
                        barAuraEffectThicknessSlider:SetValue(buttonData.barAuraEffectThickness or 2)
                        barAuraEffectThicknessSlider:SetFullWidth(true)
                        barAuraEffectThicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectThickness = val
                            CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectThicknessSlider)
                        local barAuraEffectSpeedSlider = AceGUI:Create("Slider")
                        barAuraEffectSpeedSlider:SetLabel("Speed")
                        barAuraEffectSpeedSlider:SetSliderValues(10, 200, 5)
                        barAuraEffectSpeedSlider:SetValue(buttonData.barAuraEffectSpeed or 60)
                        barAuraEffectSpeedSlider:SetFullWidth(true)
                        barAuraEffectSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSpeed = val
                            -- Update speed live without invalidating (no visual state change)
                            local gFrame = CooldownCompanion.groupFrames[CS.selectedGroup]
                            if gFrame then
                                for _, btn in ipairs(gFrame.buttons) do
                                    if btn.index == CS.selectedButton and btn.barAuraEffect and btn.barAuraEffect.pixelFrame then
                                        btn.barAuraEffect.pixelFrame._speed = val
                                    end
                                end
                            end
                        end)
                        scroll:AddChild(barAuraEffectSpeedSlider)
                    elseif buttonData.barAuraEffect == "glow" then
                        local barAuraEffectSizeSlider = AceGUI:Create("Slider")
                        barAuraEffectSizeSlider:SetLabel("Glow Size")
                        barAuraEffectSizeSlider:SetSliderValues(0, 60, 1)
                        barAuraEffectSizeSlider:SetValue(buttonData.barAuraEffectSize or 32)
                        barAuraEffectSizeSlider:SetFullWidth(true)
                        barAuraEffectSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                            buttonData.barAuraEffectSize = val
                            CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                        end)
                        scroll:AddChild(barAuraEffectSizeSlider)
                    end

                    -- Preview toggle
                    local barAuraPreviewCb = AceGUI:Create("CheckBox")
                    barAuraPreviewCb:SetLabel("Preview")
                    local barAuraPreviewActive = false
                    local gFrame = CooldownCompanion.groupFrames[CS.selectedGroup]
                    if gFrame then
                        for _, btn in ipairs(gFrame.buttons) do
                            if btn.index == CS.selectedButton and btn._barAuraEffectPreview then
                                barAuraPreviewActive = true
                                break
                            end
                        end
                    end
                    barAuraPreviewCb:SetValue(barAuraPreviewActive)
                    barAuraPreviewCb:SetFullWidth(true)
                    barAuraPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                        CooldownCompanion:SetBarAuraEffectPreview(CS.selectedGroup, CS.selectedButton, val)
                    end)
                    scroll:AddChild(barAuraPreviewCb)
                end
            end -- icon/bar color settings branch
            end -- not colorCollapsed

            -- Pandemic indicator collapsible section
            local pandemicOk, pandemicCapable = pcall(function()
                return viewerFrame and viewerFrame.CanTriggerAlertType
                    and viewerFrame:CanTriggerAlertType(Enum.CooldownViewerAlertEventType.PandemicTime)
            end)
            if pandemicOk and pandemicCapable then
            local pandemicHeading = AceGUI:Create("Heading")
            pandemicHeading:SetText("Pandemic Indicator")
            pandemicHeading:SetFullWidth(true)
            scroll:AddChild(pandemicHeading)

            local pandemicKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_pandemic"
            local pandemicCollapsed = CS.collapsedSections[pandemicKey]

            local pandemicCollapseBtn = CreateFrame("Button", nil, pandemicHeading.frame)
            table.insert(CS.buttonSettingsCollapseButtons, pandemicCollapseBtn)
            pandemicCollapseBtn:SetSize(16, 16)
            pandemicCollapseBtn:SetPoint("LEFT", pandemicHeading.label, "RIGHT", 4, 0)
            pandemicHeading.right:SetPoint("LEFT", pandemicCollapseBtn, "RIGHT", 4, 0)
            local pandemicCollapseArrow = pandemicCollapseBtn:CreateTexture(nil, "ARTWORK")
            pandemicCollapseArrow:SetSize(12, 12)
            pandemicCollapseArrow:SetPoint("CENTER")
            pandemicCollapseArrow:SetAtlas(pandemicCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
            pandemicCollapseBtn:SetScript("OnClick", function()
                CS.collapsedSections[pandemicKey] = not CS.collapsedSections[pandemicKey]
                CooldownCompanion:RefreshConfigPanel()
            end)
            pandemicCollapseBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(pandemicCollapsed and "Expand" or "Collapse")
                GameTooltip:Show()
            end)
            pandemicCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            if not pandemicCollapsed then
            if group.displayMode ~= "bars" then
            -- Icon mode pandemic controls
            local pandemicCb = AceGUI:Create("CheckBox")
            pandemicCb:SetLabel("Enable Pandemic Glow")
            pandemicCb:SetValue(buttonData.pandemicGlow == true)
            pandemicCb:SetFullWidth(true)
            pandemicCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.pandemicGlow = val or nil
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(pandemicCb)

            if buttonData.pandemicGlow then
                local pandemicStyleDrop = AceGUI:Create("Dropdown")
                pandemicStyleDrop:SetLabel("Pandemic Glow Style")
                pandemicStyleDrop:SetList({
                    ["solid"] = "Solid Border",
                    ["pixel"] = "Pixel Glow",
                    ["glow"] = "Glow",
                }, {"solid", "pixel", "glow"})
                pandemicStyleDrop:SetValue(buttonData.pandemicGlowStyle or buttonData.auraGlowStyle or "solid")
                pandemicStyleDrop:SetFullWidth(true)
                pandemicStyleDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    buttonData.pandemicGlowStyle = val
                    CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                scroll:AddChild(pandemicStyleDrop)

                local pandemicColorPicker = AceGUI:Create("ColorPicker")
                pandemicColorPicker:SetLabel("Pandemic Glow Color")
                local pgc = buttonData.pandemicGlowColor or {1, 0.5, 0, 1}
                pandemicColorPicker:SetColor(pgc[1], pgc[2], pgc[3], pgc[4])
                pandemicColorPicker:SetHasAlpha(true)
                pandemicColorPicker:SetFullWidth(true)
                pandemicColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.pandemicGlowColor = {r, g, b, a}
                end)
                pandemicColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.pandemicGlowColor = {r, g, b, a}
                    CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                end)
                scroll:AddChild(pandemicColorPicker)

                -- Size sliders (varies by pandemic glow style)
                local currentPandemicStyle = buttonData.pandemicGlowStyle or buttonData.auraGlowStyle or "solid"
                if currentPandemicStyle == "solid" then
                    local pandemicSizeSlider = AceGUI:Create("Slider")
                    pandemicSizeSlider:SetLabel("Border Size")
                    pandemicSizeSlider:SetSliderValues(1, 8, 1)
                    pandemicSizeSlider:SetValue(buttonData.pandemicGlowSize or buttonData.auraGlowSize or 2)
                    pandemicSizeSlider:SetFullWidth(true)
                    pandemicSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.pandemicGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(pandemicSizeSlider)
                elseif currentPandemicStyle == "pixel" then
                    local pandemicSizeSlider = AceGUI:Create("Slider")
                    pandemicSizeSlider:SetLabel("Line Length")
                    pandemicSizeSlider:SetSliderValues(1, 12, 1)
                    pandemicSizeSlider:SetValue(buttonData.pandemicGlowSize or buttonData.auraGlowSize or 4)
                    pandemicSizeSlider:SetFullWidth(true)
                    pandemicSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.pandemicGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(pandemicSizeSlider)

                    local pandemicThicknessSlider = AceGUI:Create("Slider")
                    pandemicThicknessSlider:SetLabel("Line Thickness")
                    pandemicThicknessSlider:SetSliderValues(1, 6, 1)
                    pandemicThicknessSlider:SetValue(buttonData.pandemicGlowThickness or buttonData.auraGlowThickness or 2)
                    pandemicThicknessSlider:SetFullWidth(true)
                    pandemicThicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.pandemicGlowThickness = val
                        CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(pandemicThicknessSlider)

                    local pandemicSpeedSlider = AceGUI:Create("Slider")
                    pandemicSpeedSlider:SetLabel("Speed")
                    pandemicSpeedSlider:SetSliderValues(10, 200, 5)
                    pandemicSpeedSlider:SetValue(buttonData.pandemicGlowSpeed or buttonData.auraGlowSpeed or 60)
                    pandemicSpeedSlider:SetFullWidth(true)
                    pandemicSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.pandemicGlowSpeed = val
                        local gf = CooldownCompanion.groupFrames[CS.selectedGroup]
                        if gf then
                            for _, btn in ipairs(gf.buttons) do
                                if btn.index == CS.selectedButton and btn.auraGlow and btn.auraGlow.pixelFrame then
                                    btn.auraGlow.pixelFrame._speed = val
                                end
                            end
                        end
                    end)
                    scroll:AddChild(pandemicSpeedSlider)
                elseif currentPandemicStyle == "glow" then
                    local pandemicSizeSlider = AceGUI:Create("Slider")
                    pandemicSizeSlider:SetLabel("Glow Size")
                    pandemicSizeSlider:SetSliderValues(0, 60, 1)
                    pandemicSizeSlider:SetValue(buttonData.pandemicGlowSize or buttonData.auraGlowSize or 32)
                    pandemicSizeSlider:SetFullWidth(true)
                    pandemicSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.pandemicGlowSize = val
                        CooldownCompanion:InvalidateAuraGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(pandemicSizeSlider)
                end

                -- Preview toggle (transient — not saved)
                local pandemicPreviewCb = AceGUI:Create("CheckBox")
                pandemicPreviewCb:SetLabel("Preview")
                local pandemicPreviewActive = false
                local gFrame = CooldownCompanion.groupFrames[CS.selectedGroup]
                if gFrame then
                    for _, btn in ipairs(gFrame.buttons) do
                        if btn.index == CS.selectedButton and btn._pandemicPreview then
                            pandemicPreviewActive = true
                            break
                        end
                    end
                end
                pandemicPreviewCb:SetValue(pandemicPreviewActive)
                pandemicPreviewCb:SetFullWidth(true)
                pandemicPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                    CooldownCompanion:SetPandemicPreview(CS.selectedGroup, CS.selectedButton, val)
                end)
                scroll:AddChild(pandemicPreviewCb)
            end
            else -- bars: bar-specific pandemic controls
                local pandemicCb = AceGUI:Create("CheckBox")
                pandemicCb:SetLabel("Enable Pandemic Indicator")
                pandemicCb:SetValue(buttonData.pandemicGlow == true)
                pandemicCb:SetFullWidth(true)
                pandemicCb:SetCallback("OnValueChanged", function(widget, event, val)
                    buttonData.pandemicGlow = val or nil
                    CooldownCompanion:RefreshConfigPanel()
                end)
                scroll:AddChild(pandemicCb)

                if buttonData.pandemicGlow then
                    local pandemicBarColorPicker = AceGUI:Create("ColorPicker")
                    pandemicBarColorPicker:SetLabel("Pandemic Bar Color")
                    local bpc = buttonData.barPandemicColor or {1, 0.5, 0, 1}
                    pandemicBarColorPicker:SetColor(bpc[1], bpc[2], bpc[3], bpc[4])
                    pandemicBarColorPicker:SetHasAlpha(true)
                    pandemicBarColorPicker:SetFullWidth(true)
                    pandemicBarColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                        buttonData.barPandemicColor = {r, g, b, a}
                    end)
                    pandemicBarColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                        buttonData.barPandemicColor = {r, g, b, a}
                    end)
                    scroll:AddChild(pandemicBarColorPicker)

                    local pandemicEffectDrop = AceGUI:Create("Dropdown")
                    pandemicEffectDrop:SetLabel("Pandemic Effect")
                    pandemicEffectDrop:SetList({
                        ["none"] = "None",
                        ["pixel"] = "Pixel Glow",
                        ["solid"] = "Solid Border",
                        ["glow"] = "Proc Glow",
                    }, {"none", "pixel", "solid", "glow"})
                    pandemicEffectDrop:SetValue(buttonData.pandemicBarEffect or buttonData.barAuraEffect or "none")
                    pandemicEffectDrop:SetFullWidth(true)
                    pandemicEffectDrop:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.pandemicBarEffect = (val ~= "none") and val or nil
                        CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                        CooldownCompanion:RefreshConfigPanel()
                    end)
                    scroll:AddChild(pandemicEffectDrop)

                    local pandemicEffect = buttonData.pandemicBarEffect or buttonData.barAuraEffect or "none"
                    if pandemicEffect ~= "none" then
                        local pandemicEffectColorPicker = AceGUI:Create("ColorPicker")
                        pandemicEffectColorPicker:SetLabel("Pandemic Effect Color")
                        local pgc = buttonData.pandemicGlowColor or {1, 0.5, 0, 1}
                        pandemicEffectColorPicker:SetColor(pgc[1], pgc[2], pgc[3], pgc[4])
                        pandemicEffectColorPicker:SetHasAlpha(true)
                        pandemicEffectColorPicker:SetFullWidth(true)
                        pandemicEffectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                            buttonData.pandemicGlowColor = {r, g, b, a}
                            CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                        end)
                        pandemicEffectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                            buttonData.pandemicGlowColor = {r, g, b, a}
                            CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                        end)
                        scroll:AddChild(pandemicEffectColorPicker)

                        if pandemicEffect == "solid" then
                            local pandemicBorderSizeSlider = AceGUI:Create("Slider")
                            pandemicBorderSizeSlider:SetLabel("Border Size")
                            pandemicBorderSizeSlider:SetSliderValues(1, 8, 1)
                            pandemicBorderSizeSlider:SetValue(buttonData.pandemicBarEffectSize or 2)
                            pandemicBorderSizeSlider:SetFullWidth(true)
                            pandemicBorderSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                buttonData.pandemicBarEffectSize = val
                                CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                            end)
                            scroll:AddChild(pandemicBorderSizeSlider)
                        elseif pandemicEffect == "pixel" then
                            local pandemicLineLengthSlider = AceGUI:Create("Slider")
                            pandemicLineLengthSlider:SetLabel("Line Length")
                            pandemicLineLengthSlider:SetSliderValues(2, 12, 1)
                            pandemicLineLengthSlider:SetValue(buttonData.pandemicBarEffectSize or 4)
                            pandemicLineLengthSlider:SetFullWidth(true)
                            pandemicLineLengthSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                buttonData.pandemicBarEffectSize = val
                                CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                            end)
                            scroll:AddChild(pandemicLineLengthSlider)

                            local pandemicLineThicknessSlider = AceGUI:Create("Slider")
                            pandemicLineThicknessSlider:SetLabel("Line Thickness")
                            pandemicLineThicknessSlider:SetSliderValues(1, 6, 1)
                            pandemicLineThicknessSlider:SetValue(buttonData.pandemicBarEffectThickness or 2)
                            pandemicLineThicknessSlider:SetFullWidth(true)
                            pandemicLineThicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                buttonData.pandemicBarEffectThickness = val
                                CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                            end)
                            scroll:AddChild(pandemicLineThicknessSlider)

                            local pandemicSpeedSlider = AceGUI:Create("Slider")
                            pandemicSpeedSlider:SetLabel("Speed")
                            pandemicSpeedSlider:SetSliderValues(10, 200, 5)
                            pandemicSpeedSlider:SetValue(buttonData.pandemicBarEffectSpeed or 60)
                            pandemicSpeedSlider:SetFullWidth(true)
                            pandemicSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                buttonData.pandemicBarEffectSpeed = val
                                local gFrame = CooldownCompanion.groupFrames[CS.selectedGroup]
                                if gFrame then
                                    for _, btn in ipairs(gFrame.buttons) do
                                        if btn.index == CS.selectedButton and btn.barAuraEffect and btn.barAuraEffect.pixelFrame then
                                            btn.barAuraEffect.pixelFrame._speed = val
                                        end
                                    end
                                end
                            end)
                            scroll:AddChild(pandemicSpeedSlider)
                        elseif pandemicEffect == "glow" then
                            local pandemicGlowSizeSlider = AceGUI:Create("Slider")
                            pandemicGlowSizeSlider:SetLabel("Glow Size")
                            pandemicGlowSizeSlider:SetSliderValues(0, 60, 1)
                            pandemicGlowSizeSlider:SetValue(buttonData.pandemicBarEffectSize or 32)
                            pandemicGlowSizeSlider:SetFullWidth(true)
                            pandemicGlowSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                                buttonData.pandemicBarEffectSize = val
                                CooldownCompanion:InvalidateBarAuraEffect(CS.selectedGroup, CS.selectedButton)
                            end)
                            scroll:AddChild(pandemicGlowSizeSlider)
                        end
                    end

                    -- Preview toggle (transient — not saved)
                    local pandemicPreviewCb = AceGUI:Create("CheckBox")
                    pandemicPreviewCb:SetLabel("Preview")
                    local pandemicPreviewActive = false
                    local gFrame = CooldownCompanion.groupFrames[CS.selectedGroup]
                    if gFrame then
                        for _, btn in ipairs(gFrame.buttons) do
                            if btn.index == CS.selectedButton and btn._pandemicPreview then
                                pandemicPreviewActive = true
                                break
                            end
                        end
                    end
                    pandemicPreviewCb:SetValue(pandemicPreviewActive)
                    pandemicPreviewCb:SetFullWidth(true)
                    pandemicPreviewCb:SetCallback("OnValueChanged", function(widget, event, val)
                        CooldownCompanion:SetPandemicPreview(CS.selectedGroup, CS.selectedButton, val)
                    end)
                    scroll:AddChild(pandemicPreviewCb)
                end
            end -- icon/bar pandemic branch
            end -- not pandemicCollapsed
            end -- pandemicCapable
    end -- hasViewerFrame and auraTracking
    end -- canTrackAura
    end -- not auraCollapsed
    end -- buttonData.type == "spell"

    -- Proc Glow collapsible section (icon mode only)
    if group.displayMode ~= "bars" then
            local procHeading = AceGUI:Create("Heading")
            procHeading:SetText("Proc Glow")
            procHeading:SetFullWidth(true)
            scroll:AddChild(procHeading)

            local procKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_procGlow"
            local procCollapsed = CS.collapsedSections[procKey]

            local procHeadingCollapseBtn = CreateFrame("Button", nil, procHeading.frame)
            table.insert(CS.buttonSettingsCollapseButtons, procHeadingCollapseBtn)
            procHeadingCollapseBtn:SetSize(16, 16)
            procHeadingCollapseBtn:SetPoint("LEFT", procHeading.label, "RIGHT", 4, 0)
            procHeading.right:SetPoint("LEFT", procHeadingCollapseBtn, "RIGHT", 4, 0)
            local procHeadingArrow = procHeadingCollapseBtn:CreateTexture(nil, "ARTWORK")
            procHeadingArrow:SetSize(12, 12)
            procHeadingArrow:SetPoint("CENTER")
            procHeadingArrow:SetAtlas(procCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
            procHeadingCollapseBtn:SetScript("OnClick", function()
                CS.collapsedSections[procKey] = not CS.collapsedSections[procKey]
                CooldownCompanion:RefreshConfigPanel()
            end)
            procHeadingCollapseBtn:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(procCollapsed and "Expand" or "Collapse")
                GameTooltip:Show()
            end)
            procHeadingCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

            if not procCollapsed then
            local procCb = AceGUI:Create("CheckBox")
            procCb:SetLabel("Show Proc Glow")
            procCb:SetValue(buttonData.procGlow == true)
            procCb:SetFullWidth(true)
            procCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.procGlow = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(procCb)

            -- (?) tooltip for proc glow
            local procInfo = CreateFrame("Button", nil, procCb.frame)
            procInfo:SetSize(16, 16)
            procInfo:SetPoint("LEFT", procCb.checkbg, "RIGHT", procCb.text:GetStringWidth() + 4, 0)
            local procInfoIcon = procInfo:CreateTexture(nil, "OVERLAY")
            procInfoIcon:SetSize(12, 12)
            procInfoIcon:SetPoint("CENTER")
            procInfoIcon:SetAtlas("QuestRepeatableTurnin")
            procInfo:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Proc Glow")
                GameTooltip:AddLine("Check this if you want procs associated with this spell to cause the icon's border to glow.", 1, 1, 1, true)
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("If this spell does not have a proc associated with it, these settings will have no effect.", 0.7, 0.7, 0.7, true)
                GameTooltip:Show()
            end)
            procInfo:SetScript("OnLeave", function()
                GameTooltip:Hide()
            end)
            table.insert(infoButtons, procInfo)
            if CooldownCompanion.db.profile.hideInfoButtons then
                procInfo:Hide()
            end

            if buttonData.procGlow == true then
                -- Style dropdown
                local procStyleDrop = AceGUI:Create("Dropdown")
                procStyleDrop:SetLabel("Glow Style")
                procStyleDrop:SetList({
                    ["solid"] = "Solid Border",
                    ["pixel"] = "Pixel Glow",
                    ["glow"] = "Glow",
                }, {"solid", "pixel", "glow"})
                procStyleDrop:SetValue(buttonData.procGlowStyle or "glow")
                procStyleDrop:SetFullWidth(true)
                procStyleDrop:SetCallback("OnValueChanged", function(widget, event, val)
                    buttonData.procGlowStyle = val
                    CooldownCompanion:InvalidateProcGlow(CS.selectedGroup, CS.selectedButton)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                scroll:AddChild(procStyleDrop)

                -- Color picker (per-button, falls back to group style)
                local procGlowColor = AceGUI:Create("ColorPicker")
                procGlowColor:SetLabel("Glow Color")
                procGlowColor:SetHasAlpha(true)
                local pgc = buttonData.procGlowColor or group.style.procGlowColor or {1, 1, 1, 1}
                procGlowColor:SetColor(pgc[1], pgc[2], pgc[3], pgc[4])
                procGlowColor:SetFullWidth(true)
                procGlowColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                    buttonData.procGlowColor = {r, g, b, a}
                end)
                procGlowColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                    buttonData.procGlowColor = {r, g, b, a}
                    CooldownCompanion:InvalidateProcGlow(CS.selectedGroup, CS.selectedButton)
                end)
                scroll:AddChild(procGlowColor)

                -- Size slider (varies by style)
                local currentProcStyle = buttonData.procGlowStyle or "glow"
                if currentProcStyle == "solid" then
                    local procSizeSlider = AceGUI:Create("Slider")
                    procSizeSlider:SetLabel("Border Size")
                    procSizeSlider:SetSliderValues(1, 8, 1)
                    procSizeSlider:SetValue(buttonData.procGlowSize or 2)
                    procSizeSlider:SetFullWidth(true)
                    procSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.procGlowSize = val
                        CooldownCompanion:InvalidateProcGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(procSizeSlider)
                elseif currentProcStyle == "pixel" then
                    local procSizeSlider = AceGUI:Create("Slider")
                    procSizeSlider:SetLabel("Line Length")
                    procSizeSlider:SetSliderValues(1, 12, 1)
                    procSizeSlider:SetValue(buttonData.procGlowSize or 4)
                    procSizeSlider:SetFullWidth(true)
                    procSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.procGlowSize = val
                        CooldownCompanion:InvalidateProcGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(procSizeSlider)

                    local procThicknessSlider = AceGUI:Create("Slider")
                    procThicknessSlider:SetLabel("Line Thickness")
                    procThicknessSlider:SetSliderValues(1, 6, 1)
                    procThicknessSlider:SetValue(buttonData.procGlowThickness or 2)
                    procThicknessSlider:SetFullWidth(true)
                    procThicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.procGlowThickness = val
                        CooldownCompanion:InvalidateProcGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(procThicknessSlider)

                    local procSpeedSlider = AceGUI:Create("Slider")
                    procSpeedSlider:SetLabel("Speed")
                    procSpeedSlider:SetSliderValues(10, 200, 5)
                    procSpeedSlider:SetValue(buttonData.procGlowSpeed or 60)
                    procSpeedSlider:SetFullWidth(true)
                    procSpeedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.procGlowSpeed = val
                        -- Live-update the active pixel frame speed
                        local gf = CooldownCompanion.groupFrames[CS.selectedGroup]
                        if gf then
                            for _, btn in ipairs(gf.buttons) do
                                if btn.index == CS.selectedButton and btn.procGlow and btn.procGlow.pixelFrame then
                                    btn.procGlow.pixelFrame._speed = val
                                end
                            end
                        end
                    end)
                    scroll:AddChild(procSpeedSlider)
                elseif currentProcStyle == "glow" then
                    local procSizeSlider = AceGUI:Create("Slider")
                    procSizeSlider:SetLabel("Glow Size")
                    procSizeSlider:SetSliderValues(0, 60, 1)
                    procSizeSlider:SetValue(buttonData.procGlowSize or group.style.procGlowOverhang or 32)
                    procSizeSlider:SetFullWidth(true)
                    procSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                        buttonData.procGlowSize = val
                        CooldownCompanion:InvalidateProcGlow(CS.selectedGroup, CS.selectedButton)
                    end)
                    scroll:AddChild(procSizeSlider)
                end

                -- Preview toggle (transient — not saved)
                local previewCb = AceGUI:Create("CheckBox")
                previewCb:SetLabel("Preview")
                local previewActive = false
                local gFrame = CooldownCompanion.groupFrames[CS.selectedGroup]
                if gFrame then
                    for _, btn in ipairs(gFrame.buttons) do
                        if btn.index == CS.selectedButton and btn._procGlowPreview then
                            previewActive = true
                            break
                        end
                    end
                end
                previewCb:SetValue(previewActive)
                previewCb:SetFullWidth(true)
                previewCb:SetCallback("OnValueChanged", function(widget, event, val)
                    CooldownCompanion:SetProcGlowPreview(CS.selectedGroup, CS.selectedButton, val)
                end)
                scroll:AddChild(previewCb)
            end
            end -- not procCollapsed
    end -- not bars (proc glow)

    -- Charge settings (only for charge-based spells)
    if buttonData.hasCharges then
        local chargeHeading = AceGUI:Create("Heading")
        chargeHeading:SetText("Charge Settings")
        chargeHeading:SetFullWidth(true)
        scroll:AddChild(chargeHeading)

        local chargeKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_charges"
        local chargesCollapsed = CS.collapsedSections[chargeKey]

        local chargeCollapseBtn = CreateFrame("Button", nil, chargeHeading.frame)
        table.insert(CS.buttonSettingsCollapseButtons, chargeCollapseBtn)
        chargeCollapseBtn:SetSize(16, 16)
        chargeCollapseBtn:SetPoint("LEFT", chargeHeading.label, "RIGHT", 4, 0)
        chargeHeading.right:SetPoint("LEFT", chargeCollapseBtn, "RIGHT", 4, 0)
        local chargeCollapseArrow = chargeCollapseBtn:CreateTexture(nil, "ARTWORK")
        chargeCollapseArrow:SetSize(12, 12)
        chargeCollapseArrow:SetPoint("CENTER")
        chargeCollapseArrow:SetAtlas(chargesCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
        chargeCollapseBtn:SetScript("OnClick", function()
            CS.collapsedSections[chargeKey] = not CS.collapsedSections[chargeKey]
            CooldownCompanion:RefreshConfigPanel()
        end)
        chargeCollapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(chargesCollapsed and "Expand" or "Collapse")
            GameTooltip:Show()
        end)
        chargeCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

        if not chargesCollapsed then
        local showChargeTextCb = AceGUI:Create("CheckBox")
        showChargeTextCb:SetLabel("Show Charge Count Text")
        showChargeTextCb:SetValue(buttonData.showChargeText or false)
        showChargeTextCb:SetFullWidth(true)
        showChargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.showChargeText = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(showChargeTextCb)

        if buttonData.showChargeText then
            local chargeFontSizeSlider = AceGUI:Create("Slider")
            chargeFontSizeSlider:SetLabel("Font Size")
            chargeFontSizeSlider:SetSliderValues(8, 32, 1)
            chargeFontSizeSlider:SetValue(buttonData.chargeFontSize or 12)
            chargeFontSizeSlider:SetFullWidth(true)
            chargeFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeFontSize = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            scroll:AddChild(chargeFontSizeSlider)

            local chargeFontDrop = AceGUI:Create("Dropdown")
            chargeFontDrop:SetLabel("Font")
            chargeFontDrop:SetList(CS.fontOptions)
            chargeFontDrop:SetValue(buttonData.chargeFont or "Fonts\\FRIZQT__.TTF")
            chargeFontDrop:SetFullWidth(true)
            chargeFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeFont = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            scroll:AddChild(chargeFontDrop)

            local chargeOutlineDrop = AceGUI:Create("Dropdown")
            chargeOutlineDrop:SetLabel("Font Outline")
            chargeOutlineDrop:SetList(CS.outlineOptions)
            chargeOutlineDrop:SetValue(buttonData.chargeFontOutline or "OUTLINE")
            chargeOutlineDrop:SetFullWidth(true)
            chargeOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeFontOutline = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            scroll:AddChild(chargeOutlineDrop)

            local chargeFontColor = AceGUI:Create("ColorPicker")
            chargeFontColor:SetLabel("Font Color (Max Charges)")
            chargeFontColor:SetHasAlpha(true)
            local chc = buttonData.chargeFontColor or {1, 1, 1, 1}
            chargeFontColor:SetColor(chc[1], chc[2], chc[3], chc[4])
            chargeFontColor:SetFullWidth(true)
            chargeFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                buttonData.chargeFontColor = {r, g, b, a}
            end)
            chargeFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                buttonData.chargeFontColor = {r, g, b, a}
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            scroll:AddChild(chargeFontColor)

            local chargeFontColorMissing = AceGUI:Create("ColorPicker")
            chargeFontColorMissing:SetLabel("Font Color (Missing Charges)")
            chargeFontColorMissing:SetHasAlpha(true)
            local chm = buttonData.chargeFontColorMissing or {1, 1, 1, 1}
            chargeFontColorMissing:SetColor(chm[1], chm[2], chm[3], chm[4])
            chargeFontColorMissing:SetFullWidth(true)
            chargeFontColorMissing:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                buttonData.chargeFontColorMissing = {r, g, b, a}
            end)
            chargeFontColorMissing:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                buttonData.chargeFontColorMissing = {r, g, b, a}
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            scroll:AddChild(chargeFontColorMissing)

            local barNoIcon = group.displayMode == "bars" and not (group.style.showBarIcon ~= false)
            local defChargeAnchor = barNoIcon and "BOTTOM" or "BOTTOMRIGHT"
            local defChargeX = barNoIcon and 0 or -2
            local defChargeY = 2

            local chargeAnchorValues = {}
            for _, pt in ipairs(CS.anchorPoints) do
                chargeAnchorValues[pt] = CS.anchorPointLabels[pt]
            end
            local chargeAnchorDrop = AceGUI:Create("Dropdown")
            chargeAnchorDrop:SetLabel("Anchor Point")
            chargeAnchorDrop:SetList(chargeAnchorValues)
            chargeAnchorDrop:SetValue(buttonData.chargeAnchor or defChargeAnchor)
            chargeAnchorDrop:SetFullWidth(true)
            chargeAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeAnchor = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            scroll:AddChild(chargeAnchorDrop)

            local chargeXSlider = AceGUI:Create("Slider")
            chargeXSlider:SetLabel("X Offset")
            chargeXSlider:SetSliderValues(-20, 20, 1)
            chargeXSlider:SetValue(buttonData.chargeXOffset or defChargeX)
            chargeXSlider:SetFullWidth(true)
            chargeXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeXOffset = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            scroll:AddChild(chargeXSlider)

            local chargeYSlider = AceGUI:Create("Slider")
            chargeYSlider:SetLabel("Y Offset")
            chargeYSlider:SetSliderValues(-20, 20, 1)
            chargeYSlider:SetValue(buttonData.chargeYOffset or defChargeY)
            chargeYSlider:SetFullWidth(true)
            chargeYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.chargeYOffset = val
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            scroll:AddChild(chargeYSlider)
        end -- showChargeText

        if group.displayMode == "bars" then
            if group.style and group.style.showCooldownText then
                local cdTextOnRechargeCb = AceGUI:Create("CheckBox")
                cdTextOnRechargeCb:SetLabel("Anchor Cooldown Text to Recharging Bar")
                cdTextOnRechargeCb:SetValue(buttonData.barCdTextOnRechargeBar or false)
                cdTextOnRechargeCb:SetFullWidth(true)
                cdTextOnRechargeCb:SetCallback("OnValueChanged", function(widget, event, val)
                    buttonData.barCdTextOnRechargeBar = val
                end)
                scroll:AddChild(cdTextOnRechargeCb)
            end

            local reverseChargesCb = AceGUI:Create("CheckBox")
            reverseChargesCb:SetLabel("Flip Charge Order")
            reverseChargesCb:SetValue(buttonData.barReverseCharges or false)
            reverseChargesCb:SetFullWidth(true)
            reverseChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.barReverseCharges = val or nil
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            scroll:AddChild(reverseChargesCb)

            local chargeGapSlider = AceGUI:Create("Slider")
            chargeGapSlider:SetLabel("Charge Bar Gap")
            chargeGapSlider:SetSliderValues(0, 20, 1)
            chargeGapSlider:SetValue(buttonData.barChargeGap or 2)
            chargeGapSlider:SetFullWidth(true)
            chargeGapSlider:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.barChargeGap = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            scroll:AddChild(chargeGapSlider)
        end
        end -- not chargesCollapsed
    end -- hasCharges

    if group.displayMode == "bars" then
        local customNameHeading = AceGUI:Create("Heading")
        customNameHeading:SetText("Custom Name")
        customNameHeading:SetFullWidth(true)
        scroll:AddChild(customNameHeading)

        local customNameKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_customname"
        local customNameCollapsed = CS.collapsedSections[customNameKey]

        local customNameCollapseBtn = CreateFrame("Button", nil, customNameHeading.frame)
        table.insert(CS.buttonSettingsCollapseButtons, customNameCollapseBtn)
        customNameCollapseBtn:SetSize(16, 16)
        customNameCollapseBtn:SetPoint("LEFT", customNameHeading.label, "RIGHT", 4, 0)
        customNameHeading.right:SetPoint("LEFT", customNameCollapseBtn, "RIGHT", 4, 0)
        local customNameCollapseArrow = customNameCollapseBtn:CreateTexture(nil, "ARTWORK")
        customNameCollapseArrow:SetSize(12, 12)
        customNameCollapseArrow:SetPoint("CENTER")
        customNameCollapseArrow:SetAtlas(customNameCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
        customNameCollapseBtn:SetScript("OnClick", function()
            CS.collapsedSections[customNameKey] = not CS.collapsedSections[customNameKey]
            CooldownCompanion:RefreshConfigPanel()
        end)
        customNameCollapseBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(customNameCollapsed and "Expand" or "Collapse")
            GameTooltip:Show()
        end)
        customNameCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
end

local function BuildItemSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local itemHeading = AceGUI:Create("Heading")
    itemHeading:SetText("Item Settings")
    itemHeading:SetFullWidth(true)
    scroll:AddChild(itemHeading)

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
    itemFontDrop:SetList(CS.fontOptions)
    itemFontDrop:SetValue(buttonData.itemCountFont or "Fonts\\FRIZQT__.TTF")
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
    itemXSlider:SetSliderValues(-20, 20, 1)
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
    itemYSlider:SetSliderValues(-20, 20, 1)
    itemYSlider:SetValue(buttonData.itemCountYOffset or defItemY)
    itemYSlider:SetFullWidth(true)
    itemYSlider:SetCallback("OnValueChanged", function(widget, event, val)
        buttonData.itemCountYOffset = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    scroll:AddChild(itemYSlider)

    if group.displayMode == "bars" then
        local chargeGapSlider = AceGUI:Create("Slider")
        chargeGapSlider:SetLabel("Charge Bar Gap")
        chargeGapSlider:SetSliderValues(0, 20, 1)
        chargeGapSlider:SetValue(buttonData.barChargeGap or 2)
        chargeGapSlider:SetFullWidth(true)
        chargeGapSlider:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.barChargeGap = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        scroll:AddChild(chargeGapSlider)

        local reverseChargesCb = AceGUI:Create("CheckBox")
        reverseChargesCb:SetLabel("Flip Charge Order")
        reverseChargesCb:SetValue(buttonData.barReverseCharges or false)
        reverseChargesCb:SetFullWidth(true)
        reverseChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.barReverseCharges = val or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        scroll:AddChild(reverseChargesCb)
    end
end

local function BuildEquipItemSettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    if group.displayMode == "bars" then
        local chargeGapSlider = AceGUI:Create("Slider")
        chargeGapSlider:SetLabel("Charge Bar Gap")
        chargeGapSlider:SetSliderValues(0, 20, 1)
        chargeGapSlider:SetValue(buttonData.barChargeGap or 2)
        chargeGapSlider:SetFullWidth(true)
        chargeGapSlider:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.barChargeGap = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        scroll:AddChild(chargeGapSlider)

        local reverseChargesCb = AceGUI:Create("CheckBox")
        reverseChargesCb:SetLabel("Flip Charge Order")
        reverseChargesCb:SetValue(buttonData.barReverseCharges or false)
        reverseChargesCb:SetFullWidth(true)
        reverseChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.barReverseCharges = val or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        scroll:AddChild(reverseChargesCb)
    end
end

------------------------------------------------------------------------
-- BUTTON SETTINGS COLUMN: Refresh
------------------------------------------------------------------------
-- Multi-select content for button settings (delete/move selected)
local function RefreshButtonSettingsMultiSelect(scroll, multiCount, multiIndices)
    local heading = AceGUI:Create("Heading")
    heading:SetText(multiCount .. " Selected")
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

-- Forward declarations — defined after all collapsible-section state
local BuildCastBarAnchoringPanel
local BuildResourceBarAnchoringPanel

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

    -- Resource bar overlay: replace button settings with resource anchoring panel
    if CS.resourceBarPanelActive then
        bsCol.bsTabGroup.frame:Hide()
        if bsCol.bsPlaceholder then bsCol.bsPlaceholder:Hide() end
        if bsCol.multiSelectScroll then bsCol.multiSelectScroll.frame:Hide() end

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
        BuildResourceBarAnchoringPanel(bsCol.resourceBarScroll)
        return
    end

    -- Hide resource bar scroll when not in resource bar mode
    if bsCol.resourceBarScroll then
        bsCol.resourceBarScroll.frame:Hide()
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
-- COLUMN 3: Settings (TabGroup)
------------------------------------------------------------------------
-- Tab UI state lives in CS (shared with Config.lua for cleanup on tab switch)
local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

local function BuildExtrasTab(container)
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

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style

    local isBarMode = group.displayMode == "bars"

    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Desaturate On Cooldown / Active Aura")
    desatCb:SetValue(style.desaturateOnCooldown or false)
    desatCb:SetFullWidth(true)
    desatCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.desaturateOnCooldown = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(desatCb)

    local gcdCb = AceGUI:Create("CheckBox")
    gcdCb:SetLabel(isBarMode and "Show GCD" or "Show GCD Swipe")
    gcdCb:SetValue(style.showGCDSwipe == true)
    gcdCb:SetFullWidth(true)
    gcdCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showGCDSwipe = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(gcdCb)

    if not isBarMode then
    local rangeCb = AceGUI:Create("CheckBox")
    rangeCb:SetLabel("Show Out of Range")
    rangeCb:SetValue(style.showOutOfRange or false)
    rangeCb:SetFullWidth(true)
    rangeCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showOutOfRange = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(rangeCb)

    -- (?) tooltip for out of range
    local rangeInfo = CreateFrame("Button", nil, rangeCb.frame)
    rangeInfo:SetSize(16, 16)
    rangeInfo:SetPoint("LEFT", rangeCb.checkbg, "RIGHT", rangeCb.text:GetStringWidth() + 4, 0)
    local rangeInfoIcon = rangeInfo:CreateTexture(nil, "OVERLAY")
    rangeInfoIcon:SetSize(12, 12)
    rangeInfoIcon:SetPoint("CENTER")
    rangeInfoIcon:SetAtlas("QuestRepeatableTurnin")
    rangeInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Out of Range")
        GameTooltip:AddLine("Tints spell and item icons red when the target is out of range. Item range checking is unavailable during combat due to Blizzard API restrictions.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    rangeInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, rangeInfo)
    end -- not isBarMode

    local tooltipCb = AceGUI:Create("CheckBox")
    tooltipCb:SetLabel("Show Tooltips")
    tooltipCb:SetValue(style.showTooltips == true)
    tooltipCb:SetFullWidth(true)
    tooltipCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showTooltips = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(tooltipCb)

    -- Compact Layout (per-button visibility feature)
    local compactCb = AceGUI:Create("CheckBox")
    compactCb:SetLabel("Compact Layout")
    compactCb:SetValue(group.compactLayout or false)
    compactCb:SetFullWidth(true)
    compactCb:SetCallback("OnValueChanged", function(widget, event, val)
        group.compactLayout = val or false
        CooldownCompanion:PopulateGroupButtons(CS.selectedGroup)
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then frame._layoutDirty = true end
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(compactCb)

    -- (?) tooltip for compact layout
    local compactInfo = CreateFrame("Button", nil, compactCb.frame)
    compactInfo:SetSize(16, 16)
    compactInfo:SetPoint("LEFT", compactCb.checkbg, "RIGHT", compactCb.text:GetStringWidth() + 4, 0)
    local compactInfoIcon = compactInfo:CreateTexture(nil, "OVERLAY")
    compactInfoIcon:SetSize(12, 12)
    compactInfoIcon:SetPoint("CENTER")
    compactInfoIcon:SetAtlas("QuestRepeatableTurnin")
    compactInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Compact Layout")
        GameTooltip:AddLine("When per-button visibility rules hide a button, shift remaining buttons to fill the gap and resize the group frame to fit visible buttons only.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    compactInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(tabInfoButtons, compactInfo)

    if group.compactLayout then
        local totalButtons = #group.buttons
        local maxVisSlider = AceGUI:Create("Slider")
        maxVisSlider:SetLabel("Max Visible Buttons")
        maxVisSlider:SetSliderValues(1, math.max(totalButtons, 1), 1)
        maxVisSlider:SetValue(group.maxVisibleButtons == 0 and totalButtons or group.maxVisibleButtons)
        maxVisSlider:SetFullWidth(true)
        maxVisSlider:SetCallback("OnValueChanged", function(widget, event, val)
            val = math.floor(val + 0.5)
            if val >= totalButtons then
                group.maxVisibleButtons = 0
            else
                group.maxVisibleButtons = val
            end
            local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
            if frame then frame._layoutDirty = true end
        end)
        container:AddChild(maxVisSlider)

        -- (?) tooltip for max visible buttons
        local maxVisInfo = CreateFrame("Button", nil, maxVisSlider.frame)
        maxVisInfo:SetSize(16, 16)
        maxVisInfo:SetPoint("LEFT", maxVisSlider.label, "RIGHT", 4, 0)
        local maxVisInfoIcon = maxVisInfo:CreateTexture(nil, "OVERLAY")
        maxVisInfoIcon:SetSize(12, 12)
        maxVisInfoIcon:SetPoint("CENTER")
        maxVisInfoIcon:SetAtlas("QuestRepeatableTurnin")
        maxVisInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Max Visible Buttons")
            GameTooltip:AddLine("Limits how many buttons can appear at once. The first buttons (by group order) that pass visibility checks are shown; the rest are hidden.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        maxVisInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(tabInfoButtons, maxVisInfo)
    end

    if not isBarMode then
    -- Loss of control
    local locCb = AceGUI:Create("CheckBox")
    locCb:SetLabel("Show Loss of Control")
    locCb:SetValue(style.showLossOfControl or false)
    locCb:SetFullWidth(true)
    locCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showLossOfControl = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(locCb)

    -- (?) tooltip for loss of control
    local locInfo = CreateFrame("Button", nil, locCb.frame)
    locInfo:SetSize(16, 16)
    locInfo:SetPoint("LEFT", locCb.checkbg, "RIGHT", locCb.text:GetStringWidth() + 4, 0)
    local locInfoIcon = locInfo:CreateTexture(nil, "OVERLAY")
    locInfoIcon:SetSize(12, 12)
    locInfoIcon:SetPoint("CENTER")
    locInfoIcon:SetAtlas("QuestRepeatableTurnin")
    locInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Loss of Control")
        GameTooltip:AddLine("Shows a red overlay on spell icons when they are locked out by a stun, interrupt, silence, or other crowd control effect.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    locInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, locInfo)

    if style.showLossOfControl then
        local locColor = AceGUI:Create("ColorPicker")
        locColor:SetLabel("LoC Overlay Color")
        locColor:SetHasAlpha(true)
        local lc = style.lossOfControlColor or {1, 0, 0, 0.5}
        locColor:SetColor(lc[1], lc[2], lc[3], lc[4])
        locColor:SetFullWidth(true)
        locColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.lossOfControlColor = {r, g, b, a}
        end)
        locColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.lossOfControlColor = {r, g, b, a}
        end)
        container:AddChild(locColor)
    end

    -- Usability dimming
    local unusableCb = AceGUI:Create("CheckBox")
    unusableCb:SetLabel("Show Unusable Dimming")
    unusableCb:SetValue(style.showUnusable or false)
    unusableCb:SetFullWidth(true)
    unusableCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showUnusable = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(unusableCb)

    -- (?) tooltip for unusable dimming
    local unusableInfo = CreateFrame("Button", nil, unusableCb.frame)
    unusableInfo:SetSize(16, 16)
    unusableInfo:SetPoint("LEFT", unusableCb.checkbg, "RIGHT", unusableCb.text:GetStringWidth() + 4, 0)
    local unusableInfoIcon = unusableInfo:CreateTexture(nil, "OVERLAY")
    unusableInfoIcon:SetSize(12, 12)
    unusableInfoIcon:SetPoint("CENTER")
    unusableInfoIcon:SetAtlas("QuestRepeatableTurnin")
    unusableInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Unusable Dimming")
        GameTooltip:AddLine("Tints spell and item icons when unusable due to insufficient resources or other restrictions. Out-of-range tinting takes priority when both apply.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    unusableInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, unusableInfo)

    if style.showUnusable then
        local unusableColor = AceGUI:Create("ColorPicker")
        unusableColor:SetLabel("Unusable Tint Color")
        unusableColor:SetHasAlpha(false)
        local uc = style.unusableColor or {0.3, 0.3, 0.6}
        unusableColor:SetColor(uc[1], uc[2], uc[3])
        unusableColor:SetFullWidth(true)
        unusableColor:SetCallback("OnValueChanged", function(widget, event, r, g, b)
            style.unusableColor = {r, g, b}
        end)
        unusableColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
            style.unusableColor = {r, g, b}
        end)
        container:AddChild(unusableColor)
    end

    -- Assisted Highlight section
    local assistedHeading = AceGUI:Create("Heading")
    assistedHeading:SetText("Assisted Highlight")
    assistedHeading:SetFullWidth(true)
    container:AddChild(assistedHeading)

    local assistedCb = AceGUI:Create("CheckBox")
    assistedCb:SetLabel("Show Assisted Highlight")
    assistedCb:SetValue(style.showAssistedHighlight or false)
    assistedCb:SetFullWidth(true)
    assistedCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showAssistedHighlight = val
        SetCVar("assistedCombatHighlight", val and "1" or "0")
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(assistedCb)

    if style.showAssistedHighlight then
        local highlightStyles = {
            blizzard = "Blizzard (Marching Ants)",
            proc = "Proc Glow",
            solid = "Solid Border",
        }
        local styleDrop = AceGUI:Create("Dropdown")
        styleDrop:SetLabel("Highlight Style")
        styleDrop:SetList(highlightStyles)
        styleDrop:SetValue(style.assistedHighlightStyle or "blizzard")
        styleDrop:SetFullWidth(true)
        styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.assistedHighlightStyle = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(styleDrop)

        if style.assistedHighlightStyle == "solid" then
            local hlColor = AceGUI:Create("ColorPicker")
            hlColor:SetLabel("Highlight Color")
            hlColor:SetHasAlpha(true)
            local c = style.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
            hlColor:SetColor(c[1], c[2], c[3], c[4])
            hlColor:SetFullWidth(true)
            hlColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                style.assistedHighlightColor = {r, g, b, a}
            end)
            hlColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                style.assistedHighlightColor = {r, g, b, a}
            end)
            container:AddChild(hlColor)

            local hlSizeSlider = AceGUI:Create("Slider")
            hlSizeSlider:SetLabel("Border Size")
            hlSizeSlider:SetSliderValues(1, 6, 0.5)
            hlSizeSlider:SetValue(style.assistedHighlightBorderSize or 2)
            hlSizeSlider:SetFullWidth(true)
            hlSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.assistedHighlightBorderSize = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            container:AddChild(hlSizeSlider)
        elseif style.assistedHighlightStyle == "blizzard" then
            local blizzSlider = AceGUI:Create("Slider")
            blizzSlider:SetLabel("Glow Size")
            blizzSlider:SetSliderValues(0, 60, 1)
            blizzSlider:SetValue(style.assistedHighlightBlizzardOverhang or 32)
            blizzSlider:SetFullWidth(true)
            blizzSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.assistedHighlightBlizzardOverhang = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            container:AddChild(blizzSlider)
        elseif style.assistedHighlightStyle == "proc" then
            local procHlColor = AceGUI:Create("ColorPicker")
            procHlColor:SetLabel("Glow Color")
            procHlColor:SetHasAlpha(true)
            local phc = style.assistedHighlightProcColor or {1, 1, 1, 1}
            procHlColor:SetColor(phc[1], phc[2], phc[3], phc[4])
            procHlColor:SetFullWidth(true)
            procHlColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                style.assistedHighlightProcColor = {r, g, b, a}
            end)
            procHlColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                style.assistedHighlightProcColor = {r, g, b, a}
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            container:AddChild(procHlColor)

            local procSlider = AceGUI:Create("Slider")
            procSlider:SetLabel("Glow Size")
            procSlider:SetSliderValues(0, 60, 1)
            procSlider:SetValue(style.assistedHighlightProcOverhang or 32)
            procSlider:SetFullWidth(true)
            procSlider:SetCallback("OnValueChanged", function(widget, event, val)
                style.assistedHighlightProcOverhang = val
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            end)
            container:AddChild(procSlider)
        end
    end
    end -- not isBarMode

    -- "Alpha" heading with (?) info button
    local alphaHeading = AceGUI:Create("Heading")
    alphaHeading:SetText("Alpha")
    alphaHeading:SetFullWidth(true)
    container:AddChild(alphaHeading)

    local alphaInfo = CreateFrame("Button", nil, alphaHeading.frame)
    alphaInfo:SetSize(16, 16)
    alphaInfo:SetPoint("LEFT", alphaHeading.label, "RIGHT", 4, 0)
    alphaHeading.right:SetPoint("LEFT", alphaInfo, "RIGHT", 4, 0)
    local alphaInfoIcon = alphaInfo:CreateTexture(nil, "OVERLAY")
    alphaInfoIcon:SetSize(12, 12)
    alphaInfoIcon:SetPoint("CENTER")
    alphaInfoIcon:SetAtlas("QuestRepeatableTurnin")
    alphaInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Alpha")
        GameTooltip:AddLine("Controls the transparency of this group. Alpha = 1 is fully visible. Alpha = 0 means completely hidden.\n\nSetting baseline alpha below 1 reveals visibility override options.\n\nThe first three options (In Combat, Out of Combat, Mounted) are 3-way toggles — click to cycle through Disabled, |cff00ff00Fully Visible|r, and |cffff0000Fully Hidden|r.\n\n|cff00ff00Fully Visible|r overrides alpha to 1 when the condition is met.\n\n|cffff0000Fully Hidden|r overrides alpha to 0 when the condition is met.\n\nIf both apply simultaneously, |cff00ff00Fully Visible|r takes priority.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    alphaInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, alphaInfo)

    -- Baseline Alpha slider
    local baseAlphaSlider = AceGUI:Create("Slider")
    baseAlphaSlider:SetLabel("Baseline Alpha")
    baseAlphaSlider:SetSliderValues(0, 1, 0.05)
    baseAlphaSlider:SetValue(group.baselineAlpha or 1)
    baseAlphaSlider:SetFullWidth(true)
    baseAlphaSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.baselineAlpha = val
        -- Apply alpha immediately for live preview
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame and frame:IsShown() then
            frame:SetAlpha(val)
        end
        -- Sync alpha state in-place so the OnUpdate loop doesn't fight the slider
        local state = CooldownCompanion.alphaState and CooldownCompanion.alphaState[CS.selectedGroup]
        if state then
            state.currentAlpha = val
            state.desiredAlpha = val
            state.lastAlpha = val
            state.fadeDuration = 0
        end
    end)
    baseAlphaSlider:SetCallback("OnMouseUp", function()
        -- Rebuild UI when crossing the 1.0 boundary to show/hide conditional section
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(baseAlphaSlider)

    -- Conditional section: visible when baselineAlpha < 1 OR any forceHide toggle is active
    local showConditional = (group.baselineAlpha or 1) < 1
        or group.forceHideInCombat or group.forceHideOutOfCombat
        or group.forceHideMounted
    if showConditional then
        -- Helper: convert forceAlpha/forceHide pair to tristate value
        -- true = Force Visible, nil = Force Hidden, false = Disabled
        local function GetTriState(visibleKey, hiddenKey)
            if group[hiddenKey] then return nil end
            if group[visibleKey] then return true end
            return false
        end

        -- Helper: build label with colored state suffix
        local function TriStateLabel(base, value)
            if value == true then
                return base .. " - |cff00ff00Fully Visible|r"
            elseif value == nil then
                return base .. " - |cffff0000Fully Hidden|r"
            end
            return base
        end

        -- Helper: create a 3-way tristate checkbox (Disabled / Force Visible / Force Hidden)
        local function CreateTriStateToggle(label, visibleKey, hiddenKey)
            local val = GetTriState(visibleKey, hiddenKey)
            local cb = AceGUI:Create("CheckBox")
            cb:SetTriState(true)
            cb:SetLabel(TriStateLabel(label, val))
            cb:SetValue(val)
            cb:SetFullWidth(true)
            cb:SetCallback("OnValueChanged", function(widget, event, newVal)
                -- Cycle: false (disabled) → true (visible) → nil (hidden) → false
                group[visibleKey] = (newVal == true)
                group[hiddenKey] = (newVal == nil)
                CooldownCompanion:RefreshConfigPanel()
            end)
            return cb
        end

        -- Heading
        local overridesHeading = AceGUI:Create("Heading")
        overridesHeading:SetText("Visibility Overrides")
        overridesHeading:SetFullWidth(true)
        container:AddChild(overridesHeading)

        -- 3-way tristate toggles (Disabled / Force Visible / Force Hidden)
        container:AddChild(CreateTriStateToggle("In Combat", "forceAlphaInCombat", "forceHideInCombat"))
        container:AddChild(CreateTriStateToggle("Out of Combat", "forceAlphaOutOfCombat", "forceHideOutOfCombat"))
        container:AddChild(CreateTriStateToggle("Mounted", "forceAlphaMounted", "forceHideMounted"))

        -- "Include Druid Travel Form" nested checkbox
        -- Show when: mounted toggle is not Disabled AND (global group OR player is a Druid)
        local mountedActive = group.forceAlphaMounted or group.forceHideMounted
        local isDruid = CooldownCompanion._playerClassID == 11
        if mountedActive and (group.isGlobal or isDruid) then
            local travelVal = group.treatTravelFormAsMounted or false
            local travelCb = AceGUI:Create("CheckBox")
            travelCb:SetLabel("Include Druid Travel Form")
            travelCb:SetValue(travelVal)
            travelCb:SetFullWidth(true)
            travelCb:SetCallback("OnValueChanged", function(widget, event, val)
                group.treatTravelFormAsMounted = val
            end)
            container:AddChild(travelCb)
        end

        -- Target Exists checkbox (force-visible only)
        local targetVal = group.forceAlphaTargetExists or false
        local targetCb = AceGUI:Create("CheckBox")
        targetCb:SetLabel(targetVal and "Target Exists - |cff00ff00Fully Visible|r" or "Target Exists")
        targetCb:SetValue(targetVal)
        targetCb:SetFullWidth(true)
        targetCb:SetCallback("OnValueChanged", function(widget, event, val)
            group.forceAlphaTargetExists = val
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(targetCb)

        -- Mouseover checkbox (force-visible only, overrides all other conditions)
        local mouseoverVal = group.forceAlphaMouseover or false
        local mouseoverCb = AceGUI:Create("CheckBox")
        mouseoverCb:SetLabel(mouseoverVal and "Mouseover - |cff00ff00Fully Visible|r" or "Mouseover")
        mouseoverCb:SetValue(mouseoverVal)
        mouseoverCb:SetFullWidth(true)
        mouseoverCb:SetCallback("OnValueChanged", function(widget, event, val)
            group.forceAlphaMouseover = val
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(mouseoverCb)

        local mouseoverInfo = CreateFrame("Button", nil, mouseoverCb.frame)
        mouseoverInfo:SetSize(16, 16)
        mouseoverInfo:SetPoint("LEFT", mouseoverCb.text, "RIGHT", 4, 0)
        local mouseoverInfoIcon = mouseoverInfo:CreateTexture(nil, "OVERLAY")
        mouseoverInfoIcon:SetSize(12, 12)
        mouseoverInfoIcon:SetPoint("CENTER")
        mouseoverInfoIcon:SetAtlas("QuestRepeatableTurnin")
        mouseoverInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Mouseover")
            GameTooltip:AddLine("When enabled, mousing over the group forces it to full visibility. Like all |cff00ff00Force Visible|r conditions, this overrides |cffff0000Force Hidden|r.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        mouseoverInfo:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        table.insert(tabInfoButtons, mouseoverInfo)

        -- Fade Delay slider
        local fadeDelaySlider = AceGUI:Create("Slider")
        fadeDelaySlider:SetLabel("Fade Delay (seconds)")
        fadeDelaySlider:SetSliderValues(0, 5, 0.1)
        fadeDelaySlider:SetValue(group.fadeDelay or 1)
        fadeDelaySlider:SetFullWidth(true)
        fadeDelaySlider:SetCallback("OnValueChanged", function(widget, event, val)
            group.fadeDelay = val
        end)
        container:AddChild(fadeDelaySlider)

        -- Fade In Duration slider
        local fadeInSlider = AceGUI:Create("Slider")
        fadeInSlider:SetLabel("Fade In Duration (seconds)")
        fadeInSlider:SetSliderValues(0, 5, 0.1)
        fadeInSlider:SetValue(group.fadeInDuration or 0.2)
        fadeInSlider:SetFullWidth(true)
        fadeInSlider:SetCallback("OnValueChanged", function(widget, event, val)
            group.fadeInDuration = val
        end)
        container:AddChild(fadeInSlider)

        -- Fade Out Duration slider
        local fadeOutSlider = AceGUI:Create("Slider")
        fadeOutSlider:SetLabel("Fade Out Duration (seconds)")
        fadeOutSlider:SetSliderValues(0, 5, 0.1)
        fadeOutSlider:SetValue(group.fadeOutDuration or 0.2)
        fadeOutSlider:SetFullWidth(true)
        fadeOutSlider:SetCallback("OnValueChanged", function(widget, event, val)
            group.fadeOutDuration = val
        end)
        container:AddChild(fadeOutSlider)
    end

    -- Apply "Hide CDC Tooltips" to tab info buttons created above
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            btn:Hide()
        end
    end

    -- Other ---------------------------------------------------------------
    -- Masque skinning toggle (only show if Masque is installed, not in bar mode)
    if CooldownCompanion.Masque and not isBarMode then
        local otherHeading = AceGUI:Create("Heading")
        otherHeading:SetText("Other")
        otherHeading:SetFullWidth(true)
        container:AddChild(otherHeading)

        local masqueCb = AceGUI:Create("CheckBox")
        masqueCb:SetLabel("Enable Masque Skinning")
        masqueCb:SetValue(group.masqueEnabled or false)
        masqueCb:SetFullWidth(true)
        masqueCb:SetCallback("OnValueChanged", function(widget, event, val)
            CooldownCompanion:ToggleGroupMasque(CS.selectedGroup, val)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(masqueCb)

        -- (?) info tooltip for Masque
        local masqueInfo = CreateFrame("Button", nil, masqueCb.frame)
        masqueInfo:SetSize(16, 16)
        masqueInfo:SetPoint("LEFT", masqueCb.checkbg, "RIGHT", masqueCb.text:GetStringWidth() + 4, 0)
        local masqueInfoIcon = masqueInfo:CreateTexture(nil, "OVERLAY")
        masqueInfoIcon:SetSize(12, 12)
        masqueInfoIcon:SetPoint("CENTER")
        masqueInfoIcon:SetAtlas("QuestRepeatableTurnin")
        masqueInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Masque Skinning")
            GameTooltip:AddLine("Uses the Masque addon to apply custom button skins to this group. Configure skins via /masque or the Masque config panel.", 1, 1, 1, true)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Overridden Settings:", 1, 0.82, 0)
            GameTooltip:AddLine("Border Size, Border Color, Square Icons (forced on)", 0.7, 0.7, 0.7, true)
            GameTooltip:Show()
        end)
        masqueInfo:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        table.insert(tabInfoButtons, masqueInfo)

        -- Hide info button if setting is enabled
        if CooldownCompanion.db.profile.hideInfoButtons then
            masqueInfo:Hide()
        end
    end

end

local function BuildPositioningTab(container)
    for _, elem in ipairs(appearanceTabElements) do
        elem:ClearAllPoints()
        elem:Hide()
        elem:SetParent(nil)
    end
    wipe(appearanceTabElements)

    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    -- Anchor to Frame (editbox + pick button row)
    local anchorRow = AceGUI:Create("SimpleGroup")
    anchorRow:SetFullWidth(true)
    anchorRow:SetLayout("Flow")

    local anchorBox = AceGUI:Create("EditBox")
    if anchorBox.editbox.Instructions then anchorBox.editbox.Instructions:Hide() end
    anchorBox:SetLabel("Anchor to Frame")
    local currentAnchor = group.anchor.relativeTo
    if currentAnchor == "UIParent" then currentAnchor = "" end
    anchorBox:SetText(currentAnchor)
    anchorBox:SetRelativeWidth(0.68)
    anchorBox:SetCallback("OnEnterPressed", function(widget, event, text)
        local wasAnchored = group.anchor.relativeTo and group.anchor.relativeTo ~= "UIParent"
        if text == "" then
            CooldownCompanion:SetGroupAnchor(CS.selectedGroup, "UIParent", wasAnchored)
        else
            CooldownCompanion:SetGroupAnchor(CS.selectedGroup, text)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    anchorRow:AddChild(anchorBox)

    local pickBtn = AceGUI:Create("Button")
    pickBtn:SetText("Pick")
    pickBtn:SetRelativeWidth(0.24)
    pickBtn:SetCallback("OnClick", function()
        local grp = CS.selectedGroup
        CS.StartPickFrame(function(name)
            -- Re-show config panel
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if name then
                CooldownCompanion:SetGroupAnchor(grp, name)
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
    end)
    anchorRow:AddChild(pickBtn)

    -- (?) tooltip for anchor picking
    local pickInfo = CreateFrame("Button", nil, pickBtn.frame)
    pickInfo:SetSize(16, 16)
    pickInfo:SetPoint("LEFT", pickBtn.frame, "RIGHT", 2, 0)
    local pickInfoIcon = pickInfo:CreateTexture(nil, "OVERLAY")
    pickInfoIcon:SetSize(12, 12)
    pickInfoIcon:SetPoint("CENTER")
    pickInfoIcon:SetAtlas("QuestRepeatableTurnin")
    pickInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Pick Frame")
        GameTooltip:AddLine("Hides the config panel and highlights frames under your cursor. Left-click a frame to anchor this group to it, or right-click to cancel.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("You can also type a frame name directly into the editbox.", 1, 1, 1, true)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Middle-click the draggable header to toggle lock/unlock.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    pickInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, pickInfo)

    container:AddChild(anchorRow)
    pickBtn.frame:SetScript("OnUpdate", function(self)
        self:SetScript("OnUpdate", nil)
        local p, rel, rp, xOfs, yOfs = self:GetPoint(1)
        if yOfs then
            self:SetPoint(p, rel, rp, xOfs, yOfs - 2)
        end
    end)

    -- Anchor Point dropdown
    local pointValues = {}
    for _, pt in ipairs(CS.anchorPoints) do
        pointValues[pt] = CS.anchorPointLabels[pt]
    end

    local anchorPt = AceGUI:Create("Dropdown")
    anchorPt:SetLabel("Anchor Point")
    anchorPt:SetList(pointValues)
    anchorPt:SetValue(group.anchor.point or "CENTER")
    anchorPt:SetFullWidth(true)
    anchorPt:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.point = val
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    container:AddChild(anchorPt)

    -- Relative Point dropdown
    local relPt = AceGUI:Create("Dropdown")
    relPt:SetLabel("Relative Point")
    relPt:SetList(pointValues)
    relPt:SetValue(group.anchor.relativePoint or "CENTER")
    relPt:SetFullWidth(true)
    relPt:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.relativePoint = val
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    container:AddChild(relPt)

    -- Allow decimal input from editbox while keeping slider/wheel at 1px steps
    local function HookSliderEditBox(sliderWidget)
        sliderWidget.editbox:SetScript("OnEnterPressed", function(editbox)
            local widget = editbox.obj
            local value = tonumber(editbox:GetText())
            if value then
                value = math.floor(value * 10 + 0.5) / 10
                value = math.max(widget.min, math.min(widget.max, value))
                PlaySound(856)
                widget:SetValue(value)
                widget:Fire("OnValueChanged", value)
                widget:Fire("OnMouseUp", value)
            end
        end)
    end

    -- X Offset
    local xSlider = AceGUI:Create("Slider")
    xSlider:SetLabel("X Offset")
    xSlider:SetSliderValues(-2000, 2000, 1)
    xSlider:SetValue(group.anchor.x or 0)
    xSlider:SetFullWidth(true)
    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.x = val
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    HookSliderEditBox(xSlider)
    container:AddChild(xSlider)

    -- Y Offset
    local ySlider = AceGUI:Create("Slider")
    ySlider:SetLabel("Y Offset")
    ySlider:SetSliderValues(-2000, 2000, 1)
    ySlider:SetValue(group.anchor.y or 0)
    ySlider:SetFullWidth(true)
    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.anchor.y = val
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then
            CooldownCompanion:AnchorGroupFrame(frame, group.anchor)
        end
    end)
    HookSliderEditBox(ySlider)
    container:AddChild(ySlider)

    -- Orientation / Layout controls (mode-dependent)
    if group.displayMode == "bars" then
        -- Vertical Bar Fill checkbox
        local vertFillCheck = AceGUI:Create("CheckBox")
        vertFillCheck:SetLabel("Vertical Bar Fill")
        vertFillCheck:SetValue(group.style.barFillVertical or false)
        vertFillCheck:SetFullWidth(true)
        vertFillCheck:SetCallback("OnValueChanged", function(widget, event, val)
            group.style.barFillVertical = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(vertFillCheck)

        -- Flip Fill/Drain Direction checkbox
        local reverseFillCheck = AceGUI:Create("CheckBox")
        reverseFillCheck:SetLabel("Flip Fill/Drain Direction")
        reverseFillCheck:SetValue(group.style.barReverseFill or false)
        reverseFillCheck:SetFullWidth(true)
        reverseFillCheck:SetCallback("OnValueChanged", function(widget, event, val)
            group.style.barReverseFill = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        container:AddChild(reverseFillCheck)

        -- Horizontal Bar Layout checkbox (only when >1 button)
        if #group.buttons > 1 then
            local horzLayoutCheck = AceGUI:Create("CheckBox")
            horzLayoutCheck:SetLabel("Horizontal Bar Layout")
            horzLayoutCheck:SetValue((group.style.orientation or "vertical") == "horizontal")
            horzLayoutCheck:SetFullWidth(true)
            horzLayoutCheck:SetCallback("OnValueChanged", function(widget, event, val)
                group.style.orientation = val and "horizontal" or "vertical"
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end)
            container:AddChild(horzLayoutCheck)
        end
    else
        local orientDrop = AceGUI:Create("Dropdown")
        orientDrop:SetLabel("Orientation")
        orientDrop:SetList({ horizontal = "Horizontal", vertical = "Vertical" })
        orientDrop:SetValue(group.style.orientation or "horizontal")
        orientDrop:SetFullWidth(true)
        orientDrop:SetCallback("OnValueChanged", function(widget, event, val)
            group.style.orientation = val
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        container:AddChild(orientDrop)
    end

    -- Buttons Per Row/Column
    local numButtons = math.max(1, #group.buttons)
    local bprSlider = AceGUI:Create("Slider")
    bprSlider:SetLabel("Buttons Per Row/Column")
    bprSlider:SetSliderValues(1, numButtons, 1)
    bprSlider:SetValue(math.min(group.style.buttonsPerRow or 12, numButtons))
    bprSlider:SetFullWidth(true)
    bprSlider:SetCallback("OnValueChanged", function(widget, event, val)
        group.style.buttonsPerRow = val
        CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    end)
    container:AddChild(bprSlider)

    -- ================================================================
    -- Strata (Layer Order) — hidden for bar mode
    -- ================================================================
    if group.displayMode ~= "bars" then
    local strataHeading = AceGUI:Create("Heading")
    strataHeading:SetText("Strata")
    strataHeading:SetFullWidth(true)
    container:AddChild(strataHeading)

    local style = group.style
    local customStrataEnabled = type(style.strataOrder) == "table"

    local strataToggle = AceGUI:Create("CheckBox")
    strataToggle:SetLabel("Custom Strata")
    strataToggle:SetValue(customStrataEnabled)
    strataToggle:SetFullWidth(true)
    strataToggle:SetCallback("OnValueChanged", function(widget, event, val)
        if not val then
            style.strataOrder = nil
            CS.pendingStrataOrder = {nil, nil, nil, nil}
            CS.pendingStrataGroup = CS.selectedGroup
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        else
            style.strataOrder = style.strataOrder or {}
            -- Force reinitialize so defaults always appear in dropdowns
            CS.pendingStrataOrder = nil
            CS.InitPendingStrataOrder(CS.selectedGroup)
        end
        -- Rebuild tab to show/hide dropdowns (toggle is a deliberate action)
        if CS.col3Container and CS.col3Container.tabGroup then
            CS.col3Container.tabGroup:SelectTab(CS.selectedTab)
        end
    end)
    container:AddChild(strataToggle)

    -- (?) tooltip for custom strata
    local strataInfo = CreateFrame("Button", nil, strataToggle.frame)
    strataInfo:SetSize(16, 16)
    strataInfo:SetPoint("LEFT", strataToggle.checkbg, "RIGHT", strataToggle.text:GetStringWidth() + 4, 0)
    local strataInfoIcon = strataInfo:CreateTexture(nil, "OVERLAY")
    strataInfoIcon:SetSize(12, 12)
    strataInfoIcon:SetPoint("CENTER")
    strataInfoIcon:SetAtlas("QuestRepeatableTurnin")
    strataInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Custom Strata")
        GameTooltip:AddLine("Controls the draw order of overlays on each icon: Cooldown Swipe, Charge Text, Proc Glow, and Assisted Highlight.", 1, 1, 1, true)
        GameTooltip:AddLine("Layer 4 draws on top, Layer 1 on the bottom. When disabled, the default order is used.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    strataInfo:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    table.insert(tabInfoButtons, strataInfo)

    if customStrataEnabled then
        -- Initialize pending state for this group
        CS.InitPendingStrataOrder(CS.selectedGroup)

        -- Build dropdown list: all 4 element options
        local strataDropdownList = {}
        for _, key in ipairs(CS.strataElementKeys) do
            strataDropdownList[key] = CS.strataElementLabels[key]
        end

        -- Create 4 dropdowns: position 4 (top) displayed first, position 1 (bottom) last
        local strataDropdowns = {}
        for displayIdx = 1, 4 do
            local pos = 5 - displayIdx  -- 4, 3, 2, 1
            local label
            if pos == 4 then
                label = "Layer 4 (Top)"
            elseif pos == 1 then
                label = "Layer 1 (Bottom)"
            else
                label = "Layer " .. pos
            end

            local drop = AceGUI:Create("Dropdown")
            drop:SetLabel(label)
            drop:SetList(strataDropdownList)
            drop:SetValue(CS.pendingStrataOrder[pos])
            drop:SetFullWidth(true)
            drop:SetCallback("OnValueChanged", function(widget, event, val)
                -- Clear this value from any other position (mutual exclusion)
                for i = 1, 4 do
                    if i ~= pos and CS.pendingStrataOrder[i] == val then
                        CS.pendingStrataOrder[i] = nil
                    end
                end
                CS.pendingStrataOrder[pos] = val

                -- Save if all 4 assigned, otherwise nil out the saved order
                if CS.IsStrataOrderComplete(CS.pendingStrataOrder) then
                    style.strataOrder = {}
                    for i = 1, 4 do
                        style.strataOrder[i] = CS.pendingStrataOrder[i]
                    end
                else
                    style.strataOrder = {}
                end
                CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)

                -- Update sibling dropdowns directly to reflect mutual exclusion
                for i = 1, 4 do
                    if strataDropdowns[i] then
                        strataDropdowns[i]:SetValue(CS.pendingStrataOrder[i])
                    end
                end
            end)
            container:AddChild(drop)
            strataDropdowns[pos] = drop
        end
    end
    end -- not bars (strata)

    -- Apply "Hide CDC Tooltips" to tab info buttons created above
    if CooldownCompanion.db.profile.hideInfoButtons then
        for _, btn in ipairs(tabInfoButtons) do
            btn:Hide()
        end
    end
end

local function BuildBarAppearanceTab(container, group, style)
    -- Bar Settings header
    local barHeading = AceGUI:Create("Heading")
    barHeading:SetText("Bar Settings")
    barHeading:SetFullWidth(true)
    container:AddChild(barHeading)

    local lengthSlider = AceGUI:Create("Slider")
    lengthSlider:SetLabel("Bar Length")
    lengthSlider:SetSliderValues(50, 400, 1)
    lengthSlider:SetValue(style.barLength or 180)
    lengthSlider:SetFullWidth(true)
    lengthSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barLength = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(lengthSlider)

    local heightSlider = AceGUI:Create("Slider")
    heightSlider:SetLabel("Bar Height")
    heightSlider:SetSliderValues(10, 50, 0.1)
    heightSlider:SetValue(style.barHeight or 20)
    heightSlider:SetFullWidth(true)
    heightSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barHeight = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(heightSlider)

    local iconRow = AceGUI:Create("SimpleGroup")
    iconRow:SetFullWidth(true)
    iconRow:SetLayout("Flow")
    container:AddChild(iconRow)

    local showIconCb = AceGUI:Create("CheckBox")
    showIconCb:SetLabel("Show Icon")
    showIconCb:SetValue(style.showBarIcon ~= false)
    showIconCb:SetRelativeWidth(0.5)
    showIconCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showBarIcon = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    iconRow:AddChild(showIconCb)

    if style.showBarIcon ~= false then
        local flipIconCheck = AceGUI:Create("CheckBox")
        flipIconCheck:SetLabel("Flip Icon Side")
        flipIconCheck:SetValue(style.barIconReverse or false)
        flipIconCheck:SetRelativeWidth(0.5)
        flipIconCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barIconReverse = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        iconRow:AddChild(flipIconCheck)
    end

    if style.showBarIcon ~= false then
        local iconOffsetSlider = AceGUI:Create("Slider")
        iconOffsetSlider:SetLabel("Icon Offset")
        iconOffsetSlider:SetSliderValues(-5, 20, 1)
        iconOffsetSlider:SetValue(style.barIconOffset or 0)
        iconOffsetSlider:SetFullWidth(true)
        iconOffsetSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barIconOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(iconOffsetSlider)
    end

    if group.buttons and #group.buttons > 1 then
        local spacingSlider = AceGUI:Create("Slider")
        spacingSlider:SetLabel("Bar Spacing")
        spacingSlider:SetSliderValues(0, 10, 0.1)
        spacingSlider:SetValue(style.buttonSpacing or ST.BUTTON_SPACING)
        spacingSlider:SetFullWidth(true)
        spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSpacing = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(spacingSlider)
    end

    local updateFreqSlider = AceGUI:Create("Slider")
    updateFreqSlider:SetLabel("Update Frequency (Hz)")
    updateFreqSlider:SetSliderValues(10, 60, 1)
    local curInterval = style.barUpdateInterval or 0.025
    updateFreqSlider:SetValue(math.floor(1 / curInterval + 0.5))
    updateFreqSlider:SetFullWidth(true)
    updateFreqSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.barUpdateInterval = 1 / val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(updateFreqSlider)

    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(style.borderSize or ST.DEFAULT_BORDER_SIZE)
    borderSlider:SetFullWidth(true)
    borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.borderSize = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderSlider)

    local borderColor = AceGUI:Create("ColorPicker")
    borderColor:SetLabel("Border Color")
    borderColor:SetHasAlpha(true)
    local bc = style.borderColor or {0, 0, 0, 1}
    borderColor:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColor:SetFullWidth(true)
    borderColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    borderColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderColor)

    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel("Bar Color")
    barColorPicker:SetHasAlpha(true)
    local brc = style.barColor or {0.2, 0.6, 1.0, 1.0}
    barColorPicker:SetColor(brc[1], brc[2], brc[3], brc[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barColorPicker)

    local barCdColorPicker = AceGUI:Create("ColorPicker")
    barCdColorPicker:SetLabel("Bar Cooldown Color")
    barCdColorPicker:SetHasAlpha(true)
    local bcc = style.barCooldownColor or {0.6, 0.6, 0.6, 1.0}
    barCdColorPicker:SetColor(bcc[1], bcc[2], bcc[3], bcc[4])
    barCdColorPicker:SetFullWidth(true)
    barCdColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barCooldownColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    barCdColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barCooldownColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barCdColorPicker)

    local barBgColorPicker = AceGUI:Create("ColorPicker")
    barBgColorPicker:SetLabel("Bar Background Color")
    barBgColorPicker:SetHasAlpha(true)
    local bbg = style.barBgColor or {0.1, 0.1, 0.1, 0.8}
    barBgColorPicker:SetColor(bbg[1], bbg[2], bbg[3], bbg[4])
    barBgColorPicker:SetFullWidth(true)
    barBgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barBgColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    barBgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barBgColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barBgColorPicker)

    -- Name Text heading
    local nameHeading = AceGUI:Create("Heading")
    nameHeading:SetText("Name Text")
    nameHeading:SetFullWidth(true)
    container:AddChild(nameHeading)

    local nameRow = AceGUI:Create("SimpleGroup")
    nameRow:SetFullWidth(true)
    nameRow:SetLayout("Flow")
    container:AddChild(nameRow)

    local showNameCb = AceGUI:Create("CheckBox")
    showNameCb:SetLabel("Show Name Text")
    showNameCb:SetValue(style.showBarNameText ~= false)
    if style.showBarNameText ~= false then
        showNameCb:SetRelativeWidth(0.5)
    else
        showNameCb:SetFullWidth(true)
    end
    showNameCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showBarNameText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    nameRow:AddChild(showNameCb)

    if style.showBarNameText ~= false then
        local flipNameCheck = AceGUI:Create("CheckBox")
        flipNameCheck:SetLabel("Flip Name Text")
        flipNameCheck:SetValue(style.barNameTextReverse or false)
        flipNameCheck:SetRelativeWidth(0.5)
        flipNameCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameTextReverse = val or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        nameRow:AddChild(flipNameCheck)
    end

    if style.showBarNameText ~= false then
        local nameFontSizeSlider = AceGUI:Create("Slider")
        nameFontSizeSlider:SetLabel("Font Size")
        nameFontSizeSlider:SetSliderValues(6, 24, 1)
        nameFontSizeSlider:SetValue(style.barNameFontSize or 10)
        nameFontSizeSlider:SetFullWidth(true)
        nameFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameFontSizeSlider)

        local nameFontDrop = AceGUI:Create("Dropdown")
        nameFontDrop:SetLabel("Font")
        nameFontDrop:SetList(CS.fontOptions)
        nameFontDrop:SetValue(style.barNameFont or "Fonts\\FRIZQT__.TTF")
        nameFontDrop:SetFullWidth(true)
        nameFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameFontDrop)

        local nameOutlineDrop = AceGUI:Create("Dropdown")
        nameOutlineDrop:SetLabel("Font Outline")
        nameOutlineDrop:SetList(CS.outlineOptions)
        nameOutlineDrop:SetValue(style.barNameFontOutline or "OUTLINE")
        nameOutlineDrop:SetFullWidth(true)
        nameOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameOutlineDrop)

        local nameFontColor = AceGUI:Create("ColorPicker")
        nameFontColor:SetLabel("Font Color")
        nameFontColor:SetHasAlpha(true)
        local nfc = style.barNameFontColor or {1, 1, 1, 1}
        nameFontColor:SetColor(nfc[1], nfc[2], nfc[3], nfc[4])
        nameFontColor:SetFullWidth(true)
        nameFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.barNameFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        nameFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.barNameFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameFontColor)

        local nameOffXSlider = AceGUI:Create("Slider")
        nameOffXSlider:SetLabel("X Offset")
        nameOffXSlider:SetSliderValues(-50, 50, 1)
        nameOffXSlider:SetValue(style.barNameTextOffsetX or 0)
        nameOffXSlider:SetFullWidth(true)
        nameOffXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameTextOffsetX = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameOffXSlider)

        local nameOffYSlider = AceGUI:Create("Slider")
        nameOffYSlider:SetLabel("Y Offset")
        nameOffYSlider:SetSliderValues(-50, 50, 1)
        nameOffYSlider:SetValue(style.barNameTextOffsetY or 0)
        nameOffYSlider:SetFullWidth(true)
        nameOffYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barNameTextOffsetY = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(nameOffYSlider)
    end

    -- Time Text heading
    local timeHeading = AceGUI:Create("Heading")
    timeHeading:SetText("Time Text")
    timeHeading:SetFullWidth(true)
    container:AddChild(timeHeading)

    local timeRow = AceGUI:Create("SimpleGroup")
    timeRow:SetFullWidth(true)
    timeRow:SetLayout("Flow")
    container:AddChild(timeRow)

    local cdTextCb = AceGUI:Create("CheckBox")
    cdTextCb:SetLabel("Show Cooldown Text")
    cdTextCb:SetValue(style.showCooldownText or false)
    if style.showCooldownText then
        cdTextCb:SetRelativeWidth(0.5)
    else
        cdTextCb:SetFullWidth(true)
    end
    cdTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showCooldownText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    timeRow:AddChild(cdTextCb)

    if style.showCooldownText then
        local flipTimeCheck = AceGUI:Create("CheckBox")
        flipTimeCheck:SetLabel("Flip Time Text")
        flipTimeCheck:SetValue(style.barTimeTextReverse or false)
        flipTimeCheck:SetRelativeWidth(0.5)
        flipTimeCheck:SetCallback("OnValueChanged", function(widget, event, val)
            style.barTimeTextReverse = val or nil
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        timeRow:AddChild(flipTimeCheck)

        -- (?) tooltip for Flip Time Text
        local flipTimeInfo = CreateFrame("Button", nil, flipTimeCheck.frame)
        flipTimeInfo:SetSize(16, 16)
        flipTimeInfo:SetPoint("LEFT", flipTimeCheck.checkbg, "RIGHT", flipTimeCheck.text:GetStringWidth() + 4, 0)
        local flipTimeInfoIcon = flipTimeInfo:CreateTexture(nil, "OVERLAY")
        flipTimeInfoIcon:SetSize(12, 12)
        flipTimeInfoIcon:SetPoint("CENTER")
        flipTimeInfoIcon:SetAtlas("QuestRepeatableTurnin")
        flipTimeInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Flip Time Text")
            GameTooltip:AddLine("Applies to all time-based text, including cooldown time, aura time, and ready text.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        flipTimeInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        flipTimeCheck:SetCallback("OnRelease", function()
            flipTimeInfo:ClearAllPoints()
            flipTimeInfo:Hide()
            flipTimeInfo:SetParent(nil)
        end)
    end

    if style.showCooldownText then
        local fontSizeSlider = AceGUI:Create("Slider")
        fontSizeSlider:SetLabel("Font Size")
        fontSizeSlider:SetSliderValues(6, 24, 1)
        fontSizeSlider:SetValue(style.cooldownFontSize or 12)
        fontSizeSlider:SetFullWidth(true)
        fontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(fontSizeSlider)

        local fontDrop = AceGUI:Create("Dropdown")
        fontDrop:SetLabel("Font")
        fontDrop:SetList(CS.fontOptions)
        fontDrop:SetValue(style.cooldownFont or "Fonts\\FRIZQT__.TTF")
        fontDrop:SetFullWidth(true)
        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(fontDrop)

        local outlineDrop = AceGUI:Create("Dropdown")
        outlineDrop:SetLabel("Font Outline")
        outlineDrop:SetList(CS.outlineOptions)
        outlineDrop:SetValue(style.cooldownFontOutline or "OUTLINE")
        outlineDrop:SetFullWidth(true)
        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(outlineDrop)

        local cdFontColor = AceGUI:Create("ColorPicker")
        cdFontColor:SetLabel("Font Color")
        cdFontColor:SetHasAlpha(true)
        local cdc = style.cooldownFontColor or {1, 1, 1, 1}
        cdFontColor:SetColor(cdc[1], cdc[2], cdc[3], cdc[4])
        cdFontColor:SetFullWidth(true)
        cdFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        cdFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdFontColor)

        local cdOffXSlider = AceGUI:Create("Slider")
        cdOffXSlider:SetLabel("X Offset")
        cdOffXSlider:SetSliderValues(-50, 50, 1)
        cdOffXSlider:SetValue(style.barCdTextOffsetX or 0)
        cdOffXSlider:SetFullWidth(true)
        cdOffXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barCdTextOffsetX = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdOffXSlider)

        local cdOffYSlider = AceGUI:Create("Slider")
        cdOffYSlider:SetLabel("Y Offset")
        cdOffYSlider:SetSliderValues(-50, 50, 1)
        cdOffYSlider:SetValue(style.barCdTextOffsetY or 0)
        cdOffYSlider:SetFullWidth(true)
        cdOffYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barCdTextOffsetY = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdOffYSlider)
    end

    -- Aura Text section
    local auraTextHeading = AceGUI:Create("Heading")
    auraTextHeading:SetText("Aura Text")
    auraTextHeading:SetFullWidth(true)
    container:AddChild(auraTextHeading)

    local auraTextCb = AceGUI:Create("CheckBox")
    auraTextCb:SetLabel("Show Aura Text")
    auraTextCb:SetValue(style.showAuraText ~= false)
    auraTextCb:SetFullWidth(true)
    auraTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showAuraText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraTextCb)

    if style.showAuraText ~= false then
        local auraFontSizeSlider = AceGUI:Create("Slider")
        auraFontSizeSlider:SetLabel("Font Size")
        auraFontSizeSlider:SetSliderValues(6, 24, 1)
        auraFontSizeSlider:SetValue(style.auraTextFontSize or 12)
        auraFontSizeSlider:SetFullWidth(true)
        auraFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontSizeSlider)

        local auraFontDrop = AceGUI:Create("Dropdown")
        auraFontDrop:SetLabel("Font")
        auraFontDrop:SetList(CS.fontOptions)
        auraFontDrop:SetValue(style.auraTextFont or "Fonts\\FRIZQT__.TTF")
        auraFontDrop:SetFullWidth(true)
        auraFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontDrop)

        local auraOutlineDrop = AceGUI:Create("Dropdown")
        auraOutlineDrop:SetLabel("Font Outline")
        auraOutlineDrop:SetList(CS.outlineOptions)
        auraOutlineDrop:SetValue(style.auraTextFontOutline or "OUTLINE")
        auraOutlineDrop:SetFullWidth(true)
        auraOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraOutlineDrop)

        local auraFontColor = AceGUI:Create("ColorPicker")
        auraFontColor:SetLabel("Font Color")
        auraFontColor:SetHasAlpha(true)
        local ac = style.auraTextFontColor or {0, 0.925, 1, 1}
        auraFontColor:SetColor(ac[1], ac[2], ac[3], ac[4])
        auraFontColor:SetFullWidth(true)
        auraFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.auraTextFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        auraFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.auraTextFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontColor)
    end

    local readySep = AceGUI:Create("Heading")
    readySep:SetText("")
    readySep:SetFullWidth(true)
    container:AddChild(readySep)

    local showReadyCb = AceGUI:Create("CheckBox")
    showReadyCb:SetLabel("Show Ready Text")
    showReadyCb:SetValue(style.showBarReadyText or false)
    showReadyCb:SetFullWidth(true)
    showReadyCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showBarReadyText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showReadyCb)

    if style.showBarReadyText then
        local readyTextBox = AceGUI:Create("EditBox")
        if readyTextBox.editbox.Instructions then readyTextBox.editbox.Instructions:Hide() end
        readyTextBox:SetLabel("Ready Text")
        readyTextBox:SetText(style.barReadyText or "Ready")
        readyTextBox:SetFullWidth(true)
        readyTextBox:SetCallback("OnEnterPressed", function(widget, event, val)
            style.barReadyText = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyTextBox)

        local readyColorPicker = AceGUI:Create("ColorPicker")
        readyColorPicker:SetLabel("Ready Text Color")
        readyColorPicker:SetHasAlpha(true)
        local rtc = style.barReadyTextColor or {0.2, 1.0, 0.2, 1.0}
        readyColorPicker:SetColor(rtc[1], rtc[2], rtc[3], rtc[4])
        readyColorPicker:SetFullWidth(true)
        readyColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.barReadyTextColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        readyColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.barReadyTextColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyColorPicker)

        local readyFontSizeSlider = AceGUI:Create("Slider")
        readyFontSizeSlider:SetLabel("Font Size")
        readyFontSizeSlider:SetSliderValues(6, 24, 1)
        readyFontSizeSlider:SetValue(style.barReadyFontSize or 12)
        readyFontSizeSlider:SetFullWidth(true)
        readyFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.barReadyFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyFontSizeSlider)

        local readyFontDrop = AceGUI:Create("Dropdown")
        readyFontDrop:SetLabel("Font")
        readyFontDrop:SetList(CS.fontOptions)
        readyFontDrop:SetValue(style.barReadyFont or "Fonts\\FRIZQT__.TTF")
        readyFontDrop:SetFullWidth(true)
        readyFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barReadyFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyFontDrop)

        local readyOutlineDrop = AceGUI:Create("Dropdown")
        readyOutlineDrop:SetLabel("Font Outline")
        readyOutlineDrop:SetList(CS.outlineOptions)
        readyOutlineDrop:SetValue(style.barReadyFontOutline or "OUTLINE")
        readyOutlineDrop:SetFullWidth(true)
        readyOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.barReadyFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(readyOutlineDrop)
    end

end

local function BuildAppearanceTab(container)
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

    -- Branch for bar mode
    if group.displayMode == "bars" then
        BuildBarAppearanceTab(container, group, style)
        return
    end

    -- Icon Settings header
    local iconHeading = AceGUI:Create("Heading")
    iconHeading:SetText("Icon Settings")
    iconHeading:SetFullWidth(true)
    container:AddChild(iconHeading)

    local squareCb = AceGUI:Create("CheckBox")
    squareCb:SetLabel("Square Icons")
    squareCb:SetValue(style.maintainAspectRatio or false)
    squareCb:SetFullWidth(true)
    -- Disable when Masque is enabled (forces square icons)
    if group.masqueEnabled then
        squareCb:SetDisabled(true)
        -- Add green "Masque skinning is active" label
        local masqueLabel = squareCb.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        masqueLabel:SetPoint("LEFT", squareCb.checkbg, "RIGHT", squareCb.text:GetStringWidth() + 8, 0)
        masqueLabel:SetText("|cff00ff00(Masque skinning is active)|r")
        table.insert(appearanceTabElements, masqueLabel)
    end
    squareCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.maintainAspectRatio = val
        if not val then
            local size = style.buttonSize or ST.BUTTON_SIZE
            style.iconWidth = style.iconWidth or size
            style.iconHeight = style.iconHeight or size
        end
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(squareCb)

    -- Sliders and pickers
    if style.maintainAspectRatio then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Button Size")
        sizeSlider:SetSliderValues(10, 100, 1)
        sizeSlider:SetValue(style.buttonSize or ST.BUTTON_SIZE)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(sizeSlider)
    else
        local wSlider = AceGUI:Create("Slider")
        wSlider:SetLabel("Icon Width")
        wSlider:SetSliderValues(10, 100, 1)
        wSlider:SetValue(style.iconWidth or style.buttonSize or ST.BUTTON_SIZE)
        wSlider:SetFullWidth(true)
        wSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.iconWidth = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(wSlider)

        local hSlider = AceGUI:Create("Slider")
        hSlider:SetLabel("Icon Height")
        hSlider:SetSliderValues(10, 100, 1)
        hSlider:SetValue(style.iconHeight or style.buttonSize or ST.BUTTON_SIZE)
        hSlider:SetFullWidth(true)
        hSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.iconHeight = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(hSlider)
    end

    if group.buttons and #group.buttons > 1 then
        local spacingSlider = AceGUI:Create("Slider")
        spacingSlider:SetLabel("Button Spacing")
        spacingSlider:SetSliderValues(0, 10, 0.1)
        spacingSlider:SetValue(style.buttonSpacing or ST.BUTTON_SPACING)
        spacingSlider:SetFullWidth(true)
        spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.buttonSpacing = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(spacingSlider)
    end

    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(style.borderSize or ST.DEFAULT_BORDER_SIZE)
    borderSlider:SetFullWidth(true)
    -- Disable when Masque is enabled (Masque provides its own border)
    if group.masqueEnabled then
        borderSlider:SetDisabled(true)
    end
    borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
        style.borderSize = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderSlider)

    local borderColor = AceGUI:Create("ColorPicker")
    borderColor:SetLabel("Border Color")
    borderColor:SetHasAlpha(true)
    local bc = style.borderColor or {0, 0, 0, 1}
    borderColor:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColor:SetFullWidth(true)
    -- Disable when Masque is enabled (Masque provides its own border)
    if group.masqueEnabled then
        borderColor:SetDisabled(true)
    end
    borderColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    borderColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.borderColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(borderColor)

    -- Text Settings header
    local textHeading = AceGUI:Create("Heading")
    textHeading:SetText("Text Settings")
    textHeading:SetFullWidth(true)
    container:AddChild(textHeading)

    -- Toggles first
    local cdTextCb = AceGUI:Create("CheckBox")
    cdTextCb:SetLabel("Show Cooldown Text")
    cdTextCb:SetValue(style.showCooldownText or false)
    cdTextCb:SetFullWidth(true)
    cdTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showCooldownText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(cdTextCb)

    -- Font settings only shown when cooldown text is enabled
    if style.showCooldownText then
        local fontSizeSlider = AceGUI:Create("Slider")
        fontSizeSlider:SetLabel("Font Size")
        fontSizeSlider:SetSliderValues(8, 32, 1)
        fontSizeSlider:SetValue(style.cooldownFontSize or 12)
        fontSizeSlider:SetFullWidth(true)
        fontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(fontSizeSlider)

        local fontDrop = AceGUI:Create("Dropdown")
        fontDrop:SetLabel("Font")
        fontDrop:SetList(CS.fontOptions)
        fontDrop:SetValue(style.cooldownFont or "Fonts\\FRIZQT__.TTF")
        fontDrop:SetFullWidth(true)
        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(fontDrop)

        local outlineDrop = AceGUI:Create("Dropdown")
        outlineDrop:SetLabel("Font Outline")
        outlineDrop:SetList(CS.outlineOptions)
        outlineDrop:SetValue(style.cooldownFontOutline or "OUTLINE")
        outlineDrop:SetFullWidth(true)
        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.cooldownFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(outlineDrop)

        local cdFontColor = AceGUI:Create("ColorPicker")
        cdFontColor:SetLabel("Font Color")
        cdFontColor:SetHasAlpha(true)
        local cdc = style.cooldownFontColor or {1, 1, 1, 1}
        cdFontColor:SetColor(cdc[1], cdc[2], cdc[3], cdc[4])
        cdFontColor:SetFullWidth(true)
        cdFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        cdFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.cooldownFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(cdFontColor)
    end

    -- Aura Text section
    local auraTextHeading = AceGUI:Create("Heading")
    auraTextHeading:SetText("Aura Text")
    auraTextHeading:SetFullWidth(true)
    container:AddChild(auraTextHeading)

    local auraTextCb = AceGUI:Create("CheckBox")
    auraTextCb:SetLabel("Show Aura Text")
    auraTextCb:SetValue(style.showAuraText ~= false)
    auraTextCb:SetFullWidth(true)
    auraTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showAuraText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraTextCb)

    if style.showAuraText ~= false then
        local auraFontSizeSlider = AceGUI:Create("Slider")
        auraFontSizeSlider:SetLabel("Font Size")
        auraFontSizeSlider:SetSliderValues(8, 32, 1)
        auraFontSizeSlider:SetValue(style.auraTextFontSize or 12)
        auraFontSizeSlider:SetFullWidth(true)
        auraFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontSizeSlider)

        local auraFontDrop = AceGUI:Create("Dropdown")
        auraFontDrop:SetLabel("Font")
        auraFontDrop:SetList(CS.fontOptions)
        auraFontDrop:SetValue(style.auraTextFont or "Fonts\\FRIZQT__.TTF")
        auraFontDrop:SetFullWidth(true)
        auraFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontDrop)

        local auraOutlineDrop = AceGUI:Create("Dropdown")
        auraOutlineDrop:SetLabel("Font Outline")
        auraOutlineDrop:SetList(CS.outlineOptions)
        auraOutlineDrop:SetValue(style.auraTextFontOutline or "OUTLINE")
        auraOutlineDrop:SetFullWidth(true)
        auraOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.auraTextFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraOutlineDrop)

        local auraFontColor = AceGUI:Create("ColorPicker")
        auraFontColor:SetLabel("Font Color")
        auraFontColor:SetHasAlpha(true)
        local ac = style.auraTextFontColor or {0, 0.925, 1, 1}
        auraFontColor:SetColor(ac[1], ac[2], ac[3], ac[4])
        auraFontColor:SetFullWidth(true)
        auraFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.auraTextFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        auraFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.auraTextFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(auraFontColor)
    end

    -- Keybind Text section
    local kbHeading = AceGUI:Create("Heading")
    kbHeading:SetText("Keybind Text")
    kbHeading:SetFullWidth(true)
    container:AddChild(kbHeading)

    local kbCb = AceGUI:Create("CheckBox")
    kbCb:SetLabel("Show Keybind Text")
    kbCb:SetValue(style.showKeybindText or false)
    kbCb:SetFullWidth(true)
    kbCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showKeybindText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(kbCb)

    if style.showKeybindText then
        local kbAnchorDrop = AceGUI:Create("Dropdown")
        kbAnchorDrop:SetLabel("Anchor")
        kbAnchorDrop:SetList({
            TOPRIGHT = "Top Right",
            TOPLEFT = "Top Left",
            BOTTOMRIGHT = "Bottom Right",
            BOTTOMLEFT = "Bottom Left",
        })
        kbAnchorDrop:SetValue(style.keybindAnchor or "TOPRIGHT")
        kbAnchorDrop:SetFullWidth(true)
        kbAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindAnchor = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbAnchorDrop)

        local kbFontSizeSlider = AceGUI:Create("Slider")
        kbFontSizeSlider:SetLabel("Font Size")
        kbFontSizeSlider:SetSliderValues(6, 24, 1)
        kbFontSizeSlider:SetValue(style.keybindFontSize or 10)
        kbFontSizeSlider:SetFullWidth(true)
        kbFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbFontSizeSlider)

        local kbFontDrop = AceGUI:Create("Dropdown")
        kbFontDrop:SetLabel("Font")
        kbFontDrop:SetList(CS.fontOptions)
        kbFontDrop:SetValue(style.keybindFont or "Fonts\\FRIZQT__.TTF")
        kbFontDrop:SetFullWidth(true)
        kbFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbFontDrop)

        local kbOutlineDrop = AceGUI:Create("Dropdown")
        kbOutlineDrop:SetLabel("Font Outline")
        kbOutlineDrop:SetList(CS.outlineOptions)
        kbOutlineDrop:SetValue(style.keybindFontOutline or "OUTLINE")
        kbOutlineDrop:SetFullWidth(true)
        kbOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.keybindFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbOutlineDrop)

        local kbFontColor = AceGUI:Create("ColorPicker")
        kbFontColor:SetLabel("Font Color")
        kbFontColor:SetHasAlpha(true)
        local kbc = style.keybindFontColor or {1, 1, 1, 1}
        kbFontColor:SetColor(kbc[1], kbc[2], kbc[3], kbc[4])
        kbFontColor:SetFullWidth(true)
        kbFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.keybindFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        kbFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.keybindFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(kbFontColor)
    end
end

------------------------------------------------------------------------
-- PER-BUTTON VISIBILITY SETTINGS
------------------------------------------------------------------------
local function BuildVisibilitySettings(scroll, buttonData, infoButtons)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end

    local isItem = buttonData.type == "item"

    -- Helper: apply a value to all selected buttons if multi-select, else just this one
    local function ApplyToSelected(field, value)
        if CS.selectedButtons then
            local count = 0
            for _ in pairs(CS.selectedButtons) do count = count + 1 end
            if count >= 2 then
                for idx in pairs(CS.selectedButtons) do
                    local bd = group.buttons[idx]
                    if bd then bd[field] = value end
                end
                return
            end
        end
        buttonData[field] = value
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Visibility Rules")
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    -- Hide While On Cooldown
    local hasCooldown = true
    if buttonData.type == "spell" then
        hasCooldown = false
        local tipData = C_TooltipInfo.GetSpellByID(buttonData.id)
        if tipData and tipData.lines then
            for _, line in ipairs(tipData.lines) do
                local left = line.leftText and line.leftText:lower() or ""
                local right = line.rightText and line.rightText:lower() or ""
                if left:find("cooldown") or left:find("recharge")
                    or right:find("cooldown") or right:find("recharge") then
                    hasCooldown = true
                    break
                end
            end
        end
    end
    local hideCDCb = AceGUI:Create("CheckBox")
    hideCDCb:SetLabel("Hide While On Cooldown")
    hideCDCb:SetValue(buttonData.hideWhileOnCooldown or false)
    hideCDCb:SetFullWidth(true)
    if not hasCooldown then
        hideCDCb:SetDisabled(true)
    end
    hideCDCb:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyToSelected("hideWhileOnCooldown", val or nil)
        if val then
            ApplyToSelected("hideWhileNotOnCooldown", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideCDCb)

    -- Hide While Not On Cooldown
    local hideNotCDCb = AceGUI:Create("CheckBox")
    hideNotCDCb:SetLabel("Hide While Not On Cooldown")
    hideNotCDCb:SetValue(buttonData.hideWhileNotOnCooldown or false)
    hideNotCDCb:SetFullWidth(true)
    if not hasCooldown then
        hideNotCDCb:SetDisabled(true)
    end
    hideNotCDCb:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyToSelected("hideWhileNotOnCooldown", val or nil)
        if val then
            ApplyToSelected("hideWhileOnCooldown", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideNotCDCb)

    -- Hide While Aura Active
    local auraDisabled = isItem or not buttonData.auraTracking
    local hideAuraCb = AceGUI:Create("CheckBox")
    hideAuraCb:SetLabel("Hide While Aura Active")
    hideAuraCb:SetValue(buttonData.hideWhileAuraActive or false)
    hideAuraCb:SetFullWidth(true)
    if auraDisabled then
        hideAuraCb:SetDisabled(true)
    end
    hideAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyToSelected("hideWhileAuraActive", val or nil)
        if val then
            ApplyToSelected("hideWhileAuraNotActive", nil)
            ApplyToSelected("useBaselineAlphaFallback", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideAuraCb)

    -- (?) tooltip
    local hideAuraInfo = CreateFrame("Button", nil, hideAuraCb.frame)
    hideAuraInfo:SetSize(16, 16)
    hideAuraInfo:SetPoint("LEFT", hideAuraCb.checkbg, "RIGHT", hideAuraCb.text:GetStringWidth() + 4, 0)
    local hideAuraInfoIcon = hideAuraInfo:CreateTexture(nil, "OVERLAY")
    hideAuraInfoIcon:SetSize(12, 12)
    hideAuraInfoIcon:SetPoint("CENTER")
    hideAuraInfoIcon:SetAtlas("QuestRepeatableTurnin")
    hideAuraInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Hide While Aura Active")
        GameTooltip:AddLine("Requires Aura Tracking to be enabled in the Settings tab.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hideAuraInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(infoButtons, hideAuraInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        hideAuraInfo:Hide()
    end

    -- Baseline Alpha Fallback (only shown when hideWhileAuraActive is checked)
    if buttonData.hideWhileAuraActive then
        local fallbackAuraCb = AceGUI:Create("CheckBox")
        fallbackAuraCb:SetLabel("Use Baseline Alpha Fallback")
        fallbackAuraCb:SetValue(buttonData.useBaselineAlphaFallbackAuraActive or false)
        fallbackAuraCb:SetFullWidth(true)
        fallbackAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
            ApplyToSelected("useBaselineAlphaFallbackAuraActive", val or nil)
        end)
        scroll:AddChild(fallbackAuraCb)

        -- (?) tooltip
        local fallbackAuraInfo = CreateFrame("Button", nil, fallbackAuraCb.frame)
        fallbackAuraInfo:SetSize(16, 16)
        fallbackAuraInfo:SetPoint("LEFT", fallbackAuraCb.checkbg, "RIGHT", fallbackAuraCb.text:GetStringWidth() + 4, 0)
        local fallbackAuraInfoIcon = fallbackAuraInfo:CreateTexture(nil, "OVERLAY")
        fallbackAuraInfoIcon:SetSize(12, 12)
        fallbackAuraInfoIcon:SetPoint("CENTER")
        fallbackAuraInfoIcon:SetAtlas("QuestRepeatableTurnin")
        fallbackAuraInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Use Baseline Alpha Fallback")
            GameTooltip:AddLine("Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        fallbackAuraInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(infoButtons, fallbackAuraInfo)
        if CooldownCompanion.db.profile.hideInfoButtons then
            fallbackAuraInfo:Hide()
        end
    end

    -- Hide While Aura Not Active
    local hideNoAuraCb = AceGUI:Create("CheckBox")
    hideNoAuraCb:SetLabel("Hide While Aura Not Active")
    hideNoAuraCb:SetValue(buttonData.hideWhileAuraNotActive or false)
    hideNoAuraCb:SetFullWidth(true)
    if auraDisabled then
        hideNoAuraCb:SetDisabled(true)
    end
    hideNoAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyToSelected("hideWhileAuraNotActive", val or nil)
        if val then
            ApplyToSelected("hideWhileAuraActive", nil)
            ApplyToSelected("useBaselineAlphaFallbackAuraActive", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideNoAuraCb)

    -- (?) tooltip
    local hideNoAuraInfo = CreateFrame("Button", nil, hideNoAuraCb.frame)
    hideNoAuraInfo:SetSize(16, 16)
    hideNoAuraInfo:SetPoint("LEFT", hideNoAuraCb.checkbg, "RIGHT", hideNoAuraCb.text:GetStringWidth() + 4, 0)
    local hideNoAuraInfoIcon = hideNoAuraInfo:CreateTexture(nil, "OVERLAY")
    hideNoAuraInfoIcon:SetSize(12, 12)
    hideNoAuraInfoIcon:SetPoint("CENTER")
    hideNoAuraInfoIcon:SetAtlas("QuestRepeatableTurnin")
    hideNoAuraInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Hide While Aura Not Active")
        GameTooltip:AddLine("Requires Aura Tracking to be enabled in the Settings tab.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hideNoAuraInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(infoButtons, hideNoAuraInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        hideNoAuraInfo:Hide()
    end

    -- Baseline Alpha Fallback (only shown when hideWhileAuraNotActive is checked)
    if buttonData.hideWhileAuraNotActive then
        local fallbackCb = AceGUI:Create("CheckBox")
        fallbackCb:SetLabel("Use Baseline Alpha Fallback")
        fallbackCb:SetValue(buttonData.useBaselineAlphaFallback or false)
        fallbackCb:SetFullWidth(true)
        fallbackCb:SetCallback("OnValueChanged", function(widget, event, val)
            ApplyToSelected("useBaselineAlphaFallback", val or nil)
        end)
        scroll:AddChild(fallbackCb)

        -- (?) tooltip
        local fallbackInfo = CreateFrame("Button", nil, fallbackCb.frame)
        fallbackInfo:SetSize(16, 16)
        fallbackInfo:SetPoint("LEFT", fallbackCb.checkbg, "RIGHT", fallbackCb.text:GetStringWidth() + 4, 0)
        local fallbackInfoIcon = fallbackInfo:CreateTexture(nil, "OVERLAY")
        fallbackInfoIcon:SetSize(12, 12)
        fallbackInfoIcon:SetPoint("CENTER")
        fallbackInfoIcon:SetAtlas("QuestRepeatableTurnin")
        fallbackInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Use Baseline Alpha Fallback")
            GameTooltip:AddLine("Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        fallbackInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(infoButtons, fallbackInfo)
        if CooldownCompanion.db.profile.hideInfoButtons then
            fallbackInfo:Hide()
        end
    end

    -- Warning: aura-based toggles enabled but auraTracking is off
    if not isItem
       and (buttonData.hideWhileAuraNotActive or buttonData.hideWhileAuraActive)
       and not buttonData.auraTracking then
        local warnSpacer = AceGUI:Create("Label")
        warnSpacer:SetText(" ")
        warnSpacer:SetFullWidth(true)
        scroll:AddChild(warnSpacer)

        local warnLabel = AceGUI:Create("Label")
        warnLabel:SetText("|cffff8800Warning: Aura Tracking is not enabled in the Settings tab. Aura-based visibility will have no effect.|r")
        warnLabel:SetFullWidth(true)
        scroll:AddChild(warnLabel)
    end

end

------------------------------------------------------------------------
-- LOAD CONDITIONS TAB
------------------------------------------------------------------------

local function BuildLoadConditionsTab(container)
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

    if not CS.selectedGroup then return end
    local groupId = CS.selectedGroup
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end

    -- Ensure loadConditions table exists
    if not group.loadConditions then
        group.loadConditions = {
            raid = false, dungeon = false, delve = false, battleground = false,
            arena = false, openWorld = false, rested = false,
        }
    end
    local lc = group.loadConditions

    local function CreateLoadConditionToggle(label, key)
        local cb = AceGUI:Create("CheckBox")
        cb:SetLabel(label)
        cb:SetValue(lc[key] or false)
        cb:SetFullWidth(true)
        cb:SetCallback("OnValueChanged", function(widget, event, val)
            lc[key] = val
            CooldownCompanion:RefreshGroupFrame(groupId)
        end)
        return cb
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText("Do Not Load When In")
    heading:SetFullWidth(true)
    container:AddChild(heading)

    local conditions = {
        { key = "raid",          label = "Raid" },
        { key = "dungeon",       label = "Dungeon" },
        { key = "delve",         label = "Delve" },
        { key = "battleground",  label = "Battleground" },
        { key = "arena",         label = "Arena" },
        { key = "openWorld",     label = "Open World" },
        { key = "rested",        label = "Rested Area" },
    }

    for _, cond in ipairs(conditions) do
        container:AddChild(CreateLoadConditionToggle(cond.label, cond.key))
    end

    -- Specialization heading
    local specHeading = AceGUI:Create("Heading")
    specHeading:SetText("Specialization Filter")
    specHeading:SetFullWidth(true)
    container:AddChild(specHeading)

    local specDesc = AceGUI:Create("Label")
    specDesc:SetText("When any spec is checked, the group only shows for those specs. Unchecking all removes the filter (always show).")
    specDesc:SetFullWidth(true)
    container:AddChild(specDesc)

    local spacer2 = AceGUI:Create("Label")
    spacer2:SetText(" ")
    spacer2:SetFullWidth(true)
    container:AddChild(spacer2)

    -- Current class spec checkboxes
    local numSpecs = GetNumSpecializations()
    for i = 1, numSpecs do
        local specId, name, _, icon = C_SpecializationInfo.GetSpecializationInfo(i)
        if specId then
            local cb = AceGUI:Create("CheckBox")
            cb:SetLabel(name)
            if icon then cb:SetImage(icon, 0.08, 0.92, 0.08, 0.92) end
            cb:SetFullWidth(true)
            cb:SetValue(group.specs and group.specs[specId] or false)
            cb:SetCallback("OnValueChanged", function(widget, event, value)
                if value then
                    if not group.specs then group.specs = {} end
                    group.specs[specId] = true
                else
                    if group.specs then
                        group.specs[specId] = nil
                        if not next(group.specs) then
                            group.specs = nil
                        end
                    end
                end
                CooldownCompanion:RefreshGroupFrame(groupId)
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(cb)
        end
    end

    -- Foreign specs (from global groups that may have specs from other classes)
    local playerSpecIds = {}
    for i = 1, numSpecs do
        local specId = C_SpecializationInfo.GetSpecializationInfo(i)
        if specId then playerSpecIds[specId] = true end
    end

    local foreignSpecs = {}
    if group.specs then
        for specId in pairs(group.specs) do
            if not playerSpecIds[specId] then
                table.insert(foreignSpecs, specId)
            end
        end
    end

    if #foreignSpecs > 0 then
        table.sort(foreignSpecs)
        for _, specId in ipairs(foreignSpecs) do
            local _, name, _, icon = GetSpecializationInfoForSpecID(specId)
            if name then
                local fcb = AceGUI:Create("CheckBox")
                fcb:SetLabel(name)
                if icon then fcb:SetImage(icon, 0.08, 0.92, 0.08, 0.92) end
                fcb:SetFullWidth(true)
                fcb:SetValue(true)
                fcb:SetCallback("OnValueChanged", function(widget, event, value)
                    if not value then
                        if group.specs then
                            group.specs[specId] = nil
                            if not next(group.specs) then
                                group.specs = nil
                            end
                        end
                    else
                        if not group.specs then group.specs = {} end
                        group.specs[specId] = true
                    end
                    CooldownCompanion:RefreshGroupFrame(groupId)
                    CooldownCompanion:RefreshConfigPanel()
                end)
                container:AddChild(fcb)
            end
        end
    end
end

------------------------------------------------------------------------
-- CAST BAR SETTINGS PANEL
------------------------------------------------------------------------

-- Collapsible section state for cast bar panel (persistent across rebuilds)
local castBarCollapsedSections = {}

local barTextureOptions = {
    ["Interface\\TargetingFrame\\UI-StatusBar"]          = "Blizzard (Default)",
    ["Interface\\BUTTONS\\WHITE8X8"]                     = "Flat",
    ["Interface\\RaidFrame\\Raid-Bar-Hp-Fill"]           = "Raid",
    ["Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"] = "Skills Bar",
}

BuildCastBarAnchoringPanel = function(container)
    local db = CooldownCompanion.db.profile
    local settings = db.castBar

    -- Enable Anchoring
    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel("Enable Cast Bar Anchoring")
    enableCb:SetValue(settings.enabled)
    enableCb:SetFullWidth(true)
    enableCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.enabled = val
        CooldownCompanion:EvaluateCastBar()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(enableCb)

    if not settings.enabled then return end

    -- Anchor Group dropdown
    local groupDropValues = { [""] = "Auto (first available)" }
    local groupDropOrder = { "" }
    for groupId, group in pairs(db.groups) do
        if CooldownCompanion:IsGroupAvailableForAnchoring(groupId) then
            groupDropValues[tostring(groupId)] = group.name or ("Group " .. groupId)
            table.insert(groupDropOrder, tostring(groupId))
        end
    end

    local anchorDrop = AceGUI:Create("Dropdown")
    anchorDrop:SetLabel("Anchor to Group")
    anchorDrop:SetList(groupDropValues, groupDropOrder)
    anchorDrop:SetValue(settings.anchorGroupId and tostring(settings.anchorGroupId) or "")
    anchorDrop:SetFullWidth(true)
    anchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.anchorGroupId = val ~= "" and tonumber(val) or nil
        CooldownCompanion:EvaluateCastBar()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(anchorDrop)

    if #groupDropOrder <= 1 then
        local noGroupsLabel = AceGUI:Create("Label")
        noGroupsLabel:SetText("No icon groups are currently enabled for this spec. Enable an icon group to anchor here.")
        noGroupsLabel:SetFullWidth(true)
        container:AddChild(noGroupsLabel)
    end

    -- Preview toggle (ephemeral — not saved to DB)
    local previewCb = AceGUI:Create("CheckBox")
    previewCb:SetLabel("Preview Cast Bar")
    previewCb:SetValue(CooldownCompanion:IsCastBarPreviewActive())
    previewCb:SetFullWidth(true)
    previewCb:SetCallback("OnValueChanged", function(widget, event, val)
        if val then
            CooldownCompanion:StartCastBarPreview()
        else
            CooldownCompanion:StopCastBarPreview()
        end
    end)
    container:AddChild(previewCb)

    -- ============ Position Section ============
    local posHeading = AceGUI:Create("Heading")
    posHeading:SetText("Position")
    posHeading:SetFullWidth(true)
    container:AddChild(posHeading)

    local posKey = "castbar_position"
    local posCollapsed = castBarCollapsedSections[posKey]

    local posCollapseBtn = CreateFrame("Button", nil, posHeading.frame)
    posCollapseBtn:SetSize(16, 16)
    posCollapseBtn:SetPoint("LEFT", posHeading.label, "RIGHT", 4, 0)
    posHeading.right:SetPoint("LEFT", posCollapseBtn, "RIGHT", 4, 0)
    local posArrow = posCollapseBtn:CreateTexture(nil, "ARTWORK")
    posArrow:SetSize(12, 12)
    posArrow:SetPoint("CENTER")
    posArrow:SetAtlas(posCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    posCollapseBtn:SetScript("OnClick", function()
        castBarCollapsedSections[posKey] = not castBarCollapsedSections[posKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not posCollapsed then
        -- Above/Below
        local posDrop = AceGUI:Create("Dropdown")
        posDrop:SetLabel("Position")
        posDrop:SetList({ below = "Below Group", above = "Above Group" }, { "below", "above" })
        posDrop:SetValue(settings.position or "below")
        posDrop:SetFullWidth(true)
        posDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.position = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(posDrop)

        -- Y Offset
        local ySlider = AceGUI:Create("Slider")
        ySlider:SetLabel("Y Offset")
        ySlider:SetSliderValues(-50, 50, 1)
        ySlider:SetValue(settings.yOffset or -2)
        ySlider:SetFullWidth(true)
        ySlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.yOffset = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(ySlider)

    end

    -- ============ Cast Effects Section ============
    local fxHeading = AceGUI:Create("Heading")
    fxHeading:SetText("Cast Effects")
    fxHeading:SetFullWidth(true)
    container:AddChild(fxHeading)

    local fxKey = "castbar_fx"
    local fxCollapsed = castBarCollapsedSections[fxKey]

    local fxCollapseBtn = CreateFrame("Button", nil, fxHeading.frame)
    fxCollapseBtn:SetSize(16, 16)
    fxCollapseBtn:SetPoint("LEFT", fxHeading.label, "RIGHT", 4, 0)
    fxHeading.right:SetPoint("LEFT", fxCollapseBtn, "RIGHT", 4, 0)
    local fxArrow = fxCollapseBtn:CreateTexture(nil, "ARTWORK")
    fxArrow:SetSize(12, 12)
    fxArrow:SetPoint("CENTER")
    fxArrow:SetAtlas(fxCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    fxCollapseBtn:SetScript("OnClick", function()
        castBarCollapsedSections[fxKey] = not castBarCollapsedSections[fxKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not fxCollapsed then
        local sparkTrailCb = AceGUI:Create("CheckBox")
        sparkTrailCb:SetLabel("Show Spark Trail")
        sparkTrailCb:SetValue(settings.showSparkTrail ~= false)
        sparkTrailCb:SetFullWidth(true)
        sparkTrailCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.showSparkTrail = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(sparkTrailCb)

        local intShakeCb = AceGUI:Create("CheckBox")
        intShakeCb:SetLabel("Show Interrupt Shake")
        intShakeCb:SetValue(settings.showInterruptShake ~= false)
        intShakeCb:SetFullWidth(true)
        intShakeCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.showInterruptShake = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(intShakeCb)

        local intGlowCb = AceGUI:Create("CheckBox")
        intGlowCb:SetLabel("Show Interrupt Glow")
        intGlowCb:SetValue(settings.showInterruptGlow ~= false)
        intGlowCb:SetFullWidth(true)
        intGlowCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.showInterruptGlow = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(intGlowCb)

        local castFinishCb = AceGUI:Create("CheckBox")
        castFinishCb:SetLabel("Show Cast Finish FX")
        castFinishCb:SetValue(settings.showCastFinishFX ~= false)
        castFinishCb:SetFullWidth(true)
        castFinishCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.showCastFinishFX = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(castFinishCb)

    end
end

local function BuildCastBarStylingPanel(container)
    local db = CooldownCompanion.db.profile
    local settings = db.castBar

    -- Enable Styling checkbox — always visible, but grayed out when anchoring is off
    local styleCb = AceGUI:Create("CheckBox")
    styleCb:SetLabel("Enable Cast Bar Styling")
    styleCb:SetValue(settings.stylingEnabled or false)
    styleCb:SetFullWidth(true)
    styleCb:SetDisabled(not settings.enabled)
    styleCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.stylingEnabled = val
        CooldownCompanion:ApplyCastBarSettings()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(styleCb)

    if not settings.enabled then return end
    if not settings.stylingEnabled then return end

    -- Height (styling-only — anchoring uses Blizzard default height)
    local hSlider = AceGUI:Create("Slider")
    hSlider:SetLabel("Height")
    hSlider:SetSliderValues(4, 40, 0.1)
    hSlider:SetValue(settings.height or 14)
    hSlider:SetFullWidth(true)
    hSlider:SetCallback("OnValueChanged", function(widget, event, val)
        settings.height = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(hSlider)

    -- ============ Bar Visuals Section ============
    local visHeading = AceGUI:Create("Heading")
    visHeading:SetText("Bar Visuals")
    visHeading:SetFullWidth(true)
    container:AddChild(visHeading)

    local visKey = "castbar_visuals"
    local visCollapsed = castBarCollapsedSections[visKey]

    local visCollapseBtn = CreateFrame("Button", nil, visHeading.frame)
    visCollapseBtn:SetSize(16, 16)
    visCollapseBtn:SetPoint("LEFT", visHeading.label, "RIGHT", 4, 0)
    visHeading.right:SetPoint("LEFT", visCollapseBtn, "RIGHT", 4, 0)
    local visArrow = visCollapseBtn:CreateTexture(nil, "ARTWORK")
    visArrow:SetSize(12, 12)
    visArrow:SetPoint("CENTER")
    visArrow:SetAtlas(visCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    visCollapseBtn:SetScript("OnClick", function()
        castBarCollapsedSections[visKey] = not castBarCollapsedSections[visKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not visCollapsed then
        -- Bar Color
        local barColorPicker = AceGUI:Create("ColorPicker")
        barColorPicker:SetLabel("Bar Color")
        local bcc = settings.barColor or { 1.0, 0.7, 0.0, 1.0 }
        barColorPicker:SetColor(bcc[1], bcc[2], bcc[3], bcc[4])
        barColorPicker:SetHasAlpha(true)
        barColorPicker:SetFullWidth(true)
        barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            settings.barColor = {r, g, b, a}
        end)
        barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            settings.barColor = {r, g, b, a}
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(barColorPicker)

        -- Bar Texture
        local texDrop = AceGUI:Create("Dropdown")
        texDrop:SetLabel("Bar Texture")
        texDrop:SetList(barTextureOptions)
        texDrop:SetValue(settings.barTexture or "Interface\\BUTTONS\\WHITE8X8")
        texDrop:SetFullWidth(true)
        texDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.barTexture = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(texDrop)

        -- Background Color
        local bgColorPicker = AceGUI:Create("ColorPicker")
        bgColorPicker:SetLabel("Background Color")
        local bgc = settings.backgroundColor or { 0, 0, 0, 0.5 }
        bgColorPicker:SetColor(bgc[1], bgc[2], bgc[3], bgc[4])
        bgColorPicker:SetHasAlpha(true)
        bgColorPicker:SetFullWidth(true)
        bgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            settings.backgroundColor = {r, g, b, a}
        end)
        bgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            settings.backgroundColor = {r, g, b, a}
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(bgColorPicker)

        -- Show Spell Icon
        local iconCb = AceGUI:Create("CheckBox")
        iconCb:SetLabel("Show Spell Icon")
        iconCb:SetValue(settings.showIcon or false)
        iconCb:SetFullWidth(true)
        iconCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.showIcon = val
            CooldownCompanion:ApplyCastBarSettings()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(iconCb)

        if settings.showIcon then
            -- Icon on Right Side
            local iconFlipCb = AceGUI:Create("CheckBox")
            iconFlipCb:SetLabel("Icon on Right Side")
            iconFlipCb:SetValue(settings.iconFlipSide or false)
            iconFlipCb:SetFullWidth(true)
            iconFlipCb:SetCallback("OnValueChanged", function(widget, event, val)
                settings.iconFlipSide = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(iconFlipCb)

            -- Icon Offset toggle
            local iconOffsetCb = AceGUI:Create("CheckBox")
            iconOffsetCb:SetLabel("Icon Offset")
            iconOffsetCb:SetValue(settings.iconOffset or false)
            iconOffsetCb:SetFullWidth(true)
            iconOffsetCb:SetCallback("OnValueChanged", function(widget, event, val)
                settings.iconOffset = val
                CooldownCompanion:ApplyCastBarSettings()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(iconOffsetCb)

            if settings.iconOffset then
                -- Icon Size slider (offset mode only)
                local iconSizeSlider = AceGUI:Create("Slider")
                iconSizeSlider:SetLabel("Icon Size")
                iconSizeSlider:SetSliderValues(8, 64, 0.1)
                iconSizeSlider:SetValue(settings.iconSize or 16)
                iconSizeSlider:SetFullWidth(true)
                iconSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.iconSize = val
                    CooldownCompanion:ApplyCastBarSettings()
                end)
                container:AddChild(iconSizeSlider)

                -- Icon X Offset slider
                local iconXSlider = AceGUI:Create("Slider")
                iconXSlider:SetLabel("Icon X Offset")
                iconXSlider:SetSliderValues(-50, 50, 0.1)
                iconXSlider:SetValue(settings.iconOffsetX or 0)
                iconXSlider:SetFullWidth(true)
                iconXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.iconOffsetX = val
                    CooldownCompanion:ApplyCastBarSettings()
                end)
                container:AddChild(iconXSlider)

                -- Icon Y Offset slider
                local iconYSlider = AceGUI:Create("Slider")
                iconYSlider:SetLabel("Icon Y Offset")
                iconYSlider:SetSliderValues(-50, 50, 0.1)
                iconYSlider:SetValue(settings.iconOffsetY or 0)
                iconYSlider:SetFullWidth(true)
                iconYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.iconOffsetY = val
                    CooldownCompanion:ApplyCastBarSettings()
                end)
                container:AddChild(iconYSlider)

                -- Icon Border Size slider (offset mode only)
                local iconBorderSlider = AceGUI:Create("Slider")
                iconBorderSlider:SetLabel("Icon Border Size")
                iconBorderSlider:SetSliderValues(0, 4, 0.1)
                iconBorderSlider:SetValue(settings.iconBorderSize or 1)
                iconBorderSlider:SetFullWidth(true)
                iconBorderSlider:SetCallback("OnValueChanged", function(widget, event, val)
                    settings.iconBorderSize = val
                    CooldownCompanion:ApplyCastBarSettings()
                end)
                container:AddChild(iconBorderSlider)
            end
        end

        -- Show Spark
        local sparkCb = AceGUI:Create("CheckBox")
        sparkCb:SetLabel("Show Spark")
        sparkCb:SetValue(settings.showSpark ~= false)
        sparkCb:SetFullWidth(true)
        sparkCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.showSpark = val
            CooldownCompanion:ApplyCastBarSettings()
        end)
        container:AddChild(sparkCb)

        -- Border Style
        local borderDrop = AceGUI:Create("Dropdown")
        borderDrop:SetLabel("Border Style")
        borderDrop:SetList({
            blizzard = "Blizzard",
            pixel = "Pixel",
            none = "None",
        }, { "blizzard", "pixel", "none" })
        borderDrop:SetValue(settings.borderStyle or "blizzard")
        borderDrop:SetFullWidth(true)
        borderDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.borderStyle = val
            CooldownCompanion:ApplyCastBarSettings()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(borderDrop)

        -- Border Color and Size (only when pixel)
        if settings.borderStyle == "pixel" then
            local borderColorPicker = AceGUI:Create("ColorPicker")
            borderColorPicker:SetLabel("Border Color")
            local brc = settings.borderColor or { 0, 0, 0, 1 }
            borderColorPicker:SetColor(brc[1], brc[2], brc[3], brc[4])
            borderColorPicker:SetHasAlpha(true)
            borderColorPicker:SetFullWidth(true)
            borderColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                settings.borderColor = {r, g, b, a}
            end)
            borderColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                settings.borderColor = {r, g, b, a}
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(borderColorPicker)

            local borderSizeSlider = AceGUI:Create("Slider")
            borderSizeSlider:SetLabel("Border Size")
            borderSizeSlider:SetSliderValues(0, 5, 0.1)
            borderSizeSlider:SetValue(settings.borderSize or 1)
            borderSizeSlider:SetFullWidth(true)
            borderSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.borderSize = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(borderSizeSlider)
        end
    end

    -- ============ Spell Name Text Section ============
    local nameHeading = AceGUI:Create("Heading")
    nameHeading:SetText("Spell Name Text")
    nameHeading:SetFullWidth(true)
    container:AddChild(nameHeading)

    local nameKey = "castbar_nametext"
    local nameCollapsed = castBarCollapsedSections[nameKey]

    local nameCollapseBtn = CreateFrame("Button", nil, nameHeading.frame)
    nameCollapseBtn:SetSize(16, 16)
    nameCollapseBtn:SetPoint("LEFT", nameHeading.label, "RIGHT", 4, 0)
    nameHeading.right:SetPoint("LEFT", nameCollapseBtn, "RIGHT", 4, 0)
    local nameArrow = nameCollapseBtn:CreateTexture(nil, "ARTWORK")
    nameArrow:SetSize(12, 12)
    nameArrow:SetPoint("CENTER")
    nameArrow:SetAtlas(nameCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    nameCollapseBtn:SetScript("OnClick", function()
        castBarCollapsedSections[nameKey] = not castBarCollapsedSections[nameKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not nameCollapsed then
        -- Show
        local nameCb = AceGUI:Create("CheckBox")
        nameCb:SetLabel("Show Spell Name")
        nameCb:SetValue(settings.showNameText ~= false)
        nameCb:SetFullWidth(true)
        nameCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.showNameText = val
            CooldownCompanion:ApplyCastBarSettings()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(nameCb)

        if settings.showNameText ~= false then
            -- Font
            local nameFontDrop = AceGUI:Create("Dropdown")
            nameFontDrop:SetLabel("Font")
            nameFontDrop:SetList(CS.fontOptions)
            nameFontDrop:SetValue(settings.nameFont or "Fonts\\FRIZQT__.TTF")
            nameFontDrop:SetFullWidth(true)
            nameFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                settings.nameFont = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(nameFontDrop)

            -- Size
            local nameSizeSlider = AceGUI:Create("Slider")
            nameSizeSlider:SetLabel("Font Size")
            nameSizeSlider:SetSliderValues(6, 24, 0.1)
            nameSizeSlider:SetValue(settings.nameFontSize or 10)
            nameSizeSlider:SetFullWidth(true)
            nameSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.nameFontSize = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(nameSizeSlider)

            -- Outline
            local nameOutlineDrop = AceGUI:Create("Dropdown")
            nameOutlineDrop:SetLabel("Outline")
            nameOutlineDrop:SetList(CS.outlineOptions)
            nameOutlineDrop:SetValue(settings.nameFontOutline or "OUTLINE")
            nameOutlineDrop:SetFullWidth(true)
            nameOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                settings.nameFontOutline = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(nameOutlineDrop)

            -- Color
            local nameColorPicker = AceGUI:Create("ColorPicker")
            nameColorPicker:SetLabel("Font Color")
            local nc = settings.nameFontColor or { 1, 1, 1, 1 }
            nameColorPicker:SetColor(nc[1], nc[2], nc[3], nc[4])
            nameColorPicker:SetHasAlpha(true)
            nameColorPicker:SetFullWidth(true)
            nameColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                settings.nameFontColor = {r, g, b, a}
            end)
            nameColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                settings.nameFontColor = {r, g, b, a}
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(nameColorPicker)
        end
    end

    -- ============ Cast Time Text Section ============
    local ctHeading = AceGUI:Create("Heading")
    ctHeading:SetText("Cast Time Text")
    ctHeading:SetFullWidth(true)
    container:AddChild(ctHeading)

    local ctKey = "castbar_casttime"
    local ctCollapsed = castBarCollapsedSections[ctKey]

    local ctCollapseBtn = CreateFrame("Button", nil, ctHeading.frame)
    ctCollapseBtn:SetSize(16, 16)
    ctCollapseBtn:SetPoint("LEFT", ctHeading.label, "RIGHT", 4, 0)
    ctHeading.right:SetPoint("LEFT", ctCollapseBtn, "RIGHT", 4, 0)
    local ctArrow = ctCollapseBtn:CreateTexture(nil, "ARTWORK")
    ctArrow:SetSize(12, 12)
    ctArrow:SetPoint("CENTER")
    ctArrow:SetAtlas(ctCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    ctCollapseBtn:SetScript("OnClick", function()
        castBarCollapsedSections[ctKey] = not castBarCollapsedSections[ctKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not ctCollapsed then
        -- Show
        local ctCb = AceGUI:Create("CheckBox")
        ctCb:SetLabel("Show Cast Time")
        ctCb:SetValue(settings.showCastTimeText ~= false)
        ctCb:SetFullWidth(true)
        ctCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.showCastTimeText = val
            CooldownCompanion:ApplyCastBarSettings()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(ctCb)

        if settings.showCastTimeText ~= false then
            -- Font
            local ctFontDrop = AceGUI:Create("Dropdown")
            ctFontDrop:SetLabel("Font")
            ctFontDrop:SetList(CS.fontOptions)
            ctFontDrop:SetValue(settings.castTimeFont or "Fonts\\FRIZQT__.TTF")
            ctFontDrop:SetFullWidth(true)
            ctFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
                settings.castTimeFont = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(ctFontDrop)

            -- Size
            local ctSizeSlider = AceGUI:Create("Slider")
            ctSizeSlider:SetLabel("Font Size")
            ctSizeSlider:SetSliderValues(6, 24, 0.1)
            ctSizeSlider:SetValue(settings.castTimeFontSize or 10)
            ctSizeSlider:SetFullWidth(true)
            ctSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.castTimeFontSize = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(ctSizeSlider)

            -- Outline
            local ctOutlineDrop = AceGUI:Create("Dropdown")
            ctOutlineDrop:SetLabel("Outline")
            ctOutlineDrop:SetList(CS.outlineOptions)
            ctOutlineDrop:SetValue(settings.castTimeFontOutline or "OUTLINE")
            ctOutlineDrop:SetFullWidth(true)
            ctOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
                settings.castTimeFontOutline = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(ctOutlineDrop)

            -- Color
            local ctColorPicker = AceGUI:Create("ColorPicker")
            ctColorPicker:SetLabel("Font Color")
            local ctc = settings.castTimeFontColor or { 1, 1, 1, 1 }
            ctColorPicker:SetColor(ctc[1], ctc[2], ctc[3], ctc[4])
            ctColorPicker:SetHasAlpha(true)
            ctColorPicker:SetFullWidth(true)
            ctColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                settings.castTimeFontColor = {r, g, b, a}
            end)
            ctColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                settings.castTimeFontColor = {r, g, b, a}
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(ctColorPicker)

            -- X Offset
            local ctXSlider = AceGUI:Create("Slider")
            ctXSlider:SetLabel("X Offset")
            ctXSlider:SetSliderValues(-50, 50, 0.1)
            ctXSlider:SetValue(settings.castTimeXOffset or 0)
            ctXSlider:SetFullWidth(true)
            ctXSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.castTimeXOffset = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(ctXSlider)

            -- Y Offset
            local ctYSlider = AceGUI:Create("Slider")
            ctYSlider:SetLabel("Y Offset")
            ctYSlider:SetSliderValues(-20, 20, 0.1)
            ctYSlider:SetValue(settings.castTimeYOffset or 0)
            ctYSlider:SetFullWidth(true)
            ctYSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.castTimeYOffset = val
                CooldownCompanion:ApplyCastBarSettings()
            end)
            container:AddChild(ctYSlider)
        end
    end
end

------------------------------------------------------------------------
-- RESOURCE BAR: Anchoring Panel
------------------------------------------------------------------------

local resourceBarCollapsedSections = {}

-- Power names + segmented check for config UI (mirrors ResourceBar.lua constants)
local POWER_NAMES_CONFIG = {
    [0]  = "Mana",
    [1]  = "Rage",
    [2]  = "Focus",
    [3]  = "Energy",
    [4]  = "Combo Points",
    [5]  = "Runes",
    [6]  = "Runic Power",
    [7]  = "Soul Shards",
    [8]  = "Lunar Power",
    [9]  = "Holy Power",
    [11] = "Maelstrom",
    [12] = "Chi",
    [13] = "Insanity",
    [16] = "Arcane Charges",
    [17] = "Fury",
    [18] = "Pain",
    [19] = "Essence",
}

local SEGMENTED_TYPES_CONFIG = {
    [4]  = true, [5]  = true, [7]  = true, [9]  = true,
    [12] = true, [16] = true, [19] = true,
}

local DEFAULT_POWER_COLORS_CONFIG = {
    [0]  = { 0, 0, 1 },
    [1]  = { 1, 0, 0 },
    [2]  = { 1, 0.5, 0.25 },
    [3]  = { 1, 1, 0 },
    [4]  = { 1, 0.96, 0.41 },
    [5]  = { 0.5, 0.5, 0.5 },
    [6]  = { 0, 0.82, 1 },
    [7]  = { 0.5, 0.32, 0.55 },
    [8]  = { 0.3, 0.52, 0.9 },
    [9]  = { 0.95, 0.9, 0.6 },
    [11] = { 0, 0.5, 1 },
    [12] = { 0.71, 1, 0.92 },
    [13] = { 0.4, 0, 0.8 },
    [16] = { 0.1, 0.1, 0.98 },
    [17] = { 0.788, 0.259, 0.992 },
    [18] = { 1, 0.612, 0 },
    [19] = { 0.286, 0.773, 0.541 },
}

local DEFAULT_COMBO_COLOR_CONFIG = { 1, 0.96, 0.41 }
local DEFAULT_COMBO_MAX_COLOR_CONFIG = { 1, 0.96, 0.41 }

local DEFAULT_RUNE_READY_COLOR_CONFIG = { 0.8, 0.8, 0.8 }
local DEFAULT_RUNE_RECHARGING_COLOR_CONFIG = { 0.490, 0.490, 0.490 }
local DEFAULT_RUNE_MAX_COLOR_CONFIG = { 0.8, 0.8, 0.8 }

local DEFAULT_SHARD_READY_COLOR_CONFIG = { 0.5, 0.32, 0.55 }
local DEFAULT_SHARD_RECHARGING_COLOR_CONFIG = { 0.490, 0.490, 0.490 }
local DEFAULT_SHARD_MAX_COLOR_CONFIG = { 0.5, 0.32, 0.55 }

local DEFAULT_HOLY_COLOR_CONFIG = { 0.95, 0.9, 0.6 }
local DEFAULT_HOLY_MAX_COLOR_CONFIG = { 0.95, 0.9, 0.6 }

local DEFAULT_CHI_COLOR_CONFIG = { 0.71, 1, 0.92 }
local DEFAULT_CHI_MAX_COLOR_CONFIG = { 0.71, 1, 0.92 }

local DEFAULT_ARCANE_COLOR_CONFIG = { 0.1, 0.1, 0.98 }
local DEFAULT_ARCANE_MAX_COLOR_CONFIG = { 0.1, 0.1, 0.98 }

local DEFAULT_ESSENCE_READY_COLOR_CONFIG = { 0.851, 0.482, 0.780 }
local DEFAULT_ESSENCE_RECHARGING_COLOR_CONFIG = { 0.490, 0.490, 0.490 }
local DEFAULT_ESSENCE_MAX_COLOR_CONFIG = { 0.851, 0.482, 0.780 }

-- Class-to-resource mapping for config UI
local CLASS_RESOURCES_CONFIG = {
    [1]  = { 1 },
    [2]  = { 9, 0 },
    [3]  = { 2 },
    [4]  = { 4, 3 },
    [5]  = { 0 },
    [6]  = { 5, 6 },
    [7]  = { 0 },
    [8]  = { 0 },
    [9]  = { 7, 0 },
    [10] = { 0 },
    [11] = { 1, 4, 3, 8, 0 },  -- All possible druid resources
    [12] = { 17 },
    [13] = { 19, 0 },
}

local SPEC_RESOURCES_CONFIG = {
    [258] = { 13, 0 },
    [262] = { 11, 0 },
    [263] = { 11, 0 },
    [62]  = { 16, 0 },
    [269] = { 12, 3 },
    [268] = { 3 },
    [581] = { 18 },
}

local function GetConfigActiveResources()
    local _, _, classID = UnitClass("player")
    if not classID then return {} end

    local specIdx = C_SpecializationInfo.GetSpecialization()
    local specID
    if specIdx then
        specID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
    end

    -- For Druid, show all possible resources (user can toggle each)
    if classID == 11 then
        return CLASS_RESOURCES_CONFIG[11]
    end

    if specID and SPEC_RESOURCES_CONFIG[specID] then
        return SPEC_RESOURCES_CONFIG[specID]
    end

    return CLASS_RESOURCES_CONFIG[classID] or {}
end

BuildResourceBarAnchoringPanel = function(container)
    local db = CooldownCompanion.db.profile
    local settings = db.resourceBars

    -- Enable Resource Bars
    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel("Enable Resource Bars")
    enableCb:SetValue(settings.enabled)
    enableCb:SetFullWidth(true)
    enableCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.enabled = val
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(enableCb)

    if not settings.enabled then return end

    -- Anchor Group dropdown
    local groupDropValues = { [""] = "Auto (first available)" }
    local groupDropOrder = { "" }
    for groupId, group in pairs(db.groups) do
        if CooldownCompanion:IsGroupAvailableForAnchoring(groupId) then
            groupDropValues[tostring(groupId)] = group.name or ("Group " .. groupId)
            table.insert(groupDropOrder, tostring(groupId))
        end
    end

    local anchorDrop = AceGUI:Create("Dropdown")
    anchorDrop:SetLabel("Anchor to Group")
    anchorDrop:SetList(groupDropValues, groupDropOrder)
    anchorDrop:SetValue(settings.anchorGroupId and tostring(settings.anchorGroupId) or "")
    anchorDrop:SetFullWidth(true)
    anchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.anchorGroupId = val ~= "" and tonumber(val) or nil
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(anchorDrop)

    if #groupDropOrder <= 1 then
        local noGroupsLabel = AceGUI:Create("Label")
        noGroupsLabel:SetText("No icon groups are currently enabled for this spec. Enable an icon group to anchor here.")
        noGroupsLabel:SetFullWidth(true)
        container:AddChild(noGroupsLabel)
    end

    -- Preview toggle (ephemeral)
    local previewCb = AceGUI:Create("CheckBox")
    previewCb:SetLabel("Preview Resource Bars")
    previewCb:SetValue(CooldownCompanion:IsResourceBarPreviewActive())
    previewCb:SetFullWidth(true)
    previewCb:SetCallback("OnValueChanged", function(widget, event, val)
        if val then
            CooldownCompanion:StartResourceBarPreview()
        else
            CooldownCompanion:StopResourceBarPreview()
        end
    end)
    container:AddChild(previewCb)

    -- ============ Position Section ============
    local posHeading = AceGUI:Create("Heading")
    posHeading:SetText("Position")
    posHeading:SetFullWidth(true)
    container:AddChild(posHeading)

    local posKey = "rb_position"
    local posCollapsed = resourceBarCollapsedSections[posKey]

    local posCollapseBtn = CreateFrame("Button", nil, posHeading.frame)
    posCollapseBtn:SetSize(16, 16)
    posCollapseBtn:SetPoint("LEFT", posHeading.label, "RIGHT", 4, 0)
    posHeading.right:SetPoint("LEFT", posCollapseBtn, "RIGHT", 4, 0)
    local posArrow = posCollapseBtn:CreateTexture(nil, "ARTWORK")
    posArrow:SetSize(12, 12)
    posArrow:SetPoint("CENTER")
    posArrow:SetAtlas(posCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    posCollapseBtn:SetScript("OnClick", function()
        resourceBarCollapsedSections[posKey] = not resourceBarCollapsedSections[posKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not posCollapsed then
        local posDrop = AceGUI:Create("Dropdown")
        posDrop:SetLabel("Position")
        posDrop:SetList({ below = "Below Group", above = "Above Group" }, { "below", "above" })
        posDrop:SetValue(settings.position or "below")
        posDrop:SetFullWidth(true)
        posDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.position = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(posDrop)

        local ySlider = AceGUI:Create("Slider")
        ySlider:SetLabel("Y Offset")
        ySlider:SetSliderValues(-50, 50, 1)
        ySlider:SetValue(settings.yOffset or -2)
        ySlider:SetFullWidth(true)
        ySlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.yOffset = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(ySlider)

        local hSlider = AceGUI:Create("Slider")
        hSlider:SetLabel("Bar Height")
        hSlider:SetSliderValues(4, 40, 0.1)
        hSlider:SetValue(settings.barHeight or 12)
        hSlider:SetFullWidth(true)
        hSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.barHeight = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(hSlider)

        local spacingSlider = AceGUI:Create("Slider")
        spacingSlider:SetLabel("Bar Spacing")
        spacingSlider:SetSliderValues(0, 20, 0.1)
        spacingSlider:SetValue(settings.barSpacing or 1)
        spacingSlider:SetFullWidth(true)
        spacingSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.barSpacing = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(spacingSlider)
    end

    -- ============ Stacking Section ============
    local stackHeading = AceGUI:Create("Heading")
    stackHeading:SetText("Stacking")
    stackHeading:SetFullWidth(true)
    container:AddChild(stackHeading)

    local stackKey = "rb_stacking"
    local stackCollapsed = resourceBarCollapsedSections[stackKey]

    local stackCollapseBtn = CreateFrame("Button", nil, stackHeading.frame)
    stackCollapseBtn:SetSize(16, 16)
    stackCollapseBtn:SetPoint("LEFT", stackHeading.label, "RIGHT", 4, 0)
    stackHeading.right:SetPoint("LEFT", stackCollapseBtn, "RIGHT", 4, 0)
    local stackArrow = stackCollapseBtn:CreateTexture(nil, "ARTWORK")
    stackArrow:SetSize(12, 12)
    stackArrow:SetPoint("CENTER")
    stackArrow:SetAtlas(stackCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    stackCollapseBtn:SetScript("OnClick", function()
        resourceBarCollapsedSections[stackKey] = not resourceBarCollapsedSections[stackKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not stackCollapsed then
        local stackDrop = AceGUI:Create("Dropdown")
        stackDrop:SetLabel("Stack Order")
        stackDrop:SetList({
            cast_first = "Cast Bar First",
            resource_first = "Resource Bars First",
        }, { "cast_first", "resource_first" })
        stackDrop:SetValue(settings.stackOrder or "cast_first")
        stackDrop:SetFullWidth(true)
        stackDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.stackOrder = val
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(stackDrop)
    end

    -- ============ Resource Toggles Section ============
    local toggleHeading = AceGUI:Create("Heading")
    toggleHeading:SetText("Resource Toggles")
    toggleHeading:SetFullWidth(true)
    container:AddChild(toggleHeading)

    local toggleKey = "rb_toggles"
    local toggleCollapsed = resourceBarCollapsedSections[toggleKey]

    local toggleCollapseBtn = CreateFrame("Button", nil, toggleHeading.frame)
    toggleCollapseBtn:SetSize(16, 16)
    toggleCollapseBtn:SetPoint("LEFT", toggleHeading.label, "RIGHT", 4, 0)
    toggleHeading.right:SetPoint("LEFT", toggleCollapseBtn, "RIGHT", 4, 0)
    local toggleArrow = toggleCollapseBtn:CreateTexture(nil, "ARTWORK")
    toggleArrow:SetSize(12, 12)
    toggleArrow:SetPoint("CENTER")
    toggleArrow:SetAtlas(toggleCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    toggleCollapseBtn:SetScript("OnClick", function()
        resourceBarCollapsedSections[toggleKey] = not resourceBarCollapsedSections[toggleKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not toggleCollapsed then
        -- Only show mana toggle for classes that actually use mana
        local _, _, classID = UnitClass("player")
        local NO_MANA_CLASSES = { [1] = true, [3] = true, [4] = true, [6] = true, [12] = true }
        if classID and not NO_MANA_CLASSES[classID] then
            local manaCb = AceGUI:Create("CheckBox")
            manaCb:SetLabel("Hide Mana for Non-Healer Specs")
            manaCb:SetValue(settings.hideManaForNonHealer or false)
            manaCb:SetFullWidth(true)
            manaCb:SetCallback("OnValueChanged", function(widget, event, val)
                settings.hideManaForNonHealer = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(manaCb)
        end

        -- Per-resource enable/disable
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            local name = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end
            local enabled = settings.resources[pt].enabled ~= false

            local resCb = AceGUI:Create("CheckBox")
            resCb:SetLabel("Show " .. name)
            resCb:SetValue(enabled)
            resCb:SetFullWidth(true)
            resCb:SetCallback("OnValueChanged", function(widget, event, val)
                if not settings.resources[pt] then
                    settings.resources[pt] = {}
                end
                settings.resources[pt].enabled = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(resCb)
        end
    end
end

------------------------------------------------------------------------
-- RESOURCE BAR: Styling Panel
------------------------------------------------------------------------

local function BuildResourceBarStylingPanel(container)
    local db = CooldownCompanion.db.profile
    local settings = db.resourceBars

    if not settings.enabled then
        local label = AceGUI:Create("Label")
        label:SetText("Enable Resource Bars to configure styling.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    -- Bar Texture
    local texDrop = AceGUI:Create("Dropdown")
    texDrop:SetLabel("Bar Texture")
    texDrop:SetList(barTextureOptions)
    texDrop:SetValue(settings.barTexture or "Interface\\BUTTONS\\WHITE8X8")
    texDrop:SetFullWidth(true)
    texDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.barTexture = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(texDrop)

    -- Background Color
    local bgColorPicker = AceGUI:Create("ColorPicker")
    bgColorPicker:SetLabel("Background Color")
    local bgc = settings.backgroundColor or { 0, 0, 0, 0.5 }
    bgColorPicker:SetColor(bgc[1], bgc[2], bgc[3], bgc[4])
    bgColorPicker:SetHasAlpha(true)
    bgColorPicker:SetFullWidth(true)
    bgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        settings.backgroundColor = {r, g, b, a}
    end)
    bgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        settings.backgroundColor = {r, g, b, a}
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(bgColorPicker)

    -- ============ Border Section ============
    local borderHeading = AceGUI:Create("Heading")
    borderHeading:SetText("Border")
    borderHeading:SetFullWidth(true)
    container:AddChild(borderHeading)

    local borderKey = "rb_border"
    local borderCollapsed = resourceBarCollapsedSections[borderKey]

    local borderCollapseBtn = CreateFrame("Button", nil, borderHeading.frame)
    borderCollapseBtn:SetSize(16, 16)
    borderCollapseBtn:SetPoint("LEFT", borderHeading.label, "RIGHT", 4, 0)
    borderHeading.right:SetPoint("LEFT", borderCollapseBtn, "RIGHT", 4, 0)
    local borderArrow = borderCollapseBtn:CreateTexture(nil, "ARTWORK")
    borderArrow:SetSize(12, 12)
    borderArrow:SetPoint("CENTER")
    borderArrow:SetAtlas(borderCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    borderCollapseBtn:SetScript("OnClick", function()
        resourceBarCollapsedSections[borderKey] = not resourceBarCollapsedSections[borderKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not borderCollapsed then
        local borderDrop = AceGUI:Create("Dropdown")
        borderDrop:SetLabel("Border Style")
        borderDrop:SetList({
            pixel = "Pixel",
            none = "None",
        }, { "pixel", "none" })
        borderDrop:SetValue(settings.borderStyle or "pixel")
        borderDrop:SetFullWidth(true)
        borderDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.borderStyle = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(borderDrop)

        if settings.borderStyle == "pixel" then
            local borderColorPicker = AceGUI:Create("ColorPicker")
            borderColorPicker:SetLabel("Border Color")
            local brc = settings.borderColor or { 0, 0, 0, 1 }
            borderColorPicker:SetColor(brc[1], brc[2], brc[3], brc[4])
            borderColorPicker:SetHasAlpha(true)
            borderColorPicker:SetFullWidth(true)
            borderColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                settings.borderColor = {r, g, b, a}
            end)
            borderColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                settings.borderColor = {r, g, b, a}
                CooldownCompanion:ApplyResourceBars()
            end)
            container:AddChild(borderColorPicker)

            local borderSizeSlider = AceGUI:Create("Slider")
            borderSizeSlider:SetLabel("Border Size")
            borderSizeSlider:SetSliderValues(0, 4, 0.1)
            borderSizeSlider:SetValue(settings.borderSize or 1)
            borderSizeSlider:SetIsPercent(false)
            borderSizeSlider:SetFullWidth(true)
            borderSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                settings.borderSize = val
                CooldownCompanion:ApplyResourceBars()
            end)
            container:AddChild(borderSizeSlider)
        end
    end

    -- Segment Gap
    local gapSlider = AceGUI:Create("Slider")
    gapSlider:SetLabel("Segment Gap")
    gapSlider:SetSliderValues(0, 20, 0.1)
    gapSlider:SetValue(settings.segmentGap or 2)
    gapSlider:SetFullWidth(true)
    gapSlider:SetCallback("OnValueChanged", function(widget, event, val)
        settings.segmentGap = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(gapSlider)

    -- ============ Text Section ============
    local textHeading = AceGUI:Create("Heading")
    textHeading:SetText("Text")
    textHeading:SetFullWidth(true)
    container:AddChild(textHeading)

    local textKey = "rb_text"
    local textCollapsed = resourceBarCollapsedSections[textKey]

    local textCollapseBtn = CreateFrame("Button", nil, textHeading.frame)
    textCollapseBtn:SetSize(16, 16)
    textCollapseBtn:SetPoint("LEFT", textHeading.label, "RIGHT", 4, 0)
    textHeading.right:SetPoint("LEFT", textCollapseBtn, "RIGHT", 4, 0)
    local textArrow = textCollapseBtn:CreateTexture(nil, "ARTWORK")
    textArrow:SetSize(12, 12)
    textArrow:SetPoint("CENTER")
    textArrow:SetAtlas(textCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    textCollapseBtn:SetScript("OnClick", function()
        resourceBarCollapsedSections[textKey] = not resourceBarCollapsedSections[textKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not textCollapsed then
        local fontDrop = AceGUI:Create("Dropdown")
        fontDrop:SetLabel("Font")
        fontDrop:SetList(CS.fontOptions)
        fontDrop:SetValue(settings.textFont or "Fonts\\FRIZQT__.TTF")
        fontDrop:SetFullWidth(true)
        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.textFont = val
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(fontDrop)

        local sizeDrop = AceGUI:Create("Slider")
        sizeDrop:SetLabel("Font Size")
        sizeDrop:SetSliderValues(6, 24, 1)
        sizeDrop:SetValue(settings.textFontSize or 10)
        sizeDrop:SetFullWidth(true)
        sizeDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.textFontSize = val
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(sizeDrop)

        local outlineDrop = AceGUI:Create("Dropdown")
        outlineDrop:SetLabel("Outline")
        outlineDrop:SetList(CS.outlineOptions)
        outlineDrop:SetValue(settings.textFontOutline or "OUTLINE")
        outlineDrop:SetFullWidth(true)
        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            settings.textFontOutline = val
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(outlineDrop)

        local textColorPicker = AceGUI:Create("ColorPicker")
        textColorPicker:SetLabel("Text Color")
        local tc = settings.textFontColor or { 1, 1, 1, 1 }
        textColorPicker:SetColor(tc[1], tc[2], tc[3], tc[4])
        textColorPicker:SetHasAlpha(true)
        textColorPicker:SetFullWidth(true)
        textColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            settings.textFontColor = {r, g, b, a}
        end)
        textColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            settings.textFontColor = {r, g, b, a}
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(textColorPicker)
    end

    -- ============ Per-Resource Colors Section ============
    local colorHeading = AceGUI:Create("Heading")
    colorHeading:SetText("Per-Resource Colors")
    colorHeading:SetFullWidth(true)
    container:AddChild(colorHeading)

    local colorKey = "rb_colors"
    local colorCollapsed = resourceBarCollapsedSections[colorKey]

    local colorCollapseBtn = CreateFrame("Button", nil, colorHeading.frame)
    colorCollapseBtn:SetSize(16, 16)
    colorCollapseBtn:SetPoint("LEFT", colorHeading.label, "RIGHT", 4, 0)
    colorHeading.right:SetPoint("LEFT", colorCollapseBtn, "RIGHT", 4, 0)
    local colorArrow = colorCollapseBtn:CreateTexture(nil, "ARTWORK")
    colorArrow:SetSize(12, 12)
    colorArrow:SetPoint("CENTER")
    colorArrow:SetAtlas(colorCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    colorCollapseBtn:SetScript("OnClick", function()
        resourceBarCollapsedSections[colorKey] = not resourceBarCollapsedSections[colorKey]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not colorCollapsed then
        local resources = GetConfigActiveResources()
        for _, pt in ipairs(resources) do
            if not settings.resources[pt] then
                settings.resources[pt] = {}
            end

            if pt == 4 then
                -- Combo Points: two color pickers (normal vs at max)
                local normalColor = settings.resources[4].comboColor or DEFAULT_COMBO_COLOR_CONFIG
                local cpNormal = AceGUI:Create("ColorPicker")
                cpNormal:SetLabel("Combo Points")
                cpNormal:SetColor(normalColor[1], normalColor[2], normalColor[3])
                cpNormal:SetHasAlpha(false)
                cpNormal:SetFullWidth(true)
                cpNormal:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[4] then settings.resources[4] = {} end
                    settings.resources[4].comboColor = {r, g, b}
                end)
                cpNormal:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[4] then settings.resources[4] = {} end
                    settings.resources[4].comboColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpNormal)

                local maxColor = settings.resources[4].comboMaxColor or DEFAULT_COMBO_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Combo Points (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[4] then settings.resources[4] = {} end
                    settings.resources[4].comboMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[4] then settings.resources[4] = {} end
                    settings.resources[4].comboMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 5 then
                -- Runes: three color pickers (ready, recharging, max)
                local readyColor = settings.resources[5].runeReadyColor or DEFAULT_RUNE_READY_COLOR_CONFIG
                local cpReady = AceGUI:Create("ColorPicker")
                cpReady:SetLabel("Runes (Ready)")
                cpReady:SetColor(readyColor[1], readyColor[2], readyColor[3])
                cpReady:SetHasAlpha(false)
                cpReady:SetFullWidth(true)
                cpReady:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeReadyColor = {r, g, b}
                end)
                cpReady:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeReadyColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpReady)

                local rechargingColor = settings.resources[5].runeRechargingColor or DEFAULT_RUNE_RECHARGING_COLOR_CONFIG
                local cpRecharging = AceGUI:Create("ColorPicker")
                cpRecharging:SetLabel("Runes (Recharging)")
                cpRecharging:SetColor(rechargingColor[1], rechargingColor[2], rechargingColor[3])
                cpRecharging:SetHasAlpha(false)
                cpRecharging:SetFullWidth(true)
                cpRecharging:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeRechargingColor = {r, g, b}
                end)
                cpRecharging:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeRechargingColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpRecharging)

                local maxColor = settings.resources[5].runeMaxColor or DEFAULT_RUNE_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Runes (All Ready)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[5] then settings.resources[5] = {} end
                    settings.resources[5].runeMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 7 then
                -- Soul Shards: three color pickers (ready, recharging, max)
                local readyColor = settings.resources[7].shardReadyColor or DEFAULT_SHARD_READY_COLOR_CONFIG
                local cpReady = AceGUI:Create("ColorPicker")
                cpReady:SetLabel("Soul Shards (Ready)")
                cpReady:SetColor(readyColor[1], readyColor[2], readyColor[3])
                cpReady:SetHasAlpha(false)
                cpReady:SetFullWidth(true)
                cpReady:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardReadyColor = {r, g, b}
                end)
                cpReady:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardReadyColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpReady)

                local rechargingColor = settings.resources[7].shardRechargingColor or DEFAULT_SHARD_RECHARGING_COLOR_CONFIG
                local cpRecharging = AceGUI:Create("ColorPicker")
                cpRecharging:SetLabel("Soul Shards (Recharging)")
                cpRecharging:SetColor(rechargingColor[1], rechargingColor[2], rechargingColor[3])
                cpRecharging:SetHasAlpha(false)
                cpRecharging:SetFullWidth(true)
                cpRecharging:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardRechargingColor = {r, g, b}
                end)
                cpRecharging:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardRechargingColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpRecharging)

                local maxColor = settings.resources[7].shardMaxColor or DEFAULT_SHARD_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Soul Shards (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[7] then settings.resources[7] = {} end
                    settings.resources[7].shardMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 9 then
                -- Holy Power: two color pickers (normal vs max)
                local normalColor = settings.resources[9].holyColor or DEFAULT_HOLY_COLOR_CONFIG
                local cpNormal = AceGUI:Create("ColorPicker")
                cpNormal:SetLabel("Holy Power")
                cpNormal:SetColor(normalColor[1], normalColor[2], normalColor[3])
                cpNormal:SetHasAlpha(false)
                cpNormal:SetFullWidth(true)
                cpNormal:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[9] then settings.resources[9] = {} end
                    settings.resources[9].holyColor = {r, g, b}
                end)
                cpNormal:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[9] then settings.resources[9] = {} end
                    settings.resources[9].holyColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpNormal)

                local maxColor = settings.resources[9].holyMaxColor or DEFAULT_HOLY_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Holy Power (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[9] then settings.resources[9] = {} end
                    settings.resources[9].holyMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[9] then settings.resources[9] = {} end
                    settings.resources[9].holyMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 12 then
                -- Chi: two color pickers (normal vs max)
                local normalColor = settings.resources[12].chiColor or DEFAULT_CHI_COLOR_CONFIG
                local cpNormal = AceGUI:Create("ColorPicker")
                cpNormal:SetLabel("Chi")
                cpNormal:SetColor(normalColor[1], normalColor[2], normalColor[3])
                cpNormal:SetHasAlpha(false)
                cpNormal:SetFullWidth(true)
                cpNormal:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[12] then settings.resources[12] = {} end
                    settings.resources[12].chiColor = {r, g, b}
                end)
                cpNormal:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[12] then settings.resources[12] = {} end
                    settings.resources[12].chiColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpNormal)

                local maxColor = settings.resources[12].chiMaxColor or DEFAULT_CHI_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Chi (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[12] then settings.resources[12] = {} end
                    settings.resources[12].chiMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[12] then settings.resources[12] = {} end
                    settings.resources[12].chiMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 16 then
                -- Arcane Charges: two color pickers (normal vs max)
                local normalColor = settings.resources[16].arcaneColor or DEFAULT_ARCANE_COLOR_CONFIG
                local cpNormal = AceGUI:Create("ColorPicker")
                cpNormal:SetLabel("Arcane Charges")
                cpNormal:SetColor(normalColor[1], normalColor[2], normalColor[3])
                cpNormal:SetHasAlpha(false)
                cpNormal:SetFullWidth(true)
                cpNormal:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[16] then settings.resources[16] = {} end
                    settings.resources[16].arcaneColor = {r, g, b}
                end)
                cpNormal:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[16] then settings.resources[16] = {} end
                    settings.resources[16].arcaneColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpNormal)

                local maxColor = settings.resources[16].arcaneMaxColor or DEFAULT_ARCANE_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Arcane Charges (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[16] then settings.resources[16] = {} end
                    settings.resources[16].arcaneMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[16] then settings.resources[16] = {} end
                    settings.resources[16].arcaneMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            elseif pt == 19 then
                -- Essence: three color pickers (ready, recharging, max)
                local readyColor = settings.resources[19].essenceReadyColor or DEFAULT_ESSENCE_READY_COLOR_CONFIG
                local cpReady = AceGUI:Create("ColorPicker")
                cpReady:SetLabel("Essence (Ready)")
                cpReady:SetColor(readyColor[1], readyColor[2], readyColor[3])
                cpReady:SetHasAlpha(false)
                cpReady:SetFullWidth(true)
                cpReady:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceReadyColor = {r, g, b}
                end)
                cpReady:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceReadyColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpReady)

                local rechargingColor = settings.resources[19].essenceRechargingColor or DEFAULT_ESSENCE_RECHARGING_COLOR_CONFIG
                local cpRecharging = AceGUI:Create("ColorPicker")
                cpRecharging:SetLabel("Essence (Recharging)")
                cpRecharging:SetColor(rechargingColor[1], rechargingColor[2], rechargingColor[3])
                cpRecharging:SetHasAlpha(false)
                cpRecharging:SetFullWidth(true)
                cpRecharging:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceRechargingColor = {r, g, b}
                end)
                cpRecharging:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceRechargingColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpRecharging)

                local maxColor = settings.resources[19].essenceMaxColor or DEFAULT_ESSENCE_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("Essence (Max)")
                cpMax:SetColor(maxColor[1], maxColor[2], maxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[19] then settings.resources[19] = {} end
                    settings.resources[19].essenceMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            else
                local name = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)
                local currentColor = settings.resources[pt].color or DEFAULT_POWER_COLORS_CONFIG[pt] or { 1, 1, 1 }

                local cp = AceGUI:Create("ColorPicker")
                cp:SetLabel(name)
                cp:SetColor(currentColor[1], currentColor[2], currentColor[3])
                cp:SetHasAlpha(false)
                cp:SetFullWidth(true)
                cp:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[pt] then
                        settings.resources[pt] = {}
                    end
                    settings.resources[pt].color = {r, g, b}
                end)
                cp:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[pt] then
                        settings.resources[pt] = {}
                    end
                    settings.resources[pt].color = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cp)
            end
        end
    end
end

-- Expose builder functions for Config.lua to call
ST._BuildSpellSettings = BuildSpellSettings
ST._BuildItemSettings = BuildItemSettings
ST._BuildEquipItemSettings = BuildEquipItemSettings
ST._RefreshButtonSettingsColumn = RefreshButtonSettingsColumn
ST._RefreshButtonSettingsMultiSelect = RefreshButtonSettingsMultiSelect
ST._BuildVisibilitySettings = BuildVisibilitySettings
ST._BuildAppearanceTab = BuildAppearanceTab
ST._BuildPositioningTab = BuildPositioningTab
ST._BuildExtrasTab = BuildExtrasTab
ST._BuildLoadConditionsTab = BuildLoadConditionsTab
ST._BuildCastBarAnchoringPanel = BuildCastBarAnchoringPanel
ST._BuildCastBarStylingPanel = BuildCastBarStylingPanel
ST._BuildResourceBarAnchoringPanel = BuildResourceBarAnchoringPanel
ST._BuildResourceBarStylingPanel = BuildResourceBarStylingPanel