--[[
    CooldownCompanion - Config/Column4
    RefreshColumn4, RefreshProfileBar.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig

------------------------------------------------------------------------
-- COLUMN 4: Group / Panel Settings Column
------------------------------------------------------------------------
local function ClearInfoButtons(buttons)
    if type(buttons) ~= "table" then
        return
    end

    for _, btn in ipairs(buttons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(buttons)
end

local function FindSelectedCustomBar()
    if not CS.selectedCustomBarId or not CooldownCompanion.GetSpecCustomAuraBars then
        return nil
    end

    local settings = CooldownCompanion:GetResourceBarSettings()
    if ST._RB and ST._RB.FindCustomBarById then
        return ST._RB.FindCustomBarById(settings, CS.selectedCustomBarId)
    end

    for _, entry in ipairs(CooldownCompanion:GetSpecCustomAuraBars() or {}) do
        if type(entry) == "table" and entry.customBarId == CS.selectedCustomBarId then
            return entry
        end
    end
    return nil
end

local function GetCustomBarEntryTabs(entry)
    local tabs = {
        { value = "appearance", text = "Appearance" },
        { value = "indicators", text = "Indicators" },
    }

    tabs[#tabs + 1] = { value = "soundalerts", text = "Sound Alerts" }
    tabs[#tabs + 1] = { value = "loadconditions", text = "Load Conditions" }
    return tabs
end

local function IsCustomBarEntryTabAllowed(entry, tab)
    if tab == "appearance" or tab == "indicators" or tab == "soundalerts" or tab == "loadconditions" then
        return true
    end
    return false
end

local function GetCustomBarDetailScrollKey()
    if not CS.selectedCustomBarId then return nil end
    return tostring(CS.selectedCustomBarId) .. ":" .. tostring(CS.customBarSettingsTab or "appearance")
end

local function ShowCustomBarMultiSelect(container, selectedIds, selectedEntries)
    if container.placeholderLabel then
        container.placeholderLabel:Hide()
    end
    if container.customBarEntryTabGroup then
        container.customBarEntryTabGroup.frame:Hide()
    end
    if container.customBarsDetailScroll then
        container.customBarsDetailScroll.frame:Hide()
    end
    if container.layoutOrderHost then
        container.layoutOrderHost:Hide()
    end
    if not container.customBarsMultiSelectScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(container)
        container.customBarsMultiSelectScroll = scroll
    end
    local scroll = container.customBarsMultiSelectScroll
    scroll.frame:SetParent(container)
    scroll.frame:ClearAllPoints()
    scroll.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    scroll.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    scroll:ReleaseChildren()
    scroll.frame:Show()

    local heading = AceGUI:Create("Heading")
    heading:SetText(#selectedEntries .. " Custom Bars Selected")
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local function AddSpacer()
        local sp = AceGUI:Create("Label")
        sp:SetText(" ")
        sp:SetFullWidth(true)
        local f, _, fl = sp.label:GetFont()
        sp:SetFont(f, 3, fl or "")
        scroll:AddChild(sp)
    end

    local anyDisabled = false
    for _, entry in ipairs(selectedEntries) do
        if entry.enabled ~= true then
            anyDisabled = true
            break
        end
    end

    local enableBtn = AceGUI:Create("Button")
    enableBtn:SetText(anyDisabled and "Enable Selected" or "Disable Selected")
    enableBtn:SetFullWidth(true)
    enableBtn:SetCallback("OnClick", function()
        for _, entry in ipairs(selectedEntries) do
            entry.enabled = anyDisabled and true or false
            if entry.enabled and not entry.trackingMode then
                entry.trackingMode = "active"
            end
        end
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(enableBtn)

    AddSpacer()

    local exportBtn = AceGUI:Create("Button")
    exportBtn:SetText("Export Selected")
    exportBtn:SetFullWidth(true)
    exportBtn:SetCallback("OnClick", function()
        local settings = CooldownCompanion:GetResourceBarSettings()
        local payload = ST._RB.BuildCustomBarsExportPayload and ST._RB.BuildCustomBarsExportPayload(settings, selectedEntries)
        local exportString = payload and ST._EncodeExportData and ST._EncodeExportData(payload)
        if exportString then
            CS.ShowPopupAboveConfig("CDC_EXPORT_CUSTOM_BARS", nil, { exportString = exportString })
        else
            CooldownCompanion:Print("Export failed: Custom Bar data was unavailable.")
        end
    end)
    scroll:AddChild(exportBtn)

    AddSpacer()

    local deleteBtn = AceGUI:Create("Button")
    deleteBtn:SetText("Delete Selected")
    deleteBtn:SetFullWidth(true)
    deleteBtn:SetCallback("OnClick", function()
        CS.ShowPopupAboveConfig("CDC_DELETE_SELECTED_CUSTOM_BARS", #selectedIds, { ids = selectedIds })
    end)
    scroll:AddChild(deleteBtn)
end

local function RefreshColumn4(container)
    -- Hide browse placeholder
    if container._browsePlaceholder then
        container._browsePlaceholder:Hide()
    end

    -- Resource Bar panel mode: show selected Custom Bar settings, or Layout & Order.
    if CS.resourceBarPanelActive then
        if container.placeholderLabel then
            container.placeholderLabel:Hide()
        end
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        if container.containerTabGroup then
            container.containerTabGroup.frame:Hide()
        end
        if container.folderTabGroup then
            container.folderTabGroup.frame:Hide()
        end
        if container.customAuraScroll then
            container.customAuraScroll.frame:Hide()
        end
        if container.layoutOrderScroll then
            container.layoutOrderScroll.frame:Hide()
        end
        if container.customBarsDetailScroll then
            container.customBarsDetailScroll.frame:Hide()
        end
        if container.customBarsMultiSelectScroll then
            container.customBarsMultiSelectScroll.frame:Hide()
        end
        if container.customBarEntryTabGroup then
            container.customBarEntryTabGroup.frame:Hide()
        end
        local selectedCustomBarIds = {}
        local selectedCustomBarEntries = {}
        local settings = CooldownCompanion:GetResourceBarSettings()
        for customBarId in pairs(CS.selectedCustomBars) do
            local entry = ST._RB.FindCustomBarById and ST._RB.FindCustomBarById(settings, customBarId)
            if entry then
                selectedCustomBarIds[#selectedCustomBarIds + 1] = customBarId
                selectedCustomBarEntries[#selectedCustomBarEntries + 1] = entry
            else
                CS.selectedCustomBars[customBarId] = nil
            end
        end
        table.sort(selectedCustomBarIds)
        if #selectedCustomBarEntries >= 2 then
            ShowCustomBarMultiSelect(container, selectedCustomBarIds, selectedCustomBarEntries)
            return
        end
        if CS.selectedCustomBarId then
            if container.layoutOrderHost then
                container.layoutOrderHost:Hide()
            end

            local selectedEntry = FindSelectedCustomBar()
            if not selectedEntry then
                CS.selectedCustomBarId = nil
                CS.customBarSettingsTab = "appearance"
            else
                if CS.customBarSettingsTab == "settings"
                    or CS.customBarSettingsTab == "layout"
                    or CS.customBarSettingsTab == "anchor"
                    or CS.customBarSettingsTab == "alpha"
                then
                    CS.customBarSettingsTab = "appearance"
                end
                if not IsCustomBarEntryTabAllowed(selectedEntry, CS.customBarSettingsTab) then
                    CS.customBarSettingsTab = "appearance"
                end

                if not container.customBarEntryTabGroup then
                    local tabGroup = AceGUI:Create("TabGroup")
                    tabGroup:SetLayout("Fill")
                    tabGroup.frame:SetParent(container)
                    tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
                        CS.customBarSettingsTab = tab or "appearance"
                        if CS.customBarSettingsTab ~= "indicators" then
                            if CooldownCompanion.ClearAllCustomAuraBarPreviews then
                                CooldownCompanion:ClearAllCustomAuraBarPreviews()
                            end
                            if CS.customBarIndicatorPreviewActive and CooldownCompanion.StopResourceBarPreview then
                                CooldownCompanion:StopResourceBarPreview()
                            end
                        end
                        ClearInfoButtons(CS.customBarInfoButtons)
                        widget:ReleaseChildren()

                        local scroll = AceGUI:Create("ScrollFrame")
                        scroll:SetLayout("List")
                        widget:AddChild(scroll)
                        container.customBarsDetailScroll = scroll
                        CS.customBarSettingsScroll = scroll
                        container._customBarDetailScrollKey = GetCustomBarDetailScrollKey()
                        ST._BuildCustomAuraBarPanel(scroll, CS.selectedCustomBarId, CS.customBarSettingsTab)
                    end)
                    container.customBarEntryTabGroup = tabGroup
                end

                local tabGroup = container.customBarEntryTabGroup
                if container.customBarsMultiSelectScroll then
                    container.customBarsMultiSelectScroll.frame:Hide()
                end
                tabGroup.frame:ClearAllPoints()
                tabGroup.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
                tabGroup.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
                tabGroup:SetTabs(GetCustomBarEntryTabs(selectedEntry))
                tabGroup.frame:Show()

                local savedOffset, savedScrollvalue
                local currentScrollKey = GetCustomBarDetailScrollKey()
                if container.customBarsDetailScroll and container._customBarDetailScrollKey == currentScrollKey then
                    local state = container.customBarsDetailScroll.status or container.customBarsDetailScroll.localstatus
                    if state and state.offset and state.offset > 0 then
                        savedOffset = state.offset
                        savedScrollvalue = state.scrollvalue
                    end
                end

                tabGroup:SelectTab(CS.customBarSettingsTab or "appearance")

                if savedOffset and container.customBarsDetailScroll then
                    local state = container.customBarsDetailScroll.status or container.customBarsDetailScroll.localstatus
                    if state then
                        state.offset = savedOffset
                        state.scrollvalue = savedScrollvalue
                    end
                end
                return
            end
        end
        if container.customBarEntryTabGroup then
            container.customBarEntryTabGroup.frame:Hide()
        end
        if container.customBarsDetailScroll then
            container.customBarsDetailScroll.frame:Hide()
        end
        if container.customBarsMultiSelectScroll then
            container.customBarsMultiSelectScroll.frame:Hide()
        end
        if not CS.selectedCustomBarId then
            -- Fall through to Layout & Order when the selected Custom Bar was removed.
        else
            return
        end
        if not container.layoutOrderHost then
            local host = CreateFrame("Frame", nil, container)
            host:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            host:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            host:SetClipsChildren(false)
            host:Hide()
            container.layoutOrderHost = host
        end
        container.layoutOrderHost:Show()
        ST._BuildLayoutOrderPanel(container.layoutOrderHost)
        return
    end
    if container.layoutOrderHost then
        container.layoutOrderHost:Hide()
    end
    if container.customBarsDetailScroll then
        container.customBarsDetailScroll.frame:Hide()
    end
    if container.customBarsMultiSelectScroll then
        container.customBarsMultiSelectScroll.frame:Hide()
    end
    if container.customBarEntryTabGroup then
        container.customBarEntryTabGroup.frame:Hide()
    end
    -- Hide layout order scroll if it exists
    if container.layoutOrderScroll then
        container.layoutOrderScroll.frame:Hide()
    end
    -- Hide custom aura scroll if it exists (now lives in col3)
    if container.customAuraScroll then
        container.customAuraScroll.frame:Hide()
    end

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

                if CS.browseMode then
                    ST._DisableAllWidgets(scroll)
                end
            end)
            tabGroup.frame:SetParent(container)
            tabGroup.frame:ClearAllPoints()
            tabGroup.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            tabGroup.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            container.folderTabGroup = tabGroup
        end

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

                if CS.browseMode then
                    ST._DisableAllWidgets(scroll)
                end
            end)
            tabGroup.frame:SetParent(container)
            tabGroup.frame:ClearAllPoints()
            tabGroup.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            tabGroup.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            container.containerTabGroup = tabGroup
        end

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

    -- Single panel selection: show panel settings in Column 4 whether the panel
    -- itself or one of its buttons is selected.
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

            if CS.browseMode then
                ST._DisableAllWidgets(scroll)
                for _, btn in ipairs(CS.tabInfoButtons) do
                    if btn.Disable then btn:Disable() end
                end
            end
        end)

        -- Parent the AceGUI widget frame to our raw column frame
        tabGroup.frame:SetParent(container)
        tabGroup.frame:ClearAllPoints()
        tabGroup.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        tabGroup.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)

        container.tabGroup = tabGroup
    end

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

local function RefreshProfileBar(bar)
    -- Release tracked AceGUI widgets
    for _, widget in ipairs(CS.profileBarAceWidgets) do
        widget:Release()
    end
    wipe(CS.profileBarAceWidgets)

    local db = CooldownCompanion.db
    local profiles = db:GetProfiles()
    local currentProfile = db:GetCurrentProfile()

    -- Build ordered profile list for AceGUI Dropdown
    local profileList = {}
    for _, name in ipairs(profiles) do
        profileList[name] = name
    end

    -- Profile dropdown (no label, compact)
    local profileDrop = AceGUI:Create("Dropdown")
    profileDrop:SetLabel("")
    profileDrop:SetList(profileList, profiles)
    profileDrop:SetValue(currentProfile)
    profileDrop:SetWidth(150)
    profileDrop:SetCallback("OnValueChanged", function(widget, event, val)
        CooldownCompanion:ClearAllConfigPreviews()
        db:SetProfile(val)
        CS.selectedFolder = nil
        CS.selectedContainer = nil
        CS.selectedGroup = nil
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        wipe(CS.selectedGroups)
        -- Exit browse mode on profile switch
        CS.browseMode = false
        CS.browseCharKey = nil
        CS.browseContainerId = nil
        CooldownCompanion:RefreshConfigPanel()
        CooldownCompanion:RefreshAllGroups()
    end)
    profileDrop.frame:SetParent(bar)
    profileDrop.frame:ClearAllPoints()
    profileDrop.frame:SetPoint("LEFT", bar, "LEFT", 0, 0)
    profileDrop.frame:Show()
    table.insert(CS.profileBarAceWidgets, profileDrop)

    -- Helper to create horizontally chained buttons
    local lastAnchor = profileDrop.frame
    local createdButtons = {}
    local PROFILE_BAR_BUTTON_MIN_WIDTH = 55
    local PROFILE_BAR_BUTTON_EXTRA_PADDING = 8
    local PROFILE_BAR_BUTTON_TRUNCATION_STEP = 4
    local PROFILE_BAR_BUTTON_TRUNCATION_MAX_WIDTH = 220
    local function AddBarButton(text, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        btn:SetAutoWidth(true)
        btn:SetCallback("OnClick", onClick)
        btn.frame:SetParent(bar)
        btn.frame:ClearAllPoints()
        btn.frame:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        btn:SetHeight(22)
        local measuredWidth = btn.frame:GetWidth() or 0
        local desiredWidth = math.max(PROFILE_BAR_BUTTON_MIN_WIDTH, measuredWidth + PROFILE_BAR_BUTTON_EXTRA_PADDING)
        btn:SetWidth(desiredWidth)
        btn.frame:Show()
        table.insert(CS.profileBarAceWidgets, btn)
        table.insert(createdButtons, btn)
        lastAnchor = btn.frame
        return btn
    end

    AddBarButton("New", function()
        ShowPopupAboveConfig("CDC_NEW_PROFILE")
    end)

    AddBarButton("Rename", function()
        ShowPopupAboveConfig("CDC_RENAME_PROFILE", currentProfile, { oldName = currentProfile })
    end)

    AddBarButton("Duplicate", function()
        ShowPopupAboveConfig("CDC_DUPLICATE_PROFILE", nil, { source = currentProfile })
    end)

    AddBarButton("Delete", function()
        local allProfiles = db:GetProfiles()
        local isOnly = #allProfiles <= 1
        if isOnly then
            ShowPopupAboveConfig("CDC_RESET_PROFILE", currentProfile, { profileName = currentProfile, isOnly = true })
        else
            ShowPopupAboveConfig("CDC_DELETE_PROFILE", currentProfile, { profileName = currentProfile })
        end
    end)

    AddBarButton("Export", function()
        ShowPopupAboveConfig("CDC_EXPORT_PROFILE")
    end)

    AddBarButton("Import", function()
        ShowPopupAboveConfig("CDC_IMPORT_PROFILE")
    end)

    -- Keep widening while text truncates so skin/font variations don't clip labels.
    for _, btn in ipairs(createdButtons) do
        local fontString = btn.frame.GetFontString and btn.frame:GetFontString() or nil
        if fontString and fontString.IsTruncated and fontString:IsTruncated() then
            local width = btn.frame:GetWidth() or PROFILE_BAR_BUTTON_MIN_WIDTH
            while width < PROFILE_BAR_BUTTON_TRUNCATION_MAX_WIDTH and fontString:IsTruncated() do
                width = math.min(PROFILE_BAR_BUTTON_TRUNCATION_MAX_WIDTH, width + PROFILE_BAR_BUTTON_TRUNCATION_STEP)
                btn:SetWidth(width)
            end
        end
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn4 = RefreshColumn4
ST._RefreshProfileBar = RefreshProfileBar
