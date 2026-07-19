--[[
    CooldownCompanion - Config/WorkspaceRouter
    Routes the workspace to button, Resources, Cast Bar & Unit Frames,
    or Other Class browsing surfaces.
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
-- Workspace: button settings / Resources home / Unit Frames home
------------------------------------------------------------------------
local function RefreshColumn3()
    -- Plain buttons view: the workspace owns the editing surface.
    if ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive() then
        return ST._RefreshButtonsWideColumn()
    end

    -- Cast Bar & Unit Frames home: the Navigator lists Cast Bar / Player
    -- Frame / Target Frame; the workspace hosts preview and settings.
    if CS.castFramesEntrySelected then
        local col3 = CS.configFrame and CS.configFrame.col3
        if not col3 then return end

        -- Hide content that shares the col3 content area
        if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
        if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
        if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
        if col3._panelTabGroup then col3._panelTabGroup.frame:Hide() end
        if col3._panelMultiSelectScroll then col3._panelMultiSelectScroll.frame:Hide() end
        if col3._browseEntryScroll then col3._browseEntryScroll.frame:Hide() end
        if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
        if ST._HideButtonsPanelPreviewSurfaces then ST._HideButtonsPanelPreviewSurfaces(col3) end

        return ST._RefreshCastFramesWideColumn(col3)
    end

    -- Resources home: the Navigator owns the Custom Bars & Resources list;
    -- the workspace hosts preview and settings.
    if CS.resourcesEntrySelected then
        local col3 = CS.configFrame and CS.configFrame.col3
        if not col3 then ST._RefreshButtonSettingsColumn() return end

        -- Hide button settings content that lives on the same col3 content area
        if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
        if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
        if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
        if col3._panelTabGroup then col3._panelTabGroup.frame:Hide() end
        if col3._panelMultiSelectScroll then col3._panelMultiSelectScroll.frame:Hide() end
        if col3._browseEntryScroll then col3._browseEntryScroll.frame:Hide() end
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
        if ST._HideButtonsPanelPreviewSurfaces then ST._HideButtonsPanelPreviewSurfaces(col3) end

        if col3._customAuraTabGroup then
            col3._customAuraTabGroup.frame:Hide()
        end

        -- Disabled home: the single wide intro pane replaces the settings
        if ST._IsResourcesEmptyStateActive and ST._IsResourcesEmptyStateActive() then
            if ST._HideResourcesWideSurfaces then
                ST._HideResourcesWideSurfaces(col3)
            end
            ShowResourcesIntroPane(col3)
            return
        end

        return ST._RefreshResourcesWideColumn(col3)
    end

    -- Other Class browsing (and any residual state): the same merged wide
    -- column. RefreshButtonsWideColumn skips the pinned preview cluster
    -- while browsing - browsed panels render live in the world - and its
    -- first refresh after a view switch releases the buttons preview.
    return ST._RefreshButtonsWideColumn()
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._RefreshColumn3 = RefreshColumn3
