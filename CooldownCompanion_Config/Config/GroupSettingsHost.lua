--[[
    CooldownCompanion - Config/GroupSettingsHost
    Group-side settings surfaces (multi-select placeholders, folder tabs,
    container tabs, single-panel tabs), parameterized on a host frame so
    Column 4 and future hosts can share them. Surface widgets are stored on
    the host frame; anchorFn(host, frame) positions each surface and
    defaults to filling the host.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

local function FillHostFrame(host, frame)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
end

local function RefreshGroupSettingsHost(container, anchorFn)
    anchorFn = anchorFn or FillHostFrame

    -- Multi-group selection: show placeholder
    local multiGroupCount = 0
    for _ in pairs(CS.selectedGroups) do multiGroupCount = multiGroupCount + 1 end
    if multiGroupCount >= 2 then
        if not container.placeholderLabel then
            container.placeholderLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            container.placeholderLabel:SetPoint("TOPLEFT", -1, 0)
        end
        container.placeholderLabel:SetText("Select a single group to configure")
        container.placeholderLabel:Show()
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        if container.containerTabGroup then
            container.containerTabGroup.frame:Hide()
        end
        if container.folderTabGroup then
            container.folderTabGroup.frame:Hide()
        end
        return
    end

    -- Panel multi-select: show placeholder
    local panelMultiCount = 0
    for _ in pairs(CS.selectedPanels) do panelMultiCount = panelMultiCount + 1 end
    if panelMultiCount >= 2 then
        if not container.placeholderLabel then
            container.placeholderLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            container.placeholderLabel:SetPoint("TOPLEFT", -1, 0)
        end
        container.placeholderLabel:SetText("Select a single panel to configure")
        container.placeholderLabel:Show()
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        if container.containerTabGroup then
            container.containerTabGroup.frame:Hide()
        end
        if container.folderTabGroup then
            container.folderTabGroup.frame:Hide()
        end
        return
    end

    -- Folder settings: direct folder selection with no child group/panel selected.
    if CS.selectedFolder and not CS.selectedContainer and not CS.selectedGroup then
        if container.placeholderLabel then container.placeholderLabel:Hide() end
        if container.tabGroup then container.tabGroup.frame:Hide() end
        if container.containerTabGroup then container.containerTabGroup.frame:Hide() end

        if not container.folderTabGroup then
            local tabGroup = AceGUI:Create("TabGroup")
            tabGroup:SetLayout("Fill")
            tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                widget:ReleaseChildren()

                local scroll = AceGUI:Create("ScrollFrame")
                scroll:SetLayout("List")
                widget:AddChild(scroll)
                CS.col4Scroll = scroll

                ST._BuildFolderLoadConditionsTab(scroll, CS.selectedFolder)

            end)
            tabGroup.frame:SetParent(container)
            container.folderTabGroup = tabGroup
        end

        anchorFn(container, container.folderTabGroup.frame)
        container.folderTabGroup:SetTabs({
            { value = "loadconditions",  text = "Load Conditions" },
        })
        container.folderTabGroup.frame:Show()
        container.folderTabGroup:SelectTab("loadconditions")
        return
    end

    if container.folderTabGroup then
        container.folderTabGroup.frame:Hide()
    end

    -- Group settings: direct group selection with no panel selected.
    if CS.selectedContainer and not CS.selectedGroup then
        if container.placeholderLabel then container.placeholderLabel:Hide() end
        if container.tabGroup then container.tabGroup.frame:Hide() end

        -- Create or reuse container settings tab group
        if not container.containerTabGroup then
            local tabGroup = AceGUI:Create("TabGroup")
            tabGroup:SetLayout("Fill")
            tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                CS.selectedContainerTab = tab
                widget:ReleaseChildren()

                local scroll = AceGUI:Create("ScrollFrame")
                scroll:SetLayout("List")
                widget:AddChild(scroll)
                CS.col4Scroll = scroll

                if tab == "general" then
                    ST._BuildContainerGeneralTab(scroll, CS.selectedContainer)
                elseif tab == "loadconditions" then
                    ST._BuildContainerLoadConditionsTab(scroll, CS.selectedContainer)
                end

            end)
            tabGroup.frame:SetParent(container)
            container.containerTabGroup = tabGroup
        end

        anchorFn(container, container.containerTabGroup.frame)
        container.containerTabGroup:SetTabs({
            { value = "general",         text = "General" },
            { value = "loadconditions",  text = "Load Conditions" },
        })
        container.containerTabGroup.frame:Show()
        local containerTab = CS.selectedContainerTab
        if containerTab ~= "general" and containerTab ~= "loadconditions" then
            containerTab = "general"
        end
        container.containerTabGroup:SelectTab(containerTab or "general")
        return
    end

    -- Hide container tab group when not in container mode
    if container.containerTabGroup then
        container.containerTabGroup.frame:Hide()
    end
    if container.folderTabGroup then
        container.folderTabGroup.frame:Hide()
    end

    if not CS.selectedGroup then
        -- Show placeholder, hide tab group
        if not container.placeholderLabel then
            container.placeholderLabel = container:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            container.placeholderLabel:SetPoint("TOPLEFT", -1, 0)
        end
        container.placeholderLabel:SetText("Select a group to configure")
        container.placeholderLabel:Show()
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        return
    end

    -- Single panel selection: show panel settings whether the panel itself
    -- or one of its buttons is selected.
    if container.placeholderLabel then
        container.placeholderLabel:Hide()
    end

    -- Create the TabGroup once, reuse on subsequent refreshes
    if not container.tabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")

        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            local previousTab = container._activePanelSettingsTab
            local tabChanged = previousTab ~= nil and previousTab ~= tab
            container._activePanelSettingsTab = tab
            CS.selectedTab = tab
            CS.panelSettingsTab = tab
            local preservePreviews = CS.previewToggleRefreshActive == true
            if tabChanged and not preservePreviews then
                CooldownCompanion:ClearAllConfigPreviews()
            end
            -- Clean up raw (?) info buttons BEFORE releasing children, so they
            -- don't leak onto recycled AceGUI frames when switching tabs
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
            CS.col4Scroll = scroll

            if tab == "appearance" then
                ST._BuildAppearanceTab(scroll)
            elseif tab == "layout" then
                ST._BuildLayoutTab(scroll)
            elseif tab == "effects" then
                ST._BuildEffectsTab(scroll)
            elseif tab == "loadconditions" then
                ST._BuildLoadConditionsTab(scroll)
            end

        end)

        -- Parent the AceGUI widget frame to the raw host frame
        tabGroup.frame:SetParent(container)

        container.tabGroup = tabGroup
    end

    anchorFn(container, container.tabGroup.frame)

    -- Update tabs every refresh — hide Indicators for text mode (info lives in format editor)
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local isTextMode = group and group.displayMode == "text"
    local tabs = {
        { value = "appearance",      text = "Appearance" },
    }
    if not isTextMode then
        tabs[#tabs + 1] = { value = "effects", text = "Indicators" }
    end
    tabs[#tabs + 1] = { value = "layout",          text = "Layout" }
    tabs[#tabs + 1] = { value = "loadconditions",  text = "Load Conditions" }
    container.tabGroup:SetTabs(tabs)

    -- Save AceGUI scroll state before tab re-select (old col4Scroll will be released)
    local savedOffset, savedScrollvalue
    if CS.col4Scroll then
        local s = CS.col4Scroll.status or CS.col4Scroll.localstatus
        if s and s.offset and s.offset > 0 then
            savedOffset = s.offset
            savedScrollvalue = s.scrollvalue
        end
    end

    -- Migrate stale tab keys from previous layout
    if CS.selectedTab == "extras" then CS.selectedTab = "effects" end
    if CS.selectedTab == "positioning" then CS.selectedTab = "layout" end
    -- Text mode has no Indicators tab — redirect to Appearance
    if isTextMode and CS.selectedTab == "effects" then
        CS.selectedTab = "appearance"
    end
    CS.panelSettingsTab = CS.selectedTab

    -- Show and refresh the tab content (SelectTab fires callback synchronously,
    -- which releases old col4Scroll and creates a new one)
    container.tabGroup.frame:Show()
    container.tabGroup:SelectTab(CS.selectedTab)

    -- Restore scroll state on the new col4Scroll widget.  LayoutFinished has already
    -- scheduled FixScrollOnUpdate for next frame — it will read these values.
    if savedOffset and CS.col4Scroll then
        local s = CS.col4Scroll.status or CS.col4Scroll.localstatus
        if s then
            s.offset = savedOffset
            s.scrollvalue = savedScrollvalue
        end
    end
end

ST._RefreshGroupSettingsHost = RefreshGroupSettingsHost
