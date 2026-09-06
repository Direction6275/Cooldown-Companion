--[[
    CooldownCompanion - ArrangeMode
    Arrange snapshots, toolbar, lock/combat transitions, and session apply/cancel.

    Part of the GroupOperations family; see its ordered block in the addon TOC.
    Public methods attach to ST.Addon; local state stays with its owner.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local pairs = pairs
local ipairs = ipairs
local next = next
local type = type
local InCombatLockdown = InCombatLockdown

local function GetUnlockedPanelAlpha(frame)
    return frame and frame._unlockGhost and 0.4 or 1
end

function CooldownCompanion:IsContainerUnlockPreviewActive(containerOrContainerId)
    local container = containerOrContainerId
    local containerId = nil

    if self._combatForcedLock then
        return false
    end

    if type(containerOrContainerId) == "number" then
        containerId = containerOrContainerId
        container = self.db.profile.groupContainers and self.db.profile.groupContainers[containerId]
    elseif type(containerOrContainerId) == "table" then
        for id, candidate in pairs(self.db.profile.groupContainers or {}) do
            if candidate == containerOrContainerId then
                containerId = id
                break
            end
        end
    end

    if not container then
        return false
    end
    if container.locked ~= false then
        return false
    end
    if containerId and not self:IsContainerVisibleToCurrentChar(containerId) then
        return false
    end

    return true
end

function CooldownCompanion:IsPanelUnlockPreviewActive(groupOrGroupId)
    local group = groupOrGroupId
    if type(groupOrGroupId) == "number" then
        group = self.db.profile.groups[groupOrGroupId]
    end
    return group
        and group.locked == false
        and not self._combatForcedLock
        and not (self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group))
        or false
end

local function ForceCombatMouseLock(frame)
    if not frame then
        return
    end

    local canChangeProtectedState = not frame.CanChangeProtectedState or frame:CanChangeProtectedState()
    if frame.EnableMouse and canChangeProtectedState then
        frame:EnableMouse(false)
    end
    if frame.SetMouseClickEnabled and canChangeProtectedState then
        frame:SetMouseClickEnabled(false)
    end
    if frame.SetMouseMotionEnabled and canChangeProtectedState then
        frame:SetMouseMotionEnabled(false)
    end
end

local function CanSafelyChangeFrameVisibility(frame)
    if not frame then
        return false
    end
    if not InCombatLockdown() then
        return true
    end
    if frame.CanChangeProtectedState then
        return frame:CanChangeProtectedState()
    end
    return not (frame.IsProtected and frame:IsProtected())
end

local function SuppressFrameVisibilityForCombat(frame)
    if not frame then
        return
    end

    if CanSafelyChangeFrameVisibility(frame) then
        frame:Hide()
        return
    end

    if frame.GetAlpha and frame._combatForcedAlpha == nil then
        frame._combatForcedAlpha = frame:GetAlpha()
    end
    if frame.SetAlpha then
        frame:SetAlpha(0)
    end
end

local function RestoreFrameVisibilityAfterCombat(frame)
    if not frame then
        return
    end

    if frame._combatForcedAlpha ~= nil and frame.SetAlpha then
        frame:SetAlpha(frame._combatForcedAlpha)
    end
    frame._combatForcedAlpha = nil
end

local ARRANGE_PANEL_SIZE_KEYS = {
    "buttonSize",
    "iconWidth",
    "iconHeight",
    "barLength",
    "barHeight",
}
-- The section-owned geometry Arrange Mode can now edit (nudger/coord label
-- write offsets, wheel/grip/size label write icon dimensions). Deliberately
-- NOT spacing or maxPerLine: those are config-only, so Cancel must not
-- roll them back.
local ARRANGE_SECTION_GEOMETRY_KEYS = {
    "offsetX",
    "offsetY",
    "iconWidth",
    "iconHeight",
}
local ARRANGE_TEXTURE_POSITION_KEYS = {
    "point",
    "relativePoint",
    "relativeTo",
    "x",
    "y",
    "buttonSize",
}

local function CopyArrangeTable(source)
    if type(source) ~= "table" then
        return nil
    end

    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function CaptureArrangeFields(source, keys)
    if type(source) ~= "table" then
        return nil
    end

    local record = { values = {}, present = {} }
    for _, key in ipairs(keys) do
        if rawget(source, key) ~= nil then
            record.values[key] = source[key]
            record.present[key] = true
        end
    end
    return record
end

local function RestoreArrangeTable(owner, key, record)
    if record == nil then
        owner[key] = nil
        return
    end

    local target = owner[key]
    if type(target) ~= "table" then
        target = {}
        owner[key] = target
    end
    for existingKey in pairs(target) do
        target[existingKey] = nil
    end
    for recordKey, value in pairs(record) do
        target[recordKey] = value
    end
end

local function RestoreArrangeFields(target, record, keys)
    for _, key in ipairs(keys) do
        if record.present[key] then
            target[key] = record.values[key]
        else
            target[key] = nil
        end
    end
end

function CooldownCompanion:CaptureArrangePanelRecord(groupId)
    local snapshot = self._arrangeSnapshot
    if not snapshot then
        return
    end

    local group = self.db.profile.groups[groupId]
    if not group then
        return
    end

    local sections
    if type(group.sections) == "table" then
        for anchor, section in pairs(group.sections) do
            if type(section) == "table" then
                sections = sections or {}
                -- The table REFERENCE is the identity token: a section that
                -- dissolves and is recreated at the same anchor is a new
                -- table, and Cancel must not pour the old one's geometry
                -- into it (structural changes are left alone).
                sections[anchor] = {
                    ref = section,
                    fields = CaptureArrangeFields(section, ARRANGE_SECTION_GEOMETRY_KEYS),
                }
            end
        end
    end

    snapshot.panels[groupId] = {
        anchor = CopyArrangeTable(group.anchor),
        size = CaptureArrangeFields(group.style, ARRANGE_PANEL_SIZE_KEYS),
        sections = sections,
        texture = CaptureArrangeFields(group.textureSettings, ARRANGE_TEXTURE_POSITION_KEYS),
        signal = CaptureArrangeFields(
            group.triggerSettings and group.triggerSettings.signal,
            ARRANGE_TEXTURE_POSITION_KEYS
        ),
        locked = group.locked,
    }
end

function CooldownCompanion:CaptureArrangeContainerRecord(containerId)
    local snapshot = self._arrangeSnapshot
    if not snapshot then
        return
    end

    local container = self.db.profile.groupContainers[containerId]
    if not container then
        return
    end

    snapshot.containers[containerId] = {
        anchor = CopyArrangeTable(container.anchor),
        locked = container.locked,
    }
    for groupId, group in pairs(self.db.profile.groups) do
        if group.parentContainerId == containerId then
            self:CaptureArrangePanelRecord(groupId)
        end
    end
end

function CooldownCompanion:CaptureArrangeCastBarRecord()
    local snapshot = self._arrangeSnapshot
    if not snapshot then
        return
    end

    local settings = self.GetCastBarSettings and self:GetCastBarSettings()
    if not settings then
        snapshot.castBar = nil
        return
    end

    snapshot.castBar = {
        settings = settings,
        anchor = CopyArrangeTable(settings.independentAnchor),
        locked = settings.independentAnchorLocked,
        width = settings.independentWidth,
        height = settings.height,
    }
end

function CooldownCompanion:CaptureArrangeResourceRecord()
    local snapshot = self._arrangeSnapshot
    if not snapshot then
        return
    end

    local resourceBar = ST._RB
    local settings = resourceBar
        and resourceBar.GetResourceBarSettings
        and resourceBar.GetResourceBarSettings()
    local placementSettings = settings
        and resourceBar.GetSpecLayoutOrder
        and resourceBar.GetSpecLayoutOrder(settings)
    if not placementSettings then
        snapshot.resource = nil
        return
    end

    snapshot.resource = {
        settings = placementSettings,
        anchor = CopyArrangeTable(placementSettings.independentAnchor),
        locked = placementSettings.independentAnchorLocked,
        width = placementSettings.independentWidth,
        -- Thickness keys: which one is live flips with orientation, so both
        -- are captured and restored verbatim.
        barWidth = placementSettings.barWidth,
        barHeight = placementSettings.barHeight,
    }
end

function CooldownCompanion:CaptureArrangeSnapshot()
    self._arrangeSnapshot = {
        panels = {},
        containers = {},
    }

    for groupId in pairs(self.db.profile.groups) do
        self:CaptureArrangePanelRecord(groupId)
    end
    for containerId in pairs(self.db.profile.groupContainers or {}) do
        self:CaptureArrangeContainerRecord(containerId)
    end
    self:CaptureArrangeCastBarRecord()
    self:CaptureArrangeResourceRecord()
end

local function RestoreArrangeSnapshot(addon, snapshot)
    if not snapshot then
        return
    end

    for groupId, record in pairs(snapshot.panels or {}) do
        local group = addon.db.profile.groups[groupId]
        if group then
            RestoreArrangeTable(group, "anchor", record.anchor)
            if record.size then
                group.style = type(group.style) == "table" and group.style or {}
                RestoreArrangeFields(group.style, record.size, ARRANGE_PANEL_SIZE_KEYS)
            end
            -- Only the SAME section instance takes its geometry back (table
            -- identity, captured above); one created, dissolved, or
            -- recreated mid-arrange is a structural change this rollback
            -- deliberately leaves alone.
            if record.sections and type(group.sections) == "table" then
                for anchor, sectionRecord in pairs(record.sections) do
                    local section = group.sections[anchor]
                    if type(section) == "table" and sectionRecord
                        and section == sectionRecord.ref and sectionRecord.fields then
                        RestoreArrangeFields(section, sectionRecord.fields, ARRANGE_SECTION_GEOMETRY_KEYS)
                    end
                end
            end
            if record.texture then
                group.textureSettings = type(group.textureSettings) == "table" and group.textureSettings or {}
                RestoreArrangeFields(group.textureSettings, record.texture, ARRANGE_TEXTURE_POSITION_KEYS)
            end
            if record.signal then
                group.triggerSettings = type(group.triggerSettings) == "table" and group.triggerSettings or {}
                group.triggerSettings.signal = type(group.triggerSettings.signal) == "table"
                    and group.triggerSettings.signal
                    or {}
                RestoreArrangeFields(group.triggerSettings.signal, record.signal, ARRANGE_TEXTURE_POSITION_KEYS)
            end
            group.locked = record.locked
        end
    end

    for containerId, record in pairs(snapshot.containers or {}) do
        local container = addon.db.profile.groupContainers[containerId]
        if container then
            RestoreArrangeTable(container, "anchor", record.anchor)
            container.locked = record.locked
            -- Push the restored anchor back onto the frame directly. The refresh
            -- pass below only re-anchors a container when normalization changes
            -- its anchor, and a restored anchor is already normalized, so nothing
            -- else moves the frame off the position the drag left it at. Panels
            -- anchor relative to their container, so they follow from here.
            local frame = addon.containerFrames and addon.containerFrames[containerId]
            if frame and type(container.anchor) == "table" then
                addon:AnchorContainerFrame(frame, container.anchor)
            end
        end
    end

    if snapshot.castBar and snapshot.castBar.settings then
        local record = snapshot.castBar
        RestoreArrangeTable(record.settings, "independentAnchor", record.anchor)
        record.settings.independentAnchorLocked = record.locked
        record.settings.independentWidth = record.width
        record.settings.height = record.height
    end
    if snapshot.resource and snapshot.resource.settings then
        local record = snapshot.resource
        RestoreArrangeTable(record.settings, "independentAnchor", record.anchor)
        record.settings.independentAnchorLocked = record.locked
        record.settings.independentWidth = record.width
        record.settings.barWidth = record.barWidth
        record.settings.barHeight = record.barHeight
    end

    addon:UnlockAllFrames()
    addon:ApplyCastBarSettings()
    addon:ApplyResourceBars()
    addon:RefreshAllAuraTextureVisuals()
    if addon.RefreshConfigPanel then
        addon:RefreshConfigPanel()
    end
    addon:CheckConfigReExpandAfterLock()
end

function CooldownCompanion:IsArrangeModeActive()
    return self._arrangeModeActive == true
end

function CooldownCompanion:IsAnyFrameUnlocked()
    for _, container in pairs(self.db.profile.groupContainers or {}) do
        if container.locked == false then
            return true
        end
    end

    for _, group in pairs(self.db.profile.groups or {}) do
        if group.locked == false then
            return true
        end
    end

    if self:IsSpecialMoverUnlockEligible("cast")
        or self:IsSpecialMoverUnlockEligible("resource") then
        return true
    end

    return false
end

function CooldownCompanion:IsUnlockToolbarPanelEligible(groupId, group)
    group = group or (self.db.profile.groups and self.db.profile.groups[groupId])
    if group and self:IsGroupCursorAnchored(group) then
        return not self._combatForcedLock
            and self:IsCursorAnchorLayoutPreviewGroupActive(groupId)
            or false
    end
    return group ~= nil
        and self:IsGroupVisibleInUnlockPreview(groupId, {
            group = group,
            panelUnlockPreview = true,
            checkCharVisibility = true,
        })
        or false
end

-- Padlocks inside an active unlock session remove only the mover they belong
-- to. Containers normally preview every child regardless of the child's saved
-- independent lock flag. Arrange also parks cursor panels regardless of that
-- flag, so the session needs an effective-lock layer shared by every preview,
-- toolbar, and activation path.
function CooldownCompanion:IsArrangePanelSuppressed(groupId)
    return self._arrangePanelSuppressed ~= nil
        and self._arrangePanelSuppressed[groupId] == true
        or false
end

function CooldownCompanion:IsArrangeContainerSuppressed(containerId)
    return self._arrangeContainerSuppressed ~= nil
        and self._arrangeContainerSuppressed[containerId] == true
        or false
end

function CooldownCompanion:ClearArrangePanelSuppressionsForContainer(containerId)
    local suppressed = self._arrangePanelSuppressed
    if not suppressed then return false end
    local changed = false
    for groupId, group in pairs(self.db.profile.groups or {}) do
        if group.parentContainerId == containerId and suppressed[groupId] then
            suppressed[groupId] = nil
            changed = true
        end
    end
    if not next(suppressed) then
        self._arrangePanelSuppressed = nil
    end
    return changed
end

function CooldownCompanion:SetArrangePanelSuppressed(groupId, suppressed)
    local group = self.db.profile.groups and self.db.profile.groups[groupId]
    if not group then return false end
    local wasSuppressed = self:IsArrangePanelSuppressed(groupId)
    suppressed = suppressed == true
    if wasSuppressed == suppressed then return false end

    if suppressed
        and self._arrangeSelectedPanelId == groupId
        and self.ClearArrangeMoverSelection then
        self:ClearArrangeMoverSelection()
    end
    self._arrangePanelSuppressed = self._arrangePanelSuppressed or {}
    self._arrangePanelSuppressed[groupId] = suppressed and true or nil
    if not next(self._arrangePanelSuppressed) then
        self._arrangePanelSuppressed = nil
    end

    -- Rebuild only cursor-preview membership and mover chrome. Ordinary
    -- runtime panels remain intact; their caller refreshes the one affected
    -- frame after its saved lock flag is updated.
    if self._arrangeModeActive
        and self._cursorAnchorLayoutPreview
        and self.ShowCursorAnchorLayoutPreview then
        self:RefreshCursorAnchorLayoutPreview()
    end
    if group.parentContainerId and self.RefreshContainerWrapper then
        self:RefreshContainerWrapper(group.parentContainerId)
    end
    return true
end

function CooldownCompanion:IsUnlockToolbarContainerEligible(containerId)
    return self:IsContainerUnlockPreviewActive(containerId)
        and self:ContainerHasArrangeEligiblePanel(containerId)
        or false
end

function CooldownCompanion:HasEligibleUnlockedMover()
    for containerId in pairs(self.db.profile.groupContainers or {}) do
        if self:IsUnlockToolbarContainerEligible(containerId) then
            return true
        end
    end
    for groupId, group in pairs(self.db.profile.groups or {}) do
        if self:IsUnlockToolbarPanelEligible(groupId, group) then
            return true
        end
    end
    return self:IsSpecialMoverUnlockEligible("cast")
        or self:IsSpecialMoverUnlockEligible("resource")
end

function CooldownCompanion:IsUnlockToolbarActive()
    return not InCombatLockdown()
        and not self._combatForcedLock
        and (self:IsArrangeModeActive() or self:HasEligibleUnlockedMover())
end

function CooldownCompanion:CheckConfigReExpandAfterLock()
    if InCombatLockdown() or self._combatForcedLock then
        return
    end
    if self:IsAnyFrameUnlocked() then
        return
    end
    if ST.ExpandConfigAfterLock then
        ST.ExpandConfigAfterLock()
    end
end

function CooldownCompanion:CheckArrangeModeAutoExit()
    self:CheckConfigReExpandAfterLock()

    if not self:IsArrangeModeActive() then
        return
    end

    -- Arrange survives combat through the forced lock; combat also hides the
    -- movers, so the runtime-visibility eligibility below must not read that
    -- suppression as "everything locked" and exit mid-fight.
    if InCombatLockdown() or self._combatForcedLock then
        return
    end

    for containerId, container in pairs(self.db.profile.groupContainers or {}) do
        if self:IsContainerVisibleToCurrentChar(containerId)
            and container.locked == false then
            return
        end
    end

    local cursorPreview = self._cursorAnchorLayoutPreview
    if cursorPreview and next(cursorPreview.activeGroupIds or {}) ~= nil then
        return
    end

    if self:IsSpecialMoverUnlockEligible("cast")
        or self:IsSpecialMoverUnlockEligible("resource") then
        return
    end

    self:ExitArrangeMode()
end

local function GetArrangeModePill(addon)
    if addon._arrangeModePill then
        return addon._arrangeModePill
    end

    local pill = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    pill:SetPoint("TOP", UIParent, "TOP", 0, -80)
    pill:SetFrameStrata("FULLSCREEN_DIALOG")
    pill:SetClampedToScreen(true)
    pill:SetMovable(true)
    pill:EnableMouse(true)
    pill:RegisterForDrag("LeftButton")
    pill:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    pill:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
    -- Gold accents tie the pill to the snap guides shown while arranging.
    ST.CreatePixelBorders(pill, 1, 0.82, 0, 0.45)

    -- The top row lives in a fixed 30px band so the pill can grow downward
    -- when the group list expands.
    local title = pill:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("LEFT", pill, "TOPLEFT", 10, -15)
    title:SetText("Panels unlocked")
    title:SetTextColor(1, 0.82, 0, 1)
    pill._title = title

    local helpButton = ST.CreateRuntimeInfoButton(pill, title, "LEFT", "RIGHT", 4, 0, function(tooltip)
        tooltip:AddLine("Panels unlocked")
        tooltip:AddLine(" ")
        tooltip:AddLine("Drag title bars to move. Hold Shift to ignore snapping.", 1, 1, 1, true)
        tooltip:AddLine("Use mover controls for precise placement.", 1, 1, 1, true)
        tooltip:AddLine("Click a group or panel row to work on it alone; click it again to show all movers.", 1, 1, 1, true)
        tooltip:AddLine("Uncheck a group to hide its handles.", 1, 1, 1, true)
        if CooldownCompanion:IsArrangeModeActive() then
            tooltip:AddLine("Done, a padlock, or /cdc lock saves. Esc or Cancel reverts.", 1, 1, 1, true)
        else
            tooltip:AddLine("Done or /cdc lock locks all shown movers. A padlock locks only its panel, group, or bar.", 1, 1, 1, true)
        end
    end)
    ST.SetRuntimeInfoButtonShown(helpButton, true)

    local doneButton = CreateFrame("Button", nil, pill, "BackdropTemplate")
    doneButton:SetSize(52, 20)
    doneButton:SetPoint("RIGHT", pill, "TOPRIGHT", -10, -15)
    doneButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    doneButton:SetBackdropColor(0.16, 0.16, 0.16, 1)
    ST.CreatePixelBorders(doneButton, 0.3, 0.85, 0.3, 0.7)
    local doneText = doneButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    doneText:SetPoint("CENTER")
    doneText:SetText("Done")
    doneText:SetTextColor(1, 1, 1, 1)
    pill._doneButton = doneButton
    pill._doneText = doneText

    local cancelButton = CreateFrame("Button", nil, pill, "BackdropTemplate")
    cancelButton:SetPoint("RIGHT", doneButton, "LEFT", -6, 0)
    cancelButton:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    cancelButton:SetBackdropColor(0.16, 0.16, 0.16, 1)
    ST.CreatePixelBorders(cancelButton, 0.9, 0.3, 0.3, 0.7)
    local cancelText = cancelButton:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    cancelText:SetPoint("CENTER")
    cancelText:SetText("Cancel")
    cancelText:SetTextColor(1, 1, 1, 1)
    pill._cancelButton = cancelButton
    pill._cancelText = cancelText
    local cancelButtonWidth = math.ceil(cancelText:GetStringWidth() + 16)
    cancelButton:SetSize(cancelButtonWidth, 20)

    -- Top band: title [?] ... [Cancel] [Done]. The tree rows stack below.
    pill._baseWidth = math.max(
        300,
        math.ceil(10 + title:GetStringWidth() + 4 + 16 + 14 + cancelButtonWidth + 6 + 52 + 10)
    )
    pill:SetSize(pill._baseWidth, 30)

    cancelButton:SetScript("OnClick", function()
        CooldownCompanion:CancelArrangeMode()
    end)
    cancelButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.3, 0.13, 0.13, 1)
    end)
    cancelButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.16, 0.16, 0.16, 1)
    end)

    doneButton:SetScript("OnClick", function()
        CooldownCompanion:ExitArrangeMode()
    end)
    doneButton:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.12, 0.26, 0.12, 1)
    end)
    doneButton:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.16, 0.16, 0.16, 1)
    end)

    pill:SetScript("OnDragStart", function(self)
        if InCombatLockdown() then return end
        self._dragInProgress = true
        self:StartMoving()
    end)
    pill:SetScript("OnDragStop", function(self)
        self._dragInProgress = nil
        self:StopMovingOrSizing()
    end)
    pill:EnableMouseWheel(true)
    pill:SetScript("OnMouseWheel", function(self, delta)
        if (self._listMaxScrollOffset or 0) == 0 then
            return
        end
        self._listScrollOffset = (self._listScrollOffset or 0) - delta
        CooldownCompanion:RefreshArrangePillList()
    end)
    pill:EnableKeyboard(true)
    pill:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and CooldownCompanion:IsArrangeModeActive() then
            if not InCombatLockdown() then
                self:SetPropagateKeyboardInput(false)
            end
            CooldownCompanion:CancelArrangeMode()
        elseif not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
    end)
    pill:SetScript("OnShow", function(self)
        if not InCombatLockdown() then
            self:SetPropagateKeyboardInput(true)
        end
        CooldownCompanion:RefreshArrangePillList()
    end)
    pill:SetScript("OnHide", function(self)
        if self._dragInProgress then
            self._dragInProgress = nil
            self:StopMovingOrSizing()
        end
        GameTooltip:Hide()
    end)
    pill:Hide()

    addon._arrangeModePill = pill
    return pill
end

-- The unlock toolbar is the shared control surface for every unlocked mover,
-- whether it came from the global arrange action or an individual lock toggle.
-- Only global arrange owns a rollback snapshot, so Cancel is exclusive to it.
function CooldownCompanion:RefreshUnlockToolbar()
    if not self:IsUnlockToolbarActive() then
        if not self:IsArrangeModeActive() then
            self._arrangeFocusContainerId = nil
            self._arrangeChromeHidden = nil
            self._arrangeSoloContainerId = nil
            self._arrangeSelectedPanelId = nil
            self._arrangeTreeRevealEntry = nil
            self._arrangePanelSuppressed = nil
            self._arrangeContainerSuppressed = nil
            -- The section selection dies with the panel selection, through
            -- the aware path (cancels its edits, repaints its chrome).
            if self.ClearArrangeSectionSelection then
                self:ClearArrangeSectionSelection()
            end
        end
        if self._arrangeModePill then
            self._arrangeModePill:Hide()
        end
        return
    end

    local pill = GetArrangeModePill(self)
    pill._listExpanded = true
    if pill._cancelButton then
        pill._cancelButton:SetShown(self:IsArrangeModeActive())
    end
    if not pill:IsShown() then
        pill:Show()
    else
        self:RefreshArrangePillList()
    end
end

-- Rebuild the pill's group list: one row per arrange-managed group, sorted by
-- name. Row name click pins the group's controls (WS2 focus); the checkbox is
-- the session-only chrome filter. Collapsed, the pill is just the top band.
-- The unlock toolbar lists the independent bar movers next to the group
-- containers. They share the containers' session-only chrome-hidden map and
-- solo slot, keyed by the string ids "cast" and "resource" -- collision-free
-- beside numeric container ids.
function CooldownCompanion:IsArrangeSpecialMoverId(id)
    return id == "cast" or id == "resource"
end

-- One unlock-eligibility gate for the special movers. Saved unlock state is
-- not enough on its own: the runtime mover only materializes when the bar
-- actually built for this character and spec. Toolbar rows, unlocked checks,
-- and arrange auto-exit all share this answer so a mover that never appeared
-- cannot hold arrange open or take a solo that shows nothing.
function CooldownCompanion:IsSpecialMoverUnlockEligible(id)
    if id == "cast" then
        local settings = self.GetCastBarSettings and self:GetCastBarSettings()
        if not (settings
            and settings.enabled == true
            and settings.independentAnchorEnabled == true
            and not settings.independentAnchorLocked) then
            return false
        end
        local frame = self.GetIndependentCastBarSnapFrame and self:GetIndependentCastBarSnapFrame()
        return frame ~= nil and frame:IsVisible() == true
    elseif id == "resource" then
        local settings = self.GetResourceBarSettings and self:GetResourceBarSettings()
        local layout = settings and self.GetSpecLayoutOrder and self:GetSpecLayoutOrder()
        if not (settings
            and settings.enabled == true
            and layout
            and layout.independentAnchorEnabled == true
            and not layout.independentAnchorLocked) then
            return false
        end
        local snapFrame = self.GetIndependentResourceStackSnapFrame and self:GetIndependentResourceStackSnapFrame()
        return snapFrame ~= nil and snapFrame:IsVisible() == true
    end
    return false
end

function CooldownCompanion:RefreshArrangeSpecialMoverChrome(id)
    if id == "cast" then
        if self.RefreshIndependentCastBarMoverChrome then
            self:RefreshIndependentCastBarMoverChrome()
        end
    elseif id == "resource" then
        if self.RefreshIndependentResourceStackMoverChrome then
            self:RefreshIndependentResourceStackMoverChrome()
        end
    end
end

function CooldownCompanion:RefreshArrangePillList()
    if ST.RefreshArrangeTreePill then
        return ST.RefreshArrangeTreePill(self)
    end
    local pill = self._arrangeModePill
    if not (pill and pill:IsShown()) then
        return
    end

    local ROW_HEIGHT = 18
    local rows = pill._rows
    if not rows then
        rows = {}
        pill._rows = rows
    end

    local entries = {}
    if self._arrangeModeActive then
        for containerId, container in pairs(self.db.profile.groupContainers or {}) do
            if container.locked == false
                and self:IsContainerVisibleToCurrentChar(containerId)
                and self:ContainerHasArrangeEligiblePanel(containerId) then
                entries[#entries + 1] = { id = containerId, name = container.name or ("Group " .. containerId) }
            end
        end
        if self:IsSpecialMoverUnlockEligible("cast") then
            entries[#entries + 1] = { id = "cast", name = "Cast Bar" }
        end
        if self:IsSpecialMoverUnlockEligible("resource") then
            entries[#entries + 1] = { id = "resource", name = "Resource Bars" }
        end
        table.sort(entries, function(a, b)
            if a.name == b.name then
                -- Mixed id types: special movers use string ids.
                return tostring(a.id) < tostring(b.id)
            end
            return a.name < b.name
        end)
    end

    local expanded = pill._listExpanded == true and #entries > 0
    if pill._expanderArrow then
        pill._expanderArrow:SetRotation(expanded and -math.pi / 2 or 0)
    end

    -- Cap the viewport so a large roster cannot push rows off screen; the
    -- overflow scrolls with the mouse wheel.
    local MAX_VISIBLE_ROWS = 12
    local maxOffset = math.max(0, #entries - MAX_VISIBLE_ROWS)
    local scrollOffset = pill._listScrollOffset or 0
    if scrollOffset > maxOffset then
        scrollOffset = maxOffset
    end
    if scrollOffset < 0 then
        scrollOffset = 0
    end
    pill._listScrollOffset = scrollOffset
    pill._listMaxScrollOffset = maxOffset
    local visibleCount = math.min(#entries, MAX_VISIBLE_ROWS)

    local function EnsureRow(index)
        local row = rows[index]
        if row then
            return row
        end

        row = CreateFrame("Button", nil, pill)
        row:SetHeight(ROW_HEIGHT)

        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        row.bg:SetColorTexture(1, 0.82, 0, 0.12)
        row.bg:Hide()

        row.check = CreateFrame("Button", nil, row, "BackdropTemplate")
        row.check:SetSize(12, 12)
        row.check:SetPoint("LEFT", row, "LEFT", 2, 0)
        row.check:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
        row.check:SetBackdropColor(0.16, 0.16, 0.16, 1)
        ST.CreatePixelBorders(row.check)
        row.check.fill = row.check:CreateTexture(nil, "OVERLAY")
        row.check.fill:SetSize(6, 6)
        row.check.fill:SetPoint("CENTER")
        row.check.fill:SetColorTexture(1, 0.82, 0, 0.9)
        row.check:SetScript("OnClick", function()
            if row.containerId then
                -- Toggle the MANUAL flag the checkbox renders; the effective
                -- state also folds in solo and would misread during one.
                local hiddenSet = CooldownCompanion._arrangeChromeHidden
                local manuallyHidden = hiddenSet ~= nil and hiddenSet[row.containerId] == true
                CooldownCompanion:SetContainerArrangeChromeHidden(row.containerId, not manuallyHidden)
                CooldownCompanion:RefreshArrangePillList()
            end
        end)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.name:SetPoint("LEFT", row.check, "RIGHT", 6, 0)
        row.name:SetPoint("RIGHT", row, "RIGHT", -2, 0)
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)

        row:SetScript("OnClick", function()
            local id = row.containerId
            if not id then
                return
            end
            local hiddenSet = CooldownCompanion._arrangeChromeHidden
            if hiddenSet and hiddenSet[id] == true then
                return
            end
            if CooldownCompanion._arrangeSoloContainerId == id then
                CooldownCompanion:SetArrangeSoloContainer(nil)
            else
                CooldownCompanion:SetArrangeSoloContainer(id)
            end
        end)
        row:SetScript("OnEnter", function(self)
            if not self._selected then
                self.bg:SetColorTexture(1, 1, 1, 0.06)
                self.bg:Show()
            end
        end)
        row:SetScript("OnLeave", function(self)
            if not self._selected then
                self.bg:Hide()
            end
        end)

        rows[index] = row
        return row
    end

    local maxNameWidth = 0
    for index = 1, visibleCount do
        local entry = entries[scrollOffset + index]
        local row = EnsureRow(index)
        row.containerId = entry.id
        row.name:SetText(entry.name)

        -- The checkbox mirrors the MANUAL flag; the gray name mirrors the
        -- effective state, so a solo grays the others without unticking them.
        local hiddenSet = self._arrangeChromeHidden
        local manuallyHidden = hiddenSet ~= nil and hiddenSet[entry.id] == true
        local hidden = self:IsContainerArrangeChromeHidden(entry.id)
        row.check.fill:SetShown(not manuallyHidden)
        row.name:SetTextColor(hidden and 0.55 or 1, hidden and 0.55 or 1, hidden and 0.55 or 1, 1)

        row._selected = self._arrangeFocusContainerId == entry.id and not hidden or nil
        if row._selected then
            row.bg:SetColorTexture(1, 0.82, 0, 0.12)
            row.bg:Show()
        elseif row:IsMouseOver() then
            row.bg:SetColorTexture(1, 1, 1, 0.06)
            row.bg:Show()
        else
            row.bg:Hide()
        end

        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", pill, "TOPLEFT", 8, -(30 + (index - 1) * ROW_HEIGHT))
        row:SetPoint("TOPRIGHT", pill, "TOPRIGHT", -8, -(30 + (index - 1) * ROW_HEIGHT))
        row:SetShown(expanded)

        local nameWidth = row.name:GetStringWidth() or 0
        if nameWidth > maxNameWidth then
            maxNameWidth = nameWidth
        end
    end

    for index = visibleCount + 1, #rows do
        rows[index].containerId = nil
        rows[index]:Hide()
    end

    if expanded then
        pill:SetSize(
            math.max(pill._baseWidth or 200, math.ceil(8 + 2 + 12 + 6 + maxNameWidth + 2 + 8 + 12)),
            30 + visibleCount * ROW_HEIGHT + 6
        )
    else
        pill:SetSize(pill._baseWidth or 200, 30)
    end
end

local function CancelActiveMoverDrag(addon, frame, activeField)
    if not (frame and frame[activeField]) then
        return
    end

    frame._dragCancelPending = true
    if not (InCombatLockdown() and frame:IsProtected()) then
        frame:StopMovingOrSizing()
    end
    if addon.EndDragSnapSession then
        addon:EndDragSnapSession(frame, false)
    end
    frame[activeField] = nil
end

local function CancelActiveMoverGestures(addon)
    if addon.ResetMoverChromeFade then
        addon:ResetMoverChromeFade()
    end
    if addon.CancelIndependentCastBarDrag then
        addon:CancelIndependentCastBarDrag()
    end
    if addon.CancelIndependentResourceStackDrag then
        addon:CancelIndependentResourceStackDrag()
    end

    for _, frame in pairs(addon.groupFrames or {}) do
        CancelActiveMoverDrag(addon, frame, "_dragInProgress")
        for _, button in ipairs(frame.buttons or {}) do
            CancelActiveMoverDrag(addon, button and button.auraTextureHost, "_isDragging")
        end
    end

    for _, frame in pairs(addon.containerFrames or {}) do
        CancelActiveMoverDrag(addon, frame, "_dragInProgress")
    end
end

function CooldownCompanion:BeginCombatForcedLock()
    if self._combatForcedLock then
        return false
    end

    local snapshot = {
        containers = {},
        groups = {},
        hadUnlocked = false,
    }

    for containerId, container in pairs(self.db.profile.groupContainers or {}) do
        if container
            and container.locked == false
            and self:IsContainerVisibleToCurrentChar(containerId)
        then
            snapshot.containers[containerId] = true
            snapshot.hadUnlocked = true
        end
    end

    for groupId, group in pairs(self.db.profile.groups or {}) do
        if group
            and group.locked == false
            and self:IsGroupVisibleToCurrentChar(groupId)
        then
            snapshot.groups[groupId] = true
            snapshot.hadUnlocked = true
        end
    end

    self._combatForcedLock = true
    self._combatForcedLockSnapshot = snapshot
    self._arrangeSelectedPanelId = nil
    self._arrangeSoloContainerId = nil
    self._arrangeFocusContainerId = nil
    -- The panel selection just went; the section selection goes with it
    -- (the aware path cancels its typed edits before the chrome comes down).
    if self.ClearArrangeSectionSelection then
        self:ClearArrangeSectionSelection()
    end

    if self._arrangeModePill then
        self._arrangeModePill:Hide()
    end
    CancelActiveMoverGestures(self)
    -- Combat hands cursor panels back to the real cursor: the arrange pin
    -- (and any config selection preview) suspends for the fight. The
    -- forced-lock flag above makes this a full clear, not a demote.
    if self.ClearCursorAnchorLayoutPreview then
        self:ClearCursorAnchorLayoutPreview()
    end

    for groupId, frame in pairs(self.groupFrames or {}) do
        local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
        frame._containerUnlockPreviewActive = nil
        frame._panelUnlockPreviewActive = nil
        frame._unlockGhost = nil
        local active = group and self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = true,
            checkLoadConditions = true,
            requireButtons = true,
        }) or false

        frame._combatForcedHidden = not active or nil
        SuppressFrameVisibilityForCombat(frame.dragHandle)
        SuppressFrameVisibilityForCombat(frame.coordLabel)
        SuppressFrameVisibilityForCombat(frame.dragHelpButton)
        SuppressFrameVisibilityForCombat(frame.nudger)
        -- The chrome just came down without going through
        -- SetGroupDragControlsShown, so explicitly remove the Aura Panel's
        -- frame-owned placeholder preview too. The live aura display stays
        -- bound and resumes for the fight; no rebind is possible in combat.
        self:SetAuraPanelPlaceholderPreviewShown(frame, false)
        -- The section click overlays are chrome by the same argument, and
        -- they hold mouse focus over live icons -- they may not do that in
        -- combat.
        ST.SetSectionMoverOverlaysShown(self, frame, group, false)
        ForceCombatMouseLock(frame)
        ForceCombatMouseLock(frame.dragHandle)
        ForceCombatMouseLock(frame.dragHelpButton)
        ForceCombatMouseLock(frame.nudger)
        for _, button in ipairs(frame.buttons or {}) do
            local buttonData = button and button.buttonData
            if CooldownCompanion:IsAuraShellEntry(buttonData) then
                ST._ApplyShellVisualsForButton(button, buttonData)
            end
            local host = button and button.auraTextureHost or nil
            if host then
                host._unlockGhost = nil
                host._dragEnabled = false
                ForceCombatMouseLock(host)
                SuppressFrameVisibilityForCombat(host.dragHandle)
                SuppressFrameVisibilityForCombat(host.coordLabel)
                SuppressFrameVisibilityForCombat(host.dragHelpButton)
                SuppressFrameVisibilityForCombat(host.nudger)
                ForceCombatMouseLock(host.dragHelpButton)
                if host.auraTextureOutlineFill then
                    host.auraTextureOutlineFill:Hide()
                end
                for _, edge in ipairs(host.auraTextureOutlineEdges or {}) do
                    edge:Hide()
                end
            end
            if not active and self.HideAuraTextureVisual then
                self:HideAuraTextureVisual(button)
            end
        end

        if active then
            local frameAlpha = (group and group.baselineAlpha) or 1
            frameAlpha = self:GetPanelCurrentAlphaValue(groupId, group)
            frame:SetAlpha(frameAlpha)
        elseif frame:IsProtected() then
            frame:SetAlpha(0)
        else
            frame:Hide()
        end
    end

    if self.containerFrames then
        for containerId, frame in pairs(self.containerFrames) do
            self:UpdateContainerDragHandle(containerId, true)
        end
    end

    return snapshot.hadUnlocked
end

function CooldownCompanion:EndCombatForcedLock()
    if not self._combatForcedLock then
        return nil
    end

    local snapshot = self._combatForcedLockSnapshot
    self._combatForcedLock = nil
    self._combatForcedLockSnapshot = nil

    for _, frame in pairs(self.groupFrames or {}) do
        frame._combatForcedHidden = nil
        RestoreFrameVisibilityAfterCombat(frame.dragHandle)
        RestoreFrameVisibilityAfterCombat(frame.coordLabel)
        RestoreFrameVisibilityAfterCombat(frame.dragHelpButton)
        RestoreFrameVisibilityAfterCombat(frame.nudger)
        -- Restore the placeholder preview immediately. Container Arrange Mode
        -- previews every member even though only the selected member has drag
        -- controls; RefreshAllGroups below re-asserts the same state.
        local group = frame.groupId and self.db.profile.groups[frame.groupId]
        local containerPreviewActive = group and group.parentContainerId
            and self:IsContainerUnlockPreviewActive(group.parentContainerId)
            or false
        local handleShown = (frame.dragHandle and frame.dragHandle:IsShown()) == true
        self:SetAuraPanelPlaceholderPreviewShown(frame, handleShown or containerPreviewActive)
        -- Section overlays share the aura placeholder preview's wide gate:
        -- drag controls up, or any member of an active container preview.
        ST.SetSectionMoverOverlaysShown(self, frame, group,
            handleShown or containerPreviewActive)
        for _, button in ipairs(frame.buttons or {}) do
            local host = button and button.auraTextureHost or nil
            RestoreFrameVisibilityAfterCombat(host and host.dragHandle or nil)
            RestoreFrameVisibilityAfterCombat(host and host.coordLabel or nil)
            RestoreFrameVisibilityAfterCombat(host and host.dragHelpButton or nil)
            RestoreFrameVisibilityAfterCombat(host and host.nudger or nil)
        end
    end

    for _, frame in pairs(self.containerFrames or {}) do
        RestoreFrameVisibilityAfterCombat(frame.dragHandle)
        RestoreFrameVisibilityAfterCombat(frame.dragHandle and frame.dragHandle.header or nil)
        RestoreFrameVisibilityAfterCombat(frame.coordLabel)
        RestoreFrameVisibilityAfterCombat(frame.nudger)
        for _, label in pairs(frame._containerPanelLabels or {}) do
            RestoreFrameVisibilityAfterCombat(label)
        end
    end

    local arrangeModeActive = self._arrangeModeActive == true
    local castSettings = self.GetCastBarSettings and self:GetCastBarSettings()
    local restoreCastMover = arrangeModeActive
        or (castSettings
            and castSettings.enabled == true
            and castSettings.independentAnchorEnabled == true
            and not castSettings.independentAnchorLocked)
    if restoreCastMover and self.ApplyCastBarSettings then
        self:ApplyCastBarSettings()
    end

    local resourceSettings = self.GetResourceBarSettings and self:GetResourceBarSettings()
    local resourceLayout = resourceSettings
        and self.GetSpecLayoutOrder
        and self:GetSpecLayoutOrder()
    local restoreResourceMover = arrangeModeActive
        or (resourceSettings
            and resourceSettings.enabled == true
            and resourceLayout
            and resourceLayout.independentAnchorEnabled == true
            and not resourceLayout.independentAnchorLocked)
    if restoreResourceMover and self.ApplyResourceBars then
        self:ApplyResourceBars()
    end

    -- Resume individual cursor unlocks as well as the global arrange pin.
    if self.ShowCursorAnchorLayoutPreview then
        self:ShowCursorAnchorLayoutPreview(nil)
    end
    self:RefreshUnlockToolbar()

    return snapshot
end

-- Shared by the group context menu and the group multi-select surface;
-- callers own the config-panel refresh.
function CooldownCompanion:SetContainerEnabled(containerId, enabled)
    local container = self.db.profile.groupContainers[containerId]
    if not container then return end
    container.enabled = enabled
    self:RefreshContainerPanels(containerId)
end

function CooldownCompanion:SetContainerLocked(containerId, locked)
    local container = self.db.profile.groupContainers[containerId]
    if not container then return end
    local toolbarWasActive = self:IsUnlockToolbarActive()
    local suppressionChanged = false
    if locked and toolbarWasActive and self:IsArrangeModeActive() then
        self._arrangeContainerSuppressed = self._arrangeContainerSuppressed or {}
        suppressionChanged = self._arrangeContainerSuppressed[containerId] ~= true
        self._arrangeContainerSuppressed[containerId] = true
    elseif not locked then
        if self._arrangeContainerSuppressed and self._arrangeContainerSuppressed[containerId] then
            self._arrangeContainerSuppressed[containerId] = nil
            suppressionChanged = true
            if not next(self._arrangeContainerSuppressed) then
                self._arrangeContainerSuppressed = nil
            end
        end
        suppressionChanged = self:ClearArrangePanelSuppressionsForContainer(containerId)
            or suppressionChanged
    end
    -- Locking the soloed group would strand every other group solo-hidden
    -- with no chrome anywhere; release the solo first.
    if locked and self._arrangeSoloContainerId == containerId and self.SetArrangeSoloContainer then
        self:SetArrangeSoloContainer(nil)
    end
    container.locked = locked
    self:UpdateContainerDragHandle(containerId, locked)
    self:RefreshContainerPanels(containerId)
    if suppressionChanged
        and self._arrangeModeActive
        and self._cursorAnchorLayoutPreview
        and self.ShowCursorAnchorLayoutPreview then
        self:RefreshCursorAnchorLayoutPreview()
    end
    self:RefreshUnlockToolbar()
end

function CooldownCompanion:SetPanelLocked(panelId, locked)
    local group = self.db.profile.groups[panelId]
    if not group then return end
    local containerId = group.parentContainerId
    local isCursorAnchored = self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group)
    if locked
        and self._arrangeSelectedPanelId == panelId
        and self.ClearArrangeMoverSelection then
        self:ClearArrangeMoverSelection()
    end
    if locked then
        group.locked = nil
    else
        group.locked = false
    end
    -- Suppression can rebuild the cursor preview. Keep a sibling's selection
    -- through that rebuild so its chrome and shared mover selection agree.
    local selectedCursorPanelId = self._cursorAnchorLayoutPreview
        and self._cursorAnchorLayoutPreview.selectedGroupId
    self:SetArrangePanelSuppressed(panelId, locked)
    if isCursorAnchored then
        self:ShowCursorAnchorLayoutPreview(selectedCursorPanelId)
        if not locked then
            -- Select through the shared owner so cursor chrome, panel selection,
            -- and solo state move together, even between panels in one group.
            self:ActivateArrangePanel(containerId, panelId, false)
        end
    else
        self:RefreshGroupFrame(panelId)
    end
    -- Panels are not part of the arrange-managed set (arrange unlocks containers,
    -- and panel padlocks hide while their container is unlocked), so this must not
    -- be the broader CheckArrangeModeAutoExit: a bulk multi-select lock would then
    -- evaluate an arrange exit once per panel and could exit partway through.
    if locked then
        self:CheckConfigReExpandAfterLock()
    end
    -- Once the last panel mover in an unlocked group is padlocked, the group
    -- wrapper has nothing left to operate on. Lock it too instead of leaving
    -- an empty border/title mover behind.
    if locked
        and containerId
        and self:IsContainerUnlockPreviewActive(containerId)
        and not self:ContainerHasArrangeEligiblePanel(containerId) then
        self:SetContainerLocked(containerId, true)
        self:CaptureArrangeContainerRecord(containerId)
        return
    end
    self:RefreshUnlockToolbar()
end

-- Refresh all panel frames belonging to a container.
function CooldownCompanion:RefreshContainerPanels(containerId)
    for gid, group in pairs(self.db.profile.groups) do
        if group.parentContainerId == containerId then
            self:RefreshGroupFrame(gid)
        end
    end
end

-- Show or hide the drag handle on a container frame to match its lock state.
function CooldownCompanion:UpdateContainerDragHandle(containerId, locked)
    local cFrame = self.containerFrames and self.containerFrames[containerId]
    if cFrame and cFrame.dragHandle then
        local effectiveLocked = locked or self._combatForcedLock
        if effectiveLocked then
            if self.ClearContainerUnlockState then
                self:ClearContainerUnlockState(containerId)
            end
            SuppressFrameVisibilityForCombat(cFrame.dragHandle)
            SuppressFrameVisibilityForCombat(cFrame.dragHandle and cFrame.dragHandle.header or nil)
            SuppressFrameVisibilityForCombat(cFrame.coordLabel)
            SuppressFrameVisibilityForCombat(cFrame.nudger)
            if cFrame._containerPanelLabels then
                for _, label in pairs(cFrame._containerPanelLabels) do
                    SuppressFrameVisibilityForCombat(label)
                end
            end
        elseif self.RefreshContainerWrapper then
            self:RefreshContainerWrapper(containerId)
        else
            cFrame.dragHandle:Show()
        end
    end
end

function CooldownCompanion:LockAllFrames()
    self._arrangePanelSuppressed = nil
    self._arrangeContainerSuppressed = nil
    -- Lock every container, including containers hidden for this character.
    -- Write the bulk state directly: SetContainerLocked refreshes that
    -- container's panels, while the single RefreshAllGroups below reconciles
    -- the complete runtime once after every lock value is settled.
    for _, container in pairs(self.db.profile.groupContainers or {}) do
        container.locked = true
    end
    -- Also lock any individually-unlocked panels
    for groupId, group in pairs(self.db.profile.groups) do
        if group.locked == false then
            group.locked = nil
        end
    end
    if self.ClearCursorAnchorLayoutPreview then
        self:ClearCursorAnchorLayoutPreview(true)
    end
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            if self.SetGroupDragControlsShown then
                self:SetGroupDragControlsShown(frame, false)
            elseif frame.dragHandle then
                frame.dragHandle:Hide()
            end
        end
    end
    -- Lock container frames
    if self.containerFrames then
        for containerId in pairs(self.containerFrames) do
            self:UpdateContainerDragHandle(containerId, true)
        end
    end
    self:RefreshAllGroups()
    self:RefreshUnlockToolbar()
end

function CooldownCompanion:UnlockAllFrames()
    -- Unlock containers only; individual panels retain their own lock state
    for groupId, frame in pairs(self.groupFrames) do
        if frame then
            self:UpdateGroupClickthrough(groupId)
            local group = self.db.profile.groups[groupId]
            local panelUnlocked = group
                and group.locked == false
                and not self._combatForcedLock
                and not (self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group))
            if panelUnlocked and self.SetGroupDragControlsShown then
                self:SetGroupDragControlsShown(frame, true)
            elseif panelUnlocked and frame.dragHandle then
                frame.dragHandle:Show()
            end
            if panelUnlocked then
                frame:SetAlpha(GetUnlockedPanelAlpha(frame))
            end
        end
    end
    -- Unlock container frames
    if self.containerFrames then
        for containerId in pairs(self.containerFrames) do
            local container = self.db.profile.groupContainers[containerId]
            -- nil means locked; only an explicit false unlocks a container.
            self:UpdateContainerDragHandle(containerId, not container or container.locked ~= false)
        end
    end
    self:RefreshAllGroups()
    self:RefreshUnlockToolbar()
end

function CooldownCompanion:EnterArrangeMode()
    if InCombatLockdown() or self._combatForcedLock then
        self:Print("Cannot unlock during combat.")
        return
    end
    if self._arrangeModeActive then
        return
    end

    self:CaptureArrangeSnapshot()
    self._arrangeModeActive = true
    self._arrangeFocusContainerId = nil
    self._arrangeChromeHidden = nil
    self._arrangeSoloContainerId = nil
    self._arrangeSelectedPanelId = nil
    self._arrangeSectionGroupId = nil
    self._arrangeSectionAnchor = nil
    self._arrangeTreeRevealEntry = nil
    self._arrangePanelSuppressed = nil
    self._arrangeContainerSuppressed = nil
    for containerId in pairs(self.db.profile.groupContainers or {}) do
        if self:IsContainerVisibleToCurrentChar(containerId)
            and self:ContainerHasArrangeEligiblePanel(containerId) then
            self:SetContainerLocked(containerId, false)
        end
    end
    if self.SetIndependentCastBarLocked then
        self:SetIndependentCastBarLocked(false)
    end
    if self.SetIndependentResourceStackLocked then
        self:SetIndependentResourceStackLocked(false)
    end
    if ST.CollapseConfigForUnlock then
        ST.CollapseConfigForUnlock()
    end
    -- Cursor-anchored panels chase the live cursor, which would sweep their
    -- mover chrome across every other outline mid-arrange. Park them on the
    -- dummy cursor for the whole unlock instead.
    if self.ShowCursorAnchorLayoutPreview then
        self:ShowCursorAnchorLayoutPreview(nil)
    end
    local pill = GetArrangeModePill(self)
    -- The group list is where solo focus and chrome hiding live; start every
    -- unlock with it open so those controls are discoverable.
    pill._listScrollOffset = 0
    self:RefreshUnlockToolbar()
    self:Print("All frames unlocked. Drag to move.")
end

function CooldownCompanion:ExitArrangeMode(opts)
    self._arrangeSnapshot = nil
    self._arrangeModeActive = nil
    self._arrangeFocusContainerId = nil
    self._arrangeChromeHidden = nil
    self._arrangeSoloContainerId = nil
    self._arrangeSelectedPanelId = nil
    self._arrangeSectionGroupId = nil
    self._arrangeSectionAnchor = nil
    self._arrangeTreeRevealEntry = nil
    self._arrangePanelSuppressed = nil
    self._arrangeContainerSuppressed = nil
    CancelActiveMoverGestures(self)
    -- LockAllFrames tears down cursor previews after clearing saved unlocks.
    self:LockAllFrames()
    if self.SetIndependentCastBarLocked then
        self:SetIndependentCastBarLocked(true)
    end
    if self.SetIndependentResourceStackLocked then
        self:SetIndependentResourceStackLocked(true)
    end
    if self._arrangeModePill then
        self._arrangeModePill:Hide()
    end
    if self.RefreshConfigPanel then
        self:RefreshConfigPanel()
    end
    if not (opts and opts.silent) then
        self:Print("All frames locked.")
    end
    if not (opts and opts.skipConfigReExpand) then
        self:CheckConfigReExpandAfterLock()
    end
end

function CooldownCompanion:CancelArrangeMode()
    if not self._arrangeModeActive then
        return
    end
    if InCombatLockdown() or self._combatForcedLock then
        self:Print("Cannot cancel unlocking during combat.")
        return
    end

    local snapshot = self._arrangeSnapshot
    self._arrangeSnapshot = nil
    self:ExitArrangeMode({ silent = true, skipConfigReExpand = true })
    if snapshot then
        RestoreArrangeSnapshot(self, snapshot)
    end
    self:Print("Unlock cancelled. Unsaved changes reverted.")
end

-- Private helpers consumed by later GroupOperations files.
ST._GetUnlockedPanelAlpha = GetUnlockedPanelAlpha
