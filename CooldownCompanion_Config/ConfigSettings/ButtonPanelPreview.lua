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
local GetConfigEntryDisplayName = ST._GetConfigEntryDisplayName
local SelectConfigButton = ST._SelectConfigButton

local PANEL_PREVIEW_PADDING = 12
local PANEL_PREVIEW_DISABLED_ALPHA = 0.45
local PANEL_PREVIEW_RING_COLOR = { 0.38, 0.60, 0.92, 1 }

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
        pools = { slots = {} },
        used = { slots = 0 },
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
    preview.used.slots = 0
    preview.root:Show()
end

local function FinalizePreviewState(preview)
    local pool = preview.pools.slots
    for index = (preview.used.slots or 0) + 1, #pool do
        local frame = pool[index]
        frame:Hide()
        frame:ClearAllPoints()
        frame:SetScript("OnMouseUp", nil)
        frame:SetScript("OnEnter", nil)
        frame:SetScript("OnLeave", nil)
    end
end

local function CreateEntrySlot(parent)
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

    return frame
end

local function AcquireSlot(preview, parent)
    local pool = preview.pools.slots
    local index = (preview.used.slots or 0) + 1
    preview.used.slots = index
    local frame = pool[index]
    if not frame then
        frame = CreateEntrySlot(parent)
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
    slot.selectedHighlight:SetFrameLevel(slot:GetFrameLevel() + 2)
    ST.ApplyBorderTextures(slot.selectedHighlight.ringTextures, slot.selectedHighlight,
        PANEL_PREVIEW_RING_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
    slot.selectedHighlight:Show()
end

local function WireEntryInteraction(slot, panelId, index, buttonData)
    slot:SetScript("OnMouseUp", function(self, mouseButton)
        if CS.dragState and CS.dragState.phase == "active" then return end
        if GetCursorInfo() then return end
        if mouseButton == "LeftButton" then
            SelectConfigButton(panelId, index, { multi = IsControlKeyDown() })
            CooldownCompanion:RefreshConfigPanel()
        end
    end)
    slot:SetScript("OnEnter", function(self)
        self.hoverHighlight:SetFrameLevel(self:GetFrameLevel() + 2)
        self.hoverHighlight:Show()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(GetConfigEntryDisplayName(buttonData) or "Entry", 1, 1, 1)
        if buttonData.enabled == false then
            GameTooltip:AddLine("Disabled", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)
    slot:SetScript("OnLeave", function(self)
        self.hoverHighlight:Hide()
        GameTooltip:Hide()
    end)
end

-- Icon-mode geometry mirrored from GroupFrame.lua (GetButtonDimensions +
-- ApplyActiveButtonLayout row/col math).
local function GetIconModeGeometry(group)
    local style = group.style or {}
    local w, h
    if style.maintainAspectRatio then
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
        orientation = style.orientation or "horizontal",
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

    if not IsIconModePanel(group) then
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

    local geo = GetIconModeGeometry(group)
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

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()

    for index, buttonData in ipairs(buttons) do
        local slot = AcquireSlot(preview, content)
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

        StyleMirroredIconFrame(slot, { buttonData = buttonData }, group)
        if buttonData.enabled == false then
            slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
        end
        ApplySelectionVisuals(slot, index)
        WireEntryInteraction(slot, panelId, index, buttonData)
    end

    local hostWidth = host:GetWidth() or 0
    local hostHeight = host:GetHeight() or 0
    if hostWidth < 40 then hostWidth = 340 end
    if hostHeight < 40 then hostHeight = 200 end
    local maxWidth = math_max(80, hostWidth - (PANEL_PREVIEW_PADDING * 2))
    local maxHeight = math_max(80, hostHeight - (PANEL_PREVIEW_PADDING * 2))
    local scale = math_min(1, maxWidth / math_max(1, contentWidth), maxHeight / math_max(1, contentHeight))

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
