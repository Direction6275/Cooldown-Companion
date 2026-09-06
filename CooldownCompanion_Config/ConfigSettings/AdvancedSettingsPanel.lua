local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState

-- One editor for the visible page. Fresh registrations own callbacks;
-- the surviving active identity holds no widgets or editable tables.
local registrations = {}
local activeEditor
local queuedOpen
local buildingPage = false
local refreshingAdvancedPanel = false
local scrollGeneration = 0
CS.advancedSettingsInfoButtons = CS.advancedSettingsInfoButtons or {}

local function BoolValue(value)
    return value == true
end

local function SortedKeyString(selection)
    if type(selection) ~= "table" then
        return ""
    end

    local keys = {}
    for key, selected in pairs(selection) do
        if selected then
            keys[#keys + 1] = tostring(key)
        end
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

local function BuildContext(extra)
    local group = CS.selectedGroup
        and CooldownCompanion.db
        and CooldownCompanion.db.profile
        and CooldownCompanion.db.profile.groups
        and CooldownCompanion.db.profile.groups[CS.selectedGroup]

    local context = {
        selectedContainer = CS.selectedContainer,
        selectedGroup = CS.selectedGroup,
        selectedGroupDisplayMode = group and (group.displayMode or "icons") or "",
        selectedGroupTriggerDisplayType = group and group.displayMode == "trigger" and CooldownCompanion.GetTriggerPanelDisplayType and CooldownCompanion:GetTriggerPanelDisplayType(group, false) or "",
        selectedButton = CS.selectedButton,
        selectedButtons = SortedKeyString(CS.selectedButtons),
        -- Which strip owns the settings surface (UnifiedTabRow.lua). Pinned
        -- even on lens-agnostic descriptors: growing a multi-select (or moving
        -- to the entry cluster's own tabs) swaps the surface WITHOUT running
        -- the styling tab's gear pass, so no sweep sees the gear go - this
        -- mismatch is what closes the panel there. Read through the strip's
        -- own accessor so this snapshot can never normalize differently from
        -- the strip's readers.
        unifiedRowScope = ST._UnifiedRowGetScope(),
        selectedPanels = SortedKeyString(CS.selectedPanels),
        selectedGroups = SortedKeyString(CS.selectedGroups),
        selectedCustomBars = SortedKeyString(CS.selectedCustomBars),
        currentSpecId = CooldownCompanion._currentSpecId,
        currentHeroSpecId = CooldownCompanion._currentHeroSpecId,
        selectedTab = CS.selectedTab,
        buttonSettingsTab = CS.buttonSettingsTab,
        panelSettingsTab = CS.panelSettingsTab,
        barsEntrySelected = BoolValue(CS.barsEntrySelected),
        castFramesSelectedItem = CS.castFramesSelectedItem,
        unifiedBarKind = CS.unifiedBarKind,
        resourcesSettingsTab = CS.resourcesSettingsTab,
        castBarHomeTab = CS.castBarHomeTab,
        selectedCustomBarId = CS.selectedCustomBarId,
        selectedResourcePowerType = CS.selectedResourcePowerType,
        resourceSettingsSpecID = CS.resourceSettingsSpecID,
        talentPickerMode = BoolValue(CS.talentPickerMode),
    }

    if type(extra) == "table" then
        for key, value in pairs(extra) do
            context[key] = value
        end
    end

    return context
end

-- The context fields a lens-agnostic descriptor deliberately does NOT pin.
-- The styling tabs are a LENS over one panel, and a settings-side gear's
-- panel follows lens shifts (owner ruling 2026-08-31): open Cooldown Text
-- Advanced at panel scope, select an entry, and the same panel rebinds to
-- that entry's scope - read-only with the Customize step when inherited,
-- live when customized - instead of closing. Everything else in the context
-- (the group, the surface, the tabs) still closes it, and a gear that does
-- not rebuild closes its panel through the dispatch-level sweep below.
local LENS_CONTEXT_FIELDS = { selectedButton = true, selectedButtons = true }

local function ContextMatches(left, right, ignoredFields)
    if type(left) ~= "table" or type(right) ~= "table" then
        return false
    end

    for key, value in pairs(left) do
        if not (ignoredFields and ignoredFields[key]) and right[key] ~= value then
            return false
        end
    end
    for key, value in pairs(right) do
        if not (ignoredFields and ignoredFields[key]) and left[key] ~= value then
            return false
        end
    end
    return true
end

-- The one compare every context check on a STORED descriptor routes through:
-- a lens-agnostic descriptor simply ignores the lens fields on both sides -
-- no copies, no stripping, contexts stay whole.
local function MatchesDescriptorContext(descriptor, context)
    return ContextMatches(descriptor.context, context,
        descriptor.lensAgnostic and LENS_CONTEXT_FIELDS or nil)
end

local function NormalizeDescriptor(opts)
    if type(opts) ~= "table" then
        return nil
    end
    if type(opts.settingKey) ~= "string" or opts.settingKey == "" then
        return nil
    end
    if type(opts.build) ~= "function" then
        return nil
    end

    local descriptor = {
        settingKey = opts.settingKey,
        title = opts.title or "Advanced Settings",
        build = opts.build,
        isAvailable = type(opts.isAvailable) == "function" and opts.isAvailable or nil,
        contextExtra = opts.context,
        context = BuildContext(opts.context),
        -- The LAZY unlock spec (lens { sec, enable } or non-lens
        -- { target, enable, refreshKind }), stored unresolved: only the
        -- panel build consumes it, through ST._ResolveAdvancedUnlock.
        unlock = type(opts.unlock) == "table" and opts.unlock or nil,
        lensAgnostic = opts.lensAgnostic == true,
    }
    return descriptor
end

local function CurrentContextMatches(descriptor)
    if not descriptor then
        return false
    end
    if descriptor.isAvailable and not descriptor.isAvailable() then
        return false
    end
    return MatchesDescriptorContext(descriptor, BuildContext(descriptor.contextExtra))
end

local function MatchesActive(descriptor)
    return activeEditor and descriptor
        and activeEditor.settingKey == descriptor.settingKey
        and MatchesDescriptorContext(activeEditor, descriptor.context)
end

local function RefreshGearTint()
    local registration = activeEditor and registrations[activeEditor.settingKey]
    if CS.SetActiveAdvancedSettingsToggleButton then
        CS.SetActiveAdvancedSettingsToggleButton(registration and registration.button or nil)
    end
    if ST._RefreshPreviewCommandCenterGear then ST._RefreshPreviewCommandCenterGear() end
end

local function ClearInfoButtons(buttons)
    for _, button in ipairs(buttons) do
        button:ClearAllPoints()
        button:Hide()
        button:SetParent(nil)
        button:SetScript("OnEnter", nil)
        button:SetScript("OnLeave", nil)
    end
    wipe(buttons)
end

local function Relayout(row)
    local scroll = ST._FindOwningSettingsScroll(row)
    if scroll and not AceGUI:IsReleasing(scroll) then scroll:DoLayout() end
end

local function ReleaseEditorView()
    local view = activeEditor and activeEditor.view
    if not view then return end
    activeEditor.view = nil
    -- Parent release owns its children; never remove a sibling mid-traversal.
    if AceGUI:IsReleasing(view.widget) then return end
    local parent = view.widget.parent
    if parent then
        for index, child in ipairs(parent.children) do
            if child == view.widget then
                table.remove(parent.children, index)
                break
            end
        end
    end
    AceGUI:Release(view.widget)
    if parent and not AceGUI:IsReleasing(parent) then Relayout(parent) end
end

local function ClearActiveEditor()
    scrollGeneration = scrollGeneration + 1
    ReleaseEditorView()
    activeEditor = nil
    RefreshGearTint()
end

local function CloseAdvancedSettingsPanel(opts)
    local key = type(opts) == "table" and opts.settingKey or nil
    if not key or (queuedOpen and queuedOpen.settingKey == key) then queuedOpen = nil end
    if not activeEditor or (key and activeEditor.settingKey ~= key) then return false end
    ClearActiveEditor()
    return true
end

local function CloseCompetingEditors()
    if CS.CancelPickAuraTexture then CS.CancelPickAuraTexture() end
    if CS.CloseProfileWideFontWindow then CS.CloseProfileWideFontWindow() end
    if CS.CloseProfileWideBarTextureWindow then CS.CloseProfileWideBarTextureWindow() end
    if CS.CloseSpellbookPanel then CS.CloseSpellbookPanel() end
end

local function CaptureRowPosition(row)
    local scroll = ST._FindOwningSettingsScroll(row)
    if not (scroll and scroll.content) then return end
    local contentTop, rowTop = scroll.content:GetTop(), row.frame:GetTop()
    if not (contentTop and rowTop) then return end
    local status = scroll.status or scroll.localstatus
    return contentTop - rowTop - ((status and status.offset) or 0)
end

local function ScheduleEditorReveal(registration, view, rowPosition)
    scrollGeneration = scrollGeneration + 1
    local generation = scrollGeneration
    C_Timer.After(0, function()
        if generation ~= scrollGeneration or buildingPage
            or registrations[registration.descriptor.settingKey] ~= registration
            or not (activeEditor and activeEditor.view == view)
            or not CurrentContextMatches(registration.descriptor)
            or CS.pendingSettingHighlight or CS.pendingLensAnchor then return end
        local row = registration.row
        local scroll = ST._FindOwningSettingsScroll(row)
        if not (scroll and row.frame:IsVisible() and view.widget.frame:IsVisible()) then return end
        local contentTop, rowTop = scroll.content:GetTop(), row.frame:GetTop()
        local editorTop = view.widget.frame:GetTop()
        local height = scroll.scrollframe:GetHeight()
        if not (contentTop and rowTop and editorTop and height and height > 0) then return end
        local maxOffset = math.max(0, scroll.content:GetHeight() - height)
        local status = scroll.status or scroll.localstatus
        local rowOffset = contentTop - rowTop
        local desired = rowPosition and rowOffset - rowPosition or ((status and status.offset) or 0)
        -- Fit the entire editor with the least movement possible. If it is
        -- taller than the viewport, keep the owner at the top and devote the
        -- remaining height to its controls.
        local bottom = contentTop - editorTop + view.widget.frame:GetHeight()
        desired = math.max(desired, bottom - height)
        desired = math.min(desired, rowOffset)
        desired = math.max(0, math.min(maxOffset, desired))
        local value = maxOffset > 0 and desired / maxOffset * 1000 or 0
        scroll:SetScroll(value)
        if scroll.scrollBarShown and scroll.scrollbar then scroll.scrollbar:SetValue(value) end
    end)
end

-- Label hierarchy belongs to the editor, independent of indentation. Walk
-- nested groups too; disabled/caption rows keep their own color precedence.
local function StyleEditorLabels(container)
    for _, child in ipairs(container.children or {}) do
        if child.SetAdvancedSetting then child:SetAdvancedSetting(true) end
        if child.children then StyleEditorLabels(child) end
    end
end

local function BuildEditorContents(view, registration)
    local descriptor = registration.descriptor
    local editor = view.widget
    CS.advancedSettingsInfoButtons = view.infoButtons
    descriptor._resolvedUnlock = descriptor.unlock
        and ST._ResolveAdvancedUnlock(descriptor.unlock) or nil
    if descriptor._resolvedUnlock then
        ST._BuildAdvancedUnlockStrip(editor, descriptor._resolvedUnlock)
    end
    local body = ST._BeginFullWidthRowGroup(editor)
    body._isAdvancedSettingsPanel = true
    body:SetCallback("OnRelease", function(widget) widget._isAdvancedSettingsPanel = nil end)
    body:PauseLayout()
    descriptor.build(body, descriptor)
    StyleEditorLabels(body)
    if descriptor._resolvedUnlock then ST._MakeAdvancedPanelReadOnly(body) end
    body:ResumeLayout()
    body:DoLayout()
end

local function BuildActiveEditor()
    if buildingPage or refreshingAdvancedPanel or not activeEditor then return end
    local registration = registrations[activeEditor.settingKey]
    if not (registration and MatchesActive(registration.descriptor)
        and CurrentContextMatches(registration.descriptor)
        and registration.row.parent and not AceGUI:IsReleasing(registration.row)) then
        ClearActiveEditor()
        return
    end
    ReleaseEditorView()
    local row = registration.row
    local parent = row.parent
    local found, before
    for index, child in ipairs(parent.children) do
        if child == row then
            found, before = true, parent.children[index + 1]
            break
        end
    end
    if not found then ClearActiveEditor(); return end

    local editor = ST._CreateInlineSettingsGroup(row)
    local view = { widget = editor, infoButtons = {} }
    activeEditor.view = view
    editor:SetCallback("OnRelease", function()
        ClearInfoButtons(view.infoButtons)
        if activeEditor and activeEditor.view == view then activeEditor.view = nil end
        scrollGeneration = scrollGeneration + 1
    end)
    editor:PauseLayout()
    parent:AddChild(editor, before)
    refreshingAdvancedPanel = true
    CS.advancedSettingsPanelRefreshing = true
    -- Error boundary only: never strand suppression flags or partial controls.
    local ok = xpcall(function() BuildEditorContents(view, registration) end, CallErrorHandler)
    registration.descriptor._resolvedUnlock = nil
    CS.advancedSettingsInfoButtons = {}
    CS.advancedSettingsPanelRefreshing = false
    refreshingAdvancedPanel = false
    editor:ResumeLayout()
    if not ok then ClearActiveEditor(); return end
    editor:DoLayout()
    Relayout(row)
    RefreshGearTint()
    return view
end

local function OpenAdvancedSettingsPanel(opts)
    local descriptor = NormalizeDescriptor(opts)
    local registration = descriptor and registrations[descriptor.settingKey]
    if not (registration and CurrentContextMatches(registration.descriptor)
        and MatchesDescriptorContext(registration.descriptor, descriptor.context)) then return false end
    if MatchesActive(descriptor) then
        CloseAdvancedSettingsPanel({ settingKey = descriptor.settingKey })
        return false
    end
    local position = CaptureRowPosition(registration.row)
    CloseCompetingEditors()
    ClearActiveEditor()
    -- Surviving identity carries no edit callbacks or owner widgets.
    activeEditor = {
        settingKey = descriptor.settingKey,
        context = descriptor.context,
        lensAgnostic = descriptor.lensAgnostic,
    }
    local view
    if not buildingPage and not CS.configRefreshInProgress then view = BuildActiveEditor() end
    if view and not CS.pendingSettingHighlight then
        CS.pendingLensAnchor = nil
        ScheduleEditorReveal(registration, view, position)
    end
    RefreshGearTint()
    return activeEditor ~= nil
end

local function QueueAdvancedSettingsPanelOpen(settingKey, extraContext)
    if type(settingKey) ~= "string" or settingKey == "" then return end
    queuedOpen = { settingKey = settingKey, context = BuildContext(extraContext) }
end

local function ConsumeQueuedAdvancedSettingsPanelOpen(opts)
    if not queuedOpen then return false end
    if not ContextMatches(queuedOpen.context, BuildContext()) then
        queuedOpen = nil
        return false
    end
    local descriptor = NormalizeDescriptor(opts)
    if not descriptor or queuedOpen.settingKey ~= descriptor.settingKey
        or not MatchesDescriptorContext(descriptor, queuedOpen.context) then return false end
    queuedOpen = nil
    if MatchesActive(descriptor) then return true end
    return OpenAdvancedSettingsPanel(opts)
end

local function RegisterAdvancedSettingsRow(opts, row, button)
    local descriptor = NormalizeDescriptor(opts)
    if not (descriptor and row and row.parent) then return false end
    registrations[descriptor.settingKey] = { descriptor = descriptor, row = row, button = button }
    ConsumeQueuedAdvancedSettingsPanelOpen(opts)
    return MatchesActive(descriptor) and true or false
end

local function ReleaseAdvancedSettingsRow(settingKey, row)
    local registration = registrations[settingKey]
    if registration and registration.row == row then
        registrations[settingKey] = nil
        scrollGeneration = scrollGeneration + 1
    end
end

local function RebindAdvancedSettingsPanel(opts)
    local registration = opts and registrations[opts.settingKey]
    if not registration then return false end
    return RegisterAdvancedSettingsRow(opts, registration.row, registration.button)
end

local function RefreshAdvancedSettingsPanel()
    if not CS.configRefreshInProgress then BuildActiveEditor() end
end

local function RunAdvancedGearBuildPass(fn, ...)
    scrollGeneration = scrollGeneration + 1
    ReleaseEditorView()
    wipe(registrations)
    buildingPage = true
    -- End the registration pass even when an individual page builder fails.
    local args, count = {...}, select("#", ...)
    local ok = xpcall(function() fn(unpack(args, 1, count)) end, CallErrorHandler)
    buildingPage = false
    queuedOpen = nil
    if not ok then
        wipe(registrations)
        ClearActiveEditor()
        return
    end
    if activeEditor then
        local registration = registrations[activeEditor.settingKey]
        if not (registration and MatchesActive(registration.descriptor)
            and CurrentContextMatches(registration.descriptor)) then
            ClearActiveEditor()
        elseif not CS.configRefreshInProgress then
            BuildActiveEditor()
        end
    end
end

local function IsAdvancedSettingsPanelOpen(settingKey, extraContext)
    if not activeEditor or (settingKey and activeEditor.settingKey ~= settingKey) then return false end
    return MatchesDescriptorContext(activeEditor, BuildContext(extraContext))
end

local function IsAdvancedSettingsEditorShown()
    local view = activeEditor and activeEditor.view
    return view ~= nil and view.widget.frame:IsVisible()
end

CS.OpenAdvancedSettingsPanel = OpenAdvancedSettingsPanel
CS.CloseAdvancedSettingsPanel = CloseAdvancedSettingsPanel
CS.RegisterAdvancedSettingsRow = RegisterAdvancedSettingsRow
CS.ReleaseAdvancedSettingsRow = ReleaseAdvancedSettingsRow
CS.RunAdvancedGearBuildPass = RunAdvancedGearBuildPass
CS.RefreshAdvancedSettingsPanel = RefreshAdvancedSettingsPanel
CS.RebindAdvancedSettingsPanel = RebindAdvancedSettingsPanel
CS.QueueAdvancedSettingsPanelOpen = QueueAdvancedSettingsPanelOpen
CS.ConsumeQueuedAdvancedSettingsPanelOpen = ConsumeQueuedAdvancedSettingsPanelOpen
CS.IsAdvancedSettingsPanelOpen = IsAdvancedSettingsPanelOpen
CS.IsAdvancedSettingsEditorShown = IsAdvancedSettingsEditorShown
