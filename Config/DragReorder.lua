--[[
    CooldownCompanion - Config/DragReorder
    Full drag-and-drop reordering system for groups and buttons.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local ShowPopupAboveConfig = ST._ShowPopupAboveConfig
local GroupsHaveForeignSpecs = ST._GroupsHaveForeignSpecs
local FolderHasForeignSpecs = ST._FolderHasForeignSpecs
local EnsureCol2PreviewHost = ST._EnsureCol2PreviewHost
local ClearCol2PreviewHost = ST._ClearCol2PreviewHost

-- File-local constants
local DRAG_THRESHOLD = 8
local PREVIEW_ANIM_DURATION = 0.08
local PREVIEW_PANEL_INSET = 8
local PREVIEW_ROW_TEXT_RIGHT_PAD = 8
local PREVIEW_DEFAULT_ROW_HEIGHT = 32

------------------------------------------------------------------------
-- Drag indicator helpers
------------------------------------------------------------------------
local function GetDragIndicator()
    if not CS.dragIndicator then
        CS.dragIndicator = CreateFrame("Frame", nil, UIParent)
        CS.dragIndicator:SetFrameStrata("TOOLTIP")
        CS.dragIndicator:SetSize(10, 2)
        local tex = CS.dragIndicator:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetColorTexture(0.2, 0.6, 1.0, 1.0)
        CS.dragIndicator.tex = tex
        CS.dragIndicator:Hide()
    end
    return CS.dragIndicator
end

local function HideDragIndicator()
    if CS.dragIndicator then CS.dragIndicator:Hide() end
end

local function GetScaledCursorPosition(scrollWidget)
    local _, cursorY = GetCursorPosition()
    local scale = scrollWidget.frame:GetEffectiveScale()
    cursorY = cursorY / scale
    return cursorY
end

local function GetDropIndex(scrollWidget, cursorY, childOffset, totalDraggable)
    -- childOffset: number of non-draggable children at the start of the scroll (e.g. input box, buttons, separator)
    -- Iterate draggable children and compare cursor Y to midpoints
    local children = { scrollWidget.content:GetChildren() }
    local dropIndex = totalDraggable + 1  -- default: after last
    local anchorFrame = nil
    local anchorAbove = true

    for ci = 1, totalDraggable do
        local child = children[ci + childOffset]
        if child and child:IsShown() then
            local top = child:GetTop()
            local bottom = child:GetBottom()
            if top and bottom then
                local mid = (top + bottom) / 2
                if cursorY > mid then
                    dropIndex = ci
                    anchorFrame = child
                    anchorAbove = true
                    break
                end
                -- Track the last child we passed as potential "below" anchor
                anchorFrame = child
                anchorAbove = false
                dropIndex = ci + 1
            end
        end
    end

    return dropIndex, anchorFrame, anchorAbove
end

------------------------------------------------------------------------
-- Column 2 cross-panel drop target detection
------------------------------------------------------------------------
local function FindPreviousPanelId(renderedRows, currentIndex)
    for i = currentIndex - 1, 1, -1 do
        if renderedRows[i].kind == "header" then
            return renderedRows[i].panelId
        end
    end
    return nil
end

local function GetCol2DropTarget(cursorY, renderedRows)
    if not renderedRows or #renderedRows == 0 then return nil end

    for i, rowMeta in ipairs(renderedRows) do
        local frame = rowMeta.widget and rowMeta.widget.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom and cursorY <= top and cursorY >= bottom then
                local mid = (top + bottom) / 2

                if rowMeta.kind == "button" then
                    if cursorY > mid then
                        return {
                            action = "insert",
                            targetPanelId = rowMeta.panelId,
                            targetIndex = rowMeta.buttonIndex,
                            anchorFrame = frame,
                            anchorAbove = true,
                        }
                    else
                        return {
                            action = "insert",
                            targetPanelId = rowMeta.panelId,
                            targetIndex = rowMeta.buttonIndex + 1,
                            anchorFrame = frame,
                            anchorAbove = false,
                        }
                    end
                elseif rowMeta.kind == "header" then
                    if rowMeta.isCollapsed then
                        -- Drop onto collapsed header = append to that panel
                        return {
                            action = "append-to-collapsed",
                            targetPanelId = rowMeta.panelId,
                            targetIndex = nil, -- will resolve to #buttons+1
                            anchorFrame = frame,
                            anchorAbove = false,
                        }
                    else
                        return {
                            action = "insert",
                            targetPanelId = rowMeta.panelId,
                            targetIndex = 1,
                            anchorFrame = frame,
                            anchorAbove = true,
                        }
                    end
                end
            end
        end
    end

    -- Cursor is in a vertical gap between visible rows/panels.
    for i = 1, #renderedRows - 1 do
        local prevMeta = renderedRows[i]
        local nextMeta = renderedRows[i + 1]
        local prevFrame = prevMeta.widget and prevMeta.widget.frame
        local nextFrame = nextMeta.widget and nextMeta.widget.frame
        if prevFrame and nextFrame and prevFrame:IsShown() and nextFrame:IsShown() then
            local prevBottom = prevFrame:GetBottom()
            local nextTop = nextFrame:GetTop()
            if prevBottom and nextTop and cursorY <= prevBottom and cursorY >= nextTop then
                local gapMid = (prevBottom + nextTop) / 2
                if nextMeta.kind == "header" and prevMeta.panelId ~= nextMeta.panelId then
                    if cursorY > gapMid then
                        return {
                            action = "append",
                            targetPanelId = prevMeta.panelId,
                            targetIndex = nil,
                            anchorFrame = prevFrame,
                            anchorAbove = false,
                        }
                    end

                    if nextMeta.isCollapsed then
                        return {
                            action = "append-to-collapsed",
                            targetPanelId = nextMeta.panelId,
                            targetIndex = nil,
                            anchorFrame = nextFrame,
                            anchorAbove = true,
                        }
                    end

                    return {
                        action = "insert",
                        targetPanelId = nextMeta.panelId,
                        targetIndex = 1,
                        anchorFrame = nextFrame,
                        anchorAbove = true,
                    }
                end

                if nextMeta.kind == "button" then
                    return {
                        action = "insert",
                        targetPanelId = nextMeta.panelId,
                        targetIndex = nextMeta.buttonIndex,
                        anchorFrame = nextFrame,
                        anchorAbove = true,
                    }
                elseif nextMeta.kind == "header" then
                    return {
                        action = nextMeta.isCollapsed and "append-to-collapsed" or "insert",
                        targetPanelId = nextMeta.panelId,
                        targetIndex = nextMeta.isCollapsed and nil or 1,
                        anchorFrame = nextFrame,
                        anchorAbove = true,
                    }
                end
            end
        end
    end

    -- Below all rows: append to last panel
    local lastRow = renderedRows[#renderedRows]
    if lastRow then
        local panelId = lastRow.panelId
        local lastFrame = lastRow.widget and lastRow.widget.frame
        if lastFrame and lastFrame:IsShown() then
            return {
                action = "append",
                targetPanelId = panelId,
                targetIndex = nil,
                anchorFrame = lastFrame,
                anchorAbove = false,
            }
        end
    end
    return nil
end

local function ShowDragIndicator(anchorFrame, anchorAbove, parentScrollWidget)
    if not anchorFrame then
        HideDragIndicator()
        return
    end
    local ind = GetDragIndicator()
    local width = parentScrollWidget.content:GetWidth() or 100
    ind:SetWidth(width)
    ind:ClearAllPoints()
    if anchorAbove then
        ind:SetPoint("BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 1)
    else
        ind:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", 0, -1)
    end
    ind:Show()
end

------------------------------------------------------------------------
-- Column 2 animated preview helpers
------------------------------------------------------------------------
local PREVIEW_MODE_ROW_DRAG = "row_drag"
local PREVIEW_MODE_PANEL_COMPACT = "panel_drag_compact"
local PREVIEW_COMPACT_GAP = 8

local function Clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function Interpolate(a, b, t)
    return a + (b - a) * t
end

local function EaseInOut(t)
    return t * t * (3 - 2 * t)
end

local function GetRelativeRect(frame, parent)
    if not (frame and parent and frame:IsShown() and parent:IsShown()) then
        return nil
    end
    local left, top = frame:GetLeft(), frame:GetTop()
    local parentLeft, parentTop = parent:GetLeft(), parent:GetTop()
    local width, height = frame:GetWidth(), frame:GetHeight()
    if not (left and top and parentLeft and parentTop and width and height) then
        return nil
    end
    return left - parentLeft, parentTop - top, width, height
end

local function CopyPreviewRow(row)
    return {
        key = row.key,
        buttonIndex = row.buttonIndex,
        x = row.x,
        y = row.y,
        width = row.width,
        height = row.height,
        text = row.text,
        icon = row.icon,
        usable = row.usable,
        textColor = row.textColor,
        imageSize = row.imageSize,
        isGap = row.isGap,
    }
end

local function CopyPreviewPanel(panel)
    local copy = {
        originalIndex = panel.originalIndex,
        panelId = panel.panelId,
        name = panel.name,
        x = panel.x,
        y = panel.y,
        width = panel.width,
        height = panel.height,
        extraHeight = panel.extraHeight,
        firstRowOffset = panel.firstRowOffset,
        rowGap = panel.rowGap,
        defaultRowHeight = panel.defaultRowHeight,
        gapAfter = panel.gapAfter,
        isCollapsed = panel.isCollapsed,
        displayMode = panel.displayMode,
        enabled = panel.enabled,
        locked = panel.locked,
        count = panel.count,
        headerColor = panel.headerColor,
        backdropColor = panel.backdropColor,
        borderColor = panel.borderColor,
        compactHeight = panel.compactHeight,
        header = {
            x = panel.header.x,
            y = panel.header.y,
            width = panel.header.width,
            height = panel.header.height,
        },
        rows = {},
    }
    for i, row in ipairs(panel.rows) do
        copy.rows[i] = CopyPreviewRow(row)
    end
    return copy
end

local function BuildCol2BasePreviewLayout()
    local panelMetas = CS.lastCol2PanelMetas
    local content = CS.col2Scroll and CS.col2Scroll.content
    if not (panelMetas and content and content:IsShown()) then
        return nil
    end

    local panels = {}
    local byId = {}

    for _, meta in ipairs(panelMetas) do
        local x, y, width, height = GetRelativeRect(meta.panelFrame, content)
        if x and y then
            local panel = {
                originalIndex = #panels + 1,
                panelId = meta.panelId,
                name = (meta.group and meta.group.name) or ("Panel " .. meta.panelId),
                x = x,
                y = y,
                width = width,
                height = height,
                isCollapsed = meta.isCollapsed and true or false,
                displayMode = meta.displayMode or "icons",
                enabled = not (meta.group and meta.group.enabled == false),
                locked = meta.group and meta.group.locked == false,
                count = meta.count or #meta.buttonRows,
                headerColor = meta.headerColor,
                backdropColor = meta.backdropColor,
                borderColor = meta.borderColor,
                rows = {},
            }

            local hx, hy, hw, hh = GetRelativeRect(meta.headerFrame, meta.panelFrame)
            panel.header = {
                x = hx or PREVIEW_PANEL_INSET,
                y = hy or 6,
                width = hw or math.max(40, width - (PREVIEW_PANEL_INSET * 2)),
                height = hh or 32,
            }

            local totalRowHeight = 0
            local totalRowGap = 0
            local previousRow
            for _, rowMeta in ipairs(meta.buttonRows) do
                local rx, ry, rw, rh = GetRelativeRect(rowMeta.frame, meta.panelFrame)
                local row = {
                    key = tostring(meta.panelId) .. ":" .. tostring(rowMeta.buttonIndex),
                    buttonIndex = rowMeta.buttonIndex,
                    x = rx or PREVIEW_PANEL_INSET,
                    y = ry or ((panel.header.y + panel.header.height) + 4),
                    width = rw or math.max(40, width - (PREVIEW_PANEL_INSET * 2)),
                    height = rh or PREVIEW_DEFAULT_ROW_HEIGHT,
                    text = rowMeta.text,
                    icon = rowMeta.icon,
                    usable = rowMeta.usable,
                    textColor = rowMeta.textColor,
                    imageSize = rowMeta.imageSize,
                }
                totalRowHeight = totalRowHeight + row.height
                if previousRow then
                    totalRowGap = totalRowGap + math.max(0, row.y - (previousRow.y + previousRow.height))
                end
                previousRow = row
                table.insert(panel.rows, row)
            end

            local rowCount = #panel.rows
            panel.rowGap = rowCount > 1 and math.floor((totalRowGap / (rowCount - 1)) + 0.5) or 2
            panel.firstRowOffset = panel.rows[1] and panel.rows[1].y or (panel.header.y + panel.header.height + 4)
            panel.defaultRowHeight = panel.rows[1] and panel.rows[1].height or PREVIEW_DEFAULT_ROW_HEIGHT
            panel.compactHeight = math.max(panel.header.height + 4, 28)
            panel.extraHeight = math.max(
                panel.header.y + panel.header.height + 4,
                height - totalRowHeight - math.max(0, rowCount - 1) * panel.rowGap
            )

            panels[#panels + 1] = panel
            byId[panel.panelId] = panel
        end
    end

    for i, panel in ipairs(panels) do
        local nextPanel = panels[i + 1]
        if nextPanel then
            panel.gapAfter = math.max(0, nextPanel.y - (panel.y + panel.height))
        else
            panel.gapAfter = 0
        end
    end

    return {
        panels = panels,
        byId = byId,
        startOffset = panels[1] and panels[1].y or 0,
    }
end

local function BuildPreviewSlotOffsets(panel, rowCount)
    local offsets = {}
    for i = 1, rowCount do
        if i == 1 then
            offsets[i] = panel.firstRowOffset
        else
            local prevRow = panel.rows[i - 1]
            local prevHeight = (prevRow and prevRow.height) or panel.defaultRowHeight
            offsets[i] = offsets[i - 1] + prevHeight + panel.rowGap
        end
    end
    return offsets
end

local function AcquirePreviewPanelFrame(preview, index)
    local panelProxy = preview.panels[index]
    if panelProxy then
        panelProxy.used = true
        return panelProxy
    end

    local frame = CreateFrame("Frame", nil, preview.root, "BackdropTemplate")
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0.58)
    frame:SetClipsChildren(true)
    frame:Hide()

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetJustifyH("CENTER")
    title:SetWordWrap(false)
    frame._cdcTitle = title

    local modeBadge = frame:CreateTexture(nil, "ARTWORK")
    modeBadge:SetSize(16, 16)
    frame._cdcModeBadge = modeBadge

    panelProxy = {
        frame = frame,
        rows = {},
        used = true,
    }
    preview.panels[index] = panelProxy
    return panelProxy
end

local function AcquirePreviewRowFrame(panelProxy, index)
    panelProxy.rowByKey = panelProxy.rowByKey or {}
    local rowProxy = panelProxy.rowByKey[index]
    if rowProxy then
        rowProxy.used = true
        return rowProxy
    end

    local frame = CreateFrame("Frame", nil, panelProxy.frame)
    frame:Hide()

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("LEFT", frame, "LEFT", 0, 0)
    frame._cdcIcon = icon

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    label:SetPoint("RIGHT", frame, "RIGHT", -PREVIEW_ROW_TEXT_RIGHT_PAD, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    frame._cdcLabel = label

    rowProxy = {
        frame = frame,
        used = true,
    }
    panelProxy.rowByKey[index] = rowProxy
    table.insert(panelProxy.rows, rowProxy)
    return rowProxy
end

local function ApplyPreviewFrameGeometry(frame, x, y, width, height, alpha)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", frame:GetParent(), "TOPLEFT", x, -y)
    frame:SetSize(width, height)
    frame:SetAlpha(alpha or 1)
    frame._cdcDisplayX = x
    frame._cdcDisplayY = y
    frame._cdcDisplayW = width
    frame._cdcDisplayH = height
    frame._cdcDisplayA = alpha or 1
end

local function QueuePreviewTween(preview, frame, x, y, width, height, alpha, duration)
    local currentX = frame._cdcDisplayX
    local currentY = frame._cdcDisplayY
    local currentW = frame._cdcDisplayW
    local currentH = frame._cdcDisplayH
    local currentA = frame._cdcDisplayA

    if not currentX then
        ApplyPreviewFrameGeometry(frame, x, y, width, height, alpha)
        return
    end

    if math.abs(currentX - x) < 0.5
        and math.abs(currentY - y) < 0.5
        and math.abs(currentW - width) < 0.5
        and math.abs(currentH - height) < 0.5
        and math.abs((currentA or 1) - (alpha or 1)) < 0.02 then
        ApplyPreviewFrameGeometry(frame, x, y, width, height, alpha)
        preview.tweens[frame] = nil
        return
    end

    preview.tweens[frame] = {
        sx = currentX,
        sy = currentY,
        sw = currentW,
        sh = currentH,
        sa = currentA or 1,
        tx = x,
        ty = y,
        tw = width,
        th = height,
        ta = alpha or 1,
        t0 = GetTime(),
        dur = duration or PREVIEW_ANIM_DURATION,
    }
end

local function UpdatePreviewGhost(preview)
    if not (preview and preview.ghost and preview.ghost:IsShown()) then
        return
    end
    local scale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale
    preview.ghost:ClearAllPoints()
    preview.ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX + 14, cursorY - 14)
end

local function TickCol2Preview(preview)
    local activeTween = false
    local now = GetTime()

    for frame, tween in pairs(preview.tweens) do
        local progress = Clamp((now - tween.t0) / tween.dur, 0, 1)
        local eased = EaseInOut(progress)
        ApplyPreviewFrameGeometry(
            frame,
            Interpolate(tween.sx, tween.tx, eased),
            Interpolate(tween.sy, tween.ty, eased),
            Interpolate(tween.sw, tween.tw, eased),
            Interpolate(tween.sh, tween.th, eased),
            Interpolate(tween.sa, tween.ta, eased)
        )
        if progress >= 1 then
            preview.tweens[frame] = nil
        else
            activeTween = true
        end
    end

    UpdatePreviewGhost(preview)

    if not activeTween and not preview.ghostActive then
        preview.root:SetScript("OnUpdate", nil)
    end
end

local function SetCol2BaseFramesHidden(hidden)
    local preview = hidden and EnsureCol2PreviewHost() or CS.col2Preview
    local content = CS.col2Scroll and CS.col2Scroll.content
    if not (preview and content) then
        return
    end

    if hidden then
        for _, frame in ipairs({ content:GetChildren() }) do
            if frame ~= preview.root and preview.hiddenFrames[frame] == nil then
                preview.hiddenFrames[frame] = frame:GetAlpha()
                frame:SetAlpha(0)
            end
        end
    else
        for frame, alpha in pairs(preview.hiddenFrames) do
            if frame and frame.SetAlpha then
                frame:SetAlpha(alpha)
            end
            preview.hiddenFrames[frame] = nil
        end
    end
end

local function BuildGapRow(template, key)
    return {
        key = key or "preview-gap",
        buttonIndex = 0,
        x = (template and template.x) or PREVIEW_PANEL_INSET,
        y = 0,
        width = (template and template.width) or 0,
        height = (template and template.height) or PREVIEW_DEFAULT_ROW_HEIGHT,
        usable = true,
        isGap = true,
    }
end

local function ApplyRowPreviewGeometry(base, panels)
    local currentY = base.startOffset
    for _, panel in ipairs(panels) do
        local rowCount = #panel.rows
        local rowGaps = math.max(0, rowCount - 1) * panel.rowGap
        local totalRowHeight = 0
        for _, row in ipairs(panel.rows) do
            totalRowHeight = totalRowHeight + (row.height or panel.defaultRowHeight)
        end

        panel.previewHeight = panel.isCollapsed and panel.height or (panel.extraHeight + totalRowHeight + rowGaps)
        panel.previewY = currentY

        local slotOffsets = BuildPreviewSlotOffsets(panel, rowCount)
        for i, row in ipairs(panel.rows) do
            row.previewY = slotOffsets[i]
        end

        currentY = currentY + panel.previewHeight + (panel.gapAfter or 0)
    end
end

local function BuildCol2PreviewModel(source)
    local base = BuildCol2BasePreviewLayout()
    if not base then
        return nil
    end

    local panels = {}
    local byId = {}
    for i, panel in ipairs(base.panels) do
        panels[i] = CopyPreviewPanel(panel)
        byId[panels[i].panelId] = panels[i]
    end

    if source and source.kind == "panel" then
        local sourceIndex
        for i, panel in ipairs(panels) do
            if panel.panelId == source.sourcePanelId then
                sourceIndex = i
                break
            end
        end
        if not sourceIndex then
            return nil
        end

        local moved = table.remove(panels, sourceIndex)
        local insertIndex = source.dropTarget and source.dropTarget.targetIndex or sourceIndex
        if insertIndex > sourceIndex then
            insertIndex = insertIndex - 1
        end
        insertIndex = Clamp(insertIndex, 1, #panels + 1)
        table.insert(panels, insertIndex, {
            isGap = true,
            previewHeight = moved.compactHeight,
        })

        local currentY = base.startOffset
        for _, panel in ipairs(panels) do
            panel.previewHeight = panel.previewHeight or panel.compactHeight
            panel.previewY = currentY
            currentY = currentY + panel.previewHeight + PREVIEW_COMPACT_GAP
        end

        return {
            mode = PREVIEW_MODE_PANEL_COMPACT,
            panels = panels,
            draggedPanel = moved,
        }
    elseif source and source.kind == "button" then
        local sourcePanel = byId[source.groupId]
        local movedRow = sourcePanel and table.remove(sourcePanel.rows, source.sourceIndex)
        if sourcePanel then
            sourcePanel.count = #sourcePanel.rows
        end

        local targetPanel = sourcePanel
        local insertIndex = source.sourceIndex
        if source.dropTarget and source.dropTarget.targetPanelId then
            targetPanel = byId[source.dropTarget.targetPanelId] or sourcePanel
            insertIndex = source.dropTarget.targetIndex or (#targetPanel.rows + 1)
            if targetPanel.panelId == sourcePanel.panelId and insertIndex > source.sourceIndex then
                insertIndex = insertIndex - 1
            end
        end

        if movedRow then
            if targetPanel and targetPanel.isCollapsed then
                targetPanel.count = (targetPanel.count or #targetPanel.rows) + 1
            elseif targetPanel then
                insertIndex = Clamp(insertIndex, 1, #targetPanel.rows + 1)
                table.insert(targetPanel.rows, insertIndex, BuildGapRow(movedRow, "gap:" .. tostring(movedRow.key or source.sourceIndex)))
                if targetPanel.panelId ~= sourcePanel.panelId then
                    targetPanel.count = #targetPanel.rows
                else
                    targetPanel.count = #targetPanel.rows
                end
            end
        end

        ApplyRowPreviewGeometry(base, panels)
        return {
            mode = PREVIEW_MODE_ROW_DRAG,
            panels = panels,
            draggedRow = movedRow,
        }
    elseif source and source.kind == "cursor" then
        local targetPanel = byId[source.targetPanelId]
        if targetPanel then
            targetPanel.count = (targetPanel.count or #targetPanel.rows) + 1
            if not targetPanel.isCollapsed then
                local templateRow = targetPanel.rows[1]
                if not templateRow then
                    templateRow = {
                        x = PREVIEW_PANEL_INSET,
                        width = math.max(60, targetPanel.width - (PREVIEW_PANEL_INSET * 2)),
                        height = PREVIEW_DEFAULT_ROW_HEIGHT,
                    }
                end
                table.insert(targetPanel.rows, #targetPanel.rows + 1, BuildGapRow(templateRow, "cursor-gap"))
            end
        end

        ApplyRowPreviewGeometry(base, panels)
        return {
            mode = PREVIEW_MODE_ROW_DRAG,
            panels = panels,
        }
    end

    ApplyRowPreviewGeometry(base, panels)
    return {
        mode = PREVIEW_MODE_ROW_DRAG,
        panels = panels,
    }
end

local function UpdateCol2Ghost(preview, source, model)
    if not (preview and preview.ghost) then
        return
    end

    preview.ghostActive = false
    preview.ghost:SetAlpha(0.95)
    preview.ghost.icon:ClearAllPoints()
    preview.ghost.label:ClearAllPoints()
    if not source or source.kind == "cursor" then
        preview.ghost:Hide()
        return
    end

    if source.kind == "panel" then
        local panel = model and model.draggedPanel
        if panel then
            local bg = panel.backdropColor
            local border = panel.borderColor
            if bg then
                preview.ghost:SetBackdropColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 0.2)
            else
                preview.ghost:SetBackdropColor(0, 0, 0, 0.22)
            end
            if border then
                preview.ghost:SetBackdropBorderColor(border[1] or 0, border[2] or 0, border[3] or 0, border[4] or 0.58)
            else
                preview.ghost:SetBackdropBorderColor(0, 0, 0, 0.58)
            end
            preview.ghost:SetSize(panel.width, panel.compactHeight or panel.header.height)
            preview.ghost.label:SetText(panel.name .. " |cff666666(" .. tostring(panel.count or 0) .. ")|r")
            preview.ghost.icon:SetSize(16, 16)
            preview.ghost.icon:SetPoint("LEFT", preview.ghost, "LEFT", 10, 0)
            preview.ghost.label:SetPoint("LEFT", preview.ghost.icon, "RIGHT", 8, 0)
            preview.ghost.label:SetPoint("RIGHT", preview.ghost, "RIGHT", -10, 0)
            if panel.displayMode == "bars" then
                preview.ghost.icon:SetAtlas("CreditsScreen-Assets-Buttons-Pause", false)
            elseif panel.displayMode == "text" then
                preview.ghost.icon:SetAtlas("poi-workorders", false)
            else
                preview.ghost.icon:SetAtlas("UI-QuestPoi-QuestNumber-SuperTracked", false)
            end
            preview.ghost.icon:Show()
            preview.ghost:Show()
            preview.ghostActive = true
        end
    elseif source.kind == "button" then
        local row = model and model.draggedRow
        if row then
            preview.ghost:SetBackdropColor(0, 0, 0, 0)
            preview.ghost:SetBackdropBorderColor(0, 0, 0, 0)
            preview.ghost:SetSize(row.width, row.height)
            preview.ghost.label:SetText(row.text or "")
            preview.ghost.icon:SetPoint("LEFT", preview.ghost, "LEFT", 0, 0)
            preview.ghost.label:SetPoint("LEFT", preview.ghost.icon, "RIGHT", 8, 0)
            preview.ghost.label:SetPoint("RIGHT", preview.ghost, "RIGHT", -8, 0)
            if row.icon then
                preview.ghost.icon:SetSize(row.imageSize or 32, row.imageSize or 32)
                preview.ghost.icon:SetTexture(row.icon)
                preview.ghost.icon:Show()
            else
                preview.ghost.icon:Hide()
            end
            if row.textColor then
                preview.ghost.label:SetTextColor(row.textColor[1] or 1, row.textColor[2] or 1, row.textColor[3] or 1)
            else
                preview.ghost.label:SetTextColor(1, 1, 1)
            end
            preview.ghost:Show()
            preview.ghostActive = true
        else
            preview.ghost:Hide()
        end
    else
        preview.ghost:Hide()
    end

    if not preview.ghostActive then
        preview.ghost:Hide()
    end
end

local ClearCol2AnimatedPreview

local function RenderCol2AnimatedPreview(source)
    local model = BuildCol2PreviewModel(source)
    if not model or not model.panels or #model.panels == 0 then
        ClearCol2AnimatedPreview()
        return
    end

    local preview = EnsureCol2PreviewHost()
    if not preview then
        return
    end

    preview.mode = model.mode
    preview.compactEntries = nil
    SetCol2BaseFramesHidden(true)
    preview.root:Show()

    for _, panelProxy in ipairs(preview.panels) do
        panelProxy.used = false
        for _, rowProxy in ipairs(panelProxy.rows) do
            rowProxy.used = false
        end
    end

    local visibleCompactIndex = 0
    for panelIndex, panel in ipairs(model.panels) do
        if model.mode == PREVIEW_MODE_PANEL_COMPACT and panel.isGap then
            -- keep the reserved space empty so the gap is the main signal
        else
            local proxyIndex = panelIndex
            if model.mode == PREVIEW_MODE_PANEL_COMPACT then
                visibleCompactIndex = visibleCompactIndex + 1
                proxyIndex = visibleCompactIndex
            end

            local panelProxy = AcquirePreviewPanelFrame(preview, proxyIndex)
            local panelFrame = panelProxy.frame
            panelFrame:SetFrameLevel((preview.root:GetFrameLevel() or 1) + proxyIndex)
            if model.mode == PREVIEW_MODE_PANEL_COMPACT then
                local bg = panel.backdropColor
                local border = panel.borderColor
                if bg then
                    panelFrame:SetBackdropColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 0.2)
                else
                    panelFrame:SetBackdropColor(0, 0, 0, 0.22)
                end
                if border then
                    panelFrame:SetBackdropBorderColor(border[1] or 0, border[2] or 0, border[3] or 0, border[4] or 0.58)
                else
                    panelFrame:SetBackdropBorderColor(0, 0, 0, 0.58)
                end
                panelFrame._cdcTitle:ClearAllPoints()
                panelFrame._cdcTitle:SetPoint("CENTER", panelFrame, "CENTER", 8, 0)
            else
                local bg = panel.backdropColor
                local border = panel.borderColor
                if bg then
                    panelFrame:SetBackdropColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 0.2)
                else
                    panelFrame:SetBackdropColor(0, 0, 0, 0.22)
                end
                if border then
                    panelFrame:SetBackdropBorderColor(border[1] or 0, border[2] or 0, border[3] or 0, border[4] or 0.58)
                else
                    panelFrame:SetBackdropBorderColor(0, 0, 0, 0.58)
                end
                panelFrame._cdcTitle:ClearAllPoints()
                panelFrame._cdcTitle:SetPoint("TOP", panelFrame, "TOP", 0, -(panel.header.y + (panel.header.height / 2)))
            end
            if panel.displayMode == "bars" then
                panelFrame._cdcModeBadge:SetAtlas("CreditsScreen-Assets-Buttons-Pause", false)
                panelFrame._cdcModeBadge:Show()
            elseif panel.displayMode == "text" then
                panelFrame._cdcModeBadge:SetAtlas("poi-workorders", false)
                panelFrame._cdcModeBadge:Show()
            else
                panelFrame._cdcModeBadge:SetAtlas("UI-QuestPoi-QuestNumber-SuperTracked", false)
                panelFrame._cdcModeBadge:Show()
            end
            panelFrame._cdcTitle:SetText(panel.name .. " |cff666666(" .. tostring(panel.count or #panel.rows) .. ")|r")
            if not panel.enabled then
                panelFrame._cdcTitle:SetTextColor(0.55, 0.55, 0.55)
            elseif panel.headerColor then
                panelFrame._cdcTitle:SetTextColor(panel.headerColor[1] or 1, panel.headerColor[2] or 1, panel.headerColor[3] or 1)
            else
                panelFrame._cdcTitle:SetTextColor(1, 1, 1)
            end
            panelFrame._cdcModeBadge:ClearAllPoints()
            panelFrame._cdcModeBadge:SetPoint("RIGHT", panelFrame._cdcTitle, "LEFT", -4, 0)

            if model.mode == PREVIEW_MODE_PANEL_COMPACT then
                QueuePreviewTween(
                    preview,
                    panelFrame,
                    panel.x,
                    panel.previewY,
                    panel.width,
                    panel.previewHeight or panel.compactHeight,
                    1,
                    PREVIEW_ANIM_DURATION
                )
                preview.compactEntries = preview.compactEntries or {}
                preview.compactEntries[#preview.compactEntries + 1] = {
                    panelId = panel.panelId,
                    originalIndex = panel.originalIndex,
                    frame = panelFrame,
                }
            else
                ApplyPreviewFrameGeometry(
                    panelFrame,
                    panel.x,
                    panel.previewY,
                    panel.width,
                    panel.previewHeight,
                    1
                )
            end
            panelFrame:Show()

            local visibleRowIndex = 0
            for _, row in ipairs(panel.rows) do
                if not row.isGap and model.mode ~= PREVIEW_MODE_PANEL_COMPACT then
                    visibleRowIndex = visibleRowIndex + 1
                    local rowProxy = AcquirePreviewRowFrame(panelProxy, row.key or (tostring(panel.panelId) .. ":" .. tostring(visibleRowIndex)))
                    rowProxy.frame._cdcLabel:SetText(row.text or "")
                    if row.textColor then
                        rowProxy.frame._cdcLabel:SetTextColor(row.textColor[1] or 1, row.textColor[2] or 1, row.textColor[3] or 1)
                    else
                        rowProxy.frame._cdcLabel:SetTextColor(row.usable == false and 0.55 or 1, row.usable == false and 0.55 or 1, row.usable == false and 0.55 or 1)
                    end
                    rowProxy.frame._cdcIcon:SetSize(row.imageSize or 32, row.imageSize or 32)
                    rowProxy.frame._cdcIcon:SetTexture(row.icon or 134400)
                    rowProxy.frame._cdcIcon:SetShown(row.icon ~= nil)
                    if rowProxy.frame._cdcIcon.SetDesaturated then
                        rowProxy.frame._cdcIcon:SetDesaturated(row.usable == false)
                    end

                    QueuePreviewTween(
                        preview,
                        rowProxy.frame,
                        row.x,
                        row.previewY,
                        row.width,
                        row.height,
                        1,
                        PREVIEW_ANIM_DURATION
                    )
                    rowProxy.frame:Show()
                end
            end

            for _, rowProxy in ipairs(panelProxy.rows) do
                if not rowProxy.used then
                    rowProxy.frame:Hide()
                end
            end
        end
    end

    for _, panelProxy in ipairs(preview.panels) do
        if not panelProxy.used then
            panelProxy.frame:Hide()
        end
    end
    UpdateCol2Ghost(preview, source, model)
    preview.root:SetScript("OnUpdate", function()
        TickCol2Preview(preview)
    end)
end

ClearCol2AnimatedPreview = function()
    SetCol2BaseFramesHidden(false)
    ClearCol2PreviewHost()
end

local function UpdateCol2CursorPreview(targetPanelId)
    if not targetPanelId then
        ClearCol2AnimatedPreview()
        return
    end
    RenderCol2AnimatedPreview({
        kind = "cursor",
        targetPanelId = targetPanelId,
    })
end

local function GetCol2CompactPanelDropTarget(cursorY)
    local preview = CS.col2Preview
    local entries = preview and preview.compactEntries
    if not entries or #entries == 0 then return nil end

    for i, entry in ipairs(entries) do
        local frame = entry.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom then
                local mid = (top + bottom) / 2
                if cursorY > mid then
                    return {
                        targetIndex = entry.originalIndex,
                        targetPanelId = entry.panelId,
                        anchorFrame = frame,
                        anchorAbove = true,
                    }
                elseif i == #entries then
                    return {
                        targetIndex = (entry.originalIndex or i) + 1,
                        targetPanelId = entry.panelId,
                        anchorFrame = frame,
                        anchorAbove = false,
                    }
                end
            end
        end
    end

    local first = entries[1]
    if first and first.frame and first.frame:IsShown() then
        return {
            targetIndex = first.originalIndex or 1,
            targetPanelId = first.panelId,
            anchorFrame = first.frame,
            anchorAbove = true,
        }
    end
    return nil
end

------------------------------------------------------------------------
-- Column 2 panel-header drop target detection
------------------------------------------------------------------------
local function GetCol2PanelDropTarget(cursorY, panelDropTargets)
    if not panelDropTargets or #panelDropTargets == 0 then return nil end

    for i, entry in ipairs(panelDropTargets) do
        local frame = entry.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom then
                local mid = (top + bottom) / 2
                if cursorY > mid then
                    -- Cursor is in the upper half → drop above this panel (index i)
                    return {
                        targetIndex = i,
                        targetPanelId = entry.panelId,
                        anchorFrame = frame,
                        anchorAbove = true,
                    }
                elseif i == #panelDropTargets then
                    -- Below midpoint of last panel → drop after last
                    return {
                        targetIndex = i + 1,
                        targetPanelId = entry.panelId,
                        anchorFrame = frame,
                        anchorAbove = false,
                    }
                end
            end
        end
    end

    -- Cursor above all panels → index 1
    local first = panelDropTargets[1]
    if first and first.frame and first.frame:IsShown() then
        return {
            targetIndex = 1,
            targetPanelId = first.panelId,
            anchorFrame = first.frame,
            anchorAbove = true,
        }
    end
    return nil
end

------------------------------------------------------------------------
-- Panel reorder
------------------------------------------------------------------------
local function PerformPanelReorder(sourcePanelId, dropIndex, panelDropTargets)
    local db = CooldownCompanion.db.profile
    -- Build ordered panelIds list from drop targets
    local panelIds = {}
    for _, entry in ipairs(panelDropTargets) do
        table.insert(panelIds, entry.panelId)
    end
    -- Find source index
    local sourceIndex
    for i, pid in ipairs(panelIds) do
        if pid == sourcePanelId then
            sourceIndex = i
            break
        end
    end
    if not sourceIndex then return end
    if dropIndex > sourceIndex then dropIndex = dropIndex - 1 end
    if sourceIndex == dropIndex then return end
    table.remove(panelIds, sourceIndex)
    table.insert(panelIds, dropIndex, sourcePanelId)
    -- Reassign .order based on new list position
    for i, pid in ipairs(panelIds) do
        if db.groups[pid] then
            db.groups[pid].order = i
        end
    end
end

------------------------------------------------------------------------
-- Group reorder
------------------------------------------------------------------------
local function PerformGroupReorder(sourceIndex, dropIndex, groupIds)
    if dropIndex > sourceIndex then dropIndex = dropIndex - 1 end
    if sourceIndex == dropIndex then return end
    local db = CooldownCompanion.db.profile
    local id = table.remove(groupIds, sourceIndex)
    table.insert(groupIds, dropIndex, id)
    -- Reassign .order based on new list position
    for i, gid in ipairs(groupIds) do
        if db.groups[gid] then
            db.groups[gid].order = i
        end
    end
end

------------------------------------------------------------------------
-- Drop target detection for column 1 with folder support
------------------------------------------------------------------------
local function GetCol1DropTarget(cursorY, renderedRows, sourceKind, sourceSection)
    if not renderedRows or #renderedRows == 0 then return nil end

    for i, rowMeta in ipairs(renderedRows) do
        local frame = rowMeta.widget and rowMeta.widget.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom and cursorY <= top and cursorY >= bottom then
                local height = top - bottom
                -- If hovering over a folder header and dragging a group, use 3-zone detection
                if rowMeta.kind == "folder" and (sourceKind == "group" or sourceKind == "folder-group") then
                    local topZone = top - height * 0.25
                    local bottomZone = bottom + height * 0.25
                    if cursorY > topZone then
                        return { action = "reorder-before", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    elseif cursorY < bottomZone then
                        return { action = "reorder-after", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    else
                        return { action = "into-folder", rowIndex = i, targetRow = rowMeta, anchorFrame = frame, targetFolderId = rowMeta.id }
                    end
                else
                    -- Standard 2-zone (above/below midpoint)
                    local mid = (top + bottom) / 2
                    if cursorY > mid then
                        return { action = "reorder-before", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    else
                        return { action = "reorder-after", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
                    end
                end
            end
        end
    end

    -- Cursor is in a gap between rows (e.g. between sections): find the first
    -- row whose top edge is below the cursor and target it with reorder-before.
    for i, rowMeta in ipairs(renderedRows) do
        local frame = rowMeta.widget and rowMeta.widget.frame
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            if top and cursorY > top then
                return { action = "reorder-before", rowIndex = i, targetRow = rowMeta, anchorFrame = frame }
            end
        end
    end

    -- Below all rows: drop after the last row overall.
    local lastRow = renderedRows[#renderedRows]
    local lastRowIndex = #renderedRows
    local lastFrame = lastRow and lastRow.widget and lastRow.widget.frame
    if lastFrame and lastFrame:IsShown() then
        return { action = "reorder-after", rowIndex = lastRowIndex, targetRow = lastRow, anchorFrame = lastFrame, isBelowAll = true }
    end
    return nil
end

-- Show drag indicator for "into-folder" drops (highlight overlay on folder row)
local function ShowFolderDropOverlay(anchorFrame, parentScrollWidget)
    local ind = GetDragIndicator()
    local width = parentScrollWidget.content:GetWidth() or 100
    ind:SetWidth(width)
    ind:SetHeight(anchorFrame:GetHeight() or 24)
    ind:ClearAllPoints()
    ind:SetPoint("TOPLEFT", anchorFrame, "TOPLEFT", 0, 0)
    ind.tex:SetColorTexture(0.4, 0.7, 0.2, 0.3)
    ind:Show()
end

-- Reset drag indicator to default line style
local function ResetDragIndicatorStyle()
    if CS.dragIndicator and CS.dragIndicator.tex then
        CS.dragIndicator:SetHeight(2)
        CS.dragIndicator.tex:SetColorTexture(0.2, 0.6, 1.0, 1.0)
    end
end

------------------------------------------------------------------------
-- Apply a column-1 folder-aware drop result
------------------------------------------------------------------------
local function ApplyCol1Drop(state)
    local dropTarget = state.dropTarget
    if not dropTarget then return end

    local db = CooldownCompanion.db.profile

    if state.kind == "group" or state.kind == "folder-group" then
        -- Column 1 rows are containers now (sourceGroupId holds a containerId)
        local sourceContainerId = state.sourceGroupId
        local container = db.groupContainers[sourceContainerId]
        if not container then return end

        if dropTarget.action == "into-folder" then
            -- Move container into the target folder
            CooldownCompanion:MoveGroupToFolder(sourceContainerId, dropTarget.targetFolderId)
        elseif dropTarget.action == "reorder-before" or dropTarget.action == "reorder-after" then
            local targetRow = dropTarget.targetRow
            if dropTarget.isBelowAll then
                -- Dropped below all rows: always become top-level
                CooldownCompanion:MoveGroupToFolder(sourceContainerId, nil)
            elseif targetRow.kind == "container" and targetRow.inFolder then
                -- If dropping on a row that's in a folder, join that folder
                CooldownCompanion:MoveGroupToFolder(sourceContainerId, targetRow.inFolder)
            elseif targetRow.kind == "folder" then
                -- Dropping before/after a folder header = top-level
                CooldownCompanion:MoveGroupToFolder(sourceContainerId, nil)
            elseif targetRow.kind == "phantom" then
                -- Dropping on phantom section placeholder = top-level in that section
                CooldownCompanion:MoveGroupToFolder(sourceContainerId, nil)
            else
                -- Dropping on a loose container = stay/become loose
                CooldownCompanion:MoveGroupToFolder(sourceContainerId, nil)
            end

            -- Cross-section move: toggle global/character status
            local targetSection = targetRow.section or state.sourceSection
            if targetSection ~= state.sourceSection then
                if targetSection == "global" then
                    container.isGlobal = true
                else
                    container.isGlobal = false
                    container.createdBy = CooldownCompanion.db.keys.char
                end
            end

            -- Reassign order values for all items in the target section
            -- to place the dragged container at the right position
            local section = targetSection
            local renderedRows = state.col1RenderedRows
            if renderedRows then
                -- Build ordered list of items in the same parent (folder or top-level)
                -- and reassign order values
                local targetFolderId = container.folderId
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == section then
                        if targetFolderId then
                            -- Ordering within a folder: collect containers in same folder
                            if row.kind == "container" and row.inFolder == targetFolderId and row.id ~= sourceContainerId then
                                table.insert(orderItems, row.id)
                            end
                        else
                            -- Top-level ordering: collect top-level items (folders + loose containers)
                            if (row.kind == "folder") or (row.kind == "container" and not row.inFolder) then
                                if row.id ~= sourceContainerId then
                                    table.insert(orderItems, { kind = row.kind, id = row.id })
                                end
                            end
                        end
                    end
                end

                -- Find insertion position
                local insertPos
                if targetFolderId then
                    -- Within folder: find target container position
                    insertPos = #orderItems + 1
                    for idx, cid in ipairs(orderItems) do
                        if cid == dropTarget.targetRow.id then
                            insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                            break
                        end
                    end
                    table.insert(orderItems, insertPos, sourceContainerId)
                    local specId = CooldownCompanion._currentSpecId
                    for i, cid in ipairs(orderItems) do
                        if db.groupContainers[cid] then
                            CooldownCompanion:SetOrderForSpec(db.groupContainers[cid], specId, i)
                        end
                    end
                else
                    -- Top-level: find target position among mixed items
                    insertPos = #orderItems + 1
                    for idx, item in ipairs(orderItems) do
                        if item.kind == dropTarget.targetRow.kind and item.id == dropTarget.targetRow.id then
                            insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                            break
                        end
                    end
                    table.insert(orderItems, insertPos, { kind = "group", id = sourceContainerId })
                    local specId = CooldownCompanion._currentSpecId
                    for i, item in ipairs(orderItems) do
                        if item.kind == "folder" and db.folders[item.id] then
                            CooldownCompanion:SetOrderForSpec(db.folders[item.id], specId, i)
                        elseif db.groupContainers[item.id] then
                            CooldownCompanion:SetOrderForSpec(db.groupContainers[item.id], specId, i)
                        end
                    end
                end
            end
        end
    elseif state.kind == "multi-group" then
        -- Multi-select: sourceGroupIds holds container IDs (Column 1 rows are containers)
        local sourceContainerIds = state.sourceGroupIds
        if not sourceContainerIds then return end

        local targetRow = dropTarget.targetRow
        -- Determine target folder and section
        local targetFolderId = nil
        if dropTarget.action == "into-folder" then
            targetFolderId = dropTarget.targetFolderId
        elseif dropTarget.action == "reorder-before" or dropTarget.action == "reorder-after" then
            if dropTarget.isBelowAll then
                targetFolderId = nil
            elseif targetRow.kind == "container" and targetRow.inFolder then
                targetFolderId = targetRow.inFolder
            else
                targetFolderId = nil
            end
        end

        local targetSection = targetRow.section or state.sourceSection

        -- Set folder and cross-section toggle for each selected container
        for cid in pairs(sourceContainerIds) do
            local c = db.groupContainers[cid]
            if c then
                CooldownCompanion:MoveGroupToFolder(cid, targetFolderId)
                local containerSection = c.isGlobal and "global" or "char"
                if containerSection ~= targetSection then
                    if targetSection == "global" then
                        c.isGlobal = true
                    else
                        c.isGlobal = false
                        c.createdBy = CooldownCompanion.db.keys.char
                    end
                end
            end
        end

        -- Sort selected containers by current per-spec order to preserve relative ordering
        local specId = CooldownCompanion._currentSpecId
        local sortedSelected = {}
        for cid in pairs(sourceContainerIds) do
            local c = db.groupContainers[cid]
            if c then
                table.insert(sortedSelected, { id = cid, order = CooldownCompanion:GetOrderForSpec(c, specId, cid) })
            end
        end
        table.sort(sortedSelected, function(a, b) return a.order < b.order end)

        -- Rebuild order for target section
        local renderedRows = state.col1RenderedRows
        if renderedRows then
            if targetFolderId then
                -- Ordering within a folder
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.kind == "container" and row.inFolder == targetFolderId and not sourceContainerIds[row.id] then
                        table.insert(orderItems, row.id)
                    end
                end

                -- Find insertion position
                local insertPos = #orderItems + 1
                for idx, cid in ipairs(orderItems) do
                    if cid == targetRow.id then
                        insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                        break
                    end
                end
                -- Insert all selected containers at the position, preserving relative order
                for i, item in ipairs(sortedSelected) do
                    table.insert(orderItems, insertPos + i - 1, item.id)
                end
                for i, cid in ipairs(orderItems) do
                    if db.groupContainers[cid] then
                        CooldownCompanion:SetOrderForSpec(db.groupContainers[cid], specId, i)
                    end
                end
            else
                -- Top-level ordering
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == targetSection then
                        if (row.kind == "folder") or (row.kind == "container" and not row.inFolder) then
                            if not sourceContainerIds[row.id] then
                                table.insert(orderItems, { kind = row.kind, id = row.id })
                            end
                        end
                    end
                end

                local insertPos = #orderItems + 1
                for idx, item in ipairs(orderItems) do
                    if item.kind == targetRow.kind and item.id == targetRow.id then
                        insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                        break
                    end
                end
                -- Insert all selected containers at the position
                for i, item in ipairs(sortedSelected) do
                    table.insert(orderItems, insertPos + i - 1, { kind = "group", id = item.id })
                end
                for i, item in ipairs(orderItems) do
                    if item.kind == "folder" and db.folders[item.id] then
                        CooldownCompanion:SetOrderForSpec(db.folders[item.id], specId, i)
                    elseif db.groupContainers[item.id] then
                        CooldownCompanion:SetOrderForSpec(db.groupContainers[item.id], specId, i)
                    end
                end
            end
        end
    elseif state.kind == "folder" then
        local sourceFolderId = state.sourceFolderId
        local folder = db.folders[sourceFolderId]
        if not folder then return end

        local dropTarget = state.dropTarget
        local targetRow = dropTarget.targetRow
        local section = targetRow.section or state.sourceSection

        -- Cross-section move: toggle folder section and update all child containers
        if section ~= state.sourceSection then
            folder.section = section
            if section == "char" then
                folder.createdBy = CooldownCompanion.db.keys.char
            end
            for containerId, container in pairs(db.groupContainers) do
                if container.folderId == sourceFolderId then
                    if section == "global" then
                        container.isGlobal = true
                    else
                        container.isGlobal = false
                        container.createdBy = CooldownCompanion.db.keys.char
                    end
                end
            end
        end

        -- Build top-level items for the section (excluding the source folder)
        local renderedRows = state.col1RenderedRows
        if renderedRows then
            local orderItems = {}
            for _, row in ipairs(renderedRows) do
                if row.section == section then
                    if (row.kind == "folder" or (row.kind == "container" and not row.inFolder)) and row.id ~= sourceFolderId then
                        table.insert(orderItems, { kind = row.kind, id = row.id })
                    end
                end
            end

            local insertPos = #orderItems + 1
            for idx, item in ipairs(orderItems) do
                local targetKind = targetRow.kind
                local targetId = targetRow.id
                -- If target is a group inside a folder, use the folder as anchor
                if targetRow.inFolder then
                    targetKind = "folder"
                    targetId = targetRow.inFolder
                end
                if item.kind == targetKind and item.id == targetId then
                    insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                    break
                end
            end
            table.insert(orderItems, insertPos, { kind = "folder", id = sourceFolderId })
            local specId = CooldownCompanion._currentSpecId
            for i, item in ipairs(orderItems) do
                if item.kind == "folder" then
                    if db.folders[item.id] then
                        CooldownCompanion:SetOrderForSpec(db.folders[item.id], specId, i)
                    end
                else
                    if db.groupContainers[item.id] then
                        CooldownCompanion:SetOrderForSpec(db.groupContainers[item.id], specId, i)
                    end
                end
            end
        end
    end

    -- Container order may have changed — re-evaluate auto-anchored bars
    CooldownCompanion:EvaluateResourceBars()
    CooldownCompanion:UpdateAnchorStacking()
    CooldownCompanion:EvaluateCastBar()
end

------------------------------------------------------------------------
-- Button reorder
------------------------------------------------------------------------
local function PerformButtonReorder(groupId, sourceIndex, dropIndex)
    if dropIndex > sourceIndex then dropIndex = dropIndex - 1 end
    if sourceIndex == dropIndex then return end
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not group then return end
    local entry = table.remove(group.buttons, sourceIndex)
    table.insert(group.buttons, dropIndex, entry)
    -- Track selectedButton
    if CS.selectedButton == sourceIndex then
        CS.selectedButton = dropIndex
    elseif CS.selectedButton then
        -- Adjust if the move shifted the selected index
        if sourceIndex < CS.selectedButton and dropIndex >= CS.selectedButton then
            CS.selectedButton = CS.selectedButton - 1
        elseif sourceIndex > CS.selectedButton and dropIndex <= CS.selectedButton then
            CS.selectedButton = CS.selectedButton + 1
        end
    end
end

------------------------------------------------------------------------
-- Cross-panel move helpers
------------------------------------------------------------------------
local function PerformCrossPanelMove(sourcePanelId, sourceIndex, targetPanelId, targetIndex)
    local db = CooldownCompanion.db.profile
    local sourceGroup = db.groups[sourcePanelId]
    local targetGroup = db.groups[targetPanelId]
    if not sourceGroup or not targetGroup then return nil end
    local buttonData = table.remove(sourceGroup.buttons, sourceIndex)
    if not buttonData then return nil end
    -- Resolve "append" targets (nil targetIndex = after last button)
    if not targetIndex then
        targetIndex = #targetGroup.buttons + 1
    end
    local maxTarget = #targetGroup.buttons + 1
    if targetIndex > maxTarget then targetIndex = maxTarget end
    table.insert(targetGroup.buttons, targetIndex, buttonData)
    return buttonData
end

local function StripButtonOverrides(buttonData)
    buttonData.styleOverrides = nil
    buttonData.overrideSections = nil
    buttonData.textFormat = nil
end

local function ButtonHasOverrides(buttonData)
    return (buttonData.styleOverrides and next(buttonData.styleOverrides))
        or (buttonData.overrideSections and next(buttonData.overrideSections))
        or buttonData.textFormat ~= nil
end

------------------------------------------------------------------------
-- Drag lifecycle
------------------------------------------------------------------------
local function CancelDrag()
    if CS.dragState then
        if CS.dragState.dimmedWidgets then
            for _, w in ipairs(CS.dragState.dimmedWidgets) do
                w.frame:SetAlpha(1)
            end
        elseif CS.dragState.widget then
            CS.dragState.widget.frame:SetAlpha(1)
        end
    end
    CS.dragState = nil
    ClearCol2AnimatedPreview()
    HideDragIndicator()
    ResetDragIndicatorStyle()
    if CS.dragTracker then
        CS.dragTracker:SetScript("OnUpdate", nil)
    end
    if CS.showPhantomSections then
        CS.showPhantomSections = false
        C_Timer.After(0, function()
            CooldownCompanion:RefreshConfigPanel()
        end)
    end
end

local function FinishDrag()
    if not CS.dragState or CS.dragState.phase ~= "active" then
        CancelDrag()
        return
    end
    local state = CS.dragState
    CS.showPhantomSections = false  -- clear before CancelDrag to avoid redundant deferred refresh
    CancelDrag()
    ResetDragIndicatorStyle()
    if state.kind == "group" and state.groupIds then
        -- Legacy flat reorder (column 2 button drags still use this path)
        PerformGroupReorder(state.sourceIndex, state.dropIndex or state.sourceIndex, state.groupIds)
        CooldownCompanion:EvaluateResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:EvaluateCastBar()
        CooldownCompanion:RefreshConfigPanel()
    elseif state.kind == "group" or state.kind == "folder" or state.kind == "folder-group" or state.kind == "multi-group" then
        -- Column 1 folder-aware drop
        -- Check for cross-section global→char with foreign specs
        local dropTarget = state.dropTarget
        if dropTarget and (state.kind == "group" or state.kind == "folder-group") then
            local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
            local sourceContainer = CooldownCompanion.db.profile.groupContainers[state.sourceGroupId]
            if targetSection and targetSection ~= state.sourceSection
               and state.sourceSection == "global"
               and sourceContainer and sourceContainer.specs
               and GroupsHaveForeignSpecs({sourceContainer}, false) then
                ShowPopupAboveConfig("CDC_DRAG_UNGLOBAL_GROUP", sourceContainer.name, {
                    dragState = state,
                })
                return
            end
        end
        -- Check for cross-section global→char with foreign specs (multi-group)
        if dropTarget and state.kind == "multi-group" and state.sourceGroupIds then
            local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
            if targetSection == "char" then
                local db = CooldownCompanion.db.profile
                local groupList = {}
                for cid in pairs(state.sourceGroupIds) do
                    if db.groupContainers[cid] then groupList[#groupList + 1] = db.groupContainers[cid] end
                end
                if GroupsHaveForeignSpecs(groupList, true) then
                    ShowPopupAboveConfig("CDC_UNGLOBAL_SELECTED_GROUPS", nil, {
                        groupIds = (function()
                            local ids = {}
                            for gid in pairs(state.sourceGroupIds) do table.insert(ids, gid) end
                            return ids
                        end)(),
                        callback = function()
                            ApplyCol1Drop(state)
                            CooldownCompanion:RefreshConfigPanel()
                        end,
                    })
                    return
                end
            end
        end
        -- Check for cross-section global→char with foreign specs in folder children
        if dropTarget and state.kind == "folder" then
            local targetSection = dropTarget.targetRow and dropTarget.targetRow.section
            if targetSection and targetSection ~= state.sourceSection
               and state.sourceSection == "global" then
                if FolderHasForeignSpecs and FolderHasForeignSpecs(state.sourceFolderId) then
                    ShowPopupAboveConfig("CDC_DRAG_UNGLOBAL_FOLDER", nil, {
                        dragState = state,
                    })
                    return
                end
            end
        end
        ApplyCol1Drop(state)
        CooldownCompanion:RefreshConfigPanel()
    elseif state.kind == "panel" then
        local dropTarget = state.dropTarget
        if dropTarget then
            PerformPanelReorder(state.sourcePanelId, dropTarget.targetIndex, state.panelDropTargets)
            -- Refresh all affected panel frames
            for _, entry in ipairs(state.panelDropTargets) do
                CooldownCompanion:RefreshGroupFrame(entry.panelId)
            end
        end
        CooldownCompanion:RefreshConfigPanel()
    elseif state.kind == "button" then
        if state.dropTarget then
            -- Cross-panel-aware path (multi-panel containers)
            local dt = state.dropTarget
            -- Resolve append targets
            local resolvedIndex = dt.targetIndex
            if not resolvedIndex then
                local tg = CooldownCompanion.db.profile.groups[dt.targetPanelId]
                resolvedIndex = tg and (#tg.buttons + 1) or 1
            end
            if dt.targetPanelId == state.groupId then
                -- Same panel: existing intra-panel reorder
                PerformButtonReorder(state.groupId, state.sourceIndex, resolvedIndex)
                CooldownCompanion:RefreshGroupFrame(state.groupId)
            else
                -- Cross-panel move
                local sourceGroup = CooldownCompanion.db.profile.groups[state.groupId]
                local buttonData = sourceGroup and sourceGroup.buttons[state.sourceIndex]
                if buttonData and ButtonHasOverrides(buttonData) then
                    ShowPopupAboveConfig("CDC_CROSS_PANEL_STRIP_OVERRIDES", buttonData.name or "this button", {
                        sourcePanelId = state.groupId,
                        sourceIndex = state.sourceIndex,
                        targetPanelId = dt.targetPanelId,
                        targetIndex = resolvedIndex,
                    })
                    return  -- popup handles move + refresh
                end
                PerformCrossPanelMove(state.groupId, state.sourceIndex, dt.targetPanelId, resolvedIndex)
                CooldownCompanion:RefreshGroupFrame(state.groupId)
                CooldownCompanion:RefreshGroupFrame(dt.targetPanelId)
            end
        else
            -- Legacy single-panel path (no col2RenderedRows)
            PerformButtonReorder(state.groupId, state.sourceIndex, state.dropIndex or state.sourceIndex)
            CooldownCompanion:RefreshGroupFrame(state.groupId)
        end
        CS.selectedButton = nil
        wipe(CS.selectedButtons)
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function StartDragTracking()
    if not CS.dragTracker then
        CS.dragTracker = CreateFrame("Frame", nil, UIParent)
    end
    CS.dragTracker:SetScript("OnUpdate", function()
        if not CS.dragState then
            CS.dragTracker:SetScript("OnUpdate", nil)
            return
        end
        if not IsMouseButtonDown("LeftButton") then
            -- Mouse released
            if CS.dragState.phase == "active" then
                FinishDrag()
            else
                -- Was just a click, not a drag — clear state
                CancelDrag()
            end
            return
        end
        local cursorY = GetScaledCursorPosition(CS.dragState.scrollWidget)
        if CS.dragState.phase == "pending" then
            if math.abs(cursorY - CS.dragState.startY) > DRAG_THRESHOLD then
                CS.dragState.phase = "active"
                -- Dim source widget(s)
                if CS.dragState.kind == "multi-group" and CS.dragState.sourceGroupIds then
                    CS.dragState.dimmedWidgets = {}
                    for _, row in ipairs(CS.dragState.col1RenderedRows) do
                        if row.kind == "container" and CS.dragState.sourceGroupIds[row.id] then
                            row.widget.frame:SetAlpha(0.4)
                            table.insert(CS.dragState.dimmedWidgets, row.widget)
                        end
                    end
                elseif CS.dragState.widget then
                    CS.dragState.widget.frame:SetAlpha(0.4)
                end
                -- Check if we need phantom sections for cross-section drops
                if CS.dragState.col1RenderedRows and not CS.showPhantomSections then
                    local hasGlobal, hasChar = false, false
                    for _, row in ipairs(CS.dragState.col1RenderedRows) do
                        if row.section == "global" then hasGlobal = true end
                        if row.section == "char" then hasChar = true end
                    end
                    if not hasGlobal or not hasChar then
                        -- Save drag metadata before rebuild
                        local savedKind = CS.dragState.kind
                        local savedSourceGroupId = CS.dragState.sourceGroupId
                        local savedSourceGroupIds = CS.dragState.sourceGroupIds
                        local savedSourceFolderId = CS.dragState.sourceFolderId
                        local savedSourceSection = CS.dragState.sourceSection
                        local savedScrollWidget = CS.dragState.scrollWidget
                        local savedStartY = CS.dragState.startY
                        CS.showPhantomSections = true
                        ST._RefreshColumn1(true)
                        -- Reconstruct drag state with new rendered rows
                        CS.dragState = {
                            kind = savedKind,
                            phase = "active",
                            sourceGroupId = savedSourceGroupId,
                            sourceGroupIds = savedSourceGroupIds,
                            sourceFolderId = savedSourceFolderId,
                            sourceSection = savedSourceSection,
                            scrollWidget = savedScrollWidget,
                            startY = savedStartY,
                            col1RenderedRows = CS.lastCol1RenderedRows,
                        }
                        -- Dim the source widget(s) in the new rows
                        if savedKind == "multi-group" and savedSourceGroupIds then
                            CS.dragState.dimmedWidgets = {}
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if row.kind == "container" and savedSourceGroupIds[row.id] then
                                    row.widget.frame:SetAlpha(0.4)
                                    table.insert(CS.dragState.dimmedWidgets, row.widget)
                                end
                            end
                        else
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if savedKind == "folder" and row.kind == "folder" and row.id == savedSourceFolderId then
                                    CS.dragState.widget = row.widget
                                    row.widget.frame:SetAlpha(0.4)
                                    break
                                elseif (savedKind == "group" or savedKind == "folder-group") and row.kind == "container" and row.id == savedSourceGroupId then
                                    CS.dragState.widget = row.widget
                                    row.widget.frame:SetAlpha(0.4)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        if CS.dragState.phase == "active" then
            if CS.dragState.col1RenderedRows then
                ClearCol2AnimatedPreview()
                -- Column 1 folder-aware drop detection
                local effectiveKind = CS.dragState.kind == "multi-group" and "group" or CS.dragState.kind
                local dropTarget = GetCol1DropTarget(cursorY, CS.dragState.col1RenderedRows, effectiveKind, CS.dragState.sourceSection)
                CS.dragState.dropTarget = dropTarget
                if dropTarget then
                    ResetDragIndicatorStyle()
                    if dropTarget.action == "into-folder" then
                        ShowFolderDropOverlay(dropTarget.anchorFrame, CS.dragState.scrollWidget)
                    elseif dropTarget.action == "reorder-before" then
                        ShowDragIndicator(dropTarget.anchorFrame, true, CS.dragState.scrollWidget)
                    else
                        ShowDragIndicator(dropTarget.anchorFrame, false, CS.dragState.scrollWidget)
                    end
                else
                    HideDragIndicator()
                end
            elseif CS.dragState.panelDropTargets then
                -- Panel reorder detection
                local preview = CS.col2Preview
                local dropTarget
                if preview and preview.mode == PREVIEW_MODE_PANEL_COMPACT then
                    dropTarget = GetCol2CompactPanelDropTarget(cursorY)
                else
                    dropTarget = GetCol2PanelDropTarget(cursorY, CS.dragState.panelDropTargets)
                end
                CS.dragState.dropTarget = dropTarget
                if dropTarget then
                    HideDragIndicator()
                    RenderCol2AnimatedPreview({
                        kind = "panel",
                        sourcePanelId = CS.dragState.sourcePanelId,
                        dropTarget = dropTarget,
                    })
                else
                    HideDragIndicator()
                    ClearCol2AnimatedPreview()
                end
            elseif CS.dragState.col2RenderedRows then
                -- Column 2 cross-panel drop detection
                local dropTarget = GetCol2DropTarget(cursorY, CS.dragState.col2RenderedRows)
                CS.dragState.dropTarget = dropTarget
                if dropTarget then
                    HideDragIndicator()
                    RenderCol2AnimatedPreview({
                        kind = "button",
                        groupId = CS.dragState.groupId,
                        sourceIndex = CS.dragState.sourceIndex,
                        dropTarget = dropTarget,
                    })
                else
                    HideDragIndicator()
                    ClearCol2AnimatedPreview()
                end
            else
                ClearCol2AnimatedPreview()
                local dropIndex, anchorFrame, anchorAbove = GetDropIndex(
                    CS.dragState.scrollWidget, cursorY,
                    CS.dragState.childOffset or 0,
                    CS.dragState.totalDraggable
                )
                CS.dragState.dropIndex = dropIndex
                ShowDragIndicator(anchorFrame, anchorAbove, CS.dragState.scrollWidget)
            end
        end
    end)
end

------------------------------------------------------------------------
-- ST._ exports (consumed by later Config/ files)
------------------------------------------------------------------------
ST._CancelDrag = CancelDrag
ST._StartDragTracking = StartDragTracking
ST._FinishDrag = FinishDrag
ST._ApplyCol1Drop = ApplyCol1Drop
ST._PerformButtonReorder = PerformButtonReorder
ST._PerformGroupReorder = PerformGroupReorder
ST._GetDragIndicator = GetDragIndicator
ST._HideDragIndicator = HideDragIndicator
ST._GetScaledCursorPosition = GetScaledCursorPosition
ST._GetDropIndex = GetDropIndex
ST._ShowDragIndicator = ShowDragIndicator
ST._GetCol1DropTarget = GetCol1DropTarget
ST._ShowFolderDropOverlay = ShowFolderDropOverlay
ST._ResetDragIndicatorStyle = ResetDragIndicatorStyle
ST._PerformCrossPanelMove = PerformCrossPanelMove
ST._StripButtonOverrides = StripButtonOverrides
ST._UpdateCol2CursorPreview = UpdateCol2CursorPreview
ST._ClearCol2AnimatedPreview = ClearCol2AnimatedPreview
