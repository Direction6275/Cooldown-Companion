local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

-- Imports from Helpers.lua
local AddAnchorDropdown = ST._AddAnchorDropdown
local AddFontControls = ST._AddFontControls
local AddOffsetSliders = ST._AddOffsetSliders

-- Imports from RowWidgets.lua (the row grammar)
local AddCheckboxRow = ST._AddCheckboxRow
local AddSliderRow = ST._AddSliderRow
local AddColorRow = ST._AddColorRow

-- Slider wiring for edits the pinned mirror can stand in for: while the
-- slider is dragged the candidate value exists only for the mirror render;
-- the saved value and live panel update once on release. The slider's edit box fires
-- OnMouseUp on Enter too, so typed values also apply live.
--
-- stateOwner/stateKeys name the exact raw fields applyValue touches. They are
-- snapshotted on every preview tick instead of restoring slider:GetValue(): a
-- slider can display a fallback for an absent field, and writing that fallback
-- back would silently materialize an override before the user commits.
local NIL_SETTING = {}
local function WireMirrorFirstSlider(slider, applyValue, commitFn, previewFn, stateOwner, stateKeys)
    if type(stateKeys) == "string" then
        stateKeys = { stateKeys }
    end
    local function CaptureState()
        local state = {}
        for index, key in ipairs(stateKeys) do
            local value = stateOwner[key]
            state[index] = value == nil and NIL_SETTING or value
        end
        return state
    end
    local function RestoreState(state)
        for index, key in ipairs(stateKeys) do
            local value = state[index]
            if value == NIL_SETTING then
                stateOwner[key] = nil
            else
                stateOwner[key] = value
            end
        end
    end

    slider:SetCallback("OnValueChanged", function(_, _, value)
        local state = CaptureState()
        applyValue(value)
        if previewFn == false then
            -- Some sliders change screen-space placement, which the pinned
            -- mirror intentionally does not represent.
        elseif previewFn then
            previewFn()
        elseif ST._RefreshButtonsPreviewMirror then
            ST._RefreshButtonsPreviewMirror(CS.selectedGroup)
        end
        RestoreState(state)
    end)
    slider:SetCallback("OnMouseUp", function(_, _, value)
        applyValue(value)
        if commitFn then
            commitFn()
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

local function UpdateSelectedGroupStyle(refreshConfig)
    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    if refreshConfig then
        CooldownCompanion:RefreshConfigPanel()
    end
end

------------------------------------------------------------------------
-- Cooldown advanced panels, as descriptors
--
-- One cooldown drives the swipe and the cooldown text, and their gears sit on
-- two different tabs - only one of which is ever on screen. The preview
-- command center's gear opens BOTH panels at once (owner ruling 2026-07-26),
-- so their contents have to be reachable without the gear that normally
-- builds them. The tab builders below call these same factories, so each
-- panel still has exactly one definition.
--
-- The style table is resolved inside `build`, never captured. A panel the
-- command center opened for the tab you are NOT on has no gear on screen to
-- rebind its descriptor (RebindAdvancedSettingsPanel only fires from
-- AddAdvancedToggle, i.e. from a gear that actually builds), so a wholesale
-- style replacement that keeps the same context - Copy Style From Panel
-- assigns a fresh group.style outright - would leave a captured table
-- orphaned and every control in the panel writing into nothing. The tab
-- callers are unaffected either way: they rebuild and rebind every refresh.
--
-- A caller whose values do NOT live in the group style passes its own table
-- (`styleTable`): with an entry selected, the style lens hands the styling tabs
-- that entry's override store for the sections it owns, and there is no
-- resolver for those. Only a caller that rebinds every refresh may do this -
-- which the tab builders do, and the command center's tab-less opens do not.
------------------------------------------------------------------------

local function RefreshSelectedGroupStyle()
    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
end

local function ResolveSelectedGroupStyle()
    local groupId = CS.selectedGroup
    local profile = groupId and CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    return group and group.style or nil
end

local function MakeCooldownTextAdvancedDescriptor(styleTable)
    return {
        settingKey = "cooldownText",
        title = "Cooldown Text Advanced",
        build = function(panel)
            local style = styleTable or ResolveSelectedGroupStyle()
            if not style then
                return
            end

            -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow
            -- column, so every builder is called with { row = true } and no
            -- rightColumn, and each falls back to `container` for its extras.
            AddFontControls(panel, style, "cooldown", { size = 12 }, RefreshSelectedGroupStyle, { row = true })

            -- deferCommit is deliberately absent, matching the stock color picker
            -- this row replaced.
            AddColorRow(panel, {
                label = "Font Color",
                tbl = style,
                key = "cooldownFontColor",
                default = {1, 1, 1, 1},
                onConfirm = RefreshSelectedGroupStyle,
                onChange = RefreshSelectedGroupStyle,
            })

            AddAnchorDropdown(panel, style, "cooldownTextAnchor", "CENTER", RefreshSelectedGroupStyle, nil, { row = true })

            AddOffsetSliders(panel, style, "cooldownTextXOffset", "cooldownTextYOffset", { x = 0, y = 0 }, RefreshSelectedGroupStyle, { row = true })
        end,
    }
end

local function MakeCooldownSwipeAdvancedDescriptor(styleTable)
    return {
        settingKey = "cooldownSwipe",
        title = "Cooldown Swipe Advanced",
        build = function(panel)
            local style = styleTable or ResolveSelectedGroupStyle()
            if not style then
                return
            end

            -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow
            -- column, so the rows go straight onto the panel scroll and the two
            -- conditional rows indent under the toggles that gate them.
            --
            -- The two structural toggles keep calling
            -- RefreshActiveAdvancedSettingsPanel: this descriptor rebuilds ITS
            -- OWN panel rather than the whole config, and that is what makes the
            -- opacity slider and the edge color appear and disappear in place.

            -- Reverse Swipe
            AddCheckboxRow(panel, {
                label = "Reverse Swipe",
                value = style.cooldownSwipeReverse or false,
                onChange = function(val)
                    style.cooldownSwipeReverse = val
                    RefreshSelectedGroupStyle()
                end,
            })

            -- Show Swipe Fill
            AddCheckboxRow(panel, {
                label = "Show Swipe Fill",
                value = style.showCooldownSwipeFill ~= false,
                onChange = function(val)
                    style.showCooldownSwipeFill = val
                    RefreshSelectedGroupStyle()
                    RefreshActiveAdvancedSettingsPanel()
                end,
            })

            -- Swipe Fill Opacity (only when fill is visible). Row grammar has
            -- no percent readout, so this reads 0 - 1 rather than the stock
            -- slider's 0% - 100%; same store, same range.
            if style.showCooldownSwipeFill ~= false then
                local opacityRow = AddSliderRow(panel, {
                    label = "Swipe Fill Opacity",
                    indent = true,
                    min = 0, max = 1, step = 0.05,
                    value = style.cooldownSwipeAlpha or 0.8,
                })
                WireMirrorFirstSlider(opacityRow, function(val)
                    style.cooldownSwipeAlpha = val
                end, RefreshSelectedGroupStyle, nil, style, "cooldownSwipeAlpha")
            end

            -- Show Swipe Edge
            AddCheckboxRow(panel, {
                label = "Show Swipe Edge",
                value = style.cooldownSwipeEdgeEnabled == true,
                onChange = function(val)
                    style.cooldownSwipeEdgeEnabled = val
                    RefreshSelectedGroupStyle()
                    RefreshActiveAdvancedSettingsPanel()
                end,
            })

            -- Swipe Edge Color (only when edge is visible). deferCommit is
            -- deliberately absent, matching the stock color picker it replaced.
            if style.cooldownSwipeEdgeEnabled == true then
                AddColorRow(panel, {
                    label = "Swipe Edge Color",
                    indent = true,
                    tbl = style,
                    key = "cooldownSwipeEdgeColor",
                    default = {1, 1, 1, 1},
                    hasAlpha = true,
                    onConfirm = RefreshSelectedGroupStyle,
                    onChange = RefreshSelectedGroupStyle,
                })
            end
        end,
    }
end

ST._WireMirrorFirstSlider = WireMirrorFirstSlider
ST._RefreshActiveAdvancedSettingsPanel = RefreshActiveAdvancedSettingsPanel
ST._UpdateSelectedGroupStyle = UpdateSelectedGroupStyle
ST._MakeCooldownTextAdvancedDescriptor = MakeCooldownTextAdvancedDescriptor
ST._MakeCooldownSwipeAdvancedDescriptor = MakeCooldownSwipeAdvancedDescriptor
