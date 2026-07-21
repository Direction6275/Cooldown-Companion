--[[
    CooldownCompanion - Group Panel Overview Preview
    Organized, read-only Panel mirrors for a selected Group. This surface is
    navigation only: every tile selects the same Panel destination as the
    Navigator, while runtime-relative positioning and entry interaction stay
    out of scope.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local math_ceil = math.ceil
local math_max = math.max
local math_min = math.min
local table_sort = table.sort

local OUTER_PADDING = 8
local TILE_GAP = 8
local TILE_INSET = 4
local LABEL_HEIGHT = 18
local MIN_ROW_HEIGHT = 84
local SCROLL_STEP = 64
local SCROLL_RESERVE = 8
local SCROLL_TRACK_WIDTH = 3
local TILE_BORDER_COLOR = { 0.24, 0.34, 0.46, 0.85 }
local TILE_HOVER_BORDER_COLOR = { 0.32, 0.82, 1, 1 }

local function Clamp(value, low, high)
    return math_max(low, math_min(value, high))
end

local function GetColumnCount(panelCount)
    if panelCount <= 1 then return 1 end
    if panelCount == 2 or panelCount == 4 then return 2 end
    return 3
end

local function GetMedian(values)
    table_sort(values)
    local middle = (#values + 1) / 2
    if middle == math.floor(middle) then
        return values[middle]
    end
    local lower = math.floor(middle)
    return (values[lower] + values[lower + 1]) / 2
end

local function GetRowMedian(records, firstIndex, count)
    local weights = {}
    for offset = 0, count - 1 do
        weights[#weights + 1] = records[firstIndex + offset].weight
    end
    return GetMedian(weights)
end

local function BuildRowLayouts(records, columns, layoutWidth)
    local rows = {}
    local recordIndex = 1
    local labelHeight = #records > 1 and LABEL_HEIGHT or 0

    while recordIndex <= #records do
        local rowCount = math_min(columns, #records - recordIndex + 1)
        local baseColumnWidth = (layoutWidth - ((columns - 1) * TILE_GAP))
            / columns
        local rowSpan = (baseColumnWidth * rowCount)
            + ((rowCount - 1) * TILE_GAP)
        local rowStartX = (layoutWidth - rowSpan) / 2
        local distributableWidth = rowSpan - ((rowCount - 1) * TILE_GAP)
        local median = math_max(1, GetRowMedian(records, recordIndex, rowCount))
        local weightSum = 0
        local row = {
            items = {},
            preferredHeight = MIN_ROW_HEIGHT,
        }

        for offset = 0, rowCount - 1 do
            local record = records[recordIndex + offset]
            record.layoutWeight = Clamp(record.weight,
                median * 0.75, median * 1.5)
            weightSum = weightSum + record.layoutWeight
        end

        local x = rowStartX
        for offset = 0, rowCount - 1 do
            local record = records[recordIndex + offset]
            local tileWidth = distributableWidth
                * (record.layoutWeight / weightSum)
            local visualWidth = math_max(1, tileWidth - (TILE_INSET * 2))
            local fittedNaturalHeight = math_min(
                record.naturalHeight,
                visualWidth * record.naturalHeight
                    / math_max(1, record.naturalWidth)
            )
            row.preferredHeight = math_max(
                row.preferredHeight,
                fittedNaturalHeight + labelHeight + (TILE_INSET * 2)
            )
            row.items[#row.items + 1] = {
                record = record,
                x = x,
                width = tileWidth,
            }
            x = x + tileWidth + TILE_GAP
        end

        rows[#rows + 1] = row
        recordIndex = recordIndex + rowCount
    end

    return rows
end

local function AllocateRowHeights(rows, visibleHeight, overflow)
    local preferredHeights = {}
    for index, row in ipairs(rows) do
        preferredHeights[index] = row.preferredHeight
    end
    local median = math_max(1, GetMedian(preferredHeights))
    local weightSum = 0
    for _, row in ipairs(rows) do
        row.heightWeight = Clamp(row.preferredHeight,
            median * 0.5, median * 2)
        weightSum = weightSum + row.heightWeight
    end

    local gapsHeight = math_max(0, (#rows - 1) * TILE_GAP)
    local contentHeight = gapsHeight
    if overflow then
        for _, row in ipairs(rows) do
            row.height = math_max(MIN_ROW_HEIGHT, row.heightWeight)
            contentHeight = contentHeight + row.height
        end
        return contentHeight
    end

    local availableHeight = math_max(
        MIN_ROW_HEIGHT * #rows,
        visibleHeight - gapsHeight
    )
    local remainingHeight = availableHeight
    local remainingWeight = weightSum
    local remainingRows = #rows
    while remainingRows > 0 do
        local appliedFloor = false
        for _, row in ipairs(rows) do
            if not row.height then
                local proposedHeight = remainingHeight
                    * row.heightWeight / remainingWeight
                if proposedHeight < MIN_ROW_HEIGHT then
                    row.height = MIN_ROW_HEIGHT
                    remainingHeight = remainingHeight - MIN_ROW_HEIGHT
                    remainingWeight = remainingWeight - row.heightWeight
                    remainingRows = remainingRows - 1
                    appliedFloor = true
                end
            end
        end
        if not appliedFloor then
            for _, row in ipairs(rows) do
                if not row.height then
                    row.height = remainingHeight
                        * row.heightWeight / remainingWeight
                    remainingRows = remainingRows - 1
                end
            end
        end
    end
    for _, row in ipairs(rows) do
        contentHeight = contentHeight + row.height
    end
    return contentHeight
end

local UpdateScrollThumb

local function ApplyTileBorder(tile, color)
    ST.ApplyBorderTextures(
        tile.borderTextures,
        tile,
        color,
        1,
        ST.BORDER_RENDER_MODE_CRISP
    )
end

local function DisableTileBorderTexelSnapping(textures)
    for index = 1, 4 do
        local texture = textures[index]
        texture:SetSnapToPixelGrid(false)
        texture:SetTexelSnappingBias(0)
    end
end

local function SetScrollOffset(overview, offset)
    offset = Clamp(offset or 0, 0, overview.maxScroll or 0)
    overview.scrollOffset = offset
    overview.scroll:SetVerticalScroll(offset)
    if UpdateScrollThumb then
        UpdateScrollThumb(overview)
    end
end

local function EnsureTile(overview, index)
    local tile = overview.tiles[index]
    if tile then return tile end

    tile = CreateFrame("Button", nil, overview.content, "BackdropTemplate")
    tile:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
    })
    tile:SetBackdropColor(0, 0, 0, 0)
    tile:SetClipsChildren(true)
    tile.borderTextures = ST.CreateBorderTextureSet(tile, "OVERLAY", 7)
    DisableTileBorderTexelSnapping(tile.borderTextures)
    ApplyTileBorder(tile, TILE_BORDER_COLOR)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile:EnableMouseWheel(true)

    local visualHost = CreateFrame("Frame", nil, tile)
    visualHost:SetClipsChildren(true)
    visualHost:SetFrameLevel(tile:GetFrameLevel() + 1)
    tile.visualHost = visualHost

    local label = CreateFrame("Frame", nil, tile, "BackdropTemplate")
    label:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    label:SetBackdropColor(0, 0, 0, 0)
    label:SetFrameLevel(tile:GetFrameLevel() + 3)
    label:EnableMouse(false)
    tile.label = label

    label.text = label:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label.text:SetPoint("LEFT", label, "LEFT", 5, 0)
    label.text:SetPoint("RIGHT", label, "RIGHT", -5, 0)
    label.text:SetJustifyH("LEFT")
    label.text:SetWordWrap(false)

    tile:SetScript("OnClick", function(self, button)
        local record = self._cdcOverviewRecord
        if not record then return end
        if button == "LeftButton" and ST._SelectConfigPanel then
            ST._SelectConfigPanel(record.panelId, { containerId = record.containerId })
            CooldownCompanion:RefreshConfigPanel()
        elseif button == "RightButton" and ST._ShowPanelContextMenu then
            GameTooltip:Hide()
            ST._ShowPanelContextMenu(record.panelId, record.containerId)
        end
    end)
    tile:SetScript("OnEnter", function(self)
        local record = self._cdcOverviewRecord
        if not record then return end
        self:SetBackdropColor(0, 0, 0, 0)
        ApplyTileBorder(self, TILE_HOVER_BORDER_COLOR)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(record.name, 1, 1, 1)
        GameTooltip:AddLine("Click to configure", 0.72, 0.82, 0.92)
        GameTooltip:AddLine("Right-click for options", 0.62, 0.72, 0.82)
        GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0, 0, 0)
        ApplyTileBorder(self, TILE_BORDER_COLOR)
        if GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)
    tile:SetScript("OnMouseWheel", function(_, delta)
        SetScrollOffset(overview, (overview.scrollOffset or 0) - (delta * SCROLL_STEP))
    end)

    overview.tiles[index] = tile
    return tile
end

local function EnsureOverview(host)
    local overview = host._cdcGroupPanelOverview
    if overview then return overview end

    overview = {
        host = host,
        tiles = {},
        usedTiles = 0,
        scrollOffset = 0,
        maxScroll = 0,
    }
    host._cdcGroupPanelOverview = overview

    local root = CreateFrame("Frame", nil, host, "BackdropTemplate")
    root:SetAllPoints(host)
    root:SetClipsChildren(true)
    root:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    root:SetBackdropColor(0, 0, 0, 0)
    root:EnableMouseWheel(true)
    root:Hide()
    overview.root = root

    local scroll = CreateFrame("ScrollFrame", nil, root)
    scroll:SetPoint("TOPLEFT", root, "TOPLEFT", OUTER_PADDING, -OUTER_PADDING)
    scroll:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -OUTER_PADDING, OUTER_PADDING)
    scroll:EnableMouseWheel(true)
    overview.scroll = scroll

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)
    overview.content = content

    local empty = root:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER", root, "CENTER", 0, 0)
    empty:SetText("No panels in this group")
    empty:Hide()
    overview.empty = empty

    local scrollTrack = CreateFrame("Frame", nil, root)
    scrollTrack:SetPoint("TOPRIGHT", root, "TOPRIGHT", -2, -OUTER_PADDING)
    scrollTrack:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -2, OUTER_PADDING)
    scrollTrack:SetWidth(SCROLL_TRACK_WIDTH)
    scrollTrack:Hide()
    overview.scrollTrack = scrollTrack

    scrollTrack.bg = scrollTrack:CreateTexture(nil, "BACKGROUND")
    scrollTrack.bg:SetAllPoints()
    scrollTrack.bg:SetColorTexture(0.12, 0.15, 0.19, 0.8)

    local thumb = scrollTrack:CreateTexture(nil, "ARTWORK")
    thumb:SetColorTexture(0.38, 0.58, 0.74, 0.9)
    thumb:SetWidth(SCROLL_TRACK_WIDTH)
    overview.scrollThumb = thumb

    local function OnMouseWheel(_, delta)
        SetScrollOffset(overview, (overview.scrollOffset or 0) - (delta * SCROLL_STEP))
    end
    root:SetScript("OnMouseWheel", OnMouseWheel)
    scroll:SetScript("OnMouseWheel", OnMouseWheel)

    return overview
end

UpdateScrollThumb = function(overview)
    if not overview.scrollTrack:IsShown() then return end
    local trackHeight = math_max(1, overview.visibleHeight or 1)
    local contentHeight = math_max(trackHeight, overview.contentHeight or trackHeight)
    local thumbHeight = math_max(20, trackHeight * (trackHeight / contentHeight))
    local travel = math_max(0, trackHeight - thumbHeight)
    local fraction = (overview.maxScroll or 0) > 0
        and (overview.scrollOffset or 0) / overview.maxScroll or 0
    overview.scrollThumb:SetHeight(thumbHeight)
    overview.scrollThumb:ClearAllPoints()
    overview.scrollThumb:SetPoint("TOP", overview.scrollTrack, "TOP", 0, -(travel * fraction))
end

local function ResetOverview(overview)
    if GameTooltip:GetOwner() then
        for index = 1, overview.usedTiles do
            if GameTooltip:GetOwner() == overview.tiles[index] then
                GameTooltip:Hide()
                break
            end
        end
    end
    for index = 1, overview.usedTiles do
        local tile = overview.tiles[index]
        if ST._ReleaseReadOnlyPanelPreview then
            ST._ReleaseReadOnlyPanelPreview(tile.visualHost)
        end
        tile._cdcOverviewRecord = nil
        tile:Hide()
    end
    overview.usedTiles = 0
    overview.empty:Hide()
    overview.scrollTrack:Hide()
end

function ST._BuildGroupPanelOverview(host, containerId)
    if not (host and containerId) then return end
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local container = db and db.groupContainers and db.groupContainers[containerId]
    if not container then return end

    local overview = EnsureOverview(host)
    local sameContainer = overview.containerId == containerId
    ResetOverview(overview)
    overview.containerId = containerId
    overview.root:Show()
    overview.scroll:Show()

    local panels = CooldownCompanion:GetPanels(containerId) or {}
    if #panels == 0 then
        overview.scroll:Hide()
        overview.empty:Show()
        overview.maxScroll = 0
        overview.scrollOffset = 0
        return
    end

    local records = {}
    for index, panelInfo in ipairs(panels) do
        local tile = EnsureTile(overview, index)
        tile.visualHost:SetSize(1, 1)
        local _, naturalWidth, naturalHeight = ST._BuildReadOnlyPanelPreview(
            tile.visualHost,
            panelInfo.groupId
        )
        local record = {
            tile = tile,
            containerId = containerId,
            panelId = panelInfo.groupId,
            name = panelInfo.group.name or ("Panel " .. tostring(panelInfo.groupId)),
            naturalWidth = math_max(1, tonumber(naturalWidth) or 220),
            naturalHeight = math_max(1, tonumber(naturalHeight) or 90),
        }
        -- Row height is intentionally standardized by the overview. Horizontal
        -- allocation should therefore follow the Panel's saved-design width,
        -- not its area (which over-rewards tall, narrow Panels).
        record.weight = record.naturalWidth
        records[index] = record
        tile._cdcOverviewRecord = record
        ApplyTileBorder(tile, TILE_BORDER_COLOR)
    end
    overview.usedTiles = #records

    local hostWidth = host:GetWidth() or 0
    local hostHeight = host:GetHeight() or 0
    if hostWidth < 100 then hostWidth = 700 end
    if hostHeight < 80 then hostHeight = 240 end
    local visibleWidth = math_max(1, hostWidth - (OUTER_PADDING * 2))
    local visibleHeight = math_max(1, hostHeight - (OUTER_PADDING * 2))
    local columns = GetColumnCount(#records)
    local rowCount = math_ceil(#records / columns)
    local minimumContentHeight = (rowCount * MIN_ROW_HEIGHT)
        + ((rowCount - 1) * TILE_GAP)
    local overflow = minimumContentHeight > visibleHeight + 0.5
    local layoutWidth = math_max(1, visibleWidth - (overflow and SCROLL_RESERVE or 0))
    local rows = BuildRowLayouts(records, columns, layoutWidth)
    local contentHeight = AllocateRowHeights(rows, visibleHeight, overflow)

    overview.visibleHeight = visibleHeight
    overview.contentHeight = contentHeight
    overview.maxScroll = math_max(0, contentHeight - visibleHeight)
    -- Keep the scroll child matched to the viewport width; `layoutWidth`
    -- reserves only the right-edge scroll affordance from the tile grid.
    overview.content:SetSize(visibleWidth, math_max(visibleHeight, contentHeight))
    overview.scrollTrack:SetShown(overflow)

    local tileTop = 0
    for _, row in ipairs(rows) do
        for _, item in ipairs(row.items) do
            local record = item.record
            local tile = record.tile
            local tileWidth = item.width
            local tileScale = tile:GetEffectiveScale()
            local snappedX = PixelUtil.GetNearestPixelSize(item.x, tileScale)
            local snappedRight = PixelUtil.GetNearestPixelSize(
                item.x + tileWidth, tileScale)
            local snappedTop = PixelUtil.GetNearestPixelSize(tileTop, tileScale)
            local snappedBottom = PixelUtil.GetNearestPixelSize(
                tileTop + row.height, tileScale)
            local onePixel = PixelUtil.GetNearestPixelSize(0, tileScale, 1)
            local snappedTileWidth = math_max(onePixel, snappedRight - snappedX)
            local snappedTileHeight = math_max(onePixel,
                snappedBottom - snappedTop)
            local labelHeight = #records > 1 and LABEL_HEIGHT or 0
            local visualWidth = math_max(1,
                snappedTileWidth - (TILE_INSET * 2))
            local visualHeight = math_max(1,
                snappedTileHeight - labelHeight - (TILE_INSET * 2))

            tile:ClearAllPoints()
            PixelUtil.SetPoint(tile, "TOPLEFT", overview.content, "TOPLEFT",
                snappedX, -snappedTop)
            PixelUtil.SetSize(tile, snappedTileWidth, snappedTileHeight, 1, 1)

            tile.label:ClearAllPoints()
            if labelHeight > 0 then
                tile.label:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1)
                tile.label:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -1, -1)
                tile.label:SetHeight(labelHeight)
                tile.label.text:SetText(record.name)
                tile.label:Show()
            else
                tile.label:Hide()
            end

            tile.visualHost:ClearAllPoints()
            tile.visualHost:SetPoint("CENTER", tile, "CENTER", 0, -(labelHeight / 2))
            tile.visualHost:SetSize(visualWidth, visualHeight)
            tile:Show()
            ST._BuildReadOnlyPanelPreview(tile.visualHost, record.panelId)
        end
        tileTop = tileTop + row.height + TILE_GAP
    end

    if not sameContainer then
        overview.scrollOffset = 0
    end
    SetScrollOffset(overview, overview.scrollOffset or 0)
end

function ST._ReleaseGroupPanelOverview(host)
    local overview = host and host._cdcGroupPanelOverview
    if not overview then return end
    ResetOverview(overview)
    overview.containerId = nil
    overview.maxScroll = 0
    overview.scrollOffset = 0
    overview.root:Hide()
end
