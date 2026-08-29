-- Unlock-mode title-bar quick actions and spatial panel anchor picking.
-- AnchorPolicy.lua remains the single owner of anchor eligibility.

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local openMenuRoot
local ARRANGE_TREE_MAX_VISIBLE = 12
local ARRANGE_TREE_ROW_HEIGHT = 20
local ARRANGE_TREE_SCROLL_TRACK_WIDTH = 3
local ARRANGE_TREE_SCREEN_MARGIN = 40

local function ResolveDescriptor(record)
    local descriptor = record and record.getDescriptor and record.getDescriptor()
    if descriptor then
        descriptor.header = descriptor.header or record.header
        descriptor.chromeRoot = descriptor.chromeRoot or record.chromeRoot
    end
    return descriptor
end

local function GetDescriptor(record)
    return record and record.openDescriptor or ResolveDescriptor(record)
end

local function SetMenuPinned(root, pinned)
    if openMenuRoot and openMenuRoot ~= root then
        openMenuRoot._moverMenuPinned = nil
    end
    openMenuRoot = pinned and root or nil
    if root then
        root._moverMenuPinned = pinned and true or nil
    end
    if CooldownCompanion.ApplyMoverChromeFadeState then
        CooldownCompanion:ApplyMoverChromeFadeState()
    end
end

local function CloseQuickMenuPin()
    if openMenuRoot then
        SetMenuPinned(openMenuRoot, false)
    end
end

if hooksecurefunc and CloseDropDownMenus then
    hooksecurefunc("CloseDropDownMenus", CloseQuickMenuPin)
end

local function RefreshStandalone(groupId, group)
    CooldownCompanion:RebuildPanelAlphaDependencyTargets()
    CooldownCompanion:RefreshGroupFrame(groupId)
    if group.parentContainerId then
        CooldownCompanion:RefreshContainerWrapper(group.parentContainerId)
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function SetStandaloneAnchor(groupId, group, target)
    if target == CooldownCompanion:GetCursorAnchorTargetName() then
        return CooldownCompanion:SetGroupAnchor(groupId, target)
    end
    if CooldownCompanion:IsGroupCursorAnchored(group) then
        local owner = group.parentContainerId
            and ("CooldownCompanionContainer" .. tostring(group.parentContainerId))
            or "UIParent"
        if not CooldownCompanion:SetGroupAnchor(groupId, owner, true) then
            return false
        end
    end
    local settings = CooldownCompanion:GetStandaloneTextureAnchorSettings(group)
    if type(settings) ~= "table" then return false end
    local options = CooldownCompanion:GetGroupAnchorValidationOptions(groupId)
    if not CooldownCompanion:ValidateAddonFrameAnchorTarget(target, options) then
        CooldownCompanion:PrintInvalidAnchorTargetReason(target, options)
        return false
    end
    local ownerTarget = group.parentContainerId
        and ("CooldownCompanionContainer" .. tostring(group.parentContainerId))
    if target == ownerTarget then
        settings.point, settings.relativeTo, settings.relativePoint = "CENTER", target, "CENTER"
        settings.x, settings.y = 0, 0
    elseif not target or target == "" or target == "UIParent" then
        settings.point, settings.relativeTo, settings.relativePoint = "CENTER", "UIParent", "CENTER"
        settings.x, settings.y = 0, 0
    elseif _G[target] then
        settings.point, settings.relativeTo, settings.relativePoint = "TOPLEFT", target, "BOTTOMLEFT"
        settings.x, settings.y = 0, -5
    else
        CooldownCompanion:Print("Frame '" .. tostring(target) .. "' not found.")
        return false
    end
    RefreshStandalone(groupId, group)
    return true
end

local function GetExternalAnchor(descriptor)
    if descriptor.kind == "cast" then
        local settings = CooldownCompanion:GetCastBarSettings()
        return settings and settings.independentAnchor
    end
    local settings = CooldownCompanion:GetResourceBarSettings()
    local layout = settings and CooldownCompanion:GetSpecLayoutOrder()
    return layout and layout.independentAnchor
end

local function ApplyExternalAnchor(descriptor, target)
    local options = { domain = "external" }
    if not CooldownCompanion:ValidateAddonFrameAnchorTarget(target, options) then
        CooldownCompanion:PrintInvalidAnchorTargetReason(target, options)
        return false
    end
    if target and target ~= "" and target ~= "UIParent" and not _G[target] then
        CooldownCompanion:Print("Frame '" .. tostring(target) .. "' not found.")
        return false
    end
    local anchor = GetExternalAnchor(descriptor)
    if type(anchor) ~= "table" then return false end
    if not target or target == "" or target == "UIParent" then
        anchor.point, anchor.relativeTo, anchor.relativePoint = "CENTER", nil, "CENTER"
        anchor.x, anchor.y = 0, 0
    else
        anchor.point, anchor.relativeTo, anchor.relativePoint = "TOPLEFT", target, "BOTTOMLEFT"
        anchor.x, anchor.y = 0, -5
    end
    if descriptor.kind == "cast" then
        CooldownCompanion:ApplyCastBarSettings()
    else
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
    end
    CooldownCompanion:RefreshConfigPanel()
    return true
end

function CooldownCompanion:ApplyMoverQuickAnchor(descriptor, target)
    if not descriptor then return false end
    if descriptor.kind == "panel" then
        local group = self.db.profile.groups[descriptor.id]
        if not group then return false end
        local wasCursorAnchored = self:IsGroupCursorAnchored(group)
        local applied
        if self:IsStandaloneTexturePanelGroup(group) then
            applied = SetStandaloneAnchor(descriptor.id, group, target)
        else
            applied = self:SetGroupAnchor(descriptor.id, target)
        end
        if applied
            and wasCursorAnchored
            and not self:IsGroupCursorAnchored(group)
            and self:IsArrangeModeActive() then
            -- Cursor-only containers intentionally stay locked in Arrange.
            -- Once this panel leaves Cursor, promote just the panel to an
            -- independent mover so it cannot become an inert toolbar row.
            self:SetPanelLocked(descriptor.id, false)
            if self.ShowCursorAnchorLayoutPreview then
                self:ShowCursorAnchorLayoutPreview(nil)
            end
            self:ActivateArrangePanel(group.parentContainerId, descriptor.id, false)
        elseif applied
            and not wasCursorAnchored
            and self:IsGroupCursorAnchored(group)
            and self:IsArrangeModeActive() then
            -- The panel just left its container preview. Clear that stale
            -- selection before rebuilding dummy-cursor membership, then keep
            -- the same panel selected through the shared activation owner.
            self:ClearArrangeMoverSelection()
            if self.ShowCursorAnchorLayoutPreview then
                self:ShowCursorAnchorLayoutPreview(nil)
            end
            self:ActivateArrangePanel(group.parentContainerId, descriptor.id, false)
        end
        return applied
    elseif descriptor.kind == "cast" or descriptor.kind == "resource" then
        return ApplyExternalAnchor(descriptor, target)
    end
    return false
end

function CooldownCompanion:ResetMoverQuickPosition(descriptor)
    if not descriptor then return end
    if descriptor.kind == "panel" then
        local group = self.db.profile.groups[descriptor.id]
        if not group then return end
        if self:IsGroupCursorAnchored(group) then
            self:SetGroupAnchor(descriptor.id, self:GetCursorAnchorTargetName())
        elseif self:IsStandaloneTexturePanelGroup(group) then
            local settings = self:GetStandaloneTextureAnchorSettings(group)
            SetStandaloneAnchor(descriptor.id, group, settings and settings.relativeTo or "UIParent")
        else
            local target = type(group.anchor) == "table" and group.anchor.relativeTo
            if not target then
                target = group.parentContainerId
                    and ("CooldownCompanionContainer" .. tostring(group.parentContainerId))
                    or "UIParent"
            end
            self:SetGroupAnchor(descriptor.id, target, target == "UIParent")
        end
    elseif descriptor.kind == "container" then
        local container = self.db.profile.groupContainers[descriptor.id]
        local frame = self.containerFrames and self.containerFrames[descriptor.id]
        if container and frame then
            container.anchor = self:NormalizeContainerAnchor(container.anchor)
            local oldX, oldY = tonumber(container.anchor.x) or 0, tonumber(container.anchor.y) or 0
            container.anchor = {
                point = "CENTER", relativeTo = "UIParent", relativePoint = "CENTER", x = 0, y = 0,
            }
            self:AnchorContainerFrame(frame, container.anchor)
            if self.SyncGroupedStandalonePreviewSettings then
                self:SyncGroupedStandalonePreviewSettings(descriptor.id, -oldX, -oldY)
            end
            self:RefreshContainerWrapper(descriptor.id)
            self:RefreshConfigPanel()
        end
    elseif descriptor.kind == "cast" or descriptor.kind == "resource" then
        local anchor = GetExternalAnchor(descriptor)
        ApplyExternalAnchor(descriptor, type(anchor) == "table" and anchor.relativeTo)
    end
end

function CooldownCompanion:OpenMoverLayoutSettings(descriptor)
    if not descriptor then return end
    self:RunConfigIntent({
        action = "open",
        entryPoint = "unlock menu",
        route = {
            kind = descriptor.kind,
            id = descriptor.id,
            containerId = descriptor.containerId,
        },
    })
end

function CooldownCompanion:StartMoverFramePick(descriptor, panelsOnly)
    if not descriptor or not self:LoadConfigAddon("unlock menu frame picker") then return end
    local CS = ST._configState
    if not (CS and CS.StartPickFrame) then
        self:Print("Frame picker is unavailable.")
        return
    end
    local restoreConfig = CS.configFrame and CS.configFrame.frame and CS.configFrame.frame:IsShown()
    CS.StartPickFrame(function(frameName)
        if restoreConfig and CS.configFrame then
            CS.configFrame.frame:Show()
        end
        if frameName then
            CooldownCompanion:ApplyMoverQuickAnchor(descriptor, frameName)
        end
    end, descriptor.kind == "panel" and descriptor.id or nil, {
        domain = descriptor.kind == "panel" and "panel" or "external",
        sourceGroupId = descriptor.kind == "panel" and descriptor.id or nil,
        sourceKind = descriptor.kind == "panel" and "group" or nil,
        requireAddonPanel = panelsOnly == true,
        instructionText = panelsOnly
            and "Click a visible panel to anchor  |  Right-click or Escape to cancel"
            or "Click a frame to anchor  |  Right-click or Escape to cancel",
    })
end

local function AddMenuButton(text, func, options, level)
    local info = UIDropDownMenu_CreateInfo()
    info.text, info.notCheckable, info.func = text, true, func
    for key, value in pairs(options or {}) do
        info[key] = value
    end
    UIDropDownMenu_AddButton(info, level)
end

local function InitializeQuickMenu(record, level, menuList)
    local descriptor = GetDescriptor(record)
    if not descriptor then return end
    level = level or 1
    if level == 2 and menuList == "anchor" then
        if descriptor.kind == "panel" then
            local group = CooldownCompanion.db.profile.groups[descriptor.id]
            if group and group.parentContainerId then
                AddMenuButton("This Group", function()
                    CooldownCompanion:ApplyMoverQuickAnchor(
                        descriptor,
                        "CooldownCompanionContainer" .. tostring(group.parentContainerId)
                    )
                end, nil, level)
            end
            AddMenuButton("Pick Visible Panel...", function()
                CooldownCompanion:StartMoverFramePick(descriptor, true)
            end, nil, level)
            AddMenuButton("Pick Frame...", function()
                CooldownCompanion:StartMoverFramePick(descriptor, false)
            end, nil, level)
            local cursorAvailable = group and CooldownCompanion:CanGroupUseCursorAnchor(group)
            if cursorAvailable and CooldownCompanion.GetDirectAnchorDependents then
                cursorAvailable = #CooldownCompanion:GetDirectAnchorDependents(descriptor.id) == 0
            end
            if cursorAvailable and CooldownCompanion.GetExternalAnchorDependents then
                cursorAvailable = #CooldownCompanion:GetExternalAnchorDependents(descriptor.id) == 0
            end
            if cursorAvailable then
                AddMenuButton("Cursor", function()
                    CooldownCompanion:ApplyMoverQuickAnchor(
                        descriptor,
                        CooldownCompanion:GetCursorAnchorTargetName()
                    )
                end, nil, level)
            end
        else
            AddMenuButton("Screen", function()
                CooldownCompanion:ApplyMoverQuickAnchor(descriptor, "UIParent")
            end, nil, level)
            AddMenuButton("Pick Visible Panel...", function()
                CooldownCompanion:StartMoverFramePick(descriptor, true)
            end, nil, level)
            AddMenuButton("Pick Frame...", function()
                CooldownCompanion:StartMoverFramePick(descriptor, false)
            end, nil, level)
        end
        return
    end

    AddMenuButton("Open Settings", function()
        CooldownCompanion:OpenMoverLayoutSettings(descriptor)
    end, nil, level)
    if descriptor.kind ~= "container" then
        AddMenuButton("Anchor to...", nil, { hasArrow = true, menuList = "anchor" }, level)
    end
    AddMenuButton("Reset Position", function()
        CooldownCompanion:ResetMoverQuickPosition(descriptor)
    end, nil, level)
    AddMenuButton("Controls & Shortcuts", nil, {
        disabled = true,
        tooltipTitle = "Controls & Shortcuts",
        tooltipText = "Drag to move. Use the arrow controls or coordinate fields for precise placement. Escape cancels an anchor pick; Cancel reverts the unlock session.",
        tooltipOnButton = true,
    }, level)
end

function ST.CreateMoverQuickMenuButton(header, size, getDescriptor, chromeRoot)
    if not (header and getDescriptor) then return nil end
    local button = CreateFrame("Button", nil, header)
    button:SetSize(size or 14, size or 14)
    button:RegisterForClicks("LeftButtonUp")
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER", 0, 2)
    label:SetText("...")
    label:SetTextColor(0.82, 0.82, 0.82, 0.95)
    button.label = label

    local dropdown = CreateFrame("Frame", nil, UIParent, "UIDropDownMenuTemplate")
    local record = {
        header = header,
        chromeRoot = chromeRoot or header,
        getDescriptor = getDescriptor,
        dropdown = dropdown,
    }
    UIDropDownMenu_Initialize(dropdown, function(_, level, menuList)
        InitializeQuickMenu(record, level, menuList)
    end, "MENU")

    button:SetScript("OnEnter", function()
        label:SetTextColor(1, 1, 1, 1)
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("More actions")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        label:SetTextColor(0.82, 0.82, 0.82, 0.95)
        GameTooltip:Hide()
    end)
    button:SetScript("OnClick", function()
        -- Toolbar rows are recycled while their dropdown can remain open.
        -- Freeze this click's target so submenus cannot retarget after a scroll.
        record.openDescriptor = ResolveDescriptor(record)
        if not record.openDescriptor then return end
        CloseDropDownMenus()
        ToggleDropDownMenu(1, nil, dropdown, button, 0, 0)
        SetMenuPinned(record.chromeRoot, true)
    end)
    return button
end

local function ArrangeTreePanelVisible(addon, panelInfo, panelUnlocked)
    local groupId, group = panelInfo.groupId, panelInfo.group
    local visibilityOpts = {
        group = group,
        checkCharVisibility = true,
    }
    if panelUnlocked then
        visibilityOpts.panelUnlockPreview = true
    else
        visibilityOpts.assumeContainerUnlocked = true
    end
    return addon:IsGroupVisibleInUnlockPreview(groupId, visibilityOpts) and (
        not addon:IsGroupCursorAnchored(group)
        or addon._cursorAnchorLayoutPreview
            and addon._cursorAnchorLayoutPreview.activeGroupIds
            and addon._cursorAnchorLayoutPreview.activeGroupIds[groupId] == true
    )
end

local function BuildArrangeTree(addon)
    local roots = {}
    if not addon:IsUnlockToolbarActive() then return roots end
    for containerId, container in pairs(addon.db.profile.groupContainers or {}) do
        if addon:IsContainerVisibleToCurrentChar(containerId) then
            local containerUnlocked = addon:IsUnlockToolbarContainerEligible(containerId)
            local children = {}
            for _, panelInfo in ipairs(addon:GetPanels(containerId)) do
                local panelUnlocked = addon:IsUnlockToolbarPanelEligible(
                    panelInfo.groupId,
                    panelInfo.group
                )
                local cursorPreview = addon._cursorAnchorLayoutPreview
                local cursorAvailable = addon:IsGroupCursorAnchored(panelInfo.group)
                    and cursorPreview
                    and cursorPreview.activeGroupIds
                    and cursorPreview.activeGroupIds[panelInfo.groupId] == true
                    or false
                if (containerUnlocked or panelUnlocked or cursorAvailable)
                    and ArrangeTreePanelVisible(addon, panelInfo, panelUnlocked) then
                    local child = {
                        kind = "panel",
                        id = panelInfo.groupId,
                        containerId = containerId,
                        name = panelInfo.group.name or ("Panel " .. tostring(panelInfo.groupId)),
                        order = addon:GetOrderForSpec(
                            panelInfo.group,
                            addon._currentSpecId,
                            panelInfo.group.order or panelInfo.groupId
                        ),
                        cursor = addon:IsGroupCursorAnchored(panelInfo.group),
                    }
                    -- A third level: one row per Panel Section, addressed as
                    -- (groupId, anchor). Anchor reading order, matching the
                    -- Layout tab's blocks and the panel's own geometry.
                    -- Only under the SELECTED panel (owner ruling 2026-08-29):
                    -- the rows expand with the panel's selection and collapse
                    -- away with it, so the list stays panels-first.
                    local panelSelected = addon._arrangeSelectedPanelId == panelInfo.groupId
                    if not panelSelected then
                        local containerFrame = addon.containerFrames
                            and addon.containerFrames[containerId]
                        panelSelected = containerFrame
                            and containerFrame._containerSelectedGroupId == panelInfo.groupId
                            or false
                    end
                    if panelSelected
                        and ST.PanelSupportsSections(panelInfo.group)
                        and type(panelInfo.group.sections) == "table" then
                        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
                            if type(panelInfo.group.sections[anchor]) == "table" then
                                local sections = child.sections
                                if not sections then
                                    sections = {}
                                    child.sections = sections
                                end
                                sections[#sections + 1] = {
                                    kind = "section",
                                    id = anchor,
                                    groupId = panelInfo.groupId,
                                    containerId = containerId,
                                    name = ST.PANEL_SECTION_ANCHOR_LABELS[anchor] .. " Section",
                                }
                            end
                        end
                    end
                    children[#children + 1] = child
                end
            end
            if #children > 0 or containerUnlocked then
                table.sort(children, function(a, b)
                    if a.order ~= b.order then return a.order < b.order end
                    return tostring(a.id) < tostring(b.id)
                end)
                roots[#roots + 1] = {
                    kind = "root",
                    id = containerId,
                    name = container.name or ("Group " .. tostring(containerId)),
                    order = addon:GetOrderForSpec(container, addon._currentSpecId, container.order or containerId),
                    children = children,
                    wrapperAvailable = containerUnlocked,
                }
            end
        end
    end
    table.sort(roots, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return tostring(a.id) < tostring(b.id)
    end)
    if addon:IsSpecialMoverUnlockEligible("cast") then
        roots[#roots + 1] = { kind = "special", id = "cast", name = "Cast Bar", wrapperAvailable = true }
    end
    if addon:IsSpecialMoverUnlockEligible("resource") then
        roots[#roots + 1] = { kind = "special", id = "resource", name = "Resource Bars", wrapperAvailable = true }
    end
    return roots
end

local function FlattenArrangeTree(roots)
    local entries = {}
    for _, root in ipairs(roots) do
        entries[#entries + 1] = root
        if root.kind == "root" then
            for _, child in ipairs(root.children) do
                child.parent = root
                entries[#entries + 1] = child
                for _, section in ipairs(child.sections or {}) do
                    section.parent = root
                    entries[#entries + 1] = section
                end
            end
        end
    end
    return entries
end

function CooldownCompanion:SetArrangeTreePanelHover(containerId, groupId, hovered)
    local frame = self.containerFrames and self.containerFrames[containerId]
    if not frame then return end
    if hovered then
        frame._containerHoveredGroupId = groupId
    else
        frame._containerHoveredGroupId = frame._containerSelectedGroupId
    end
    self:RefreshContainerWrapper(containerId)
end

local IsTreeEntrySelected
local RootHasSelectedChild

local function IsArrangeTreeEntryActionable(entry)
    if not entry then return false end
    if entry.kind == "root" then
        return entry.wrapperAvailable == true
    end
    return entry.kind == "panel" or entry.kind == "special"
end

local function GetArrangeTreeEntryDescriptor(entry)
    if not IsArrangeTreeEntryActionable(entry) then return nil end
    if entry.kind == "root" then
        return { kind = "container", id = entry.id, focusId = entry.id }
    elseif entry.kind == "panel" then
        return {
            kind = "panel",
            id = entry.id,
            containerId = entry.containerId,
            focusId = entry.containerId,
        }
    elseif entry.kind == "special" then
        return { kind = entry.id, focusId = entry.id }
    end
    return nil
end

local function LockArrangeTreeEntry(entry)
    local descriptor = GetArrangeTreeEntryDescriptor(entry)
    if not descriptor then return end
    if descriptor.kind == "container" and ST.LockContainerFromMover then
        ST.LockContainerFromMover(descriptor.id)
    elseif descriptor.kind == "panel" and ST.LockPanelFromMover then
        ST.LockPanelFromMover(descriptor.id)
    elseif descriptor.kind == "cast" and ST.LockIndependentCastBarFromMover then
        ST.LockIndependentCastBarFromMover()
    elseif descriptor.kind == "resource" and ST.LockIndependentResourceStackFromMover then
        ST.LockIndependentResourceStackFromMover()
    end
end

local function ActivateArrangeTreeEntry(entry)
    if not entry or entry.manuallyHidden then return end
    if (entry.kind == "root" or entry.kind == "special")
        and not entry.wrapperAvailable then
        return
    end
    local rootId = entry.containerId or entry.id
    if entry.kind == "panel" then
        CooldownCompanion:ActivateArrangePanel(entry.containerId, entry.id, true)
        return
    end
    if entry.kind == "section" then
        CooldownCompanion:ActivateArrangeSection(entry.groupId, entry.id, true)
        return
    end
    if IsTreeEntrySelected(CooldownCompanion, entry)
        and CooldownCompanion._arrangeSoloContainerId == rootId then
        CooldownCompanion:ClearArrangeMoverSelection()
        return
    end
    -- Selection is global even though panel state is stored on each container.
    -- Clear the previous row first so switching roots never leaves a second,
    -- dimmed row logically selected behind the active solo view.
    CooldownCompanion:ClearArrangeMoverSelection()
    if entry.kind == "root" and entry.wrapperAvailable then
        CooldownCompanion:SelectContainerWrapper(entry.id)
        CooldownCompanion:FocusArrangeContainer(entry.id)
    elseif entry.kind == "special" then
        CooldownCompanion:FocusArrangeContainer(entry.id)
    end
    if CooldownCompanion._arrangeSoloContainerId ~= rootId then
        CooldownCompanion:SetArrangeSoloContainer(rootId)
    end
    CooldownCompanion:RefreshArrangePillList()
end

local function EnsureArrangeTreeRow(pill, index)
    pill._treeRows = pill._treeRows or {}
    local row = pill._treeRows[index]
    if row then return row end

    row = CreateFrame("Button", nil, pill)
    row:SetHeight(20)
    row:RegisterForClicks("LeftButtonUp")
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(1, 0.82, 0, 0.12)
    row.bg:Hide()

    row.check = CreateFrame("Button", nil, row, "BackdropTemplate")
    row.check:SetSize(12, 12)
    row.check:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    row.check:SetBackdropColor(0.16, 0.16, 0.16, 1)
    ST.CreatePixelBorders(row.check)
    row.check.fill = row.check:CreateTexture(nil, "OVERLAY")
    row.check.fill:SetSize(6, 6)
    row.check.fill:SetPoint("CENTER")
    row.check.fill:SetColorTexture(1, 0.82, 0, 0.9)
    row.check:SetScript("OnClick", function()
        local entry = row.entry
        if not (entry and entry.wrapperAvailable) then return end
        CooldownCompanion:SetContainerArrangeChromeHidden(entry.id, not entry.manuallyHidden)
        CooldownCompanion:RefreshArrangePillList()
    end)

    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)

    row.lockButton = ST.CreateMoverLockBadge(row, 12, function()
        LockArrangeTreeEntry(row.entry)
    end)
    row.lockButton:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    row.lockButton:SetAlpha(0.82)
    row.lockButton:HookScript("OnEnter", function(self) self:SetAlpha(1) end)
    row.lockButton:HookScript("OnLeave", function(self) self:SetAlpha(0.82) end)

    row.menuButton = ST.CreateMoverQuickMenuButton(
        row,
        12,
        function() return GetArrangeTreeEntryDescriptor(row.entry) end,
        row
    )
    row.menuButton:SetPoint("RIGHT", row.lockButton, "LEFT", -2, 0)

    row:SetScript("OnClick", function() ActivateArrangeTreeEntry(row.entry) end)
    row:SetScript("OnEnter", function(self)
        self._hovered = true
        local entry = self.entry
        if entry and (entry.kind == "panel" or entry.kind == "section")
            and not entry.cursor then
            CooldownCompanion:SetArrangeTreePanelHover(entry.containerId,
                entry.groupId or entry.id, true)
        end
        CooldownCompanion:RefreshArrangePillList()
    end)
    row:SetScript("OnLeave", function(self)
        self._hovered = nil
        local entry = self.entry
        if entry and (entry.kind == "panel" or entry.kind == "section")
            and not entry.cursor then
            CooldownCompanion:SetArrangeTreePanelHover(entry.containerId,
                entry.groupId or entry.id, false)
        end
        CooldownCompanion:RefreshArrangePillList()
    end)

    pill._treeRows[index] = row
    return row
end

local function EnsureArrangeTreeScrollIndicator(pill)
    if pill._treeScrollTrack then
        return pill._treeScrollTrack, pill._treeScrollThumb
    end

    local track = CreateFrame("Frame", nil, pill)
    track:SetWidth(ARRANGE_TREE_SCROLL_TRACK_WIDTH)
    track:EnableMouse(false)
    track.bg = track:CreateTexture(nil, "BACKGROUND")
    track.bg:SetAllPoints()
    track.bg:SetColorTexture(0.12, 0.12, 0.12, 0.9)

    local thumb = track:CreateTexture(nil, "ARTWORK")
    thumb:SetWidth(ARRANGE_TREE_SCROLL_TRACK_WIDTH)
    thumb:SetColorTexture(1, 0.82, 0, 0.9)

    pill._treeScrollTrack = track
    pill._treeScrollThumb = thumb
    return track, thumb
end

local function FindArrangeTreeEntryIndex(entries, requested)
    if not requested then return nil end
    for index, entry in ipairs(entries) do
        -- A section's id is its anchor name, unique only within one panel,
        -- so the groupId is part of the match (nil == nil for other kinds).
        if entry.kind == requested.kind and entry.id == requested.id
            and entry.groupId == requested.groupId then
            return index
        end
    end
    return nil
end

IsTreeEntrySelected = function(addon, entry)
    if entry.kind == "section" then
        return addon._arrangeSectionGroupId == entry.groupId
            and addon._arrangeSectionAnchor == entry.id
    end
    if entry.kind == "panel" then
        if addon._arrangeSelectedPanelId == entry.id then
            return true
        end
        if entry.cursor then
            local preview = addon._cursorAnchorLayoutPreview
            return preview and preview.selectedGroupId == entry.id or false
        end
        local frame = addon.containerFrames and addon.containerFrames[entry.containerId]
        return frame and frame._containerSelectedGroupId == entry.id or false
    elseif entry.kind == "root" then
        local frame = addon.containerFrames and addon.containerFrames[entry.id]
        return addon._arrangeFocusContainerId == entry.id
            and (not frame or frame._containerSelectedGroupId == nil)
            and not RootHasSelectedChild(addon, entry)
    end
    return addon._arrangeFocusContainerId == entry.id
end

RootHasSelectedChild = function(addon, root)
    local selectedPanelId = addon._arrangeSelectedPanelId
    local selectedPanel = selectedPanelId and addon.db.profile.groups[selectedPanelId]
    if selectedPanel and selectedPanel.parentContainerId == root.id then return true end
    local frame = addon.containerFrames and addon.containerFrames[root.id]
    if frame and frame._containerSelectedGroupId then return true end
    local preview = addon._cursorAnchorLayoutPreview
    local selected = preview and preview.selectedGroupId
    if selected then
        local group = addon.db.profile.groups[selected]
        return group and group.parentContainerId == root.id or false
    end
    return false
end

local function UpdateArrangeTreeRow(addon, row, entry)
    row.entry = entry
    local rootId = entry.containerId or entry.id
    local hiddenSet = addon._arrangeChromeHidden
    entry.manuallyHidden = hiddenSet and hiddenSet[rootId] == true or false
    entry.soloHidden = addon._arrangeSoloContainerId ~= nil
        and addon._arrangeSoloContainerId ~= rootId

    local isRoot = entry.kind == "root"
    local isSpecial = entry.kind == "special"
    local actionsShown = IsArrangeTreeEntryActionable(entry)

    row.check:SetShown((isRoot or isSpecial) and entry.wrapperAvailable)
    if row.check:IsShown() then
        row.check:ClearAllPoints()
        row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.check.fill:SetShown(not entry.manuallyHidden)
    end
    row.lockButton:SetShown(actionsShown)
    row.menuButton:SetShown(actionsShown)

    row.name:ClearAllPoints()
    if entry.kind == "section" then
        row.name:SetPoint("LEFT", row, "LEFT", 34, 0)
    elseif entry.kind == "panel" then
        row.name:SetPoint("LEFT", row, "LEFT", 22, 0)
    elseif entry.wrapperAvailable then
        row.name:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
    else
        row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
    end
    if actionsShown then
        row.name:SetPoint("RIGHT", row.menuButton, "LEFT", -4, 0)
    else
        row.name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    end
    row.name:SetText(entry.name)

    local inactive = entry.manuallyHidden or (isRoot and not entry.wrapperAvailable)
    local dimmed = inactive or entry.soloHidden
    row.name:SetTextColor(dimmed and 0.5 or 1, dimmed and 0.5 or 1, dimmed and 0.5 or 1, 1)
    row:SetAlpha(inactive and 0.72 or 1)

    local selected = IsTreeEntrySelected(addon, entry)
    local childSelected = isRoot and RootHasSelectedChild(addon, entry)
    local canvasHovered = false
    if entry.kind == "panel" and not entry.cursor then
        local frame = addon.containerFrames and addon.containerFrames[entry.containerId]
        canvasHovered = frame and frame._containerHoveredGroupId == entry.id or false
    end
    if selected then
        row.bg:SetColorTexture(1, 0.82, 0, 0.20)
        row.bg:Show()
    elseif childSelected then
        row.bg:SetColorTexture(1, 0.82, 0, 0.08)
        row.bg:Show()
    elseif (row._hovered or canvasHovered) and not inactive then
        row.bg:SetColorTexture(1, 1, 1, 0.08)
        row.bg:Show()
    else
        row.bg:Hide()
    end
end

-- GroupOperations delegates its existing public refresh entry point here once
-- this module has loaded.
function ST.RefreshArrangeTreePill(self)
    local pill = self._arrangeModePill
    if not (pill and pill:IsShown()) then return end

    for _, legacyRow in ipairs(pill._rows or {}) do
        legacyRow:Hide()
    end

    local roots = BuildArrangeTree(self)
    local entries = FlattenArrangeTree(roots)
    local expanded = #entries > 0

    local maxVisible = ARRANGE_TREE_MAX_VISIBLE
    local maxOffset = math.max(0, #entries - maxVisible)
    local offset = math.max(0, math.min(pill._listScrollOffset or 0, maxOffset))
    local revealIndex = FindArrangeTreeEntryIndex(entries, self._arrangeTreeRevealEntry)
    self._arrangeTreeRevealEntry = nil
    if revealIndex then
        if revealIndex <= offset then
            offset = revealIndex - 1
        elseif revealIndex > offset + maxVisible then
            offset = revealIndex - maxVisible
        end
        offset = math.max(0, math.min(offset, maxOffset))
    end
    pill._listScrollOffset = offset
    pill._listMaxScrollOffset = maxOffset
    local visibleCount = expanded and math.min(#entries, maxVisible) or 0
    local overflow = maxOffset > 0
    local maxContentWidth = 0
    pill._treeMeasure = pill._treeMeasure
        or pill:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    for _, entry in ipairs(entries) do
        pill._treeMeasure:SetText(entry.name)
        local leftInset
        if entry.kind == "section" then
            leftInset = 34
        elseif entry.kind == "panel" then
            leftInset = 22
        elseif entry.wrapperAvailable then
            leftInset = 20
        else
            leftInset = 2
        end
        local rightInset = IsArrangeTreeEntryActionable(entry) and 32 or 2
        maxContentWidth = math.max(
            maxContentWidth,
            leftInset + (pill._treeMeasure:GetStringWidth() or 0) + rightInset
        )
    end

    for index = 1, visibleCount do
        local entry = entries[offset + index]
        local row = EnsureArrangeTreeRow(pill, index)
        UpdateArrangeTreeRow(self, row, entry)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", pill, "TOPLEFT", 8,
            -(30 + (index - 1) * ARRANGE_TREE_ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", pill, "TOPRIGHT", overflow and -14 or -8,
            -(30 + (index - 1) * ARRANGE_TREE_ROW_HEIGHT))
        row:Show()
    end
    for index = visibleCount + 1, #(pill._treeRows or {}) do
        pill._treeRows[index].entry = nil
        pill._treeRows[index]:Hide()
    end

    if expanded then
        local baseWidth = pill._baseWidth or 300
        local requestedWidth = math.max(
            baseWidth,
            math.ceil(16 + maxContentWidth + (overflow and 6 or 0))
        )
        local screenWidth = UIParent and UIParent.GetWidth and UIParent:GetWidth() or nil
        local maxWidth = screenWidth
            and math.max(baseWidth, math.floor(screenWidth - ARRANGE_TREE_SCREEN_MARGIN))
            or requestedWidth
        pill:SetSize(
            math.min(requestedWidth, maxWidth),
            30 + visibleCount * ARRANGE_TREE_ROW_HEIGHT + 6
        )
    else
        pill:SetSize(pill._baseWidth or 300, 30)
    end

    local track, thumb = EnsureArrangeTreeScrollIndicator(pill)
    track:SetShown(overflow)
    if overflow then
        track:ClearAllPoints()
        track:SetPoint("TOPRIGHT", pill, "TOPRIGHT", -5, -31)
        track:SetPoint("BOTTOMRIGHT", pill, "BOTTOMRIGHT", -5, 6)
        local trackHeight = math.max(1, visibleCount * ARRANGE_TREE_ROW_HEIGHT - 1)
        local thumbHeight = math.max(20, trackHeight * (visibleCount / #entries))
        local travel = math.max(0, trackHeight - thumbHeight)
        local fraction = maxOffset > 0 and offset / maxOffset or 0
        thumb:SetHeight(thumbHeight)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -(travel * fraction))
    end
end
