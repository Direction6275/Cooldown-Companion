-- Ordinary panels expose the style bundles used by their configured contents.
-- Context belongs to the section, never a remembered Icons/Bars editing mode.
local _, ST = ...
local Addon, CS = ST.Addon, ST._configState
local AceGUI = LibStub("AceGUI-3.0")
local BAR_LAYOUT_FIELDS = { compactLayout = true, compactGrowthDirection = true, maxVisibleButtons = true }

local panelEditorStates = setmetatable({}, { __mode = "k" })
function ST._GetPanelSettingsState(owner)
    local state = panelEditorStates[owner]
    if not state then
        state = { folds = {}, scrolls = {}, anchors = {} }
        panelEditorStates[owner] = state
    end
    return state
end

function ST._GetSettingsPreviewTarget(target)
    local meta = getmetatable(target)
    return meta and meta._settingsPreviewTarget
end

local function Selection(group)
    local context = group._settingsContext
    if context then return context.entry, context.mode, context.buttonIndex end
    local count = 0
    for _, selected in pairs(CS.selectedButtons or {}) do
        if selected then count = count + 1 end
    end
    if count >= 2 then return nil, "multi" end
    local entry = CS.selectedButton and group.buttons and group.buttons[CS.selectedButton]
    return entry, entry and "entry" or "panel", entry and CS.selectedButton or nil
end
ST._GetPanelSettingsSelection = Selection

-- Temporary cooldown/aura visibility never changes the editor's organization.
-- Modules use shared dimensions, but do not make entry appearance applicable.
function ST._GetPanelSettingsContents(owner, panelId)
    owner = owner._settingsOwner or owner._attachedBarOwner or owner
    local kind = ST.GetPanelLayoutKind(owner)
    return {
        icons = kind == "icons" or kind == "mixed",
        bars = kind == "bars" or kind == "mixed",
        modules = ST._PanelHasConfiguredModuleBars ~= nil
            and ST._PanelHasConfiguredModuleBars(panelId or CS.selectedGroup),
    }
end

function ST._GetSettingsWidgetContext(widget)
    while widget do
        if widget._cdcSettingsContext then return widget._cdcSettingsContext end
        widget = widget.parent
    end
end

function ST._SettingsContextKey(context, key)
    if not context or context.kind or context.presentation == "shared" or not key or key:match("^presentation:") then return key end
    return "presentation:" .. context.presentation .. ":" .. key
end

function ST._PreparePanelSettingsNavigation(owner, tab)
    local pending = CS.pendingSettingHighlight
    if not pending then return end
    local entry = Selection(owner)
    local presentation = pending.presentation or (entry and ST.GetEntryPresentation(owner, entry))
        or (ST.GetPanelLayoutKind(owner) == "bars" and "bars" or "icons")
    pending.presentation = presentation
    local context = { presentation = presentation }
    pending.rowKey = ST._SettingsContextKey(context, pending.rowKey)
    local keys = {}
    for key in pairs(pending.collapseKeys or {}) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        local qualified = ST._SettingsContextKey(context, key)
        CS.collapsedSections[qualified], pending.collapseKeys[qualified] = false, true
    end
    if tab == "appearance" or tab == "effects" then
        ST._GetPanelSettingsState(owner).folds[ST._SettingsContextKey(context, tab .. "_defaults")] = false
    end
end

function ST._CreatePanelSettingsContext(owner, presentation)
    local entry, mode, buttonIndex = Selection(owner)
    presentation = presentation or (entry and ST.GetEntryPresentation(owner, entry)) or "shared"
    local context = { owner = owner, presentation = presentation, entry = entry, mode = mode,
        buttonIndex = buttonIndex, panelId = CS.selectedGroup, tab = CS.selectedTab, sections = {} }
    context.contents = not entry and ST._GetPanelSettingsContents(owner, context.panelId) or nil
    function context:IsCurrent()
        local profile = Addon.db and Addon.db.profile
        if self.released or CS.barsEntrySelected or CS.unifiedBarKind or CS.selectedTab ~= self.tab or not profile
            or profile.groups[self.panelId] ~= self.owner or CS.selectedGroup ~= self.panelId then return false end
        local selected, scope = Selection(self.owner)
        if not selected and self.contents then
            local current = ST._GetPanelSettingsContents(self.owner, self.panelId)
            for _, key in ipairs({ "icons", "bars", "modules" }) do
                if current[key] ~= self.contents[key] then return false end
            end
        end
        return selected == self.entry and scope == self.mode
            and (not selected or ST.GetEntryPresentation(self.owner, selected) == self.presentation)
    end
    local bar = presentation == "bars"
    local function SavedStyle()
        if bar then return owner.attachedBarStyle end
        return owner.style
    end
    function context:ReadStyle()
        return bar and ST.GetAttachedBarStyle(owner) or owner.style or {}
    end
    -- Lazy writes keep opening an unused Bars group from changing saved data.
    -- All style controls assign keys; entry lenses read a detached snapshot.
    local writeStyle = setmetatable({}, {
        __index = function(_, key)
            local saved = SavedStyle()
            local value = saved and saved[key]
            if value ~= nil then return value end
            if bar then return ST.ATTACHED_BAR_DEFAULTS[key] end
        end,
        __newindex = function(_, key, value)
            if not context:IsCurrent() then return end
            local saved = SavedStyle()
            if not saved then
                saved = {}
                if bar then
                    owner.barOnlyLayout = owner.barOnlyLayout or { mode = ST.GetBarOnlyLayoutMode(owner) }
                    owner.attachedBarStyle = saved
                else owner.style = saved end
            end
            saved[key] = value
        end,
    })
    context.writeStyle = writeStyle
    getmetatable(writeStyle)._settingsPreviewTarget = {
        isCurrent = function() return context:IsCurrent() end,
        capture = function(keys)
            local restoreOwner = ST._CaptureRawSettingsFields(owner,
                bar and { "attachedBarStyle", "barOnlyLayout" } or { "style" })
            local restoreStyle = ST._CaptureRawSettingsFields(SavedStyle(), keys)
            return function()
                restoreStyle()
                restoreOwner()
            end
        end,
    }
    function context:EntryWrites()
        if not self.entryWrites then
            local overrides = self.entry.styleOverrides
            self.entryWrites = setmetatable({}, {
                __index = overrides,
                __newindex = function(_, key, value)
                    if self:IsCurrent() and self.entry.styleOverrides == overrides then overrides[key] = value end
                end,
            })
            getmetatable(self.entryWrites)._settingsPreviewTarget = {
                isCurrent = function()
                    return self:IsCurrent() and self.entry.styleOverrides == overrides
                end,
                capture = function(keys) return ST._CaptureRawSettingsFields(overrides, keys) end,
            }
        end
        return self.entryWrites
    end
    context.group = setmetatable({
        _settingsContext = context, _settingsOwner = owner,
        _attachedBarOwner = bar and owner or nil,
        displayMode = bar and "bars" or "icons", style = writeStyle,
        -- Fixed dimensions are editable only when bar entries form the body.
        -- All selection scopes use the same applicability as Finder.
        _fittedBarLayout = bar and ST.GetPanelLayoutKind(owner) ~= "bars" or false,
        _moduleGeometryOnly = bar and context.contents and not context.contents.bars or false,
    }, {
        __index = function(_, key)
            if bar and BAR_LAYOUT_FIELDS[key] then
                local value = owner.barOnlyLayout and owner.barOnlyLayout[key]
                if value ~= nil then return value end
                if key == "compactLayout" then return false end
                return key == "maxVisibleButtons" and 0 or "center"
            end
            return owner[key]
        end,
        __newindex = function(_, key, value)
            if not context:IsCurrent() then return end
            if bar and BAR_LAYOUT_FIELDS[key] then
                owner.barOnlyLayout = owner.barOnlyLayout or { mode = ST.GetBarOnlyLayoutMode(owner) }
                owner.barOnlyLayout[key] = value
            else owner[key] = value end
        end,
    })
    getmetatable(context.group)._settingsPreviewTarget = {
        isCurrent = function() return context:IsCurrent() end,
        capture = function(keys)
            local ownerKeys, layoutKeys = {}, {}
            for _, key in ipairs(keys) do
                local destination = bar and BAR_LAYOUT_FIELDS[key] and layoutKeys or ownerKeys
                destination[#destination + 1] = key
            end
            local layout = owner.barOnlyLayout
            local savedLayout = rawget(owner, "barOnlyLayout")
            local restoreOwner = ST._CaptureRawSettingsFields(owner, ownerKeys)
            local restoreLayout = ST._CaptureRawSettingsFields(layout, layoutKeys)
            return function()
                restoreOwner()
                restoreLayout()
                if #layoutKeys > 0 then rawset(owner, "barOnlyLayout", savedLayout) end
            end
        end,
    }
    return context
end

function ST._SettingsUsesOnlyAura(group)
    local context = group and group._settingsContext
    return ST.IsAuraPanelGroup(group) or (context and context.entry and context.entry.addedAs == "aura") or false
end

function ST._CanSettingsGroupUseOverrideSection(group, sectionId)
    if not ST.CanGroupUseOverrideSection(group, sectionId) then return false end
    local context = group and group._settingsContext
    if context and context.entry then
        return ST._CanButtonUseConfigOverrideSection(context.entry, sectionId, group)
    end
    return true
end

function ST._MarkSettingsScope(widget, scope, group, descendants)
    local context = group and group._settingsContext
    if not widget or not context or context.mode ~= "entry" then return end
    if not widget._cdcScopeCleanup then
        widget._cdcScopeCleanup = true
        local previous = widget.events and widget.events.OnRelease
        widget:SetCallback("OnRelease", function(released, event, ...)
            if previous then previous(released, event, ...) end
            released._cdcSettingsScope, released._cdcScopeCleanup = nil, nil
        end)
    end
    if not descendants or widget._cdcSettingsScope == nil then widget._cdcSettingsScope = scope end
    if descendants then
        for _, child in ipairs(widget.children or {}) do ST._MarkSettingsScope(child, scope, group, true) end
    end
end

local function RemoveWidget(container, index)
    local widget = table.remove(container.children, index)
    widget._cdcSettingsScope, widget._cdcSettingsHeading, widget._cdcSettingsCollapsed = nil, nil, nil
    AceGUI:Release(widget)
end

-- Scope is assigned by the existing lens, including nested independently
-- customizable rows. Remove only editor widgets, never override data.
function ST._FilterEntrySettingsWidgets(container)
    for i = #(container.children or {}), 1, -1 do
        local child = container.children[i]
        local scope = child._cdcSettingsScope
        if child.children then ST._FilterEntrySettingsWidgets(child) end
        if not child._cdcSettingsHeading and ((scope == "denied" or scope == "panelOnly")
            and not (child.children and #child.children > 0)
            or (child.children and #child.children == 0)) then
            RemoveWidget(container, i)
        end
    end
    local hasRows = false
    for i = #(container.children or {}), 1, -1 do
        local child = container.children[i]
        if child._cdcSettingsHeading then
            local available = child._cdcSettingsAvailable
            if available == false or (not hasRows and not child._cdcSettingsCollapsed) then
                RemoveWidget(container, i)
            end
            hasRows = false
        elseif child._cdcSettingsSubheading then
            if not hasRows then RemoveWidget(container, i) end
        else hasRows = true end
    end
end

local function NewSectionHost(container, context)
    local host = ST._BeginFullWidthRowGroup(container)
    host._cdcSettingsContext = context
    host:SetCallback("OnRelease", function(widget)
        context.released = true
        widget._cdcSettingsContext = nil
    end)
    return host
end
ST._NewPanelSettingsSectionHost = NewSectionHost

function ST._BuildCompletePanelStyleTab(container, owner, tab, builder)
    if not ST.PanelSupportsAttachedBars(owner) then return false end
    ST._PreparePanelSettingsNavigation(owner, tab)
    local entry, mode = Selection(owner)
    if entry then
        local context = ST._CreatePanelSettingsContext(owner)
        local host = NewSectionHost(container, context)
        builder(host, context.group)
        if ST._FilterEntrySettingsWidgets then ST._FilterEntrySettingsWidgets(host) end
        return true
    end
    local contents = ST._GetPanelSettingsContents(owner)
    ST._AddLensPanelScopeNote(container, { mode = mode })
    local folds = ST._GetPanelSettingsState(owner).folds
    for _, presentation in ipairs({ "icons", "bars" }) do
        if contents[presentation] or (presentation == "bars" and contents.modules and tab == "appearance") then
            local context = ST._CreatePanelSettingsContext(owner, presentation)
            local host = NewSectionHost(container, context)
            local key = ST._SettingsContextKey(context, tab .. "_defaults")
            if folds[key] == nil then folds[key] = false end
            local _, collapsed = ST._BuildCollapsibleSection(host, presentation == "icons" and "Icons" or "Bars",
                key, folds, nil, { leftAligned = true })
            if not collapsed then builder(host, context.group) end
        end
    end
    return true
end

-- Module geometry uses the same section lens as an entry, with a lazy object
-- adapter. Opening a resource that has no placement record creates no data.
function ST._CreateModuleSettingsContext(kind, powerType, spec)
    local settings = kind == "resources" and Addon:GetResourceBarSettings() or Addon:GetCastBarSettings()
    if not settings then return nil end
    spec = spec or Addon._currentSpecId
    local canonical = kind == "resources" and ST._RB.GetCanonicalPowerType(powerType) or nil
    local panel = ST.GetModuleGeometryPanel(kind, spec)
    local captured = {}
    for _, key in ipairs({ "selectedGroup", "selectedButton", "selectedResourcePowerType", "resourceSettingsSpecID",
        "barsEntrySelected", "unifiedBarKind", "barWorkspaceKind", "selectedTab", "resourcesSettingsTab", "castBarHomeTab" }) do
        captured[key] = CS[key]
    end
    local context = { kind = kind, settings = settings, owner = panel, presentation = "bars", mode = "entry",
        panelId = CS.selectedGroup, spec = spec, powerType = canonical, sections = {} }
    local profile, currentSpec = Addon.db.profile, Addon._currentSpecId
    function context:IsCurrent()
        if self.released or Addon.db.profile ~= profile or Addon._currentSpecId ~= currentSpec then return false end
        for _, key in ipairs({ "selectedGroup", "selectedButton", "selectedResourcePowerType", "resourceSettingsSpecID",
            "barsEntrySelected", "unifiedBarKind", "barWorkspaceKind", "selectedTab", "resourcesSettingsTab", "castBarHomeTab" }) do
            if CS[key] ~= captured[key] then return false end
        end
        local current = kind == "resources" and Addon:GetResourceBarSettings() or Addon:GetCastBarSettings()
        return current == settings and ST.GetModuleGeometryPanel(kind, spec) == panel
    end
    function context:GetLayout(create)
        if kind ~= "resources" then return nil end
        local layout = settings.layoutOrder and (settings.layoutOrder[spec] or settings.layoutOrder[tostring(spec)])
        if not layout and create then
            layout = ST._RB.GetSpecLayoutOrder(settings, spec)
        end
        return layout
    end
    function context:GetObject(create)
        if kind ~= "resources" then return settings end
        local layout = self:GetLayout(create)
        if not layout then return nil end
        if create then layout.resources = layout.resources or {} end
        local slot = layout.resources and layout.resources[canonical]
        if not slot and create then slot = {}; layout.resources[canonical] = slot end
        return slot
    end
    function context:ReadStyle()
        local baseline
        if kind == "resources" then
            local layout = self:GetLayout(false) or {}
            -- The default is resolved without the selected object's override.
            local geometry = ST.ResolveResourceBarGeometry(settings, layout, nil, panel)
            baseline = geometry.thickness
        else baseline = ST.ResolveBarGeometry(panel, { baseline = settings.height or 15 }).thickness end
        return { barHeight = baseline }
    end
    function context:Refresh()
        if kind == "resources" then Addon:ApplyResourceBars() else Addon:ApplyCastBarSettings() end
        if Addon.RepositionCastBar then Addon:RepositionCastBar() end
        if ST._RefreshResourcesCanvasForDrag then ST._RefreshResourcesCanvasForDrag() end
    end
    local metadata = { _geometryContext = context, _barGeometryKind = kind, displayAs = "bars",
        type = "module", name = kind == "resources" and (ST._RB.POWER_NAMES[powerType] or "Resource") or "Cast Bar" }
    context.entry = setmetatable({}, {
        __index = function(_, key)
            if metadata[key] ~= nil then return metadata[key] end
            local object = context:GetObject(false)
            return object and object[key]
        end,
        __newindex = function(_, key, value)
            if context:IsCurrent() then context:GetObject(true)[key] = value end
        end,
    })
    function context:EntryWrites()
        local object = self:GetObject(false)
        local overrides = object and object.styleOverrides
        local writes = setmetatable({}, { __index = overrides, __newindex = function(_, key, value)
            if self:IsCurrent() and self:GetObject(false) == object and object.styleOverrides == overrides then overrides[key] = value end
        end })
        getmetatable(writes)._settingsPreviewTarget = {
            isCurrent = function() return self:IsCurrent() and self:GetObject(false) == object and object.styleOverrides == overrides end,
            capture = function(keys) return ST._CaptureRawSettingsFields(overrides, keys) end,
        }
        return writes
    end
    context.group = { _settingsContext = context, _attachedBarOwner = panel or { displayMode = "icons" },
        displayMode = "bars", style = context:ReadStyle(), buttons = {} }
    return context
end

function ST._BuildModuleBarThickness(container, kind, powerType, spec, setting)
    local context = ST._CreateModuleSettingsContext(kind, powerType, spec)
    if not context then return end
    local host = ST._NewPanelSettingsSectionHost(container, context)
    local lens = ST._ResolveStyleLens(context.group)
    local sec = ST._BeginLensSection(lens, context.group, "barThickness", { column = host })
    local row = ST._AddSliderRow(host, { label = "Bar Thickness", setting = setting,
        min = 4, max = 100, step = 0.1, value = sec.tbl.barHeight or 12, disabled = sec.disabled,
        onChange = function(value)
            ST._PreviewScalarSetting(sec.tbl, "barHeight", value, ST._RefreshResourcesCanvasForDrag)
        end,
        onRelease = function(value)
            if not context:IsCurrent() then return end
            sec.tbl.barHeight = value
            context:Refresh()
        end,
    })
    sec:Chrome(row)
    sec:Finish()
    return context
end

function ST._BuildModuleGeometrySummary(container, kind, powerType, spec)
    local context = ST._CreateModuleSettingsContext(kind, powerType, spec)
    if context and context.entry.overrideSections and context.entry.overrideSections.barThickness then
        local host = ST._NewPanelSettingsSectionHost(container, context)
        ST._BuildCustomizationsSection(host, context.group, context.entry, CS.tabInfoButtons)
    end
end
