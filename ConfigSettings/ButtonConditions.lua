--[[
    CooldownCompanion - ConfigSettings/ButtonConditions.lua: Per-button visibility settings and
    group-level load conditions
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton

local tabInfoButtons = CS.tabInfoButtons
local appearanceTabElements = CS.appearanceTabElements

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

    local visKey = CS.selectedGroup .. "_" .. CS.selectedButton .. "_visibility"
    local visCollapsed = CS.collapsedSections[visKey]
    local visCollapseBtn = AttachCollapseButton(heading, visCollapsed, function()
        CS.collapsedSections[visKey] = not CS.collapsedSections[visKey]
        CooldownCompanion:RefreshConfigPanel()
    end)


    if not visCollapsed then
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

    -- Hide While Unusable
    local hideUnusableCb = AceGUI:Create("CheckBox")
    hideUnusableCb:SetLabel("Hide While Unusable")
    hideUnusableCb:SetValue(buttonData.hideWhileUnusable or false)
    hideUnusableCb:SetFullWidth(true)
    hideUnusableCb:SetCallback("OnValueChanged", function(widget, event, val)
        ApplyToSelected("hideWhileUnusable", val or nil)
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(hideUnusableCb)

    -- (?) tooltip
    local hideUnusableInfo = CreateFrame("Button", nil, hideUnusableCb.frame)
    hideUnusableInfo:SetSize(16, 16)
    hideUnusableInfo:SetPoint("LEFT", hideUnusableCb.checkbg, "RIGHT", hideUnusableCb.text:GetStringWidth() + 4, 0)
    local hideUnusableInfoIcon = hideUnusableInfo:CreateTexture(nil, "OVERLAY")
    hideUnusableInfoIcon:SetSize(12, 12)
    hideUnusableInfoIcon:SetPoint("CENTER")
    hideUnusableInfoIcon:SetAtlas("QuestRepeatableTurnin")
    hideUnusableInfo:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Hide While Unusable")
        GameTooltip:AddLine("Uses the same logic as unusable dimming, but completely hides the button instead of dimming it.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    hideUnusableInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
    table.insert(infoButtons, hideUnusableInfo)
    if CooldownCompanion.db.profile.hideInfoButtons then
        hideUnusableInfo:Hide()
    end

    end -- not buttonData.isPassive

    -- Item-specific zero charges/stacks visibility toggles
    if isItem and not CooldownCompanion.IsItemEquippable(buttonData) then
        if buttonData.hasCharges then
            -- Hide While At Zero Charges
            local hideZeroChargesCb = AceGUI:Create("CheckBox")
            hideZeroChargesCb:SetLabel("Hide While At Zero Charges")
            hideZeroChargesCb:SetValue(buttonData.hideWhileZeroCharges or false)
            hideZeroChargesCb:SetFullWidth(true)
            hideZeroChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
                ApplyToSelected("hideWhileZeroCharges", val or nil)
                if val then
                    ApplyToSelected("desaturateWhileZeroCharges", nil)
                else
                    ApplyToSelected("useBaselineAlphaFallbackZeroCharges", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(hideZeroChargesCb)

            -- Baseline Alpha Fallback (nested under hideWhileZeroCharges)
            if buttonData.hideWhileZeroCharges then
                local fallbackZeroChargesCb = AceGUI:Create("CheckBox")
                fallbackZeroChargesCb:SetLabel("Use Baseline Alpha Fallback")
                fallbackZeroChargesCb:SetValue(buttonData.useBaselineAlphaFallbackZeroCharges or false)
                fallbackZeroChargesCb:SetFullWidth(true)
                fallbackZeroChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
                    ApplyToSelected("useBaselineAlphaFallbackZeroCharges", val or nil)
                end)
                scroll:AddChild(fallbackZeroChargesCb)

                -- (?) tooltip
                local fallbackZCInfo = CreateFrame("Button", nil, fallbackZeroChargesCb.frame)
                fallbackZCInfo:SetSize(16, 16)
                fallbackZCInfo:SetPoint("LEFT", fallbackZeroChargesCb.checkbg, "RIGHT", fallbackZeroChargesCb.text:GetStringWidth() + 4, 0)
                local fallbackZCInfoIcon = fallbackZCInfo:CreateTexture(nil, "OVERLAY")
                fallbackZCInfoIcon:SetSize(12, 12)
                fallbackZCInfoIcon:SetPoint("CENTER")
                fallbackZCInfoIcon:SetAtlas("QuestRepeatableTurnin")
                fallbackZCInfo:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Use Baseline Alpha Fallback")
                    GameTooltip:AddLine("Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                fallbackZCInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
                table.insert(infoButtons, fallbackZCInfo)
                if CooldownCompanion.db.profile.hideInfoButtons then
                    fallbackZCInfo:Hide()
                end
            end

            -- Desaturate While At Zero Charges
            local desatZeroChargesCb = AceGUI:Create("CheckBox")
            desatZeroChargesCb:SetLabel("Desaturate While At Zero Charges")
            desatZeroChargesCb:SetValue(buttonData.desaturateWhileZeroCharges or false)
            desatZeroChargesCb:SetFullWidth(true)
            desatZeroChargesCb:SetCallback("OnValueChanged", function(widget, event, val)
                ApplyToSelected("desaturateWhileZeroCharges", val or nil)
                if val then
                    ApplyToSelected("hideWhileZeroCharges", nil)
                    ApplyToSelected("useBaselineAlphaFallbackZeroCharges", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(desatZeroChargesCb)
        else
            -- Stack-based items
            -- Hide While At Zero Stacks
            local hideZeroStacksCb = AceGUI:Create("CheckBox")
            hideZeroStacksCb:SetLabel("Hide While At Zero Stacks")
            hideZeroStacksCb:SetValue(buttonData.hideWhileZeroStacks or false)
            hideZeroStacksCb:SetFullWidth(true)
            hideZeroStacksCb:SetCallback("OnValueChanged", function(widget, event, val)
                ApplyToSelected("hideWhileZeroStacks", val or nil)
                if val then
                    ApplyToSelected("desaturateWhileZeroStacks", nil)
                else
                    ApplyToSelected("useBaselineAlphaFallbackZeroStacks", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(hideZeroStacksCb)

            -- Baseline Alpha Fallback (nested under hideWhileZeroStacks)
            if buttonData.hideWhileZeroStacks then
                local fallbackZeroStacksCb = AceGUI:Create("CheckBox")
                fallbackZeroStacksCb:SetLabel("Use Baseline Alpha Fallback")
                fallbackZeroStacksCb:SetValue(buttonData.useBaselineAlphaFallbackZeroStacks or false)
                fallbackZeroStacksCb:SetFullWidth(true)
                fallbackZeroStacksCb:SetCallback("OnValueChanged", function(widget, event, val)
                    ApplyToSelected("useBaselineAlphaFallbackZeroStacks", val or nil)
                end)
                scroll:AddChild(fallbackZeroStacksCb)

                -- (?) tooltip
                local fallbackZSInfo = CreateFrame("Button", nil, fallbackZeroStacksCb.frame)
                fallbackZSInfo:SetSize(16, 16)
                fallbackZSInfo:SetPoint("LEFT", fallbackZeroStacksCb.checkbg, "RIGHT", fallbackZeroStacksCb.text:GetStringWidth() + 4, 0)
                local fallbackZSInfoIcon = fallbackZSInfo:CreateTexture(nil, "OVERLAY")
                fallbackZSInfoIcon:SetSize(12, 12)
                fallbackZSInfoIcon:SetPoint("CENTER")
                fallbackZSInfoIcon:SetAtlas("QuestRepeatableTurnin")
                fallbackZSInfo:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:AddLine("Use Baseline Alpha Fallback")
                    GameTooltip:AddLine("Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true)
                    GameTooltip:Show()
                end)
                fallbackZSInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
                table.insert(infoButtons, fallbackZSInfo)
                if CooldownCompanion.db.profile.hideInfoButtons then
                    fallbackZSInfo:Hide()
                end
            end

            -- Desaturate While At Zero Stacks
            local desatZeroStacksCb = AceGUI:Create("CheckBox")
            desatZeroStacksCb:SetLabel("Desaturate While At Zero Stacks")
            desatZeroStacksCb:SetValue(buttonData.desaturateWhileZeroStacks or false)
            desatZeroStacksCb:SetFullWidth(true)
            desatZeroStacksCb:SetCallback("OnValueChanged", function(widget, event, val)
                ApplyToSelected("desaturateWhileZeroStacks", val or nil)
                if val then
                    ApplyToSelected("hideWhileZeroStacks", nil)
                    ApplyToSelected("useBaselineAlphaFallbackZeroStacks", nil)
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
            scroll:AddChild(desatZeroStacksCb)
        end
    end

    -- Hide While Not Equipped (equippable items only)
    if isItem and CooldownCompanion.IsItemEquippable(buttonData) then
        local hideNotEquippedCb = AceGUI:Create("CheckBox")
        hideNotEquippedCb:SetLabel("Hide While Not Equipped")
        hideNotEquippedCb:SetValue(buttonData.hideWhileNotEquipped or false)
        hideNotEquippedCb:SetFullWidth(true)
        hideNotEquippedCb:SetCallback("OnValueChanged", function(widget, event, val)
            ApplyToSelected("hideWhileNotEquipped", val or nil)
            if not val then
                ApplyToSelected("useBaselineAlphaFallbackNotEquipped", nil)
            end
            CooldownCompanion:RefreshConfigPanel()
        end)
        scroll:AddChild(hideNotEquippedCb)

        -- Baseline Alpha Fallback (nested under hideWhileNotEquipped)
        if buttonData.hideWhileNotEquipped then
            local fallbackNotEquippedCb = AceGUI:Create("CheckBox")
            fallbackNotEquippedCb:SetLabel("Use Baseline Alpha Fallback")
            fallbackNotEquippedCb:SetValue(buttonData.useBaselineAlphaFallbackNotEquipped or false)
            fallbackNotEquippedCb:SetFullWidth(true)
            fallbackNotEquippedCb:SetCallback("OnValueChanged", function(widget, event, val)
                ApplyToSelected("useBaselineAlphaFallbackNotEquipped", val or nil)
            end)
            scroll:AddChild(fallbackNotEquippedCb)

            -- (?) tooltip
            local fallbackNEInfo = CreateFrame("Button", nil, fallbackNotEquippedCb.frame)
            fallbackNEInfo:SetSize(16, 16)
            fallbackNEInfo:SetPoint("LEFT", fallbackNotEquippedCb.checkbg, "RIGHT", fallbackNotEquippedCb.text:GetStringWidth() + 4, 0)
            local fallbackNEInfoIcon = fallbackNEInfo:CreateTexture(nil, "OVERLAY")
            fallbackNEInfoIcon:SetSize(12, 12)
            fallbackNEInfoIcon:SetPoint("CENTER")
            fallbackNEInfoIcon:SetAtlas("QuestRepeatableTurnin")
            fallbackNEInfo:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine("Use Baseline Alpha Fallback")
                GameTooltip:AddLine("Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true)
                GameTooltip:Show()
            end)
            fallbackNEInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
            table.insert(infoButtons, fallbackNEInfo)
            if CooldownCompanion.db.profile.hideInfoButtons then
                fallbackNEInfo:Hide()
            end
        end
    end

    -- Hide While Aura Active (not applicable for items)
    if not isItem then
    local auraDisabled = not buttonData.auraTracking
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

    -- Desaturate While Aura Not Active (spell+aura only; passive buttons always desaturate)
    if not buttonData.isPassive then
        local desatNoAuraCb = AceGUI:Create("CheckBox")
        desatNoAuraCb:SetLabel("Desaturate While Aura Not Active")
        desatNoAuraCb:SetValue(buttonData.desaturateWhileAuraNotActive or false)
        desatNoAuraCb:SetFullWidth(true)
        if auraDisabled then
            desatNoAuraCb:SetDisabled(true)
        end
        desatNoAuraCb:SetCallback("OnValueChanged", function(widget, event, val)
            ApplyToSelected("desaturateWhileAuraNotActive", val or nil)
        end)
        scroll:AddChild(desatNoAuraCb)

        -- (?) tooltip
        local desatNoAuraInfo = CreateFrame("Button", nil, desatNoAuraCb.frame)
        desatNoAuraInfo:SetSize(16, 16)
        desatNoAuraInfo:SetPoint("LEFT", desatNoAuraCb.checkbg, "RIGHT", desatNoAuraCb.text:GetStringWidth() + 4, 0)
        local desatNoAuraInfoIcon = desatNoAuraInfo:CreateTexture(nil, "OVERLAY")
        desatNoAuraInfoIcon:SetSize(12, 12)
        desatNoAuraInfoIcon:SetPoint("CENTER")
        desatNoAuraInfoIcon:SetAtlas("QuestRepeatableTurnin")
        desatNoAuraInfo:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine("Desaturate While Aura Not Active")
            GameTooltip:AddLine("Requires Aura Tracking to be enabled above.", 1, 1, 1, true)
            GameTooltip:Show()
        end)
        desatNoAuraInfo:SetScript("OnLeave", function() GameTooltip:Hide() end)
        table.insert(infoButtons, desatNoAuraInfo)
        if CooldownCompanion.db.profile.hideInfoButtons then
            desatNoAuraInfo:Hide()
        end
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
    end -- not isItem

    end -- not visCollapsed

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

    local instanceCollapsed = CS.collapsedSections["loadconditions_instance"]
    AttachCollapseButton(heading, instanceCollapsed, function()
        CS.collapsedSections["loadconditions_instance"] = not CS.collapsedSections["loadconditions_instance"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not instanceCollapsed then
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
    end -- not instanceCollapsed

    -- Specialization heading
    local specHeading = AceGUI:Create("Heading")
    specHeading:SetText("Specialization Filter")
    ColorHeading(specHeading)
    specHeading:SetFullWidth(true)
    container:AddChild(specHeading)

    local specCollapsed = CS.collapsedSections["loadconditions_spec"]
    AttachCollapseButton(specHeading, specCollapsed, function()
        CS.collapsedSections["loadconditions_spec"] = not CS.collapsedSections["loadconditions_spec"]
        CooldownCompanion:RefreshConfigPanel()
    end)

    if not specCollapsed then
    -- Current class spec checkboxes
    local numSpecs = GetNumSpecializations()
    local configID = C_ClassTalents.GetActiveConfigID()
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
                    CooldownCompanion:CleanHeroTalentsForSpec(group, specId)
                end
                CooldownCompanion:RefreshGroupFrame(groupId)
                CooldownCompanion:RefreshConfigPanel()
            end)
            container:AddChild(cb)
            cb.checkbg:SetPoint("TOPLEFT")

            -- Hero talent sub-tree checkboxes (indented, only when spec is checked)
            if group.specs and group.specs[specId] and configID then
                local subTreeIDs = C_ClassTalents.GetHeroTalentSpecsForClassSpec(nil, specId)
                if subTreeIDs then
                    for _, subTreeID in ipairs(subTreeIDs) do
                        local subTreeInfo = C_Traits.GetSubTreeInfo(configID, subTreeID)
                        if subTreeInfo then
                            local htCb = AceGUI:Create("CheckBox")
                            htCb:SetLabel(subTreeInfo.name or ("Hero " .. subTreeID))
                            htCb:SetFullWidth(true)
                            htCb:SetValue(group.heroTalents and group.heroTalents[subTreeID] or false)
                            -- Indent the checkbox
                            htCb:SetCallback("OnValueChanged", function(widget, event, value)
                                if value then
                                    if not group.heroTalents then group.heroTalents = {} end
                                    group.heroTalents[subTreeID] = true
                                else
                                    if group.heroTalents then
                                        group.heroTalents[subTreeID] = nil
                                        if not next(group.heroTalents) then
                                            group.heroTalents = nil
                                        end
                                    end
                                end
                                CooldownCompanion:RefreshGroupFrame(groupId)
                                CooldownCompanion:RefreshConfigPanel()
                            end)
                            container:AddChild(htCb)
                            htCb.checkbg:SetPoint("TOPLEFT", 20, 0)
                            -- Set hero talent atlas icon
                            if subTreeInfo.iconElementID then
                                htCb:SetImage(136235)  -- placeholder fileID for layout
                                htCb.image:SetAtlas(subTreeInfo.iconElementID, false)
                                htCb.image:SetTexCoord(0, 1, 0, 1)
                            end
                        end
                    end
                end
            end
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
                fcb.checkbg:SetPoint("TOPLEFT")
            end
        end
    end
    end -- not specCollapsed
end


------------------------------------------------------------------------
-- EXPORTS
------------------------------------------------------------------------
ST._BuildVisibilitySettings = BuildVisibilitySettings
ST._BuildLoadConditionsTab = BuildLoadConditionsTab
