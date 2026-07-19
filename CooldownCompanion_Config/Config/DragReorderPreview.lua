--[[
    CooldownCompanion - Config/DragReorderPreview
    Animated drag preview rendering for Column 1 and Column 2.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local DR = ST._DragReorder or {}
ST._DragReorder = DR

local EnsureCol1PreviewHost = ST._EnsureCol1PreviewHost
local ClearCol1PreviewHost = ST._ClearCol1PreviewHost
local EnsureCol2PreviewHost = ST._EnsureCol2PreviewHost
local ClearCol2PreviewHost = ST._ClearCol2PreviewHost
local SetupGroupRowIndicators = ST._SetupGroupRowIndicators
local SetupFolderRowIndicators = ST._SetupFolderRowIndicators
local ApplyColumn1MarkerAppearance = ST._ApplyColumn1MarkerAppearance
local FindCol1SectionDividerTarget = DR.FindCol1SectionDividerTarget
local FindCol1FolderBlockRange = DR.FindCol1FolderBlockRange

local PREVIEW_ANIM_DURATION = 0.08
local PREVIEW_PANEL_INSET = 8
local PREVIEW_ROW_TEXT_RIGHT_PAD = 8
local PREVIEW_DEFAULT_ROW_HEIGHT = 32

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
    return t < 0.5 and (2 * t * t) or (1 - (((-2 * t + 2) ^ 2) / 2))
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
    elseif displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then
        texture:SetTexture(CooldownCompanion:GetRotationAssistantFallbackIcon())
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

local function SeedCol1PreviewFrame(frame, x, y, width, height)
    if frame and frame._cdcDisplayX == nil then
        ApplyPreviewFrameGeometry(frame, x, y, width, height, 1)
    end
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
    if preview.centerGhostOnCursor then
        local offsetX = math.floor((preview.ghost:GetWidth() or 0) / 2)
        local offsetY = math.floor((preview.ghost:GetHeight() or 0) / 2)
        preview.ghost:SetPoint(
            "TOPLEFT",
            UIParent,
            "BOTTOMLEFT",
            cursorX - offsetX,
            cursorY + offsetY
        )
    else
        preview.ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX + 14, cursorY - 14)
    end
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
    preview.centerGhostOnCursor = false
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
        rowType = row.rowType,
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
        shellRect = row.shellRect and {
            x = row.shellRect.x,
            y = row.shellRect.y,
            width = row.shellRect.width,
            height = row.shellRect.height,
        } or nil,
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
            local shellX, shellY, shellWidth, shellHeight = GetRelativeRect(
                rowMeta.dragShellFrame,
                content
            )
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
                rowType = rowMeta.rowType,
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
                shellRect = shellX and {
                    x = shellX,
                    y = shellY,
                    width = shellWidth,
                    height = shellHeight,
                } or nil,
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
    if source.kind == "rail-panel" then
        return row.rowType == "panel"
            and source.sourcePanelIds
            and source.sourcePanelIds[row.id] == true
    elseif source.kind == "folder" then
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

    if source.kind == "rail-panel" then
        for _, row in ipairs(base.rows) do
            if IsCol1AuxOwnedBySource(row, source) then
                movedRows[#movedRows + 1] = row
                movedIndexes[row.originalIndex] = true
            end
        end
    elseif source.kind == "folder" then
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
    if (source.kind == "group" or source.kind == "folder-group")
        and firstRow.shellRect
    then
        gapHeight = firstRow.shellRect.height
    end
    if source.kind == "rail-panel" and #movedRows > 1 then
        ghostRow = CopyCol1PreviewRow(firstRow)
        ghostRow.text = tostring(#movedRows) .. " panels"
        ghostRow.height = math.max(firstRow.height, PREVIEW_DEFAULT_ROW_HEIGHT)
    elseif source.kind == "multi-group" and #movedRows > 1 then
        local selectedCount = 0
        if source.sourceGroupIds then
            for _ in pairs(source.sourceGroupIds) do
                selectedCount = selectedCount + 1
            end
        end
        ghostRow = CopyCol1PreviewRow(firstRow)
        ghostRow.text = tostring(math.max(1, selectedCount)) .. " groups"
        ghostRow.height = math.max(firstRow.height, PREVIEW_DEFAULT_ROW_HEIGHT)
    elseif source.kind == "group" or source.kind == "folder-group" then
        ghostRow = CopyCol1PreviewRow(firstRow)
        ghostRow.height = gapHeight
        ghostRow.width = firstRow.shellRect and firstRow.shellRect.width or ghostRow.width
        ghostRow.fullContainerGhost = true
    else
        ghostRow = CopyCol1PreviewRow(firstRow)
    end

    if source.kind == "group" or source.kind == "folder-group" then
        ghostRow.centerGroupLabel = true
    end

    return movedRows, movedIndexes, gapHeight, ghostRow
end


local function ResolveCol1PreviewAnchor(base, source, dropTarget)
    if not dropTarget then
        return nil, nil
    end
    if dropTarget.isBelowAll then
        return #base.rows + 1, base.rows[#base.rows]
    end

    if source.kind == "rail-panel" then
        if dropTarget.targetPanelId then
            for _, row in ipairs(base.rows) do
                if row.kind == "aux-block"
                    and row.rowType == "panel"
                    and row.id == dropTarget.targetPanelId
                then
                    if dropTarget.action == "before" then
                        return row.originalIndex, row
                    end
                    return row.originalIndex + 1, row
                end
            end
            return nil, nil
        end

        if dropTarget.action == "append" and dropTarget.targetContainerId then
            local headerRow
            local lastPanelRow
            for _, row in ipairs(base.rows) do
                if row.kind == "container" and row.id == dropTarget.targetContainerId then
                    headerRow = row
                elseif row.kind == "aux-block"
                    and row.rowType == "panel"
                    and row.ownerId == dropTarget.targetContainerId
                then
                    lastPanelRow = row
                end
            end
            local anchorRow = lastPanelRow or headerRow
            if anchorRow then
                return anchorRow.originalIndex + 1, lastPanelRow
            end
        end
        return nil, nil
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
                    shellRect = movedRows[1] and movedRows[1].shellRect or nil,
                    shellHeaderY = movedRows[1] and movedRows[1].y or nil,
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
            ownerKind = source.kind == "rail-panel" and "container" or nil,
            ownerId = source.kind == "rail-panel"
                and source.dropTarget.targetContainerId or nil,
            shellRect = source.kind ~= "rail-panel"
                and movedRows[1] and movedRows[1].shellRect or nil,
            shellHeaderY = source.kind ~= "rail-panel"
                and movedRows[1] and movedRows[1].y or nil,
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
        simplifyGroupBlocks = source.kind == "group"
            or source.kind == "folder-group"
            or source.kind == "multi-group",
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

local function CenterCol1GroupPreviewLabel(frame, icon, label, row, availableWidth)
    local width = math.max(1, availableWidth or frame:GetWidth() or 1)
    label:SetText(row.text or "")
    if row.textColor then
        label:SetTextColor(row.textColor[1] or 1, row.textColor[2] or 1, row.textColor[3] or 1)
    else
        label:SetTextColor(1, 1, 1)
    end

    local hasIcon = row.icon and (row.iconAlpha or 1) > 0.05
    local iconSize = math.min(32, (row.iconRect and row.iconRect.height) or 32)
    local gap = hasIcon and 8 or 0
    local maxTextWidth = math.max(1, width - (hasIcon and (iconSize + gap + 16) or 16))
    local textWidth = math.min(label:GetStringWidth(), maxTextWidth)
    local totalWidth = textWidth + (hasIcon and (iconSize + gap) or 0)

    label:ClearAllPoints()
    label:SetWidth(textWidth)
    label:SetJustifyH("LEFT")
    if hasIcon then
        icon:SetTexture(row.icon)
        icon:SetAlpha(row.iconAlpha or 1)
        icon:SetSize(iconSize, iconSize)
        icon:ClearAllPoints()
        icon:SetPoint("LEFT", frame, "CENTER", -(totalWidth / 2), 0)
        icon:Show()
        label:SetPoint("LEFT", icon, "RIGHT", gap, 0)
    else
        icon:Hide()
        label:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
end

local function RenderCol1GroupOutlines(preview, model)
    local ranges = {}
    local order = {}

    for _, row in ipairs(model and model.rows or {}) do
        local containerId
        if row.kind == "container" then
            containerId = row.id
        elseif row.ownerKind == "container" then
            containerId = row.ownerId
        end

        if containerId and not row.layoutOnly then
            local range = ranges[containerId]
            if not range then
                range = {
                    headerRow = row.kind == "container" and row or nil,
                    shellRect = row.shellRect,
                    baseContentTop = row.y,
                    baseContentBottom = row.y and (row.y + (row.height or 0)) or nil,
                    targetContentTop = row.previewY,
                    targetContentBottom = (row.previewY or 0) + (row.height or 0),
                    fallbackLeft = math.max(0, (row.x or 0) - 8),
                    fallbackRight = (row.x or 0) + (row.width or 0) + 4,
                }
                ranges[containerId] = range
                order[#order + 1] = containerId
            else
                if row.kind == "container" then
                    range.headerRow = row
                    range.shellRect = row.shellRect or range.shellRect
                end
                if row.y then
                    range.baseContentTop = range.baseContentTop
                        and math.min(range.baseContentTop, row.y) or row.y
                    range.baseContentBottom = range.baseContentBottom
                        and math.max(range.baseContentBottom, row.y + (row.height or 0))
                        or (row.y + (row.height or 0))
                end
                range.fallbackLeft = math.min(
                    range.fallbackLeft,
                    math.max(0, (row.x or 0) - 8)
                )
                range.fallbackRight = math.max(
                    range.fallbackRight,
                    (row.x or 0) + (row.width or 0) + 4
                )
                range.targetContentTop = math.min(
                    range.targetContentTop,
                    row.previewY or range.targetContentTop
                )
                range.targetContentBottom = math.max(
                    range.targetContentBottom,
                    (row.previewY or 0) + (row.height or 0)
                )
            end
        end
    end

    for _, panelProxy in ipairs(preview.panels or {}) do
        panelProxy.used = false
    end

    local rootWidth = preview.root:GetWidth() or 0
    for index, containerId in ipairs(order) do
        local range = ranges[containerId]
        local panelProxy = AcquirePreviewPanelFrame(preview, index)
        local frame = panelProxy.frame
        panelProxy.used = true
        frame:SetBackdropColor(0.025, 0.02, 0.015, 0.20)
        frame:SetBackdropBorderColor(0.38, 0.33, 0.26, 0.72)
        frame:SetFrameLevel((preview.root:GetFrameLevel() or 1) + 1)

        local shell = range.shellRect
        local left = shell and shell.x or range.fallbackLeft
        local right = shell and (shell.x + shell.width) or range.fallbackRight
        local baseTop = shell and shell.y
            or math.max(0, (range.baseContentTop or range.targetContentTop) - 4)
        local baseBottom = shell and (shell.y + shell.height)
            or ((range.baseContentBottom or range.targetContentBottom) + 4)
        local topInset = shell and range.baseContentTop
            and (range.baseContentTop - shell.y) or 4
        local bottomInset = shell and range.baseContentBottom
            and ((shell.y + shell.height) - range.baseContentBottom) or 4
        local targetTop = math.max(0, range.targetContentTop - topInset)
        local targetBottom = range.targetContentBottom + bottomInset
        if rootWidth > 0 then
            right = math.min(right, rootWidth - 2)
        end
        local outlineWidth = math.max(1, right - left)
        if model.simplifyGroupBlocks and range.headerRow then
            CenterCol1GroupPreviewLabel(
                frame,
                frame._cdcModeBadge,
                frame._cdcTitle,
                range.headerRow,
                outlineWidth
            )
            frame._cdcTitle:Show()
        else
            frame._cdcTitle:Hide()
            frame._cdcModeBadge:Hide()
        end
        SeedCol1PreviewFrame(
            frame,
            left,
            baseTop,
            outlineWidth,
            math.max(1, baseBottom - baseTop)
        )
        QueuePreviewTween(
            preview,
            frame,
            left,
            targetTop,
            outlineWidth,
            math.max(1, targetBottom - targetTop),
            1,
            PREVIEW_ANIM_DURATION
        )
        frame:Show()
    end

    for _, panelProxy in ipairs(preview.panels or {}) do
        if not panelProxy.used then
            panelProxy.frame:Hide()
        end
    end
end

local function RenderCol1DropGap(preview, model)
    local gapRow
    for _, row in ipairs(model and model.rows or {}) do
        if row.isGap then
            gapRow = row
            break
        end
    end

    if not gapRow then
        if preview.dropGap then
            preview.dropGap:Hide()
        end
        return
    end

    local gap = preview.dropGap
    if not gap then
        gap = CreateFrame("Frame", nil, preview.root, "BackdropTemplate")
        gap:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        gap:EnableMouse(false)
        preview.dropGap = gap
    end

    local classColor = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    local r = classColor and classColor.r or 0.30
    local g = classColor and classColor.g or 0.62
    local b = classColor and classColor.b or 1.00
    gap:SetBackdropColor(r, g, b, 0.16)
    gap:SetBackdropBorderColor(r, g, b, 0.58)
    gap:SetFrameLevel((preview.root:GetFrameLevel() or 1) + 5)

    local x = gapRow.x or PREVIEW_PANEL_INSET
    local y = gapRow.previewY or 0
    local width = gapRow.width or 120
    local height = gapRow.height or PREVIEW_DEFAULT_ROW_HEIGHT
    if gapRow.shellRect then
        local shell = gapRow.shellRect
        local headerInset = (gapRow.shellHeaderY or shell.y) - shell.y
        x = shell.x
        y = y - headerInset
        width = shell.width
        height = shell.height
    end

    QueuePreviewTween(
        preview,
        gap,
        x,
        y,
        width,
        height,
        1,
        PREVIEW_ANIM_DURATION
    )
    gap:Show()
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
        -- Match the proven Column 2 drag approach: replace the complete
        -- AceGUI content surface for the duration of the drag. Hiding only
        -- tracked child rows leaves InlineGroup shells behind and produces
        -- overlapping/clipped geometry when addon-owned proxies move.
        for _, frame in ipairs({ content:GetChildren() }) do
            if frame ~= preview.root and preview.hiddenFrames[frame] == nil then
                preview.hiddenFrames[frame] = frame:GetAlpha()
                frame:SetAlpha(0)
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

    if row.kind == "container" then
        preview.ghost:SetBackdropColor(0.025, 0.02, 0.015, 0.20)
        preview.ghost:SetBackdropBorderColor(0.38, 0.33, 0.26, 0.92)
    else
        preview.ghost:SetBackdropColor(0, 0, 0, 0)
        preview.ghost:SetBackdropBorderColor(0, 0, 0, 0)
    end
    preview.ghost:SetSize(row.width or 160, row.height or PREVIEW_DEFAULT_ROW_HEIGHT)
    preview.ghost.label:SetText(row.text or "")
    if row.textColor then
        preview.ghost.label:SetTextColor(row.textColor[1] or 1, row.textColor[2] or 1, row.textColor[3] or 1)
    else
        preview.ghost.label:SetTextColor(1, 1, 1)
    end

    if row.centerGroupLabel then
        CenterCol1GroupPreviewLabel(
            preview.ghost,
            preview.ghost.icon,
            preview.ghost.label,
            row,
            row.width or 160
        )
    else
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
    end

    HideCol1PreviewBadges(preview.ghost)
    if row.kind == "folder" then
        local db = CooldownCompanion.db.profile
        local folder = db and db.folders and db.folders[row.id]
        if folder then
            SetupFolderRowIndicators({ frame = preview.ghost }, folder)
        end
    end

    preview.ghost:Show()
    preview.ghostActive = true
    UpdatePreviewGhost(preview)
end

local ClearCol1AnimatedPreview

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
    preview.centerGhostOnCursor = true
    SetCol1BaseFramesHidden(true, source)
    preview.root:Show()

    for _, rowProxy in ipairs(preview.rows) do
        rowProxy.used = false
    end

    RenderCol1GroupOutlines(preview, model)
    RenderCol1DropGap(preview, model)

    for _, row in ipairs(model.rows) do
        local hiddenInsideSimplifiedGroup = model.simplifyGroupBlocks
            and (row.kind == "container"
                or (row.kind == "aux-block" and row.ownerKind == "container"))
        if not row.isGap and not row.layoutOnly and not hiddenInsideSimplifiedGroup then
            local rowProxy = AcquireCol1PreviewRowFrame(preview, row.key or tostring(row.originalIndex))
            local frame = rowProxy.frame
            frame:SetFrameLevel((preview.root:GetFrameLevel() or 1) + 10)
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

            SeedCol1PreviewFrame(frame, row.x, row.y, row.width, row.height)
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

DR.PREVIEW_MODE_PANEL_COMPACT = PREVIEW_MODE_PANEL_COMPACT
DR.RenderCol2AnimatedPreview = RenderCol2AnimatedPreview
DR.ClearCol2AnimatedPreview = ClearCol2AnimatedPreview
DR.RenderCol1AnimatedPreview = RenderCol1AnimatedPreview
DR.ClearCol1AnimatedPreview = ClearCol1AnimatedPreview
DR.UpdateCol2CursorPreview = UpdateCol2CursorPreview
DR.SetDraggedFolderAccentBarHidden = SetDraggedFolderAccentBarHidden
DR.ShouldAnimateCol1PreviewForDrop = ShouldAnimateCol1PreviewForDrop
DR.ShouldShowCol1StaticReorderIndicator = ShouldShowCol1StaticReorderIndicator
DR.ResolveCol1LoadedUnloadedPlaceholderTarget = ResolveCol1LoadedUnloadedPlaceholderTarget
