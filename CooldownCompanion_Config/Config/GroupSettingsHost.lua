--[[
    CooldownCompanion - Config/GroupSettingsHost
    Group-side settings surfaces (multi-select placeholders, container tabs,
    single-panel tabs), parameterized on the workspace
    host frame. Surface widgets are stored on the host; anchorFn(host, frame)
    positions each surface and defaults to filling it.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Set only while this file drives SelectTab itself. A user clicking a tab
-- fires the same callback with the flag clear, which is the only way to tell
-- "the user picked this tab" from "we re-selected the remembered one" — and
-- that distinction is what decides whether a text panel lands on Format.
local programmaticTabSelect = false

local function SelectPanelSettingsTabProgrammatic(tabGroup, tab)
    programmaticTabSelect = true
    tabGroup:SelectTab(tab)
    programmaticTabSelect = false
end

local function FillHostFrame(host, frame)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    frame:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, 0)
end

-- stripOnly: an entry owns the settings surface, so the panel tabs are
-- painted as the left half of the unified row and no panel content is
-- built. Clicking one of them selects it, which builds its content and
-- flips the scope without touching the entry selection.
local function RefreshGroupSettingsHost(container, anchorFn, stripOnly)
    anchorFn = anchorFn or FillHostFrame
    -- Callers that re-select the panel tab (e.g. the custom strata toggle)
    -- need the host that most recently built these surfaces.
    CS.groupSettingsActiveHost = container

    -- The text Format tab hosts a live editor with a pending debounced write
    -- and an animation driver on the container frame. Settle both here, at
    -- the top, before any branch below decides what owns the surface: the
    -- placeholder branches and the tabs-only pass all take the tab content
    -- away without re-selecting a tab, and the branch that does re-select one
    -- releases again from the callback (Release is idempotent).
    if ST._ReleaseTextFormatTabEditor then
        ST._ReleaseTextFormatTabEditor()
    end

    -- No panel to show tabs for: the placeholder branches below own the
    -- host, whatever the caller asked for.
    if stripOnly and not CS.selectedGroup then
        stripOnly = false
    end

    -- Panel multi-select: show placeholder. (Group multi-select never reaches
    -- this host: RefreshButtonsWideColumn early-returns to the batch surface.)
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
        return
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

                if tab == "general" then
                    ST._BuildContainerGeneralTab(scroll, CS.selectedContainer)
                elseif tab == "loadconditions" then
                    ST._BuildContainerLoadConditionsTab(scroll, CS.selectedContainer)
                end

                -- Re-run the layout with final widths: nested Flow rows resize
                -- themselves after their children land, and that height never
                -- reaches the scroll frame until something relayouts it.
                scroll:DoLayout()

            end)
            tabGroup.frame:SetParent(container)
            container.containerTabGroup = tabGroup
        end

        anchorFn(container, container.containerTabGroup.frame)
        container.containerTabGroup:SetTabs({
            { value = "general",         text = "General" },
            { value = "loadconditions",  text = "Visibility" },
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
            -- A click on the tab itself is the user choosing a tab; our own
            -- re-selects are not. Once there is a choice to honor, it is
            -- honored for every panel, text or not.
            if not programmaticTabSelect then
                CS.panelSettingsTabExplicit = true
            end
            -- Flush the Format tab's pending write and release its controller
            -- BEFORE ReleaseChildren hands the container frame back to
            -- AceGUI's pool. There is exactly ONE format editor in the config
            -- (the Format tab's, panel or entry lens alike), so this single
            -- release is the whole contract.
            if ST._ReleaseTextFormatTabEditor then
                ST._ReleaseTextFormatTabEditor()
            end
            local previousTab = container._activePanelSettingsTab
            local tabChanged = previousTab ~= nil and previousTab ~= tab
            -- Selecting a panel tab hands the settings surface to panel
            -- scope. Any entry stays selected: the list highlight,
            -- breadcrumb and preview identity are untouched.
            local scopeChanged = ST._UnifiedRowGetScope() ~= "primary"
            ST._UnifiedRowSetScope("primary")
            container._activePanelSettingsTab = tab
            CS.selectedTab = tab
            CS.panelSettingsTab = tab
            if tabChanged or scopeChanged then
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

            if tab == "format" then
                ST._BuildTextFormatTab(scroll)
            elseif tab == "appearance" then
                ST._BuildAppearanceTab(scroll)
            elseif tab == "layout" then
                ST._BuildLayoutTab(scroll)
            elseif tab == "effects" then
                ST._BuildEffectsTab(scroll)
            elseif tab == "loadconditions" then
                -- One Visibility tab for both scopes: the dispatcher edits
                -- the selected entry's rules when there is one (including
                -- the rotation assistant's virtual entry, which has no entry
                -- tabs of its own) and the panel's otherwise.
                ST._BuildVisibilityTab(scroll)
            end

            -- Re-run the layout with final widths: AddChild lays out on every
            -- insertion, so half-width overrides applied after a builder
            -- returns are invisible until something else triggers a layout
            -- (the two-column tabs' trailing widgets mis-wrapped otherwise).
            scroll:DoLayout()

        end)

        -- Parent the AceGUI widget frame to the raw host frame
        tabGroup.frame:SetParent(container)

        -- Panel tabs are the left cluster of the unified tab row.
        ST._UnifiedRowInstallStrip(tabGroup, "primary")

        container.tabGroup = tabGroup
    end

    anchorFn(container, container.tabGroup.frame)
    -- Shown before the tabs are built: the entry strip measures this one to
    -- find where its own cluster starts.
    container.tabGroup.frame:Show()

    -- Update tabs every refresh — text mode leads with Format (the format is
    -- what a text panel IS) and has no Indicators tab (info lives in the
    -- format editor).
    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local isTextMode = group and group.displayMode == "text"
    local tabsMode = isTextMode and "text" or "standard"
    if container._cdcPanelSettingsTabsMode ~= tabsMode then
        local tabs = {}
        if isTextMode then
            tabs[#tabs + 1] = { value = "format", text = "Format" }
        end
        tabs[#tabs + 1] = { value = "appearance", text = "Appearance" }
        if not isTextMode then
            tabs[#tabs + 1] = { value = "effects", text = "Indicators" }
        end
        tabs[#tabs + 1] = { value = "layout",          text = "Layout" }
        tabs[#tabs + 1] = { value = "loadconditions",  text = "Visibility" }
        container.tabGroup:SetTabs(tabs)
        container._cdcPanelSettingsTabsMode = tabsMode
    end

    -- Migrate stale tab keys from previous layout
    if CS.selectedTab == "extras" then CS.selectedTab = "effects" end
    if CS.selectedTab == "positioning" then CS.selectedTab = "layout" end
    -- Text mode has no Indicators tab — redirect to Appearance
    if isTextMode and CS.selectedTab == "effects" then
        CS.selectedTab = "appearance"
    end
    -- Only text mode has a Format tab — redirect to Appearance, the same way
    -- Indicators redirects the other direction.
    if not isTextMode and CS.selectedTab == "format" then
        CS.selectedTab = "appearance"
    end
    -- A text panel with no tab choice to honor lands on Format. The remembered
    -- tab is one shared value with no "unset" state (it ships as "appearance"),
    -- so "is this a choice?" is tracked separately: a tab click, or a route
    -- that deliberately names a destination, sets the flag, and from then on
    -- the remembered tab wins here too.
    if isTextMode and not CS.panelSettingsTabExplicit then
        CS.selectedTab = "format"
    end
    CS.panelSettingsTab = CS.selectedTab

    -- Tabs-only pass: an entry owns the surface, so the remembered panel
    -- tab stays remembered and no panel content is built. Its highlight is
    -- cleared by the unified-row pass that follows.
    if stripOnly then
        return
    end

    -- Save AceGUI scroll state before tab re-select (old col4Scroll will be released)
    local savedOffset, savedScrollvalue
    if CS.col4Scroll then
        local s = CS.col4Scroll.status or CS.col4Scroll.localstatus
        if s and s.offset and s.offset > 0 then
            savedOffset = s.offset
            savedScrollvalue = s.scrollvalue
        end
    end

    -- Show and refresh the tab content (SelectTab fires callback synchronously,
    -- which releases old col4Scroll and creates a new one)
    SelectPanelSettingsTabProgrammatic(container.tabGroup, CS.selectedTab)

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
-- For the few outside callers that rebuild the current panel tab in place.
-- Going through this instead of SelectTab keeps a rebuild from being mistaken
-- for the user choosing a tab.
ST._SelectPanelSettingsTabProgrammatic = SelectPanelSettingsTabProgrammatic
