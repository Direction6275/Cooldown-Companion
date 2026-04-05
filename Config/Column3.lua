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
    -- Hide browse placeholder when not showing it
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
        if col3._panelMultiSelectScroll then col3._panelMultiSelectScroll.frame:Hide() end

        -- Create/show custom aura tab group
        if col3._customAuraScroll then
            col3._customAuraScroll.frame:Hide()
        end
        if not col3._customAuraTabGroup then
            local customAuraTabs = {}
            for slotIdx = 1, maxCustomAuraTabs do
                customAuraTabs[#customAuraTabs + 1] = {
                    value = "bar_" .. slotIdx,
                    text = slotIdx,
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
                if col3Normal._panelMultiSelectScroll then col3Normal._panelMultiSelectScroll.frame:Hide() end

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

    -- Panel multi-select: batch operations in Column 3
    local panelMultiCount = 0
    local multiPanelIds = {}
    for pid in pairs(CS.selectedPanels) do
        panelMultiCount = panelMultiCount + 1
        multiPanelIds[#multiPanelIds + 1] = pid
    end
    if panelMultiCount >= 2 and CS.selectedContainer then
        if col3Normal then
            if col3Normal.bsTabGroup then col3Normal.bsTabGroup.frame:Hide() end
            if col3Normal.bsPlaceholder then col3Normal.bsPlaceholder:Hide() end
            if col3Normal.multiSelectScroll then col3Normal.multiSelectScroll.frame:Hide() end
            if col3Normal._panelTabGroup then col3Normal._panelTabGroup.frame:Hide() end
            if col3Normal._autoAddScroll then col3Normal._autoAddScroll.frame:Hide() end

            if not col3Normal._panelMultiSelectScroll then
                local scroll = AceGUI:Create("ScrollFrame")
                scroll:SetLayout("List")
                scroll.frame:SetParent(col3Normal.content)
                scroll.frame:ClearAllPoints()
                scroll.frame:SetPoint("TOPLEFT", col3Normal.content, "TOPLEFT", 0, 0)
                scroll.frame:SetPoint("BOTTOMRIGHT", col3Normal.content, "BOTTOMRIGHT", 0, 0)
                col3Normal._panelMultiSelectScroll = scroll
            end
            col3Normal._panelMultiSelectScroll:ReleaseChildren()
            col3Normal._panelMultiSelectScroll.frame:Show()
            ST._RefreshPanelMultiSelect(col3Normal._panelMultiSelectScroll, panelMultiCount, multiPanelIds)
        end
        return
    end
    -- Hide panel multi-select scroll when not active
    if col3Normal and col3Normal._panelMultiSelectScroll then
        col3Normal._panelMultiSelectScroll.frame:Hide()
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
                if tab ~= "effects" then
                    CooldownCompanion:ClearAllTextureIndicatorPreviews()
                end
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

                if CS.browseMode then
                    ST._DisableAllWidgets(scroll)
                    for _, btn in ipairs(CS.tabInfoButtons) do
                        if btn.Disable then btn:Disable() end
                    end
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

        -- Migrate stale tab / mode redirects
        if isTextMode and CS.panelSettingsTab == "effects" then
            CS.panelSettingsTab = "appearance"
        end

        -- Save scroll state before SelectTab releases the old ScrollFrame
        local savedOffset, savedScrollvalue
        local prevScroll = col3Normal._panelSettingsScroll
        if prevScroll then
            local s = prevScroll.status or prevScroll.localstatus
            if s and s.offset and s.offset > 0 then
                savedOffset = s.offset
                savedScrollvalue = s.scrollvalue
            end
        end

        col3Normal._panelTabGroup.frame:Show()
        col3Normal._panelTabGroup:SelectTab(CS.panelSettingsTab or "appearance")

        -- Stash a reference on col3 so we can find it next refresh
        col3Normal._panelSettingsScroll = CS.col4Scroll

        -- Restore scroll state on the new scroll widget.  LayoutFinished has already
        -- scheduled FixScrollOnUpdate for next frame — it will read these values.
        if savedOffset and CS.col4Scroll then
            local s = CS.col4Scroll.status or CS.col4Scroll.localstatus
            if s then
                s.offset = savedOffset
                s.scrollvalue = savedScrollvalue
            end
        end

        return
    end

    ST._RefreshButtonSettingsColumn()
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn3 = RefreshColumn3
