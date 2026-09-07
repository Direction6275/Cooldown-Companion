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

    New snapshots (templateVersion 2) carry Appearance, Indicators, Visibility,
    Arrangement, Aura subtype, section settings without members, bar fill
    direction, and relative placement. They exclude eligibility, Alpha
    inheritance, entries, strata and specific panel/frame anchor targets.

    Apply remains one click and preserves the destination's position and
    anchor target. Create remains one click: ordinary placement uses the new
    Group, while cursor templates create a cursor-anchored panel. No picker
    or scope selection is added.

    Unversioned templates retain their original look/shape/compact contract
    and Group-relative create offset. They never apply newly captured fields
    such as Visibility or Aura Collapse Direction. Updating from a panel
    replaces the snapshot with the current version.

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

-- Legacy snapshots cannot apply settings they never captured.
local function GetPanelTemplateScopeList(self, mode, template)
    local scopes = {}
    if template and template.templateVersion == 2 then
        for _, scope in ipairs(self:GetPanelCopyScopeList(mode)) do
            if scope ~= "position" then scopes[#scopes + 1] = scope end
        end
    else
        local modeScopes = ST.PANEL_COPY_SCOPES[mode] or {}
        if modeScopes.appearance then scopes[#scopes + 1] = "appearance" end
        if modeScopes.indicators then scopes[#scopes + 1] = "indicators" end
    end
    return scopes
end

local TEMPLATE_BAR_FILL_KEYS = { "barFillVertical", "barReverseFill" }

function CooldownCompanion:GetPanelTemplateCreationMode(template)
    if ST.IsAuraPanelGroup(template) then
        if template.displayMode == "icons" then return "auraIcons" end
        if template.displayMode == "bars" then return "auraBars" end
    end
    return template and template.displayMode
end

local function TemplateSubtypeMatches(template, group)
    -- Old templates have no reliable subtype evidence. Preserve their original
    -- compatibility until the owner updates them from an actual panel.
    return template.templateVersion ~= 2
        or ST.IsAuraPanelGroup(template) == ST.IsAuraPanelGroup(group)
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

-- Save and update capture one complete settings snapshot; the caller stamps
-- the name. Versioning distinguishes absent legacy scopes from saved defaults.
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
        templateVersion = 2,
        auraPanel = ST.IsAuraPanelGroup(group),
        displayMode = mode,
        buttons = {},
        style = style,
    }

    local modeScopes = ST.PANEL_COPY_SCOPES[mode] or {}
    for _, scopeName in ipairs(GetPanelTemplateScopeList(self, mode, template)) do
        local scopeData = modeScopes[scopeName]
        -- The applier's own key walk, one scope at a time as it runs it.
        ST._ForEachPanelCopyStyleKey(mode, { scopeName }, CopyStyleKey)
        if scopeData.copiesMasque then
            template.masqueEnabled = group.masqueEnabled and true or false
        end
        if scopeName == "visibility" then
            ST._CopyPanelVisibility(self, group, template, scopeData)
        elseif scopeName == "arrangement" then
            ST._CopyPanelArrangement(group, template, mode, scopeData)
        end
    end
    -- These existing template extras remain part of the complete setup.
    if mode == "bars" then
        for _, key in ipairs(TEMPLATE_BAR_FILL_KEYS) do CopyStyleKey(key) end
    end

    -- Sections: settings only, never membership. Only a panel the section
    -- model covers (icons, not an Aura Panel) can have any, and a section
    -- whose table is gone is no section (its entries are base members), so
    -- the walk is over the tables that exist.
    if ST.PanelSupportsSections(group) and type(group.sections) == "table" then
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            local section = group.sections[anchor]
            if type(section) == "table" then
                local copy = {}
                for _, key in ipairs(ST.PANEL_TEMPLATE_SECTION_KEYS) do
                    copy[key] = ST._CopyPresetValue(section[key])
                end
                template.sections = template.sections or {}
                template.sections[anchor] = copy
            end
        end
    end

    -- Stored as the EFFECTIVE format: a legacy panel can still carry only
    -- decimalTimers=true with no durationFormat, and the template must not
    -- hand a target that panel's "clock" baseline while the panel itself
    -- renders decimals (the applier's rule). decimalTimers is in no key list,
    -- so the fresh style never carries it.
    if copiedDurationFormat and self.GetDurationFormat then
        style.durationFormat = self.GetDurationFormat(sourceStyle)
    end

    -- Save offsets without retaining another panel/frame's identity. A new
    -- non-cursor panel uses its own Group; apply leaves its target untouched.
    template.positionMode = self:IsCursorAnchor(group.anchor) and "cursor" or "group"
    ST._CopyPanelPosition(self, group, template)

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
    if mode ~= existing.displayMode or not TemplateSubtypeMatches(existing, group) then
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
    if not mode or mode ~= template.displayMode or not TemplateSubtypeMatches(template, group) then
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

-- opts.position (default false, used by creation): also apply saved placement.
-- Current snapshots preserve the target; old snapshots retain Group placement.
function CooldownCompanion:ApplyPanelTemplate(templateId, groupId, opts)
    groupId = tonumber(groupId)
    local canApply, reason = self:CanApplyPanelTemplate(templateId, groupId)
    if not canApply then
        return false, reason
    end
    local template = self:GetPanelTemplate(templateId)
    local mode = template.displayMode
    local position = opts and opts.position == true
    local currentSnapshot = template.templateVersion == 2
    local scopes = GetPanelTemplateScopeList(self, mode, template)
    if currentSnapshot and position then
        local group = self.db.profile.groups[groupId]
        if (template.positionMode == "cursor") ~= self:IsCursorAnchor(group.anchor) then
            return false, "anchor_mode_mismatch"
        end
        scopes[#scopes + 1] = "position"
    end
    local shapeKeys = ST.PANEL_TEMPLATE_SHAPE_KEYS[mode]
    if currentSnapshot then
        shapeKeys = mode == "bars" and TEMPLATE_BAR_FILL_KEYS or nil
    end
    return ST._ApplyPanelSettingsSource(self, groupId, template, scopes, {
        shapeKeys = shapeKeys,
        copyCompact = not currentSnapshot,
        skipCompact = template.compactLayout == nil,
        sections = template.sections,
        anchor = not currentSnapshot and position and template.anchor or nil,
    })
end

-- A new panel in `containerId` with the template's type, settings and placement.
-- CreatePanel builds the panel's frame itself, so out of
-- combat the apply runs against a live frame. Returns the new panel id, or
-- nil with nothing left behind.
function CooldownCompanion:CreatePanelFromTemplate(containerId, templateId)
    local template = self:GetPanelTemplate(templateId)
    if not template then return nil end
    local newGroupId = self:CreatePanel(containerId, self:GetPanelTemplateCreationMode(template))
    if not newGroupId then return nil end

    local group = self.db.profile.groups[newGroupId]
    group.name = template.name
    if template.templateVersion == 2 and template.positionMode == "cursor" then
        -- This is a fresh, empty panel with no anchor dependents. Set its
        -- saved target before apply; the common applier owns combat deferral.
        group.anchor = self:GetDefaultCursorPanelAnchor()
    end

    local applied = self:ApplyPanelTemplate(templateId, newGroupId, { position = true })
    if not applied then
        self:DeletePanel(containerId, newGroupId)
        return nil
    end
    return newGroupId
end
