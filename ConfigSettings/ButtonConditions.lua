--[[
    CooldownCompanion - ConfigSettings/ButtonConditions.lua: Per-button visibility settings and
    group-level load conditions
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua and State.lua
local BuildHeroTalentSubTreeCheckboxes = ST._BuildHeroTalentSubTreeCheckboxes
local ColorHeading = ST._ColorHeading
local AttachCollapseButton = ST._AttachCollapseButton
local CreateInfoButton = ST._CreateInfoButton

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
    CreateInfoButton(hideUnusableCb.frame, hideUnusableCb.checkbg, "LEFT", "RIGHT", hideUnusableCb.text:GetStringWidth() + 4, 0, {
        "Hide While Unusable",
        {"Uses the same logic as unusable dimming, but completely hides the button instead of dimming it.", 1, 1, 1, true},
    }, infoButtons)

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
                CreateInfoButton(fallbackZeroChargesCb.frame, fallbackZeroChargesCb.checkbg, "LEFT", "RIGHT", fallbackZeroChargesCb.text:GetStringWidth() + 4, 0, {
                    "Use Baseline Alpha Fallback",
                    {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
                }, infoButtons)
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
                CreateInfoButton(fallbackZeroStacksCb.frame, fallbackZeroStacksCb.checkbg, "LEFT", "RIGHT", fallbackZeroStacksCb.text:GetStringWidth() + 4, 0, {
                    "Use Baseline Alpha Fallback",
                    {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
                }, infoButtons)
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
            CreateInfoButton(fallbackNotEquippedCb.frame, fallbackNotEquippedCb.checkbg, "LEFT", "RIGHT", fallbackNotEquippedCb.text:GetStringWidth() + 4, 0, {
                "Use Baseline Alpha Fallback",
                {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
            }, infoButtons)
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
    CreateInfoButton(hideAuraCb.frame, hideAuraCb.checkbg, "LEFT", "RIGHT", hideAuraCb.text:GetStringWidth() + 4, 0, {
        "Hide While Aura Active",
        {"Requires Aura Tracking to be enabled above.", 1, 1, 1, true},
    }, infoButtons)

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
        CreateInfoButton(fallbackAuraCb.frame, fallbackAuraCb.checkbg, "LEFT", "RIGHT", fallbackAuraCb.text:GetStringWidth() + 4, 0, {
            "Use Baseline Alpha Fallback",
            {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
        }, infoButtons)
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
    CreateInfoButton(hideNoAuraCb.frame, hideNoAuraCb.checkbg, "LEFT", "RIGHT", hideNoAuraCb.text:GetStringWidth() + 4, 0, {
        "Hide While Aura Not Active",
        {"Requires Aura Tracking to be enabled above.", 1, 1, 1, true},
    }, infoButtons)

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
        CreateInfoButton(desatNoAuraCb.frame, desatNoAuraCb.checkbg, "LEFT", "RIGHT", desatNoAuraCb.text:GetStringWidth() + 4, 0, {
            "Desaturate While Aura Not Active",
            {"Requires Aura Tracking to be enabled above.", 1, 1, 1, true},
        }, infoButtons)
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
        CreateInfoButton(fallbackCb.frame, fallbackCb.checkbg, "LEFT", "RIGHT", fallbackCb.text:GetStringWidth() + 4, 0, {
            "Use Baseline Alpha Fallback",
            {"Instead of fully hiding, show the button dimmed at the group's baseline alpha. The button keeps its layout position.", 1, 1, 1, true},
        }, infoButtons)
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
            BuildHeroTalentSubTreeCheckboxes(container, group, configID, specId, 20, groupId)
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
