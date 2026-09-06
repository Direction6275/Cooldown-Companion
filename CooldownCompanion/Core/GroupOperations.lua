--[[
    CooldownCompanion - GroupOperations
    Group refresh, availability rebuilding, dormant frames, and runtime coordination.

    Part of the GroupOperations family; see its ordered block in the addon TOC.
    Public methods attach to ST.Addon; local state stays with its owner.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local pairs = pairs
local ipairs = ipairs
local type = type
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local InCombatLockdown = InCombatLockdown
local C_CVar_GetCVarBool = C_CVar.GetCVarBool

-- ArrangeMode.lua
local GetUnlockedPanelAlpha = ST._GetUnlockedPanelAlpha

local function ClearButtonVisualState(button)
    local clear = ST._ClearButtonVisualState
    if clear then
        clear(button)
    end
end

local function UnregisterKeyPressHighlightFrame(frame)
    local unregisterButton = ST._UnregisterKeyPressHighlightButton
    if not (unregisterButton and frame and frame.buttons) then return end
    for _, button in ipairs(frame.buttons) do
        unregisterButton(button)
    end
end

local function RefreshKeyPressHighlightFrame(frame)
    local cacheButtonBindingKeys = ST._CacheButtonBindingKeys
    local refreshButton = ST._RefreshKeyPressHighlightEnrollment
    if not (frame and frame.buttons) then return end
    if not (cacheButtonBindingKeys or refreshButton) then return end

    for _, button in ipairs(frame.buttons) do
        if cacheButtonBindingKeys then
            cacheButtonBindingKeys(button, button.buttonData)
        else
            refreshButton(button)
        end
    end
end

local function GetFrameName(frame)
    if not frame then
        return nil
    end
    if frame.GetName then
        return frame:GetName()
    end
    if frame.groupId then
        return "CooldownCompanionGroup" .. frame.groupId
    end
    return frame.name
end

local function GetCurrentAnchorTargetName(frame)
    if not frame then
        return nil
    end
    if frame.anchoredToParent then
        return GetFrameName(frame.anchoredToParent)
    end
    if frame.GetPoint then
        local _, relativeFrame = frame:GetPoint(1)
        return GetFrameName(relativeFrame)
    end
    return frame.relativeTo
end

local function IsFrameAnchoredToSavedTarget(frame, anchor)
    local relativeTo = type(anchor) == "table" and anchor.relativeTo or nil
    if not relativeTo or relativeTo == "UIParent" then
        return true
    end
    return GetCurrentAnchorTargetName(frame) == relativeTo
end

local function GetPanelAnchorDepth(groups, groupId, visiting)
    visiting = visiting or {}
    if visiting[groupId] then
        return 0
    end
    visiting[groupId] = true

    local group = groups and groups[groupId]
    local anchor = group and group.anchor
    local relativeTo = type(anchor) == "table" and anchor.relativeTo or nil
    local kind, targetGroupId = CooldownCompanion:ParseAddonAnchorFrameName(relativeTo)
    if kind ~= "group" then
        visiting[groupId] = nil
        return 0
    end

    local target = groups[targetGroupId]
    if not (target and target.parentContainerId) then
        visiting[groupId] = nil
        return 0
    end

    local depth = GetPanelAnchorDepth(groups, targetGroupId, visiting) + 1
    visiting[groupId] = nil
    return depth
end

ST.LOAD_CONDITION_OPTIONS = ST.LOAD_CONDITION_OPTIONS or {
    { key = "raid",          label = "Raid" },
    { key = "dungeon",       label = "Dungeon" },
    { key = "delve",         label = "Delve" },
    { key = "battleground",  label = "Battleground" },
    { key = "arena",         label = "Arena" },
    { key = "openWorld",     label = "Open World" },
    { key = "rested",        label = "Rested Area" },
    { key = "petBattle",     label = "Pet Battle", default = true },
    { key = "vehicleUI",     label = "Vehicle / Override UI", default = true },
}

--- Return the per-spec order for a container, falling back to the
--- global .order field and then to the supplied default (typically the ID).
--- @param obj table  groupContainer with optional specOrders
--- @param specId number|nil  current specialization ID
--- @param default number|nil  fallback when no order exists
function CooldownCompanion:GetOrderForSpec(obj, specId, default)
    if obj.specOrders and specId then
        local so = obj.specOrders[specId]
        if so then return so end
    end
    return obj.order or default
end

--- Write a per-spec order value to a container.
--- Creates the specOrders table if it doesn't exist.
function CooldownCompanion:SetOrderForSpec(obj, specId, value)
    if not specId then
        obj.order = value
        return
    end
    if not obj.specOrders then obj.specOrders = {} end
    obj.specOrders[specId] = value
end

function CooldownCompanion:ClearUnsupportedProfileRuntime()
    if InCombatLockdown() then
        self._pendingUnsupportedLegacyHide = true
        return
    end

    self._pendingUnsupportedLegacyHide = nil

    local activeGroupIds = {}
    for groupId in pairs(self.groupFrames or {}) do
        activeGroupIds[#activeGroupIds + 1] = groupId
    end
    for _, groupId in ipairs(activeGroupIds) do
        self:UnloadGroup(groupId)
    end

    for containerId, frame in pairs(self.containerFrames or {}) do
        frame:Hide()
        self.containerFrames[containerId] = nil
    end

    for _, frame in pairs(self._dormantFrames or {}) do
        frame:Hide()
    end

    if self.RevertResourceBars then
        self:RevertResourceBars()
    end
    if self.RevertCastBar then
        self:RevertCastBar()
    end
end

function CooldownCompanion:IsGroupAvailableForAnchoring(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if not group.parentContainerId then return false end
    if self.CanGroupBeExternalAnchorTarget then
        if not self:CanGroupBeExternalAnchorTarget(groupId) then return false end
    elseif self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then
        return false
    end
    if self.IsIconLikeDisplayMode and not self:IsIconLikeDisplayMode(group.displayMode) then return false end
    -- An Aura Panel is never an anchor target (owner ruling 2026-08-15). Its
    -- height is whatever the active auras happen to need right now, so anything
    -- stacked off its edge would chase the aura churn. Structural, not a stored
    -- anchorEligible = false: an imported or hand-edited profile can undo a data
    -- write, and this predicate is what every consumer asks.
    --
    -- The rule now also lives on CanGroupBeExternalAnchorTarget (AnchorPolicy),
    -- which the branch above prefers and which covers MANUAL targets too. Kept
    -- here as well because the `elseif` fallback runs when that predicate is
    -- missing, and this list may not lose the rule with it.
    if ST.IsAuraPanelGroup(group) then return false end
    if group.anchorEligible == false then return false end
    local container = self:GetParentContainer(group)
    if container and container.isGlobal and not container.anchorEligible then return false end
    if container and not container.isGlobal and container.anchorEligible == false then return false end
    if not self:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = true,
        checkLoadConditions = true,
    }) then
        return false
    end

    return true
end

function CooldownCompanion:IsGroupAvailableForPanelAnchorTarget(groupId)
    local group = self.db.profile.groups[groupId]
    if not group then return false end
    if self.CanGroupBePanelAnchorTarget then
        if not self:CanGroupBePanelAnchorTarget(groupId) then return false end
    else
        if not group.parentContainerId then return false end
        if self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then return false end
        if CooldownCompanion:IsStandaloneTexturePanelGroup(group) then return false end
    end

    local container = self:GetParentContainer(group)
    if container and container.isGlobal and not container.anchorEligible then return false end
    if container and not container.isGlobal and container.anchorEligible == false then return false end

    if not self:IsGroupActive(groupId, {
        group = group,
        checkCharVisibility = true,
        checkLoadConditions = true,
    }) then
        return false
    end

    return true
end

function CooldownCompanion:GetFirstAvailableAnchorGroup()
    local db = self.db.profile
    local groups = db.groups
    if not groups then return nil end
    local containers = db.groupContainers
    if not containers then return nil end
    local specId = self._currentSpecId

    -- One walk over the panels, bucketed by container, in place of one
    -- GetPanels walk-and-sort per container: this runs on the bars-and-frames
    -- gate path, so its cost lands on every bar evaluation. Same ordering as
    -- GetPanels (order, then numeric id, then string id).
    local panelsByContainer = {}
    for groupId, group in pairs(groups) do
        local cid = group.parentContainerId
        if cid ~= nil and containers[cid] then
            local bucket = panelsByContainer[cid]
            if not bucket then
                bucket = {}
                panelsByContainer[cid] = bucket
            end
            bucket[#bucket + 1] = { groupId = groupId, group = group }
        end
    end

    local orderedContainers = {}
    for cid in pairs(panelsByContainer) do
        orderedContainers[#orderedContainers + 1] = {
            id = cid,
            order = self:GetOrderForSpec(containers[cid], specId, cid),
        }
    end
    table.sort(orderedContainers, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end

        local aId = tonumber(a.id)
        local bId = tonumber(b.id)
        if aId and bId and aId ~= bId then
            return aId < bId
        end
        return tostring(a.id) < tostring(b.id)
    end)

    for _, containerInfo in ipairs(orderedContainers) do
        local panels = panelsByContainer[containerInfo.id]
        table.sort(panels, ST.ComparePanelOrder)
        for _, panelInfo in ipairs(panels) do
            if self:IsGroupAvailableForAnchoring(panelInfo.groupId) then
                return panelInfo.groupId
            end
        end
    end
    return nil
end

local function IsResourceBarIndependentAnchor(settings, specId)
    local independent = settings and settings.independentAnchorEnabled == true
    local layouts = settings and settings.layoutOrder
    local layoutKey = specId and (tonumber(specId) or specId)
    local layout = nil
    if layoutKey and type(layouts) == "table" then
        layout = layouts[layoutKey] or layouts[tostring(layoutKey)]
    end
    if type(layout) == "table" and layout.independentAnchorEnabled ~= nil then
        independent = layout.independentAnchorEnabled == true
    end
    return independent
end

function CooldownCompanion:IsResourceBarAnchorIndependent()
    local settings = self.GetResourceBarSettings and self:GetResourceBarSettings() or nil
    return IsResourceBarIndependentAnchor(settings, self._currentSpecId)
end

-- anchorGroupId: the already-resolved GetFirstAvailableAnchorGroup result,
-- when the caller has it. That resolution walks and sorts every panel, and
-- the suppression refresh below is on the bars-and-frames gate path.
local function CollectStableExternalAnchorCompactReasons(self, groupId, anchorGroupId)
    groupId = tonumber(groupId)
    if not groupId then return nil end

    if anchorGroupId == nil then
        anchorGroupId = self.GetFirstAvailableAnchorGroup and tonumber(self:GetFirstAvailableAnchorGroup()) or nil
    end
    if anchorGroupId ~= groupId then return nil end

    local reasons = nil
    local function AddReason(reason)
        reasons = reasons or {}
        reasons[#reasons + 1] = reason
    end

    local frameSettings = self.GetFrameAnchoringSettings and self:GetFrameAnchoringSettings() or nil
    if frameSettings and frameSettings.enabled == true then
        AddReason("frameAnchoring")
    end

    local resourceSettings = self.GetResourceBarSettings and self:GetResourceBarSettings() or nil
    if resourceSettings
        and resourceSettings.enabled == true
        and not IsResourceBarIndependentAnchor(resourceSettings, self._currentSpecId) then
        AddReason("resourceBars")
    end

    local castSettings = self.GetCastBarSettings and self:GetCastBarSettings() or nil
    if castSettings and castSettings.enabled == true and castSettings.independentAnchorEnabled ~= true then
        AddReason("castBar")
    end

    return reasons
end

function CooldownCompanion:IsGroupStableExternalAnchor(groupId)
    return CollectStableExternalAnchorCompactReasons(self, groupId) ~= nil
end

function CooldownCompanion:GetGroupCompactLayoutSuppressionReasons(groupId)
    groupId = tonumber(groupId)
    if groupId and groupId == self._compactLayoutSuppressedGroupId then
        return self._compactLayoutSuppressionReasons
    end
    return nil
end

function CooldownCompanion:IsGroupCompactLayoutActive(groupId, group)
    group = group or (self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId])
    if not group or group.compactLayout ~= true then
        return false
    end
    return tonumber(groupId) ~= self._compactLayoutSuppressedGroupId
end

local function AreCompactSuppressionReasonsEqual(left, right)
    if left == right then return true end
    if type(left) ~= "table" or type(right) ~= "table" or #left ~= #right then
        return false
    end
    for index = 1, #left do
        if left[index] ~= right[index] then
            return false
        end
    end
    return true
end

local function RefreshCompactSuppressionAffectedGroup(self, groupId)
    groupId = tonumber(groupId)
    if not groupId then return end

    local group = self.db and self.db.profile and self.db.profile.groups and self.db.profile.groups[groupId]
    if not group or group.compactLayout ~= true then return end

    local frame = self.groupFrames and self.groupFrames[groupId]
    if frame then
        frame._layoutDirty = true
    end

    if (InCombatLockdown and InCombatLockdown() and frame and frame:IsProtected()) or not frame then
        self._pendingFullRefresh = true
    elseif self.RefreshGroupFrame then
        self:RefreshGroupFrame(groupId)
    end
end

function CooldownCompanion:RefreshStableExternalAnchorCompactSuppression(options)
    options = options or {}

    local oldGroupId = self._compactLayoutSuppressedGroupId
    local oldReasons = self._compactLayoutSuppressionReasons
    local newGroupId = self.GetFirstAvailableAnchorGroup and tonumber(self:GetFirstAvailableAnchorGroup()) or nil
    local newReasons = newGroupId and CollectStableExternalAnchorCompactReasons(self, newGroupId, newGroupId) or nil
    if not newReasons then
        newGroupId = nil
    end

    local targetChanged = oldGroupId ~= newGroupId
    local reasonsChanged = not AreCompactSuppressionReasonsEqual(oldReasons, newReasons)
    if not targetChanged and not reasonsChanged then
        return false
    end

    self._compactLayoutSuppressedGroupId = newGroupId
    self._compactLayoutSuppressionReasons = newReasons

    if targetChanged and options.refreshAffected ~= false then
        RefreshCompactSuppressionAffectedGroup(self, oldGroupId)
        RefreshCompactSuppressionAffectedGroup(self, newGroupId)
    end

    return true
end

function CooldownCompanion:PopulatePanelAnchorTargetDropdown(dropdown, sourceGroupId)
    local db = self.db.profile
    local containers = db.groupContainers or {}
    local groupedPanels = {}
    local eligibleCount = 0

    dropdown:SetList({}, {})

    for groupId, group in pairs(db.groups) do
        local targetFrameName = "CooldownCompanionGroup" .. groupId
        if groupId ~= sourceGroupId
            and _G[targetFrameName]
            and not self:WouldCreateCircularAnchor(sourceGroupId, groupId)
            and self:IsGroupAvailableForPanelAnchorTarget(groupId) then
            eligibleCount = eligibleCount + 1
            local cid = group.parentContainerId
            local ctr = containers[cid]
            local contName = ctr and ctr.name or "Group"
            local containerBucket = groupedPanels[cid]
            if not containerBucket then
                containerBucket = {
                    id = cid,
                    name = contName,
                    order = self:GetOrderForSpec(ctr or {}, self._currentSpecId, cid),
                    panels = {},
                }
                groupedPanels[cid] = containerBucket
            end
            table.insert(containerBucket.panels, {
                id = groupId,
                key = tostring(groupId),
                name = group.name or ("Panel " .. groupId),
                contName = contName,
                order = group.order or groupId,
            })
        end
    end

    local sortedContainers = {}
    for _, container in pairs(groupedPanels) do
        table.insert(sortedContainers, container)
    end
    table.sort(sortedContainers, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.name < b.name
    end)
    for _, container in ipairs(sortedContainers) do
        local containerHdrKey = "_panel_ctr_" .. tostring(container.id)
        dropdown:AddItem(containerHdrKey, "|cffffd100" .. container.name .. "|r")
        dropdown:SetItemDisabled(containerHdrKey, true)

        table.sort(container.panels, function(a, b)
            if a.order ~= b.order then return a.order < b.order end
            return a.name < b.name
        end)
        for _, panel in ipairs(container.panels) do
            dropdown:AddItem(panel.key, "   " .. panel.name)
            dropdown.list[panel.key] = panel.contName .. ": " .. panel.name
        end
    end

    return eligibleCount
end

local function GetFrameForButtonSetComparison(addon, groupId)
    local frame = addon.groupFrames and addon.groupFrames[groupId]
    if frame then return frame end
    return addon._dormantFrames and addon._dormantFrames[groupId] or nil
end

function CooldownCompanion:GroupButtonSetNeedsRebuild(groupId, group, opts)
    opts = opts or {}
    local frame = GetFrameForButtonSetComparison(self, groupId)
    if not frame or not frame.buttons then
        return false
    end
    if self:IsRotationAssistantGroup(group) then
        local buttonData = frame._rotationAssistantButtonData
        return #frame.buttons ~= 1
            or not frame.buttons[1]
            or frame.buttons[1].buttonData ~= buttonData
    end
    -- An Aura Panel's button list is empty by design, so the entry-count
    -- comparison below would report "needs rebuild" forever: one such panel
    -- would force a full refresh of EVERY group on every availability pass.
    -- Answering a flat false instead deleted the panel's OWN refresh trigger --
    -- nothing re-ran population when a talent or load-condition change altered
    -- WHICH entries are usable, so the footprint, the unlock placeholders and
    -- the aura rebind all went stale. Compare the ordered entry signature
    -- PopulateGroupButtons stamped on the frame instead. It holds still for a
    -- panel whose entries did not change -- so the every-sweep refresh storm the
    -- flat false was guarding against stays prevented -- and differs the moment
    -- they do, including a same-count swap between two mutually exclusive talent
    -- auras, which no count comparison could see.
    if ST.IsAuraPanelGroup(group) then
        -- Resolved exactly the way PopulateGroupButtons resolves it, so an
        -- unlock preview (which relaxes load conditions for the stored
        -- signature) cannot make stored and current disagree on every sweep.
        local buttonUsabilityOptions = opts.buttonUsabilityOptions
            or self:GetGroupButtonUsabilityOptions(groupId, group)
        -- A frame that has never been populated carries no signature. Reading
        -- that as the empty signature mirrors the non-aura path below exactly:
        -- an empty button list needs a rebuild when there are usable entries,
        -- and does not when there are none.
        return (frame._auraPanelEntrySig or "")
            ~= self:GetAuraPanelEntrySignature(group, buttonUsabilityOptions)
    end
    if not group.buttons then
        return #frame.buttons > 0
    end

    local usableButtons = {}
    local usableCount = 0
    local buttonUsabilityOptions = opts.buttonUsabilityOptions
    -- Aura-section members leave both sides of the comparison below: they never
    -- materialize a button, so counting them would report "needs rebuild" every
    -- sweep. Their identity rides the signature instead, diffed here first so a
    -- talent swap inside a section still triggers the rebuild the button
    -- comparison can no longer see.
    local auraSectionPanel = ST.PanelHasAuraSection(group)
    if auraSectionPanel then
        local options = buttonUsabilityOptions
            or self:GetGroupButtonUsabilityOptions(groupId, group)
        if (frame._auraSectionEntrySig or "")
            ~= self:GetAuraSectionEntrySignature(group, options) then
            return true
        end
    end
    for _, buttonData in ipairs(group.buttons) do
        if self:IsButtonUsable(buttonData, group, buttonUsabilityOptions)
            and not (auraSectionPanel and ST.IsAuraSectionEntry(group, buttonData)) then
            usableCount = usableCount + 1
            usableButtons[usableCount] = buttonData
        end
    end

    if #frame.buttons ~= usableCount then
        return true
    end

    for i = 1, usableCount do
        local button = frame.buttons[i]
        if not button or button.buttonData ~= usableButtons[i] then
            return true
        end
    end

    return false
end

function CooldownCompanion:AnyGroupButtonSetNeedsRebuild()
    if not self.db or not self.db.profile or not self.db.profile.groups then
        return false
    end

    for groupId, group in pairs(self.db.profile.groups) do
        if self:IsGroupVisibleToCurrentChar(groupId)
            and self:IsGroupActive(groupId, {
                group = group,
                checkCharVisibility = false,
                checkLoadConditions = true,
                requireButtons = false,
            })
            and self:GroupButtonSetNeedsRebuild(groupId, group)
        then
            return true
        end
    end

    return false
end

function CooldownCompanion:ResetSpellAvailabilityButtonRuntime()
    local function resetFrameButtons(frame)
        if not frame or not frame.buttons then return end
        for _, button in ipairs(frame.buttons) do
            local buttonData = button.buttonData
            if buttonData and buttonData.type == "spell" then
                button._noCooldown = nil
                button._noCooldownSpellId = nil
                button._baseNoCooldown = nil
                button._baseNoCooldownSpellId = nil
                button._resourceGateCost = nil
                button._resourceGateCostSpellId = nil
                button._baseResourceGateCost = nil
                button._baseResourceGateCostSpellId = nil
                button._displaySpellId = nil
                button._liveOverrideSpellId = nil
                button._lastSpellTexture = nil
                button._lastTextureCheckAt = nil
                button._iconDirty = true
                button._cooldownDeferred = nil
                button._durationObj = nil
                button._chargeDurationObj = nil
                -- _totemSwipeStyleActive stays: it owes the swipe-style restore
                -- and the next pass runs the falling edge (see GroupFrame).
                button._totemActive = nil
                button._chargeRecharging = nil
                button._chargeState = nil
                button._currentReadableCharges = nil
                button._chargeCountReadable = nil
                button._zeroChargesConfirmed = nil
                button._displayCountZeroUsabilityFallback = nil
                ClearButtonVisualState(button)
            end
        end
    end

    if self.groupFrames then
        for _, frame in pairs(self.groupFrames) do
            resetFrameButtons(frame)
        end
    end
    if self._dormantFrames then
        for _, frame in pairs(self._dormantFrames) do
            resetFrameButtons(frame)
        end
    end

    self:MarkCooldownsDirty("availability-rebuild")
end

-- opts.perGroupRebuild: never escalate to RefreshAllGroups. The visibility
-- pass already repopulates each panel whose entry set moved and re-finalizes
-- anchors afterwards, so a caller that cannot have changed container
-- visibility (SPELLS_CHANGED on a shapeshift, the settling pass) gets the
-- changed panels rebuilt without a from-scratch refresh of every panel in
-- the profile. Spec and talent callers keep the escalation: they can flip
-- which containers exist for the character.
function CooldownCompanion:RefreshAllGroupsForSpellAvailability(opts)
    local needsFullRefresh = not (opts and opts.perGroupRebuild)
        and self:AnyGroupButtonSetNeedsRebuild()
    self:ResetSpellAvailabilityButtonRuntime()

    if needsFullRefresh then
        self:RefreshAllGroups()
    else
        self:RefreshAllGroupsVisibilityOnly()
    end

    ST.TagRefreshPass("availability-rebuild")
    self:UpdateAllCooldowns()

    -- D3: spec/talent/spell-availability churn can change override identity
    -- without repopulating buttons — refresh the identity index (coalesced).
    self:RequestSpellButtonIndexRebuild("availability")
end

function CooldownCompanion:CreateAllGroupFrames()
    local previousCreatingAllGroupFrames = self._creatingAllGroupFrames
    self._creatingAllGroupFrames = true
    for groupId, _ in pairs(self.db.profile.groups) do
        if self:IsGroupVisibleToCurrentChar(groupId) then
            self:CreateGroupFrame(groupId)
        end
    end
    self._creatingAllGroupFrames = previousCreatingAllGroupFrames
    self:FinalizePanelAnchors()
    self:FinalizeNonPanelGroupAnchors()
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
    self:RefreshCursorAnchorLayoutPreview()
end

function CooldownCompanion:FinalizePanelAnchors()
    local groups = self.db and self.db.profile and self.db.profile.groups
    if not (groups and self.groupFrames) then
        return
    end

    self:RefreshStableExternalAnchorCompactSuppression()

    -- This is the post-create/post-refresh owner for panel lifecycle order:
    -- size every panel first, then re-apply saved anchors from roots outward.
    local panels = {}
    for groupId, group in pairs(groups) do
        local frame = self.groupFrames[groupId]
        if group and group.parentContainerId and group.anchor and frame then
            if not self:IsGroupCompactLayoutActive(groupId, group) then
                frame.layoutButtonCount = self:GetGroupLayoutButtonCount(groupId, group)
            else
                frame.layoutButtonCount = nil
            end
            self:ResizeGroupFrame(groupId)
            panels[#panels + 1] = {
                groupId = groupId,
                group = group,
                frame = frame,
                depth = GetPanelAnchorDepth(groups, groupId),
            }
        end
    end

    table.sort(panels, function(a, b)
        if a.depth ~= b.depth then
            return a.depth < b.depth
        end
        return tostring(a.groupId) < tostring(b.groupId)
    end)

    for _, panel in ipairs(panels) do
        local compactLayoutActive = self:IsGroupCompactLayoutActive(panel.groupId, panel.group)
        if not (compactLayoutActive and IsFrameAnchoredToSavedTarget(panel.frame, panel.group.anchor)) then
            self:AnchorGroupFrame(panel.frame, panel.group.anchor)
        end
    end

    self:RebuildPanelAlphaDependencyTargets(groups)
    -- Every bulk frame pass ends here, so the stable external anchor
    -- re-points once per pass, after the marked panel's frame object settles.
    self:RefreshExternalAnchorFrame()
end

function CooldownCompanion:FinalizeNonPanelGroupAnchors()
    local groups = self.db and self.db.profile and self.db.profile.groups
    if not (groups and self.groupFrames) then
        return
    end

    for groupId, group in pairs(groups) do
        local anchor = group and group.anchor
        local relativeTo = type(anchor) == "table" and anchor.relativeTo or nil
        local targetKind = self:ParseAddonAnchorFrameName(relativeTo)
        local frame = self.groupFrames[groupId]
        if frame
            and group
            and not group.parentContainerId
            and (targetKind == "group" or targetKind == "container") then
            self:AnchorGroupFrame(frame, anchor)
        end
    end
end

function CooldownCompanion:RefreshAllGroups()
    if self._unsupportedLegacyProfile then
        self:ClearUnsupportedProfileRuntime()
        return
    end

    self:RefreshStableExternalAnchorCompactSuppression({ refreshAffected = false })

    -- Defer entire refresh during combat — protected frame operations
    -- (Show/Hide/SetSize/SetPoint/SetFrameStrata/RegisterForDrag/EnableMouse)
    -- are all blocked. Per-tick cooldown updates continue independently.
    if InCombatLockdown() then
        self._pendingFullRefresh = true
        if self.RefreshAlphaUpdateDriver then
            self:RefreshAlphaUpdateDriver()
        end
        return
    end
    -- Clean up stale container frames (e.g. after profile switch)
    if self.containerFrames then
        local containers = self.db.profile.groupContainers or {}
        for containerId, frame in pairs(self.containerFrames) do
            if not containers[containerId] then
                frame:Hide()
                self.containerFrames[containerId] = nil
            end
        end
        -- Ensure all current-profile containers have frames
        for containerId, _ in pairs(containers) do
            if self:IsContainerVisibleToCurrentChar(containerId) then
                if not self.containerFrames[containerId] then
                    self:CreateContainerFrame(containerId)
                else
                    self.containerFrames[containerId]:Show()
                end
            else
                if self.containerFrames[containerId] then
                    self.containerFrames[containerId]:Hide()
                end
            end
        end
    end

    -- Fully unload frames for groups not in the current profile
    -- (e.g. after a profile switch).
    for groupId, _ in pairs(self.groupFrames) do
        if not self.db.profile.groups[groupId] then
            self:UnloadGroup(groupId)
            self:DiscardDormantFrame(groupId)
        end
    end
    -- Also discard dormant frames for deleted groups
    if self._dormantFrames then
        for groupId, _ in pairs(self._dormantFrames) do
            if not self.db.profile.groups[groupId] then
                self:DiscardDormantFrame(groupId)
            end
        end
    end

    -- Refresh current profile's groups: load active ones, unload inactive ones
    for groupId, group in pairs(self.db.profile.groups) do
        local visible = self:IsGroupVisibleToCurrentChar(groupId)
        if not visible then
            self:UnloadGroup(groupId)
        elseif self:IsGroupActive(groupId, {
            group = group,
            checkCharVisibility = false,
            checkLoadConditions = true,
            requireButtons = false,
        }) then
            self:RefreshGroupFrame(groupId)
        else
            self:UnloadGroup(groupId)
        end
    end

    self:FinalizeContainerAnchorsToScreenOffsets()
    self:FinalizePanelAnchors()
    if self.RefreshAllContainerWrappers then
        self:RefreshAllContainerWrappers()
    end
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
    self:RefreshCursorAnchorLayoutPreview()
    self:RefreshUnlockToolbar()
end

-- Refresh only frame-level visibility/load-state without rebuilding buttons.
-- Used by zone/resting/pet-battle transitions to avoid compact-layout flash
-- caused by full button repopulation.
function CooldownCompanion:RefreshAllGroupsVisibilityOnly()
    -- nil until this pass reports: a hook must never read the previous pass.
    self._lastVisibilityPassChanged = nil
    if self._unsupportedLegacyProfile then
        self:ClearUnsupportedProfileRuntime()
        return
    end

    -- Whether this pass loaded, unloaded, repopulated or first-showed any
    -- frame. The anchor/wrapper finalization at the end costs a resize and
    -- re-anchor of every panel, and the resource bar hook re-applies the bars
    -- after it; neither has anything to do when the pass changed nothing,
    -- which is every shapeshift on a profile without form-gated entries.
    local changed = self:RefreshStableExternalAnchorCompactSuppression() == true

    -- Fully unload frames for groups not in the current profile
    for groupId, _ in pairs(self.groupFrames) do
        if not self.db.profile.groups[groupId] then
            self:UnloadGroup(groupId)
            self:DiscardDormantFrame(groupId)
            changed = true
        end
    end
    -- Also discard dormant frames for deleted groups
    if self._dormantFrames then
        for groupId, _ in pairs(self._dormantFrames) do
            if not self.db.profile.groups[groupId] then
                self:DiscardDormantFrame(groupId)
            end
        end
    end

    for groupId, group in pairs(self.db.profile.groups) do
        local visible = self:IsGroupVisibleToCurrentChar(groupId)
        if not visible then
            if self.groupFrames[groupId] then
                self:UnloadGroup(groupId)
                changed = true
            end
        else
            local active = self:IsGroupActive(groupId, {
                group = group,
                checkCharVisibility = true,
                checkLoadConditions = true,
                requireButtons = true,
            })

            if not active then
                if self.groupFrames[groupId] then
                    self:UnloadGroup(groupId)
                    changed = true
                end
            else
                local frame = self.groupFrames[groupId]
                if frame and self:GroupButtonSetNeedsRebuild(groupId, group) then
                    self:RefreshGroupFrame(groupId)
                    frame = self.groupFrames[groupId]
                    changed = true
                elseif not frame then
                    changed = true
                    if self:GroupButtonSetNeedsRebuild(groupId, group) then
                        -- Recover the shell and repopulate it rather than
                        -- discarding it: frames cannot be destroyed, so a
                        -- discard leaks the whole tree (buttons, cooldowns and
                        -- their irremovable aura slot containers) and leaves a
                        -- second frame answering to the same global name, which
                        -- the by-name anchor checks then match against.
                        -- RefreshGroupFrame recovers the dormant shell into
                        -- groupFrames and repopulates its children.
                        self:RefreshGroupFrame(groupId)
                        frame = self.groupFrames[groupId]
                    else
                        -- Recover dormant frame with buttons intact (no repopulation needed)
                        frame = self:RecoverDormantFrame(groupId)
                    end
                end
                if not frame then
                    if InCombatLockdown() then
                        self._pendingVisibilityRefresh = true
                    else
                        frame = self:CreateGroupFrame(groupId)
                    end
                end

                if frame then
                    local wasShown = frame:IsShown()
                    if InCombatLockdown() and frame:IsProtected() then
                        if not wasShown then
                            self._pendingVisibilityRefresh = true
                        end
                    else
                        frame:Show()
                    end
                    local isLocked = not (
                        frame._containerUnlockPreviewActive == true
                        or frame._panelUnlockPreviewActive == true
                    )
                    if self.IsGroupCursorAnchored and self:IsGroupCursorAnchored(group) then
                        isLocked = true
                    end
                    -- Keep unlocked panels fully visible, except unlock ghosts.
                    if not isLocked then
                        frame:SetAlpha(GetUnlockedPanelAlpha(frame))
                    -- Apply current alpha from the alpha fade system so frame
                    -- doesn't flash at 1.0 when baseline alpha is configured.
                    else
                        local frameAlpha, _, hasRuntimeAlpha = self:GetPanelCurrentAlphaValue(groupId, group)
                        if hasRuntimeAlpha then
                            frame:SetAlpha(frameAlpha)
                        end
                    end

                    -- When transitioning hidden -> shown, refresh button state
                    -- immediately so compact groups never show stale slots.
                    if not wasShown then
                        changed = true
                        if frame.UpdateCooldowns then
                            frame:UpdateCooldowns()
                        end
                        if self:IsGroupCompactLayoutActive(groupId, group) then
                            frame._layoutDirty = true
                            self:UpdateGroupLayout(groupId)
                        end
                    end
                end
            end
        end
    end

    -- Read by the resource bar lifecycle hook on this method, which otherwise
    -- re-applies every bar 0.1s after each pass.
    self._lastVisibilityPassChanged = changed
    if changed then
        self:FinalizeContainerAnchorsToScreenOffsets()
        self:FinalizePanelAnchors()
        if self.RefreshAllContainerWrappers then
            self:RefreshAllContainerWrappers()
        end
    end
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
    self:RefreshCursorAnchorLayoutPreview()
end

-- Fully unload a group: save/clear button OnUpdate scripts, clear runtime
-- state, hide the frame, and move it to a dormant cache for reuse. Config
-- data (db.profile.groups) is preserved so the group can reload when load
-- conditions change. Buttons remain attached to the frame so visibility-only
-- transitions can reuse them without creating new C-side frame objects, and
-- Masque registration is left intact for the same reason -- it is torn down
-- in DiscardDormantFrame, the true-teardown path.
function CooldownCompanion:UnloadGroup(groupId)
    local frame = self.groupFrames[groupId]
    if not frame then return end
    UnregisterKeyPressHighlightFrame(frame)

    -- Save and clear button OnUpdate scripts.
    -- Buttons stay attached to the frame for potential reuse.
    if frame.buttons then
        for _, button in ipairs(frame.buttons) do
            if self.HideAuraTextureVisual then
                self:HideAuraTextureVisual(button)
            end
            local onUpdate = button:GetScript("OnUpdate")
            if onUpdate then
                button._savedOnUpdate = onUpdate
                button:SetScript("OnUpdate", nil)
            end
        end
    end

    -- Clear alpha fade state
    if self.alphaState then
        self.alphaState[groupId] = nil
    end

    -- Stop alphaSyncFrame OnUpdate
    if frame.alphaSyncFrame then
        frame.alphaSyncFrame:SetScript("OnUpdate", nil)
    end

    -- Hide and move to dormant cache for reuse
    if InCombatLockdown() and frame:IsProtected() then
        if frame:IsShown() then
            self._pendingVisibilityRefresh = true
        end
    else
        frame:Hide()
    end
    frame._triggerSoundInitialized = nil
    frame._triggerSoundWasVisible = nil
    self._dormantFrames = self._dormantFrames or {}
    self._dormantFrames[groupId] = frame
    self.groupFrames[groupId] = nil
    -- D3: frame left the live set — refresh the identity index (coalesced).
    self:RequestSpellButtonIndexRebuild("unload")
    -- Native aura sounds are Blizzard-side registrations keyed on unit+spell,
    -- not on this frame, so parking the panel does not stop them: a hidden
    -- panel keeps alerting until a pass parks its records. Same reason the
    -- delete paths rebind.
    self:RequestAuraRebind("unload")
    if self.RefreshCursorAnchorTicker then
        self:RefreshCursorAnchorTicker()
    end
    if self.RefreshAlphaUpdateDriver then
        self:RefreshAlphaUpdateDriver()
    end
end

-- Recover a dormant frame: restore it to groupFrames and re-enable button
-- OnUpdate scripts. Used by visibility-only transitions to avoid recreating
-- buttons.
function CooldownCompanion:RecoverDormantFrame(groupId)
    if not self._dormantFrames then return nil end
    local frame = self._dormantFrames[groupId]
    if not frame then return nil end

    self._dormantFrames[groupId] = nil
    self.groupFrames[groupId] = frame

    -- Restore button OnUpdate scripts
    if frame.buttons then
        for _, button in ipairs(frame.buttons) do
            if button._savedOnUpdate then
                button:SetScript("OnUpdate", button._savedOnUpdate)
                button._savedOnUpdate = nil
            end
        end
    end
    RefreshKeyPressHighlightFrame(frame)

    -- Masque registration survives dormancy, so reconcile it in both directions:
    -- rebuild it when the group should be skinned but isn't, and release it when
    -- the group stopped being skinned while the frame was parked. The second case
    -- matters because writers that bypass ToggleGroupMasque (preset/style copies,
    -- combat-deferred edits) can clear masqueEnabled on a dormant group, and only
    -- RemoveButtonFromMasque restores CC's native borders.
    local group = self.db.profile.groups[groupId]
    if group and group.masqueEnabled and self.Masque and not self.MasqueGroups[groupId] then
        self:CreateMasqueGroup(groupId)
        for _, button in ipairs(frame.buttons) do
            self:AddButtonToMasque(groupId, button)
        end
    elseif self.Masque and self.MasqueGroups[groupId] and not (group and group.masqueEnabled) then
        for _, button in ipairs(frame.buttons) do
            self:RemoveButtonFromMasque(groupId, button)
        end
        self:DeleteMasqueGroup(groupId)
    end

    -- Restore alpha sync if this frame inherits alpha from a parent frame.
    -- Skip if anchor is pending re-evaluation — anchoredToParent may be stale
    -- and will be corrected when AnchorGroupFrame runs from the layout ticker.
    if frame.anchoredToParent and not frame._anchorDirty then
        self:SetupAlphaSync(frame, frame.anchoredToParent)
    end

    -- D3: frame re-entered the live set without repopulation — refresh the
    -- identity index (coalesced).
    self:RequestSpellButtonIndexRebuild("recover")
    -- The counterpart to the unload rebind: recovery skips PopulateGroupButtons
    -- (that is the point of the dormant path), so nothing else re-binds these
    -- buttons. Any pass that ran while the panel was parked left its records
    -- parked — container hidden, sounds released — and they stay that way.
    self:RequestAuraRebind("recover")

    return frame
end

-- Discard a dormant frame permanently (used by delete operations). This is the
-- true-teardown path, so the Masque group is released here rather than when the
-- frame is merely parked.
function CooldownCompanion:DiscardDormantFrame(groupId)
    local frame = self._dormantFrames and self._dormantFrames[groupId] or nil
    UnregisterKeyPressHighlightFrame(frame)
    if frame and frame.buttons then
        for _, button in ipairs(frame.buttons) do
            self:RemoveButtonFromMasque(groupId, button)
            if self.ReleaseAuraTextureVisual then
                self:ReleaseAuraTextureVisual(button)
            end
        end
    end
    self:DeleteMasqueGroup(groupId)
    if frame and self.ReleaseGroupButtonPools then
        self:ReleaseGroupButtonPools(frame)
    end
    if self._dormantFrames then
        self._dormantFrames[groupId] = nil
    end
end

-- A1 shared per-pass input snapshot: the GCD state (spell 61304), the
-- assisted-highlight hostile-target gate, and the CDM viewer CVar -- the three
-- reads every button in a pass must see identically (D4 inventory A1). Extracted
-- so routed mini-passes (F1 3b) take the same once-per-batch snapshot the broad
-- walk uses. Deliberately does NOT touch _cooldownUpdatePassActive or
-- _passTimeStateSeen: a mini-pass must not set either (3b constraints 4-5), so
-- those stay in UpdateAllCooldowns below.
function CooldownCompanion:SnapshotCooldownPassContext()
    self._gcdInfo = C_Spell.GetSpellCooldown(61304)
    -- GCD activity: isActive is NeverSecret (12.0.1 hotfix)
    self._gcdActive = self._gcdInfo and self._gcdInfo.isActive or false
    -- Cache for GCD overlay display in CooldownUpdate (only when GCD is active)
    self._gcdDurationObj = self._gcdActive and C_Spell.GetSpellCooldownDuration(61304) or nil

    -- Assisted highlight target gate:
    -- hard target has priority; if none exists, allow soft enemy fallback.
    local hasHostileTarget = false
    if UnitExists("target") then
        hasHostileTarget = UnitCanAttack("player", "target") and true or false
    elseif UnitExists("softenemy") then
        hasHostileTarget = UnitCanAttack("player", "softenemy") and true or false
    end
    self._assistedHighlightHasHostileTarget = hasHostileTarget

    -- Cache CDM viewer CVar once per tick (avoids per-button GetCVarBool in ResolveBuffViewerFrameForSpell)
    self._cdmViewerEnabled = C_CVar_GetCVarBool("cooldownViewerEnabled") == true
end

function CooldownCompanion:UpdateAllCooldowns()
    local T = ST.RefreshTelemetry
    local telemetryOn = T and T.enabled
    local t0, frames, buttons
    if telemetryOn then
        t0 = debugprofilestop()
        frames, buttons = 0, 0
    end

    self:SnapshotCooldownPassContext()
    self._cooldownUpdatePassActive = true
    -- F2 idle skip: reset the per-pass time-animation flag. Any button that renders
    -- time-driven state this walk sets it true (NoteButtonTimeState); a walk that
    -- ends with it still false latches idle-eligible below. Fail open.
    self._passTimeStateSeen = false

    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame.UpdateCooldowns and frame:IsShown() then
            frame:UpdateCooldowns()
            if telemetryOn then
                frames = frames + 1
                buttons = buttons + (frame.buttons and #frame.buttons or 0)
            end
        end
    end

    self._cooldownUpdatePassActive = nil
    -- F2 idle-skip eligibility: a completed full walk that saw no time-animated
    -- button latches idle-eligible. Only this line may latch it true; every
    -- other writer (NoteButtonTimeState) may only clear it to false. It is thus
    -- never older than the last completed walk. Maintained unconditionally (not
    -- gated on telemetry) so the live-skip predicate (CanSkipIdleTickerRefresh)
    -- can read it. Fail open.
    self._tickerIdleEligible = not self._passTimeStateSeen
    -- F2: any completed walk restarts the idle-skip safety clock (see
    -- TICKER_MAX_CONSECUTIVE_SKIPS). Covers every walk path, not just the ticker.
    self._tickerSkipStreak = 0
    if telemetryOn then
        local elapsed = debugprofilestop() - t0
        T:RecordPass(frames, buttons, elapsed)
    end
end

function CooldownCompanion:UpdateAllGroupLayouts()
    -- Combat state cannot change part-way through a synchronous pass, so the
    -- lockdown read is per pass, not per frame.
    local inCombat = InCombatLockdown()
    for groupId, frame in pairs(self.groupFrames) do
        if frame and frame:IsShown() then
            local protected = inCombat and frame:IsProtected()
            if frame._strataDirty and not protected then
                self:RefreshGroupFrame(groupId)
            end
            if frame._sizeDirty then
                self:ResizeGroupFrame(groupId)
            end
            if frame._layoutDirty then
                self:UpdateGroupLayout(groupId)
            end
            if frame._anchorDirty and not protected then
                local group = self.db.profile.groups[groupId]
                if group then
                    self:AnchorGroupFrame(frame, group.anchor)
                end
            end
        end
    end
    -- Recover deferred container anchors
    if self.containerFrames then
        for containerId, frame in pairs(self.containerFrames) do
            if frame and frame:IsShown() and frame._anchorDirty then
                if not (inCombat and frame:IsProtected()) then
                    local container = self.db.profile.groupContainers[containerId]
                    if container then
                        self:AnchorContainerFrame(frame, container.anchor)
                    end
                end
            end
        end
    end
end

-- Utility functions
function CooldownCompanion:GetSpellInfo(spellId)
    local spellInfo = C_Spell.GetSpellInfo(spellId)
    if spellInfo then
        return spellInfo.name, spellInfo.iconID, spellInfo.castTime
    end
    return nil
end

function CooldownCompanion:GetItemInfo(itemId)
    local itemName, _, _, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemId)
    if not itemName then
        local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemId)
        return nil, icon
    end
    return itemName, itemIcon
end
