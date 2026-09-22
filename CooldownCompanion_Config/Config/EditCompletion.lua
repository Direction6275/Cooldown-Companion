-- Synchronous completion of panel/entry and Resources/module edits. Candidate
-- previews retain their write/render/rollback lifetime. Runtime attachment
-- coordination and profile-wide operations keep their existing owners.
local _, ST = ...
local Addon, CS = ST.Addon, ST._configState

function ST._CaptureConfigEditTarget(panelId, context)
    local profile = Addon.db and Addon.db.profile
    local panel = profile and profile.groups and profile.groups[panelId]
    if context and context.kind then
        return { profile = profile, panelId = panelId, context = context, kind = context.kind }
    end
    if not panel then return nil end
    return { profile = profile, panelId = panelId, panel = panel, context = context }
end

local function IsValidTarget(target)
    return target and Addon.db.profile == target.profile
        and (target.kind or target.profile.groups[target.panelId] == target.panel)
        and (not target.context or target.context:IsCurrent())
end
ST._IsConfigEditTargetCurrent = IsValidTarget

-- Capture once while the control is built. Shared builders may ask this
-- callback to finish their settings/advanced rebuild as part of the same edit.
-- Its true receipt means they must not run a second completion afterward.
function ST._MakeConfigEditRefresh(group)
    local context = group and group._settingsContext
    local target = ST._CaptureConfigEditTarget(context and context.panelId or CS.selectedGroup, context)
    return function(operation, outcome)
        return ST._CompleteConfigEdit(target, operation or "style", outcome)
    end
end

-- Module receipts survive the settings widgets released by their own rebuild,
-- but never a different profile, module record, or workspace destination.
function ST._IsModuleEditWorkspaceCurrent(edit)
    local settings = edit.moduleKind == "resources" and Addon:GetResourceBarSettings() or Addon:GetCastBarSettings()
    return Addon.db.profile == edit.profile and settings == edit.settings
        and CS.selectedGroup == edit.panelId and CS.barsEntrySelected == edit.barsEntrySelected
        and Addon._currentSpecId == edit.currentSpec
end

local function CompleteModuleEdit(target, operation, effect)
    local context, kind = target.context, target.kind
    local settingsOnly = operation == "settings"
    local settings = settingsOnly or operation == "style-settings"
    local soon = operation == "style-settings-soon" or operation == "style-advanced-soon"
    local advanced = operation == "style-advanced" or operation == "style-advanced-soon"
    local attachment = operation == "attachment"
    local enable = operation == "enable"
    assert(settings or soon or advanced or attachment or enable or operation == "style", "Unknown module edit completion")
    if attachment then
        if not Addon:SetModuleAttachment(kind, effect.mode, effect.panelId, context.spec) then return false end
        Addon:EvaluateBarsAndFramesRuntime("module-attachment")
        ST._OpenBarWorkspace(kind)
    elseif enable then
        context.settings.enabled = effect == true
        if effect then ST._PrepareBarWorkspaceEnable(kind) end
        Addon:EvaluateResourceBars()
    elseif not settingsOnly then
        if kind == "resources" then
            -- The runtime owner already lays out old/new hosts and evaluates Cast.
            Addon:ApplyResourceBars()
        else
            Addon:ApplyCastBarSettings()
            if Addon.RepositionCastBar then Addon:RepositionCastBar() end
        end
    end
    local col3 = CS.configFrame and CS.configFrame.col3
    local edit = { moduleKind = kind, profile = target.profile, settings = context.settings,
        currentSpec = Addon._currentSpecId, panelId = CS.selectedGroup, barsEntrySelected = CS.barsEntrySelected,
        preservePreview = settingsOnly, previewHost = col3 and col3._cdcActiveWideHost }
    if settings or attachment or enable then
        ST._RefreshConfigEditWorkspace(edit)
    elseif advanced and not soon and CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    end
    if not settingsOnly and not edit.previewBuilt and ST._RefreshResourcesLayoutPreview then
        edit.previewBuilt = ST._RefreshResourcesLayoutPreview() == true
    end
    if soon then
        -- Preserve the immediate canvas through the editor's existing safe
        -- callback-release boundary; this is not a delayed visual update.
        edit.preservePreview = edit.previewBuilt
        CS.RefreshAdvancedSettingsPanelSoon(not advanced, edit)
    end
    return true
end

-- Callers choose a known edit outcome, not arbitrary refresh flags/callbacks.
function ST._CompleteConfigEdit(target, operation, effect)
    if not IsValidTarget(target) then return false end
    if target.kind then return CompleteModuleEdit(target, operation, effect) end
    local settingsOnly = operation == "settings"
    local settings = settingsOnly or operation == "style-settings" or operation == "frame-settings"
    local frame = operation == "frame" or operation == "frame-settings"
    assert(settings or frame or operation == "style" or operation == "style-advanced", "Unknown config edit completion")

    if frame then
        ST._GroupFrame.RefreshGroupFrameRuntime(Addon, target.panelId)
    elseif not settingsOnly then
        ST._GroupFrame.UpdateGroupStyleRuntime(Addon, target.panelId, effect, target.context)
    end

    -- A style completion can change geometry and presentation, but does not
    -- declare new membership. The mirror verifies its bindings before reuse.
    local outcome = not settingsOnly and not frame and ((effect == "appearance" or effect == "interaction") and "appearance" or "geometry") or nil
    local edit = { panelId = target.panelId, preservePreview = settingsOnly, previewOutcome = outcome, refreshNavigator = frame }
    if settings then
        ST._RefreshConfigEditWorkspace(edit)
    elseif operation == "style-advanced" and CS.selectedGroup == target.panelId
        and CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    end

    -- Runtime absence/combat deferral and rejected UI rebuilds must still
    -- repaint saved design. This receipt belongs to this invocation only.
    if not settingsOnly and not edit.previewBuilt and ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(target.panelId, false, outcome)
    end
    return true
end
