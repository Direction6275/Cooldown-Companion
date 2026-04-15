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
local EnsureCol1PreviewHost = ST._EnsureCol1PreviewHost
local ClearCol1PreviewHost = ST._ClearCol1PreviewHost
local EnsureCol2PreviewHost = ST._EnsureCol2PreviewHost
local ClearCol2PreviewHost = ST._ClearCol2PreviewHost
local SetupGroupRowIndicators = ST._SetupGroupRowIndicators
local SetupFolderRowIndicators = ST._SetupFolderRowIndicators
local ApplyColumn1MarkerAppearance = ST._ApplyColumn1MarkerAppearance

-- File-local constants
local DRAG_THRESHOLD = 8
local PREVIEW_ANIM_DURATION = 0.08
local PREVIEW_PANEL_INSET = 8
local PREVIEW_ROW_TEXT_RIGHT_PAD = 8
local PREVIEW_DEFAULT_ROW_HEIGHT = 32
local COL1_HIT_X_PAD = 6

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

local function GetDragScaleFrame(scrollWidget)
    if not scrollWidget then
        return UIParent
    end
    return scrollWidget.frame or scrollWidget
end

local function GetScaledCursorCoordinates(scrollWidget)
    local cursorX, cursorY = GetCursorPosition()
    local scaleFrame = GetDragScaleFrame(scrollWidget)
    local scale = (scaleFrame and scaleFrame.GetEffectiveScale and scaleFrame:GetEffectiveScale()) or 1
    return cursorX / scale, cursorY / scale
end

local function GetScaledCursorPosition(scrollWidget)
    return GetScaledCursorCoordinates(scrollWidget)
end

local function GetRawCursorCoordinates()
    return GetCursorPosition()
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
    local width
    if parentScrollWidget and parentScrollWidget.content then
        width = parentScrollWidget.content:GetWidth()
    else
        local scaleFrame = GetDragScaleFrame(parentScrollWidget)
        width = scaleFrame and scaleFrame:GetWidth()
    end
    width = width or 100
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

local function ApplyPreviewBackdrop(frame, bg, border)
    if bg then
        frame:SetBackdropColor(bg[1] or 0, bg[2] or 0, bg[3] or 0, bg[4] or 0.2)
    else
        frame:SetBackdropColor(0, 0, 0, 0.22)
    end

    if border then
        frame:SetBackdropBorderColor(border[1] or 0, border[2] or 0, border[3] or 0, border[4] or 0.58)
    else
        frame:SetBackdropBorderColor(0, 0, 0, 0.58)
    end
end

local function ApplyPreviewModeBadge(texture, displayMode)
    if displayMode == "bars" then
        texture:SetAtlas("CreditsScreen-Assets-Buttons-Pause", false)
    elseif displayMode == "text" then
        texture:SetAtlas("poi-workorders", false)
    elseif displayMode == "textures" then
        texture:SetTexture(134400)
    elseif displayMode == "trigger" then
        texture:SetTexture(134400)
    else
        texture:SetAtlas("UI-QuestPoi-QuestNumber-SuperTracked", false)
    end
    texture:Show()
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

local function ApplyRelativeRect(region, parent, rect)
    if not (region and parent and rect and rect.width and rect.height) then
        return false
    end

    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", parent, "TOPLEFT", rect.x or 0, -(rect.y or 0))
    region:SetPoint(
        "BOTTOMRIGHT",
        parent,
        "TOPLEFT",
        (rect.x or 0) + rect.width,
        -((rect.y or 0) + rect.height)
    )
    return true
end

local function BuildPreviewHeaderText(panel)
    return (panel.name or ("Panel " .. tostring(panel.panelId))) ..
        " |cff666666(" .. tostring(panel.count or #panel.rows) .. ")|r"
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
        iconRect = row.iconRect and {
            x = row.iconRect.x,
            y = row.iconRect.y,
            width = row.iconRect.width,
            height = row.iconRect.height,
        } or nil,
        labelRect = row.labelRect and {
            x = row.labelRect.x,
            y = row.labelRect.y,
            width = row.labelRect.width,
            height = row.labelRect.height,
        } or nil,
        isGap = row.isGap,
        isMarker = row.isMarker,
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
            labelRect = panel.header.labelRect and {
                x = panel.header.labelRect.x,
                y = panel.header.labelRect.y,
                width = panel.header.labelRect.width,
                height = panel.header.labelRect.height,
            } or nil,
            modeBadgeRect = panel.header.modeBadgeRect and {
                x = panel.header.modeBadgeRect.x,
                y = panel.header.modeBadgeRect.y,
                width = panel.header.modeBadgeRect.width,
                height = panel.header.modeBadgeRect.height,
            } or nil,
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
                labelRect = (function()
                    local lx, ly, lw, lh = GetRelativeRect(meta.headerWidget and meta.headerWidget.label, meta.panelFrame)
                    if lx then
                        return { x = lx, y = ly, width = lw, height = lh }
                    end
                end)(),
                modeBadgeRect = (function()
                    local bx, by, bw, bh = GetRelativeRect(meta.headerWidget and meta.headerWidget._cdcModeBadge, meta.panelFrame)
                    if bx then
                        return { x = bx, y = by, width = bw, height = bh }
                    end
                end)(),
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
                    iconRect = (function()
                        local ix, iy, iw, ih = GetRelativeRect(rowMeta.widget and rowMeta.widget.image, rowMeta.frame)
                        if ix then
                            return { x = ix, y = iy, width = iw, height = ih }
                        end
                    end)(),
                    labelRect = (function()
                        local lx, ly, lw, lh = GetRelativeRect(rowMeta.widget and rowMeta.widget.label, rowMeta.frame)
                        if lx then
                            return { x = lx, y = ly, width = lw, height = lh }
                        end
                    end)(),
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
                targetPanel.count = #targetPanel.rows
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
            ApplyPreviewBackdrop(preview.ghost, panel.backdropColor, panel.borderColor)
            preview.ghost:SetSize(panel.width, panel.compactHeight or panel.header.height)
            preview.ghost.label:SetText(panel.name .. " |cff666666(" .. tostring(panel.count or 0) .. ")|r")
            preview.ghost.icon:SetSize(16, 16)
            preview.ghost.icon:SetPoint("LEFT", preview.ghost, "LEFT", 10, 0)
            preview.ghost.label:SetPoint("LEFT", preview.ghost.icon, "RIGHT", 8, 0)
            preview.ghost.label:SetPoint("RIGHT", preview.ghost, "RIGHT", -10, 0)
            ApplyPreviewModeBadge(preview.ghost.icon, panel.displayMode)
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
            ApplyPreviewBackdrop(panelFrame, panel.backdropColor, panel.borderColor)
            if model.mode == PREVIEW_MODE_PANEL_COMPACT then
                panelFrame._cdcTitle:ClearAllPoints()
                panelFrame._cdcTitle:SetPoint("CENTER", panelFrame, "CENTER", 8, 0)
            else
                if not ApplyRelativeRect(panelFrame._cdcTitle, panelFrame, panel.header.labelRect) then
                    panelFrame._cdcTitle:ClearAllPoints()
                    panelFrame._cdcTitle:SetPoint("TOP", panelFrame, "TOP", 0, -(panel.header.y + (panel.header.height / 2)))
                end
            end
            ApplyPreviewModeBadge(panelFrame._cdcModeBadge, panel.displayMode)
            panelFrame._cdcTitle:SetText(BuildPreviewHeaderText(panel))
            if not panel.enabled then
                panelFrame._cdcTitle:SetTextColor(0.55, 0.55, 0.55)
            elseif panel.headerColor then
                panelFrame._cdcTitle:SetTextColor(panel.headerColor[1] or 1, panel.headerColor[2] or 1, panel.headerColor[3] or 1)
            else
                panelFrame._cdcTitle:SetTextColor(1, 1, 1)
            end
            if model.mode == PREVIEW_MODE_PANEL_COMPACT then
                panelFrame._cdcModeBadge:ClearAllPoints()
                panelFrame._cdcModeBadge:SetPoint("RIGHT", panelFrame._cdcTitle, "LEFT", -4, 0)
            else
                local textW = panelFrame._cdcTitle:GetStringWidth()
                panelFrame._cdcModeBadge:ClearAllPoints()
                panelFrame._cdcModeBadge:SetPoint(
                    "RIGHT",
                    panelFrame._cdcTitle,
                    "CENTER",
                    -(textW / 2) - 2,
                    0
                )
            end

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
                    rowProxy.frame._cdcIcon:ClearAllPoints()
                    if not ApplyRelativeRect(rowProxy.frame._cdcIcon, rowProxy.frame, row.iconRect) then
                        rowProxy.frame._cdcIcon:SetPoint("LEFT", rowProxy.frame, "LEFT", 0, 0)
                        rowProxy.frame._cdcIcon:SetSize(row.imageSize or 32, row.imageSize or 32)
                    end
                    rowProxy.frame._cdcIcon:SetTexture(row.icon or 134400)
                    rowProxy.frame._cdcIcon:SetShown(row.icon ~= nil)
                    if rowProxy.frame._cdcIcon.SetDesaturated then
                        rowProxy.frame._cdcIcon:SetDesaturated(row.usable == false)
                    end
                    if not ApplyRelativeRect(rowProxy.frame._cdcLabel, rowProxy.frame, row.labelRect) then
                        rowProxy.frame._cdcLabel:ClearAllPoints()
                        rowProxy.frame._cdcLabel:SetPoint("LEFT", rowProxy.frame._cdcIcon, "RIGHT", 8, 0)
                        rowProxy.frame._cdcLabel:SetPoint("RIGHT", rowProxy.frame, "RIGHT", -PREVIEW_ROW_TEXT_RIGHT_PAD, 0)
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

------------------------------------------------------------------------
-- Column 1 animated preview helpers
------------------------------------------------------------------------
local PREVIEW_MODE_COL1_LIST = "col1_list_drag"

local function CopyCol1PreviewRow(row)
    return {
        key = row.key,
        originalIndex = row.originalIndex,
        kind = row.kind,
        id = row.id,
        inFolder = row.inFolder,
        section = row.section,
        loadBucket = row.loadBucket,
        acceptsDrop = row.acceptsDrop,
        x = row.x,
        y = row.y,
        width = row.width,
        height = row.height,
        text = row.text,
        textColor = row.textColor and {
            row.textColor[1],
            row.textColor[2],
            row.textColor[3],
        } or nil,
        icon = row.icon,
        iconAlpha = row.iconAlpha,
        iconRect = row.iconRect and {
            x = row.iconRect.x,
            y = row.iconRect.y,
            width = row.iconRect.width,
            height = row.iconRect.height,
        } or nil,
        labelRect = row.labelRect and {
            x = row.labelRect.x,
            y = row.labelRect.y,
            width = row.labelRect.width,
            height = row.labelRect.height,
        } or nil,
        gapAfter = row.gapAfter,
        isGap = row.isGap,
        isMarker = row.isMarker,
        previewProxy = row.previewProxy,
        layoutOnly = row.layoutOnly,
        ownerKind = row.ownerKind,
        ownerId = row.ownerId,
        ownerFolderId = row.ownerFolderId,
    }
end

local function HideCol1PreviewBadges(frame)
    if frame and frame._cdcBadges then
        for _, badge in ipairs(frame._cdcBadges) do
            badge:Hide()
        end
    end
end

local function BuildCol1BasePreviewLayout()
    local renderedRows = CS.lastCol1RenderedRows
    local content = CS.col1Scroll and CS.col1Scroll.content
    if not (renderedRows and content and content:IsShown()) then
        return nil
    end

    local rows = {}
    for rowIndex, rowMeta in ipairs(renderedRows) do
        local widget = rowMeta.widget
        local frame = widget and widget.frame
        local x, y, width, height = GetRelativeRect(frame, content)
        if x and y then
            local label = widget and widget.label
            local image = widget and widget.image
            local isMarker = rowMeta.isMarker
            if isMarker == nil and rowMeta.keepVisibleDuringPreview then
                isMarker = true
            end

            rows[#rows + 1] = {
                key = table.concat({
                    tostring(rowMeta.kind or "row"),
                    tostring(rowMeta.id or rowIndex),
                    tostring(rowIndex),
                }, ":"),
                originalIndex = rowIndex,
                kind = rowMeta.kind,
                id = rowMeta.id,
                inFolder = rowMeta.inFolder,
                section = rowMeta.section,
                loadBucket = rowMeta.loadBucket,
                acceptsDrop = rowMeta.acceptsDrop,
                x = x,
                y = y,
                width = width,
                height = height,
                text = label and label.GetText and label:GetText() or "",
                textColor = (function()
                    if not (label and label.GetTextColor) then return nil end
                    local r, g, b = label:GetTextColor()
                    return {r or 1, g or 1, b or 1}
                end)(),
                icon = image and image.GetTexture and image:GetTexture() or nil,
                iconAlpha = image and image.GetAlpha and image:GetAlpha() or 1,
                iconRect = (function()
                    local ix, iy, iw, ih = GetRelativeRect(image, frame)
                    if ix then
                        return {x = ix, y = iy, width = iw, height = ih}
                    end
                end)(),
                labelRect = (function()
                    local lx, ly, lw, lh = GetRelativeRect(label, frame)
                    if lx then
                        return {x = lx, y = ly, width = lw, height = lh}
                    end
                end)(),
                gapAfter = 0,
                isMarker = isMarker,
                previewProxy = rowMeta.previewProxy ~= false,
                layoutOnly = rowMeta.layoutOnly and true or false,
                ownerKind = rowMeta.ownerKind,
                ownerId = rowMeta.ownerId,
                ownerFolderId = rowMeta.ownerFolderId,
            }
        end
    end

    for i, row in ipairs(rows) do
        local nextRow = rows[i + 1]
        if nextRow then
            row.gapAfter = math.max(0, nextRow.y - (row.y + row.height))
        else
            row.gapAfter = 0
        end
    end

    return {
        rows = rows,
        startOffset = rows[1] and rows[1].y or 0,
    }
end

local function FindCol1FolderBlockRange(rows, folderId)
    local headerIndex
    for i, row in ipairs(rows) do
        if row.kind == "folder" and row.id == folderId then
            headerIndex = i
            break
        end
    end
    if not headerIndex then
        return nil
    end

    local lastIndex = headerIndex
    for i = headerIndex + 1, #rows do
        local row = rows[i]
        if row.kind == "container" and row.inFolder == folderId then
            lastIndex = i
        elseif row.kind == "aux-block" and row.ownerFolderId == folderId then
            lastIndex = i
        else
            break
        end
    end
    return headerIndex, lastIndex
end

local function FindCol1BaseRowAtOrAfterOriginalIndex(rows, originalIndex)
    if not (rows and originalIndex) then
        return nil
    end
    for _, row in ipairs(rows) do
        if row.originalIndex >= originalIndex then
            return row
        end
    end
    return nil
end

local function FindCol1BaseRowBeforeOriginalIndex(rows, originalIndex)
    if not (rows and originalIndex) then
        return nil
    end
    local lastMatch
    for _, row in ipairs(rows) do
        if row.originalIndex < originalIndex then
            lastMatch = row
        else
            break
        end
    end
    return lastMatch
end

local function IsCol1AuxOwnedBySource(row, source)
    if not (row and row.kind == "aux-block" and source) then
        return false
    end
    if source.kind == "folder" then
        return row.ownerFolderId == source.sourceFolderId
    elseif source.kind == "multi-group" and source.sourceGroupIds then
        return row.ownerKind == "container" and source.sourceGroupIds[row.ownerId]
    else
        return row.ownerKind == "container" and row.ownerId == source.sourceGroupId
    end
end

local function BuildCol1DraggedRows(base, source)
    local movedRows = {}
    local movedIndexes = {}

    if source.kind == "folder" then
        local firstIndex, lastIndex = FindCol1FolderBlockRange(base.rows, source.sourceFolderId)
        if not firstIndex then
            return nil
        end
        for i = firstIndex, lastIndex do
            local row = base.rows[i]
            movedRows[#movedRows + 1] = row
            movedIndexes[row.originalIndex] = true
        end
    elseif source.kind == "multi-group" and source.sourceGroupIds then
        for _, row in ipairs(base.rows) do
            if (row.kind == "container" and source.sourceGroupIds[row.id])
                or IsCol1AuxOwnedBySource(row, source)
            then
                movedRows[#movedRows + 1] = row
                movedIndexes[row.originalIndex] = true
            end
        end
    else
        for _, row in ipairs(base.rows) do
            if row.kind == "container" and row.id == source.sourceGroupId then
                movedRows[#movedRows + 1] = row
                movedIndexes[row.originalIndex] = true
            elseif IsCol1AuxOwnedBySource(row, source) then
                movedRows[#movedRows + 1] = row
                movedIndexes[row.originalIndex] = true
            end
        end
    end

    if #movedRows == 0 then
        return nil
    end

    local gapHeight
    local contiguous = true
    for i = 2, #movedRows do
        if movedRows[i].originalIndex ~= (movedRows[i - 1].originalIndex + 1) then
            contiguous = false
            break
        end
    end
    if contiguous then
        local firstRow = movedRows[1]
        local lastRow = movedRows[#movedRows]
        gapHeight = math.max(
            PREVIEW_DEFAULT_ROW_HEIGHT,
            (lastRow.y + lastRow.height) - firstRow.y
        )
    else
        gapHeight = 0
        for i, row in ipairs(movedRows) do
            gapHeight = gapHeight + row.height
            if i < #movedRows then
                gapHeight = gapHeight + math.max(row.gapAfter or 0, 2)
            end
        end
    end

    local ghostRow
    local firstRow = movedRows[1]
    if source.kind == "multi-group" and #movedRows > 1 then
        local selectedCount = 0
        if source.sourceGroupIds then
            for _ in pairs(source.sourceGroupIds) do
                selectedCount = selectedCount + 1
            end
        end
        ghostRow = CopyCol1PreviewRow(firstRow)
        ghostRow.text = tostring(math.max(1, selectedCount)) .. " groups"
        ghostRow.height = math.max(firstRow.height, PREVIEW_DEFAULT_ROW_HEIGHT)
    else
        ghostRow = CopyCol1PreviewRow(firstRow)
    end

    return movedRows, movedIndexes, gapHeight, ghostRow
end

local IsUnloadedTopLevelDrop
local ShouldIncludeCol1TopLevelOrderRow

local function ResolveCol1GroupDropTargetFolderId(state, dropTarget)
    if not dropTarget then
        return nil
    end

    if dropTarget.folderBlockId then
        if dropTarget.action == "into-folder" then
            return dropTarget.folderBlockId
        end
        return nil
    end

    if dropTarget.action == "into-folder" then
        return dropTarget.targetFolderId
    end

    if dropTarget.action ~= "reorder-before" and dropTarget.action ~= "reorder-after" then
        return nil
    end

    local targetRow = dropTarget.targetRow
    if not targetRow or dropTarget.isBelowAll then
        return nil
    end

    if targetRow.kind == "container" and targetRow.inFolder then
        return targetRow.inFolder
    end

    return nil
end

local function FindCol1GroupSourcePosition(renderedRows, section, folderId, sourceContainerId, includeUnloaded)
    local pos = 0
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section then
            if folderId then
                if row.kind == "container" and row.inFolder == folderId then
                    pos = pos + 1
                    if row.id == sourceContainerId then
                        return pos
                    end
                end
            elseif ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
                pos = pos + 1
                if row.kind == "container" and row.id == sourceContainerId then
                    return pos
                end
            end
        end
    end
    return nil
end

local function BuildCol1GroupOrderItems(renderedRows, section, folderId, sourceContainerId, includeUnloaded)
    local orderItems = {}
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section then
            if folderId then
                if row.kind == "container" and row.inFolder == folderId and row.id ~= sourceContainerId then
                    table.insert(orderItems, row.id)
                end
            elseif ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
                if row.id ~= sourceContainerId then
                    table.insert(orderItems, { kind = row.kind, id = row.id })
                end
            end
        end
    end
    return orderItems
end

local function ResolveCol1GroupInsertPos(orderItems, dropTarget, folderId, includeUnloaded)
    local targetRow = dropTarget and dropTarget.targetRow
    if folderId then
        local insertPos = #orderItems + 1
        if targetRow and targetRow.kind == "container" then
            for idx, cid in ipairs(orderItems) do
                if cid == targetRow.id then
                    insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                    break
                end
            end
        end
        return insertPos
    end

    local insertPos = includeUnloaded and 1 or (#orderItems + 1)
    if targetRow and targetRow.kind ~= "unloaded-divider" then
        insertPos = #orderItems + 1
        for idx, item in ipairs(orderItems) do
            if item.kind == targetRow.kind and item.id == targetRow.id then
                insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                break
            end
        end
    end
    return insertPos
end

local function IsCol1GroupDropNoOp(state)
    local dropTarget = state and state.dropTarget
    if not dropTarget then
        return true
    end

    local targetRow = dropTarget.targetRow
    local targetSection = (targetRow and targetRow.section) or state.sourceSection
    local targetFolderId = ResolveCol1GroupDropTargetFolderId(state, dropTarget)

    if targetSection ~= state.sourceSection or targetFolderId ~= state.sourceFolderId then
        return false
    end

    if dropTarget.action ~= "into-folder"
        and dropTarget.action ~= "reorder-before"
        and dropTarget.action ~= "reorder-after"
    then
        return false
    end

    if targetRow and targetRow.kind == "container" and targetRow.id == state.sourceGroupId then
        return true
    end

    local renderedRows = state.col1RenderedRows
    if not renderedRows then
        return false
    end

    local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, targetFolderId)
    local sourcePos = FindCol1GroupSourcePosition(
        renderedRows,
        targetSection,
        targetFolderId,
        state.sourceGroupId,
        includeUnloaded
    )
    if not sourcePos then
        return false
    end

    local orderItems = BuildCol1GroupOrderItems(
        renderedRows,
        targetSection,
        targetFolderId,
        state.sourceGroupId,
        includeUnloaded
    )
    local insertPos = ResolveCol1GroupInsertPos(orderItems, dropTarget, targetFolderId, includeUnloaded)
    return insertPos == sourcePos
end

local function FindCol1FolderSourcePosition(renderedRows, section, sourceFolderId, includeUnloaded)
    local pos = 0
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section and ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
            pos = pos + 1
            if row.kind == "folder" and row.id == sourceFolderId then
                return pos
            end
        end
    end
    return nil
end

local function BuildCol1FolderOrderItems(renderedRows, section, sourceFolderId, includeUnloaded)
    local orderItems = {}
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section and ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
            if row.id ~= sourceFolderId then
                table.insert(orderItems, { kind = row.kind, id = row.id })
            end
        end
    end
    return orderItems
end

local function ResolveCol1FolderInsertPos(orderItems, dropTarget, targetRow, includeUnloaded)
    local insertPos = includeUnloaded and 1 or (#orderItems + 1)
    if targetRow and targetRow.kind ~= "unloaded-divider" then
        insertPos = #orderItems + 1
        for idx, item in ipairs(orderItems) do
            local targetKind = targetRow.kind
            local targetId = targetRow.id
            if targetRow.inFolder then
                targetKind = "folder"
                targetId = targetRow.inFolder
            end
            if item.kind == targetKind and item.id == targetId then
                insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                break
            end
        end
    end
    return insertPos
end

local function IsCol1FolderDropNoOp(state)
    local dropTarget = state and state.dropTarget
    if not dropTarget then
        return true
    end

    if dropTarget.action ~= "reorder-before" and dropTarget.action ~= "reorder-after" then
        return false
    end

    local targetRow = dropTarget.targetRow
    local targetSection = (targetRow and targetRow.section) or state.sourceSection
    if targetSection ~= state.sourceSection then
        return false
    end

    if targetRow and targetRow.kind == "folder" and targetRow.id == state.sourceFolderId then
        return true
    end

    local renderedRows = state.col1RenderedRows
    if not renderedRows then
        return false
    end

    local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, nil)
    local sourcePos = FindCol1FolderSourcePosition(renderedRows, targetSection, state.sourceFolderId, includeUnloaded)
    if not sourcePos then
        return false
    end

    local orderItems = BuildCol1FolderOrderItems(renderedRows, targetSection, state.sourceFolderId, includeUnloaded)
    local insertPos = ResolveCol1FolderInsertPos(orderItems, dropTarget, targetRow, includeUnloaded)
    return insertPos == sourcePos
end

local function ResolveCol1PreviewAnchor(base, source, dropTarget)
    if not dropTarget then
        return nil, nil
    end
    if dropTarget.isBelowAll then
        return #base.rows + 1, base.rows[#base.rows]
    end

    local targetRow = dropTarget.targetRow
    local targetIndex = dropTarget.rowIndex or 1

    if targetRow and targetRow.kind == "folder" then
        local firstIndex, lastIndex = FindCol1FolderBlockRange(base.rows, targetRow.id)
        if firstIndex then
            if dropTarget.action == "reorder-before" then
                return base.rows[firstIndex].originalIndex, base.rows[firstIndex]
            end
            return base.rows[lastIndex].originalIndex + 1, base.rows[firstIndex]
        end
    end

    if targetRow and targetRow.kind == "unloaded-divider" then
        return targetIndex, FindCol1BaseRowAtOrAfterOriginalIndex(base.rows, targetIndex) or FindCol1BaseRowBeforeOriginalIndex(base.rows, targetIndex)
    end

    if source.kind == "folder" and targetRow and targetRow.inFolder then
        local firstIndex, lastIndex = FindCol1FolderBlockRange(base.rows, targetRow.inFolder)
        if firstIndex then
            if dropTarget.action == "reorder-before" then
                return base.rows[firstIndex].originalIndex, base.rows[firstIndex]
            end
            return base.rows[lastIndex].originalIndex + 1, base.rows[firstIndex]
        end
    end

    if dropTarget.action == "reorder-before" then
        return targetIndex, base.rows[targetIndex]
    end
    return targetIndex + 1, base.rows[targetIndex]
end

local function IsExternalFolderChildTarget(rowMeta, sourceKind, sourceFolderId)
    if not (rowMeta and rowMeta.kind == "container" and rowMeta.inFolder) then
        return false
    end
    if sourceKind ~= "group" and sourceKind ~= "folder-group" then
        return false
    end
    return sourceFolderId ~= rowMeta.inFolder
end

local function BuildCol1PreviewModel(source)
    if not source or not source.dropTarget then
        return nil
    end

    local base = BuildCol1BasePreviewLayout()
    if not base or not base.rows or #base.rows == 0 then
        return nil
    end

    local movedRows, movedIndexes, gapHeight, ghostRow = BuildCol1DraggedRows(base, source)
    if not movedRows then
        return nil
    end

    local rows = {}
    for _, row in ipairs(base.rows) do
        if not movedIndexes[row.originalIndex]
            and not IsCol1AuxOwnedBySource(row, source)
        then
            rows[#rows + 1] = CopyCol1PreviewRow(row)
        end
    end

    local highlightRowKey
    local highlightFolderId
    local folderGapId
    if source.dropTarget.action == "into-folder" then
        highlightFolderId = source.dropTarget.folderBlockId or source.dropTarget.targetFolderId
        if source.kind ~= "folder" then
            folderGapId = highlightFolderId
        end
        if not highlightFolderId then
            local targetOriginalIndex = source.dropTarget.rowIndex
            local targetRow = FindCol1BaseRowAtOrAfterOriginalIndex(rows, targetOriginalIndex)
            highlightRowKey = targetRow and targetRow.key or nil
        else
            local firstIndex, lastIndex = FindCol1FolderBlockRange(rows, highlightFolderId)
            if firstIndex and lastIndex then
                local template = rows[lastIndex] or rows[firstIndex] or movedRows[1]
                table.insert(rows, lastIndex + 1, {
                    key = "gap:folder:" .. tostring(highlightFolderId) .. ":append",
                    isGap = true,
                    x = (template and template.x) or PREVIEW_PANEL_INSET,
                    width = (template and template.width) or math.max(120, ghostRow.width or 160),
                    height = gapHeight,
                    gapAfter = (template and template.gapAfter) or 0,
                    folderAccentId = source.kind ~= "folder" and highlightFolderId or nil,
                })
            end
        end
    else
        local anchorOriginalIndex, gapTemplate = ResolveCol1PreviewAnchor(base, source, source.dropTarget)
        if not anchorOriginalIndex then
            return nil
        end

        local insertIndex = #rows + 1
        local targetRow = source.dropTarget.targetRow
        for i, row in ipairs(rows) do
            if row.originalIndex >= anchorOriginalIndex then
                insertIndex = i
                break
            end
        end

        if targetRow and source.kind ~= "folder" then
            if targetRow.kind == "container" and targetRow.inFolder then
                folderGapId = targetRow.inFolder
            end
        end
        local template = gapTemplate or movedRows[1]
        table.insert(rows, insertIndex, {
            key = "gap:" .. tostring(source.kind) .. ":" .. tostring(insertIndex),
            isGap = true,
            x = (template and template.x) or PREVIEW_PANEL_INSET,
            width = (template and template.width) or math.max(120, ghostRow.width or 160),
            height = gapHeight,
            gapAfter = (template and template.gapAfter) or 0,
            folderAccentId = folderGapId,
        })
    end

    local currentY = base.startOffset
    for _, row in ipairs(rows) do
        if row.layoutOnly then
            currentY = math.max(currentY, row.y)
            row.previewY = row.y
            currentY = math.max(currentY, row.y + row.height + (row.gapAfter or 0))
        else
            row.previewY = currentY
            currentY = currentY + row.height + (row.gapAfter or 0)
        end
    end

    return {
        mode = PREVIEW_MODE_COL1_LIST,
        rows = rows,
        draggedRow = ghostRow,
        highlightRowKey = highlightRowKey,
        highlightFolderId = highlightFolderId,
        suppressedAccentFolderId = source.kind == "folder" and source.sourceFolderId or nil,
    }
end

local function AcquireCol1PreviewRowFrame(preview, key)
    preview.rowByKey = preview.rowByKey or {}
    local rowProxy = preview.rowByKey[key]
    if rowProxy then
        rowProxy.used = true
        return rowProxy
    end

    local frame = CreateFrame("Frame", nil, preview.root, "BackdropTemplate")
    frame:Hide()
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(0, 0, 0, 0)
    frame:SetBackdropBorderColor(0, 0, 0, 0)

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

    local leftLine = frame:CreateTexture(nil, "ARTWORK")
    leftLine:SetHeight(1)
    leftLine:Hide()
    frame._cdcLeftLine = leftLine

    local rightLine = frame:CreateTexture(nil, "ARTWORK")
    rightLine:SetHeight(1)
    rightLine:Hide()
    frame._cdcRightLine = rightLine

    rowProxy = {
        frame = frame,
        used = true,
    }
    preview.rowByKey[key] = rowProxy
    preview.rows[#preview.rows + 1] = rowProxy
    return rowProxy
end

local function AcquireCol1PreviewAccentBar(preview, index)
    preview.accentBars = preview.accentBars or {}
    local bar = preview.accentBars[index]
    if not bar then
        bar = preview.root:CreateTexture(nil, "ARTWORK")
        preview.accentBars[index] = bar
    end
    return bar
end

local function RenderCol1PreviewAccentBars(preview, model)
    local classColor = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    local suppressedAccentFolderId = model and model.suppressedAccentFolderId
    local ranges = {}
    if classColor and model and model.rows then
        for _, row in ipairs(model.rows) do
            local accentFolderId = nil
            if row.kind == "container" and row.inFolder then
                accentFolderId = row.inFolder
            elseif row.isGap and row.folderAccentId then
                accentFolderId = row.folderAccentId
            end

            if accentFolderId
                and accentFolderId ~= suppressedAccentFolderId
                and not row.layoutOnly
            then
                local range = ranges[accentFolderId]
                if not range then
                    range = {
                        x = row.x,
                        top = row.previewY,
                        bottom = row.previewY + row.height,
                    }
                    ranges[accentFolderId] = range
                else
                    range.x = math.min(range.x, row.x)
                    range.top = math.min(range.top, row.previewY)
                    range.bottom = math.max(range.bottom, row.previewY + row.height)
                end
            end
        end
    end

    local index = 0
    for _, range in pairs(ranges) do
        index = index + 1
        local bar = AcquireCol1PreviewAccentBar(preview, index)
        bar:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.8)
        bar:SetWidth(3)
        bar:ClearAllPoints()
        bar:SetPoint("TOPLEFT", preview.root, "TOPLEFT", range.x, -range.top)
        bar:SetPoint("BOTTOMLEFT", preview.root, "TOPLEFT", range.x, -range.bottom)
        bar:Show()
    end

    for i = index + 1, #(preview.accentBars or {}) do
        preview.accentBars[i]:Hide()
    end
end

local function SetDraggedFolderAccentBarHidden(source, hidden)
    if not (source and source.kind == "folder" and source.sourceFolderId) then
        return
    end

    local preview = EnsureCol1PreviewHost()
    if not preview then
        return
    end

    for _, region in ipairs(CS.folderAccentBars or {}) do
        if region and region._cdcFolderId == source.sourceFolderId and region.SetAlpha then
            if hidden then
                if preview.hiddenRegions[region] == nil then
                    preview.hiddenRegions[region] = region:GetAlpha()
                    region:SetAlpha(0)
                end
            else
                local alpha = preview.hiddenRegions[region]
                if alpha ~= nil then
                    region:SetAlpha(alpha)
                    preview.hiddenRegions[region] = nil
                end
            end
        end
    end
end

local function SetCol1BaseFramesHidden(hidden, source)
    local preview = hidden and EnsureCol1PreviewHost() or CS.col1Preview
    local content = CS.col1Scroll and CS.col1Scroll.content
    if not (preview and content) then
        return
    end

    if hidden then
        for _, rowMeta in ipairs(CS.lastCol1RenderedRows or {}) do
            local frame = rowMeta.widget and rowMeta.widget.frame
            if frame and frame ~= preview.root and preview.hiddenFrames[frame] == nil then
                local shouldHide = rowMeta.previewProxy ~= false
                if rowMeta.kind == "aux-block" then
                    shouldHide = IsCol1AuxOwnedBySource(rowMeta, source)
                end
                if shouldHide then
                    preview.hiddenFrames[frame] = frame:GetAlpha()
                    frame:SetAlpha(0)
                end
            end
        end
        for _, region in ipairs(CS.folderAccentBars or {}) do
            if region and region.SetAlpha and preview.hiddenRegions[region] == nil then
                preview.hiddenRegions[region] = region:GetAlpha()
                region:SetAlpha(0)
            end
        end
    else
        for frame, alpha in pairs(preview.hiddenFrames) do
            if frame and frame.SetAlpha then
                frame:SetAlpha(alpha)
            end
            preview.hiddenFrames[frame] = nil
        end
        for region, alpha in pairs(preview.hiddenRegions or {}) do
            if region and region.SetAlpha then
                region:SetAlpha(alpha)
            end
            preview.hiddenRegions[region] = nil
        end
    end
end

local function UpdateCol1Ghost(preview, model)
    if not (preview and preview.ghost) then
        return
    end

    local row = model and model.draggedRow
    preview.ghostActive = false
    if not row then
        HideCol1PreviewBadges(preview.ghost)
        preview.ghost:Hide()
        return
    end

    preview.ghost:SetBackdropColor(0, 0, 0, 0)
    preview.ghost:SetBackdropBorderColor(0, 0, 0, 0)
    preview.ghost:SetSize(row.width or 160, row.height or PREVIEW_DEFAULT_ROW_HEIGHT)
    preview.ghost.label:SetText(row.text or "")
    if row.textColor then
        preview.ghost.label:SetTextColor(row.textColor[1] or 1, row.textColor[2] or 1, row.textColor[3] or 1)
    else
        preview.ghost.label:SetTextColor(1, 1, 1)
    end

    if row.icon and (row.iconAlpha or 1) > 0.05 then
        preview.ghost.icon:SetTexture(row.icon)
        preview.ghost.icon:SetAlpha(row.iconAlpha or 1)
        preview.ghost.icon:Show()
        if not ApplyRelativeRect(preview.ghost.icon, preview.ghost, row.iconRect) then
            preview.ghost.icon:ClearAllPoints()
            preview.ghost.icon:SetPoint("LEFT", preview.ghost, "LEFT", 0, 0)
            preview.ghost.icon:SetSize(
                (row.iconRect and row.iconRect.width) or 32,
                (row.iconRect and row.iconRect.height) or 32
            )
        end
    else
        preview.ghost.icon:Hide()
    end

    if not ApplyRelativeRect(preview.ghost.label, preview.ghost, row.labelRect) then
        preview.ghost.label:ClearAllPoints()
        if preview.ghost.icon:IsShown() then
            preview.ghost.label:SetPoint("LEFT", preview.ghost.icon, "RIGHT", 8, 0)
        else
            preview.ghost.label:SetPoint("LEFT", preview.ghost, "LEFT", 8, 0)
        end
        preview.ghost.label:SetPoint("RIGHT", preview.ghost, "RIGHT", -PREVIEW_ROW_TEXT_RIGHT_PAD, 0)
    end

    HideCol1PreviewBadges(preview.ghost)
    if row.kind == "container" then
        local db = CooldownCompanion.db.profile
        local container = db and db.groupContainers and db.groupContainers[row.id]
        if container then
            SetupGroupRowIndicators({ frame = preview.ghost }, container)
        end
    elseif row.kind == "folder" then
        local db = CooldownCompanion.db.profile
        local folder = db and db.folders and db.folders[row.id]
        if folder then
            SetupFolderRowIndicators({ frame = preview.ghost }, folder)
        end
    end

    preview.ghost:Show()
    preview.ghostActive = true
end

local ClearCol1AnimatedPreview
local FindCol1SectionDividerTarget

local function SectionHasLoadedCol1Rows(renderedRows, section)
    for _, row in ipairs(renderedRows or {}) do
        if row.section == section
            and row.loadBucket == "loaded"
            and (row.kind == "container" or row.kind == "folder")
        then
            return true
        end
    end
    return false
end

local function ShouldAnimateCol1PreviewForDrop(sourceLoadBucket, dropTarget, renderedRows)
    if not dropTarget then
        return false
    end

    if sourceLoadBucket == "mixed" or sourceLoadBucket == "unloaded" then
        return true
    end

    local targetRow = dropTarget.targetRow
    if sourceLoadBucket == "loaded"
        and targetRow
        and targetRow.kind == "unloaded-divider"
        and not SectionHasLoadedCol1Rows(renderedRows, targetRow.section)
    then
        return true
    end

    if targetRow and (targetRow.kind == "unloaded-divider" or targetRow.loadBucket == "unloaded") then
        return false
    end

    return true
end

local function ShouldShowCol1StaticReorderIndicator(sourceLoadBucket, dropTarget)
    if not dropTarget then
        return false
    end

    if dropTarget.action ~= "reorder-before" and dropTarget.action ~= "reorder-after" then
        return false
    end

    if sourceLoadBucket == "loaded" then
        return false
    end

    return true
end

local function ResolveCol1LoadedUnloadedPlaceholderTarget(renderedRows, sourceLoadBucket, dropTarget)
    if sourceLoadBucket ~= "loaded" or not dropTarget then
        return nil
    end

    if dropTarget.action ~= "reorder-before" and dropTarget.action ~= "reorder-after" then
        return nil
    end

    local targetRow = dropTarget.targetRow
    if not targetRow or (targetRow.kind ~= "unloaded-divider" and targetRow.loadBucket ~= "unloaded") then
        return nil
    end

    return FindCol1SectionDividerTarget(renderedRows, targetRow.section)
end

local function RenderCol1AnimatedPreview(source)
    local model = BuildCol1PreviewModel(source)
    if not model or not model.rows or #model.rows == 0 then
        ClearCol1AnimatedPreview()
        return false
    end

    local preview = EnsureCol1PreviewHost()
    if not preview then
        return false
    end

    preview.mode = model.mode
    SetCol1BaseFramesHidden(true, source)
    preview.root:Show()

    for _, rowProxy in ipairs(preview.rows) do
        rowProxy.used = false
    end

    for _, row in ipairs(model.rows) do
        if not row.isGap and not row.layoutOnly then
            local rowProxy = AcquireCol1PreviewRowFrame(preview, row.key or tostring(row.originalIndex))
            local frame = rowProxy.frame
            local isMarker = row.isMarker and true or false
            if model.highlightRowKey and model.highlightRowKey == row.key then
                frame:SetBackdropColor(0.30, 0.52, 0.18, 0.18)
                frame:SetBackdropBorderColor(0.54, 0.78, 0.28, 0.95)
            else
                frame:SetBackdropColor(0, 0, 0, 0)
                frame:SetBackdropBorderColor(0, 0, 0, 0)
            end
            HideCol1PreviewBadges(frame)

            if not isMarker and row.icon and (row.iconAlpha or 1) > 0.05 then
                frame._cdcIcon:SetTexture(row.icon)
                frame._cdcIcon:SetAlpha(row.iconAlpha or 1)
                frame._cdcIcon:Show()
                if not ApplyRelativeRect(frame._cdcIcon, frame, row.iconRect) then
                    frame._cdcIcon:ClearAllPoints()
                    frame._cdcIcon:SetPoint("LEFT", frame, "LEFT", 0, 0)
                    frame._cdcIcon:SetSize(32, 32)
                end
            else
                frame._cdcIcon:Hide()
            end

            if isMarker then
                ApplyColumn1MarkerAppearance({
                    frame = frame,
                    label = frame._cdcLabel,
                    _cdcLabel = frame._cdcLabel,
                    _cdcIcon = frame._cdcIcon,
                }, {
                    text = row.text,
                    color = row.textColor,
                })
            else
                frame._cdcLabel:SetText(row.text or "")
                if row.textColor then
                    frame._cdcLabel:SetTextColor(row.textColor[1] or 1, row.textColor[2] or 1, row.textColor[3] or 1)
                else
                    frame._cdcLabel:SetTextColor(1, 1, 1)
                end
                if not ApplyRelativeRect(frame._cdcLabel, frame, row.labelRect) then
                    frame._cdcLabel:ClearAllPoints()
                    if frame._cdcIcon:IsShown() then
                        frame._cdcLabel:SetPoint("LEFT", frame._cdcIcon, "RIGHT", 8, 0)
                    else
                        frame._cdcLabel:SetPoint("LEFT", frame, "LEFT", 0, 0)
                    end
                    frame._cdcLabel:SetPoint("RIGHT", frame, "RIGHT", -PREVIEW_ROW_TEXT_RIGHT_PAD, 0)
                end
                frame._cdcLeftLine:Hide()
                frame._cdcRightLine:Hide()
                if row.kind == "container" then
                    local db = CooldownCompanion.db.profile
                    local container = db and db.groupContainers and db.groupContainers[row.id]
                    if container then
                        SetupGroupRowIndicators({ frame = frame }, container)
                    end
                elseif row.kind == "folder" then
                    local db = CooldownCompanion.db.profile
                    local folder = db and db.folders and db.folders[row.id]
                    if folder then
                        SetupFolderRowIndicators({ frame = frame }, folder)
                    end
                end
            end

            QueuePreviewTween(
                preview,
                frame,
                row.x,
                row.previewY,
                row.width,
                row.height,
                1,
                PREVIEW_ANIM_DURATION
            )
            frame:Show()
        end
    end

    for _, rowProxy in ipairs(preview.rows) do
        if not rowProxy.used then
            rowProxy.frame:Hide()
        end
    end

    RenderCol1PreviewAccentBars(preview, model)
    UpdateCol1Ghost(preview, model)
    preview.root:SetScript("OnUpdate", function()
        TickCol2Preview(preview)
    end)
    return true
end

ClearCol1AnimatedPreview = function()
    SetCol1BaseFramesHidden(false)
    SetDraggedFolderAccentBarHidden(CS.dragState, false)
    ClearCol1PreviewHost()
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

local function IsPanelReorderNoOp(sourcePanelId, dropIndex, panelDropTargets)
    if not (sourcePanelId and dropIndex and panelDropTargets) then
        return true
    end

    local sourceIndex
    for i, entry in ipairs(panelDropTargets) do
        if entry.panelId == sourcePanelId then
            sourceIndex = i
            break
        end
    end
    if not sourceIndex then
        return true
    end

    if dropIndex > sourceIndex then
        dropIndex = dropIndex - 1
    end

    return sourceIndex == dropIndex
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
local function GetCol1DropFrame(rowMeta)
    return rowMeta and rowMeta.widget and rowMeta.widget.frame
end

local function GetCol1HorizontalBounds(scrollWidget, renderedRows)
    local content = scrollWidget and scrollWidget.content
    if content and content.IsShown and content:IsShown() then
        local left, right = content:GetLeft(), content:GetRight()
        if left and right then
            return left, right
        end
    end

    for _, rowMeta in ipairs(renderedRows or {}) do
        local frame = GetCol1DropFrame(rowMeta)
        if frame and frame:IsShown() then
            local left, right = frame:GetLeft(), frame:GetRight()
            if left and right then
                return left, right
            end
        end
    end

    return nil, nil
end

local function IsCursorWithinHorizontalBounds(cursorX, left, right, pad)
    if not (cursorX and left and right) then
        return false
    end
    pad = pad or 0
    return cursorX >= (left + pad) and cursorX <= (right - pad)
end

local function BuildCol1DropResult(action, rowIndex, rowMeta, extra)
    local frame = GetCol1DropFrame(rowMeta)
    if not (rowMeta and frame and frame:IsShown()) then
        return nil
    end

    local result = {
        action = action,
        rowIndex = rowIndex,
        targetRow = rowMeta,
        anchorFrame = frame,
    }
    if extra then
        for key, value in pairs(extra) do
            result[key] = value
        end
    end
    return result
end

local function GetCol1FolderBlockIdForRow(rowMeta, sourceKind)
    if sourceKind ~= "group" and sourceKind ~= "folder-group" then
        return nil
    end
    if not rowMeta then
        return nil
    end

    if rowMeta.kind == "folder" then
        return rowMeta.id
    end
    if rowMeta.kind == "container" and rowMeta.inFolder then
        return rowMeta.inFolder
    end
    if rowMeta.kind == "aux-block" and rowMeta.ownerFolderId then
        return rowMeta.ownerFolderId
    end

    return nil
end

local function GetCol1FolderBlockInfo(renderedRows, folderId)
    if not folderId then
        return nil
    end

    local firstIndex, lastIndex = FindCol1FolderBlockRange(renderedRows or {}, folderId)
    if not firstIndex or not lastIndex then
        return nil
    end

    local firstRow = renderedRows[firstIndex]
    local lastRow = renderedRows[lastIndex]
    local firstFrame = GetCol1DropFrame(firstRow)
    local lastFrame = GetCol1DropFrame(lastRow)
    if not (firstRow and lastRow and firstFrame and lastFrame and firstFrame:IsShown() and lastFrame:IsShown()) then
        return nil
    end

    local top = firstFrame:GetTop()
    local bottom = lastFrame:GetBottom()
    if not (top and bottom) then
        return nil
    end

    return {
        folderId = folderId,
        headerIndex = firstIndex,
        firstIndex = firstIndex,
        lastIndex = lastIndex,
        headerRow = firstRow,
        firstRow = firstRow,
        lastRow = lastRow,
        firstFrame = firstFrame,
        lastFrame = lastFrame,
        top = top,
        bottom = bottom,
    }
end

local function GetCol1FolderBlockEdgeInset(frame)
    local height = frame and frame:GetHeight()
    if not height or height <= 0 then
        return 8
    end
    return math.min(14, math.max(8, height * 0.35))
end

local function BuildCol1FolderBlockDropResult(renderedRows, folderId, action, extra)
    local blockInfo = GetCol1FolderBlockInfo(renderedRows, folderId)
    if not blockInfo then
        return nil
    end

    local result = BuildCol1DropResult(action, blockInfo.headerIndex, blockInfo.headerRow, {
        targetFolderId = folderId,
        folderBlockId = folderId,
        folderBlockFirstRow = blockInfo.firstRow,
        folderBlockLastRow = blockInfo.lastRow,
        folderBlockFirstIndex = blockInfo.firstIndex,
        folderBlockLastIndex = blockInfo.lastIndex,
        folderBlockPosition = action == "into-folder" and "inside"
            or (action == "reorder-before" and "before" or "after"),
    })
    if not result then
        return nil
    end

    result.anchorFrame = action == "reorder-after" and blockInfo.lastFrame or blockInfo.firstFrame
    if extra then
        for key, value in pairs(extra) do
            result[key] = value
        end
    end
    return result
end

local function BuildCol1FolderReorderBlockTarget(renderedRows, folderId, action, extra)
    local blockInfo = GetCol1FolderBlockInfo(renderedRows, folderId)
    if not blockInfo then
        return nil
    end

    local result = BuildCol1DropResult(action, blockInfo.headerIndex, blockInfo.headerRow, {
        folderBlockId = folderId,
        folderBlockFirstRow = blockInfo.firstRow,
        folderBlockLastRow = blockInfo.lastRow,
        folderBlockFirstIndex = blockInfo.firstIndex,
        folderBlockLastIndex = blockInfo.lastIndex,
        folderBlockPosition = action == "reorder-before" and "before" or "after",
    })
    if not result then
        return nil
    end

    result.anchorFrame = action == "reorder-after" and blockInfo.lastFrame or blockInfo.firstFrame
    if extra then
        for key, value in pairs(extra) do
            result[key] = value
        end
    end
    return result
end

local function FindCol1FolderDropTarget(renderedRows, section, folderId)
    if not folderId then
        return nil
    end

    for _, candidate in ipairs(renderedRows or {}) do
        if candidate.section == section and candidate.kind == "folder" and candidate.id == folderId then
            return BuildCol1FolderBlockDropResult(renderedRows, folderId, "into-folder")
        end
    end

    return nil
end

local function ResolveCol1FolderBlockDropTarget(renderedRows, rowMeta, sourceKind, action, extra)
    local folderId = GetCol1FolderBlockIdForRow(rowMeta, sourceKind)
    if not folderId then
        return nil
    end

    return BuildCol1FolderBlockDropResult(renderedRows, folderId, action or "into-folder", extra)
end

local ResolveCol1FolderBlockBoundaryTarget

local function ResolveCol1FolderBlockHoverTarget(
    renderedRows,
    folderId,
    cursorY,
    sourceKind,
    sourceSection,
    sourceFolderId,
    sourceLoadBucket
)
    local blockInfo = GetCol1FolderBlockInfo(renderedRows, folderId)
    if not blockInfo or not cursorY or cursorY > blockInfo.top or cursorY < blockInfo.bottom then
        return nil
    end

    local topInset = GetCol1FolderBlockEdgeInset(blockInfo.firstFrame)
    if cursorY >= (blockInfo.top - topInset) then
        return ResolveCol1FolderBlockBoundaryTarget(
            renderedRows,
            blockInfo.headerRow,
            sourceKind,
            sourceSection,
            sourceLoadBucket,
            "reorder-before"
        )
    end

    local bottomInset = GetCol1FolderBlockEdgeInset(blockInfo.lastFrame)
    if cursorY <= (blockInfo.bottom + bottomInset) then
        return ResolveCol1FolderBlockBoundaryTarget(
            renderedRows,
            blockInfo.headerRow,
            sourceKind,
            sourceSection,
            sourceLoadBucket,
            "reorder-after"
        )
    end

    if sourceFolderId and sourceFolderId == folderId then
        return nil
    end

    return BuildCol1FolderBlockDropResult(renderedRows, folderId, "into-folder")
end

local function ResolveCol1FolderDragBlockHoverTarget(renderedRows, folderId, cursorY, previousDropTarget)
    local blockInfo = GetCol1FolderBlockInfo(renderedRows, folderId)
    if not blockInfo or not cursorY or cursorY > blockInfo.top or cursorY < blockInfo.bottom then
        return nil
    end

    local mid = (blockInfo.top + blockInfo.bottom) / 2
    local action = cursorY > mid and "reorder-before" or "reorder-after"
    local hysteresis = math.min(18, math.max(8, (blockInfo.top - blockInfo.bottom) * 0.12))
    if previousDropTarget
        and previousDropTarget.folderBlockId == folderId
        and (previousDropTarget.action == "reorder-before" or previousDropTarget.action == "reorder-after")
        and math.abs(cursorY - mid) <= hysteresis
    then
        action = previousDropTarget.action
    end
    return BuildCol1FolderReorderBlockTarget(renderedRows, folderId, action)
end

FindCol1SectionDividerTarget = function(renderedRows, section)
    for i, rowMeta in ipairs(renderedRows or {}) do
        if rowMeta.section == section and rowMeta.kind == "unloaded-divider" then
            return BuildCol1DropResult("reorder-before", i, rowMeta)
        end
    end
    return nil
end

local function FindFirstCol1UnloadedTargetInSection(renderedRows, section, startIndex)
    for i = startIndex or 1, #(renderedRows or {}) do
        local rowMeta = renderedRows[i]
        if rowMeta.section ~= section then
            if rowMeta.section then
                break
            end
        elseif rowMeta.loadBucket == "unloaded" and (rowMeta.kind == "folder" or rowMeta.kind == "container") then
            return BuildCol1DropResult("reorder-before", i, rowMeta)
        end
    end
    return nil
end

local function FindLastCol1UnloadedTargetInSection(renderedRows, section, startIndex)
    for i = startIndex or #(renderedRows or {}), 1, -1 do
        local rowMeta = renderedRows[i]
        if rowMeta.section ~= section then
            if rowMeta.section then
                break
            end
        elseif rowMeta.loadBucket == "unloaded" and (rowMeta.kind == "folder" or rowMeta.kind == "container") then
            return BuildCol1DropResult("reorder-after", i, rowMeta)
        end
    end
    return nil
end

local function ResolveCol1UnloadedSectionTarget(renderedRows, section, startIndex, preferLast)
    if preferLast then
        return FindLastCol1UnloadedTargetInSection(renderedRows, section, startIndex)
            or FindCol1SectionDividerTarget(renderedRows, section)
    end
    return FindFirstCol1UnloadedTargetInSection(renderedRows, section, startIndex)
        or FindCol1SectionDividerTarget(renderedRows, section)
end

local function FindFirstCol1DropTargetInSection(renderedRows, section, startIndex)
    for i = startIndex or 1, #(renderedRows or {}) do
        local rowMeta = renderedRows[i]
        if rowMeta.section ~= section then
            if rowMeta.section then
                break
            end
        elseif rowMeta.kind == "unloaded-divider" then
            return BuildCol1DropResult("reorder-before", i, rowMeta)
        elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
            return BuildCol1DropResult("reorder-before", i, rowMeta)
        end
    end
    return nil
end

local function FindLastCol1DropTargetInSection(renderedRows, section, startIndex)
    for i = startIndex or #(renderedRows or {}), 1, -1 do
        local rowMeta = renderedRows[i]
        if rowMeta.section ~= section then
            if rowMeta.section then
                break
            end
        elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
            return BuildCol1DropResult("reorder-after", i, rowMeta)
        end
    end
    return nil
end

local function ResolveCol1AuxBlockTarget(renderedRows, rowIndex, rowMeta, sourceKind, sourceSection, sourceFolderId, sourceLoadBucket)
    if not rowMeta then
        return nil
    end
    if sourceLoadBucket == "unloaded" then
        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, rowIndex + 1)
    end
    if rowMeta.ownerFolderId
        and (sourceKind == "group" or sourceKind == "folder-group")
    then
        return BuildCol1FolderBlockDropResult(renderedRows, rowMeta.ownerFolderId, "into-folder")
    end
    local nextTarget = FindFirstCol1DropTargetInSection(renderedRows, rowMeta.section, rowIndex + 1)
    if nextTarget then
        return nextTarget
    end
    return FindLastCol1DropTargetInSection(renderedRows, rowMeta.section, rowIndex - 1)
end

local function IsCol1UnloadedDragSource(sourceLoadBucket)
    return sourceLoadBucket == "unloaded"
end

local function IsCol1MixedDragSource(sourceLoadBucket)
    return sourceLoadBucket == "mixed"
end

local function ResolveCol1MixedSectionTarget(renderedRows, rowMeta, rowIndex, sourceSection, action)
    if not rowMeta then
        return nil
    end

    local targetSection = rowMeta.section
    if not targetSection then
        return nil
    end

    if targetSection == sourceSection then
        if rowMeta.kind == "section-header" then
            return FindFirstCol1DropTargetInSection(renderedRows, targetSection, rowIndex)
        end
        if rowMeta.kind == "unloaded-divider" then
            return FindCol1SectionDividerTarget(renderedRows, targetSection)
        end
        if rowMeta.kind == "phantom"
            or rowMeta.kind == "folder"
            or rowMeta.loadBucket == "unloaded"
            or rowMeta.acceptsDrop
        then
            return BuildCol1DropResult(action or "reorder-before", rowIndex, rowMeta)
        end
        return nil
    end

    if rowMeta.kind == "phantom" then
        return BuildCol1DropResult("reorder-before", rowIndex, rowMeta)
    end

    if rowMeta.kind == "unloaded-divider" then
        return FindCol1SectionDividerTarget(renderedRows, targetSection)
    end

    return FindFirstCol1DropTargetInSection(renderedRows, targetSection, rowIndex)
        or FindCol1SectionDividerTarget(renderedRows, targetSection)
end

ResolveCol1FolderBlockBoundaryTarget = function(renderedRows, rowMeta, sourceKind, sourceSection, sourceLoadBucket, action, extra)
    local folderBlockTarget = ResolveCol1FolderBlockDropTarget(renderedRows, rowMeta, sourceKind, action, extra)
    if not folderBlockTarget then
        return nil
    end

    local targetRow = folderBlockTarget.targetRow
    if not targetRow then
        return folderBlockTarget
    end

    if IsCol1MixedDragSource(sourceLoadBucket) then
        return ResolveCol1MixedSectionTarget(
            renderedRows,
            targetRow,
            folderBlockTarget.rowIndex,
            sourceSection,
            action
        )
    end

    if IsCol1UnloadedDragSource(sourceLoadBucket) then
        if targetRow.loadBucket ~= "unloaded" then
            local startIndex = action == "reorder-after"
                and (folderBlockTarget.folderBlockLastIndex or folderBlockTarget.rowIndex)
                or folderBlockTarget.rowIndex
            return ResolveCol1UnloadedSectionTarget(
                renderedRows,
                targetRow.section,
                startIndex,
                action == "reorder-after"
            )
        end
        return folderBlockTarget
    end

    if targetRow.loadBucket == "unloaded" then
        return FindCol1SectionDividerTarget(renderedRows, targetRow.section)
    end

    return folderBlockTarget
end

local function ResolvePreviousFolderBlockBoundaryTarget(renderedRows, rowIndex, sourceKind, sourceSection, sourceLoadBucket, action, extra)
    local previousRow = rowIndex and renderedRows and renderedRows[rowIndex - 1]
    if not previousRow then
        return nil
    end

    local previousFolderId = GetCol1FolderBlockIdForRow(previousRow, sourceKind)
    if not previousFolderId then
        return nil
    end

    local currentFolderId = GetCol1FolderBlockIdForRow(renderedRows[rowIndex], sourceKind)
    if currentFolderId and currentFolderId == previousFolderId then
        return nil
    end

    return ResolveCol1FolderBlockBoundaryTarget(
        renderedRows,
        previousRow,
        sourceKind,
        sourceSection,
        sourceLoadBucket,
        action,
        extra
    )
end

local function GetCol1DropTarget(cursorX, cursorY, scrollWidget, renderedRows, sourceKind, sourceSection, sourceFolderId, sourceLoadBucket, previousDropTarget)
    if not renderedRows or #renderedRows == 0 then return nil end
    local sourceIsMixed = IsCol1MixedDragSource(sourceLoadBucket)
    local sourceIsUnloaded = IsCol1UnloadedDragSource(sourceLoadBucket)
    local contentLeft, contentRight = GetCol1HorizontalBounds(scrollWidget, renderedRows)
    if not IsCursorWithinHorizontalBounds(cursorX, contentLeft, contentRight, COL1_HIT_X_PAD) then
        return nil
    end

    if sourceKind == "group" or sourceKind == "folder-group" then
        local seenFolderBlocks = {}
        for _, rowMeta in ipairs(renderedRows) do
            local folderId = GetCol1FolderBlockIdForRow(rowMeta, sourceKind)
            if folderId and not seenFolderBlocks[folderId] then
                seenFolderBlocks[folderId] = true
                local folderBlockTarget = ResolveCol1FolderBlockHoverTarget(
                    renderedRows,
                    folderId,
                    cursorY,
                    sourceKind,
                    sourceSection,
                    sourceFolderId,
                    sourceLoadBucket
                )
                if folderBlockTarget then
                    return folderBlockTarget
                end
            end
        end
    elseif sourceKind == "folder" then
        local seenFolderBlocks = {}
        for _, rowMeta in ipairs(renderedRows) do
            if rowMeta.kind == "folder" and rowMeta.id and not seenFolderBlocks[rowMeta.id] then
                seenFolderBlocks[rowMeta.id] = true
                local folderBlockTarget = ResolveCol1FolderDragBlockHoverTarget(
                    renderedRows,
                    rowMeta.id,
                    cursorY,
                    previousDropTarget
                )
                if folderBlockTarget then
                    return folderBlockTarget
                end
            end
        end
    end

    for i, rowMeta in ipairs(renderedRows) do
        local frame = GetCol1DropFrame(rowMeta)
        if frame and frame:IsShown() then
            local left, right = frame:GetLeft(), frame:GetRight()
            local top = frame:GetTop()
            local bottom = frame:GetBottom()
            if top and bottom
                and IsCursorWithinHorizontalBounds(cursorX, left, right, COL1_HIT_X_PAD)
                and cursorY <= top
                and cursorY >= bottom
            then
                if rowMeta.kind == "folder" and (sourceKind == "group" or sourceKind == "folder-group") then
                    return BuildCol1FolderBlockDropResult(renderedRows, rowMeta.id, "into-folder")
                elseif IsExternalFolderChildTarget(rowMeta, sourceKind, sourceFolderId) then
                    return ResolveCol1FolderBlockDropTarget(renderedRows, rowMeta, sourceKind, "into-folder")
                elseif rowMeta.kind == "aux-block" then
                    return ResolveCol1AuxBlockTarget(renderedRows, i, rowMeta, sourceKind, sourceSection, sourceFolderId, sourceLoadBucket)
                elseif rowMeta.kind == "section-header" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i + 1, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    return FindFirstCol1DropTargetInSection(renderedRows, rowMeta.section, i + 1)
                elseif rowMeta.kind == "unloaded-divider" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    local previousFolderTarget = ResolvePreviousFolderBlockBoundaryTarget(
                        renderedRows,
                        i,
                        sourceKind,
                        sourceSection,
                        sourceLoadBucket,
                        "reorder-after"
                    )
                    if previousFolderTarget then
                        return previousFolderTarget
                    end
                    return FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                elseif rowMeta.loadBucket == "unloaded" then
                    if sourceIsMixed then
                        local mid = (top + bottom) / 2
                        if cursorY > mid then
                            return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                        end
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-after")
                    end
                    if sourceIsUnloaded then
                        local mid = (top + bottom) / 2
                        if cursorY > mid then
                            return BuildCol1DropResult("reorder-before", i, rowMeta)
                        else
                            return BuildCol1DropResult("reorder-after", i, rowMeta)
                        end
                    end
                    local previousFolderTarget = ResolvePreviousFolderBlockBoundaryTarget(
                        renderedRows,
                        i,
                        sourceKind,
                        sourceSection,
                        sourceLoadBucket,
                        "reorder-after"
                    )
                    if previousFolderTarget then
                        return previousFolderTarget
                    end
                    return FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
                    if sourceIsMixed then
                        local mid = (top + bottom) / 2
                        if cursorY > mid then
                            return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                        end
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-after")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    local mid = (top + bottom) / 2
                    if cursorY > mid then
                        return BuildCol1DropResult("reorder-before", i, rowMeta)
                    else
                        return BuildCol1DropResult("reorder-after", i, rowMeta)
                    end
                else
                    return nil
                end
            end
        end
    end

    -- Cursor is in a gap between rows (e.g. between sections): find the first
    -- row whose top edge is below the cursor and target it with reorder-before.
    for i, rowMeta in ipairs(renderedRows) do
        local frame = GetCol1DropFrame(rowMeta)
        if frame and frame:IsShown() then
            local top = frame:GetTop()
            if top and cursorY > top then
                local folderBoundaryTarget = ResolveCol1FolderBlockBoundaryTarget(
                    renderedRows,
                    rowMeta,
                    sourceKind,
                    sourceSection,
                    sourceLoadBucket,
                    "reorder-before"
                )
                if folderBoundaryTarget then
                    return folderBoundaryTarget
                elseif rowMeta.kind == "section-header" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i + 1, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    return FindFirstCol1DropTargetInSection(renderedRows, rowMeta.section, i + 1)
                elseif IsExternalFolderChildTarget(rowMeta, sourceKind, sourceFolderId) then
                    return ResolveCol1FolderBlockBoundaryTarget(
                        renderedRows,
                        rowMeta,
                        sourceKind,
                        sourceSection,
                        sourceLoadBucket,
                        "reorder-before"
                    )
                elseif rowMeta.kind == "aux-block" then
                    return ResolveCol1AuxBlockTarget(renderedRows, i, rowMeta, sourceKind, sourceSection, sourceFolderId, sourceLoadBucket)
                elseif rowMeta.kind == "unloaded-divider" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i + 1)
                    end
                    return FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                elseif rowMeta.loadBucket == "unloaded" then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return BuildCol1DropResult("reorder-before", i, rowMeta)
                    end
                    return FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
                    if sourceIsMixed then
                        return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-before")
                    end
                    if sourceIsUnloaded then
                        return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i)
                    end
                    return BuildCol1DropResult("reorder-before", i, rowMeta)
                end
            end
        end
    end

    -- Below all rows: drop after the last row overall.
    for i = #renderedRows, 1, -1 do
        local rowMeta = renderedRows[i]
        local frame = GetCol1DropFrame(rowMeta)
        if frame and frame:IsShown() then
            local folderBoundaryTarget = ResolveCol1FolderBlockBoundaryTarget(
                renderedRows,
                rowMeta,
                sourceKind,
                sourceSection,
                sourceLoadBucket,
                "reorder-after",
                { isBelowAll = true }
            )
            if folderBoundaryTarget then
                return folderBoundaryTarget
            elseif rowMeta.kind == "unloaded-divider" or rowMeta.loadBucket == "unloaded" then
                if sourceIsMixed then
                    return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-after")
                end
                if sourceIsUnloaded then
                    return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i, true)
                end
                local dividerTarget = FindCol1SectionDividerTarget(renderedRows, rowMeta.section)
                if dividerTarget then
                    return dividerTarget
                end
            elseif rowMeta.kind == "phantom" or rowMeta.acceptsDrop then
                if sourceIsMixed then
                    return ResolveCol1MixedSectionTarget(renderedRows, rowMeta, i, sourceSection, "reorder-after")
                end
                if sourceIsUnloaded then
                    return ResolveCol1UnloadedSectionTarget(renderedRows, rowMeta.section, i, true)
                end
                return BuildCol1DropResult("reorder-after", i, rowMeta, { isBelowAll = true })
            end
        end
    end
    return nil
end

IsUnloadedTopLevelDrop = function(state, dropTarget, targetFolderId)
    if targetFolderId then
        return false
    end
    if not IsCol1UnloadedDragSource(state and state.sourceLoadBucket) then
        return false
    end
    local targetRow = dropTarget and dropTarget.targetRow
    return targetRow and (targetRow.kind == "unloaded-divider" or targetRow.loadBucket == "unloaded")
end

ShouldIncludeCol1TopLevelOrderRow = function(row, includeUnloaded)
    if not row then
        return false
    end
    if row.kind ~= "folder" and not (row.kind == "container" and not row.inFolder) then
        return false
    end
    if includeUnloaded then
        return row.loadBucket == "unloaded"
    end
    return row.loadBucket ~= "unloaded"
end

local function FindCol1TopLevelInsertPos(orderItems, targetRow, action, defaultPos)
    local insertPos = defaultPos or (#orderItems + 1)
    if not targetRow or targetRow.kind == "unloaded-divider" then
        return insertPos
    end
    for idx, item in ipairs(orderItems) do
        if item.kind == targetRow.kind and item.id == targetRow.id then
            insertPos = action == "reorder-after" and idx + 1 or idx
            break
        end
    end
    return insertPos
end

local function AssignCol1TopLevelOrders(orderItems, db, specId, startOrder)
    local nextOrder = startOrder or 1
    for _, item in ipairs(orderItems) do
        if item.kind == "folder" and db.folders[item.id] then
            CooldownCompanion:SetOrderForSpec(db.folders[item.id], specId, nextOrder)
            nextOrder = nextOrder + 1
        elseif db.groupContainers[item.id] then
            CooldownCompanion:SetOrderForSpec(db.groupContainers[item.id], specId, nextOrder)
            nextOrder = nextOrder + 1
        end
    end
    return nextOrder
end

local function PartitionSelectedContainersByLoadBucket(sourceContainerIds, renderedRows, specId, db)
    local loadBucketById = {}
    for _, row in ipairs(renderedRows or {}) do
        if row.kind == "container" and sourceContainerIds[row.id] then
            loadBucketById[row.id] = row.loadBucket
        end
    end

    local loaded, unloaded = {}, {}
    for cid in pairs(sourceContainerIds or {}) do
        local container = db.groupContainers[cid]
        if container then
            local item = {
                kind = "group",
                id = cid,
                order = CooldownCompanion:GetOrderForSpec(container, specId, cid),
            }
            if loadBucketById[cid] == "unloaded" then
                table.insert(unloaded, item)
            else
                table.insert(loaded, item)
            end
        end
    end

    table.sort(loaded, function(a, b) return a.order < b.order end)
    table.sort(unloaded, function(a, b) return a.order < b.order end)
    return loaded, unloaded
end

-- Show drag indicator for "into-folder" drops (highlight overlay on folder row)
local function ShowFolderDropOverlay(dropTarget, parentScrollWidget)
    HideDragIndicator()
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

        if dropTarget.action == "into-folder" or dropTarget.action == "reorder-before" or dropTarget.action == "reorder-after" then
            local targetRow = dropTarget.targetRow
            local targetFolderId = ResolveCol1GroupDropTargetFolderId(state, dropTarget)
            CooldownCompanion:MoveGroupToFolder(sourceContainerId, targetFolderId)

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
                targetFolderId = container.folderId
                local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, targetFolderId)
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
                            if ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
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
                    insertPos = includeUnloaded and 1 or (#orderItems + 1)
                    if dropTarget.targetRow.kind ~= "unloaded-divider" then
                        insertPos = #orderItems + 1
                        for idx, item in ipairs(orderItems) do
                            if item.kind == dropTarget.targetRow.kind and item.id == dropTarget.targetRow.id then
                                insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                                break
                            end
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
        local targetFolderId = ResolveCol1GroupDropTargetFolderId(state, dropTarget)

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
            elseif IsCol1MixedDragSource(state.sourceLoadBucket) then
                local selectedLoaded, selectedUnloaded = PartitionSelectedContainersByLoadBucket(sourceContainerIds, renderedRows, specId, db)
                local loadedOrderItems = {}
                local unloadedOrderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == targetSection and not sourceContainerIds[row.id] then
                        if ShouldIncludeCol1TopLevelOrderRow(row, false) then
                            table.insert(loadedOrderItems, { kind = row.kind, id = row.id })
                        elseif ShouldIncludeCol1TopLevelOrderRow(row, true) then
                            table.insert(unloadedOrderItems, { kind = row.kind, id = row.id })
                        end
                    end
                end

                local targetIsUnloaded = targetRow.kind == "unloaded-divider" or targetRow.loadBucket == "unloaded"
                local loadedInsertPos
                local unloadedInsertPos
                if targetIsUnloaded then
                    loadedInsertPos = #loadedOrderItems + 1
                    unloadedInsertPos = FindCol1TopLevelInsertPos(unloadedOrderItems, targetRow, dropTarget.action, 1)
                else
                    loadedInsertPos = FindCol1TopLevelInsertPos(loadedOrderItems, targetRow, dropTarget.action, #loadedOrderItems + 1)
                    unloadedInsertPos = 1
                end

                for i, item in ipairs(selectedLoaded) do
                    table.insert(loadedOrderItems, loadedInsertPos + i - 1, { kind = item.kind, id = item.id })
                end
                for i, item in ipairs(selectedUnloaded) do
                    table.insert(unloadedOrderItems, unloadedInsertPos + i - 1, { kind = item.kind, id = item.id })
                end

                local nextOrder = AssignCol1TopLevelOrders(loadedOrderItems, db, specId, 1)
                AssignCol1TopLevelOrders(unloadedOrderItems, db, specId, nextOrder)
            else
                -- Top-level ordering
                local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, targetFolderId)
                local orderItems = {}
                for _, row in ipairs(renderedRows) do
                    if row.section == targetSection then
                        if ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded) then
                            if not sourceContainerIds[row.id] then
                                table.insert(orderItems, { kind = row.kind, id = row.id })
                            end
                        end
                    end
                end

                local insertPos = includeUnloaded and 1 or (#orderItems + 1)
                if targetRow.kind ~= "unloaded-divider" then
                    insertPos = #orderItems + 1
                    for idx, item in ipairs(orderItems) do
                        if item.kind == targetRow.kind and item.id == targetRow.id then
                            insertPos = dropTarget.action == "reorder-after" and idx + 1 or idx
                            break
                        end
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
            local includeUnloaded = IsUnloadedTopLevelDrop(state, dropTarget, nil)
            local orderItems = {}
            for _, row in ipairs(renderedRows) do
                if row.section == section then
                    if ShouldIncludeCol1TopLevelOrderRow(row, includeUnloaded)
                        and row.id ~= sourceFolderId then
                        table.insert(orderItems, { kind = row.kind, id = row.id })
                    end
                end
            end

            local insertPos = includeUnloaded and 1 or (#orderItems + 1)
            if targetRow.kind ~= "unloaded-divider" then
                insertPos = #orderItems + 1
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
    if targetGroup.displayMode == "textures" and #targetGroup.buttons >= 1 then
        CooldownCompanion:Print("Texture Panels can only hold one entry.")
        return nil
    end
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
local function SetDraggedWidgetAlpha(widget, alpha)
    if not widget then return end
    if widget.frame and widget.frame.SetAlpha then
        widget.frame:SetAlpha(alpha)
    elseif widget.SetAlpha then
        widget:SetAlpha(alpha)
    end
end

local function CancelDrag()
    if CS.dragState then
        if CS.dragState.kind == "layout-slot"
            and CS.dragState.layoutDrag
            and CS.dragState.layoutDrag.onCancel then
            CS.dragState.layoutDrag.onCancel(CS.dragState)
        end
    end
    ClearCol1AnimatedPreview()
    ClearCol2AnimatedPreview()
    if CS.dragState then
        if CS.dragState.dimmedWidgets then
            for _, w in ipairs(CS.dragState.dimmedWidgets) do
                SetDraggedWidgetAlpha(w, 1)
            end
        elseif CS.dragState.widget then
            SetDraggedWidgetAlpha(CS.dragState.widget, 1)
        end
    end
    CS.dragState = nil
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
    if state.kind == "layout-slot" then
        local cursorX, cursorY = GetRawCursorCoordinates()
        if state.layoutDrag and state.layoutDrag.resolveDropTarget then
            state.dropTarget = state.layoutDrag.resolveDropTarget(cursorX, cursorY, state)
        end
        if state.layoutDrag and state.layoutDrag.applyDrop then
            state.layoutDrag.applyDrop(state)
        end
        CancelDrag()
        ResetDragIndicatorStyle()
        return
    end
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
        local changed = true
        if dropTarget then
            if state.kind == "group" or state.kind == "folder-group" then
                changed = not IsCol1GroupDropNoOp(state)
            elseif state.kind == "folder" then
                changed = not IsCol1FolderDropNoOp(state)
            end
        end
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
        if changed then
            ApplyCol1Drop(state)
        end
        CooldownCompanion:RefreshConfigPanel()
    elseif state.kind == "panel" then
        local dropTarget = state.dropTarget
        local changed = dropTarget and not IsPanelReorderNoOp(state.sourcePanelId, dropTarget.targetIndex, state.panelDropTargets)
        if changed then
            wipe(CS.selectedPanels)
            CS.selectedGroup = state.sourcePanelId
            CS.selectedButton = nil
            wipe(CS.selectedButtons)
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
        local cursorX, cursorY
        if CS.dragState.kind == "layout-slot" then
            cursorX, cursorY = GetRawCursorCoordinates()
        else
            cursorX, cursorY = GetScaledCursorCoordinates(CS.dragState.scrollWidget)
        end
        if CS.dragState.phase == "pending" then
            local deltaY = math.abs(cursorY - (CS.dragState.startY or cursorY))
            local deltaX = math.abs(cursorX - (CS.dragState.startX or cursorX))
            if deltaY > DRAG_THRESHOLD or deltaX > DRAG_THRESHOLD then
                CS.dragState.phase = "active"
                if CS.dragState.kind == "layout-slot"
                    and CS.dragState.layoutDrag
                    and CS.dragState.layoutDrag.onActivate then
                    CS.dragState.layoutDrag.onActivate(CS.dragState)
                end
                -- Dim source widget(s)
                if CS.dragState.kind == "multi-group" and CS.dragState.sourceGroupIds then
                    CS.dragState.dimmedWidgets = {}
                    for _, row in ipairs(CS.dragState.col1RenderedRows) do
                        if row.kind == "container" and CS.dragState.sourceGroupIds[row.id] then
                            SetDraggedWidgetAlpha(row.widget, 0.4)
                            table.insert(CS.dragState.dimmedWidgets, row.widget)
                        end
                    end
                elseif CS.dragState.widget then
                    SetDraggedWidgetAlpha(CS.dragState.widget, 0.4)
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
                        local savedSourceLoadBucket = CS.dragState.sourceLoadBucket
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
                            sourceLoadBucket = savedSourceLoadBucket,
                            scrollWidget = savedScrollWidget,
                            startY = savedStartY,
                            col1RenderedRows = CS.lastCol1RenderedRows,
                        }
                        -- Dim the source widget(s) in the new rows
                        if savedKind == "multi-group" and savedSourceGroupIds then
                            CS.dragState.dimmedWidgets = {}
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if row.kind == "container" and savedSourceGroupIds[row.id] then
                                    SetDraggedWidgetAlpha(row.widget, 0.4)
                                    table.insert(CS.dragState.dimmedWidgets, row.widget)
                                end
                            end
                        else
                            for _, row in ipairs(CS.dragState.col1RenderedRows) do
                                if savedKind == "folder" and row.kind == "folder" and row.id == savedSourceFolderId then
                                    CS.dragState.widget = row.widget
                                    SetDraggedWidgetAlpha(row.widget, 0.4)
                                    break
                                elseif (savedKind == "group" or savedKind == "folder-group") and row.kind == "container" and row.id == savedSourceGroupId then
                                    CS.dragState.widget = row.widget
                                    SetDraggedWidgetAlpha(row.widget, 0.4)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        if CS.dragState.phase == "active" then
            SetDraggedFolderAccentBarHidden(CS.dragState, true)
            if CS.dragState.kind == "layout-slot" then
                local dropTarget = CS.dragState.layoutDrag
                    and CS.dragState.layoutDrag.resolveDropTarget
                    and CS.dragState.layoutDrag.resolveDropTarget(cursorX, cursorY, CS.dragState)
                CS.dragState.dropTarget = dropTarget
                ClearCol2AnimatedPreview()
                if CS.dragState.layoutDrag and CS.dragState.layoutDrag.onUpdate then
                    CS.dragState.layoutDrag.onUpdate(CS.dragState, cursorX, cursorY, dropTarget)
                elseif dropTarget and CS.dragState.layoutDrag.showIndicator then
                    CS.dragState.layoutDrag.showIndicator(dropTarget)
                else
                    HideDragIndicator()
                end
            elseif CS.dragState.col1RenderedRows then
                ClearCol2AnimatedPreview()
                -- Column 1 folder-aware drop detection
                local effectiveKind = CS.dragState.kind == "multi-group" and "group" or CS.dragState.kind
                local dropTarget = GetCol1DropTarget(
                    cursorX,
                    cursorY,
                    CS.dragState.scrollWidget,
                    CS.dragState.col1RenderedRows,
                    effectiveKind,
                    CS.dragState.sourceSection,
                    CS.dragState.sourceFolderId,
                    CS.dragState.sourceLoadBucket,
                    CS.dragState.dropTarget
                )
                CS.dragState.dropTarget = dropTarget
                if dropTarget then
                    ResetDragIndicatorStyle()
                    HideDragIndicator()
                    local shouldAnimatePreview = ShouldAnimateCol1PreviewForDrop(
                        CS.dragState.sourceLoadBucket,
                        dropTarget,
                        CS.dragState.col1RenderedRows
                    )
                    if not shouldAnimatePreview or not RenderCol1AnimatedPreview({
                        kind = CS.dragState.kind,
                        sourceGroupId = CS.dragState.sourceGroupId,
                        sourceGroupIds = CS.dragState.sourceGroupIds,
                        sourceFolderId = CS.dragState.sourceFolderId,
                        dropTarget = dropTarget,
                    }) then
                        ClearCol1AnimatedPreview()
                        local unloadedPlaceholderTarget = ResolveCol1LoadedUnloadedPlaceholderTarget(
                            CS.dragState.col1RenderedRows,
                            CS.dragState.sourceLoadBucket,
                            dropTarget
                        )
                        if dropTarget.action == "into-folder" then
                            HideDragIndicator()
                        elseif unloadedPlaceholderTarget then
                            HideDragIndicator()
                        elseif ShouldShowCol1StaticReorderIndicator(
                            CS.dragState.sourceLoadBucket,
                            dropTarget
                        )
                            and dropTarget.action == "reorder-before"
                        then
                            ShowDragIndicator(dropTarget.anchorFrame, true, CS.dragState.scrollWidget)
                        elseif ShouldShowCol1StaticReorderIndicator(
                            CS.dragState.sourceLoadBucket,
                            dropTarget
                        ) then
                            ShowDragIndicator(dropTarget.anchorFrame, false, CS.dragState.scrollWidget)
                        else
                            HideDragIndicator()
                        end
                    end
                else
                    ClearCol1AnimatedPreview()
                    HideDragIndicator()
                end
            elseif CS.dragState.panelDropTargets then
                ClearCol1AnimatedPreview()
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
                ClearCol1AnimatedPreview()
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
                ClearCol1AnimatedPreview()
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
