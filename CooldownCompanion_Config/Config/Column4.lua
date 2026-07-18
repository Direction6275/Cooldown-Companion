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
local ResetConfigSelection = ST._ResetConfigSelection
local RefreshGroupSettingsHost = ST._RefreshGroupSettingsHost

------------------------------------------------------------------------
-- COLUMN 4: Group / Panel Settings Column
------------------------------------------------------------------------
local function HideWidgetFrame(widget)
    if widget and widget.frame then
        widget.frame:Hide()
    end
end

local function HideFrame(frame)
    if frame then
        frame:Hide()
    end
end

local function HideLayoutOrderConflictScroll(container)
    HideWidgetFrame(container.layoutOrderConflictScroll)
end

local function HideResourceBarPanelSurfaces(container)
    HideFrame(container.placeholderLabel)
    HideWidgetFrame(container.tabGroup)
    HideWidgetFrame(container.containerTabGroup)
    HideWidgetFrame(container.folderTabGroup)
    HideWidgetFrame(container.customAuraScroll)
    HideWidgetFrame(container.layoutOrderScroll)
    HideWidgetFrame(container.customBarsDetailScroll)
    HideWidgetFrame(container.customBarsMultiSelectScroll)
    HideWidgetFrame(container.customBarEntryTabGroup)
    HideWidgetFrame(container.resourceSettingsDetailScroll)
    HideWidgetFrame(container.resourceSettingsTabGroup)
    HideWidgetFrame(container.resourcesTabGroup)
    HideFrame(container.resourcesPreviewHost)
    HideWidgetFrame(container.castBarHomeTabGroup)
    HideFrame(container._castBarIntroPane)
    HideLayoutOrderConflictScroll(container)
end

local function ShowLayoutOrderConflictScroll(container)
    HideResourceBarPanelSurfaces(container)

    if not container.layoutOrderConflictScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(container)
        container.layoutOrderConflictScroll = scroll
    end

    local scroll = container.layoutOrderConflictScroll
    scroll.frame:SetParent(container)
    scroll.frame:ClearAllPoints()
    scroll.frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
    scroll.frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    scroll:ReleaseChildren()
    scroll.frame:Show()

    local RBP = ST._RBP
    if RBP and RBP.BuildResourceBarConflictGate
        and RBP.BuildResourceBarConflictGate(scroll, "Layout & Order", true)
    then
        return
    end

    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText("Resolve Resource Bars before editing Layout & Order.")
    label:SetFullWidth(true)
    scroll:AddChild(label)
end

-- In the Resources and Cast Bar homes a persistent Layout & Order preview
-- pane occupies the top of the column; every settings surface anchors
-- beneath it. When no preview pane is shown (e.g. a per-bar detail page
-- replacing it) surfaces fill the whole column.
local function AnchorResourcesContentFrame(container, frame)
    frame:ClearAllPoints()
    local previewHost = container.resourcesPreviewHost
    if (CS.resourcesEntrySelected or CS.castFramesEntrySelected)
        and previewHost and previewHost:IsShown() then
        frame:SetPoint("TOPLEFT", previewHost, "BOTTOMLEFT", 0, -4)
        frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    else
        frame:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", container, "BOTTOMRIGHT", 0, 0)
    end
end

local function RefreshColumn4(container)
    -- Wide col3 layouts (plain buttons view, Resources home): column 4 is
    -- hidden and the wide column 3 hosts these surfaces instead
    -- (ButtonsWideColumn.lua / ResourcesWideColumn.lua).
    if ST._IsWideCol3LayoutActive and ST._IsWideCol3LayoutActive() then
        return
    end

    HideLayoutOrderConflictScroll(container)

    -- Cast Bar & Unit Frames home: col4 = Cast Bar, with the persistent
    -- Layout & Order preview pane pinned at the top like the Resources home
    if CS.castFramesEntrySelected then
        HideResourceBarPanelSurfaces(container)
        if CooldownCompanion.GetCurrentResourceBarConflict and CooldownCompanion:GetCurrentResourceBarConflict() then
            ShowLayoutOrderConflictScroll(container)
            return
        end

        local settings = CooldownCompanion:GetCastBarSettings()
        if not (settings and settings.enabled) then
            if ST._ShowColumnIntroPane then
                ST._ShowColumnIntroPane(container, "_castBarIntroPane", {
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
            end
            return
        end

        local previewHost = container.resourcesPreviewHost
        if not previewHost then
            previewHost = CreateFrame("Frame", nil, container)
            previewHost:SetClipsChildren(false)
            container.resourcesPreviewHost = previewHost
        end
        previewHost:ClearAllPoints()
        previewHost:SetPoint("TOPLEFT", container, "TOPLEFT", 0, 0)
        previewHost:SetPoint("TOPRIGHT", container, "TOPRIGHT", 0, 0)
        local columnHeight = container:GetHeight() or 0
        previewHost:SetHeight(math.max(150, math.floor(columnHeight * 0.35)))
        previewHost:Show()
        ST._BuildLayoutOrderPanel(previewHost)

        if not container.castBarHomeTabGroup then
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
                container.castBarHomeScroll = scroll
                container._castBarHomeScrollKey = "castbar:" .. tab
                if tab == "general" then
                    ST._BuildCastBarAnchoringPanel(scroll)
                elseif tab == "appearance" then
                    ST._BuildCastBarStylingPanel(scroll)
                elseif tab == "layout" then
                    ST._BuildCastBarPositioningPanel(scroll)
                end
            end)
            tabGroup.frame:SetParent(container)
            container.castBarHomeTabGroup = tabGroup
        end

        local tabGroup = container.castBarHomeTabGroup
        AnchorResourcesContentFrame(container, tabGroup.frame)
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
        if container.castBarHomeScroll and container._castBarHomeScrollKey == currentScrollKey then
            local state = container.castBarHomeScroll.status or container.castBarHomeScroll.localstatus
            if state and state.offset and state.offset > 0 then
                savedOffset = state.offset
                savedScrollvalue = state.scrollvalue
            end
        end

        tabGroup.frame:Show()
        tabGroup:SelectTab(tab)

        if savedOffset and container.castBarHomeScroll then
            local state = container.castBarHomeScroll.status or container.castBarHomeScroll.localstatus
            if state then
                state.offset = savedOffset
                state.scrollvalue = savedScrollvalue
            end
        end
        return
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
    if container.resourceSettingsDetailScroll then
        container.resourceSettingsDetailScroll.frame:Hide()
    end
    if container.resourceSettingsTabGroup then
        container.resourceSettingsTabGroup.frame:Hide()
    end
    if container.resourcesTabGroup then
        container.resourcesTabGroup.frame:Hide()
    end
    if container.resourcesPreviewHost then
        container.resourcesPreviewHost:Hide()
    end
    if container.castBarHomeTabGroup then
        container.castBarHomeTabGroup.frame:Hide()
    end
    if container._castBarIntroPane then
        container._castBarIntroPane:Hide()
    end
    -- Hide layout order scroll if it exists
    if container.layoutOrderScroll then
        container.layoutOrderScroll.frame:Hide()
    end
    -- Hide custom aura scroll if it exists (now lives in col3)
    if container.customAuraScroll then
        container.customAuraScroll.frame:Hide()
    end

    -- Group-side settings surfaces (multi-select placeholders, folder,
    -- container, and single-panel tabs) live in GroupSettingsHost.lua;
    -- their widgets are still stored on this container.
    RefreshGroupSettingsHost(container)
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
        ResetConfigSelection(true)
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

    AddBarButton("Export Backup", function()
        ShowPopupAboveConfig("CDC_EXPORT_PROFILE")
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
