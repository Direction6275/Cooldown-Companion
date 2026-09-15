-- Attached entries and module blocks share the normal preview drag lifecycle.
local _, ST = ...
local Addon, CS = ST.Addon, ST._configState
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

local function SideLabel(side, region, resources)
    local name = side:sub(1,1):upper() .. side:sub(2)
    return name .. (region == "main" and " main area" or " entire icon region")
        .. (resources == "before" and " / before Resources" or " / after Resources")
end

function ST._CreatePanelAttachmentDrag(preview, panelId, positions, modules, outer)
    local group = Addon.db.profile.groups[panelId]
    if not ST.PanelSupportsAttachedBars(group) then return end
    local model = { panelPreview = true, panelId = panelId, preview = preview, positions = positions }
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
    local indicator = preview.attachmentDropIndicator
    if not indicator then
        indicator = CreateFrame("Frame", nil, preview.content)
        indicator:SetFrameLevel(preview.content:GetFrameLevel() + 30)
        indicator.fill = indicator:CreateTexture(nil, "OVERLAY")
        indicator.fill:SetAllPoints()
        indicator.fill:SetColorTexture(0.25, 0.65, 1, 0.35)
        indicator.label = indicator:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        indicator.label:SetPoint("BOTTOM", indicator, "TOP", 0, 3)
        preview.attachmentDropIndicator = indicator
    end
    indicator:Hide()
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
        for index, position in pairs(positions) do
            if Contains(position, x, y, 2 / scale) then
                local entry = group.buttons[index]
                local side, region, resources = ST.GetAttachedBarPlacement(entry)
                if Supported(side) then
                    local after = (side == "below" and y >= -position.y + position.height / 2)
                        or (side == "above" and y < -position.y + position.height / 2)
                        or (side == "right" and x >= position.x + position.width / 2)
                        or (side == "left" and x < position.x + position.width / 2)
                    return { side = side, region = region, resources = resources, index = index, after = after,
                        rect = position, rejectMessage = source and source.buttonData
                            and ST.GetAttachedBarDropRejection(group, source.buttonData, entry, after) }
                end
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
                rect = { x = closest.x - 18, y = -closest.y + 5, width = 36, height = 10 } }
        end
    end
    local function Update(state)
        local target = state.dropTarget
        if not target then indicator:Hide(); return end
        local rect = target.rect
        indicator:ClearAllPoints()
        indicator:SetPoint("TOPLEFT", preview.content, "TOPLEFT", rect.x, rect.y)
        indicator:SetSize(rect.width, rect.height)
        local module = state.slotData and state.slotData.module
        local label = target.rejectMessage or SideLabel(target.side, target.region, target.resources)
        if module and module.kind == "cast" then label = "Cast Bar / last in this stack" end
        if not module and state.slotData.buttonData then
            local count = #ST.GetAttachedBarDragEntries(group, state.slotData.buttonData)
            if count > 1 then label = label .. " / move " .. count .. " aura bars together" end
        end
        indicator.label:SetText(label)
        indicator.fill:SetColorTexture(target.rejectMessage and 1 or 0.25, target.rejectMessage and 0.2 or 0.65, 1, 0.35)
        indicator:Show()
    end
    model.onActivate = function(state) GameTooltip:Hide(); Update(state) end
    model.onUpdate = function(state) Update(state) end
    model.onCancel = function() indicator:Hide() end
    model.applyDrop = function(state)
        local target, source = state.dropTarget, state.slotData
        if not target or Addon.db.profile.groups[panelId] ~= group then return end
        if target.rejectMessage then Addon:Print(target.rejectMessage); return end
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
                -- Put the boundary before/after the chosen complete aura unit.
                local destination = target.index and group.buttons[target.index]
                local unit = destination and ST.GetAttachedBarDragEntries(group, destination) or {}
                local boundary, unitSet = nil, {}
                for _, entry in ipairs(unit) do unitSet[entry] = true end
                if destination then
                    local ordered = {}
                    local targetRegion = ST.ResolvePanelAttachmentRegion(group, target.side, target.region)
                    for _, area in ipairs(ST.BuildAttachedBarAreas(group)) do
                        if area.side == target.side and area.region == targetRegion then
                            for _, item in ipairs(ST.GetAttachedBarAreaOrder(group, area.entries)) do
                                ordered[#ordered + 1] = item.entry
                            end
                        end
                    end
                    for i, entry in ipairs(ordered) do
                        if unitSet[entry] then
                            if not boundary then boundary = i
                            elseif target.after then boundary = math.max(boundary, i)
                            else boundary = math.min(boundary, i) end
                        end
                    end
                    for i, entry in ipairs(ordered) do
                        local side, entryRegion = ST.GetAttachedBarPlacement(entry)
                        if boundary then
                            entry.barPlacement = { side = side, region = entryRegion,
                                resources = (i < boundary or (i == boundary and target.after)) and "before" or "after" }
                        end
                    end
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
        if button ~= "LeftButton" or not drag or GetCursorInfo() then return end
        local x, y = GetCursorPosition()
        CS.dragState = { kind = "layout-slot", phase = "pending", previewSlot = self,
            scrollWidget = UIParent, startX = x, startY = y, layoutDrag = drag, slotData = { module = module } }
        ST._StartDragTracking()
    end)
    frame:SetScript("OnMouseUp", function(self, button)
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
        if self.hoverHighlight then self.hoverHighlight:Show() end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(slot.label)
        GameTooltip:AddLine(module.kind == "cast" and "Drag to another side. The cast bar stays last."
            or "Drag to move this Resources block. Resource ordering stays inside the block.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function(self)
        if self.hoverHighlight then self.hoverHighlight:Hide() end
        GameTooltip:Hide()
    end)
end
