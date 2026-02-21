--[[
    CooldownCompanion - Config/Column3
    RefreshColumn3, RefreshProfileBar.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local AceGUI = LibStub("AceGUI-3.0")

-- Imports from earlier Config/ files
local ShowPopupAboveConfig = ST._ShowPopupAboveConfig

------------------------------------------------------------------------
-- COLUMN 3: Group Settings / Tab Column
------------------------------------------------------------------------
local function RefreshColumn3(container)
    -- Cast Bar panel mode: show cast bar settings instead of group settings
    if CS.castBarPanelActive then
        if container.placeholderLabel then
            container.placeholderLabel:Hide()
        end
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        if container.customAuraScroll then
            container.customAuraScroll.frame:Hide()
        end
        if container.frameAnchoringScroll then
            container.frameAnchoringScroll.frame:Hide()
        end
        -- Create or reuse the cast bar scroll frame
        if not container.castBarScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(container)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            container.castBarScroll = scroll
        end
        container.castBarScroll:ReleaseChildren()
        container.castBarScroll.frame:Show()
        ST._BuildCastBarStylingPanel(container.castBarScroll)
        return
    end
    -- Hide cast bar scroll if it exists
    if container.castBarScroll then
        container.castBarScroll.frame:Hide()
    end

    -- Resource Bar panel mode: show custom aura bar panel instead of group settings
    if CS.resourceBarPanelActive then
        if container.placeholderLabel then
            container.placeholderLabel:Hide()
        end
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        if container.frameAnchoringScroll then
            container.frameAnchoringScroll.frame:Hide()
        end
        if not container.customAuraScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(container)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            container.customAuraScroll = scroll
        end
        container.customAuraScroll:ReleaseChildren()
        container.customAuraScroll.frame:Show()
        ST._BuildCustomAuraBarPanel(container.customAuraScroll)
        return
    end
    -- Hide custom aura scroll if it exists
    if container.customAuraScroll then
        container.customAuraScroll.frame:Hide()
    end

    -- Frame Anchoring panel mode: show target frame settings
    if CS.frameAnchoringPanelActive then
        if container.placeholderLabel then
            container.placeholderLabel:Hide()
        end
        if container.tabGroup then
            container.tabGroup.frame:Hide()
        end
        if not container.frameAnchoringScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(container)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
            container.frameAnchoringScroll = scroll
        end
        container.frameAnchoringScroll:ReleaseChildren()
        container.frameAnchoringScroll.frame:Show()
        ST._BuildFrameAnchoringTargetPanel(container.frameAnchoringScroll)
        return
    end
    -- Hide frame anchoring scroll if it exists
    if container.frameAnchoringScroll then
        container.frameAnchoringScroll.frame:Hide()
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
        return
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

    if container.placeholderLabel then
        container.placeholderLabel:Hide()
    end

    -- Create the TabGroup once, reuse on subsequent refreshes
    if not container.tabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")

        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            CS.selectedTab = tab
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
            CS.col3Scroll = scroll

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

        -- Parent the AceGUI widget frame to our raw column frame
        tabGroup.frame:SetParent(container)
        tabGroup.frame:ClearAllPoints()
        tabGroup.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        tabGroup.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)

        container.tabGroup = tabGroup
    end

    -- Update tabs every refresh so the effects tab label reflects current group mode
    local effectsLabel = "Indicators"
    container.tabGroup:SetTabs({
        { value = "appearance",      text = "Appearance" },
        { value = "effects",         text = effectsLabel },
        { value = "layout",          text = "Layout" },
        { value = "loadconditions",  text = "Load Conditions" },
    })

    -- Save AceGUI scroll state before tab re-select (old col3Scroll will be released)
    local savedOffset, savedScrollvalue
    if CS.col3Scroll then
        local s = CS.col3Scroll.status or CS.col3Scroll.localstatus
        if s and s.offset and s.offset > 0 then
            savedOffset = s.offset
            savedScrollvalue = s.scrollvalue
        end
    end

    -- Migrate stale tab keys from previous layout
    if CS.selectedTab == "extras" then CS.selectedTab = "effects" end
    if CS.selectedTab == "positioning" then CS.selectedTab = "layout" end

    -- Show and refresh the tab content (SelectTab fires callback synchronously,
    -- which releases old col3Scroll and creates a new one)
    container.tabGroup.frame:Show()
    container.tabGroup:SelectTab(CS.selectedTab)

    -- Restore scroll state on the new col3Scroll widget.  LayoutFinished has already
    -- scheduled FixScrollOnUpdate for next frame — it will read these values.
    if savedOffset and CS.col3Scroll then
        local s = CS.col3Scroll.status or CS.col3Scroll.localstatus
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
        db:SetProfile(val)
        CS.selectedGroup = nil
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        wipe(CS.selectedGroups)
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
    local function AddBarButton(text, width, onClick)
        local btn = AceGUI:Create("Button")
        btn:SetText(text)
        btn:SetWidth(width)
        btn:SetCallback("OnClick", onClick)
        btn.frame:SetParent(bar)
        btn.frame:ClearAllPoints()
        btn.frame:SetPoint("LEFT", lastAnchor, "RIGHT", 4, 0)
        btn:SetHeight(22)
        btn.frame:Show()
        table.insert(CS.profileBarAceWidgets, btn)
        lastAnchor = btn.frame
        return btn
    end

    AddBarButton("New", 55, function()
        ShowPopupAboveConfig("CDC_NEW_PROFILE")
    end)

    AddBarButton("Rename", 80, function()
        ShowPopupAboveConfig("CDC_RENAME_PROFILE", currentProfile, { oldName = currentProfile })
    end)

    AddBarButton("Duplicate", 90, function()
        ShowPopupAboveConfig("CDC_DUPLICATE_PROFILE", nil, { source = currentProfile })
    end)

    AddBarButton("Delete", 70, function()
        local allProfiles = db:GetProfiles()
        local isOnly = #allProfiles <= 1
        if isOnly then
            ShowPopupAboveConfig("CDC_RESET_PROFILE", currentProfile, { profileName = currentProfile, isOnly = true })
        else
            ShowPopupAboveConfig("CDC_DELETE_PROFILE", currentProfile, { profileName = currentProfile })
        end
    end)

    AddBarButton("Export", 75, function()
        ShowPopupAboveConfig("CDC_EXPORT_PROFILE")
    end)

    AddBarButton("Import", 75, function()
        ShowPopupAboveConfig("CDC_IMPORT_PROFILE")
    end)
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn3 = RefreshColumn3
ST._RefreshProfileBar = RefreshProfileBar
