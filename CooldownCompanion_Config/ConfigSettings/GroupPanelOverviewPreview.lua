--[[
    CooldownCompanion - Group Panel Overview Preview
    Organized, read-only Panel mirrors for a selected Group. Every tile selects
    the same Panel destination as the Navigator, while runtime-relative
    positioning and entry interaction stay out of scope.

    Creating a Panel happens here too. A populated Group gets an add tile in the
    grid's last row, wearing the content tiles' own border so it reads as part
    of the surface. An empty Group instead gets the create surface itself: a
    centered block that says why the Group is empty, then a picker of clickable
    panel-type cards -- the two everyday types large, the specialists quiet
    below -- and a Cooldown Manager starter card. A Group that cannot take a new
    Panel (Browse Other Classes, invalid class scope) keeps the plain label and
    nothing clickable.
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
local RESOURCE_BADGE_SIZE = 24
local RESOURCE_BADGE_INSET = 4
local RESOURCE_BADGE_ATLAS = "Waypoint-MapPin-Tracked"
local TILE_BORDER_COLOR = { 0.24, 0.34, 0.46, 0.85 }
-- PanelShared loads before this file and owns the one create accent. The tiles'
-- hover border is that accent at full strength, so it aliases rather than
-- restates it: there is no second cyan to keep in sync.
local CREATE_ACCENT = ST._CREATE_ACCENT
local TILE_HOVER_BORDER_COLOR = CREATE_ACCENT.hoverBorder

-- The add tile wears the content tiles' own border, idle and hover, so it
-- reads as one of them rather than as separate chrome. Only the glyph tells
-- them apart.
local ADD_TILE_WIDTH = 64
-- Below this the grid is too cramped to give up a lane, so the tile steps
-- aside and the Group context menu carries the create action alone.
local ADD_TILE_MIN_GRID_WIDTH = 120
local ADD_TILE_GLYPH_COLOR = { 0.62, 0.72, 0.82 }

-- Empty-Group create surface. The preview host is far wider than either the
-- prose or the picker wants to be, so the whole block is centered and each band
-- is capped on its own: the header keeps a readable measure, and the cards get
-- more room because they carry six side-by-side faces instead of one sentence.
local EMPTY_STATE_MAX_TEXT_WIDTH = 640
local EMPTY_STATE_MAX_CARD_WIDTH = 960
local EMPTY_STATE_TOP_PADDING = 12
local EMPTY_STATE_BOTTOM_PADDING = 12
local EMPTY_STATE_HEADING_SIZE = 15
local EMPTY_STATE_BODY_SIZE = 12
local EMPTY_STATE_SUBLINE_GAP = 6
local EMPTY_STATE_DIVIDER_GAP = 10
local EMPTY_STATE_DIVIDER_HEIGHT = 1.5
local EMPTY_STATE_DIVIDER_ALPHA = 0.8
local EMPTY_STATE_SECTION_GAP = 14
local EMPTY_STATE_SUBLINE_COLOR = { 0.7, 0.7, 0.7 }
local EMPTY_STATE_HEADING_TEXT = "This group is empty."
local EMPTY_STATE_SUBLINE_TEXT = "Panels display the spells and items you track. Choose a type below to get started."

-- Panel-type picker. Every card says what it makes on its own face, centered,
-- so nothing here needs a tooltip to be understood.
local CARD_GAP = 8
-- Wider than the gap between cards, so the drop from the two everyday types to
-- the four specialists reads as a change in rank and not as another row.
local CARD_TIER_GAP = 12
local CARD_TITLE_BODY_GAP = 4
local CARD_BODY_COLOR = { 0.72, 0.82, 0.92 }
local CARD_BODY_FONT = "GameFontHighlight"

-- The two tiers differ only in weight: same face, same centering, smaller type
-- and tighter padding for the quiet one. `columnChoices` is tried widest-first
-- and the first count the band can hold wins. The specialists skip 3 on
-- purpose: four cards in threes leave a lone orphan on the second row.
local PRIMARY_CARD_STYLE = {
    titleFont = "GameFontNormalLarge",
    bodyFont = CARD_BODY_FONT,
    titleHeight = 22,
    padding = 12,
    minHeight = 96,
    minWidth = 220,
    columnChoices = { 2, 1 },
}
local SECONDARY_CARD_STYLE = {
    titleFont = "GameFontNormal",
    bodyFont = CARD_BODY_FONT,
    titleHeight = 18,
    padding = 8,
    minHeight = 0,
    minWidth = 168,
    columnChoices = { 4, 2, 1 },
}
-- The everyday row must never end up shorter than the quiet one below it, which
-- the Trigger Panel's long blurb can otherwise force.
local PRIMARY_CARD_HEIGHT_LEAD = 12

-- The Cooldown Manager starter is a different kind of offer, so it wears gold
-- rather than the create accent and answers hover with its border alone.
local STARTER_CARD_BORDER_COLOR = { 0.62, 0.52, 0.28, 0.95 }
local STARTER_CARD_HOVER_BORDER_COLOR = { 0.86, 0.72, 0.38, 1 }
local STARTER_CARD_FILL_COLOR = { 0.16, 0.13, 0.07, 0.80 }
local STARTER_CARD_TITLE = "Start from the Cooldown Manager"
local STARTER_CARD_BODY =
    "Adds the Cooldown Manager starter panels this group is missing."

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

-- `lastRowWidth` narrows the final row only, which is how the add tile claims
-- its lane: every row above keeps the width it would have had, and the column
-- count, weight clamp, and centering are untouched. It defaults to
-- `layoutWidth`, so a caller that wants no lane passes nothing.
local function BuildRowLayouts(records, columns, layoutWidth, lastRowWidth)
    local rows = {}
    local recordIndex = 1

    while recordIndex <= #records do
        local rowCount = math_min(columns, #records - recordIndex + 1)
        local isLastRow = (recordIndex + rowCount - 1) >= #records
        local rowWidth = (isLastRow and lastRowWidth) or layoutWidth
        local baseColumnWidth = (rowWidth - ((columns - 1) * TILE_GAP))
            / columns
        local rowSpan = (baseColumnWidth * rowCount)
            + ((rowCount - 1) * TILE_GAP)
        local rowStartX = (rowWidth - rowSpan) / 2
        local distributableWidth = rowSpan - ((rowCount - 1) * TILE_GAP)
        local median = math_max(1, GetRowMedian(records, recordIndex, rowCount))
        local weightSum = 0
        local row = {
            items = {},
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

    local resourceBadge = CreateFrame("Frame", nil, tile)
    resourceBadge:SetSize(RESOURCE_BADGE_SIZE, RESOURCE_BADGE_SIZE)
    resourceBadge:SetPoint("TOPRIGHT", tile, "TOPRIGHT",
        -RESOURCE_BADGE_INSET, -RESOURCE_BADGE_INSET)
    resourceBadge:SetFrameLevel(tile:GetFrameLevel() + 4)
    resourceBadge:EnableMouse(false)
    resourceBadge.icon = resourceBadge:CreateTexture(nil, "OVERLAY")
    resourceBadge.icon:SetAllPoints()
    resourceBadge.icon:SetAtlas(RESOURCE_BADGE_ATLAS, false)
    resourceBadge:Hide()
    tile.resourceBadge = resourceBadge

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
        if record.hasAttachedResources then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Resource Bars are attached to this panel.",
                1, 1, 1, true)
        end
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

-- The create affordance for the whole surface. It lives in the same scroll
-- child as the Panel tiles so it inherits their scrolling and wheel routing,
-- and it borrows their border at both idle and hover: this is a tile among
-- tiles, and only the glyph says what it does.
local function EnsureAddTile(overview)
    local tile = overview.addTile
    if tile then return tile end

    tile = CreateFrame("Button", nil, overview.content, "BackdropTemplate")
    tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    tile:SetBackdropColor(0, 0, 0, 0)
    tile.borderTextures = ST.CreateBorderTextureSet(tile, "OVERLAY", 7)
    DisableTileBorderTexelSnapping(tile.borderTextures)
    ApplyTileBorder(tile, TILE_BORDER_COLOR)
    tile:RegisterForClicks("LeftButtonUp")
    tile:EnableMouseWheel(true)
    -- Layout shows it; until then it must not float over the surface.
    tile:Hide()

    local glyph = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    glyph:SetPoint("CENTER", tile, "CENTER", 0, 0)
    glyph:SetText("+")
    glyph:SetTextColor(ADD_TILE_GLYPH_COLOR[1], ADD_TILE_GLYPH_COLOR[2],
        ADD_TILE_GLYPH_COLOR[3])
    tile.glyph = glyph

    tile:SetScript("OnClick", function(self)
        local containerId = self._cdcAddContainerId
        -- The click lands after the build pass, so the Group may already be
        -- gone or out of scope. Re-answer the create gate before acting.
        if not (containerId and ST._IsCreateTargetContainer
            and ST._IsCreateTargetContainer(containerId)) then
            return
        end
        if ST._ShowPanelTypeMenuForContainer then
            ST._ShowPanelTypeMenuForContainer(containerId)
        end
    end)
    tile:SetScript("OnEnter", function(self)
        ApplyTileBorder(self, TILE_HOVER_BORDER_COLOR)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Add Panel", 1, 1, 1)
        GameTooltip:AddLine("Click to choose a panel type", 0.72, 0.82, 0.92)
        GameTooltip:Show()
    end)
    tile:SetScript("OnLeave", function(self)
        ApplyTileBorder(self, TILE_BORDER_COLOR)
        if GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)
    tile:SetScript("OnMouseWheel", function(_, delta)
        SetScrollOffset(overview, (overview.scrollOffset or 0) - (delta * SCROLL_STEP))
    end)

    overview.addTile = tile
    return tile
end

-- Pixel-snapped placement in scroll-child coordinates, matching how the Panel
-- tiles are placed so the add tile lands on the same grid lines they do.
local function PlaceAddTile(overview, tile, x, y, width, height)
    local scale = tile:GetEffectiveScale()
    local snappedX = PixelUtil.GetNearestPixelSize(x, scale)
    local snappedRight = PixelUtil.GetNearestPixelSize(x + width, scale)
    local snappedTop = PixelUtil.GetNearestPixelSize(y, scale)
    local snappedBottom = PixelUtil.GetNearestPixelSize(y + height, scale)
    local onePixel = PixelUtil.GetNearestPixelSize(0, scale, 1)

    tile:ClearAllPoints()
    PixelUtil.SetPoint(tile, "TOPLEFT", overview.content, "TOPLEFT",
        snappedX, -snappedTop)
    PixelUtil.SetSize(tile,
        math_max(onePixel, snappedRight - snappedX),
        math_max(onePixel, snappedBottom - snappedTop), 1, 1)
    ApplyTileBorder(tile, TILE_BORDER_COLOR)
    tile:Show()
end

local function ShowPlainEmptyLabel(overview)
    overview.scroll:Hide()
    overview.empty:Show()
    overview.maxScroll = 0
    overview.scrollOffset = 0
end

------------------------------------------------------------------------
-- Empty-Group create surface
------------------------------------------------------------------------

-- Keeps the shipped font of a template while asking for a specific size, so
-- the block follows the client's font choice and only its measure is ours.
local function ApplyFontSize(fontString, size)
    local file, _, flags = fontString:GetFont()
    if file then
        fontString:SetFont(file, size, flags)
    end
end

local function NewEmptyStateLine(block, size, color)
    local line = block:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ApplyFontSize(line, size)
    line:SetJustifyH("CENTER")
    if color then
        line:SetTextColor(color[1], color[2], color[3])
    end
    if ST._ConfigureWrappedHelperLabel then
        ST._ConfigureWrappedHelperLabel(line)
    end
    return line
end

-- The block and its header fixtures outlive a rebuild. The picker cards are
-- pooled too, but they are re-styled from scratch every build, so nothing about
-- one card's last tier can survive into its next one.
local function EnsureEmptyStateBlock(overview)
    local block = overview.emptyBlock
    if block then return block end

    block = CreateFrame("Frame", nil, overview.content)
    block:EnableMouse(false)
    block:Hide()
    overview.emptyBlock = block

    block.heading = NewEmptyStateLine(block, EMPTY_STATE_HEADING_SIZE)
    block.heading:SetText(EMPTY_STATE_HEADING_TEXT)

    block.subline = NewEmptyStateLine(block, EMPTY_STATE_BODY_SIZE,
        EMPTY_STATE_SUBLINE_COLOR)
    block.subline:SetText(EMPTY_STATE_SUBLINE_TEXT)

    block.divider = block:CreateTexture(nil, "ARTWORK")

    return block
end

------------------------------------------------------------------------
-- Panel-type picker cards
------------------------------------------------------------------------

local function ApplyCardFill(card, color)
    if not color then return end
    card:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
end

-- One pooled card family serves both tiers and the starter, so every card must
-- be told its whole appearance on every configure. Idle and hover live on the
-- card itself because the scripts are installed once and the look changes per
-- build. A nil hover fill means "keep the idle fill", which is how the starter
-- answers the cursor with its border alone.
local function EnsurePickerCard(overview, block, index)
    local card = overview.cards[index]
    if card then return card end

    card = CreateFrame("Button", nil, block, "BackdropTemplate")
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    card:SetBackdropColor(0, 0, 0, 0)
    card.borderTextures = ST.CreateBorderTextureSet(card, "OVERLAY", 7)
    DisableTileBorderTexelSnapping(card.borderTextures)
    card:RegisterForClicks("LeftButtonUp")
    card:EnableMouseWheel(true)
    -- Layout shows it; until then it must not float over the surface.
    card:Hide()

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.body = card:CreateFontString(nil, "OVERLAY", CARD_BODY_FONT)

    card:SetScript("OnClick", function(self)
        local create = self._cdcOverviewCreate
        if not create then return end
        local containerId = create.containerId
        -- The click lands after the build pass, so the Group may already be
        -- gone or out of scope. Re-answer the create gate before acting.
        if not (containerId and ST._IsCreateTargetContainer
            and ST._IsCreateTargetContainer(containerId)) then
            return
        end
        if create.cdmStarter then
            if ST._CreateMissingCDMPanelsInSelectedContainer then
                ST._CreateMissingCDMPanelsInSelectedContainer(containerId)
            end
        elseif create.mode and ST._CreatePanelInContainer then
            ST._CreatePanelInContainer(containerId, create.mode)
        end
    end)
    card:SetScript("OnEnter", function(self)
        if not self._cdcOverviewCreate then return end
        ApplyTileBorder(self, self._cdcHoverBorder or self._cdcIdleBorder)
        ApplyCardFill(self, self._cdcHoverFill or self._cdcIdleFill)
    end)
    card:SetScript("OnLeave", function(self)
        ApplyTileBorder(self, self._cdcIdleBorder)
        ApplyCardFill(self, self._cdcIdleFill)
    end)
    card:SetScript("OnMouseWheel", function(_, delta)
        SetScrollOffset(overview, (overview.scrollOffset or 0) - (delta * SCROLL_STEP))
    end)

    overview.cards[index] = card
    return card
end

local function AnchorPickerCardText(card, style, topOffset)
    card.title:ClearAllPoints()
    card.title:SetPoint("TOP", card, "TOP", 0, -topOffset)
    card.body:ClearAllPoints()
    card.body:SetPoint("TOP", card, "TOP", 0,
        -(topOffset + style.titleHeight + CARD_TITLE_BODY_GAP))
end

-- Re-asserted on every configure, because a card reused from the other tier
-- still carries that tier's font, insets, and anchors. Title and description
-- are both centered on the card's own text column: the face says what it makes,
-- so nothing has to be hovered to be read. The padding anchors are also the
-- neutral measurement position; placement centers the measured block later.
local function ApplyPickerCardStyle(card, style, textWidth)
    card.title:SetFontObject(_G[style.titleFont])
    card.title:SetWidth(textWidth)
    card.title:SetHeight(style.titleHeight)
    card.title:SetJustifyH("CENTER")
    card.title:SetJustifyV("MIDDLE")
    card.title:SetWordWrap(false)

    card.body:SetFontObject(_G[style.bodyFont])
    card.body:SetWidth(textWidth)
    card.body:SetJustifyH("CENTER")
    card.body:SetJustifyV("TOP")
    card.body:SetTextColor(CARD_BODY_COLOR[1], CARD_BODY_COLOR[2],
        CARD_BODY_COLOR[3])
    if ST._ConfigureWrappedHelperLabel then
        ST._ConfigureWrappedHelperLabel(card.body)
    end
    AnchorPickerCardText(card, style, style.padding)
end

local function ApplyPickerCardAccent(card, accent)
    card._cdcIdleBorder = accent.idleBorder
    card._cdcHoverBorder = accent.hoverBorder
    card._cdcIdleFill = accent.idleFill
    card._cdcHoverFill = accent.hoverFill
    ApplyTileBorder(card, accent.idleBorder)
    ApplyCardFill(card, accent.idleFill)
end

-- The starter's hover fill stays nil on purpose: see ApplyCardFill.
local CARD_STARTER_ACCENT = {
    idleBorder = STARTER_CARD_BORDER_COLOR,
    hoverBorder = STARTER_CARD_HOVER_BORDER_COLOR,
    idleFill = STARTER_CARD_FILL_COLOR,
    hoverFill = nil,
}

-- Widest count the band can hold wins, so a narrow host collapses 2 -> 1 and
-- 4 -> 2 -> 1 instead of squeezing unreadable cards.
local function ResolveTierColumns(style, bandWidth)
    for _, columns in ipairs(style.columnChoices) do
        local needed = (columns * style.minWidth)
            + ((columns - 1) * CARD_GAP)
        if bandWidth >= needed then
            return columns
        end
    end
    return 1
end

-- Styles and fills one tier's cards and reports the geometry the block needs,
-- without placing anything: the everyday row cannot be positioned until the
-- quiet row below it has confessed its height. `forceColumns` is for the
-- starter, which is one full-width offer rather than a tier that packs.
local function MeasurePickerTier(overview, block, firstIndex, entries, style,
    bandWidth, forceColumns)
    local columns = forceColumns or ResolveTierColumns(style, bandWidth)
    local cardWidth = (bandWidth - ((columns - 1) * CARD_GAP)) / columns
    local textWidth = math_max(1, cardWidth - (style.padding * 2))
    local bodyHeight = 0

    for offset, entry in ipairs(entries) do
        local card = EnsurePickerCard(overview, block, firstIndex + offset - 1)
        ApplyPickerCardStyle(card, style, textWidth)
        card.title:SetText(entry.title)
        card.body:SetText(entry.body)
        -- Shown before the wrapped height is read, for the same reason the
        -- block is: the measurement should come from a live region. Placement
        -- follows in this same pass, so nothing is left floating.
        card:Show()
        bodyHeight = math_max(bodyHeight, card.body:GetStringHeight() or 0)
    end

    -- One height for the whole tier, taken from its tallest wrapped
    -- description, so the row reads as a row instead of a ragged edge.
    local height = math_max(style.minHeight or 0,
        (style.padding * 2) + style.titleHeight + CARD_TITLE_BODY_GAP
            + bodyHeight)

    return {
        columns = columns,
        cardWidth = cardWidth,
        height = height,
        count = #entries,
    }
end

-- Places an already-measured tier centered on the block and returns the height
-- it consumed, which grows when a narrow band pushes the tier onto more rows.
local function PlacePickerTier(overview, block, firstIndex, entries, metrics,
    style, containerId, accent, top)
    if metrics.count == 0 then
        return 0
    end

    local placed = 0
    local y = top
    while placed < metrics.count do
        local rowCount = math_min(metrics.columns, metrics.count - placed)
        local rowSpan = (rowCount * metrics.cardWidth)
            + ((rowCount - 1) * CARD_GAP)
        local x = -(rowSpan / 2)
        for offset = 1, rowCount do
            local entry = entries[placed + offset]
            local card = overview.cards[firstIndex + placed + offset - 1]
            card._cdcOverviewCreate = {
                containerId = containerId,
                mode = entry.mode,
                cdmStarter = entry.cdmStarter,
            }
            ApplyPickerCardAccent(card, accent)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", block, "TOP", x, -y)
            card:SetSize(math_max(1, metrics.cardWidth),
                math_max(1, metrics.height))
            local bodyHeight = card.body:GetStringHeight() or 0
            local contentHeight = style.titleHeight + CARD_TITLE_BODY_GAP
                + bodyHeight
            local textOffset = math_max(style.padding,
                (metrics.height - contentHeight) / 2)
            -- Recomputed after every configure, once this tier's final height
            -- is known, so pooled cards cannot retain another tier's offset.
            AnchorPickerCardText(card, style, textOffset)
            card:Show()
            x = x + metrics.cardWidth + CARD_GAP
        end
        placed = placed + rowCount
        y = y + metrics.height + CARD_GAP
    end

    return (y - top) - CARD_GAP
end

-- Lays the whole block out top-down in block coordinates and returns its
-- height, which is what tells the caller whether the surface needs to scroll.
local function LayoutEmptyStateBlock(overview, containerId, visibleWidth)
    local block = EnsureEmptyStateBlock(overview)
    block:SetWidth(visibleWidth)
    -- Shown before measuring: the caller only positions it afterwards, and the
    -- string heights this pass reads should come from a live region.
    block:Show()

    local textWidth = math_max(1,
        math_min(visibleWidth, EMPTY_STATE_MAX_TEXT_WIDTH))
    local y = EMPTY_STATE_TOP_PADDING

    local function PlaceLine(line, gapBefore)
        y = y + (gapBefore or 0)
        line:SetWidth(textWidth)
        line:ClearAllPoints()
        line:SetPoint("TOP", block, "TOP", 0, -y)
        line:Show()
        y = y + math_max(1, line:GetStringHeight() or 0)
    end

    PlaceLine(block.heading)
    PlaceLine(block.subline, EMPTY_STATE_SUBLINE_GAP)

    -- GetClassColor is documented MayReturnNothing, so the divider falls back
    -- to the tile border's own blue rather than vanishing.
    local classColor = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    local dividerR = classColor and classColor.r or TILE_BORDER_COLOR[1]
    local dividerG = classColor and classColor.g or TILE_BORDER_COLOR[2]
    local dividerB = classColor and classColor.b or TILE_BORDER_COLOR[3]
    y = y + EMPTY_STATE_DIVIDER_GAP
    block.divider:ClearAllPoints()
    block.divider:SetPoint("TOP", block, "TOP", 0, -y)
    block.divider:SetSize(textWidth, EMPTY_STATE_DIVIDER_HEIGHT)
    block.divider:SetColorTexture(dividerR, dividerG, dividerB,
        EMPTY_STATE_DIVIDER_ALPHA)
    block.divider:Show()
    y = y + EMPTY_STATE_DIVIDER_HEIGHT + EMPTY_STATE_DIVIDER_GAP

    -- Tiers come from the descriptor's own `primary` flag and nothing else, so
    -- promoting a panel type is a one-word edit in PanelShared.
    local primaryEntries, secondaryEntries = {}, {}
    for _, panelType in ipairs(ST._PANEL_TYPES or {}) do
        local tier = panelType.primary and primaryEntries or secondaryEntries
        tier[#tier + 1] = {
            title = panelType.label,
            body = panelType.description,
            mode = panelType.mode,
        }
    end
    local starterEntries = {
        {
            title = STARTER_CARD_TITLE,
            body = STARTER_CARD_BODY,
            cdmStarter = true,
        },
    }

    local cardBandWidth = math_max(1,
        math_min(visibleWidth, EMPTY_STATE_MAX_CARD_WIDTH))
    local primaryFirst = 1
    local secondaryFirst = primaryFirst + #primaryEntries
    local starterFirst = secondaryFirst + #secondaryEntries

    local secondaryMetrics = MeasurePickerTier(overview, block, secondaryFirst,
        secondaryEntries, SECONDARY_CARD_STYLE, cardBandWidth)
    local primaryMetrics = MeasurePickerTier(overview, block, primaryFirst,
        primaryEntries, PRIMARY_CARD_STYLE, cardBandWidth)
    primaryMetrics.height = math_max(primaryMetrics.height,
        secondaryMetrics.height + PRIMARY_CARD_HEIGHT_LEAD)
    -- The starter is one full-width offer, so it never shares a row.
    local starterMetrics = MeasurePickerTier(overview, block, starterFirst,
        starterEntries, SECONDARY_CARD_STYLE, cardBandWidth, 1)

    y = y + PlacePickerTier(overview, block, primaryFirst, primaryEntries,
        primaryMetrics, PRIMARY_CARD_STYLE, containerId, CREATE_ACCENT, y)
    y = y + CARD_TIER_GAP
    y = y + PlacePickerTier(overview, block, secondaryFirst, secondaryEntries,
        secondaryMetrics, SECONDARY_CARD_STYLE, containerId, CREATE_ACCENT, y)
    y = y + EMPTY_STATE_SECTION_GAP
    y = y + PlacePickerTier(overview, block, starterFirst, starterEntries,
        starterMetrics, SECONDARY_CARD_STYLE, containerId,
        CARD_STARTER_ACCENT, y)

    overview.usedCards = starterFirst + #starterEntries - 1

    return y + EMPTY_STATE_BOTTOM_PADDING
end

-- An editable Group with no Panels gets the create surface itself instead of a
-- bare label and glyph. The block rides in the scroll child, so a short host
-- scrolls it rather than clipping the lowest cards out of reach; when it fits,
-- it centers on the surface.
local function BuildEmptyGroupState(overview, host, containerId, sameContainer)
    if not (ST._IsCreateTargetContainer
        and ST._IsCreateTargetContainer(containerId)) then
        ShowPlainEmptyLabel(overview)
        return
    end

    local hostWidth = host:GetWidth() or 0
    local hostHeight = host:GetHeight() or 0
    if hostWidth < 100 then hostWidth = 700 end
    if hostHeight < 80 then hostHeight = 240 end
    local visibleWidth = math_max(1, hostWidth - (OUTER_PADDING * 2))
    local visibleHeight = math_max(1, hostHeight - (OUTER_PADDING * 2))

    -- The heading speaks for the surface here, so the plain label stays down.
    overview.empty:Hide()

    -- Laid out at the full band first. If that overflows, the scroll track is
    -- about to appear, so one re-measure at the narrower band lets the cards
    -- keep clear of it. Exactly one retry: the second pass is never wider than
    -- the first, so it cannot re-open the question it just answered.
    local layoutWidth = visibleWidth
    local blockHeight = LayoutEmptyStateBlock(overview, containerId,
        layoutWidth)
    if blockHeight > visibleHeight and visibleWidth > SCROLL_RESERVE then
        layoutWidth = math_max(1, visibleWidth - SCROLL_RESERVE)
        blockHeight = LayoutEmptyStateBlock(overview, containerId, layoutWidth)
    end
    local block = overview.emptyBlock
    local blockTop = blockHeight < visibleHeight
        and ((visibleHeight - blockHeight) / 2) or 0
    block:SetHeight(math_max(1, blockHeight))
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", overview.content, "TOPLEFT", 0, -blockTop)
    block:Show()

    local contentHeight = math_max(visibleHeight, blockTop + blockHeight)
    overview.visibleHeight = visibleHeight
    overview.contentHeight = contentHeight
    overview.maxScroll = math_max(0, contentHeight - visibleHeight)
    if not sameContainer then
        overview.scrollOffset = 0
    end
    overview.content:SetSize(visibleWidth, contentHeight)
    overview.scrollTrack:SetShown(overview.maxScroll > 0)
    SetScrollOffset(overview, overview.scrollOffset or 0)
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
        -- Panel-type picker cards, pooled across builds the way the Panel tiles
        -- are. Every build re-styles the ones it uses and every reset hides
        -- them and drops their click actions.
        cards = {},
        usedCards = 0,
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
    -- The picker cards go down first, and their create actions go with them, so
    -- a click that lands mid-refresh finds nothing to act on rather than acting
    -- on the Group that just left the screen.
    for index = 1, overview.usedCards do
        local card = overview.cards[index]
        card._cdcOverviewCreate = nil
        card:Hide()
    end
    overview.usedCards = 0
    if overview.emptyBlock then
        overview.emptyBlock:Hide()
    end
    if GameTooltip:GetOwner() then
        if GameTooltip:GetOwner() == overview.addTile then
            GameTooltip:Hide()
        else
            for index = 1, overview.usedTiles do
                if GameTooltip:GetOwner() == overview.tiles[index] then
                    GameTooltip:Hide()
                    break
                end
            end
        end
    end
    for index = 1, overview.usedTiles do
        local tile = overview.tiles[index]
        if ST._ReleaseReadOnlyPanelPreview then
            ST._ReleaseReadOnlyPanelPreview(tile.visualHost)
        end
        tile._cdcOverviewRecord = nil
        tile.resourceBadge:Hide()
        tile:Hide()
    end
    overview.usedTiles = 0
    -- The add tile is released the same way the Panel tiles are: layout shows
    -- it again only where it belongs, so an eligible -> ineligible refresh
    -- cannot leave it floating over the grid.
    if overview.addTile then
        overview.addTile._cdcAddContainerId = nil
        overview.addTile:Hide()
    end
    overview.empty:Hide()
    overview.scrollTrack:Hide()
end

-- The Group overview currently on screen. Only one is ever built at a time, so
-- a module-local handle lets read-only callers find its create controls without
-- reaching into the preview host's private state.
local activeOverview

function ST._BuildGroupPanelOverview(host, containerId)
    if not (host and containerId) then return end
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local container = db and db.groupContainers and db.groupContainers[containerId]
    if not container then return end

    local overview = EnsureOverview(host)
    activeOverview = overview
    ResetOverview(overview)
    local sameContainer = overview.containerId == containerId
    overview.containerId = containerId
    overview.root:Show()
    overview.scroll:Show()

    local panels = CooldownCompanion:GetPanels(containerId) or {}
    if #panels == 0 then
        BuildEmptyGroupState(overview, host, containerId, sameContainer)
        return
    end

    local attachedResourcePanelId
    if ST._GetResourcesEntryPlacement then
        local placement, anchorPanelId = ST._GetResourcesEntryPlacement()
        if placement == "attached" then
            attachedResourcePanelId = anchorPanelId
        end
    end

    local records = {}
    for index, panelInfo in ipairs(panels) do
        local tile = EnsureTile(overview, index)
        local naturalWidth, naturalHeight =
            ST._GetReadOnlyPanelPreviewNaturalSize(panelInfo.groupId)
        local record = {
            tile = tile,
            containerId = containerId,
            panelId = panelInfo.groupId,
            name = panelInfo.group.name or ("Panel " .. tostring(panelInfo.groupId)),
            naturalWidth = math_max(1, tonumber(naturalWidth) or 220),
            naturalHeight = math_max(1, tonumber(naturalHeight) or 90),
            hasAttachedResources = attachedResourcePanelId == panelInfo.groupId,
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
    local idealRowHeight = (visibleHeight - ((rowCount - 1) * TILE_GAP))
        / rowCount
    local rowHeight = math_max(MIN_ROW_HEIGHT, idealRowHeight)
    local contentHeight = (rowCount * rowHeight)
        + ((rowCount - 1) * TILE_GAP)
    local overflow = contentHeight > visibleHeight + 0.5
    local layoutWidth = math_max(1, visibleWidth - (overflow and SCROLL_RESERVE or 0))

    -- The add tile rides in the last row's own band, so it costs the grid a
    -- lane there and nothing anywhere else: row count, content height, and the
    -- scroll math all stay exactly what a bare grid would produce. It steps
    -- aside when the Group cannot take a new Panel, or when giving up the lane
    -- would leave the Panels themselves too narrow to read.
    local gridWidth = layoutWidth - ADD_TILE_WIDTH - TILE_GAP
    local showAddTile = ST._IsCreateTargetContainer
        and ST._IsCreateTargetContainer(containerId)
        and gridWidth >= ADD_TILE_MIN_GRID_WIDTH
    local rows = BuildRowLayouts(records, columns, layoutWidth,
        showAddTile and gridWidth or nil)

    overview.visibleHeight = visibleHeight
    overview.contentHeight = contentHeight
    overview.maxScroll = math_max(0, contentHeight - visibleHeight)
    -- Keep the scroll child matched to the viewport width; `layoutWidth`
    -- reserves only the right-edge scroll affordance from the tile grid.
    overview.content:SetSize(visibleWidth, math_max(visibleHeight, contentHeight))
    overview.scrollTrack:SetShown(overflow)

    local tileTop = 0
    local addTileX, addTileTop
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
                tileTop + rowHeight, tileScale)
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
                tile.label.text:ClearAllPoints()
                tile.label.text:SetPoint("LEFT", tile.label, "LEFT", 5, 0)
                local labelRightInset = record.hasAttachedResources
                    and (RESOURCE_BADGE_SIZE + RESOURCE_BADGE_INSET + 2)
                    or 5
                tile.label.text:SetPoint("RIGHT", tile.label, "RIGHT",
                    -labelRightInset, 0)
                tile.label.text:SetText(record.name)
                tile.label:Show()
            else
                tile.label:Hide()
            end

            tile.resourceBadge:SetShown(record.hasAttachedResources)
            tile.visualHost:ClearAllPoints()
            tile.visualHost:SetPoint("CENTER", tile, "CENTER", 0, -(labelHeight / 2))
            tile.visualHost:SetSize(visualWidth, visualHeight)
            tile:Show()
            ST._BuildReadOnlyPanelPreview(tile.visualHost, record.panelId)
        end
        -- Overwritten each pass, so after the loop these describe the last
        -- row: the lane BuildRowLayouts just reserved sits right of its last
        -- tile, at its top.
        local lastItem = row.items[#row.items]
        if lastItem then
            addTileX = lastItem.x + lastItem.width + TILE_GAP
            addTileTop = tileTop
        end
        tileTop = tileTop + rowHeight + TILE_GAP
    end

    if showAddTile and addTileX then
        local addTile = EnsureAddTile(overview)
        addTile._cdcAddContainerId = containerId
        PlaceAddTile(overview, addTile, addTileX, addTileTop,
            ADD_TILE_WIDTH, rowHeight)
    end

    if not sameContainer then
        overview.scrollOffset = 0
    end
    SetScrollOffset(overview, overview.scrollOffset or 0)
end

function ST._ReleaseGroupPanelOverview(host)
    local overview = host and host._cdcGroupPanelOverview
    if not overview then return end
    if activeOverview == overview then
        activeOverview = nil
    end
    ResetOverview(overview)
    overview.containerId = nil
    overview.maxScroll = 0
    overview.scrollOffset = 0
    overview.root:Hide()
end

-- Read-only lookup of one panel-type card in the empty state's picker, used to
-- point at it without owning it. Only the type cards carry a display mode: the
-- add tile and the Cooldown Manager starter have none, so a lookup by mode can
-- never land on them. Returns nil whenever the picker is not the surface on
-- screen, so callers must tolerate a missing frame.
function ST._GetEmptyPickerCardFrame(mode)
    local overview = activeOverview
    if not (mode and overview and overview.root:IsShown()) then return nil end
    for index = 1, overview.usedCards or 0 do
        local card = overview.cards[index]
        local create = card and card._cdcOverviewCreate
        if create and create.mode == mode and card:IsShown() then
            return card
        end
    end
    return nil
end
