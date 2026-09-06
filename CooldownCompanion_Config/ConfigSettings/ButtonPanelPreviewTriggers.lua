--[[
    CooldownCompanion - ButtonPanelPreviewTriggers
    Selection strips and texture/icon/text trigger-display mirrors.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local StyleMirroredIconFrame = ST._StyleMirroredIconFrame
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local IsStoredPreviewFlagActive = ST._IsStoredPreviewFlagActive
local AuraTextures = ST._AT
local ApplyTextureIndicatorEffects = AuraTextures and AuraTextures.ApplyTextureIndicatorEffects
local SetTextureIndicatorBaseVisuals = AuraTextures and AuraTextures.SetTextureIndicatorBaseVisuals
local StopAllTextureIndicatorEffects = AuraTextures and AuraTextures.StopAllTextureIndicatorEffects

local PP = ST._ButtonPanelPreview

-- ButtonPanelPreviewEffects.lua
local StopConditionalTicker = PP.StopConditionalTicker
local ClearSlotEffectPreviews = PP.ClearSlotEffectPreviews
local ApplySlotEffectPreviews = PP.ApplySlotEffectPreviews
local EnsureConditionalTicker = PP.EnsureConditionalTicker

-- ButtonPanelPreviewShared.lua
local SetPreviewMessage = PP.SetPreviewMessage
local FinalizePreviewState = PP.FinalizePreviewState
local STRIP_ICON_SIZE = PP.STRIP_ICON_SIZE
local STRIP_PER_ROW = PP.STRIP_PER_ROW
local STRIP_SPACING = PP.STRIP_SPACING
local GetHostFitScale = PP.GetHostFitScale
local AcquireSlot = PP.AcquireSlot
local ApplyPreviewSlotGeometry = PP.ApplyPreviewSlotGeometry
local DisableReadOnlySlotInteraction = PP.DisableReadOnlySlotInteraction
local IsGlowPreviewActiveOnEntry = PP.IsGlowPreviewActiveOnEntry
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = PP.PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET
local PANEL_PREVIEW_RING_COLOR = PP.PANEL_PREVIEW_RING_COLOR
local CollectEntryStatus = ST._CollectEntryStatus
local PANEL_PREVIEW_DISABLED_ALPHA = PP.PANEL_PREVIEW_DISABLED_ALPHA
local ApplySlotBadges = PP.ApplySlotBadges
local ApplySelectionVisuals = PP.ApplySelectionVisuals
local CopyMode = PP.CopyMode
local PANEL_PREVIEW_PADDING = PP.PANEL_PREVIEW_PADDING
local EMPTY_ENTRY_GUIDANCE_BAND = PP.EMPTY_ENTRY_GUIDANCE_BAND
local GetHostFitBox = PP.GetHostFitBox
local GetTriggerDisplayNaturalSize = PP.GetTriggerDisplayNaturalSize
local GetStripNaturalSize = PP.GetStripNaturalSize
local TRIGGER_PREVIEW_STRIP_MAX_SHARE = PP.TRIGGER_PREVIEW_STRIP_MAX_SHARE

-- ButtonPanelPreviewInteraction.lua
local CreatePreviewLayoutDrag = PP.CreatePreviewLayoutDrag
local WireEntryInteraction = PP.WireEntryInteraction

-- ButtonPanelPreviewIcons.lua
local ResetSlotConditionalVisuals = PP.ResetSlotConditionalVisuals
local ApplySlotConditionalPreview = PP.ApplySlotConditionalPreview

-- layout (optional) is the trigger preview's band placement: scaleOverride
-- replaces the fit-to-host scale (the display visual above owns most of the
-- height) and anchorPoint = "BOTTOM" parks the strip along the bottom edge.
local function BuildSelectionStrip(preview, host, panelId, group, readOnly, layout)
    StopConditionalTicker(preview)
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
        if readOnly then
            SetPreviewMessage(preview, "Empty Panel")
        else
            SetPreviewMessage(preview,
                "Search for a spell or item in the field below, enter an ID, or drag one into this preview.",
                "Add your first entry")
        end
        FinalizePreviewState(preview)
        return
    end

    local w, h = STRIP_ICON_SIZE, STRIP_ICON_SIZE
    local cols = math_min(count, STRIP_PER_ROW)
    local rows = math_ceil(count / STRIP_PER_ROW)
    local contentWidth = (cols - 1) * (w + STRIP_SPACING) + w
    local contentHeight = (rows - 1) * (h + STRIP_SPACING) + h
    local scale = layout and layout.scaleOverride
        or GetHostFitScale(host, contentWidth, contentHeight, readOnly)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()

    local layoutDrag = readOnly and { slots = {} } or CreatePreviewLayoutDrag(preview, panelId)
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
    local dragModel = (not readOnly and not isRA and count >= 2) and layoutDrag or nil

    for i, entryInfo in ipairs(entries) do
        local slot = AcquireSlot(preview, content, "iconSlots")
        slot:SetSize(w, h)
        local cx, cy = layoutDrag.cellXY(i)
        ApplyPreviewSlotGeometry(preview, slot, "TOPLEFT", cx, cy)

        local buttonData = entryInfo.buttonData
        StyleMirroredIconFrame(slot, { buttonData = buttonData }, group)
        -- Selection strips are pickers, not mirrors: no conditional or
        -- effect previews here, and recycled grid slots keep neither.
        ResetSlotConditionalVisuals(slot)
        slot.icon:SetVertexColor(1, 1, 1, 1)
        ClearSlotEffectPreviews(slot)
        if slot.keybindText then slot.keybindText:Hide() end

        if readOnly then
            slot.icon:SetDesaturated(false)
            DisableReadOnlySlotInteraction(slot)
        elseif entryInfo.isRotationAssistant then
            slot:EnableMouse(true)
            slot.icon:SetDesaturated(false)
            slot._cdcPreviewButtonData = buttonData
            ApplySlotEffectPreviews(slot, buttonData, group, panelId, 1, false)
            ApplySlotConditionalPreview(slot, buttonData, group, panelId, 1)
            if slot.problemBadge then slot.problemBadge:Hide() end
            if slot.problemBadgeBack then slot.problemBadgeBack:Hide() end
            if slot.overrideBadge then slot.overrideBadge:Hide() end
            if slot.overrideBadgeBack then slot.overrideBadgeBack:Hide() end
            -- The assistant pseudo-entry is never a copy target, and the
            -- recycled slot may carry a ring from a grid render.
            if slot.copyTargetHighlight then slot.copyTargetHighlight:Hide() end
            -- Recycled slots may carry a drag handler from a grid render
            slot:SetScript("OnMouseDown", nil)
            if CS.selectedRotationAssistantEntry == true
                and not IsGlowPreviewActiveOnEntry(panelId, 1) then
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
                    -- This click means "select the panel"; the shared selector
                    -- clears the virtual entry and preserves the Visibility
                    -- viewport while ownership changes.
                    ST._SelectConfigButtonPanel(panelId, { clearPanelMulti = true })
                else
                    ST._SelectConfigRotationAssistantEntry(panelId, { containerId = CS.selectedContainer })
                end
                CooldownCompanion:RefreshConfigSelection()
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
            layoutDrag.slots[1] = slot
        else
            local status = CollectEntryStatus(buttonData, group)
            slot.icon:SetDesaturated(not status.usable)
            if status.disabled then
                slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
            end
            slot._cdcBaseAlpha = status.disabled and PANEL_PREVIEW_DISABLED_ALPHA or 1
            ApplySlotBadges(slot, status, scale)
            ApplySelectionVisuals(slot, entryInfo.index)
            CopyMode.ApplyTargetVisuals(slot, panelId, buttonData)
            layoutDrag.slots[entryInfo.index] = slot
            WireEntryInteraction(slot, panelId, entryInfo.index, buttonData, status, dragModel)
        end
    end

    local anyAnimated = false
    for _, slot in pairs(layoutDrag.slots) do
        if slot and slot._cdcCondAnim then
            anyAnimated = true
            break
        end
    end
    if not readOnly and anyAnimated then
        EnsureConditionalTicker(preview)
    end

    content:SetScale(scale)
    content:ClearAllPoints()
    if layout and layout.anchorPoint == "BOTTOM" then
        -- Offset in content-local units so the strip clears the fit-box
        -- padding by exactly PANEL_PREVIEW_PADDING on screen at any scale.
        content:SetPoint("BOTTOM", preview.root, "BOTTOM", 0,
            PANEL_PREVIEW_PADDING / math_max(scale, 0.01))
    else
        content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)
    end

    FinalizePreviewState(preview)
end

-- Standalone-display Live Preview: draws the panel's actual chosen visual fit
-- to the host, instead of (texture panels) or above (trigger panels) the
-- entry-icon selection strip. For these panels the chosen texture/icon/text IS
-- the visual, so a spell icon alone would show something that never renders
-- in-game. Reuses GroupTabs' fit-to-box renderer (ST._UpdateTexturePanelPreview)
-- for textures; icon and text visuals are drawn by the render helpers below.
local TEXTURE_INDICATOR_MIRROR_PREVIEWS = {
    { key = "proc", flag = "_textureProcPreview" },
    { key = "aura", flag = "_textureAuraPreview" },
    { key = "ready", flag = "_textureReadyPreview" },
    { key = "unusable", flag = "_textureUnusablePreview" },
}

local function StopTextureMirrorEffects(mirror)
    local host = mirror and mirror.effectHost
    if not host then
        return
    end

    if StopAllTextureIndicatorEffects then
        StopAllTextureIndicatorEffects(host)
    else
        host:SetScript("OnUpdate", nil)
        if host.visualRoot then
            host.visualRoot:SetAlpha(1)
            host.visualRoot:SetScale(1)
            host.visualRoot:ClearAllPoints()
            host.visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
        end
    end

    host._activeDisplayType = nil
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._indicatorBaseVisualsReady = nil
end

local function GetStoredTextureIndicatorPreview(panelId)
    if not (panelId and IsStoredPreviewFlagActive) then
        return nil, nil
    end

    for _, preview in ipairs(TEXTURE_INDICATOR_MIRROR_PREVIEWS) do
        if IsStoredPreviewFlagActive(panelId, nil, preview.flag) then
            return preview.key, preview.flag
        end
    end
    return nil, nil
end

local function EnsureTextureMirror(preview)
    local mirror = preview.textureMirror
    if mirror then
        return mirror
    end

    local root = CreateFrame("Frame", nil, preview.root)
    root:SetAllPoints(preview.root)
    root:SetClipsChildren(false)

    -- Effects belong to this config-owned frame tree. The runtime Texture
    -- host is never borrowed, shown, or animated by the pinned Live Preview.
    local effectHost = CreateFrame("Frame", nil, root)
    effectHost:SetAllPoints(root)
    effectHost:SetClipsChildren(false)
    local visualRoot = CreateFrame("Frame", nil, effectHost)
    visualRoot:SetPoint("CENTER", effectHost, "CENTER", 0, 0)
    visualRoot:SetSize(1, 1)
    effectHost.visualRoot = visualRoot

    mirror = {
        root = root,
        effectHost = effectHost,
        anchor = visualRoot,
        clickMode = "texture",
        primary = visualRoot:CreateTexture(nil, "ARTWORK"),
        secondary = visualRoot:CreateTexture(nil, "ARTWORK"),
        placeholder = root:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge"),
    }
    effectHost.primaryTexture = mirror.primary
    effectHost.secondaryTexture = mirror.secondary
    mirror.placeholder:SetPoint("CENTER")
    mirror.placeholder:SetText("No texture selected")

    -- Click the rendered visual to open its picker (inline texture browser or
    -- the trigger icon picker, per the build's clickMode). root is a raw,
    -- module-owned frame, so attaching scripts here is safe (not an AceGUI
    -- underlying frame). Mouse is enabled per build; the browse guard skips
    -- while the inline browser is already open for this panel.
    local hoverFrame = CreateFrame("Frame", nil, root)
    hoverFrame:SetAllPoints(root)
    hoverFrame:SetFrameLevel(effectHost:GetFrameLevel() + 5)
    local hoverCue = hoverFrame:CreateTexture(nil, "OVERLAY")
    hoverCue:SetAllPoints()
    hoverCue:SetColorTexture(1, 1, 1, 0.06)
    hoverCue:Hide()
    mirror.hoverCue = hoverCue

    local function IsBrowsingThisPanel()
        return CS.inlineTextureBrowserOpen ~= nil
            and CS.inlineTextureBrowserOpen == CS.selectedGroup
    end
    -- Named so the in-place clear below can re-present it: clearing rebuilds
    -- the config under a cursor that never leaves the frame, so OnEnter will
    -- not fire again on its own and the hover would strand a cue with no
    -- tooltip and a stale "Right-click to clear" line.
    local function ShowMirrorHover(self)
        if not mirror.clickMode then return end
        if mirror.clickMode == "texture" and IsBrowsingThisPanel() then return end
        hoverCue:Show()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if mirror.clickMode == "icon" then
            GameTooltip:AddLine("Click to choose an icon")
            if mirror.hasIcon then
                GameTooltip:AddLine("Right-click to clear", 0.7, 0.7, 0.7)
            end
        else
            GameTooltip:AddLine("Click to browse textures")
        end
        GameTooltip:Show()
    end
    root:SetScript("OnEnter", ShowMirrorHover)
    root:SetScript("OnLeave", function()
        hoverCue:Hide()
        GameTooltip:Hide()
    end)
    root:SetScript("OnMouseUp", function(self, mouseButton)
        if mirror.clickMode == "icon" then
            local group = CS.selectedGroup
                and CooldownCompanion.db.profile.groups[CS.selectedGroup]
            if not group then return end
            if mouseButton == "RightButton" then
                local settings = CooldownCompanion:GetTriggerPanelIconSettings(group)
                if settings and settings.manualIcon ~= nil then
                    settings.manualIcon = nil
                    GameTooltip:Hide()
                    CooldownCompanion:RefreshAllAuraTextureVisuals()
                    CooldownCompanion:RefreshConfigPanel()
                    if self:IsMouseOver() then
                        ShowMirrorHover(self)
                    else
                        hoverCue:Hide()
                    end
                end
                return
            end
            if mouseButton ~= "LeftButton" then return end
            if ST._OpenTriggerPanelIconPicker then
                ST._OpenTriggerPanelIconPicker(CS.selectedGroup)
            end
            return
        end
        if mirror.clickMode ~= "texture" then return end
        if IsBrowsingThisPanel() then return end
        if ST._OpenStandaloneTexturePicker and CS.selectedGroup then
            ST._OpenStandaloneTexturePicker(CS.selectedGroup)
        end
    end)

    preview.textureMirror = mirror
    return mirror
end

-- Hosts are shared across selections, and specialized previews can reserve a
-- bottom band for their strip or empty-entry guidance, so the mirror's extent
-- must be re-anchored every build.
local function ApplyMirrorBand(mirror, previewRoot, bottomReserve)
    local root = mirror.root
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", previewRoot, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", previewRoot, "BOTTOMRIGHT", 0, bottomReserve or 0)
end

local function ApplyTextureMirrorEffectPreview(mirror, panelId, group, settings, boxWidth, boxHeight)
    local indicatorKey, previewFlag = GetStoredTextureIndicatorPreview(panelId)
    if not (indicatorKey and previewFlag and type(settings) == "table"
        and ApplyTextureIndicatorEffects and SetTextureIndicatorBaseVisuals) then
        return
    end
    if not (mirror.primary:IsShown() or mirror.secondary:IsShown()) then
        return
    end

    local geometry = CooldownCompanion:GetTexturePanelRenderGeometry(settings)
    if not geometry then
        return
    end
    local fit = math_min(
        (tonumber(boxWidth) or geometry.boundsWidth) / math_max(geometry.boundsWidth, 1),
        (tonumber(boxHeight) or geometry.boundsHeight) / math_max(geometry.boundsHeight, 1),
        1
    )

    local host = mirror.effectHost
    local visualRoot = host.visualRoot
    visualRoot:ClearAllPoints()
    visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
    visualRoot:SetSize(math_max(1, tonumber(boxWidth) or geometry.boundsWidth),
        math_max(1, tonumber(boxHeight) or geometry.boundsHeight))

    host._activeDisplayType = "texture"
    host._activeTextureSettings = settings
    host._activeTextureGeometry = {
        pieces = geometry.pieces,
        rotationRadians = geometry.rotationRadians,
        boundsWidth = geometry.boundsWidth * fit,
        boundsHeight = geometry.boundsHeight * fit,
    }
    host._indicatorBaseVisualsReady = nil
    SetTextureIndicatorBaseVisuals(host)

    local previewButton = mirror.effectPreviewButton or {}
    mirror.effectPreviewButton = previewButton
    for _, preview in ipairs(TEXTURE_INDICATOR_MIRROR_PREVIEWS) do
        previewButton[preview.flag] = nil
    end
    previewButton.buttonData = group and group.buttons and group.buttons[1] or nil
    previewButton[previewFlag] = true
    ApplyTextureIndicatorEffects(host, previewButton, group, indicatorKey)
end

local function GetActiveTextureMirror(groupId)
    if not (ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()) then
        return nil
    end
    if groupId and groupId ~= CS.selectedGroup then
        return nil
    end

    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.buttonsPreviewHost
    if not (host and host:IsShown() and col3._cdcActiveWideHost == host) then
        return nil
    end

    local preview = host._cdcPanelPreview
    local mirror = preview and preview.textureMirror
    if not (mirror and mirror.root:IsShown()) then
        return nil
    end
    return mirror
end

-- Clear paths can run without rebuilding the pinned preview (for example an
-- entry-tab switch). Stop the config-owned effect immediately so a cleared
-- stored flag can never leave an animation running on the mirror.
function ST._StopTextureIndicatorPreviewMirror(groupId)
    local mirror = GetActiveTextureMirror(groupId)
    if not mirror then
        return false
    end
    StopTextureMirrorEffects(mirror)
    return true
end

-- Color and speed controls update continuously. Reapply the saved effect to
-- the existing config-owned host so its phase continues smoothly instead of
-- rebuilding the mirror and restarting the animation on every drag tick.
function ST._RefreshTextureIndicatorMirrorEffect(groupId)
    local mirror = GetActiveTextureMirror(groupId)
    if not (mirror and mirror.texturePanelId == groupId) then
        return false
    end

    local group = CooldownCompanion.db.profile.groups[groupId]
    if not (group and CooldownCompanion:IsTexturePanelGroup(group)) then
        return false
    end

    ApplyTextureMirrorEffectPreview(
        mirror,
        groupId,
        group,
        mirror.texturePanelSettings,
        mirror.texturePanelBoxWidth,
        mirror.texturePanelBoxHeight
    )
    return true
end

-- Lazy per-type visuals: children of mirror.root, so the stale-mirror hide in
-- _BuildButtonPanelPreview and the readOnly release cover them automatically.
local function EnsureMirrorIconVisual(mirror)
    local visual = mirror.iconVisual
    if visual then
        return visual
    end
    local holder = CreateFrame("Frame", nil, mirror.effectHost.visualRoot)
    holder:SetPoint("CENTER", mirror.effectHost.visualRoot, "CENTER", 0, 0)
    holder:SetSize(STRIP_ICON_SIZE, STRIP_ICON_SIZE)
    visual = {
        holder = holder,
        bg = holder:CreateTexture(nil, "BACKGROUND"),
        icon = holder:CreateTexture(nil, "ARTWORK"),
        borders = {},
    }
    visual.bg:SetAllPoints()
    for index = 1, 4 do
        visual.borders[index] = holder:CreateTexture(nil, "OVERLAY")
    end
    holder.bg = visual.bg
    holder.icon = visual.icon
    holder.borderTextures = visual.borders
    mirror.effectHost.iconFrame = holder
    mirror.iconVisual = visual
    return visual
end

local function EnsureMirrorTextVisual(mirror)
    local visual = mirror.textVisual
    if visual then
        return visual
    end
    local holder = CreateFrame("Frame", nil, mirror.effectHost.visualRoot)
    holder:SetPoint("CENTER", mirror.effectHost.visualRoot, "CENTER", 0, 0)
    holder:SetSize(1, 1)
    visual = {
        holder = holder,
        bg = holder:CreateTexture(nil, "BACKGROUND"),
        text = holder:CreateFontString(nil, "OVERLAY"),
    }
    visual.bg:SetAllPoints()
    visual.text:SetJustifyV("MIDDLE")
    visual.text:SetJustifyH("CENTER")
    visual.text:SetWordWrap(false)
    visual.text:SetMaxLines(0)
    holder.bg = visual.bg
    holder.text = visual.text
    holder.borderTextures = {}
    mirror.effectHost.textFrame = holder
    mirror.textVisual = visual
    return visual
end

-- Config-side twin of the runtime ApplyTriggerIconVisual: the saved icon with
-- its background, tint, and border, scaled to fit the display band.
local function RenderTriggerIconMirror(mirror, settings, boxWidth, boxHeight)
    local visual = EnsureMirrorIconVisual(mirror)
    local holder = visual.holder
    local hasIcon = settings and ST._IsValidIconTexture
        and ST._IsValidIconTexture(settings.manualIcon)
    mirror.hasIcon = hasIcon and true or false
    if not hasIcon then
        holder:Hide()
        mirror.placeholder:SetText("No icon selected")
        mirror.placeholder:Show()
        return
    end
    mirror.placeholder:Hide()

    local width, height = CooldownCompanion.GetTriggerIconDimensions(settings)
    holder:SetScale(1)
    holder:SetSize(width, height)

    local borderSize = settings.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(settings)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(holder, borderSize, borderRenderMode)
    local bgColor = settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderColor = settings.borderColor or { 0, 0, 0, 1 }
    local tintColor = settings.iconTintColor or { 1, 1, 1, 1 }

    visual.bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0,
        bgColor[4] ~= nil and bgColor[4] or 0.5)
    visual.bg:Show()
    for _, border in ipairs(visual.borders) do
        border:SetColorTexture(borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0,
            borderColor[4] ~= nil and borderColor[4] or 1)
        border:Show()
    end
    ApplyBorderEdgePositions(visual.borders, holder, borderSize, borderRenderMode)

    local icon = visual.icon
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", borderLayoutSize, -borderLayoutSize)
    icon:SetPoint("BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)
    icon:SetTexture(settings.manualIcon)
    icon:SetVertexColor(tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1,
        tintColor[4] ~= nil and tintColor[4] or 1)
    local applyTexCoord = ST._ApplyIconTexCoord
    if applyTexCoord then
        applyTexCoord(icon, width, height, settings.iconZoom)
    end
    icon:Show()

    holder:SetScale(math_min(1, boxWidth / math_max(1, width), boxHeight / math_max(1, height)))
    holder:Show()
end

-- Config-side twin of the runtime ApplyTriggerTextVisual: the display text at
-- its real metrics (font, alignment, background), scaled to fit the band.
local function RenderTriggerTextMirror(mirror, settings, boxWidth, boxHeight)
    local visual = EnsureMirrorTextVisual(mirror)
    local holder = visual.holder
    local hasText = settings and CooldownCompanion.HasTriggerTextValue(settings)
    if not hasText then
        holder:Hide()
        mirror.placeholder:SetText("No text entered")
        mirror.placeholder:Show()
        return
    end
    mirror.placeholder:Hide()

    local bgColor = settings.textBgColor or { 0, 0, 0, 0 }
    local fontColor = settings.textFontColor or { 1, 1, 1, 1 }
    local text = visual.text

    holder:SetScale(1)
    local frameWidth, frameHeight, insetX, insetY, textWidth, textHeight, lineCount =
        CooldownCompanion.GetTriggerTextDisplayMetrics(text, settings)
    holder:SetSize(frameWidth, frameHeight)

    visual.bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0,
        bgColor[4] ~= nil and bgColor[4] or 0)
    text:SetSize(textWidth or math_max(1, frameWidth - (insetX * 2)),
        textHeight or math_max(1, frameHeight - (insetY * 2)))
    text:SetWordWrap((lineCount or 1) > 1)
    text:SetJustifyV((lineCount or 1) > 1 and "TOP" or "MIDDLE")
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", holder, "TOPLEFT", insetX, -insetY)
    text:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -insetX, insetY)
    text:SetJustifyH(settings.textAlignment or "CENTER")
    text:SetTextColor(fontColor[1] or 1, fontColor[2] or 1, fontColor[3] or 1,
        fontColor[4] ~= nil and fontColor[4] or 1)
    text:Show()

    holder:SetScale(math_min(1, boxWidth / math_max(1, frameWidth), boxHeight / math_max(1, frameHeight)))
    holder:Show()
end

local function ApplyTriggerMirrorEffectPreview(mirror, group, panelId, displayType, settings, boxWidth, boxHeight)
    local host = mirror and mirror.effectHost
    if not host then return end

    local active = CooldownCompanion:IsTriggerPanelEffectsPreviewActive(panelId)
    if not active then
        StopTextureMirrorEffects(mirror)
        return
    end

    host._activeDisplayType = displayType
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._triggerIconBaseColor = nil
    host._triggerTextBaseColor = nil
    host._indicatorBaseVisualsReady = nil

    if displayType == "texture" then
        local geometry = settings and CooldownCompanion:GetTexturePanelRenderGeometry(settings)
        if not geometry or not (mirror.primary:IsShown() or mirror.secondary:IsShown()) then
            StopTextureMirrorEffects(mirror)
            return
        end
        local fit = math_min(
            (tonumber(boxWidth) or geometry.boundsWidth) / math_max(geometry.boundsWidth, 1),
            (tonumber(boxHeight) or geometry.boundsHeight) / math_max(geometry.boundsHeight, 1),
            1
        )
        host._activeTextureSettings = settings
        host._activeTextureGeometry = {
            pieces = geometry.pieces,
            rotationRadians = geometry.rotationRadians,
            boundsWidth = geometry.boundsWidth * fit,
            boundsHeight = geometry.boundsHeight * fit,
        }
    elseif displayType == "icon" then
        if not (mirror.iconVisual and mirror.iconVisual.holder:IsShown()) then
            StopTextureMirrorEffects(mirror)
            return
        end
        local color = settings and settings.iconTintColor or { 1, 1, 1, 1 }
        host._triggerIconBaseColor = { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
    elseif displayType == "text" then
        if not (mirror.textVisual and mirror.textVisual.holder:IsShown()) then
            StopTextureMirrorEffects(mirror)
            return
        end
        local color = settings and settings.textFontColor or { 1, 1, 1, 1 }
        host._triggerTextBaseColor = { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
    end

    local previewGroup = {
        locked = true,
        triggerSettings = group and group.triggerSettings,
    }
    CooldownCompanion:ApplyTriggerPanelEffects(host, mirror.effectPreviewButton or {}, previewGroup, true)
end

-- Paint a trigger panel's display visual into the mirror: the config-side twin
-- of the runtime RenderStandaloneDisplay dispatch. Split out of the builder so
-- a settings change can repaint just this, leaving the selection strip's slots
-- and their wiring alone.
local function RenderTriggerDisplayVisual(mirror, group, panelId, boxWidth, boxHeight, readOnly)
    local displayType = CooldownCompanion.GetStandaloneDisplayType(group)
    local settings
    -- Explicit branches: an and/or chain can't yield nil for the text case.
    if displayType == "icon" then
        mirror.clickMode = "icon"
    elseif displayType == "text" then
        mirror.clickMode = nil
    else
        mirror.clickMode = "texture"
    end

    mirror.primary:Hide()
    mirror.secondary:Hide()
    if mirror.iconVisual then mirror.iconVisual.holder:Hide() end
    if mirror.textVisual then mirror.textVisual.holder:Hide() end

    if displayType == "icon" then
        settings = CooldownCompanion:GetTriggerPanelIconSettings(group)
        RenderTriggerIconMirror(mirror, settings, boxWidth, boxHeight)
    elseif displayType == "text" then
        settings = CooldownCompanion:GetTriggerPanelTextSettings(group)
        RenderTriggerTextMirror(mirror, settings, boxWidth, boxHeight)
    else
        mirror.placeholder:SetText("No texture selected")
        -- Same staged-selection precedence as BuildTextureMirror: picker
        -- selection first, then the config-only continuous-edit copy, then the
        -- saved trigger texture.
        local staged = CS.textureMirrorStage
        local configStaged = CS.textureConfigPreviewStage
        settings = readOnly and CooldownCompanion:GetTriggerPanelSignalSettings(group)
            or (staged and staged.groupId == panelId and staged.selection)
            or (configStaged and configStaged.groupId == panelId and configStaged.settings)
            or CooldownCompanion:GetTriggerPanelSignalSettings(group)
        local render = ST._UpdateTexturePanelPreview
        if render then
            render(mirror, settings, boxWidth, boxHeight)
        end
    end

    if not readOnly then
        ApplyTriggerMirrorEffectPreview(mirror, group, panelId, displayType, settings, boxWidth, boxHeight)
    end
end

local function BuildTextureMirror(preview, host, panelId, group, readOnly)
    -- No animated slots on a texture panel; mirror BuildSelectionStrip's setup.
    StopConditionalTicker(preview)

    local mirror = EnsureTextureMirror(preview)
    mirror.root:Show()

    -- The mirror is shared with the trigger preview on this host, so restore
    -- the texture-panel presentation before rendering.
    mirror.clickMode = "texture"
    mirror.placeholder:SetText("No texture selected")
    if mirror.iconVisual then mirror.iconVisual.holder:Hide() end
    if mirror.textVisual then mirror.textVisual.holder:Hide() end

    -- Only make the rendered texture clickable when the panel has its entry.
    -- An empty texture panel still offers drop-to-add on the preview host, and
    -- an interactive mirror would swallow the drop.
    local hasEntry = group and group.buttons and group.buttons[1] ~= nil
    local guidanceReserve = not readOnly and not hasEntry and EMPTY_ENTRY_GUIDANCE_BAND or 0
    ApplyMirrorBand(mirror, preview.root, guidanceReserve)
    mirror.root:EnableMouse(not readOnly and hasEntry and true or false)
    if not hasEntry then
        mirror.hoverCue:Hide()
    end

    -- Focused texture mirrors retain the established measurement guard;
    -- overview mirrors use the tile's actual smaller fit box.
    local boxWidth, boxHeight = GetHostFitBox(host, readOnly)
    local mirrorBoxHeight = math_max(1, boxHeight - guidanceReserve)

    -- Prefer the picker's staged selection for the panel being edited, else the
    -- saved texture. Both are NormalizeAuraTextureSettings tables, so the shared
    -- renderer needs no per-source handling; nil means the panel has no texture.
    local staged = CS.textureMirrorStage
    local configStaged = CS.textureConfigPreviewStage
    local settings = readOnly and CooldownCompanion:GetTexturePanelSettings(group)
        or (staged and staged.groupId == panelId and staged.selection)
        or (configStaged and configStaged.groupId == panelId and configStaged.settings)
        or CooldownCompanion:GetTexturePanelSettings(group)

    mirror.texturePanelId = panelId
    mirror.texturePanelSettings = settings
    mirror.texturePanelBoxWidth = boxWidth
    mirror.texturePanelBoxHeight = mirrorBoxHeight

    local render = ST._UpdateTexturePanelPreview
    if render then
        render(mirror, settings, boxWidth, mirrorBoxHeight)
    end
    if not readOnly then
        ApplyTextureMirrorEffectPreview(mirror, panelId, group, settings, boxWidth, mirrorBoxHeight)
    end
    if guidanceReserve > 0 then
        SetPreviewMessage(preview,
            "Add an entry with the field below, or drag it into this preview.")
        local label = preview.messageLabel
        label:ClearAllPoints()
        label:SetPoint("BOTTOMLEFT", preview.root, "BOTTOMLEFT", 18, PANEL_PREVIEW_PADDING)
        label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, PANEL_PREVIEW_PADDING)
    end

    FinalizePreviewState(preview)
end

-- Trigger-panel Live Preview: the panel's actual display visual (texture,
-- icon, or text) renders large on top, with the entry selection strip in a
-- band along the bottom keeping all of its picker behavior. Unlike texture
-- panels, the mirror stays clickable with zero entries: trigger appearance is
-- configurable without entries and the bottom tab has no picker buttons, so
-- the preview click is the only path into the pickers. Drop-to-add is safe
-- either way - the payload drop overlay sits above the mirror whenever a
-- spell or item is on the cursor. Read-only Group Overview tiles do not
-- stack; see the branch below.
local function BuildTriggerPanelPreview(preview, host, panelId, group, readOnly)
    StopConditionalTicker(preview)

    local mirror = EnsureTextureMirror(preview)
    local boxWidth, boxHeight = GetHostFitBox(host, readOnly)

    -- Group Overview tiles stand on a standardized row height with only ~36px
    -- of fit box left, and the strip is an editing affordance a tile cannot be
    -- clicked in anyway. A tile therefore shows the panel's real display
    -- alone, the way a texture panel's tile does, rather than splitting that
    -- band two ways and rendering both halves too small to read. With no
    -- display configured yet the entry strip is the only informative thing
    -- left, so it stands in.
    if readOnly then
        preview.triggerStripReserve = 0
        if GetTriggerDisplayNaturalSize(group) <= 0 then
            mirror.root:Hide()
            return BuildSelectionStrip(preview, host, panelId, group, readOnly)
        end
        mirror.root:Show()
        mirror.root:EnableMouse(false)
        mirror.hoverCue:Hide()
        ApplyMirrorBand(mirror, preview.root, 0)
        RenderTriggerDisplayVisual(mirror, group, panelId, boxWidth, boxHeight, true)
        FinalizePreviewState(preview)
        return
    end

    mirror.root:Show()

    local count = #(group.buttons or {})
    local reserve, stripLayout
    if count > 0 then
        local stripW, stripH = GetStripNaturalSize(count)
        local stripScale = math_min(1, boxWidth / math_max(1, stripW),
            (boxHeight * TRIGGER_PREVIEW_STRIP_MAX_SHARE) / math_max(1, stripH))
        reserve = (stripH * stripScale) + PANEL_PREVIEW_PADDING
        stripLayout = { anchorPoint = "BOTTOM", scaleOverride = stripScale }
    else
        reserve = EMPTY_ENTRY_GUIDANCE_BAND
    end

    ApplyMirrorBand(mirror, preview.root, reserve)
    -- Recorded for ST._RefreshTriggerDisplayVisual: the band depends only on
    -- the entry count and the host, so a display setting cannot move it.
    preview.triggerStripReserve = reserve

    RenderTriggerDisplayVisual(mirror, group, panelId, boxWidth,
        math_max(1, boxHeight - reserve), false)
    mirror.root:EnableMouse(mirror.clickMode ~= nil)
    if not mirror.clickMode then
        mirror.hoverCue:Hide()
    end

    if count > 0 then
        return BuildSelectionStrip(preview, host, panelId, group, readOnly, stripLayout)
    end

    SetPreviewMessage(preview,
        "Add entries with the field below, or drag them into this preview.")
    -- Tuck the message into the reserved bottom band so it never overlaps the
    -- display visual; SetPreviewMessage restores the default anchors for the
    -- next build.
    local label = preview.messageLabel
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", preview.root, "BOTTOMLEFT", 18, PANEL_PREVIEW_PADDING)
    label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, PANEL_PREVIEW_PADDING)
    FinalizePreviewState(preview)
end

-- Repaint ONLY a trigger panel's display visual in the pinned mirror, leaving
-- the selection strip's slots and their wiring untouched. The appearance tabs
-- call this on every tick of a slider drag, where a full preview rebuild would
-- re-run per-entry usability and load-condition queries and re-wire every
-- strip slot each frame. Returns false when there is no live trigger mirror to
-- repaint so callers can fall back to the full rebuild.
function ST._RefreshTriggerDisplayVisual(groupId)
    if not (ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()) then return false end
    if not groupId or groupId ~= CS.selectedGroup then return false end
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.buttonsPreviewHost
    if not (host and host:IsShown() and col3._cdcActiveWideHost == host) then return false end
    local preview = host._cdcPanelPreview
    local mirror = preview and preview.textureMirror
    if not (mirror and mirror.root:IsShown()) then return false end
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not (group and CooldownCompanion:IsTriggerPanelGroup(group)) then return false end

    local boxWidth, boxHeight = GetHostFitBox(host, false)
    RenderTriggerDisplayVisual(mirror, group, groupId, boxWidth,
        math_max(1, boxHeight - (preview.triggerStripReserve or 0)), false)
    mirror.root:EnableMouse(mirror.clickMode ~= nil)
    if not mirror.clickMode then
        mirror.hoverCue:Hide()
    end
    return true
end

function ST._StopTriggerPanelEffectsPreviewMirror(groupId)
    local mirror = GetActiveTextureMirror(groupId)
    if not mirror then return false end
    StopTextureMirrorEffects(mirror)
    return true
end

-- Private helpers consumed by later ButtonPanelPreview files.
PP.StopTextureMirrorEffects = StopTextureMirrorEffects
PP.BuildTextureMirror = BuildTextureMirror
PP.BuildTriggerPanelPreview = BuildTriggerPanelPreview
PP.BuildSelectionStrip = BuildSelectionStrip
