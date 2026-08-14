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
-- The glyph the settings-side advanced gears already wear
-- (ADVANCED_TOGGLE_ATLAS in Helpers.lua): this button opens the same side
-- panel they do. Restated rather than imported because Helpers loads after
-- this file.
local GEAR_ATLAS = "QuestLog-icon-setting"
local GEAR_GAP = 4
-- Blizzard's own small inline book glyph (the quest log's campaign lore book),
-- the only one that still reads as a book at this size. Unlike the flat gear
-- beside it this is coloured art, and it keeps its own colours at rest for
-- readability; ApplySpellbookTint desaturates it only under the gold open
-- tint, so the two states still read apart at a glance.
local SPELLBOOK_ATLAS = "campaign-questlog-lorebook"
local SPELLBOOK_ICON_WIDTH = 15
local SPELLBOOK_ICON_HEIGHT = 13
local SPELLBOOK_RIGHT_INSET = 4

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

-- Pandemic recolor stand-in (PTR 8 Phase 2): its own flag; the canvas
-- unions it into the Active Aura stand-in, since the recolor only exists
-- over the aura fill.
local function CustomBarPandemicPreview(cabConfig)
    return {
        groupScoped = true,
        IsActive = function()
            return CooldownCompanion:IsCustomAuraBarPandemicPreviewActive(cabConfig) == true
        end,
        SetActive = function(_, _, show)
            CooldownCompanion:SetCustomAuraBarPandemicPreview(cabConfig, show)
        end,
    }
end

-- Pandemic MARKER stand-in: decorates the duration text the Active Aura
-- stand-in writes, so the canvas unions it into that flag too.
local function CustomBarMarkerPreview(cabConfig)
    return {
        groupScoped = true,
        IsActive = function()
            return CooldownCompanion:IsCustomAuraBarMarkerPreviewActive(cabConfig) == true
        end,
        SetActive = function(_, _, show)
            CooldownCompanion:SetCustomAuraBarMarkerPreview(cabConfig, show)
        end,
    }
end

-- Spell custom-bar cooldown stand-in: the mid-cooldown look on the config
-- canvas — fill progress, cooldown/recharge colour, duration text and the
-- charge readout. One flag holding a KIND rather than two flags: the two
-- looks are the same fabrication in different colours, and only one can
-- ever run.
local function CustomBarCooldownPreview(cabConfig, kind)
    return {
        groupScoped = true,
        IsActive = function()
            return CooldownCompanion:GetCustomBarCooldownPreviewKind(cabConfig) == kind
        end,
        SetActive = function(_, _, show)
            CooldownCompanion:SetCustomBarCooldownPreview(cabConfig, show and kind or nil)
        end,
    }
end

local function ResourceAuraPreview(powerType)
    return {
        groupScoped = true,
        IsActive = function()
            return CooldownCompanion:IsResourceAuraActivePreviewActive(powerType) == true
        end,
        SetActive = function(_, _, show)
            CooldownCompanion:SetResourceAuraActivePreview(powerType, show)
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

-- Does this entry have a count the charge previews can stand in for? The two
-- mirrors disagree, deliberately: the icon mirror renders the charge states
-- for anything with charge behavior (real charges, a Blizzard display or use
-- count), while the Bar mirror gates on real charges alone
-- (UsesConfigOnlyBarChargeBehavior in ButtonPanelPreview). Asking the same
-- question the renderer for THIS display mode will ask is what keeps the
-- chooser from offering a preview that draws nothing.
local function UsesChargePreviewBehavior(buttonData, displayMode)
    if displayMode == "bars" then
        local barUsesCharges = ST._UsesConfigOnlyBarChargeBehavior
        return barUsesCharges ~= nil and barUsesCharges(buttonData) == true
    end
    local usesCharges = CooldownCompanion.UsesChargeBehavior
    return usesCharges ~= nil and usesCharges(buttonData) == true
end

-- Same scoping rule as SectionApplies: with a single entry selected that
-- entry must qualify, at panel scope at least one entry must.
local function ChargeEntryApplies(group, displayMode, buttonIndex)
    local buttons = group.buttons or {}
    if buttonIndex then
        return UsesChargePreviewBehavior(buttons[buttonIndex], displayMode)
    end
    for _, buttonData in ipairs(buttons) do
        if UsesChargePreviewBehavior(buttonData, displayMode) then
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

-- Effective pandemic enable (PTR 8 visuals): the per-entry override wins,
-- else the effective style's explicit-true key — the same resolution the
-- live bind gate and the config mirror perform, so the control is never
-- offered where the preview renders nothing nor hidden at entry scope
-- where the live rig actually renders.
local function PandemicEffectEnabled(group, buttonIndex)
    local buttonData = buttonIndex and (group.buttons or {})[buttonIndex] or nil
    if buttonData and buttonData.pandemicEffect ~= nil then
        return buttonData.pandemicEffect == true
    end
    return StyleFlagEnabled(group, buttonIndex, "pandemicEffectEnabled")
end

-- Effective marker enable, the same three-step resolution the live bind gate
-- performs (AuraDisplay's IsPandemicMarkerWanted): the panel kill switch, then
-- the per-entry override, then the tracked-unit default. Deliberately separate
-- from PandemicEffectEnabled above — the marker and the effect are independent
-- settings, and the effect is off by default, so sharing that gate would hide
-- the marker preview on almost every panel.
local function PandemicMarkerEnabled(group, buttonIndex)
    if ResolveTargetStyle(group, buttonIndex).pandemicMarkerEnabled == false then
        return false
    end
    local buttonData = buttonIndex and (group.buttons or {})[buttonIndex] or nil
    if buttonData and buttonData.pandemicMarker ~= nil then
        return buttonData.pandemicMarker == true
    end
    -- Panel scope has no single entry to read a unit from, so the control
    -- stays offered and the stand-in decides per entry.
    if not buttonData then
        return true
    end
    return (buttonData.auraUnit or "player") == "target"
end

local function TextureIndicatorEnabled(group, indicatorKey)
    -- Read-only: never pass createIfMissing here, a mere preview refresh
    -- must not write indicator tables into the profile.
    local indicators = CooldownCompanion.GetTexturePanelIndicatorSettings
        and CooldownCompanion:GetTexturePanelIndicatorSettings(group)
    local config = type(indicators) == "table" and indicators[indicatorKey] or nil
    return type(config) == "table" and config.enabled and true or false
end

local function TextureAuraDisplayEnabled(group)
    local buttonData = group and group.buttons and group.buttons[1] or nil
    return CooldownCompanion.IsTexturePanelAuraDisplayEnabled
        and CooldownCompanion:IsTexturePanelAuraDisplayEnabled(group, buttonData)
        or false
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
-- The cooldown previews follow the aura pattern (owner ruling 2026-08-08):
-- on icons and bars the old single "Preview Cooldown State" is split into
-- the Cooldown Text and Cooldown Swipe readouts, each rendering only what
-- it names (the swipe entry keeps the rest of the state look - fill,
-- desaturation, tint - since those have no other preview). Text and
-- rotation assistant panels keep the single state entry: their cooldown
-- look is indivisible.
------------------------------------------------------------------------

local GROUP_EFFECTS = "Effects"
local GROUP_STATES = "Button States"
local GROUP_READOUTS = "Text & Timers"

------------------------------------------------------------------------
-- Where each preview's settings live (the quick-access gear)
--
-- `settings` is either one route or a route per display mode. A route names
-- the tab to show and, when the setting has an advanced side panel, the
-- `AddAdvancedToggle` key that opens it - the gear queues that key and lets
-- the rebuild pop it open, exactly as the shipped enable-then-open callers
-- do. Routes with no key navigate to the tab and stop.
--
-- A gear opens at most ONE advanced panel (owner ruling 2026-08-08,
-- retiring the 2026-07-26 open-every-panel shape along with the combined
-- cooldown preview that needed it). A route may carry `resolveKey` instead
-- of `key` when which panel owns the setting depends on the target's
-- effective style - the cooldown swipe gear follows the icon fill timer's
-- ownership of the cooldown visual.
--
-- `lensSection` is only set where the style section this preview shows differs
-- from the control's own `section`; the gear reads one or the other to find
-- the section's home tab and open the collapsible it is drawn in.
------------------------------------------------------------------------

-- The conditional states share a shape: their visuals live on the Indicators
-- tab wherever there is one. Text panels have none (GroupSettingsHost builds
-- the tab list without it), so they land on Appearance - which is where a
-- text panel's state styling lives anyway.
local function StateRoute(advancedKey)
    -- With an advanced key the queue resolves the section for us
    -- (ST._INDICATORS_SECTION_BY_ADVANCED_KEY maps it to "effects_states");
    -- with none there is nothing to resolve from, so name the section on the
    -- route or the gear lands on a collapsed header with nothing under it.
    local statesSection = (advancedKey == nil) and "effects_states" or nil
    return {
        icons = { tab = "effects", key = advancedKey, uncollapse = statesSection },
        bars = { tab = "effects", key = advancedKey, uncollapse = statesSection },
        rotationAssistant = { tab = "effects", key = advancedKey, uncollapse = statesSection },
        text = { tab = "appearance" },
    }
end

-- Text settings sit inside a collapsible on both destinations ("Text" in
-- icons Appearance, "Text & Icon" in bars), so the gear opens it on the way
-- past - a queued advanced key whose checkbox is never built would expire
-- silently.
local ICON_TEXT_SECTION = "appearance_text"
local BAR_TEXT_SECTION = "barappearance_textIcon"

local function TextRoute(iconKey, barKey)
    return {
        icons = { tab = "appearance", key = iconKey, uncollapse = ICON_TEXT_SECTION },
        bars = { tab = "appearance", key = barKey, uncollapse = BAR_TEXT_SECTION },
    }
end

-- The three charge states are three looks at one setting, so they share one
-- destination.
local CHARGE_ROUTE = TextRoute("chargeText", "barChargeText")

local CONTROLS = {
    {
        id = "procGlow",
        label = "Preview Proc Glow",
        group = GROUP_EFFECTS,
        modes = { icons = true },
        section = "procGlow",
        glowStyleKey = "procGlowStyle",
        settings = { tab = "effects", key = "procGlow" },
        preview = FlagPreview("_procGlowPreview", "SetProcGlowPreview", "SetGroupProcGlowPreview"),
    },
    {
        id = "auraGlow",
        label = "Preview Aura Glow",
        group = GROUP_EFFECTS,
        modes = { icons = true },
        section = "auraIndicator",
        glowStyleKey = "auraGlowStyle",
        settings = { tab = "effects", key = "auraGlow" },
        preview = FlagPreview("_auraGlowPreview", "SetAuraGlowPreview", "SetGroupAuraGlowPreview"),
    },
    {
        id = "pandemicGlow",
        label = "Preview Pandemic Effect",
        group = GROUP_EFFECTS,
        modes = { icons = true },
        section = "pandemic",
        requiresPandemicEffect = true,
        settings = { tab = "effects", key = "pandemicGlow" },
        preview = FlagPreview("_pandemicPreview", "SetPandemicPreview", "SetGroupPandemicPreview"),
    },
    {
        id = "readyGlow",
        label = "Preview Ready Glow Style",
        group = GROUP_EFFECTS,
        modes = { icons = true },
        section = "readyGlow",
        glowStyleKey = "readyGlowStyle",
        settings = { tab = "effects", key = "readyGlow" },
        preview = FlagPreview("_readyGlowPreview", "SetReadyGlowPreview", "SetGroupReadyGlowPreview"),
    },
    {
        id = "keyPressHighlight",
        label = "Preview Key Press Highlight",
        group = GROUP_EFFECTS,
        modes = { icons = true },
        section = "keyPressHighlight",
        glowStyleKey = "keyPressHighlightStyle",
        settings = { tab = "effects", key = "keyPressHighlight" },
        preview = GroupOnlyFlagPreview("_keyPressHighlightPreview", "SetGroupKeyPressHighlightPreview"),
    },
    {
        id = "barActiveAura",
        label = "Preview Active Aura Indicator",
        group = GROUP_EFFECTS,
        modes = { bars = true },
        section = "barActiveAura",
        requiresBarAuraIndicator = true,
        settings = { tab = "effects", key = "barActiveAura" },
        preview = FlagPreview("_barAuraEffectPreview", "SetBarAuraEffectPreview", "SetGroupBarAuraEffectPreview"),
    },
    {
        id = "barPandemic",
        label = "Preview Pandemic Color",
        group = GROUP_EFFECTS,
        modes = { bars = true },
        section = "pandemic",
        requiresPandemicEffect = true,
        -- No advanced key exists for the bars pandemic FILL rows (enable +
        -- color only), so the gear lands on the Effects tab with the Pandemic
        -- section forced open by name — the rows live inside it. The section
        -- constant is GroupTabs' (EFFECTS_PANDEMIC_SECTION); bars shares it.
        settings = { tab = "effects", uncollapse = "effects_pandemic" },
        preview = FlagPreview("_pandemicPreview", "SetBarPandemicPreview", "SetGroupBarPandemicPreview"),
    },
    {
        id = "textureProc",
        label = "Preview Proc Effect",
        group = GROUP_EFFECTS,
        modes = { textures = true },
        indicatorKey = "proc",
        excludesTextureAuraDisplay = true,
        settings = { tab = "effects", key = "textureIndicator_proc" },
        preview = TextureIndicatorPreview("proc"),
    },
    {
        id = "textureAura",
        label = "Preview Aura Effect",
        group = GROUP_EFFECTS,
        modes = { textures = true },
        indicatorKey = "aura",
        requiresTextureAuraDisplay = true,
        -- Aura-controlled Texture options live directly in the Indicators
        -- section; there is no advanced side panel to open.
        settings = { tab = "effects", uncollapse = "effects_textureIndicators" },
        preview = TextureIndicatorPreview("aura"),
    },
    {
        id = "textureReady",
        label = "Preview Ready Effect",
        group = GROUP_EFFECTS,
        modes = { textures = true },
        indicatorKey = "ready",
        excludesTextureAuraDisplay = true,
        settings = { tab = "effects", key = "textureIndicator_ready" },
        preview = TextureIndicatorPreview("ready"),
    },
    {
        id = "textureUnusable",
        label = "Preview Unusable Effect",
        group = GROUP_EFFECTS,
        modes = { textures = true },
        indicatorKey = "unusable",
        excludesTextureAuraDisplay = true,
        settings = { tab = "effects", key = "textureIndicator_unusable" },
        preview = TextureIndicatorPreview("unusable"),
    },
    {
        id = "triggerEffects",
        label = "Preview Effects",
        group = GROUP_EFFECTS,
        modes = { trigger = true },
        requiresTriggerEffect = true,
        -- No key: the preview plays every enabled trigger effect at once, and
        -- each has its own advanced panel. The tab draws them inside one
        -- collapsible section, so the gear opens that on the way past.
        settings = { tab = "effects", uncollapse = "effects_triggerEffects" },
        preview = TriggerEffectsPreview,
    },

    {
        id = "cooldown",
        label = "Preview Cooldown State",
        group = GROUP_STATES,
        -- Icons and bars split this into the Cooldown Text / Cooldown Swipe
        -- readouts below (owner ruling 2026-08-08); the modes whose cooldown
        -- look is indivisible keep the state entry. The rotation assistant's
        -- cooldown settings sit inside its collapsible "Timers" section; text
        -- panels have no advanced panel for cooldown visuals at all, so both
        -- routes are tab-only.
        modes = { text = true, rotationAssistant = true },
        settings = {
            rotationAssistant = { tab = "effects", uncollapse = "effects_timers" },
            text = { tab = "appearance" },
        },
        preview = ConditionalPreview("cooldown"),
    },
    {
        id = "unusable",
        label = "Preview Unusable State",
        group = GROUP_STATES,
        modes = { icons = true, bars = true, text = true, rotationAssistant = true },
        styleKey = "showUnusable",
        lensSection = "unusableDimming",
        settings = StateRoute("unusableVisual"),
        preview = ConditionalPreview("unusable"),
    },
    {
        id = "outOfRange",
        label = "Preview Out of Range State",
        group = GROUP_STATES,
        modes = { icons = true, text = true, rotationAssistant = true },
        styleKey = "showOutOfRange",
        lensSection = "showOutOfRange",
        settings = StateRoute(nil),
        preview = ConditionalPreview("out_of_range"),
    },
    {
        id = "lossOfControl",
        label = "Preview Loss of Control",
        group = GROUP_STATES,
        modes = { icons = true, bars = true, rotationAssistant = true },
        section = "lossOfControl",
        styleKey = "showLossOfControl",
        settings = StateRoute(nil),
        preview = ConditionalPreview("loss_of_control"),
    },

    {
        id = "cooldownText",
        label = "Preview Cooldown Text",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "cooldownText",
        styleKeyDefaultOn = "showCooldownText",
        settings = TextRoute("cooldownText", "barCooldownText"),
        preview = ConditionalPreview("cooldown_text"),
    },
    {
        id = "cooldownSwipe",
        label = "Preview Cooldown Swipe",
        group = GROUP_READOUTS,
        modes = { icons = true },
        -- The state look minus the countdown text (owner ruling 2026-08-08):
        -- desaturation and the cooldown tint preview here and nowhere else,
        -- so the entry carries no style gate - offered even with the swipe
        -- itself switched off, exactly as the state entry it replaced was.
        settings = {
            tab = "effects",
            uncollapse = "effects_timers",
            -- The icon fill timer owns the cooldown visual (and disables the
            -- swipe checkbox and its gear) while active, so the one panel
            -- this gear opens moves with that ownership. A nil key (swipe
            -- explicitly off, no fill) navigates to the tab and stops.
            resolveKey = function(group, buttonIndex)
                local style = ResolveTargetStyle(group, buttonIndex)
                if style.iconFillEnabled == true and group.masqueEnabled ~= true then
                    return "iconFillTimer"
                end
                if style.showCooldownSwipe ~= false then
                    return "cooldownSwipe"
                end
                return nil
            end,
        },
        preview = ConditionalPreview("cooldown_swipe"),
    },
    {
        id = "auraDurationText",
        label = "Preview Aura Duration Text",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "auraText",
        styleKeyDefaultOn = "showAuraText",
        settings = TextRoute("auraText", "barAuraText"),
        preview = ConditionalPreview("aura_duration_text"),
    },
    {
        id = "pandemicMarker",
        label = "Preview Pandemic Marker",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        -- Sits with the readouts, not the effects: the marker IS the duration
        -- text, dressed. Its settings live in the Indicators tab's Pandemic
        -- section, so this is a two-mode effects route rather than TextRoute's
        -- Appearance one; both gear keys are in the gear-to-section map, which
        -- is what uncollapses the header.
        section = "pandemic",
        styleKeyDefaultOn = "showAuraText",
        requiresPandemicMarker = true,
        settings = {
            icons = { tab = "effects", key = "pandemicMarker" },
            bars = { tab = "effects", key = "barPandemicMarker" },
        },
        preview = ConditionalPreview("pandemic_marker"),
    },
    {
        id = "auraStackText",
        label = "Preview Aura Stack Text",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "auraStackText",
        styleKeyDefaultOn = "showAuraStackText",
        settings = TextRoute("auraStackText", "barAuraStackText"),
        preview = ConditionalPreview("aura_stack_text"),
    },
    {
        id = "auraDurationSwipe",
        label = "Preview Aura Duration Swipe",
        group = GROUP_READOUTS,
        modes = { icons = true },
        section = "auraDurationSwipe",
        styleKeyDefaultOn = "showAuraDurationSwipe",
        settings = { tab = "effects", key = "auraDurationSwipe" },
        preview = ConditionalPreview("aura_duration_swipe"),
    },
    {
        id = "chargeFull",
        label = "Preview Max Charges",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "chargeText",
        styleKeyDefaultOn = "showChargeText",
        requiresChargeEntry = true,
        settings = CHARGE_ROUTE,
        preview = ConditionalPreview("charge_full"),
    },
    {
        id = "chargeMissing",
        label = "Preview Missing Charges",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "chargeText",
        styleKeyDefaultOn = "showChargeText",
        requiresChargeEntry = true,
        settings = CHARGE_ROUTE,
        preview = ConditionalPreview("charge_missing"),
    },
    {
        id = "chargeZero",
        label = "Preview Zero Charges",
        group = GROUP_READOUTS,
        modes = { icons = true, bars = true },
        section = "chargeText",
        styleKeyDefaultOn = "showChargeText",
        requiresChargeEntry = true,
        settings = CHARGE_ROUTE,
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
    if control.requiresPandemicEffect and not PandemicEffectEnabled(group, buttonIndex) then
        return false
    end
    if control.requiresPandemicMarker and not PandemicMarkerEnabled(group, buttonIndex) then
        return false
    end
    if control.indicatorKey and not TextureIndicatorEnabled(group, control.indicatorKey) then
        return false
    end
    if control.requiresTextureAuraDisplay and not TextureAuraDisplayEnabled(group) then
        return false
    end
    if control.excludesTextureAuraDisplay and TextureAuraDisplayEnabled(group) then
        return false
    end
    if control.requiresTriggerEffect and not AnyTriggerEffectEnabled(group) then
        return false
    end
    if control.requiresChargeEntry and not ChargeEntryApplies(group, displayMode, buttonIndex) then
        return false
    end
    return true
end

-- The style section this preview is showing, or nil for previews that are not
-- a section's look (the object previews, the texture indicators).
local function ControlSectionId(control)
    return control.lensSection or control.section
end

-- Where the gear goes for the control the chooser is naming. Returns nil
-- when the preview has no settings destination, which is what hides the
-- button.
--
-- One destination whatever is selected: the styling tabs ARE the lens onto a
-- selected entry, so the tab that draws the section is the right landing
-- whether that entry customizes it, inherits it, or nothing is selected at
-- all. What changes with the selection is only whether the section can be
-- edited there, and the section's own scope chrome says that.
local function ResolveGearRoute(control, displayMode)
    local settings = control.settings
    if type(settings) ~= "table" then
        return nil
    end
    -- One route, or one per display mode.
    if settings.tab or settings.object then
        return settings
    end
    return displayMode and settings[displayMode] or nil
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

-- Does this resource have an overlay that would render? The same three
-- questions the collector asks before it builds a want: the resource is
-- on, the overlay is enabled for this spec, and an aura is actually set.
local function ResourceAuraOverlayConfigured(settings, powerType)
    if powerType == RB.RESOURCE_HEALTH then
        return false
    end
    if not (RB.IsResourceEnabled and RB.IsResourceEnabled(powerType, settings)) then
        return false
    end
    local resource = settings.resources and settings.resources[powerType]
    if not (type(resource) == "table"
        and RB.IsResourceAuraOverlayEnabled
        and RB.IsResourceAuraOverlayEnabled(resource)) then
        return false
    end
    local entry = RB.GetActiveResourceAuraEntry and RB.GetActiveResourceAuraEntry(resource)
    local spellID = type(entry) == "table" and tonumber(entry.auraColorSpellID) or nil
    return spellID ~= nil and spellID > 0
end

local function CastBarEnabled()
    local settings = CooldownCompanion.GetCastBarSettings
        and CooldownCompanion:GetCastBarSettings()
    return settings ~= nil and settings.enabled == true
end

-- Does a canvas cast lane exist ANYWHERE for the current configuration?
-- Distinct from "is the control offered on this surface": navigating away
-- from a home must not stop a running preview, but the cast bar being
-- disabled or moved to its own anchor leaves the preview with nothing to
-- render on, and it would silently resume when the setting came back.
local function HasCastPreviewDestination()
    local settings = CooldownCompanion.GetCastBarSettings
        and CooldownCompanion:GetCastBarSettings()
    local IsTruthyConfigFlag = RB and RB.IsTruthyConfigFlag
    return settings ~= nil
        and settings.enabled == true
        and IsTruthyConfigFlag ~= nil
        and not IsTruthyConfigFlag(settings.independentAnchorEnabled)
end

local function StopStrandedCastPreview()
    if HasCastPreviewDestination() then return end
    if CooldownCompanion:IsCastBarPreviewActive() then
        CooldownCompanion:StopCastBarPreview()
    end
end

local OBJECT_CONTROLS = {
    {
        id = "healthAbsorbs",
        label = "Preview Absorbs",
        group = GROUP_HEALTH_BAR,
        object = "health",
        Applies = function(healthConfig) return HealthEffectEnabled(healthConfig, "showAbsorbs") end,
        settings = { object = "health", key = "healthAbsorbs" },
        preview = HealthEffectPreview("absorbs"),
    },
    {
        id = "healthHealAbsorbs",
        label = "Preview Healing Absorbs",
        group = GROUP_HEALTH_BAR,
        object = "health",
        Applies = function(healthConfig) return HealthEffectEnabled(healthConfig, "showHealAbsorbs") end,
        settings = { object = "health", key = "healthHealAbsorbs" },
        preview = HealthEffectPreview("healAbsorbs"),
    },
    {
        id = "healthIncomingHeals",
        label = "Preview Incoming Heals",
        group = GROUP_HEALTH_BAR,
        object = "health",
        Applies = function(healthConfig) return HealthEffectEnabled(healthConfig, "showIncomingHeals") end,
        settings = { object = "health", key = "healthIncomingHeals" },
        preview = HealthEffectPreview("incomingHeals"),
    },
    {
        id = "healthLowHealthAlert",
        label = "Preview Low Health Alert",
        group = GROUP_HEALTH_BAR,
        object = "health",
        Applies = function(healthConfig) return HealthEffectEnabled(healthConfig, "showLowHealthAlert") end,
        settings = { object = "health", key = "healthLowHealthAlert" },
        preview = HealthEffectPreview("lowHealthAlert"),
    },
    {
        id = "castBar",
        label = "Preview Cast Bar",
        group = GROUP_CAST_BAR,
        object = "cast",
        Applies = CastBarEnabled,
        -- Tab only: the preview is the whole bar, so its home is the cast
        -- bar's Appearance tab rather than any one advanced panel.
        settings = { object = "cast" },
        preview = CastBarPreview,
    },
}

-- Does this spell custom bar track a charge spell? Decides whether the
-- recharge look exists at all, and which label the cooldown entry wears
-- (zero charges IS the cooldown colour on a charge spell). The shared
-- resolver (RB.GetCustomBarReadyChargeCount), which the canvas's charge
-- readout and its recharge-preview gate also use — split answers would let
-- the entries offered and the stand-in drawn disagree.
local function CustomBarMaxCharges(cab)
    if not (RB and RB.GetCustomBarReadyChargeCount) then return nil end
    return RB.GetCustomBarReadyChargeCount(cab)
end

-- Which objects a surface hosts. The homes list the objects that
-- workspace configures; the buttons workspace lists the bars its unified
-- anchor preview actually draws as lanes, which is also exactly when a
-- bar's settings can be open below the divider there.
local function CollectObjectControls(objects)
    local applicable = {}
    StopStrandedCastPreview()
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
                local isSpellBar = type(cab) == "table" and cab.entryType == "spell"
                local auraTracked = type(cab) == "table"
                    and (not isSpellBar or cab.auraTracking == true)
                if type(cab) == "table" and CooldownCompanion:IsCustomBarRuntimeEligible(cab) then
                    local name = cab.label
                    if not name or name == "" then
                        name = C_Spell.GetSpellName(tonumber(cab.spellID)) or "Custom Bar"
                    end
                    -- The cooldown looks, spell bars only (an aura bar has no
                    -- cooldown leg at all). Listed before the aura entries:
                    -- the cooldown is the bar's base render, the aura display
                    -- occludes it. On a charge spell the cooldown colour is
                    -- the zero-charges look, so the entry says so, and the
                    -- recharge look exists only there.
                    if isSpellBar then
                        local maxCharges = CustomBarMaxCharges(cab)
                        -- Both looks share the bar's Colors section, so the
                        -- gear route is one shape.
                        local cooldownRoute = {
                            object = "customBarAura",
                            customBarId = cab.customBarId,
                            appearanceSection = "colors",
                        }
                        applicable[#applicable + 1] = {
                            id = "customBarCooldown_" .. tostring(cab.customBarId),
                            label = maxCharges and "Preview Zero Charges" or "Preview Cooldown",
                            group = "Custom Bar: " .. name,
                            object = "customBars",
                            settings = cooldownRoute,
                            preview = CustomBarCooldownPreview(cab, "cooldown"),
                        }
                        if maxCharges then
                            applicable[#applicable + 1] = {
                                id = "customBarRecharge_" .. tostring(cab.customBarId),
                                label = "Preview Recharging",
                                group = "Custom Bar: " .. name,
                                object = "customBars",
                                settings = cooldownRoute,
                                preview = CustomBarCooldownPreview(cab, "recharge"),
                            }
                        end
                    end
                    if auraTracked then
                        applicable[#applicable + 1] = {
                            id = "customBarAura_" .. tostring(cab.customBarId),
                            label = "Preview Active Aura",
                            group = "Custom Bar: " .. name,
                            object = "customBars",
                            settings = {
                                object = "customBarAura",
                                customBarId = cab.customBarId,
                                -- The bar's Aura tab only exists for a spell
                                -- entry (GetCustomBarEntryTabs).
                                auraTab = cab.spellID ~= nil,
                            },
                            preview = CustomBarAuraPreview(cab),
                        }
                        -- Offered exactly while the entry's own enable is on
                        -- (the same honesty rule as requiresPandemicEffect on
                        -- the panel controls).
                        if cab.pandemicEffect == true then
                            applicable[#applicable + 1] = {
                                id = "customBarPandemic_" .. tostring(cab.customBarId),
                                label = "Preview Pandemic Color",
                                group = "Custom Bar: " .. name,
                                object = "customBars",
                                settings = {
                                    object = "customBarAura",
                                    customBarId = cab.customBarId,
                                    auraTab = cab.spellID ~= nil,
                                },
                                preview = CustomBarPandemicPreview(cab),
                            }
                        end
                        -- Same honesty rule, resolved through the shared marker
                        -- gate: the panel kill switch, then this bar's own switch,
                        -- then the tracked-unit default. The canvas union must
                        -- agree with this or the stand-in strands armed.
                        if CooldownCompanion:IsPandemicMarkerPreviewWanted(cab, cab) then
                            applicable[#applicable + 1] = {
                                id = "customBarPandemicMarker_" .. tostring(cab.customBarId),
                                label = "Preview Pandemic Marker",
                                group = "Custom Bar: " .. name,
                                object = "customBars",
                                settings = {
                                    object = "customBarAura",
                                    customBarId = cab.customBarId,
                                    auraTab = cab.spellID ~= nil,
                                },
                                preview = CustomBarMarkerPreview(cab),
                            }
                        end
                    end
                end
            end
        end
    end

    -- Per-resource groups (the aura pass, Phase 2): one group per resource
    -- whose overlay is configured, built the same way as the custom-bar
    -- groups above, and keyed by power type — the identity that survives
    -- rebuilds. The CANVAS owns which resources have a lane on screen (its
    -- choice of list depends on the anchor mode), so ask it rather than
    -- re-derive: enumerating independently here put the menu out of step
    -- with the canvas in both directions, offering toggles whose lane was
    -- absent and dropping toggles whose lane was drawn.
    if objects.resourceAuras then
        local settings = CooldownCompanion.GetResourceBarSettings
            and CooldownCompanion:GetResourceBarSettings()
        -- Lazy: this file loads before the ConfigSettings modules.
        local LanePowerTypes = ST._ResourcesPreviewResourceLanePowerTypes
        if settings and settings.enabled == true and LanePowerTypes then
            for _, powerType in ipairs(LanePowerTypes()) do
                if ResourceAuraOverlayConfigured(settings, powerType) then
                    applicable[#applicable + 1] = {
                        id = "resourceAura_" .. tostring(powerType),
                        label = "Preview Active Aura",
                        group = RB.POWER_NAMES[powerType] or ("Power " .. powerType),
                        object = "resourceAuras",
                        settings = { object = "resourceAura", powerType = powerType },
                        preview = ResourceAuraPreview(powerType),
                    }
                end
            end
        end
    end
    return applicable
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
-- The quick-access gear: jump to the settings for the chosen preview
--
-- Two halves. Moving the config surface is plain selection/tab state, the
-- same writes the navigator and tab rows make. Opening the advanced side
-- panel rides `QueueAdvancedSettingsPanelOpen`: the key is queued, and the
-- rebuild pops the panel open when it reaches the matching gear. That is
-- the shipped seam (the enable-a-setting-and-open-its-panel callers use it),
-- and it is why every piece of navigation state must be written BEFORE the
-- queue - the queue snapshots the context and the consume side drops it if
-- the context has moved on.
------------------------------------------------------------------------

-- Which cluster of the unified tab row owns the settings surface at the
-- destination: "primary" for a module/panel tab, "detail" for one belonging
-- to a selected entry or bar.
local function SetRowScope(scope)
    if ST._UnifiedRowSetScope then
        ST._UnifiedRowSetScope(scope)
    end
end

-- Objects live on the two homes rather than in the buttons workspace, so
-- their routes select a destination first. Returns the surface whose canvas
-- shows the destination, which is the one to repaint afterwards.
local function ApplyObjectRoute(route)
    local RBP = ST._RBP

    if route.object == "cast" then
        if not CS.barsEntrySelected and ST._SelectConfigBarsEntry then
            ST._SelectConfigBarsEntry()
        end
        if ST._SelectConfigCastFramesItem then
            ST._SelectConfigCastFramesItem("castbar")
        end
        CS.castBarHomeTab = "appearance"
        SetRowScope("detail")
        return RESOURCES_SURFACE
    end

    -- Everything else is a Resources-home object. Selecting the home first
    -- matters: it always drops any object selection, so a bar selected below
    -- would be cleared right after we made it.
    if not CS.barsEntrySelected and ST._SelectConfigBarsEntry then
        ST._SelectConfigBarsEntry()
    end

    if route.object == "health" then
        -- A module tab rather than a bar: at primary scope it owns the
        -- surface even while a bar stays selected beside it. The cast/frames
        -- item is cleared here because this is the only Resources-home route
        -- that selects nothing of its own - the resource and custom routes
        -- get the clear from their State.lua setters.
        CS.castFramesSelectedItem = nil
        CS.resourcesSettingsTab = "health"
        SetRowScope("primary")
        if RBP then
            RBP.collapsedSections["rb_health_effects"] = nil
        end
    elseif route.object == "customBarAura" then
        if ST._SelectConfigCustomBar then
            ST._SelectConfigCustomBar(route.customBarId)
        end
        if ST._SetConfigCustomBarSettingsTab then
            ST._SetConfigCustomBarSettingsTab(route.auraTab and "aura" or "appearance")
        end
        SetRowScope("detail")
        -- Both halves of the Aura tab are collapsible and keyed per bar, so a
        -- route that lands there has to open the two it means: the tracking
        -- section and the effects this preview is showing. An Appearance-tab
        -- route names its own section instead (the cooldown previews land on
        -- Colors).
        if RBP then
            local barKey = tostring(route.customBarId)
            if route.auraTab then
                RBP.collapsedSections["cab_aura_" .. barKey] = nil
                RBP.collapsedSections["cab_aura_effects_" .. barKey] = nil
            end
            if route.appearanceSection then
                RBP.collapsedSections["cab_" .. route.appearanceSection .. "_" .. barKey] = nil
            end
        end
    elseif route.object == "resourceAura" then
        -- Always the CURRENT spec: the overlay the preview draws is resolved
        -- for it (GetActiveResourceAuraEntry), so a resource already selected
        -- but parked on another spec's tab would send the gear to settings
        -- that are not the ones being previewed.
        local specID = RBP and RBP.GetCurrentConfigSpecID() or nil
        if CS.selectedResourcePowerType ~= route.powerType then
            if ST._SelectConfigResource then
                ST._SelectConfigResource(route.powerType, { specID = specID })
            end
        elseif ST._SetConfigResourceSettingsSpecID then
            ST._SetConfigResourceSettingsSpecID(specID)
        end
        SetRowScope("detail")
        if RBP then
            RBP.collapsedSections["rb_aura_overlay_" .. tostring(route.powerType)] = nil
        end
    end

    return RESOURCES_SURFACE
end

-- Where the styling tabs DRAW this section: the tab that owns it in this
-- display mode, plus the collapse key of the collapsible it sits in. The
-- registry is stated by the tab builders themselves (ST._SECTION_HOME), keyed
-- by mode first, so a section drawn somewhere else on a bar panel than on an
-- icons one still resolves to the place the user will actually be looking.
-- A mode with no home for the section answers nil, and the route's own tab
-- constant carries the navigation as before.
local function ResolveSectionHome(sectionId)
    if not sectionId then
        return nil
    end
    local homes = ST._SECTION_HOME
    local _, group = ResolveContext()
    local byMode = homes and homes[(group and group.displayMode) or "icons"]
    return byMode and byMode[sectionId] or nil
end

-- Force one collapsible open, on BOTH sides of the style lens.
--
-- Which key a collapsible actually uses is ST._ResolveLensCollapseKey's call
-- (Helpers.lua): a section the selected entry cannot edit gets its OWN
-- lens-scoped key and opens collapsed the first time that key is seen. Which
-- side a given collapse key landed on is a per-tab fact - the same key names a
-- whole mixed section on one panel and one lens section on another - so this
-- opens both rather than guessing, and the sectionId handed to the resolver is
-- deliberately nil: a nil section resolves the lens-scoped variant under an
-- entry lens and the base key everywhere else, which is exactly the pair.
--
-- The lens key is set to FALSE, not nil. nil reads as "never seen", and the
-- resolver seeds that straight back to collapsed on the rebuild this
-- navigation is about to trigger.
local function ForceSectionOpen(collapseKey, lens, group)
    if not collapseKey then
        return
    end
    CS.collapsedSections[collapseKey] = nil
    local resolve = ST._ResolveLensCollapseKey
    local lensKey = resolve and resolve(lens, group, nil, collapseKey)
    if lensKey and lensKey ~= collapseKey then
        CS.collapsedSections[lensKey] = false
    end
end

-- The navigate-to-a-section core of ApplyGearRoute below, without the gear:
-- no advanced-panel queue, no route object, no preview to carry across. The
-- entry Settings pane's Customizations list clicks a section NAME and wants
-- exactly this - land on the tab that edits it, with the section unfolded.
--
-- ORDERING, same as the gear's: every navigation write lands BEFORE the
-- refresh. The rebuild reads CS.selectedTab / CS.panelSettingsTab and the
-- collapse table, so a refresh made first would build the surface the click
-- was leaving and then be told where to go.
--
-- Context comes from ResolveContext, not from the caller: the destination has
-- to be the panel the config is actually showing, and taking a group would let
-- a stale row navigate against one it is not on.
--
-- `opts.tab` is for a destination that is not an override section at all - the
-- text panel's Format tab, where the flat per-entry textFormat is edited.
--
-- Deliberately does NOT consult the home's `available` / `gearEnabled`
-- predicates. Every other route into here starts at a control that is on screen
-- (a preview gear must be visible to be clicked), so its section is drawn by
-- definition; the one caller that can name a section it cannot see - the
-- Customizations list - pre-gates on those predicates and never calls with an
-- unavailable destination.
--
-- `opts.advancedKey` additionally opens that section's advanced-settings panel
-- once the destination rebuilds, which is what the Customizations list's gear
-- adds over its name link. Queued in exactly the place the gear route queues it
-- (NavigateToPreviewSettings below): after every navigation write, before the
-- refresh. QueueAdvancedSettingsPanelOpen SNAPSHOTS the config context, and
-- that context reads CS.selectedTab / CS.panelSettingsTab, so a queue made any
-- earlier is stamped with the surface the click was leaving and expires against
-- a gear that never sees it.
local function NavigateToSectionHome(sectionId, opts)
    local _, group = ResolveContext()
    if not group then
        return false
    end

    local home = ResolveSectionHome(sectionId)
    local tab = (opts and opts.tab) or (home and home.tab)
    if not tab then
        return false
    end

    -- The inline texture browser takes over the settings area; leave it
    -- before landing somewhere underneath it.
    if CS.CancelPickAuraTexture then
        CS.CancelPickAuraTexture()
    end

    SetRowScope("primary")
    CS.selectedTab = tab
    CS.panelSettingsTab = tab
    -- A deliberate destination, so it outranks a display mode's own default
    -- landing tab.
    CS.panelSettingsTabExplicit = true
    if type(CS.collapsedSections) == "table" then
        local resolveLens = ST._ResolveStyleLens
        local lens = resolveLens and resolveLens(group) or nil
        ForceSectionOpen(home and home.collapseKey, lens, group)
    end

    -- Every write above is made; the rebuild below is what consumes this. The
    -- already-open guard is the gear route's, for the same reason: a panel still
    -- up on this key would be re-opened through the queue rather than left
    -- alone, and nothing here means "toggle".
    local advancedKey = opts and opts.advancedKey
    if advancedKey
        and CS.QueueAdvancedSettingsPanelOpen
        and not (CS.IsAdvancedSettingsPanelOpen and CS.IsAdvancedSettingsPanelOpen(advancedKey)) then
        CS.QueueAdvancedSettingsPanelOpen(advancedKey)
    end

    CooldownCompanion:RefreshConfigPanel()
    return true
end

-- `queueKey` is the key that is about to ride the queue, already resolved by
-- the caller - passed in so the uncollapse below only opens the section whose
-- gear actually has to build, not one the route merely names. `sectionId` is
-- the style section the preview shows, when it is one.
local function ApplyGearRoute(route, queueKey, sectionId)
    if route.object then
        return ApplyObjectRoute(route)
    end

    local home = ResolveSectionHome(sectionId)

    SetRowScope("primary")
    local tab = (home and home.tab) or route.tab
    CS.selectedTab = tab
    CS.panelSettingsTab = tab
    -- A deliberate destination, so it outranks a display mode's own default
    -- landing tab (text panels otherwise land on Format).
    CS.panelSettingsTabExplicit = true
    -- A collapsed section never builds its checkbox, and a queued key with
    -- no gear to consume it expires silently.
    if type(CS.collapsedSections) == "table" then
        -- The lens the section keys below are opened against - the same one the
        -- tab builder will resolve when it rebuilds a moment from now.
        local _, routeGroup = ResolveContext()
        local resolveLens = ST._ResolveStyleLens
        local lens = (routeGroup and resolveLens) and resolveLens(routeGroup) or nil

        -- Landing on the tab with the section collapsed shows a header and
        -- nothing else, so open it whether or not a key rides along: with an
        -- entry that only inherits the section there is no key at all, and the
        -- section's scope chrome is the whole point of arriving. A section the
        -- entry cannot edit at all folds itself by default under the lens, and
        -- the same reasoning applies harder there.
        ForceSectionOpen(home and home.collapseKey, lens, routeGroup)
        ForceSectionOpen(route.uncollapse, lens, routeGroup)
        -- Same rule, read off the key rather than named on the route: the
        -- Indicators tab collapses all three of its sections, and which one
        -- holds a given gear is GroupTabs' fact to state - it owns both the
        -- sections and the advanced keys - so the map lives there. Keys
        -- reached in a display mode that has no such section just clear one
        -- nothing uses.
        local sectionByKey = queueKey and ST._INDICATORS_SECTION_BY_ADVANCED_KEY
        ForceSectionOpen(sectionByKey and sectionByKey[queueKey], lens, routeGroup)
    end
    return BUTTONS_SURFACE
end

-- The one advanced key this route opens. Usually named statically (`key`);
-- a route may carry `resolveKey` instead when which panel owns the setting
-- depends on the target's effective style (the cooldown swipe gear follows
-- the icon fill timer's ownership of the cooldown visual). Resolved from
-- live selection state rather than carried on the bar: the same answer is
-- wanted at click time and at hover time, and the panel the gear acts on
-- never changes underneath either.
local function ResolveRouteAdvancedKey(route)
    if not route then
        return nil
    end
    if route.resolveKey then
        local _, group, buttonIndex = ResolveContext()
        if not group then
            return nil
        end
        return route.resolveKey(group, buttonIndex)
    end
    return route.key
end

-- Gold gear, gold tooltip: the command center's gear reads as "on" while
-- the panel behind this preview is up, which is also what the tint (read
-- off the window itself) shows.
local function IsRoutePanelOpen(route)
    if not CS.IsAdvancedSettingsPanelOpen then
        return false
    end
    local key = ResolveRouteAdvancedKey(route)
    return key ~= nil and CS.IsAdvancedSettingsPanelOpen(key) == true
end

-- Will the section's controls land INERT for the current selection? Under the
-- style lens a section the selected entry only inherits builds read-only, gear
-- included, so a queued advanced key would open a panel on controls that
-- cannot commit - or expire against a gear that was never enabled. Arriving on
-- the tab with the section open, where its Customize chrome explains the
-- state, is the whole answer there.
local function RouteSectionIsInert(sectionId)
    if not sectionId then
        return false
    end
    local resolveLens = ST._ResolveStyleLens
    local resolveSection = ST._ResolveLensSection
    if not (resolveLens and resolveSection) then
        return false
    end
    local _, group = ResolveContext()
    if not group then
        return false
    end
    local lens = resolveLens(group)
    -- Only the entry lens can be inert; panel and multi always write the panel
    -- style, and asking about them would misread a styleless panel as inert.
    if not (lens and lens.mode == "entry") then
        return false
    end
    local _, _, writeStyle = resolveSection(lens, group, sectionId)
    return writeStyle == nil
end

local function NavigateToPreviewSettings(bar)
    local control = bar._selected
    local route = bar._gearRoute
    if not (control and route) then
        return
    end

    -- Toggle: while this gear's advanced panel is on screen, the click
    -- closes it. No navigation happens on the way out - a panel can only
    -- stay open while its surface is current, so there is nowhere to go.
    if IsRoutePanelOpen(route) and CS.CloseAdvancedSettingsPanel then
        CS.CloseAdvancedSettingsPanel({ skipRefresh = true })
        return
    end

    local sectionId = ControlSectionId(control)
    local queueKey = ResolveRouteAdvancedKey(route)
    -- Read BEFORE ApplyGearRoute: the lens is resolved from the selection,
    -- which navigation does not touch, but keeping the read on this side of it
    -- keeps the answer tied to the state the click was made in.
    local suppressQueue = queueKey ~= nil and RouteSectionIsInert(sectionId)

    local surface = bar._surface
    local ok, panelId, buttonIndex = surface.ResolveTarget()
    if not ok then
        return
    end

    -- Read BEFORE navigating. Every seam below clears previews - the panel
    -- and entry tab switches both do, and so do the two home selectors - so
    -- a live check afterwards always reports "not running" and the preview
    -- the user was studying would silently die on the way to its settings.
    local wasRunning = control.preview.IsActive(panelId, buttonIndex) == true

    -- The inline texture browser takes over the settings area; leave it
    -- before landing somewhere underneath it.
    if CS.CancelPickAuraTexture then
        CS.CancelPickAuraTexture()
    end

    local destination = ApplyGearRoute(route, queueKey, sectionId)

    -- Queued last, with every navigation write already made, so the context
    -- it snapshots is the one the rebuild will consume it under. The
    -- already-open case normally exits through the toggle branch above;
    -- this guard keeps a stale open from flapping the panel shut if the
    -- post-navigation context still matches it.
    if queueKey
        and not suppressQueue
        and CS.QueueAdvancedSettingsPanelOpen
        and not (CS.IsAdvancedSettingsPanelOpen and CS.IsAdvancedSettingsPanelOpen(queueKey)) then
        CS.QueueAdvancedSettingsPanelOpen(queueKey)
    end

    CooldownCompanion:RefreshConfigPanel()

    -- Put the preview back if a seam took it. Guarded on live state so a
    -- route that crossed nothing does not flicker through a clear/set cycle.
    if wasRunning and control.preview.IsActive(panelId, buttonIndex) ~= true then
        SetPreviewRunning(destination, control, panelId, buttonIndex, true)
    end
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

------------------------------------------------------------------------
-- Gear tint: gold while an advanced settings panel is on screen, grey
-- otherwise.
--
-- Read from the window itself rather than from
-- IsAdvancedSettingsPanelOpen(key), which also compares the full navigation
-- context and so answered "closed" for a panel the user could plainly see.
-- And repaintable on its own, because the panel opens and closes without
-- rebuilding this bar - a settings-side gear toggles it with no config
-- refresh at all. Those two together are what made the tint look random.
------------------------------------------------------------------------

-- The bar currently on screen, so the advanced panel can repaint its gear
-- without going through a rebuild.
local activeBar

local function IsAdvancedSettingsWindowShown()
    local window = CS.advancedSettingsPanelWindow
    local frame = window and window.frame
    return frame ~= nil and frame:IsShown() == true
end

local function ApplyGearTint(bar)
    local gear = bar and bar.gear
    if not gear then
        return
    end
    if IsAdvancedSettingsWindowShown() then
        gear._icon:SetVertexColor(1, 0.82, 0, 1)
    else
        gear._icon:SetVertexColor(0.72, 0.72, 0.72, 0.85)
    end
end

-- Same rule for the spellbook toggle, read off its window handle for the same
-- reason: it opens and closes without rebuilding this bar.
local function IsSpellbookWindowShown()
    local window = CS.spellbookPanelWindow
    local frame = window and window.frame
    return frame ~= nil and frame:IsShown() == true
end

-- Unlike the other badges on the band, this one keeps the atlas's own colours at
-- rest: greyed out it was hard to read. The open state is what desaturates, so
-- the flat gold still tells the two apart at a glance.
local function ApplySpellbookTint(bar)
    local toggle = bar and bar.spellbook
    if not toggle then
        return
    end
    if IsSpellbookWindowShown() then
        toggle._icon:SetDesaturated(true)
        toggle._icon:SetVertexColor(1, 0.82, 0, 1)
    else
        toggle._icon:SetDesaturated(false)
        toggle._icon:SetVertexColor(1, 1, 1, 1)
    end
end

-- The spellbook exists to drag entries in, so it only appears where a drop
-- could land. Same rule as the workspace add box (ButtonsWideColumn's
-- UpdateAddBox): assistant panels never take user entries, and a
-- texture panel holds exactly one, so once set there is nothing to add.
local function PanelAcceptsNewEntries(group)
    if not group then
        return false
    end
    if CooldownCompanion:IsRotationAssistantGroup(group) then
        return false
    end
    if group.displayMode == "textures" and #(group.buttons or {}) >= 1 then
        return false
    end
    return true
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

    -- Quick access to the settings behind the chosen preview: the same
    -- destination the user would otherwise hunt for, one click from where
    -- they are already looking at the thing it styles.
    local gear = CreateFrame("Button", nil, bar)
    gear:SetSize(PLAY_SIZE, PLAY_SIZE)
    gear:SetPoint("LEFT", play, "RIGHT", GEAR_GAP, 0)
    gear._icon = gear:CreateTexture(nil, "ARTWORK")
    gear._icon:SetSize(PLAY_ICON_SIZE, PLAY_ICON_SIZE)
    gear._icon:SetPoint("CENTER")
    gear._icon:SetAtlas(GEAR_ATLAS, false)

    gear:SetScript("OnEnter", function(self)
        self._icon:SetVertexColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local route = bar._gearRoute
        if IsRoutePanelOpen(route) then
            GameTooltip:AddLine("Close settings")
            GameTooltip:AddLine("Close the advanced settings for this preview.", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Open settings")
            GameTooltip:AddLine("Go to the settings for this preview.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function()
        ApplyGearTint(bar)
        GameTooltip:Hide()
    end)
    gear:SetScript("OnClick", function()
        NavigateToPreviewSettings(bar)
    end)
    bar.gear = gear

    -- Drag spells in from the addon's own list instead of opening Blizzard's
    -- book. Pinned to the opposite end of the band, clear of the controls above.
    local spellbook = CreateFrame("Button", nil, bar)
    spellbook:SetSize(PLAY_SIZE, PLAY_SIZE)
    spellbook:SetPoint("RIGHT", bar, "RIGHT", -SPELLBOOK_RIGHT_INSET, 0)
    spellbook._icon = spellbook:CreateTexture(nil, "ARTWORK")
    spellbook._icon:SetSize(SPELLBOOK_ICON_WIDTH, SPELLBOOK_ICON_HEIGHT)
    spellbook._icon:SetPoint("CENTER")
    spellbook._icon:SetAtlas(SPELLBOOK_ATLAS, false)
    -- Desaturation and colour both belong to ApplySpellbookTint, which
    -- ApplyBarState runs right after this bar is built.

    spellbook:SetScript("OnEnter", function(self)
        self._icon:SetDesaturated(false)
        self._icon:SetVertexColor(1, 1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        if IsSpellbookWindowShown() then
            GameTooltip:AddLine("Close spellbook")
            GameTooltip:AddLine("Close the spell list beside the config.", 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Open spellbook")
            GameTooltip:AddLine("Drag a spell from the list onto a panel to add it.", 0.7, 0.7, 0.7)
        end
        GameTooltip:Show()
    end)
    spellbook:SetScript("OnLeave", function()
        ApplySpellbookTint(bar)
        GameTooltip:Hide()
    end)
    spellbook:SetScript("OnClick", function()
        if CS.ToggleSpellbookPanel then
            CS.ToggleSpellbookPanel()
        end
    end)
    bar.spellbook = spellbook

    bar._surface = surface
    host._cdcPreviewCommandCenter = bar
    return bar
end

local function ApplyBarState(bar, control, running, gearRoute, group)
    bar._selected = control
    bar._gearRoute = gearRoute
    bar.play._running = running

    bar.chooser:Show()
    bar.play:Show()
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

    -- The buttons workspace only: the Resources / Cast home configures bar
    -- objects, and there is nothing there to drop a spell on. Within the
    -- workspace, only panels that can still take an entry.
    bar.spellbook:SetShown(bar._surface == BUTTONS_SURFACE
        and PanelAcceptsNewEntries(group))
    ApplySpellbookTint(bar)

    if running then
        bar.chooser.chevron:SetVertexColor(1, 0.82, 0, 1)
        bar.play._icon:SetAtlas(STOP_ATLAS, false)
        bar.play._icon:SetVertexColor(1, 0.82, 0, 1)
    else
        bar.chooser.chevron:SetVertexColor(0.72, 0.72, 0.72, 0.85)
        bar.play._icon:SetAtlas(PLAY_ATLAS, false)
        bar.play._icon:SetVertexColor(0.72, 0.72, 0.72, 0.85)
    end

    if not gearRoute then
        bar.gear:Hide()
        return
    end
    ApplyGearTint(bar)
    bar.gear:Show()
end

local function ShowSpellbookOnlyBar(host)
    local bar = EnsureBar(host, BUTTONS_SURFACE)
    bar.chooser:Hide()
    bar.play:Hide()
    bar.gear:Hide()
    bar.spellbook:Show()
    ApplySpellbookTint(bar)
    host._cdcPreviewReserveBottom = BAR_RESERVE
    bar:Show()
    activeBar = bar
end

local function HideBar(host)
    host._cdcPreviewReserveBottom = nil
    local bar = host and host._cdcPreviewCommandCenter
    if bar then
        bar:Hide()
        if activeBar == bar then
            activeBar = nil
        end
    end
end

-- How far the bar's controls reach from the host's left edge. The bar
-- frame itself spans the whole width, but only this much of the band is
-- actually occupied - chrome pinned to the opposite corner of the same
-- band asks so it can keep clear. 0 while the bar is not showing.
local function GetPreviewCommandCenterOccupiedWidth(host)
    local bar = host and host._cdcPreviewCommandCenter
    if not (bar and bar:IsShown()) then
        return 0
    end
    local width = BAR_LEFT_INSET + (bar.chooser:GetWidth() or 0)
    if bar.play:IsShown() then
        width = width + PLAY_GAP + PLAY_SIZE
    end
    if bar.gear:IsShown() then
        width = width + GEAR_GAP + PLAY_SIZE
    end
    return width
end

-- Called by the advanced settings panel as it opens and closes: the gear
-- reports whether that panel is on screen, and nothing else repaints this
-- bar when it toggles.
local function RefreshPreviewCommandCenterGear()
    local bar = activeBar
    if bar and bar._gearRoute and bar:IsShown() then
        ApplyGearTint(bar)
    end
end

-- The same hook for the spellbook toggle, called by the spellbook window as it
-- opens and closes.
local function RefreshPreviewCommandCenterSpellbook()
    local bar = activeBar
    if bar and bar:IsShown() and bar.spellbook and bar.spellbook:IsShown() then
        ApplySpellbookTint(bar)
    end
end

------------------------------------------------------------------------
-- Shared bar update: resolve which entry the chooser names, whether it is
-- running, and show the bar. Both surfaces reach this having already
-- decided what they can offer.
------------------------------------------------------------------------

local function UpdateBar(host, surface, applicable, group, displayMode)
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
    ApplyBarState(bar, selected, running,
        ResolveGearRoute(selected, displayMode), group)

    host._cdcPreviewReserveBottom = BAR_RESERVE
    bar:Show()
    activeBar = bar
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
        -- Same bookkeeping the empty-band teardown does: with no surface up
        -- there is nothing to carry forward, and leaving this set lets the
        -- next pass migrate a preview the user has already left.
        CS.previewCommandCenterWasRunning = false
        return
    end

    local displayMode = group.displayMode or "icons"
    local applicable = {}
    for _, control in ipairs(CONTROLS) do
        if ControlApplies(control, group, displayMode, buttonIndex) then
            applicable[#applicable + 1] = control
        end
    end

    -- Object previews (health/cast/custom-bar auras) deliberately do NOT
    -- appear here, even on the anchor panel whose canvas draws the bar
    -- lanes — owner ruling 2026-07-26: the panel-view chooser stays scoped
    -- to panel previews, and the bars' previews live on the Resources /
    -- Cast Bar & Unit Frames home that configures those objects.

    if #applicable == 0 then
        -- Zero controls means a texture panel. Empty, the band still earns
        -- its keep as a drag target; full, there is nothing to offer at
        -- all, so the band gives its reserve back to the preview.
        if PanelAcceptsNewEntries(group) then
            ShowSpellbookOnlyBar(host)
        else
            HideBar(host)
        end
        CS.previewCommandCenterWasRunning = false
        return
    end

    MigrateRunningPreview(panelId, buttonIndex, applicable)

    local _, running = UpdateBar(host, BUTTONS_SURFACE, applicable, group, displayMode)
    -- Read by the migration above on the next pass, since the selection
    -- seam clears previews before we get to look at live state.
    CS.previewCommandCenterWasRunning = running
end

------------------------------------------------------------------------
-- Resources, Cast Bar & Unit Frames entry point. The home and its
-- cast/frames objects share one preview host and one renderer, so they
-- share one bar; what differs is which objects are being configured.
------------------------------------------------------------------------

local function UpdateResourcesPreviewCommandCenter(host)
    if not host then
        return
    end

    -- One canvas draws every object this workspace configures, whatever is
    -- selected, so the health bar, the custom bars and the resource overlays
    -- qualify for the whole workspace rather than for its home alone. Each
    -- object still carries its own enablement gate below (CollectObject-
    -- Controls), so a disabled module contributes nothing.
    --
    -- The cast bar qualifies only when THIS canvas actually draws a cast
    -- lane. Testing "the cast bar is attached" was not enough: an
    -- independent resource stack drops the cast slot from the canvas even
    -- with the cast bar attached, and the control then named a preview that
    -- repainted a cast-free canvas and visibly did nothing.
    local onBarsWorkspace = CS.barsEntrySelected == true
    local objects = {
        cast = ST._ResourcesPreviewRendersCastSlot ~= nil
            and ST._ResourcesPreviewRendersCastSlot() == true,
        health = onBarsWorkspace,
        customBars = onBarsWorkspace or CS.selectedCustomBarId ~= nil,
        resourceAuras = onBarsWorkspace
            or CS.selectedResourcePowerType ~= nil,
    }
    UpdateBar(host, RESOURCES_SURFACE, CollectObjectControls(objects))
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._UpdatePreviewCommandCenter = UpdatePreviewCommandCenter
ST._UpdateResourcesPreviewCommandCenter = UpdateResourcesPreviewCommandCenter
ST._RefreshPreviewCommandCenterGear = RefreshPreviewCommandCenterGear
ST._RefreshPreviewCommandCenterSpellbook = RefreshPreviewCommandCenterSpellbook
-- Read by the bars canvas while it places its bottom-right enable cluster.
ST._GetPreviewCommandCenterOccupiedWidth = GetPreviewCommandCenterOccupiedWidth
-- The gear's navigate-to-a-section half, for surfaces that want the destination
-- without the gear: the entry Settings pane's Customizations list.
ST._NavigateToSectionHome = NavigateToSectionHome
