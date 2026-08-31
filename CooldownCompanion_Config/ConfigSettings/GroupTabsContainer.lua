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

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

-- Declared at module load so unopened tabs remain searchable without being
-- constructed. Maps stay local so every rendered row binds its exact route.
local CONTAINER_FINDER = {}

local function ContainerFinderAlphaEnabled(context)
    return context and context.container and context.container.groupAlphaEnabled == true
end

local function ContainerFinderMountedAlpha(context)
    local container = context and context.container
    return ContainerFinderAlphaEnabled(context) and (
        container.forceAlphaRegularMounted
        or container.forceHideRegularMounted
        or container.forceAlphaDragonriding
        or container.forceHideDragonriding
    ) and (container.isGlobal or CooldownCompanion._playerClassID == 11)
end

local function ContainerFinderTargetAlpha(context)
    local container = context and context.container
    return ContainerFinderAlphaEnabled(context)
        and container.forceAlphaTargetExists == true
end

local function ContainerFinderCustomFade(context)
    local container = context and context.container
    return ContainerFinderAlphaEnabled(context) and container.customFade == true
end

if ST._DefineSettingRoute then
    CONTAINER_FINDER.general = ST._DefineSettingRoute({
        idPrefix = "group.general",
        scope = "group",
        tab = "general",
        tabLabel = "General",
        section = "basics",
        sectionLabel = "General",
        rowScope = "primary",
    }):Settings({
        enabled = { label = "Enabled", aliases = { "show group" } },
        locked = { label = "Locked", aliases = { "unlock group", "move group" } },
    })

    CONTAINER_FINDER.layout = ST._DefineSettingRoute({
        idPrefix = "group.general.layout",
        scope = "group",
        tab = "general",
        tabLabel = "General",
        section = "layout",
        sectionLabel = "Layout",
        collapseKeys = { "container_layout" },
        rowScope = "primary",
    }):Settings({
        xOffset = { label = "X Offset", aliases = { "horizontal position" } },
        yOffset = { label = "Y Offset", aliases = { "vertical position" } },
    })

    local alphaRoute = ST._DefineSettingRoute({
        idPrefix = "group.general.alpha",
        scope = "group",
        tab = "general",
        tabLabel = "General",
        section = "alpha",
        sectionLabel = "Group Alpha",
        collapseKeys = { "container_alpha" },
        rowScope = "primary",
    })
    CONTAINER_FINDER.alpha = alphaRoute:Settings({
        enabled = { label = "Enable Group Alpha", aliases = { "group opacity", "group transparency" } },
        baseline = { label = "Baseline Alpha", aliases = { "opacity", "transparency" }, applies = ContainerFinderAlphaEnabled },
        combat = { label = "In Combat", applies = ContainerFinderAlphaEnabled },
        outOfCombat = { label = "Out of Combat", applies = ContainerFinderAlphaEnabled },
        regularMount = { label = "Regular Mount", applies = ContainerFinderAlphaEnabled },
        skyriding = { label = "Skyriding", aliases = { "dragonriding" }, applies = ContainerFinderAlphaEnabled },
        travelForm = {
            label = "Include Druid Travel Form (applies to both)",
            aliases = { "travel form" },
            applies = ContainerFinderMountedAlpha,
        },
        target = { label = "Target Exists", applies = ContainerFinderAlphaEnabled },
        enemy = { label = "Enemy Only", aliases = { "hostile target" }, applies = ContainerFinderTargetAlpha },
        focus = { label = "Focus Exists", applies = ContainerFinderAlphaEnabled },
        mouseover = { label = "Mouseover", applies = ContainerFinderAlphaEnabled },
        customFade = { label = "Custom Fade Settings", aliases = { "fade" }, applies = ContainerFinderAlphaEnabled },
        fadeDelay = { label = "Fade Delay (seconds)", applies = ContainerFinderCustomFade },
        fadeIn = { label = "Fade In Duration (seconds)", applies = ContainerFinderCustomFade },
        fadeOut = { label = "Fade Out Duration (seconds)", applies = ContainerFinderCustomFade },
    })

    CONTAINER_FINDER.strata = ST._DefineSettingRoute({
        idPrefix = "group.general.strata",
        scope = "group",
        tab = "general",
        tabLabel = "General",
        section = "strata",
        sectionLabel = "Frame Strata",
        collapseKeys = { "container_strata" },
        rowScope = "primary",
    }):Settings({
        frameStrata = { label = "Container Frame Strata", aliases = { "layer" } },
    })

    local whereRoute = ST._DefineSettingRoute({
        idPrefix = "group.visibility.where",
        scope = "group",
        tab = "loadconditions",
        tabLabel = "Visibility",
        section = "where",
        sectionLabel = "Where To Hide It",
        collapseKeys = { "container_loadconditions_local" },
        rowScope = "primary",
    })
    CONTAINER_FINDER.where = whereRoute:Settings({
        raid = { label = "Raid" },
        dungeon = { label = "Dungeon" },
        delve = { label = "Delve" },
        battleground = { label = "Battleground" },
        arena = { label = "Arena" },
        openWorld = { label = "Open World" },
        rested = { label = "Rested Area" },
        petBattle = { label = "Pet Battle" },
        vehicleUI = { label = "Vehicle / Override UI", aliases = { "vehicle ui", "override ui" } },
    })
end

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
        setting = CONTAINER_FINDER.general and CONTAINER_FINDER.general.enabled,
        value = container.enabled ~= false,
        onChange = function(value)
            container.enabled = value
            RefreshPanels()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    AddCheckboxRow(masterRight, {
        label = "Locked",
        setting = CONTAINER_FINDER.general and CONTAINER_FINDER.general.locked,
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
            setting = CONTAINER_FINDER.layout and CONTAINER_FINDER.layout.xOffset,
            min = -2000, max = 2000, step = 0.1,
            value = container.anchor.x or 0,
            onRelease = function(val)
                ApplyContainerOffset("x", val)
            end,
        })

        AddSliderRow(layoutRight, {
            label = "Y Offset",
            setting = CONTAINER_FINDER.layout and CONTAINER_FINDER.layout.yOffset,
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
            setting = CONTAINER_FINDER.alpha and CONTAINER_FINDER.alpha.enabled,
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
                settings = CONTAINER_FINDER.alpha,
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
        setting = CONTAINER_FINDER.strata and CONTAINER_FINDER.strata.frameStrata,
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
        settings = CONTAINER_FINDER.where,
        onChanged = RefreshContainerLoadConditions,
    })
end

-- Expose for Config.lua
ST._BuildContainerGeneralTab = BuildContainerGeneralTab
ST._BuildContainerLoadConditionsTab = BuildContainerLoadConditionsTab
