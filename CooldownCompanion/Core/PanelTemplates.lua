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

    Version 3 snapshots carry every supported panel setting, including Alpha
    inheritance, strata and panel Text Format. capturedFields records presence
    even for nil-valued settings: absent values inside that coverage RESET a
    target, while fields outside it were never saved. No profile baseline is
    substituted. Entries, eligibility, identity and anchor connections stay local.

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
    durationFormat rewrite, the Aura Panel invariants, the
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

-- Also used by the create menus. Unknown versions must never fall through to
-- the old-template path, which would apply a different scope silently.
function CooldownCompanion:CanUsePanelTemplate(template)
    if type(template) ~= "table" then return false, "missing_template" end
    local version = template.templateVersion
    if version ~= nil and version ~= 1 and version ~= 2 and version ~= 3 then
        return false, "unsupported_template_version"
    end
    if not ST.PANEL_TEMPLATE_STYLE_KEYS[template.displayMode] then
        return false, "mode_mismatch"
    end
    if version == 3 then
        local fields = template.capturedFields
        if type(template.style) ~= "table" or type(fields) ~= "table"
            or type(fields.style) ~= "table" or type(fields.group) ~= "table"
            or type(fields.loadConditions) ~= "table" or type(fields.section) ~= "table" then
            return false, "invalid_template"
        end
    end
    return true
end

-- A fresh coverage map is saved with each snapshot. Intersecting it with the
-- current contract on apply keeps unknown fields out without inventing values
-- for controls added after this particular snapshot was made.
local function GetPanelTemplateFields(group, mode)
    local fields = { style = {}, group = {}, loadConditions = {}, section = {} }
    for sectionId, section in pairs(ST.OVERRIDE_SECTIONS) do
        if section.modes and (section.modes[mode]
            or (mode == "bars" and ST.IsTotemPanelGroup(group) and sectionId == "auraIndicator")) then
            for _, key in ipairs(section.keys) do fields.style[key] = true end
        end
    end
    for _, key in ipairs(ST.PANEL_TEMPLATE_STYLE_KEYS[mode]) do fields.style[key] = true end
    if mode == "bars" and ST.IsAuraPanelGroup(group) then
        fields.style.barOrientation = nil
        fields.style.buttonsPerRow = nil
    end
    for _, key in ipairs(ST.PANEL_TEMPLATE_GROUP_KEYS) do fields.group[key] = true end
    if mode == "icons" then fields.group.masqueEnabled = true end
    for _, option in ipairs(ST.LOAD_CONDITION_OPTIONS) do fields.loadConditions[option.key] = true end
    if ST.PanelSupportsSections(group) then
        for _, key in ipairs(ST.PANEL_TEMPLATE_SECTION_KEYS) do fields.section[key] = true end
    end
    return fields
end
ST._GetPanelTemplateFields = GetPanelTemplateFields

local function FlushTemplateEditor()
    -- The config module publishes its existing commit owner only when loaded.
    -- Flush without releasing the editor: a rejected apply keeps it usable.
    if ST._FlushTextFormatTabCommit then ST._FlushTextFormatTabCommit() end
end

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
    if ST.IsTotemPanelGroup(template) then
        return template.displayMode == "bars" and "totemBars" or "totemIcons"
    end
    if ST.IsAuraPanelGroup(template) then
        if template.displayMode == "icons" then return "auraIcons" end
        if template.displayMode == "bars" then return "auraBars" end
    end
    return template and template.displayMode
end

local function TemplateSubtypeMatches(template, group)
    -- Old templates have no reliable subtype evidence. Preserve their original
    -- compatibility until the owner updates them from an actual panel.
    return (template.templateVersion == nil or template.templateVersion == 1)
        or (ST.IsAuraPanelGroup(template) == ST.IsAuraPanelGroup(group)
            and ST.IsTotemPanelGroup(template) == ST.IsTotemPanelGroup(group))
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
    local sourceStyle = group.style or {}
    local style = {}
    local fields = GetPanelTemplateFields(group, mode)

    local template = {
        templateVersion = 3,
        capturedFields = fields,
        auraPanel = ST.IsAuraPanelGroup(group),
        totemPanel = ST.IsTotemPanelGroup(group),
        displayMode = mode,
        buttons = {},
        style = style,
    }

    for key in pairs(fields.style) do style[key] = ST._CopyPresetValue(sourceStyle[key]) end
    -- Reuse the hide-rule reader's missing-table versus empty-table semantics.
    ST._CopyPanelVisibility(self, group, template, ST.PANEL_COPY_SCOPES[mode].visibility)
    for key in pairs(fields.group) do template[key] = ST._CopyPresetValue(group[key]) end
    template.inheritPanelAlpha = group.inheritPanelAlpha ~= false

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
    if fields.style.durationFormat and self.GetDurationFormat then
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
    FlushTemplateEditor()
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
function CooldownCompanion:CanUpdatePanelTemplate(templateId, groupId)
    local existing = self:GetPanelTemplate(templateId)
    local usable, reason = self:CanUsePanelTemplate(existing)
    -- A supported but incomplete snapshot can be repaired by updating it from
    -- a real panel; only applying/creating requires captured-field metadata.
    if not usable and reason ~= "invalid_template" then return false, reason end
    local group = GetProfileGroup(self, groupId)
    local mode = self:GetPanelCopyMode(group)
    if not mode then
        return false, "missing_group"
    end
    if mode ~= existing.displayMode or not TemplateSubtypeMatches(existing, group) then
        return false, "mode_mismatch"
    end
    return true
end

function CooldownCompanion:UpdatePanelTemplate(templateId, groupId)
    local canUpdate, reason = self:CanUpdatePanelTemplate(templateId, groupId)
    if not canUpdate then return false, reason end
    FlushTemplateEditor()
    templateId = tonumber(templateId)
    local existing = self:GetPanelTemplate(templateId)
    local group = GetProfileGroup(self, groupId)
    local mode = self:GetPanelCopyMode(group)
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
    local usable, reason = self:CanUsePanelTemplate(template)
    if not usable then return false, reason end
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
    -- Check the proposed sections on a detached view before ANY settings are
    -- written. Adding an empty section must also account for existing members
    -- naming that anchor. The ordinary setter remains the only mutation owner.
    local capturesAuraOnly = template.templateVersion ~= 3
        or template.capturedFields.section.auraOnly == true
    if capturesAuraOnly and type(template.sections) == "table" and ST.PanelSupportsSections(group) then
        local proposed = {}
        for key, value in pairs(group) do proposed[key] = value end
        proposed.sections = ST._CopyPresetValue(group.sections or {})
        for _, anchor in ipairs(ST.PANEL_SECTION_ANCHORS) do
            local section = template.sections[anchor]
            if type(section) == "table" and section.auraOnly == true then
                proposed.sections[anchor] = proposed.sections[anchor] or {}
                local blocker = ST.GetAuraSectionToggleBlocker(proposed, anchor)
                if blocker then
                    return false, "section_conflict", { section = anchor, reason = blocker }
                end
            end
        end
    end
    return true
end

-- opts.position (default false, used by creation): also apply saved placement.
-- Current snapshots preserve the target; old snapshots retain Group placement.
function CooldownCompanion:ApplyPanelTemplate(templateId, groupId, opts)
    groupId = tonumber(groupId)
    FlushTemplateEditor()
    local canApply, reason, details = self:CanApplyPanelTemplate(templateId, groupId)
    if not canApply then
        return false, reason, details
    end
    local template = self:GetPanelTemplate(templateId)
    local mode = template.displayMode
    local position = opts and opts.position == true
    local completeSnapshot = template.templateVersion == 3
    local currentSnapshot = completeSnapshot or template.templateVersion == 2
    local scopes = completeSnapshot and {} or GetPanelTemplateScopeList(self, mode, template)
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
    local fields
    if completeSnapshot then
        fields = GetPanelTemplateFields(template, mode)
        for scope, keys in pairs(fields) do
            for key in pairs(keys) do
                if template.capturedFields[scope][key] ~= true then keys[key] = nil end
            end
        end
        shapeKeys = nil
    end
    return ST._ApplyPanelSettingsSource(self, groupId, template, scopes, {
        templateFields = fields,
        preserveCompactLimit = true,
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
    local usable, reason = self:CanUsePanelTemplate(template)
    if not usable then return nil, reason end
    local newGroupId = self:CreatePanel(containerId, self:GetPanelTemplateCreationMode(template))
    if not newGroupId then return nil end

    local group = self.db.profile.groups[newGroupId]
    group.name = template.name
    if (template.templateVersion == 2 or template.templateVersion == 3) and template.positionMode == "cursor" then
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
