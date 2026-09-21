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

-- Callers choose a known edit outcome, not arbitrary refresh flags/callbacks.
function ST._CompleteConfigEdit(target, operation)
    if not IsValidTarget(target) then return false end
    local settingsOnly = operation == "settings"
    local settings = settingsOnly or operation == "style-settings" or operation == "frame-settings"
    assert(settings or operation == "style" or operation == "style-advanced", "Unknown config edit completion")

    if operation == "frame-settings" then
        ST._GroupFrame.RefreshGroupFrameRuntime(Addon, target.panelId)
    elseif not settingsOnly then
        ST._GroupFrame.UpdateGroupStyleRuntime(Addon, target.panelId)
    end

    local edit = { panelId = target.panelId, preservePreview = settingsOnly }
    if settings then
        ST._RefreshConfigEditWorkspace(edit)
    elseif operation == "style-advanced" and CS.selectedGroup == target.panelId
        and CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    end

    -- Runtime absence/combat deferral and rejected UI rebuilds must still
    -- repaint saved design. This receipt belongs to this invocation only.
    if not settingsOnly and not edit.previewBuilt and ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(target.panelId)
    end
    return true
end
