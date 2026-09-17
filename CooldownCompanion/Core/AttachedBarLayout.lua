-- Attached entry layout. Reads only CC-owned icon-body dimensions; native
-- aura-container extents are connected by anchors, never measured in Lua.
local ADDON_NAME, ST = ...
local Addon = ST.Addon
local SIDES = { "above", "below", "left", "right" }
local FLOW = {
    above = { point = "BOTTOM", far = "TOP", dx = 0, dy = 1 },
    below = { point = "TOP", far = "BOTTOM", dx = 0, dy = -1 },
    left = { point = "RIGHT", far = "LEFT", dx = -1, dy = 0 },
    right = { point = "LEFT", far = "RIGHT", dx = 1, dy = 0 },
}

-- Shared ordered model for the runtime and preview. Resource placement is a
-- boundary between areas, never a member interleaved among their entries.
function ST.BuildAttachedBarAreas(group)
    local areas, order = {}, {}
    for _, side in ipairs(SIDES) do
        for _, region in ipairs({ "main", "outer" }) do
            for _, resources in ipairs({ "before", "after" }) do
                local key = side .. ":" .. region .. ":" .. resources
                local area = { key = key, side = side, region = region,
                    resources = resources, entries = {} }
                areas[key] = area
                order[#order + 1] = area
            end
        end
    end
    if ST.PanelUsesAttachedBarLayout(group) then
        for index, entry in ipairs(group.buttons or {}) do
            if ST.IsPanelBarEntry(group, entry) then
                local side, region, resources = ST.GetAttachedBarPlacement(entry)
                region = ST.ResolvePanelAttachmentRegion(group, side, region)
                local area = areas[side .. ":" .. region .. ":" .. resources]
                area.entries[#area.entries + 1] = { entry = entry, index = index }
            end
        end
    end
    return order
end

-- Settings use configured membership, never live aura visibility or geometry.
function ST.AttachedBarGapApplies(group, modules)
    if not ST.PanelSupportsAttachedBars(group) then return false end
    if modules and #modules > 0 then return true end
    for _, area in ipairs(ST.BuildAttachedBarAreas(group)) do
        for _, item in ipairs(area.entries) do
            if ST.IsPanelLayoutEntryEligible(group, item.entry) then return true end
        end
    end
    return false
end

local function EnsureArea(frame, groupId, area)
    local states = frame._attachedBarAreas
    local state = states[area.key]
    if not state then
        local mount = CreateFrame("Frame", nil, frame, "DisableUntrustedLayoutScriptsTemplate")
        mount:SetSize(1, 1)
        state = { key = "entry-bars:" .. tostring(frame) .. ":" .. area.key,
            parent = frame, mount = mount }
        states[area.key] = state
    end
    return state
end

function ST.GetConfiguredPanelIconGeometry(group)
    local style, entries = group.style or {}, {}
    for _, entry in ipairs(group.buttons or {}) do
        if ST.GetEntryPresentation(group, entry) == "icons" and ST.IsPanelLayoutEntryEligible(group, entry) then
            entries[#entries + 1] = { buttonData = entry }
        end
    end
    local size = style.buttonSize or ST.BUTTON_SIZE
    local width = style.maintainAspectRatio and size or style.iconWidth or size
    local height = style.maintainAspectRatio and size or style.iconHeight or size
    local lists = ST.PartitionPanelSectionMembers(group, entries)
    return ST.BuildPanelSectionLayout(group, ST.GetSectionsForLayout(group) or {}, lists,
        width, height, style.buttonSpacing or ST.BUTTON_SPACING, 0)
end

-- Within an area fixed bars precede native aura buckets. Each unit's auras
-- stay contiguous, in saved order; the first encountered unit leads.
function ST.GetAttachedBarAreaOrder(group, entries)
    local ordered, units, firstUnit = {}, { player = {}, target = {} }, nil
    for _, item in ipairs(entries) do
        if ST.IsCollapsingAttachedBar(group, item.entry) then
            local unit = Addon:IsAuraTrackedOnTarget(item.entry) and "target" or "player"
            firstUnit = firstUnit or unit
            units[unit][#units[unit] + 1] = item
        else ordered[#ordered + 1] = item end
    end
    for _, unit in ipairs(firstUnit == "target" and { "target", "player" } or { "player", "target" }) do
        for _, item in ipairs(units[unit]) do ordered[#ordered + 1] = item end
    end
    return ordered
end

function ST.ResolveAttachedBarDimensions(group, style, side, width, height)
    local geometry = ST.ResolveBarGeometry(group, { style = style, thickness = style.barHeight,
        side = side, fit = ST.GetPanelLayoutKind(group) == "mixed", width = width, height = height,
        vertical = style.barFillVertical, length = ST.GetBarOnlyLength(group, style) })
    return geometry.width, geometry.height, geometry.vertical, geometry.length
end

-- Preview expansion uses explicit saved geometry, never live aura sizes.
function ST.GetAttachedBarPreviewLayout(group, width, height, base, included, modules)
    group = group._unifiedPanelOwner or group
    local positions, modulePositions = {}, {}
    local minX, minY, maxX, maxY = 0, 0, width, height
    local offsets = {}
    local geometry = ST.ResolveBarGeometry(group)
    local spacing, gap = geometry.spacing, geometry.distance
    local function Region(name)
        return name == "main" and base or { x = 0, y = 0, width = width, height = height }
    end
    local function Place(side, regionName, w, h, offset)
        local region = Region(regionName)
        local x, y = region.x + (region.width - w) / 2, region.y + (region.height - h) / 2
        if side == "above" then y = region.y - offset - h
        elseif side == "below" then y = region.y + region.height + offset
        elseif side == "left" then x = region.x - offset - w
        else x = region.x + region.width + offset end
        minX, minY = math.min(minX, x), math.min(minY, y)
        maxX, maxY = math.max(maxX, x + w), math.max(maxY, y + h)
        return { x = x, y = -y, width = w, height = h, vertical = side == "left" or side == "right" }
    end
    local function PlaceModule(module)
        local side, region = module.side, ST.ResolvePanelAttachmentRegion(group, module.side, module.region)
        local lane, body = side .. ":" .. region, Region(region)
        local vertical = side == "left" or side == "right"
        local length = vertical and body.height or body.width
        if ST.GetPanelLayoutKind(group) == "bars" and ST.GetBarOnlyLayoutMode(group) == "stack" then
            local style = ST.GetAttachedBarStyle(group)
            local barLength, thickness = ST.GetBarOnlyLength(group, style), style.barHeight or 12
            local w, h = style.barFillVertical and thickness or barLength, style.barFillVertical and barLength or thickness
            length = vertical and h or w
        end
        local yOffset = module.kind == "cast" and module.attachmentOffset or 0
        local offset = (offsets[lane] or gap) + (module.side == "above" and yOffset or -yOffset)
        local position = Place(side, region, vertical and module.thickness or length,
            vertical and length or module.thickness, offset)
        position.module = module
        modulePositions[#modulePositions + 1] = position
        offsets[lane] = offset + module.thickness + spacing
    end
    for _, area in ipairs(ST.BuildAttachedBarAreas(group)) do
        local region = Region(area.region)
        local lane = area.side .. ":" .. area.region
        if area.resources == "after" then
            for _, module in ipairs(modules or {}) do
                if module.kind == "resources" and module.side == area.side
                    and ST.ResolvePanelAttachmentRegion(group, module.side, module.region) == area.region then
                    PlaceModule(module)
                end
            end
        end
        local offset = offsets[lane] or gap
        local ordered = ST.GetAttachedBarAreaOrder(group, area.entries)
        for _, item in ipairs(ordered) do
            if not included or included[item.index] then
                local style = Addon:GetEntryEffectiveStyle(group, item.entry)
                local w, h, vertical = ST.ResolveAttachedBarDimensions(group, style, area.side, region.width, region.height)
                local position = Place(area.side, area.region, w, h, offset)
                position.vertical = vertical
                positions[item.index] = position
                offset = offset + ((area.side == "left" or area.side == "right") and w or h) + spacing
            end
        end
        -- An empty area must not replace an absent predecessor with spacing.
        if #ordered > 0 or offsets[lane] then offsets[lane] = offset end
    end
    for _, module in ipairs(modules or {}) do
        if module.kind == "cast" then PlaceModule(module) end
    end
    return positions, -minX, -minY, maxX - minX, maxY - minY, modulePositions
end

-- Resize the configured stack, not its 1px owner or its dormant Grid cells.
-- Edge factors count only dimensions inherited from the panel. Customized
-- shapes still contribute to the bounds, but resizing cannot change them.
function ST.GetBarStackResizeMetrics(group, included, positions, originX, originY, width, height)
    local panelStyle = ST.GetAttachedBarStyle(group)
    local vertical = panelStyle.barFillVertical == true
    local widthKey = vertical and "barHeight" or "barLength"
    local heightKey = vertical and "barLength" or "barHeight"
    local metrics = {
        xSide = originX > width - originX - 1 and "LEFT" or "RIGHT",
        ySide = originY > height - originY - 1 and "TOP" or "BOTTOM",
        xFactor = 0, yFactor = 0,
    }
    local xEdge = metrics.xSide == "LEFT" and 0 or 1
    local yEdge = metrics.ySide == "TOP" and 0 or 1
    local offsets = {}
    for _, area in ipairs(ST.BuildAttachedBarAreas(group)) do
        local lane = area.side .. ":" .. area.region
        local offset = offsets[lane] or 0
        local sideways = area.side == "left" or area.side == "right"
        for _, item in ipairs(ST.GetAttachedBarAreaOrder(group, area.entries)) do
            if included[item.index] then
                local style = Addon:GetEntryEffectiveStyle(group, item.entry)
                local base = ST.GetEntryBaseStyle(group, item.entry)
                local sameOrientation = (style.barFillVertical == true) == vertical
                local dw = sameOrientation and (style == base or rawget(style, widthKey) == nil) and 1 or 0
                local dh = sameOrientation and (style == base or rawget(style, heightKey) == nil) and 1 or 0
                local left, right, top, bottom = -dw / 2, dw / 2, -dh / 2, dh / 2
                if area.side == "left" then left, right = -offset - dw, -offset
                elseif area.side == "right" then left, right = offset, offset + dw
                elseif area.side == "above" then top, bottom = -offset - dh, -offset
                else top, bottom = offset, offset + dh end
                local position = positions[item.index]
                local x = metrics.xSide == "LEFT" and -position.x or position.x + position.width
                local y = metrics.ySide == "TOP" and position.y or -position.y + position.height
                local xFactor = metrics.xSide == "LEFT" and -left or right
                local yFactor = metrics.ySide == "TOP" and -top or bottom
                if x > xEdge then xEdge, metrics.xFactor = x, xFactor
                elseif x == xEdge then metrics.xFactor = math.max(metrics.xFactor, xFactor) end
                if y > yEdge then yEdge, metrics.yFactor = y, yFactor
                elseif y == yEdge then metrics.yFactor = math.max(metrics.yFactor, yFactor) end
                offset = offset + (sideways and dw or dh)
            end
        end
        offsets[lane] = offset
    end
    return metrics
end

function ST.LayoutAttachedBars(groupId, frame, group)
    group = group._unifiedPanelOwner or group
    if not ST.PanelSupportsAttachedBars(group) then return end
    local attached = ST.PanelUsesAttachedBarLayout(group)
    if not attached then
        for _, state in pairs(frame._attachedBarAreas or {}) do
            state.entries, state.tail = {}, nil
        end
    end
    local resourceBlocks = Addon.GetPanelResourceBlocks and Addon:GetPanelResourceBlocks(groupId) or {}
    if not attached and not next(resourceBlocks) then
        frame._attachmentTails = nil
        return
    end
    frame._attachedBarAreas = frame._attachedBarAreas or {}
    local byEntry = {}
    for _, button in ipairs(frame.buttons or {}) do byEntry[button.buttonData] = button end
    local geometry = ST.ResolveBarGeometry(group)
    local spacing, gap = geometry.spacing, geometry.distance
    local body = ST.GetPanelAnchorBodyFrame(frame)
    local hasIcons = (frame.visibleButtonCount or 0) > 0
        or (frame._sectionLayout and next(frame._sectionLayout.sections))
    local mixed = ST.GetPanelLayoutKind(group) == "mixed"
    local configured = mixed and not hasIcons and ST.GetConfiguredPanelIconGeometry(group)
    local previous = {}
    for _, area in ipairs(ST.BuildAttachedBarAreas(group)) do
        local state = EnsureArea(frame, groupId, area)
        state.entries = {}
        state.side, state.spacing = area.side, spacing
        local flow = FLOW[area.side]
        state.point, state.far, state.dx, state.dy = flow.point, flow.far, flow.dx, flow.dy
        local anchorBody = area.region == "main" and body or frame
        local lane = area.side .. ":" .. area.region
        local predecessor = previous[lane]
        -- Each module supplies its own live block. The coordinator only moves
        -- that block; it never enables, updates, or destroys module frames.
        if area.resources == "after" then
            local block = resourceBlocks[lane]
            if block then
                block.frame:ClearAllPoints()
                local distance = predecessor and spacing or gap
                block.frame:SetPoint(flow.point, predecessor or anchorBody, flow.far,
                    flow.dx * distance, flow.dy * distance)
                predecessor = block.tail or block.frame
            end
        end
        local ref = predecessor or anchorBody
        local regionWidth, regionHeight = anchorBody:GetWidth(), anchorBody:GetHeight()
        if configured then
            regionWidth = area.region == "main" and configured.baseWidth or configured.footprintWidth
            regionHeight = area.region == "main" and configured.baseHeight or configured.footprintHeight
        end
        local offset = gap
        if predecessor then offset = spacing end
        local last = nil
        for _, item in ipairs(area.entries) do
            local entry, button = item.entry, byEntry[item.entry]
            if button then
                local effective = Addon:GetEntryEffectiveStyle(group, entry)
                -- Runtime geometry is transient: no fitted dimension or
                -- orientation is written back into an entry's customizations.
                local style = {}
                for key, value in pairs(ST.GetEntryBaseStyle(group, entry)) do style[key] = value end
                for key, value in pairs(effective) do style[key] = value end
                local width, height, vertical, length = ST.ResolveAttachedBarDimensions(
                    group, style, area.side, regionWidth, regionHeight)
                style.barLength, style.barFillVertical = length, vertical
                -- A positioning pass must not reset the charge renderer or
                -- cooldown visuals. Normal style refreshes already apply all
                -- appearance changes; only a changed fitted geometry needs
                -- another style application here.
                local current = button.style
                if not current or current.barLength ~= length
                    or (current.barFillVertical == true) ~= vertical then
                    button:UpdateStyle(style)
                end
                if ST.IsCollapsingAttachedBar(group, entry) then
                    Addon:StampAuraSectionEntryKey(group, entry)
                    button:Hide()
                    state.entries[#state.entries + 1] = {
                        id = tostring(entry._auraKey), buttonData = entry, style = style,
                        width = width, height = height,
                        vertical = vertical, spacing = spacing,
                        inset = style.borderSize or ST.DEFAULT_BORDER_SIZE,
                    }
                elseif not button._visibilityHidden or button._forceVisibleByConfig then
                    button:ClearAllPoints()
                    button:SetPoint(flow.point, last or ref, flow.far,
                        flow.dx * (last and spacing or offset), flow.dy * (last and spacing or offset))
                    button:Show()
                    last = button
                end
            end
        end
        state.mount:ClearAllPoints()
        state.mount:SetPoint(flow.point, last or ref, flow.far,
            flow.dx * (last and spacing or offset), flow.dy * (last and spacing or offset))
        if #state.entries == 0 then state.tail = nil end
        state.fixedTail = last
        previous[lane] = state.tail or last or predecessor
    end
    frame._attachmentTails = previous
end

-- The cast bar has exactly one legal ordering position: the terminal edge of
-- its selected lane. Tails may be native aura containers; never measure them.
function ST.GetPanelAttachmentTail(frame, side, region)
    local group = frame and Addon.db and Addon.db.profile.groups[frame.groupId]
    if group then region = ST.ResolvePanelAttachmentRegion(group, side, region) end
    return frame and frame._attachmentTails and frame._attachmentTails[side .. ":" .. region]
end

function ST.RefreshPanelAttachments(groupId)
    local frame = Addon.groupFrames and Addon.groupFrames[groupId]
    local group = Addon.db and Addon.db.profile.groups[groupId]
    if frame and group then ST.LayoutAttachedBars(groupId, frame, group) end
    if Addon.RepositionCastBar then Addon:RepositionCastBar() end
end

function ST.CollectAttachedBarAuraBlocks(wants)
    for groupId, frame in pairs(Addon.groupFrames or {}) do
        local group = Addon.db.profile.groups[groupId]
        if ST.PanelHasAttachedBars(group) then
            -- Restore the current owner mounts before the OOC bind pass. The
            -- collectors use saved eligibility, never aura activity.
            ST.LayoutAttachedBars(groupId, frame, group)
            for _, area in ipairs(ST.BuildAttachedBarAreas(group)) do
                local state = frame._attachedBarAreas[area.key]
                local want = { side = area.side, owner = state, entries = {} }
                state.tail = nil
                for _, entry in ipairs(state.entries) do
                    local data = entry.buttonData
                    local candidates = Addon:GetAuraCandidateSpellIDSet(data, true)
                    if candidates then
                        entry.spellSet = candidates
                        entry.unit = Addon:IsAuraTrackedOnTarget(data) and "target" or "player"
                        if Addon:IsBarPanelAuraStackDisplay(data) then
                            entry.stackBarMax = Addon:GetAuraStackBarMax(data, true)
                        end
                        want.entries[#want.entries + 1] = entry
                    end
                end
                want.targetFirst = want.entries[1] and want.entries[1].unit == "target" or false
                wants[#wants + 1] = want
            end
        end
    end
end

-- Native aura buckets are one placement unit. Their saved entry order still
-- determines order within the bucket; dragging the bucket cannot split it.
function ST.GetAttachedBarDragEntries(group, source)
    local result = {}
    if not ST.IsCollapsingAttachedBar(group, source) then return { source } end
    local side, region, resources = ST.GetAttachedBarPlacement(source)
    region = ST.ResolvePanelAttachmentRegion(group, side, region)
    local target = Addon:IsAuraTrackedOnTarget(source)
    for _, entry in ipairs(group.buttons or {}) do
        local es, er, ep = ST.GetAttachedBarPlacement(entry)
        er = ST.ResolvePanelAttachmentRegion(group, es, er)
        if ST.IsCollapsingAttachedBar(group, entry) and es == side and er == region and ep == resources
            and Addon:IsAuraTrackedOnTarget(entry) == target then result[#result + 1] = entry end
    end
    return result
end

function ST.GetAttachedBarDropRejection(group, source, destination, after)
    if not destination then return end
    local sourceAura, targetAura = ST.IsCollapsingAttachedBar(group, source), ST.IsCollapsingAttachedBar(group, destination)
    if sourceAura and not targetAura and not after then
        return "Collapsing aura groups follow the fixed bars in each area."
    end
    if not sourceAura and targetAura and after then
        return "Fixed bars must precede the collapsing aura groups in each area."
    end
end

-- Preview and commit share the same ordering decision. This phase never writes
-- entries, so hovering a destination cannot change saved placement or identity.
function ST.PlanAttachedBarEntryMove(group, source, target)
    if not ST.PanelUsesAttachedBarLayout(group) or not target then return end
    local exists = false
    for _, entry in ipairs(group.buttons) do if entry == source then exists = true; break end end
    if not exists then return end
    local destination = target.index and group.buttons[target.index]
    local reason = ST.GetAttachedBarDropRejection(group, source, destination, target.after)
    if reason then return nil, nil, reason end
    local unit = ST.GetAttachedBarDragEntries(group, source)
    local moving = {}; for _, entry in ipairs(unit) do moving[entry] = true end
    if moving[destination] then return end
    -- A hit anywhere within another native group names its complete edge.
    -- Inserting among its saved members would draw somewhere else once the
    -- native containers restore indivisible unit ordering.
    if destination and ST.IsCollapsingAttachedBar(group, destination) then
        local targetUnit = ST.GetAttachedBarDragEntries(group, destination)
        destination = target.after and targetUnit[#targetUnit] or targetUnit[1]
    end
    local remaining, insert = {}, nil
    for _, entry in ipairs(group.buttons) do
        if not moving[entry] then
            if entry == destination and not target.after then insert = #remaining + 1 end
            remaining[#remaining + 1] = entry
            if entry == destination and target.after then insert = #remaining + 1 end
        end
    end
    insert = insert or #remaining + 1
    for i, entry in ipairs(unit) do
        table.insert(remaining, insert + i - 1, entry)
    end
    return remaining, unit
end

function Addon:MoveAttachedBarEntries(groupId, source, target)
    local group = self.db.profile.groups[groupId]
    local remaining, unit, reason = ST.PlanAttachedBarEntryMove(group, source, target)
    if not remaining then
        if reason then self:Print(reason) end
        return false
    end
    for _, entry in ipairs(unit) do
        entry.barPlacement = { side = target.side, region = target.region, resources = target.resources or "after" }
    end
    wipe(group.buttons)
    for i, entry in ipairs(remaining) do group.buttons[i] = entry end
    self:RefreshGroupFrame(groupId)
    self:RequestAuraRebind("config", groupId)
    return true
end
