--[[
    CooldownCompanion - Core/GroupManagement.lua: Group CRUD, AddButtonToGroup,
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

        -- Measure the target's ANCHORING BODY. AnchorContainerFrame positions
        -- against it, so converting this offset against the panel's outer union
        -- instead would move the container the moment a section appeared.
        relativeFrame = ST.GetPanelAnchorBodyFrame(relativeFrame)

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

    -- Same rule as everywhere else a panel is measured for a dependent: the
    -- anchoring body, because that is what AnchorGroupFrame will SetPoint the
    -- panel against once these offsets are saved.
    relFrame = ST.GetPanelAnchorBodyFrame(relFrame)

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
-- Shared with Core/PanelTemplates.lua so a template snapshot copies values
-- with the same deep-copy rule the settings applier writes them with.
ST._CopyPresetValue = CopyPresetValue

-- Panel arrangement orientation is remembered PER MODE so a display-mode
-- swap can never destroy another mode's layout: bars and text panels read
-- their own keys (unset = vertical), everything else keeps style.orientation
-- (unset = horizontal). Every layout read goes through here.
function ST.GetPanelLayoutOrientation(displayMode, style)
    if displayMode == "bars" then
        return style.barOrientation or "vertical"
    end
    if displayMode == "text" then
        return style.textOrientation or "vertical"
    end
    return style.orientation or "horizontal"
end

local function CopyCompactLayoutSettings(sourceGroup, targetGroup)
    targetGroup.compactLayout = sourceGroup.compactLayout == true
    targetGroup.compactGrowthDirection = sourceGroup.compactGrowthDirection or "center"

    local sourceMaxVisible = tonumber(sourceGroup.maxVisibleButtons) or 0
    local targetButtonCount = targetGroup.buttons and #targetGroup.buttons or 0
    if targetButtonCount == 0 then
        -- An empty target has nothing to clamp against, and a template must
        -- reproduce the panel's limit as entries arrive.
        targetGroup.maxVisibleButtons = sourceMaxVisible
    elseif sourceMaxVisible > 0 then
        targetGroup.maxVisibleButtons = math.min(sourceMaxVisible, targetButtonCount)
        if targetGroup.maxVisibleButtons >= targetButtonCount then
            targetGroup.maxVisibleButtons = 0
        end
    else
        targetGroup.maxVisibleButtons = 0
    end
end

------------------------------------------------------------------------
-- Copy Panel Settings ("Copy Panel Settings To...")
--
-- The one panel-to-panel style transfer: armed from the Navigator's panel
-- context menu, it pushes the source panel's Appearance and/or Indicators
-- tab settings onto a clicked target panel. Replaces the retired
-- panel-setting presets and the pull-style Copy Style From Panel, whose
-- machinery this reuses in scoped form. What copies is declared by
-- ST.PANEL_COPY_SCOPES (Defaults.lua) plus the override sections' own key
-- lists; anchors, Layout-tab keys, visibility, name, and entries never move.
------------------------------------------------------------------------

-- Which copy family a panel belongs to. nil for the specialist modes
-- (textures, trigger, rotation assistant), which the feature does not serve.
-- Aura Panels ride their base display mode, exactly as the retired preset
-- paths judged them; the subtype's invariants are re-established after apply.
function CooldownCompanion:GetPanelCopyMode(group)
    if not group then return nil end
    local displayMode = group.displayMode
    if displayMode == nil or displayMode == "icons" then
        return "icons"
    end
    if displayMode == "bars" or displayMode == "text" then
        return displayMode
    end
    return nil
end

-- The scopes a mode offers, in menu order. "all" is every listed scope and
-- is always valid for a copyable mode.
function CooldownCompanion:GetPanelCopyScopeList(mode)
    local modeScopes = ST.PANEL_COPY_SCOPES[mode]
    if not modeScopes then return {} end
    local list = {}
    if modeScopes.appearance then list[#list + 1] = "appearance" end
    if modeScopes.indicators then list[#list + 1] = "indicators" end
    return list
end

-- The one enumeration of the style keys a mode's copy scopes carry, in write
-- order: for each scope name in `scopes`, its override sections' keys, then
-- its own styleKeys. The settings applier below and the template snapshot
-- (Core/PanelTemplates.lua) both walk it, so the two can never disagree
-- about which keys make up the look.
local function ForEachPanelCopyStyleKey(mode, scopes, fn)
    local modeScopes = ST.PANEL_COPY_SCOPES[mode]
    if not modeScopes then return end
    for _, scopeName in ipairs(scopes) do
        local scopeData = modeScopes[scopeName]
        if scopeData then
            for _, sectionId in ipairs(scopeData.sections or {}) do
                local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
                if sectionDef then
                    for _, key in ipairs(sectionDef.keys or {}) do
                        fn(key)
                    end
                end
            end
            for _, key in ipairs(scopeData.styleKeys or {}) do
                fn(key)
            end
        end
    end
end
ST._ForEachPanelCopyStyleKey = ForEachPanelCopyStyleKey

function CooldownCompanion:CanCopyPanelSettings(sourceGroupId, targetGroupId, scope)
    sourceGroupId = tonumber(sourceGroupId)
    targetGroupId = tonumber(targetGroupId)

    local db = self.db and self.db.profile
    local sourceGroup = db and db.groups and db.groups[sourceGroupId]
    local targetGroup = db and db.groups and db.groups[targetGroupId]
    if not sourceGroup or not targetGroup then
        return false, "missing_group"
    end
    if sourceGroupId == targetGroupId then
        return false, "same_group"
    end

    local mode = self:GetPanelCopyMode(sourceGroup)
    if not mode or mode ~= self:GetPanelCopyMode(targetGroup) then
        return false, "mode_mismatch"
    end

    local modeScopes = ST.PANEL_COPY_SCOPES[mode]
    if not modeScopes or (scope ~= "all" and not modeScopes[scope]) then
        return false, "invalid_scope"
    end

    -- Any panel in the profile is a legal source or target as long as both
    -- resolve to a valid class scope. This is a deliberate widening from the
    -- retired pull copy's visibility gate: the armed mode's promise is that
    -- every real panel on every class is a live source, and styles carry no
    -- class-specific content.
    if self.ResolveContainerClassScope then
        local sourceScope = sourceGroup.parentContainerId
            and self:ResolveContainerClassScope(sourceGroup.parentContainerId)
        local targetScope = targetGroup.parentContainerId
            and self:ResolveContainerClassScope(targetGroup.parentContainerId)
        if (sourceScope and sourceScope.isInvalid)
            or (targetScope and targetScope.isInvalid) then
            return false, "invalid_class_scope"
        end
    end

    return true
end

-- The one writer behind Copy Panel Settings and Panel Templates
-- (Core/PanelTemplates.lua). `source` is any panel-shaped table - a live
-- panel or a stored template: its style, masqueEnabled and compact trio are
-- read, and whether it is an Aura Panel is derived from the table itself.
-- `scopes` is the list of ST.PANEL_COPY_SCOPES[mode] scope names to write.
--
-- opts, every one optional and template-only (the copy feature passes none):
--   shapeKeys    style keys copied after the look scopes, each by the same
--                source-value-else-baseline rule (ST.PANEL_TEMPLATE_SHAPE_KEYS)
--   skipCompact  leave the target's compact trio alone even where a scope
--                copies it (a template saved from an Aura Panel carries none)
--   anchor       { point, relativePoint, x, y }: the target's offset from its
--                own Group frame, written and re-anchored only for a panel
--                that has one. Never any other anchor target.
--
-- Returns true once the data is written, whether the frame refresh ran or
-- was combat-deferred, exactly as the copy feature always has.
local function ApplyPanelSettingsSource(self, targetGroupId, source, scopes, opts)
    opts = opts or {}
    local db = self.db.profile
    local targetGroup = db.groups[targetGroupId]
    local mode = self:GetPanelCopyMode(targetGroup)
    local modeScopes = ST.PANEL_COPY_SCOPES[mode]

    -- Per key: the source's value, or the shipped default where the source
    -- carries none - so the target's scope comes out exactly matching the
    -- source's, including keys the source left at default. globalStyle is the
    -- baseline the panel style itself was seeded from; a key absent there too
    -- is nil-defaulted at its read sites, and nil is the faithful copy.
    local baseline = db.globalStyle or {}
    local sourceStyle = source.style or {}
    local targetStyle = targetGroup.style
    if type(targetStyle) ~= "table" then
        targetStyle = {}
        targetGroup.style = targetStyle
    end

    local copiedDurationFormat = false
    local function CopyStyleKey(key)
        local value = sourceStyle[key]
        if value == nil then
            value = baseline[key]
        end
        targetStyle[key] = CopyPresetValue(value)
        if key == "durationFormat" then
            copiedDurationFormat = true
        end
    end

    local oldMasqueEnabled = targetGroup.masqueEnabled and true or false
    local copiedMasque = false

    for _, scopeName in ipairs(scopes) do
        local scopeData = modeScopes[scopeName]
        if scopeData then
            -- One scope at a time, so each scope's keys land before its Masque
            -- and compact writes, exactly as they always have.
            ForEachPanelCopyStyleKey(mode, { scopeName }, CopyStyleKey)
            if scopeData.copiesMasque then
                targetGroup.masqueEnabled = source.masqueEnabled and true or false
                copiedMasque = true
            end
            -- Compact settings never cross an Aura Panel boundary in either
            -- direction: on an Aura Panel compactGrowthDirection is the
            -- Layout-owned Collapse Direction (a placement setting outside
            -- this feature's line), and compactLayout is invariant-forced
            -- false there - so an Aura endpoint has nothing Appearance-shaped
            -- to give or take here.
            if scopeData.copiesCompact
                and not opts.skipCompact
                and not ST.IsAuraPanelGroup(source)
                and not ST.IsAuraPanelGroup(targetGroup) then
                CopyCompactLayoutSettings(source, targetGroup)
            end
        end
    end

    -- Shape rides after the look, by the same baseline rule. Only a template
    -- asks for it: the copy feature's line stops at the look.
    for _, key in ipairs(opts.shapeKeys or {}) do
        CopyStyleKey(key)
    end

    -- durationFormat: legacy profiles can still carry only decimalTimers=true
    -- with no explicit durationFormat (no migration normalizes the pair; the
    -- read path resolves it, ButtonFrame/Helpers.lua). Copying the raw keys
    -- would hand such a source's target the baseline "clock" while the source
    -- renders decimals - so the copy writes the source's EFFECTIVE format in
    -- canonical form and clears the target's retired legacy key.
    if copiedDurationFormat and self.GetDurationFormat then
        targetStyle.durationFormat = self.GetDurationFormat(sourceStyle)
        targetStyle.decimalTimers = nil
    end

    -- Copy eligibility compares the base displayMode only, so an ordinary icon
    -- or bar panel is a legal source for an Aura Panel. The writers above can
    -- strand a flag the subtype cannot carry (compactLayout collapses the
    -- footprint, masqueEnabled disables config rows with no toggle left to
    -- clear it), so the invariants are re-established here — before the Masque
    -- comparison below, and before the combat-deferred return.
    self:EnforceAuraPanelInvariants(targetGroup)

    local newMasqueEnabled = targetGroup.masqueEnabled and true or false

    -- The source can carry a Masque flag from a client that had it installed.
    -- If Masque is unavailable here, do not leave the target flagged: that
    -- disables icon controls in config with no visible switch to clear it.
    if copiedMasque and not self.Masque and newMasqueEnabled then
        targetGroup.masqueEnabled = false
        newMasqueEnabled = false
    end

    -- The Group-relative offset is pure data, so it lands before the combat
    -- gate like every key above; the frame side runs with the refresh below,
    -- or rides _anchorDirty out of combat the way a deferred layout does.
    local anchor = opts.anchor
    local wasCursorAnchored = false
    if anchor and targetGroup.parentContainerId then
        wasCursorAnchored = self:IsCursorAnchor(targetGroup.anchor)
        targetGroup.anchor = {
            point = anchor.point or "CENTER",
            relativeTo = "CooldownCompanionContainer" .. targetGroup.parentContainerId,
            relativePoint = anchor.relativePoint or "CENTER",
            x = tonumber(anchor.x) or 0,
            y = tonumber(anchor.y) or 0,
        }
    else
        anchor = nil
    end

    local frame = self.groupFrames and self.groupFrames[targetGroupId]
    if InCombatLockdown() and (not frame or frame:IsProtected()) then
        if frame then
            frame._layoutDirty = true
            if anchor then
                frame._anchorDirty = true
            end
        end
        self._pendingFullRefresh = true
        return true
    end

    -- Keep Masque's internal group/button lifecycle in sync when the copy
    -- flips skinning state.
    if copiedMasque and self.Masque and oldMasqueEnabled ~= newMasqueEnabled then
        self:ToggleGroupMasque(targetGroupId, newMasqueEnabled)
    end

    -- Re-anchoring is the finishing sequence SetGroupAnchor's own container
    -- branch runs (Core/GroupFrame.lua): anchor, rebuild alpha dependencies,
    -- refresh interaction state, and tell the cursor runtime if the panel
    -- just left the cursor. It runs before the layout refresh so the buttons
    -- are laid out against the final anchor.
    if anchor and frame and ST._FinishGroupAnchorChange then
        ST._FinishGroupAnchorChange(self, targetGroupId, frame, targetGroup, wasCursorAnchored)
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
ST._ApplyPanelSettingsSource = ApplyPanelSettingsSource

function CooldownCompanion:CopyPanelSettings(sourceGroupId, targetGroupId, scope)
    sourceGroupId = tonumber(sourceGroupId)
    targetGroupId = tonumber(targetGroupId)

    local canCopy, reason = self:CanCopyPanelSettings(sourceGroupId, targetGroupId, scope)
    if not canCopy then
        return false, reason
    end

    local db = self.db.profile
    local sourceGroup = db.groups[sourceGroupId]
    local mode = self:GetPanelCopyMode(db.groups[targetGroupId])

    local scopes
    if scope == "all" then
        scopes = self:GetPanelCopyScopeList(mode)
    else
        scopes = { scope }
    end

    return ApplyPanelSettingsSource(self, targetGroupId, sourceGroup, scopes)
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
        local aOrder = a.group.order or 0
        local bOrder = b.group.order or 0
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end

        local aId = tonumber(a.groupId)
        local bId = tonumber(b.groupId)
        if aId and bId and aId ~= bId then
            return aId < bId
        end
        return tostring(a.groupId) < tostring(b.groupId)
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
    if self.RefreshStableExternalAnchorCompactSuppression then
        self:RefreshStableExternalAnchorCompactSuppression()
    end
    RefreshPanelAlphaDependencyTargets(self)
    self:RequestAuraRebind("delete")
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

function CooldownCompanion:DuplicateContainer(containerId, skipFinalize)
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
    if not skipFinalize then
        if self.FinalizeContainerAnchorsToScreenOffsets then
            self:FinalizeContainerAnchorsToScreenOffsets()
        end
        RefreshPanelAlphaDependencyTargets(self)
    end

    return newContainerId
end

-- Batch duplicate: one global anchor-finalize pass instead of one per copy.
function CooldownCompanion:DuplicateContainers(containerIds)
    local duplicatedAny = false
    for _, containerId in ipairs(containerIds) do
        if self:DuplicateContainer(containerId, true) then
            duplicatedAny = true
        end
    end
    if duplicatedAny then
        if self.FinalizeContainerAnchorsToScreenOffsets then
            self:FinalizeContainerAnchorsToScreenOffsets()
        end
        RefreshPanelAlphaDependencyTargets(self)
    end
end

------------------------------------------------------------------------
-- Panel CRUD (within containers)
------------------------------------------------------------------------

local function ShouldDefaultPanelCompactLayout(displayMode)
    return displayMode == "icons" or displayMode == "bars"
end

-- Aura Panels are a subtype, not a display mode, so creation surfaces name them
-- with a pseudo-mode that resolves here into a real displayMode plus the
-- subtype flag. The pseudo-mode string must never reach group.displayMode.
local AURA_PANEL_PSEUDO_MODES = {
    auraIcons = "icons",
    auraBars = "bars",
}

local function ResolvePanelCreationMode(displayMode)
    local baseMode = AURA_PANEL_PSEUDO_MODES[displayMode]
    if baseMode then
        return baseMode, true
    end
    return displayMode, false
end

function CooldownCompanion:CreatePanel(containerId, displayMode)
    local db = self.db.profile
    local container = db.groupContainers[containerId]
    if not container then return nil end
    displayMode = displayMode or "icons"
    local isAuraPanel
    displayMode, isAuraPanel = ResolvePanelCreationMode(displayMode)
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
        compactLayout = ShouldDefaultPanelCompactLayout(displayMode),
        maxVisibleButtons = 0,
        compactGrowthDirection = "center",
        inheritPanelAlpha = true,
        -- Alpha fade defaults (panels own their own alpha)
        baselineAlpha = 1,
        fadeDelay = 1,
        fadeInDuration = 0.2,
        fadeOutDuration = 0.2,
    }

    -- Every Aura Panel entry renders through the aura container's own flow
    -- layout, so CC's compact reflow and Masque skinning have nothing to drive.
    -- nextAuraKey is the monotonic source of the per-panel entry keys Blizzard's
    -- aura groups are identified by.
    if isAuraPanel then
        db.groups[groupId].auraPanel = true
        db.groups[groupId].nextAuraKey = 1
        self:EnforceAuraPanelInvariants(db.groups[groupId])
    end

    -- Style defaults (nil-guard respects user-customized globalStyle)
    local style = db.groups[groupId].style
    style.orientation = "horizontal"
    -- Stamp the per-mode orientation key at birth: new-format bar/text
    -- panels must always carry it, or the sentinel-stripped re-run of the
    -- orientation migration after a profile import would mistake them for
    -- pre-split panels and copy the icons key over their layout.
    if displayMode == "bars" then
        style.barOrientation = "vertical"
    elseif displayMode == "text" then
        style.textOrientation = "vertical"
    end
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
    if style.showAuraDurationSwipe == nil then style.showAuraDurationSwipe = style.showCooldownSwipe ~= false end
    if style.showCooldownSwipeFill == nil then style.showCooldownSwipeFill = true end
    if style.showAuraDurationSwipeFill == nil then style.showAuraDurationSwipeFill = style.showCooldownSwipeFill ~= false end
    if style.auraDurationSwipeReverse == nil then style.auraDurationSwipeReverse = true end
    if style.auraDurationSwipeEdgeEnabled == nil then style.auraDurationSwipeEdgeEnabled = style.cooldownSwipeEdgeEnabled == true end
    if style.auraDurationSwipeAlpha == nil then style.auraDurationSwipeAlpha = style.cooldownSwipeAlpha or 0.8 end
    if style.auraDurationSwipeEdgeColor == nil then style.auraDurationSwipeEdgeColor = CopyTable(style.cooldownSwipeEdgeColor or {1, 1, 1, 1}) end
    if style.iconFillEnabled == nil then style.iconFillEnabled = false end
    if style.iconFillOrientation == nil then style.iconFillOrientation = "vertical" end
    if style.iconFillReverse == nil then style.iconFillReverse = false end
    if style.iconFillTimerBehavior == nil then style.iconFillTimerBehavior = "drain" end
    if style.iconFillCooldownColor == nil then style.iconFillCooldownColor = {0.6, 0.13, 0.18, 0.55} end
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
    if self.RefreshStableExternalAnchorCompactSuppression then
        self:RefreshStableExternalAnchorCompactSuppression()
    end
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
    if self.RefreshStableExternalAnchorCompactSuppression then
        self:RefreshStableExternalAnchorCompactSuppression()
    end
    RefreshPanelAlphaDependencyTargets(self)
    -- Native aura sounds are held by the display bindings, not the frame, so
    -- unloading alone leaves a deleted entry's alert registered and firing.
    -- The rebind pass parks every record and re-registers from current config.
    self:RequestAuraRebind("delete")
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
    elseif self.RefreshStableExternalAnchorCompactSuppression then
        self:RefreshStableExternalAnchorCompactSuppression()
    end

    RefreshPanelAlphaDependencyTargets(self)
    return true, sourceDeleted
end

local DISPLAY_MODE_CHANGE_REFUSALS = {
    assistant = "Assistant Panels cannot be converted. Create a new Assistant Panel instead.",
    trigger = "Trigger Panels cannot be converted. Create a new Trigger Panel instead.",
    ["texture-entry-limit"] = "Texture Panels can only hold one entry. Remove extra entries first, or create a new Texture Panel.",
    ["aura-entries"] = "This panel contains aura entries, which can only be tracked in icon, bar, text, or Texture panels. Remove them first, or convert to one of those modes.",
    ["aura-panel-modes"] = "Aura Panels can only switch between icons and bars.",
    ["aura-panel-create-only"] = "Aura Panels cannot be converted from an existing panel. Create a new Aura Panel instead.",
}

function CooldownCompanion:CanChangePanelDisplayMode(groupId, newMode)
    local group = self.db.profile.groups[groupId]
    if not group then return false end

    -- The Aura Panel subtype is fixed at creation: an Aura Panel may only swap
    -- between its icon and bar forms (the flag survives), and no ordinary panel
    -- may gain or lose the flag by converting.
    local requestedAuraPanel
    newMode, requestedAuraPanel = ResolvePanelCreationMode(newMode)
    if ST.IsAuraPanelGroup(group) then
        if newMode ~= "icons" and newMode ~= "bars" then
            return false, "aura-panel-modes"
        end
    elseif requestedAuraPanel then
        return false, "aura-panel-create-only"
    end

    local oldMode = group.displayMode
    if oldMode ~= newMode
        and (ST.IsRotationAssistantDisplayMode(oldMode) or ST.IsRotationAssistantDisplayMode(newMode)) then
        return false, "assistant"
    end

    if oldMode ~= newMode and (oldMode == "trigger" or newMode == "trigger") then
        return false, "trigger"
    end

    if newMode == "textures" and #(group.buttons or {}) > 1 then
        return false, "texture-entry-limit"
    end

    -- Primary aura entries only display through the aura system, which binds
    -- to icon, bar, text and Texture panels; refuse conversions that would
    -- strand them.
    if oldMode ~= newMode
        and newMode ~= "icons"
        and newMode ~= "bars"
        and newMode ~= "textures"
        and newMode ~= "text"
        and newMode ~= nil then
        for _, bd in ipairs(group.buttons or {}) do
            if bd.addedAs == "aura" then
                return false, "aura-entries"
            end
        end
    end

    return true
end

function CooldownCompanion:ChangePanelDisplayMode(groupId, newMode)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    local ok, reason = self:CanChangePanelDisplayMode(groupId, newMode)
    if not ok then
        if DISPLAY_MODE_CHANGE_REFUSALS[reason] then
            self:Print(DISPLAY_MODE_CHANGE_REFUSALS[reason])
        end
        return false
    end

    -- Only now that the request has been judged: an Aura Panel pseudo-mode
    -- carries the same base displayMode as its plain twin, so translating any
    -- earlier would let a non-aura panel be converted straight into one.
    newMode = ResolvePanelCreationMode(newMode)

    local oldMode = group.displayMode
    if (oldMode == "textures" or oldMode == "trigger") and newMode ~= oldMode then
        -- Leaving texture mode should carry the standalone texture position
        -- back into the normal panel anchor so the panel does not jump back.
        SyncGroupAnchorFromTexturePanelSettings(self, groupId, group)
    end

    group.displayMode = newMode
    if oldMode ~= newMode and newMode == "textures" and self.EnableTexturePanelAuraDisplayForEntry then
        for _, buttonData in ipairs(group.buttons or {}) do
            self:EnableTexturePanelAuraDisplayForEntry(group, buttonData)
        end
    end
    if oldMode ~= newMode and ShouldClearCDMPanelSourceForDisplayMode(group, newMode) then
        group.cdmPanelSource = nil
    end
    -- Config previews are stored per-group and gated by the panel's mirror
    -- surface at APPLY time; a transition across the mirror boundary (e.g.
    -- icons -> textures) would migrate previews armed for the config mirror
    -- onto the live world buttons. Clear them on every mode change.
    if oldMode ~= newMode and self.ClearAllConfigPreviews then
        self:ClearAllConfigPreviews()
    end
    -- Orientation is remembered per mode (ST.GetPanelLayoutOrientation), so
    -- entering bars/text no longer stomps the icons layout: only stamp the
    -- mode's own key on first entry so new-format panels always carry it.
    if newMode == "bars" and group.style.barOrientation == nil then
        group.style.barOrientation = "vertical"
    elseif newMode == "text" and group.style.textOrientation == nil then
        group.style.textOrientation = "vertical"
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
    elseif self.RefreshStableExternalAnchorCompactSuppression then
        self:RefreshStableExternalAnchorCompactSuppression()
    end
    RefreshPanelAlphaDependencyTargets(self)
    self:RequestAuraRebind("delete")
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
    self.db.profile.groups[newGroupId] = newGroup
    self:CreateGroupFrame(newGroupId)
    RefreshPanelAlphaDependencyTargets(self)
    return newGroupId
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

-- A panel whose entries currently fit a single row/column keeps that single
-- line as entries are added; only a panel the user deliberately wrapped
-- (wrap count below the entry count) may start a new row or column. Every
-- path that grows a panel's entry list calls this with the count from
-- before the growth, after inserting.
--
-- On a panel with sections only BASE members count: a sectioned entry lays
-- out on its own anchor, never in the base line, so an add into a section
-- must not widen the base wrap. The entries at or below the old count are
-- read as the ones already there, which every add path's append makes exact.
function CooldownCompanion:KeepPanelSingleLineOnGrowth(group, previousCount)
    if not group then return end
    local displayMode = group.displayMode or "icons"
    if displayMode ~= "icons" and displayMode ~= "bars" and displayMode ~= "text" then
        return
    end
    local style = group.style
    if not style then return end
    previousCount = tonumber(previousCount) or 0
    local buttons = group.buttons or {}
    local newCount = #buttons
    if ST.GetSectionsForLayout(group) then
        local previousBase, newBase = 0, 0
        for index, buttonData in ipairs(buttons) do
            if ST.GetPanelSectionForEntry(group, buttonData) == nil then
                newBase = newBase + 1
                if index <= previousCount then
                    previousBase = previousBase + 1
                end
            end
        end
        previousCount, newCount = previousBase, newBase
    end
    local perLine = tonumber(style.buttonsPerRow) or 12
    if perLine >= previousCount and newCount > perLine then
        style.buttonsPerRow = newCount
    end
end

-- `section` (optional): the anchor name of a section the new entry joins on
-- a panel that supports sections. An aura-only section or a bad anchor is
-- refused by the membership writer, and the entry stays in the base grid.
function CooldownCompanion:AddButtonToGroup(groupId, buttonType, id, name, isPetSpell, isPassive, forceAura, cdmChildSlot, preserveSpellID, section)
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

    -- Aura Panels hold aura entries only, and only for one unit. Judge the add
    -- here, where id and the aura-intent arguments have reached their final
    -- form, against the same central predicate the move paths use, so nothing
    -- is inserted that the panel cannot render.
    if ST.IsAuraPanelGroup(group) then
        local probe = {
            type = buttonType,
            id = id,
            name = name,
            addedAs = "spell",
        }
        if buttonType == "spell" and (forceAura == true or (isPassive and forceAura ~= false)) then
            probe.addedAs = "aura"
            probe.auraUnit = self:ResolveStandaloneAuraDefaultUnit(probe)
        end
        local auraRejectMessage = self:GetPanelManualEntryRejectMessage(group, probe)
        if auraRejectMessage then
            self:Print(auraRejectMessage)
            return nil
        end
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

    -- Blizzard identifies aura groups per container, so every Aura Panel entry
    -- carries a stable key that is unique within its own panel (Defaults.lua
    -- owns the stamp; the config insert paths call the same one).
    self:StampAuraPanelEntryKey(group, group.buttons[buttonIndex])

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
            -- Explicit aura adds (picked as an aura, not a passive that
            -- auto-classified) default to showing only while the aura is
            -- active — the entry exists to display the aura. Icon and bar
            -- groups both compose a full shell; text panels show auras through
            -- their format's aura tokens, so no shell default applies.
            local displayMode = group.displayMode or "icons"
            if forceAura == true and (displayMode == "icons" or displayMode == "bars") then
                group.buttons[buttonIndex].hideWhileAuraNotActive = true
            end
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
            local hasViewerFrame = false
            if viewerFrame and GetCVarBool("cooldownViewerEnabled") then
                local parent = viewerFrame:GetParent()
                local parentName = parent and parent:GetName()
                hasViewerFrame = parentName == "BuffIconCooldownViewer" or parentName == "BuffBarCooldownViewer"
            end
            if hasViewerFrame
                and IsDistinctAuraViewerFrameForSpell(newButton, viewerFrame) then
                newButton.auraTracking = false
                newButton.auraIndicatorEnabled = false
                hasViewerFrame = false
            end
            if hasViewerFrame then
                newButton.auraTracking = true
                newButton.auraIndicatorEnabled = true
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

    if self.EnableTexturePanelAuraDisplayForEntry then
        self:EnableTexturePanelAuraDisplayForEntry(group, newButton)
    end

    if group.displayMode == "trigger" and self.NormalizeTriggerConditionRowData then
        self:NormalizeTriggerConditionRowData(newButton)
    end

    -- Membership lands before the single-line keeper, so a sectioned arrival
    -- is never counted against the base line.
    if section and ST.PanelSupportsSections(group) then
        ST.SetPanelSectionForEntry(group, newButton, section)
    end

    self:KeepPanelSingleLineOnGrowth(group, buttonIndex - 1)
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

    -- An equipment slot is never an aura entry; the central predicate owns the
    -- wording so this path cannot drift from the add and move paths.
    if ST.IsAuraPanelGroup(group) then
        local auraRejectMessage = self:GetPanelManualEntryRejectMessage(group, newButton)
        if auraRejectMessage then
            self:Print(auraRejectMessage)
            return nil
        end
    end

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

    self:KeepPanelSingleLineOnGrowth(group, buttonIndex - 1)
    self:RefreshGroupFrame(groupId)
    return buttonIndex
end

function CooldownCompanion:RemoveButtonFromGroup(groupId, buttonIndex)
    local group = self.db.profile.groups[groupId]
    if not group then return end

    -- A section IS its members: take the leaving entry out of its cluster before
    -- it goes, so the last one out dissolves it. An orphaned section table would
    -- otherwise sit in the profile as a Layout-tab block for a cluster nothing
    -- is in, and as a drop target promising offset (0,0) while quietly holding
    -- the old one's offsets.
    ST.DetachEntryFromPanelSection(group, group.buttons and group.buttons[buttonIndex])
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

-- Add-time eligibility check only; do not call from per-frame or combat paths.
function CooldownCompanion:CanPlayerEverCastSpell(spellID)
    local id = tonumber(spellID)
    if not id then return false, false end

    -- Resolve at call time: SpellQueries.lua loads before this file, and keeping
    -- the lookup here avoids capturing an unavailable helper at file scope.
    local baseID = ST.ResolveToBaseSpell(id)
    local hasBaseVariant = baseID ~= id
    local spellExists = C_Spell.DoesSpellExist(id)
        or (hasBaseVariant and C_Spell.DoesSpellExist(baseID))
    if not spellExists then return false, false end

    if C_SpellBook.IsSpellKnownOrInSpellBook(id, Enum.SpellBookSpellBank.Player)
        or (hasBaseVariant and C_SpellBook.IsSpellKnownOrInSpellBook(baseID, Enum.SpellBookSpellBank.Player)) then
        return true, true
    end
    if C_SpellBook.IsSpellKnownOrInSpellBook(id, Enum.SpellBookSpellBank.Pet)
        or (hasBaseVariant and C_SpellBook.IsSpellKnownOrInSpellBook(baseID, Enum.SpellBookSpellBank.Pet)) then
        return true, true
    end

    local slotIndex = C_SpellBook.FindSpellBookSlotForSpell(id, true, true, true, true)
    if not slotIndex and hasBaseVariant then
        slotIndex = C_SpellBook.FindSpellBookSlotForSpell(baseID, true, true, true, true)
    end
    if slotIndex then return true, true end

    if WalkTalentTree(function(defInfo)
        return defInfo.spellID == id or (hasBaseVariant and defInfo.spellID == baseID)
    end) then
        return true, true
    end

    return FindDisplaySpell(function(displaySpellID)
        return displaySpellID == id or (hasBaseVariant and displaySpellID == baseID)
    end) == true, true
end

-- Group-scoped aura tracking is owned by the spell entry's castable identity.
-- Standalone aura entries have no separate castable identity, so their primary
-- aura remains the ownership probe. The castability primitive normalizes both.
function CooldownCompanion:EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID)
    if type(buttonData) ~= "table" then return false, false end

    if buttonData.type == "spell" and buttonData.addedAs ~= "aura" then
        return self:CanPlayerEverCastSpell(buttonData.id)
    end
    if not primaryAuraSpellID then return false, false end
    return self:CanPlayerEverCastSpell(primaryAuraSpellID)
end

-- Pet scope can follow a pet self-buff, so a standalone Aura entry does not
-- need a separate castable identity. Spell entries still use their castable
-- spell as the ownership proof that keeps their Aura override meaningful.
function CooldownCompanion:EntryCanUsePetAuraScope(buttonData, primaryAuraSpellID)
    if type(buttonData) ~= "table" then return false end
    if buttonData.type == "spell" and buttonData.addedAs == "aura" then
        return true
    end
    return self:EntryOwnsAuraForGroupScope(buttonData, primaryAuraSpellID) == true
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
    end

    table_sort(result, function(a, b) return a.charKey < b.charKey end)
    return result
end
