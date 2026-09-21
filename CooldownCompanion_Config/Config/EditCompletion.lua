-- Synchronous completion of ordinary panel/entry edits. Candidate previews
-- retain their write/render/rollback lifetime. Profile/topology operations and
-- specialized module editors retain their existing broad refresh paths.
local _, ST = ...
local Addon, CS = ST.Addon, ST._configState

function ST._CaptureConfigEditTarget(panelId, context)
    local profile = Addon.db and Addon.db.profile
    local panel = profile and profile.groups and profile.groups[panelId]
    if not panel or (context and context.kind) then return nil end
    return { profile = profile, panelId = panelId, panel = panel, context = context }
end

local function IsValidTarget(target)
    return target and Addon.db.profile == target.profile
        and target.profile.groups[target.panelId] == target.panel
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

-- Callers choose a known edit outcome, not arbitrary refresh flags/callbacks.
function ST._CompleteConfigEdit(target, operation, effect)
    if not IsValidTarget(target) then return false end
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
