-- Entry presentation is independent of tracking identity and panel ownership.
local ADDON_NAME, ST = ...
local Addon = ST.Addon
ST.BAR_ONLY_LAYOUT_KEYS = { "mode", "compactLayout", "compactGrowthDirection", "maxVisibleButtons", "stackGap" }
ST.ATTACHED_BAR_LAYOUT_KEYS = { "spacing", "gap", "length" }

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

function ST.GetBarOnlyLayoutMode(group)
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    if group and group.barOnlyLayout then
        return group.barOnlyLayout.mode == "stack" and "stack" or "grid"
    end
    -- The development attached-bar format predates the layout selector.
    if group and (group.attachedBarStyle or group.attachedBarLayout) then return "stack" end
    return "grid"
end

function ST.PanelUsesAttachedBarLayout(group)
    if not ST.PanelSupportsAttachedBars(group) then return false end
    local kind = ST.GetPanelLayoutKind(group)
    return kind == "mixed" or (kind == "bars" and ST.GetBarOnlyLayoutMode(group) == "stack")
end

function ST.IsAttachedBarEntry(group, entry)
    return ST.IsPanelBarEntry(group, entry) and ST.PanelUsesAttachedBarLayout(group) or false
end

-- Freeze canonical defaults, never the current profile's icon baseline.
ST.ATTACHED_BAR_DEFAULTS = CopyTable(ST._defaults.profile.globalStyle)
ST.ATTACHED_BAR_DEFAULTS.barHeight = 12
ST.ATTACHED_BAR_DEFAULTS.barLength = 180
ST.ATTACHED_BAR_DEFAULTS.showBarIcon = false
ST.ATTACHED_BAR_DEFAULTS.showBarNameText = false
ST.ATTACHED_BAR_DEFAULTS.showKeybindText = false
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
    group = group and (group._unifiedPanelOwner or group._attachedBarOwner or group)
    if ST.IsPanelBarEntry(group, entry) then return ST.GetAttachedBarStyle(group) end
    return group and group.style or {}
end

-- An ephemeral view lets the established Bar Panel grid consume its own
-- geometry without changing the saved panel type or the icon arrangement.
function ST.GetPanelLayoutGroup(group, forEditing)
    if not ST.PanelSupportsAttachedBars(group) or ST.GetPanelLayoutKind(group) ~= "bars"
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
        _fittedBarLayout = ST.GetPanelLayoutKind(group) == "mixed" }, {
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
    if ST.PanelSupportsAttachedBars(group) and ST.GetPanelLayoutKind(group) == "bars" then
        return ST.GetPanelBarStyleGroup(group)
    end
    return group
end

function ST.GetBarOnlyLength(group, style)
    local oldLayout = not group.barOnlyLayout and group.attachedBarLayout
    return (oldLayout and oldLayout.length) or style.barLength or 180
end

function ST.GetPanelAttachmentDimensions(frame, group, region)
    if ST.PanelSupportsAttachedBars(group) and ST.GetPanelLayoutKind(group) == "bars"
        and ST.GetBarOnlyLayoutMode(group) == "stack" then
        local style = ST.GetAttachedBarStyle(group)
        local length, thickness = ST.GetBarOnlyLength(group, style), style.barHeight or 12
        return style.barFillVertical and thickness or length, style.barFillVertical and length or thickness
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
        for _, entry in ipairs(group.buttons or {}) do
            if ST.IsPanelLayoutEntryEligible(group, entry) then
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

function ST.IsCollapsingAttachedBar(group, entry)
    return ST.IsAttachedBarEntry(group, entry)
        and entry.type == "spell" and entry.addedAs == "aura"
        and entry.hideWhileAuraNotActive == true
        and not entry.auraTrackGroup and not entry.auraTrackPet
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
