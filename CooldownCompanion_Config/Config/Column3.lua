--[[
    CooldownCompanion - Config/Column3
    RefreshColumn3 (button settings / Custom Bars column).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

------------------------------------------------------------------------
-- Module intro panes: centered descriptive text + an enable button,
-- shown in place of a module's settings while it is disabled. Used by
-- the Resources empty state (wide pane) and the Cast Bar / Unit Frames
-- columns (mini front doors).
------------------------------------------------------------------------
local function ShowColumnIntroPane(col, paneKey, opts)
    local pane = col[paneKey]
    if not pane then
        local content = col.content or col
        pane = CreateFrame("Frame", nil, content)
        pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)

        local title = pane:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        title:SetPoint("BOTTOM", pane, "CENTER", 0, 64)
        title:SetText(opts.title)

        local sideInset = opts.sideInset or 48
        local body = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        body:SetPoint("TOP", title, "BOTTOM", 0, -14)
        body:SetPoint("LEFT", pane, "LEFT", sideInset, 0)
        body:SetPoint("RIGHT", pane, "RIGHT", -sideInset, 0)
        body:SetJustifyH("CENTER")
        body:SetSpacing(3)
        body:SetText(opts.body)

        local enableBtn = AceGUI:Create("Button")
        enableBtn:SetText(opts.buttonText)
        enableBtn:SetWidth(opts.buttonWidth or 220)
        enableBtn:SetCallback("OnClick", opts.onEnable)
        enableBtn.frame:SetParent(pane)
        enableBtn.frame:ClearAllPoints()
        enableBtn.frame:SetPoint("TOP", body, "BOTTOM", 0, -28)
        pane._enableBtn = enableBtn

        col[paneKey] = pane
    end
    pane._enableBtn.frame:Show()
    pane:Show()
end
ST._ShowColumnIntroPane = ShowColumnIntroPane

local function ShowResourcesIntroPane(col3)
    ShowColumnIntroPane(col3, "_resourcesIntroPane", {
        title = "Track your resources at a glance",
        body = "Class resources displayed as bars, attached to one of your panels or positioned anywhere on screen."
            .. "\n\nAdd Custom Bars to track any aura or cooldown you choose.",
        buttonText = "Enable Resource Bars",
        onEnable = function()
            local settings = CooldownCompanion:GetResourceBarSettings()
            if not settings then
                return
            end
            settings.enabled = true
            CooldownCompanion:EvaluateResourceBars()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })
end

------------------------------------------------------------------------
-- COLUMN 3: Button Settings (normal) / Custom Bars (bars mode)
------------------------------------------------------------------------
local function RefreshColumn3()
    -- Hide browse placeholder when not showing it
    local col3BrowseClean = CS.configFrame and CS.configFrame.col3
    if col3BrowseClean and col3BrowseClean._browsePlaceholder then
        col3BrowseClean._browsePlaceholder:Hide()
    end

    -- Cast Bar & Unit Frames home: col3 = Cast Bar
    if CS.castFramesEntrySelected then
        local col3 = CS.configFrame and CS.configFrame.col3
        if not col3 then return end

        -- Hide content that shares the col3 content area
        if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
        if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
        if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
        if col3._panelTabGroup then col3._panelTabGroup.frame:Hide() end
        if col3._panelMultiSelectScroll then col3._panelMultiSelectScroll.frame:Hide() end
        if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
        if col3._customBarsScroll then col3._customBarsScroll.frame:Hide() end
        if col3._resourcesIntroPane then col3._resourcesIntroPane:Hide() end

        local settings = CooldownCompanion:GetCastBarSettings()
        if not (settings and settings.enabled) then
            if col3._castBarHomeTabGroup then
                col3._castBarHomeTabGroup.frame:Hide()
            end
            ShowColumnIntroPane(col3, "_castBarIntroPane", {
                title = "Cast Bar",
                body = "Skin the Blizzard cast bar and anchor it to a panel, or position it anywhere on screen.",
                buttonText = "Enable Cast Bar",
                sideInset = 24,
                onEnable = function()
                    local cb = CooldownCompanion:GetCastBarSettings()
                    if not cb then
                        return
                    end
                    cb.enabled = true
                    CooldownCompanion:EvaluateCastBar()
                    CooldownCompanion:UpdateAnchorStacking()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
            return
        end
        if col3._castBarIntroPane then
            col3._castBarIntroPane:Hide()
        end

        if not col3._castBarHomeTabGroup then
            local tabGroup = AceGUI:Create("TabGroup")
            tabGroup:SetLayout("Fill")
            tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                CS.castBarHomeTab = tab
                -- Clean up info buttons from the previous tab before recycling widgets
                for _, btn in ipairs(CS.tabInfoButtons) do
                    btn:ClearAllPoints()
                    btn:Hide()
                    btn:SetParent(nil)
                end
                wipe(CS.tabInfoButtons)
                widget:ReleaseChildren()
                local scroll = AceGUI:Create("ScrollFrame")
                scroll:SetLayout("List")
                widget:AddChild(scroll)
                col3._castBarHomeScroll = scroll
                col3._castBarHomeScrollKey = "castbar:" .. tab
                if tab == "general" then
                    ST._BuildCastBarAnchoringPanel(scroll)
                elseif tab == "appearance" then
                    ST._BuildCastBarStylingPanel(scroll)
                elseif tab == "layout" then
                    ST._BuildCastBarPositioningPanel(scroll)
                end
            end)
            tabGroup.frame:SetParent(col3.content)
            tabGroup.frame:ClearAllPoints()
            tabGroup.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
            tabGroup.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
            col3._castBarHomeTabGroup = tabGroup
        end

        local tabGroup = col3._castBarHomeTabGroup
        tabGroup:SetTabs({
            { value = "general", text = "General" },
            { value = "appearance", text = "Appearance" },
            { value = "layout", text = "Layout" },
        })

        local tab = CS.castBarHomeTab
        if tab ~= "general" and tab ~= "appearance" and tab ~= "layout" then
            tab = "general"
        end
        CS.castBarHomeTab = tab

        -- Preserve scroll position across value-change refreshes
        local savedOffset, savedScrollvalue
        local currentScrollKey = "castbar:" .. tab
        if col3._castBarHomeScroll and col3._castBarHomeScrollKey == currentScrollKey then
            local state = col3._castBarHomeScroll.status or col3._castBarHomeScroll.localstatus
            if state and state.offset and state.offset > 0 then
                savedOffset = state.offset
                savedScrollvalue = state.scrollvalue
            end
        end

        tabGroup.frame:Show()
        tabGroup:SelectTab(tab)

        if savedOffset and col3._castBarHomeScroll then
            local state = col3._castBarHomeScroll.status or col3._castBarHomeScroll.localstatus
            if state then
                state.offset = savedOffset
                state.scrollvalue = savedScrollvalue
            end
        end
        return
    end

    -- Bars & Frames panel mode or the Resources home: show Custom Bars
    if CS.resourceBarPanelActive or CS.resourcesEntrySelected then
        local col3 = CS.configFrame and CS.configFrame.col3
        if not col3 then ST._RefreshButtonSettingsColumn() return end

        -- Hide button settings content that lives on the same col3 content area
        if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
        if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
        if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
        if col3._panelTabGroup then col3._panelTabGroup.frame:Hide() end
        if col3._panelMultiSelectScroll then col3._panelMultiSelectScroll.frame:Hide() end

        if col3._customAuraTabGroup then
            col3._customAuraTabGroup.frame:Hide()
        end
        if col3._castBarHomeTabGroup then col3._castBarHomeTabGroup.frame:Hide() end
        if col3._castBarIntroPane then col3._castBarIntroPane:Hide() end

        -- Disabled home: the single wide intro pane replaces the list
        if ST._IsResourcesEmptyStateActive and ST._IsResourcesEmptyStateActive() then
            if col3._customBarsScroll then
                col3._customBarsScroll.frame:Hide()
            end
            ShowResourcesIntroPane(col3)
            return
        end
        if col3._resourcesIntroPane then
            col3._resourcesIntroPane:Hide()
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
    if col3Normal and col3Normal._resourcesIntroPane then
        col3Normal._resourcesIntroPane:Hide()
    end
    if col3Normal and col3Normal._castBarHomeTabGroup then
        col3Normal._castBarHomeTabGroup.frame:Hide()
    end
    if col3Normal and col3Normal._castBarIntroPane then
        col3Normal._castBarIntroPane:Hide()
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
