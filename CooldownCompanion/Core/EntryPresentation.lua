-- Entry presentation is independent of tracking identity and panel ownership.
local ADDON_NAME, ST = ...
local Addon = ST.Addon
ST.BAR_ONLY_LAYOUT_KEYS = { "mode", "compactLayout", "compactGrowthDirection", "maxVisibleButtons", "stackGap" }
ST.ATTACHED_BAR_LAYOUT_KEYS = { "spacing", "gap", "length" }

-- Geometry has one owner even when the bar's renderer belongs to a module.
-- Inputs are configuration/body geometry, never native aura-container extents.
function ST.ResolveBarGeometry(group, options)
    options = options or {}
    group = group and (group._attachedBarOwner or group._unifiedPanelOwner or group)
    local ordinary = ST.PanelSupportsAttachedBars(group)
    local attached = ordinary and options.attached ~= false
    local style = options.style or (ordinary and ST.GetAttachedBarStyle(group)) or {}
    local layout = ordinary and group.attachedBarLayout or {}
    layout = layout or {}
    local stack = ST.PanelUsesBarStack(group, options.layoutKind)
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
        distance = attached and (stack and (group.barOnlyLayout and group.barOnlyLayout.stackGap or 0)
            or layout.gap or 3) or options.distance or 3,
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

function ST.GetModuleGeometryHost(kind, spec)
    if not Addon.ResolveModulePanel then return nil end
    local target = Addon:ResolveModulePanel(kind, spec, spec and spec ~= Addon._currentSpecId and { configured = true } or nil)
    return target and target.mode ~= "independent" and target.group or nil
end

function ST.GetModuleGeometryPanel(kind, spec)
    local group = ST.GetModuleGeometryHost(kind, spec)
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
    if ST.PanelSupportsAttachedBars(group) and entry and entry.displayAs == "bars" then
        return "bars"
    end
    return group and group.displayMode or "icons"
end

function ST.IsPanelBarEntry(group, entry)
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    return ST.PanelSupportsAttachedBars(group) and entry and entry.displayAs == "bars" or false
end

function ST.CanSegmentEntryCharges(group, entry)
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    return entry ~= nil and not ST.IsAuraPanelGroup(group) and not ST.IsTotemPanelGroup(group)
        and ST.GetEntryPresentation(group, entry) == "bars"
        and entry.type == "spell" and entry.addedAs ~= "aura" and entry.hasCharges == true
end

-- Read the old ownership before override cleanup. Icon entries can carry a
-- dormant bar customization too; changing presentation must retain it.
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
end

-- Structural eligibility only: cooldown/aura visibility and temporary load
-- conditions cannot turn a mixed panel into a differently arranged bar grid.
function ST.IsPanelLayoutEntryEligible(group, entry)
    if not entry or entry.enabled == false then return false end
    if entry.specs and next(entry.specs) and not entry.specs[Addon._currentSpecId] then return false end
    if Addon.GetLoadConditionSourcesForEntry and Addon.EvaluateLoadConditionSources then
        return Addon:EvaluateLoadConditionSources(Addon:GetLoadConditionSourcesForEntry(entry, group), {
            eligibilityOnly = true,
        })
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
-- The same decision owns fitting, the saved bar arrangement and its controls.
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

function ST.GetBarOnlyLayoutMode(group)
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    if group and group.barOnlyLayout then
        return group.barOnlyLayout.mode == "stack" and "stack" or "grid"
    end
    -- The development attached-bar format predates the layout selector.
    if group and (group.attachedBarStyle or group.attachedBarLayout) then return "stack" end
    return "grid"
end

function ST.PanelUsesBarStack(group, kind)
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    return ST.PanelSupportsAttachedBars(group) and ST.GetPanelGeometryKind(group, kind) == "bars"
        and ST.GetBarOnlyLayoutMode(group) == "stack"
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
    return kind == "mixed" or ST.PanelUsesBarStack(group, kind)
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
    group.attachedBarStyle = CopyTable(ST._defaults.profile.globalStyle)
    group.barOnlyLayout = { mode = "grid" }
end
local styleCache = setmetatable({}, { __mode = "k" })

function ST.GetAttachedBarStyle(group, forEditing)
    if forEditing then
        group.barOnlyLayout = group.barOnlyLayout or { mode = ST.GetBarOnlyLayoutMode(group) }
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
    return style
end

function ST.GetEntryBaseStyle(group, entry)
    if entry and entry._geometryContext then return entry._geometryContext:ReadStyle() end
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    if ST.IsPanelBarEntry(group, entry) then return ST.GetAttachedBarStyle(group) end
    return group and group.style or {}
end

-- An ephemeral view lets the established Bar Panel grid consume its own
-- geometry without changing the saved panel type or the icon arrangement.
function ST.GetPanelLayoutGroup(group, forEditing, kind)
    if not ST.PanelSupportsAttachedBars(group) or ST.GetPanelGeometryKind(group, kind) ~= "bars"
        or ST.GetBarOnlyLayoutMode(group) ~= "grid" then return group end
    local layout = group.barOnlyLayout or {}
    return setmetatable({
        _unifiedPanelOwner = group, displayMode = "bars", style = ST.GetAttachedBarStyle(group, forEditing),
        compactLayout = layout.compactLayout == true,
        compactGrowthDirection = layout.compactGrowthDirection or "center",
        maxVisibleButtons = layout.maxVisibleButtons or 0,
    }, { __index = group })
end

function ST.GetPanelBarStyleGroup(group)
    local style = ST.GetAttachedBarStyle(group, true)
    local defaults = { compactLayout = false, compactGrowthDirection = "center", maxVisibleButtons = 0 }
    return setmetatable({ displayMode = "bars", style = style, _attachedBarOwner = group,
        _fittedBarLayout = ST.GetPanelGeometryKind(group) ~= "bars" }, {
        __index = function(_, key)
            if defaults[key] ~= nil then
                local value = group.barOnlyLayout and group.barOnlyLayout[key]
                if value ~= nil then return value end
                return defaults[key]
            end
            return group[key]
        end,
        __newindex = function(_, key, value)
            if defaults[key] ~= nil then
                group.barOnlyLayout = group.barOnlyLayout or { mode = ST.GetBarOnlyLayoutMode(group) }
                group.barOnlyLayout[key] = value
            else
                group[key] = value
            end
        end,
    })
end

-- Movers edit the visible bar dimensions in either bar-only arrangement.
function ST.GetPanelSizingGroup(group)
    if ST.PanelSupportsAttachedBars(group) and ST.GetPanelGeometryKind(group) == "bars" then
        return ST.GetPanelBarStyleGroup(group)
    end
    return group
end

function ST.GetBarOnlyLength(group, style)
    local oldLayout = not group.barOnlyLayout and group.attachedBarLayout
    return (oldLayout and oldLayout.length) or style.barLength or 180
end

function ST.GetPanelAttachmentDimensions(frame, group, region)
    if ST.PanelUsesBarStack(group) then
        local style = ST.GetAttachedBarStyle(group)
        local length, thickness = ST.GetBarOnlyLength(group, style), style.barHeight or 12
        return style.barFillVertical and thickness or length, style.barFillVertical and length or thickness
    end
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

function ST.GetBarGridCellDimensions(group)
    local style = group.style or {}
    local width, height = style.barLength or 180, style.barHeight or 20
    if style.barFillVertical then width, height = height, width end
    if group._unifiedPanelOwner then
        local includeInactive = ST.GetPanelLayoutKind(group._unifiedPanelOwner) == "empty"
        for _, entry in ipairs(group.buttons or {}) do
            if includeInactive or ST.IsPanelLayoutEntryEligible(group, entry) then
                local effective = Addon:GetEntryEffectiveStyle(group, entry)
                local w, h = effective.barLength or 180, effective.barHeight or 12
                if effective.barFillVertical then w, h = h, w end
                width, height = math.max(width, w), math.max(height, h)
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

function ST.GetPanelIconButtons(frame, group, buttons)
    if not ST.PanelHasAttachedBars(group) then return buttons end
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

function ST.PanelHasAttachedBars(group)
    if not ST.PanelUsesAttachedBarLayout(group) then return false end
    return true
end
