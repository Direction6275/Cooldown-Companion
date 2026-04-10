--[[
    CooldownCompanion - Core/GroupManagement.lua: Group/folder CRUD, AddButtonToGroup,
    RemoveButtonFromGroup, spell search (FindTalentSpellByName)
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local pairs = pairs
local ipairs = ipairs
local tonumber = tonumber
local math_floor = math.floor
local table_sort = table.sort
local table_remove = table.remove
local GROUP_SETTING_PRESET_MODES = {
    icons = true,
    bars = true,
    text = true,
}

local function IsValidGroupSettingPresetMode(mode)
    return GROUP_SETTING_PRESET_MODES[mode] == true
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
    return frameName:match("^CooldownCompanionContainer%d+$") ~= nil
        or frameName:match("^CooldownCompanionGroup%d+$") ~= nil
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

    local settings = self:GetTexturePanelSettings(group, true)
    local frame = self.groupFrames and self.groupFrames[groupId]
    local anchor = type(group.anchor) == "table" and group.anchor or nil
    local point = (anchor and anchor.point) or "CENTER"
    local relativePoint = (anchor and anchor.relativePoint) or "CENTER"

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

local function SyncGroupAnchorFromTexturePanelSettings(self, group)
    if not (self and type(group) == "table") then
        return
    end

    local settings = self:GetTexturePanelSettings(group)
    if not settings then
        return
    end

    group.anchor = group.anchor or {}

    local point = settings.point or group.anchor.point or "CENTER"
    local relativePoint = settings.relativePoint or group.anchor.relativePoint or "CENTER"
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

function CooldownCompanion:GetParentContainerId(groupId)
    local group = self.db.profile.groups[groupId]
    return group and group.parentContainerId
end

function CooldownCompanion:IsPanelGroup(groupId)
    local group = self.db.profile.groups[groupId]
    return group ~= nil and group.parentContainerId ~= nil
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
        baselineAlpha = 1,
        forceAlphaRegularMounted = false,
        forceAlphaDragonriding = false,
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

    return containerId
end

function CooldownCompanion:DeleteContainer(containerId)
    local db = self.db.profile
    if not db.groupContainers[containerId] then return end

    -- Delete all child panels first
    local panelIds = {}
    for groupId, group in pairs(db.groups) do
        if group.parentContainerId == containerId then
            panelIds[#panelIds + 1] = groupId
        end
    end
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

    -- If source was global, clear folderId on the copy
    if sourceContainer.isGlobal and newContainer.folderId then
        newContainer.folderId = nil
    end

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
    for _, groupId in ipairs(sourcePanelIds) do
        local group = db.groups[groupId]
        if group then
            local newGroupId = db.nextGroupId
            db.nextGroupId = newGroupId + 1

            local newPanel = CopyTable(group)
            newPanel.parentContainerId = newContainerId
            newPanel.anchor = {
                point = "CENTER",
                relativeTo = containerFrameName,
                relativePoint = "CENTER",
                x = group.anchor and group.anchor.x or 0,
                y = group.anchor and group.anchor.y or 0,
            }

            db.groups[newGroupId] = newPanel
            self:CreateGroupFrame(newGroupId)
        end
    end

    -- Create container frame (Phase 3 — safe noop if method doesn't exist yet)
    if self.CreateContainerFrame then
        self:CreateContainerFrame(newContainerId)
    end
    if self.FinalizeContainerAnchorsToScreenOffsets then
        self:FinalizeContainerAnchorsToScreenOffsets()
    end

    return newContainerId
end

function CooldownCompanion:RenameContainer(containerId, newName)
    local container = self.db.profile.groupContainers[containerId]
    if container then
        container.name = newName
    end
end

------------------------------------------------------------------------
-- Panel CRUD (within containers)
------------------------------------------------------------------------

function CooldownCompanion:CreatePanel(containerId, displayMode)
    local db = self.db.profile
    local container = db.groupContainers[containerId]
    if not container then return nil end

    local groupId = db.nextGroupId
    db.nextGroupId = groupId + 1

    local panelOrder = self:GetPanelCount(containerId) + 1
    local containerFrameName = "CooldownCompanionContainer" .. containerId

    db.groups[groupId] = {
        name = "Panel " .. panelOrder,
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
        displayMode = displayMode or "icons",
        masqueEnabled = false,
        compactLayout = false,
        maxVisibleButtons = 0,
        compactGrowthDirection = "center",
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
    if style.showLossOfControl == nil then style.showLossOfControl = false end
    if style.showTooltips == nil then style.showTooltips = false end
    if style.showUnusable == nil then style.showUnusable = true end
    if style.showCooldownSwipe == nil then style.showCooldownSwipe = true end
    if style.showCooldownSwipeFill == nil then style.showCooldownSwipeFill = true end
    if style.barAuraEffect == nil then style.barAuraEffect = "color" end

    if displayMode == "textures" then
        db.groups[groupId].textureSettings = {
            blendMode = "BLEND",
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = "UIParent",
            x = 0,
            y = 0,
        }
    end

    self:CreateGroupFrame(groupId)
    return groupId
end

function CooldownCompanion:DeletePanel(containerId, groupId)
    local db = self.db.profile
    local group = db.groups[groupId]
    if not group or group.parentContainerId ~= containerId then return false end

    self:UnloadGroup(groupId)
    self:DiscardDormantFrame(groupId)
    db.groups[groupId] = nil
    return true
end

function CooldownCompanion:DuplicatePanel(containerId, groupId)
    local db = self.db.profile
    local sourcePanel = db.groups[groupId]
    if not sourcePanel or sourcePanel.parentContainerId ~= containerId then return nil end

    local newGroupId = db.nextGroupId
    db.nextGroupId = newGroupId + 1

    local newPanel = CopyTable(sourcePanel)
    newPanel.name = sourcePanel.name .. " (Copy)"
    newPanel.order = self:GetPanelCount(containerId) + 1

    db.groups[newGroupId] = newPanel
    self:CreateGroupFrame(newGroupId)
    return newGroupId
end

function CooldownCompanion:MovePanel(groupId, targetContainerId)
    local db = self.db.profile
    local group = db.groups[groupId]
    if not group or not group.parentContainerId then return false end
    if not db.groupContainers[targetContainerId] then return false end

    local sourceContainerId = group.parentContainerId
    if sourceContainerId == targetContainerId then return false end

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

    return true, sourceDeleted
end

function CooldownCompanion:RenamePanelGroup(groupId, newName)
    local group = self.db.profile.groups[groupId]
    if group then
        group.name = newName
    end
end

function CooldownCompanion:ChangePanelDisplayMode(groupId, newMode)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    if newMode == "textures" and #group.buttons > 1 then
        self:Print("Texture Panels can only hold one entry. Remove extra entries first, or create a new Texture Panel.")
        return false
    end

    local oldMode = group.displayMode
    if oldMode == "textures" and newMode ~= "textures" then
        -- Leaving texture mode should carry the standalone texture position
        -- back into the normal panel anchor so the panel does not jump back.
        SyncGroupAnchorFromTexturePanelSettings(self, group)
    end

    group.displayMode = newMode
    if newMode == "bars" or newMode == "text" then
        group.style.orientation = "vertical"
    end
    if newMode ~= "icons" and group.masqueEnabled and self.ToggleGroupMasque then
        self:ToggleGroupMasque(groupId, false)
    end
    if newMode == "textures" then
        -- Entering texture mode switches from group.anchor to textureSettings,
        -- so convert the panel's current on-screen position once here.
        SyncTexturePanelPositionFromGroupFrame(self, groupId, group)
    end
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

    self:UnloadGroup(id)
    self:DiscardDormantFrame(id)
    self.db.profile.groups[id] = nil

    -- If this was the last panel, delete the parent container too
    if parentId and self:GetPanelCount(parentId) == 0 then
        self:DeleteContainer(parentId)
    end
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
    newGroup.createdBy = self.db.keys.char
    newGroup.isGlobal = false
    if sourceGroup.isGlobal and newGroup.folderId then
        newGroup.folderId = nil
    end

    self.db.profile.groups[newGroupId] = newGroup
    self:CreateGroupFrame(newGroupId)
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
    if folder then
        folder.name = newName
    end
end

function CooldownCompanion:MoveGroupToFolder(id, folderId)
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
    end

    self:RefreshAllGroups()
end

function CooldownCompanion:AddButtonToGroup(groupId, buttonType, id, name, isPetSpell, isPassive, forceAura, cdmChildSlot)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    if group.displayMode == "textures" and #group.buttons >= 1 then
        self:Print("Texture Panels can only hold one entry. Remove the current entry first if you want to replace it.")
        return nil
    end

    -- Resolve spell transforms to base spell ID so the override chain can
    -- freely reach all variant forms at runtime.  Skip for items (no spell
    -- transform system), pet spells (may not resolve through GetBaseSpell),
    -- and CDM child-slot buttons (viewer-frame mapping uses specific IDs).
    local transformNotified
    if buttonType == "spell" and not isPetSpell and not cdmChildSlot then
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
                print("|cff00ccffCooldown Companion:|r Added " .. baseName
                    .. " (currently showing as " .. overrideName
                    .. ") - tracks all spell variants.")
                transformNotified = true
            end
        end
    end

    local buttonIndex = #group.buttons + 1
    group.buttons[buttonIndex] = {
        type = buttonType,
        id = id,
        name = name,
        isPetSpell = isPetSpell or nil,
        isPassive = isPassive or nil,
        cdmChildSlot = cdmChildSlot or nil,
    }

    -- Auto-detect charges for spells (skip for passives — no cooldown).
    -- Treat as charge-based only when max charges is greater than 1.
    if buttonType == "spell" and not isPassive then
        local chargeInfo = C_Spell.GetSpellCharges(id)
        -- Base spell may not have charges when the override form does
        -- (e.g. Primal Strike → Stormstrike). Try the current override.
        local chargeQueryID = id
        if not chargeInfo then
            local overrideID = C_Spell.GetOverrideSpell(id)
            if overrideID and overrideID ~= 0 and overrideID ~= id then
                chargeInfo = C_Spell.GetSpellCharges(overrideID)
                chargeQueryID = overrideID
            end
        end
        if chargeInfo then
            local mc = chargeInfo.maxCharges
            if mc > 1 then
                group.buttons[buttonIndex].hasCharges = true
                group.buttons[buttonIndex]._hasDisplayCount = nil
                group.buttons[buttonIndex].showChargeText = true
                group.buttons[buttonIndex].maxCharges = mc

                -- Secondary: display count
                local rawDisplayCount = C_Spell.GetSpellDisplayCount(chargeQueryID)
                if not issecretvalue(rawDisplayCount) then
                    local displayCount = tonumber(rawDisplayCount)
                    if displayCount and displayCount > (group.buttons[buttonIndex].maxCharges or 0) then
                        group.buttons[buttonIndex].maxCharges = displayCount
                    end
                end
            end
        else
            local rawDisplayCount = C_Spell.GetSpellDisplayCount(chargeQueryID)
            if not issecretvalue(rawDisplayCount) then
                local displayCount = tonumber(rawDisplayCount)
                if displayCount ~= nil then
                    group.buttons[buttonIndex]._hasDisplayCount = true
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
        local plainCount = C_Item.GetItemCount(id)
        local chargeCount = C_Item.GetItemCount(id, false, true)
        if chargeCount > plainCount then
            group.buttons[buttonIndex].hasCharges = true
            group.buttons[buttonIndex].showChargeText = true
            group.buttons[buttonIndex].maxCharges = chargeCount
        end
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
                        if viewerFrame then break end
                    end
                end
            end
            local hasViewerFrame = false
            if viewerFrame and GetCVarBool("cooldownViewerEnabled") then
                local parent = viewerFrame:GetParent()
                local parentName = parent and parent:GetName()
                hasViewerFrame = parentName == "BuffIconCooldownViewer" or parentName == "BuffBarCooldownViewer"
            end
            if hasViewerFrame then
                newButton.auraTracking = true
                newButton.auraIndicatorEnabled = true
                local overrideBuffs = self.ABILITY_BUFF_OVERRIDES[id]
                if overrideBuffs then
                    newButton.auraSpellID = overrideBuffs
                end
                if C_Spell.IsSpellHarmful(id) then
                    newButton.auraUnit = "target"
                end
            end
        end
    end
    -- forceAura == false: skip all aura auto-detection (track as cooldown)
    if forceAura == false then
        group.buttons[buttonIndex].auraTracking = false
    end

    if buttonType == "spell" and forceAura ~= false then
        self:NormalizeStandaloneAuraButtonData(
            group.buttons[buttonIndex],
            group.buttons,
            { trustExplicitAuraLabel = true }
        )
    end

    self:RefreshGroupFrame(groupId)
    return buttonIndex, transformNotified
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

------------------------------------------------------------------------
-- Cross-Character Browse Helpers
------------------------------------------------------------------------

--- Scan profile containers for unique createdBy values other than current char.
--- Returns sorted array of { charKey, classFilename, classID }.
function CooldownCompanion:EnumerateBrowseCharacters()
    local db = self.db.profile
    local currentChar = self.db.keys.char
    local seen = {}
    local result = {}

    for _, container in pairs(db.groupContainers) do
        local key = container.createdBy
        if key and key ~= currentChar and not container.isGlobal and not seen[key] then
            seen[key] = true
            local info = self.db.global.characterInfo and self.db.global.characterInfo[key]
            result[#result + 1] = {
                charKey = key,
                classFilename = info and info.classFilename or nil,
                classID = info and info.classID or nil,
            }
        end
    end

    table_sort(result, function(a, b) return a.charKey < b.charKey end)
    return result
end

--- Return sorted array of { containerId, container } for a given character key.
function CooldownCompanion:GetCharacterContainers(charKey)
    local db = self.db.profile
    local result = {}

    for containerId, container in pairs(db.groupContainers) do
        if container.createdBy == charKey and not container.isGlobal then
            -- Skip empty containers (no panels with buttons)
            local hasButtons = false
            for _, group in pairs(db.groups) do
                if group.parentContainerId == containerId and group.buttons and #group.buttons > 0 then
                    hasButtons = true
                    break
                end
            end
            if hasButtons then
                result[#result + 1] = { containerId = containerId, container = container }
            end
        end
    end

    local specId = self._currentSpecId
    table_sort(result, function(a, b)
        return self:GetOrderForSpec(a.container, specId, a.containerId) < self:GetOrderForSpec(b.container, specId, b.containerId)
    end)
    return result
end

--- Copy a container from browse mode. Reuses DuplicateContainer, renames to original name.
function CooldownCompanion:CopyContainerFromBrowse(sourceContainerId)
    local sourceContainer = self.db.profile.groupContainers[sourceContainerId]
    if not sourceContainer then return nil end

    local originalName = sourceContainer.name
    local newContainerId = self:DuplicateContainer(sourceContainerId)
    if newContainerId then
        -- Rename from "X (Copy)" back to original name
        self.db.profile.groupContainers[newContainerId].name = originalName
    end
    return newContainerId
end

--- Copy a panel into an existing container owned by the current character.
function CooldownCompanion:CopyPanelToContainer(sourceGroupId, targetContainerId)
    local db = self.db.profile
    local sourcePanel = db.groups[sourceGroupId]
    if not sourcePanel then return nil end
    if not db.groupContainers[targetContainerId] then return nil end

    local newGroupId = db.nextGroupId
    db.nextGroupId = newGroupId + 1

    local newPanel = CopyTable(sourcePanel)
    newPanel.parentContainerId = targetContainerId
    newPanel.order = self:GetPanelCount(targetContainerId) + 1

    local containerFrameName = "CooldownCompanionContainer" .. targetContainerId
    newPanel.anchor = {
        point = "CENTER",
        relativeTo = containerFrameName,
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }

    db.groups[newGroupId] = newPanel
    self:CreateGroupFrame(newGroupId)
    return newGroupId
end

--- Copy a panel as a brand new standalone group (container + panel).
function CooldownCompanion:CopyPanelAsNewGroup(sourceGroupId, sourceName)
    local db = self.db.profile
    local sourcePanel = db.groups[sourceGroupId]
    if not sourcePanel then return nil, nil end

    -- Create a new container
    local containerId = self:CreateContainer(sourceName or "Copied Group")

    -- Create container frame
    if self.CreateContainerFrame then
        self:CreateContainerFrame(containerId)
    end

    -- Deep-copy the source panel into the new container
    local newGroupId = db.nextGroupId
    db.nextGroupId = newGroupId + 1

    local newPanel = CopyTable(sourcePanel)
    newPanel.parentContainerId = containerId
    newPanel.order = 1
    newPanel.name = "Panel 1"

    local containerFrameName = "CooldownCompanionContainer" .. containerId
    newPanel.anchor = {
        point = "CENTER",
        relativeTo = containerFrameName,
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }

    db.groups[newGroupId] = newPanel
    self:CreateGroupFrame(newGroupId)

    return containerId, newGroupId
end
