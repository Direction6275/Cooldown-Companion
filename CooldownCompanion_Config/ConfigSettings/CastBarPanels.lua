local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- Imports from Helpers.lua
local BuildCollapsibleSection = ST._BuildCollapsibleSection
local AddAdvancedToggle = ST._AddAdvancedToggle
local CreateCharacterCopyButton = ST._CreateCharacterCopyButton
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
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

------------------------------------------------------------------------
-- SETTINGS FINDER CATALOG
------------------------------------------------------------------------

local CASTBAR_FINDER = {}

local function CastBarFinderEnabled(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true
end

local function CastBarFinderIconAdvanced(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true and settings.showIcon ~= false
end

local function CastBarFinderTicksAdvanced(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true and settings.showChannelTickMarks == true
end

local function CastBarFinderNameAdvanced(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true and settings.showNameText ~= false
end

local function CastBarFinderTimeAdvanced(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true and settings.showCastTimeText ~= false
end

local function CastBarFinderAttached(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true and settings.independentAnchorEnabled ~= true
end

local function CastBarFinderIndependent(context)
    local cache = context and context._ccCastBarFinderCache
    local settings = cache and cache.settings
    return settings and settings.enabled == true and settings.independentAnchorEnabled == true
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
        enabled = { label = "Enable Cast Bar Anchoring", aliases = { "enable cast bar" } },
        anchoringMode = { label = "Anchoring Mode", applies = CastBarFinderEnabled },
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
        yOffset = { label = "Y Offset", aliases = { "stack gap" } },
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
        sectionLabel = "Bar",
        collapseKeys = { "castbar_bar" },
        rowScope = "detail",
        applies = CastBarFinderEnabled,
    })
    CASTBAR_FINDER.bar = bar:Settings({
        texture = { label = "Bar Texture" },
        height = { label = "Height", aliases = { "bar height" } },
        color = { label = "Bar Color", aliases = { "fill color" } },
        background = { label = "Background Color" },
    })

    local border = ST._DefineSettingRoute({
        idPrefix = "castBar.appearance.border",
        scope = "castBar",
        tab = "appearance",
        tabLabel = "Appearance",
        tabStateKey = "castBarHomeTab",
        section = "border",
        sectionLabel = "Border",
        collapseKeys = { "castbar_border" },
        rowScope = "detail",
        applies = CastBarFinderEnabled,
    })
    CASTBAR_FINDER.border = border:Settings({
        style = { label = "Border Style" },
        color = { label = "Border Color", applies = CastBarFinderCacheFlag("pixelBorder") },
        thickness = { label = "Border Thickness", applies = CastBarFinderCacheFlag("pixelBorder") },
        size = { label = "Border Size", applies = CastBarFinderCacheFlag("customBorderSize") },
    })

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
        sparkTrail = { label = "Show Spark Trail", applies = CastBarFinderCacheFlag("sparkShown") },
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
        sectionLabel = "Contents",
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
        applies = CastBarFinderIconAdvanced,
    })
    CASTBAR_FINDER.icon = icon:Settings({
        zoom = { label = "Icon Zoom" },
        rightSide = { label = "Icon on Right Side" },
        offset = { label = "Icon Offset" },
        size = { label = "Icon Size", applies = CastBarFinderCacheFlag("iconOffsetEnabled") },
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
        applies = CastBarFinderTicksAdvanced,
    })
    CASTBAR_FINDER.ticks = ticks:Settings({
        width = { label = "Tick Mark Width" },
        color = { label = "Tick Mark Color" },
        penultimate = { label = "Highlight Second-to-Last Tick", aliases = { "second to last tick" } },
        highlightColor = { label = "Highlight Color", applies = CastBarFinderCacheFlag("penultimateHighlight") },
    })

    local name = ST._DefineSettingRoute({
        idPrefix = "castBar.appearance.contents.name",
        scope = "castBar",
        tab = "appearance",
        tabLabel = "Appearance",
        tabStateKey = "castBarHomeTab",
        section = "contents",
        sectionLabel = "Spell Name",
        collapseKeys = { "castbar_contents" },
        rowScope = "detail",
        advancedKey = "castbarNameText",
        applies = CastBarFinderNameAdvanced,
    })
    CASTBAR_FINDER.name = name:Settings({
        fontSize = { label = "Font Size" },
        font = { label = "Font" },
        outline = { label = "Font Outline" },
        color = { label = "Font Color" },
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
        applies = CastBarFinderTimeAdvanced,
    })
    CASTBAR_FINDER.castTime = castTime:Settings({
        fontSize = { label = "Font Size" },
        font = { label = "Font" },
        outline = { label = "Font Outline" },
        color = { label = "Font Color" },
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

local function CanShowAttachedCastBarOffsetControls(rbSettings, cbSettings, layout)
    return rbSettings
        and rbSettings.enabled
        and (not layout or layout.independentAnchorEnabled ~= true)
        and cbSettings
        and cbSettings.enabled
        and cbSettings.independentAnchorEnabled ~= true
end

-- Built once for the active Cast Bar Finder context. Applicability reads the
-- context-owned snapshot instead of resolving settings, spec layout, or
-- border state while a query is being typed.
local function RefreshCastBarFinderCache()
    local settings = CooldownCompanion:GetCastBarSettings()
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local layout = CooldownCompanion:GetSpecLayoutOrder()
    local castLayout = layout and layout.castBar
    local attachedOffsetAvailable = CanShowAttachedCastBarOffsetControls(
        rbSettings, settings, layout)
    local pixelBorder = settings and (settings.borderStyle or "pixel") == "pixel"
    local borderMode = settings and ST.GetBorderRenderMode(settings, "borderRenderMode")
    local iconBorderMode = settings and ST.GetBorderRenderMode(settings, "iconBorderRenderMode")

    local cache = {
        settings = settings,
        attachedOffsetAvailable = attachedOffsetAvailable == true,
        attachedYOffsetEnabled = attachedOffsetAvailable == true
            and type(castLayout) == "table"
            and castLayout.panelAnchorYOffsetEnabled == true,
        pixelBorder = pixelBorder == true,
        customBorderSize = pixelBorder == true
            and borderMode ~= ST.BORDER_RENDER_MODE_CRISP,
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

-- Two rows, both of them row-grammar: every call site is a grid column now
-- (the Resource Bars Layout section's right column, and this file's own
-- Layout tab), so there is no stock shape left to keep.
local function BuildAttachedCastBarOffsetControls(container, layout)
    local rbSettings = CooldownCompanion:GetResourceBarSettings()
    local cbSettings = CooldownCompanion:GetCastBarSettings()
    layout = layout or CooldownCompanion:GetSpecLayoutOrder()
    if not layout or not CanShowAttachedCastBarOffsetControls(rbSettings, cbSettings, layout) then
        return false
    end
    if type(layout.castBar) ~= "table" then
        layout.castBar = {}
    end
    local castLayout = layout.castBar

    AddCheckboxRow(container, {
        label = "Enable Cast Bar-Only Y Offset",
        setting = CASTBAR_FINDER.attached and CASTBAR_FINDER.attached.ownYOffset,
        value = castLayout.panelAnchorYOffsetEnabled == true,
        onChange = function(val)
            castLayout.panelAnchorYOffsetEnabled = val == true
            RefreshAttachedCastBarOffset(true)
        end,
    })

    if castLayout.panelAnchorYOffsetEnabled then
        AddSliderRow(container, {
            label = "Cast Bar Y Offset",
            setting = CASTBAR_FINDER.attached and CASTBAR_FINDER.attached.castBarYOffset,
            indent = true,
            min = -100, max = 100, step = 0.1,
            value = castLayout.panelAnchorYOffset or 0,
            onChange = function(val)
                ST._PreviewScalarSetting(castLayout, "panelAnchorYOffset", val, RefreshBarsCanvasForDrag)
            end,
            onRelease = function(val)
                castLayout.panelAnchorYOffset = val
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
            label = "Enable Cast Bar Anchoring",
            setting = CASTBAR_FINDER.general and CASTBAR_FINDER.general.enabled,
            value = settings.enabled,
            onChange = function(val)
                settings.enabled = val
                CooldownCompanion:EvaluateCastBar()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        CreateCharacterCopyButton(enableRow, "castBar", "Cast Bar", function()
            CooldownCompanion:EvaluateCastBar()
            CooldownCompanion:UpdateAnchorStacking()
            CooldownCompanion:RefreshConfigPanel()
        end)

        if settings.enabled then
            AddDropdownRow(generalLeft, {
                label = "Anchoring Mode",
                setting = CASTBAR_FINDER.general and CASTBAR_FINDER.general.anchoringMode,
                pulloutWidth = WIDE_PULLOUT_WIDTH,
                list = {
                    attached = "Attached to Panel",
                    independent = "Independent",
                },
                order = { "attached", "independent" },
                value = settings.independentAnchorEnabled == true and "independent" or "attached",
                onChange = function(val)
                    settings.independentAnchorEnabled = (val == "independent")
                    CooldownCompanion:EvaluateCastBar()
                    CooldownCompanion:UpdateAnchorStacking()
                    CooldownCompanion:RefreshConfigPanel()
                end,
            })
        end
    end

end

local function BuildCastBarPositioningPanel(container)
    local settings = CooldownCompanion:GetCastBarSettings()

    if not settings.enabled then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Enable Cast Bar Anchoring to configure positioning.")
        label:SetFullWidth(true)
        container:AddChild(label)
        return
    end

    if not settings.independentAnchorEnabled then
        local _, layoutCollapsed = BuildCollapsibleSection(container, "Layout",
            "castbar_layout", nil, nil, ROW_SECTION)

        if layoutCollapsed then return end

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
                CooldownCompanion:RepositionCastBar()
                CooldownCompanion:UpdateAnchorStacking()
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
        min = 20, max = 600, step = 1,
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
    local settings = CooldownCompanion:GetCastBarSettings()

    -- The retired styling switch used to carry this gate too: with the
    -- module off, styling rows would commit to a bar that immediately
    -- reverts. Same disabled-state surface as the positioning panel.
    if not settings.enabled then
        local label = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(label)
        label:SetText("Enable Cast Bar Anchoring to configure appearance.")
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

    -- ================================================================
    -- Bar (the fill itself, what shows behind it, and how tall it is)
    -- ================================================================
    -- The CC bar is always CC-styled: the old "Enable Cast Bar Styling"
    -- switch meant "restyle Blizzard's bar or leave it native", and that
    -- choice died with the frame replacement (owner ruling 2026-08-08).
    local _, barCollapsed = BuildCollapsibleSection(container, "Bar",
        "castbar_bar", nil, nil, ROW_SECTION)

    if not barCollapsed then
        -- LEFT column: the bar's own shape. RIGHT column: the two colors it
        -- draws with.
        local barLeft, barRight = BeginRowGrid(container)

        -- LibSharedMedia names run past the control column, so the menu is
        -- widened - a 140px control would otherwise open a 140px menu.
        local texRow = AddDropdownRow(barLeft, {
            label = "Bar Texture",
            setting = CASTBAR_FINDER.bar and CASTBAR_FINDER.bar.texture,
            pulloutWidth = WIDE_PULLOUT_WIDTH,
        })
        CS.SetupBarTextureDropdown(texRow)
        texRow:SetValue(settings.barTexture or "Solid")
        CS.SetBarTextureDropdownCallback(texRow, function(widget, event, val)
            settings.barTexture = val
            applyCastBar()
        end)

        -- The canvas sizes the cast slot from this value, so the whole
        -- stack reflows under the drag; the live bar restyles on release.
        AddMirrorFirstSliderRow(barLeft, {
            label = "Height",
            setting = CASTBAR_FINDER.bar and CASTBAR_FINDER.bar.height,
            min = 4, max = 40, step = 0.1,
            value = settings.height or 15,
            set = function(val) settings.height = val end,
            apply = applyCastBar,
            stateOwner = settings,
            stateKeys = "height",
        })

        AddColorRow(barRight, {
            label = "Bar Color",
            setting = CASTBAR_FINDER.bar and CASTBAR_FINDER.bar.color,
            tbl = settings,
            key = "barColor",
            default = {1.0, 0.7, 0.0, 1.0},
            hasAlpha = true,
            onConfirm = applyCastBar,
            onChange = castPreviewOnly,
        })

        AddColorRow(barRight, {
            label = "Background Color",
            setting = CASTBAR_FINDER.bar and CASTBAR_FINDER.bar.background,
            tbl = settings,
            key = "backgroundColor",
            default = {0, 0, 0, 0.5},
            hasAlpha = true,
            onConfirm = applyCastBar,
            onChange = castPreviewOnly,
        })
    end

    -- ================================================================
    -- Border
    -- ================================================================
    local _, borderCollapsed = BuildCollapsibleSection(container, "Border",
        "castbar_border", nil, nil, ROW_SECTION)

    if not borderCollapsed then
        -- LEFT column: which border is drawn, and the color it is drawn in.
        -- RIGHT column: how thick it is - the mode and the size it gates, which
        -- have to stay adjacent.
        local borderLeft, borderRight = BeginRowGrid(container)

        AddDropdownRow(borderLeft, {
            label = "Border Style",
            setting = CASTBAR_FINDER.border and CASTBAR_FINDER.border.style,
            list = {
                blizzard = "Blizzard",
                pixel = "Pixel",
                none = "None",
            },
            order = { "blizzard", "pixel", "none" },
            value = settings.borderStyle or "pixel",
            onChange = function(val)
                settings.borderStyle = val
                CooldownCompanion:ApplyCastBarSettings()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if settings.borderStyle == "pixel" then
            AddColorRow(borderLeft, {
                label = "Border Color",
                setting = CASTBAR_FINDER.border and CASTBAR_FINDER.border.color,
                indent = true,
                tbl = settings,
                key = "borderColor",
                default = {0, 0, 0, 1},
                hasAlpha = true,
                onConfirm = applyCastBar,
                onChange = castPreviewOnly,
            })

            local renderMode = AddBorderRenderModeDropdown(borderRight, settings, "borderRenderMode", function()
                CooldownCompanion:ApplyCastBarSettings()
                CooldownCompanion:RefreshConfigPanel()
            end, nil, {
                row = true,
                setting = CASTBAR_FINDER.border and CASTBAR_FINDER.border.thickness,
            })
            local borderThicknessLocked = ST.IsBorderThicknessLocked()

            if renderMode ~= ST.BORDER_RENDER_MODE_CRISP then
                AddMirrorFirstSliderRow(borderRight, {
                    label = "Border Size",
                    setting = CASTBAR_FINDER.border and CASTBAR_FINDER.border.size,
                    indent = true,
                    min = 0, max = 5, step = 0.1,
                    value = settings.borderSize or 1,
                    disabled = borderThicknessLocked,
                    set = function(val)
                        if borderThicknessLocked then return end
                        settings.borderSize = val
                    end,
                    apply = applyCastBar,
                    stateOwner = settings,
                    stateKeys = "borderSize",
                })
            end
        end
    end

    -- ================================================================
    -- Cast Effects
    -- ================================================================
    local _, effectsCollapsed = BuildCollapsibleSection(container, "Cast Effects",
        "castbar_effects", nil, nil, ROW_SECTION)

    if not effectsCollapsed then
        -- LEFT column: the spark pair and finish effect. RIGHT column: the
        -- interrupt pair, which reads as one choice.
        local effectsLeft, effectsRight = BeginRowGrid(container)

        AddCheckboxRow(effectsLeft, {
            label = "Show Spark",
            setting = CASTBAR_FINDER.effects and CASTBAR_FINDER.effects.spark,
            value = settings.showSpark ~= false,
            onChange = function(val)
                settings.showSpark = val
                applyCastBar()
                CooldownCompanion:RefreshConfigPanel()
            end,
        })

        if settings.showSpark ~= false then
            AddCheckboxRow(effectsLeft, {
                label = "Show Spark Trail",
                setting = CASTBAR_FINDER.effects and CASTBAR_FINDER.effects.sparkTrail,
                indent = true,
                value = settings.showSparkTrail ~= false,
                onChange = function(val)
                    settings.showSparkTrail = val
                    applyCastBar()
                end,
            })
        end

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
    local _, contentsCollapsed = BuildCollapsibleSection(container, "Contents",
        "castbar_contents", nil, nil, ROW_SECTION)

    if contentsCollapsed then return end

    -- LEFT column: the marks that ride the fill. RIGHT column: the two texts.
    local contentsLeft, contentsRight = BeginRowGrid(container)

    local iconRow = AddCheckboxRow(contentsLeft, {
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
        AddMirrorFirstSliderRow(panel, {
            label = "Icon Size",
            setting = CASTBAR_FINDER.icon and CASTBAR_FINDER.icon.size,
            indent = true,
            min = 8, max = 64, step = 0.1,
            value = settings.iconSize or 16,
            set = function(val) settings.iconSize = val end,
            apply = applyCastBar,
            stateOwner = settings,
            stateKeys = "iconSize",
        })

        -- The two offsets below are NOT on the canvas: the facsimile pins its
        -- icon flush to the slot's edge and never reads them.
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
        ST._BuildIconZoomControls(panel, settings, applyCastBar, {
            previewRefresh = castPreviewOnly,
            setting = CASTBAR_FINDER.icon and CASTBAR_FINDER.icon.zoom,
        })

        AddCheckboxRow(panel, {
            label = "Icon on Right Side",
            setting = CASTBAR_FINDER.icon and CASTBAR_FINDER.icon.rightSide,
            value = settings.iconFlipSide or false,
            onChange = function(val)
                settings.iconFlipSide = val
                applyCastBar()
            end,
        })

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

    AddAdvancedToggle(iconRow, "castbarIcon", cbAdvBtns, settings.showIcon ~= false, {
        title = "Spell Icon Advanced",
        build = BuildIconAdvanced,
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
            onChange = castPreviewOnly,
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
                onChange = castPreviewOnly,
            })
        end
    end

    AddAdvancedToggle(channelTickRow, "castbarChannelTicks", cbAdvBtns,
        settings.showChannelTickMarks == true, {
            title = "Channel Tick Marks Advanced",
            build = BuildChannelTickAdvanced,
        })

    local nameRow = AddCheckboxRow(contentsRight, {
        label = "Show Spell Name",
        setting = CASTBAR_FINDER.contents and CASTBAR_FINDER.contents.name,
        value = settings.showNameText ~= false,
        onChange = function(val)
            settings.showNameText = val
            CooldownCompanion:ApplyCastBarSettings()
            CooldownCompanion:RefreshConfigPanel()
        end,
    })

    -- Single rail: the font trio comes from the shared helper (its keys are
    -- exactly nameFont / nameFontSize / nameFontOutline) and the color follows.
    local function BuildNameTextAdvanced(panel)
        AddFontControls(panel, settings, "name", {
            size = 10, sizeMin = 6, sizeMax = 24, sizeStep = 0.1,
            font = "Friz Quadrata TT", outline = "OUTLINE",
        }, applyCastBar, {
            row = true,
            previewRefresh = castPreviewOnly,
            settings = CASTBAR_FINDER.name and {
                size = CASTBAR_FINDER.name.fontSize,
                font = CASTBAR_FINDER.name.font,
                outline = CASTBAR_FINDER.name.outline,
            },
        })

        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- this row replaced.
        AddColorRow(panel, {
            label = "Font Color",
            setting = CASTBAR_FINDER.name and CASTBAR_FINDER.name.color,
            tbl = settings,
            key = "nameFontColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = applyCastBar,
            onChange = castPreviewOnly,
        })
    end

    AddAdvancedToggle(nameRow, "castbarNameText", cbAdvBtns, settings.showNameText ~= false, {
        title = "Spell Name Advanced",
        build = BuildNameTextAdvanced,
    })

    local castTimeRow = AddCheckboxRow(contentsRight, {
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
        AddFontControls(panel, settings, "castTime", {
            size = 10, sizeMin = 6, sizeMax = 24, sizeStep = 0.1,
            font = "Friz Quadrata TT", outline = "OUTLINE",
        }, applyCastBar, {
            row = true,
            previewRefresh = castPreviewOnly,
            settings = CASTBAR_FINDER.castTime and {
                size = CASTBAR_FINDER.castTime.fontSize,
                font = CASTBAR_FINDER.castTime.font,
                outline = CASTBAR_FINDER.castTime.outline,
            },
        })

        -- deferCommit is deliberately absent, matching the stock color-picker call
        -- this row replaced.
        AddColorRow(panel, {
            label = "Font Color",
            setting = CASTBAR_FINDER.castTime and CASTBAR_FINDER.castTime.color,
            tbl = settings,
            key = "castTimeFontColor",
            default = {1, 1, 1, 1},
            hasAlpha = true,
            onConfirm = applyCastBar,
            onChange = castPreviewOnly,
        })

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

    AddAdvancedToggle(castTimeRow, "castbarCastTime", cbAdvBtns, settings.showCastTimeText ~= false, {
        title = "Cast Time Advanced",
        build = BuildCastTimeAdvanced,
    })
end

-- Expose for ButtonSettings.lua and Config.lua
ST._BuildCastBarAnchoringPanel = BuildCastBarAnchoringPanel
ST._BuildCastBarPositioningPanel = BuildCastBarPositioningPanel
ST._BuildCastBarStylingPanel = BuildCastBarStylingPanel
ST._BuildAttachedCastBarOffsetControls = BuildAttachedCastBarOffsetControls
