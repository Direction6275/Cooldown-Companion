-- Ordinary panels expose both style bundles. Context belongs to the section
-- being built, never to a remembered global Icons/Bars editing mode.
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

function ST._GetSettingsWidgetContext(widget)
    while widget do
        if widget._cdcSettingsContext then return widget._cdcSettingsContext end
        widget = widget.parent
    end
end

function ST._SettingsContextKey(context, key)
    if not context or context.presentation == "shared" or not key or key:match("^presentation:") then return key end
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
    function context:IsCurrent()
        local profile = Addon.db and Addon.db.profile
        if self.released or CS.barsEntrySelected or CS.unifiedBarKind or CS.selectedTab ~= self.tab or not profile
            or profile.groups[self.panelId] ~= self.owner or CS.selectedGroup ~= self.panelId then return false end
        local selected, scope = Selection(self.owner)
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
        _fittedBarLayout = bar and mode == "entry" and ST.GetPanelLayoutKind(owner) == "mixed" or false,
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
    local eligible = { icons = false, bars = false }
    for _, item in ipairs(owner.buttons or {}) do
        if ST.IsPanelLayoutEntryEligible(owner, item) then eligible[ST.GetEntryPresentation(owner, item)] = true end
    end
    if not eligible.icons and not eligible.bars then eligible.icons = true end
    ST._AddLensPanelScopeNote(container, { mode = mode })
    local folds = ST._GetPanelSettingsState(owner).folds
    for _, presentation in ipairs({ "icons", "bars" }) do
        local context = ST._CreatePanelSettingsContext(owner, presentation)
        local host = NewSectionHost(container, context)
        local key = ST._SettingsContextKey(context, tab .. "_defaults")
        if folds[key] == nil then folds[key] = not eligible[presentation] end
        local _, collapsed = ST._BuildCollapsibleSection(host, presentation == "icons" and "Icons" or "Bars",
            key, folds, nil, { leftAligned = true })
        if not collapsed then builder(host, context.group) end
    end
    return true
end
