--[[
    CooldownCompanion - Config/ButtonsWideColumn
    Wide column 3 for the plain buttons view: hosts the entry settings
    surfaces (bsTabGroup, entry multi-select), the panel batch actions, and
    the group-side settings surfaces (via GroupSettingsHost) in one column
    spanning the col3+col4 region. Column 4 is hidden while this is active.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

local PREVIEW_GAP = 4
local ADD_BOX_HEIGHT = 26
local STRIP_HEIGHT = 30
local STRIP_ICON_SIZE = 20
local STRIP_BADGE_SIZE = 18
local STRIP_BADGE_GAP = 3

local DISPLAY_MODE_LABELS = {
    icons = "Icons",
    bars = "Bars",
    text = "Text",
    textures = "Textures",
    trigger = "Trigger",
    [ST.DISPLAY_MODE_ROTATION_ASSISTANT] = "Rotation Assistant",
}

local function HideEntrySurfaces(col3)
    if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
    if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
    if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
end

-- Settings surfaces anchor beneath the pinned preview, its add box, and
-- the identity strip when shown, and fill the whole column otherwise
-- (Resources-home pattern).
local function AnchorButtonsContentFrame(col3, frame)
    frame:ClearAllPoints()
    local previewHost = col3.buttonsPreviewHost
    local addBox = col3.buttonsAddBox
    local strip = col3.buttonsIdentityStrip
    local topAnchor
    if strip and strip:IsShown() then
        topAnchor = strip
    elseif addBox and addBox.frame:IsShown() then
        topAnchor = addBox.frame
    elseif previewHost and previewHost:IsShown() then
        topAnchor = previewHost
    end
    if topAnchor then
        frame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -PREVIEW_GAP)
        frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    else
        frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
        frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    end
end

local function CanManuallyAddToPanel(group)
    if not group then return false end
    if group.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT then return false end
    if group.displayMode == "textures" and #(group.buttons or {}) >= 1 then return false end
    return true
end

local function IsCursorDropPayload(cursorType)
    return cursorType == "spell" or cursorType == "item" or cursorType == "petaction"
end

-- Drop-to-add overlay over the preview: shown while a spell/item is on the
-- cursor, mirroring the column 2 panel drop overlays. TryReceiveCursorDrop
-- targets CS.selectedGroup, which is exactly the previewed panel.
local function EnsurePreviewDropOverlay(host)
    local overlay = host._cdcDropOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, host, "BackdropTemplate")
        overlay:SetAllPoints(host)
        overlay:SetBackdrop({ bgFile = "Interface\\BUTTONS\\WHITE8X8" })
        overlay:SetBackdropColor(0.15, 0.55, 0.85, 0.25)
        overlay:EnableMouse(true)

        local inner = overlay:CreateTexture(nil, "ARTWORK")
        inner:SetPoint("TOPLEFT", 2, -2)
        inner:SetPoint("BOTTOMRIGHT", -2, 2)
        inner:SetColorTexture(0.05, 0.15, 0.25, 0.6)

        overlay._cdcText = overlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        overlay._cdcText:SetPoint("CENTER", 0, 0)
        overlay._cdcText:SetText("|cffAADDFFDrop here|r")

        local function ReceiveDrop()
            if ST._TryReceiveCursorDrop then
                ST._TryReceiveCursorDrop()
            end
        end
        overlay:SetScript("OnReceiveDrag", ReceiveDrop)
        overlay:SetScript("OnMouseUp", function(self, button)
            if button == "LeftButton" and GetCursorInfo() then
                ReceiveDrop()
            end
        end)
        overlay:Hide()
        host._cdcDropOverlay = overlay
    end
    overlay:SetFrameLevel(host:GetFrameLevel() + 30)
    return overlay
end

local function UpdatePreviewDropOverlay()
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.buttonsPreviewHost
    if not host then return end
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local show = host:IsShown()
        and IsCursorDropPayload(GetCursorInfo())
        and CanManuallyAddToPanel(group)
        and ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()
    if show then
        EnsurePreviewDropOverlay(host):Show()
    elseif host._cdcDropOverlay then
        host._cdcDropOverlay:Hide()
    end
end

local previewCursorWatcher = CreateFrame("Frame")
previewCursorWatcher:RegisterEvent("CURSOR_CHANGED")
previewCursorWatcher:SetScript("OnEvent", UpdatePreviewDropOverlay)

local function HidePanelPreview(col3)
    local host = col3.buttonsPreviewHost
    if host then
        host:Hide()
        if host._cdcDropOverlay then
            host._cdcDropOverlay:Hide()
        end
        if ST._ReleaseButtonPanelPreview then
            ST._ReleaseButtonPanelPreview(host)
        end
    end
    if col3.buttonsAddBox then
        col3.buttonsAddBox.frame:Hide()
    end
    if col3.buttonsIdentityStrip then
        col3.buttonsIdentityStrip:Hide()
    end
end

-- Pinned preview of the selected panel at the top of the wide column.
local function UpdatePanelPreview(col3)
    if not CS.selectedGroup then
        HidePanelPreview(col3)
        return
    end

    local host = col3.buttonsPreviewHost
    if not host then
        host = CreateFrame("Frame", nil, col3.content)
        host:SetClipsChildren(false)
        col3.buttonsPreviewHost = host
    end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    host:SetPoint("TOPRIGHT", col3.content, "TOPRIGHT", 0, 0)
    local columnHeight = col3.content:GetHeight() or 0
    host:SetHeight(math.max(150, math.floor(columnHeight * 0.35)))
    host:Show()
    ST._BuildButtonPanelPreview(host, CS.selectedGroup)
    UpdatePreviewDropOverlay()
end

-- Add-entry box pinned under the preview, scoped to the selected panel.
-- Reuses the same TryAdd/autocomplete plumbing as the column 2 inline add.
local function EnsureAddBox(col3)
    local addBox = col3.buttonsAddBox
    if addBox then return addBox end

    addBox = AceGUI:Create("EditBox")
    if addBox.editbox.Instructions then addBox.editbox.Instructions:Hide() end
    addBox:SetLabel("")
    addBox:SetText("")
    addBox:DisableButton(true)
    addBox.frame:SetParent(col3.content)

    local editFrame = addBox.editbox
    local instructions = editFrame:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    instructions:SetPoint("LEFT", editFrame, "LEFT", 6, 0)
    instructions:SetPoint("RIGHT", editFrame, "RIGHT", -6, 0)
    instructions:SetJustifyH("LEFT")
    instructions:SetTextColor(0.5, 0.5, 0.5)
    instructions:SetText("Add spell, item, trinket slot, or ID")
    addBox._cdcInstructions = instructions

    addBox:SetCallback("OnEnterPressed", function(widget, event, text)
        if CS.ConsumeAutocompleteEnter() then return end
        CS.HideAutocomplete()
        text = text or ""
        if text == "" or not CS.selectedGroup then return end
        local targetGroupId = CS.selectedGroup
        if not ST._TryAdd(text) then return end
        if ST._NotifyTutorialAction and CS.selectedButton then
            ST._NotifyTutorialAction("inline_add_succeeded", {
                groupId = targetGroupId,
                buttonIndex = CS.selectedButton,
                rawInput = text,
            })
        end
        widget:SetText("")
        local targetGroup = CooldownCompanion.db.profile.groups[targetGroupId]
        if not (targetGroup and targetGroup.displayMode == "textures") then
            CS.pendingWideAddFocus = true
        end
        CooldownCompanion:RefreshConfigPanel()
    end)
    addBox:SetCallback("OnTextChanged", function(widget, event, text)
        instructions:SetShown((text or "") == "")
        if text and #text >= 1 then
            local results = ST._SearchAutocomplete(text)
            CS.ShowAutocompleteResults(results, widget, ST._OnAutocompleteSelect, {
                requireExactNumericEnter = true,
            })
        else
            CS.HideAutocomplete()
        end
    end)
    CS.SetupAutocompleteKeyHandler(addBox)

    col3.buttonsAddBox = addBox
    return addBox
end

local function UpdateAddBox(col3)
    local host = col3.buttonsPreviewHost
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not (host and host:IsShown() and CanManuallyAddToPanel(group)) then
        if col3.buttonsAddBox then
            col3.buttonsAddBox.frame:Hide()
        end
        return
    end

    local addBox = EnsureAddBox(col3)
    addBox.frame:ClearAllPoints()
    addBox.frame:SetPoint("TOPLEFT", host, "BOTTOMLEFT", 0, -PREVIEW_GAP)
    addBox.frame:SetPoint("TOPRIGHT", host, "BOTTOMRIGHT", 0, -PREVIEW_GAP)
    addBox.frame:SetHeight(ADD_BOX_HEIGHT)
    addBox.frame:Show()

    -- Also consume the shared autocomplete focus flag when the column 2
    -- inline add isn't open (its box consumes it when addingToPanelId is set).
    local wantFocus = CS.pendingWideAddFocus
    if not wantFocus and CS.pendingEditBoxFocus and not CS.addingToPanelId then
        CS.pendingEditBoxFocus = false
        wantFocus = true
    end
    if wantFocus then
        CS.pendingWideAddFocus = false
        C_Timer.After(0, function()
            if addBox.editbox and addBox.frame:IsShown() then
                addBox:SetFocus()
            end
        end)
    end
end

local function EnsureIdentityStrip(col3)
    local strip = col3.buttonsIdentityStrip
    if strip then return strip end

    strip = CreateFrame("Frame", nil, col3.content)
    strip:SetHeight(STRIP_HEIGHT)

    strip.name = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    strip.name:SetJustifyH("CENTER")
    strip.name:SetWordWrap(false)

    local divider = strip:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.08)
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
    divider:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)

    strip.badges = {}
    col3.buttonsIdentityStrip = strip
    return strip
end

local function AcquireStripBadge(strip, index)
    local badge = strip.badges[index]
    if not badge then
        badge = CreateFrame("Frame", nil, strip)
        badge:SetSize(STRIP_BADGE_SIZE, STRIP_BADGE_SIZE)
        badge:EnableMouse(true)
        badge.icon = badge:CreateTexture(nil, "ARTWORK")
        badge.icon:SetAllPoints()
        badge:SetScript("OnEnter", function(self)
            if not self._cdcLabel then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self._cdcLabel, 1, 1, 1)
            GameTooltip:Show()
        end)
        badge:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        strip.badges[index] = badge
    end
    return badge
end

-- Identity strip between the add box and the settings surfaces: names what
-- the settings below are editing (selected entry or panel) and carries the
-- full status badge row the retired column 2 entry rows used to show.
local function UpdateIdentityStrip(col3)
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local icon, name, badgeStatus
    if group then
        local multiCount = 0
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        if multiCount >= 2 then
            -- Entry multi-select surface lists its members itself.
        elseif CS.selectedRotationAssistantEntry == true
            and CooldownCompanion:IsRotationAssistantGroup(group) then
            local spellID = CooldownCompanion:GetRotationAssistantActionSpellID()
            icon = CooldownCompanion:GetRotationAssistantFallbackIcon(spellID)
            name = ST.ROTATION_ASSISTANT_NAME
        elseif CS.selectedButton and group.buttons[CS.selectedButton] then
            local buttonData = group.buttons[CS.selectedButton]
            icon = ST._GetLayoutPreviewIcon and ST._GetLayoutPreviewIcon(buttonData)
            name = ST._GetConfigEntryDisplayName
                and ST._GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
                or buttonData.name
            -- Spell entries: name the tracking kind next to the sword/heart
            -- decoration icon (same addedAs fallback the decoration uses).
            if name and buttonData.type == "spell" then
                local addedAs = buttonData.addedAs
                if addedAs ~= "spell" and addedAs ~= "aura" then
                    addedAs = buttonData.isPassive and "aura" or "spell"
                end
                name = name .. " |cff808080(" .. (addedAs == "aura" and "Aura" or "Spell") .. ")|r"
            end
            badgeStatus = ST._CollectEntryStatus and ST._CollectEntryStatus(buttonData, group)
        else
            name = group.name or "Panel"
            local modeLabel = DISPLAY_MODE_LABELS[group.displayMode or "icons"]
            if modeLabel then
                name = name .. " |cff808080(" .. modeLabel .. ")|r"
            end
        end
    end

    local strip = col3.buttonsIdentityStrip
    if not name then
        if strip then strip:Hide() end
        return
    end
    strip = EnsureIdentityStrip(col3)

    -- Inline the entry icon so it centers (and truncates) with the name;
    -- the crop matches the 0.08 tex-coord inset used on icon slots.
    if icon then
        name = "|T" .. icon .. ":" .. STRIP_ICON_SIZE .. ":" .. STRIP_ICON_SIZE
            .. ":0:0:64:64:5:59:5:59|t " .. name
    end

    local shown = 0
    local rightAnchor
    if badgeStatus and ST._EntryStatusBadges then
        for _, desc in ipairs(ST._EntryStatusBadges) do
            if badgeStatus[desc.key] then
                shown = shown + 1
                local badge = AcquireStripBadge(strip, shown)
                badge.icon:SetAtlas(desc.atlas, false)
                badge._cdcLabel = (desc.key == "warn" and badgeStatus.loadBlocked)
                    and "Hidden by load conditions" or desc.label
                badge:ClearAllPoints()
                if rightAnchor then
                    badge:SetPoint("RIGHT", rightAnchor, "LEFT", -STRIP_BADGE_GAP, 0)
                else
                    badge:SetPoint("RIGHT", strip, "RIGHT", -2, 0)
                end
                badge:Show()
                rightAnchor = badge
            end
        end
    end
    for i = shown + 1, #strip.badges do
        strip.badges[i]:Hide()
    end

    strip.name:SetText(name)
    strip.name:ClearAllPoints()
    strip.name:SetPoint("LEFT", strip, "LEFT", 2, 0)
    if rightAnchor then
        strip.name:SetPoint("RIGHT", rightAnchor, "LEFT", -8, 0)
    else
        strip.name:SetPoint("RIGHT", strip, "RIGHT", -2, 0)
    end

    local addBox = col3.buttonsAddBox
    local top = (addBox and addBox.frame:IsShown()) and addBox.frame
        or col3.buttonsPreviewHost
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -PREVIEW_GAP)
    strip:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -PREVIEW_GAP)
    strip:Show()
end

-- True when the column should show entry settings instead of the
-- group-side surfaces: a valid single entry (including the rotation
-- assistant's virtual entry) or an entry multi-select.
local function IsEntrySelectionActive()
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    if not group then
        return false
    end
    local multiCount = 0
    for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
    if multiCount >= 2 then
        return true
    end
    if CS.selectedRotationAssistantEntry == true
        and CooldownCompanion:IsRotationAssistantGroup(group) then
        return true
    end
    return CS.selectedButton ~= nil and group.buttons[CS.selectedButton] ~= nil
end

local function RefreshButtonsWideColumn()
    local col3 = CS.configFrame and CS.configFrame.col3
    if not col3 then return end

    -- Hide surfaces owned by the resources/cast homes that share col3
    if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
    col3._customAuraSubScroll = nil
    if col3._customAuraScroll then col3._customAuraScroll.frame:Hide() end
    if col3._customBarsScroll then col3._customBarsScroll.frame:Hide() end
    if col3._resourcesIntroPane then col3._resourcesIntroPane:Hide() end
    if col3._unitFramesScroll then col3._unitFramesScroll.frame:Hide() end
    if col3._unitFramesIntroPane then col3._unitFramesIntroPane:Hide() end

    -- Panel multi-select: batch operations replace everything else
    local panelMultiCount = 0
    local multiPanelIds = {}
    for pid in pairs(CS.selectedPanels) do
        panelMultiCount = panelMultiCount + 1
        multiPanelIds[#multiPanelIds + 1] = pid
    end
    if panelMultiCount >= 2 and CS.selectedContainer then
        HideEntrySurfaces(col3)
        HidePanelPreview(col3)
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end

        if not col3._panelMultiSelectScroll then
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            scroll.frame:SetParent(col3.content)
            scroll.frame:ClearAllPoints()
            scroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
            scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
            col3._panelMultiSelectScroll = scroll
        end
        col3._panelMultiSelectScroll:ReleaseChildren()
        col3._panelMultiSelectScroll.frame:Show()
        ST._RefreshPanelMultiSelect(col3._panelMultiSelectScroll, panelMultiCount, multiPanelIds)
        return
    end
    if col3._panelMultiSelectScroll then
        col3._panelMultiSelectScroll.frame:Hide()
    end

    -- Entry selected: the entry settings surfaces own the settings area
    if IsEntrySelectionActive() then
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
        UpdatePanelPreview(col3)
        UpdateAddBox(col3)
        UpdateIdentityStrip(col3)
        if col3.bsTabGroup then
            AnchorButtonsContentFrame(col3, col3.bsTabGroup.frame)
        end
        if col3.multiSelectScroll then
            AnchorButtonsContentFrame(col3, col3.multiSelectScroll.frame)
        end
        ST._RefreshButtonSettingsColumn()
        -- The multi-select scroll may have been created just now with fill
        -- anchors; re-anchor it below the preview.
        if col3.multiSelectScroll then
            AnchorButtonsContentFrame(col3, col3.multiSelectScroll.frame)
        end
        return
    end

    -- Otherwise the group-side surfaces (panel, container, folder settings,
    -- placeholders) own the settings area
    HideEntrySurfaces(col3)
    UpdatePanelPreview(col3)
    UpdateAddBox(col3)
    UpdateIdentityStrip(col3)

    local host = col3.groupSettingsHost
    if not host then
        host = CreateFrame("Frame", nil, col3.content)
        col3.groupSettingsHost = host
    end
    AnchorButtonsContentFrame(col3, host)
    host:Show()
    ST._RefreshGroupSettingsHost(host)
end

ST._RefreshButtonsWideColumn = RefreshButtonsWideColumn
ST._AnchorButtonsContentFrame = AnchorButtonsContentFrame
