local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Slider wiring for edits the pinned mirror can stand in for: while the
-- slider is dragged the candidate value exists only for the mirror render;
-- the saved value and live panel update once on release. The slider's edit box fires
-- OnMouseUp on Enter too, so typed values also apply live.
--
-- stateOwner/stateKeys name the exact raw fields applyValue touches. They are
-- snapshotted on every preview tick instead of restoring slider:GetValue(): a
-- slider can display a fallback for an absent field, and writing that fallback
-- back would silently materialize an override before the user commits.
local function WireMirrorFirstSlider(slider, applyValue, commitFn, previewFn, stateOwner, stateKeys, outcome)
    local context = ST._GetSettingsWidgetContext and ST._GetSettingsWidgetContext(slider)
    local target = ST._CaptureConfigEditTarget(CS.selectedGroup, context)

    -- The target carries this same context, so its check covers both.
    slider:SetCallback("OnValueChanged", function(_, _, value)
        if target then
            if not ST._IsConfigEditTargetCurrent(target) then return end
        elseif context and not context:IsCurrent() then return end
        ST._WithSettingsPreview(stateOwner, stateKeys, function() applyValue(value) end, function(outcome)
            if previewFn == false then
                -- Some sliders change screen-space placement, which the pinned
                -- mirror intentionally does not represent.
            elseif previewFn then
                previewFn(outcome)
            elseif ST._RefreshButtonsPreviewMirror then
                ST._RefreshButtonsPreviewMirror(target and target.panelId or CS.selectedGroup, true, outcome)
            end
        end)
    end)
    slider:SetCallback("OnMouseUp", function(_, _, value)
        if target then
            if not ST._IsConfigEditTargetCurrent(target) then return end
        elseif context and not context:IsCurrent() then return end
        applyValue(value)
        if commitFn then
            commitFn()
        elseif target then
            ST._CompleteConfigEdit(target, "style", outcome)
        else
            CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
        end
    end)
end

local function RefreshActiveAdvancedSettingsPanel()
    if CS.RefreshAdvancedSettingsPanel then
        CS.RefreshAdvancedSettingsPanel()
    end
end

ST._WireMirrorFirstSlider = WireMirrorFirstSlider
ST._RefreshActiveAdvancedSettingsPanel = RefreshActiveAdvancedSettingsPanel
