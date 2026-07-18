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

local PANEL_PREVIEW_PADDING = 12
local PANEL_PREVIEW_DISABLED_ALPHA = 0.45
local PANEL_PREVIEW_RING_COLOR = { 0.38, 0.60, 0.92, 1 }
-- Above the bar slots' text frame (statusBar level + 2)
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = 5
-- Badges counter-scale against the preview's scale-to-fit so they stay
-- readable, clamped so they never dwarf a heavily scaled-down slot.
local PANEL_PREVIEW_BADGE_SCREEN_SIZE = 14
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
        pools = { iconSlots = {}, barSlots = {} },
        used = { iconSlots = 0, barSlots = 0 },
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

local SLOT_FACTORIES = {
    iconSlots = CreateIconSlot,
    barSlots = CreateBarSlot,
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
local function EnsureDropIndicator(preview)
    local ind = preview.dropIndicator
    if not ind then
        -- Own high-level holder so the line draws above the slot frames
        -- even when zero spacing puts it flush against a slot edge.
        local holder = CreateFrame("Frame", nil, preview.root)
        holder:SetAllPoints(preview.root)
        holder:SetFrameLevel(preview.root:GetFrameLevel() + 40)
        ind = holder:CreateTexture(nil, "OVERLAY")
        ind:SetColorTexture(PANEL_PREVIEW_RING_COLOR[1], PANEL_PREVIEW_RING_COLOR[2],
            PANEL_PREVIEW_RING_COLOR[3], 0.9)
        preview.dropIndicator = ind
    end
    return ind
end

local function CreatePreviewLayoutDrag(preview, panelId)
    local layoutDrag = {
        panelPreview = true,
        slots = {},
        count = 0,
        slotW = 1,
        slotH = 1,
        spacing = 0,
        scale = 1,
        flowX = 1,
        flowY = 0,
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

        local centers = {}
        for i = 1, count do
            local slot = layoutDrag.slots[i]
            local sl, sb, sw, sh = slot and slot:GetScaledRect()
            if not sl then return nil end
            centers[i] = { x = sl + sw / 2, y = sb + sh / 2 }
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
        if state.widget and state.widget.hoverHighlight then
            state.widget.hoverHighlight:Hide()
        end
    end

    layoutDrag.onUpdate = function(state, cursorX, cursorY, dropTarget)
        local ind = EnsureDropIndicator(preview)
        local insertIndex = dropTarget and dropTarget.insertIndex
        local sourceIndex = state.slotData and state.slotData.index
        -- No target, or a no-op drop back onto the source position
        if not insertIndex
            or (sourceIndex and (insertIndex == sourceIndex or insertIndex == sourceIndex + 1)) then
            ind:Hide()
            return
        end

        local count = layoutDrag.count
        local scale = layoutDrag.scale
        local gap = (layoutDrag.spacing * scale) / 2
        local horizontal = layoutDrag.flowY == 0
        local target, edge, offX, offY
        if insertIndex <= count then
            -- Leading edge of the slot the entry would land in front of
            target = layoutDrag.slots[insertIndex]
            if horizontal then
                edge = (layoutDrag.flowX >= 0) and "LEFT" or "RIGHT"
                offX, offY = (edge == "LEFT") and -gap or gap, 0
            else
                edge = (layoutDrag.flowY < 0) and "TOP" or "BOTTOM"
                offX, offY = 0, (edge == "TOP") and gap or -gap
            end
        else
            -- Trailing edge of the last slot
            target = layoutDrag.slots[count]
            if horizontal then
                edge = (layoutDrag.flowX >= 0) and "RIGHT" or "LEFT"
                offX, offY = (edge == "RIGHT") and gap or -gap, 0
            else
                edge = (layoutDrag.flowY < 0) and "BOTTOM" or "TOP"
                offX, offY = 0, (edge == "BOTTOM") and -gap or gap
            end
        end
        if not target then
            ind:Hide()
            return
        end
        -- The indicator lives on the unscaled root, so sizes and offsets
        -- multiply the content scale to line up with the scaled slots.
        if horizontal then
            ind:SetSize(2, layoutDrag.slotH * scale + 4)
        else
            ind:SetSize(layoutDrag.slotW * scale + 4, 2)
        end
        ind:ClearAllPoints()
        ind:SetPoint("CENTER", target, edge, offX, offY)
        ind:Show()
    end

    layoutDrag.onCancel = function()
        if preview.dropIndicator then
            preview.dropIndicator:Hide()
        end
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
        CS.dragState = {
            kind = "layout-slot",
            phase = "pending",
            widget = self,
            scrollWidget = UIParent,
            startX = cursorX,
            startY = cursorY,
            layoutDrag = layoutDrag,
            slotData = { index = index },
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
                if state.kind ~= "layout-slot" or state.phase ~= "pending" or state.widget ~= self then
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
local function GetPanelGeometry(group, isBarMode)
    local style = group.style or {}
    local w, h
    if isBarMode then
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

local function GetHostFitScale(host, contentWidth, contentHeight)
    local hostWidth = host:GetWidth() or 0
    local hostHeight = host:GetHeight() or 0
    if hostWidth < 40 then hostWidth = 340 end
    if hostHeight < 40 then hostHeight = 200 end
    local maxWidth = math_max(80, hostWidth - (PANEL_PREVIEW_PADDING * 2))
    local maxHeight = math_max(80, hostHeight - (PANEL_PREVIEW_PADDING * 2))
    return math_min(1, maxWidth / math_max(1, contentWidth), maxHeight / math_max(1, contentHeight))
end

-- Fallback for panel types with no meaningful geometric mirror (text,
-- trigger, texture, and rotation-assistant panels): a flat strip of
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
    layoutDrag.spacing = STRIP_SPACING
    layoutDrag.scale = scale
    layoutDrag.flowX, layoutDrag.flowY = 1, 0
    preview.layoutDrag = layoutDrag
    local dragModel = (not isRA and count >= 2) and layoutDrag or nil

    for i, entryInfo in ipairs(entries) do
        local slot = AcquireSlot(preview, content, "iconSlots")
        slot:SetSize(w, h)
        local row = math_floor((i - 1) / STRIP_PER_ROW)
        local col = (i - 1) % STRIP_PER_ROW
        slot:ClearAllPoints()
        slot:SetPoint("TOPLEFT", content, "TOPLEFT",
            col * (w + STRIP_SPACING), -(row * (h + STRIP_SPACING)))

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
    if not isBarMode and not IsIconModePanel(group) then
        return BuildSelectionStrip(preview, host, panelId, group)
    end

    local buttons = group.buttons or {}
    local count = #buttons
    if count == 0 then
        SetPreviewMessage(preview, "This panel has no entries yet. Add spells or items in the Panels column.")
        FinalizePreviewState(preview)
        return
    end

    local geo = GetPanelGeometry(group, isBarMode)
    local w, h = geo.entryWidth, geo.entryHeight
    local spacing = geo.spacing
    local perRow = math_max(1, geo.buttonsPerRow)
    local xMul, yMul, growthAnchor = GetGrowthMultipliers((group.style or {}).growthOrigin)

    local cols, rows
    if geo.orientation == "horizontal" then
        cols = math_min(count, perRow)
        rows = math_ceil(count / perRow)
    else
        rows = math_min(count, perRow)
        cols = math_ceil(count / perRow)
    end
    local contentWidth = (cols - 1) * (w + spacing) + w
    local contentHeight = (rows - 1) * (h + spacing) + h

    -- Scale is needed while styling (badges counter-scale against it), so
    -- compute it up front from the grid extents.
    local scale = GetHostFitScale(host, contentWidth, contentHeight)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()

    local poolName = isBarMode and "barSlots" or "iconSlots"
    local styleFn = isBarMode and StyleBarEntry or StyleIconEntry

    local layoutDrag = CreatePreviewLayoutDrag(preview, panelId)
    layoutDrag.count = count
    layoutDrag.slotW, layoutDrag.slotH = w, h
    layoutDrag.spacing = spacing
    layoutDrag.scale = scale
    if geo.orientation == "horizontal" then
        layoutDrag.flowX, layoutDrag.flowY = xMul, 0
    else
        layoutDrag.flowX, layoutDrag.flowY = 0, yMul
    end
    preview.layoutDrag = layoutDrag
    local dragModel = (count >= 2) and layoutDrag or nil

    for index, buttonData in ipairs(buttons) do
        local slot = AcquireSlot(preview, content, poolName)
        slot:SetSize(w, h)

        local row, col
        if geo.orientation == "horizontal" then
            row = math_floor((index - 1) / perRow)
            col = (index - 1) % perRow
        else
            col = math_floor((index - 1) / perRow)
            row = (index - 1) % perRow
        end
        slot:ClearAllPoints()
        slot:SetPoint(growthAnchor, content, growthAnchor,
            xMul * col * (w + spacing), yMul * row * (h + spacing))

        styleFn(slot, buttonData, group)
        local status = CollectEntryStatus(buttonData, group)
        slot.icon:SetDesaturated(not status.usable)
        if status.disabled then
            slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
        end
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
