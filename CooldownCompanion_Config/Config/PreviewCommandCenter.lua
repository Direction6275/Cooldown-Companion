--[[
    CooldownCompanion - PreviewCommandCenter
    The preview command center: a chooser naming one preview state plus a
    play/stop button, pinned to the bottom-left of a workspace's pinned
    Live Preview surface, so the control that triggers a preview lives
    where the preview is actually visible.

    A chooser rather than a row of toggle badges (owner ruling 2026-07-25,
    after seeing the row in game): exactly one preview can ever be live,
    and a row of independently-clickable badges reads as "check any
    combination" - the one thing the model does not allow. It also drops
    the badge-soup problem and the need for a distinct glyph per state.

    Two families of preview, two scoping rules:
    - Panel previews (the buttons workspace) follow the selection: with a
      single entry selected the preview runs on that entry, with nothing
      (or a multi-select) on the whole panel.
    - Object previews (the resource/cast bars) are bound to the bar they
      belong to, so nothing narrows them and the chooser lists them under
      the object's own menu group.
    Previews stay mutually exclusive across the whole config, exactly as
    the settings-side badges they replaced always were.

    The bar is a child of the preview host, so every path that hides the
    host (view switches, talent picker, config close) takes the bar with
    it - it is deliberately NOT a new col3 surface. The inline texture
    browser is the exception by design: it takes over the settings area
    while the pinned preview stays, so the bar stays usable there too.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local RB = ST._RB

local BAR_HEIGHT = 20
local BAR_BOTTOM_INSET = 3
local BAR_LEFT_INSET = 4
local PLAY_SIZE = 18
local PLAY_ICON_SIZE = 13
local CHEVRON_SIZE = 10
local LABEL_GAP = 3
local PLAY_GAP = 6
local PLAY_ATLAS = "CreditsScreen-Assets-Buttons-Play"
local STOP_ATLAS = "CreditsScreen-Assets-Buttons-Pause"
local CHEVRON_ATLAS = "uitools-icon-chevron-down"

-- Vertical band the bar claims inside the host. The preview renderers
-- read this off the host and keep their content above it.
local BAR_RESERVE = BAR_HEIGHT + BAR_BOTTOM_INSET

------------------------------------------------------------------------
-- Preview state adapters
--
-- Three families reach three different runtime surfaces, but each one
-- reduces to the same pair: "is this preview on for the target" and "turn
-- it on/off for the target". Flag and conditional previews accept an
-- entry index; texture and trigger previews are panel-wide only.
------------------------------------------------------------------------

local function FlagPreview(flag, buttonSetter, groupSetter)
    return {
        IsActive = function(panelId, buttonIndex)
            return CooldownCompanion:IsPreviewFlagActive(panelId, buttonIndex, flag) == true
        end,
        SetActive = function(panelId, buttonIndex, show)
            if buttonIndex then
                local setter = CooldownCompanion[buttonSetter]
                if setter then setter(CooldownCompanion, panelId, buttonIndex, show) end
                return
            end
            local setter = CooldownCompanion[groupSetter]
            if setter then setter(CooldownCompanion, panelId, show) end
        end,
    }
end

-- Previews with no per-entry setter (key press highlight is driven by the
-- idle enrollment driver, panel-wide only). Selection does not narrow
-- these; they always run on the whole panel.
local function GroupOnlyFlagPreview(flag, groupSetter)
    return {
        -- Panel-wide by nature, so it never follows the selection.
        groupScoped = true,
        IsActive = function(panelId)
            return CooldownCompanion:IsPreviewFlagActive(panelId, nil, flag) == true
        end,
        SetActive = function(panelId, _, show)
            local setter = CooldownCompanion[groupSetter]
            if setter then setter(CooldownCompanion, panelId, show) end
        end,
    }
end

local function ConditionalPreview(kind)
    return {
        IsActive = function(panelId, buttonIndex)
            return CooldownCompanion:IsConditionalVisualPreviewActive(panelId, buttonIndex, kind) == true
        end,
        SetActive = function(panelId, buttonIndex, show)
            CooldownCompanion:SetConditionalVisualPreviewActive(panelId, buttonIndex, kind, show)
        end,
    }
end

local function TextureIndicatorPreview(indicatorKey)
    return {
        groupScoped = true,
        IsActive = function(panelId)
            return CooldownCompanion:IsGroupTextureIndicatorPreviewActive(panelId, indicatorKey) == true
        end,
        SetActive = function(panelId, _, show)
            CooldownCompanion:SetGroupTextureIndicatorPreview(panelId, indicatorKey, show)
        end,
    }
end

local TriggerEffectsPreview = {
    groupScoped = true,
    IsActive = function(panelId)
        return CooldownCompanion:IsTriggerPanelEffectsPreviewActive(panelId) == true
    end,
    SetActive = function(panelId, _, show)
        CooldownCompanion:SetTriggerPanelEffectsPreview(panelId, show)
    end,
}

-- Previews owned by one config object rather than by a panel: they always
-- run on the bar they belong to, so neither the selected panel nor the
-- selected entry can narrow them (hence groupScoped - they never follow a
-- selection). What makes them worth a control is that the resting bar
-- cannot show them at all: absorbs and a cast in progress only exist for a
-- moment, so the canvas has to be told to stage one.
local function HealthEffectPreview(effectKey)
    return {
        groupScoped = true,
        IsActive = function()
            return CooldownCompanion:IsHealthEffectPreviewActive(effectKey) == true
        end,
        SetActive = function(_, _, show)
            CooldownCompanion:SetHealthEffectPreview(effectKey, show)
        end,
    }
end

local CastBarPreview = {
    groupScoped = true,
    IsActive = function()
        return CooldownCompanion:IsCastBarPreviewActive() == true
    end,
    SetActive = function(_, _, show)
        if show then
            CooldownCompanion:StartCastBarPreview()
        else
            CooldownCompanion:StopCastBarPreview()
        end
    end,
}

-- Custom-bar active-aura preview (the aura pass): a CC-side stand-in on the
-- config canvas — fill, texts, and effects render as if the aura were
-- running; the real bar and the aura slot kit are never touched. Keyed by
-- the stored config table (the identity the runtime carries).
local function CustomBarAuraPreview(cabConfig)
    return {
        groupScoped = true,
        IsActive = function()
            return CooldownCompanion:IsCustomAuraBarActivePreviewActive(cabConfig) == true
        end,
        SetActive = function(_, _, show)
            CooldownCompanion:SetCustomAuraBarActivePreview(cabConfig, show)
        end,
    }
end

------------------------------------------------------------------------
-- Availability gates
------------------------------------------------------------------------

-- Override-section rules decide whether a glow/indicator preview can do
-- anything for the target: the selected entry must be able to use the
-- section, or - at panel scope - at least one entry must. Reuses the
-- shipped rule (aura tracking, equipment slots, no-cooldown spells)
-- rather than restating it.
local function SectionApplies(group, sectionId, buttonIndex)
    local canUse = ST._CanButtonUseConfigOverrideSection
    if not (sectionId and canUse) then
        return true
    end
    local buttons = group.buttons or {}
    if buttonIndex then
        local buttonData = buttons[buttonIndex]
        return buttonData ~= nil and canUse(buttonData, sectionId) == true
    end
    for _, buttonData in ipairs(buttons) do
        if canUse(buttonData, sectionId) == true then
            return true
        end
    end
    return false
end

-- Style as it applies to the target: the selected entry's effective style,
-- or the panel style at panel scope.
local function ResolveTargetStyle(group, buttonIndex)
    local style = group.style or {}
    local buttonData = buttonIndex and (group.buttons or {})[buttonIndex] or nil
    if buttonData and CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end
    return style
end

-- Conditional state previews render nothing while the visual they stand
-- in for is switched off, so the toggle hides with it - matching how the
-- settings-side badges have always behaved.
local function StyleFlagEnabled(group, buttonIndex, styleKey)
    return ResolveTargetStyle(group, buttonIndex)[styleKey] and true or false
end

-- Same idea for the settings that default ON, where nil means enabled and
-- only an explicit false disables (the `~= false` shape the shipped
-- badges gate on).
local function StyleFlagEnabledByDefault(group, buttonIndex, styleKey)
    return ResolveTargetStyle(group, buttonIndex)[styleKey] ~= false
end

-- Glow previews render nothing while the glow style is "none" (the
-- default for Ready Glow), which is exactly the condition the entry
-- popout toggles and the panel badges already gate on.
local function GlowStyleSelected(group, buttonIndex, styleKey)
    local value = ResolveTargetStyle(group, buttonIndex)[styleKey]
    return value ~= nil and value ~= "none"
end

local function BarAuraIndicatorEnabled(group, buttonIndex)
    if not ST.IsBarAuraIndicatorEnabled then
        return true
    end
    return ST.IsBarAuraIndicatorEnabled(ResolveTargetStyle(group, buttonIndex)) == true
end

local function TextureIndicatorEnabled(group, indicatorKey)
    -- Read-only: never pass createIfMissing here, a mere preview refresh
    -- must not write indicator tables into the profile.
    local indicators = CooldownCompanion.GetTexturePanelIndicatorSettings
        and CooldownCompanion:GetTexturePanelIndicatorSettings(group)
    local config = type(indicators) == "table" and indicators[indicatorKey] or nil
    return type(config) == "table" and config.enabled and true or false
end

local function AnyTriggerEffectEnabled(group)
    local effects = CooldownCompanion.GetTriggerPanelEffectSettings
        and CooldownCompanion:GetTriggerPanelEffectSettings(group)
    if type(effects) ~= "table" then
        return false
    end
    for _, config in pairs(effects) do
        if type(config) == "table" and config.enabled then
            return true
        end
    end
    return false
end

------------------------------------------------------------------------
-- Every panel preview, in menu order, grouped by what the preview
-- actually is: something CC draws on top, a situation the button is in,
-- or a readout it displays. Labels are the existing ones verbatim - the
-- no-rename ruling holds here too.
--
-- Note the states are deliberately single entries. The old UI offered
-- "Preview Cooldown Text", "Preview Cooldown Swipe", "Preview Cooldown
-- Fill" and "Preview Cooldown Tint" as four separate controls that all
-- fired the identical cooldown preview; they collapse to one here.
------------------------------------------------------------------------

local GROUP_EFFECTS = "Effects"
local GROUP_STATES = "Button States"
local GROUP_READOUTS = "Text & Timers"

local CONTROLS = {
    {
        id = "procGlow",
        label = "Preview Proc Glow",
        group = GROUP_EFFECTS,
        modes = { icons = true },
        section = "procGlow",
        glowStyleKey = "procGlowStyle",
        preview = FlagPreview("_procGlowPreview", "SetProcGlowPreview", "SetGroupProcGlowPreview"),
    },
    {
        id = "auraGlow",
        label = "Preview Aura Glow",
        group = GROUP_EFFECTS,
        modes = { icons = true },
        section = "auraIndicator",
        glowStyleKey = "auraGlowStyle",
        preview = FlagPreview("_auraGlowPreview", "SetAuraGlowPreview", "SetGroupAuraGlowPreview"),
    },
    {
        id = "readyGlow",
        label = "Preview Ready Glow Style",
        group = GROUP_EFFECTS,
        modes = { icons = true },
        section = "readyGlow",
        glowStyleKey = "readyGlowStyle",
        preview = FlagPreview("_readyGlowPreview", "SetReadyGlowPreview", "SetGroupReadyGlowPreview"),
    },
    {
        id = "keyPressHighlight",
        label = "Preview Key Press Highlight",
        group = GROUP_EFFECTS,
        modes = { icons = true },
        section = "keyPressHighlight",
        glowStyleKey = "keyPressHighlightStyle",
        preview = GroupOnlyFlagPreview("_keyPressHighlightPreview", "SetGroupKeyPressHighlightPreview"),
    },
    {
        id = "barActiveAura",
        label = "Preview Active Aura Indicator",
        group = GROUP_EFFECTS,
        modes = { bars = true },
        section = "barActiveAura",
        requiresBarAuraIndicator = true,
        preview = FlagPreview("_barAuraEffectPreview", "SetBarAuraEffectPreview", "SetGroupBarAuraEffectPreview"),
    },
    {
        id = "textureProc",
        label = "Preview Proc Effect",
        group = GROUP_EFFECTS,
        modes = { textures = true },
        indicatorKey = "proc",
        preview = TextureIndicatorPreview("proc"),
    },
    {
        id = "textureReady",
        label = "Preview Ready Effect",
        group = GROUP_EFFECTS,
        modes = { textures = true },
        indicatorKey = "ready",
        preview = TextureIndicatorPreview("ready"),
    },
    {
        id = "textureUnusable",
        label = "Preview Unusable Effect",
        group = GROUP_EFFECTS,
        modes = { textures = true },
        indicatorKey = "unusable",
        preview = TextureIndicatorPreview("unusable"),
    },
    {
        id = "triggerEffects",
        label = "Preview Effects",
        group = GROUP_EFFECTS,
        modes = { trigger = true },
        requiresTriggerEffect = true,
        preview = TriggerEffectsPreview,
    },

    {
        id = "cooldown",
        label = "Preview Cooldown State",
        group = GROUP_STATES,
        modes = { icons = true, bars = true, text = true, rotationAssistant = true },
        preview = ConditionalPreview("cooldown"),
    },
    {
        id = "unusable",
        label = "Preview Unusable State",
        group = GROUP_STATES,
        modes = { icons = true, bars = true, text = true, rotationAssistant = true },
        styleKey = "showUnusable",
        preview = ConditionalPreview("unusable"),
    },
    {
        id = "outOfRange",
        label = "Preview Out of Range State",
        group = GROUP_STATES,
        modes = { icons = true, text = true, rotationAssistant = true },
        styleKey = "showOutOfRange",
        preview = ConditionalPreview("out_of_range"),
    },
    {
        id = "lossOfControl",
        label = "Preview Loss of Control",
        group = GROUP_STATES,
        modes = { icons = true, bars = true, rotationAssistant = true },
        section = "lossOfControl",
        styleKey = "showLossOfControl",
        preview = ConditionalPreview("loss_of_control"),
    },

    {
        id = "auraDurationText",
        label = "Preview Aura Duration Text",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "auraText",
        styleKeyDefaultOn = "showAuraText",
        preview = ConditionalPreview("aura_duration_text"),
    },
    {
        id = "auraStackText",
        label = "Preview Aura Stack Text",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "auraStackText",
        styleKeyDefaultOn = "showAuraStackText",
        preview = ConditionalPreview("aura_stack_text"),
    },
    {
        id = "auraDurationSwipe",
        label = "Preview Aura Duration Swipe",
        group = GROUP_READOUTS,
        modes = { icons = true },
        section = "auraDurationSwipe",
        styleKeyDefaultOn = "showAuraDurationSwipe",
        preview = ConditionalPreview("aura_duration_swipe"),
    },
    {
        id = "chargeFull",
        label = "Preview Max Charges",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "chargeText",
        styleKeyDefaultOn = "showChargeText",
        preview = ConditionalPreview("charge_full"),
    },
    {
        id = "chargeMissing",
        label = "Preview Missing Charges",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "chargeText",
        styleKeyDefaultOn = "showChargeText",
        preview = ConditionalPreview("charge_missing"),
    },
    {
        id = "chargeZero",
        label = "Preview Zero Charges",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "chargeText",
        styleKeyDefaultOn = "showChargeText",
        preview = ConditionalPreview("charge_zero"),
    },
}

local function ControlApplies(control, group, displayMode, buttonIndex)
    if not control.modes[displayMode] then
        return false
    end
    if control.section and not SectionApplies(group, control.section, buttonIndex) then
        return false
    end
    if control.styleKey and not StyleFlagEnabled(group, buttonIndex, control.styleKey) then
        return false
    end
    if control.styleKeyDefaultOn
        and not StyleFlagEnabledByDefault(group, buttonIndex, control.styleKeyDefaultOn) then
        return false
    end
    if control.glowStyleKey and not GlowStyleSelected(group, buttonIndex, control.glowStyleKey) then
        return false
    end
    if control.requiresBarAuraIndicator and not BarAuraIndicatorEnabled(group, buttonIndex) then
        return false
    end
    if control.indicatorKey and not TextureIndicatorEnabled(group, control.indicatorKey) then
        return false
    end
    if control.requiresTriggerEffect and not AnyTriggerEffectEnabled(group) then
        return false
    end
    return true
end

------------------------------------------------------------------------
-- Object previews: the resource and cast bars.
--
-- Grouped by the bar they play on rather than by what they draw, because
-- that is how the owner picks them ("show me what the health bar does"),
-- and because it is the shape the future per-custom-bar aura previews
-- slot into: one more group per bar, no widget or menu changes.
--
-- Availability reads the same effective config the runtime does, so an
-- entry appears exactly when picking it would show something. All of
-- these settings are explicit opt-ins (`== true`), unlike the
-- default-ON button states above.
------------------------------------------------------------------------

local GROUP_HEALTH_BAR = "Health Bar"
local GROUP_CAST_BAR = "Cast Bar"

local function GetHealthEffectConfig()
    local settings = CooldownCompanion.GetResourceBarSettings
        and CooldownCompanion:GetResourceBarSettings()
    if not (settings and settings.enabled == true) then
        return nil
    end
    if not (RB and RB.IsResourceEnabled and RB.IsResourceEnabled(RB.RESOURCE_HEALTH, settings)) then
        return nil
    end
    -- Resolved for the player's current spec, which is the one the live
    -- health bar is running - the same table the runtime reads.
    local config = RB.GetResourceDisplayConfig
        and RB.GetResourceDisplayConfig(settings, RB.RESOURCE_HEALTH)
    return type(config) == "table" and config or nil
end

-- Takes the config resolved once per pass by CollectObjectControls rather
-- than resolving its own: GetResourceDisplayConfig deep-copies the
-- resource table on every call, and all four health gates want the same
-- answer.
local function HealthEffectEnabled(healthConfig, settingKey)
    return healthConfig ~= nil and healthConfig[settingKey] == true
end

local function CastBarEnabled()
    local settings = CooldownCompanion.GetCastBarSettings
        and CooldownCompanion:GetCastBarSettings()
    return settings ~= nil and settings.enabled == true
end

local OBJECT_CONTROLS = {
    {
        id = "healthAbsorbs",
        label = "Preview Absorbs",
        group = GROUP_HEALTH_BAR,
        object = "health",
        Applies = function(healthConfig) return HealthEffectEnabled(healthConfig, "showAbsorbs") end,
        preview = HealthEffectPreview("absorbs"),
    },
    {
        id = "healthHealAbsorbs",
        label = "Preview Healing Absorbs",
        group = GROUP_HEALTH_BAR,
        object = "health",
        Applies = function(healthConfig) return HealthEffectEnabled(healthConfig, "showHealAbsorbs") end,
        preview = HealthEffectPreview("healAbsorbs"),
    },
    {
        id = "healthIncomingHeals",
        label = "Preview Incoming Heals",
        group = GROUP_HEALTH_BAR,
        object = "health",
        Applies = function(healthConfig) return HealthEffectEnabled(healthConfig, "showIncomingHeals") end,
        preview = HealthEffectPreview("incomingHeals"),
    },
    {
        id = "healthLowHealthAlert",
        label = "Preview Low Health Alert",
        group = GROUP_HEALTH_BAR,
        object = "health",
        Applies = function(healthConfig) return HealthEffectEnabled(healthConfig, "showLowHealthAlert") end,
        preview = HealthEffectPreview("lowHealthAlert"),
    },
    {
        id = "castBar",
        label = "Preview Cast Bar",
        group = GROUP_CAST_BAR,
        object = "cast",
        Applies = CastBarEnabled,
        preview = CastBarPreview,
    },
}

-- Which objects a surface hosts. The homes list the objects that
-- workspace configures; the buttons workspace lists the bars its unified
-- anchor preview actually draws as lanes, which is also exactly when a
-- bar's settings can be open below the divider there.
local function CollectObjectControls(objects)
    local applicable = {}
    -- Resolved once and handed to the gates that want it, since resolving
    -- deep-copies the resource table. Skipped entirely on a surface that
    -- hosts no health entries.
    local healthConfig = objects.health and GetHealthEffectConfig() or nil
    for _, control in ipairs(OBJECT_CONTROLS) do
        if objects[control.object] and control.Applies(healthConfig) then
            applicable[#applicable + 1] = control
        end
    end

    -- Per-custom-bar groups (the aura pass): one group per live
    -- aura-tracked Custom Bar, built dynamically — the entry appears
    -- exactly when the bar would render an aura display. Controls close
    -- over the stored config table, the same identity the runtime keys
    -- its preview state by.
    if objects.customBars then
        local settings = CooldownCompanion.GetResourceBarSettings
            and CooldownCompanion:GetResourceBarSettings()
        if settings and settings.enabled == true then
            for _, cab in ipairs(CooldownCompanion:GetSpecCustomAuraBars()) do
                local auraTracked = type(cab) == "table"
                    and (cab.entryType ~= "spell" or cab.auraTracking == true)
                if auraTracked and CooldownCompanion:IsCustomBarRuntimeEligible(cab) then
                    local name = cab.label
                    if not name or name == "" then
                        name = C_Spell.GetSpellName(tonumber(cab.spellID)) or "Custom Bar"
                    end
                    applicable[#applicable + 1] = {
                        id = "customBarAura_" .. tostring(cab.customBarId),
                        label = "Preview Active Aura",
                        group = "Custom Bar: " .. name,
                        object = "customBars",
                        preview = CustomBarAuraPreview(cab),
                    }
                end
            end
        end
    end
    return applicable
end

-- Which bars the unified anchor preview draws as lanes: the same
-- attached-vs-independent test the lane renderer itself makes
-- (ST._HasAttachedBarLanesToRender). A bar on its own independent anchor
-- is not on that canvas and its settings cannot be opened there, so its
-- previews stay on its own home.
local function GetAnchorLaneObjects()
    local rbSettings = CooldownCompanion.GetResourceBarSettings
        and CooldownCompanion:GetResourceBarSettings()
    local cbSettings = CooldownCompanion.GetCastBarSettings
        and CooldownCompanion:GetCastBarSettings()
    local layout = CooldownCompanion.GetSpecLayoutOrder
        and CooldownCompanion:GetSpecLayoutOrder()
    local IsTruthyConfigFlag = RB and RB.IsTruthyConfigFlag
    if not (layout and IsTruthyConfigFlag) then
        return {}
    end
    local barsAttached = rbSettings ~= nil
        and rbSettings.enabled == true
        and not IsTruthyConfigFlag(layout.independentAnchorEnabled)
    return {
        health = barsAttached,
        cast = cbSettings ~= nil
            and cbSettings.enabled == true
            and not IsTruthyConfigFlag(cbSettings.independentAnchorEnabled),
        -- Custom bars ride the same attached resource stack as the health
        -- bar; their aura previews belong on the anchor canvas too.
        customBars = barsAttached,
    }
end

------------------------------------------------------------------------
-- Context: which panel the bar acts on, and whether a single selected
-- entry narrows it. A multi-select keeps panel scope (the setters take
-- one entry, and "nothing narrowed" is the ruled fallback).
------------------------------------------------------------------------

local function ResolveContext()
    local panelId = CS.selectedGroup
    if not panelId then
        return nil
    end
    local db = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = db and db.groups and db.groups[panelId] or nil
    if not group then
        return nil
    end

    local multiCount = 0
    for _ in pairs(CS.selectedButtons or {}) do
        multiCount = multiCount + 1
    end
    local buttonIndex
    if multiCount < 2
        and CS.selectedButton
        and (group.buttons or {})[CS.selectedButton] then
        buttonIndex = CS.selectedButton
    end

    return panelId, group, buttonIndex
end

------------------------------------------------------------------------
-- Surfaces: the two hosts that can carry a bar. Each one knows how to
-- resolve the preview target, where its remembered choice lives (so the
-- two never fight over one key), and how to repaint itself after a
-- toggle.
------------------------------------------------------------------------

local BUTTONS_SURFACE = {
    selectionKey = "previewCommandCenterSelection",
    ResolveTarget = function()
        local panelId, _, buttonIndex = ResolveContext()
        if not panelId then
            return false
        end
        return true, panelId, buttonIndex
    end,
    Repaint = function()
        -- Rebuilds the mirror, which re-runs the update below and
        -- repaints the bar from live state.
        if ST._RefreshButtonsPreviewMirror then
            ST._RefreshButtonsPreviewMirror()
        end
    end,
}

local RESOURCES_SURFACE = {
    selectionKey = "resourcesPreviewCommandCenterSelection",
    -- Object previews run on the bar they belong to: there is no panel or
    -- entry to resolve, and no selection state that could fail.
    ResolveTarget = function()
        return true, nil, nil
    end,
    Repaint = function()
        if ST._RefreshResourcesLayoutPreview then
            ST._RefreshResourcesLayoutPreview()
        end
    end,
}

------------------------------------------------------------------------
-- Running a preview
--
-- Previews are mutually exclusive across the whole config, so starting
-- one clears every other.
------------------------------------------------------------------------

local function SetPreviewRunning(surface, control, panelId, buttonIndex, show)
    if show and CooldownCompanion.ClearAllConfigPreviews then
        CooldownCompanion:ClearAllConfigPreviews()
    end
    control.preview.SetActive(panelId, buttonIndex, show)
    surface.Repaint()
end

------------------------------------------------------------------------
-- A running preview follows the selection (owner ruling 2026-07-25).
-- Previewing is "show me what I am editing", so changing what you are
-- editing re-scopes the preview rather than stranding it on the entry
-- you just left - which read as broken, since the chooser scopes to the
-- new selection and would report "stopped" while the old entry glowed.
--
-- Deselecting widens the preview back to the whole panel, which is the
-- same rule read the other way. If the preview cannot apply to the new
-- target (aura glow, and the new entry tracks no aura) it simply stops.
--
-- Safe to re-scope from here: this runs at the top of the mirror's build
-- closure, so the slots are laid out after it and read the new state -
-- no extra refresh, no re-entrancy.
------------------------------------------------------------------------

local function FindControlById(controlId)
    if not controlId then
        return nil
    end
    for _, control in ipairs(CONTROLS) do
        if control.id == controlId then
            return control
        end
    end
    return nil
end

local function IsControlApplicable(control, applicable)
    for _, candidate in ipairs(applicable) do
        if candidate == control then
            return true
        end
    end
    return false
end

local function MigrateRunningPreview(panelId, buttonIndex, applicable)
    local lastPanelId = CS.previewCommandCenterLastPanel
    local lastButtonIndex = CS.previewCommandCenterLastButton
    CS.previewCommandCenterLastPanel = panelId
    CS.previewCommandCenterLastButton = buttonIndex

    -- Only within one panel: a preview belongs to the panel it was
    -- started on, and following the user across panels would be a
    -- surprise rather than a convenience.
    if lastPanelId ~= panelId or lastButtonIndex == buttonIndex then
        return
    end

    local control = FindControlById(CS.previewCommandCenterSelection)
    if not control or control.preview.groupScoped then
        return
    end
    -- Gate on what was running at the LAST update, not on live state:
    -- SelectConfigButton (State.lua) calls ClearAllConfigPreviews on every
    -- entry selection, so by the time this runs the preview we mean to
    -- carry over has already been wiped and a live check always says no.
    -- That is why entry -> entry did nothing while deselecting worked.
    if not CS.previewCommandCenterWasRunning then
        return
    end

    -- No-op when the seam already cleared it; a real move otherwise.
    control.preview.SetActive(panelId, lastButtonIndex, false)
    if IsControlApplicable(control, applicable) then
        control.preview.SetActive(panelId, buttonIndex, true)
    end
end

------------------------------------------------------------------------
-- The bar: a chooser naming the selected preview, plus a play/stop
-- button that arms it.
--
-- A dropdown rather than a row of toggles because exactly one preview can
-- ever be live - a row of independently-clickable badges reads as "check
-- any combination", which is the one thing the model does not allow.
------------------------------------------------------------------------

local function EnsureMenuFrame()
    if not CS.previewCommandCenterMenu then
        local menu = CreateFrame(
            "Frame", "CDCPreviewCommandCenterDropdown", UIParent, "UIDropDownMenuTemplate")
        -- The list re-arms this on every open (ToggleDropDownMenu copies it
        -- to listFrame.onHide) and fires it however the menu closes: the
        -- global mouse-down handler, picking an item, another menu opening,
        -- or our own CloseDropDownMenus. This plus ToggleDropDownMenu's
        -- return value is ALL the open/closed state we track - the previous
        -- guard read _G.DropDownList1 directly, but the dropdown code runs
        -- in its own environment (GetCurrentEnvironment() at the top of
        -- UIDropDownMenu.lua), so that global never matched the live list
        -- and the guard was dead code: every click read "closed" and
        -- reopened the menu, which looked exactly like it never closing.
        menu.onHide = function()
            CS.previewCommandCenterMenuOpen = nil
            CS.previewCommandCenterMenuClosedAt = GetTime()
        end
        -- Open UPWARD, over the preview canvas, instead of down over the
        -- settings below the divider - a menu laid over live settings
        -- reads as chaos. ToggleDropDownMenu prefers these fields over its
        -- own arguments when an anchor frame is passed, and still applies
        -- its own screen clamp afterwards. `relativeTo` is deliberately
        -- left unset so the anchor passed at open time wins.
        menu.point = "BOTTOMLEFT"
        menu.relativePoint = "TOPLEFT"
        menu.xOffset = 0
        menu.yOffset = 2
        CS.previewCommandCenterMenu = menu
    end
    return CS.previewCommandCenterMenu
end

local function OpenPreviewMenu(bar)
    local surface = bar._surface
    local ok, panelId, buttonIndex = surface.ResolveTarget()
    if not ok then
        return
    end

    local menu = EnsureMenuFrame()
    UIDropDownMenu_Initialize(menu, function(_, level)
        local applicable = bar._applicable or {}
        -- Headers only earn their space once the menu actually spans more
        -- than one group (a texture or trigger panel offers Effects only).
        local showHeaders = false
        local firstGroup = applicable[1] and applicable[1].group
        for _, control in ipairs(applicable) do
            if control.group ~= firstGroup then
                showHeaders = true
                break
            end
        end

        local currentGroup
        for _, control in ipairs(applicable) do
            if showHeaders and control.group ~= currentGroup then
                currentGroup = control.group
                local header = UIDropDownMenu_CreateInfo()
                header.text = control.group
                header.isTitle = true
                header.notCheckable = true
                UIDropDownMenu_AddButton(header, level)
            end

            local info = UIDropDownMenu_CreateInfo()
            info.text = control.label
            -- Radio, not check: picking one is picking the only one.
            info.checked = (CS[surface.selectionKey] == control.id)
            info.func = function()
                CloseDropDownMenus()
                CS[surface.selectionKey] = control.id
                -- Choosing a preview is asking to see it.
                SetPreviewRunning(surface, control, panelId, buttonIndex, true)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    -- Returns true when it opened the list, false when it toggled it
    -- closed or refused (empty menu).
    local opened = ToggleDropDownMenu(1, nil, menu, bar.chooser, 0, 0)
    CS.previewCommandCenterMenuOpen = opened and true or nil
end

local function EnsureBar(host, surface)
    local bar = host._cdcPreviewCommandCenter
    if bar then
        bar._surface = surface
        return bar
    end

    bar = CreateFrame("Frame", nil, host)
    bar:SetHeight(BAR_HEIGHT)
    bar:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", BAR_LEFT_INSET, BAR_BOTTOM_INSET)
    bar:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, BAR_BOTTOM_INSET)
    -- Above the mirror's own frames so the bar is never drawn under a slot
    -- that overhangs its cell (glows render outside the slot rect).
    bar:SetFrameLevel(host:GetFrameLevel() + 20)

    -- Chooser: label + chevron, no backdrop (hierarchy from position and
    -- color, never boxes).
    local chooser = CreateFrame("Button", nil, bar)
    chooser:SetHeight(BAR_HEIGHT)
    chooser:SetPoint("LEFT", bar, "LEFT", 0, 0)

    local label = chooser:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", chooser, "LEFT", 0, 0)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(false)
    chooser.label = label

    local chevron = chooser:CreateTexture(nil, "ARTWORK")
    chevron:SetSize(CHEVRON_SIZE, CHEVRON_SIZE)
    chevron:SetPoint("LEFT", label, "RIGHT", LABEL_GAP, 0)
    chevron:SetAtlas(CHEVRON_ATLAS, false)
    chooser.chevron = chevron

    chooser:SetScript("OnEnter", function(self)
        self.label:SetTextColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Choose a preview")
        GameTooltip:AddLine("Only one preview runs at a time.", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    chooser:SetScript("OnLeave", function(self)
        if self._refreshColors then self._refreshColors() end
        GameTooltip:Hide()
    end)
    -- Fire on mouse DOWN, matching when the list does its own
    -- outside-click auto-hide, so open and close feel identical.
    chooser:RegisterForClicks("LeftButtonDown")
    chooser:SetScript("OnClick", function()
        -- Our click reached OnClick with the list still up: this click is
        -- the close. (Covers the ordering where frame scripts run before
        -- the global mouse-down handler.)
        if CS.previewCommandCenterMenuOpen then
            CloseDropDownMenus()
            return
        end
        -- The list already hid THIS SAME FRAME - the global mouse-down
        -- handler closed it because our click landed outside the list.
        -- That click was the close; consume it instead of reopening.
        -- GetTime() is frame-constant, so equality means "this click".
        if CS.previewCommandCenterMenuClosedAt == GetTime() then
            return
        end
        OpenPreviewMenu(bar)
    end)
    bar.chooser = chooser

    local play = CreateFrame("Button", nil, bar)
    play:SetSize(PLAY_SIZE, PLAY_SIZE)
    play:SetPoint("LEFT", chooser, "RIGHT", PLAY_GAP, 0)
    play._icon = play:CreateTexture(nil, "ARTWORK")
    play._icon:SetSize(PLAY_ICON_SIZE, PLAY_ICON_SIZE)
    play._icon:SetPoint("CENTER")
    play._icon:SetAtlas(PLAY_ATLAS, false)

    play:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._running and "Stop preview" or "Start preview")
        GameTooltip:Show()
    end)
    play:SetScript("OnLeave", function() GameTooltip:Hide() end)
    play:SetScript("OnClick", function(self)
        local control = bar._selected
        if not control then
            return
        end
        local ok, panelId, buttonIndex = bar._surface.ResolveTarget()
        if not ok then
            return
        end
        SetPreviewRunning(bar._surface, control, panelId, buttonIndex, not self._running)
    end)
    bar.play = play

    bar._surface = surface
    host._cdcPreviewCommandCenter = bar
    return bar
end

local function ApplyBarState(bar, control, running)
    bar._selected = control
    bar.play._running = running

    bar.chooser.label:SetText(control.label)
    bar.chooser:SetWidth(bar.chooser.label:GetStringWidth() + LABEL_GAP + CHEVRON_SIZE)

    bar.chooser._refreshColors = function()
        if running then
            bar.chooser.label:SetTextColor(1, 0.82, 0, 1)
        else
            bar.chooser.label:SetTextColor(0.72, 0.72, 0.72, 1)
        end
    end
    bar.chooser._refreshColors()

    if running then
        bar.chooser.chevron:SetVertexColor(1, 0.82, 0, 1)
        bar.play._icon:SetAtlas(STOP_ATLAS, false)
        bar.play._icon:SetVertexColor(1, 0.82, 0, 1)
    else
        bar.chooser.chevron:SetVertexColor(0.72, 0.72, 0.72, 0.85)
        bar.play._icon:SetAtlas(PLAY_ATLAS, false)
        bar.play._icon:SetVertexColor(0.72, 0.72, 0.72, 0.85)
    end
end

local function HideBar(host)
    host._cdcPreviewReserveBottom = nil
    local bar = host and host._cdcPreviewCommandCenter
    if bar then
        bar:Hide()
    end
end

------------------------------------------------------------------------
-- Shared bar update: resolve which entry the chooser names, whether it is
-- running, and show the bar. Both surfaces reach this having already
-- decided what they can offer.
------------------------------------------------------------------------

local function UpdateBar(host, surface, applicable)
    if #applicable == 0 then
        HideBar(host)
        return nil, false
    end

    local ok, panelId, buttonIndex = surface.ResolveTarget()
    if not ok then
        HideBar(host)
        return nil, false
    end

    -- Whatever is actually running wins the selection, so a preview
    -- started elsewhere still reads correctly here. Otherwise keep the
    -- remembered choice, falling back to the first applicable one when it
    -- does not apply to this surface.
    local selected, running
    local remembered
    for _, control in ipairs(applicable) do
        if control.preview.IsActive(panelId, buttonIndex) == true then
            selected, running = control, true
            break
        end
        if control.id == CS[surface.selectionKey] then
            remembered = control
        end
    end
    if not selected then
        selected, running = remembered or applicable[1], false
    end
    CS[surface.selectionKey] = selected.id

    local bar = EnsureBar(host, surface)
    bar._applicable = applicable
    ApplyBarState(bar, selected, running)

    host._cdcPreviewReserveBottom = BAR_RESERVE
    bar:Show()
    return selected, running
end

------------------------------------------------------------------------
-- Buttons workspace entry point. Called at the top of the buttons
-- preview's build closure, so it runs on every rebuild path (selection
-- change, panel switch, divider drag, preview toggle) and - critically -
-- BEFORE the mirror measures itself, since it owns the host's bottom
-- reserve.
------------------------------------------------------------------------

local function UpdatePreviewCommandCenter(host)
    if not host then
        return
    end

    local panelId, group, buttonIndex = ResolveContext()
    if not panelId then
        HideBar(host)
        return
    end

    local displayMode = group.displayMode or "icons"
    local applicable = {}
    for _, control in ipairs(CONTROLS) do
        if ControlApplies(control, group, displayMode, buttonIndex) then
            applicable[#applicable + 1] = control
        end
    end

    -- On the anchor panel the canvas draws the attached bar lanes and
    -- their settings open below the divider, so the bars' previews belong
    -- in this menu too - the rule everywhere is that the chooser lists
    -- every preview for what the canvas is showing. Appended after the
    -- panel groups, under their own object headers.
    if ST._ShouldUseUnifiedAnchorPreview and ST._ShouldUseUnifiedAnchorPreview(panelId) then
        for _, control in ipairs(CollectObjectControls(GetAnchorLaneObjects())) do
            applicable[#applicable + 1] = control
        end
    end

    if #applicable == 0 then
        HideBar(host)
        return
    end

    MigrateRunningPreview(panelId, buttonIndex, applicable)

    local _, running = UpdateBar(host, BUTTONS_SURFACE, applicable)
    -- Read by the migration above on the next pass, since the selection
    -- seam clears previews before we get to look at live state.
    CS.previewCommandCenterWasRunning = running
end

------------------------------------------------------------------------
-- Resources / Cast Bar & Unit Frames entry point. Both homes share one
-- preview host and one renderer, so they share one bar; what differs is
-- which objects that home configures.
------------------------------------------------------------------------

local function UpdateResourcesPreviewCommandCenter(host)
    if not host then
        return
    end

    -- The health bar is a Resources-workspace object; the cast bar is
    -- drawn on both homes and owns one of them. Custom bars are Resources
    -- objects too — their aura previews live here.
    --
    -- The cast bar only qualifies while it is attached, because that is when
    -- the canvas draws it as a lane and previews render on the canvas. A cast
    -- bar on its own independent anchor has no canvas representation at all,
    -- so offering the control there would name a preview nothing can show.
    local objects = {
        cast = GetAnchorLaneObjects().cast == true,
        health = CS.resourcesEntrySelected == true,
        customBars = CS.resourcesEntrySelected == true or CS.selectedCustomBarId ~= nil,
    }
    UpdateBar(host, RESOURCES_SURFACE, CollectObjectControls(objects))
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._UpdatePreviewCommandCenter = UpdatePreviewCommandCenter
ST._UpdateResourcesPreviewCommandCenter = UpdateResourcesPreviewCommandCenter
