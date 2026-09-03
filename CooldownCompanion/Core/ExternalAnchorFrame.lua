--[[
    CooldownCompanion - Core/ExternalAnchorFrame.lua: the stable external anchor

    External addons (BigWigs and friends) anchor by GLOBAL FRAME NAME, and
    every panel frame is its own global ("CooldownCompanionGroup<id>"), so an
    anchor saved against one panel follows that panel only. This file owns ONE
    frame whose name never changes, CooldownCompanionExternalAnchor, and keeps
    it glued to whichever panel the owner marked for the current
    specialization.

    Storage: db.profile.externalAnchorPanels[specId] = groupId. One panel per
    spec; marking another panel replaces the previous holder. The key lives on
    the profile, so it travels with profile export/import and profile copies.
    A deleted panel drops its marks on every spec (delete cascades call
    ClearExternalAnchorMarksForPanels), and a stale mark left by an import is
    dropped where it is read.

    The frame is unprotected and only ever repositions ITSELF, so every path
    here is combat-safe. It SetAllPoints the marked panel's frame OBJECT
    (groupFrames or the dormant cache, never the global name, which a discard
    can leave answering twice), so moves, resizes, arrange drags, section
    changes and cursor motion follow for free. Re-pointing happens only when
    the resolved frame object changes, which FinalizePanelAnchors and the
    delete cascades drive.

    Visibility is deliberately NOT mirrored (owner ruling 2026-09-03): the
    frame stays shown while the marked panel has a frame for this character,
    even when that panel is hidden by its rules. With no usable target (no
    mark for this spec, or the marked panel never loads on this character) it
    hides and parks 1x1 at screen center.

    External addons only: Frame Anchoring, panel-to-panel anchors and
    container anchors never offer this frame as a target (owner ruling).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local type = type
local pairs = pairs
local tonumber = tonumber

local EXTERNAL_ANCHOR_FRAME_NAME = "CooldownCompanionExternalAnchor"
ST.EXTERNAL_ANCHOR_FRAME_NAME = EXTERNAL_ANCHOR_FRAME_NAME

local function GetStore(self, create)
    local profile = self.db and self.db.profile
    if not profile then return nil end
    local store = profile.externalAnchorPanels
    if type(store) ~= "table" then
        if not create then return nil end
        store = {}
        profile.externalAnchorPanels = store
    end
    return store
end

local function PanelExists(self, groupId)
    local groups = self.db and self.db.profile and self.db.profile.groups
    return groupId ~= nil and groups ~= nil and groups[groupId] ~= nil
end

function CooldownCompanion:GetExternalAnchorFrameName()
    return EXTERNAL_ANCHOR_FRAME_NAME
end

--- The panel marked for a spec (default: the current one), or nil.
function CooldownCompanion:GetExternalAnchorPanelId(specId)
    specId = tonumber(specId or self._currentSpecId)
    local store = specId and GetStore(self, false) or nil
    local groupId = store and tonumber(store[specId]) or nil
    if not groupId then return nil end
    if not PanelExists(self, groupId) then
        store[specId] = nil
        return nil
    end
    return groupId
end

function CooldownCompanion:IsExternalAnchorPanel(groupId)
    groupId = tonumber(groupId)
    return groupId ~= nil and self:GetExternalAnchorPanelId() == groupId
end

--- Mark a panel for the current spec. groupId nil clears the spec's mark.
function CooldownCompanion:SetExternalAnchorPanel(groupId)
    local specId = tonumber(self._currentSpecId)
    if not specId then return false end
    groupId = tonumber(groupId)
    if groupId and not PanelExists(self, groupId) then return false end
    local store = GetStore(self, true)
    store[specId] = groupId
    self:RefreshExternalAnchorFrame()
    return true
end

--- Delete cascades: a panel leaving the profile takes its marks with it on
--- every spec, not only the current one. groupIds is a set keyed by id.
function CooldownCompanion:ClearExternalAnchorMarksForPanels(groupIds)
    local store = GetStore(self, false)
    if store then
        for specId, groupId in pairs(store) do
            if groupIds[groupId] or groupIds[tonumber(groupId)] then
                store[specId] = nil
            end
        end
    end
    self:RefreshExternalAnchorFrame()
end

local function ResolveTargetFrame(self)
    local groupId = self:GetExternalAnchorPanelId()
    if not groupId then return nil end
    local frame = self.groupFrames and self.groupFrames[groupId] or nil
    if not frame and self._dormantFrames then
        frame = self._dormantFrames[groupId]
    end
    return frame
end

--- Point the stable frame at the marked panel's current frame object.
--- Idempotent and cheap: nothing happens unless the target object changed.
function CooldownCompanion:RefreshExternalAnchorFrame()
    local target = ResolveTargetFrame(self)
    local anchor = self._externalAnchorFrame
    if not anchor then
        if not target then return end
        anchor = CreateFrame("Frame", EXTERNAL_ANCHOR_FRAME_NAME, UIParent)
        anchor:EnableMouse(false)
        self._externalAnchorFrame = anchor
    end
    if anchor._externalAnchorTarget == target then return end
    anchor._externalAnchorTarget = target
    anchor:ClearAllPoints()
    if target then
        anchor:SetAllPoints(target)
        anchor:Show()
    else
        anchor:SetSize(1, 1)
        anchor:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        anchor:Hide()
    end
end
