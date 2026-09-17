-- Detached attachment layouts for drag previews. Only the drop handler writes
-- saved data; geometry comes from the same coordinator as the resting preview.
local _, ST = ...
local PP = ST._ButtonPanelPreview
local Drag = {}
PP.AttachmentDrag = Drag

local function ShallowCopy(value)
    local copy = {}
    for key, item in pairs(value) do copy[key] = item end
    return setmetatable(copy, getmetatable(value))
end

-- A resource boundary may move past a complete native aura unit, never through
-- one. Both preview and commit consume this map of entry-owned placements.
function Drag.ResourcePlacements(group, target)
    local destination = target.index and group.buttons[target.index]
    local placements = {}
    if not destination then return placements end
    local unitSet, ordered = {}, {}
    for _, entry in ipairs(ST.GetAttachedBarDragEntries(group, destination)) do unitSet[entry] = true end
    local region = ST.ResolvePanelAttachmentRegion(group, target.side, target.region)
    for _, area in ipairs(ST.BuildAttachedBarAreas(group)) do
        if area.side == target.side and area.region == region then
            for _, item in ipairs(ST.GetAttachedBarAreaOrder(group, area.entries)) do
                ordered[#ordered + 1] = item.entry
            end
        end
    end
    local boundary
    for i, entry in ipairs(ordered) do
        if unitSet[entry] then
            if not boundary or target.after then boundary = i end
        end
    end
    if boundary then
        for i, entry in ipairs(ordered) do
            local side, entryRegion = ST.GetAttachedBarPlacement(entry)
            placements[entry] = { side = side, region = entryRegion,
                resources = (i < boundary or (i == boundary and target.after)) and "before" or "after" }
        end
    end
    return placements
end

function Drag.Project(group, modules, source, target)
    local order, placements = group.buttons, {}
    local projectedModules = {}
    for i, module in ipairs(modules) do projectedModules[i] = ShallowCopy(module) end
    if target and not target.rejectMessage then
        if source.buttonData then
            local moved, unit = ST.PlanAttachedBarEntryMove(group, source.buttonData, target)
            if moved then
                order = moved
                for _, entry in ipairs(unit) do
                    placements[entry] = { side = target.side, region = target.region,
                        resources = target.resources or "after" }
                end
            end
        elseif source.module then
            local block = source.module
            for i, module in ipairs(modules) do
                if module == block then
                    projectedModules[i].side, projectedModules[i].region = target.side, target.region
                end
            end
            if block.kind == "resources" then
                placements = Drag.ResourcePlacements(group, target)
                -- Crossing to an occupied side appends to its one resource
                -- block, using the same internal order and spacing as commit.
                local merged, result = nil, {}
                for _, module in ipairs(projectedModules) do
                    if module.kind == "resources" and module.side == target.side then
                        if not merged then
                            merged = ShallowCopy(module)
                            merged.slots = {}
                            merged.region = target.region
                            result[#result + 1] = merged
                        end
                    else result[#result + 1] = module end
                end
                for _, original in ipairs(modules) do
                    if original ~= block and original.kind == "resources" and original.side == target.side then
                        for _, slot in ipairs(original.slots) do merged.slots[#merged.slots + 1] = slot end
                    end
                end
                for _, slot in ipairs(block.slots) do merged.slots[#merged.slots + 1] = slot end
                merged.thickness = 0
                for i, slot in ipairs(merged.slots) do
                    merged.thickness = merged.thickness + (slot.thickness or 12)
                        + (i > 1 and (merged.spacing or 0) or 0)
                end
                projectedModules = result
            end
        end
    end
    local projected = ShallowCopy(group)
    projected.buttons = {}
    for i, entry in ipairs(order) do
        projected.buttons[i] = entry
        if placements[entry] then
            projected.buttons[i] = ShallowCopy(entry)
            projected.buttons[i].barPlacement = placements[entry]
        end
    end
    return projected, projectedModules, order
end

function Drag.Layout(preview, group, modules, source, target)
    local projected, projectedModules, order = Drag.Project(group, modules, source, target)
    local body, included, indices = preview.attachmentBody, {}, {}
    for index, entry in ipairs(group.buttons) do indices[entry] = index end
    for i, entry in ipairs(order) do
        included[i] = preview.layoutDrag.slots[indices[entry]] ~= nil
    end
    local positions, _, _, _, _, modulePositions = ST.GetAttachedBarPreviewLayout(projected,
        body.width, body.height, body.base, included, projectedModules)
    local byIndex = {}
    -- Keep the body and fit scale fixed for the entire gesture. Recentring on
    -- the changing attachment bounds would move the icons under the cursor.
    for i, position in pairs(positions) do
        position.x, position.y = position.x + body.padX, position.y - body.padY
        byIndex[indices[order[i]]] = position
    end
    for _, position in ipairs(modulePositions) do
        position.x, position.y = position.x + body.padX, position.y - body.padY
    end
    return byIndex, modulePositions
end

function Drag.Bounds(rect, position)
    if not rect then return { x = position.x, y = position.y, width = position.width, height = position.height } end
    local right = math.max(rect.x + rect.width, position.x + position.width)
    local bottom = math.min(rect.y - rect.height, position.y - position.height)
    rect.x, rect.y = math.min(rect.x, position.x), math.max(rect.y, position.y)
    rect.width, rect.height = right - rect.x, rect.y - bottom
    return rect
end

function Drag.Paint(preview, group, positions, modules, moving, movingSlots)
    local bounds
    for index, position in pairs(positions) do
        local slot = preview.layoutDrag.slots[index]
        if slot then
            local entry = group.buttons[index]
            if moving[entry] then
                slot:SetAlpha(0)
                bounds = Drag.Bounds(bounds, position)
            else
                PP.QueuePreviewSlotTween(preview, slot, "TOPLEFT", position.x, position.y)
                slot:SetAlpha(slot._cdcBaseAlpha or 1)
            end
        end
    end
    ST._BuildPanelModulePreview(preview, preview.panelId, modules, nil, true)
    for _, position in ipairs(modules) do
        for _, descriptor in ipairs(position.module.slots) do
            local frame = preview.modulePreview.framesBySlot[descriptor]
            frame:SetAlpha(movingSlots[descriptor] and 0 or 1)
            if movingSlots[descriptor] then
                bounds = Drag.Bounds(bounds, { x = frame._attachmentX, y = frame._attachmentY,
                    width = frame:GetWidth(), height = frame:GetHeight() })
            end
        end
    end
    PP.StartPreviewTicker(preview)
    return bounds
end
