--[[
    CooldownCompanion - Config/ButtonsWideColumn
    Workspace for the plain buttons view and Other Class browsing:
    hosts the entry settings surfaces (bsTabGroup, entry multi-select),
    the panel batch actions, and the group-side settings surfaces (via
    GroupSettingsHost) in one unified surface. It frames two labeled areas:
    the pinned Live Preview above the split divider (the column title names
    it) and the editing surface
    below it (the "Editing:" path and selected-entry context on one line,
    followed by the add box and settings).
    Browsing skips the pinned preview cluster
    (panels render live in the world).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")
local CleanRecycledEntry = ST._CleanRecycledEntry
local ApplyConfigRowIcon = ST._ApplyConfigRowIcon
local StartDragTracking = ST._StartDragTracking
local GetScaledCursorPosition = ST._GetScaledCursorPosition

local PREVIEW_GAP = 4
local ADD_BOX_HEIGHT = 26
local EDIT_CONTEXT_ICON_SIZE = 16
local EDIT_CONTEXT_BADGE_SIZE = 16
local EDIT_CONTEXT_BADGE_GAP = 3
local DIVIDER_HEIGHT = 9
local DIVIDER_HIT_EXTEND = 5
local PREVIEW_SPLIT_DEFAULT = 0.42
local PREVIEW_MIN_HEIGHT = 100
local SETTINGS_MIN_HEIGHT = 150
local EDIT_INSET = 6
local EDIT_HEADER_TOP_GAP = 6
local EDIT_HEADER_HEIGHT = 18
local EDIT_HEADER_GAP = 5
local EDIT_BOTTOM_INSET = 6
local EDIT_CHIPS_HEIGHT = 18
local EDIT_CHIPS_GAP = 4
local EDIT_HEADER_ACTION_GAP = 3

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

-- Structural container below the split divider. The divider itself separates
-- Live Preview from Editing; this frame only hosts the Editing path (including
-- any selected entry context), the add box, and the settings surfaces.
local function EnsureEditingSurface(col3)
    local surface = col3._cdcEditingSurface
    if surface then return surface end

    surface = CreateFrame("Frame", nil, col3.content)
    -- Keep the structural host at content level; its child header and
    -- badges then sit alongside the sibling settings widgets.
    surface:SetFrameLevel(col3.content:GetFrameLevel())

    local headerLine = CreateFrame("Frame", nil, surface)
    headerLine:SetPoint("TOPLEFT", surface, "TOPLEFT", EDIT_INSET, -EDIT_HEADER_TOP_GAP)
    headerLine:SetPoint("TOPRIGHT", surface, "TOPRIGHT", -EDIT_INSET, -EDIT_HEADER_TOP_GAP)
    headerLine:SetHeight(EDIT_HEADER_HEIGHT)
    headerLine.badges = {}

    local text = headerLine:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", headerLine, "LEFT", 0, 0)
    text:SetPoint("RIGHT", headerLine, "RIGHT", 0, 0)
    text:SetHeight(EDIT_HEADER_HEIGHT)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    headerLine.text = text
    surface._cdcHeader = headerLine

    col3._cdcEditingSurface = surface
    return surface
end

local function GetActiveEditingAddBox(col3)
    local alternate = col3._cdcAlternateEditingAddBox
    if alternate and alternate.frame and alternate.frame:IsShown() then
        return alternate
    end
    local panelAddBox = col3.buttonsAddBox
    if panelAddBox and panelAddBox.frame and panelAddBox.frame:IsShown() then
        return panelAddBox
    end
    return nil
end

local function SetWideEditingAddBox(col3, widget)
    local previous = col3._cdcAlternateEditingAddBox
    if previous and previous ~= widget and previous.frame then
        previous.frame:Hide()
    end
    col3._cdcAlternateEditingAddBox = widget
    if widget and widget.frame then
        widget.frame._cdcEditingHeight = widget.frame._cdcEditingHeight or ADD_BOX_HEIGHT
        widget.frame:Show()
    end
end

local function SetWideEditingHeaderActions(col3, actions)
    local headerLine = EnsureEditingSurface(col3)._cdcHeader
    headerLine.actionButtons = headerLine.actionButtons or {}
    for index, action in ipairs(actions or {}) do
        local button = headerLine.actionButtons[index]
        if not button then
            button = CreateFrame("Button", nil, headerLine, "UIPanelButtonTemplate")
            button:SetHeight(18)
            button:SetNormalFontObject(GameFontNormalSmall)
            button:SetHighlightFontObject(GameFontHighlightSmall)
            headerLine.actionButtons[index] = button
        end
        button:SetText(action.text or "")
        button:SetWidth(action.width or 64)
        button:SetScript("OnClick", action.onClick)
        button:Show()
    end
    for index = #(actions or {}) + 1, #headerLine.actionButtons do
        headerLine.actionButtons[index]:Hide()
    end
end

local function LayoutWideEditingChips(frame)
    if not (frame and frame:IsShown()) then return end
    local label = frame._cdcPrefix
    local buttons = frame._cdcButtons or {}
    label:ClearAllPoints()
    label:SetPoint("LEFT", frame, "LEFT", 0, 0)

    local left = label
    for _, button in ipairs(buttons) do
        if button:IsShown() then
            button:ClearAllPoints()
            button:SetPoint("LEFT", left, "RIGHT", 0, 0)
            left = button
        end
    end
end

local function SetWideEditingChips(col3, prefix, items)
    local surface = EnsureEditingSurface(col3)
    local frame = col3._cdcEditingChips
    if not frame then
        frame = CreateFrame("Frame", nil, surface)
        frame:SetHeight(EDIT_CHIPS_HEIGHT)
        frame:SetClipsChildren(true)
        frame._cdcPrefix = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        frame._cdcPrefix:SetJustifyH("LEFT")
        frame._cdcButtons = {}
        frame:SetScript("OnSizeChanged", LayoutWideEditingChips)
        col3._cdcEditingChips = frame
    end

    if not items or #items == 0 then
        frame:Hide()
        return
    end

    frame._cdcPrefix:SetText((prefix or "Not currently shown:") .. " ")
    for index, item in ipairs(items) do
        local captured = item
        local button = frame._cdcButtons[index]
        if not button then
            button = CreateFrame("Button", nil, frame)
            button:RegisterForClicks("AnyUp")
            button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            button.text:SetAllPoints()
            button.text:SetJustifyH("LEFT")
            button:SetScript("OnEnter", function(self)
                self.text:SetTextColor(1, 0.82, 0)
                if self._cdcTooltip then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self._cdcTooltip, 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", function(self)
                local color = self._cdcSelected and self._cdcSelectedColor or self._cdcNormalColor
                self.text:SetTextColor(color[1], color[2], color[3])
                GameTooltip:Hide()
            end)
            frame._cdcButtons[index] = button
        end
        button.text:SetText((index > 1 and "  \194\183  " or "") .. tostring(item.label or ""))
        button:SetSize(math.ceil(button.text:GetStringWidth()) + 2, EDIT_CHIPS_HEIGHT)
        button._cdcSelected = item.selected == true
        button._cdcNormalColor = { 0.70, 0.68, 0.64 }
        button._cdcSelectedColor = { 1, 1, 1 }
        button._cdcTooltip = item.tooltip
        local color = button._cdcSelected and button._cdcSelectedColor or button._cdcNormalColor
        button.text:SetTextColor(color[1], color[2], color[3])
        button:SetScript("OnClick", function(_, mouseButton)
            if mouseButton == "RightButton" and captured.onRightClick then
                captured.onRightClick()
            elseif mouseButton == "LeftButton" and captured.onClick then
                captured.onClick()
            end
        end)
        button:Show()
    end
    for index = #items + 1, #frame._cdcButtons do
        frame._cdcButtons[index]:Hide()
    end
    frame:Show()
    LayoutWideEditingChips(frame)
end

local function ClearWideEditingExtras(col3)
    local alternate = col3._cdcAlternateEditingAddBox
    if alternate and alternate.frame then
        alternate.frame:Hide()
    end
    col3._cdcAlternateEditingAddBox = nil
    if col3._cdcEditingChips then
        col3._cdcEditingChips:Hide()
    end
    SetWideEditingHeaderActions(col3, nil)
end

local function AcquireEditingHeaderBadge(headerLine, index)
    local badge = headerLine.badges[index]
    if badge then return badge end

    badge = CreateFrame("Frame", nil, headerLine)
    badge:SetSize(EDIT_CONTEXT_BADGE_SIZE, EDIT_CONTEXT_BADGE_SIZE)
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
    headerLine.badges[index] = badge
    return badge
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
            and ST._RBP.IsResourceEditableInColumn4(CS.selectedResourcePowerType, settings, true) then
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
    local headerLine = EnsureEditingSurface(col3)._cdcHeader
    local header = headerLine.text
    local parent, leaf = GetEditingHeaderPath()
    local context = col3._cdcEditingContext

    local shown = 0
    local rightAnchor
    local actionButtons = headerLine.actionButtons or {}
    for index = #actionButtons, 1, -1 do
        local button = actionButtons[index]
        if button:IsShown() then
            button:ClearAllPoints()
            if rightAnchor then
                button:SetPoint("RIGHT", rightAnchor, "LEFT", -EDIT_HEADER_ACTION_GAP, 0)
            else
                button:SetPoint("RIGHT", headerLine, "RIGHT", 0, 0)
            end
            rightAnchor = button
        end
    end
    local badgeStatus = context and context.badgeStatus
    if badgeStatus and ST._EntryStatusBadges then
        for _, desc in ipairs(ST._EntryStatusBadges) do
            if badgeStatus[desc.key] then
                shown = shown + 1
                local badge = AcquireEditingHeaderBadge(headerLine, shown)
                badge.icon:SetAtlas(desc.atlas, false)
                badge._cdcLabel = (desc.key == "warn" and badgeStatus.loadBlocked)
                    and "Hidden by load conditions" or desc.label
                badge:ClearAllPoints()
                if rightAnchor then
                    badge:SetPoint("RIGHT", rightAnchor, "LEFT", -EDIT_CONTEXT_BADGE_GAP, 0)
                else
                    badge:SetPoint("RIGHT", headerLine, "RIGHT", 0, 0)
                end
                badge:Show()
                rightAnchor = badge
            end
        end
    end
    for i = shown + 1, #headerLine.badges do
        headerLine.badges[i]:Hide()
    end

    header:ClearAllPoints()
    header:SetPoint("LEFT", headerLine, "LEFT", 0, 0)
    if rightAnchor then
        header:SetPoint("RIGHT", rightAnchor, "LEFT", -EDIT_CONTEXT_BADGE_GAP - 3, 0)
    else
        header:SetPoint("RIGHT", headerLine, "RIGHT", 0, 0)
    end

    if not leaf then
        header:SetText("Editing")
        return
    end

    if context and context.name then
        local contextName = context.name
        if context.icon then
            contextName = "|T" .. context.icon .. ":" .. EDIT_CONTEXT_ICON_SIZE
                .. ":" .. EDIT_CONTEXT_ICON_SIZE .. ":0:0:64:64:5:59:5:59|t " .. contextName
        end
        if context.kindText then
            contextName = contextName .. " |cff7d7566(" .. context.kindText .. ")|r"
        end
        local path = parent and (parent .. " \194\187 " .. leaf) or leaf
        header:SetFormattedText("Editing: |cff9d9587%s \194\187 |r|cffffffff%s|r", path, contextName)
    elseif parent then
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

-- Vertical space the editing surface's fixed chrome (header, add box, gaps,
-- and insets) claims below the split divider before the settings surface
-- (shared by the divider drag and the height computation below).
local function GetEditingOverhead(col3)
    local overhead = EDIT_HEADER_TOP_GAP + EDIT_HEADER_HEIGHT
        + PREVIEW_GAP + EDIT_BOTTOM_INSET
    local addBox = GetActiveEditingAddBox(col3)
    if addBox then
        overhead = overhead + EDIT_HEADER_GAP
            + (addBox.frame._cdcEditingHeight or ADD_BOX_HEIGHT)
    end
    local chips = col3._cdcEditingChips
    if chips and chips:IsShown() then
        overhead = overhead + EDIT_CHIPS_GAP + EDIT_CHIPS_HEIGHT
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
-- box settles its visibility, so the first computation can run against
-- stale overhead.
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

    local leftLine = divider:CreateTexture(nil, "ARTWORK")
    leftLine:SetColorTexture(0.52, 0.44, 0.34, 0.42)
    leftLine:SetHeight(1)
    leftLine:SetPoint("LEFT", divider, "LEFT", 0, 0)
    leftLine:SetPoint("RIGHT", divider, "CENTER", -11, 0)

    local rightLine = divider:CreateTexture(nil, "ARTWORK")
    rightLine:SetColorTexture(0.52, 0.44, 0.34, 0.42)
    rightLine:SetHeight(1)
    rightLine:SetPoint("LEFT", divider, "CENTER", 11, 0)
    rightLine:SetPoint("RIGHT", divider, "RIGHT", 0, 0)

    local diamond = divider:CreateTexture(nil, "OVERLAY")
    diamond:SetColorTexture(0.62, 0.48, 0.28, 0.72)
    diamond:SetSize(7, 7)
    diamond:SetPoint("CENTER")
    diamond:SetRotation(math.rad(45))

    local diamondCore = divider:CreateTexture(nil, "OVERLAY", nil, 1)
    diamondCore:SetColorTexture(0.12, 0.08, 0.04, 0.95)
    diamondCore:SetSize(3, 3)
    diamondCore:SetPoint("CENTER")
    diamondCore:SetRotation(math.rad(45))
    divider._grip = diamond

    local function SetHot(hot)
        if hot then
            leftLine:SetColorTexture(0.85, 0.62, 0.22, 0.62)
            rightLine:SetColorTexture(0.85, 0.62, 0.22, 0.62)
            diamond:SetColorTexture(1, 0.72, 0.18, 0.92)
        else
            leftLine:SetColorTexture(0.52, 0.44, 0.34, 0.42)
            rightLine:SetColorTexture(0.52, 0.44, 0.34, 0.42)
            diamond:SetColorTexture(0.62, 0.48, 0.28, 0.72)
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
-- editing header and add box; they fill the whole column when no preview
-- is active.
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
        local addBox = GetActiveEditingAddBox(col3)
        if addBox then
            addBox.frame:ClearAllPoints()
            addBox.frame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -EDIT_HEADER_GAP)
            addBox.frame:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -EDIT_HEADER_GAP)
            addBox.frame:SetHeight(addBox.frame._cdcEditingHeight or ADD_BOX_HEIGHT)
            topAnchor = addBox.frame
        end
        local chips = col3._cdcEditingChips
        if chips and chips:IsShown() then
            chips:SetParent(surface)
            chips:ClearAllPoints()
            chips:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -EDIT_CHIPS_GAP)
            chips:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -EDIT_CHIPS_GAP)
            chips:SetHeight(EDIT_CHIPS_HEIGHT)
            topAnchor = chips
        end
        frame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -PREVIEW_GAP)
        frame:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -EDIT_INSET, EDIT_BOTTOM_INSET)
    else
        local addBox = GetActiveEditingAddBox(col3)
        local chips = col3._cdcEditingChips
        local hasChips = chips and chips:IsShown()
        if addBox or hasChips then
            if col3.buttonsSplitDivider then
                col3.buttonsSplitDivider:CancelDrag()
                col3.buttonsSplitDivider:Hide()
            end
            local surface = EnsureEditingSurface(col3)
            surface:ClearAllPoints()
            surface:SetAllPoints(col3.content)
            surface:Show()
            UpdateEditingHeader(col3)

            local topAnchor = surface._cdcHeader
            if addBox then
                addBox.frame:ClearAllPoints()
                addBox.frame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -EDIT_HEADER_GAP)
                addBox.frame:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -EDIT_HEADER_GAP)
                addBox.frame:SetHeight(addBox.frame._cdcEditingHeight or ADD_BOX_HEIGHT)
                topAnchor = addBox.frame
            end
            if hasChips then
                chips:SetParent(surface)
                chips:ClearAllPoints()
                chips:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -EDIT_CHIPS_GAP)
                chips:SetPoint("TOPRIGHT", topAnchor, "BOTTOMRIGHT", 0, -EDIT_CHIPS_GAP)
                chips:SetHeight(EDIT_CHIPS_HEIGHT)
                topAnchor = chips
            end
            frame:SetPoint("TOPLEFT", topAnchor, "BOTTOMLEFT", 0, -PREVIEW_GAP)
            frame:SetPoint("BOTTOMRIGHT", surface, "BOTTOMRIGHT", -EDIT_INSET, EDIT_BOTTOM_INSET)
        else
            HideEditingChrome(col3)
            frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
            frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
        end
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
-- cursor, mirroring the Navigator panel drop overlays. TryReceiveCursorDrop
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
    col3._cdcEditingContext = nil
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
-- shared inline add.
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
        -- The workspace box always targets the selected panel; a stale
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
            -- inline box), so a successful pick must clear it here
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

    -- Also consume the shared autocomplete focus flag when an inline
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

-- Extend the Editing path with a selected entry or attached bar. The entry
-- icon, tracking kind, and status badges all share that header line instead
-- of consuming a separate identity row below the add box.
local function UpdateEditingContext(col3)
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

    if name then
        col3._cdcEditingContext = {
            icon = icon,
            name = name,
            badgeStatus = badgeStatus,
            kindText = kindText,
        }
    else
        col3._cdcEditingContext = nil
    end
    UpdateEditingHeader(col3)
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

local function RefreshBrowseEntryList(col3, group)
    HideEntrySurfaces(col3)
    HidePanelPreview(col3)
    if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end

    local scroll = col3._browseEntryScroll
    if not scroll then
        scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(col3.content)
        scroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
        scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
        col3._browseEntryScroll = scroll
    end
    scroll:ReleaseChildren()
    scroll.frame:Show()

    local heading = AceGUI:Create("Label")
    heading:SetText((group.name or "Panel") .. " Entries")
    heading:SetFullWidth(true)
    heading:SetFontObject(GameFontNormal)
    scroll:AddChild(heading)

    local function AddInlineEntryBox()
        if ST._BuildInlineAddControls then
            CS.addingToPanelId = CS.selectedGroup
            ST._BuildInlineAddControls(
                scroll,
                {},
                group,
                CS.selectedGroup,
                #(group.buttons or {}),
                { force = true }
            )
        end
    end

    if CooldownCompanion:IsRotationAssistantGroup(group) then
        local entry = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(entry)
        entry:SetText(ST.ROTATION_ASSISTANT_NAME)
        entry:SetFullWidth(true)
        entry:SetFontObject(GameFontHighlight)
        ApplyConfigRowIcon(entry, CooldownCompanion:GetRotationAssistantFallbackIcon())
        entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        entry:SetCallback("OnClick", function()
            if ST._SelectConfigRotationAssistantEntry then
                ST._SelectConfigRotationAssistantEntry(CS.selectedGroup, {
                    containerId = CS.selectedContainer,
                })
                CooldownCompanion:RefreshConfigPanel()
            end
        end)
        scroll:AddChild(entry)
        return
    end

    if #(group.buttons or {}) == 0 then
        local empty = AceGUI:Create("Label")
        ST._ConfigureWrappedHelperLabel(empty)
        empty:SetText("|cff888888This panel has no entries.|r")
        empty:SetFullWidth(true)
        scroll:AddChild(empty)
        AddInlineEntryBox()
        return
    end

    for buttonIndex, buttonData in ipairs(group.buttons or {}) do
        local entry = AceGUI:Create("InteractiveLabel")
        CleanRecycledEntry(entry)
        if ST._ConfigureConfigEntryRow then
            ST._ConfigureConfigEntryRow(entry, group, CS.selectedGroup, buttonData, buttonIndex)
        else
            entry:SetText(buttonData.name or ("Unknown " .. tostring(buttonData.type)))
            entry:SetFullWidth(true)
            entry:SetFontObject(GameFontHighlight)
            ApplyConfigRowIcon(entry, ST._GetButtonIcon and ST._GetButtonIcon(buttonData) or 134400)
            entry:SetHighlight("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        end

        local panelId = CS.selectedGroup
        entry:SetCallback("OnClick", function(_, _, mouseButton)
            if mouseButton ~= "LeftButton"
                or IsControlKeyDown()
                or GetCursorInfo()
            then
                return
            end
            local cursorX, cursorY = GetScaledCursorPosition(scroll)
            CS.dragState = {
                kind = "button",
                phase = "pending",
                sourceIndex = buttonIndex,
                groupId = panelId,
                scrollWidget = scroll,
                widget = entry,
                startX = cursorX,
                startY = cursorY,
                childOffset = 1,
                totalDraggable = #(group.buttons or {}),
            }
            StartDragTracking()
        end)
        entry.frame:SetScript("OnMouseUp", function(_, mouseButton)
            if CS.dragState and CS.dragState.phase == "active" then return end
            if mouseButton == "LeftButton" and ST._SelectConfigButton then
                ST._SelectConfigButton(panelId, buttonIndex, { multi = IsControlKeyDown() })
                CooldownCompanion:RefreshConfigPanel()
            elseif mouseButton == "RightButton" and ST._ShowEntryContextMenu then
                if ST._SelectConfigButtonPanel then
                    ST._SelectConfigButtonPanel(panelId, { clearPanelMulti = true })
                end
                ST._ShowEntryContextMenu(panelId, buttonIndex, buttonData)
            end
        end)
        scroll:AddChild(entry)
    end
    AddInlineEntryBox()
end

local function RefreshButtonsWideColumn()
    local col3 = CS.configFrame and CS.configFrame.col3
    if not col3 then return end

    -- Hide surfaces owned by the resources/cast homes that share col3
    if col3._customAuraTabGroup then col3._customAuraTabGroup.frame:Hide() end
    col3._customAuraSubScroll = nil
    if col3._customAuraScroll then col3._customAuraScroll.frame:Hide() end
    if ST._HideResourcesWideSurfaces then ST._HideResourcesWideSurfaces(col3) end
    if col3._browseEntryScroll then col3._browseEntryScroll.frame:Hide() end

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

    if browse and CS.selectedGroup and not IsEntrySelectionActive() then
        local browseGroup = CooldownCompanion.db.profile.groups[CS.selectedGroup]
        if browseGroup then
            RefreshBrowseEntryList(col3, browseGroup)
            return
        end
    end

    -- Attached bar selected in the unified anchor preview: that bar's
    -- settings own the settings area
    local unifiedBarKind = not browse and GetValidatedUnifiedBarKind() or nil
    if unifiedBarKind then
        HideEntrySurfaces(col3)
        if col3.groupSettingsHost then col3.groupSettingsHost:Hide() end
        UpdatePanelPreview(col3)
        UpdateAddBox(col3)
        UpdateEditingContext(col3)
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
            UpdateEditingContext(col3)
            -- Final height pass: the add box just settled its visibility,
            -- which feeds the settings-minimum clamp.
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

    -- Otherwise the group-side surfaces (panel and Group settings,
    -- placeholders) own the settings area
    HideEntrySurfaces(col3)
    if browse then
        HidePanelPreview(col3)
    else
        UpdatePanelPreview(col3)
        UpdateAddBox(col3)
        UpdateEditingContext(col3)
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
        -- The Editing header shares the mirror's selection identity and
        -- status badges, so keep it in step with targeted rebuilds.
        UpdateEditingContext(col3)
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
ST._SetWideEditingAddBox = SetWideEditingAddBox
ST._SetWideEditingHeaderActions = SetWideEditingHeaderActions
ST._SetWideEditingChips = SetWideEditingChips
ST._ClearWideEditingExtras = ClearWideEditingExtras
-- Divider + editing-surface hide for view branches that release the split
-- while their own preview host holds it (Resources/cast homes).
ST._HideWideEditingChrome = HideEditingChrome
-- Shared teardown for view switches away from the buttons view (resources,
-- cast frames, talent picker, config close): hides the preview surfaces AND
-- releases the preview so its conditional ticker stops and override
-- targeting disarms. Transient same-view hides must NOT use this - the
-- following rebuild pass re-shows the preview and targeting should survive.
ST._HideButtonsPanelPreviewSurfaces = HidePanelPreview
