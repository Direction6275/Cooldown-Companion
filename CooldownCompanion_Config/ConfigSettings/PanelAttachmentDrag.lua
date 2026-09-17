-- Attached entries and module blocks share the normal preview drag lifecycle.
local _, ST = ...
local Addon, CS = ST.Addon, ST._configState
local PP = ST._ButtonPanelPreview
local SIDES = { "above", "below", "left", "right" }

local function CursorLocal(preview, x, y)
    local left, bottom, width, height = preview.content:GetScaledRect()
    if not left or not width or width <= 0 then return end
    local scale = width / preview.content:GetWidth()
    return (x - left) / scale, (bottom + height - y) / scale, scale
end

local function Contains(rect, x, y, margin)
    margin = margin or 0
    return x >= rect.x - margin and x <= rect.x + rect.width + margin
        and y >= -rect.y - margin and y <= -rect.y + rect.height + margin
end

function ST._CreatePanelAttachmentDrag(preview, panelId, positions, modules, outer)
    local group = Addon.db.profile.groups[panelId]
    if not ST.PanelSupportsAttachedBars(group) then return end
    local model = { panelPreview = true, panelId = panelId, preview = preview, positions = positions }
    local Drag = PP.AttachmentDrag
    local moduleList = {}
    for _, position in ipairs(modules) do moduleList[#moduleList + 1] = position.module end
    local entryTargets, visited, indices = {}, {}, {}
    for index, entry in ipairs(group.buttons) do indices[entry] = index end
    for index, entry in ipairs(group.buttons) do
        if positions[index] and not visited[entry] then
            local rect
            for _, member in ipairs(ST.GetAttachedBarDragEntries(group, entry)) do
                visited[member] = true
                local position = positions[indices[member]]
                if position then rect = Drag.Bounds(rect, position) end
            end
            local side, region, resources = ST.GetAttachedBarPlacement(entry)
            entryTargets[#entryTargets + 1] = { index = index, entry = entry, rect = rect,
                side = side, region = ST.ResolvePanelAttachmentRegion(group, side, region), resources = resources }
        end
    end
    local pads = {}
    for _, region in ipairs({ "main", "outer" }) do
        local rect = region == "main" and preview.barBaseRect or outer
        for _, side in ipairs(SIDES) do
            if ST.ResolvePanelAttachmentRegion(group, side, region) == region then
                local x, y = rect.x + rect.width / 2, rect.y + rect.height / 2
                if side == "above" then y = rect.y - 16
                elseif side == "below" then y = rect.y + rect.height + 16
                elseif side == "left" then x = rect.x - 16
                else x = rect.x + rect.width + 16 end
                pads[#pads + 1] = { x = x, y = y, side = side, region = region }
            end
        end
    end
    model.resolveDropTarget = function(cx, cy, state)
        local x, y, scale = CursorLocal(preview, cx, cy)
        if not x then return end
        local source = state and state.slotData
        local module = source and source.module
        local function Supported(side)
            if not module then return true end
            if module.kind == "cast" then return side == "above" or side == "below" end
            local vertical = module.side == "left" or module.side == "right"
            return vertical == (side == "left" or side == "right")
        end
        -- Resolve against the resting geometry, never the animated frames.
        -- Native aura buckets have one hit rectangle and two legal edges.
        for _, candidate in ipairs(entryTargets) do
            local rect, side, region = candidate.rect, candidate.side, candidate.region
            if Supported(side) and Contains(rect, x, y, 2 / scale) then
                local after = (side == "below" and y >= -rect.y + rect.height / 2)
                    or (side == "above" and y < -rect.y + rect.height / 2)
                    or (side == "right" and x >= rect.x + rect.width / 2)
                    or (side == "left" and x < rect.x + rect.width / 2)
                return { side = side, region = region, resources = candidate.resources, index = candidate.index, after = after,
                    rect = rect, rejectMessage = source and source.buttonData
                        and ST.GetAttachedBarDropRejection(group, source.buttonData, candidate.entry, after) }
            end
        end
        for _, position in ipairs(modules) do
            local block = position.module
            if block.kind == "resources" and Supported(block.side) and Contains(position, x, y, 3 / scale) then
                local before = (block.side == "below" and y < -position.y + position.height / 2)
                    or (block.side == "above" and y >= -position.y + position.height / 2)
                    or (block.side == "right" and x < position.x + position.width / 2)
                    or (block.side == "left" and x >= position.x + position.width / 2)
                return { side = block.side, region = block.region, resources = before and "before" or "after", rect = position }
            end
        end
        local closest, distance
        for _, pad in ipairs(pads) do
            if Supported(pad.side) then
                local d = (x - pad.x)^2 + (y - pad.y)^2
                if not distance or d < distance then closest, distance = pad, d end
            end
        end
        if closest and distance <= (100 / scale)^2 then
            return { side = closest.side, region = closest.region, resources = "after",
                rect = { x = closest.x, y = -closest.y, width = 1, height = 1 } }
        end
    end
    local moving, movingSlots, movingCount, lastTarget, lastBounds
    local function SameTarget(a, b)
        return a == b or (a and b and a.side == b.side and a.region == b.region
            and a.resources == b.resources and a.index == b.index and a.after == b.after
            and a.rejectMessage == b.rejectMessage)
    end
    local function Update(state)
        local target = state.dropTarget
        if not moving then
            moving, movingSlots, movingCount = {}, {}, 0
            local source = state.slotData
            if source.buttonData then
                for _, entry in ipairs(ST.GetAttachedBarDragEntries(group, source.buttonData)) do
                    moving[entry], movingCount = true, movingCount + 1
                end
            else
                for _, slot in ipairs(source.module.slots) do movingSlots[slot] = true end
            end
        end
        if not lastBounds or not SameTarget(lastTarget, target) then
            local entryPositions, modulePositions = Drag.Layout(preview, group, moduleList, state.slotData, target)
            lastBounds = Drag.Paint(preview, group, entryPositions, modulePositions, moving, movingSlots)
            lastTarget = target
            if lastBounds then
                -- The shared cursor ghost lifts the source; the shared gap
                -- below marks its landing while neighbours move aside.
                PP.ConfigurePreviewGhost(preview, {
                    scale = preview.content:GetEffectiveScale() / UIParent:GetEffectiveScale(),
                    slotW = lastBounds.width, slotH = lastBounds.height,
                    exactFootprint = true, hideGhostIcon = true,
                }, state.slotData.buttonData)
            end
        end
        if not target or not lastBounds then
            if preview.gapFrame then preview.gapFrame:Hide() end
            return
        end
        local rect = target.rejectMessage and target.rect or lastBounds
        local module = state.slotData and state.slotData.module
        local label = target.rejectMessage
        if not label and module and module.kind == "cast" then label = "Cast Bar / last in this stack" end
        if movingCount > 1 and not label then label = "Move " .. movingCount .. " aura bars together" end
        PP.ShowPreviewGap(preview, "TOPLEFT", rect.x, rect.y, rect.width, rect.height,
            target.rejectMessage and "reject" or nil, label)
    end
    model.onActivate = function(state) GameTooltip:Hide(); Update(state) end
    model.onUpdate = function(state) Update(state) end
    model.onCancel = function()
        if moving then Drag.Paint(preview, group, positions, modules, {}, {}) end
        moving, movingSlots, movingCount, lastTarget, lastBounds = nil, nil, nil, nil, nil
        PP.ClearPreviewGhost(preview)
        PP.StartPreviewTicker(preview)
    end
    model.applyDrop = function(state)
        local target, source = state.dropTarget, state.slotData
        if not target or Addon.db.profile.groups[panelId] ~= group then return end
        if target.rejectMessage then Addon:Print(target.rejectMessage); return end
        -- Restore replicas while the original entry indices still name them.
        -- RefreshConfigPanel cancels the outer gesture again after the write.
        model.onCancel()
        ST._FlushPresentationEditors()
        if source.buttonData then
            local selected = CS.selectedGroup == panelId and group.buttons[CS.selectedButton or 0]
            if Addon:MoveAttachedBarEntries(panelId, source.buttonData, target) then
                wipe(CS.selectedButtons)
                if selected then
                    for i, entry in ipairs(group.buttons) do
                        if entry == selected then CS.selectedButton = i; break end
                    end
                end
            end
        elseif source.module then
            local block, region = source.module, target.region == "main" and "main" or "panel"
            local lane = target.side .. (target.region == "main" and (target.side == "above" or target.side == "below") and "Main" or "")
            if block.kind == "cast" then
                block.slots[1].setPos(lane)
            else
                block.layout.resourceBlocks = block.layout.resourceBlocks or {}
                block.layout.resourceBlocks[target.side] = { anchorRegion = region }
                local appendOrder
                if block.side ~= target.side then
                    for _, position in ipairs(modules) do
                        local other = position.module
                        if other ~= block and other.kind == "resources" and other.side == target.side then
                            for _, slot in ipairs(other.slots) do
                                appendOrder = math.max(appendOrder or 0, slot.getOrder())
                            end
                        end
                    end
                end
                for i, slot in ipairs(block.slots) do
                    slot.setPos(lane)
                    if appendOrder then slot.setOrder(appendOrder + i) end
                end
                for entry, placement in pairs(Drag.ResourcePlacements(group, target)) do
                    entry.barPlacement = placement
                end
            end
            Addon:ApplyResourceBars()
            ST.RefreshPanelAttachments(panelId)
            Addon:RequestAuraRebind("config", panelId)
        end
        Addon:RefreshConfigPanel()
    end
    return model
end

function ST._WirePanelAttachmentModule(frame, module, slot, drag)
    frame:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" or CS.copyCustomization or not drag or GetCursorInfo() then return end
        local x, y = GetCursorPosition()
        CS.dragState = { kind = "layout-slot", phase = "pending", previewSlot = self,
            scrollWidget = UIParent, startX = x, startY = y, layoutDrag = drag, slotData = { module = module } }
        ST._StartDragTracking()
    end)
    frame:SetScript("OnMouseUp", function(self, button)
        if button == "RightButton" then
            ST._ShowModuleThicknessMenu(slot)
            return
        end
        if button ~= "LeftButton" or ST._ConsumeDragEscapeMouseUp() then return end
        local state = CS.dragState
        if state then
            if state.phase ~= "pending" or state.previewSlot ~= self then return end
            ST._CancelDrag()
        end
        if ST._SelectPanelAttachmentModule(slot, false) then
            Addon:RefreshConfigPanel()
        end
    end)
    frame:SetScript("OnEnter", function(self)
        if CS.dragState and CS.dragState.phase == "active" then return end
        if self.hoverHighlight then self.hoverHighlight:Show() end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(slot.label)
        local context = ST._CreateModuleSettingsContext(slot.kind == "resource" and "resources" or "castbar", slot.powerType)
        if context and context.entry.overrideSections and context.entry.overrideSections.barThickness then
            GameTooltip:AddLine("Customized: Bar Thickness", 1, 0.82, 0)
        end
        if CS.copyCustomization then
            local compatible = context and ST._ButtonPanelPreview.CopyMode.IsEligibleTarget(CS.copyCustomization, context.group, context.entry)
            GameTooltip:AddLine(compatible and "Click to apply compatible thickness customization."
                or "This bar supports Bar Thickness customization only.", 1, 1, 1, true)
        end
        GameTooltip:AddLine(module.kind == "cast" and "Drag to another side. The cast bar stays last."
            or "Drag to move this Resources block. Resource ordering stays inside the block.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        if self.hoverHighlight then self.hoverHighlight:Hide() end
        GameTooltip:Hide()
    end)
end
