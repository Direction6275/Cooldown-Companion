--[[
    CooldownCompanion - Config/Column3
    RefreshColumn3 (button settings / Custom Bars column).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

local RenderAutoAddFlow = ST._RenderAutoAddFlow

------------------------------------------------------------------------
-- COLUMN 3: Button Settings (normal) / Custom Bars (bars mode)
------------------------------------------------------------------------
local function RefreshColumn3()
    -- Hide browse placeholder when not showing it
    local col3BrowseClean = CS.configFrame and CS.configFrame.col3
    if col3BrowseClean and col3BrowseClean._browsePlaceholder then
        col3BrowseClean._browsePlaceholder:Hide()
    end

    -- Bars & Frames panel mode: show Custom Bars
    if CS.resourceBarPanelActive then
        if CS.autoAddFlowActive and ST._CancelAutoAddFlow then
            ST._CancelAutoAddFlow()
        end
        local col3 = CS.configFrame and CS.configFrame.col3
        if not col3 then ST._RefreshButtonSettingsColumn() return end

        -- Hide button settings content that lives on the same col3 content area
        if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
        if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
        if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
        if col3._autoAddScroll then col3._autoAddScroll.frame:Hide() end
        if col3._panelTabGroup then col3._panelTabGroup.frame:Hide() end
        if col3._panelMultiSelectScroll then col3._panelMultiSelectScroll.frame:Hide() end

        if col3._customAuraTabGroup then
            col3._customAuraTabGroup.frame:Hide()
        end

        if not col3._customBarsScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(col3.content)
            col3._customBarsScroll = scroll
        end

        col3._customBarsScroll.frame:ClearAllPoints()
        col3._customBarsScroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
        col3._customBarsScroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
        col3._customBarsScroll:ReleaseChildren()
        col3._customBarsScroll.frame:Show()
        ST._BuildCustomBarsListPanel(col3._customBarsScroll)
        return
    end

    -- Normal mode: hide Custom Bars panel
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
    if col3Normal and col3Normal._customBarsScroll then
        col3Normal._customBarsScroll.frame:Hide()
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

    ST._RefreshButtonSettingsColumn()
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn3 = RefreshColumn3
