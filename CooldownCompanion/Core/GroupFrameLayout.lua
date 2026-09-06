--[[
    CooldownCompanion - GroupFrameLayout
    Button population, panel sizing, compact layout, and style refresh.

    Part of the GroupFrame family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._GroupFrame.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local ipairs = ipairs
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local math_abs = math.abs
local table_insert = table.insert
local InCombatLockdown = InCombatLockdown
local issecretvalue = issecretvalue
local select = select
local wipe = wipe
local GetTextEntryMetrics = ST._GetTextEntryMetrics

local GF = ST._GroupFrame

-- GroupFrameShared.lua
local GetContainerPreviewSelectionState = GF.GetContainerPreviewSelectionState
local GetGroupButtonSizingOptions = GF.GetGroupButtonSizingOptions
local GetGrowthMultipliers = GF.GetGrowthMultipliers
local PropagateFrameStrata = GF.PropagateFrameStrata
local NormalizeCompactGrowthDirection = GF.NormalizeCompactGrowthDirection
local GetCompactAnchorFixedPoint = GF.GetCompactAnchorFixedPoint
local UpdateCoordLabel = GF.UpdateCoordLabel
local GetCompactSlotForIndex = GF.GetCompactSlotForIndex

-- GroupFrameButtonPool.lua
local IsRuntimeButtonUsable = GF.IsRuntimeButtonUsable
local ClearButtonCompactSlotCache = GF.ClearButtonCompactSlotCache
local GetRuntimeGroupButtonList = GF.GetRuntimeGroupButtonList
local GetButtonPoolKey = GF.GetButtonPoolKey
local GetExistingButtonPoolKey = GF.GetExistingButtonPoolKey
local ReleaseButtonToPool = GF.ReleaseButtonToPool
local AcquireButtonFromPool = GF.AcquireButtonFromPool
local PreparePooledButtonForUse = GF.PreparePooledButtonForUse
local ResetButtonGlowTransitionState = GF.ResetButtonGlowTransitionState

-- GroupFrameMovers.lua
local UpdateResizedPanelContainerWrapper = GF.UpdateResizedPanelContainerWrapper

-- Compute button width/height from group style (bar mode vs square vs non-square).
-- Returns width, height, isBarMode.
local function GetButtonDimensions(group, buttonUsabilityOptions, groupId)
    local style = group.style or {}
    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    local isTextureMode = CooldownCompanion:IsStandaloneTexturePanelGroup(group)
    local w, h
    if isTextureMode then
        w, h = 1, 1
    elseif isTextMode then
        if GetTextEntryMetrics then
            -- The grid pitch is the widest/tallest usable entry. Each entry
            -- frame keeps its own measured size (UpdateStyle -> ApplyTextLayout),
            -- so short entries stay short inside a wider pitch. The group-level
            -- format seeds a floor so an entry-less panel still has a size.
            w, h = GetTextEntryMetrics(style, nil, style.textFormat or "{name}  {status}")
            for _, buttonData in ipairs(group.buttons or {}) do
                if CooldownCompanion:IsButtonUsable(buttonData, group, buttonUsabilityOptions) then
                    local effectiveStyle = CooldownCompanion:GetEffectiveStyle(style, buttonData)
                    local fmt = buttonData.textFormat or effectiveStyle.textFormat or "{name}  {status}"
                    local buttonWidth, buttonHeight = GetTextEntryMetrics(effectiveStyle, buttonData, fmt)
                    w = math_max(w, buttonWidth)
                    h = math_max(h, buttonHeight)
                end
            end
        else
            w, h = 200, 20
        end
    elseif isBarMode then
        w, h = style.barLength or 180, style.barHeight or 20
        if style.barFillVertical then w, h = h, w end
    elseif style.maintainAspectRatio then
        local size = style.buttonSize or ST.BUTTON_SIZE
        w, h = size, size
    else
        w = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        h = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end
    return w, h, isBarMode
end

-- Zero-based row, col of a 1-based Aura Panel cell.
-- Bars stack in a single column: their entries render through the aura
-- container as a flowed bar list, so buttonsPerRow has no meaning there.
function CooldownCompanion:GetAuraPanelCellSlot(group, slotIndex)
    local style = group.style or {}
    if group.displayMode == "bars" then
        return slotIndex - 1, 0
    end
    local buttonsPerRow = math_max(1, style.buttonsPerRow or 12)
    if ST.GetPanelLayoutOrientation(group.displayMode, style) == "horizontal" then
        return math_floor((slotIndex - 1) / buttonsPerRow), (slotIndex - 1) % buttonsPerRow
    end
    return (slotIndex - 1) % buttonsPerRow, math_floor((slotIndex - 1) / buttonsPerRow)
end

-- The grid an Aura Panel's footprint and its unlock placeholders share.
-- The panel sizes to the FULL expanded grid -- one cell per entry whether that
-- entry's aura is up or not -- because Blizzard's container packs only ACTIVE
-- auras, and a footprint that followed activity would move under the player
-- every time an aura came or went. The extent is walked off GetAuraPanelCellSlot
-- instead of recomputed, so cell placement and cell count can never disagree.
-- An empty panel still owns one cell, which keeps it grabbable while unlocked.
-- Returns cols, rows, cellCount, cellWidth, cellHeight, spacing.
function CooldownCompanion:GetAuraPanelGridMetrics(groupId, group, buttonSizingOptions)
    local cellWidth, cellHeight = GetButtonDimensions(group, buttonSizingOptions, groupId)
    local style = group.style or {}
    local cellCount = self.GetGroupLayoutButtonCount
        and self:GetGroupLayoutButtonCount(groupId, group, {
            buttonUsabilityOptions = buttonSizingOptions,
        })
        or 0
    local cols, rows = 1, 1
    for slotIndex = 1, cellCount do
        local row, col = self:GetAuraPanelCellSlot(group, slotIndex)
        if row + 1 > rows then rows = row + 1 end
        if col + 1 > cols then cols = col + 1 end
    end
    return cols, rows, cellCount, cellWidth, cellHeight, style.buttonSpacing or ST.BUTTON_SPACING
end

-- Unlock affordance only. An Aura Panel materializes no CC buttons, so while it
-- is unlocked it would otherwise be an empty box with nothing to aim at. One dim
-- tile per entry marks the cells the aura container fills once those auras go
-- up. The preview root belongs to the PANEL rather than its drag handle: it must
-- remain visible while drag/nudge chrome fades, and while an unlocked container
-- is showing all of its member panels before one is selected.
function CooldownCompanion:SetAuraPanelPlaceholderPreviewShown(frame, shown)
    if not frame then return end

    shown = shown == true
    frame._auraPanelPlaceholderPreviewShown = shown or nil
    local root = frame._auraPanelPlaceholderRoot
    if root then
        if shown then
            local _, selectedInContainer = GetContainerPreviewSelectionState(frame.groupId)
            ST._SyncAuraPanelPlaceholderLevels(frame, selectedInContainer)
        end
        root:SetIgnoreParentAlpha(shown and frame._unlockGhost == true)
        root:SetShown(shown)
    end
    -- The mixed panel's aura-section tiles ride the same switch, so every path
    -- that raises or drops this preview -- drag chrome, container preview, the
    -- combat forced lock -- covers both without knowing which it has.
    ST.SetAuraSectionPlaceholderRootShown(frame, shown)

    -- The placeholders are the complete unlock presentation. Keep the live
    -- aura container bound but hidden so active auras are not double-drawn.
    -- The fan-out is by CHROME frame, so on a mixed panel this reaches that
    -- panel's own section containers and nothing else.
    self:SetAuraPanelChromeSuppressed(frame, shown)
end

function CooldownCompanion:UpdateAuraPanelPlaceholders(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]
    if not (frame and group) then return end

    local tiles = frame._auraPanelPlaceholders
    if not ST.IsAuraPanelGroup(group) then
        for _, tile in ipairs(tiles or {}) do
            tile:Hide()
        end
        self:SetAuraPanelPlaceholderPreviewShown(frame, false)
        return
    end

    local root = frame._auraPanelPlaceholderRoot
    if not root then
        root = CreateFrame("Frame", nil, frame)
        root:SetAllPoints(frame)
        root:EnableMouse(false)
        frame._auraPanelPlaceholderRoot = root
    end
    local previewShown = frame._auraPanelPlaceholderPreviewShown == true
    local _, selectedInContainer = GetContainerPreviewSelectionState(groupId)
    ST._SyncAuraPanelPlaceholderLevels(frame, selectedInContainer)
    root:SetIgnoreParentAlpha(previewShown and frame._unlockGhost == true)
    root:SetShown(previewShown)

    if not tiles then
        tiles = {}
        frame._auraPanelPlaceholders = tiles
    end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    local cellWidth, cellHeight, spacing = select(4, self:GetAuraPanelGridMetrics(groupId, group, buttonSizingOptions))
    local style = group.style or {}
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    local isBarMode = group.displayMode == "bars"

    local slotIndex = 0
    for _, buttonData in ipairs(group.buttons or {}) do
        if IsRuntimeButtonUsable(self, buttonData, group, buttonUsabilityOptions) then
            slotIndex = slotIndex + 1
            local tile = tiles[slotIndex]
            if not tile then
                tile = CreateFrame("Frame", nil, root, "BackdropTemplate")
                tile:EnableMouse(false)
                tile:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
                tile:SetBackdropColor(0.08, 0.08, 0.08, 0.6)
                tile.icon = tile:CreateTexture(nil, "ARTWORK")
                tile.icon:SetAlpha(0.6)
                tile.borderTextures = ST.CreateBorderTextureSet(tile, "OVERLAY")
                tile.iconBorderTextures = ST.CreateBorderTextureSet(tile, "OVERLAY")
                tile.barBounds = CreateFrame("Frame", nil, tile)
                tile.barBounds:EnableMouse(false)
                tile.iconBounds = CreateFrame("Frame", nil, tile)
                tile.iconBounds:EnableMouse(false)
                tiles[slotIndex] = tile
            end

            local row, col = self:GetAuraPanelCellSlot(group, slotIndex)
            tile:SetSize(cellWidth, cellHeight)
            tile:ClearAllPoints()
            tile:SetPoint(
                growthAnchor,
                frame,
                growthAnchor,
                xMul * col * (cellWidth + spacing),
                yMul * row * (cellHeight + spacing)
            )

            local effectiveStyle = self:GetEffectiveStyle(style, buttonData) or style
            local borderSize = effectiveStyle.borderSize or ST.DEFAULT_BORDER_SIZE
            local borderRenderMode = ST.GetBorderRenderMode(effectiveStyle)
            local effectiveBorderRenderMode = ST.GetEffectiveBorderRenderMode(
                borderRenderMode, nil, borderSize)
            local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(
                tile, borderSize, borderRenderMode)
            local borderColor = effectiveStyle.borderColor or { 0, 0, 0, 1 }

            -- Bar placeholders mirror the live Aura Panel's two chrome regions:
            -- the remaining bar area and, when enabled, its separate icon square.
            -- Icon placeholders keep one border around the whole cell.
            tile.icon:ClearAllPoints()
            tile.barBounds:ClearAllPoints()
            tile.iconBounds:ClearAllPoints()
            local placeholderIconShown = true
            local iconWidth, iconHeight
            if isBarMode then
                local isVertical = style.barFillVertical == true
                local iconSize, iconOffset, iconReverse
                placeholderIconShown, iconSize, iconOffset, iconReverse =
                    ST._GetAuraPanelBarIconGeometry(
                        effectiveStyle, true, isVertical, cellWidth, cellHeight)

                local barWidth, barHeight = cellWidth, cellHeight
                if placeholderIconShown then
                    local step = iconSize + iconOffset
                    tile.iconBounds:SetSize(iconSize, iconSize)
                    if isVertical then
                        local iconEdge, barEdge = "TOP", "BOTTOM"
                        if iconReverse then iconEdge, barEdge = "BOTTOM", "TOP" end
                        tile.iconBounds:SetPoint(iconEdge, tile, iconEdge, 0, 0)
                        barHeight = math_max(cellHeight - step, 1)
                        tile.barBounds:SetPoint(barEdge, tile, barEdge, 0, 0)
                    else
                        local iconEdge, barEdge = "LEFT", "RIGHT"
                        if iconReverse then iconEdge, barEdge = "RIGHT", "LEFT" end
                        tile.iconBounds:SetPoint(iconEdge, tile, iconEdge, 0, 0)
                        barWidth = math_max(cellWidth - step, 1)
                        tile.barBounds:SetPoint(barEdge, tile, barEdge, 0, 0)
                    end

                    local iconSide = math_max(1, iconSize - (2 * borderLayoutSize))
                    tile.icon:SetSize(iconSide, iconSide)
                    tile.icon:SetPoint("CENTER", tile.iconBounds, "CENTER", 0, 0)
                    iconWidth, iconHeight = iconSide, iconSide
                else
                    tile.iconBounds:SetSize(1, 1)
                    tile.iconBounds:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
                    tile.barBounds:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
                end
                tile.barBounds:SetSize(barWidth, barHeight)

                ST.ApplyBorderTextures(
                    tile.borderTextures, tile.barBounds, borderColor,
                    borderSize, effectiveBorderRenderMode)
                if placeholderIconShown then
                    ST.ApplyBorderTextures(
                        tile.iconBorderTextures, tile.iconBounds, borderColor,
                        borderSize, effectiveBorderRenderMode)
                else
                    ST.HideBorderTextures(tile.iconBorderTextures)
                end
            else
                tile.barBounds:SetSize(1, 1)
                tile.barBounds:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
                tile.iconBounds:SetSize(1, 1)
                tile.iconBounds:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
                ST.ApplyBorderTextures(
                    tile.borderTextures, tile, borderColor,
                    borderSize, effectiveBorderRenderMode)
                ST.HideBorderTextures(tile.iconBorderTextures)

                tile.icon:SetPoint(
                    "TOPLEFT", tile, "TOPLEFT", borderLayoutSize, -borderLayoutSize)
                tile.icon:SetPoint(
                    "BOTTOMRIGHT", tile, "BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)
                iconWidth = math_max(1, cellWidth - (2 * borderLayoutSize))
                iconHeight = math_max(1, cellHeight - (2 * borderLayoutSize))
            end

            if placeholderIconShown then
                if ST._ApplyIconTexCoord then
                    ST._ApplyIconTexCoord(tile.icon, iconWidth, iconHeight, effectiveStyle.iconZoom)
                else
                    tile.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            end

            local icon = buttonData.type == "spell" and C_Spell.GetSpellTexture(buttonData.id) or nil
            if placeholderIconShown and icon and not issecretvalue(icon) then
                tile.icon:SetTexture(icon)
                tile.icon:Show()
            else
                tile.icon:Hide()
            end

            tile:Show()
        end
    end

    for extraIndex = slotIndex + 1, #tiles do
        tiles[extraIndex]:Hide()
    end
end

local function ApplyTextGroupHeader(self, frame, group, style, isTextMode)
    local showHeader = isTextMode and style.showTextGroupHeader == true
    local headerHeight = 0

    if showHeader then
        if not frame.textHeader then
            frame.textHeader = frame:CreateFontString(nil, "OVERLAY")
            frame.textHeader:SetJustifyV("TOP")
        end
        local font = self:FetchFont(style.textFont or "Friz Quadrata TT")
        local fontSize = style.textHeaderFontSize or style.textFontSize or 12
        local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
        frame.textHeader:SetFont(font, fontSize, fontOutline)
        local hdrColor = style.textHeaderFontColor or {1, 1, 1, 1}
        frame.textHeader:SetTextColor(hdrColor[1], hdrColor[2], hdrColor[3], hdrColor[4] or 1)
        ST.ApplyFontShadowForOutline(frame.textHeader, fontOutline, style.textShadow == true)
        local align = style.textAlignment or "LEFT"
        frame.textHeader:SetJustifyH(align)
        frame.textHeader:SetText(group.name or "")
        frame.textHeader:ClearAllPoints()
        local growthOrigin = style.growthOrigin or "TOPLEFT"
        -- Raw "BOTTOM" counts only while it is the ACTIVE centered edge; an
        -- axis-mismatched value folds to TOPLEFT in layout, and the header
        -- must land on the same edge the entries grow from.
        local vEdge = (growthOrigin == "BOTTOMLEFT" or growthOrigin == "BOTTOMRIGHT"
            or ST.GetCenteredGrowthEdge(growthOrigin, ST.GetPanelLayoutOrientation(group.displayMode, style)) == "BOTTOM")
            and "BOTTOM" or "TOP"
        local anchor = align == "RIGHT" and (vEdge .. "RIGHT") or align == "CENTER" and vEdge or (vEdge .. "LEFT")
        local parentAnchor = anchor
        local xOff = (align == "CENTER") and 0 or (align == "RIGHT") and -2 or 2
        local yOff = vEdge == "BOTTOM" and 1 or -1
        frame.textHeader:SetPoint(anchor, frame, parentAnchor, xOff, yOff)
        frame.textHeader:SetWidth(frame:GetWidth() - 4)
        frame.textHeader:Show()
        headerHeight = fontSize + 4
    elseif frame.textHeader then
        frame.textHeader:Hide()
    end

    frame._textHeaderHeight = headerHeight
    frame._textHeaderShown = showHeader
    return headerHeight
end

local function ApplyActiveButtonLayout(self, groupId, frame, group, buttonSizingOptions, headerHeight)
    local buttonWidth, buttonHeight, isBarMode = GetButtonDimensions(group, buttonSizingOptions, groupId)
    local style = group.style or {}
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)
    local buttonsPerRow = style.buttonsPerRow or 12
    local isTriggerMode = group.displayMode == "trigger"
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    local centeredEdge = not ST.IsAuraPanelGroup(group)
        and ST.GetCenteredGrowthEdge(style.growthOrigin, orientation) or nil
    -- Panel Sections place their own members and park the base cluster on an
    -- interior anchor frame; the loop below then runs its existing arithmetic
    -- against that frame instead of the panel. A panel with no sections gets
    -- nil here and lays out through the exact code it always did.
    local sectionLayout, sectionLists, baseAnchor = ST.PrepareSectionedPanelLayout(
        frame, group, frame.buttons, buttonWidth, buttonHeight, spacing, headerHeight,
        buttonSizingOptions)
    local layoutRef = baseAnchor or frame
    local layoutButtons = sectionLists and sectionLists.base or frame.buttons
    local total = #layoutButtons
    local lineCount = math_ceil(total / buttonsPerRow)
    local visibleIndex = 0

    for _, button in ipairs(layoutButtons) do
        visibleIndex = visibleIndex + 1
        ClearButtonCompactSlotCache(button)
        button:ClearAllPoints()
        if isTriggerMode then
            button:SetPoint("CENTER", layoutRef, "CENTER", 0, 0)
        elseif centeredEdge then
            -- Each button pins its edge midpoint to the frame's, so full lines
            -- land where corner growth puts them and the trailing partial line
            -- centers itself against them.
            local line = math_floor((visibleIndex - 1) / buttonsPerRow)
            local indexInLine = (visibleIndex - 1) % buttonsPerRow
            local itemsInLine = (line == lineCount - 1) and (total - line * buttonsPerRow) or buttonsPerRow
            if orientation == "horizontal" then
                local edgeYMul = centeredEdge == "TOP" and -1 or 1
                button:SetPoint(centeredEdge, layoutRef, centeredEdge,
                    (indexInLine - (itemsInLine - 1) / 2) * (buttonWidth + spacing),
                    edgeYMul * (line * (buttonHeight + spacing) + headerHeight))
            else
                local edgeXMul = centeredEdge == "LEFT" and 1 or -1
                button:SetPoint(centeredEdge, layoutRef, centeredEdge,
                    edgeXMul * line * (buttonWidth + spacing),
                    ((itemsInLine - 1) / 2 - indexInLine) * (buttonHeight + spacing) - headerHeight / 2)
            end
        else
            local row, col
            if orientation == "horizontal" then
                row = math_floor((visibleIndex - 1) / buttonsPerRow)
                col = (visibleIndex - 1) % buttonsPerRow
            else
                col = math_floor((visibleIndex - 1) / buttonsPerRow)
                row = (visibleIndex - 1) % buttonsPerRow
            end
            button:SetPoint(growthAnchor, layoutRef, growthAnchor, xMul * col * (buttonWidth + spacing), yMul * (row * (buttonHeight + spacing) + headerHeight))
        end
    end

    if sectionLayout then
        -- The count stays the panel's materialized total: section members were
        -- placed by PrepareSectionedPanelLayout, not by the base loop above.
        visibleIndex = #frame.buttons
    end
    frame.visibleButtonCount = isTriggerMode and (visibleIndex > 0 and 1 or 0) or visibleIndex
    if group.parentContainerId and not self:IsGroupCompactLayoutActive(groupId, group) and self.GetGroupLayoutButtonCount then
        frame.layoutButtonCount = self:GetGroupLayoutButtonCount(groupId, group, {
            buttonUsabilityOptions = buttonSizingOptions,
        })
    else
        frame.layoutButtonCount = nil
    end
    frame._layoutDirty = false
end

local function FinishGroupButtonRefresh(self, groupId, frame, group)
    -- Compact population first measures all entries. Defer saved positioning
    -- until the immediate reflow has the final visible base dimensions.
    local compact = self:IsGroupCompactLayoutActive(groupId, group)
    frame._deferPanelBaseAnchor = compact or nil
    self:ResizeGroupFrame(groupId)

    -- Update clickthrough state
    self:UpdateGroupClickthrough(groupId)

    -- Initial cooldown update
    frame:UpdateCooldowns()

    -- Compact mode: apply reflow immediately so newly rebuilt buttons don't
    -- briefly appear before the next ticker-driven layout pass.
    frame._deferPanelBaseAnchor = nil
    if compact then
        frame._layoutDirty = true
        self:UpdateGroupLayout(groupId, true)
    end

    -- Propagate group frame strata to all button sub-elements
    local effectiveStrata = group.frameStrata or "MEDIUM"
    for _, button in ipairs(frame.buttons) do
        PropagateFrameStrata(button, effectiveStrata)
    end

    -- Update event-driven range check registrations
    self:UpdateRangeCheckRegistrations()
end

local function IsIconMasqueStyleRefreshUnsafe(self, group)
    local displayMode = group and group.displayMode
    return self.Masque
        and group
        and group.masqueEnabled
        and (displayMode == nil or displayMode == "icons")
end

local function ClearStyleUpdateEntries(entries, visibleCount)
    if not entries then return end
    local count = math_max(entries.count or 0, visibleCount or 0)
    for index = 1, count do
        entries[index] = nil
    end
    entries.count = 0
end

local function GetStyleUpdateEntries(self, groupId, frame, group)
    if IsIconMasqueStyleRefreshUnsafe(self, group) then
        return nil
    end

    local style = group.style or {}
    local isTextMode = group.displayMode == "text"
    local headerShown = isTextMode and style.showTextGroupHeader == true
    if (frame._textHeaderShown == true) ~= headerShown then
        return nil
    end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local sourceButtons = GetRuntimeGroupButtonList(self, frame, group)
    local entries = frame._styleUpdateEntries
    if not entries then
        entries = {}
        frame._styleUpdateEntries = entries
    end

    local previousCount = entries.count or 0
    local visibleIndex = 0
    -- Filtered exactly the way PopulateGroupButtons filters when it BUILDS the
    -- list: an aura-section member materializes no button, so counting one here
    -- would make the expectation disagree with frame.buttons on every style
    -- update and drop the fast path forever.
    local auraSectionPanel = ST.PanelHasAuraSection(group)
    for sourceIndex, buttonData in ipairs(sourceButtons) do
        if IsRuntimeButtonUsable(self, buttonData, group, buttonUsabilityOptions)
            and not (auraSectionPanel and ST.IsAuraSectionEntry(group, buttonData)) then
            visibleIndex = visibleIndex + 1
            local button = frame.buttons and frame.buttons[visibleIndex]
            if not button then
                ClearStyleUpdateEntries(entries, visibleIndex)
                return nil
            end
            local effectiveStyle = self:GetEffectiveStyle(style, buttonData)
            local poolKey = GetButtonPoolKey(group, buttonData, effectiveStyle)
            if button.buttonData ~= buttonData
                or button.index ~= sourceIndex
                or GetExistingButtonPoolKey(button) ~= poolKey then
                ClearStyleUpdateEntries(entries, visibleIndex)
                return nil
            end

            local entry = entries[visibleIndex]
            if not entry then
                entry = {}
                entries[visibleIndex] = entry
            end
            entry.style = effectiveStyle
        end
    end

    if #(frame.buttons or {}) ~= visibleIndex then
        ClearStyleUpdateEntries(entries, visibleIndex)
        return nil
    end

    for index = visibleIndex + 1, previousCount do
        entries[index] = nil
    end
    entries.count = visibleIndex
    return entries, buttonUsabilityOptions
end

function CooldownCompanion:PopulateGroupButtons(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    local isBarMode = group.displayMode == "bars"
    local style = group.style or {}
    local sourceButtons = GetRuntimeGroupButtonList(self, frame, group)

    -- Release existing buttons into bounded per-frame pools.
    for _, button in ipairs(frame.buttons) do
        ReleaseButtonToPool(self, frame, groupId, button)
    end
    wipe(frame.buttons)

    -- Text mode group header
    local isTextMode = group.displayMode == "text"
    local headerHeight = ApplyTextGroupHeader(self, frame, group, style, isTextMode)

    if ST.IsAuraPanelGroup(group) then
        -- An Aura Panel renders every entry through ONE Blizzard aura container
        -- mounted on this frame, so CC creates no buttons for it at all. Drain
        -- the pools instead of leaving the released buttons parked in them:
        -- nothing on this frame will ever acquire from a pool again, so pooled
        -- frames would sit there for the session. Normally there are none --
        -- the subtype is fixed at creation -- so this is defensive.
        self:ReleaseGroupButtonPools(frame)
        -- The counts carry the FULL expanded grid rather than aura activity, so
        -- the footprint holds still while auras come and go.
        local cellCount = select(3, self:GetAuraPanelGridMetrics(groupId, group, buttonSizingOptions))
        frame.visibleButtonCount = cellCount
        -- There is no frame.buttons list here for the availability sweep's
        -- identity comparison to read, so stamp the equivalent: the ordered
        -- identity of the very entries those cells were just counted from,
        -- under the same usability options the count used.
        -- GroupButtonSetNeedsRebuild diffs against this to decide whether the
        -- panel needs repopulating -- it is the panel's only refresh trigger.
        frame._auraPanelEntrySig = self:GetAuraPanelEntrySignature(group, buttonSizingOptions)
        -- layoutButtonCount reserves container space for entries that did not
        -- materialize; the grid already counts every entry, so it has no work.
        frame.layoutButtonCount = nil
        frame._layoutDirty = false
    else
        -- An aura-only SECTION does to its own members what an Aura Panel does to
        -- a whole panel: they render through Blizzard's container, so CC
        -- materializes no button for them -- and with no button they are never
        -- registered with Masque either, which is what keeps an aura section off
        -- a skin the mixed panel around it still uses.
        local auraSectionPanel = ST.PanelHasAuraSection(group)
        -- Create new buttons (skip untalented spells)
        for i, buttonData in ipairs(sourceButtons) do
            if IsRuntimeButtonUsable(self, buttonData, group, buttonUsabilityOptions)
                and not (auraSectionPanel and ST.IsAuraSectionEntry(group, buttonData)) then
                local effectiveStyle = self:GetEffectiveStyle(style, buttonData)
                local poolKey = GetButtonPoolKey(group, buttonData, effectiveStyle)
                local button = AcquireButtonFromPool(frame, poolKey, buttonData)
                local reusedButton = button ~= nil
                if not button then
                    if group.displayMode == "text" then
                        button = self:CreateTextFrame(frame, i, buttonData, effectiveStyle)
                    elseif isBarMode then
                        button = self:CreateBarFrame(frame, i, buttonData, effectiveStyle)
                    else
                        button = self:CreateButtonFrame(frame, i, buttonData, effectiveStyle)
                        if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
                            button:SetAlpha(0)
                            button._lastVisAlpha = 0
                        end
                    end
                end

                button._buttonPoolKey = poolKey
                table_insert(frame.buttons, button)
                if reusedButton then
                    PreparePooledButtonForUse(self, frame, group, button, i, buttonData, effectiveStyle)
                elseif buttonData._rotationAssistantVirtual == true and self.RefreshRotationAssistantButton then
                    self:RefreshRotationAssistantButton(button)
                end

                button:Show()

                -- Add to Masque if enabled (after button is shown and in the list, icons only)
                if group.displayMode == "icons" and group.masqueEnabled then
                    self:AddButtonToMasque(groupId, button)
                end
            end
        end

        -- The mixed panel's own version of the Aura Panel refresh trigger. Its
        -- aura-section members are invisible to the frame.buttons comparison
        -- GroupButtonSetNeedsRebuild makes -- they have no button to compare --
        -- so their ordered identity is carried here instead and diffed on the
        -- next availability sweep. nil while the panel has no aura section, so
        -- an ordinary panel stores nothing and compares nothing.
        frame._auraSectionEntrySig = auraSectionPanel
            and self:GetAuraSectionEntrySignature(group, buttonSizingOptions)
            or nil

        -- The other half of that trigger: the pass that turns the LAST aura
        -- section off. RefreshGroupFrame asks for the rebind by reading the
        -- panel's current state, and by then the state says "no aura sections",
        -- so the records those sections held would stay bound until something
        -- unrelated rebound them. This marker remembers that the panel HAD one,
        -- and RefreshGroupFrame consumes it once and clears it -- so a panel that
        -- never carried an aura section never sets it and never requests a thing.
        if auraSectionPanel then
            frame._auraSectionRebindOwed = true
        end

        ApplyActiveButtonLayout(self, groupId, frame, group, buttonSizingOptions, headerHeight)
    end

    FinishGroupButtonRefresh(self, groupId, frame, group)
    -- D3: button population changed — refresh the identity index (coalesced).
    self:RequestSpellButtonIndexRebuild("populate")
    -- Aura slots bind to materialized buttons: re-run the (coalesced,
    -- OOC-deferred) rebind pass whenever population changes.
    self:RequestAuraRebind("populate")
end

function CooldownCompanion:ResizeGroupFrame(groupId)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    local buttonWidth, buttonHeight, isBarMode = GetButtonDimensions(group, buttonSizingOptions, groupId)
    local style = group.style or {}
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)
    local buttonsPerRow = style.buttonsPerRow or 12
    -- Stamped by whichever layout pass ran last (ApplyActiveButtonLayout, or
    -- UpdateGroupLayout under compact mode), so the footprint and the placement
    -- are measured from one set of numbers and can never disagree.
    local sectionLayout = frame._sectionLayout
    local numButtons = frame.visibleButtonCount
        or (self:IsRotationAssistantGroup(group) and 1)
        or #group.buttons
    if group.parentContainerId and not self:IsGroupCompactLayoutActive(groupId, group) and frame.layoutButtonCount then
        numButtons = math_max(numButtons, frame.layoutButtonCount)
    end

    local targetWidth, targetHeight

    -- The section branch wins an empty count. A panel whose only entries live in
    -- AURA sections materializes no buttons at all, so numButtons reads 0 while
    -- the sections still own a real rectangle. For every other sectioned panel
    -- the two branches agree by construction (nothing materialized means every
    -- section line measures nothing, which is layout.isEmpty, whose footprint IS
    -- this one-button rectangle), so nothing else changes shape.
    if numButtons == 0 and not sectionLayout then
        targetWidth, targetHeight = buttonWidth, buttonHeight
    elseif sectionLayout then
        -- A sectioned panel spans the union of its base cluster and every
        -- section that has something visible in it. An all-hidden section
        -- contributes nothing, so the footprint never reserves empty space.
        -- footprintWidth/Height is the union, or -- with nothing visible at all
        -- -- the same one-button rectangle the numButtons == 0 branch above
        -- hands an empty panel, so the two branches cannot disagree.
        targetWidth = math_max(sectionLayout.footprintWidth, 1)
        targetHeight = math_max(sectionLayout.footprintHeight, 1)
    else
        local rows, cols
        if ST.IsAuraPanelGroup(group) then
            -- Aura Panels claim the full expanded grid regardless of which of
            -- their auras happen to be up right now.
            cols, rows = self:GetAuraPanelGridMetrics(groupId, group, buttonSizingOptions)
        elseif orientation == "horizontal" then
            cols = math_min(numButtons, buttonsPerRow)
            rows = math_ceil(numButtons / buttonsPerRow)
        else
            rows = math_min(numButtons, buttonsPerRow)
            cols = math_ceil(numButtons / buttonsPerRow)
        end

        local width = cols * buttonWidth + (cols - 1) * spacing
        local height = rows * buttonHeight + (rows - 1) * spacing

        -- Add text group header height if active
        local headerH = frame._textHeaderHeight or 0
        height = height + headerH

        targetWidth = math_max(width, buttonWidth)
        targetHeight = math_max(height, buttonHeight)
    end

    -- Group frames become protected when they contain secure action buttons.
    -- Defer resizing during combat and retry from the layout ticker.
    if InCombatLockdown() and frame:IsProtected() then
        frame._sizeDirty = true
        return false
    end

    frame:SetSize(targetWidth, targetHeight)

    -- ApplyTextGroupHeader runs before the layout pass in both
    -- PopulateGroupButtons and UpdateGroupStyle, so its frame:GetWidth() read
    -- is the pre-resize width. That was survivable while text width came from
    -- a slider; auto-sized entries change the width on any format/font/name
    -- change, so re-fit the header here, where the final width is known.
    if frame._textHeaderShown and frame.textHeader then
        frame.textHeader:SetWidth(math_max(1, targetWidth - 4))
    end

    local compactGrowthDirection = NormalizeCompactGrowthDirection(group.compactGrowthDirection)
    local fixedPoint
    if not ST.IsAuraPanelGroup(group) then
        -- Centered growth pins the edge midpoint so the panel's primary-axis
        -- center holds still as the frame resizes, the same compensation
        -- compact mode runs for its fixed corner. It wins over the compact
        -- start/center/end alignment, which it supersedes.
        fixedPoint = ST.GetCenteredGrowthEdge(style.growthOrigin, orientation)
    end
    if not fixedPoint and self:IsGroupCompactLayoutActive(groupId, group) then
        fixedPoint = GetCompactAnchorFixedPoint(orientation, compactGrowthDirection, style.growthOrigin)
    end
    local anchorX, anchorY = ST.UpdatePanelBaseAnchor(frame, group, sectionLayout,
        fixedPoint, targetWidth, targetHeight)
    if anchorX then UpdateCoordLabel(frame, anchorX, anchorY) end
    frame._sizeDirty = nil
    -- The one moment a dependent's SetPoint target has to change hands: the
    -- panel frame and its anchoring body are the same frame while there are no
    -- sections and different frames once there are. Between flips the base
    -- anchor child just moves inside the frame and dependents follow for free,
    -- so nothing pays for this on an ordinary resize.
    local anchorBodyActive = ST.IsPanelSectionAnchorBodyActive(frame)
    if anchorBodyActive ~= (frame._sectionAnchorBodyActive == true) then
        frame._sectionAnchorBodyActive = anchorBodyActive or nil
        self:ReanchorPanelSectionDependents(groupId)
    end
    -- Sizing is the one choke point every Aura Panel geometry change passes
    -- through (population, restyle, resize grip, deferred ticker resize), so the
    -- unlock placeholders re-fit here and nowhere else.
    if ST.IsAuraPanelGroup(group) then
        self:UpdateAuraPanelPlaceholders(groupId)
    elseif frame._auraSectionPlaceholders or ST.PanelHasAuraSection(group) then
        -- The aura-section twin, at the same choke point and for the same
        -- reason. Tiles it already has are enough to come back here on the pass
        -- that turned the flag OFF, which is what clears them.
        ST.UpdateAuraSectionPlaceholders(self, groupId, frame, group)
        local _, selectedInContainer = GetContainerPreviewSelectionState(groupId)
        ST._SyncAuraPanelPlaceholderLevels(frame, selectedInContainer)
        ST.SetAuraSectionPlaceholderRootShown(frame,
            frame._auraPanelPlaceholderPreviewShown == true)
    end
    -- The section click overlays re-fit at the same choke point, so a wheel or
    -- grip resize mid-gesture keeps them glued to the rects they name.
    ST.UpdateSectionMoverOverlays(self, frame, group)
    return true
end

-- Compact layout reflow: reposition visible buttons to fill gaps left by hidden ones.
-- Only runs when compact layout is effective and _layoutDirty is true.
function CooldownCompanion:UpdateGroupLayout(groupId, forceResize)
    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]
    if not frame or not group then return end

    if not self:IsGroupCompactLayoutActive(groupId, group) then
        for _, button in ipairs(frame.buttons) do
            ClearButtonCompactSlotCache(button)
        end
        frame._layoutDirty = false
        return
    end

    local buttonUsabilityOptions = self.GetGroupButtonUsabilityOptions
        and self:GetGroupButtonUsabilityOptions(groupId, group)
        or nil
    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    local buttonWidth, buttonHeight, isBarMode = GetButtonDimensions(group, buttonSizingOptions, groupId)
    local style = group.style or {}
    local spacing = style.buttonSpacing or ST.BUTTON_SPACING
    local orientation = ST.GetPanelLayoutOrientation(group.displayMode, style)
    local buttonsPerRow = style.buttonsPerRow or 12
    local compactGrowthDirection = NormalizeCompactGrowthDirection(group.compactGrowthDirection)

    local maxVis = (group.maxVisibleButtons and group.maxVisibleButtons > 0) and group.maxVisibleButtons or #frame.buttons

    local visibleButtons = frame._compactVisibleButtons
    if visibleButtons then
        wipe(visibleButtons)
    else
        visibleButtons = {}
        frame._compactVisibleButtons = visibleButtons
    end
    for _, button in ipairs(frame.buttons) do
        local forceVisible = button._forceVisibleByConfig
        local shouldHide = (not forceVisible) and (button._visibilityHidden or #visibleButtons >= maxVis)
        local wasShown = button:IsShown()
        if shouldHide then
            if wasShown then
                ResetButtonGlowTransitionState(button)
            end
            button:Hide()
        else
            button:Show()
            table_insert(visibleButtons, button)
        end
    end

    local visibleCount = #visibleButtons
    local headerH = frame._textHeaderHeight or 0
    -- Sections split the pass: the base grid packs only its own visible members,
    -- and each section independently collapses its own line toward its anchor.
    -- Hidden members drop out of a section's line exactly the way they drop out
    -- of a base row here.
    local sectionLayout, sectionLists, baseAnchor = ST.PrepareSectionedPanelLayout(
        frame, group, visibleButtons, buttonWidth, buttonHeight, spacing, headerH,
        buttonSizingOptions)
    local layoutRef = baseAnchor or frame
    local layoutButtons = sectionLists and sectionLists.base or visibleButtons
    local layoutCount = #layoutButtons
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    -- A centered growth edge fully specifies the arrangement, so it wins over
    -- the compact start/center/end alignment (owner ruling 2026-08-16): each
    -- packed line centers itself against the frame's edge midpoint.
    local centeredEdge = ST.GetCenteredGrowthEdge(style.growthOrigin, orientation)
    local lineCount = centeredEdge and math_ceil(layoutCount / buttonsPerRow) or 0
    for visibleIndex, button in ipairs(layoutButtons) do
        local x, y
        if centeredEdge then
            local line = math_floor((visibleIndex - 1) / buttonsPerRow)
            local indexInLine = (visibleIndex - 1) % buttonsPerRow
            local itemsInLine = (line == lineCount - 1) and (layoutCount - line * buttonsPerRow) or buttonsPerRow
            if orientation == "horizontal" then
                local edgeYMul = centeredEdge == "TOP" and -1 or 1
                x = (indexInLine - (itemsInLine - 1) / 2) * (buttonWidth + spacing)
                y = edgeYMul * (line * (buttonHeight + spacing) + headerH)
            else
                local edgeXMul = centeredEdge == "LEFT" and 1 or -1
                x = edgeXMul * line * (buttonWidth + spacing)
                y = ((itemsInLine - 1) / 2 - indexInLine) * (buttonHeight + spacing) - headerH / 2
            end
        else
            local row, col = GetCompactSlotForIndex(
                visibleIndex,
                layoutCount,
                buttonsPerRow,
                orientation,
                compactGrowthDirection
            )
            x = xMul * col * (buttonWidth + spacing)
            y = yMul * (row * (buttonHeight + spacing) + headerH)
        end
        local anchor = centeredEdge or growthAnchor
        if button._compactSlotAnchor ~= anchor
            or button._compactSlotX ~= x
            or button._compactSlotY ~= y then
            button:ClearAllPoints()
            button:SetPoint(anchor, layoutRef, anchor, x, y)
            button._compactSlotAnchor = anchor
            button._compactSlotX = x
            button._compactSlotY = y
        end
    end

    -- With sections in play the footprint can change while the total visible
    -- count does not (a section member hides as a base member appears), so the
    -- union is compared against the frame's real size too.
    -- Compared with a half-pixel tolerance: GetSize hands back float32 of what
    -- was set, while the union is computed in doubles (centered lines halve an
    -- odd pitch), so an exact test would report a change on a footprint that
    -- did not move and re-resize the frame every pass.
    local footprintChanged = false
    if sectionLayout then
        local currentWidth, currentHeight = frame:GetSize()
        -- Compared against the same footprintWidth/Height ResizeGroupFrame sizes
        -- from, empty panel included, or an all-hidden sectioned panel would
        -- measure 1x1 here against a one-button frame and ask for a resize on
        -- every single pass.
        footprintChanged = math_abs(currentWidth - math_max(sectionLayout.footprintWidth, 1)) > 0.5
            or math_abs(currentHeight - math_max(sectionLayout.footprintHeight, 1)) > 0.5
    end
    if forceResize or frame.visibleButtonCount ~= visibleCount or footprintChanged then
        frame.visibleButtonCount = visibleCount
        self:ResizeGroupFrame(groupId)
    end

    frame._layoutDirty = false
end

function CooldownCompanion:UpdateGroupStyle(groupId)
    -- The config's pinned mirror renders from saved settings, so it rides
    -- every style update — before the frame guard, because the mirror must
    -- refresh even when the group has no materialized live frame. No-op
    -- unless the config's wide view is showing this panel.
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(groupId)
    end

    local frame = self.groupFrames[groupId]
    local group = self.db.profile.groups[groupId]

    if not frame or not group then return end

    if InCombatLockdown() and frame:IsProtected() then
        self._pendingFullRefresh = true
        return
    end
    ST.UpdateGroupSizeLabel(frame)

    local entries, buttonUsabilityOptions = GetStyleUpdateEntries(self, groupId, frame, group)
    if not entries then
        self:PopulateGroupButtons(groupId)
        UpdateResizedPanelContainerWrapper(groupId)
        return
    end

    local style = group.style or {}
    local isTextMode = group.displayMode == "text"
    local headerHeight = ApplyTextGroupHeader(self, frame, group, style, isTextMode)

    for visibleIndex = 1, entries.count do
        local entry = entries[visibleIndex]
        local button = frame.buttons[visibleIndex]
        if button.UpdateStyle then
            button:UpdateStyle(entry.style)
        end
        if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
            button:SetAlpha(0)
            button._lastVisAlpha = 0
        end
    end

    local buttonSizingOptions = GetGroupButtonSizingOptions(self, groupId, group, buttonUsabilityOptions)
    ApplyActiveButtonLayout(self, groupId, frame, group, buttonSizingOptions, headerHeight)
    FinishGroupButtonRefresh(self, groupId, frame, group)

    -- The frame has its final size now, so the container unlock preview's
    -- border can re-fit on the same tick — config size sliders restyle
    -- through here, and the border must track them as tightly as it tracks
    -- the mover grip.
    UpdateResizedPanelContainerWrapper(groupId)

    -- Style-only fast path skips PopulateGroupButtons, but the aura slot kit
    -- consumes style keys at bind time — re-request the (coalesced) rebind so
    -- the composed aura visuals track style edits too. The groupId scopes the
    -- in-combat defer note to edits that actually touch an aura display.
    self:RequestAuraRebind("style", groupId)
end
