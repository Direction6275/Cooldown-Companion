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

local PRESENTATION_HEADER_HEIGHT = 32
local PRESENTATION_HEADER_TYPE = "CCPresentationHeader"
local PRESENTATION_LAYOUT = "CCPanelStylePage"

local function UpdatePresentationHeader(header, hovered)
    if header.selected then
        header.label:SetTextColor(1, 0.82, 0)
    elseif hovered then
        header.label:SetTextColor(1, 1, 1)
    else
        header.label:SetTextColor(0.65, 0.65, 0.65)
    end
    header.underline:SetColorTexture(1, 0.65, 0, header.selected and 0.9 or (hovered and 0.5 or 0.18))
    header.underline:SetHeight(header.selected and 2 or 1)
end

-- Own the header's art and mouse handlers in a dedicated widget, so neither
-- can leak into ordinary AceGUI labels/buttons when the surface is recycled.
AceGUI:RegisterWidgetType(PRESENTATION_HEADER_TYPE, function()
    local frame = CreateFrame("Button", nil, UIParent)
    frame:Hide()
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -3)
    label:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 3)
    label:SetJustifyH("CENTER")
    local underline = frame:CreateTexture(nil, "ARTWORK")
    underline:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    local header = { type = PRESENTATION_HEADER_TYPE, frame = frame, label = label, underline = underline }
    function header:OnAcquire()
        self:SetWidth(200)
        self:SetHeight(PRESENTATION_HEADER_HEIGHT - 6)
        self:SetText("")
        self:SetSelected(false)
        self:SetInteractive(false)
    end
    function header:SetText(text) self.label:SetText(text) end
    function header:SetSelected(selected)
        self.selected = selected
        UpdatePresentationHeader(self)
    end
    function header:SetInteractive(interactive)
        self.interactive = interactive
        self.frame:EnableMouse(interactive)
    end
    frame:SetScript("OnEnter", function() UpdatePresentationHeader(header, true) end)
    frame:SetScript("OnLeave", function() UpdatePresentationHeader(header) end)
    frame:SetScript("OnClick", function(_, button)
        if header.interactive and button == "LeftButton" then header:Fire("OnClick") end
    end)
    return AceGUI:RegisterAsWidget(header)
end, 1)

-- The headings and scroll are siblings: the header never participates in the
-- scroll's section geometry, and every scope reserves exactly the same space.
AceGUI:RegisterLayout(PRESENTATION_LAYOUT, function(content, children)
    local width, height = content:GetWidth(), content:GetHeight()
    local headerCount = 0
    for _, child in ipairs(children) do
        if child.type == PRESENTATION_HEADER_TYPE then headerCount = headerCount + 1 end
    end
    for index, child in ipairs(children) do
        child.frame:ClearAllPoints()
        if child.type == "ScrollFrame" then
            child:SetWidth(width)
            child:SetHeight(math.max(1, height - PRESENTATION_HEADER_HEIGHT))
            child.frame:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -PRESENTATION_HEADER_HEIGHT)
            child.frame:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
        else
            local headerWidth = width / headerCount
            child:SetWidth(headerWidth)
            child:SetHeight(PRESENTATION_HEADER_HEIGHT - 6)
            child.frame:SetPoint("TOPLEFT", content, "TOPLEFT", (index - 1) * headerWidth, 0)
        end
        child.frame:Show()
    end
end)

local function CreatePresentationPage(widget, group, tab, presentation, available)
    local page = AceGUI:Create("SimpleGroup")
    page:SetAutoAdjustHeight(false)
    page:SetLayout(PRESENTATION_LAYOUT)
    page:PauseLayout()
    widget:AddChild(page)
    local entry = ST._GetPanelSettingsSelection(group)
    if not entry and available.icons and available.bars then
        local panelId = CS.selectedGroup
        for _, kind in ipairs({ "icons", "bars" }) do
            local header = AceGUI:Create(PRESENTATION_HEADER_TYPE)
            local selected = kind == presentation
            local label = kind == "icons" and "Icons" or "Bars"
            header:SetText(label)
            header:SetSelected(selected)
            header:SetInteractive(true)
            header:SetCallback("OnClick", function()
                if selected or CS.selectedGroup ~= panelId or CS.selectedTab ~= tab
                    or CooldownCompanion.db.profile.groups[panelId] ~= group
                    or ST._GetPanelSettingsSelection(group) then return end
                if ST._FlushSettingsEdits then ST._FlushSettingsEdits() end
                ST._RememberPanelSettingsView()
                ST._GetPanelSettingsState(group).presentation = kind
                CooldownCompanion:ClearAllConfigPreviews()
                CooldownCompanion:RefreshConfigSelection()
            end)
            page:AddChild(header)
        end
    else
        local header = AceGUI:Create(PRESENTATION_HEADER_TYPE)
        header:SetText(presentation == "bars" and "Bars" or "Icons")
        header:SetSelected(true)
        page:AddChild(header)
    end
    page:ResumeLayout()
    return page
end

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

-- stripOnly: the selected entry's Settings/Customizations tab owns the shared
-- surface, so its style tabs are painted beside it without building content.
-- Both strips still belong to the same selected entry.
local function RefreshGroupSettingsHost(container, anchorFn, stripOnly)
    anchorFn = anchorFn or FillHostFrame
    if ST._RememberPanelSettingsView then ST._RememberPanelSettingsView() end
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
            if ST._FlushSettingsEdits then ST._FlushSettingsEdits() end
            if ST._RememberPanelSettingsView then ST._RememberPanelSettingsView() end
            local oldScroll = CS.col4Scroll
            local oldOwner = oldScroll and oldScroll._cdcSettingsOwner
            local oldView = oldScroll and oldScroll._cdcSettingsViewKey
            local oldEntry = oldScroll and oldScroll._cdcSettingsEntry
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
            -- Selecting a style tab hands that strip the settings surface.
            -- The selected object decides whether its values come from an
            -- entry lens or the panel defaults.
            local scopeChanged = ST._UnifiedRowGetScope() ~= "primary"
            ST._UnifiedRowSetScope("primary")
            container._activePanelSettingsTab = tab
            CS.selectedTab = tab
            CS.panelSettingsTab = tab
            -- A programmatic rebuild already resolved its navigation intent. Only
            -- a manual tab change ends playback here.
            if (tabChanged or scopeChanged) and not CS.configRefreshInProgress then
                local wasPlaying = ST._ConfigPreview.Get() ~= nil
                CooldownCompanion:ClearAllConfigPreviews()
                if wasPlaying and ST._RefreshButtonsPreviewMirror then ST._RefreshButtonsPreviewMirror() end
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

            local styleGroup = CooldownCompanion.db.profile.groups[CS.selectedGroup]
            local presentation, available
            if styleGroup and ST.PanelSupportsAttachedBars(styleGroup) then
                ST._PreparePanelSettingsNavigation(styleGroup, tab)
                available = container._settingsPresentations and container._settingsPresentations[tab] or {}
                presentation = ST._GetPanelSettingsPresentation(styleGroup, tab, available)
            end
            local scrollParent = presentation
                and CreatePresentationPage(widget, styleGroup, tab, presentation, available) or widget
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scrollParent:AddChild(scroll)
            CS.col4Scroll = scroll
            scroll._cdcStylePresentation = nil
            scroll._cdcSettingsScopeKey, scroll._cdcSettingsOwner = nil, nil
            scroll._cdcSettingsViewKey, scroll._cdcSettingsEntry = nil, nil
            if styleGroup then
                scroll._cdcStylePresentation = styleGroup.displayMode or "icons"
                if ST.PanelSupportsAttachedBars(styleGroup) then
                    local entry = ST._GetPanelSettingsSelection(styleGroup)
                    local scope = entry and "entry" or "panel"
                    local state = ST._GetPanelSettingsState(styleGroup)
                    state.panelTab = tab
                    if entry then state.presentation = ST.GetEntryPresentation(styleGroup, entry) end
                    if presentation then scope = scope .. ":" .. presentation end
                    scroll._cdcStylePresentation = presentation or "ordinary"
                    scroll._cdcSettingsScopeKey = scope .. ":" .. tab
                    scroll._cdcSettingsOwner = styleGroup
                    scroll._cdcSettingsEntry = entry
                    scroll._cdcSettingsViewKey = presentation and presentation .. ":" .. tab or nil
                    local views = state.scrolls
                    local key = scope .. ":" .. tab
                    views[key] = views[key] or {}
                    scroll:SetStatusTable(views[key])
                    if presentation and (oldOwner ~= styleGroup or oldView ~= scroll._cdcSettingsViewKey
                        or oldEntry ~= entry or CS.pendingLensAnchor) then
                        ST._PreparePanelSettingsView(scroll)
                    end
                end
            end
            scroll:SetCallback("OnRelease", function(released)
                local registry = CS.lensAnchorRegistry
                if registry and registry.scroll == released then registry.released = true end
                released._cdcStylePresentation, released._cdcSettingsScopeKey = nil, nil
                released._cdcSettingsOwner, released._cdcSettingsViewKey, released._cdcSettingsEntry = nil, nil, nil
            end)
            if ST._BeginLensAnchorBuild then
                ST._BeginLensAnchorBuild(scroll)
            end

            -- One advanced-gear build pass per surface rebuild
            -- (AdvancedSettingsPanel.lua): gears stamp as they build, and
            -- the pass's foot sweep closes every gear panel whose gear did
            -- not rebuild - collapsed sections, early-returned builders and
            -- gearless tabs alike.
            CS.RunAdvancedGearBuildPass(function()
                if tab == "format" then
                    ST._BuildTextFormatTab(scroll)
                elseif tab == "appearance" then
                    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
                    if ST.IsTotemPanelGroup(group) then ST._BuildTotemAppearanceTab(scroll, group)
                    else ST._BuildAppearanceTab(scroll) end
                elseif tab == "layout" then
                    ST._BuildLayoutTab(scroll)
                elseif tab == "effects" then
                    local group = CooldownCompanion.db.profile.groups[CS.selectedGroup]
                    if ST.IsTotemPanelGroup(group) then ST._BuildTotemEffectsTab(scroll, group)
                    else ST._BuildEffectsTab(scroll) end
                elseif tab == "loadconditions" then
                    -- One Visibility tab for both scopes: the dispatcher
                    -- edits the selected entry's rules when there is one
                    -- (including the rotation assistant's virtual entry,
                    -- which has no entry tabs of its own) and the panel's
                    -- otherwise.
                    ST._BuildVisibilityTab(scroll)
                end
            end)

            -- Re-run the layout with final widths: AddChild lays out on every
            -- insertion, so half-width overrides applied after a builder
            -- returns are invisible until something else triggers a layout
            -- (the two-column tabs' trailing widgets mis-wrapped otherwise).
            scroll:DoLayout()
            if ST._EndLensAnchorBuild then
                ST._EndLensAnchorBuild()
            end
            -- Direct tab clicks do not run the config refresh coordinator.
            -- Complete the same layout/editor/anchor sequence synchronously.
            if not CS.configRefreshInProgress and CS.pendingLensAnchor then
                if ST._UnifiedRowRefresh then ST._UnifiedRowRefresh() end
                if CS.RefreshAdvancedSettingsPanel then CS.RefreshAdvancedSettingsPanel() end
                scroll:FixScroll()
                if ST._RestoreLensAnchor then ST._RestoreLensAnchor() end
            end
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
    local isRotationEntry = group
        and CS.selectedRotationAssistantEntry == true
        and CooldownCompanion:IsRotationAssistantGroup(group)
    local isSingleEntry = group
        and CS.selectedButton ~= nil
        and group.buttons
        and group.buttons[CS.selectedButton] ~= nil
        and ST._GroupSupportsPerButtonOverrides
        and ST._GroupSupportsPerButtonOverrides(group)
    if group and ST.PanelSupportsAttachedBars(group) then isSingleEntry = ST._GetPanelSettingsSelection(group) ~= nil end
    local availableTabs, presentations
    if ST._GetOrdinarySettingsTabs then availableTabs, presentations = ST._GetOrdinarySettingsTabs(group) end
    container._settingsPresentations = presentations
    local selectionMode = isRotationEntry and "rotation-entry"
        or (isSingleEntry and "entry" or "panel")
    local tabsMode = (isTextMode and "text" or "standard") .. ":" .. selectionMode
    if availableTabs then
        tabsMode = tabsMode .. ":" .. tostring(availableTabs.layout) .. ":" .. tostring(availableTabs.appearance) .. ":" .. tostring(availableTabs.effects)
    end
    if group and ST.PanelSupportsAttachedBars(group) then
        local entry = ST._GetPanelSettingsSelection(group)
        local scope = entry and "entry" or "panel"
        local state = ST._GetPanelSettingsState(group)
        if entry then state.presentation = ST.GetEntryPresentation(group, entry) end
        if scope == "panel" and not CS.pendingSettingHighlight
            and container._settingsTabOwner ~= group then
            CS.selectedTab = state.panelTab or CS.selectedTab
        end
        container._settingsTabOwner, container._settingsTabScope = group, scope
    else
        container._settingsTabOwner, container._settingsTabScope = nil, nil
    end
    if container._cdcPanelSettingsTabsMode ~= tabsMode then
        local tabs = {}
        if isRotationEntry then
            -- The assistant's virtual entry owns Visibility alone. Its style
            -- and layout belong to the panel reached through the breadcrumb.
            tabs[#tabs + 1] = { value = "loadconditions", text = "Visibility" }
        else
            if isTextMode then
                tabs[#tabs + 1] = { value = "format", text = "Format" }
            end
            -- Entries expose Layout only when they own placement controls.
            if not isSingleEntry or (availableTabs and availableTabs.layout) then
                tabs[#tabs + 1] = { value = "layout", text = "Layout" }
            end
            if not availableTabs or availableTabs.appearance then tabs[#tabs + 1] = { value = "appearance", text = "Appearance" } end
            if not isTextMode and (not availableTabs or availableTabs.effects) then
                tabs[#tabs + 1] = { value = "effects", text = "Indicators" }
            end
            tabs[#tabs + 1] = { value = "loadconditions",  text = "Visibility" }
        end
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
    if isRotationEntry then
        CS.selectedTab = "loadconditions"
    elseif isSingleEntry and CS.selectedTab == "layout" and not (availableTabs and availableTabs.layout) then
        CS.selectedTab = isTextMode and "format" or "appearance"
    end
    if availableTabs and not availableTabs[CS.selectedTab] then
        for _, candidate in ipairs({ "layout", "appearance", "effects", "loadconditions" }) do
            if availableTabs[candidate] then CS.selectedTab = candidate; break end
        end
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
    local savedOffset, savedScrollvalue, savedScope, savedOwner
    if CS.col4Scroll then
        local s = CS.col4Scroll.status or CS.col4Scroll.localstatus
        if s and s.offset and s.offset > 0 then
            savedOffset = s.offset
            savedScrollvalue = s.scrollvalue
            savedScope = CS.col4Scroll._cdcSettingsScopeKey
            savedOwner = CS.col4Scroll._cdcSettingsOwner
        end
    end

    -- Show and refresh the tab content (SelectTab fires callback synchronously,
    -- which releases old col4Scroll and creates a new one)
    SelectPanelSettingsTabProgrammatic(container.tabGroup, CS.selectedTab)

    -- Restore the saved position; a full refresh applies it after the
    -- inline Advanced editor is reinserted, before returning to rendering.
    if savedOffset and CS.col4Scroll and savedScope == CS.col4Scroll._cdcSettingsScopeKey
        and savedOwner == CS.col4Scroll._cdcSettingsOwner then
        local s = CS.col4Scroll.status or CS.col4Scroll.localstatus
        if s then
            s.offset = savedOffset
            s.scrollvalue = savedScrollvalue
            CS.FixConfigScroll(CS.col4Scroll)
        end
    end
end

ST._RefreshGroupSettingsHost = RefreshGroupSettingsHost
-- For the few outside callers that rebuild the current panel tab in place.
-- Going through this instead of SelectTab keeps a rebuild from being mistaken
-- for the user choosing a tab.
ST._SelectPanelSettingsTabProgrammatic = SelectPanelSettingsTabProgrammatic
