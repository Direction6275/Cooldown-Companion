-- Entry presentation is independent of tracking identity and panel ownership.
local ADDON_NAME, ST = ...
local Addon = ST.Addon
ST.ATTACHED_BAR_LAYOUT_KEYS = { "spacing", "gap" }

-- Geometry has one owner even when the bar's renderer belongs to a module.
-- Inputs are configuration/body geometry, never native aura-container extents.
function ST.ResolveBarGeometry(group, options)
    options = options or {}
    group = group and (group._attachedBarOwner or group._unifiedPanelOwner or group)
    local ordinary = ST.PanelSupportsAttachedBars(group)
    local attached = ordinary and options.attached ~= false
    local style = options.style or (ordinary and ST.GetAttachedBarStyle(group)) or {}
    local layout = ordinary and group.attachedBarLayout or {}
    local vertical = options.vertical == true
    if attached and options.fit then vertical = options.side == "left" or options.side == "right" end
    local thickness = options.thickness
    local owner = options.owner
    if owner and owner.overrideSections and owner.overrideSections.barThickness and owner.styleOverrides then
        thickness = rawget(owner.styleOverrides, "barHeight") or thickness
    end
    thickness = thickness or (attached and style.barHeight) or options.baseline or style.barHeight or 12
    local length = options.length or style.barLength or 180
    if attached and options.fit then length = (vertical and options.height or options.width) or length end
    length = math.max(1, length)
    return {
        thickness = thickness, length = length, vertical = vertical,
        width = vertical and thickness or length, height = vertical and length or thickness,
        spacing = attached and (layout.spacing or 3) or options.spacing or 3,
        distance = attached and (layout.gap or 3) or options.distance or 3,
    }
end

-- Read-only availability checks must not create a module setup as a side
-- effect of opening an ordinary Panel's settings.
function ST.GetConfiguredModuleBarSettings(kind)
    local profile = Addon.db and Addon.db.profile
    if not profile then return nil end
    if kind == "resources" then
        return profile.resourceBarsByClass and profile.resourceBarsByClass[Addon._playerClassFilename]
    end
    local char = Addon.db.keys and Addon.db.keys.char
    return profile.castBarByChar and profile.castBarByChar[char]
end

-- target: an already resolved runtime ResolveModulePanel(kind) result, so a
-- caller that resolved once per apply reuses it.
function ST.GetModuleGeometryHost(kind, spec, target)
    if not target then
        if not Addon.ResolveModulePanel then return nil end
        target = Addon:ResolveModulePanel(kind, spec, spec and spec ~= Addon._currentSpecId and { configured = true } or nil)
    end
    return target and target.mode ~= "independent" and target.group or nil
end

function ST.GetModuleGeometryPanel(kind, spec, target)
    local group = ST.GetModuleGeometryHost(kind, spec, target)
    return ST.PanelSupportsAttachedBars(group) and group or nil
end

function ST.UsesSharedModuleGeometry(kind, spec)
    if not Addon.ResolveModulePanel then return false end
    local group = ST.GetModuleGeometryHost(kind, spec)
    return not group or ST.PanelSupportsAttachedBars(group)
end

function ST.ResolveResourceBarGeometry(settings, layout, powerType, group)
    settings, layout = settings or {}, layout or {}
    local vertical = (layout.orientation or settings.orientation) == "vertical"
    local baseline = vertical and (layout.barWidth or settings.barWidth or layout.barHeight or settings.barHeight)
        or (layout.barHeight or settings.barHeight or layout.barWidth or settings.barWidth)
    local slot = layout.resources and layout.resources[powerType]
    local thickness
    -- Specialized hosts retain their old geometry behavior. Independent bars
    -- use the same explicit customization but keep their local sizing baseline.
    if not ST.PanelSupportsAttachedBars(group) and (group or settings._barGeometryVersion ~= 1)
        and layout.customBarHeights and slot then
        thickness = vertical and (slot.barWidth or slot.barHeight) or (slot.barHeight or slot.barWidth)
    end
    return ST.ResolveBarGeometry(group, { owner = (not group or ST.PanelSupportsAttachedBars(group)) and slot or nil, baseline = baseline or 12, thickness = thickness,
        vertical = vertical, spacing = layout.barSpacing or settings.barSpacing or 3.6 })
end

-- Segment spacing follows the same panel -> individual resource ownership as
-- thickness. Independent/specialized hosts retain their resource default.
function ST.ResolveResourceSegmentGap(settings, layout, powerType, group)
    settings, layout = settings or {}, layout or {}
    local canonical = ST._RB and ST._RB.GetCanonicalPowerType and ST._RB.GetCanonicalPowerType(powerType) or powerType
    local slot = layout.resources and layout.resources[canonical]
    if slot and slot.overrideSections and slot.overrideSections.barCharges and slot.styleOverrides then
        local value = rawget(slot.styleOverrides, "barChargeSegmentGap")
        if value ~= nil then return value end
    end
    if ST.PanelSupportsAttachedBars(group) then
        return ST.GetAttachedBarStyle(group).barChargeSegmentGap or 4
    end
    return layout.segmentGap or settings.segmentGap or 4
end

function ST.ResolveCastBarGeometry(settings, group)
    settings = settings or {}
    return ST.ResolveBarGeometry(group, { owner = (not group or ST.PanelSupportsAttachedBars(group)) and settings or nil, baseline = settings.height or 15 })
end

-- Screen Y is independent of attachment side: positive is up, negative down.
-- The old field measured distance away from the panel. Keep that interpretation
-- only for legacy values, including character-owned defaults which can be
-- inherited by several specs on different sides of a class-shared layout.
function ST.GetCastBarAttachmentOffset(settings, layout)
    settings = settings or {}
    local placement = layout and layout.castBar or {}
    local enabled, offset = placement.panelAnchorYOffsetEnabled, placement.panelAnchorScreenYOffset
    if enabled == nil then enabled = settings.panelAnchorYOffsetEnabled end
    if offset == nil then
        offset = placement.panelAnchorYOffset
        if offset == nil then offset = settings.panelAnchorYOffset end
        offset = (tonumber(offset) or 0) * (placement.position == "above" and 1 or -1)
    end
    offset = tonumber(offset) or 0
    return enabled == true and offset or 0, enabled == true, offset
end

function ST.PanelSupportsAttachedBars(group)
    return type(group) == "table"
        and (group.displayMode or "icons") == "icons"
        and not ST.IsAuraPanelGroup(group)
        and not ST.IsTotemPanelGroup(group)
end

function ST.GetEntryPresentation(group, entry)
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    if entry and entry.rotationAssistant then return "icons" end
    if ST.IsIndicatorGroup(group) then return "indicator" end
    if ST.PanelSupportsAttachedBars(group) and entry and entry.displayAs == "bars" then
        return "bars"
    end
    return group and group.displayMode or "icons"
end

function ST.IsPanelBarEntry(group, entry)
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    return ST.PanelSupportsAttachedBars(group) and entry and not entry.rotationAssistant
        and entry.displayAs == "bars" or false
end

function ST.CanSegmentEntryCharges(group, entry)
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    return entry ~= nil and not ST.IsAuraPanelGroup(group) and not ST.IsTotemPanelGroup(group)
        and ST.GetEntryPresentation(group, entry) == "bars"
        and entry.type == "spell" and entry.addedAs ~= "aura" and entry.hasCharges == true
end

function ST.CanUseBarSegmentGap(group, entry)
    if not entry or ST.GetEntryPresentation(group, entry) ~= "bars" then return false end
    if ST.CanSegmentEntryCharges(group, entry) and entry.barSegmentCharges == true then return true end
    if entry.type ~= "spell" or not (entry.addedAs == "aura" or entry.auraTracking == true)
        or not Addon:IsBarPanelAuraStackDisplay(entry)
        or Addon:GetBarPanelAuraStackDisplayMode(entry) ~= "segmented" then return false end
    local maximum = Addon:GetAuraStackBarMax(entry, true)
    return maximum ~= nil and maximum > 1 and maximum <= ST.STACK_SEGMENT_MAX
end

-- Read the old ownership before override cleanup. Icon entries can carry a
-- dormant bar customization too; changing presentation must retain it. The
-- retired panel-level key is dropped once its entries are seeded, so an entry
-- that arrives later with no choice reads off instead of inheriting it.
function ST.NormalizeEntryBarCharges(group)
    local base = ST.PanelSupportsAttachedBars(group) and (group.attachedBarStyle or ST.ATTACHED_BAR_DEFAULTS) or group.style or {}
    for _, entry in ipairs(group.buttons or {}) do
        if entry.barSegmentCharges == nil then
            local value = base.barSegmentCharges
            if entry.overrideSections and entry.overrideSections.barCharges and entry.styleOverrides then
                local override = rawget(entry.styleOverrides, "barSegmentCharges")
                if override ~= nil then value = override end
            end
            entry.barSegmentCharges = value == true
        end
        if entry.styleOverrides then
            entry.styleOverrides.barSegmentCharges = nil
            if entry.overrideSections and rawget(entry.styleOverrides, "barChargeSegmentGap") == nil then
                entry.overrideSections.barCharges = nil
                if not next(entry.overrideSections) then entry.overrideSections = nil end
            end
            if not next(entry.styleOverrides) then entry.styleOverrides = nil end
        end
    end
    if group.attachedBarStyle then group.attachedBarStyle.barSegmentCharges = nil end
    if group.style then group.style.barSegmentCharges = nil end
end

-- LEGACY CONVERSION. Bar-only panels once kept a separate arrangement block: a
-- Grid / Collapsing Stack choice and a second Compact Mode. A panel now has one
-- Compact Mode, and a bar-only panel is always a Grid (owner ruling
-- 2026-10-19). The block is consumed whole and removed, so every load and
-- import can run this; panel templates retire theirs in the template store.
-- A Stack becomes the one-line Grid it drew, its near edge left where the
-- stack began. Only its first bar's side survives a stack spread over several
-- sides, and a Stack's Resources or cast bar now attach to the Grid's edge.
local STACK_TO_GRID = {
    below = { orientation = "vertical", origin = "TOPLEFT", point = "TOP", dx = 0, dy = -1 },
    above = { orientation = "vertical", origin = "BOTTOMLEFT", point = "BOTTOM", dx = 0, dy = 1 },
    right = { orientation = "horizontal", origin = "TOPLEFT", point = "LEFT", dx = 1, dy = 0 },
    left = { orientation = "horizontal", origin = "TOPRIGHT", point = "RIGHT", dx = -1, dy = 0 },
}
-- A Stack never wrapped; this keeps its line unbroken as entries are added.
local STACK_LINE_LENGTH = 100

-- Writes the block's compact trio onto its owner's one setting. A Stack always
-- closed its cooldown bars' gaps, so it counts as on.
local function IsLegacyBarCompactOn(layout)
    return layout.mode == "stack" or layout.compactLayout == true
end
local function ApplyLegacyBarCompact(owner, layout)
    local stack = layout.mode == "stack"
    if IsLegacyBarCompactOn(layout) then owner.compactLayout = true end
    owner.compactGrowthDirection = stack and "start" or layout.compactGrowthDirection or "center"
    owner.maxVisibleButtons = not stack and tonumber(layout.maxVisibleButtons) or 0
end

function ST.RetireBarOnlyLayout(group)
    local layout = type(group) == "table" and rawget(group, "barOnlyLayout")
    if layout == nil then return end
    group.barOnlyLayout = nil
    if type(layout) ~= "table" or not ST.PanelSupportsAttachedBars(group) then return end
    -- The block only ever arranged a panel whose entries are all bars. On any
    -- other panel it was dormant, and the panel's own Compact Mode governed.
    local first
    for _, entry in ipairs(group.buttons or {}) do
        if not ST.IsPanelBarEntry(group, entry) then return end
        first = first or entry
    end
    if not first then return end
    if layout.mode == "stack" then
        local line = STACK_TO_GRID[(ST.GetAttachedBarPlacement(first))]
        local style = group.attachedBarStyle or CopyTable(ST.ATTACHED_BAR_DEFAULTS)
        group.attachedBarStyle = style
        style.barOrientation, style.growthOrigin = line.orientation, line.origin
        style.buttonsPerRow = math.max(#group.buttons, STACK_LINE_LENGTH)
        style.buttonSpacing = group.attachedBarLayout and group.attachedBarLayout.spacing or 3
        local anchor = group.anchor
        if type(anchor) == "table" and not (Addon.IsCursorAnchor and Addon:IsCursorAnchor(anchor)) then
            local gap = tonumber(layout.stackGap) or 0
            anchor.point = line.point
            anchor.x = (tonumber(anchor.x) or 0) + line.dx * gap
            anchor.y = (tonumber(anchor.y) or 0) + line.dy * gap
            anchor.baseWidth, anchor.baseHeight = nil, nil
        end
    end
    -- The block's growth and limit are what a bar-only panel showed, so it
    -- keeps them even with the block's Compact Mode off.
    ApplyLegacyBarCompact(group, layout)
end

-- The template-store twin. A template has no entries to show whether its panel
-- was bar-only, so its block may have been dormant: the block's Compact Mode
-- (a Stack counts as on) carries over only when the template's own is off, and
-- the captured coverage grows to match. Never touches a template's position.
function ST.RetireTemplateBarOnlyLayout(template)
    if type(template) ~= "table" then return end
    local fields = type(template.capturedFields) == "table" and template.capturedFields or nil
    if fields then fields.barOnlyLayout = nil end
    local layout = rawget(template, "barOnlyLayout")
    if layout == nil then return end
    template.barOnlyLayout = nil
    if type(layout) ~= "table" or not ST.PanelSupportsAttachedBars(template) then return end
    if template.compactLayout == true or not IsLegacyBarCompactOn(layout) then return end
    ApplyLegacyBarCompact(template, layout)
    if fields and type(fields.group) == "table" then
        for _, key in ipairs(ST.COMPACT_LAYOUT_KEYS) do fields.group[key] = true end
    end
end

-- Read-only; nothing may write into it.
local LAYOUT_ELIGIBILITY_OPTS = { eligibilityOnly = true }

-- Structural eligibility only: cooldown/aura visibility and temporary load
-- conditions cannot turn a mixed panel into a differently arranged bar grid.
function ST.IsPanelLayoutEntryEligible(group, entry)
    if not entry or entry.enabled == false then return false end
    if entry.specs and next(entry.specs) and not entry.specs[Addon._currentSpecId] then return false end
    if Addon.GetLoadConditionSourcesForEntry and Addon.EvaluateLoadConditionSources then
        return Addon:EvaluateLoadConditionSources(Addon:GetLoadConditionSourcesForEntry(entry, group),
            LAYOUT_ELIGIBILITY_OPTS)
    end
    return true
end

function ST.GetPanelLayoutKind(group)
    if group and group._unifiedPanelOwner then return "bars" end
    if not ST.PanelSupportsAttachedBars(group) then return group and group.displayMode or "icons" end
    local icons, bars = false, false
    for _, entry in ipairs(group.buttons or {}) do
        if ST.IsPanelLayoutEntryEligible(group, entry) then
            if entry.displayAs == "bars" then bars = true else icons = true end
            if icons and bars then return "mixed" end
        end
    end
    if bars then return "bars" end
    return icons and "icons" or "empty"
end

-- Eligibility still controls runtime membership. When none is eligible,
-- configured entries provide the geometry for editing their inactive ghosts.
-- The same decision picks attached-bar fitting versus the bar-only grid, and
-- which dimensions the movers edit.
function ST.GetPanelGeometryKind(group, kind)
    kind = kind or ST.GetPanelLayoutKind(group)
    if kind ~= "empty" then return kind end
    local icons, bars = false, false
    for _, entry in ipairs(group.buttons or {}) do
        if entry.displayAs == "bars" then bars = true else icons = true end
    end
    if icons and bars then return "mixed" end
    return bars and "bars" or icons and "icons" or "empty"
end

function ST.PanelUsesAttachedBarLayout(group, kind)
    if not ST.PanelSupportsAttachedBars(group) then return false end
    kind = ST.GetPanelGeometryKind(group, kind)
    if kind == "icons" then
        -- Disabled/spec-ineligible bars can still be shown for editing. They
        -- belong beside the icon body even when no eligible bar remains to
        -- make this a mixed layout; they must never become icon-grid cells.
        for _, entry in ipairs(group.buttons or {}) do
            if ST.IsPanelBarEntry(group, entry) then return true end
        end
    end
    return kind == "mixed"
end

function ST.IsAttachedBarEntry(group, entry, layoutKind)
    return ST.IsPanelBarEntry(group, entry) and ST.PanelUsesAttachedBarLayout(group, layoutKind) or false
end

-- Freeze canonical defaults, never the current profile's icon baseline.
ST.ATTACHED_BAR_DEFAULTS = CopyTable(ST._defaults.profile.globalStyle)
ST.ATTACHED_BAR_DEFAULTS.barHeight = 12
ST.ATTACHED_BAR_DEFAULTS.barLength = 180
ST.ATTACHED_BAR_DEFAULTS.showBarIcon = false
ST.ATTACHED_BAR_DEFAULTS.showBarNameText = false
ST.ATTACHED_BAR_DEFAULTS.showKeybindText = false

-- Creation policy is separate from the saved-data fallback above. Existing
-- panels and imports with absent defaults must keep their compact appearance.
function ST.InitializeNewPanelBarStyle(group)
    if not ST.PanelSupportsAttachedBars(group) then return end
    group._barGeometryVersion = 1
    group._sharedBarStyleVersion = 1
    group.attachedBarStyle = CopyTable(ST._defaults.profile.globalStyle)
end
local styleCache = setmetatable({}, { __mode = "k" })

function ST.GetAttachedBarStyle(group, forEditing)
    if forEditing then
        if not group.attachedBarStyle then
            group.attachedBarStyle = CopyTable(ST.ATTACHED_BAR_DEFAULTS)
        end
        -- Editors and runtime use the same canonical fallback. Materialize
        -- only missing values; explicit false, zero, and empty values survive.
        for key, value in pairs(ST.ATTACHED_BAR_DEFAULTS) do
            if group.attachedBarStyle[key] == nil then
                group.attachedBarStyle[key] = type(value) == "table" and CopyTable(value) or value
            end
        end
        return group.attachedBarStyle
    end
    if not group.attachedBarStyle then return ST.ATTACHED_BAR_DEFAULTS end
    local style = styleCache[group]
    if not style then style = {}; styleCache[group] = style end
    wipe(style)
    for key, value in pairs(ST.ATTACHED_BAR_DEFAULTS) do style[key] = value end
    for key, value in pairs(group.attachedBarStyle) do style[key] = value end
    if ST.ApplySharedBarTypography then ST.ApplySharedBarTypography(style) end
    return style
end

-- barStyle: an already resolved GetAttachedBarStyle(owner) for a caller
-- walking many entries in one pass.
function ST.GetEntryBaseStyle(group, entry, barStyle)
    if entry and entry._geometryContext then return entry._geometryContext:ReadStyle() end
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    if ST.IsPanelBarEntry(group, entry) then return barStyle or ST.GetAttachedBarStyle(group) end
    return group and group.style or {}
end

-- An ephemeral view lets the bars-mode grid lay out a bar-only panel from its
-- shared bar style without changing the saved panel type or the icon arrangement.
-- Compact Mode is the panel's own: one setting for icons and bars alike.
function ST.GetPanelLayoutGroup(group, forEditing, kind)
    if not ST.PanelSupportsAttachedBars(group) or ST.GetPanelGeometryKind(group, kind) ~= "bars" then return group end
    return setmetatable({
        _unifiedPanelOwner = group, displayMode = "bars", style = ST.GetAttachedBarStyle(group, forEditing),
    }, { __index = group })
end

function ST.GetPanelBarStyleGroup(group)
    local style = ST.GetAttachedBarStyle(group, true)
    return setmetatable({ displayMode = "bars", style = style, _attachedBarOwner = group,
        _fittedBarLayout = ST.GetPanelGeometryKind(group) ~= "bars" }, { __index = group, __newindex = group })
end

-- Movers on a bar-only panel edit its shared bar style's dimensions.
function ST.GetPanelSizingGroup(group)
    if ST.PanelSupportsAttachedBars(group) and ST.GetPanelGeometryKind(group) == "bars" then
        return ST.GetPanelBarStyleGroup(group)
    end
    return group
end

function ST.GetPanelAttachmentDimensions(frame, group, region)
    if ST.PanelSupportsAttachedBars(group) and ST.GetConfiguredPanelIconGeometry
        and (frame.visibleButtonCount or 0) == 0
        and not (frame._sectionLayout and next(frame._sectionLayout.sections))
        and ST.GetPanelGeometryKind(group) ~= "bars" then
        local configured = ST.GetConfiguredPanelIconGeometry(group)
        if region == "main" then return configured.baseWidth, configured.baseHeight end
        return configured.footprintWidth, configured.footprintHeight
    end
    local body = region == "main" and ST.GetPanelAnchorBodyFrame(frame) or frame
    return body:GetWidth(), body:GetHeight()
end

function Addon:GetEntryEffectiveStyle(group, entry)
    return self:GetEffectiveStyle(ST.GetEntryBaseStyle(group, entry), entry, group)
end

local function WidenBarCell(width, height, group, entry, barStyle)
    local effective = Addon:GetEffectiveStyle(ST.GetEntryBaseStyle(group, entry, barStyle), entry, group)
    local w, h = effective.barLength or 180, effective.barHeight or 12
    if effective.barFillVertical then w, h = h, w end
    return math.max(width, w), math.max(height, h)
end

function ST.GetBarGridCellDimensions(group)
    local style = group.style or {}
    local width, height = style.barLength or 180, style.barHeight or 20
    if style.barFillVertical then width, height = height, width end
    local owner = group._unifiedPanelOwner
    if owner then
        local barStyle = ST.GetAttachedBarStyle(owner)
        local anyEligible = false
        for _, entry in ipairs(group.buttons or {}) do
            if ST.IsPanelLayoutEntryEligible(group, entry) then
                anyEligible = true
                width, height = WidenBarCell(width, height, group, entry, barStyle)
            end
        end
        -- Nothing eligible: the configured entries size the inactive ghosts.
        if not anyEligible and ST.GetPanelLayoutKind(owner) == "empty" then
            for _, entry in ipairs(group.buttons or {}) do
                width, height = WidenBarCell(width, height, group, entry, barStyle)
            end
        end
    end
    return width, height
end

local SIDES = { above = true, below = true, left = true, right = true }
function ST.GetAttachedBarPlacement(entry)
    local placement = entry and entry.barPlacement or {}
    return SIDES[placement.side] and placement.side or "below",
        placement.region == "outer" and "outer" or "main",
        placement.resources == "before" and "before" or "after"
end

function ST.ResolvePanelAttachmentRegion(group, side, region)
    region = region == "main" and "main" or "outer"
    if region == "main" or not ST.GetSectionsForLayout then return region end
    for _, entry in ipairs(group.buttons or {}) do
        if not ST.IsPanelBarEntry(group, entry) then
            local anchor = ST.GetPanelSectionForEntry(group, entry)
            if anchor then
                local _, sectionSide = ST.GetPanelSectionPlacement(group, anchor)
                if sectionSide == side then return region end
            end
        end
    end
    return "main"
end

function ST.IsCollapsingAttachedBar(group, entry, layoutKind)
    return entry and entry.type == "spell" and entry.addedAs == "aura"
        and entry.hideWhileAuraNotActive == true
        and not entry.auraTrackGroup and not entry.auraTrackPet
        and ST.IsAttachedBarEntry(group, entry, layoutKind) or false
end

function Addon:SetEntryPresentation(groupId, index, presentation)
    local group = self.db.profile.groups[groupId]
    local entry = group and group.buttons and group.buttons[index]
    if not ST.PanelSupportsAttachedBars(group) or not entry then return false end
    if presentation ~= "icons" and presentation ~= "bars" then return false end
    if entry.rotationAssistant and presentation ~= "icons" then return false end
    if ST.GetEntryPresentation(group, entry) == presentation then return true end
    self:ClearAllConfigPreviews()
    entry.displayAs = presentation == "bars" and "bars" or nil
    if presentation == "bars" then
        ST.GetAttachedBarStyle(group, true)
        self:StampAuraSectionEntryKey(group, entry)
    elseif entry.section and not (group.sections and group.sections[entry.section]) then
        entry.section = nil
    end
    self:RefreshGroupFrame(groupId)
    self:RequestAuraRebind("config", groupId)
    return true
end

-- Moves detach only source-owned placement. Copies retain placement.
function ST.DetachEntryBarPlacement(entry)
    if entry then entry.barPlacement = nil end
end

-- Its only caller, ApplyActiveButtonLayout, runs after the populate stamp or
-- the style pass's stamp check, so the stamped kind is current; a nil stamp
-- falls back to a fresh walk.
function ST.GetPanelIconButtons(frame, group, buttons)
    if not ST.PanelUsesAttachedBarLayout(group, frame._panelLayoutKind) then return buttons end
    local icons = frame._iconLayoutButtons or {}
    frame._iconLayoutButtons = icons
    wipe(icons)
    for _, button in ipairs(buttons) do
        if not ST.IsPanelBarEntry(group, button.buttonData) then
            icons[#icons + 1] = button
        end
    end
    return icons
end

