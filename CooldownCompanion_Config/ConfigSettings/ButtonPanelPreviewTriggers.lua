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
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local IsStoredPreviewFlagActive = ST._IsStoredPreviewFlagActive
local AuraTextures = ST._AT
local ApplyTextureIndicatorEffects = AuraTextures and AuraTextures.ApplyTextureIndicatorEffects
local SetTextureIndicatorBaseVisuals = AuraTextures and AuraTextures.SetTextureIndicatorBaseVisuals
local StopAllTextureIndicatorEffects = AuraTextures and AuraTextures.StopAllTextureIndicatorEffects

local PP = ST._ButtonPanelPreview
local AceGUI = LibStub("AceGUI-3.0")

local conditionPhrases = {
    cooldownActive = {[true]="on cooldown", [false]="off cooldown"},
    procActive = {[true]="showing a proc", [false]="not showing a proc"},
    rangeActive = {[true]="in range", [false]="out of range"},
    usable = {[true]="usable", [false]="unusable"},
    chargesRecharging = {[true]="recharging a charge", [false]="not recharging any charges"},
    chargeState = {full="at full charges", missing="below full charges with at least one remaining", zero="out of charges"},
    countTextActive = {[true]="showing count text", [false]="not showing count text"},
    countState = {full="at its maximum display count", missing="below its maximum display count with a nonzero count",
        zero="at zero display count"},
}

local function TrackingSummary(group)
    local I = ST.Indicator
    local source = I.Primary(group)
    if source.enabled == false then return "Cannot show: the primary source is disabled." end
    local prefix = group.enabled == false
        and "This Indicator is disabled. When enabled, it shows when " or "Shows when "
    if I.IsAura(group) then return prefix .. (source.name or tostring(source.id)) .. " is active." end
    local sources = {}
    -- Read the same saved clauses as I.Match: every enabled source and clause
    -- must match, even when the primary selector says Always.
    for _, entry in ipairs(group.buttons or {}) do
        if entry.enabled ~= false then
            local name, phrases = entry.name or tostring(entry.id), {}
            for _, clause in ipairs(entry.triggerConditions or {}) do
                local expected = clause.state
                if expected == nil then expected = clause.expected ~= false end
                local values = conditionPhrases[clause.key]
                local phrase = values and values[expected]
                if clause.unavailable or not I.ConditionKeys[clause.key] or not phrase then
                    return "Cannot show: " .. name .. " has an unavailable condition. Replace or remove that condition."
                end
                phrases[#phrases + 1] = phrase
            end
            sources[#sources + 1] = name .. " is " .. (#phrases > 0 and table.concat(phrases, " and ") or "available to track")
        end
    end
    return prefix .. table.concat(sources, ", and ") .. "."
end

function PP.ReleaseIndicatorPreviewControls(preview)
    if preview.indicatorCaption then preview.indicatorCaption:Hide() end
    if preview.indicatorDuration then
        AceGUI:Release(preview.indicatorDuration)
        preview.indicatorDuration = nil
    end
end

function PP.BuildIndicatorPreview(preview, host, panelId, group, readOnly)
    if preview.indicatorDuration then preview.indicatorDuration.frame:Hide() end
    if preview.indicatorCaption then preview.indicatorCaption:Hide() end
    local I = ST.Indicator
    if not I.Primary(group) then
        PP.SetPreviewMessage(preview, "Add a spell, aura, or item using the field below.", "Choose a source")
        PP.FinalizePreviewState(preview)
        return
    end
    -- Detached saved-design render: no production aura widgets are inspected.
    local candidate = CopyTable(group)
    I.Initialize(candidate)
    local stage = CS.textureConfigPreviewStage
    local pickerStage = CS.textureMirrorStage
    if not readOnly and pickerStage and pickerStage.groupId == panelId and pickerStage.selection then
        candidate.indicatorSettings.signal=CopyTable(pickerStage.selection)
    elseif not readOnly and stage and stage.groupId == panelId then
        candidate.indicatorSettings.signal=CopyTable(stage.settings)
    end
    local surface = preview.indicatorSurface
    if not surface then
        surface = CreateFrame("Frame",nil,preview.root)
        surface:EnableMouse(false)
        surface.visualRoot = CreateFrame("Frame",nil,surface)
        surface.visualRoot:SetPoint("CENTER")
        surface.primaryTexture = surface.visualRoot:CreateTexture(nil,"ARTWORK")
        surface.secondaryTexture = surface.visualRoot:CreateTexture(nil,"ARTWORK")
        preview.indicatorSurface = surface
    end
    local state = not readOnly and CS.indicatorPreviewState or "half"
    local fraction = state == "full" and 1 or state == "empty" and 0 or 0.5
    if state == "timeless" then fraction=1 end
    if not I.Render(surface,nil,candidate,true,fraction) then
        PP.SetPreviewMessage(preview,"Choose artwork in Appearance to preview this Indicator.")
        PP.FinalizePreviewState(preview)
        return
    end
    if state == "timeless" then surface.indicatorReadouts.timer:SetText("") end
    if not readOnly then
        candidate.locked = true
        local sample = {buttonData=I.Primary(candidate), _textureAuraPreview=true}
        if I.IsAura(candidate) then
            -- Native text has no registered vertex-color artwork animation.
            if candidate.indicatorSettings.displayType == "text" then
                local effects=I.Effects(candidate)
                if effects.colorShift then effects.colorShift.enabled=false end
            end
            ApplyTextureIndicatorEffects(surface,sample,candidate,"aura")
        else
            CooldownCompanion:ApplyTriggerPanelEffects(surface,sample,candidate,true,true)
        end
    end
    local width,height=surface:GetSize()
    local settings = I.Settings(candidate)
    local showDuration = not readOnly and (settings.readouts.timer
        or settings.displayType == "texture" and settings.progress.enabled)
    local footerHeight = 0
    if not readOnly then
        local caption=preview.indicatorCaption
        if not caption then
            caption=preview.root:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
            ST._ConfigureWrappedHelperLabel(caption)
            caption:SetJustifyH("CENTER")
            caption:SetTextColor(0.75,0.75,0.75)
            preview.indicatorCaption=caption
        end
        local captionWidth = PP.GetHostFitBox(host,false)
        caption:ClearAllPoints()
        caption:SetWidth(captionWidth)
        caption:SetPoint("TOP",surface,"BOTTOM",0,-8)
        caption:SetText(TrackingSummary(group))
        caption:Show()
        footerHeight = 8 + math_max(1,caption:GetStringHeight())
        if showDuration then
            local control = preview.indicatorDuration
            if not control then
                -- Use the shared row's dropdown geometry and pool cleanup.
                control = AceGUI:Create("CDC-DropdownRow")
                control:SetLabel("Duration")
                control:SetList({full="Full",half="Half",empty="Empty",timeless="No Timer"},
                    {"full","half","empty","timeless"})
                control.frame:SetParent(preview.root)
                preview.indicatorDuration = control
            end
            control:SetWidth(math_min(260,captionWidth))
            control.frame:ClearAllPoints()
            control.frame:SetPoint("TOP",caption,"BOTTOM",0,-8)
            control:SetValue(state)
            control:SetCallback("OnValueChanged",function(_,_,value)
                CS.indicatorPreviewState=value
                ST._RefreshButtonsPreviewMirror(panelId)
            end)
            control.frame:Show()
            footerHeight = footerHeight + 8 + control.frame:GetHeight()
        end
    end
    -- Caption and controls stay readable at the host scale. Reserve their
    -- measured height before fitting the artwork, then center the whole stack.
    local scale = PP.GetHostFitScale(host,width,height+(readOnly and 28 or 0),readOnly,footerHeight)
    surface:SetScale(scale)
    surface:ClearAllPoints()
    surface:SetPoint("CENTER",preview.root,"CENTER",0,readOnly and 10 or footerHeight / (2 * scale))
    surface:Show()
    preview.barBaseRect = {x=0,y=0,width=width,height=height}
    PP.FinalizePreviewState(preview)
end
local StylePreviewIcon = PP.StylePreviewIcon

-- ButtonPanelPreviewEffects.lua
local StopConditionalTicker = PP.StopConditionalTicker
local ClearSlotEffectPreviews = PP.ClearSlotEffectPreviews
local ApplySlotEffectPreviews = PP.ApplySlotEffectPreviews
local EnsureConditionalTicker = PP.EnsureConditionalTicker

-- ButtonPanelPreviewShared.lua
local SetPreviewMessage = PP.SetPreviewMessage
local HidePreviewMessage = PP.HidePreviewMessage
local FinalizePreviewState = PP.FinalizePreviewState
local STRIP_ICON_SIZE = PP.STRIP_ICON_SIZE
local STRIP_PER_ROW = PP.STRIP_PER_ROW
local STRIP_SPACING = PP.STRIP_SPACING
local GetHostFitScale = PP.GetHostFitScale
local AcquireSlot = PP.AcquireSlot
local ApplyPreviewSlotGeometry = PP.ApplyPreviewSlotGeometry
local DisableReadOnlySlotInteraction = PP.DisableReadOnlySlotInteraction
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = PP.PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET
local CollectEntryStatus = ST._CollectEntryStatus
local PANEL_PREVIEW_DISABLED_ALPHA = PP.PANEL_PREVIEW_DISABLED_ALPHA
local ApplySlotBadges = PP.ApplySlotBadges
local ApplySelectionVisuals = PP.ApplySelectionVisuals
local CopyMode = PP.CopyMode
local PANEL_PREVIEW_PADDING = PP.PANEL_PREVIEW_PADDING
local EMPTY_ENTRY_GUIDANCE_BAND = PP.EMPTY_ENTRY_GUIDANCE_BAND
local GetHostFitBox = PP.GetHostFitBox
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
        StylePreviewIcon(slot, buttonData, group)
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
            -- This pseudo-entry has its own click semantics. The next grid
            -- binding must reinstall the shared handlers after this override.
            slot._cdcEntryHandlersInstalled = nil
            slot._cdcSpecialEntryHandlers = true
            slot:SetScript("OnMouseDown", nil)
            ApplySelectionVisuals(slot, 1, CS.selectedRotationAssistantEntry == true)
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

PP.BuildSelectionStrip = BuildSelectionStrip

function ST._RefreshTriggerDisplayVisual(groupId)
    if groupId ~= CS.selectedGroup then return false end
    ST._RefreshButtonsPreviewMirror(groupId)
    return true
end
