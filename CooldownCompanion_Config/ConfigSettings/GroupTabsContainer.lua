local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local tonumber = tonumber

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local CreateInfoButton = ST._CreateInfoButton
local BuildAlphaControls = ST._BuildAlphaControls
local AddScopedLoadConditionToggles = ST._AddScopedLoadConditionToggles
local BuildWhereToHideTooltip = ST._BuildWhereToHideTooltip
local AddCharacterEligibilityControls = ST._AddCharacterEligibilityControls
local AddClassSpecEligibilityControls = ST._AddClassSpecEligibilityControls

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AnchorRowBadge = ST._AnchorRowBadge
local BeginRowGrid = ST._BeginRowGrid

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

local tabInfoButtons = CS.tabInfoButtons

------------------------------------------------------------------------
-- CONTAINER TAB BUILDERS (for Group settings in the workspace)
------------------------------------------------------------------------

local function BuildContainerGeneralTab(scroll, containerId)
    local db = CooldownCompanion.db.profile
    local container = db.groupContainers and db.groupContainers[containerId]
    if not container then return end

    local function RefreshPanels()
        CooldownCompanion:RefreshContainerPanels(containerId)
    end

    -- Row grammar (RowWidgets.lua). The two master switches lead the tab with
    -- no header of their own: they are what the whole group IS, not one aspect
    -- of it, and every section below them is a facet they gate. Everything
    -- else is a collapsible row-grammar section. Nothing here carries an
    -- advanced gear, so there is no queued advanced key to keep uncollapsed.
    local masterLeft, masterRight = BeginRowGrid(scroll)

    AddCheckboxRow(masterLeft, {
        label = "Enabled",
        value = container.enabled ~= false,
        onChange = function(value)
            container.enabled = value
            RefreshPanels()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    AddCheckboxRow(masterRight, {
        label = "Locked",
        value = container.locked ~= false,
        onChange = function(value)
            CooldownCompanion:SetContainerLocked(containerId, value)
            CooldownCompanion:RefreshConfigPanel()
            if not value and ST.CollapseConfigForUnlock then
                ST.CollapseConfigForUnlock()
            elseif value then
                CooldownCompanion:CheckArrangeModeAutoExit()
            end
        end,
    })

    -- ================================================================
    -- Layout
    -- ================================================================
    local _, layoutCollapsed = BuildCollapsibleSection(scroll, "Layout", "container_layout", nil, nil, ROW_SECTION)

    if not layoutCollapsed then
        container.anchor = CooldownCompanion:NormalizeContainerAnchor(container.anchor)
        local committedOffsets = {
            x = tonumber(container.anchor.x) or 0,
            y = tonumber(container.anchor.y) or 0,
        }
        local function ApplyContainerOffset(axis, value)
            local oldValue = committedOffsets[axis] or 0
            container.anchor[axis] = value
            committedOffsets[axis] = value

            local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
            if containerFrame then
                CooldownCompanion:AnchorContainerFrame(containerFrame, container.anchor)
            end

            if CooldownCompanion.SyncGroupedStandalonePreviewSettings then
                local deltaX, deltaY = 0, 0
                if axis == "x" then
                    deltaX = value - oldValue
                else
                    deltaY = value - oldValue
                end
                CooldownCompanion:SyncGroupedStandalonePreviewSettings(containerId, deltaX, deltaY)
            end

            if containerFrame and CooldownCompanion.RefreshContainerWrapper then
                CooldownCompanion:RefreshContainerWrapper(containerId)
            end
        end

        -- One offset each side: the pair is the whole section, so splitting it
        -- across the grid keeps both columns populated.
        local layoutLeft, layoutRight = BeginRowGrid(scroll)

        AddSliderRow(layoutLeft, {
            label = "X Offset",
            min = -2000, max = 2000, step = 0.1,
            value = container.anchor.x or 0,
            onRelease = function(val)
                ApplyContainerOffset("x", val)
            end,
        })

        AddSliderRow(layoutRight, {
            label = "Y Offset",
            min = -2000, max = 2000, step = 0.1,
            value = container.anchor.y or 0,
            onRelease = function(val)
                ApplyContainerOffset("y", val)
            end,
        })
    end -- if not layoutCollapsed

    -- ================================================================
    -- Group Alpha
    -- ================================================================
    local _, alphaCollapsed = BuildCollapsibleSection(scroll, "Group Alpha", "container_alpha", nil, nil, ROW_SECTION)

    if not alphaCollapsed then
        local function RefreshContainerAlphaSettings()
            RefreshPanels()
            CooldownCompanion:RefreshConfigPanel()
        end

        -- The switch that gates everything else in this section, in a grid of
        -- its own so the alpha builder below can open its own two columns.
        local switchLeft = BeginRowGrid(scroll)

        local groupAlphaRow = AddCheckboxRow(switchLeft, {
            label = "Enable Group Alpha",
            value = container.groupAlphaEnabled == true,
            onChange = function(value)
                container.groupAlphaEnabled = value == true
                if CooldownCompanion.RefreshAlphaUpdateDriver then
                    CooldownCompanion:RefreshAlphaUpdateDriver()
                end
                RefreshContainerAlphaSettings()
            end,
        })

        -- Anchor args are a placeholder: AnchorRowBadge re-points the button
        -- onto the end of the label's badge chain.
        AnchorRowBadge(groupAlphaRow, CreateInfoButton(groupAlphaRow.frame, groupAlphaRow.frame, "LEFT", "LEFT", 0, 0, {
            "Group Alpha",
            {"When enabled, applies these alpha settings to panels anchored directly to this group. Panels anchored elsewhere keep their own alpha behavior.", 1, 1, 1, true},
        }, tabInfoButtons))

        if container.groupAlphaEnabled == true then
            BuildAlphaControls(scroll, container, RefreshContainerAlphaSettings, nil, {
                row = true,
                isGlobal = container.isGlobal,
                hideHeading = true,
                onBaselineCommitted = function(val)
                    if CooldownCompanion.ApplyContainerAlphaPreview then
                        CooldownCompanion:ApplyContainerAlphaPreview(containerId, val)
                    end
                end,
            })
        end
    end -- if not alphaCollapsed

    -- ================================================================
    -- Frame Strata
    -- ================================================================
    local _, strataCollapsed = BuildCollapsibleSection(scroll, "Frame Strata", "container_strata", nil, nil, ROW_SECTION)

    if not strataCollapsed then
    -- One setting; the right column stays empty.
    local strataLeft = BeginRowGrid(scroll)

    AddDropdownRow(strataLeft, {
        label = "Container Frame Strata",
        list = {
            BACKGROUND = "Background",
            LOW = "Low",
            MEDIUM = "Medium (Default)",
            HIGH = "High",
        },
        order = { "BACKGROUND", "LOW", "MEDIUM", "HIGH" },
        value = container.frameStrata or "MEDIUM",
        onChange = function(value)
            container.frameStrata = value
            local containerFrame = CooldownCompanion.containerFrames and CooldownCompanion.containerFrames[containerId]
            if containerFrame then
                containerFrame:SetFrameStrata(value)
            end
            RefreshPanels()
        end,
    })
    end -- if not strataCollapsed
end

local function BuildContainerLoadConditionsTab(scroll, containerId)
    local db = CooldownCompanion.db.profile
    local container = db.groupContainers and db.groupContainers[containerId]
    if not container then return end

    local function RefreshPanels()
        CooldownCompanion:RefreshContainerPanels(containerId)
    end
    local inheritedSources = CooldownCompanion:GetInheritedLoadConditionSources(container)
    local function RefreshContainerLoadConditions()
        RefreshPanels()
        CooldownCompanion:RefreshConfigPanel()
    end

    -- Two halves, same shape as the panel tab: who the group is for, then
    -- where it stays hidden. Groups sit at the top of the inheritance chain,
    -- so there is never an inherited summary to lead with. Row grammar
    -- throughout, and nothing here carries a gear, so there is no
    -- advanced-panel queue to keep uncollapsed.
    local _, whoCollapsed = BuildCollapsibleSection(scroll, "Who Can Use This",
        "container_loadconditions_who", nil, nil, ROW_SECTION)

    if not whoCollapsed then
        local eligibilityOpts = {
            target = container,
            inheritedSources = inheritedSources,
            eligibilitySubjectLabel = "group",
            allowClassEligibility = container.isGlobal == true,
            ownerCharKey = container.createdBy,
            omitHeading = true,
            showSelectedRows = true,
            onChanged = RefreshContainerLoadConditions,
        }

        -- Same split as the panel tab: person on the left, class/spec/hero
        -- chain on the right, each picker carrying its own selections.
        local whoLeft, whoRight = BeginRowGrid(scroll)
        AddCharacterEligibilityControls(whoLeft, eligibilityOpts)
        AddClassSpecEligibilityControls(whoRight, eligibilityOpts)

        local hasOwnSpecs = (type(container.specs) == "table" and next(container.specs) ~= nil)
            or (type(container.loadConditions) == "table"
                and type(container.loadConditions.specAllowlist) == "table"
                and next(container.loadConditions.specAllowlist) ~= nil)
            or (type(container.heroTalents) == "table" and next(container.heroTalents) ~= nil)
        if hasOwnSpecs then
            -- Compact and inside the grid. It clears exactly what the right
            -- column holds, so it sits at that column's tail even though the
            -- left one is usually shorter - meaning wins over balance for a
            -- control this destructive.
            local clearBtn = AceGUI:Create("Button")
            clearBtn:SetText("Clear All Spec Filters")
            clearBtn:SetAutoWidth(true)
            clearBtn:SetCallback("OnClick", function()
                container.specs = nil
                if type(container.loadConditions) == "table" then
                    container.loadConditions.specAllowlist = nil
                end
                container.heroTalents = nil
                RefreshPanels()
                CooldownCompanion:RefreshConfigPanel()
            end)
            whoRight:AddChild(clearBtn)
        end
    end -- not whoCollapsed

    AddScopedLoadConditionToggles(scroll, {
        target = container,
        defaults = CooldownCompanion:GetDefaultLoadConditions(),
        inheritedSources = inheritedSources,
        headingText = "Where To Hide It",
        localCollapsedKey = "container_loadconditions_local",
        row = true,
        infoTooltipLines = BuildWhereToHideTooltip("group", true, true),
        infoButtons = tabInfoButtons,
        onChanged = RefreshContainerLoadConditions,
    })
end

-- Expose for Config.lua
ST._BuildContainerGeneralTab = BuildContainerGeneralTab
ST._BuildContainerLoadConditionsTab = BuildContainerLoadConditionsTab
