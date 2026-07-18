--[[
    CooldownCompanion - ButtonPanelPreview
    Clickable in-config mirror of the selected button panel for the wide
    buttons column. Renders every saved entry from saved settings only
    (never live button frames - live icon geometry can be secret-sensitive
    in config context), scaled to fit the host. Clicking an entry selects
    it through the normal config selection flow.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil

local StyleMirroredIconFrame = ST._StyleMirroredIconFrame
local GetLayoutPreviewIcon = ST._GetLayoutPreviewIcon
local GetConfigEntryDisplayName = ST._GetConfigEntryDisplayName
local SelectConfigButton = ST._SelectConfigButton
local ShowEntryContextMenu = ST._ShowEntryContextMenu
local SetIconAreaPoints = ST._SetIconAreaPoints
local SetBarAreaPoints = ST._SetBarAreaPoints
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local PerformButtonReorder = ST._PerformButtonReorder
local StartDragTracking = ST._StartDragTracking
local CancelDrag = ST._CancelDrag
local GetEffectiveTextHeight = ST._GetEffectiveTextHeight

local PANEL_PREVIEW_PADDING = 12
local PANEL_PREVIEW_DISABLED_ALPHA = 0.45
local PANEL_PREVIEW_RING_COLOR = { 0.38, 0.60, 0.92, 1 }
-- Above the bar slots' text frame (statusBar level + 2)
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = 5
-- Badges counter-scale against the preview's scale-to-fit so they stay
-- readable, clamped so they never dwarf a heavily scaled-down slot.
local PANEL_PREVIEW_BADGE_SCREEN_SIZE = 14
-- Matches the resources layout preview's tween timing
local PANEL_PREVIEW_ANIM_DURATION = 0.08
local DEFAULT_BAR_COLOR = { 0.2, 0.6, 1.0, 1.0 }

-- Mirror of GroupFrame.lua GetGrowthMultipliers: anchor corner plus x/y
-- offset signs for the configured growth origin.
local function GetGrowthMultipliers(growthOrigin)
    if growthOrigin == "TOPRIGHT" then return -1, -1, "TOPRIGHT" end
    if growthOrigin == "BOTTOMLEFT" then return 1, 1, "BOTTOMLEFT" end
    if growthOrigin == "BOTTOMRIGHT" then return -1, 1, "BOTTOMRIGHT" end
    return 1, -1, "TOPLEFT"
end

local function EnsurePreviewState(host)
    local preview = host._cdcPanelPreview
    if preview then
        preview.buildId = (preview.buildId or 0) + 1
        return preview
    end

    preview = {
        buildId = 1,
        pools = { iconSlots = {}, barSlots = {}, textSlots = {} },
        used = { iconSlots = 0, barSlots = 0, textSlots = 0 },
    }
    host._cdcPanelPreview = preview

    local root = CreateFrame("Frame", nil, host)
    root:SetAllPoints(host)
    root:SetClipsChildren(false)
    root:Hide()
    preview.root = root

    local content = CreateFrame("Frame", nil, root)
    content:SetClipsChildren(false)
    preview.content = content

    return preview
end

local function ResetPreviewState(preview)
    for poolName in pairs(preview.pools) do
        preview.used[poolName] = 0
    end
    preview.root:Show()
end

local function FinalizePreviewState(preview)
    for poolName, pool in pairs(preview.pools) do
        local used = preview.used[poolName] or 0
        for index = used + 1, #pool do
            local frame = pool[index]
            frame:Hide()
            frame:ClearAllPoints()
            frame:SetScript("OnMouseDown", nil)
            frame:SetScript("OnMouseUp", nil)
            frame:SetScript("OnEnter", nil)
            frame:SetScript("OnLeave", nil)
        end
    end
end

-- Hover glow and selection marker shared by both slot kinds.
local function AttachSlotHighlights(frame)
    frame.hoverHighlight = CreateFrame("Frame", nil, frame)
    frame.hoverHighlight:SetAllPoints(frame)
    frame.hoverHighlight:EnableMouse(false)
    frame.hoverHighlight.tex = frame.hoverHighlight:CreateTexture(nil, "OVERLAY")
    frame.hoverHighlight.tex:SetAllPoints()
    frame.hoverHighlight.tex:SetColorTexture(1, 1, 1, 0.10)
    frame.hoverHighlight.tex:SetBlendMode("ADD")
    frame.hoverHighlight:Hide()

    -- Selection marker: held hover-style glow plus a thin accent ring,
    -- sized well for icon-grid density (the resource preview's arrows
    -- overwhelm small icons).
    frame.selectedHighlight = CreateFrame("Frame", nil, frame)
    frame.selectedHighlight:SetAllPoints(frame)
    frame.selectedHighlight:EnableMouse(false)
    frame.selectedHighlight.tex = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    frame.selectedHighlight.tex:SetAllPoints()
    frame.selectedHighlight.tex:SetColorTexture(1, 1, 1, 0.10)
    frame.selectedHighlight.tex:SetBlendMode("ADD")
    frame.selectedHighlight.ringTextures = {}
    for i = 1, 4 do
        frame.selectedHighlight.ringTextures[i] = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    end
    frame.selectedHighlight:Hide()
end

-- Icon-mode slot: the frame shape ST._StyleMirroredIconFrame expects
-- (bg, icon, countText, borderTextures[4]).
local function CreateIconSlot(parent)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetClipsChildren(false)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.countText:SetPoint("CENTER")
    frame.borderTextures = {}
    for i = 1, 4 do
        frame.borderTextures[i] = frame:CreateTexture(nil, "OVERLAY")
    end

    AttachSlotHighlights(frame)
    return frame
end

-- Bar-mode slot: static twin of the frames BarMode.lua CreateBarFrame
-- builds (minus cooldowns, time text, and counts).
local function CreateBarSlot(parent)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetClipsChildren(false)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.iconBg = frame:CreateTexture(nil, "BACKGROUND")
    frame.icon = frame:CreateTexture(nil, "ARTWORK")

    frame.iconBounds = CreateFrame("Frame", nil, frame)
    frame.iconBounds:EnableMouse(false)
    frame.barBounds = CreateFrame("Frame", nil, frame)
    frame.barBounds:EnableMouse(false)

    frame.statusBar = CreateFrame("StatusBar", nil, frame)
    frame.statusBar:EnableMouse(false)

    frame.textFrame = CreateFrame("Frame", nil, frame)
    frame.textFrame:EnableMouse(false)
    frame.nameText = frame.textFrame:CreateFontString(nil, "OVERLAY")

    frame.iconBorderTextures = {}
    frame.borderTextures = {}
    for i = 1, 4 do
        frame.iconBorderTextures[i] = frame:CreateTexture(nil, "OVERLAY")
        frame.borderTextures[i] = frame:CreateTexture(nil, "OVERLAY")
    end

    AttachSlotHighlights(frame)
    return frame
end

-- Text-mode slot: static twin of TextMode.lua CreateTextFrame (bg,
-- borders, single FontString; no cooldown/count runtime pieces).
local function CreateTextSlot(parent)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetClipsChildren(false)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.textString = frame:CreateFontString(nil, "OVERLAY")
    frame.borderTextures = {}
    for i = 1, 4 do
        frame.borderTextures[i] = frame:CreateTexture(nil, "OVERLAY")
    end

    AttachSlotHighlights(frame)
    return frame
end

local SLOT_FACTORIES = {
    iconSlots = CreateIconSlot,
    barSlots = CreateBarSlot,
    textSlots = CreateTextSlot,
}

local function AcquireSlot(preview, parent, poolName)
    local pool = preview.pools[poolName]
    local index = (preview.used[poolName] or 0) + 1
    preview.used[poolName] = index
    local frame = pool[index]
    if not frame then
        frame = SLOT_FACTORIES[poolName](parent)
        pool[index] = frame
    end
    frame:SetParent(parent)
    frame:Show()
    frame:SetAlpha(1)
    frame.hoverHighlight:Hide()
    frame.selectedHighlight:Hide()
    return frame
end

local function SetPreviewMessage(preview, message)
    local label = preview.messageLabel
    if not label then
        label = preview.root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(true)
        label:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 18, -18)
        label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, 18)
        preview.messageLabel = label
    end
    label:SetText(message or "")
    label:Show()
end

local function HidePreviewMessage(preview)
    if preview.messageLabel then
        preview.messageLabel:Hide()
    end
end

local function ApplySelectionVisuals(slot, index)
    local isSelected = CS.selectedButton == index or CS.selectedButtons[index] == true
    if not isSelected then
        slot.selectedHighlight:Hide()
        return
    end
    slot.selectedHighlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
    ST.ApplyBorderTextures(slot.selectedHighlight.ringTextures, slot.selectedHighlight,
        PANEL_PREVIEW_RING_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
    slot.selectedHighlight:Show()
end

-- Entry status signals, mirroring the column 2 row badges exactly.
local function CollectEntryStatus(buttonData, group)
    local usable = CooldownCompanion:IsButtonUsable(buttonData, group)
    local loadAllowed = CooldownCompanion:IsButtonLoadConditionMet(buttonData, group)
    local status = {
        usable = usable,
        disabled = buttonData.enabled == false,
        warn = (not usable) and buttonData.enabled ~= false,
        loadBlocked = not loadAllowed,
        override = CooldownCompanion:HasStyleOverrides(buttonData) and true or false,
        fallback = CooldownCompanion.HasItemFallbacks(buttonData) and true or false,
        talent = (buttonData.talentConditions and #buttonData.talentConditions > 0) and true or false,
        sound = false,
    }
    if buttonData.type == "spell" then
        local enabledSoundEvents = CooldownCompanion:GetEnabledSoundAlertEventsForButton(buttonData)
        -- The aura-applied sound is config-only (played by the game's aura
        -- system, never the runtime engine), so it needs its own check.
        if not enabledSoundEvents
            and (buttonData.auraTracking or buttonData.addedAs == "aura")
            and CooldownCompanion:GetAuraAppliedSoundFileForButton(buttonData) then
            enabledSoundEvents = true
        end
        status.sound = enabledSoundEvents and true or false
    end
    return status
end

-- Ordered badge descriptors, same atlases and meaning as the retired
-- column 2 entry rows; the identity strip in the wide column renders the
-- full set. The "warn" label is replaced with the load-conditions wording
-- when status.loadBlocked is set.
local ENTRY_STATUS_BADGES = {
    { key = "disabled", atlas = "GM-icon-visibleDis-pressed", label = "Disabled" },
    { key = "warn", atlas = "Ping_Marker_Icon_Warning", label = "Spell/item unavailable" },
    { key = "override", atlas = "Crosshair_VehichleCursor_32", label = "Has appearance overrides" },
    { key = "fallback", atlas = "banker", label = "Uses item fallbacks" },
    { key = "sound", atlas = "common-icon-sound", label = "Sound alerts enabled" },
    { key = "talent", atlas = "UI-HUD-MicroMenu-SpecTalents-Mouseover", label = "Has talent conditions" },
}

-- Single problem indicator in the slot's top-right corner: only states
-- where the entry won't behave normally (disabled, or unusable/blocked)
-- earn a mark on the icon, drawn over a dark backdrop so it reads against
-- bright icon art. Informational badges (talent, sound, override,
-- fallback) live in the identity strip and the hover tooltip instead.
local function ApplySlotBadges(slot, status, scale)
    local atlas
    if status.disabled then
        atlas = "GM-icon-visibleDis-pressed"
    elseif status.warn then
        atlas = "Ping_Marker_Icon_Warning"
    end
    if not atlas then
        if slot.problemBadge then slot.problemBadge:Hide() end
        if slot.problemBadgeBack then slot.problemBadgeBack:Hide() end
        return
    end
    local tex = slot.problemBadge
    local back = slot.problemBadgeBack
    if not tex then
        back = slot:CreateTexture(nil, "OVERLAY", nil, 6)
        back:SetColorTexture(0, 0, 0, 0.7)
        slot.problemBadgeBack = back
        tex = slot:CreateTexture(nil, "OVERLAY", nil, 7)
        slot.problemBadge = tex
    end
    local size = math_min(24, math_max(12, PANEL_PREVIEW_BADGE_SCREEN_SIZE / math_max(scale, 0.01)))
    tex:SetAtlas(atlas, false)
    tex:SetSize(size, size)
    tex:ClearAllPoints()
    tex:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)
    back:ClearAllPoints()
    back:SetPoint("CENTER", tex, "CENTER", 0, 0)
    back:SetSize(size + 2, size + 2)
    tex:Show()
    back:Show()
end

------------------------------------------------------------------------
-- In-preview drag-to-reorder, via the shared "layout-slot" drag kind.
-- Slots map 1:1 to group.buttons indices; the resolved drop target is an
-- insertion index in the pre-removal list (PerformButtonReorder's
-- convention). Raw cursor coordinates are compared against GetScaledRect
-- values, matching the drag tracker and the resources layout preview.
------------------------------------------------------------------------
-- Slot placement with tween bookkeeping (the resources preview's
-- ApplySlotGeometry/QueueSlotTween pattern, reduced to position-only:
-- slot sizes never change during a reorder drag).
local function ApplyPreviewSlotGeometry(preview, slot, anchor, x, y)
    slot:ClearAllPoints()
    slot:SetPoint(anchor, preview.content, anchor, x, y)
    slot._cdcPrevAnchor = anchor
    slot._cdcPrevX = x
    slot._cdcPrevY = y
    if preview.tweens then
        preview.tweens[slot] = nil
    end
end

local function QueuePreviewSlotTween(preview, slot, anchor, x, y)
    if slot._cdcPrevAnchor ~= anchor or not slot._cdcPrevX then
        ApplyPreviewSlotGeometry(preview, slot, anchor, x, y)
        return
    end
    local cx, cy = slot._cdcPrevX, slot._cdcPrevY
    if math.abs(cx - x) < 0.5 and math.abs(cy - y) < 0.5 then
        ApplyPreviewSlotGeometry(preview, slot, anchor, x, y)
        return
    end
    preview.tweens[slot] = {
        anchor = anchor,
        sx = cx, sy = cy,
        tx = x, ty = y,
        t0 = GetTime(),
        dur = PANEL_PREVIEW_ANIM_DURATION,
    }
end

local function EaseInOut(t)
    return t < 0.5 and (2 * t * t) or (1 - (((-2 * t + 2) ^ 2) / 2))
end

local function Interpolate(a, b, t)
    return a + ((b - a) * t)
end

local function UpdateGhostPosition(ghost)
    if not (ghost and ghost:IsShown()) then return end
    local uiScale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / uiScale
    cursorY = cursorY / uiScale
    local offsetX = math_floor((ghost:GetWidth() or 0) / 2)
    local offsetY = math_floor((ghost:GetHeight() or 0) / 2)
    ghost:ClearAllPoints()
    ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX - offsetX, cursorY + offsetY)
end

local function TickPanelPreview(preview)
    local active = false
    local now = GetTime()
    for slot, tween in pairs(preview.tweens) do
        local progress = math_min(1, math_max(0, (now - tween.t0) / tween.dur))
        local eased = EaseInOut(progress)
        local x = Interpolate(tween.sx, tween.tx, eased)
        local y = Interpolate(tween.sy, tween.ty, eased)
        slot:ClearAllPoints()
        slot:SetPoint(tween.anchor, preview.content, tween.anchor, x, y)
        slot._cdcPrevAnchor = tween.anchor
        slot._cdcPrevX = x
        slot._cdcPrevY = y
        if progress >= 1 then
            preview.tweens[slot] = nil
        else
            active = true
        end
    end
    UpdateGhostPosition(preview.ghost)
    if not active and not preview.ghostActive then
        preview.root:SetScript("OnUpdate", nil)
    end
end

local function StartPreviewTicker(preview)
    preview.root:SetScript("OnUpdate", function()
        TickPanelPreview(preview)
    end)
end

-- Cursor-following ghost: the dragged entry's footprint with its icon
-- centered, floating on the tooltip strata like the resources ghost.
local function EnsurePreviewGhost(preview)
    local ghost = preview.ghost
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetFrameLevel(2000)
        ghost:EnableMouse(false)
        ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
        ghost.bg:SetAllPoints()
        ghost.bg:SetColorTexture(0.05, 0.10, 0.18, 0.55)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ghost:Hide()
        preview.ghost = ghost
    end
    return ghost
end

local function ConfigurePreviewGhost(preview, layoutDrag, buttonData)
    local ghost = EnsurePreviewGhost(preview)
    local scale = layoutDrag.scale
    local gw = math_max(8, layoutDrag.slotW * scale)
    local gh = math_max(8, layoutDrag.slotH * scale)
    ghost:SetSize(gw, gh)
    local iconSize = math_min(gw, gh)
    ghost.icon:ClearAllPoints()
    ghost.icon:SetSize(iconSize, iconSize)
    ghost.icon:SetPoint("CENTER")
    local icon = GetLayoutPreviewIcon and GetLayoutPreviewIcon(buttonData)
    if icon then
        ghost.icon:SetTexture(icon)
        ghost.icon:Show()
    else
        ghost.icon:Hide()
    end
    ghost:SetAlpha(0.9)
    ghost:Show()
    preview.ghostActive = true
    UpdateGhostPosition(ghost)
end

local function ClearPreviewGhost(preview)
    preview.ghostActive = false
    if preview.ghost then
        preview.ghost:Hide()
    end
end

-- Translucent marker filling the cell the entry would land in.
local function EnsureGapFrame(preview)
    local gap = preview.gapFrame
    if not gap then
        gap = CreateFrame("Frame", nil, preview.content)
        gap.bg = gap:CreateTexture(nil, "BACKGROUND")
        gap.bg:SetAllPoints()
        gap.bg:SetColorTexture(PANEL_PREVIEW_RING_COLOR[1], PANEL_PREVIEW_RING_COLOR[2],
            PANEL_PREVIEW_RING_COLOR[3], 0.18)
        preview.gapFrame = gap
    end
    return gap
end

-- Slide the remaining slots into the arrangement they'd have after the
-- drop: the lifted entry's slot goes invisible, the others compact in
-- order with a gap held open at the insertion cell.
local function UpdateGridDragPreview(preview, layoutDrag, sourceIndex, dropTarget)
    local insertIndex = dropTarget and dropTarget.insertIndex
    local gapPos
    if insertIndex then
        gapPos = insertIndex
        if gapPos > sourceIndex then gapPos = gapPos - 1 end
        if gapPos > layoutDrag.count then gapPos = layoutDrag.count end
    end
    local renderIndex = 1
    for i = 1, layoutDrag.count do
        local slot = layoutDrag.slots[i]
        if slot then
            if i == sourceIndex then
                slot:SetAlpha(0)
            else
                local displayIndex = renderIndex
                if gapPos and displayIndex >= gapPos then
                    displayIndex = displayIndex + 1
                end
                local x, y = layoutDrag.cellXY(displayIndex)
                QueuePreviewSlotTween(preview, slot, layoutDrag.anchor, x, y)
                renderIndex = renderIndex + 1
            end
        end
    end
    if gapPos then
        local gap = EnsureGapFrame(preview)
        gap:SetSize(layoutDrag.slotW, layoutDrag.slotH)
        local x, y = layoutDrag.cellXY(gapPos)
        QueuePreviewSlotTween(preview, gap, layoutDrag.anchor, x, y)
        gap:Show()
    elseif preview.gapFrame then
        preview.gapFrame:Hide()
    end
end

local function ResetGridDragPreview(preview, layoutDrag)
    for i = 1, layoutDrag.count do
        local slot = layoutDrag.slots[i]
        if slot then
            local x, y = layoutDrag.cellXY(i)
            QueuePreviewSlotTween(preview, slot, layoutDrag.anchor, x, y)
            slot:SetAlpha(slot._cdcBaseAlpha or 1)
        end
    end
    if preview.gapFrame then
        preview.gapFrame:Hide()
    end
end

local function CreatePreviewLayoutDrag(preview, panelId)
    -- Builders fill in count, slotW/H, scale, anchor, and cellXY (display
    -- cell index -> anchored x,y offset) after creating the model.
    local layoutDrag = {
        panelPreview = true,
        slots = {},
        count = 0,
        slotW = 1,
        slotH = 1,
        scale = 1,
        anchor = "TOPLEFT",
    }

    -- Insertion anchors: midpoints between consecutive slot centers, with
    -- the two end positions extrapolated half a step beyond the run, so
    -- the nearest anchor is the insertion index. Works for any growth
    -- origin and wrapping because it only uses actual slot geometry.
    layoutDrag.resolveDropTarget = function(cursorX, cursorY)
        local count = layoutDrag.count
        if count < 2 then return nil end
        local root = preview.root
        if not (root and root:IsVisible() and root.GetScaledRect) then return nil end
        local left, bottom, width, height = root:GetScaledRect()
        if not left then return nil end
        local margin = 40
        if cursorX < left - margin or cursorX > left + width + margin
            or cursorY < bottom - margin or cursorY > bottom + height + margin then
            return nil
        end

        -- Base cell centers, NOT live slot rects: the slots animate while
        -- a drag is held, and resolving against moving frames would make
        -- the drop target oscillate under the cursor (the "stable slots"
        -- trick from the resources preview).
        local content = preview.content
        local cLeft, cBottom, cWidth, cHeight = content:GetScaledRect()
        if not (cLeft and cBottom and cWidth and cHeight) then return nil end
        local localW = content:GetWidth() or 1
        local localH = content:GetHeight() or 1
        local factor = (localW > 0) and (cWidth / localW) or 1
        local anchor = layoutDrag.anchor
        local slotW, slotH = layoutDrag.slotW, layoutDrag.slotH

        local centers = {}
        for i = 1, count do
            local x, y = layoutDrag.cellXY(i)
            -- Convert the anchored offset to top-left space, then to the
            -- scaled screen coordinates raw cursor values live in.
            local tlX, tlY
            if anchor == "TOPLEFT" then
                tlX, tlY = x + slotW / 2, y - slotH / 2
            elseif anchor == "TOPRIGHT" then
                tlX, tlY = localW + x - slotW / 2, y - slotH / 2
            elseif anchor == "BOTTOMLEFT" then
                tlX, tlY = x + slotW / 2, -localH + y + slotH / 2
            else -- BOTTOMRIGHT
                tlX, tlY = localW + x - slotW / 2, -localH + y + slotH / 2
            end
            centers[i] = {
                x = cLeft + tlX * factor,
                y = cBottom + cHeight + tlY * factor,
            }
        end

        local bestIndex, bestDist
        for i = 1, count + 1 do
            local ax, ay
            if i == 1 then
                ax = centers[1].x - (centers[2].x - centers[1].x) / 2
                ay = centers[1].y - (centers[2].y - centers[1].y) / 2
            elseif i == count + 1 then
                ax = centers[count].x + (centers[count].x - centers[count - 1].x) / 2
                ay = centers[count].y + (centers[count].y - centers[count - 1].y) / 2
            else
                ax = (centers[i - 1].x + centers[i].x) / 2
                ay = (centers[i - 1].y + centers[i].y) / 2
            end
            local dx, dy = cursorX - ax, cursorY - ay
            local dist = dx * dx + dy * dy
            if not bestDist or dist < bestDist then
                bestDist, bestIndex = dist, i
            end
        end
        return { insertIndex = bestIndex }
    end

    layoutDrag.onActivate = function(state)
        GameTooltip:Hide()
        local sourceIndex = state.slotData and state.slotData.index
        local slot = sourceIndex and layoutDrag.slots[sourceIndex]
        if slot and slot.hoverHighlight then
            slot.hoverHighlight:Hide()
        end
        ConfigurePreviewGhost(preview, layoutDrag, state.slotData and state.slotData.buttonData)
        UpdateGridDragPreview(preview, layoutDrag, sourceIndex, state.dropTarget)
        StartPreviewTicker(preview)
    end

    layoutDrag.onUpdate = function(state, cursorX, cursorY, dropTarget)
        local sourceIndex = state.slotData and state.slotData.index
        if not sourceIndex then return end
        UpdateGridDragPreview(preview, layoutDrag, sourceIndex, dropTarget)
        if not preview.ghostActive then
            ConfigurePreviewGhost(preview, layoutDrag, state.slotData.buttonData)
        end
        StartPreviewTicker(preview)
    end

    layoutDrag.onCancel = function()
        ResetGridDragPreview(preview, layoutDrag)
        ClearPreviewGhost(preview)
        -- Keep ticking so the return-to-rest tween plays out
        StartPreviewTicker(preview)
    end

    layoutDrag.applyDrop = function(state)
        local dropTarget = state and state.dropTarget
        local sourceIndex = state and state.slotData and state.slotData.index
        local insertIndex = dropTarget and dropTarget.insertIndex
        if not (PerformButtonReorder and sourceIndex and insertIndex) then return end
        if insertIndex == sourceIndex or insertIndex == sourceIndex + 1 then return end
        PerformButtonReorder(panelId, sourceIndex, insertIndex)
        CooldownCompanion:RefreshGroupFrame(panelId)
        CooldownCompanion:RefreshConfigPanel()
    end

    return layoutDrag
end

-- Shift-hover shows the real spell/item tooltip, mirroring the column 2
-- entry rows; a plain hover shows the decorated entry name plus the same
-- status lines the row badges carry.
local function ShowEntrySlotTooltip(slot, buttonData, status)
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    if IsShiftKeyDown() then
        if buttonData.type == "spell" and buttonData.id then
            GameTooltip:SetSpellByID(buttonData.id)
            GameTooltip:Show()
            return
        elseif buttonData.type == "item" and buttonData.id then
            GameTooltip:SetItemByID(buttonData.id)
            GameTooltip:Show()
            return
        elseif CooldownCompanion.IsEquipmentSlotEntry
            and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
            local effectiveItem = CooldownCompanion.ResolveEffectiveItem
                and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
            if effectiveItem and effectiveItem.trackable and effectiveItem.itemID then
                GameTooltip:SetItemByID(effectiveItem.itemID)
                GameTooltip:Show()
                return
            end
        end
    end
    local name = GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
    GameTooltip:SetText(name or "Entry", 1, 1, 1)
    if buttonData.type == "spell" then
        -- Same addedAs fallback the name decorations use.
        local addedAs = buttonData.addedAs
        if addedAs ~= "spell" and addedAs ~= "aura" then
            addedAs = buttonData.isPassive and "aura" or "spell"
        end
        GameTooltip:AddLine(addedAs == "aura" and "Tracked as an aura" or "Tracked as a spell",
            0.6, 0.6, 0.6)
    end
    if status.disabled then
        GameTooltip:AddLine("Disabled", 0.6, 0.6, 0.6)
    end
    if status.warn then
        if status.loadBlocked then
            GameTooltip:AddLine("Hidden by load conditions", 1, 0.3, 0.3)
        else
            GameTooltip:AddLine("Spell/item unavailable", 1, 0.3, 0.3)
        end
    end
    if status.override then
        GameTooltip:AddLine("Has appearance overrides", 1, 1, 1)
    end
    if status.fallback then
        GameTooltip:AddLine("Uses item fallbacks", 1, 1, 1)
    end
    if status.sound then
        GameTooltip:AddLine("Sound alerts enabled", 1, 1, 1)
    end
    if status.talent then
        GameTooltip:AddLine("Has talent conditions", 1, 1, 1)
    end
    if CooldownCompanion:HasLocalLoadConditions(buttonData) then
        GameTooltip:AddLine("This entry adds load conditions.", 0.7, 0.7, 0.7)
    end
    if slot._cdcDraggable then
        GameTooltip:AddLine("Drag to reorder.", 0.75, 0.82, 0.92)
    end
    GameTooltip:Show()
end

local function WireEntryInteraction(slot, panelId, index, buttonData, status, layoutDrag)
    slot._cdcDraggable = layoutDrag ~= nil
    slot:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or GetCursorInfo() then return end
        if not (layoutDrag and StartDragTracking) then return end
        local cursorX, cursorY = GetCursorPosition()
        -- No `widget` field: the tracker's dim/restore would fight the
        -- alpha choreography our layoutDrag callbacks run (dragged slot
        -- goes fully invisible; disabled slots rest at reduced alpha).
        CS.dragState = {
            kind = "layout-slot",
            phase = "pending",
            previewSlot = self,
            scrollWidget = UIParent,
            startX = cursorX,
            startY = cursorY,
            layoutDrag = layoutDrag,
            slotData = { index = index, buttonData = buttonData },
        }
        StartDragTracking()
    end)
    slot:SetScript("OnMouseUp", function(self, mouseButton)
        if GetCursorInfo() then return end
        if mouseButton == "LeftButton" then
            local state = CS.dragState
            if state then
                -- Only fall through to selection for our own still-pending
                -- press; active drags finish through the tracker.
                if state.kind ~= "layout-slot" or state.phase ~= "pending" or state.previewSlot ~= self then
                    return
                end
                if CancelDrag then CancelDrag() else CS.dragState = nil end
            end
            SelectConfigButton(panelId, index, { multi = IsControlKeyDown() })
            CooldownCompanion:RefreshConfigPanel()
        elseif mouseButton == "RightButton" or mouseButton == "MiddleButton" then
            if CS.dragState and CS.dragState.phase == "active" then return end
            if ShowEntryContextMenu then
                ShowEntryContextMenu(panelId, index, buttonData)
            end
        end
    end)
    slot:SetScript("OnEnter", function(self)
        if CS.dragState and CS.dragState.phase == "active" then return end
        self.hoverHighlight:SetFrameLevel(self:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
        self.hoverHighlight:Show()
        ShowEntrySlotTooltip(self, buttonData, status)
    end)
    slot:SetScript("OnLeave", function(self)
        self.hoverHighlight:Hide()
        GameTooltip:Hide()
    end)
end

-- Entry footprint and grid settings mirrored from GroupFrame.lua
-- (GetButtonDimensions + ApplyActiveButtonLayout).
local function GetPanelGeometry(group, isBarMode, isTextMode)
    local style = group.style or {}
    local w, h
    if isTextMode then
        -- Mirror of GroupFrame's text-mode sizing: widest entry width and
        -- tallest effective format height win (the config mirror measures
        -- every entry, not just currently usable ones).
        w = style.textWidth or 200
        h = style.textHeight or 20
        if GetEffectiveTextHeight then
            h = GetEffectiveTextHeight(style, style.textFormat)
            for _, buttonData in ipairs(group.buttons or {}) do
                local effectiveStyle = CooldownCompanion.GetEffectiveStyle
                    and CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
                local fmt = buttonData.textFormat or effectiveStyle.textFormat
                w = math_max(w, effectiveStyle.textWidth or 200)
                h = math_max(h, GetEffectiveTextHeight(effectiveStyle, fmt))
            end
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
    return {
        entryWidth = w,
        entryHeight = h,
        spacing = style.buttonSpacing or ST.BUTTON_SPACING,
        orientation = style.orientation or (isBarMode and "vertical" or "horizontal"),
        buttonsPerRow = style.buttonsPerRow or 12,
    }
end

local function IsIconModePanel(group)
    if group.displayMode ~= nil and group.displayMode ~= "icons" then
        return false
    end
    if CooldownCompanion.IsStandaloneTexturePanelGroup
        and CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        return false
    end
    return true
end

local function StyleIconEntry(slot, buttonData, group)
    StyleMirroredIconFrame(slot, { buttonData = buttonData }, group)
end

-- Static mirror of TextMode.lua CreateTextFrame: same saved settings,
-- entry name in place of the live token-substituted format string.
local function StyleTextEntry(slot, buttonData, group)
    local style = group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end

    local bgColor = style.textBgColor or { 0, 0, 0, 0 }
    slot.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    local borderSize = style.textBorderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(style, "textBorderRenderMode")
    local borderColor = style.textBorderColor or { 0, 0, 0, 1 }
    for i = 1, 4 do
        slot.borderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end
    ApplyBorderEdgePositions(slot.borderTextures, slot, borderSize, borderRenderMode)

    local ts = slot.textString
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    ts:SetFont(font, fontSize, fontOutline)
    local baseColor = style.textFontColor or { 1, 1, 1, 1 }
    ts:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
    ts:SetJustifyH(style.textAlignment or "LEFT")
    ST.ApplyFontShadowForOutline(ts, fontOutline, style.textShadow == true)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(slot, borderSize, borderRenderMode)
    local inset = ((borderSize > 0
        or ST.IsEffectiveCrispBorderRenderMode(borderRenderMode, nil, borderSize)) and borderLayoutSize or 0) + 2
    ts:ClearAllPoints()
    ts:SetPoint("TOPLEFT", inset, -1)
    ts:SetPoint("BOTTOMRIGHT", -inset, 1)
    ts:SetText(buttonData.customName or buttonData.name or GetConfigEntryDisplayName(buttonData) or "")
end

-- Mirror of GroupFrame's ApplyTextGroupHeader, drawn on the content frame.
local function UpdateTextGroupHeader(preview, group, style, headerHeight)
    local header = preview.textHeader
    if headerHeight <= 0 then
        if header then header:Hide() end
        return
    end
    if not header then
        header = preview.content:CreateFontString(nil, "OVERLAY")
        header:SetJustifyV("TOP")
        preview.textHeader = header
    end
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textHeaderFontSize or style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    header:SetFont(font, fontSize, fontOutline)
    local hdrColor = style.textHeaderFontColor or { 1, 1, 1, 1 }
    header:SetTextColor(hdrColor[1], hdrColor[2], hdrColor[3], hdrColor[4] or 1)
    ST.ApplyFontShadowForOutline(header, fontOutline, style.textShadow == true)
    local align = style.textAlignment or "LEFT"
    header:SetJustifyH(align)
    header:SetText(group.name or "")
    header:ClearAllPoints()
    local growthOrigin = style.growthOrigin or "TOPLEFT"
    local vEdge = (growthOrigin == "BOTTOMLEFT" or growthOrigin == "BOTTOMRIGHT") and "BOTTOM" or "TOP"
    local anchor = align == "RIGHT" and (vEdge .. "RIGHT") or align == "CENTER" and vEdge or (vEdge .. "LEFT")
    local xOff = (align == "CENTER") and 0 or (align == "RIGHT") and -2 or 2
    local yOff = vEdge == "BOTTOM" and 1 or -1
    header:SetPoint(anchor, preview.content, anchor, xOff, yOff)
    header:SetWidth(math_max(1, (preview.content:GetWidth() or 0) - 4))
    header:Show()
end

local function GetHostFitScale(host, contentWidth, contentHeight)
    local hostWidth = host:GetWidth() or 0
    local hostHeight = host:GetHeight() or 0
    if hostWidth < 40 then hostWidth = 340 end
    if hostHeight < 40 then hostHeight = 200 end
    local maxWidth = math_max(80, hostWidth - (PANEL_PREVIEW_PADDING * 2))
    local maxHeight = math_max(80, hostHeight - (PANEL_PREVIEW_PADDING * 2))
    return math_min(1, maxWidth / math_max(1, contentWidth), maxHeight / math_max(1, contentHeight))
end

-- Fallback for panel types with no meaningful geometric mirror (trigger,
-- texture, and rotation-assistant panels): a flat strip of
-- clickable entry icons with the same selection, badges, tooltips, and
-- context-menu behavior as the mirrored slots.
local STRIP_ICON_SIZE = 36
local STRIP_SPACING = 4
local STRIP_PER_ROW = 8

local function BuildSelectionStrip(preview, host, panelId, group)
    local isRA = group.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT
    local entries = {}
    if isRA then
        local spellID = CooldownCompanion:GetRotationAssistantActionSpellID()
        entries[1] = {
            buttonData = {
                type = "spell",
                id = spellID,
                name = ST.ROTATION_ASSISTANT_NAME,
                manualIcon = CooldownCompanion:GetRotationAssistantFallbackIcon(spellID),
            },
            isRotationAssistant = true,
        }
    else
        for index, buttonData in ipairs(group.buttons or {}) do
            entries[#entries + 1] = { buttonData = buttonData, index = index }
        end
    end

    local count = #entries
    if count == 0 then
        SetPreviewMessage(preview, "This panel has no entries yet. Add spells or items in the Panels column.")
        FinalizePreviewState(preview)
        return
    end

    local w, h = STRIP_ICON_SIZE, STRIP_ICON_SIZE
    local cols = math_min(count, STRIP_PER_ROW)
    local rows = math_ceil(count / STRIP_PER_ROW)
    local contentWidth = (cols - 1) * (w + STRIP_SPACING) + w
    local contentHeight = (rows - 1) * (h + STRIP_SPACING) + h
    local scale = GetHostFitScale(host, contentWidth, contentHeight)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()

    local layoutDrag = CreatePreviewLayoutDrag(preview, panelId)
    layoutDrag.count = count
    layoutDrag.slotW, layoutDrag.slotH = w, h
    layoutDrag.scale = scale
    layoutDrag.anchor = "TOPLEFT"
    layoutDrag.cellXY = function(d)
        local row = math_floor((d - 1) / STRIP_PER_ROW)
        local col = (d - 1) % STRIP_PER_ROW
        return col * (w + STRIP_SPACING), -(row * (h + STRIP_SPACING))
    end
    preview.layoutDrag = layoutDrag
    local dragModel = (not isRA and count >= 2) and layoutDrag or nil

    for i, entryInfo in ipairs(entries) do
        local slot = AcquireSlot(preview, content, "iconSlots")
        slot:SetSize(w, h)
        local cx, cy = layoutDrag.cellXY(i)
        ApplyPreviewSlotGeometry(preview, slot, "TOPLEFT", cx, cy)

        local buttonData = entryInfo.buttonData
        StyleMirroredIconFrame(slot, { buttonData = buttonData }, group)

        if entryInfo.isRotationAssistant then
            slot.icon:SetDesaturated(false)
            if slot.problemBadge then slot.problemBadge:Hide() end
            if slot.problemBadgeBack then slot.problemBadgeBack:Hide() end
            -- Recycled slots may carry a drag handler from a grid render
            slot:SetScript("OnMouseDown", nil)
            if CS.selectedRotationAssistantEntry == true then
                slot.selectedHighlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
                ST.ApplyBorderTextures(slot.selectedHighlight.ringTextures, slot.selectedHighlight,
                    PANEL_PREVIEW_RING_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
                slot.selectedHighlight:Show()
            end
            slot:SetScript("OnMouseUp", function(self, mouseButton)
                if CS.dragState and CS.dragState.phase == "active" then return end
                if GetCursorInfo() then return end
                if mouseButton ~= "LeftButton" then return end
                if CS.selectedRotationAssistantEntry == true then
                    ST._SelectConfigButtonPanel(panelId, { clearPanelMulti = true })
                else
                    ST._SelectConfigRotationAssistantEntry(panelId, { containerId = CS.selectedContainer })
                end
                CooldownCompanion:RefreshConfigPanel()
            end)
            slot:SetScript("OnEnter", function(self)
                self.hoverHighlight:SetFrameLevel(self:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
                self.hoverHighlight:Show()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(ST.ROTATION_ASSISTANT_NAME, 1, 1, 1)
                GameTooltip:Show()
            end)
            slot:SetScript("OnLeave", function(self)
                self.hoverHighlight:Hide()
                GameTooltip:Hide()
            end)
        else
            local status = CollectEntryStatus(buttonData, group)
            slot.icon:SetDesaturated(not status.usable)
            if status.disabled then
                slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
            end
            slot._cdcBaseAlpha = status.disabled and PANEL_PREVIEW_DISABLED_ALPHA or 1
            ApplySlotBadges(slot, status, scale)
            ApplySelectionVisuals(slot, entryInfo.index)
            layoutDrag.slots[entryInfo.index] = slot
            WireEntryInteraction(slot, panelId, entryInfo.index, buttonData, status, dragModel)
        end
    end

    content:SetScale(scale)
    content:ClearAllPoints()
    content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)

    FinalizePreviewState(preview)
end

-- Static mirror of BarMode.lua CreateBarFrame: same saved settings, same
-- shared area/border helpers, full fill, no runtime state.
local function StyleBarEntry(slot, buttonData, group)
    local style = group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end

    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(slot, borderSize, borderRenderMode)
    local showIcon = style.showBarIcon ~= false
    local isVertical = style.barFillVertical or false
    local iconReverse = showIcon and (style.barIconReverse or false)
    local barHeight = style.barHeight or 20
    local iconSize = (style.barIconSizeOverride and style.barIconSize) or barHeight
    local iconOffset = showIcon and (style.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = barAreaLeft
    local bgColor = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
    local borderColor = style.borderColor or { 0, 0, 0, 1 }

    slot.bg:ClearAllPoints()
    if showIcon then
        SetBarAreaPoints(slot.bg, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        slot.bg:SetAllPoints()
    end
    slot.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    if showIcon then
        SetIconAreaPoints(slot.icon, slot, isVertical, iconReverse, iconSize, borderLayoutSize)
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.icon:SetTexture(GetLayoutPreviewIcon(buttonData))
        slot.icon:Show()
        SetIconAreaPoints(slot.iconBg, slot, isVertical, iconReverse, iconSize, 0)
        slot.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        slot.iconBg:Show()
        SetIconAreaPoints(slot.iconBounds, slot, isVertical, iconReverse, iconSize, 0)
        for i = 1, 4 do
            slot.iconBorderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        end
        ApplyBorderEdgePositions(slot.iconBorderTextures, slot.iconBounds, borderSize, borderRenderMode)
    else
        slot.icon:Hide()
        slot.iconBg:Hide()
        for i = 1, 4 do
            slot.iconBorderTextures[i]:Hide()
        end
    end

    if showIcon then
        SetBarAreaPoints(slot.barBounds, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        slot.barBounds:ClearAllPoints()
        slot.barBounds:SetAllPoints()
    end

    SetBarAreaPoints(slot.statusBar, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
    slot.statusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    slot.statusBar:SetMinMaxValues(0, 1)
    slot.statusBar:SetValue(1)
    slot.statusBar:SetReverseFill(style.barReverseFill or false)
    slot.statusBar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
    local barColor = style.barColor or DEFAULT_BAR_COLOR
    slot.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    slot.statusBar:Show()

    SetBarAreaPoints(slot.textFrame, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
    slot.textFrame:SetFrameLevel(slot.statusBar:GetFrameLevel() + 2)

    local nameText = slot.nameText
    CooldownCompanion.ApplyFontStyle(nameText, style, "barName", 10)
    local nameOffX = style.barNameTextOffsetX or 0
    local nameOffY = style.barNameTextOffsetY or 0
    local nameReverse = style.barNameTextReverse
    nameText:ClearAllPoints()
    if isVertical then
        if nameReverse then
            nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        nameText:SetJustifyH("CENTER")
    else
        if nameReverse then
            nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            nameText:SetJustifyH("RIGHT")
        else
            nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            nameText:SetJustifyH("LEFT")
        end
    end
    if style.showBarNameText ~= false or buttonData.customName then
        nameText:SetText(buttonData.customName or buttonData.name or GetConfigEntryDisplayName(buttonData) or "")
        nameText:Show()
    else
        nameText:Hide()
    end

    for i = 1, 4 do
        slot.borderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end
    ApplyBorderEdgePositions(slot.borderTextures, slot.barBounds, borderSize, borderRenderMode)
end

function ST._BuildButtonPanelPreview(host, panelId)
    -- Rebuilding pulls the slot frames out from under an in-flight drag
    if CS.dragState and CS.dragState.kind == "layout-slot" and CancelDrag then
        CancelDrag()
    end

    local preview = EnsurePreviewState(host)
    -- Fresh static layout: discard any tweens or ghost the canceled drag
    -- queued so they can't fight the rebuilt slot positions
    preview.tweens = preview.tweens or {}
    wipe(preview.tweens)
    ClearPreviewGhost(preview)
    preview.root:SetScript("OnUpdate", nil)
    if preview.gapFrame then
        preview.gapFrame:Hide()
    end
    if preview.textHeader then
        preview.textHeader:Hide()
    end
    ResetPreviewState(preview)
    HidePreviewMessage(preview)
    preview.content:Hide()

    local group = panelId and CooldownCompanion.db.profile.groups[panelId]
    if not group then
        SetPreviewMessage(preview, "Select a panel to preview it here.")
        FinalizePreviewState(preview)
        return
    end

    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    if not isBarMode and not isTextMode and not IsIconModePanel(group) then
        return BuildSelectionStrip(preview, host, panelId, group)
    end

    local buttons = group.buttons or {}
    local count = #buttons
    if count == 0 then
        SetPreviewMessage(preview, "This panel has no entries yet. Add spells or items in the Panels column.")
        FinalizePreviewState(preview)
        return
    end

    local geo = GetPanelGeometry(group, isBarMode, isTextMode)
    local w, h = geo.entryWidth, geo.entryHeight
    local spacing = geo.spacing
    local perRow = math_max(1, geo.buttonsPerRow)
    local style = group.style or {}
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)

    -- Text-mode group header claims a row of space above (or below, for
    -- bottom growth) the entries, exactly like the live layout.
    local headerHeight = 0
    if isTextMode and style.showTextGroupHeader == true then
        headerHeight = (style.textHeaderFontSize or style.textFontSize or 12) + 4
    end

    local cols, rows
    if geo.orientation == "horizontal" then
        cols = math_min(count, perRow)
        rows = math_ceil(count / perRow)
    else
        rows = math_min(count, perRow)
        cols = math_ceil(count / perRow)
    end
    local contentWidth = (cols - 1) * (w + spacing) + w
    local contentHeight = (rows - 1) * (h + spacing) + h + headerHeight

    -- Scale is needed while styling (badges counter-scale against it), so
    -- compute it up front from the grid extents.
    local scale = GetHostFitScale(host, contentWidth, contentHeight)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()
    UpdateTextGroupHeader(preview, group, style, headerHeight)

    local poolName = isBarMode and "barSlots" or (isTextMode and "textSlots" or "iconSlots")
    local styleFn = isBarMode and StyleBarEntry or (isTextMode and StyleTextEntry or StyleIconEntry)

    local layoutDrag = CreatePreviewLayoutDrag(preview, panelId)
    layoutDrag.count = count
    layoutDrag.slotW, layoutDrag.slotH = w, h
    layoutDrag.scale = scale
    layoutDrag.anchor = growthAnchor
    layoutDrag.cellXY = function(d)
        local row, col
        if geo.orientation == "horizontal" then
            row = math_floor((d - 1) / perRow)
            col = (d - 1) % perRow
        else
            col = math_floor((d - 1) / perRow)
            row = (d - 1) % perRow
        end
        return xMul * col * (w + spacing), yMul * (row * (h + spacing) + headerHeight)
    end
    preview.layoutDrag = layoutDrag
    local dragModel = (count >= 2) and layoutDrag or nil

    for index, buttonData in ipairs(buttons) do
        local slot = AcquireSlot(preview, content, poolName)
        slot:SetSize(w, h)

        local cx, cy = layoutDrag.cellXY(index)
        ApplyPreviewSlotGeometry(preview, slot, growthAnchor, cx, cy)

        styleFn(slot, buttonData, group)
        local status = CollectEntryStatus(buttonData, group)
        if slot.icon then
            slot.icon:SetDesaturated(not status.usable)
        end
        if status.disabled then
            slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
        end
        slot._cdcBaseAlpha = status.disabled and PANEL_PREVIEW_DISABLED_ALPHA or 1
        ApplySlotBadges(slot, status, scale)
        ApplySelectionVisuals(slot, index)
        layoutDrag.slots[index] = slot
        WireEntryInteraction(slot, panelId, index, buttonData, status, dragModel)
    end

    content:SetScale(scale)
    content:ClearAllPoints()
    content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)

    FinalizePreviewState(preview)
end

ST._CollectEntryStatus = CollectEntryStatus
ST._EntryStatusBadges = ENTRY_STATUS_BADGES

function ST._ReleaseButtonPanelPreview(host)
    local preview = host and host._cdcPanelPreview
    if preview then
        preview.root:Hide()
    end
end
