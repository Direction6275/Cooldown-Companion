--[[
    CooldownCompanion - PreviewCommandCenter
    The preview command center: a strip of preview toggles pinned to the
    bottom of the buttons workspace's Live Preview surface, so the controls
    that trigger a preview live where the preview is actually visible.

    Scope follows the selection - with a single entry selected the toggles
    preview that entry, with nothing (or a multi-select) they preview the
    whole panel. Previews stay mutually exclusive across the whole config,
    exactly as the settings-side badges have always been.

    The strip is a child of the preview host, so every path that hides the
    host (view switches, talent picker, texture browser, config close)
    takes the strip with it - it is deliberately NOT a new col3 surface.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local STRIP_HEIGHT = 20
local STRIP_BOTTOM_INSET = 3
local BUTTON_SIZE = 18
local ICON_SIZE = 13
local BUTTON_SPACING = 6
local STATUS_GAP = 10
local PREVIEW_ATLAS = "CreditsScreen-Assets-Buttons-Play"

-- Vertical band the strip claims inside the host. The preview renderers
-- read this off the host and keep their content above it.
local STRIP_RESERVE = STRIP_HEIGHT + STRIP_BOTTOM_INSET

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
        IsActive = function(panelId)
            return CooldownCompanion:IsGroupTextureIndicatorPreviewActive(panelId, indicatorKey) == true
        end,
        SetActive = function(panelId, _, show)
            CooldownCompanion:SetGroupTextureIndicatorPreview(panelId, indicatorKey, show)
        end,
    }
end

local TriggerEffectsPreview = {
    IsActive = function(panelId)
        return CooldownCompanion:IsTriggerPanelEffectsPreviewActive(panelId) == true
    end,
    SetActive = function(panelId, _, show)
        CooldownCompanion:SetTriggerPanelEffectsPreview(panelId, show)
    end,
}

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
-- The curated control set (owner ruling 2026-07-25): the glow/indicator
-- toggles plus the universal states. Labels are the existing ones
-- verbatim - the no-rename ruling holds here too.
------------------------------------------------------------------------

local CONTROLS = {
    {
        id = "procGlow",
        label = "Preview Proc Glow",
        modes = { icons = true },
        section = "procGlow",
        glowStyleKey = "procGlowStyle",
        preview = FlagPreview("_procGlowPreview", "SetProcGlowPreview", "SetGroupProcGlowPreview"),
    },
    {
        id = "auraGlow",
        label = "Preview Aura Glow",
        modes = { icons = true },
        section = "auraIndicator",
        glowStyleKey = "auraGlowStyle",
        preview = FlagPreview("_auraGlowPreview", "SetAuraGlowPreview", "SetGroupAuraGlowPreview"),
    },
    {
        id = "readyGlow",
        label = "Preview Ready Glow Style",
        modes = { icons = true },
        section = "readyGlow",
        glowStyleKey = "readyGlowStyle",
        preview = FlagPreview("_readyGlowPreview", "SetReadyGlowPreview", "SetGroupReadyGlowPreview"),
    },
    {
        id = "barActiveAura",
        label = "Preview Active Aura Indicator",
        modes = { bars = true },
        section = "barActiveAura",
        requiresBarAuraIndicator = true,
        preview = FlagPreview("_barAuraEffectPreview", "SetBarAuraEffectPreview", "SetGroupBarAuraEffectPreview"),
    },
    {
        id = "cooldown",
        label = "Preview Cooldown State",
        modes = { icons = true, bars = true, text = true, rotationAssistant = true },
        preview = ConditionalPreview("cooldown"),
    },
    {
        id = "unusable",
        label = "Preview Unusable State",
        modes = { icons = true, bars = true, text = true, rotationAssistant = true },
        styleKey = "showUnusable",
        preview = ConditionalPreview("unusable"),
    },
    {
        id = "outOfRange",
        label = "Preview Out of Range State",
        modes = { icons = true, text = true, rotationAssistant = true },
        styleKey = "showOutOfRange",
        preview = ConditionalPreview("out_of_range"),
    },
    {
        id = "textureProc",
        label = "Preview Proc Effect",
        modes = { textures = true },
        indicatorKey = "proc",
        preview = TextureIndicatorPreview("proc"),
    },
    {
        id = "textureReady",
        label = "Preview Ready Effect",
        modes = { textures = true },
        indicatorKey = "ready",
        preview = TextureIndicatorPreview("ready"),
    },
    {
        id = "textureUnusable",
        label = "Preview Unusable Effect",
        modes = { textures = true },
        indicatorKey = "unusable",
        preview = TextureIndicatorPreview("unusable"),
    },
    {
        id = "triggerEffects",
        label = "Preview Effects",
        modes = { trigger = true },
        requiresTriggerEffect = true,
        preview = TriggerEffectsPreview,
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
-- Context: which panel the strip acts on, and whether a single selected
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
-- Strip frame
------------------------------------------------------------------------

local function SetButtonActive(btn, active)
    if not btn._activeHighlight then
        local highlight = btn:CreateTexture(nil, "BACKGROUND")
        highlight:SetPoint("TOPLEFT", -1, 1)
        highlight:SetPoint("BOTTOMRIGHT", 1, -1)
        highlight:SetColorTexture(0.85, 0.65, 0.0, 0.6)
        highlight:Hide()
        btn._activeHighlight = highlight
    end
    if active then
        btn._activeHighlight:Show()
        btn._icon:SetVertexColor(1, 0.82, 0, 1)
    else
        btn._activeHighlight:Hide()
        btn._icon:SetVertexColor(0.72, 0.72, 0.72, 0.85)
    end
end

local function EnsureStrip(host)
    local strip = host._cdcPreviewCommandCenter
    if strip then
        return strip
    end

    strip = CreateFrame("Frame", nil, host)
    strip:SetHeight(STRIP_HEIGHT)
    strip:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, STRIP_BOTTOM_INSET)
    strip:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, STRIP_BOTTOM_INSET)
    -- Above the mirror's own frames so the strip is never drawn under a
    -- slot that overhangs its cell (glows render outside the slot rect).
    strip:SetFrameLevel(host:GetFrameLevel() + 20)
    strip.buttons = {}

    -- Every toggle wears the same play badge, so a shared status line
    -- carries the name of whichever control is hovered (or currently
    -- previewing). Reads as status, not helper prose.
    local status = strip:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    status:SetHeight(STRIP_HEIGHT)
    status:SetJustifyH("LEFT")
    status:SetWordWrap(false)
    strip.status = status

    host._cdcPreviewCommandCenter = strip
    return strip
end

local function SetStatusText(strip, text)
    strip.status:SetText(text or "")
end

-- The active control's name is the resting status; hovering shows the
-- hovered one instead.
local function RefreshRestingStatus(strip)
    SetStatusText(strip, strip._activeLabel)
end

local function AcquireButton(strip, index)
    local btn = strip.buttons[index]
    if btn then
        return btn
    end

    btn = CreateFrame("Button", nil, strip)
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn._icon = btn:CreateTexture(nil, "ARTWORK")
    btn._icon:SetSize(ICON_SIZE, ICON_SIZE)
    btn._icon:SetPoint("CENTER")
    btn._icon:SetAtlas(PREVIEW_ATLAS, false)

    btn:SetScript("OnEnter", function(self)
        SetStatusText(strip, self._label)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self._label)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        RefreshRestingStatus(strip)
        GameTooltip:Hide()
    end)
    btn:SetScript("OnClick", function(self)
        if not self._control then
            return
        end
        local panelId, _, buttonIndex = ResolveContext()
        if not panelId then
            return
        end

        local show = not self._control.preview.IsActive(panelId, buttonIndex)
        -- Previews are mutually exclusive across the whole config: turning
        -- one on clears every other (including the settings-side badge
        -- highlight, which ClearAllConfigPreviews resets).
        if show then
            if CooldownCompanion.ClearAllConfigPreviews then
                CooldownCompanion:ClearAllConfigPreviews()
            end
        elseif ST._ClearActivePreviewBadgeButton then
            ST._ClearActivePreviewBadgeButton()
        end
        self._control.preview.SetActive(panelId, buttonIndex, show)

        -- An open advanced popout can be showing "Preview: ON" for the
        -- preview just cleared.
        if ST._RefreshAdvancedSettingsPreviewButtons then
            ST._RefreshAdvancedSettingsPreviewButtons()
        end
        -- Rebuilds the mirror, which re-runs the update below and repaints
        -- the strip from live state.
        if ST._RefreshButtonsPreviewMirror then
            ST._RefreshButtonsPreviewMirror()
        end
    end)

    strip.buttons[index] = btn
    return btn
end

local function LayoutButtons(strip, shown)
    local count = #shown
    local totalWidth = count * BUTTON_SIZE + math.max(0, count - 1) * BUTTON_SPACING
    local firstOffset = -(totalWidth / 2) + (BUTTON_SIZE / 2)

    for index, btn in ipairs(shown) do
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", strip, "CENTER",
            firstOffset + (index - 1) * (BUTTON_SIZE + BUTTON_SPACING), 0)
    end

    strip.status:ClearAllPoints()
    strip.status:SetPoint("LEFT", strip, "CENTER", (totalWidth / 2) + STATUS_GAP, 0)
end

local function HideStrip(host)
    host._cdcPreviewReserveBottom = nil
    local strip = host and host._cdcPreviewCommandCenter
    if strip then
        strip:Hide()
    end
end

------------------------------------------------------------------------
-- Update entry point. Called at the top of the buttons preview's build
-- closure, so it runs on every rebuild path (selection change, panel
-- switch, divider drag, preview toggle) and - critically - BEFORE the
-- mirror measures itself, since it owns the host's bottom reserve.
------------------------------------------------------------------------

local function UpdatePreviewCommandCenter(host)
    if not host then
        return
    end

    local panelId, group, buttonIndex = ResolveContext()
    if not panelId then
        HideStrip(host)
        return
    end

    local displayMode = group.displayMode or "icons"
    local applicable = {}
    for _, control in ipairs(CONTROLS) do
        if ControlApplies(control, group, displayMode, buttonIndex) then
            applicable[#applicable + 1] = control
        end
    end

    if #applicable == 0 then
        HideStrip(host)
        return
    end

    local strip = EnsureStrip(host)
    local shown = {}
    local activeLabel

    for index, control in ipairs(applicable) do
        local btn = AcquireButton(strip, index)
        btn._control = control
        btn._label = control.label
        local active = control.preview.IsActive(panelId, buttonIndex) == true
        SetButtonActive(btn, active)
        if active then
            activeLabel = control.label
        end
        btn:Show()
        shown[#shown + 1] = btn
    end

    for index = #applicable + 1, #strip.buttons do
        local btn = strip.buttons[index]
        btn._control = nil
        btn:Hide()
    end

    strip._activeLabel = activeLabel
    RefreshRestingStatus(strip)
    LayoutButtons(strip, shown)

    host._cdcPreviewReserveBottom = STRIP_RESERVE
    strip:Show()
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._UpdatePreviewCommandCenter = UpdatePreviewCommandCenter
