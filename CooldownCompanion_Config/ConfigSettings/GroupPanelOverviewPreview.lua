--[[
    CooldownCompanion - Group Panel Overview Preview
    Organized, read-only Panel mirrors for a selected Group. Every tile selects
    the same Panel destination as the Navigator, while runtime-relative
    positioning and entry interaction stay out of scope.

    Creating a Panel happens here too. A populated Group gets an add tile beside
    the grid's last row, or below the three-column stack, wearing the content
    tiles' own border so it reads as part of the surface. An empty Group
    instead gets the create surface itself: a
    centered picker of clickable panel-type cards -- Panel and Indicator equally
    prominent, Aura and Totem families beneath them, with a header library for
    templates and a Cooldown Manager starter below. A Group that
    cannot take a new Panel (Browse Other Classes, invalid class scope) keeps
    the plain label and nothing clickable.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local math_ceil = math.ceil
local math_max = math.max
local math_min = math.min
local table_sort = table.sort

local OUTER_PADDING = 8
local TILE_GAP = 8
local TILE_INSET = 4
local LABEL_HEIGHT = 18
local STATUS_BADGE_SIZE = 24
local STATUS_BADGE_GAP = 4
local STATUS_BADGE_ATLAS = "GM-icon-visibleDis-pressed"
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
local ADD_ROW_HEIGHT = 40
-- Below this the grid is too cramped to give up a lane, so the tile steps
-- aside and the Group context menu carries the create action alone.
local ADD_TILE_MIN_GRID_WIDTH = 120
local ADD_TILE_GLYPH_COLOR = { 0.62, 0.72, 0.82 }

-- Empty-Group create surface. The preview host is far wider than either the
-- prose or the picker wants to be, so the header and choices each have a
-- readable maximum width within the centered block.
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
local EMPTY_STATE_HEADING_TEXT = "Choose your first panel"
local EMPTY_STATE_SUBLINE_TEXT = "Add a display to this group."

-- Panel-type picker. Every card says what it makes on its own face; ordinary
-- cards also keep the descriptor's fuller explanation as hover help.
local CARD_GAP = 8
local CARD_TIER_GAP = 12
local CARD_TITLE_BODY_GAP = 4
local CARD_TITLE_COLOR = { 1, 0.82, 0 }
local CARD_BODY_COLOR = { 0.72, 0.82, 0.92 }
local CARD_BODY_FONT = "GameFontHighlight"

-- Each family explains its behavior once, above its Icons / Bars choices.
local PICKER_FAMILIES = {
    { key = "aura", label = "Aura Panels",
        description = "Tracked buffs and debuffs, shown while active." },
    { key = "totem", label = "Totem Panels",
        description = "Active totems and summons, added automatically." },
}
local FAMILY_COLLAPSE_NOTE = "Inactive auras and empty totem slots collapse."

local LIBRARY_BUTTON_HEIGHT = 26
local LIBRARY_ICON_ATLAS = "campaign-questlog-lorebook"
local LIBRARY_MODES = { "icons", "indicator", "auraIcons", "auraBars", "totemIcons", "totemBars" }

-- All picker buttons share the same face and centering. Their styles change
-- only hierarchy, density, and whether the body copy is shown. Compact tiers
-- skip 3 columns on purpose: four cards in threes leave a lone orphan.
local PRIMARY_CARD_STYLE = {
    titleFont = "GameFontNormalLarge",
    bodyFont = CARD_BODY_FONT,
    titleHeight = 22,
    padding = 12,
    minHeight = 104,
    minWidth = 220,
    columnChoices = { 2, 1 },
}
local SECONDARY_CARD_STYLE = {
    titleFont = "GameFontNormal",
    bodyFont = CARD_BODY_FONT,
    titleHeight = 18,
    padding = 8,
    minHeight = 48,
    minWidth = 168,
    columnChoices = { 4, 2, 1 },
    titleOnly = true,
}
local FAMILY_CARD_STYLE = {
    titleFont = "GameFontNormal",
    bodyFont = CARD_BODY_FONT,
    titleHeight = 18,
    padding = 6,
    minHeight = 34,
    minWidth = 120,
    columnChoices = { 2, 1 },
    titleOnly = true,
}
local FAMILY_CARD_ACCENT = {
    idleBorder = CREATE_ACCENT.idleBorder,
    hoverBorder = CREATE_ACCENT.hoverBorder,
    idleFill = { 0.13, 0.20, 0.25, 0.88 },
    hoverFill = { 0.16, 0.25, 0.31, 0.92 },
}
local STARTER_CARD_STYLE = {
    titleFont = "GameFontNormal",
    titleColor = EMPTY_STATE_SUBLINE_COLOR,
    bodyFont = CARD_BODY_FONT,
    titleHeight = 18,
    padding = 4,
    minHeight = 30,
    minWidth = 168,
    columnChoices = { 1 },
    titleOnly = true,
}
local TEMPLATE_CARD_STYLE = {
    titleFont = "GameFontNormalLarge",
    bodyFont = CARD_BODY_FONT,
    titleHeight = 22,
    padding = 12,
    minHeight = 72,
    minWidth = 220,
    columnChoices = { 2, 1 },
    titleOnly = true,
    wrapTitle = true,
}

-- The starter stays available as a quiet footer action.
local STARTER_CARD_TITLE = "Start from the Cooldown Manager"
local STARTER_CARD_BODY =
    "Add its starter panels to this group."

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

local function LayoutTileHeader(record, showLabel)
    local tile = record.tile
    local label = tile.label
    local disabled = record.disabledReason ~= nil
    local statusReserve = disabled and (STATUS_BADGE_SIZE + STATUS_BADGE_GAP) or 0
    tile.statusBadge:SetShown(disabled)
    tile.statusBadge:ClearAllPoints()
    tile.statusBadge:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -RESOURCE_BADGE_INSET,
        -(RESOURCE_BADGE_INSET + (record.hasAttachedResources
            and (RESOURCE_BADGE_SIZE - STATUS_BADGE_SIZE) / 2 or 0)))
    tile.resourceBadge:ClearAllPoints()
    tile.resourceBadge:SetPoint("TOPRIGHT", tile, "TOPRIGHT",
        -(RESOURCE_BADGE_INSET + statusReserve), -RESOURCE_BADGE_INSET)
    local height = (showLabel or disabled) and LABEL_HEIGHT or 0
    if disabled then
        height = math_max(height, STATUS_BADGE_SIZE + RESOURCE_BADGE_INSET)
    end
    if height == 0 then
        label:Hide()
        return 0
    end
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", tile, "TOPLEFT", 1, -1)
    label:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -1, -1)
    label.text:ClearAllPoints()
    label.text:SetPoint("LEFT", label, "LEFT", 5, 0)
    local rightInset = record.hasAttachedResources
        and (RESOURCE_BADGE_SIZE + RESOURCE_BADGE_INSET + 2) or 5
    label.text:SetPoint("RIGHT", label, "RIGHT", -(rightInset + statusReserve), 0)
    label:SetHeight(height)
    label:Show()
    return height
end

-- Give each Panel its natural height, then share any spare viewport height
-- across the cards. Include the renderer's padding so mirrors still fit.
local function BuildStackedRowLayouts(records, layoutWidth, layoutHeight, showAddTile)
    local rows = {}
    local contentHeight = 0
    local previewPadding = ST._ButtonPanelPreview.PANEL_PREVIEW_PADDING * 2
    local visualWidth = math_max(1,
        layoutWidth - (TILE_INSET * 2) - previewPadding)
    for _, record in ipairs(records) do
        local scale = math_min(1, visualWidth / record.naturalWidth)
        local height = math_max(MIN_ROW_HEIGHT, math_ceil(
            record.naturalHeight * scale + LABEL_HEIGHT
                + (TILE_INSET * 2) + previewPadding))
        rows[#rows + 1] = {
            height = height,
            items = { { record = record, x = 0, width = layoutWidth } },
        }
        contentHeight = contentHeight + height + TILE_GAP
    end
    -- The trailing gap separates the add row, or goes away with that row.
    contentHeight = contentHeight + (showAddTile and ADD_ROW_HEIGHT or -TILE_GAP)
    if contentHeight < layoutHeight then
        local extraHeight = (layoutHeight - contentHeight) / #rows
        for _, row in ipairs(rows) do
            row.height = row.height + extraHeight
        end
        contentHeight = layoutHeight
    end
    return rows, contentHeight
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

local function SetScrollOffset(overview, offset)
    offset = Clamp(offset or 0, 0, overview.maxScroll or 0)
    overview.scrollOffset = offset
    overview.scroll:SetVerticalScroll(offset)
    if UpdateScrollThumb then
        UpdateScrollThumb(overview)
    end
end

local function RestoreOverviewColors(tile)
    for _, saved in ipairs(tile.disabledVisuals or {}) do
        local region = saved.region
        if saved.texture then
            region:SetDesaturation(saved.desaturation)
            if saved.color[1] then region:SetVertexColor(unpack(saved.color)) end
        else
            if saved.color[1] then region:SetTextColor(unpack(saved.color)) end
            region:SetText(saved.text)
        end
    end
    tile.disabledVisuals = nil
end

-- Only walk the saved-design mirror, never live frames or the tile's chrome.
-- Restore before renderer reuse: some pooled regions retain their last tint.
local function GrayOverviewContents(tile)
    local savedRegions = {}
    -- Keep restoration available even if a later region interrupts the pass.
    tile.disabledVisuals = savedRegions
    local seen = {}
    local function GrayRegion(region)
        if seen[region] then return end
        seen[region] = true
        if region:IsObjectType("Texture") then
            local color = { region:GetVertexColor() }
            savedRegions[#savedRegions + 1] = {
                region = region, texture = true, color = color,
                desaturation = region:GetDesaturation(),
            }
            region:SetDesaturation(1)
            if color[1] then
                local gray = (color[1] + color[2] + color[3]) / 3
                region:SetVertexColor(gray, gray, gray, color[4])
            end
        elseif region:IsObjectType("FontString") then
            local text = region:GetText()
            -- Unused pooled labels can have no text at all.
            if text then
                local color = { region:GetTextColor() }
                savedRegions[#savedRegions + 1] = { region = region, color = color, text = text }
                region:SetTextColor(0.65, 0.65, 0.65, color[4])
                -- Formatted timers can carry inline colors that override SetTextColor.
                region:SetText((text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
            end
        end
    end
    local function GrayFrame(frame)
        for _, region in ipairs({ frame:GetRegions() }) do GrayRegion(region) end
        if frame:IsObjectType("StatusBar") then GrayRegion(frame:GetStatusBarTexture()) end
        for _, child in ipairs({ frame:GetChildren() }) do GrayFrame(child) end
    end
    GrayFrame(tile.visualHost)
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
    ApplyTileBorder(tile, TILE_BORDER_COLOR)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
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
    label.text:SetJustifyV("MIDDLE")
    label.text:SetWordWrap(false)

    local statusBadge = CreateFrame("Frame", nil, tile)
    statusBadge:SetSize(STATUS_BADGE_SIZE, STATUS_BADGE_SIZE)
    statusBadge:SetFrameLevel(tile:GetFrameLevel() + 4)
    statusBadge:EnableMouse(false)
    statusBadge.icon = statusBadge:CreateTexture(nil, "OVERLAY")
    statusBadge.icon:SetAllPoints()
    statusBadge.icon:SetAtlas(STATUS_BADGE_ATLAS, false)
    statusBadge.icon:SetVertexColor(0.65, 0.65, 0.65, 1)
    statusBadge:Hide()
    tile.statusBadge = statusBadge

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
            if CS.spellbookPanelDocked then CS.CloseSpellbookPanel() end
            ST._SelectConfigPanel(record.panelId, { containerId = record.containerId })
            CooldownCompanion:RefreshConfigPanel()
        elseif button == "RightButton" and ST._ShowPanelContextMenu then
            GameTooltip:Hide()
            ST._ShowPanelContextMenu(record.panelId, record.containerId)
        elseif button == "MiddleButton" and record.canToggleAnchorLock
            and ST._TogglePanelAnchorLock then
            GameTooltip:Hide()
            ST._TogglePanelAnchorLock(record.panelId)
        end
    end)
    tile:SetScript("OnEnter", function(self)
        local record = self._cdcOverviewRecord
        if not record then return end
        self:SetBackdropColor(0, 0, 0, 0)
        ApplyTileBorder(self, TILE_HOVER_BORDER_COLOR)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(record.name, 1, 1, 1)
        GameTooltip:AddLine(record.typeLabel, 0.72, 0.82, 0.92)
        if record.disabledReason then
            GameTooltip:AddLine(record.disabledReason, 0.85, 0.84, 0.81)
        end
        GameTooltip:AddLine("Click to configure", 0.72, 0.82, 0.92)
        GameTooltip:AddLine("Right-click for options", 0.62, 0.72, 0.82)
        if record.canToggleAnchorLock then
            GameTooltip:AddLine("Middle-click to lock/unlock", 0.62, 0.72, 0.82)
        end
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

    block.families = {}
    for _, family in ipairs(PICKER_FAMILIES) do
        local label = NewEmptyStateLine(block, EMPTY_STATE_BODY_SIZE)
        label:SetText(family.label)
        label:SetJustifyH("LEFT")
        local description = NewEmptyStateLine(block, EMPTY_STATE_BODY_SIZE,
            EMPTY_STATE_SUBLINE_COLOR)
        description:SetText(family.description)
        description:SetJustifyH("LEFT")
        block.families[family.key] = { label = label, description = description }
    end
    block.familyNote = NewEmptyStateLine(block, EMPTY_STATE_BODY_SIZE,
        EMPTY_STATE_SUBLINE_COLOR)
    block.familyNote:SetText(FAMILY_COLLAPSE_NOTE)

    return block
end

------------------------------------------------------------------------
-- Panel-type picker cards
------------------------------------------------------------------------

local function ApplyCardFill(card, color)
    if not color then return end
    card:SetBackdropColor(color[1], color[2], color[3], color[4] or 1)
end

-- Navigation belongs to the header, outside the create cards. The library's
-- header lives above the scroll viewport so Back stays reachable in long grids.
local function CreateLibraryNavigation(overview, parent, opensLibrary)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    button.borderTextures = ST.CreateBorderTextureSet(button, "OVERLAY", 7)
    button:RegisterForClicks("LeftButtonUp")
    button.label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.label:SetPoint("CENTER", button, "CENTER", opensLibrary and 10 or 0, 0)
    if opensLibrary then
        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetAtlas(LIBRARY_ICON_ATLAS)
        button.icon:SetSize(18, 18)
        button.icon:SetPoint("LEFT", button, "LEFT", 6, 0)
    else
        button.label:SetText("Back")
    end
    local function Restore(self)
        ApplyTileBorder(self, CREATE_ACCENT.idleBorder)
        ApplyCardFill(self, CREATE_ACCENT.idleFill)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
    end
    button:SetScript("OnEnter", function(self)
        ApplyTileBorder(self, CREATE_ACCENT.hoverBorder)
        ApplyCardFill(self, CREATE_ACCENT.hoverFill)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(opensLibrary and "Templates" or "Choose a panel type", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", Restore)
    button:SetScript("OnHide", Restore)
    button:SetScript("OnClick", function(self)
        if not self:IsVisible() or not (overview.containerId
            and ST._IsCreateTargetContainer(overview.containerId)) then return end
        if opensLibrary then
            overview.pickerScrollOffset = overview.scrollOffset
            overview.scrollOffset = 0
        else
            overview.scrollOffset = overview.pickerScrollOffset or 0
            overview.pickerScrollOffset = nil
        end
        overview.showTemplates = opensLibrary
        Restore(self)
        ST._ReflowGroupPanelOverview(overview.host)
        -- Reflow can reuse the highlighted Panel frame for a template card.
        -- Resolve tutorial targets again before positioning its guide/glow.
        if CS.tutorialRuntime and CS.tutorialRuntime.active then
            if ST._RebuildTutorialAnchors then ST._RebuildTutorialAnchors() end
            if ST._RefreshTutorialPlacement then ST._RefreshTutorialPlacement() end
        end
    end)
    Restore(button)
    return button
end

local function EnsureLibraryHeader(overview)
    if overview.libraryHeader then return overview.libraryHeader end
    local header = CreateFrame("Frame", nil, overview.root)
    header:EnableMouse(false)
    header:SetPoint("TOPLEFT", overview.root, "TOPLEFT", OUTER_PADDING, -OUTER_PADDING)
    header.heading = NewEmptyStateLine(header, EMPTY_STATE_HEADING_SIZE)
    header.heading:SetText("Templates")
    header.subline = NewEmptyStateLine(header, EMPTY_STATE_BODY_SIZE, EMPTY_STATE_SUBLINE_COLOR)
    header.subline:SetText("Choose a template.")
    header.divider = header:CreateTexture(nil, "ARTWORK")
    header.back = CreateLibraryNavigation(overview, header, false)
    overview.libraryHeader = header
    return header
end

local function SetOverviewHeaderHeight(overview, height)
    overview.scroll:SetPoint("TOPLEFT", overview.root, "TOPLEFT",
        OUTER_PADDING, -(OUTER_PADDING + height))
    overview.scrollTrack:SetPoint("TOPRIGHT", overview.root, "TOPRIGHT",
        -2, -(OUTER_PADDING + height))
end

-- Reserve equal space on both sides of centered copy. At very narrow widths
-- navigation gets its own row instead of colliding with the heading.
local function LayoutPickerHeader(header, width, button, isBack)
    local bandWidth = math_min(width, EMPTY_STATE_MAX_CARD_WIDTH)
    local textWidth = math_min(width, EMPTY_STATE_MAX_TEXT_WIDTH)
    local y = EMPTY_STATE_TOP_PADDING
    if button and button:IsShown() then
        local buttonWidth = button.label:GetStringWidth() + (isBack and 20 or 38)
        button:SetSize(buttonWidth, LIBRARY_BUTTON_HEIGHT)
        button:ClearAllPoints()
        button:SetPoint(isBack and "TOPLEFT" or "TOPRIGHT", header, "TOP",
            (isBack and -1 or 1) * bandWidth / 2, -y)
        local available = bandWidth - 2 * (buttonWidth + CARD_GAP)
        if available < 140 then
            y = y + LIBRARY_BUTTON_HEIGHT + CARD_GAP
        else
            textWidth = math_min(textWidth, available)
        end
    end
    local copyTop = y
    for index, line in ipairs({ header.heading, header.subline }) do
        if index == 2 then y = y + EMPTY_STATE_SUBLINE_GAP end
        line:SetWidth(math_max(1, textWidth))
        line:SetWordWrap(true)
        line:ClearAllPoints()
        line:SetPoint("TOP", header, "TOP", 0, -y)
        line:Show()
        y = y + math_max(1, line:GetStringHeight() or 0)
    end
    y = math_max(y, copyTop + LIBRARY_BUTTON_HEIGHT) + EMPTY_STATE_DIVIDER_GAP
    -- GetClassColor may return nothing; keep the established blue fallback.
    local color = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    header.divider:ClearAllPoints()
    header.divider:SetPoint("TOP", header, "TOP", 0, -y)
    header.divider:SetSize(math_min(width, EMPTY_STATE_MAX_TEXT_WIDTH), EMPTY_STATE_DIVIDER_HEIGHT)
    header.divider:SetColorTexture(color and color.r or TILE_BORDER_COLOR[1],
        color and color.g or TILE_BORDER_COLOR[2], color and color.b or TILE_BORDER_COLOR[3],
        EMPTY_STATE_DIVIDER_ALPHA)
    header.divider:Show()
    return y + EMPTY_STATE_DIVIDER_HEIGHT + EMPTY_STATE_DIVIDER_GAP
end

-- One pooled card family serves both tiers and the starter, so every card must
-- be told its whole appearance on every configure. Idle and hover live on the
-- card itself because the scripts are installed once and the look changes per
-- build. A nil hover fill means "keep the idle fill", which is how the starter
-- answers the cursor with its border alone.
-- While the first-run tutorial waits for the player to create an Icon Panel,
-- every other create card stands down so the guided path cannot dead-end.
-- Checked live in the handlers (the tutorial can end without a rebuild); the
-- build pass reads it once for the dimmed look. Templates use their exact
-- creation mode, including ordinary legacy Bar templates under Panel.
local function IsCardTutorialLocked(create)
    if not create or create.mode == "icons" then
        return false
    end
    return (ST._IsTutorialAwaitingIconPanel and ST._IsTutorialAwaitingIconPanel()) == true
end

local function GetPickerTemplatesByMode()
    local byMode, count = {}, 0
    for _, mode in ipairs(LIBRARY_MODES) do byMode[mode] = {} end
    for _, entry in ipairs(CooldownCompanion:GetPanelTemplates(nil)) do
        local mode = CooldownCompanion:GetPanelTemplateCreationMode(entry.template)
        if byMode[mode] then
            local entries = byMode[mode]
            entries[#entries + 1] = entry
            count = count + 1
        end
    end
    return byMode, count
end

local function EnsurePickerCard(overview, block, index)
    local card = overview.cards[index]
    if card then return card end

    card = CreateFrame("Button", nil, block, "BackdropTemplate")
    card:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    card:SetBackdropColor(0, 0, 0, 0)
    card.borderTextures = ST.CreateBorderTextureSet(card, "OVERLAY", 7)
    card:RegisterForClicks("LeftButtonUp")
    card:EnableMouseWheel(true)
    -- Layout shows it; until then it must not float over the surface.
    card:Hide()

    card.title = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    card.body = card:CreateFontString(nil, "OVERLAY", CARD_BODY_FONT)
    card.format = NewEmptyStateLine(card, EMPTY_STATE_BODY_SIZE,
        EMPTY_STATE_SUBLINE_COLOR)

    card:SetScript("OnClick", function(self)
        local create = self._cdcOverviewCreate
        if not create or create.disabled or not self:IsVisible() or IsCardTutorialLocked(create) then return end
        local containerId = create.containerId
        -- The click lands after the build pass, so the Group may already be
        -- gone or out of scope. Re-answer the create gate before acting.
        if not (containerId and ST._IsCreateTargetContainer
            and ST._IsCreateTargetContainer(containerId)) then
            return
        end
        if create.templateId then
            local template = CooldownCompanion:GetPanelTemplate(create.templateId)
            if not template or CooldownCompanion:GetPanelTemplateCreationMode(template) ~= create.mode then return end
            ST._CreatePanelFromTemplateInContainer(containerId, create.templateId)
        elseif create.cdmStarter then
            if ST._CreateMissingCDMPanelsInSelectedContainer then
                ST._CreateMissingCDMPanelsInSelectedContainer(containerId)
            end
        elseif create.mode and ST._CreatePanelInContainer then
            ST._CreatePanelInContainer(containerId, create.mode)
        end
    end)
    card:SetScript("OnEnter", function(self)
        local create = self._cdcOverviewCreate
        if not create or IsCardTutorialLocked(create) then return end
        if not create.disabled then
            ApplyTileBorder(self, self._cdcHoverBorder or self._cdcIdleBorder)
            ApplyCardFill(self, self._cdcHoverFill or self._cdcIdleFill)
        end
        if create.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(create.tooltipTitle or "Panel", 1, 1, 1)
            GameTooltip:AddLine(create.tooltipText,
                CARD_BODY_COLOR[1], CARD_BODY_COLOR[2],
                CARD_BODY_COLOR[3], true)
            GameTooltip:Show()
        end
    end)
    card:SetScript("OnLeave", function(self)
        ApplyTileBorder(self, self._cdcIdleBorder)
        ApplyCardFill(self, self._cdcIdleFill)
        if GameTooltip:GetOwner() == self then
            GameTooltip:Hide()
        end
    end)
    card:SetScript("OnMouseWheel", function(_, delta)
        SetScrollOffset(overview, (overview.scrollOffset or 0) - (delta * SCROLL_STEP))
    end)
    card:SetScript("OnHide", function(self)
        if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
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
    card.format:ClearAllPoints()
    card.format:SetPoint("TOP", card, "TOP", 0,
        -(topOffset + style.titleHeight + CARD_TITLE_BODY_GAP
            + (card.body:GetStringHeight() or 0) + CARD_TITLE_BODY_GAP))
end

-- Re-asserted on every configure, because pooled cards can move between the
-- create choices and wrapped template names. The padding anchors
-- are the measurement position; placement centers the measured block later.
local function ApplyPickerCardStyle(card, style, textWidth)
    card.title:SetFontObject(_G[style.titleFont])
    local titleColor = style.titleColor or CARD_TITLE_COLOR
    card.title:SetTextColor(titleColor[1], titleColor[2], titleColor[3])
    card.title:SetWidth(textWidth)
    card.title:SetHeight(style.wrapTitle and 0 or style.titleHeight)
    card.title:SetJustifyH("CENTER")
    card.title:SetJustifyV("MIDDLE")
    card.title:SetWordWrap(style.wrapTitle == true)

    card.body:SetFontObject(_G[style.bodyFont])
    card.body:SetWidth(textWidth)
    card.body:SetJustifyH("CENTER")
    card.body:SetJustifyV("TOP")
    card.body:SetTextColor(CARD_BODY_COLOR[1], CARD_BODY_COLOR[2],
        CARD_BODY_COLOR[3])
    if ST._ConfigureWrappedHelperLabel then
        ST._ConfigureWrappedHelperLabel(card.body)
    end
    card.body:SetShown(style.titleOnly ~= true)
    card.format:SetWidth(textWidth)
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
    idleBorder = { 0, 0, 0, 0 },
    hoverBorder = CREATE_ACCENT.hoverBorder,
    idleFill = { 0, 0, 0, 0 },
    hoverFill = nil,
}

-- Positions and finishes one already-measured card. Width and height are passed
-- in rather than read off a tier, because families have their own column
-- widths. The text offset is recomputed here, once the card's
-- final height is known, so a pooled card cannot retain another tier's offset.
local function PlacePickerCard(block, card, entry, style, containerId, accent,
    x, y, width, height)
    card._cdcOverviewCreate = {
        containerId = containerId,
        mode = entry.mode,
        cdmStarter = entry.cdmStarter,
        templateId = entry.templateId,
        disabled = entry.disabled,
        tooltipTitle = entry.tooltipTitle,
        tooltipText = entry.tooltipText,
    }
    card:SetAlpha((entry.disabled or IsCardTutorialLocked(card._cdcOverviewCreate)) and 0.35 or 1)
    ApplyPickerCardAccent(card, accent)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", block, "TOP", x, -y)
    card:SetSize(math_max(1, width), math_max(1, height))
    local bodyHeight = style.titleOnly and 0
        or (card.body:GetStringHeight() or 0)
    local formatHeight = entry.format and (card.format:GetStringHeight() or 0) or 0
    local titleHeight = style.wrapTitle and card.title:GetStringHeight() or style.titleHeight
    local contentHeight = titleHeight
        + (bodyHeight > 0 and (CARD_TITLE_BODY_GAP + bodyHeight) or 0)
        + (formatHeight > 0 and (CARD_TITLE_BODY_GAP + formatHeight) or 0)
    AnchorPickerCardText(card, style,
        math_max(style.padding, (height - contentHeight) / 2))
    card:Show()
end

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

-- Styles and fills one tier's cards and reports the geometry the block needs
-- without placing anything. `forceColumns` is for the starter, which is one
-- full-width offer rather than a tier that packs.
local function MeasurePickerTier(overview, block, firstIndex, entries, style,
    bandWidth, forceColumns)
    local columns = forceColumns or ResolveTierColumns(style, bandWidth)
    local cardWidth = (bandWidth - ((columns - 1) * CARD_GAP)) / columns
    local textWidth = math_max(1, cardWidth - (style.padding * 2))
    local bodyHeight = 0
    local titleHeight = style.titleHeight

    for offset, entry in ipairs(entries) do
        local card = EnsurePickerCard(overview, block, firstIndex + offset - 1)
        ApplyPickerCardStyle(card, style, textWidth)
        card.title:SetText(entry.title)
        card.body:SetText(entry.body)
        card.format:SetText(entry.format)
        card.format:SetShown(entry.format ~= nil and not style.titleOnly)
        -- Shown before the wrapped height is read, for the same reason the
        -- block is: the measurement should come from a live region. Placement
        -- follows in this same pass, so nothing is left floating.
        card:Show()
        if style.wrapTitle then
            titleHeight = math_max(titleHeight, card.title:GetStringHeight() or 0)
        end
        if not style.titleOnly then
            bodyHeight = math_max(bodyHeight,
                (card.body:GetStringHeight() or 0)
                    + (entry.format and (CARD_TITLE_BODY_GAP
                        + (card.format:GetStringHeight() or 0)) or 0))
        end
    end

    -- One height for the whole tier, taken from its tallest wrapped
    -- title or description, so the cards stay aligned.
    local height = math_max(style.minHeight or 0,
        (style.padding * 2) + titleHeight
            + (bodyHeight > 0 and (CARD_TITLE_BODY_GAP + bodyHeight) or 0))

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
    style, containerId, accent, top, centerX)
    if metrics.count == 0 then
        return 0
    end

    local placed = 0
    local y = top
    while placed < metrics.count do
        local rowCount = math_min(metrics.columns, metrics.count - placed)
        local rowSpan = (rowCount * metrics.cardWidth)
            + ((rowCount - 1) * CARD_GAP)
        local x = (centerX or 0) - (rowSpan / 2)
        for offset = 1, rowCount do
            local entry = entries[placed + offset]
            local card = overview.cards[firstIndex + placed + offset - 1]
            card:SetFrameLevel(block:GetFrameLevel() + 1)
            PlacePickerCard(block, card, entry, style, containerId, accent,
                x, y, metrics.cardWidth, metrics.height)
            x = x + metrics.cardWidth + CARD_GAP
        end
        placed = placed + rowCount
        y = y + metrics.height + CARD_GAP
    end

    return (y - top) - CARD_GAP
end

-- Families align with the primary columns. Wrapped descriptions share a
-- measured height within each row, keeping the Icons / Bars buttons aligned.
local function LayoutPickerFamilies(overview, block, families,
    bandWidth, columns, containerId, top)
    local width = (bandWidth - ((columns - 1) * CARD_GAP)) / columns
    local y = top
    for first = 1, #families, columns do
        local last = math_min(first + columns - 1, #families)
        local labelHeight, descriptionHeight = 0, 0
        for index = first, last do
            local family = families[index]
            local widgets = block.families[family.key]
            widgets.label:SetWidth(width)
            widgets.description:SetWidth(width)
            widgets.label:Show()
            widgets.description:Show()
            labelHeight = math_max(labelHeight, widgets.label:GetStringHeight() or 0)
            descriptionHeight = math_max(descriptionHeight,
                widgets.description:GetStringHeight() or 0)
            family.metrics = MeasurePickerTier(overview, block, family.firstIndex,
                family.entries, FAMILY_CARD_STYLE, width)
        end
        local buttonsTop = y + labelHeight + CARD_TITLE_BODY_GAP
            + descriptionHeight + CARD_GAP
        local rowHeight = 0
        for index = first, last do
            local family = families[index]
            local widgets = block.families[family.key]
            local x = -(bandWidth / 2) + ((index - first) * (width + CARD_GAP))
            widgets.label:ClearAllPoints()
            widgets.label:SetPoint("TOPLEFT", block, "TOP", x, -y)
            widgets.description:ClearAllPoints()
            widgets.description:SetPoint("TOPLEFT", block, "TOP", x,
                -(y + labelHeight + CARD_TITLE_BODY_GAP))
            rowHeight = math_max(rowHeight, PlacePickerTier(overview, block,
                family.firstIndex, family.entries, family.metrics, FAMILY_CARD_STYLE,
                containerId, FAMILY_CARD_ACCENT, buttonsTop, x + width / 2))
        end
        y = buttonsTop + rowHeight
        if last < #families then y = y + CARD_TIER_GAP end
    end
    return y - top
end

-- A picker card going down takes its create action with it, so a click that
-- lands mid-refresh finds nothing to act on, and takes its tooltip too when
-- the cursor was resting on it.
local function ReleasePickerCard(card)
    if GameTooltip:GetOwner() == card then
        GameTooltip:Hide()
    end
    card._cdcOverviewCreate = nil
    card:Hide()
end

-- Lays the whole block out top-down in block coordinates and returns its
-- height, which is what tells the caller whether the surface needs to scroll.
local function LayoutEmptyStateBlock(overview, containerId, visibleWidth, templateCount)
    local block = EnsureEmptyStateBlock(overview)
    block:SetWidth(visibleWidth)
    -- Shown before measuring: the caller only positions it afterwards, and the
    -- string heights this pass reads should come from a live region.
    block:Show()

    local textWidth = math_max(1,
        math_min(visibleWidth, EMPTY_STATE_MAX_TEXT_WIDTH))
    for _, label in pairs(block.libraryLabels or {}) do label:Hide() end
    if not block.libraryButton then
        block.libraryButton = CreateLibraryNavigation(overview, block, true)
    end
    block.libraryButton.label:SetText(tostring(templateCount))
    block.libraryButton:SetShown(templateCount > 0)
    local y = LayoutPickerHeader(block, visibleWidth, block.libraryButton)

    local function PlaceLine(line, gapBefore)
        y = y + (gapBefore or 0)
        line:SetWidth(textWidth)
        line:ClearAllPoints()
        line:SetPoint("TOP", block, "TOP", 0, -y)
        line:Show()
        y = y + math_max(1, line:GetStringHeight() or 0)
    end

    -- Menu order stays independent of the picker's visual families.
    local familyByKey = {}
    for _, family in ipairs(PICKER_FAMILIES) do
        familyByKey[family.key] = { key = family.key, entries = {} }
    end
    local primaryEntries, secondaryEntries = {}, {}
    for _, panelType in ipairs(ST._PANEL_TYPES or {}) do
        local entry = {
            title = panelType.pickerLabel or panelType.label,
            body = panelType.pickerDescription or panelType.description,
            format = panelType.pickerFormat,
            mode = panelType.mode,
            tooltipTitle = panelType.label,
            tooltipText = panelType.description,
        }
        local family = familyByKey[panelType.pickerFamily]
        if panelType.primary then
            primaryEntries[#primaryEntries + 1] = entry
        elseif family then
            family.entries[#family.entries + 1] = entry
        else
            secondaryEntries[#secondaryEntries + 1] = entry
        end
    end
    local starterEntries = {
        {
            title = STARTER_CARD_TITLE,
            tooltipTitle = STARTER_CARD_TITLE,
            tooltipText = STARTER_CARD_BODY,
            cdmStarter = true,
        },
    }

    local cardBandWidth = math_max(1,
        math_min(visibleWidth, EMPTY_STATE_MAX_CARD_WIDTH))
    local primaryFirst = 1
    local families = {}
    local secondaryFirst = primaryFirst + #primaryEntries
    for _, definition in ipairs(PICKER_FAMILIES) do
        local family = familyByKey[definition.key]
        local hasEntries = #family.entries > 0
        block.families[family.key].label:SetShown(hasEntries)
        block.families[family.key].description:SetShown(hasEntries)
        if hasEntries then
            family.firstIndex = secondaryFirst
            secondaryFirst = secondaryFirst + #family.entries
            families[#families + 1] = family
        end
    end
    local starterFirst = secondaryFirst + #secondaryEntries

    local primaryMetrics = MeasurePickerTier(overview, block, primaryFirst,
        primaryEntries, PRIMARY_CARD_STYLE, cardBandWidth)
    local secondaryMetrics = MeasurePickerTier(overview, block, secondaryFirst,
        secondaryEntries, SECONDARY_CARD_STYLE, cardBandWidth)
    -- The starter is one full-width offer, so it never shares a row.
    local starterMetrics = MeasurePickerTier(overview, block, starterFirst,
        starterEntries, STARTER_CARD_STYLE, cardBandWidth, 1)

    y = y + PlacePickerTier(overview, block, primaryFirst, primaryEntries,
        primaryMetrics, PRIMARY_CARD_STYLE, containerId, CREATE_ACCENT, y)
    if #families > 0 then
        y = y + EMPTY_STATE_SECTION_GAP
        y = y + LayoutPickerFamilies(overview, block, families,
            cardBandWidth, primaryMetrics.columns, containerId, y)
        PlaceLine(block.familyNote, CARD_TIER_GAP)
    else
        block.familyNote:Hide()
    end
    if #secondaryEntries > 0 then
        y = y + CARD_TIER_GAP
    end
    y = y + PlacePickerTier(overview, block, secondaryFirst, secondaryEntries,
        secondaryMetrics, SECONDARY_CARD_STYLE, containerId, CREATE_ACCENT, y)
    y = y + EMPTY_STATE_SECTION_GAP
    y = y + PlacePickerTier(overview, block, starterFirst, starterEntries,
        starterMetrics, STARTER_CARD_STYLE, containerId,
        CARD_STARTER_ACCENT, y)

    -- The reflow path re-runs this pass without a reset, so a card the last
    -- layout used and this one does not must
    -- not linger on screen holding a stale create action.
    local usedCards = starterFirst + #starterEntries - 1
    for index = usedCards + 1, overview.usedCards or 0 do
        local card = overview.cards[index]
        if card then
            ReleasePickerCard(card)
        end
    end
    overview.usedCards = usedCards

    return y + EMPTY_STATE_BOTTOM_PADDING
end

local function LayoutTemplateLibrary(overview, containerId, width, templatesByMode)
    local block = EnsureEmptyStateBlock(overview)
    block:SetWidth(width)
    block:Show()
    block.heading:Hide()
    block.subline:Hide()
    block.divider:Hide()
    block.familyNote:Hide()
    if block.libraryButton then block.libraryButton:Hide() end
    for _, family in pairs(block.families) do
        family.label:Hide()
        family.description:Hide()
    end
    block.libraryLabels = block.libraryLabels or {}
    for _, label in pairs(block.libraryLabels) do label:Hide() end
    local bandWidth = math_min(width, EMPTY_STATE_MAX_CARD_WIDTH)
    local y, usedCards = 0, 0
    for _, mode in ipairs(LIBRARY_MODES) do
        local entries = templatesByMode[mode]
        if #entries > 0 then
            if usedCards > 0 then y = y + EMPTY_STATE_SECTION_GAP end
            local label = block.libraryLabels[mode]
            if not label then
                label = NewEmptyStateLine(block, EMPTY_STATE_BODY_SIZE)
                block.libraryLabels[mode] = label
            end
            label:SetText(ST._GetPanelModeLabel(mode) .. " (" .. #entries .. ")")
            label:SetWidth(bandWidth)
            label:ClearAllPoints()
            label:SetPoint("TOP", block, "TOP", 0, -y)
            label:Show()
            y = y + label:GetStringHeight() + CARD_GAP
            local templateEntries = {}
            for _, saved in ipairs(entries) do
                local entry = { title = saved.template.name, mode = mode, templateId = saved.id }
                ST._AddPanelTemplateMenuTooltip(entry, saved.template)
                templateEntries[#templateEntries + 1] = entry
            end
            local firstIndex = usedCards + 1
            local metrics = MeasurePickerTier(overview, block, firstIndex,
                templateEntries, TEMPLATE_CARD_STYLE, bandWidth)
            y = y + PlacePickerTier(overview, block, firstIndex, templateEntries,
                metrics, TEMPLATE_CARD_STYLE, containerId, CREATE_ACCENT, y)
            usedCards = usedCards + #templateEntries
        end
    end
    for index = usedCards + 1, overview.usedCards or 0 do
        ReleasePickerCard(overview.cards[index])
    end
    overview.usedCards = usedCards
    return y + EMPTY_STATE_BOTTOM_PADDING
end

local function HideEmptyPicker(overview)
    for index = 1, overview.usedCards do ReleasePickerCard(overview.cards[index]) end
    overview.usedCards = 0
    if overview.emptyBlock then overview.emptyBlock:Hide() end
    if overview.libraryHeader then overview.libraryHeader:Hide() end
    SetOverviewHeaderHeight(overview, 0)
end

-- An editable Group with no Panels gets the create surface itself instead of a
-- bare label and glyph. The block rides in the scroll child, so a short host
-- scrolls it rather than clipping the lowest cards out of reach; when it fits,
-- it centers on the full empty workspace.
local function BuildEmptyGroupState(overview, host, containerId, sameContainer)
    if not sameContainer then
        overview.showTemplates = nil
        overview.pickerScrollOffset = nil
        overview.scrollOffset = 0
    end
    if not (ST._IsCreateTargetContainer
        and ST._IsCreateTargetContainer(containerId)) then
        HideEmptyPicker(overview)
        overview.showTemplates = nil
        overview.pickerScrollOffset = nil
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
    overview.scroll:Show()
    local templatesByMode, templateCount = GetPickerTemplatesByMode()
    if overview.showTemplates and templateCount == 0 then
        overview.showTemplates = nil
        overview.scrollOffset = overview.pickerScrollOffset or 0
        overview.pickerScrollOffset = nil
    end
    if overview.showTemplates then
        local header = EnsureLibraryHeader(overview)
        header:SetWidth(visibleWidth)
        header:Show()
        local headerHeight = LayoutPickerHeader(header, visibleWidth, header.back, true)
        -- A short preview still needs a usable grid viewport. Collapse the
        -- explanatory copy to one navigation row instead of inverting anchors.
        if headerHeight + TEMPLATE_CARD_STYLE.minHeight > visibleHeight then
            header.back:ClearAllPoints()
            header.back:SetPoint("TOPLEFT", header, "TOPLEFT", 0, -4)
            header.heading:ClearAllPoints()
            header.heading:SetPoint("LEFT", header.back, "RIGHT", CARD_GAP, 0)
            header.heading:SetWidth(math_max(1, visibleWidth - header.back:GetWidth() - CARD_GAP))
            header.heading:SetWordWrap(false)
            header.subline:Hide()
            header.divider:Hide()
            headerHeight = LIBRARY_BUTTON_HEIGHT + 8
        end
        header:SetHeight(headerHeight)
        SetOverviewHeaderHeight(overview, headerHeight)
        visibleHeight = math_max(1, visibleHeight - headerHeight)
    else
        if overview.libraryHeader then overview.libraryHeader:Hide() end
        SetOverviewHeaderHeight(overview, 0)
    end

    -- Laid out at the full band first. If that overflows, the scroll track is
    -- about to appear, so one re-measure at the narrower band lets the cards
    -- keep clear of it. Exactly one retry: the second pass is never wider than
    -- the first, so it cannot re-open the question it just answered.
    local layoutWidth = visibleWidth
    local function LayoutBlock(width)
        if overview.showTemplates then
            return LayoutTemplateLibrary(overview, containerId, width, templatesByMode)
        end
        return LayoutEmptyStateBlock(overview, containerId, width, templateCount)
    end
    local blockHeight = LayoutBlock(layoutWidth)
    if blockHeight > visibleHeight and visibleWidth > SCROLL_RESERVE then
        layoutWidth = math_max(1, visibleWidth - SCROLL_RESERVE)
        blockHeight = LayoutBlock(layoutWidth)
    end
    local block = overview.emptyBlock
    local blockTop = blockHeight < visibleHeight
        and ((visibleHeight - blockHeight) / 2) or 0
    if overview.showTemplates then
        -- Center the header and grid as one surface, just like the new-group
        -- picker. On overflow they start at the top and only the cards scroll.
        local header = overview.libraryHeader
        header:SetPoint("TOPLEFT", overview.root, "TOPLEFT", OUTER_PADDING,
            -(OUTER_PADDING + blockTop))
        SetOverviewHeaderHeight(overview, header:GetHeight() + blockTop)
        visibleHeight = visibleHeight - blockTop
        blockTop = 0
    end
    block:SetHeight(math_max(1, blockHeight))
    block:ClearAllPoints()
    block:SetPoint("TOPLEFT", overview.content, "TOPLEFT", 0, -blockTop)
    block:Show()

    local contentHeight = math_max(visibleHeight, blockTop + blockHeight)
    overview.visibleHeight = visibleHeight
    overview.contentHeight = contentHeight
    overview.maxScroll = math_max(0, contentHeight - visibleHeight)
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
    HideEmptyPicker(overview)
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
        RestoreOverviewColors(tile)
        if ST._ReleaseReadOnlyPanelPreview then
            ST._ReleaseReadOnlyPanelPreview(tile.visualHost)
        end
        tile._cdcOverviewRecord = nil
        tile.visualHost:SetAlpha(1)
        tile.statusBadge:Hide()
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

-- The tile grid's whole geometry pass: row layout, tile placement, labels,
-- scroll bookkeeping, and the add tile's lane. Shared between the full build
-- and the divider-drag reflow so the two can never disagree about where a
-- tile lands. `full` additionally re-renders each tile's read-only panel
-- preview — the expensive half a per-frame caller must skip.
local function LayoutPanelTileGrid(overview, host, records, full)
    local hostWidth = host:GetWidth() or 0
    local hostHeight = host:GetHeight() or 0
    if hostWidth < 100 then hostWidth = 700 end
    if hostHeight < 80 then hostHeight = 240 end
    local visibleWidth = math_max(1, hostWidth - (OUTER_PADDING * 2))
    local visibleHeight = math_max(1, hostHeight - (OUTER_PADDING * 2))
    local stacked = ST._IsThreeColumnConfigLayout
        and ST._IsThreeColumnConfigLayout()
    local showAddTile = ST._IsCreateTargetContainer
        and ST._IsCreateTargetContainer(overview.containerId)
    local rows, rowHeight, contentHeight, layoutWidth, overflow
    if stacked then
        layoutWidth = visibleWidth
        rows, contentHeight = BuildStackedRowLayouts(records,
            layoutWidth, visibleHeight, showAddTile)
        if contentHeight > visibleHeight + 0.5 then
            layoutWidth = math_max(1, visibleWidth - SCROLL_RESERVE)
            rows, contentHeight = BuildStackedRowLayouts(records,
                layoutWidth, visibleHeight, showAddTile)
        end
        overflow = contentHeight > visibleHeight + 0.5
    else
        local columns = GetColumnCount(#records)
        local rowCount = math_ceil(#records / columns)
        local idealRowHeight = (visibleHeight - ((rowCount - 1) * TILE_GAP))
            / rowCount
        rowHeight = math_max(MIN_ROW_HEIGHT, idealRowHeight)
        contentHeight = (rowCount * rowHeight)
            + ((rowCount - 1) * TILE_GAP)
        overflow = contentHeight > visibleHeight + 0.5
        layoutWidth = math_max(1, visibleWidth - (overflow and SCROLL_RESERVE or 0))

        -- The grid's add tile claims a lane in the final row only. Hide it
        -- when giving up that lane would leave the Panels too narrow to read.
        local gridWidth = layoutWidth - ADD_TILE_WIDTH - TILE_GAP
        showAddTile = showAddTile and gridWidth >= ADD_TILE_MIN_GRID_WIDTH
        rows = BuildRowLayouts(records, columns, layoutWidth,
            showAddTile and gridWidth or nil)
    end

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
        local tileHeight = row.height or rowHeight
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
                tileTop + tileHeight, tileScale)
            local onePixel = PixelUtil.GetNearestPixelSize(0, tileScale, 1)
            local snappedTileWidth = math_max(onePixel, snappedRight - snappedX)
            local snappedTileHeight = math_max(onePixel,
                snappedBottom - snappedTop)
            local labelHeight = LayoutTileHeader(record, stacked or #records > 1)
            local visualWidth = math_max(1,
                snappedTileWidth - (TILE_INSET * 2))
            local visualHeight = math_max(1,
                snappedTileHeight - labelHeight - (TILE_INSET * 2))

            tile:ClearAllPoints()
            PixelUtil.SetPoint(tile, "TOPLEFT", overview.content, "TOPLEFT",
                snappedX, -snappedTop)
            PixelUtil.SetSize(tile, snappedTileWidth, snappedTileHeight, 1, 1)

            tile.resourceBadge:SetShown(record.hasAttachedResources)
            tile.visualHost:SetAlpha(1)
            tile.visualHost:ClearAllPoints()
            tile.visualHost:SetPoint("CENTER", tile, "CENTER", 0, -(labelHeight / 2))
            tile.visualHost:SetSize(visualWidth, visualHeight)
            tile:Show()
            if full then
                RestoreOverviewColors(tile)
                ST._BuildReadOnlyPanelPreview(tile.visualHost, record.panelId, record.previewOptions)
                if record.disabledReason then GrayOverviewContents(tile) end
            end
        end
        -- Overwritten each pass, so after the loop these describe the last
        -- row: the lane BuildRowLayouts just reserved sits right of its last
        -- tile, at its top.
        local lastItem = row.items[#row.items]
        if lastItem then
            addTileX = lastItem.x + lastItem.width + TILE_GAP
            addTileTop = tileTop
        end
        tileTop = tileTop + tileHeight + TILE_GAP
    end

    if stacked then
        addTileX, addTileTop = 0, tileTop
    end
    if showAddTile and addTileX then
        local addTile = EnsureAddTile(overview)
        addTile._cdcAddContainerId = overview.containerId
        PlaceAddTile(overview, addTile, addTileX, addTileTop,
            stacked and layoutWidth or ADD_TILE_WIDTH,
            stacked and ADD_ROW_HEIGHT or rowHeight)
    elseif overview.addTile then
        -- A reflow can flip the lane ineligible (the scroll reserve narrowing
        -- the grid) with no reset having hidden the tile first.
        overview.addTile._cdcAddContainerId = nil
        overview.addTile:Hide()
    end
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
    overview.showTemplates = nil
    overview.pickerScrollOffset = nil

    local records = {}
    local includeSections = true
    local browsingOtherClasses = ST._configState
        and ST._configState.otherClassLibraryActive == true
    for index, panelInfo in ipairs(panels) do
        local tile = EnsureTile(overview, index)
        local modules = ST._GetPanelAttachmentPreviewModules(panelInfo.groupId, { groupOverview = true })
        local naturalWidth, naturalHeight =
            ST._GetReadOnlyPanelPreviewNaturalSize(panelInfo.groupId, includeSections, modules)
        local record = {
            tile = tile,
            containerId = containerId,
            panelId = panelInfo.groupId,
            typeLabel = ST._GetPanelTypeLabel(panelInfo.group),
            name = panelInfo.group.name or ("Panel " .. tostring(panelInfo.groupId)),
            naturalWidth = math_max(1, tonumber(naturalWidth) or 220),
            naturalHeight = math_max(1, tonumber(naturalHeight) or 90),
            hasAttachedResources = #modules > 0,
            previewOptions = { groupOverview = true, includeSections = includeSections, previewModules = modules },
            canToggleAnchorLock = not browsingOtherClasses,
        }
        local panelDisabled = panelInfo.group.enabled == false
        local groupDisabled = container.enabled == false
        if panelDisabled and groupDisabled then
            record.disabledReason = "Panel and Group disabled"
        elseif groupDisabled then
            record.disabledReason = "Group disabled"
        elseif panelDisabled then
            record.disabledReason = "Disabled"
        end
        tile.label.text:SetText(record.name)
        -- Row height is intentionally standardized by the overview. Horizontal
        -- allocation should therefore follow the Panel's saved-design width,
        -- not its area (which over-rewards tall, narrow Panels).
        record.weight = record.naturalWidth
        records[index] = record
        tile._cdcOverviewRecord = record
        ApplyTileBorder(tile, TILE_BORDER_COLOR)
    end
    overview.usedTiles = #records

    LayoutPanelTileGrid(overview, host, records, true)

    if not sameContainer then
        overview.scrollOffset = 0
    end
    SetScrollOffset(overview, overview.scrollOffset or 0)
end

-- Per-frame geometry catch-up for live host resizes (the preview split
-- divider). Re-flows the tiles the last build produced against the host's
-- current size without touching the previews inside them, so the tile
-- borders track the divider at frame rate; the throttled full rebuild
-- re-scales the preview contents moments later. Same split the unlock
-- movers use: anchored chrome at frame rate, restyle on the throttle.
function ST._ReflowGroupPanelOverview(host)
    local overview = host and host._cdcGroupPanelOverview
    if not (overview and overview.containerId and overview.root:IsShown()) then
        return
    end

    if overview.usedTiles == 0 then
        -- The empty-Group create surface is pure layout (pooled cards, no
        -- panel previews), so its own build pass is cheap enough to re-run.
        if overview.emptyBlock and overview.emptyBlock:IsShown() then
            BuildEmptyGroupState(overview, host, overview.containerId, true)
        end
        return
    end

    local records = {}
    for index = 1, overview.usedTiles do
        local record = overview.tiles[index]
            and overview.tiles[index]._cdcOverviewRecord
        if not record then return end
        records[index] = record
    end

    LayoutPanelTileGrid(overview, host, records, false)
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
    overview.showTemplates = nil
    overview.pickerScrollOffset = nil
    overview.root:Hide()
end

-- Surface visibility is separate from tutorial anchor availability: both the
-- create choices and the template library can contain tutorial-dimmed cards.
function ST._IsEmptyGroupPickerVisible()
    local overview = activeOverview
    return (overview and overview.root:IsVisible()
        and overview.emptyBlock and overview.emptyBlock:IsShown()) or false
end

-- Read-only lookup of one panel-type card in the empty state's picker, used to
-- point at it without owning it. Templates are not tutorial create targets.
-- Returns nil whenever the picker is not the surface on
-- screen, so callers must tolerate a missing frame.
function ST._GetEmptyPickerCardFrame(mode)
    local overview = activeOverview
    if not (mode and overview and overview.root:IsShown()) then return nil end
    for index = 1, overview.usedCards or 0 do
        local card = overview.cards[index]
        local create = card and card._cdcOverviewCreate
        if create and not create.templateId and create.mode == mode and card:IsShown() then
            return card
        end
    end
    return nil
end
