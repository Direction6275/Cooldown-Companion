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

local PANEL_PREVIEW_PADDING = 12
local PANEL_PREVIEW_DISABLED_ALPHA = 0.45
local PANEL_PREVIEW_RING_COLOR = { 0.38, 0.60, 0.92, 1 }
-- Above the bar slots' text frame (statusBar level + 2)
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = 5
-- Badges counter-scale against the preview's scale-to-fit so they stay
-- readable, clamped so they never dwarf a heavily scaled-down slot.
local PANEL_PREVIEW_BADGE_SCREEN_SIZE = 12
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

-- Badge cluster in the slot's top-right corner: same atlases and meaning
-- as the column 2 entry rows, stacked right-to-left in the same order.
local function ApplySlotBadges(slot, status, scale)
    slot.badges = slot.badges or {}
    local size = math_min(24, math_max(12, PANEL_PREVIEW_BADGE_SCREEN_SIZE / math_max(scale, 0.01)))
    local shown = 0
    local function AddBadge(atlas)
        shown = shown + 1
        local tex = slot.badges[shown]
        if not tex then
            tex = slot:CreateTexture(nil, "OVERLAY", nil, 7)
            slot.badges[shown] = tex
        end
        tex:SetAtlas(atlas, false)
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        tex:SetPoint("TOPRIGHT", slot, "TOPRIGHT", -((shown - 1) * (size + 1)), 0)
        tex:Show()
    end
    if status.disabled then AddBadge("GM-icon-visibleDis-pressed") end
    if status.warn then AddBadge("Ping_Marker_Icon_Warning") end
    if status.override then AddBadge("Crosshair_VehichleCursor_32") end
    if status.fallback then AddBadge("banker") end
    if status.sound then AddBadge("common-icon-sound") end
    if status.talent then AddBadge("UI-HUD-MicroMenu-SpecTalents-Mouseover") end
    for i = shown + 1, #slot.badges do
        slot.badges[i]:Hide()
    end
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
    GameTooltip:Show()
end

local function WireEntryInteraction(slot, panelId, index, buttonData, status)
    slot:SetScript("OnMouseUp", function(self, mouseButton)
        if CS.dragState and CS.dragState.phase == "active" then return end
        if GetCursorInfo() then return end
        if mouseButton == "LeftButton" then
            SelectConfigButton(panelId, index, { multi = IsControlKeyDown() })
            CooldownCompanion:RefreshConfigPanel()
        elseif mouseButton == "RightButton" or mouseButton == "MiddleButton" then
            if ShowEntryContextMenu then
                ShowEntryContextMenu(panelId, index, buttonData)
            end
        end
    end)
    slot:SetScript("OnEnter", function(self)
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
        SetPreviewMessage(preview, "Preview for this panel type is coming in a later update.")
        FinalizePreviewState(preview)
        return
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
    local hostWidth = host:GetWidth() or 0
    local hostHeight = host:GetHeight() or 0
    if hostWidth < 40 then hostWidth = 340 end
    if hostHeight < 40 then hostHeight = 200 end
    local maxWidth = math_max(80, hostWidth - (PANEL_PREVIEW_PADDING * 2))
    local maxHeight = math_max(80, hostHeight - (PANEL_PREVIEW_PADDING * 2))
    local scale = math_min(1, maxWidth / math_max(1, contentWidth), maxHeight / math_max(1, contentHeight))

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()

    local poolName = isBarMode and "barSlots" or "iconSlots"
    local styleFn = isBarMode and StyleBarEntry or StyleIconEntry

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
        WireEntryInteraction(slot, panelId, index, buttonData, status)
    end

    content:SetScale(scale)
    content:ClearAllPoints()
    content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)

    FinalizePreviewState(preview)
end

function ST._ReleaseButtonPanelPreview(host)
    local preview = host and host._cdcPanelPreview
    if preview then
        preview.root:Hide()
    end
end
