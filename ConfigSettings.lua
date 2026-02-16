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
-- Aura bar autocomplete cache (TrackedBuff + TrackedBar spells only)
------------------------------------------------------------------------
local auraBarAutocompleteCache = nil

local function BuildAuraBarAutocompleteCache()
    local cache = {}
    local seen = {}
    for _, cat in ipairs({
        Enum.CooldownViewerCategory.TrackedBuff,
        Enum.CooldownViewerCategory.TrackedBar,
    }) do
        local catLabel = (cat == Enum.CooldownViewerCategory.TrackedBuff)
            and "Tracked Buff" or "Tracked Bar"
        local ids = C_CooldownViewer.GetCooldownViewerCategorySet(cat, true)
        if ids then
            for _, cdID in ipairs(ids) do
                local info = C_CooldownViewer.GetCooldownViewerCooldownInfo(cdID)
                if info and info.spellID and not seen[info.spellID] then
                    seen[info.spellID] = true
                    local name = C_Spell.GetSpellName(info.spellID)
                    local icon = C_Spell.GetSpellTexture(info.spellID)
                    if name then
                        cache[#cache + 1] = {
                            id = info.spellID,
                            name = name,
                            nameLower = name:lower(),
                            icon = icon or 134400,
                            category = catLabel,
                        }
                    end
                end
            end
        end
    end
    auraBarAutocompleteCache = cache
    return cache
end

-- Helper: tint AceGUI Heading labels with player class color
local function ColorHeading(heading)
    local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if cc then
        heading.label:SetTextColor(cc.r, cc.g, cc.b)
    end
end

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

    -- Desaturate While Inactive toggle (passive/proc only — default on)
    if buttonData.isPassive then
        local desatInactiveCb = AceGUI:Create("CheckBox")
        desatInactiveCb:SetLabel("Desaturate While Inactive")
        desatInactiveCb:SetValue(buttonData.desaturateWhileInactive ~= false)
        desatInactiveCb:SetFullWidth(true)
        desatInactiveCb:SetCallback("OnValueChanged", function(widget, event, val)
            buttonData.desaturateWhileInactive = val or nil
            CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
        end)
        scroll:AddChild(desatInactiveCb)
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

            -- Enable Active Aura Indicator toggle
            local auraIndicatorCb = AceGUI:Create("CheckBox")
            auraIndicatorCb:SetLabel("Enable Active Aura Indicator")
            auraIndicatorCb:SetValue(buttonData.auraIndicatorEnabled == true)
            auraIndicatorCb:SetFullWidth(true)
            auraIndicatorCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraIndicatorEnabled = val or nil
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(auraIndicatorCb)

            if buttonData.auraIndicatorEnabled then
                if group.displayMode ~= "bars" then
                    -- Icon mode: preview toggle
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
                else
                    -- Bar mode: preview toggle
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
            end

            -- Don't Desaturate While Active (aura tracking related)
            local auraNoDesatCb = AceGUI:Create("CheckBox")
            auraNoDesatCb:SetLabel("Don't Desaturate While Active")
            auraNoDesatCb:SetValue(buttonData.auraNoDesaturate == true)
            auraNoDesatCb:SetFullWidth(true)
            auraNoDesatCb:SetCallback("OnValueChanged", function(widget, event, val)
                buttonData.auraNoDesaturate = val or nil
            end)
            scroll:AddChild(auraNoDesatCb)

            -- Pandemic glow/indicator toggles (aura tracking related)
            local pandemicCapable = viewerFrame
                and viewerFrame.CanTriggerAlertType
                and viewerFrame:CanTriggerAlertType(Enum.CooldownViewerAlertEventType.PandemicTime)
            if pandemicCapable then
            if group.displayMode ~= "bars" then
            -- Icon mode: Pandemic Glow toggle
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
            end -- pandemicCapable
    end -- hasViewerFrame and auraTracking
    end -- canTrackAura
    end -- not auraCollapsed

    -- Indicators section (available for all spells, icon mode only)
    if group.displayMode ~= "bars" then
    local indicatorHeading = AceGUI:Create("Heading")
    indicatorHeading:SetText("Indicators")
    ColorHeading(indicatorHeading)
    indicatorHeading:SetFullWidth(true)
    scroll:AddChild(indicatorHeading)

    local indicatorKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_indicators"
    local indicatorCollapsed = CS.collapsedSections[indicatorKey]

    local indicatorCollapseBtn = CreateFrame("Button", nil, indicatorHeading.frame)
    table.insert(CS.buttonSettingsCollapseButtons, indicatorCollapseBtn)
    indicatorCollapseBtn:SetSize(16, 16)
    indicatorCollapseBtn:SetPoint("LEFT", indicatorHeading.label, "RIGHT", 4, 0)
    indicatorHeading.right:SetPoint("LEFT", indicatorCollapseBtn, "RIGHT", 4, 0)
    local indicatorCollapseArrow = indicatorCollapseBtn:CreateTexture(nil, "ARTWORK")
    indicatorCollapseArrow:SetSize(12, 12)
    indicatorCollapseArrow:SetPoint("CENTER")
    indicatorCollapseArrow:SetAtlas(indicatorCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
    indicatorCollapseBtn:SetScript("OnClick", function()
        CS.collapsedSections[indicatorKey] = not CS.collapsedSections[indicatorKey]
        CooldownCompanion:RefreshConfigPanel()
    end)
    indicatorCollapseBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(indicatorCollapsed and "Expand" or "Collapse")
        GameTooltip:Show()
    end)
    indicatorCollapseBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    if not indicatorCollapsed then
    -- Proc Glow toggle
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
    end -- not indicatorCollapsed
    end -- icon mode

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

-- Forward declarations — defined after all collapsible-section state
local BuildCastBarAnchoringPanel
local BuildResourceBarAnchoringPanel
local BuildCustomAuraBarPanel
local BuildFrameAnchoringPlayerPanel
local BuildFrameAnchoringTargetPanel

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
-- COLUMN 3: Settings (TabGroup)
------------------------------------------------------------------------
-- Tab UI state lives in CS (shared with Config.lua for cleanup on tab switch)
local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

------------------------------------------------------------------------
-- PROMOTE BUTTON HELPER
------------------------------------------------------------------------
-- Creates a small button next to a heading label that promotes a section
-- to per-button style overrides.
local function CreatePromoteButton(headingWidget, sectionId, buttonData, groupStyle)
    local promoteBtn = CreateFrame("Button", nil, headingWidget.frame)
    promoteBtn:SetSize(16, 16)
    promoteBtn:SetPoint("LEFT", headingWidget.label, "RIGHT", 4, 0)
    headingWidget.right:SetPoint("LEFT", promoteBtn, "RIGHT", 4, 0)

    local icon = promoteBtn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")

    -- Determine if promote is available
    local multiCount = 0
    if CS.selectedButtons then
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
    end
    local canPromote = CS.selectedButton ~= nil and multiCount < 2
        and buttonData ~= nil
        and not (buttonData.overrideSections and buttonData.overrideSections[sectionId])

    if canPromote then
        icon:SetAtlas("Crosshair_VehichleCursor_32")
        promoteBtn:Enable()
    else
        icon:SetAtlas("Crosshair_unableVehichleCursor_32")
        promoteBtn:Disable()
    end

    local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
    local sectionLabel = sectionDef and sectionDef.label or sectionId

    promoteBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if canPromote then
            GameTooltip:AddLine("Override " .. sectionLabel .. " for this button")
        else
            GameTooltip:AddLine("Select a button to add an override", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    promoteBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    promoteBtn:SetScript("OnClick", function()
        if not canPromote then return end
        CooldownCompanion:PromoteSection(buttonData, groupStyle, sectionId)
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)

    table.insert(tabInfoButtons, promoteBtn)
    return promoteBtn
end

------------------------------------------------------------------------
-- REVERT BUTTON HELPER (for Overrides tab headings)
------------------------------------------------------------------------
local function CreateRevertButton(headingWidget, buttonData, sectionId)
    local revertBtn = CreateFrame("Button", nil, headingWidget.frame)
    revertBtn:SetSize(16, 16)
    revertBtn:SetPoint("LEFT", headingWidget.label, "RIGHT", 4, 0)
    headingWidget.right:SetPoint("LEFT", revertBtn, "RIGHT", 4, 0)

    local icon = revertBtn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")
    icon:SetAtlas("common-search-clearbutton")

    revertBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
        GameTooltip:AddLine("Revert " .. (sectionDef and sectionDef.label or sectionId) .. " to group defaults")
        GameTooltip:Show()
    end)
    revertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    revertBtn:SetScript("OnClick", function()
        CooldownCompanion:RevertSection(buttonData, sectionId)
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)

    return revertBtn
end

------------------------------------------------------------------------
-- REUSABLE SECTION BUILDER FUNCTIONS
------------------------------------------------------------------------
-- Each builder takes (container, styleTable, refreshCallback) and adds
-- AceGUI widgets to the container, reading/writing values from styleTable.

local function BuildCooldownTextControls(container, styleTable, refreshCallback)
    local cdTextCb = AceGUI:Create("CheckBox")
    cdTextCb:SetLabel("Show Cooldown Text")
    cdTextCb:SetValue(styleTable.showCooldownText or false)
    cdTextCb:SetFullWidth(true)
    cdTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showCooldownText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(cdTextCb)

    if styleTable.showCooldownText then
        local fontSizeSlider = AceGUI:Create("Slider")
        fontSizeSlider:SetLabel("Font Size")
        fontSizeSlider:SetSliderValues(8, 32, 1)
        fontSizeSlider:SetValue(styleTable.cooldownFontSize or 12)
        fontSizeSlider:SetFullWidth(true)
        fontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownFontSize = val
            refreshCallback()
        end)
        container:AddChild(fontSizeSlider)

        local fontDrop = AceGUI:Create("Dropdown")
        fontDrop:SetLabel("Font")
        CS.SetupFontDropdown(fontDrop)
        fontDrop:SetValue(styleTable.cooldownFont or "Friz Quadrata TT")
        fontDrop:SetFullWidth(true)
        fontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownFont = val
            refreshCallback()
        end)
        container:AddChild(fontDrop)

        local outlineDrop = AceGUI:Create("Dropdown")
        outlineDrop:SetLabel("Font Outline")
        outlineDrop:SetList(CS.outlineOptions)
        outlineDrop:SetValue(styleTable.cooldownFontOutline or "OUTLINE")
        outlineDrop:SetFullWidth(true)
        outlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.cooldownFontOutline = val
            refreshCallback()
        end)
        container:AddChild(outlineDrop)

        local cdFontColor = AceGUI:Create("ColorPicker")
        cdFontColor:SetLabel("Font Color")
        cdFontColor:SetHasAlpha(true)
        local cdc = styleTable.cooldownFontColor or {1, 1, 1, 1}
        cdFontColor:SetColor(cdc[1], cdc[2], cdc[3], cdc[4])
        cdFontColor:SetFullWidth(true)
        cdFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.cooldownFontColor = {r, g, b, a}
            refreshCallback()
        end)
        cdFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.cooldownFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(cdFontColor)
    end
end

local function BuildAuraTextControls(container, styleTable, refreshCallback)
    local auraTextCb = AceGUI:Create("CheckBox")
    auraTextCb:SetLabel("Show Aura Text")
    auraTextCb:SetValue(styleTable.showAuraText ~= false)
    auraTextCb:SetFullWidth(true)
    auraTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showAuraText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(auraTextCb)

    if styleTable.showAuraText ~= false then
        local auraFontSizeSlider = AceGUI:Create("Slider")
        auraFontSizeSlider:SetLabel("Font Size")
        auraFontSizeSlider:SetSliderValues(8, 32, 1)
        auraFontSizeSlider:SetValue(styleTable.auraTextFontSize or 12)
        auraFontSizeSlider:SetFullWidth(true)
        auraFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraTextFontSize = val
            refreshCallback()
        end)
        container:AddChild(auraFontSizeSlider)

        local auraFontDrop = AceGUI:Create("Dropdown")
        auraFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(auraFontDrop)
        auraFontDrop:SetValue(styleTable.auraTextFont or "Friz Quadrata TT")
        auraFontDrop:SetFullWidth(true)
        auraFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraTextFont = val
            refreshCallback()
        end)
        container:AddChild(auraFontDrop)

        local auraOutlineDrop = AceGUI:Create("Dropdown")
        auraOutlineDrop:SetLabel("Font Outline")
        auraOutlineDrop:SetList(CS.outlineOptions)
        auraOutlineDrop:SetValue(styleTable.auraTextFontOutline or "OUTLINE")
        auraOutlineDrop:SetFullWidth(true)
        auraOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraTextFontOutline = val
            refreshCallback()
        end)
        container:AddChild(auraOutlineDrop)

        local auraFontColor = AceGUI:Create("ColorPicker")
        auraFontColor:SetLabel("Font Color")
        auraFontColor:SetHasAlpha(true)
        local ac = styleTable.auraTextFontColor or {0, 0.925, 1, 1}
        auraFontColor:SetColor(ac[1], ac[2], ac[3], ac[4])
        auraFontColor:SetFullWidth(true)
        auraFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.auraTextFontColor = {r, g, b, a}
            refreshCallback()
        end)
        auraFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.auraTextFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(auraFontColor)
    end
end

local function BuildKeybindTextControls(container, styleTable, refreshCallback)
    local kbCb = AceGUI:Create("CheckBox")
    kbCb:SetLabel("Show Keybind Text")
    kbCb:SetValue(styleTable.showKeybindText or false)
    kbCb:SetFullWidth(true)
    kbCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showKeybindText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(kbCb)

    if styleTable.showKeybindText then
        local kbAnchorDrop = AceGUI:Create("Dropdown")
        kbAnchorDrop:SetLabel("Anchor")
        local kbAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            kbAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        kbAnchorDrop:SetList(kbAnchorValues, CS.anchorPoints)
        kbAnchorDrop:SetValue(styleTable.keybindAnchor or "TOPRIGHT")
        kbAnchorDrop:SetFullWidth(true)
        kbAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindAnchor = val
            refreshCallback()
        end)
        container:AddChild(kbAnchorDrop)

        local kbFontSizeSlider = AceGUI:Create("Slider")
        kbFontSizeSlider:SetLabel("Font Size")
        kbFontSizeSlider:SetSliderValues(6, 24, 1)
        kbFontSizeSlider:SetValue(styleTable.keybindFontSize or 10)
        kbFontSizeSlider:SetFullWidth(true)
        kbFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindFontSize = val
            refreshCallback()
        end)
        container:AddChild(kbFontSizeSlider)

        local kbFontDrop = AceGUI:Create("Dropdown")
        kbFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(kbFontDrop)
        kbFontDrop:SetValue(styleTable.keybindFont or "Friz Quadrata TT")
        kbFontDrop:SetFullWidth(true)
        kbFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindFont = val
            refreshCallback()
        end)
        container:AddChild(kbFontDrop)

        local kbOutlineDrop = AceGUI:Create("Dropdown")
        kbOutlineDrop:SetLabel("Font Outline")
        kbOutlineDrop:SetList(CS.outlineOptions)
        kbOutlineDrop:SetValue(styleTable.keybindFontOutline or "OUTLINE")
        kbOutlineDrop:SetFullWidth(true)
        kbOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.keybindFontOutline = val
            refreshCallback()
        end)
        container:AddChild(kbOutlineDrop)

        local kbFontColor = AceGUI:Create("ColorPicker")
        kbFontColor:SetLabel("Font Color")
        kbFontColor:SetHasAlpha(true)
        local kbc = styleTable.keybindFontColor or {1, 1, 1, 1}
        kbFontColor:SetColor(kbc[1], kbc[2], kbc[3], kbc[4])
        kbFontColor:SetFullWidth(true)
        kbFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.keybindFontColor = {r, g, b, a}
            refreshCallback()
        end)
        kbFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.keybindFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(kbFontColor)
    end
end

local function BuildChargeTextControls(container, styleTable, refreshCallback)
    local chargeTextCb = AceGUI:Create("CheckBox")
    chargeTextCb:SetLabel("Show Charge Text")
    chargeTextCb:SetValue(styleTable.showChargeText ~= false)
    chargeTextCb:SetFullWidth(true)
    chargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showChargeText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(chargeTextCb)

    if styleTable.showChargeText ~= false then
        local chargeFontSizeSlider = AceGUI:Create("Slider")
        chargeFontSizeSlider:SetLabel("Font Size")
        chargeFontSizeSlider:SetSliderValues(8, 32, 1)
        chargeFontSizeSlider:SetValue(styleTable.chargeFontSize or 12)
        chargeFontSizeSlider:SetFullWidth(true)
        chargeFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeFontSize = val
            refreshCallback()
        end)
        container:AddChild(chargeFontSizeSlider)

        local chargeFontDrop = AceGUI:Create("Dropdown")
        chargeFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(chargeFontDrop)
        chargeFontDrop:SetValue(styleTable.chargeFont or "Friz Quadrata TT")
        chargeFontDrop:SetFullWidth(true)
        chargeFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeFont = val
            refreshCallback()
        end)
        container:AddChild(chargeFontDrop)

        local chargeOutlineDrop = AceGUI:Create("Dropdown")
        chargeOutlineDrop:SetLabel("Font Outline")
        chargeOutlineDrop:SetList(CS.outlineOptions)
        chargeOutlineDrop:SetValue(styleTable.chargeFontOutline or "OUTLINE")
        chargeOutlineDrop:SetFullWidth(true)
        chargeOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeFontOutline = val
            refreshCallback()
        end)
        container:AddChild(chargeOutlineDrop)

        local chargeFontColor = AceGUI:Create("ColorPicker")
        chargeFontColor:SetLabel("Font Color (Max Charges)")
        chargeFontColor:SetHasAlpha(true)
        local cfc = styleTable.chargeFontColor or {1, 1, 1, 1}
        chargeFontColor:SetColor(cfc[1], cfc[2], cfc[3], cfc[4])
        chargeFontColor:SetFullWidth(true)
        chargeFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.chargeFontColor = {r, g, b, a}
            refreshCallback()
        end)
        chargeFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.chargeFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(chargeFontColor)

        local chargeFontColorMissing = AceGUI:Create("ColorPicker")
        chargeFontColorMissing:SetLabel("Font Color (Missing Charges)")
        chargeFontColorMissing:SetHasAlpha(true)
        local cfcm = styleTable.chargeFontColorMissing or {1, 1, 1, 1}
        chargeFontColorMissing:SetColor(cfcm[1], cfcm[2], cfcm[3], cfcm[4])
        chargeFontColorMissing:SetFullWidth(true)
        chargeFontColorMissing:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.chargeFontColorMissing = {r, g, b, a}
            refreshCallback()
        end)
        chargeFontColorMissing:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.chargeFontColorMissing = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(chargeFontColorMissing)

        local chargeFontColorZero = AceGUI:Create("ColorPicker")
        chargeFontColorZero:SetLabel("Font Color (Zero Charges)")
        chargeFontColorZero:SetHasAlpha(true)
        local cfcz = styleTable.chargeFontColorZero or {1, 1, 1, 1}
        chargeFontColorZero:SetColor(cfcz[1], cfcz[2], cfcz[3], cfcz[4])
        chargeFontColorZero:SetFullWidth(true)
        chargeFontColorZero:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.chargeFontColorZero = {r, g, b, a}
            refreshCallback()
        end)
        chargeFontColorZero:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.chargeFontColorZero = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(chargeFontColorZero)

        local chargeAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            chargeAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local chargeAnchorDrop = AceGUI:Create("Dropdown")
        chargeAnchorDrop:SetLabel("Anchor")
        chargeAnchorDrop:SetList(chargeAnchorValues, CS.anchorPoints)
        chargeAnchorDrop:SetValue(styleTable.chargeAnchor or "BOTTOMRIGHT")
        chargeAnchorDrop:SetFullWidth(true)
        chargeAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeAnchor = val
            refreshCallback()
        end)
        container:AddChild(chargeAnchorDrop)

        local chargeXSlider = AceGUI:Create("Slider")
        chargeXSlider:SetLabel("X Offset")
        chargeXSlider:SetSliderValues(-20, 20, 1)
        chargeXSlider:SetValue(styleTable.chargeXOffset or -2)
        chargeXSlider:SetFullWidth(true)
        chargeXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeXOffset = val
            refreshCallback()
        end)
        container:AddChild(chargeXSlider)

        local chargeYSlider = AceGUI:Create("Slider")
        chargeYSlider:SetLabel("Y Offset")
        chargeYSlider:SetSliderValues(-20, 20, 1)
        chargeYSlider:SetValue(styleTable.chargeYOffset or 2)
        chargeYSlider:SetFullWidth(true)
        chargeYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.chargeYOffset = val
            refreshCallback()
        end)
        container:AddChild(chargeYSlider)
    end
end

local function BuildBorderControls(container, styleTable, refreshCallback)
    local borderSlider = AceGUI:Create("Slider")
    borderSlider:SetLabel("Border Size")
    borderSlider:SetSliderValues(0, 5, 0.1)
    borderSlider:SetValue(styleTable.borderSize or ST.DEFAULT_BORDER_SIZE)
    borderSlider:SetFullWidth(true)
    borderSlider:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.borderSize = val
        refreshCallback()
    end)
    container:AddChild(borderSlider)

    local borderColor = AceGUI:Create("ColorPicker")
    borderColor:SetLabel("Border Color")
    borderColor:SetHasAlpha(true)
    local bc = styleTable.borderColor or {0, 0, 0, 1}
    borderColor:SetColor(bc[1], bc[2], bc[3], bc[4])
    borderColor:SetFullWidth(true)
    borderColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.borderColor = {r, g, b, a}
        refreshCallback()
    end)
    borderColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.borderColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(borderColor)
end

local function BuildBackgroundColorControls(container, styleTable, refreshCallback)
    local bgColor = AceGUI:Create("ColorPicker")
    bgColor:SetLabel("Background Color")
    bgColor:SetHasAlpha(true)
    local bgc = styleTable.backgroundColor or {0, 0, 0, 0.5}
    bgColor:SetColor(bgc[1], bgc[2], bgc[3], bgc[4])
    bgColor:SetFullWidth(true)
    bgColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.backgroundColor = {r, g, b, a}
        refreshCallback()
    end)
    bgColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.backgroundColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(bgColor)
end

local function BuildDesaturationControls(container, styleTable, refreshCallback)
    local desatCb = AceGUI:Create("CheckBox")
    desatCb:SetLabel("Desaturate On Cooldown")
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
end

local function BuildShowGCDSwipeControls(container, styleTable, refreshCallback)
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local isBarMode = group and group.displayMode == "bars"
    local cb = AceGUI:Create("CheckBox")
    cb:SetLabel(isBarMode and "Show GCD" or "Show GCD Swipe")
    cb:SetValue(styleTable.showGCDSwipe == true)
    cb:SetFullWidth(true)
    cb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showGCDSwipe = val
        refreshCallback()
    end)
    container:AddChild(cb)
end

local function BuildLossOfControlControls(container, styleTable, refreshCallback)
    local locCb = AceGUI:Create("CheckBox")
    locCb:SetLabel("Show Loss of Control")
    locCb:SetValue(styleTable.showLossOfControl or false)
    locCb:SetFullWidth(true)
    locCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showLossOfControl = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(locCb)

    if styleTable.showLossOfControl then
        local locColor = AceGUI:Create("ColorPicker")
        locColor:SetLabel("LoC Overlay Color")
        locColor:SetHasAlpha(true)
        local lc = styleTable.lossOfControlColor or {1, 0, 0, 0.5}
        locColor:SetColor(lc[1], lc[2], lc[3], lc[4])
        locColor:SetFullWidth(true)
        locColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.lossOfControlColor = {r, g, b, a}
            refreshCallback()
        end)
        locColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.lossOfControlColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(locColor)
    end
end

local function BuildUnusableDimmingControls(container, styleTable, refreshCallback)
    local unusableCb = AceGUI:Create("CheckBox")
    unusableCb:SetLabel("Show Unusable Dimming")
    unusableCb:SetValue(styleTable.showUnusable or false)
    unusableCb:SetFullWidth(true)
    unusableCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showUnusable = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(unusableCb)

    if styleTable.showUnusable then
        local unusableColor = AceGUI:Create("ColorPicker")
        unusableColor:SetLabel("Unusable Tint Color")
        unusableColor:SetHasAlpha(false)
        local uc = styleTable.unusableColor or {0.3, 0.3, 0.6}
        unusableColor:SetColor(uc[1], uc[2], uc[3])
        unusableColor:SetFullWidth(true)
        unusableColor:SetCallback("OnValueChanged", function(widget, event, r, g, b)
            styleTable.unusableColor = {r, g, b}
            refreshCallback()
        end)
        unusableColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
            styleTable.unusableColor = {r, g, b}
            refreshCallback()
        end)
        container:AddChild(unusableColor)
    end
end

local function BuildAssistedHighlightControls(container, styleTable, refreshCallback)
    local assistedCb = AceGUI:Create("CheckBox")
    assistedCb:SetLabel("Show Assisted Highlight")
    assistedCb:SetValue(styleTable.showAssistedHighlight or false)
    assistedCb:SetFullWidth(true)
    assistedCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showAssistedHighlight = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(assistedCb)

    if styleTable.showAssistedHighlight then
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
            CooldownCompanion:RefreshConfigPanel()
        end)
        container:AddChild(styleDrop)

        if styleTable.assistedHighlightStyle == "solid" then
            local hlColor = AceGUI:Create("ColorPicker")
            hlColor:SetLabel("Highlight Color")
            hlColor:SetHasAlpha(true)
            local c = styleTable.assistedHighlightColor or {0.3, 1, 0.3, 0.9}
            hlColor:SetColor(c[1], c[2], c[3], c[4])
            hlColor:SetFullWidth(true)
            hlColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                styleTable.assistedHighlightColor = {r, g, b, a}
                refreshCallback()
            end)
            hlColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                styleTable.assistedHighlightColor = {r, g, b, a}
                refreshCallback()
            end)
            container:AddChild(hlColor)

            local hlSizeSlider = AceGUI:Create("Slider")
            hlSizeSlider:SetLabel("Border Size")
            hlSizeSlider:SetSliderValues(1, 6, 0.5)
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
            blizzSlider:SetSliderValues(0, 60, 1)
            blizzSlider:SetValue(styleTable.assistedHighlightBlizzardOverhang or 32)
            blizzSlider:SetFullWidth(true)
            blizzSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.assistedHighlightBlizzardOverhang = val
                refreshCallback()
            end)
            container:AddChild(blizzSlider)
        elseif styleTable.assistedHighlightStyle == "proc" then
            local procHlColor = AceGUI:Create("ColorPicker")
            procHlColor:SetLabel("Glow Color")
            procHlColor:SetHasAlpha(true)
            local phc = styleTable.assistedHighlightProcColor or {1, 1, 1, 1}
            procHlColor:SetColor(phc[1], phc[2], phc[3], phc[4])
            procHlColor:SetFullWidth(true)
            procHlColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
                styleTable.assistedHighlightProcColor = {r, g, b, a}
                refreshCallback()
            end)
            procHlColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
                styleTable.assistedHighlightProcColor = {r, g, b, a}
                refreshCallback()
            end)
            container:AddChild(procHlColor)

            local procSlider = AceGUI:Create("Slider")
            procSlider:SetLabel("Glow Size")
            procSlider:SetSliderValues(0, 60, 1)
            procSlider:SetValue(styleTable.assistedHighlightProcOverhang or 32)
            procSlider:SetFullWidth(true)
            procSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.assistedHighlightProcOverhang = val
                refreshCallback()
            end)
            container:AddChild(procSlider)
        end
    end
end

local function BuildProcGlowControls(container, styleTable, refreshCallback)
    -- Style dropdown
    local procStyleDrop = AceGUI:Create("Dropdown")
    procStyleDrop:SetLabel("Glow Style")
    procStyleDrop:SetList({
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }, {"solid", "pixel", "glow"})
    procStyleDrop:SetValue(styleTable.procGlowStyle or "glow")
    procStyleDrop:SetFullWidth(true)
    procStyleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.procGlowStyle = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(procStyleDrop)

    -- Color picker
    local procGlowColor = AceGUI:Create("ColorPicker")
    procGlowColor:SetLabel("Glow Color")
    procGlowColor:SetHasAlpha(true)
    local pgc = styleTable.procGlowColor or {1, 1, 1, 1}
    procGlowColor:SetColor(pgc[1], pgc[2], pgc[3], pgc[4])
    procGlowColor:SetFullWidth(true)
    procGlowColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.procGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    procGlowColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.procGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(procGlowColor)

    -- Size/thickness/speed sliders (conditional on style)
    local currentStyle = styleTable.procGlowStyle or "glow"
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 1)
        sizeSlider:SetValue(styleTable.procGlowSize or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "pixel" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Line Length")
        sizeSlider:SetSliderValues(1, 12, 1)
        sizeSlider:SetValue(styleTable.procGlowSize or 4)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 1)
        thicknessSlider:SetValue(styleTable.procGlowThickness or 2)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowThickness = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 5)
        speedSlider:SetValue(styleTable.procGlowSpeed or 60)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowSpeed = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "glow" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 1)
        sizeSlider:SetValue(styleTable.procGlowSize or 32)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.procGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    end
end

local function BuildPandemicGlowControls(container, styleTable, refreshCallback)
    -- Style dropdown
    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Glow Style")
    styleDrop:SetList({
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }, {"solid", "pixel", "glow"})
    styleDrop:SetValue(styleTable.pandemicGlowStyle or "solid")
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.pandemicGlowStyle = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(styleDrop)

    -- Color picker
    local colorPicker = AceGUI:Create("ColorPicker")
    colorPicker:SetLabel("Glow Color")
    colorPicker:SetHasAlpha(true)
    local c = styleTable.pandemicGlowColor or {1, 0.5, 0, 1}
    colorPicker:SetColor(c[1], c[2], c[3], c[4])
    colorPicker:SetFullWidth(true)
    colorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.pandemicGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    colorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.pandemicGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(colorPicker)

    -- Size/thickness/speed sliders (conditional on style)
    local currentStyle = styleTable.pandemicGlowStyle or "solid"
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 1)
        sizeSlider:SetValue(styleTable.pandemicGlowSize or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "pixel" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Line Length")
        sizeSlider:SetSliderValues(1, 12, 1)
        sizeSlider:SetValue(styleTable.pandemicGlowSize or 4)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 1)
        thicknessSlider:SetValue(styleTable.pandemicGlowThickness or 2)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowThickness = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 5)
        speedSlider:SetValue(styleTable.pandemicGlowSpeed or 60)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowSpeed = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "glow" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 1)
        sizeSlider:SetValue(styleTable.pandemicGlowSize or 32)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.pandemicGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    end
end

local function BuildPandemicBarControls(container, styleTable, refreshCallback)
    -- Pandemic bar color
    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel("Pandemic Bar Color")
    barColorPicker:SetHasAlpha(true)
    local bpc = styleTable.barPandemicColor or {1, 0.5, 0, 1}
    barColorPicker:SetColor(bpc[1], bpc[2], bpc[3], bpc[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barPandemicColor = {r, g, b, a}
        refreshCallback()
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barPandemicColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barColorPicker)

    -- Effect dropdown
    local effectDrop = AceGUI:Create("Dropdown")
    effectDrop:SetLabel("Pandemic Effect")
    effectDrop:SetList({
        ["none"] = "None",
        ["pixel"] = "Pixel Glow",
        ["solid"] = "Solid Border",
        ["glow"] = "Proc Glow",
    }, {"none", "pixel", "solid", "glow"})
    effectDrop:SetValue(styleTable.pandemicBarEffect or "none")
    effectDrop:SetFullWidth(true)
    effectDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.pandemicBarEffect = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(effectDrop)

    local currentEffect = styleTable.pandemicBarEffect or "none"
    if currentEffect ~= "none" then
        -- Effect color
        local effectColorPicker = AceGUI:Create("ColorPicker")
        effectColorPicker:SetLabel("Pandemic Effect Color")
        effectColorPicker:SetHasAlpha(true)
        local ec = styleTable.pandemicBarEffectColor or {1, 0.5, 0, 1}
        effectColorPicker:SetColor(ec[1], ec[2], ec[3], ec[4])
        effectColorPicker:SetFullWidth(true)
        effectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.pandemicBarEffectColor = {r, g, b, a}
            refreshCallback()
        end)
        effectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.pandemicBarEffectColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(effectColorPicker)

        -- Size/thickness/speed sliders (conditional on effect)
        if currentEffect == "solid" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Border Size")
            sizeSlider:SetSliderValues(1, 8, 1)
            sizeSlider:SetValue(styleTable.pandemicBarEffectSize or 2)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)
        elseif currentEffect == "pixel" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Line Length")
            sizeSlider:SetSliderValues(2, 12, 1)
            sizeSlider:SetValue(styleTable.pandemicBarEffectSize or 4)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)

            local thicknessSlider = AceGUI:Create("Slider")
            thicknessSlider:SetLabel("Line Thickness")
            thicknessSlider:SetSliderValues(1, 6, 1)
            thicknessSlider:SetValue(styleTable.pandemicBarEffectThickness or 2)
            thicknessSlider:SetFullWidth(true)
            thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectThickness = val
                refreshCallback()
            end)
            container:AddChild(thicknessSlider)

            local speedSlider = AceGUI:Create("Slider")
            speedSlider:SetLabel("Speed")
            speedSlider:SetSliderValues(10, 200, 5)
            speedSlider:SetValue(styleTable.pandemicBarEffectSpeed or 60)
            speedSlider:SetFullWidth(true)
            speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectSpeed = val
                refreshCallback()
            end)
            container:AddChild(speedSlider)
        elseif currentEffect == "glow" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Glow Size")
            sizeSlider:SetSliderValues(0, 60, 1)
            sizeSlider:SetValue(styleTable.pandemicBarEffectSize or 32)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.pandemicBarEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)
        end
    end
end

local function BuildAuraIndicatorControls(container, styleTable, refreshCallback)
    -- Style dropdown (no "none" — toggle handles enable/disable)
    local styleDrop = AceGUI:Create("Dropdown")
    styleDrop:SetLabel("Glow Style")
    styleDrop:SetList({
        ["solid"] = "Solid Border",
        ["pixel"] = "Pixel Glow",
        ["glow"] = "Glow",
    }, {"solid", "pixel", "glow"})
    styleDrop:SetValue(styleTable.auraGlowStyle or "pixel")
    styleDrop:SetFullWidth(true)
    styleDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.auraGlowStyle = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(styleDrop)

    -- Color picker
    local colorPicker = AceGUI:Create("ColorPicker")
    colorPicker:SetLabel("Indicator Color")
    colorPicker:SetHasAlpha(true)
    local c = styleTable.auraGlowColor or {1, 0.84, 0, 0.9}
    colorPicker:SetColor(c[1], c[2], c[3], c[4])
    colorPicker:SetFullWidth(true)
    colorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.auraGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    colorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.auraGlowColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(colorPicker)

    -- Size/thickness/speed sliders (conditional on style)
    local currentStyle = styleTable.auraGlowStyle or "pixel"
    if currentStyle == "solid" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Border Size")
        sizeSlider:SetSliderValues(1, 8, 1)
        sizeSlider:SetValue(styleTable.auraGlowSize or 2)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    elseif currentStyle == "pixel" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Line Length")
        sizeSlider:SetSliderValues(1, 12, 1)
        sizeSlider:SetValue(styleTable.auraGlowSize or 4)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)

        local thicknessSlider = AceGUI:Create("Slider")
        thicknessSlider:SetLabel("Line Thickness")
        thicknessSlider:SetSliderValues(1, 6, 1)
        thicknessSlider:SetValue(styleTable.auraGlowThickness or 2)
        thicknessSlider:SetFullWidth(true)
        thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowThickness = val
            refreshCallback()
        end)
        container:AddChild(thicknessSlider)

        local speedSlider = AceGUI:Create("Slider")
        speedSlider:SetLabel("Speed")
        speedSlider:SetSliderValues(10, 200, 5)
        speedSlider:SetValue(styleTable.auraGlowSpeed or 60)
        speedSlider:SetFullWidth(true)
        speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowSpeed = val
            refreshCallback()
        end)
        container:AddChild(speedSlider)
    elseif currentStyle == "glow" then
        local sizeSlider = AceGUI:Create("Slider")
        sizeSlider:SetLabel("Glow Size")
        sizeSlider:SetSliderValues(0, 60, 1)
        sizeSlider:SetValue(styleTable.auraGlowSize or 32)
        sizeSlider:SetFullWidth(true)
        sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.auraGlowSize = val
            refreshCallback()
        end)
        container:AddChild(sizeSlider)
    end
end

local function BuildBarActiveAuraControls(container, styleTable, refreshCallback)
    -- Bar aura color
    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel("Active Aura Bar Color")
    barColorPicker:SetHasAlpha(true)
    local bac = styleTable.barAuraColor or {0.2, 1.0, 0.2, 1.0}
    barColorPicker:SetColor(bac[1], bac[2], bac[3], bac[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barAuraColor = {r, g, b, a}
        refreshCallback()
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barAuraColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barColorPicker)

    -- Effect dropdown
    local effectDrop = AceGUI:Create("Dropdown")
    effectDrop:SetLabel("Active Aura Effect")
    effectDrop:SetList({
        ["none"] = "None",
        ["pixel"] = "Pixel Glow",
        ["solid"] = "Solid Border",
        ["glow"] = "Proc Glow",
    }, {"none", "pixel", "solid", "glow"})
    effectDrop:SetValue(styleTable.barAuraEffect or "none")
    effectDrop:SetFullWidth(true)
    effectDrop:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.barAuraEffect = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(effectDrop)

    local currentEffect = styleTable.barAuraEffect or "none"
    if currentEffect ~= "none" then
        -- Effect color
        local effectColorPicker = AceGUI:Create("ColorPicker")
        effectColorPicker:SetLabel("Effect Color")
        effectColorPicker:SetHasAlpha(true)
        local ec = styleTable.barAuraEffectColor or {1, 0.84, 0, 0.9}
        effectColorPicker:SetColor(ec[1], ec[2], ec[3], ec[4])
        effectColorPicker:SetFullWidth(true)
        effectColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.barAuraEffectColor = {r, g, b, a}
            refreshCallback()
        end)
        effectColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.barAuraEffectColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(effectColorPicker)

        -- Size/thickness/speed sliders (conditional on effect)
        if currentEffect == "solid" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Border Size")
            sizeSlider:SetSliderValues(1, 8, 1)
            sizeSlider:SetValue(styleTable.barAuraEffectSize or 2)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)
        elseif currentEffect == "pixel" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Line Length")
            sizeSlider:SetSliderValues(2, 12, 1)
            sizeSlider:SetValue(styleTable.barAuraEffectSize or 4)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)

            local thicknessSlider = AceGUI:Create("Slider")
            thicknessSlider:SetLabel("Line Thickness")
            thicknessSlider:SetSliderValues(1, 6, 1)
            thicknessSlider:SetValue(styleTable.barAuraEffectThickness or 2)
            thicknessSlider:SetFullWidth(true)
            thicknessSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectThickness = val
                refreshCallback()
            end)
            container:AddChild(thicknessSlider)

            local speedSlider = AceGUI:Create("Slider")
            speedSlider:SetLabel("Speed")
            speedSlider:SetSliderValues(10, 200, 5)
            speedSlider:SetValue(styleTable.barAuraEffectSpeed or 60)
            speedSlider:SetFullWidth(true)
            speedSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectSpeed = val
                refreshCallback()
            end)
            container:AddChild(speedSlider)
        elseif currentEffect == "glow" then
            local sizeSlider = AceGUI:Create("Slider")
            sizeSlider:SetLabel("Glow Size")
            sizeSlider:SetSliderValues(0, 60, 1)
            sizeSlider:SetValue(styleTable.barAuraEffectSize or 32)
            sizeSlider:SetFullWidth(true)
            sizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
                styleTable.barAuraEffectSize = val
                refreshCallback()
            end)
            container:AddChild(sizeSlider)
        end
    end
end

local function BuildBarColorsControls(container, styleTable, refreshCallback)
    local barColorPicker = AceGUI:Create("ColorPicker")
    barColorPicker:SetLabel("Bar Color")
    barColorPicker:SetHasAlpha(true)
    local brc = styleTable.barColor or {0.2, 0.6, 1.0, 1.0}
    barColorPicker:SetColor(brc[1], brc[2], brc[3], brc[4])
    barColorPicker:SetFullWidth(true)
    barColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barColor = {r, g, b, a}
        refreshCallback()
    end)
    barColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barColorPicker)

    local barCdColorPicker = AceGUI:Create("ColorPicker")
    barCdColorPicker:SetLabel("Bar Cooldown Color")
    barCdColorPicker:SetHasAlpha(true)
    local bcc = styleTable.barCooldownColor or {0.6, 0.6, 0.6, 1.0}
    barCdColorPicker:SetColor(bcc[1], bcc[2], bcc[3], bcc[4])
    barCdColorPicker:SetFullWidth(true)
    barCdColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barCooldownColor = {r, g, b, a}
        refreshCallback()
    end)
    barCdColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barCooldownColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barCdColorPicker)

    local barChargeColorPicker = AceGUI:Create("ColorPicker")
    barChargeColorPicker:SetLabel("Bar Recharging Color")
    barChargeColorPicker:SetHasAlpha(true)
    local bchc = styleTable.barChargeColor or {1.0, 0.82, 0.0, 1.0}
    barChargeColorPicker:SetColor(bchc[1], bchc[2], bchc[3], bchc[4])
    barChargeColorPicker:SetFullWidth(true)
    barChargeColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barChargeColor = {r, g, b, a}
        refreshCallback()
    end)
    barChargeColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barChargeColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barChargeColorPicker)

    local barBgColorPicker = AceGUI:Create("ColorPicker")
    barBgColorPicker:SetLabel("Bar Background Color")
    barBgColorPicker:SetHasAlpha(true)
    local bbg = styleTable.barBgColor or {0.1, 0.1, 0.1, 0.8}
    barBgColorPicker:SetColor(bbg[1], bbg[2], bbg[3], bbg[4])
    barBgColorPicker:SetFullWidth(true)
    barBgColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        styleTable.barBgColor = {r, g, b, a}
        refreshCallback()
    end)
    barBgColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        styleTable.barBgColor = {r, g, b, a}
        refreshCallback()
    end)
    container:AddChild(barBgColorPicker)
end

local function BuildBarNameTextControls(container, styleTable, refreshCallback)
    local showNameCb = AceGUI:Create("CheckBox")
    showNameCb:SetLabel("Show Name Text")
    showNameCb:SetValue(styleTable.showBarNameText ~= false)
    showNameCb:SetFullWidth(true)
    showNameCb:SetCallback("OnValueChanged", function(widget, event, val)
        styleTable.showBarNameText = val
        refreshCallback()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(showNameCb)

    if styleTable.showBarNameText ~= false then
        local flipNameCheck = AceGUI:Create("CheckBox")
        flipNameCheck:SetLabel("Flip Name Text")
        flipNameCheck:SetValue(styleTable.barNameTextReverse or false)
        flipNameCheck:SetFullWidth(true)
        flipNameCheck:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameTextReverse = val or nil
            refreshCallback()
        end)
        container:AddChild(flipNameCheck)

        local nameFontSizeSlider = AceGUI:Create("Slider")
        nameFontSizeSlider:SetLabel("Font Size")
        nameFontSizeSlider:SetSliderValues(6, 24, 1)
        nameFontSizeSlider:SetValue(styleTable.barNameFontSize or 10)
        nameFontSizeSlider:SetFullWidth(true)
        nameFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameFontSize = val
            refreshCallback()
        end)
        container:AddChild(nameFontSizeSlider)

        local nameFontDrop = AceGUI:Create("Dropdown")
        nameFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(nameFontDrop)
        nameFontDrop:SetValue(styleTable.barNameFont or "Friz Quadrata TT")
        nameFontDrop:SetFullWidth(true)
        nameFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameFont = val
            refreshCallback()
        end)
        container:AddChild(nameFontDrop)

        local nameOutlineDrop = AceGUI:Create("Dropdown")
        nameOutlineDrop:SetLabel("Font Outline")
        nameOutlineDrop:SetList(CS.outlineOptions)
        nameOutlineDrop:SetValue(styleTable.barNameFontOutline or "OUTLINE")
        nameOutlineDrop:SetFullWidth(true)
        nameOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barNameFontOutline = val
            refreshCallback()
        end)
        container:AddChild(nameOutlineDrop)

        local nameFontColor = AceGUI:Create("ColorPicker")
        nameFontColor:SetLabel("Font Color")
        nameFontColor:SetHasAlpha(true)
        local nfc = styleTable.barNameFontColor or {1, 1, 1, 1}
        nameFontColor:SetColor(nfc[1], nfc[2], nfc[3], nfc[4])
        nameFontColor:SetFullWidth(true)
        nameFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.barNameFontColor = {r, g, b, a}
            refreshCallback()
        end)
        nameFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.barNameFontColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(nameFontColor)
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
        CooldownCompanion:RefreshConfigPanel()
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

        local readyColorPicker = AceGUI:Create("ColorPicker")
        readyColorPicker:SetLabel("Ready Text Color")
        readyColorPicker:SetHasAlpha(true)
        local rtc = styleTable.barReadyTextColor or {0.2, 1.0, 0.2, 1.0}
        readyColorPicker:SetColor(rtc[1], rtc[2], rtc[3], rtc[4])
        readyColorPicker:SetFullWidth(true)
        readyColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            styleTable.barReadyTextColor = {r, g, b, a}
            refreshCallback()
        end)
        readyColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            styleTable.barReadyTextColor = {r, g, b, a}
            refreshCallback()
        end)
        container:AddChild(readyColorPicker)

        local readyFontSizeSlider = AceGUI:Create("Slider")
        readyFontSizeSlider:SetLabel("Font Size")
        readyFontSizeSlider:SetSliderValues(6, 24, 1)
        readyFontSizeSlider:SetValue(styleTable.barReadyFontSize or 12)
        readyFontSizeSlider:SetFullWidth(true)
        readyFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barReadyFontSize = val
            refreshCallback()
        end)
        container:AddChild(readyFontSizeSlider)

        local readyFontDrop = AceGUI:Create("Dropdown")
        readyFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(readyFontDrop)
        readyFontDrop:SetValue(styleTable.barReadyFont or "Friz Quadrata TT")
        readyFontDrop:SetFullWidth(true)
        readyFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barReadyFont = val
            refreshCallback()
        end)
        container:AddChild(readyFontDrop)

        local readyOutlineDrop = AceGUI:Create("Dropdown")
        readyOutlineDrop:SetLabel("Font Outline")
        readyOutlineDrop:SetList(CS.outlineOptions)
        readyOutlineDrop:SetValue(styleTable.barReadyFontOutline or "OUTLINE")
        readyOutlineDrop:SetFullWidth(true)
        readyOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            styleTable.barReadyFontOutline = val
            refreshCallback()
        end)
        container:AddChild(readyOutlineDrop)
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
        noOverridesLabel:SetText("|cff888888No appearance overrides.\n\nTo customize this button's appearance, select it and click the export icon next to a group settings section heading.|r")
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
        "borderSettings", "backgroundColor", "cooldownText", "auraText",
        "keybindText", "chargeText", "desaturation", "showGCDSwipe", "showOutOfRange", "showTooltips",
        "lossOfControl", "unusableDimming", "assistedHighlight", "procGlow", "pandemicGlow", "auraIndicator",
        "barColors", "barNameText", "barReadyText", "pandemicBar", "barActiveAura",
    }

    -- Map of section IDs to builder functions
    local sectionBuilders = {
        borderSettings = BuildBorderControls,
        backgroundColor = BuildBackgroundColorControls,
        cooldownText = BuildCooldownTextControls,
        auraText = BuildAuraTextControls,
        keybindText = BuildKeybindTextControls,
        chargeText = BuildChargeTextControls,
        desaturation = BuildDesaturationControls,
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

                local revertBtn = CreateRevertButton(heading, buttonData, sectionId)
                table.insert(infoButtons, revertBtn)

                local builder = sectionBuilders[sectionId]
                if builder then
                    builder(scroll, overrides, refreshCallback)
                end
            end
        end
    end
end

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

    -- Inline promote button for desaturation
    do
        local btnData = CS.selectedButton and group.buttons[CS.selectedButton]
        local desatPromote = CreateFrame("Button", nil, desatCb.frame)
        desatPromote:SetSize(16, 16)
        desatPromote:SetPoint("LEFT", desatCb.checkbg, "RIGHT", desatCb.text:GetStringWidth() + 20, 0)
        local desatPromoteIcon = desatPromote:CreateTexture(nil, "OVERLAY")
        desatPromoteIcon:SetSize(12, 12)
        desatPromoteIcon:SetPoint("CENTER")
        local multiCount = 0
        if CS.selectedButtons then
            for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        end
        local canPromote = CS.selectedButton ~= nil and multiCount < 2
            and btnData ~= nil
            and not (btnData.overrideSections and btnData.overrideSections.desaturation)
        if canPromote then
            desatPromoteIcon:SetAtlas("Crosshair_VehichleCursor_32")
            desatPromote:Enable()
        else
            desatPromoteIcon:SetAtlas("Crosshair_unableVehichleCursor_32")
            desatPromote:Disable()
        end
        desatPromote:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if canPromote then
                GameTooltip:AddLine("Override Desaturation for this button")
            else
                GameTooltip:AddLine("Select a button to add an override", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        desatPromote:SetScript("OnLeave", function() GameTooltip:Hide() end)
        desatPromote:SetScript("OnClick", function()
            if not canPromote then return end
            CooldownCompanion:PromoteSection(btnData, style, "desaturation")
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        table.insert(tabInfoButtons, desatPromote)
    end

    local gcdCb = AceGUI:Create("CheckBox")
    gcdCb:SetLabel(isBarMode and "Show GCD" or "Show GCD Swipe")
    gcdCb:SetValue(style.showGCDSwipe == true)
    gcdCb:SetFullWidth(true)
    gcdCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showGCDSwipe = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(gcdCb)

    -- Inline promote button for show GCD swipe
    do
        local btnData = CS.selectedButton and group.buttons[CS.selectedButton]
        local gcdPromote = CreateFrame("Button", nil, gcdCb.frame)
        gcdPromote:SetSize(16, 16)
        gcdPromote:SetPoint("LEFT", gcdCb.checkbg, "RIGHT", gcdCb.text:GetStringWidth() + 20, 0)
        local gcdPromoteIcon = gcdPromote:CreateTexture(nil, "OVERLAY")
        gcdPromoteIcon:SetSize(12, 12)
        gcdPromoteIcon:SetPoint("CENTER")
        local multiCount = 0
        if CS.selectedButtons then
            for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        end
        local canPromote = CS.selectedButton ~= nil and multiCount < 2
            and btnData ~= nil
            and not (btnData.overrideSections and btnData.overrideSections.showGCDSwipe)
        if canPromote then
            gcdPromoteIcon:SetAtlas("Crosshair_VehichleCursor_32")
            gcdPromote:Enable()
        else
            gcdPromoteIcon:SetAtlas("Crosshair_unableVehichleCursor_32")
            gcdPromote:Disable()
        end
        gcdPromote:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if canPromote then
                GameTooltip:AddLine("Override Show GCD Swipe for this button")
            else
                GameTooltip:AddLine("Select a button to add an override", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        gcdPromote:SetScript("OnLeave", function() GameTooltip:Hide() end)
        gcdPromote:SetScript("OnClick", function()
            if not canPromote then return end
            CooldownCompanion:PromoteSection(btnData, style, "showGCDSwipe")
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        table.insert(tabInfoButtons, gcdPromote)
    end

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

    -- Inline promote button for show out of range
    do
        local btnData = CS.selectedButton and group.buttons[CS.selectedButton]
        local rangePromote = CreateFrame("Button", nil, rangeCb.frame)
        rangePromote:SetSize(16, 16)
        rangePromote:SetPoint("LEFT", rangeInfo, "RIGHT", 4, 0)
        local rangePromoteIcon = rangePromote:CreateTexture(nil, "OVERLAY")
        rangePromoteIcon:SetSize(12, 12)
        rangePromoteIcon:SetPoint("CENTER")
        local multiCount = 0
        if CS.selectedButtons then
            for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        end
        local canPromote = CS.selectedButton ~= nil and multiCount < 2
            and btnData ~= nil
            and not (btnData.overrideSections and btnData.overrideSections.showOutOfRange)
        if canPromote then
            rangePromoteIcon:SetAtlas("Crosshair_VehichleCursor_32")
            rangePromote:Enable()
        else
            rangePromoteIcon:SetAtlas("Crosshair_unableVehichleCursor_32")
            rangePromote:Disable()
        end
        rangePromote:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if canPromote then
                GameTooltip:AddLine("Override Show Out of Range for this button")
            else
                GameTooltip:AddLine("Select a button to add an override", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        rangePromote:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rangePromote:SetScript("OnClick", function()
            if not canPromote then return end
            CooldownCompanion:PromoteSection(btnData, style, "showOutOfRange")
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        table.insert(tabInfoButtons, rangePromote)
    end

    local tooltipCb = AceGUI:Create("CheckBox")
    tooltipCb:SetLabel("Show Tooltips")
    tooltipCb:SetValue(style.showTooltips == true)
    tooltipCb:SetFullWidth(true)
    tooltipCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showTooltips = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(tooltipCb)

    -- Inline promote button for show tooltips
    do
        local btnData = CS.selectedButton and group.buttons[CS.selectedButton]
        local tooltipPromote = CreateFrame("Button", nil, tooltipCb.frame)
        tooltipPromote:SetSize(16, 16)
        tooltipPromote:SetPoint("LEFT", tooltipCb.checkbg, "RIGHT", tooltipCb.text:GetStringWidth() + 20, 0)
        local tooltipPromoteIcon = tooltipPromote:CreateTexture(nil, "OVERLAY")
        tooltipPromoteIcon:SetSize(12, 12)
        tooltipPromoteIcon:SetPoint("CENTER")
        local multiCount = 0
        if CS.selectedButtons then
            for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        end
        local canPromote = CS.selectedButton ~= nil and multiCount < 2
            and btnData ~= nil
            and not (btnData.overrideSections and btnData.overrideSections.showTooltips)
        if canPromote then
            tooltipPromoteIcon:SetAtlas("Crosshair_VehichleCursor_32")
            tooltipPromote:Enable()
        else
            tooltipPromoteIcon:SetAtlas("Crosshair_unableVehichleCursor_32")
            tooltipPromote:Disable()
        end
        tooltipPromote:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if canPromote then
                GameTooltip:AddLine("Override Show Tooltips for this button")
            else
                GameTooltip:AddLine("Select a button to add an override", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        tooltipPromote:SetScript("OnLeave", function() GameTooltip:Hide() end)
        tooltipPromote:SetScript("OnClick", function()
            if not canPromote then return end
            CooldownCompanion:PromoteSection(btnData, style, "showTooltips")
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        table.insert(tabInfoButtons, tooltipPromote)
    end

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

    -- Inline promote button for loss of control
    do
        local btnData = CS.selectedButton and group.buttons[CS.selectedButton]
        local locPromote = CreateFrame("Button", nil, locCb.frame)
        locPromote:SetSize(16, 16)
        locPromote:SetPoint("LEFT", locInfo, "RIGHT", 4, 0)
        local locPromoteIcon = locPromote:CreateTexture(nil, "OVERLAY")
        locPromoteIcon:SetSize(12, 12)
        locPromoteIcon:SetPoint("CENTER")
        local multiCount = 0
        if CS.selectedButtons then
            for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        end
        local canPromote = CS.selectedButton ~= nil and multiCount < 2
            and btnData ~= nil
            and not (btnData.overrideSections and btnData.overrideSections.lossOfControl)
        if canPromote then
            locPromoteIcon:SetAtlas("Crosshair_VehichleCursor_32")
            locPromote:Enable()
        else
            locPromoteIcon:SetAtlas("Crosshair_unableVehichleCursor_32")
            locPromote:Disable()
        end
        locPromote:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if canPromote then
                GameTooltip:AddLine("Override Loss of Control for this button")
            else
                GameTooltip:AddLine("Select a button to add an override", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        locPromote:SetScript("OnLeave", function() GameTooltip:Hide() end)
        locPromote:SetScript("OnClick", function()
            if not canPromote then return end
            CooldownCompanion:PromoteSection(btnData, style, "lossOfControl")
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        table.insert(tabInfoButtons, locPromote)
    end

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

    -- Inline promote button for unusable dimming
    do
        local btnData = CS.selectedButton and group.buttons[CS.selectedButton]
        local unusablePromote = CreateFrame("Button", nil, unusableCb.frame)
        unusablePromote:SetSize(16, 16)
        unusablePromote:SetPoint("LEFT", unusableInfo, "RIGHT", 4, 0)
        local unusablePromoteIcon = unusablePromote:CreateTexture(nil, "OVERLAY")
        unusablePromoteIcon:SetSize(12, 12)
        unusablePromoteIcon:SetPoint("CENTER")
        local multiCount = 0
        if CS.selectedButtons then
            for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        end
        local canPromote = CS.selectedButton ~= nil and multiCount < 2
            and btnData ~= nil
            and not (btnData.overrideSections and btnData.overrideSections.unusableDimming)
        if canPromote then
            unusablePromoteIcon:SetAtlas("Crosshair_VehichleCursor_32")
            unusablePromote:Enable()
        else
            unusablePromoteIcon:SetAtlas("Crosshair_unableVehichleCursor_32")
            unusablePromote:Disable()
        end
        unusablePromote:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if canPromote then
                GameTooltip:AddLine("Override Unusable Dimming for this button")
            else
                GameTooltip:AddLine("Select a button to add an override", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end)
        unusablePromote:SetScript("OnLeave", function() GameTooltip:Hide() end)
        unusablePromote:SetScript("OnClick", function()
            if not canPromote then return end
            CooldownCompanion:PromoteSection(btnData, style, "unusableDimming")
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
            CooldownCompanion:RefreshConfigPanel()
        end)
        table.insert(tabInfoButtons, unusablePromote)
    end

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

    -- Compact Layout section
    local compactHeading = AceGUI:Create("Heading")
    compactHeading:SetText("Compact Layout")
    ColorHeading(compactHeading)
    compactHeading:SetFullWidth(true)
    container:AddChild(compactHeading)

    local compactCb = AceGUI:Create("CheckBox")
    compactCb:SetLabel("Use Compact Layout")
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
    -- Assisted Highlight section
    local assistedHeading = AceGUI:Create("Heading")
    assistedHeading:SetText("Assisted Highlight")
    ColorHeading(assistedHeading)
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
    ColorHeading(alphaHeading)
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
        GameTooltip:AddLine("Controls the transparency of this group. Alpha = 1 is fully visible. Alpha = 0 means completely hidden.\n\nThe first three options (In Combat, Out of Combat, Mounted) are 3-way toggles — click to cycle through Disabled, |cff00ff00Fully Visible|r, and |cffff0000Fully Hidden|r.\n\n|cff00ff00Fully Visible|r overrides alpha to 1 when the condition is met.\n\n|cffff0000Fully Hidden|r overrides alpha to 0 when the condition is met.\n\nIf both apply simultaneously, |cff00ff00Fully Visible|r takes priority.", 1, 1, 1, true)
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
    container:AddChild(baseAlphaSlider)

    do
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
        ColorHeading(otherHeading)
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
    ColorHeading(strataHeading)
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

local LSM = LibStub("LibSharedMedia-3.0")

-- For resource bars: LSM textures + "Blizzard (Class)" special entry
local function GetResourceBarTextureOptions()
    local t = {}
    for _, name in ipairs(LSM:List("statusbar")) do
        t[name] = name
    end
    t["blizzard_class"] = "Blizzard (Class)"
    return t
end

-- For cast bars and bar-mode buttons: LSM textures only
local function GetBarTextureOptions()
    local t = {}
    for _, name in ipairs(LSM:List("statusbar")) do
        t[name] = name
    end
    return t
end

local function BuildBarAppearanceTab(container, group, style)
    -- Bar Settings header
    local barHeading = AceGUI:Create("Heading")
    barHeading:SetText("Bar Settings")
    ColorHeading(barHeading)
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

    -- Bar Colors heading
    local barColorsHeading = AceGUI:Create("Heading")
    barColorsHeading:SetText("Bar Colors")
    ColorHeading(barColorsHeading)
    barColorsHeading:SetFullWidth(true)
    container:AddChild(barColorsHeading)
    CreatePromoteButton(barColorsHeading, "barColors", CS.selectedButton and group.buttons[CS.selectedButton], style)

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

    local barTexDrop = AceGUI:Create("Dropdown")
    barTexDrop:SetLabel("Bar Texture")
    barTexDrop:SetList(GetBarTextureOptions())
    barTexDrop:SetValue(style.barTexture or "Solid")
    barTexDrop:SetFullWidth(true)
    barTexDrop:SetCallback("OnValueChanged", function(widget, event, val)
        style.barTexture = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barTexDrop)

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

    local barChargeColorPicker = AceGUI:Create("ColorPicker")
    barChargeColorPicker:SetLabel("Bar Recharging Color")
    barChargeColorPicker:SetHasAlpha(true)
    local bchc = style.barChargeColor or {1.0, 0.82, 0.0, 1.0}
    barChargeColorPicker:SetColor(bchc[1], bchc[2], bchc[3], bchc[4])
    barChargeColorPicker:SetFullWidth(true)
    barChargeColorPicker:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
        style.barChargeColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    barChargeColorPicker:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
        style.barChargeColor = {r, g, b, a}
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
    container:AddChild(barChargeColorPicker)

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
    ColorHeading(nameHeading)
    nameHeading:SetFullWidth(true)
    container:AddChild(nameHeading)
    CreatePromoteButton(nameHeading, "barNameText", CS.selectedButton and group.buttons[CS.selectedButton], style)

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
        CS.SetupFontDropdown(nameFontDrop)
        nameFontDrop:SetValue(style.barNameFont or "Friz Quadrata TT")
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
    ColorHeading(timeHeading)
    timeHeading:SetFullWidth(true)
    container:AddChild(timeHeading)
    CreatePromoteButton(timeHeading, "cooldownText", CS.selectedButton and group.buttons[CS.selectedButton], style)

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
        CS.SetupFontDropdown(fontDrop)
        fontDrop:SetValue(style.cooldownFont or "Friz Quadrata TT")
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

end

------------------------------------------------------------------------
-- EFFECTS TAB (Glows / Indicators)
------------------------------------------------------------------------
local function BuildBarEffectsTab(container, group, style)
    -- Active Aura Indicator section
    local barAuraHeading = AceGUI:Create("Heading")
    barAuraHeading:SetText("Active Aura Indicator")
    ColorHeading(barAuraHeading)
    barAuraHeading:SetFullWidth(true)
    container:AddChild(barAuraHeading)
    CreatePromoteButton(barAuraHeading, "barActiveAura", CS.selectedButton and group.buttons[CS.selectedButton], style)

    BuildBarActiveAuraControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    -- Aura Text section
    local auraTextHeading = AceGUI:Create("Heading")
    auraTextHeading:SetText("Aura Text")
    ColorHeading(auraTextHeading)
    auraTextHeading:SetFullWidth(true)
    container:AddChild(auraTextHeading)
    CreatePromoteButton(auraTextHeading, "auraText", CS.selectedButton and group.buttons[CS.selectedButton], style)

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
        CS.SetupFontDropdown(auraFontDrop)
        auraFontDrop:SetValue(style.auraTextFont or "Friz Quadrata TT")
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

    -- Pandemic Indicator section
    local pandemicBarHeading = AceGUI:Create("Heading")
    pandemicBarHeading:SetText("Pandemic Indicator")
    ColorHeading(pandemicBarHeading)
    pandemicBarHeading:SetFullWidth(true)
    container:AddChild(pandemicBarHeading)
    CreatePromoteButton(pandemicBarHeading, "pandemicBar", CS.selectedButton and group.buttons[CS.selectedButton], style)

    BuildPandemicBarControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    -- Ready Text heading
    local readyHeading = AceGUI:Create("Heading")
    readyHeading:SetText("Ready Text")
    ColorHeading(readyHeading)
    readyHeading:SetFullWidth(true)
    container:AddChild(readyHeading)
    CreatePromoteButton(readyHeading, "barReadyText", CS.selectedButton and group.buttons[CS.selectedButton], style)

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
        CS.SetupFontDropdown(readyFontDrop)
        readyFontDrop:SetValue(style.barReadyFont or "Friz Quadrata TT")
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

local function BuildEffectsTab(container)
    if not CS.selectedGroup then return end
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then return end
    local style = group.style

    -- Branch for bar mode
    if group.displayMode == "bars" then
        BuildBarEffectsTab(container, group, style)
        return
    end

    -- Icon mode: Glows tab

    -- Active Aura Glow section
    local auraIndicatorHeading = AceGUI:Create("Heading")
    auraIndicatorHeading:SetText("Active Aura Glow")
    ColorHeading(auraIndicatorHeading)
    auraIndicatorHeading:SetFullWidth(true)
    container:AddChild(auraIndicatorHeading)
    CreatePromoteButton(auraIndicatorHeading, "auraIndicator", CS.selectedButton and group.buttons[CS.selectedButton], style)

    BuildAuraIndicatorControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    -- Aura Text section
    local auraTextHeading = AceGUI:Create("Heading")
    auraTextHeading:SetText("Aura Text")
    ColorHeading(auraTextHeading)
    auraTextHeading:SetFullWidth(true)
    container:AddChild(auraTextHeading)
    CreatePromoteButton(auraTextHeading, "auraText", CS.selectedButton and group.buttons[CS.selectedButton], style)

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
        CS.SetupFontDropdown(auraFontDrop)
        auraFontDrop:SetValue(style.auraTextFont or "Friz Quadrata TT")
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

    -- Pandemic Glow section
    local pandemicGlowHeading = AceGUI:Create("Heading")
    pandemicGlowHeading:SetText("Pandemic Glow")
    ColorHeading(pandemicGlowHeading)
    pandemicGlowHeading:SetFullWidth(true)
    container:AddChild(pandemicGlowHeading)
    CreatePromoteButton(pandemicGlowHeading, "pandemicGlow", CS.selectedButton and group.buttons[CS.selectedButton], style)

    BuildPandemicGlowControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)

    -- Proc Glow section
    local procGlowHeading = AceGUI:Create("Heading")
    procGlowHeading:SetText("Proc Glow")
    ColorHeading(procGlowHeading)
    procGlowHeading:SetFullWidth(true)
    container:AddChild(procGlowHeading)
    CreatePromoteButton(procGlowHeading, "procGlow", CS.selectedButton and group.buttons[CS.selectedButton], style)

    BuildProcGlowControls(container, style, function()
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    end)
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
    ColorHeading(iconHeading)
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

    -- Border heading
    local borderHeading = AceGUI:Create("Heading")
    borderHeading:SetText("Border")
    ColorHeading(borderHeading)
    borderHeading:SetFullWidth(true)
    container:AddChild(borderHeading)
    CreatePromoteButton(borderHeading, "borderSettings", CS.selectedButton and group.buttons[CS.selectedButton], style)

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
    ColorHeading(textHeading)
    textHeading:SetFullWidth(true)
    container:AddChild(textHeading)
    CreatePromoteButton(textHeading, "cooldownText", CS.selectedButton and group.buttons[CS.selectedButton], style)

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
        CS.SetupFontDropdown(fontDrop)
        fontDrop:SetValue(style.cooldownFont or "Friz Quadrata TT")
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

    -- Keybind Text section
    local kbHeading = AceGUI:Create("Heading")
    kbHeading:SetText("Keybind Text")
    ColorHeading(kbHeading)
    kbHeading:SetFullWidth(true)
    container:AddChild(kbHeading)
    CreatePromoteButton(kbHeading, "keybindText", CS.selectedButton and group.buttons[CS.selectedButton], style)

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
        CS.SetupFontDropdown(kbFontDrop)
        kbFontDrop:SetValue(style.keybindFont or "Friz Quadrata TT")
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

    -- Charge Text section
    local chargeHeading = AceGUI:Create("Heading")
    chargeHeading:SetText("Charge Text")
    ColorHeading(chargeHeading)
    chargeHeading:SetFullWidth(true)
    container:AddChild(chargeHeading)
    CreatePromoteButton(chargeHeading, "chargeText", CS.selectedButton and group.buttons[CS.selectedButton], style)

    local chargeTextCb = AceGUI:Create("CheckBox")
    chargeTextCb:SetLabel("Show Charge Text")
    chargeTextCb:SetValue(style.showChargeText ~= false)
    chargeTextCb:SetFullWidth(true)
    chargeTextCb:SetCallback("OnValueChanged", function(widget, event, val)
        style.showChargeText = val
        CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(chargeTextCb)

    if style.showChargeText ~= false then
        local chargeFontSizeSlider = AceGUI:Create("Slider")
        chargeFontSizeSlider:SetLabel("Font Size")
        chargeFontSizeSlider:SetSliderValues(8, 32, 1)
        chargeFontSizeSlider:SetValue(style.chargeFontSize or 12)
        chargeFontSizeSlider:SetFullWidth(true)
        chargeFontSizeSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeFontSize = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontSizeSlider)

        local chargeFontDrop = AceGUI:Create("Dropdown")
        chargeFontDrop:SetLabel("Font")
        CS.SetupFontDropdown(chargeFontDrop)
        chargeFontDrop:SetValue(style.chargeFont or "Friz Quadrata TT")
        chargeFontDrop:SetFullWidth(true)
        chargeFontDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeFont = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontDrop)

        local chargeOutlineDrop = AceGUI:Create("Dropdown")
        chargeOutlineDrop:SetLabel("Font Outline")
        chargeOutlineDrop:SetList(CS.outlineOptions)
        chargeOutlineDrop:SetValue(style.chargeFontOutline or "OUTLINE")
        chargeOutlineDrop:SetFullWidth(true)
        chargeOutlineDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeFontOutline = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeOutlineDrop)

        local chargeFontColor = AceGUI:Create("ColorPicker")
        chargeFontColor:SetLabel("Font Color (Max Charges)")
        chargeFontColor:SetHasAlpha(true)
        local cfc = style.chargeFontColor or {1, 1, 1, 1}
        chargeFontColor:SetColor(cfc[1], cfc[2], cfc[3], cfc[4])
        chargeFontColor:SetFullWidth(true)
        chargeFontColor:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.chargeFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        chargeFontColor:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.chargeFontColor = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontColor)

        local chargeFontColorMissing = AceGUI:Create("ColorPicker")
        chargeFontColorMissing:SetLabel("Font Color (Missing Charges)")
        chargeFontColorMissing:SetHasAlpha(true)
        local cfcm = style.chargeFontColorMissing or {1, 1, 1, 1}
        chargeFontColorMissing:SetColor(cfcm[1], cfcm[2], cfcm[3], cfcm[4])
        chargeFontColorMissing:SetFullWidth(true)
        chargeFontColorMissing:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.chargeFontColorMissing = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        chargeFontColorMissing:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.chargeFontColorMissing = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontColorMissing)

        local chargeFontColorZero = AceGUI:Create("ColorPicker")
        chargeFontColorZero:SetLabel("Font Color (Zero Charges)")
        chargeFontColorZero:SetHasAlpha(true)
        local cfcz = style.chargeFontColorZero or {1, 1, 1, 1}
        chargeFontColorZero:SetColor(cfcz[1], cfcz[2], cfcz[3], cfcz[4])
        chargeFontColorZero:SetFullWidth(true)
        chargeFontColorZero:SetCallback("OnValueChanged", function(widget, event, r, g, b, a)
            style.chargeFontColorZero = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        chargeFontColorZero:SetCallback("OnValueConfirmed", function(widget, event, r, g, b, a)
            style.chargeFontColorZero = {r, g, b, a}
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeFontColorZero)

        local chargeAnchorValues = {}
        for _, pt in ipairs(CS.anchorPoints) do
            chargeAnchorValues[pt] = CS.anchorPointLabels[pt]
        end
        local chargeAnchorDrop = AceGUI:Create("Dropdown")
        chargeAnchorDrop:SetLabel("Anchor")
        chargeAnchorDrop:SetList(chargeAnchorValues, CS.anchorPoints)
        chargeAnchorDrop:SetValue(style.chargeAnchor or "BOTTOMRIGHT")
        chargeAnchorDrop:SetFullWidth(true)
        chargeAnchorDrop:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeAnchor = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeAnchorDrop)

        local chargeXSlider = AceGUI:Create("Slider")
        chargeXSlider:SetLabel("X Offset")
        chargeXSlider:SetSliderValues(-20, 20, 1)
        chargeXSlider:SetValue(style.chargeXOffset or -2)
        chargeXSlider:SetFullWidth(true)
        chargeXSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeXOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeXSlider)

        local chargeYSlider = AceGUI:Create("Slider")
        chargeYSlider:SetLabel("Y Offset")
        chargeYSlider:SetSliderValues(-20, 20, 1)
        chargeYSlider:SetValue(style.chargeYOffset or 2)
        chargeYSlider:SetFullWidth(true)
        chargeYSlider:SetCallback("OnValueChanged", function(widget, event, val)
            style.chargeYOffset = val
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end)
        container:AddChild(chargeYSlider)
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
    ColorHeading(heading)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    -- Hide While On Cooldown (skip for passives — no cooldown)
    if not buttonData.isPassive then
    local hideCDCb = AceGUI:Create("CheckBox")
    hideCDCb:SetLabel("Hide While On Cooldown")
    hideCDCb:SetValue(buttonData.hideWhileOnCooldown or false)
    hideCDCb:SetFullWidth(true)
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
    hideNotCDCb:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyToSelected("hideWhileNotOnCooldown", val or nil)
        if val then
            ApplyToSelected("hideWhileOnCooldown", nil)
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideNotCDCb)
    end -- not buttonData.isPassive

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
        GameTooltip:AddLine("Requires Aura Tracking to be enabled above.", 1, 1, 1, true)
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
        GameTooltip:AddLine("Requires Aura Tracking to be enabled above.", 1, 1, 1, true)
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
        warnLabel:SetText("|cffff8800Warning: Aura Tracking is not enabled. Enable it above for aura-based visibility to take effect.|r")
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
    ColorHeading(heading)
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
    ColorHeading(specHeading)
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
    ColorHeading(posHeading)
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
        ySlider:SetValue(settings.yOffset or 0)
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
    ColorHeading(fxHeading)
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
    styleCb:SetValue(settings.stylingEnabled ~= false)
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
    hSlider:SetValue(settings.height or 15)
    hSlider:SetFullWidth(true)
    hSlider:SetCallback("OnValueChanged", function(widget, event, val)
        settings.height = val
        CooldownCompanion:ApplyCastBarSettings()
    end)
    container:AddChild(hSlider)

    -- ============ Bar Visuals Section ============
    local visHeading = AceGUI:Create("Heading")
    visHeading:SetText("Bar Visuals")
    ColorHeading(visHeading)
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
        texDrop:SetList(GetBarTextureOptions())
        texDrop:SetValue(settings.barTexture or "Solid")
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
        iconCb:SetValue(settings.showIcon ~= false)
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
        borderDrop:SetValue(settings.borderStyle or "pixel")
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
    ColorHeading(nameHeading)
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
            CS.SetupFontDropdown(nameFontDrop)
            nameFontDrop:SetValue(settings.nameFont or "Friz Quadrata TT")
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
    ColorHeading(ctHeading)
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
            CS.SetupFontDropdown(ctFontDrop)
            ctFontDrop:SetValue(settings.castTimeFont or "Friz Quadrata TT")
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
    [8]  = "Astral Power",
    [9]  = "Holy Power",
    [11] = "Maelstrom",
    [12] = "Chi",
    [13] = "Insanity",
    [16] = "Arcane Charges",
    [17] = "Fury",
    [18] = "Pain",
    [19] = "Essence",
    [100] = "Maelstrom Weapon",
}

local DEFAULT_MW_BASE_COLOR_CONFIG = { 0, 0.5, 1 }
local DEFAULT_MW_OVERLAY_COLOR_CONFIG = { 1, 0.84, 0 }
local DEFAULT_MW_MAX_COLOR_CONFIG = { 0.5, 0.8, 1 }

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
local DEFAULT_COMBO_CHARGED_COLOR_CONFIG = { 0.24, 0.65, 1.0 }

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
    [263] = { 100, 0 },
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

    -- Inherit group alpha checkbox
    local alphaCb = AceGUI:Create("CheckBox")
    alphaCb:SetLabel("Inherit group alpha")
    alphaCb:SetValue(settings.inheritAlpha)
    alphaCb:SetFullWidth(true)
    alphaCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.inheritAlpha = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(alphaCb)

    -- ============ Position Section ============
    local posHeading = AceGUI:Create("Heading")
    posHeading:SetText("Position")
    ColorHeading(posHeading)
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
        ySlider:SetValue(settings.yOffset or -3)
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
        spacingSlider:SetValue(settings.barSpacing or 3.6)
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
    ColorHeading(stackHeading)
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
        stackDrop:SetValue(settings.stackOrder or "resource_first")
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
    ColorHeading(toggleHeading)
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
            manaCb:SetValue(settings.hideManaForNonHealer ~= false)
            manaCb:SetFullWidth(true)
            manaCb:SetCallback("OnValueChanged", function(widget, event, val)
                settings.hideManaForNonHealer = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(manaCb)
        end

        local flipCb = AceGUI:Create("CheckBox")
        flipCb:SetLabel("Flip primary and secondary bars")
        flipCb:SetValue(settings.reverseResourceOrder)
        flipCb:SetFullWidth(true)
        flipCb:SetCallback("OnValueChanged", function(widget, event, val)
            settings.reverseResourceOrder = val
            CooldownCompanion:ApplyResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
        end)
        container:AddChild(flipCb)

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
    texDrop:SetList(GetResourceBarTextureOptions())
    texDrop:SetValue(settings.barTexture or "Solid")
    texDrop:SetFullWidth(true)
    texDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.barTexture = val
        CooldownCompanion:ApplyResourceBars()
        -- Defer panel rebuild to next frame so it doesn't interfere with current callback
        C_Timer.After(0, function() CooldownCompanion:RefreshConfigPanel() end)
    end)
    container:AddChild(texDrop)

    -- Brightness slider (only for Blizzard Class texture)
    if settings.barTexture == "blizzard_class" then
        local brightSlider = AceGUI:Create("Slider")
        brightSlider:SetLabel("Class Texture Brightness")
        brightSlider:SetSliderValues(0.5, 2.0, 0.05)
        brightSlider:SetValue(settings.classBarBrightness or 1.3)
        brightSlider:SetFullWidth(true)
        brightSlider:SetCallback("OnValueChanged", function(widget, event, val)
            settings.classBarBrightness = val
            CooldownCompanion:ApplyResourceBars()
        end)
        container:AddChild(brightSlider)
    end

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
    ColorHeading(borderHeading)
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
    gapSlider:SetValue(settings.segmentGap or 4)
    gapSlider:SetFullWidth(true)
    gapSlider:SetCallback("OnValueChanged", function(widget, event, val)
        settings.segmentGap = val
        CooldownCompanion:ApplyResourceBars()
    end)
    container:AddChild(gapSlider)

    -- ============ Text Section ============
    local textHeading = AceGUI:Create("Heading")
    textHeading:SetText("Text")
    ColorHeading(textHeading)
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
        CS.SetupFontDropdown(fontDrop)
        fontDrop:SetValue(settings.textFont or "Friz Quadrata TT")
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
    ColorHeading(colorHeading)
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

                -- Charged combo point color (Rogue only)
                local _, _, classID = UnitClass("player")
                if classID == 4 then
                    local chargedColor = settings.resources[4].comboChargedColor or DEFAULT_COMBO_CHARGED_COLOR_CONFIG
                    local cpCharged = AceGUI:Create("ColorPicker")
                    cpCharged:SetLabel("Combo Points (Charged)")
                    cpCharged:SetColor(chargedColor[1], chargedColor[2], chargedColor[3])
                    cpCharged:SetHasAlpha(false)
                    cpCharged:SetFullWidth(true)
                    cpCharged:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                        if not settings.resources[4] then settings.resources[4] = {} end
                        settings.resources[4].comboChargedColor = {r, g, b}
                    end)
                    cpCharged:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                        if not settings.resources[4] then settings.resources[4] = {} end
                        settings.resources[4].comboChargedColor = {r, g, b}
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(cpCharged)
                end
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
            elseif pt == 100 then
                -- Maelstrom Weapon: three color pickers (base, overlay, max)
                local baseColor = settings.resources[100].mwBaseColor or DEFAULT_MW_BASE_COLOR_CONFIG
                local cpBase = AceGUI:Create("ColorPicker")
                cpBase:SetLabel("MW (Base)")
                cpBase:SetColor(baseColor[1], baseColor[2], baseColor[3])
                cpBase:SetHasAlpha(false)
                cpBase:SetFullWidth(true)
                cpBase:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwBaseColor = {r, g, b}
                end)
                cpBase:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwBaseColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpBase)

                local overlayColor = settings.resources[100].mwOverlayColor or DEFAULT_MW_OVERLAY_COLOR_CONFIG
                local cpOverlay = AceGUI:Create("ColorPicker")
                cpOverlay:SetLabel("MW (Overlay)")
                cpOverlay:SetColor(overlayColor[1], overlayColor[2], overlayColor[3])
                cpOverlay:SetHasAlpha(false)
                cpOverlay:SetFullWidth(true)
                cpOverlay:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwOverlayColor = {r, g, b}
                end)
                cpOverlay:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwOverlayColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpOverlay)

                local mwMaxColor = settings.resources[100].mwMaxColor or DEFAULT_MW_MAX_COLOR_CONFIG
                local cpMax = AceGUI:Create("ColorPicker")
                cpMax:SetLabel("MW (Max)")
                cpMax:SetColor(mwMaxColor[1], mwMaxColor[2], mwMaxColor[3])
                cpMax:SetHasAlpha(false)
                cpMax:SetFullWidth(true)
                cpMax:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwMaxColor = {r, g, b}
                end)
                cpMax:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    if not settings.resources[100] then settings.resources[100] = {} end
                    settings.resources[100].mwMaxColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpMax)
            else
                local name = POWER_NAMES_CONFIG[pt] or ("Power " .. pt)

                if settings.barTexture == "blizzard_class" and ST.POWER_ATLAS_TYPES and ST.POWER_ATLAS_TYPES[pt] then
                    -- Atlas-backed type; color picker not applicable
                else
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

end

------------------------------------------------------------------------
-- Custom Aura Bar Panel (col2 takeover when resource bar panel active)
------------------------------------------------------------------------

BuildCustomAuraBarPanel = function(container)
    auraBarAutocompleteCache = nil
    local db = CooldownCompanion.db.profile
    local settings = db.resourceBars
    local customBars = CooldownCompanion:GetSpecCustomAuraBars()
    local maxSlots = ST.MAX_CUSTOM_AURA_BARS or 3

    -- Spec label
    local specIdx = C_SpecializationInfo.GetSpecialization()
    if specIdx then
        local _, specName, _, specIcon = C_SpecializationInfo.GetSpecializationInfo(specIdx)
        if specName then
            local specLabel = AceGUI:Create("Label")
            specLabel:SetText("|T" .. specIcon .. ":14:14:0:0|t  Configuring: |cffffd100" .. specName .. "|r")
            specLabel:SetFullWidth(true)
            specLabel:SetFontObject(GameFontNormal)
            container:AddChild(specLabel)

            local spacer = AceGUI:Create("Label")
            spacer:SetText(" ")
            spacer:SetFullWidth(true)
            container:AddChild(spacer)
        end
    end

    for slotIdx = 1, maxSlots do
        if not customBars[slotIdx] then
            customBars[slotIdx] = { enabled = false }
        end
        local cab = customBars[slotIdx]

        local slotKey = "rb_cab_slot_" .. slotIdx
        local slotCollapsed = resourceBarCollapsedSections[slotKey]
        local slotHeadingText = "Slot " .. slotIdx
        if cab.enabled then
            local slotLabel = cab.label or ""
            if cab.spellID then
                local spellName = C_Spell.GetSpellName(cab.spellID)
                if spellName then slotLabel = spellName end
            end
            if slotLabel == "" then slotLabel = "Empty" end
            slotHeadingText = slotHeadingText .. ": " .. slotLabel
        end

        local slotHeading = AceGUI:Create("Heading")
        slotHeading:SetText(slotHeadingText)
        ColorHeading(slotHeading)
        slotHeading:SetFullWidth(true)
        container:AddChild(slotHeading)

        local slotCollapseBtn = CreateFrame("Button", nil, slotHeading.frame)
        slotCollapseBtn:SetSize(16, 16)
        slotCollapseBtn:SetPoint("LEFT", slotHeading.label, "RIGHT", 4, 0)
        slotHeading.right:SetPoint("LEFT", slotCollapseBtn, "RIGHT", 4, 0)
        local slotArrow = slotCollapseBtn:CreateTexture(nil, "ARTWORK")
        slotArrow:SetSize(12, 12)
        slotArrow:SetPoint("CENTER")
        slotArrow:SetAtlas(slotCollapsed and "glues-characterSelect-icon-arrowUp-small" or "glues-characterSelect-icon-arrowDown-small")
        local capturedSlotKey = slotKey
        slotCollapseBtn:SetScript("OnClick", function()
            resourceBarCollapsedSections[capturedSlotKey] = not resourceBarCollapsedSections[capturedSlotKey]
            CooldownCompanion:RefreshConfigPanel()
        end)

        if not slotCollapsed then
            local capturedIdx = slotIdx

            -- Enable checkbox
            local enableCab = AceGUI:Create("CheckBox")
            enableCab:SetLabel("Enable")
            enableCab:SetValue(cab.enabled == true)
            enableCab:SetFullWidth(true)
            enableCab:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[capturedIdx].enabled = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(enableCab)

            if cab.enabled then

            -- Spell ID edit box with autocomplete
            local spellEdit = AceGUI:Create("EditBox")
            if spellEdit.editbox.Instructions then spellEdit.editbox.Instructions:Hide() end
            spellEdit:SetLabel("Spell ID or Name")
            spellEdit:SetText(cab.spellID and tostring(cab.spellID) or "")
            spellEdit:SetFullWidth(true)
            spellEdit:DisableButton(true)

            -- Autocomplete: onSelect closure for this slot
            local function onAuraBarSelect(entry)
                CS.HideAutocomplete()
                local bars = CooldownCompanion:GetSpecCustomAuraBars()
                bars[capturedIdx].spellID = entry.id
                bars[capturedIdx].label = C_Spell.GetSpellName(entry.id) or ""
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end

            spellEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                if CS.ConsumeAutocompleteEnter() then return end
                CS.HideAutocomplete()
                text = text:gsub("%s", "")
                local id = tonumber(text)
                local bars = CooldownCompanion:GetSpecCustomAuraBars()
                bars[capturedIdx].spellID = id
                if id then
                    bars[capturedIdx].label = C_Spell.GetSpellName(id) or ""
                else
                    bars[capturedIdx].label = ""
                end
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            spellEdit:SetCallback("OnTextChanged", function(widget, event, text)
                if text and #text >= 1 then
                    local cache = auraBarAutocompleteCache or BuildAuraBarAutocompleteCache()
                    local results = CS.SearchAutocompleteInCache(text, cache)
                    CS.ShowAutocompleteResults(results, widget, onAuraBarSelect)
                else
                    CS.HideAutocomplete()
                end
            end)

            local editboxFrame = spellEdit.editbox
            if not editboxFrame._cdcAutocompHooked then
                editboxFrame._cdcAutocompHooked = true
                editboxFrame:HookScript("OnKeyDown", function(self, key)
                    CS.HandleAutocompleteKeyDown(key)
                end)
            end

            container:AddChild(spellEdit)

            -- Label (read-only display)
            if cab.spellID then
                local spellName = C_Spell.GetSpellName(cab.spellID)
                if spellName then
                    local labelDisplay = AceGUI:Create("Label")
                    labelDisplay:SetText("|cff888888" .. spellName .. "|r")
                    labelDisplay:SetFullWidth(true)
                    container:AddChild(labelDisplay)
                end
            end

            -- Tracking Mode dropdown
            local trackDrop = AceGUI:Create("Dropdown")
            trackDrop:SetLabel("Tracking Mode")
            trackDrop:SetList({
                stacks = "Stack Count",
                active = "Active (On/Off)",
            }, { "stacks", "active" })
            trackDrop:SetValue(cab.trackingMode or "stacks")
            trackDrop:SetFullWidth(true)
            trackDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[capturedIdx].trackingMode = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(trackDrop)

            -- Max Stacks editbox (hidden in "active" tracking mode)
            if (cab.trackingMode or "stacks") ~= "active" then
            local maxEdit = AceGUI:Create("EditBox")
            if maxEdit.editbox.Instructions then maxEdit.editbox.Instructions:Hide() end
            maxEdit:SetLabel("Max Stacks")
            maxEdit:SetText(tostring(cab.maxStacks or 1))
            maxEdit:SetFullWidth(true)
            maxEdit:SetCallback("OnEnterPressed", function(widget, event, text)
                local val = tonumber(text)
                if val and val >= 1 and val <= 99 then
                    customBars[capturedIdx].maxStacks = val
                end
                widget:SetText(tostring(customBars[capturedIdx].maxStacks or 1))
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
            end)
            container:AddChild(maxEdit)
            end

            -- Display Mode dropdown (hidden in "active" tracking mode)
            if (cab.trackingMode or "stacks") ~= "active" then
            local modeDrop = AceGUI:Create("Dropdown")
            modeDrop:SetLabel("Display Mode")
            modeDrop:SetList({
                continuous = "Continuous",
                segmented = "Segmented",
                overlay = "Overlay",
            }, { "continuous", "segmented", "overlay" })
            modeDrop:SetValue(cab.displayMode or "segmented")
            modeDrop:SetFullWidth(true)
            modeDrop:SetCallback("OnValueChanged", function(widget, event, val)
                customBars[capturedIdx].displayMode = val
                CooldownCompanion:ApplyResourceBars()
                CooldownCompanion:UpdateAnchorStacking()
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(modeDrop)
            end

            -- ---- Colors section (only when has spell ID) ----
            if cab.spellID then
                local colorHeading = AceGUI:Create("Heading")
                colorHeading:SetText("Colors")
                ColorHeading(colorHeading)
                colorHeading:SetFullWidth(true)
                container:AddChild(colorHeading)

                -- Bar Color (all modes)
                local barColor = cab.barColor or {0.5, 0.5, 1}
                local cpBar = AceGUI:Create("ColorPicker")
                cpBar:SetLabel("Bar Color")
                cpBar:SetColor(barColor[1], barColor[2], barColor[3])
                cpBar:SetHasAlpha(false)
                cpBar:SetFullWidth(true)
                local cabIdx = capturedIdx
                cpBar:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                    customBars[cabIdx].barColor = {r, g, b}
                    CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx])
                end)
                cpBar:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                    customBars[cabIdx].barColor = {r, g, b}
                    CooldownCompanion:ApplyResourceBars()
                end)
                container:AddChild(cpBar)

                -- Overlay Color (overlay mode only)
                if cab.displayMode == "overlay" then
                    local overlayColor = cab.overlayColor or {1, 0.84, 0}
                    local cpOverlay = AceGUI:Create("ColorPicker")
                    cpOverlay:SetLabel("Overlay Color")
                    cpOverlay:SetColor(overlayColor[1], overlayColor[2], overlayColor[3])
                    cpOverlay:SetHasAlpha(false)
                    cpOverlay:SetFullWidth(true)
                    cpOverlay:SetCallback("OnValueChanged", function(widget, event, r, g, b)
                        customBars[cabIdx].overlayColor = {r, g, b}
                        CooldownCompanion:RecolorCustomAuraBar(customBars[cabIdx])
                    end)
                    cpOverlay:SetCallback("OnValueConfirmed", function(widget, event, r, g, b)
                        customBars[cabIdx].overlayColor = {r, g, b}
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(cpOverlay)
                end

                -- Show Text checkbox (continuous mode only)
                if cab.displayMode == "continuous" then
                    local textCb = AceGUI:Create("CheckBox")
                    textCb:SetLabel("Show Text")
                    textCb:SetValue(cab.showText == true)
                    textCb:SetFullWidth(true)
                    textCb:SetCallback("OnValueChanged", function(widget, event, val)
                        customBars[cabIdx].showText = val
                        CooldownCompanion:ApplyResourceBars()
                    end)
                    container:AddChild(textCb)
                end
            end
            end -- if cab.enabled
        end
    end

    -- "Copy from..." button
    local _, _, classID = UnitClass("player")
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
    local currentSpecID
    if specIdx then
        currentSpecID = C_SpecializationInfo.GetSpecializationInfo(specIdx)
    end
    if currentSpecID and numSpecs and numSpecs > 1 then
        local copySpacer = AceGUI:Create("Label")
        copySpacer:SetText(" ")
        copySpacer:SetFullWidth(true)
        container:AddChild(copySpacer)

        local copyBtn = AceGUI:Create("Button")
        copyBtn:SetText("Copy from\226\128\166")
        copyBtn:SetFullWidth(true)
        copyBtn:SetCallback("OnClick", function()
            local menuFrame = _G["CDCCopyCABMenu"]
            if not menuFrame then
                menuFrame = CreateFrame("Frame", "CDCCopyCABMenu", UIParent, "UIDropDownMenuTemplate")
            end
            UIDropDownMenu_Initialize(menuFrame, function(self, level)
                for i = 1, numSpecs do
                    local sID, sName, _, sIcon = GetSpecializationInfoForClassID(classID, i)
                    if sID and sID ~= currentSpecID then
                        local info = UIDropDownMenu_CreateInfo()
                        local sourceBars = settings.customAuraBars and settings.customAuraBars[sID]
                        local hasData = false
                        if sourceBars then
                            for _, cab in ipairs(sourceBars) do
                                if cab.enabled and cab.spellID then hasData = true; break end
                            end
                        end
                        info.text = "|T" .. sIcon .. ":14:14:0:0|t " .. sName
                        info.disabled = not hasData
                        info.func = function()
                            settings.customAuraBars[currentSpecID] = CopyTable(sourceBars)
                            CooldownCompanion:ApplyResourceBars()
                            CooldownCompanion:UpdateAnchorStacking()
                            CooldownCompanion:RefreshConfigPanel()
                            CloseDropDownMenus()
                        end
                        UIDropDownMenu_AddButton(info, level)
                    end
                end
            end, "MENU")
            menuFrame:SetFrameStrata("FULLSCREEN_DIALOG")
            ToggleDropDownMenu(1, nil, menuFrame, "cursor", 0, 0)
        end)
        container:AddChild(copyBtn)
    end
end

------------------------------------------------------------------------
-- Frame Anchoring panels
------------------------------------------------------------------------

local ANCHOR_POINTS = {
    "TOPLEFT", "TOP", "TOPRIGHT",
    "LEFT", "CENTER", "RIGHT",
    "BOTTOMLEFT", "BOTTOM", "BOTTOMRIGHT",
}
local ANCHOR_POINT_LABELS = {}
for _, p in ipairs(ANCHOR_POINTS) do ANCHOR_POINT_LABELS[p] = p end

local MIRROR_POINTS = {
    LEFT         = "RIGHT",
    RIGHT        = "LEFT",
    TOPLEFT      = "TOPRIGHT",
    TOPRIGHT     = "TOPLEFT",
    BOTTOMLEFT   = "BOTTOMRIGHT",
    BOTTOMRIGHT  = "BOTTOMLEFT",
    TOP          = "TOP",
    BOTTOM       = "BOTTOM",
    CENTER       = "CENTER",
}

local UNIT_FRAME_OPTIONS = {
    [""]         = "Auto-detect",
    blizzard     = "Blizzard Default",
    uuf          = "UnhaltedUnitFrames",
    elvui        = "ElvUI",
    custom       = "Custom",
}
local UNIT_FRAME_ORDER = { "", "blizzard", "uuf", "elvui", "custom" }

BuildFrameAnchoringPlayerPanel = function(container)
    local db = CooldownCompanion.db.profile
    local settings = db.frameAnchoring

    -- Enable Frame Anchoring
    local enableCb = AceGUI:Create("CheckBox")
    enableCb:SetLabel("Enable Frame Anchoring")
    enableCb:SetValue(settings.enabled)
    enableCb:SetFullWidth(true)
    enableCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.enabled = val
        CooldownCompanion:EvaluateFrameAnchoring()
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
        CooldownCompanion:EvaluateFrameAnchoring()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(anchorDrop)

    if #groupDropOrder <= 1 then
        local noGroupsLabel = AceGUI:Create("Label")
        noGroupsLabel:SetText("No icon groups are currently enabled for this spec. Enable an icon group to anchor here.")
        noGroupsLabel:SetFullWidth(true)
        container:AddChild(noGroupsLabel)
    end

    -- Unit Frames dropdown
    local ufDrop = AceGUI:Create("Dropdown")
    ufDrop:SetLabel("Unit Frames")
    ufDrop:SetList(UNIT_FRAME_OPTIONS, UNIT_FRAME_ORDER)
    ufDrop:SetValue(settings.unitFrameAddon or "")
    ufDrop:SetFullWidth(true)
    ufDrop:SetCallback("OnValueChanged", function(widget, event, val)
        settings.unitFrameAddon = val ~= "" and val or nil
        CooldownCompanion:EvaluateFrameAnchoring()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(ufDrop)

    -- Custom frame name editboxes (only when "Custom" selected)
    if settings.unitFrameAddon == "custom" then
        -- Player frame row (editbox + pick button)
        local playerRow = AceGUI:Create("SimpleGroup")
        playerRow:SetFullWidth(true)
        playerRow:SetLayout("Flow")

        local playerEdit = AceGUI:Create("EditBox")
        playerEdit:SetLabel("Player Frame Name")
        playerEdit:SetText(settings.customPlayerFrame or "")
        playerEdit:SetRelativeWidth(0.68)
        playerEdit:SetCallback("OnEnterPressed", function(widget, event, text)
            settings.customPlayerFrame = text
            CooldownCompanion:EvaluateFrameAnchoring()
        end)
        playerRow:AddChild(playerEdit)

        local playerPickBtn = AceGUI:Create("Button")
        playerPickBtn:SetText("Pick")
        playerPickBtn:SetRelativeWidth(0.24)
        playerPickBtn:SetCallback("OnClick", function()
            CS.StartPickFrame(function(name)
                if CS.configFrame then
                    CS.configFrame.frame:Show()
                end
                if name then
                    settings.customPlayerFrame = name
                    CooldownCompanion:EvaluateFrameAnchoring()
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
        end)
        playerRow:AddChild(playerPickBtn)

        container:AddChild(playerRow)

        -- Target frame row (editbox + pick button)
        local targetRow = AceGUI:Create("SimpleGroup")
        targetRow:SetFullWidth(true)
        targetRow:SetLayout("Flow")

        local targetEdit = AceGUI:Create("EditBox")
        targetEdit:SetLabel("Target Frame Name")
        targetEdit:SetText(settings.customTargetFrame or "")
        targetEdit:SetRelativeWidth(0.68)
        targetEdit:SetCallback("OnEnterPressed", function(widget, event, text)
            settings.customTargetFrame = text
            CooldownCompanion:EvaluateFrameAnchoring()
        end)
        targetRow:AddChild(targetEdit)

        local targetPickBtn = AceGUI:Create("Button")
        targetPickBtn:SetText("Pick")
        targetPickBtn:SetRelativeWidth(0.24)
        targetPickBtn:SetCallback("OnClick", function()
            CS.StartPickFrame(function(name)
                if CS.configFrame then
                    CS.configFrame.frame:Show()
                end
                if name then
                    settings.customTargetFrame = name
                    CooldownCompanion:EvaluateFrameAnchoring()
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
        end)
        targetRow:AddChild(targetPickBtn)

        container:AddChild(targetRow)
    end

    -- Mirroring checkbox
    local mirrorCb = AceGUI:Create("CheckBox")
    mirrorCb:SetLabel("Mirror target from player")
    mirrorCb:SetValue(settings.mirroring)
    mirrorCb:SetFullWidth(true)
    mirrorCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.mirroring = val
        CooldownCompanion:ApplyFrameAnchoring()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(mirrorCb)

    -- Inherit group alpha checkbox
    local alphaCb = AceGUI:Create("CheckBox")
    alphaCb:SetLabel("Inherit group alpha")
    alphaCb:SetValue(settings.inheritAlpha)
    alphaCb:SetFullWidth(true)
    alphaCb:SetCallback("OnValueChanged", function(widget, event, val)
        settings.inheritAlpha = val
        CooldownCompanion:ApplyFrameAnchoring()
    end)
    container:AddChild(alphaCb)

    -- Player Frame section heading
    local playerHeading = AceGUI:Create("Heading")
    playerHeading:SetText("Player Frame Position")
    ColorHeading(playerHeading)
    playerHeading:SetFullWidth(true)
    container:AddChild(playerHeading)

    local ps = settings.player

    -- Anchor Point
    local apDrop = AceGUI:Create("Dropdown")
    apDrop:SetLabel("Anchor Point")
    apDrop:SetList(ANCHOR_POINT_LABELS, ANCHOR_POINTS)
    apDrop:SetValue(ps.anchorPoint or "RIGHT")
    apDrop:SetFullWidth(true)
    apDrop:SetCallback("OnValueChanged", function(widget, event, val)
        ps.anchorPoint = val
        CooldownCompanion:ApplyFrameAnchoring()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(apDrop)

    -- Relative Anchor Point
    local rpDrop = AceGUI:Create("Dropdown")
    rpDrop:SetLabel("Relative Anchor Point")
    rpDrop:SetList(ANCHOR_POINT_LABELS, ANCHOR_POINTS)
    rpDrop:SetValue(ps.relativePoint or "LEFT")
    rpDrop:SetFullWidth(true)
    rpDrop:SetCallback("OnValueChanged", function(widget, event, val)
        ps.relativePoint = val
        CooldownCompanion:ApplyFrameAnchoring()
        CooldownCompanion:RefreshConfigPanel()
    end)
    container:AddChild(rpDrop)

    -- X Offset
    local xSlider = AceGUI:Create("Slider")
    xSlider:SetLabel("X Offset")
    xSlider:SetSliderValues(-200, 200, 0.1)
    xSlider:SetValue(ps.xOffset or 0)
    xSlider:SetFullWidth(true)
    xSlider:SetCallback("OnValueChanged", function(widget, event, val)
        ps.xOffset = val
        CooldownCompanion:ApplyFrameAnchoring()
    end)
    container:AddChild(xSlider)

    -- Y Offset
    local ySlider = AceGUI:Create("Slider")
    ySlider:SetLabel("Y Offset")
    ySlider:SetSliderValues(-200, 200, 0.1)
    ySlider:SetValue(ps.yOffset or 0)
    ySlider:SetFullWidth(true)
    ySlider:SetCallback("OnValueChanged", function(widget, event, val)
        ps.yOffset = val
        CooldownCompanion:ApplyFrameAnchoring()
    end)
    container:AddChild(ySlider)
end

BuildFrameAnchoringTargetPanel = function(container)
    local db = CooldownCompanion.db.profile
    local settings = db.frameAnchoring

    if not settings.enabled then
        local disabledLabel = AceGUI:Create("Label")
        disabledLabel:SetText("Enable Frame Anchoring in the Player Frame column to configure target settings.")
        disabledLabel:SetFullWidth(true)
        container:AddChild(disabledLabel)
        return
    end

    if settings.mirroring then
        local infoLabel = AceGUI:Create("Label")
        infoLabel:SetText("Target frame is mirrored from player frame settings.")
        infoLabel:SetFullWidth(true)
        container:AddChild(infoLabel)
    else
        -- Independent target settings
        local targetHeading = AceGUI:Create("Heading")
        targetHeading:SetText("Target Frame Position")
        ColorHeading(targetHeading)
        targetHeading:SetFullWidth(true)
        container:AddChild(targetHeading)

        local ts = settings.target

        -- Anchor Point
        local apDrop = AceGUI:Create("Dropdown")
        apDrop:SetLabel("Anchor Point")
        apDrop:SetList(ANCHOR_POINT_LABELS, ANCHOR_POINTS)
        apDrop:SetValue(ts.anchorPoint or "LEFT")
        apDrop:SetFullWidth(true)
        apDrop:SetCallback("OnValueChanged", function(widget, event, val)
            ts.anchorPoint = val
            CooldownCompanion:ApplyFrameAnchoring()
        end)
        container:AddChild(apDrop)

        -- Relative Anchor Point
        local rpDrop = AceGUI:Create("Dropdown")
        rpDrop:SetLabel("Relative Anchor Point")
        rpDrop:SetList(ANCHOR_POINT_LABELS, ANCHOR_POINTS)
        rpDrop:SetValue(ts.relativePoint or "RIGHT")
        rpDrop:SetFullWidth(true)
        rpDrop:SetCallback("OnValueChanged", function(widget, event, val)
            ts.relativePoint = val
            CooldownCompanion:ApplyFrameAnchoring()
        end)
        container:AddChild(rpDrop)

        -- X Offset
        local xSlider = AceGUI:Create("Slider")
        xSlider:SetLabel("X Offset")
        xSlider:SetSliderValues(-200, 200, 0.1)
        xSlider:SetValue(ts.xOffset or 0)
        xSlider:SetFullWidth(true)
        xSlider:SetCallback("OnValueChanged", function(widget, event, val)
            ts.xOffset = val
            CooldownCompanion:ApplyFrameAnchoring()
        end)
        container:AddChild(xSlider)

        -- Y Offset
        local ySlider = AceGUI:Create("Slider")
        ySlider:SetLabel("Y Offset")
        ySlider:SetSliderValues(-200, 200, 0.1)
        ySlider:SetValue(ts.yOffset or 0)
        ySlider:SetFullWidth(true)
        ySlider:SetCallback("OnValueChanged", function(widget, event, val)
            ts.yOffset = val
            CooldownCompanion:ApplyFrameAnchoring()
        end)
        container:AddChild(ySlider)
    end
end

------------------------------------------------------------------------
-- CUSTOM NAME SECTION (bar groups only)
------------------------------------------------------------------------
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

-- Expose builder functions for Config.lua to call
ST._BuildSpellSettings = BuildSpellSettings
ST._BuildItemSettings = BuildItemSettings
ST._BuildEquipItemSettings = BuildEquipItemSettings
ST._RefreshButtonSettingsColumn = RefreshButtonSettingsColumn
ST._RefreshButtonSettingsMultiSelect = RefreshButtonSettingsMultiSelect
ST._BuildVisibilitySettings = BuildVisibilitySettings
ST._BuildCustomNameSection = BuildCustomNameSection
ST._BuildAppearanceTab = BuildAppearanceTab
ST._BuildPositioningTab = BuildPositioningTab
ST._BuildExtrasTab = BuildExtrasTab
ST._BuildEffectsTab = BuildEffectsTab
ST._BuildLoadConditionsTab = BuildLoadConditionsTab
ST._BuildCastBarAnchoringPanel = BuildCastBarAnchoringPanel
ST._BuildCastBarStylingPanel = BuildCastBarStylingPanel
ST._BuildResourceBarAnchoringPanel = BuildResourceBarAnchoringPanel
ST._BuildResourceBarStylingPanel = BuildResourceBarStylingPanel
ST._BuildCustomAuraBarPanel = BuildCustomAuraBarPanel
ST._BuildFrameAnchoringPlayerPanel = BuildFrameAnchoringPlayerPanel
ST._BuildFrameAnchoringTargetPanel = BuildFrameAnchoringTargetPanel
ST._BuildOverridesTab = BuildOverridesTab