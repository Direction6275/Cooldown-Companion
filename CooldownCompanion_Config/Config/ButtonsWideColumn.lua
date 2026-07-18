--[[
    CooldownCompanion - Config/ButtonsWideColumn
    Wide column 3 for the plain buttons view and Other Class browsing:
    hosts the entry settings surfaces (bsTabGroup, entry multi-select),
    the panel batch actions, and the group-side settings surfaces (via
    GroupSettingsHost) in one column spanning the old col3+col4 region.
    The column frames two labeled areas: the pinned Live Preview above the
    split divider (the column title names it) and the editing surface
    below it (the "Editing:" header, add box, identity strip, and settings
    on a more opaque backdrop). Browsing skips the pinned preview cluster
    (panels render live in the world).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")

local PREVIEW_GAP = 4
local ADD_BOX_HEIGHT = 26
local STRIP_HEIGHT = 26
local STRIP_ICON_SIZE = 20
local STRIP_BADGE_SIZE = 18
local STRIP_BADGE_GAP = 3
local DIVIDER_HEIGHT = 9
local DIVIDER_HIT_EXTEND = 5
local PREVIEW_SPLIT_DEFAULT = 0.42
local PREVIEW_MIN_HEIGHT = 100
local SETTINGS_MIN_HEIGHT = 150
local EDIT_INSET = 6
local EDIT_HEADER_TOP_GAP = 6
local EDIT_HEADER_HEIGHT = 16
local EDIT_HEADER_GAP = 5
local EDIT_BOTTOM_INSET = 6

-- The preview/settings split is owner-adjustable via the drag divider below;
-- the chosen fraction persists per profile.
local function GetPreviewSplit()
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local fraction = db and db.configPreviewSplit
    if type(fraction) ~= "number" then
        return PREVIEW_SPLIT_DEFAULT, false
    end
    return math.max(0.1, math.min(fraction, 0.75)), true
end

local function SetPreviewSplit(fraction)
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if db then
        db.configPreviewSplit = fraction
    end
end

local function HideEntrySurfaces(col3)
    if col3.bsTabGroup then col3.bsTabGroup.frame:Hide() end
    if col3.bsPlaceholder then col3.bsPlaceholder:Hide() end
    if col3.multiSelectScroll then col3.multiSelectScroll.frame:Hide() end
end

-- The wide col3 layout hosts exactly one pinned preview at a time: the
-- buttons panel mirror or the Resources home's Layout & Order preview.
-- The split divider, persisted fraction, and height clamps below are
-- shared; each view registers its host frame and rebuild function while
-- its preview is showing, and clears the registration when it hides.
local function SetActiveWidePreview(col3, host, rebuild)
    col3._cdcActiveWideHost = host
    col3._cdcActiveWideRebuild = rebuild
end

local function ClearActiveWidePreview(col3, host)
    if col3._cdcActiveWideHost == host then
        col3._cdcActiveWideHost = nil
        col3._cdcActiveWideRebuild = nil
    end
end

local function RebuildActiveWidePreview(col3)
    local host = col3._cdcActiveWideHost
    local rebuild = col3._cdcActiveWideRebuild
    if host and rebuild then
        rebuild(host)
    end
end

-- The editing surface: the visually distinct, more opaque container below
-- the split divider. It frames the "Editing:" header, the add box, the
-- identity strip, and the settings surfaces so the workspace reads as two
-- labeled areas (Live Preview above the divider, Editing below it).
local function EnsureEditingSurface(col3)
    local surface = col3._cdcEditingSurface
    if surface then return surface end

    surface = CreateFrame("Frame", nil, col3.content, "BackdropTemplate")
    surface:SetBackdrop({
        bgFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeFile = "Interface\\BUTTONS\\WHITE8X8",
        edgeSize = 1,
    })
    surface:SetBackdropColor(0, 0, 0, 0.5)
    surface:SetBackdropBorderColor(1, 1, 1, 0.06)
    -- Same frame level as the column content so the fill draws behind the
    -- settings widgets (siblings created at content level + 1).
    surface:SetFrameLevel(col3.content:GetFrameLevel())

    local header = surface:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", surface, "TOPLEFT", EDIT_INSET, -EDIT_HEADER_TOP_GAP)
    header:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -EDIT_INSET, -EDIT_HEADER_TOP_GAP)
    header:SetHeight(EDIT_HEADER_HEIGHT)
    header:SetJustifyH("LEFT")
    header:SetWordWrap(false)
    surface._cdcHeader = header

    col3._cdcEditingSurface = surface
    return surface
end

-- Path shown in the editing header: the parent context dimmed, the leaf
-- (what the settings below actually edit) emphasized.
local function GetEditingHeaderPath()
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    if CS.castFramesEntrySelected then
        if CS.castFramesSelectedItem == "player" then
            return "Cast Bar & Unit Frames", "Player Frame"
        elseif CS.castFramesSelectedItem == "target" then
            return "Cast Bar & Unit Frames", "Target Frame"
        end
        return "Cast Bar & Unit Frames", "Cast Bar"
    end
    if CS.resourcesEntrySelected then
        local multiCount = 0
        for _ in pairs(CS.selectedCustomBars) do multiCount = multiCount + 1 end
        if multiCount >= 2 then
            return "Resources", "Custom Bars"
        end
        local settings = CooldownCompanion.GetResourceBarSettings
            and CooldownCompanion:GetResourceBarSettings()
        if CS.selectedResourcePowerType and ST._RBP
            and ST._RBP.IsResourceEditableInColumn4
            and ST._RBP.IsResourceEditableInColumn4(CS.selectedResourcePowerType, settings) then
            local powerNames = ST._RB and ST._RB.POWER_NAMES
            local resourceName = powerNames and powerNames[tonumber(CS.selectedResourcePowerType)]
            return "Resources", resourceName or "Resource"
        end
        if CS.selectedCustomBarId then
            local entry = ST._FindSelectedConfigCustomBar and ST._FindSelectedConfigCustomBar()
            if entry then
                return "Resources", entry.label or "Custom Bar"
            end
        end
        return nil, "Resources"
    end
    local group = db and CS.selectedGroup and db.groups[CS.selectedGroup]
    if not group then return nil, nil end
    local containerId = group.parentContainerId or CS.selectedContainer
    local container = containerId and db.groupContainers and db.groupContainers[containerId]
    return container and container.name, group.name or "Panel"
end

local function UpdateEditingHeader(col3)
    local header = EnsureEditingSurface(col3)._cdcHeader
    local parent, leaf = GetEditingHeaderPath()
    if not leaf then
        header:SetText("Editing")
        return
    end
    if parent then
        header:SetFormattedText("Editing: |cff9d9587%s \194\187 |r|cffffffff%s|r", parent, leaf)
    else
        header:SetFormattedText("Editing: |cffffffff%s|r", leaf)
    end
end

-- Shared hide for the divider and the editing surface: every path that
-- stops showing the preview/editing split must run this so the chrome
-- never lingers over a full-column surface.
local function HideEditingChrome(col3)
    if col3.buttonsSplitDivider then
        col3.buttonsSplitDivider:CancelDrag()
        col3.buttonsSplitDivider:Hide()
    end
    if col3._cdcEditingSurface then
        col3._cdcEditingSurface:Hide()
    end
end

-- Vertical space the editing surface's fixed chrome (header, add box,
-- identity strip, gaps, and insets) claims below the split divider before
-- the settings surface (shared by the divider drag and the height
-- computation below).
local function GetEditingOverhead(col3)
    local overhead = EDIT_HEADER_TOP_GAP + EDIT_HEADER_HEIGHT
        + PREVIEW_GAP + EDIT_BOTTOM_INSET
    local addBox = col3.buttonsAddBox
    if addBox and addBox.frame:IsShown() then
        overhead = overhead + EDIT_HEADER_GAP + ADD_BOX_HEIGHT
    end
    local strip = col3.buttonsIdentityStrip
    if strip and strip:IsShown() then
        overhead = overhead + PREVIEW_GAP + STRIP_HEIGHT
    end
    return overhead
end

-- Single source of truth for the preview host height: the persisted split
-- fraction, floored at the preview minimum (taller default floor when no
-- custom split is saved) and capped so the settings region below the
-- divider keeps its own minimum — the same clamp the divider drag applies.
local function ComputePreviewHostHeight(col3)
    local columnHeight = col3.content:GetHeight() or 0
    local fraction, custom = GetPreviewSplit()
    local minHeight = custom and PREVIEW_MIN_HEIGHT or 170
    local desired = math.max(minHeight, math.floor(columnHeight * fraction))
    local maxHeight = columnHeight - DIVIDER_HEIGHT
        - GetEditingOverhead(col3) - SETTINGS_MIN_HEIGHT
    -- Degenerate tiny column: the preview floor wins (the config window's
    -- own minimum height makes this a transient state at worst).
    if maxHeight < PREVIEW_MIN_HEIGHT then
        maxHeight = PREVIEW_MIN_HEIGHT
    end
    return math.min(desired, maxHeight)
end

-- Re-apply the persisted split against the CURRENT column height and
-- overhead. Called from LayoutColumns (which runs on every window resize)
-- and as the refresh pass's final step — the preview builds before the add
-- box and identity strip settle their visibility, so the first computation
-- can run against stale overhead.
local function ReapplyPanelPreviewSplit()
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3._cdcActiveWideHost
    if not (host and host:IsShown()) then return end
    if (col3.content:GetHeight() or 0) <= 0 then return end
    local newHeight = ComputePreviewHostHeight(col3)
    local heightChanged = math.abs((host:GetHeight() or 0) - newHeight) >= 0.5
    -- The preview's scale-to-fit reads the host width too, so a width-only
    -- window resize still needs a rebuild even when the split height held.
    local width = host:GetWidth() or 0
    local widthChanged = math.abs((host._cdcLastLayoutWidth or 0) - width) >= 0.5
    if not (heightChanged or widthChanged) then return end
    if heightChanged then
        host:SetHeight(newHeight)
    end
    host._cdcLastLayoutWidth = width
    RebuildActiveWidePreview(col3)
end

-- Draggable divider between the pinned preview and the editing surface:
-- drag to rebalance the split, double-click to reset to the default. The
-- fraction persists per profile.
local function EnsurePreviewDivider(col3)
    local divider = col3.buttonsSplitDivider
    if divider then return divider end

    -- A Button, not a Frame: OnDoubleClick is a Button-only script handler.
    divider = CreateFrame("Button", nil, col3.content)
    divider:SetHeight(DIVIDER_HEIGHT)
    divider:EnableMouse(true)
    -- The visual bar stays slim; the invisible drag target extends a few
    -- pixels above and below it.
    divider:SetHitRectInsets(0, 0, -DIVIDER_HIT_EXTEND, -DIVIDER_HIT_EXTEND)

    local line = divider:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("LEFT", divider, "LEFT", 0, 0)
    line:SetPoint("RIGHT", divider, "RIGHT", 0, 0)

    local grip = divider:CreateTexture(nil, "OVERLAY")
    grip:SetColorTexture(1, 1, 1, 0.2)
    grip:SetSize(24, 2)
    grip:SetPoint("CENTER")
    divider._grip = grip

    local function SetHot(hot)
        if hot then
            grip:SetColorTexture(1, 0.82, 0, 0.7)
        else
            grip:SetColorTexture(1, 1, 1, 0.2)
        end
    end

    -- View switches and config close can hide the divider mid-drag; the
    -- OnUpdate persists on hidden frames and would resume on re-show with
    -- no mouse button down, so every hide path must cancel the drag.
    function divider:CancelDrag()
        if not self._dragging then return end
        self._dragging = false
        self:SetScript("OnUpdate", nil)
        SetHot(false)
    end

    divider:SetScript("OnEnter", function(self)
        SetHot(true)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Drag to resize the preview")
        GameTooltip:AddLine("Double-click to reset", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    divider:SetScript("OnLeave", function(self)
        if not self._dragging then SetHot(false) end
        GameTooltip:Hide()
    end)

    divider:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        local host = col3._cdcActiveWideHost
        if not (host and host:IsShown()) then return end
        self._dragging = true
        self._rebuildElapsed = 0
        SetHot(true)
        self:SetScript("OnUpdate", function(dividerSelf, elapsed)
            local contentTop = col3.content:GetTop()
            local columnHeight = col3.content:GetHeight() or 0
            if not contentTop or columnHeight <= 0 then return end
            local _, cursorY = GetCursorPosition()
            cursorY = cursorY / col3.content:GetEffectiveScale()
            local maxHeight = columnHeight - DIVIDER_HEIGHT
                - GetEditingOverhead(col3) - SETTINGS_MIN_HEIGHT
            if maxHeight < PREVIEW_MIN_HEIGHT then return end
            local desired = (contentTop - cursorY) - (DIVIDER_HEIGHT / 2)
            desired = math.max(PREVIEW_MIN_HEIGHT, math.min(desired, maxHeight))
            host:SetHeight(desired)
            -- Rescale the preview as the host resizes, throttled.
            dividerSelf._rebuildElapsed = dividerSelf._rebuildElapsed + elapsed
            if dividerSelf._rebuildElapsed >= 0.08 then
                dividerSelf._rebuildElapsed = 0
                RebuildActiveWidePreview(col3)
            end
        end)
    end)
    divider:SetScript("OnMouseUp", function(self)
        if not self._dragging then return end
        self:CancelDrag()
        local host = col3._cdcActiveWideHost
        local columnHeight = col3.content:GetHeight() or 0
        if host and columnHeight > 0 then
            SetPreviewSplit(host:GetHeight() / columnHeight)
            RebuildActiveWidePreview(col3)
        end
    end)
    divider:SetScript("OnDoubleClick", function(self)
        self:CancelDrag()
        SetPreviewSplit(nil)
        local host = col3._cdcActiveWideHost
        if host and (col3.content:GetHeight() or 0) > 0 then
            host:SetHeight(ComputePreviewHostHeight(col3))
            RebuildActiveWidePreview(col3)
        end
    end)

    col3.buttonsSplitDivider = divider
    return divider
end

-- Settings surfaces anchor inside the editing surface below the split
-- divider (which sits directly under the pinned preview), beneath the
-- editing header, the add box, and the identity strip when shown; they
-- fill the whole column when no preview is active.
local function AnchorButtonsContentFrame(col3, frame)
    frame:ClearAllPoints()
    local previewHost = col3._cdcActiveWideHost
    if previewHost and previewHost:IsShown() then
        local divider = EnsurePreviewDivider(col3)
        divider:ClearAllPoints()
        divider:SetPoint("TOPLEFT", previewHost, "BOTTOMLEFT", 0, 0)
        divider:SetPoint("TOPRIGHT", previewHost, "BOTTOMRIGHT", 0, 0)
        divider:Show()

        local surface = EnsureEditingSurface(col3)
        surface:ClearAllPoints()
        surface:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, 0)
        surface:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
        surface:Show()
        UpdateEditingHeader(col3)

        local topAnchor = surface._cdcHeader
        local strip = col3.buttonsIdentityStrip
        local addBox = col3.buttonsAddBox
        if strip and strip:IsShown() then
            topAnchor = strip
        elseif addBox and addBox.frame:IsShown() then
            topAnchor = addBox.frame
        end
        frame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -PREVIEW_GAP)
        frame:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -EDIT_INSET, EDIT_BOTTOM_INSET)
    else
        HideEditingChrome(col3)
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
        ClearActiveWidePreview(col3, host)
        host:Hide()
        if host._cdcDropOverlay then
            host._cdcDropOverlay:Hide()
        end
        if ST._ReleaseAnchorAwarePanelPreview then
            ST._ReleaseAnchorAwarePanelPreview(host)
        elseif ST._ReleaseButtonPanelPreview then
            ST._ReleaseButtonPanelPreview(host)
        end
    end
    if col3.buttonsAddBox then
        col3.buttonsAddBox.frame:Hide()
    end
    if col3.buttonsIdentityStrip then
        col3.buttonsIdentityStrip:Hide()
    end
    HideEditingChrome(col3)
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
    -- Anchor-aware build: the unified preview (real mirror + attached bar
    -- lanes) on the anchor panel, the plain mirror everywhere else.
    local function BuildPreview(hostFrame)
        if not CS.selectedGroup then return end
        if ST._BuildAnchorAwarePanelPreview then
            ST._BuildAnchorAwarePanelPreview(hostFrame, CS.selectedGroup)
        elseif ST._BuildButtonPanelPreview then
            ST._BuildButtonPanelPreview(hostFrame, CS.selectedGroup)
        end
    end
    SetActiveWidePreview(col3, host, BuildPreview)
    host:SetHeight(ComputePreviewHostHeight(col3))
    host:Show()
    BuildPreview(host)
    UpdatePreviewDropOverlay()
end

-- Add-entry box inside the editing surface (under its header), scoped to
-- the selected panel. Reuses the same TryAdd/autocomplete plumbing as the
-- column 2 inline add.
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
        -- The wide box always targets the selected panel; a stale column 2
        -- inline-add target left over from browse mode must not win.
        CS.addingToPanelId = nil
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
            -- This box is persistent (not rebuilt from CS.newInput like the
            -- column 2 inline box), so a successful pick must clear it here
            -- or the stale text re-adds on the next Enter press.
            CS.ShowAutocompleteResults(results, widget, function(entry)
                -- Explicit target: the shared select handler prefers
                -- CS.addingToPanelId, which never belongs to this box.
                CS.addingToPanelId = nil
                if ST._OnAutocompleteSelect(entry) then
                    widget:SetText("")
                    instructions:Show()
                end
            end, {
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
    local header = EnsureEditingSurface(col3)._cdcHeader
    addBox.frame:ClearAllPoints()
    addBox.frame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -EDIT_HEADER_GAP)
    addBox.frame:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -EDIT_HEADER_GAP)
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

-- Async adds (uncached item IDs) complete after the add box's Enter
-- handler already returned false; the loader calls this on success so the
-- persistent box doesn't keep the added item's text armed for a duplicate
-- Enter. The text guard skips the clear if the user has typed since; a
-- hidden box still clears (its text would otherwise re-arm on re-show).
local function ClearWideAddBoxAfterAdd(originalInput)
    local col3 = CS.configFrame and CS.configFrame.col3
    local addBox = col3 and col3.buttonsAddBox
    if not addBox then return end
    if originalInput and addBox:GetText() ~= originalInput then return end
    addBox:SetText("")
    if addBox._cdcInstructions then
        addBox._cdcInstructions:Show()
    end
end

local function EnsureIdentityStrip(col3)
    local strip = col3.buttonsIdentityStrip
    if strip then return strip end

    strip = CreateFrame("Frame", nil, col3.content)
    strip:SetHeight(STRIP_HEIGHT)

    strip.name = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    strip.name:SetJustifyH("LEFT")
    strip.name:SetWordWrap(false)

    strip.tag = strip:CreateFontString(nil, "OVERLAY", "GameFontNormalMed3")
    strip.tag:SetTextColor(0.5, 0.5, 0.5)

    -- No bottom separator line: the split divider always renders directly
    -- beneath the strip and carries the single separator line.

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

-- Context strip between the add box and the settings surfaces: shown only
-- for a selected entry or attached bar, where it carries identity, tracking
-- kind, and the status badges the retired column 2 entry rows used to show.
-- The panel itself is already named by the Editing header above.
local function UpdateIdentityStrip(col3)
    local group = CS.selectedGroup and CooldownCompanion.db.profile.groups[CS.selectedGroup]
    local icon, name, badgeStatus, kindText
    if group then
        local multiCount = 0
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
        if CS.unifiedBarKind then
            -- Unified anchor preview: name the selected attached bar.
            if CS.unifiedBarKind == "resource" and CS.selectedResourcePowerType then
                local powerNames = ST._RB and ST._RB.POWER_NAMES
                name = powerNames and powerNames[tonumber(CS.selectedResourcePowerType)]
                    or "Resource"
                kindText = "Resource"
            elseif CS.unifiedBarKind == "custom" then
                local entry = ST._FindSelectedConfigCustomBar and ST._FindSelectedConfigCustomBar()
                name = (entry and entry.label) or "Custom Bar"
                kindText = "Custom Bar"
            elseif CS.unifiedBarKind == "cast" then
                name = "Cast Bar"
            end
        elseif multiCount >= 2 then
            -- Entry multi-select surface lists its members itself.
        elseif CS.selectedRotationAssistantEntry == true
            and CooldownCompanion:IsRotationAssistantGroup(group) then
            local spellID = CooldownCompanion:GetRotationAssistantActionSpellID()
            icon = CooldownCompanion:GetRotationAssistantFallbackIcon(spellID)
            name = ST.ROTATION_ASSISTANT_NAME
        elseif CS.selectedButton and group.buttons[CS.selectedButton] then
            local buttonData = group.buttons[CS.selectedButton]
            icon = ST._GetLayoutPreviewIcon and ST._GetLayoutPreviewIcon(buttonData)
            -- Undecorated name: the decoration marks and tracking kind live
            -- in the preview icons' hover tooltip instead.
            name = ST._GetConfigEntryDisplayName
                and ST._GetConfigEntryDisplayName(buttonData)
                or buttonData.name
            -- Same addedAs fallback the name decorations use.
            if buttonData.type == "spell" then
                local addedAs = buttonData.addedAs
                if addedAs ~= "spell" and addedAs ~= "aura" then
                    addedAs = buttonData.isPassive and "aura" or "spell"
                end
                kindText = addedAs == "aura" and "Aura" or "Spell"
            end
            badgeStatus = ST._CollectEntryStatus and ST._CollectEntryStatus(buttonData, group)
        end
    end

    local strip = col3.buttonsIdentityStrip
    if not name then
        if strip then strip:Hide() end
        return
    end
    strip = EnsureIdentityStrip(col3)

    -- Inline the entry icon so it aligns (and truncates) with the name;
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

    -- Tracking-kind helper text sits with the badge cluster on the right.
    if kindText then
        strip.tag:SetText("(" .. kindText .. ")")
        strip.tag:ClearAllPoints()
        if rightAnchor then
            strip.tag:SetPoint("RIGHT", rightAnchor, "LEFT", -STRIP_BADGE_GAP - 3, 0)
        else
            strip.tag:SetPoint("RIGHT", strip, "RIGHT", -2, 0)
        end
        strip.tag:Show()
        rightAnchor = strip.tag
    else
        strip.tag:Hide()
    end

    -- Keep the contextual identity left-aligned while reserving room for
    -- the tracking tag and status badges on the right.
    strip.name:SetText(name)
    strip.name:ClearAllPoints()
    strip.name:SetPoint("LEFT", strip, "LEFT", EDIT_INSET, 0)
    if rightAnchor then
        strip.name:SetPoint("RIGHT", rightAnchor, "LEFT", -STRIP_BADGE_GAP - 5, 0)
    else
        strip.name:SetPoint("RIGHT", strip, "RIGHT", -EDIT_INSET, 0)
    end

    local addBox = col3.buttonsAddBox
    local top = (addBox and addBox.frame:IsShown()) and addBox.frame
        or EnsureEditingSurface(col3)._cdcHeader
    strip:ClearAllPoints()
    strip:SetPoint("TOPLEFT", top, "BOTTOMLEFT", 0, -PREVIEW_GAP)
    strip:SetPoint("TOPRIGHT", top, "BOTTOMRIGHT", 0, -PREVIEW_GAP)
    strip:Show()
end

-- Validate the unified bar selection before showing its settings: clears
-- it (returning nil) when the panel stopped being the anchor target, the
-- bar was deleted, or its module was disabled.
local function GetValidatedUnifiedBarKind()
    local kind = CS.unifiedBarKind
    if not kind then return nil end
    if not (ST._ShouldUseUnifiedAnchorPreview
        and ST._ShouldUseUnifiedAnchorPreview(CS.selectedGroup)) then
        CS.unifiedBarKind = nil
        return nil
    end
    if kind == "resource" then
        local settings = CooldownCompanion:GetResourceBarSettings()
        local RBP = ST._RBP
        if not (CS.selectedResourcePowerType and RBP and RBP.IsResourceEditableInColumn4
            and RBP.IsResourceEditableInColumn4(CS.selectedResourcePowerType, settings)) then
            CS.unifiedBarKind = nil
            return nil
        end
    elseif kind == "custom" then
        if not (CS.selectedCustomBarId and ST._FindSelectedConfigCustomBar
            and ST._FindSelectedConfigCustomBar()) then
            CS.unifiedBarKind = nil
            return nil
        end
    elseif kind == "cast" then
        local cb = CooldownCompanion:GetCastBarSettings()
        local independent = cb and (cb.independentAnchorEnabled == true or cb.independentAnchorEnabled == 1)
        if not (cb and cb.enabled == true and not independent) then
            CS.unifiedBarKind = nil
            return nil
        end
    else
        CS.unifiedBarKind = nil
        return nil
    end
    return kind
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
    if ST._HideResourcesWideSurfaces then ST._HideResourcesWideSurfaces(col3) end

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

    -- Other Class browsing shares this merged column but skips the pinned
    -- preview cluster: browsed panels render live in the world, and column
    -- 2 keeps its entry rows there.
    local browse = CS.otherClassLibraryActive

    -- Attached bar selected in the unified anchor preview: that bar's
    -- settings own the settings area
    local unifiedBarKind = not browse and GetValidatedUnifiedBarKind() or nil
    if unifiedBarKind then
        HideEntrySurfaces(col3)
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
        UpdatePanelPreview(col3)
        UpdateAddBox(col3)
        UpdateIdentityStrip(col3)
        ReapplyPanelPreviewSplit()
        local shown = false
        if unifiedBarKind == "resource" then
            shown = ST._ShowResourceSettingsSurface
                and ST._ShowResourceSettingsSurface(col3) == true
        elseif unifiedBarKind == "custom" then
            local entry = ST._FindSelectedConfigCustomBar and ST._FindSelectedConfigCustomBar()
            if entry and ST._ShowCustomBarDetailSurface then
                ST._ShowCustomBarDetailSurface(col3, entry)
                shown = true
            end
        else
            if ST._ShowCastBarSettingsSurface then
                ST._ShowCastBarSettingsSurface(col3)
                shown = true
            end
        end
        if shown then
            return
        end
        -- The surface didn't materialize (transient state); clear the bar
        -- selection and run a clean pass through the normal branches.
        CS.unifiedBarKind = nil
        return RefreshButtonsWideColumn()
    end

    -- Entry selected: the entry settings surfaces own the settings area
    if IsEntrySelectionActive() then
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
        if browse then
            HidePanelPreview(col3)
        else
            UpdatePanelPreview(col3)
            UpdateAddBox(col3)
            UpdateIdentityStrip(col3)
            -- Final height pass: the add box and strip just settled their
            -- visibility, which feeds the settings-minimum clamp.
            ReapplyPanelPreviewSplit()
        end
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
    if browse then
        HidePanelPreview(col3)
    else
        UpdatePanelPreview(col3)
        UpdateAddBox(col3)
        UpdateIdentityStrip(col3)
        -- Final height pass (see the entry branch above).
        ReapplyPanelPreviewSplit()
    end

    local host = col3.groupSettingsHost
    if not host then
        host = CreateFrame("Frame", nil, col3.content)
        col3.groupSettingsHost = host
    end
    AnchorButtonsContentFrame(col3, host)
    host:Show()
    ST._RefreshGroupSettingsHost(host)
end

-- The mirror owns a panel's config previews only while the wide buttons
-- view is showing that panel's pinned preview. Anywhere else - Other
-- Class browsing being the reachable case, where browsed panels render
-- live in the world - the live buttons are the only preview surface.
local function IsPanelMirrorPreviewActive(groupId)
    if not (ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()) then return false end
    return groupId ~= nil and groupId == CS.selectedGroup
end

-- Rebuild just the pinned mirror (e.g. after a preview toggle flips, or
-- from UpdateGroupStyle so style edits reflect immediately) without a full
-- config refresh. An optional groupId scopes the rebuild: updates to a
-- panel other than the mirrored one are skipped.
local function RefreshButtonsPreviewMirror(groupId)
    if not (ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()) then return end
    if groupId and groupId ~= CS.selectedGroup then return end
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.buttonsPreviewHost
    if host and host:IsShown() and CS.selectedGroup then
        if ST._BuildAnchorAwarePanelPreview then
            ST._BuildAnchorAwarePanelPreview(host, CS.selectedGroup)
        elseif ST._BuildButtonPanelPreview then
            ST._BuildButtonPanelPreview(host, CS.selectedGroup)
        end
        -- The strip shares the mirror's data (custom name, status badges) -
        -- keep it in step with every targeted rebuild. It handles its own
        -- visibility, so no shown-state gate is needed.
        UpdateIdentityStrip(col3)
    end
end

ST._RefreshButtonsWideColumn = RefreshButtonsWideColumn
ST._AnchorButtonsContentFrame = AnchorButtonsContentFrame
-- Shared wide-preview plumbing (also used by the Resources wide column):
-- host registration for the split divider, the height computation, and
-- the persisted-split reapply.
ST._SetActiveWidePreview = SetActiveWidePreview
ST._ClearActiveWidePreview = ClearActiveWidePreview
ST._ComputeWidePreviewHostHeight = ComputePreviewHostHeight
ST._RefreshButtonsPreviewMirror = RefreshButtonsPreviewMirror
ST._IsPanelMirrorPreviewActive = IsPanelMirrorPreviewActive
ST._ReapplyPanelPreviewSplit = ReapplyPanelPreviewSplit
ST._ClearWideAddBoxAfterAdd = ClearWideAddBoxAfterAdd
-- Divider + editing-surface hide for view branches that release the split
-- while their own preview host holds it (Resources/cast homes).
ST._HideWideEditingChrome = HideEditingChrome
-- Shared teardown for view switches away from the buttons view (resources,
-- cast frames, talent picker, config close): hides the preview surfaces AND
-- releases the preview so its conditional ticker stops and override
-- targeting disarms. Transient same-view hides must NOT use this - the
-- following rebuild pass re-shows the preview and targeting should survive.
ST._HideButtonsPanelPreviewSurfaces = HidePanelPreview
