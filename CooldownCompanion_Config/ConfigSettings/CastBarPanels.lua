local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateCharacterCopyButton = ST._CreateCharacterCopyButton
local AddAnchorDropdown = ST._AddAnchorDropdown
local BuildIndependentAnchorTargetRow = ST._BuildIndependentAnchorTargetRow
local AddBorderRenderModeDropdown = ST._AddBorderRenderModeDropdown

-- Imports from RowWidgets.lua (the row grammar). The rules every row-grammar
-- section follows are stated once, in the recipe comment at the top of
-- BuildAppearanceTab's icons path (GroupTabsAppearance.lua); this file conforms to them
-- rather than restating them.
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddDropdownRow = ST._AddDropdownRow
local AddColorRow = ST._AddColorRow
local BeginRowGrid = ST._BeginRowGrid

-- Row-grammar section headers: caret far left, label, then a class-colored
-- rule fading right.
local ROW_SECTION = { leftAligned = true }

-- The gear sites' "Turn On" enable specs, riding the LAZY unlock specs the
-- gears store in options.unlock (resolved only at panel-build time by
-- ST._ResolveAdvancedUnlock, Helpers.lua). File-local constants so a rebuild
-- allocates none of them; the channel-tick spec stays inline at its site
-- because its checkbox sequence also repaints the canvas, so it rides `run`.
local TURNON_SHOW_ICON = { label = "Enable Spell Icon", key = "showIcon" }
local TURNON_SHOW_NAME_TEXT = { label = "Enable Spell Name", key = "showNameText" }
local TURNON_SHOW_CAST_TIME = { label = "Enable Cast Time", key = "showCastTimeText" }

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

local CASTBAR_FINDER = {}

local function CastBarFinderEnabled(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true
end

-- The four Contents advanced routes gate on CastBarFinderEnabled alone,
-- STRUCTURE only: their gears build whenever the styling panel does, which is
-- whenever the module is enabled - a content toggle that is off just opens
-- its panel read-only behind the Turn On footer, so it stays findable.

local function CastBarFinderAttached(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true and not CooldownCompanion:IsModuleAnchorIndependent("castbar")
end

local function CastBarFinderIndependent(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true and CooldownCompanion:IsModuleAnchorIndependent("castbar")
end

local function CastBarFinderCacheFlag(key)
    return function(context)
        local cache = context and context._ccCastBarFinderCache
        return cache and cache[key] == true
    end
end

if ST._DefineSettingRoute then
    local general = ST._DefineSettingRoute({
        idPrefix = "castBar.general.castBar",
        scope = "castBar",
        tab = "general",
        tabLabel = "General",
        tabStateKey = "castBarHomeTab",
        section = "castBar",
        sectionLabel = "Cast Bar",
        collapseKeys = { "castbar_general" },
        rowScope = "detail",
    })
    CASTBAR_FINDER.general = general:Settings({
        enabled = { label = "Enable Cast Bar", aliases = { "enable cast bar anchoring" } },
        anchoringMode = { label = "Anchoring Mode", aliases = { "attach to" }, applies = CastBarFinderEnabled },
        anchorPanel = { label = "Anchor Panel", applies = function(context)
            return CastBarFinderEnabled(context) and CooldownCompanion:GetModuleAttachment("castbar").mode == "panel"
        end },
    })

    local attached = ST._DefineSettingRoute({
        idPrefix = "castBar.layout.attached",
        scope = "castBar",
        tab = "layout",
        tabLabel = "Layout",
        tabStateKey = "castBarHomeTab",
        section = "layout",
        sectionLabel = "Layout",
        collapseKeys = { "castbar_layout" },
        rowScope = "detail",
        applies = CastBarFinderAttached,
    })
    CASTBAR_FINDER.attached = attached:Settings({
        yOffset = { label = "Y Offset", aliases = { "stack gap" },
            applies = function() return not ST.GetModuleGeometryPanel("castbar") end },
        ownYOffset = {
            label = "Enable Cast Bar-Only Y Offset",
            aliases = { "separate cast bar offset" },
            applies = CastBarFinderCacheFlag("attachedOffsetAvailable"),
        },
        castBarYOffset = {
            label = "Cast Bar Y Offset",
            applies = CastBarFinderCacheFlag("attachedYOffsetEnabled"),
        },
    })

    local independent = ST._DefineSettingRoute({
        idPrefix = "castBar.layout.anchor",
        scope = "castBar",
        tab = "layout",
        tabLabel = "Layout",
        tabStateKey = "castBarHomeTab",
        section = "anchor",
        sectionLabel = "Anchor Settings",
        collapseKeys = { "castbar_anchor" },
        rowScope = "detail",
        applies = CastBarFinderIndependent,
    })
    CASTBAR_FINDER.independent = independent:Settings({
        anchorFrame = { label = "Anchor to Frame", aliases = { "relative frame", "anchor target" } },
        unlock = { label = "Unlock Placement", aliases = { "move cast bar" } },
        anchorPoint = { label = "Anchor Point" },
        relativePoint = { label = "Relative Point", aliases = { "relative anchor point" } },
        width = { label = "Cast Bar Width" },
        xOffset = { label = "X Offset" },
        yOffset = { label = "Y Offset" },
    })

    local bar = ST._DefineSettingRoute({
        idPrefix = "castBar.appearance.bar",
        scope = "castBar",
        tab = "appearance",
        tabLabel = "Appearance",
        tabStateKey = "castBarHomeTab",
        section = "bar",
        sectionLabel = "Bar Appearance",
        collapseKeys = { ST._SharedBarStyleCollapseKey("barTexture", "castbar") },
        rowScope = "detail",
        applies = CastBarFinderEnabled,
    })
    CASTBAR_FINDER.bar = bar:Settings({
        height = { label = "Height", aliases = { "bar height" }, applies = function() return not ST.UsesSharedModuleGeometry("castbar") end },
        thickness = { label = "Bar Thickness", sectionId = "barThickness", applies = function() return ST.UsesSharedModuleGeometry("castbar") end },
        color = { label = "Cast Color", aliases = { "bar color", "fill color" } },
    })
    -- Customizations links land on the thickness row like the resource ones.
    ST._CastBarThicknessSetting = CASTBAR_FINDER.bar.thickness

    local effects = ST._DefineSettingRoute({
        idPrefix = "castBar.appearance.effects",
        scope = "castBar",
        tab = "appearance",
        tabLabel = "Appearance",
        tabStateKey = "castBarHomeTab",
        section = "effects",
        sectionLabel = "Cast Effects",
        collapseKeys = { "castbar_effects" },
        rowScope = "detail",
        applies = CastBarFinderEnabled,
    })
    CASTBAR_FINDER.effects = effects:Settings({
        spark = { label = "Show Spark" },
        sparkTrail = { advancedKey = "castSpark", label = "Show Spark Trail", applies = CastBarFinderCacheFlag("sparkShown") },
        finish = { label = "Show Cast Finish FX", aliases = { "finish effect" } },
        interruptShake = { label = "Show Interrupt Shake" },
        interruptGlow = { label = "Show Interrupt Glow" },
    })

    local contents = ST._DefineSettingRoute({
        idPrefix = "castBar.appearance.contents",
        scope = "castBar",
        tab = "appearance",
        tabLabel = "Appearance",
        tabStateKey = "castBarHomeTab",
        section = "contents",
        sectionLabel = "Text & Icon",
        collapseKeys = { "castbar_contents" },
        rowScope = "detail",
        applies = CastBarFinderEnabled,
    })
    CASTBAR_FINDER.contents = contents:Settings({
        icon = { label = "Show Spell Icon", aliases = { "cast icon" } },
        ticks = { label = "Show Channel Tick Marks", aliases = { "channel ticks" } },
        name = { label = "Show Spell Name", aliases = { "cast name" } },
        time = { label = "Show Cast Time", aliases = { "cast duration" } },
    })

    local icon = ST._DefineSettingRoute({
        idPrefix = "castBar.appearance.contents.icon",
        scope = "castBar",
        tab = "appearance",
        tabLabel = "Appearance",
        tabStateKey = "castBarHomeTab",
        section = "contents",
        sectionLabel = "Spell Icon",
        collapseKeys = { "castbar_contents" },
        rowScope = "detail",
        advancedKey = "castbarIcon",
        applies = CastBarFinderEnabled,
    })
    CASTBAR_FINDER.icon = icon:Settings({
        offset = { label = "Icon Offset" },
        xOffset = { label = "Icon X Offset", applies = CastBarFinderCacheFlag("iconOffsetEnabled") },
        yOffset = { label = "Icon Y Offset", applies = CastBarFinderCacheFlag("iconOffsetEnabled") },
        borderThickness = {
            label = "Border Thickness",
            aliases = { "icon border thickness" },
            applies = CastBarFinderCacheFlag("iconOffsetEnabled"),
        },
        borderSize = { label = "Icon Border Size", applies = CastBarFinderCacheFlag("customIconBorderSize") },
    })

    local ticks = ST._DefineSettingRoute({
        idPrefix = "castBar.appearance.contents.channelTicks",
        scope = "castBar",
        tab = "appearance",
        tabLabel = "Appearance",
        tabStateKey = "castBarHomeTab",
        section = "contents",
        sectionLabel = "Channel Tick Marks",
        collapseKeys = { "castbar_contents" },
        rowScope = "detail",
        advancedKey = "castbarChannelTicks",
        applies = CastBarFinderEnabled,
    })
    CASTBAR_FINDER.ticks = ticks:Settings({
        width = { label = "Tick Mark Width" },
        color = { label = "Tick Mark Color" },
        penultimate = { label = "Highlight Second-to-Last Tick", aliases = { "second to last tick" } },
        highlightColor = { label = "Highlight Color", applies = CastBarFinderCacheFlag("penultimateHighlight") },
    })

    local castTime = ST._DefineSettingRoute({
        idPrefix = "castBar.appearance.contents.castTime",
        scope = "castBar",
        tab = "appearance",
        tabLabel = "Appearance",
        tabStateKey = "castBarHomeTab",
        section = "contents",
        sectionLabel = "Cast Time",
        collapseKeys = { "castbar_contents" },
        rowScope = "detail",
        advancedKey = "castbarCastTime",
        applies = CastBarFinderEnabled,
    })
    CASTBAR_FINDER.castTime = castTime:Settings({
        xOffset = { label = "X Offset" },
        yOffset = { label = "Y Offset" },
    })
end

-- LibSharedMedia texture names (and the longer anchoring-mode label) run past
-- the 140px control column, and a dropdown sizes its menu from the control.
local WIDE_PULLOUT_WIDTH = 300

-- The workspace Live Preview draws the attached cast bar's own facsimile from
-- these settings and does NOT rebuild with the settings column, so every row
-- whose effect lands there repaints it directly. ResourceBarPanelsHelpers.lua
-- publishes the three helpers and loads AFTER this file (TOC), so they are read
-- at call time rather than aliased at file scope - the same rule Helpers.lua
-- follows for the row builders.
local function RefreshBarsCanvas()
    if ST._RefreshResourcesCanvas then
        ST._RefreshResourcesCanvas()
    end
end

local function RefreshBarsCanvasForDrag()
    if ST._RefreshResourcesCanvasForDrag then
        ST._RefreshResourcesCanvasForDrag()
    end
end

local function AddMirrorFirstSliderRow(container, opts)
    return ST._AddMirrorFirstSliderRow(container, opts)
end

------------------------------------------------------------------------
-- CAST BAR SETTINGS PANEL
------------------------------------------------------------------------

local function CanShowAttachedCastBarOffsetControls(cbSettings, layout)
    return type(layout) == "table" and cbSettings
        and cbSettings.enabled
        and not CooldownCompanion:IsModuleAnchorIndependent("castbar")
end

-- Built once for the active Cast Bar Finder context. Applicability reads the
-- context-owned snapshot instead of resolving settings, spec layout, or
-- border state while a query is being typed.
local function RefreshCastBarFinderCache()
    local settings = CooldownCompanion:GetCastBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    local _, offsetEnabled = ST.GetCastBarAttachmentOffset(settings, layout)
    local attachedOffsetAvailable = CanShowAttachedCastBarOffsetControls(settings, layout)
    local iconBorderMode = settings and ST.GetBorderRenderMode(settings, "iconBorderRenderMode")

    local cache = {
        settings = settings,
        attachedOffsetAvailable = attachedOffsetAvailable == true,
        attachedYOffsetEnabled = attachedOffsetAvailable == true and offsetEnabled,
        sparkShown = settings and settings.showSpark ~= false or false,
        iconOffsetEnabled = settings and settings.iconOffset == true or false,
        customIconBorderSize = settings and settings.iconOffset == true
            and iconBorderMode ~= ST.BORDER_RENDER_MODE_CRISP or false,
        penultimateHighlight = settings
            and settings.highlightPenultimateChannelTick == true or false,
    }
    return cache
end

if ST._RegisterSettingsFinderContextPreparer then
    ST._RegisterSettingsFinderContextPreparer("castBar", function(context)
        context._ccCastBarFinderCache = RefreshCastBarFinderCache()
    end)
end

local function RefreshAttachedCastBarOffset(refreshConfig)
    CooldownCompanion:RepositionCastBar()
    if refreshConfig then
        CooldownCompanion:RefreshConfigPanel()
    end
end

-- The cast bar's optional offset is added after the panel's shared distance
-- or stack spacing. It never changes the placement of the preceding bars.
local function BuildAttachedCastBarOffsetControls(container, layout)
    local cbSettings = CooldownCompanion:GetCastBarSettings()
    layout = layout or CooldownCompanion:GetSpecLayoutOrder()
    if not CanShowAttachedCastBarOffsetControls(cbSettings, layout) then
        return false
    end
    local context = ST._CreateModuleSettingsContext("castbar")
    local resources = CooldownCompanion:GetResourceBarSettings()
    local function IsCurrent()
        return context:IsCurrent() and CooldownCompanion:GetResourceBarSettings() == resources
            and CooldownCompanion:GetSpecLayoutOrder() == layout
    end
    local function SetOffset(key, value)
        layout.castBar = layout.castBar or {}
        layout.castBar[key] = value
        if key == "panelAnchorScreenYOffset" then layout.castBar.panelAnchorYOffset = nil end
    end
    local offset, enabled = ST.GetCastBarAttachmentOffset(cbSettings, layout)

    AddCheckboxRow(container, {
        label = "Enable Cast Bar-Only Y Offset",
        setting = CASTBAR_FINDER.attached and CASTBAR_FINDER.attached.ownYOffset,
        value = enabled,
        onChange = function(val)
            if not IsCurrent() then return end
            local _, _, savedOffset = ST.GetCastBarAttachmentOffset(cbSettings, layout)
            SetOffset("panelAnchorScreenYOffset", savedOffset)
            SetOffset("panelAnchorYOffsetEnabled", val == true)
            RefreshAttachedCastBarOffset(true)
        end,
    })

    if enabled then
        AddSliderRow(container, {
            label = "Cast Bar Y Offset",
            setting = CASTBAR_FINDER.attached and CASTBAR_FINDER.attached.castBarYOffset,
            indent = false,
            min = -100, max = 100, step = 0.1,
            value = offset,
            tooltip = { { "Moves only the cast bar vertically. Positive values move it up; negative values move it down.", 1, 1, 1, true } },
            onChange = function(val)
                if not IsCurrent() then return end
                layout.castBar = layout.castBar or {}
                ST._PreviewScalarSetting(layout.castBar, "panelAnchorScreenYOffset", val, RefreshBarsCanvasForDrag)
            end,
            onRelease = function(val)
                if not IsCurrent() then return end
                SetOffset("panelAnchorScreenYOffset", val)
                RefreshAttachedCastBarOffset(false)
            end,
        })
    end

    return true
end

local function BuildCastBarAnchoringPanel(container)
    local db = CooldownCompanion.db.profile
    local settings = CooldownCompanion:GetCastBarSettings()

    -- ================================================================
    -- Cast Bar (the module switch and how the bar is placed)
    -- ================================================================
    -- The module switch lives INSIDE this section rather than above it: every
    -- row-grammar tab opens on a section header, and a free-standing control
    -- over the first caret has nowhere to belong. Disabling the module ends
    -- the section after one row and builds nothing below it, exactly as the
    -- pre-row tab returned early after the same checkbox.
    local _, generalCollapsed = BuildCollapsibleSection(container, "Cast Bar",
        "castbar_general", nil, nil, ROW_SECTION)

    if not generalCollapsed then
        -- The mode only means anything while the bar is on, so the two stay
        -- adjacent in one column rather than splitting a gate from what it
        -- gates. The right column is deliberately empty.
        local generalLeft = BeginRowGrid(container)

        local enableRow = AddCheckboxRow(generalLeft, {
            label = "Enable Cast Bar",
            setting = CASTBAR_FINDER.general and CASTBAR_FINDER.general.enabled,
            value = settings.enabled,
            onChange = function(val)
                settings.enabled = val
                if val then ST._PrepareBarWorkspaceEnable("castbar") end
                CooldownCompanion:EvaluateCastBar()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        CreateCharacterCopyButton(enableRow, "castBar", "Cast Bar", function()
            CooldownCompanion:EvaluateCastBar()
            CooldownCompanion:RefreshConfigPanel()
        end)

        if settings.enabled then
            ST._BuildModuleAnchoringControls(generalLeft, "castbar", {
                mode = CASTBAR_FINDER.general and CASTBAR_FINDER.general.anchoringMode,
                panel = CASTBAR_FINDER.general and CASTBAR_FINDER.general.anchorPanel,
            })

        end
    end

end

local function BuildCastBarPositioningPanel(container)
    local settings = CooldownCompanion:GetCastBarSettings()

    if not settings.enabled then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Enable Cast Bar to configure positioning.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    if not CooldownCompanion:IsModuleAnchorIndependent("castbar") then
        local _, layoutCollapsed = BuildCollapsibleSection(container, "Layout",
            "castbar_layout", nil, nil, ROW_SECTION)

        if layoutCollapsed then return end

        if ST.GetModuleGeometryPanel("castbar") then
            local left = BeginRowGrid(container)
            BuildAttachedCastBarOffsetControls(left)
            return
        end

        local rbSettings = CooldownCompanion:GetResourceBarSettings()
        local layout = CooldownCompanion:GetSpecLayoutOrder()

        -- LEFT column: the gap between the whole bar stack and the panel it
        -- hangs off. RIGHT column: the cast bar's own override of that gap.
        -- Same split as the Resource Bars Layout section, which shows the
        -- same two controls from the other side.
        local posLeft, posRight = BeginRowGrid(container)

        AddSliderRow(posLeft, {
            label = "Y Offset",
            setting = CASTBAR_FINDER.attached and CASTBAR_FINDER.attached.yOffset,
            min = -100, max = 100, step = 0.1,
            value = (layout and (layout.yOffset or layout.verticalXOffset))
                or (rbSettings and rbSettings.yOffset) or 3,
            onChange = function(val)
                if layout then
                    ST._PreviewScalarSetting(layout, "yOffset", val, RefreshBarsCanvasForDrag)
                end
            end,
            onRelease = function(val)
                if layout then layout.yOffset = val end
                CooldownCompanion:ApplyResourceBars()
            end,
        })

        BuildAttachedCastBarOffsetControls(posRight, layout)
        return
    end

    -- The anchor table is a stored setting, not a rendered control, so it is
    -- seeded whether or not the section below is expanded.
    if type(settings.independentAnchor) ~= "table" then
        settings.independentAnchor = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
    end
    local anchor = settings.independentAnchor

    -- ================================================================
    -- Anchor Settings (independent mode only)
    -- ================================================================
    local _, anchorCollapsed = BuildCollapsibleSection(container, "Anchor Settings",
        "castbar_anchor", nil, nil, ROW_SECTION)

    if anchorCollapsed then return end

    local function refreshCastBarAnchor()
        CooldownCompanion:ApplyCastBarSettings()
    end

    -- A frame name needs the whole 140px control column to stay readable, so
    -- Pick does not share it: the editbox row takes a grid of its own and
    -- Pick sits at the head of that grid's right column, immediately across
    -- the 16px gutter.
    local targetLeft, targetRight = BeginRowGrid(container)
    BuildIndependentAnchorTargetRow(targetLeft, anchor, refreshCastBarAnchor, {
        row = true,
        pickContainer = targetRight,
        setting = CASTBAR_FINDER.independent and CASTBAR_FINDER.independent.anchorFrame,
    })

    -- LEFT column: how the bar is placed - the drag toggle and the two points
    -- that have to be read together (mine, then the target's). RIGHT column:
    -- its size and the offset applied on top of those points.
    local anchorLeft, anchorRight = BeginRowGrid(container)

    AddCheckboxRow(anchorLeft, {
        label = "Unlock Placement",
        setting = CASTBAR_FINDER.independent and CASTBAR_FINDER.independent.unlock,
        value = not settings.independentAnchorLocked,
        onChange = function(val)
            settings.independentAnchorLocked = not val
            CooldownCompanion:ApplyCastBarSettings()
            if not val then
                CooldownCompanion:CheckArrangeModeAutoExit()
            end
        end,
    })

    AddAnchorDropdown(anchorLeft, anchor, "point", "CENTER", refreshCastBarAnchor, "Anchor Point", {
        row = true,
        setting = CASTBAR_FINDER.independent and CASTBAR_FINDER.independent.anchorPoint,
    })
    AddAnchorDropdown(anchorLeft, anchor, "relativePoint", "CENTER", refreshCastBarAnchor, "Relative Point", {
        row = true,
        setting = CASTBAR_FINDER.independent and CASTBAR_FINDER.independent.relativePoint,
    })

    AddSliderRow(anchorRight, {
        label = "Cast Bar Width",
        setting = CASTBAR_FINDER.independent and CASTBAR_FINDER.independent.width,
        min = 20, max = 600, step = 0.1,
        value = settings.independentWidth or 200,
        onChange = function(val)
            ST._PreviewScalarSetting(settings, "independentWidth", val, RefreshBarsCanvasForDrag)
        end,
        onRelease = function(val)
            settings.independentWidth = val
            CooldownCompanion:ApplyCastBarSettings()
        end,
    })

    AddSliderRow(anchorRight, {
        label = "X Offset",
        setting = CASTBAR_FINDER.independent and CASTBAR_FINDER.independent.xOffset,
        min = -2000, max = 2000, step = 0.1,
        value = anchor.x or 0,
        onRelease = function(val)
            anchor.x = val
            CooldownCompanion:ApplyCastBarSettings()
        end,
    })

    AddSliderRow(anchorRight, {
        label = "Y Offset",
        setting = CASTBAR_FINDER.independent and CASTBAR_FINDER.independent.yOffset,
        min = -2000, max = 2000, step = 0.1,
        value = anchor.y or 0,
        onRelease = function(val)
            anchor.y = val
            CooldownCompanion:ApplyCastBarSettings()
        end,
    })
end

local function BuildCastBarStylingPanel(container)
    if ST.UsesSharedModuleGeometry("castbar") then ST._BuildModuleGeometrySummary(container, "castbar") end
    local settings = CooldownCompanion:GetCastBarSettings()

    -- The retired styling switch used to carry this gate too: with the
    -- module off, styling rows would commit to a bar that immediately
    -- reverts. Same disabled-state surface as the positioning panel.
    if not settings.enabled then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Enable Cast Bar to configure appearance.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    -- Everything on this panel is the cast bar's LOOK, and the canvas draws
    -- that look; so the commit path applies to the live bar and repaints the
    -- canvas together, and the drag/picker-open path stays on the canvas alone.
    local applyCastBar = function()
        CooldownCompanion:ApplyCastBarSettings()
        RefreshBarsCanvas()
    end
    local castPreviewOnly = RefreshBarsCanvasForDrag
    local cbAdvBtns = {}

    -- Size leads and the fill color closes the one Bar Appearance section.
    ST._BuildModuleBarStyle(container, "castbar", nil, nil, "appearance", {
        leadingRows = function(left)
            if ST.UsesSharedModuleGeometry("castbar") then
                ST._BuildModuleBarThickness(left, "castbar", nil, nil, CASTBAR_FINDER.bar.thickness)
            else
                -- Specialized hosts retain the cast bar's local height baseline.
                AddMirrorFirstSliderRow(left, {
                    label = "Height", setting = CASTBAR_FINDER.bar.height,
                    min = 4, max = 40, step = 0.1, value = settings.height or 15,
                    set = function(value) settings.height = value end,
                    apply = applyCastBar, stateOwner = settings, stateKeys = "height",
                })
            end
        end,
        trailingRows = function(left)
            -- Fill color conveys casting; it does not inherit a spell's ready color.
            AddColorRow(left, { label = "Cast Color", setting = CASTBAR_FINDER.bar.color,
                tbl = settings, key = "barColor", default = {1, 0.7, 0, 1}, hasAlpha = true,
                onConfirm = applyCastBar, onPreview = castPreviewOnly })
        end,
    })
    -- ================================================================
    -- Cast Effects
    -- ================================================================
    local _, effectsCollapsed = BuildCollapsibleSection(container, "Cast Effects",
        "castbar_effects", nil, nil, ROW_SECTION)

    if not effectsCollapsed then
        -- LEFT column: the spark pair and finish effect. RIGHT column: the
        -- interrupt pair, which reads as one choice.
        local effectsLeft, effectsRight = BeginRowGrid(container)

        local sparkRow = AddCheckboxRow(effectsLeft, {
            label = "Show Spark",
            setting = CASTBAR_FINDER.effects and CASTBAR_FINDER.effects.spark,
            value = settings.showSpark ~= false,
            onChange = function(val)
                settings.showSpark = val
                applyCastBar()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        ST._AddAdvancedToggle(sparkRow, "castSpark", {}, true, {
            unlock = settings.showSpark == false and { target = settings, refreshKind = "castBar", enable = { label = "Enable Spark", key = "showSpark" } } or nil,
            build = function(panel)
                AddCheckboxRow(panel, {
                    label = "Show Spark Trail",
                    setting = CASTBAR_FINDER.effects and CASTBAR_FINDER.effects.sparkTrail,
                    indent = false,
                    value = settings.showSparkTrail ~= false,
                    onChange = function(val)
                        settings.showSparkTrail = val
                        applyCastBar()
                    end,
                })
            end,
        })

        AddCheckboxRow(effectsLeft, {
            label = "Show Cast Finish FX",
            setting = CASTBAR_FINDER.effects and CASTBAR_FINDER.effects.finish,
            value = settings.showCastFinishFX ~= false,
            onChange = function(val)
                settings.showCastFinishFX = val
                applyCastBar()
            end,
        })

        AddCheckboxRow(effectsRight, {
            label = "Show Interrupt Shake",
            setting = CASTBAR_FINDER.effects and CASTBAR_FINDER.effects.interruptShake,
            value = settings.showInterruptShake ~= false,
            onChange = function(val)
                settings.showInterruptShake = val
                applyCastBar()
            end,
        })

        AddCheckboxRow(effectsRight, {
            label = "Show Interrupt Glow",
            setting = CASTBAR_FINDER.effects and CASTBAR_FINDER.effects.interruptGlow,
            value = settings.showInterruptGlow ~= false,
            onChange = function(val)
                settings.showInterruptGlow = val
                applyCastBar()
            end,
        })
    end

    -- ================================================================
    -- Contents (what the bar draws on top of the fill)
    -- ================================================================
    local _, contentsCollapsed = BuildCollapsibleSection(container, "Text & Icon",
        ST._SharedBarStyleCollapseKey("barNameTypography", "castbar"), nil, nil, ROW_SECTION)

    if contentsCollapsed then return end

    ST._AddSettingsSubheading(container, "Name Text")
    local nameLeft, nameRight = BeginRowGrid(container)
    ST._BuildModuleBarStyleRows(nameRight, "castbar", nil, nil, "barNameTypography")
    ST._AddSettingsSubheading(container, "Duration Text")
    local durationLeft, durationRight = BeginRowGrid(container)
    ST._BuildModuleBarStyleRows(durationRight, "castbar", nil, nil, "barDurationTypography")
    ST._AddSettingsSubheading(container, "Icon")
    local iconLeft, iconRight = BeginRowGrid(container)
    ST._BuildModuleBarStyleRows(iconRight, "castbar", nil, nil, "barIconAppearance")
    ST._BuildModuleBarStyleRows(iconRight, "castbar", nil, nil, "iconZoom")
    ST._AddSettingsSubheading(container, "Channel Ticks")
    local contentsLeft = BeginRowGrid(container)

    local iconRow = AddCheckboxRow(iconLeft, {
        label = "Show Spell Icon",
        setting = CASTBAR_FINDER.contents and CASTBAR_FINDER.contents.icon,
        value = settings.showIcon ~= false,
        onChange = function(val)
            settings.showIcon = val
            CooldownCompanion:ApplyCastBarSettings()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- every row goes straight onto the panel scroll. All of these hang off the
    -- Icon Offset toggle, which lives in the same panel, so they indent as its
    -- children.
    local function BuildIconOffsetAdvanced(panel)
        -- The canvas reserves the icon's square out of the bar's length, so
        -- the fill re-measures under the drag.
        AddSliderRow(panel, {
            label = "Icon X Offset",
            setting = CASTBAR_FINDER.icon and CASTBAR_FINDER.icon.xOffset,
            indent = true,
            min = -50, max = 50, step = 0.1,
            value = settings.iconOffsetX or 0,
            onRelease = function(val)
                settings.iconOffsetX = val
                CooldownCompanion:ApplyCastBarSettings()
            end,
        })

        AddSliderRow(panel, {
            label = "Icon Y Offset",
            setting = CASTBAR_FINDER.icon and CASTBAR_FINDER.icon.yOffset,
            indent = true,
            min = -50, max = 50, step = 0.1,
            value = settings.iconOffsetY or 0,
            onRelease = function(val)
                settings.iconOffsetY = val
                CooldownCompanion:ApplyCastBarSettings()
            end,
        })

        -- Only the advanced panel rebuilds here, not the config column, so the
        -- canvas repaint has to be asked for.
        local iconRenderMode = AddBorderRenderModeDropdown(panel, settings, "iconBorderRenderMode", function()
            applyCastBar()
            if CS.RefreshAdvancedSettingsPanel then
                CS.RefreshAdvancedSettingsPanel()
            end
        end, nil, {
            row = true,
            indent = true,
            setting = CASTBAR_FINDER.icon and CASTBAR_FINDER.icon.borderThickness,
        })
        local borderThicknessLocked = ST.IsBorderThicknessLocked()

        if iconRenderMode ~= ST.BORDER_RENDER_MODE_CRISP then
            AddMirrorFirstSliderRow(panel, {
                label = "Icon Border Size",
                setting = CASTBAR_FINDER.icon and CASTBAR_FINDER.icon.borderSize,
                indent = true,
                min = 0, max = 4, step = 0.1,
                value = settings.iconBorderSize or 1,
                disabled = borderThicknessLocked,
                set = function(val)
                    if borderThicknessLocked then return end
                    settings.iconBorderSize = val
                end,
                apply = applyCastBar,
                stateOwner = settings,
                stateKeys = "iconBorderSize",
            })
        end
    end

    local function BuildIconAdvanced(panel)
        AddCheckboxRow(panel, {
            label = "Icon Offset",
            setting = CASTBAR_FINDER.icon and CASTBAR_FINDER.icon.offset,
            value = settings.iconOffset or false,
            onChange = function(val)
                settings.iconOffset = val
                applyCastBar()
                if CS.RefreshAdvancedSettingsPanel then
                    CS.RefreshAdvancedSettingsPanel()
                end
            end,
        })

        if settings.iconOffset then
            BuildIconOffsetAdvanced(panel)
        end
    end

    AddAdvancedToggle(iconRow, "castbarIcon", cbAdvBtns, true, {
        title = "Spell Icon Advanced",
        build = BuildIconAdvanced,
        -- Non-lens lazy spec (ST._ResolveAdvancedUnlock): write-true plus
        -- the contents checkboxes' apply-then-rebuild refresh sequence.
        unlock = settings.showIcon == false and {
            target = settings,
            enable = TURNON_SHOW_ICON,
            refreshKind = "castBar",
        } or nil,
    })

    local channelTickRow = AddCheckboxRow(contentsLeft, {
        label = "Show Channel Tick Marks",
        setting = CASTBAR_FINDER.contents and CASTBAR_FINDER.contents.ticks,
        value = settings.showChannelTickMarks == true,
        onChange = function(val)
            settings.showChannelTickMarks = val
            applyCastBar()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    local function BuildChannelTickAdvanced(panel)
        AddMirrorFirstSliderRow(panel, {
            label = "Tick Mark Width",
            setting = CASTBAR_FINDER.ticks and CASTBAR_FINDER.ticks.width,
            min = 1, max = 5, step = 0.1,
            value = settings.channelTickWidth or 1,
            set = function(val) settings.channelTickWidth = val end,
            apply = applyCastBar,
            stateOwner = settings,
            stateKeys = "channelTickWidth",
        })

        AddColorRow(panel, {
            label = "Tick Mark Color",
            setting = CASTBAR_FINDER.ticks and CASTBAR_FINDER.ticks.color,
            tbl = settings,
            key = "channelTickColor",
            default = {1, 1, 1, 0.8},
            hasAlpha = true,
            onConfirm = applyCastBar,
            onPreview = castPreviewOnly,
        })

        local penultimateRow = AddCheckboxRow(panel, {
            label = "Highlight\nSecond-to-Last Tick",
            labelLines = 2,
            height = 42,
            controlColumnWidth = 32,
            value = settings.highlightPenultimateChannelTick == true,
            onChange = function(val)
                settings.highlightPenultimateChannelTick = val
                applyCastBar()
                if CS.RefreshAdvancedSettingsPanel then
                    CS.RefreshAdvancedSettingsPanel()
                end
            end,
        })
        if CASTBAR_FINDER.ticks and CASTBAR_FINDER.ticks.penultimate
            and ST._BindSettingWidget then
            ST._BindSettingWidget(penultimateRow, CASTBAR_FINDER.ticks.penultimate)
        end

        if settings.highlightPenultimateChannelTick == true then
            AddColorRow(panel, {
                label = "Highlight Color",
                setting = CASTBAR_FINDER.ticks and CASTBAR_FINDER.ticks.highlightColor,
                indent = true,
                tbl = settings,
                key = "penultimateChannelTickColor",
                default = {1, 0.82, 0, 1},
                hasAlpha = true,
                onConfirm = applyCastBar,
                onPreview = castPreviewOnly,
            })
        end
    end

    AddAdvancedToggle(channelTickRow, "castbarChannelTicks", cbAdvBtns, true, {
        title = "Channel Tick Marks Advanced",
        build = BuildChannelTickAdvanced,
        -- Non-lens lazy spec (ST._ResolveAdvancedUnlock): this checkbox's
        -- sequence also repaints the canvas (applyCastBar), which no shared
        -- refreshKind runs, so the enable owns its whole sequence as `run`.
        unlock = settings.showChannelTickMarks ~= true and {
            enable = {
                label = "Enable Channel Tick Marks",
                run = function()
                    settings.showChannelTickMarks = true
                    applyCastBar()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            },
        } or nil,
    })

    local nameRow = AddCheckboxRow(nameLeft, {
        label = "Show Spell Name",
        setting = CASTBAR_FINDER.contents and CASTBAR_FINDER.contents.name,
        value = settings.showNameText ~= false,
        onChange = function(val)
            settings.showNameText = val
            CooldownCompanion:ApplyCastBarSettings()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    local castTimeRow = AddCheckboxRow(durationLeft, {
        label = "Show Cast Time",
        setting = CASTBAR_FINDER.contents and CASTBAR_FINDER.contents.time,
        value = settings.showCastTimeText ~= false,
        onChange = function(val)
            settings.showCastTimeText = val
            CooldownCompanion:ApplyCastBarSettings()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail. The two offsets are hand-written rather than routed through
    -- AddOffsetSliders: that helper takes ONE symmetric range, and this pair is
    -- deliberately +/-50 across and only +/-20 up the bar.
    local function BuildCastTimeAdvanced(panel)
        -- Both offsets place the countdown on the canvas facsimile too.
        AddMirrorFirstSliderRow(panel, {
            label = "X Offset",
            setting = CASTBAR_FINDER.castTime and CASTBAR_FINDER.castTime.xOffset,
            min = -50, max = 50, step = 0.1,
            value = settings.castTimeXOffset or 0,
            set = function(val) settings.castTimeXOffset = val end,
            apply = applyCastBar,
            stateOwner = settings,
            stateKeys = "castTimeXOffset",
        })

        AddMirrorFirstSliderRow(panel, {
            label = "Y Offset",
            setting = CASTBAR_FINDER.castTime and CASTBAR_FINDER.castTime.yOffset,
            min = -20, max = 20, step = 0.1,
            value = settings.castTimeYOffset or 0,
            set = function(val) settings.castTimeYOffset = val end,
            apply = applyCastBar,
            stateOwner = settings,
            stateKeys = "castTimeYOffset",
        })
    end

    AddAdvancedToggle(castTimeRow, "castbarCastTime", cbAdvBtns, true, {
        title = "Cast Time Advanced",
        build = BuildCastTimeAdvanced,
        -- Non-lens lazy spec (ST._ResolveAdvancedUnlock): write-true plus
        -- the contents checkboxes' apply-then-rebuild refresh sequence.
        unlock = settings.showCastTimeText == false and {
            target = settings,
            enable = TURNON_SHOW_CAST_TIME,
            refreshKind = "castBar",
        } or nil,
    })
end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildCastBarAnchoringPanel = BuildCastBarAnchoringPanel
ST._BuildCastBarPositioningPanel = BuildCastBarPositioningPanel
ST._BuildCastBarStylingPanel = BuildCastBarStylingPanel
ST._BuildAttachedCastBarOffsetControls = BuildAttachedCastBarOffsetControls
