--[[
    CooldownCompanion - Config/WorkspaceRouter
    Routes the workspace to button, Resources / Cast Bar & Unit Frames,
    or Other Class browsing surfaces.
]]

local _, ST = ...
local CS = ST._configState

------------------------------------------------------------------------
-- Workspace: button settings / Resources, Cast Bar & Unit Frames home
------------------------------------------------------------------------
local function RefreshColumn3()
    -- Plain buttons view: the workspace owns the editing surface.
    if ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive() then
        return ST._RefreshButtonsWideColumn()
    end

    -- Resources, Cast Bar & Unit Frames: one workspace preview, whose
    -- selected object decides which settings surface shows beneath it. The
    -- Navigator keeps only the destination row here.
    if CS.barsEntrySelected then
        local col3 = CS.configFrame and CS.configFrame.col3
        if not col3 then ST._RefreshButtonSettingsColumn() return end

        -- Hide button settings content that lives on the same col3 content area
        if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
        if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
        if col3._multiSelectActionsScroll then col3._multiSelectActionsScroll.frame:Hide() end
        if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
        if ST._HideButtonsPanelPreviewSurfaces then ST._HideButtonsPanelPreviewSurfaces(col3) end

        -- One dispatcher for the whole destination: it picks the canvas,
        -- the overview pane, or the conflict gate on its own.
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
