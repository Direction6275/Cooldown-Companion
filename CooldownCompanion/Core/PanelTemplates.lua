--[[
    CooldownCompanion - Core/PanelTemplates.lua: Panel Templates store and API

    A Panel Template is one panel's style saved under a name, ACCOUNT-WIDE
    (db.global.panelTemplates), so a player can create new panels from it on
    any spec or character, or apply it to a panel that already exists. The
    config addon owns every surface (context menus, popups, create tiles);
    this file owns the data and the apply path.

    The store is deliberately a MINI PROFILE: `groups` is a map of
    panel-shaped tables (the documented panel shape in Defaults.lua) with an
    empty `buttons` list, plus its own `nextGroupId`, so the per-login
    migration chain can walk it exactly as it walks a profile. That walk is
    CooldownCompanion:NormalizePanelTemplateStore (Core/Migrations.lua), run
    every login and on profile change; nothing here normalizes a template.

    THE LINE. A template carries exactly three things:
      * the look: every key of every ST.PANEL_COPY_SCOPES[mode] scope - the
        registry Copy Panel Settings writes - plus masqueEnabled and the
        compact trio where the mode's appearance scope carries them;
      * the shape: ST.PANEL_TEMPLATE_SHAPE_KEYS[mode], the arrangement the
        Layout tab edits;
      * the panel's offset from its own Group frame (point, relativePoint,
        x, y) - and only that anchor.
    It never carries entries, per-entry settings, sections, alpha or
    visibility, strata, name-derived data (order, createdBy, cdmPanelSource),
    the Aura Panel flag, or an anchor to another panel, frame, or the cursor.

    Owner ruling (2026-09-01): Apply on an existing panel keeps the panel
    where it is; create-from-template places the new panel at the template's
    offset. ApplyPanelTemplate exposes the switch (opts.position, default
    off): CreatePanelFromTemplate below passes it itself, and the config
    passes position = false for Apply on an existing panel.

    Every apply runs through ST._ApplyPanelSettingsSource
    (Core/GroupManagement.lua), the applier Copy Panel Settings uses, so the
    baseline rule, the durationFormat rewrite, the Aura Panel invariants, the
    Masque lifecycle and the combat deferral stay one implementation.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local pairs = pairs
local ipairs = ipairs
local type = type
local tonumber = tonumber
local tostring = tostring
local table_sort = table.sort
local string_lower = string.lower

local CONTAINER_FRAME_PREFIX = "CooldownCompanionContainer"

local function DefaultTemplateAnchor()
    return { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 }
end

-- Trimmed, never empty: a blank name falls back to the template's id.
local function NormalizeTemplateName(name, templateId)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then
        name = "Template " .. tostring(templateId)
    end
    return name
end

-- Unique within the store, case-insensitively: a taken name gets " (2)",
-- " (3)", ... appended until it is free. `excludeId` is the template being
-- named, whose own current name is not a collision.
local function UniqueTemplateName(store, name, excludeId)
    local taken = {}
    for id, template in pairs(store.groups) do
        if id ~= excludeId and type(template) == "table" and type(template.name) == "string" then
            taken[string_lower(template.name)] = true
        end
    end
    if not taken[string_lower(name)] then
        return name
    end
    local suffix = 2
    while taken[string_lower(name .. " (" .. suffix .. ")")] do
        suffix = suffix + 1
    end
    return name .. " (" .. suffix .. ")"
end

local function GetProfileGroup(self, groupId)
    local db = self.db and self.db.profile
    groupId = tonumber(groupId)
    return db and db.groups and groupId and db.groups[groupId] or nil
end

-- The template body for one panel: look, shape, and Group offset, nothing
-- else. Save and update share it; the caller stamps the name.
local function BuildPanelTemplateSnapshot(self, group, mode)
    local db = self.db.profile
    -- Per key: the panel's value, or the shipped default where it carries
    -- none - the baseline rule the settings applier writes with - so the
    -- template reproduces the panel exactly, including keys left at default.
    local baseline = db.globalStyle or {}
    local sourceStyle = group.style or {}
    local style = {}
    local copiedDurationFormat = false
    local function CopyStyleKey(key)
        local value = sourceStyle[key]
        if value == nil then
            value = baseline[key]
        end
        style[key] = ST._CopyPresetValue(value)
        if key == "durationFormat" then
            copiedDurationFormat = true
        end
    end

    local template = {
        displayMode = mode,
        buttons = {},
        style = style,
    }

    local modeScopes = ST.PANEL_COPY_SCOPES[mode] or {}
    local isAuraPanel = ST.IsAuraPanelGroup(group)
    for _, scopeName in ipairs(self:GetPanelCopyScopeList(mode)) do
        local scopeData = modeScopes[scopeName]
        -- The applier's own key walk, one scope at a time as it runs it.
        ST._ForEachPanelCopyStyleKey(mode, { scopeName }, CopyStyleKey)
        if scopeData.copiesMasque then
            template.masqueEnabled = group.masqueEnabled and true or false
        end
        -- An Aura Panel's compact trio is not a look (its compactLayout is
        -- invariant-forced false and its compactGrowthDirection is the
        -- Layout-owned Collapse Direction), so the template carries none and
        -- an apply leaves the target's alone.
        if scopeData.copiesCompact and not isAuraPanel then
            template.compactLayout = group.compactLayout == true
            template.compactGrowthDirection = group.compactGrowthDirection or "center"
            template.maxVisibleButtons = tonumber(group.maxVisibleButtons) or 0
        end
    end
    for _, key in ipairs(ST.PANEL_TEMPLATE_SHAPE_KEYS[mode] or {}) do
        CopyStyleKey(key)
    end

    -- Stored as the EFFECTIVE format: a legacy panel can still carry only
    -- decimalTimers=true with no durationFormat, and the template must not
    -- hand a target that panel's "clock" baseline while the panel itself
    -- renders decimals (the applier's rule). decimalTimers is in no key list,
    -- so the fresh style never carries it.
    if copiedDurationFormat and self.GetDurationFormat then
        style.durationFormat = self.GetDurationFormat(sourceStyle)
    end

    -- The one placement fact: the offset from the panel's own Group frame.
    -- Any other anchor target (another panel, a frame, the cursor) is outside
    -- the line, so it collapses to the Group's center.
    local anchor = group.anchor
    local containerFrameName = group.parentContainerId
        and (CONTAINER_FRAME_PREFIX .. group.parentContainerId)
    if type(anchor) == "table" and containerFrameName and anchor.relativeTo == containerFrameName then
        template.anchor = {
            point = anchor.point or "CENTER",
            relativePoint = anchor.relativePoint or "CENTER",
            x = tonumber(anchor.x) or 0,
            y = tonumber(anchor.y) or 0,
        }
    else
        template.anchor = DefaultTemplateAnchor()
    end

    return template
end

------------------------------------------------------------------------
-- Store
------------------------------------------------------------------------

-- db.global.panelTemplates, self-healing: `groups` is always a table and
-- `nextGroupId` always a number above every stored id.
function CooldownCompanion:GetPanelTemplateStore()
    local global = self.db and self.db.global
    if not global then return nil end
    local store = global.panelTemplates
    if type(store) ~= "table" then
        store = {}
        global.panelTemplates = store
    end
    if type(store.groups) ~= "table" then
        store.groups = {}
    end
    -- Recomputed when missing, non-numeric, or stale (at or below a stored
    -- id): a counter that lags the store would hand a new save an id already
    -- in use and silently overwrite that template.
    local maxId = 0
    for id in pairs(store.groups) do
        id = tonumber(id) or 0
        if id > maxId then
            maxId = id
        end
    end
    if type(store.nextGroupId) ~= "number" or store.nextGroupId <= maxId then
        store.nextGroupId = maxId + 1
    end
    return store
end

function CooldownCompanion:GetPanelTemplate(templateId)
    local store = self:GetPanelTemplateStore()
    templateId = tonumber(templateId)
    local template = store and templateId and store.groups[templateId] or nil
    return type(template) == "table" and template or nil
end

-- Sorted array of { id = , template = }: by name (case-insensitive), then
-- id. `mode` nil lists every template, else only that base copy mode
-- ("icons" / "bars" / "text", the answer GetPanelCopyMode gives).
function CooldownCompanion:GetPanelTemplates(mode)
    local list = {}
    local store = self:GetPanelTemplateStore()
    if not store then return list end
    for id, template in pairs(store.groups) do
        -- A non-numeric key is no template id the API can address (every
        -- entry point tonumber()s its id), so it is not listed.
        if type(id) == "number"
            and type(template) == "table"
            and (mode == nil or template.displayMode == mode) then
            list[#list + 1] = { id = id, template = template }
        end
    end
    table_sort(list, function(a, b)
        local nameA = string_lower(tostring(a.template.name or ""))
        local nameB = string_lower(tostring(b.template.name or ""))
        if nameA ~= nameB then
            return nameA < nameB
        end
        return (tonumber(a.id) or 0) < (tonumber(b.id) or 0)
    end)
    return list
end

------------------------------------------------------------------------
-- Save / update / rename / delete
------------------------------------------------------------------------

-- Same eligibility as Copy Panel Settings' source side: the specialist
-- modes (textures, trigger, rotation assistant) have no template.
function CooldownCompanion:CanSavePanelTemplate(groupId)
    return self:GetPanelCopyMode(GetProfileGroup(self, groupId)) ~= nil
end

-- Returns the new template id, or nil when the panel cannot be a template.
function CooldownCompanion:SavePanelTemplate(groupId, name)
    local group = GetProfileGroup(self, groupId)
    local mode = self:GetPanelCopyMode(group)
    local store = mode and self:GetPanelTemplateStore()
    if not store then return nil end

    local templateId = store.nextGroupId
    store.nextGroupId = templateId + 1

    local template = BuildPanelTemplateSnapshot(self, group, mode)
    template.name = UniqueTemplateName(store, NormalizeTemplateName(name, templateId), templateId)
    store.groups[templateId] = template
    return templateId
end

-- Re-snapshots an existing template from a panel, keeping its id and name.
-- A template never changes mode: the panel must share the template's.
function CooldownCompanion:UpdatePanelTemplate(templateId, groupId)
    templateId = tonumber(templateId)
    local existing = self:GetPanelTemplate(templateId)
    if not existing then
        return false, "missing_template"
    end
    local group = GetProfileGroup(self, groupId)
    local mode = self:GetPanelCopyMode(group)
    if not mode then
        return false, "missing_group"
    end
    if mode ~= existing.displayMode then
        return false, "mode_mismatch"
    end

    local template = BuildPanelTemplateSnapshot(self, group, mode)
    template.name = existing.name
    self:GetPanelTemplateStore().groups[templateId] = template
    return true
end

function CooldownCompanion:RenamePanelTemplate(templateId, name)
    templateId = tonumber(templateId)
    local template = self:GetPanelTemplate(templateId)
    if not template then
        return false, "missing_template"
    end
    template.name = UniqueTemplateName(
        self:GetPanelTemplateStore(), NormalizeTemplateName(name, templateId), templateId)
    return true
end

function CooldownCompanion:DeletePanelTemplate(templateId)
    templateId = tonumber(templateId)
    local store = self:GetPanelTemplateStore()
    if not (store and templateId and store.groups[templateId]) then
        return false, "missing_template"
    end
    store.groups[templateId] = nil
    return true
end

------------------------------------------------------------------------
-- Apply / create
------------------------------------------------------------------------

-- Mirrors CanCopyPanelSettings' target side: the modes must match, and the
-- target's Group must resolve to a valid class scope.
function CooldownCompanion:CanApplyPanelTemplate(templateId, groupId)
    local template = self:GetPanelTemplate(templateId)
    if not template then
        return false, "missing_template"
    end
    local group = GetProfileGroup(self, groupId)
    if not group then
        return false, "missing_group"
    end
    local mode = self:GetPanelCopyMode(group)
    if not mode or mode ~= template.displayMode then
        return false, "mode_mismatch"
    end
    if self.ResolveContainerClassScope then
        local scope = group.parentContainerId
            and self:ResolveContainerClassScope(group.parentContainerId)
        if scope and scope.isInvalid then
            return false, "invalid_class_scope"
        end
    end
    return true
end

-- opts.position (default false): also move the panel to the template's
-- Group-relative offset. Off, the panel keeps its anchor whatever it is.
function CooldownCompanion:ApplyPanelTemplate(templateId, groupId, opts)
    groupId = tonumber(groupId)
    local canApply, reason = self:CanApplyPanelTemplate(templateId, groupId)
    if not canApply then
        return false, reason
    end
    local template = self:GetPanelTemplate(templateId)
    local mode = template.displayMode
    local position = opts and opts.position == true
    return ST._ApplyPanelSettingsSource(self, groupId, template, self:GetPanelCopyScopeList(mode), {
        shapeKeys = ST.PANEL_TEMPLATE_SHAPE_KEYS[mode],
        -- A template saved from an Aura Panel carries no compact trio; the
        -- applier must then leave the target's alone rather than default it.
        skipCompact = template.compactLayout == nil,
        anchor = position and template.anchor or nil,
    })
end

-- A new panel in `containerId` wearing the template's name, look, shape and
-- Group offset. CreatePanel builds the panel's frame itself, so out of
-- combat the apply runs against a live frame. Returns the new panel id, or
-- nil with nothing left behind.
function CooldownCompanion:CreatePanelFromTemplate(containerId, templateId)
    local template = self:GetPanelTemplate(templateId)
    if not template then return nil end
    local newGroupId = self:CreatePanel(containerId, template.displayMode)
    if not newGroupId then return nil end

    self.db.profile.groups[newGroupId].name = template.name

    local applied = self:ApplyPanelTemplate(templateId, newGroupId, { position = true })
    if not applied then
        self:DeletePanel(containerId, newGroupId)
        return nil
    end
    return newGroupId
end
