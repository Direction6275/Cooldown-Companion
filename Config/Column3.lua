--[[
    CooldownCompanion - Config/Column3
    RefreshColumn3 (button settings / custom aura bars column).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

local RenderAutoAddFlow = ST._RenderAutoAddFlow

------------------------------------------------------------------------
-- COLUMN 3: Button Settings (normal) / Custom Aura Bars (bars mode)
------------------------------------------------------------------------
local function RefreshColumn3()
    -- Cross-character browse mode: show placeholder
    if CS.browseMode then
        local col3 = CS.configFrame and CS.configFrame.col3
        if col3 then
            if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
            if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
            if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
            if col3._autoAddScroll then col3._autoAddScroll.frame:Hide() end
            if col3._panelTabGroup then col3._panelTabGroup.frame:Hide() end
            if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
            if col3._customAuraScroll then col3._customAuraScroll.frame:Hide() end
            -- Show a browse mode label
            if not col3._browsePlaceholder then
                col3._browsePlaceholder = col3.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                col3._browsePlaceholder:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 4, -4)
            end
            local charName = CS.browseCharKey and (CS.browseCharKey:match("^(.-)%s*%-") or CS.browseCharKey) or "..."
            col3._browsePlaceholder:SetText("Browsing " .. charName .. "'s groups")
            col3._browsePlaceholder:Show()
        end
        return
    end
    -- Hide browse placeholder when not in browse mode
    local col3BrowseClean = CS.configFrame and CS.configFrame.col3
    if col3BrowseClean and col3BrowseClean._browsePlaceholder then
        col3BrowseClean._browsePlaceholder:Hide()
    end

    -- Bars & Frames panel mode: show Custom Aura Bars
    if CS.resourceBarPanelActive then
        if CS.autoAddFlowActive and ST._CancelAutoAddFlow then
            ST._CancelAutoAddFlow()
        end
        local col3 = CS.configFrame and CS.configFrame.col3
        if not col3 then ST._RefreshButtonSettingsColumn() return end
        local maxCustomAuraTabs = ST.MAX_CUSTOM_AURA_BARS or 3

        -- Hide button settings content that lives on the same col3 content area
        if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
        if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
        if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
        if col3._autoAddScroll then col3._autoAddScroll.frame:Hide() end
        if col3._panelTabGroup then col3._panelTabGroup.frame:Hide() end

        -- Create/show custom aura tab group
        if col3._customAuraScroll then
            col3._customAuraScroll.frame:Hide()
        end
        if not col3._customAuraTabGroup then
            local customAuraTabs = {}
            for slotIdx = 1, maxCustomAuraTabs do
                customAuraTabs[#customAuraTabs + 1] = {
                    value = "bar_" .. slotIdx,
                    text = "Bar " .. slotIdx,
                }
            end
            local tabGroup = AceGUI:Create("TabGroup")
            tabGroup:SetTabs(customAuraTabs)
            tabGroup:SetLayout("Fill")
            tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                CS.customAuraBarTab = tab
                widget:ReleaseChildren()

                local scroll = AceGUI:Create("ScrollFrame")
                scroll:SetLayout("List")
                widget:AddChild(scroll)
                col3._customAuraSubScroll = scroll

                local selectedSlot = tonumber((tab or ""):match("^bar_(%d+)$")) or 1
                ST._BuildCustomAuraBarPanel(scroll, selectedSlot)
            end)
            tabGroup.frame:SetParent(col3.content)
            col3._customAuraTabGroup = tabGroup
        end

        col3._customAuraTabGroup.frame:ClearAllPoints()
        col3._customAuraTabGroup.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
        col3._customAuraTabGroup.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)

        local selectedTab = tostring(CS.customAuraBarTab or "bar_1")
        local selectedSlot = tonumber(selectedTab:match("^bar_(%d+)$"))
        if not selectedSlot or selectedSlot < 1 or selectedSlot > maxCustomAuraTabs then
            selectedTab = "bar_1"
            CS.customAuraBarTab = selectedTab
        end
        col3._customAuraTabGroup.frame:Show()
        col3._customAuraTabGroup:SelectTab(selectedTab)
        return
    end

    -- Normal mode: hide custom aura panel
    local col3Normal = CS.configFrame and CS.configFrame.col3
    if col3Normal and col3Normal._customAuraTabGroup then
        col3Normal._customAuraTabGroup.frame:Hide()
    end
    if col3Normal then
        col3Normal._customAuraSubScroll = nil
    end
    if col3Normal and col3Normal._customAuraScroll then
        col3Normal._customAuraScroll.frame:Hide()
    end

    if CS.autoAddFlowActive and CS.autoAddFlowState then
        local flowState = CS.autoAddFlowState
        local group = flowState.groupID and CooldownCompanion.db.profile.groups[flowState.groupID]
        if not group or CS.selectedGroup ~= flowState.groupID or next(CS.selectedGroups) then
            if ST._CancelAutoAddFlow then
                ST._CancelAutoAddFlow()
            end
        else
            if col3Normal then
                if col3Normal.bsTabGroup then col3Normal.bsTabGroup.frame:Hide() end
                if col3Normal.bsPlaceholder then col3Normal.bsPlaceholder:Hide() end
                if col3Normal.multiSelectScroll then col3Normal.multiSelectScroll.frame:Hide() end
                if col3Normal._panelTabGroup then col3Normal._panelTabGroup.frame:Hide() end

                if not col3Normal._autoAddScroll then
                    local scroll = AceGUI:Create("ScrollFrame")
                    scroll:SetLayout("List")
                    scroll.frame:SetParent(col3Normal.content)
                    scroll.frame:ClearAllPoints()
                    scroll.frame:SetPoint("TOPLEFT", col3Normal.content, "TOPLEFT", 0, 0)
                    scroll.frame:SetPoint("BOTTOMRIGHT", col3Normal.content, "BOTTOMRIGHT", 0, 0)
                    col3Normal._autoAddScroll = scroll
                end

                col3Normal._autoAddScroll:ReleaseChildren()
                col3Normal._autoAddScroll.frame:Show()
                if RenderAutoAddFlow then
                    RenderAutoAddFlow(col3Normal._autoAddScroll)
                end
                return
            end
        end
    end

    if col3Normal and col3Normal._autoAddScroll then
        col3Normal._autoAddScroll.frame:Hide()
    end

    -- Hide panel tab group whenever we're NOT about to show it
    if col3Normal and col3Normal._panelTabGroup then
        col3Normal._panelTabGroup.frame:Hide()
    end

    -- Panel settings in Column 3: container mode + panel selected + no button
    local anyButtonSelected = CS.selectedButton ~= nil
    if not anyButtonSelected then
        for _ in pairs(CS.selectedButtons) do anyButtonSelected = true; break end
    end

    if CS.selectedContainer and CS.selectedGroup and not anyButtonSelected then
        if col3Normal then
            if col3Normal.bsTabGroup then col3Normal.bsTabGroup.frame:Hide() end
            if col3Normal.bsPlaceholder then col3Normal.bsPlaceholder:Hide() end
            if col3Normal.multiSelectScroll then col3Normal.multiSelectScroll.frame:Hide() end
        end

        -- Create panel tab group lazily (same pattern as col3._customAuraTabGroup)
        if not col3Normal._panelTabGroup then
            local tabGroup = AceGUI:Create("TabGroup")
            tabGroup:SetLayout("Fill")
            tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                CS.panelSettingsTab = tab
                for _, btn in ipairs(CS.tabInfoButtons) do
                    btn:ClearAllPoints(); btn:Hide(); btn:SetParent(nil)
                end
                wipe(CS.tabInfoButtons)
                widget:ReleaseChildren()

                local scroll = AceGUI:Create("ScrollFrame")
                scroll:SetLayout("List")
                widget:AddChild(scroll)
                CS.col4Scroll = scroll

                if tab == "appearance" then
                    ST._BuildAppearanceTab(scroll)
                elseif tab == "effects" then
                    ST._BuildEffectsTab(scroll)
                elseif tab == "layout" then
                    ST._BuildLayoutTab(scroll)
                elseif tab == "loadconditions" then
                    ST._BuildLoadConditionsTab(scroll)
                end
            end)
            tabGroup.frame:SetParent(col3Normal.content)
            col3Normal._panelTabGroup = tabGroup
        end

        -- Position and configure tabs
        col3Normal._panelTabGroup.frame:ClearAllPoints()
        col3Normal._panelTabGroup.frame:SetPoint("TOPLEFT", col3Normal.content, "TOPLEFT", 0, 0)
        col3Normal._panelTabGroup.frame:SetPoint("BOTTOMRIGHT", col3Normal.content, "BOTTOMRIGHT", 0, 0)

        local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
        local isTextMode = group and group.displayMode == "text"
        local tabs = { { value = "appearance", text = "Appearance" } }
        if not isTextMode then
            tabs[#tabs + 1] = { value = "effects", text = "Indicators" }
        end
        tabs[#tabs + 1] = { value = "layout", text = "Layout" }
        tabs[#tabs + 1] = { value = "loadconditions", text = "Load Conditions" }
        col3Normal._panelTabGroup:SetTabs(tabs)

        -- Migrate stale tab / text-mode redirect
        if isTextMode and CS.panelSettingsTab == "effects" then CS.panelSettingsTab = "appearance" end

        col3Normal._panelTabGroup.frame:Show()
        col3Normal._panelTabGroup:SelectTab(CS.panelSettingsTab or "appearance")
        return
    end

    ST._RefreshButtonSettingsColumn()
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn3 = RefreshColumn3
