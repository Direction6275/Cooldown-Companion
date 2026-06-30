--[[
    CooldownCompanion - Core/GroupManagement.lua: Group/folder CRUD, AddButtonToGroup,
    RemoveButtonFromGroup, spell search (FindTalentSpellByName)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local InCombatLockdown = InCombatLockdown
local math_floor = math.floor
local table_sort = table.sort
local table_remove = table.remove
local IsDistinctAuraViewerFrameForSpell = ST.IsDistinctAuraViewerFrameForSpell
local GROUP_SETTING_PRESET_MODES = {
    icons = true,
    bars = true,
    text = true,
}

local DIRECT_STYLE_COPY_MODES = {
    icons = true,
    bars = true,
}

local function IsValidGroupSettingPresetMode(mode)
    return GROUP_SETTING_PRESET_MODES[mode] == true
end

local function IsValidDirectStyleCopyMode(mode)
    return DIRECT_STYLE_COPY_MODES[mode] == true
end

local function ShouldClearCDMPanelSourceForDisplayMode(group, displayMode)
    if not (group and group.cdmPanelSource) then
        return false
    end

    local getSourceDisplayMode = ST._GetCDMPanelSourceDisplayMode
    if not getSourceDisplayMode then
        return false
    end

    local expectedMode = getSourceDisplayMode(group.cdmPanelSource)
    return expectedMode == nil or expectedMode ~= displayMode
end

local function GetAnchorOffset(point, width, height)
    local halfW = (width or 0) / 2
    local halfH = (height or 0) / 2
    if point == "TOPLEFT" then return -halfW, halfH end
    if point == "TOP" then return 0, halfH end
    if point == "TOPRIGHT" then return halfW, halfH end
    if point == "LEFT" then return -halfW, 0 end
    if point == "CENTER" then return 0, 0 end
    if point == "RIGHT" then return halfW, 0 end
    if point == "BOTTOMLEFT" then return -halfW, -halfH end
    if point == "BOTTOM" then return 0, -halfH end
    if point == "BOTTOMRIGHT" then return halfW, -halfH end
    return 0, 0
end

local function RoundAnchorOffset(value)
    return math_floor(((value or 0) * 10) + 0.5) / 10
end

local function GetFrameSizeInUIParentSpace(frame)
    if not (frame and frame.GetSize) then
        return nil, nil
    end

    local width, height = frame:GetSize()
    if not (width and height) then
        return width, height
    end

    local frameScale = frame.GetEffectiveScale and frame:GetEffectiveScale() or nil
    local uiScale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or nil
    if frameScale and uiScale and uiScale > 0 then
        local scaleRatio = frameScale / uiScale
        width = width * scaleRatio
        height = height * scaleRatio
    end

    return width, height
end

local function IsAddonAnchorFrameName(frameName)
    if type(frameName) ~= "string" then
        return false
    end
    if CooldownCompanion.GetAddonAnchorTargetInfo then
        local info = CooldownCompanion:GetAddonAnchorTargetInfo(frameName)
        return info and (info.kind == "container" or info.kind == "group" or info.kind == "cursor") or false
    end
    return frameName:match("^CooldownCompanionContainer%d+$") ~= nil
        or frameName:match("^CooldownCompanionGroup%d+$") ~= nil
        or frameName == "CooldownCompanionCursor"
end

local function IsFrameLikeAnchorTarget(frame)
    return type(frame) == "table" and type(frame.GetObjectType) == "function"
end

local function RefreshPanelAlphaDependencyTargets(self)
    if self.RebuildPanelAlphaDependencyTargets then
        self:RebuildPanelAlphaDependencyTargets()
    end
end

local function NormalizeCopiedEntityForContainerScope(self, entity, container)
    if type(entity) ~= "table" or not container or container.isGlobal == true then
        return
    end
    if self.NormalizeEligibilityForCharacterScope then
        local opts = {
            ownerCharKey = container.createdBy or (self.db and self.db.keys and self.db.keys.char),
        }
        self:NormalizeEligibilityForCharacterScope(entity, opts)
        if type(entity.buttons) == "table" then
            for _, button in ipairs(entity.buttons) do
                self:NormalizeEligibilityForCharacterScope(button, opts)
            end
        end
    end
end

local function ClearInvalidCopiedFolderId(self, entity, sourceEntity)
    if type(entity) ~= "table" or not entity.folderId then
        return
    end
    if sourceEntity and sourceEntity.isGlobal then
        entity.folderId = nil
        return
    end
    if self.CanMoveContainerToFolder then
        local ok = self:CanMoveContainerToFolder(entity, entity.folderId)
        if not ok then
            entity.folderId = nil
        end
    end
end

function CooldownCompanion:NormalizeContainerAnchor(anchor, resolveAddonFrames)
    local normalized = type(anchor) == "table" and anchor or {}
    local point = normalized.point or "CENTER"
    local relativeTo = normalized.relativeTo or "UIParent"
    local relativePoint = normalized.relativePoint or "CENTER"
    local x = tonumber(normalized.x) or 0
    local y = tonumber(normalized.y) or 0
    local newX = RoundAnchorOffset(x)
    local newY = RoundAnchorOffset(y)
    local changed = (normalized.point ~= "CENTER")
        or (normalized.relativeTo ~= "UIParent")
        or (normalized.relativePoint ~= "CENTER")
        or (normalized.x ~= newX)
        or (normalized.y ~= newY)

    if point ~= "CENTER" or relativeTo ~= "UIParent" or relativePoint ~= "CENTER" then
        if IsAddonAnchorFrameName(relativeTo) and not resolveAddonFrames then
            normalized.x = newX
            normalized.y = newY
            return normalized, changed, true
        end

        local relativeFrame
        if relativeTo == "UIParent" then
            relativeFrame = UIParent
        elseif type(relativeTo) == "table" then
            relativeFrame = relativeTo
        elseif type(relativeTo) == "string" then
            relativeFrame = _G[relativeTo]
        end

        if not (relativeFrame and relativeFrame.GetCenter and relativeFrame.GetSize) then
            normalized.x = newX
            normalized.y = newY
            return normalized, changed, true
        end

        local rcx, rcy = relativeFrame:GetCenter()
        local rw, rh = GetFrameSizeInUIParentSpace(relativeFrame)
        local ucx, ucy = UIParent:GetCenter()

        if not (rcx and rcy and rw and rh and ucx and ucy) then
            normalized.x = newX
            normalized.y = newY
            return normalized, changed, true
        end

        local rax, ray = GetAnchorOffset(relativePoint, rw, rh)
        local fax, fay = GetAnchorOffset(point, 1, 1)
        local frameCenterX = rcx + rax + x - fax
        local frameCenterY = rcy + ray + y - fay
        newX = RoundAnchorOffset(frameCenterX - ucx)
        newY = RoundAnchorOffset(frameCenterY - ucy)
    end

    normalized.point = "CENTER"
    normalized.relativeTo = "UIParent"
    normalized.relativePoint = "CENTER"
    normalized.x = newX
    normalized.y = newY

    return normalized, changed, false
end

function CooldownCompanion:FinalizeContainerAnchorsToScreenOffsets()
    local containers = self.db and self.db.profile and self.db.profile.groupContainers
    if not containers then return end

    for containerId, container in pairs(containers) do
        if type(container) == "table" and self:IsContainerVisibleToCurrentChar(containerId) then
            local anchor = type(container.anchor) == "table" and container.anchor or nil
            local relativeTo = anchor and anchor.relativeTo
            local skipFinalize = IsAddonAnchorFrameName(relativeTo)
                and self.GetContainerAnchorTargetState
                and self:GetContainerAnchorTargetState(containerId, relativeTo) == "unsafe"

            if not skipFinalize then
                local normalized, changed, deferred = self:NormalizeContainerAnchor(container.anchor, true)
                if not deferred then
                    container.anchor = normalized
                    if changed then
                        local frame = self.containerFrames and self.containerFrames[containerId]
                        if frame then
                            self:AnchorContainerFrame(frame, container.anchor)
                        end
                    end
                end
            end
        end
    end
end

local function SyncTexturePanelPositionFromGroupFrame(self, groupId, group)
    if not (self and groupId and type(group) == "table") then
        return
    end

    local settings
    if group.displayMode == "trigger" then
        settings = self:GetTriggerPanelSignalSettings(group, true)
    else
        settings = self:GetTexturePanelSettings(group, true)
    end
    local frame = self.groupFrames and self.groupFrames[groupId]
    local anchor = type(group.anchor) == "table" and group.anchor or nil
    local point = (anchor and anchor.point) or "CENTER"
    local relativePoint = (anchor and anchor.relativePoint) or "CENTER"
    local relativeTo = anchor and anchor.relativeTo or nil
    local ownContainerFrame = group.parentContainerId and ("CooldownCompanionContainer" .. tostring(group.parentContainerId)) or nil
    if type(relativeTo) == "string"
        and relativeTo ~= "UIParent"
        and relativeTo ~= ownContainerFrame
        and not self:IsCursorAnchor(relativeTo) then
        local options = self.GetGroupAnchorValidationOptions and self:GetGroupAnchorValidationOptions(groupId) or nil
        local ok = not self.ValidateAddonFrameAnchorTarget or self:ValidateAddonFrameAnchorTarget(relativeTo, options)
        if ok then
            settings.point = point
            settings.relativePoint = relativePoint
            settings.relativeTo = relativeTo
            settings.x = RoundAnchorOffset(tonumber(anchor and anchor.x) or 0)
            settings.y = RoundAnchorOffset(tonumber(anchor and anchor.y) or 0)
            return
        end
    end

    if frame and frame.GetCenter then
        local cx, cy = frame:GetCenter()
        local fw, fh = frame:GetSize()
        local rcx, rcy = UIParent:GetCenter()
        local rw, rh = UIParent:GetSize()

        if cx and cy and fw and fh and rcx and rcy and rw and rh then
            local fax, fay = GetAnchorOffset(point, fw, fh)
            local framePtX = cx + fax
            local framePtY = cy + fay
            local rax, ray = GetAnchorOffset(relativePoint, rw, rh)
            local refPtX = rcx + rax
            local refPtY = rcy + ray

            settings.point = point
            settings.relativePoint = relativePoint
            settings.relativeTo = "UIParent"
            settings.x = RoundAnchorOffset(framePtX - refPtX)
            settings.y = RoundAnchorOffset(framePtY - refPtY)
            return
        end
    end

    settings.point = point
    settings.relativePoint = relativePoint
    settings.relativeTo = "UIParent"
    settings.x = tonumber(anchor and anchor.x) or 0
    settings.y = tonumber(anchor and anchor.y) or 0
end

local function SyncGroupAnchorFromTexturePanelSettings(self, groupId, group)
    if not (self and groupId and type(group) == "table") then
        return
    end

    local settings
    if group.displayMode == "trigger" then
        settings = self:GetTriggerPanelSignalSettings(group)
    else
        settings = self:GetTexturePanelSettings(group)
    end
    if not settings then
        return
    end

    if self:IsCursorAnchor(group.anchor) then
        return
    end

    group.anchor = group.anchor or {}

    local point = settings.point or group.anchor.point or "CENTER"
    local relativePoint = settings.relativePoint or group.anchor.relativePoint or "CENTER"
    local settingsRelativeTo = type(settings.relativeTo) == "string" and settings.relativeTo or nil
    if settingsRelativeTo and settingsRelativeTo ~= "UIParent" then
        local targetFrame = _G[settingsRelativeTo]
        local options = self.GetGroupAnchorValidationOptions and self:GetGroupAnchorValidationOptions(groupId) or nil
        local ok = not self.ValidateAddonFrameAnchorTarget or self:ValidateAddonFrameAnchorTarget(settingsRelativeTo, options)
        if ok and (targetFrame == nil or IsFrameLikeAnchorTarget(targetFrame)) then
            group.anchor.point = point
            group.anchor.relativeTo = settingsRelativeTo
            group.anchor.relativePoint = relativePoint
            group.anchor.x = RoundAnchorOffset(tonumber(settings.x) or 0)
            group.anchor.y = RoundAnchorOffset(tonumber(settings.y) or 0)
            return
        end
    end

    local relativeTo = group.anchor.relativeTo or "UIParent"
    local relFrame = nil

    if relativeTo ~= "UIParent" then
        relFrame = _G[relativeTo]
        if not (relFrame and relFrame.GetCenter and relFrame.GetSize) then
            relativeTo = "UIParent"
            relFrame = nil
        end
    end

    if not relFrame then
        relFrame = UIParent
    end

    local rw, rh = relFrame:GetSize()
    local rcx, rcy = relFrame:GetCenter()
    local uw, uh = UIParent:GetSize()
    local ucx, ucy = UIParent:GetCenter()

    if rw and rh and rcx and rcy and uw and uh and ucx and ucy then
        local uiAnchorX, uiAnchorY = GetAnchorOffset(relativePoint, uw, uh)
        local screenPtX = ucx + uiAnchorX + (tonumber(settings.x) or 0)
        local screenPtY = ucy + uiAnchorY + (tonumber(settings.y) or 0)
        local relAnchorX, relAnchorY = GetAnchorOffset(relativePoint, rw, rh)
        local refPtX = rcx + relAnchorX
        local refPtY = rcy + relAnchorY

        group.anchor.point = point
        group.anchor.relativeTo = relativeTo
        group.anchor.relativePoint = relativePoint
        group.anchor.x = RoundAnchorOffset(screenPtX - refPtX)
        group.anchor.y = RoundAnchorOffset(screenPtY - refPtY)
        return
    end

    group.anchor.point = point
    group.anchor.relativeTo = relativeTo
    group.anchor.relativePoint = relativePoint
    group.anchor.x = tonumber(settings.x) or 0
    group.anchor.y = tonumber(settings.y) or 0
end

local function CopyPresetValue(v)
    if type(v) == "table" then
        return CopyTable(v)
    end
    return v
end

local function GetGroupDisplayMode(group)
    if group and group.displayMode == "bars" then
        return "bars"
    end
    return "icons"
end

local function GroupMatchesDirectStyleCopyMode(group, mode)
    if not group or not IsValidDirectStyleCopyMode(mode) then
        return false
    end
    if mode == "bars" then
        return group.displayMode == "bars"
    end
    return group.displayMode == nil or group.displayMode == "icons"
end

function CooldownCompanion:CanCopyDirectStyleFromPanel(mode, sourceGroupId, targetGroupId)
    sourceGroupId = tonumber(sourceGroupId)
    targetGroupId = tonumber(targetGroupId)
    if not IsValidDirectStyleCopyMode(mode) then
        return false, "invalid_mode"
    end

    local db = self.db and self.db.profile
    local sourceGroup = db and db.groups and db.groups[sourceGroupId]
    local targetGroup = db and db.groups and db.groups[targetGroupId]
    if not sourceGroup or not targetGroup then
        return false, "missing_group"
    end
    if sourceGroupId == targetGroupId then
        return false, "same_group"
    end
    if not GroupMatchesDirectStyleCopyMode(sourceGroup, mode)
        or not GroupMatchesDirectStyleCopyMode(targetGroup, mode) then
        return false, "mode_mismatch"
    end

    if self.ResolveContainerClassScope
        and sourceGroup.parentContainerId
        and targetGroup.parentContainerId then
        local sourceScope = self:ResolveContainerClassScope(sourceGroup.parentContainerId)
        local targetScope = self:ResolveContainerClassScope(targetGroup.parentContainerId)
        if not sourceScope or not targetScope or sourceScope.isInvalid or targetScope.isInvalid then
            return false, "invalid_class_scope"
        end
        if sourceScope.runtimeVisible == true then
            return true
        end
        if sourceScope.isOtherClass
            and targetScope.isOtherClass
            and sourceScope.ownerClassKey == targetScope.ownerClassKey then
            return true
        end
        return false, "source_unavailable"
    end

    if self:IsGroupVisibleToCurrentChar(sourceGroupId) then
        return true
    end
    return false, "source_unavailable"
end

local function CopyCompactLayoutSettings(sourceGroup, targetGroup)
    targetGroup.compactLayout = sourceGroup.compactLayout == true
    targetGroup.compactGrowthDirection = sourceGroup.compactGrowthDirection or "center"

    local sourceMaxVisible = tonumber(sourceGroup.maxVisibleButtons) or 0
    local targetButtonCount = targetGroup.buttons and #targetGroup.buttons or 0
    if sourceMaxVisible > 0 and targetButtonCount > 0 then
        targetGroup.maxVisibleButtons = math.min(sourceMaxVisible, targetButtonCount)
        if targetGroup.maxVisibleButtons >= targetButtonCount then
            targetGroup.maxVisibleButtons = 0
        end
    else
        targetGroup.maxVisibleButtons = 0
    end
end

local function BuildGroupSettingPresetBaseline(profile, mode)
    local style = CopyTable(profile.globalStyle or {})
    if mode == "bars" then
        style.orientation = "vertical"
    else
        style.orientation = "horizontal"
    end
    style.buttonsPerRow = 12
    style.showCooldownText = true

    local groupData = {}

    if mode == "icons" then
        groupData.masqueEnabled = false
    end

    return {
        style = style,
        group = groupData,
    }
end

local function CaptureGroupSettingPresetData(profile, mode, group)
    local baseline = BuildGroupSettingPresetBaseline(profile, mode)
    local data = {
        version = 1,
        style = CopyTable(group.style or baseline.style),
        group = CopyTable(baseline.group),
    }

    if mode == "icons" then
        data.group.masqueEnabled = group.masqueEnabled and true or false
    end

    return data
end

local function ApplyGroupSettingPresetData(profile, group, mode, presetData)
    local baseline = BuildGroupSettingPresetBaseline(profile, mode)
    local groupData = presetData and presetData.group
    local styleData = presetData and presetData.style

    if mode == "icons" then
        group.masqueEnabled = nil
    end

    group.style = CopyTable(baseline.style)
    for key, value in pairs(baseline.group) do
        group[key] = CopyPresetValue(value)
    end

    if type(groupData) == "table" then
        if mode == "icons" and groupData.masqueEnabled ~= nil then
            group.masqueEnabled = groupData.masqueEnabled and true or false
        end
    end

    if type(styleData) == "table" then
        for key, value in pairs(styleData) do
            group.style[key] = CopyPresetValue(value)
        end
    end

    -- Expand legacy 4-element strataOrder from older presets
    local so = group.style.strataOrder
    if type(so) == "table" and #so == 4 then
        local cooldownPos
        for i = 1, 4 do
            if so[i] == "cooldown" then cooldownPos = i; break end
        end
        local insertAt = (cooldownPos or 0) + 1
        table.insert(so, insertAt, "auraGlow")
        table.insert(so, insertAt + 1, "readyGlow")
    end
end

-- Group Management Functions
function CooldownCompanion:NormalizeGroupSettingPresetsStore()
    local profile = self.db and self.db.profile
    if not profile then return nil end

    if type(profile.groupSettingPresets) ~= "table" then
        profile.groupSettingPresets = {}
    end

    local store = profile.groupSettingPresets
    if type(store.icons) ~= "table" then
        store.icons = {}
    end
    if type(store.bars) ~= "table" then
        store.bars = {}
    end

    return store
end

function CooldownCompanion:GetGroupSettingPresetList(mode)
    if not IsValidGroupSettingPresetMode(mode) then
        return {}, {}
    end

    local store = self:NormalizeGroupSettingPresetsStore()
    if not store then
        return {}, {}
    end

    local list = {}
    local order = {}
    for presetName, presetData in pairs(store[mode]) do
        if type(presetName) == "string" and presetName ~= "" and type(presetData) == "table" then
            list[presetName] = presetName
            order[#order + 1] = presetName
        end
    end
    table_sort(order)

    return list, order
end

function CooldownCompanion:SaveGroupSettingPreset(mode, presetName, groupId, opts)
    opts = opts or {}
    if not IsValidGroupSettingPresetMode(mode) then
        return false, "invalid_mode"
    end
    if type(presetName) ~= "string" or presetName == "" then
        return false, "invalid_name"
    end

    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not group then
        return false, "missing_group"
    end
    if GetGroupDisplayMode(group) ~= mode then
        return false, "mode_mismatch"
    end

    local store = self:NormalizeGroupSettingPresetsStore()
    if not store then
        return false, "missing_store"
    end

    if not opts.allowOverwrite and store[mode][presetName] ~= nil then
        return false, "already_exists"
    end

    store[mode][presetName] = CaptureGroupSettingPresetData(self.db.profile, mode, group)
    return true
end

function CooldownCompanion:DeleteGroupSettingPreset(mode, presetName)
    if not IsValidGroupSettingPresetMode(mode) then
        return false, "invalid_mode"
    end
    if type(presetName) ~= "string" or presetName == "" then
        return false, "invalid_name"
    end

    local store = self:NormalizeGroupSettingPresetsStore()
    if not store then
        return false, "missing_store"
    end
    if store[mode][presetName] == nil then
        return false, "missing_preset"
    end

    store[mode][presetName] = nil
    return true
end

function CooldownCompanion:ApplyGroupSettingPreset(mode, presetName, groupId)
    if not IsValidGroupSettingPresetMode(mode) then
        return false, "invalid_mode"
    end
    if type(presetName) ~= "string" or presetName == "" then
        return false, "invalid_name"
    end

    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not group then
        return false, "missing_group"
    end
    if GetGroupDisplayMode(group) ~= mode then
        return false, "mode_mismatch"
    end

    local store = self:NormalizeGroupSettingPresetsStore()
    local presetData = store and store[mode] and store[mode][presetName]
    if type(presetData) ~= "table" then
        return false, "missing_preset"
    end

    local oldMasqueEnabled = group.masqueEnabled and true or false
    ApplyGroupSettingPresetData(self.db.profile, group, mode, presetData)
    local newMasqueEnabled = group.masqueEnabled and true or false

    -- Presets can be imported from clients with Masque enabled.
    -- If Masque is unavailable on this client, do not leave groups flagged
    -- as Masque-enabled because that disables icon controls in config.
    if mode == "icons" and not self.Masque and newMasqueEnabled then
        group.masqueEnabled = false
        newMasqueEnabled = false
    end

    -- Keep Masque's internal group/button lifecycle in sync when preset apply
    -- flips skinning state for icon groups.
    if mode == "icons" and self.Masque and oldMasqueEnabled ~= newMasqueEnabled then
        self:ToggleGroupMasque(groupId, newMasqueEnabled)
    end

    self:RefreshGroupFrame(groupId)
    return true
end

function CooldownCompanion:GetDirectStyleCopyPanelList(mode, targetGroupId)
    targetGroupId = tonumber(targetGroupId)
    if not IsValidDirectStyleCopyMode(mode) then
        return {}, {}
    end

    local db = self.db and self.db.profile
    if not db then
        return {}, {}
    end

    local targetGroup = db.groups and db.groups[targetGroupId]
    if not GroupMatchesDirectStyleCopyMode(targetGroup, mode) then
        return {}, {}
    end

    local list = {}
    local order = {}
    local sortData = {}
    for groupId, group in pairs(db.groups or {}) do
        if groupId ~= targetGroupId
            and GroupMatchesDirectStyleCopyMode(group, mode)
            and self:CanCopyDirectStyleFromPanel(mode, groupId, targetGroupId) then
            local parentContainer = self:GetParentContainer(group)
            local containerName = parentContainer and parentContainer.name
                or group.name
                or ("Panel " .. tostring(groupId))
            local panelName = group.name or ("Panel " .. tostring(groupId))
            local label = containerName
            if parentContainer and panelName ~= containerName then
                label = containerName .. " - " .. panelName
            end
            local orderValue = parentContainer
                and self:GetOrderForSpec(parentContainer, self._currentSpecId, group.parentContainerId)
                or (group.order or groupId)

            list[groupId] = label
            order[#order + 1] = groupId
            sortData[groupId] = {
                order = orderValue or groupId,
                panelOrder = group.order or groupId,
                label = label,
            }
        end
    end

    table_sort(order, function(a, b)
        local left = sortData[a]
        local right = sortData[b]
        if left.order ~= right.order then
            return left.order < right.order
        end
        if left.panelOrder ~= right.panelOrder then
            return left.panelOrder < right.panelOrder
        end
        return left.label < right.label
    end)

    return list, order
end

function CooldownCompanion:CopyDirectStyleFromPanel(mode, sourceGroupId, targetGroupId)
    sourceGroupId = tonumber(sourceGroupId)
    targetGroupId = tonumber(targetGroupId)

    local canCopy, reason = self:CanCopyDirectStyleFromPanel(mode, sourceGroupId, targetGroupId)
    if not canCopy then
        return false, reason
    end

    local db = self.db and self.db.profile
    local sourceGroup = db and db.groups and db.groups[sourceGroupId]
    local targetGroup = db and db.groups and db.groups[targetGroupId]

    local oldMasqueEnabled = targetGroup.masqueEnabled and true or false
    local presetData = CaptureGroupSettingPresetData(db, mode, sourceGroup)
    ApplyGroupSettingPresetData(db, targetGroup, mode, presetData)
    CopyCompactLayoutSettings(sourceGroup, targetGroup)
    local newMasqueEnabled = targetGroup.masqueEnabled and true or false

    if mode == "icons" and not self.Masque and newMasqueEnabled then
        targetGroup.masqueEnabled = false
        newMasqueEnabled = false
    end

    local frame = self.groupFrames and self.groupFrames[targetGroupId]
    if InCombatLockdown() and (not frame or frame:IsProtected()) then
        if frame then
            frame._layoutDirty = true
        end
        self._pendingFullRefresh = true
        return true
    end

    if mode == "icons" and self.Masque and oldMasqueEnabled ~= newMasqueEnabled then
        self:ToggleGroupMasque(targetGroupId, newMasqueEnabled)
    end

    if self.PopulateGroupButtons then
        self:PopulateGroupButtons(targetGroupId)
    end
    if frame then
        frame._layoutDirty = true
    end
    self:RefreshGroupFrame(targetGroupId)
    return true
end

------------------------------------------------------------------------
-- Container & Panel Helpers
------------------------------------------------------------------------

-- Returns a sorted array of { groupId = id, group = groupData } for all panels
-- belonging to the given container, ordered by panel.order.
function CooldownCompanion:GetPanels(containerId)
    local panels = {}
    for groupId, group in pairs(self.db.profile.groups) do
        if group.parentContainerId == containerId then
            panels[#panels + 1] = { groupId = groupId, group = group }
        end
    end
    table_sort(panels, function(a, b)
        return (a.group.order or 0) < (b.group.order or 0)
    end)
    return panels
end

function CooldownCompanion:GetPanelCount(containerId)
    local count = 0
    for _, group in pairs(self.db.profile.groups) do
        if group.parentContainerId == containerId then
            count = count + 1
        end
    end
    return count
end

------------------------------------------------------------------------
-- Container CRUD
------------------------------------------------------------------------

function CooldownCompanion:CreateContainer(name)
    local db = self.db.profile
    local containerId = db.nextContainerId
    db.nextContainerId = containerId + 1

    db.groupContainers[containerId] = {
        name = name or "New Group",
        order = containerId,
        createdBy = self.db.keys.char,
        isGlobal = false,
        enabled = true,
        locked = true,
        -- Alpha fade defaults
        groupAlphaEnabled = false,
        baselineAlpha = 1,
        forceAlphaInCombat = false,
        forceAlphaOutOfCombat = false,
        forceAlphaRegularMounted = false,
        forceAlphaDragonriding = false,
        forceAlphaTargetExists = false,
        forceAlphaTargetEnemyOnly = false,
        forceAlphaFocusExists = false,
        forceAlphaMouseover = false,
        forceHideInCombat = false,
        forceHideOutOfCombat = false,
        forceHideRegularMounted = false,
        forceHideDragonriding = false,
        treatTravelFormAsMounted = false,
        fadeDelay = 1,
        fadeInDuration = 0.2,
        fadeOutDuration = 0.2,
        -- Anchor (invisible container frame)
        anchor = {
            point = "CENTER",
            relativeTo = "UIParent",
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
    }
    if self._currentSpecId then
        db.groupContainers[containerId].specs = {
            [self._currentSpecId] = true,
        }
    end

    return containerId
end

local ResetStandalonePanelAnchorsTargeting

function CooldownCompanion:DeleteContainer(containerId)
    local db = self.db.profile
    if not db.groupContainers[containerId] then return end

    -- Delete all child panels first
    local panelIds = {}
    local deletedGroupIds = {}
    for groupId, group in pairs(db.groups) do
        if group.parentContainerId == containerId then
            panelIds[#panelIds + 1] = groupId
            deletedGroupIds[groupId] = true
        end
    end
    ResetStandalonePanelAnchorsTargeting(db.groups, deletedGroupIds, { [containerId] = true })
    for _, groupId in ipairs(panelIds) do
        self:UnloadGroup(groupId)
        self:DiscardDormantFrame(groupId)
        db.groups[groupId] = nil
    end

    -- Clean up container frame
    if self.containerFrames and self.containerFrames[containerId] then
        self.containerFrames[containerId]:Hide()
        self.containerFrames[containerId] = nil
    end

    db.groupContainers[containerId] = nil
    if self.ClearContainerAlphaRuntimeState then
        self:ClearContainerAlphaRuntimeState(containerId)
    end
    RefreshPanelAlphaDependencyTargets(self)
end

local function GetStandalonePanelAnchorSettings(panel)
    if not CooldownCompanion.GetStandaloneTextureAnchorSettings then
        return nil
    end
    return CooldownCompanion:GetStandaloneTextureAnchorSettings(panel)
end

local function ParseStandaloneAddonAnchorTarget(relativeTo)
    if type(relativeTo) ~= "string" then
        return nil
    end
    local groupId = relativeTo:match("^CooldownCompanionGroup(%d+)$")
    if groupId then
        return "group", tonumber(groupId)
    end
    local containerId = relativeTo:match("^CooldownCompanionContainer(%d+)$")
    if containerId then
        return "container", tonumber(containerId)
    end
    return nil
end

local function GetStandaloneAddonAnchorTarget(panel)
    local settings = GetStandalonePanelAnchorSettings(panel)
    local relativeTo = type(settings) == "table" and settings.relativeTo or nil
    local kind, id = ParseStandaloneAddonAnchorTarget(relativeTo)
    return kind, id, relativeTo
end

local function GetStandalonePanelAnchorTarget(panel)
    local settings = GetStandalonePanelAnchorSettings(panel)
    local relativeTo = type(settings) == "table" and settings.relativeTo or nil
    return settings, type(relativeTo) == "string" and relativeTo or nil
end

local function ResetStandalonePanelAnchor(panel)
    local settings = GetStandalonePanelAnchorSettings(panel)
    if type(settings) ~= "table" then
        return
    end
    settings.point = "CENTER"
    settings.relativeTo = "UIParent"
    settings.relativePoint = "CENTER"
    settings.x = 0
    settings.y = 0
end

ResetStandalonePanelAnchorsTargeting = function(groups, deletedGroupIds, deletedContainerIds)
    if type(groups) ~= "table" then
        return
    end
    deletedGroupIds = type(deletedGroupIds) == "table" and deletedGroupIds or {}
    deletedContainerIds = type(deletedContainerIds) == "table" and deletedContainerIds or {}

    for groupId, panel in pairs(groups) do
        if not deletedGroupIds[groupId] then
            local targetKind, targetId = GetStandaloneAddonAnchorTarget(panel)
            if (targetKind == "group" and deletedGroupIds[targetId])
                or (targetKind == "container" and deletedContainerIds[targetId]) then
                ResetStandalonePanelAnchor(panel)
            end
        end
    end
end

local function RemapDuplicatedStandalonePanelAnchor(panel, groupIdMap, containerIdMap)
    local settings, relativeTo = GetStandalonePanelAnchorTarget(panel)
    if not settings or not relativeTo or relativeTo == "UIParent" then
        return
    end

    local targetKind, targetId = ParseStandaloneAddonAnchorTarget(relativeTo)
    if targetKind == "group" then
        local newTargetId = targetId and groupIdMap[targetId] or nil
        if newTargetId then
            settings.relativeTo = "CooldownCompanionGroup" .. tostring(newTargetId)
        else
            ResetStandalonePanelAnchor(panel)
        end
    elseif targetKind == "container" then
        local newTargetId = targetId and containerIdMap and containerIdMap[targetId] or nil
        if newTargetId then
            settings.relativeTo = "CooldownCompanionContainer" .. tostring(newTargetId)
        else
            ResetStandalonePanelAnchor(panel)
        end
    elseif relativeTo:find("^CooldownCompanion") then
        ResetStandalonePanelAnchor(panel)
    else
        return
    end
end

local function ResetCopiedStandalonePanelAnchor(panel, groups, sourceGroupId, sourceContainerId, targetContainerId)
    local settings, relativeTo = GetStandalonePanelAnchorTarget(panel)
    if not settings or not relativeTo or relativeTo == "UIParent" then
        return
    end

    local targetKind, targetId = ParseStandaloneAddonAnchorTarget(relativeTo)
    if not targetKind then
        if relativeTo:find("^CooldownCompanion") then
            ResetStandalonePanelAnchor(panel)
        end
        return
    end

    if targetKind == "container" then
        if targetId ~= targetContainerId then
            ResetStandalonePanelAnchor(panel)
        end
        return
    end

    if targetKind ~= "group" then
        ResetStandalonePanelAnchor(panel)
        return
    end

    local targetGroup = groups and groups[targetId] or nil
    if targetId == sourceGroupId
        or not targetGroup
        or targetGroup.parentContainerId ~= targetContainerId then
        ResetStandalonePanelAnchor(panel)
    end
end

function CooldownCompanion:DuplicateContainer(containerId)
    local db = self.db.profile
    local sourceContainer = db.groupContainers[containerId]
    if not sourceContainer then return nil end

    local newContainerId = db.nextContainerId
    db.nextContainerId = newContainerId + 1

    local newContainer = CopyTable(sourceContainer)
    newContainer.name = sourceContainer.name .. " (Copy)"
    newContainer.order = newContainerId
    newContainer.specOrders = nil
    newContainer.createdBy = self.db.keys.char
    newContainer.isGlobal = false
    NormalizeCopiedEntityForContainerScope(self, newContainer, newContainer)
    ClearInvalidCopiedFolderId(self, newContainer, sourceContainer)

    db.groupContainers[newContainerId] = newContainer

    -- Collect source panel IDs first (avoid modifying db.groups during pairs iteration)
    local sourcePanelIds = {}
    for groupId, group in pairs(db.groups) do
        if group.parentContainerId == containerId then
            sourcePanelIds[#sourcePanelIds + 1] = groupId
        end
    end

    -- Deep copy all child panels, re-anchoring to new container
    local containerFrameName = "CooldownCompanionContainer" .. newContainerId
    local groupIdMap = {}
    for _, groupId in ipairs(sourcePanelIds) do
        local group = db.groups[groupId]
        if group then
            local newGroupId = db.nextGroupId
            db.nextGroupId = newGroupId + 1

            local newPanel = CopyTable(group)
            newPanel.cdmPanelSource = nil
            newPanel.parentContainerId = newContainerId
            newPanel.anchor = {
                point = "CENTER",
                relativeTo = containerFrameName,
                relativePoint = "CENTER",
                x = group.anchor and group.anchor.x or 0,
                y = group.anchor and group.anchor.y or 0,
            }
            NormalizeCopiedEntityForContainerScope(self, newPanel, newContainer)

            db.groups[newGroupId] = newPanel
            groupIdMap[groupId] = newGroupId
            self:CreateGroupFrame(newGroupId)
        end
    end

    local containerIdMap = { [containerId] = newContainerId }
    for _, newGroupId in pairs(groupIdMap) do
        RemapDuplicatedStandalonePanelAnchor(db.groups[newGroupId], groupIdMap, containerIdMap)
    end

    -- Create container frame (Phase 3 — safe noop if method doesn't exist yet)
    if self.CreateContainerFrame then
        self:CreateContainerFrame(newContainerId)
    end
    if self.FinalizeContainerAnchorsToScreenOffsets then
        self:FinalizeContainerAnchorsToScreenOffsets()
    end
    RefreshPanelAlphaDependencyTargets(self)

    return newContainerId
end

------------------------------------------------------------------------
-- Panel CRUD (within containers)
------------------------------------------------------------------------

function CooldownCompanion:CreatePanel(containerId, displayMode)
    local db = self.db.profile
    local container = db.groupContainers[containerId]
    if not container then return nil end
    displayMode = displayMode or "icons"
    local isRotationAssistant = ST.IsRotationAssistantDisplayMode
        and ST.IsRotationAssistantDisplayMode(displayMode)

    local groupId = db.nextGroupId
    db.nextGroupId = groupId + 1

    local panelOrder = self:GetPanelCount(containerId) + 1
    local containerFrameName = "CooldownCompanionContainer" .. containerId

    db.groups[groupId] = {
        name = isRotationAssistant and ST.ROTATION_ASSISTANT_NAME or ("Panel " .. panelOrder),
        parentContainerId = containerId,
        order = panelOrder,
        anchor = {
            point = "CENTER",
            relativeTo = containerFrameName,
            relativePoint = "CENTER",
            x = 0,
            y = 0,
        },
        buttons = {},
        style = CopyTable(db.globalStyle),
        displayMode = displayMode,
        masqueEnabled = false,
        compactLayout = true,
        maxVisibleButtons = 0,
        compactGrowthDirection = "center",
        inheritPanelAlpha = true,
        -- Alpha fade defaults (panels own their own alpha)
        baselineAlpha = 1,
        fadeDelay = 1,
        fadeInDuration = 0.2,
        fadeOutDuration = 0.2,
    }

    -- Style defaults (nil-guard respects user-customized globalStyle)
    local style = db.groups[groupId].style
    style.orientation = "horizontal"
    style.growthOrigin = "TOPLEFT"
    style.buttonsPerRow = 12
    style.showCooldownText = true
    if style.desaturateOnCooldown == nil then style.desaturateOnCooldown = true end
    if style.showOutOfRange == nil then style.showOutOfRange = true end
    if style.showGCDSwipe == nil then style.showGCDSwipe = false end
    if style.showLossOfControl == nil then style.showLossOfControl = true end
    if style.showTooltips == nil then style.showTooltips = false end
    if style.showUnusable == nil then style.showUnusable = true end
    if style.unusableVisualMode == nil then style.unusableVisualMode = "dim" end
    if style.showCooldownSwipe == nil then style.showCooldownSwipe = true end
    if style.showCooldownSwipeFill == nil then style.showCooldownSwipeFill = true end
    if style.auraUseBlizzardSwipe == nil then style.auraUseBlizzardSwipe = false end
    if style.iconFillEnabled == nil then style.iconFillEnabled = false end
    if style.iconFillOrientation == nil then style.iconFillOrientation = "vertical" end
    if style.iconFillReverse == nil then style.iconFillReverse = false end
    if style.iconFillTimerBehavior == nil then style.iconFillTimerBehavior = "drain" end
    if style.iconFillCooldownColor == nil then style.iconFillCooldownColor = {0.6, 0.13, 0.18, 0.55} end
    if style.iconFillAuraColor == nil then style.iconFillAuraColor = {0.2, 1.0, 0.2, 0.55} end
    if style.barAuraEffect == nil then style.barAuraEffect = "color" end
    if style.barAuraIndicatorEnabled == nil then
        style.barAuraIndicatorEnabled = (style.barAuraEffect or "none") ~= "none"
    end
    if isRotationAssistant then
        style.orientation = "horizontal"
        style.growthOrigin = "TOPLEFT"
        style.buttonsPerRow = 1
        style.maintainAspectRatio = true
        style.showCooldownText = false
        style.showChargeText = false
        style.showAuraText = false
        style.showAuraStackText = false
        style.showAssistedHighlight = false
        style.showLossOfControl = false
        style.showUnusable = false
        style.procGlowStyle = "none"
        style.pandemicGlowStyle = "none"
        style.readyGlowStyle = "none"
        style.keyPressHighlightStyle = "none"
        style.iconFillEnabled = false
        style.auraUseBlizzardSwipe = false
    end

    if displayMode == "textures" then
        db.groups[groupId].textureSettings = {
            blendMode = "BLEND",
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
            x = 0,
            y = 0,
        }
    elseif displayMode == "trigger" then
        db.groups[groupId].triggerSettings = {
            displayType = "texture",
            signal = {
                blendMode = "BLEND",
                point = "CENTER",
                relativePoint = "CENTER",
                relativeTo = "UIParent",
                x = 0,
                y = 0,
            },
            effects = {},
        }
    end

    self:CreateGroupFrame(groupId)
    return groupId
end

function CooldownCompanion:DeletePanel(containerId, groupId)
    local db = self.db.profile
    local group = db.groups[groupId]
    if not group or group.parentContainerId ~= containerId then return false end

    ResetStandalonePanelAnchorsTargeting(db.groups, { [groupId] = true })
    self:UnloadGroup(groupId)
    self:DiscardDormantFrame(groupId)
    db.groups[groupId] = nil
    RefreshPanelAlphaDependencyTargets(self)
    return true
end

function CooldownCompanion:DuplicatePanel(containerId, groupId)
    local db = self.db.profile
    local sourcePanel = db.groups[groupId]
    if not sourcePanel or sourcePanel.parentContainerId ~= containerId then return nil end
    local container = db.groupContainers[containerId]

    local newGroupId = db.nextGroupId
    db.nextGroupId = newGroupId + 1

    local newPanel = CopyTable(sourcePanel)
    newPanel.name = sourcePanel.name .. " (Copy)"
    newPanel.order = self:GetPanelCount(containerId) + 1
    newPanel.cdmPanelSource = nil
    ResetCopiedStandalonePanelAnchor(newPanel, db.groups, groupId, containerId, containerId)
    NormalizeCopiedEntityForContainerScope(self, newPanel, container)

    db.groups[newGroupId] = newPanel
    self:CreateGroupFrame(newGroupId)
    RefreshPanelAlphaDependencyTargets(self)
    return newGroupId
end

function CooldownCompanion:MovePanel(groupId, targetContainerId)
    local db = self.db.profile
    local group
    if self.CanMovePanelToContainer then
        local ok, reason = self:CanMovePanelToContainer(groupId, targetContainerId)
        if not ok then
            if self.Print
                and (reason == "invalid-class-scope"
                    or reason == "scope-mismatch"
                    or reason == "mixed-class-panel") then
                self:Print("Panels cannot be moved into groups owned by another class.")
            end
            return false
        end
        group = db.groups[groupId]
    else
        group = db.groups[groupId]
        if not group or not group.parentContainerId then return false end
        if not db.groupContainers[targetContainerId] then return false end
        if group.parentContainerId == targetContainerId then return false end
    end

    local sourceContainerId = group.parentContainerId

    -- Reassign to target container
    group.parentContainerId = targetContainerId

    -- Reset anchor to center of new container frame
    local containerFrameName = "CooldownCompanionContainer" .. targetContainerId
    group.anchor = {
        point = "CENTER",
        relativeTo = containerFrameName,
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
    ResetCopiedStandalonePanelAnchor(group, db.groups, groupId, sourceContainerId, targetContainerId)

    -- Put at end of target's panel list (GetPanelCount already sees the moved panel)
    group.order = self:GetPanelCount(targetContainerId)

    -- Force alpha re-evaluation with new container context
    if self.alphaState then
        self.alphaState[groupId] = nil
    end

    self:RefreshGroupFrame(groupId)

    -- If source container is now empty, delete it
    local sourceDeleted = false
    if self:GetPanelCount(sourceContainerId) == 0 then
        self:DeleteContainer(sourceContainerId)
        sourceDeleted = true
    end

    RefreshPanelAlphaDependencyTargets(self)
    return true, sourceDeleted
end

function CooldownCompanion:ChangePanelDisplayMode(groupId, newMode)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    local oldMode = group.displayMode
    if oldMode ~= newMode
        and (ST.IsRotationAssistantDisplayMode(oldMode) or ST.IsRotationAssistantDisplayMode(newMode)) then
        self:Print("Assistant Panels cannot be converted. Create a new Assistant Panel instead.")
        return false
    end

    if oldMode ~= newMode and (oldMode == "trigger" or newMode == "trigger") then
        self:Print("Trigger Panels cannot be converted. Create a new Trigger Panel instead.")
        return false
    end

    if newMode == "textures" and #group.buttons > 1 then
        self:Print("Texture Panels can only hold one entry. Remove extra entries first, or create a new Texture Panel.")
        return false
    end

    if (oldMode == "textures" or oldMode == "trigger") and newMode ~= oldMode then
        -- Leaving texture mode should carry the standalone texture position
        -- back into the normal panel anchor so the panel does not jump back.
        SyncGroupAnchorFromTexturePanelSettings(self, groupId, group)
    end

    group.displayMode = newMode
    if oldMode ~= newMode and ShouldClearCDMPanelSourceForDisplayMode(group, newMode) then
        group.cdmPanelSource = nil
    end
    if newMode == "bars" or newMode == "text" then
        group.style.orientation = "vertical"
    end
    if newMode ~= "icons" and group.masqueEnabled and self.ToggleGroupMasque then
        self:ToggleGroupMasque(groupId, false)
    end
    if newMode == "textures" or newMode == "trigger" then
        -- Entering texture mode switches from group.anchor to textureSettings,
        -- so convert the panel's current on-screen position once here.
        SyncTexturePanelPositionFromGroupFrame(self, groupId, group)
    end
    if newMode == "trigger" then
        group.triggerSettings = group.triggerSettings or {
            displayType = "texture",
            signal = {
                blendMode = "BLEND",
                point = "CENTER",
                relativePoint = "CENTER",
                relativeTo = "UIParent",
                x = 0,
                y = 0,
            },
            effects = {},
        }
        if group.triggerSettings.displayType == nil then
            group.triggerSettings.displayType = "texture"
        end
        if type(group.triggerSettings.effects) ~= "table" then
            group.triggerSettings.effects = {}
        end
        if self.NormalizeTriggerConditionRowData then
            for _, buttonData in ipairs(group.buttons or {}) do
                self:NormalizeTriggerConditionRowData(buttonData)
            end
        end
    end
    RefreshPanelAlphaDependencyTargets(self)
    self:RefreshGroupFrame(groupId)
    return true
end

------------------------------------------------------------------------
-- Public Group API (container + panel combo operations)
------------------------------------------------------------------------

function CooldownCompanion:CreateGroup(name)
    local containerId = self:CreateContainer(name)

    -- Create container frame (Phase 3 — safe noop if method doesn't exist yet)
    if self.CreateContainerFrame then
        self:CreateContainerFrame(containerId)
    end

    return containerId
end

function CooldownCompanion:DeleteGroup(id)
    -- If this is a containerId, delete the container and all its panels
    if self.db.profile.groupContainers[id] then
        self:DeleteContainer(id)
        return
    end

    -- Otherwise treat as a panel groupId
    local group = self.db.profile.groups[id]
    if not group then return end

    local parentId = group.parentContainerId

    ResetStandalonePanelAnchorsTargeting(self.db.profile.groups, { [id] = true })
    self:UnloadGroup(id)
    self:DiscardDormantFrame(id)
    self.db.profile.groups[id] = nil

    -- If this was the last panel, delete the parent container too
    if parentId and self:GetPanelCount(parentId) == 0 then
        self:DeleteContainer(parentId)
    end
    RefreshPanelAlphaDependencyTargets(self)
end

function CooldownCompanion:DuplicateGroup(id)
    -- If this is a containerId, duplicate the container and all panels
    if self.db.profile.groupContainers[id] then
        return self:DuplicateContainer(id)
    end

    -- Otherwise treat as a panel groupId
    local sourceGroup = self.db.profile.groups[id]
    if not sourceGroup then return nil end

    -- If the panel belongs to a container, duplicate within it
    if sourceGroup.parentContainerId then
        return self:DuplicatePanel(sourceGroup.parentContainerId, id)
    end

    -- Legacy path (no container) — should not happen post-migration
    local newGroupId = self.db.profile.nextGroupId
    self.db.profile.nextGroupId = newGroupId + 1

    local newGroup = CopyTable(sourceGroup)
    newGroup.name = sourceGroup.name .. " (Copy)"
    newGroup.order = newGroupId
    newGroup.cdmPanelSource = nil
    newGroup.createdBy = self.db.keys.char
    newGroup.isGlobal = false
    NormalizeCopiedEntityForContainerScope(self, newGroup, newGroup)
    ClearInvalidCopiedFolderId(self, newGroup, sourceGroup)

    self.db.profile.groups[newGroupId] = newGroup
    self:CreateGroupFrame(newGroupId)
    RefreshPanelAlphaDependencyTargets(self)
    return newGroupId
end

function CooldownCompanion:CreateFolder(name, section)
    local db = self.db.profile
    local folderId = db.nextFolderId
    db.nextFolderId = folderId + 1
    db.folders[folderId] = {
        name = name,
        order = folderId,
        section = section or "char",
        createdBy = self.db.keys.char,
    }
    return folderId
end

function CooldownCompanion:DeleteFolder(folderId)
    local db = self.db.profile
    if not db.folders[folderId] then return end
    -- Collect child container IDs first (avoid modifying table during pairs iteration)
    local childIds = {}
    for containerId, container in pairs(db.groupContainers) do
        if container.folderId == folderId then
            childIds[#childIds + 1] = containerId
        end
    end
    for _, containerId in ipairs(childIds) do
        self:DeleteContainer(containerId)
    end
    db.folders[folderId] = nil
end

function CooldownCompanion:RenameFolder(folderId, newName)
    local folder = self.db.profile.folders[folderId]
    if not folder then return false end
    local normalizedName = tostring(newName or ""):match("^%s*(.-)%s*$")
    if normalizedName == "" then return false end
    folder.name = normalizedName
    return true
end

function CooldownCompanion:MoveGroupToFolder(id, folderId, opts)
    local db = self.db.profile

    -- Resolve to container (id may be containerId or panel groupId)
    local containerId = id
    local container = db.groupContainers[id]
    if not container then
        local group = db.groups[id]
        if group and group.parentContainerId then
            containerId = group.parentContainerId
            container = db.groupContainers[containerId]
        end
    end
    if not container then return end

    if folderId and self.CanMoveContainerToFolder then
        local ok = self:CanMoveContainerToFolder(containerId, folderId, opts)
        if not ok then
            if self.Print then
                self:Print("Groups cannot be moved into folders owned by another class.")
            end
            return false
        end
    end

    container.folderId = folderId  -- nil = loose (no folder)

    -- When moving into a folder: clear custom icon (icons only shown on non-foldered
    -- containers) and stamp folder spec filters onto this container.
    if folderId then
        container.manualIcon = nil
        local folder = db.folders and db.folders[folderId]
        if folder and folder.specs and next(folder.specs) then
            container.specs = CopyTable(folder.specs)
        end
    end

    -- Refresh all panels in this container (folder change may affect visibility)
    local panels = self:GetPanels(containerId)
    for _, p in ipairs(panels) do
        self:RefreshGroupFrame(p.groupId)
    end
    return true
end

function CooldownCompanion:ToggleFolderGlobal(folderId)
    local db = self.db.profile
    local folder = db.folders[folderId]
    if not folder then return end
    local newSection = (folder.section == "global") and "char" or "global"
    folder.section = newSection
    if newSection == "char" then
        folder.createdBy = self.db.keys.char
    end
    -- Move all child containers to the new section
    for _, container in pairs(db.groupContainers) do
        if container.folderId == folderId then
            if newSection == "global" then
                container.isGlobal = true
            else
                container.isGlobal = false
                container.createdBy = self.db.keys.char
            end
        end
    end
    if newSection == "char" and self.NormalizeFolderEligibilityForCharacterScope then
        self:NormalizeFolderEligibilityForCharacterScope(folderId)
    end
    self:RefreshAllGroups()
end

function CooldownCompanion:ToggleGroupGlobal(containerId)
    local db = self.db.profile
    local container = db.groupContainers[containerId]
    if not container then return end

    local newGlobal = not container.isGlobal
    container.isGlobal = newGlobal
    if not newGlobal then
        container.createdBy = self.db.keys.char
        if self.NormalizeContainerEligibilityForCharacterScope then
            self:NormalizeContainerEligibilityForCharacterScope(containerId)
        end
    end

    self:RefreshAllGroups()
end

function CooldownCompanion:AddButtonToGroup(groupId, buttonType, id, name, isPetSpell, isPassive, forceAura, cdmChildSlot, preserveSpellID)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    local rejectMessage = self:GetPanelManualEntryRejectMessage(group)
    if rejectMessage then
        self:Print(rejectMessage)
        return nil
    end

    -- Resolve spell transforms to base spell ID so the override chain can
    -- freely reach all variant forms at runtime.  Skip for items (no spell
    -- transform system), pet spells (may not resolve through GetBaseSpell),
    -- forced aura entries, CDM child-slot buttons (viewer-frame mapping
    -- uses specific IDs), and CDM starter entries whose display metadata
    -- already selected the intended spell ID.
    local transformNotified
    if buttonType == "spell"
        and not isPetSpell
        and forceAura ~= true
        and not cdmChildSlot
        and preserveSpellID ~= true then
        local baseID = ST.ResolveToBaseSpell(id)
        if baseID ~= id then
            id = baseID
            name = C_Spell.GetSpellName(baseID) or name
        end
        -- Notify the user when the spell has an active transform so
        -- they understand why the panel may show a different name/icon.
        local overrideID = C_Spell.GetOverrideSpell(id)
        if overrideID and overrideID ~= 0 and overrideID ~= id then
            local baseName = C_Spell.GetSpellName(id) or name
            local overrideName = C_Spell.GetSpellName(overrideID)
            if overrideName and overrideName ~= baseName then
                self:Print("Added " .. baseName
                    .. " (currently showing as " .. overrideName
                    .. ") - tracks all spell variants.")
                transformNotified = true
            end
        end
    end

    local isPassiveCooldown = false
    if buttonType == "spell"
        and forceAura ~= true
        and ST.IsPassiveCooldownSpell
        and ST.IsPassiveCooldownSpell(id) then
        isPassiveCooldown = true
        isPassive = nil
        forceAura = false
    end

    local buttonIndex = #group.buttons + 1
    group.buttons[buttonIndex] = {
        type = buttonType,
        id = id,
        name = name,
        isPetSpell = isPetSpell or nil,
        isPassive = isPassive or nil,
        isPassiveCooldown = isPassiveCooldown or nil,
        cdmChildSlot = cdmChildSlot or nil,
    }

    -- Auto-detect charges for castable and passive-cooldown spells.
    -- Treat as charge-based only when max charges is greater than 1.
    if buttonType == "spell" and not isPassive then
        local chargeInfo, chargeQueryID, maxCharges = ST.ResolveSpellChargeInfo(id)
        if chargeInfo then
            local mc = maxCharges or chargeInfo.maxCharges
            if mc and mc > 1 then
                group.buttons[buttonIndex].hasCharges = true
                group.buttons[buttonIndex]._hasDisplayCount = nil
                group.buttons[buttonIndex]._displayCountFamily = nil
                group.buttons[buttonIndex].showChargeText = true
                group.buttons[buttonIndex].maxCharges = mc
            end
        else
            local rawDisplayCount = C_Spell.GetSpellDisplayCount(chargeQueryID)
            if not issecretvalue(rawDisplayCount) then
                local displayCount = tonumber(rawDisplayCount)
                if displayCount ~= nil then
                    group.buttons[buttonIndex]._hasDisplayCount = true
                    group.buttons[buttonIndex]._displayCountFamily = true
                    group.buttons[buttonIndex].showChargeText = true
                    if displayCount > (group.buttons[buttonIndex].maxCharges or 0) then
                        group.buttons[buttonIndex].maxCharges = displayCount
                    end
                else
                    group.buttons[buttonIndex]._hasDisplayCount = nil
                end
            end
            group.buttons[buttonIndex]._castCountCandidate = nil
            group.buttons[buttonIndex]._castCountConfirmed = nil
            group.buttons[buttonIndex]._castCountSeeded = nil
            group.buttons[buttonIndex]._castCountSelf = nil
            group.buttons[buttonIndex]._castCountEventSpellID = nil
            self._hasDisplayCountCandidates = true
        end
    end

    -- Auto-detect charges for items (e.g. Hellstone: GetItemCount with includeUses > plain count)
    if buttonType == "item" then
        self.UpdateItemChargeMetadata(group.buttons[buttonIndex], id)
    end

    -- Record original classification (immutable label for config display).
    -- This represents add intent, not current auraTracking state.
    if buttonType == "spell" then
        if forceAura == true or (isPassive and forceAura ~= false) then
            group.buttons[buttonIndex].addedAs = "aura"
        else
            group.buttons[buttonIndex].addedAs = "spell"
        end
    end

    -- Aura tracking: forceAura overrides auto-detection for dual-CDM spells
    if forceAura == true then
        group.buttons[buttonIndex].auraTracking = true
        group.buttons[buttonIndex].auraIndicatorEnabled = true
    elseif forceAura == nil then
        -- Force aura tracking for passive/proc spells
        if isPassive then
            group.buttons[buttonIndex].auraTracking = true
            group.buttons[buttonIndex].auraIndicatorEnabled = true
        end

        -- Auto-detect aura tracking for spells with viewer aura frames
        if buttonType == "spell" then
            local newButton = group.buttons[buttonIndex]
            local viewerFrame
            local foundViaAbilityBuffOverride = false
            local resolvedAuraId = C_UnitAuras.GetCooldownAuraBySpellID(id)
            viewerFrame = (resolvedAuraId and resolvedAuraId ~= 0
                    and self.viewerAuraFrames[resolvedAuraId])
                or self.viewerAuraFrames[id]
            if not viewerFrame then
                local child = self:FindViewerChildForSpell(id)
                if child then
                    self.viewerAuraFrames[id] = child
                    viewerFrame = child
                end
            end
            if not viewerFrame then
                local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[id]
                if overrideBuffs then
                    for buffId in overrideBuffs:gmatch("%d+") do
                        viewerFrame = self.viewerAuraFrames[tonumber(buffId)]
                        if viewerFrame then
                            foundViaAbilityBuffOverride = true
                            break
                        end
                    end
                end
            end
            local hasViewerFrame = false
            if viewerFrame and GetCVarBool("cooldownViewerEnabled") then
                local parent = viewerFrame:GetParent()
                local parentName = parent and parent:GetName()
                hasViewerFrame = parentName == "BuffIconCooldownViewer" or parentName == "BuffBarCooldownViewer"
            end
            if hasViewerFrame
                and not foundViaAbilityBuffOverride
                and IsDistinctAuraViewerFrameForSpell(newButton, viewerFrame) then
                newButton.auraTracking = false
                newButton.auraIndicatorEnabled = false
                hasViewerFrame = false
            end
            if hasViewerFrame then
                newButton.auraTracking = true
                newButton.auraIndicatorEnabled = true
                local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[id]
                if overrideBuffs and newButton.addedAs ~= "aura" then
                    newButton.auraSpellID = overrideBuffs
                end
            end
        end
    end
    -- forceAura == false: skip all aura auto-detection (track as cooldown)
    if forceAura == false then
        group.buttons[buttonIndex].auraTracking = false
    end

    local newButton = group.buttons[buttonIndex]
    if buttonType == "spell"
        and newButton
        and newButton.addedAs == "aura"
        and newButton.auraUnit ~= "player"
        and newButton.auraUnit ~= "target" then
        newButton.auraUnit = self:ResolveStandaloneAuraDefaultUnit(newButton)
    end

    if buttonType == "spell" and forceAura ~= false then
        self:NormalizeStandaloneAuraButtonData(
            newButton,
            group.buttons,
            { trustExplicitAuraLabel = true }
        )
    end

    if group.displayMode == "trigger" and self.NormalizeTriggerConditionRowData then
        self:NormalizeTriggerConditionRowData(newButton)
    end

    self:RefreshGroupFrame(groupId)
    return buttonIndex, transformNotified
end

function CooldownCompanion:AddEquipmentSlotToGroup(groupId, itemSlot, itemSlotKind)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    local rejectMessage = self:GetPanelManualEntryRejectMessage(group)
    if rejectMessage then
        self:Print(rejectMessage)
        return nil
    end

    local newButton = {
        type = self.EQUIPMENT_SLOT_TYPE or "equipmentSlot",
        itemSlot = itemSlot,
        itemSlotKind = itemSlotKind or self.EQUIPMENT_SLOT_KIND_TRINKET or "trinket",
    }
    if not (self.IsEquipmentSlotEntry and self.IsEquipmentSlotEntry(newButton)) then
        return nil
    end
    newButton.name = self.GetEquipmentSlotDisplayName
        and self.GetEquipmentSlotDisplayName(newButton) or "Trinket Slot"

    local buttonIndex = #group.buttons + 1
    group.buttons[buttonIndex] = newButton

    if group.displayMode == "trigger" and self.NormalizeTriggerConditionRowData then
        self:NormalizeTriggerConditionRowData(newButton)
    end

    self:RefreshGroupFrame(groupId)
    return buttonIndex
end

function CooldownCompanion:RemoveButtonFromGroup(groupId, buttonIndex)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    table_remove(group.buttons, buttonIndex)
    self:RefreshGroupFrame(groupId)
end

-- Walk the class talent tree using the active config, calling visitor(defInfo)
-- for each definition. The tree is shared across all specs, so the active config
-- can query nodes for every specialization.
-- If visitor returns a truthy value, stop and return that value.
local function WalkTalentTree(visitor)
    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return nil end
    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo or not configInfo.treeIDs then return nil end

    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        if nodes then
            for _, nodeID in ipairs(nodes) do
                local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)
                if nodeInfo and nodeInfo.entryIDs then
                    for _, entryID in ipairs(nodeInfo.entryIDs) do
                        local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                        if entryInfo and entryInfo.definitionID then
                            local defInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                            if defInfo then
                                local result = visitor(defInfo)
                                if result then return result end
                            end
                        end
                    end
                end
            end
        end
    end
    return nil
end

-- Search spec display spells (key abilities shown on the spec selection screen)
-- across all specs for the player's class.
local function FindDisplaySpell(matcher)
    local _, _, classID = UnitClass("player")
    if not classID then return nil end
    local numSpecs = C_SpecializationInfo.GetNumSpecializationsForClassID(classID)
    for specIndex = 1, numSpecs do
        local specID = GetSpecializationInfoForClassID(classID, specIndex)
        if specID then
            local ids = C_SpecializationInfo.GetSpellsDisplay(specID)
            if ids then
                for _, spellID in ipairs(ids) do
                    local result = matcher(spellID)
                    if result then return result end
                end
            end
        end
    end
    return nil
end

-- Search the off-spec spellbook for a spell by name or ID.
-- Returns spellID, name if found; nil otherwise.
local function FindOffSpecSpell(spellIdentifier)
    local slot, bank = C_SpellBook.FindSpellBookSlotForSpell(spellIdentifier, false, true, false, true)
    if not slot then return nil end
    local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
    if info and info.spellID then
        return info.spellID, info.name
    end
    return nil
end

function CooldownCompanion:FindTalentSpellByName(name)
    local lowerName = name:lower()

    -- 1) Search talent tree (covers all talent choices across specs)
    local result = WalkTalentTree(function(defInfo)
        if defInfo.spellID then
            local spellInfo = C_Spell.GetSpellInfo(defInfo.spellID)
            if spellInfo and spellInfo.name and spellInfo.name:lower() == lowerName then
                return { defInfo.spellID, spellInfo.name }
            end
        end
    end)
    if result then return result[1], result[2] end

    -- 2) Search spec display spells (key baseline abilities per spec)
    result = FindDisplaySpell(function(spellID)
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo and spellInfo.name and spellInfo.name:lower() == lowerName then
            return { spellID, spellInfo.name }
        end
    end)
    if result then return result[1], result[2] end

    -- 3) Search off-spec spellbook (covers previously activated specs)
    local spellID, spellName = FindOffSpecSpell(name)
    if spellID and spellName then return spellID, spellName end

    return nil
end

--- Return sorted active-profile character choices for Load Conditions.
--- Includes the current character, AceDB profile keys that point at the active
--- profile, and owners referenced by entities in the active profile.
function CooldownCompanion:EnumerateActiveProfileCharacters()
    local db = self.db
    local profile = db and db.profile
    local currentChar = db and db.keys and db.keys.char
    local currentProfile = db and db.keys and db.keys.profile
    if db and db.GetCurrentProfile then
        currentProfile = db:GetCurrentProfile() or currentProfile
    end

    local seen = {}
    local result = {}

    local function AddCharKey(charKey)
        if type(charKey) ~= "string" or charKey == "" or seen[charKey] then
            return
        end
        seen[charKey] = true
        local info = db and db.global and db.global.characterInfo and db.global.characterInfo[charKey]
        result[#result + 1] = {
            charKey = charKey,
            classFilename = info and info.classFilename or nil,
            classID = info and info.classID or nil,
        }
    end

    AddCharKey(currentChar)

    local profileKeys = db and db.sv and db.sv.profileKeys
    if type(profileKeys) == "table" and type(currentProfile) == "string" then
        for charKey, profileKey in pairs(profileKeys) do
            if profileKey == currentProfile then
                AddCharKey(charKey)
            end
        end
    end

    if type(profile) == "table" then
        for _, group in pairs(profile.groups or {}) do
            if type(group) == "table" and not group.isGlobal then
                AddCharKey(group.createdBy)
            end
        end
        for _, container in pairs(profile.groupContainers or {}) do
            if type(container) == "table" and not container.isGlobal then
                AddCharKey(container.createdBy)
            end
        end
        for _, folder in pairs(profile.folders or {}) do
            if type(folder) == "table" and folder.section == "char" then
                AddCharKey(folder.createdBy)
            end
        end
    end

    table_sort(result, function(a, b) return a.charKey < b.charKey end)
    return result
end
