--[[
    CooldownCompanion - Config/UnifiedTabRow
    One visual tab row spanning the two AceGUI TabGroups of the buttons
    workspace: the panel-scope strip owned by GroupSettingsHost and the
    entry-scope strip created in Panel.lua. The groups stay separate -
    each keeps its own content pipeline, scroll restore and info-button
    lifecycle - and only their tab strips are made to share a row.

    Panel tabs are pinned to a single natural-width row on the left and
    never reflow. Selecting an entry appends that entry's tabs after a
    tab-width gap; they wrap inside whatever space is left. Exactly one
    tab reads as selected across both strips, and only the scope that owns
    the surface shows content, so a panel tab can be opened without
    dropping the entry selection.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Delineation between the two clusters (no boxes): roughly one tab of
-- clear space, the entry icon at the head of the entry cluster, and the
-- accent tint on entry tab labels (applied by the tab-text builders).
local CLUSTER_GAP = 80

-- AceGUI BuildTabs geometry, mirrored here so the strips can be re-laid
-- out without duplicating its row math: rows sit 20px apart, an untitled
-- strip starts 10px down, and neighbouring tabs overlap by 10px.
local TAB_ROW_PITCH = 20
local TAB_STRIP_INSET = 10
local TAB_OVERLAP = 10

-- Wrap budget handed to the panel strip. Large enough that BuildTabs never
-- wraps it and never pads its tabs out to fill the row, so panel tabs keep
-- natural widths and stay put when the entry cluster appears or leaves.
local PANEL_STRIP_BUDGET = 100000

-- Floor for the entry cluster's wrap budget. Below this the cluster is
-- unusable as a strip, so it is allowed to run past the right edge instead
-- (the accepted narrow-window edge) rather than wrapping one tab per row.
local MIN_ENTRY_STRIP = 120

------------------------------------------------------------------------
-- Strip geometry
------------------------------------------------------------------------

-- Rendered width of a strip's leading row, matching how BuildTabs chains
-- tabs (each anchored 10px into its predecessor).
local function MeasureStripWidth(tabGroup)
    if not tabGroup then return 0 end
    local total, count = 0, 0
    for _, tab in ipairs(tabGroup.tabs) do
        if tab:IsShown() then
            total = total + (tab:GetWidth() or 0)
            count = count + 1
        end
    end
    if count == 0 then return 0 end
    return total - TAB_OVERLAP * (count - 1)
end

local function GetPanelStrip()
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.groupSettingsHost
    if not (host and host:IsShown()) then return nil end
    local tabGroup = host.tabGroup
    if not (tabGroup and tabGroup.frame:IsShown()) then return nil end
    return tabGroup
end

local function GetEntryStrip()
    local col3 = CS.configFrame and CS.configFrame.col3
    return col3 and col3.bsTabGroup or nil
end

local function GetStripRowCount(tabGroup)
    local offset = tabGroup.borderoffset or (TAB_STRIP_INSET + TAB_ROW_PITCH)
    local rows = math.floor(((offset - TAB_STRIP_INSET) / TAB_ROW_PITCH) + 0.5)
    if rows < 1 then rows = 1 end
    return rows
end

-- BuildTabs reads self.frame.width in preference to the frame's real
-- width. Setting the field lets a strip wrap inside a sub-range of its
-- frame while the frame itself keeps covering the whole settings rect,
-- which is what its content pane needs.
local function BuildPanelStrip(tabGroup, baseBuildTabs)
    tabGroup._cdcStripOffset = 0
    tabGroup.frame.width = PANEL_STRIP_BUDGET
    baseBuildTabs(tabGroup)
end

local function BuildEntryStrip(tabGroup, baseBuildTabs)
    local offset = 0
    local panel = GetPanelStrip()
    if panel then
        local panelWidth = MeasureStripWidth(panel)
        if panelWidth > 0 then
            offset = panelWidth + CLUSTER_GAP
        end
    end

    local remaining = (tabGroup.frame:GetWidth() or 0) - offset
    if remaining < MIN_ENTRY_STRIP then
        remaining = MIN_ENTRY_STRIP
    end

    tabGroup._cdcStripOffset = offset
    tabGroup.frame.width = remaining
    baseBuildTabs(tabGroup)

    if GetStripRowCount(tabGroup) == 1 then
        -- The cluster fits beside the panel tabs. AceGUI pads a tight row
        -- out to fill its width, which would size entry tabs differently
        -- from panel tabs; rebuilding without the constraint keeps every
        -- tab in the row sized the same way, and what fit padded still fits.
        tabGroup.frame.width = PANEL_STRIP_BUDGET
        baseBuildTabs(tabGroup)
    end
end

-- BuildTabs anchors the first tab of every row to the group's frame and
-- chains the rest off it, so shifting the row leaders moves whole rows.
local function OffsetStripRows(tabGroup)
    local offset = tabGroup._cdcStripOffset or 0
    if offset <= 0 then return end
    for _, tab in ipairs(tabGroup.tabs) do
        if tab:IsShown() then
            local point, relativeTo, relativePoint, x, y = tab:GetPoint(1)
            if point and relativeTo == tabGroup.frame then
                tab:SetPoint(point, relativeTo, relativePoint, (x or 0) + offset, y or 0)
            end
        end
    end
end

-- Both strips share the row, so both content panes must clear the tallest
-- one; otherwise a wrapped entry row draws over panel-scope content.
local function ApplyRowCount(tabGroup, rows)
    if not tabGroup then return end
    local offset = TAB_STRIP_INSET + rows * TAB_ROW_PITCH
    tabGroup.borderoffset = offset
    tabGroup.border:SetPoint("TOPLEFT", 1, -offset)
end

local ApplyUnifiedRow

-- Wraps the widget's own BuildTabs so every rebuild - SetTabs, a window
-- resize, and the deferred pass AceGUI schedules after one - lands with
-- the same budget and offset, and so a rebuild that changes the row count
-- (a resize that wraps the entry cluster) takes both content panes with it.
local function InstallStripLayout(tabGroup, buildFn)
    if not tabGroup or tabGroup._cdcUnifiedStrip then return end
    tabGroup._cdcUnifiedStrip = true

    local baseBuildTabs = tabGroup.BuildTabs
    tabGroup.BuildTabs = function(self)
        buildFn(self, baseBuildTabs)
        OffsetStripRows(self)
        self._cdcRowCount = GetStripRowCount(self)
        ApplyUnifiedRow()
    end
end

local function InstallPanelStrip(tabGroup)
    InstallStripLayout(tabGroup, BuildPanelStrip)
end

local function InstallEntryStrip(tabGroup)
    InstallStripLayout(tabGroup, BuildEntryStrip)
end

------------------------------------------------------------------------
-- Scope: which strip owns the settings surface
------------------------------------------------------------------------

-- The remembered scope only means anything while an entry is selected;
-- with no entry cluster in the row the panel strip always owns the
-- surface.
local function GetScope()
    return CS.unifiedRowScope == "panel" and "panel" or "entry"
end

local function SetScope(scope)
    CS.unifiedRowScope = (scope == "panel") and "panel" or "entry"
end

local function SetStripActive(tabGroup, active)
    if not tabGroup then return end
    if active then
        tabGroup.content:Show()
        tabGroup.border:SetBackdropColor(0.1, 0.1, 0.1, 0.5)
        tabGroup.border:SetBackdropBorderColor(0.4, 0.4, 0.4)
        return
    end
    -- Tabs are children of the border frame, so the pane is dropped by
    -- clearing its backdrop and hiding the content frame rather than by
    -- hiding the border itself.
    tabGroup.content:Hide()
    tabGroup.border:SetBackdropColor(0, 0, 0, 0)
    tabGroup.border:SetBackdropBorderColor(0, 0, 0, 0)
    for _, tab in ipairs(tabGroup.tabs) do
        tab:SetSelected(false)
    end
end

-- Run after both strips have been given their tabs and the owning scope
-- has selected its tab: harmonises the row count and enforces one
-- selected tab across the row. Re-entrant guard: the row-count pass moves
-- a border, which can cascade a layout back through a strip.
local applying = false
function ApplyUnifiedRow()
    if applying then return end
    applying = true

    local panel = GetPanelStrip()
    local entry = GetEntryStrip()
    local entryShown = entry and entry.frame:IsShown() or false

    local rows = 1
    if entryShown then
        rows = math.max(rows, entry._cdcRowCount or 1)
    end
    ApplyRowCount(panel, rows)
    if entryShown then
        ApplyRowCount(entry, rows)
    end

    local scope = entryShown and GetScope() or "panel"
    if scope == "panel" and not panel and entryShown then
        -- No panel strip in the row (Other Class browsing hides it): the
        -- entry cluster is the only thing that can own the surface.
        scope = "entry"
    end
    SetStripActive(panel, scope == "panel")
    if entry then
        SetStripActive(entry, entryShown and scope == "entry")
    end

    applying = false
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._UnifiedRowInstallPanelStrip = InstallPanelStrip
ST._UnifiedRowInstallEntryStrip = InstallEntryStrip
ST._UnifiedRowGetScope = GetScope
ST._UnifiedRowSetScope = SetScope
ST._UnifiedRowApply = ApplyUnifiedRow
