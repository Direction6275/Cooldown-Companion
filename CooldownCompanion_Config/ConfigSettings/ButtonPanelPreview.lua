--[[
    CooldownCompanion - ButtonPanelPreview
    Clickable in-config mirror of the selected button panel for the wide
    buttons column. Renders every saved entry from saved settings only
    (never live button frames - live icon geometry can be secret-sensitive
    in config context), scaled to fit the host. Clicking an entry selects
    it through the normal config selection flow.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState

local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil

local StyleMirroredIconFrame = ST._StyleMirroredIconFrame
local GetLayoutPreviewIcon = ST._GetLayoutPreviewIcon
local GetConfigEntryDisplayName = ST._GetConfigEntryDisplayName
local SelectConfigButton = ST._SelectConfigButton
local ShowEntryContextMenu = ST._ShowEntryContextMenu
local SetIconAreaPoints = ST._SetIconAreaPoints
local SetBarAreaPoints = ST._SetBarAreaPoints
local ApplyBorderEdgePositions = ST._ApplyBorderEdgePositions
local PerformButtonReorder = ST._PerformButtonReorder
local StartDragTracking = ST._StartDragTracking
local CancelDrag = ST._CancelDrag
-- Text entries auto-size from a measured worst-case render of their format
-- (ButtonFrame/TextMode.lua). Cached per entry, keyed on the entry table, so
-- every call site here passes its buttonData.
local GetTextEntryMetrics = ST._GetTextEntryMetrics
local CreateGlowContainer = ST._CreateGlowContainer
local SetBarAuraEffect = ST._SetBarAuraEffect
local GetStoredConditionalPreviewState = ST._GetStoredConditionalPreviewState
local IsStoredPreviewFlagActive = ST._IsStoredPreviewFlagActive
local GetConditionalPreviewTiming = ST._GetConditionalPreviewTiming
local ParseFormatString = ST._ParseFormatString
local ApplyIconCountTextStyle = ST._ApplyIconCountTextStyle
local ApplyBarCountTextStyle = ST._ApplyBarCountTextStyle
local AnchorIconFill = ST._AnchorIconFill
local ApplyIconFillGeometry = ST._ApplyIconFillGeometry
local ApplyIconFillLayer = ST._ApplyIconFillLayer
local ResolveIconFillTimerValue = ST._ResolveIconFillTimerValue
local DEFAULT_BAR_AURA_COLOR = ST._DEFAULT_BAR_AURA_COLOR
local DEFAULT_BAR_CHARGE_COLOR = ST._DEFAULT_BAR_CHARGE_COLOR
local AuraTextures = ST._AT
local ApplyTextureIndicatorEffects = AuraTextures and AuraTextures.ApplyTextureIndicatorEffects
local SetTextureIndicatorBaseVisuals = AuraTextures and AuraTextures.SetTextureIndicatorBaseVisuals
local StopAllTextureIndicatorEffects = AuraTextures and AuraTextures.StopAllTextureIndicatorEffects

local PANEL_PREVIEW_PADDING = 12
local PANEL_PREVIEW_DISABLED_ALPHA = 0.45
local PANEL_PREVIEW_RING_COLOR = { 0.38, 0.60, 0.92, 1 }
-- Above the bar slots' text frame (statusBar level + 2)
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = 5
-- Badges counter-scale against the preview's scale-to-fit so they stay
-- readable, clamped so they never dwarf a heavily scaled-down slot.
local PANEL_PREVIEW_BADGE_SCREEN_SIZE = 14
-- The crossed-eye atlas has substantial transparent padding around its glyph.
local PANEL_PREVIEW_VISIBILITY_BADGE_SCREEN_SIZE = 18
-- Matches the resources layout preview's tween timing
local PANEL_PREVIEW_ANIM_DURATION = 0.08
-- Update cadence for animated conditional previews (countdown numbers,
-- loop re-arms); the swipes and fills self-animate between ticks.
local PANEL_PREVIEW_COND_TICK = 0.25
local DEFAULT_BAR_COLOR = { 0.2, 0.6, 1.0, 1.0 }
local DEFAULT_BAR_READY_TEXT_COLOR = { 0.2, 1.0, 0.2, 1.0 }
local BAR_PREVIEW_ICON_FALLBACK = 134400

local PANEL_PREVIEW_GHOST_ALPHA = 0.35
local PANEL_PREVIEW_GHOST_HOVER_ALPHA = 0.65
local PANEL_PREVIEW_VISIBILITY_BADGE_ATLAS = "GM-icon-visibleDis-pressed"
local PANEL_PREVIEW_AURA_SPACE_BADGE_ATLAS = "QuestRepeatableTurnin"
local BAR_PREVIEW_EFFECT_FLAGS = {
    "_procGlowPreview",
    "_auraGlowPreview",
    "_barAuraEffectPreview",
    "_pandemicPreview",
    "_readyGlowPreview",
    "_keyPressHighlightPreview",
}
local function IsBarPreviewAuraActive(conditional, effectFlags)
    if conditional and conditional.auraActive == true then
        return true
    end
    -- Deliberately the UNION of both display modes' aura-preview kinds: the
    -- mirror simulates "the aura is active" for any aura preview, whichever
    -- mode hosts it. The kind inventory is owned by Core/Aura.lua.
    local kind = conditional and conditional.kind or nil
    if kind and (CooldownCompanion:IsAuraPreviewKindExposingShell(kind, true)
        or CooldownCompanion:IsAuraPreviewKindExposingShell(kind, false)) then
        return true
    end
    return effectFlags
        and (effectFlags._auraGlowPreview or effectFlags._barAuraEffectPreview
            or effectFlags._pandemicPreview)
        and true or false
end

local BAR_PREVIEW_REASON_DEFS = {
    { key = "disabled", label = "Disabled", rule = "Enabled is off" },
    -- The aura pair shares one reason but not one rule name: while inactive
    -- the entry is either hidden or dimmed, and naming the wrong toggle
    -- sends the owner looking for a switch they never turned on.
    { key = "aura-inactive", label = "Aura inactive",
        rule = function(buttonData)
            return buttonData.auraShellDim == true
                and "Dim While Aura Inactive"
                or "Show Only While Aura Active"
        end,
        fallback = "auraShellDim" },
    { key = "on-cooldown", label = "On cooldown", rule = "Hide While On Cooldown",
        fallback = "useBaselineAlphaFallbackOnCooldown" },
    { key = "not-on-cooldown", label = "Not on cooldown", rule = "Hide While Not On Cooldown",
        fallback = "useBaselineAlphaFallbackNotOnCooldown" },
    { key = "no-proc", label = "No proc", rule = "Hide While No Proc",
        fallback = "useBaselineAlphaFallbackNoProc" },
    { key = "zero-charges", label = "Zero charges", rule = "Hide While At Zero Charges",
        fallback = "useBaselineAlphaFallbackZeroCharges" },
    -- Items with use-count fallbacks title this row "Hide While No Uses
    -- Available" in the config (ButtonConditions), so the tooltip must name
    -- the toggle the way that entry's own row does.
    { key = "zero-stacks", label = "Zero stacks",
        rule = function(buttonData)
            return type(CooldownCompanion.HasItemFallbacks) == "function"
                and CooldownCompanion.HasItemFallbacks(buttonData) == true
                and "Hide While No Uses Available"
                or "Hide While At Zero Stacks"
        end,
        fallback = "useBaselineAlphaFallbackZeroStacks" },
    { key = "not-equipped", label = "Not equipped", rule = "Hide While Not Equipped",
        fallback = "useBaselineAlphaFallbackNotEquipped" },
    { key = "unusable", label = "Unusable", rule = "Hide While Unusable",
        fallback = "useBaselineAlphaFallbackUnusable" },
}

-- Snapshot the config-owned preview state for a mirror entry. Preview.lua owns
-- both stores, so this path never consults live button fields.
local function GetStoredBarPreviewState(panelId, index)
    local conditional = GetStoredConditionalPreviewState
        and GetStoredConditionalPreviewState(panelId, index) or nil
    local effectFlags = {}
    if IsStoredPreviewFlagActive then
        for _, flag in ipairs(BAR_PREVIEW_EFFECT_FLAGS) do
            if IsStoredPreviewFlagActive(panelId, index, flag) then
                effectFlags[flag] = true
            end
        end
    end
    return {
        conditional = conditional,
        effectFlags = effectFlags,
    }
end

local function HasStoredBarEffectPreview(effectFlags)
    if type(effectFlags) ~= "table" then
        return false
    end
    for _, flag in ipairs(BAR_PREVIEW_EFFECT_FLAGS) do
        if effectFlags[flag] == true then
            return true
        end
    end
    return false
end

local function IsBarPreviewNoCooldownSpell(buttonData)
    return buttonData.type == "spell"
        and type(ST.IsNoCooldownSpell) == "function"
        and ST.IsNoCooldownSpell(buttonData.id) == true
end

local function UsesConfigOnlyBarChargeBehavior(buttonData)
    if type(buttonData) ~= "table" then return false end
    if buttonData.type == "spell" and buttonData.addedAs == "aura" then
        return false
    end
    return buttonData.hasCharges == true
end
-- Exported because the Bar mirror's charge rendering gates on this narrower
-- rule than the icon mirror's UsesChargeBehavior, and the preview command
-- center only offers a charge preview that would visibly render.
ST._UsesConfigOnlyBarChargeBehavior = UsesConfigOnlyBarChargeBehavior

-- Pure Bar-mirror visibility projection. Inputs are saved entry/group data and
-- a stored config-preview snapshot only. It deliberately does not accept live
-- status, button frames, aura state, item counts, usability, or equipment data.
local function ResolveBarPreviewVisibility(buttonData, group, previewState)
    buttonData = type(buttonData) == "table" and buttonData or {}
    group = type(group) == "table" and group or {}
    previewState = type(previewState) == "table" and previewState or {}

    local conditional = type(previewState.conditional) == "table"
        and previewState.conditional or nil
    local kind = conditional and conditional.kind or nil
    local effectFlags = type(previewState.effectFlags) == "table"
        and previewState.effectFlags or nil
    local exactPreview = kind ~= nil or HasStoredBarEffectPreview(effectFlags)

    -- Stable baseline: aura/proc inactive, ready, full charges, and otherwise
    -- available/usable/equipped. Only a stored preview may replace those facts.
    local auraActive = IsBarPreviewAuraActive(conditional, effectFlags)
    local procActive = conditional and conditional.procActive == true or false
    if effectFlags and effectFlags._procGlowPreview then
        procActive = true
    end

    local chargeState = conditional and conditional.chargeState or "full"
    if kind == "charge_full" then
        chargeState = "full"
    elseif kind == "charge_missing" then
        chargeState = "missing"
    elseif kind == "charge_zero" then
        chargeState = "zero"
    end
    local onCooldown = conditional and conditional.onCooldown == true or false
    -- Cooldown Text draws only the countdown, but a countdown still claims
    -- the cooldown situation, so the hide rules project it like the full
    -- state preview always was.
    if kind == "cooldown" or kind == "cooldown_text" then
        onCooldown = true
    end

    local itemQuantityKind = conditional and conditional.itemQuantityKind or nil
    local itemAvailableQuantity = conditional and conditional.itemAvailableQuantity or nil
    if kind == "charge_zero" and itemQuantityKind == "stacks" then
        itemAvailableQuantity = 0
    end
    local isEquippableNotEquipped = conditional
        and conditional.isEquippableNotEquipped == true or false
    local unusable = conditional
        and (conditional.unusable == true or kind == "unusable") or false

    local activeReasons = {}
    if buttonData.enabled == false then
        activeReasons.disabled = true
    end
    local isAuraEntry = buttonData.type == "spell"
        and (buttonData.auraTracking == true or buttonData.addedAs == "aura")
    -- Either aura shell form suppresses the entry's own look while the aura
    -- is inactive; the dim key selects dimmed instead of hidden below. The
    -- predicate is the runtime's own so the mirror cannot disagree with what
    -- the panel will actually draw.
    if isAuraEntry and not auraActive
        and CooldownCompanion:IsAuraShellEntry(buttonData) then
        activeReasons["aura-inactive"] = true
    end

    local usesChargeBehavior = UsesConfigOnlyBarChargeBehavior(buttonData)
    local itemUsesResolvedCooldownState = buttonData.type == "item"
        and itemQuantityKind == "stacks"
    local needsNoCooldownCheck = buttonData.hideWhileOnCooldown
        or buttonData.hideWhileNotOnCooldown
    local noCooldown = needsNoCooldownCheck and IsBarPreviewNoCooldownSpell(buttonData) or false
    local zeroOnlyChargeSpellHide = false

    if buttonData.hideWhileOnCooldown and not noCooldown then
        if itemUsesResolvedCooldownState then
            if onCooldown then activeReasons["on-cooldown"] = true end
        elseif usesChargeBehavior then
            if chargeState == "zero" or chargeState == "missing" then
                activeReasons["on-cooldown"] = true
            end
        elseif onCooldown then
            activeReasons["on-cooldown"] = true
        end
    end

    if buttonData.hideWhileNotOnCooldown and not noCooldown then
        if itemUsesResolvedCooldownState then
            if not onCooldown then activeReasons["not-on-cooldown"] = true end
        elseif usesChargeBehavior then
            if buttonData.type == "spell"
                and buttonData.hasCharges == true
                and buttonData.showOnlyAtZeroCharges then
                if chargeState == "full" or chargeState == "missing" then
                    activeReasons["not-on-cooldown"] = true
                    zeroOnlyChargeSpellHide = true
                end
            elseif chargeState == "full" then
                activeReasons["not-on-cooldown"] = true
            end
        elseif not onCooldown then
            activeReasons["not-on-cooldown"] = true
        end
    end

    if buttonData.hideWhileNoProc then
        local isSpellEntry = buttonData.type == "spell"
            and buttonData.addedAs ~= "aura"
            and not buttonData.isPassive
            and not buttonData.isPassiveCooldown
        if isSpellEntry and not procActive then
            activeReasons["no-proc"] = true
        end
    end

    local hasItemFallbacks = type(CooldownCompanion.HasItemFallbacks) == "function"
        and CooldownCompanion.HasItemFallbacks(buttonData) == true
    if buttonData.hideWhileZeroCharges
        and not hasItemFallbacks
        and chargeState == "zero" then
        activeReasons["zero-charges"] = true
    end
    if buttonData.type == "item"
        and buttonData.hideWhileZeroStacks
        and itemQuantityKind == "stacks"
        and (tonumber(itemAvailableQuantity) or 0) == 0 then
        activeReasons["zero-stacks"] = true
    end
    if buttonData.hideWhileNotEquipped and isEquippableNotEquipped then
        activeReasons["not-equipped"] = true
    end
    if buttonData.hideWhileUnusable
        and not buttonData.isPassive
        and not buttonData.isPassiveCooldown
        and unusable then
        activeReasons.unusable = true
    end

    local reasons = {}
    local onlyReason
    for _, definition in ipairs(BAR_PREVIEW_REASON_DEFS) do
        if activeReasons[definition.key] then
            local rule = definition.rule
            if type(rule) == "function" then
                rule = rule(buttonData)
            end
            reasons[#reasons + 1] = {
                key = definition.key,
                label = definition.label,
                rule = rule,
            }
            onlyReason = definition
        end
    end

    local underlyingMode = "visible"
    local underlyingAlpha = 1
    if #reasons == 1
        and onlyReason.fallback
        and buttonData[onlyReason.fallback]
        and not (zeroOnlyChargeSpellHide and onlyReason.key == "not-on-cooldown") then
        underlyingMode = "dimmed"
        underlyingAlpha = CooldownCompanion.DIM_FALLBACK_ALPHA
    elseif #reasons > 0 then
        underlyingMode = "hidden"
        underlyingAlpha = PANEL_PREVIEW_GHOST_ALPHA
    end

    local mode = exactPreview and "visible" or underlyingMode
    local visibilityAlpha = exactPreview and 1 or underlyingAlpha
    return {
        mode = mode,
        effectiveMode = mode,
        visibilityAlpha = visibilityAlpha,
        visualAlpha = visibilityAlpha,
        exactPreview = exactPreview,
        forcedPreview = exactPreview and underlyingMode ~= "visible",
        underlyingMode = underlyingMode,
        reasons = reasons,
        underlyingReasons = reasons,
    }
end

-- Bar mirrors must not follow the currently equipped item in an equipment
-- slot. Manual icons and configured spell/item identities are stable inputs;
-- equipment slots without a manual icon deliberately use a stable fallback.
local function GetConfigOnlyBarPreviewIcon(buttonData)
    if type(buttonData) ~= "table" then
        return BAR_PREVIEW_ICON_FALLBACK
    end
    local manualIcon = buttonData.manualIcon
    if type(manualIcon) == "number" or type(manualIcon) == "string" then
        return manualIcon
    end
    if buttonData.type == "spell" and buttonData.id then
        return C_Spell.GetSpellTexture(buttonData.id) or BAR_PREVIEW_ICON_FALLBACK
    end
    if buttonData.type == "item" and buttonData.id then
        return C_Item.GetItemIconByID(buttonData.id) or BAR_PREVIEW_ICON_FALLBACK
    end
    return BAR_PREVIEW_ICON_FALLBACK
end

local function GetConfigOnlyBarPreviewName(buttonData)
    if type(buttonData) ~= "table" then return "" end
    if buttonData.customName then return buttonData.customName end
    if CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        return (CooldownCompanion.GetEquipmentSlotDisplayName
            and CooldownCompanion.GetEquipmentSlotDisplayName(buttonData))
            or buttonData.name or "Equipment Slot"
    end
    if buttonData.type == "spell" and buttonData.id then
        return C_Spell.GetSpellName(buttonData.id) or buttonData.name or ""
    end
    if buttonData.type == "item" and buttonData.id then
        return C_Item.GetItemNameByID(buttonData.id) or buttonData.name or ""
    end
    return buttonData.name or ""
end

-- Mirror of GroupFrame.lua GetGrowthMultipliers: anchor corner plus x/y
-- offset signs for the configured growth origin.
local function GetGrowthMultipliers(growthOrigin)
    if growthOrigin == "TOPRIGHT" then return -1, -1, "TOPRIGHT" end
    if growthOrigin == "BOTTOMLEFT" then return 1, 1, "BOTTOMLEFT" end
    if growthOrigin == "BOTTOMRIGHT" then return -1, 1, "BOTTOMRIGHT" end
    return 1, -1, "TOPLEFT"
end

-- Chrome pinned to the bottom of the host (the preview command center)
-- claims a band the rendered preview must stay clear of. Hosts without
-- chrome report 0, so measuring frames and overview tiles are unaffected.
local function GetHostBottomReserve(host)
    return host and host._cdcPreviewReserveBottom or 0
end

-- Re-anchored on every build: the reserve appears and disappears with the
-- selection, and the content centers inside whatever is left.
local function ApplyHostBottomReserve(host, root)
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, GetHostBottomReserve(host))
end

local function EnsurePreviewState(host)
    local preview = host._cdcPanelPreview
    if preview then
        preview.buildId = (preview.buildId or 0) + 1
        ApplyHostBottomReserve(host, preview.root)
        return preview
    end

    preview = {
        buildId = 1,
        pools = { iconSlots = {}, barSlots = {}, textSlots = {} },
        used = { iconSlots = 0, barSlots = 0, textSlots = 0 },
    }
    host._cdcPanelPreview = preview

    local root = CreateFrame("Frame", nil, host)
    root:SetClipsChildren(false)
    root:Hide()
    ApplyHostBottomReserve(host, root)
    preview.root = root

    local content = CreateFrame("Frame", nil, root)
    content:SetClipsChildren(false)
    preview.content = content

    return preview
end

local function ResetPreviewState(preview)
    for poolName in pairs(preview.pools) do
        preview.used[poolName] = 0
    end
    preview.root:Show()
end

local ResetBarSlotWorkspaceState
-- Copy-customization mode namespace: the helpers live in a do-block below
-- (this file rides the 200-local ceiling) and publish through this table.
local CopyMode = {}

local function FinalizePreviewState(preview)
    for poolName, pool in pairs(preview.pools) do
        local used = preview.used[poolName] or 0
        for index = used + 1, #pool do
            local frame = pool[index]
            ResetBarSlotWorkspaceState(frame)
            frame:Hide()
            frame:ClearAllPoints()
            frame:SetScript("OnMouseDown", nil)
            frame:SetScript("OnMouseUp", nil)
            frame:SetScript("OnEnter", nil)
            frame:SetScript("OnLeave", nil)
        end
    end
    -- Every build path ends here, so the copy-customization banner follows
    -- the preview onto whatever panel it now shows.
    CopyMode.UpdateBanner(preview)

    -- Aura Panel caption. The replica is the EXPANDED grid - every entry, in
    -- order - because that is the footprint the panel holds; in the world
    -- Blizzard packs only the auras that are up. No static mirror can show
    -- that, so the preview says it instead of letting the grid imply gaps.
    --
    -- Written inline rather than as a helper: this file rides the 200-local
    -- ceiling (see the CopyMode do-block above), and every build path already
    -- passes through here, which is also what makes the hide reliable when the
    -- preview moves onto an ordinary panel.
    local auraCaptionGroup = preview.readOnly ~= true and preview.panelId
        and CooldownCompanion.db.profile.groups[preview.panelId] or nil
    if auraCaptionGroup and ST.IsAuraPanelGroup(auraCaptionGroup) then
        local caption = preview.auraCaption
        if not caption then
            caption = preview.root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            caption:SetJustifyH("CENTER")
            caption:SetWordWrap(false)
            caption:SetPoint("BOTTOM", preview.root, "BOTTOM", 0, 2)
            caption:SetText("Inactive auras take no space in game.")
            preview.auraCaption = caption
        end
        caption:Show()
    elseif preview.auraCaption then
        preview.auraCaption:Hide()
    end
end

-- Group Panel Overview tiles reuse the saved-design mirror without exposing
-- any of the focused preview's entry interaction or preview-state machinery.
-- Focused builds explicitly re-enable mouse input when wiring a recycled slot.
local function DisableReadOnlySlotInteraction(slot)
    if slot._cdcShiftTooltipAdapter and ST._ClearConfigShiftTooltipHover then
        ST._ClearConfigShiftTooltipHover(slot._cdcShiftTooltipAdapter)
    end
    if ResetBarSlotWorkspaceState then
        ResetBarSlotWorkspaceState(slot)
    end
    slot:EnableMouse(false)
    slot:SetScript("OnMouseDown", nil)
    slot:SetScript("OnMouseUp", nil)
    slot:SetScript("OnEnter", nil)
    slot:SetScript("OnLeave", nil)
    slot._cdcDraggable = false
    slot._cdcEntryIndex = nil
    slot._cdcEntryStatus = nil
    slot._cdcCondAnim = nil
    slot:SetAlpha(1)
    if slot.hoverHighlight then slot.hoverHighlight:Hide() end
    if slot.selectedHighlight then slot.selectedHighlight:Hide() end
    if slot.copyTargetHighlight then slot.copyTargetHighlight:Hide() end
    if slot.problemBadge then slot.problemBadge:Hide() end
    if slot.problemBadgeBack then slot.problemBadgeBack:Hide() end
    if slot.overrideBadge then slot.overrideBadge:Hide() end
    if slot.overrideBadgeBack then slot.overrideBadgeBack:Hide() end
    if slot.visibilityBadge then slot.visibilityBadge:Hide() end
end

-- Hover glow and selection marker shared by both slot kinds.
local function AttachSlotHighlights(frame)
    frame.hoverHighlight = CreateFrame("Frame", nil, frame)
    frame.hoverHighlight:SetAllPoints(frame)
    frame.hoverHighlight:EnableMouse(false)
    frame.hoverHighlight.tex = frame.hoverHighlight:CreateTexture(nil, "OVERLAY")
    frame.hoverHighlight.tex:SetAllPoints()
    frame.hoverHighlight.tex:SetColorTexture(1, 1, 1, 0.10)
    frame.hoverHighlight.tex:SetBlendMode("ADD")
    frame.hoverHighlight:Hide()

    -- Selection marker: held hover-style glow plus a thin accent ring,
    -- sized well for icon-grid density (the resource preview's arrows
    -- overwhelm small icons).
    frame.selectedHighlight = CreateFrame("Frame", nil, frame)
    frame.selectedHighlight:SetAllPoints(frame)
    frame.selectedHighlight:EnableMouse(false)
    frame.selectedHighlight.tex = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    frame.selectedHighlight.tex:SetAllPoints()
    frame.selectedHighlight.tex:SetColorTexture(1, 1, 1, 0.10)
    frame.selectedHighlight.tex:SetBlendMode("ADD")
    frame.selectedHighlight.ringTextures = {}
    for i = 1, 4 do
        frame.selectedHighlight.ringTextures[i] = frame.selectedHighlight:CreateTexture(nil, "OVERLAY")
    end
    frame.selectedHighlight:Hide()
end

-- Icon-mode slot: the frame shape ST._StyleMirroredIconFrame expects
-- (bg, icon, countText, borderTextures[4]).
local function CreateIconSlot(parent)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetClipsChildren(false)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.countText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.countText:SetPoint("CENTER")
    frame.borderTextures = {}
    for i = 1, 4 do
        frame.borderTextures[i] = frame:CreateTexture(nil, "OVERLAY")
    end

    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints(frame.icon)
    frame.cooldown:SetDrawBling(false)
    frame.cooldown:SetHideCountdownNumbers(true)
    frame.cooldown:EnableMouse(false)
    frame.cooldown:Hide()

    AttachSlotHighlights(frame)
    return frame
end

-- Bar-mode slot: static twin of the frames BarMode.lua CreateBarFrame
-- builds (minus cooldowns, time text, and counts).
local function CreateBarSlot(parent)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetClipsChildren(false)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.iconBg = frame:CreateTexture(nil, "BACKGROUND")
    frame.icon = frame:CreateTexture(nil, "ARTWORK")

    frame.iconBounds = CreateFrame("Frame", nil, frame)
    frame.iconBounds:EnableMouse(false)
    frame.barBounds = CreateFrame("Frame", nil, frame)
    frame.barBounds:EnableMouse(false)

    frame.statusBar = CreateFrame("StatusBar", nil, frame)
    frame.statusBar:EnableMouse(false)

    frame.textFrame = CreateFrame("Frame", nil, frame)
    frame.textFrame:EnableMouse(false)
    frame.nameText = frame.textFrame:CreateFontString(nil, "OVERLAY")

    frame.iconBorderTextures = {}
    frame.borderTextures = {}
    for i = 1, 4 do
        frame.iconBorderTextures[i] = frame:CreateTexture(nil, "OVERLAY")
        frame.borderTextures[i] = frame:CreateTexture(nil, "OVERLAY")
    end

    AttachSlotHighlights(frame)
    return frame
end

-- Ghosting is workspace presentation, not button visibility. Keep the root
-- frame fully opaque/clickable and dim only the regions that reproduce the
-- runtime bar. This is the sole owner of Bar mirror visual alpha.
local function ApplyBarSlotVisualAlpha(slot, alpha)
    if not slot.statusBar then return end
    alpha = tonumber(alpha) or 1

    local function SetAlpha(region)
        if region then region:SetAlpha(alpha) end
    end
    SetAlpha(slot.bg)
    SetAlpha(slot.iconBg)
    SetAlpha(slot.icon)
    SetAlpha(slot.statusBar)
    SetAlpha(slot.textFrame)
    SetAlpha(slot.textOverlay)
    local barAuraEffect = slot.barAuraEffect
    if barAuraEffect then
        SetAlpha(barAuraEffect.solidFrame)
        SetAlpha(barAuraEffect.procFrame)
    end
    for _, texture in ipairs(slot.iconBorderTextures or {}) do
        texture:SetAlpha(alpha)
    end
    for _, texture in ipairs(slot.borderTextures or {}) do
        texture:SetAlpha(alpha)
    end
end

ResetBarSlotWorkspaceState = function(frame)
    if not frame.statusBar then return end
    if frame._cdcShiftTooltipAdapter and ST._ClearConfigShiftTooltipHover then
        ST._ClearConfigShiftTooltipHover(frame._cdcShiftTooltipAdapter)
    end
    frame._cdcBarPreviewVisibility = nil
    frame._cdcBarPreviewHovered = nil
    frame._cdcBarPreviewScale = nil
    frame._cdcEntryIndex = nil
    frame._cdcEntryStatus = nil
    frame._cdcDraggable = false
    frame._cdcBaseAlpha = 1
    ApplyBarSlotVisualAlpha(frame, 1)
    if frame.visibilityBadge then frame.visibilityBadge:Hide() end
    if frame.problemBadge then frame.problemBadge:Hide() end
    if frame.problemBadgeBack then frame.problemBadgeBack:Hide() end
    if frame.overrideBadge then frame.overrideBadge:Hide() end
    if frame.overrideBadgeBack then frame.overrideBadgeBack:Hide() end
    frame._cdcVisibilityBadgeShown = nil
end

-- Text-mode slot: static twin of TextMode.lua CreateTextFrame (bg,
-- borders, single FontString; no cooldown/count runtime pieces).
local function CreateTextSlot(parent)
    local frame = CreateFrame("Button", nil, parent)
    frame:SetClipsChildren(false)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.textString = frame:CreateFontString(nil, "OVERLAY")
    frame.borderTextures = {}
    for i = 1, 4 do
        frame.borderTextures[i] = frame:CreateTexture(nil, "OVERLAY")
    end

    AttachSlotHighlights(frame)
    return frame
end

local SLOT_FACTORIES = {
    iconSlots = CreateIconSlot,
    barSlots = CreateBarSlot,
    textSlots = CreateTextSlot,
}

local function AcquireSlot(preview, parent, poolName)
    local pool = preview.pools[poolName]
    local index = (preview.used[poolName] or 0) + 1
    preview.used[poolName] = index
    local frame = pool[index]
    if not frame then
        frame = SLOT_FACTORIES[poolName](parent)
        pool[index] = frame
    end
    frame:SetParent(parent)
    ResetBarSlotWorkspaceState(frame)
    frame:Show()
    frame:SetAlpha(1)
    frame.hoverHighlight:Hide()
    frame.selectedHighlight:Hide()
    return frame
end

local function SetPreviewMessage(preview, message)
    local label = preview.messageLabel
    if not label then
        label = preview.root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(true)
        preview.messageLabel = label
    end
    -- Re-anchored on every call: the trigger preview tucks this label into its
    -- bottom band after calling here, so the full-area default must come back
    -- for every other caller on a shared host.
    label:ClearAllPoints()
    label:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 18, -18)
    label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, 18)
    label:SetText(message or "")
    label:Show()
end

local function HidePreviewMessage(preview)
    if preview.messageLabel then
        preview.messageLabel:Hide()
    end
end

local function IsEntrySelected(index)
    return CS.selectedButton == index or CS.selectedButtons[index] == true
end

-- Glow-family previews draw at the slot's edge, exactly where the blue
-- selection ring lives, so the two fight for the same pixels. While one
-- is running on an entry its ring stands down for the duration - the
-- breadcrumb, the tab row and the preview chooser all still say which
-- entry is being edited. Conditional state previews (swipes, texts,
-- tints) draw on the icon face and are left alone.
local SELECTION_YIELDING_PREVIEW_FLAGS = {
    "_procGlowPreview",
    "_auraGlowPreview",
    "_missingAuraPreview",
    "_pandemicPreview",
    "_readyGlowPreview",
    "_barAuraEffectPreview",
    "_keyPressHighlightPreview",
}

local function IsGlowPreviewActiveOnEntry(panelId, index)
    if not (panelId and index and CooldownCompanion.IsPreviewFlagActive) then
        return false
    end
    for _, flag in ipairs(SELECTION_YIELDING_PREVIEW_FLAGS) do
        if CooldownCompanion:IsPreviewFlagActive(panelId, index, flag) then
            return true
        end
    end
    return false
end

local function ApplySelectionVisuals(slot, index, suppress)
    local isSelected = IsEntrySelected(index)
    if suppress or not isSelected then
        slot.selectedHighlight:Hide()
        return
    end
    slot.selectedHighlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
    ST.ApplyBorderTextures(slot.selectedHighlight.ringTextures, slot.selectedHighlight,
        PANEL_PREVIEW_RING_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
    slot.selectedHighlight:Show()
end

------------------------------------------------------------------------
-- Copy Customization: armed from the entry context menu's "Copy
-- Customization To..." submenu. While armed, a banner rides the preview,
-- compatible entries ring green, and left-clicking one copies the armed
-- customization onto it. The mode survives panel switches (any compatible
-- entry anywhere is a target) and stays armed after each apply; Esc
-- (Panel.lua's key chain), right-click, or clicking the source cancels.
--
-- Wrapped in a do-block: the block's locals release their register slots
-- at its end, keeping the main chunk under Lua's 200-local ceiling; the
-- survivors publish through the CopyMode table declared up top.
------------------------------------------------------------------------
do

local PANEL_PREVIEW_COPY_COLOR = { 0.30, 0.90, 0.45, 1 }
local PANEL_PREVIEW_COPY_BANNER_HEIGHT = 20

-- Helpers.lua loads before this file (config toc order), so its exports are
-- real by the time this chunk runs and are captured as block upvalues. A
-- missing export would be a packaging error; nothing here fails open.
local CanUseConfigOverrideSection = ST._CanButtonUseConfigOverrideSection
local GroupSupportsPerButtonOverrides = ST._GroupSupportsPerButtonOverrides

-- Resolves the armed source from ids at call time: the mode outlives
-- arbitrary user actions, so the index may have shifted (reorder,
-- duplicate) or the entry may be gone entirely. sourceRef is the identity
-- token; a repairable shift re-stamps the index, anything else is nil.
local function ResolveCopyCustomizationSource(state)
    local groups = CooldownCompanion.db.profile.groups
    local group = groups and groups[state.sourceGroupId]
    if not (group and group.buttons) then return nil end
    local buttonData = group.buttons[state.sourceButtonIndex]
    if buttonData == state.sourceRef then
        return group, buttonData
    end
    for i, candidate in ipairs(group.buttons) do
        if candidate == state.sourceRef then
            state.sourceButtonIndex = i
            return group, candidate
        end
    end
    return nil
end

local function CancelCopyCustomization(options)
    if not CS.copyCustomization then return end
    CS.copyCustomization = nil
    if not (options and options.skipRefresh) then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function ArmCopyCustomization(groupId, buttonIndex, buttonData, scope, sectionId)
    -- Rival modes own the same columns and selection stores.
    if CS.exportMode and ST._ExitExportMode then
        ST._ExitExportMode({ skipRefresh = true })
    end
    if CS.importMode and ST._ExitImportMode then
        ST._ExitImportMode({ skipRefresh = true })
    end
    if CS.copyPanelSettings and ST._CancelCopyPanelSettings then
        ST._CancelCopyPanelSettings({ skipRefresh = true })
    end
    wipe(CS.selectedButtons)
    CS.copyCustomization = {
        sourceGroupId = groupId,
        sourceButtonIndex = buttonIndex,
        sourceRef = buttonData,
        scope = scope,
        sectionId = sectionId,
    }
    CooldownCompanion:RefreshConfigPanel()
end

ST._ArmCopyCustomization = ArmCopyCustomization
ST._CancelCopyCustomization = CancelCopyCustomization

local function GetCopyCustomizationLabel(state)
    if state.scope == "format" then return "Text Format" end
    if state.scope == "all" then return "All Customizations" end
    local sectionDef = ST.OVERRIDE_SECTIONS[state.sectionId]
    return sectionDef and sectionDef.label or tostring(state.sectionId)
end

local function CanCopySectionToEntry(targetGroup, targetButtonData, sectionId)
    local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
    if not sectionDef then return false end
    if sectionDef.modes[targetGroup.displayMode or "icons"] ~= true then return false end
    -- == true drops the reason the helper returns alongside its verdict.
    return CanUseConfigOverrideSection(targetButtonData, sectionId) == true
end

local function IsEligibleCopyTarget(state, targetGroup, targetButtonData)
    if not (state and targetGroup and targetButtonData) then return false end
    local sourceGroup, sourceData = ResolveCopyCustomizationSource(state)
    if not sourceData or targetButtonData == sourceData then return false end
    if not GroupSupportsPerButtonOverrides(targetGroup) then return false end
    -- The mode outlives arbitrary edits, so the armed payload can be
    -- reverted on the source while the rings are up. A vanished payload
    -- must fail here: a nil format would WIPE the target's saved format,
    -- and a cleared section would no-op while reporting success.
    if state.scope == "format" then
        return sourceData.textFormat ~= nil
            and (targetGroup.displayMode or "icons") == "text"
    end
    if state.scope == "section" then
        if not (sourceData.overrideSections
            and sourceData.overrideSections[state.sectionId]) then
            return false
        end
        return CanCopySectionToEntry(targetGroup, targetButtonData, state.sectionId)
    end
    -- "all": eligible when at least one of the source's customizations lands.
    if sourceData.textFormat ~= nil and (targetGroup.displayMode or "icons") == "text" then
        return true
    end
    for sectionId in pairs(sourceData.overrideSections or {}) do
        if CanCopySectionToEntry(targetGroup, targetButtonData, sectionId) then
            return true
        end
    end
    return false
end

-- Returns true when the click was consumed by an armed copy mode.
local function HandleCopyCustomizationClick(panelId, index, buttonData)
    local state = CS.copyCustomization
    if not state then return false end
    local targetGroup = CooldownCompanion.db.profile.groups[panelId]
    if not targetGroup then return false end
    local sourceGroup, sourceData = ResolveCopyCustomizationSource(state)
    if not sourceData then
        -- The armed source no longer exists; nothing sane to copy.
        CancelCopyCustomization()
        return true
    end
    if buttonData == sourceData then
        CancelCopyCustomization()
        return true
    end
    if not IsEligibleCopyTarget(state, targetGroup, buttonData) then
        -- Ineligible entry: stay armed; the hover tooltip explains why.
        return true
    end

    local sourceStyle = sourceGroup.style or {}
    local applied, skipped, formatCopied = 0, 0, false
    if state.scope == "section" then
        if CooldownCompanion:CopySectionOverride(sourceData, sourceStyle, buttonData, state.sectionId) then
            applied = 1
        end
    elseif state.scope == "format" then
        -- Eligibility guaranteed a non-nil source format at this click.
        buttonData.textFormat = sourceData.textFormat
        formatCopied = true
        applied = 1
    else
        local sections = sourceData.overrideSections or {}
        for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER or {}) do
            if sections[sectionId] then
                if CanCopySectionToEntry(targetGroup, buttonData, sectionId)
                    and CooldownCompanion:CopySectionOverride(sourceData, sourceStyle, buttonData, sectionId) then
                    applied = applied + 1
                else
                    skipped = skipped + 1
                end
            end
        end
        if sourceData.textFormat ~= nil then
            if (targetGroup.displayMode or "icons") == "text" then
                buttonData.textFormat = sourceData.textFormat
                formatCopied = true
                applied = applied + 1
            else
                skipped = skipped + 1
            end
        end
    end

    if applied == 0 then
        -- Nothing landed (the payload vanished between the eligibility check
        -- and the write). Leave the target untouched and report nothing.
        return true
    end

    CooldownCompanion:UpdateGroupStyle(panelId)
    -- The format is re-parsed on the way through PopulateGroupButtons, which
    -- only the frame refresh reaches. Paid only when a format actually copied.
    if formatCopied then
        CooldownCompanion:RefreshGroupFrame(panelId)
    end
    local name = GetConfigEntryDisplayName(buttonData) or buttonData.name or "entry"
    if skipped > 0 then
        state.lastAppliedText = ("Applied to %s (%d of %d)"):format(name, applied, applied + skipped)
    else
        state.lastAppliedText = "Applied to " .. name
    end
    CooldownCompanion:RefreshConfigPanel()
    return true
end

local function EnsureCopyCustomizationBanner(preview)
    -- The unified anchor composition builds the mirror into an inner host
    -- shrunk to the panel content, where a banner would sit on the entries
    -- themselves; it passes the outer Live Preview host so the strip reads
    -- at the top of the whole preview instead. Re-anchored on every ensure:
    -- the same preview state can build under either composition.
    local bannerHost = preview.copyBannerHost or preview.root
    local banner = preview.copyBanner
    if banner then
        banner:SetParent(bannerHost)
        banner:ClearAllPoints()
        banner:SetPoint("TOPLEFT", bannerHost, "TOPLEFT", 0, 0)
        banner:SetPoint("TOPRIGHT", bannerHost, "TOPRIGHT", 0, 0)
        return banner
    end

    -- Slim full-width strip whose dark fill and green accent line fade out
    -- toward the sides (the retired override-targeting banner's shape).
    banner = CreateFrame("Frame", nil, bannerHost)
    banner:SetPoint("TOPLEFT", bannerHost, "TOPLEFT", 0, 0)
    banner:SetPoint("TOPRIGHT", bannerHost, "TOPRIGHT", 0, 0)
    banner:SetHeight(PANEL_PREVIEW_COPY_BANNER_HEIGHT)

    local clear = CreateColor(0, 0, 0, 0)
    local fill = CreateColor(0, 0, 0, 0.7)
    local accent = CreateColor(PANEL_PREVIEW_COPY_COLOR[1],
        PANEL_PREVIEW_COPY_COLOR[2], PANEL_PREVIEW_COPY_COLOR[3], 0.8)
    banner.bgLeft = banner:CreateTexture(nil, "BACKGROUND")
    banner.bgLeft:SetPoint("TOPLEFT")
    banner.bgLeft:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", 0, 0)
    banner.bgLeft:SetTexture("Interface/Buttons/WHITE8x8")
    banner.bgLeft:SetGradient("HORIZONTAL", clear, fill)
    banner.bgRight = banner:CreateTexture(nil, "BACKGROUND")
    banner.bgRight:SetPoint("TOPLEFT", banner, "TOP", 0, 0)
    banner.bgRight:SetPoint("BOTTOMRIGHT")
    banner.bgRight:SetTexture("Interface/Buttons/WHITE8x8")
    banner.bgRight:SetGradient("HORIZONTAL", fill, clear)

    banner.lineLeft = banner:CreateTexture(nil, "BORDER")
    banner.lineLeft:SetPoint("BOTTOMLEFT")
    banner.lineLeft:SetPoint("BOTTOMRIGHT", banner, "BOTTOM", 0, 0)
    banner.lineLeft:SetHeight(1)
    banner.lineLeft:SetTexture("Interface/Buttons/WHITE8x8")
    banner.lineLeft:SetGradient("HORIZONTAL", clear, accent)
    banner.lineRight = banner:CreateTexture(nil, "BORDER")
    banner.lineRight:SetPoint("BOTTOMLEFT", banner, "BOTTOM", 0, 0)
    banner.lineRight:SetPoint("BOTTOMRIGHT")
    banner.lineRight:SetHeight(1)
    banner.lineRight:SetTexture("Interface/Buttons/WHITE8x8")
    banner.lineRight:SetGradient("HORIZONTAL", accent, clear)

    banner.text = banner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Nudged right so the crosshair + text block reads centered.
    banner.text:SetPoint("CENTER", banner, "CENTER", 9, 0)
    banner.text:SetJustifyH("LEFT")
    banner.text:SetWordWrap(false)

    banner.crosshair = banner:CreateTexture(nil, "OVERLAY")
    banner.crosshair:SetSize(12, 12)
    banner.crosshair:SetPoint("RIGHT", banner.text, "LEFT", -5, 0)
    banner.crosshair:SetAtlas("Crosshair_VehichleCursor_32")
    banner.crosshair:SetVertexColor(PANEL_PREVIEW_COPY_COLOR[1],
        PANEL_PREVIEW_COPY_COLOR[2], PANEL_PREVIEW_COPY_COLOR[3])

    banner:Hide()
    preview.copyBanner = banner
    return banner
end

-- Rebuilt with every preview build: the mode deliberately survives panel
-- switches, so whichever panel the preview shows carries the banner.
local function UpdateCopyCustomizationBanner(preview)
    local state = preview.readOnly ~= true and CS.copyCustomization or nil
    if state and not ResolveCopyCustomizationSource(state) then
        -- The armed source is gone (deleted, moved away, profile changed).
        -- Clear silently - we're already mid-rebuild.
        CS.copyCustomization = nil
        state = nil
    end

    local banner = preview.copyBanner
    if not state then
        if banner then banner:Hide() end
        return
    end

    banner = EnsureCopyCustomizationBanner(preview)
    local text = "Click an entry to apply |cffffd100"
        .. GetCopyCustomizationLabel(state) .. "|r"
    if state.lastAppliedText then
        text = text .. "  |cff99e6a3" .. state.lastAppliedText .. "|r"
    end
    banner.text:SetText(text)
    banner:SetFrameLevel((preview.copyBannerHost or preview.root):GetFrameLevel() + 40)
    banner:Show()
end

-- Green ring on the entries an armed copy click can land on. A dedicated
-- frame, NOT slot.selectedHighlight: the source entry is usually still
-- selected while the mode is armed, so the two rings coexist.
local function ApplyCopyTargetVisuals(slot, panelId, buttonData)
    local state = CS.copyCustomization
    local eligible = false
    if state and panelId and buttonData then
        local targetGroup = CooldownCompanion.db.profile.groups[panelId]
        eligible = IsEligibleCopyTarget(state, targetGroup, buttonData)
    end
    if not eligible then
        if slot.copyTargetHighlight then slot.copyTargetHighlight:Hide() end
        return
    end

    local highlight = slot.copyTargetHighlight
    if not highlight then
        highlight = CreateFrame("Frame", nil, slot)
        highlight:SetAllPoints(slot)
        highlight:EnableMouse(false)
        highlight.ringTextures = {}
        for i = 1, 4 do
            highlight.ringTextures[i] = highlight:CreateTexture(nil, "OVERLAY")
        end
        slot.copyTargetHighlight = highlight
    end
    highlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
    ST.ApplyBorderTextures(highlight.ringTextures, highlight,
        PANEL_PREVIEW_COPY_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
    highlight:Show()
end

CopyMode.COLOR = PANEL_PREVIEW_COPY_COLOR
CopyMode.Cancel = CancelCopyCustomization
CopyMode.GetLabel = GetCopyCustomizationLabel
CopyMode.IsEligibleTarget = IsEligibleCopyTarget
CopyMode.HandleClick = HandleCopyCustomizationClick
CopyMode.UpdateBanner = UpdateCopyCustomizationBanner
CopyMode.ApplyTargetVisuals = ApplyCopyTargetVisuals

end

local function CollectEntryMetadata(buttonData, group)
    -- The per-entry text format is the flat buttonData.textFormat field (never
    -- part of the styleOverrides sections), so it needs its own check to count
    -- as a customization. Counted in EVERY display mode: a format stranded on
    -- a panel that left text mode is still saved, and the Customizations list
    -- and this badge must agree about whether the entry customizes anything.
    local hasOverrides = CooldownCompanion:HasStyleOverrides(buttonData) and true or false
    if not hasOverrides and buttonData.textFormat ~= nil then
        hasOverrides = true
    end
    local status = {
        override = hasOverrides,
        fallback = CooldownCompanion.HasItemFallbacks(buttonData) and true or false,
        talent = (buttonData.talentConditions and #buttonData.talentConditions > 0) and true or false,
        sound = false,
    }
    if buttonData.type == "spell" then
        local enabledSoundEvents = CooldownCompanion:GetEnabledSoundAlertEventsForButton(buttonData)
        -- The aura sounds are config-only (played by the game's aura
        -- system, never the runtime engine), so they need their own check.
        if not enabledSoundEvents
            and (buttonData.auraTracking or buttonData.addedAs == "aura")
            and CooldownCompanion:HasAnyAuraSoundForButton(buttonData) then
            enabledSoundEvents = true
        end
        status.sound = enabledSoundEvents and true or false
    end
    return status
end

-- Aura activity is hidden from addon code during restricted gameplay. An
-- entry that hides with its aura therefore keeps its layout slot even though
-- Blizzard can hide the AuraButton drawn inside it. Surface that limitation
-- directly on the live preview instead of making Compact Mode look broken.
--
-- Never on an Aura Panel: Blizzard's own container lays those cells out and
-- packs only the active auras, so nothing is reserved and the badge would be
-- claiming the opposite of what the panel does.
local function DoesHiddenAuraReserveLayoutSpace(buttonData, group)
    local displayMode = group and (group.displayMode or "icons") or "icons"
    return (displayMode == "icons" or displayMode == "bars")
        and not ST.IsAuraPanelGroup(group)
        and buttonData.type == "spell"
        and (buttonData.auraTracking or buttonData.addedAs == "aura")
        and buttonData.hideWhileAuraNotActive == true
end

-- Entry status signals shared with the workspace entry-row presentation.
local function CollectEntryStatus(buttonData, group)
    local status = CollectEntryMetadata(buttonData, group)
    local usable = CooldownCompanion:IsButtonUsable(buttonData, group)
    local loadAllowed = CooldownCompanion:IsButtonLoadConditionMet(buttonData, group)
    status.usable = usable
    status.disabled = buttonData.enabled == false
    status.warn = (not usable) and buttonData.enabled ~= false
    status.loadBlocked = not loadAllowed
    status.auraHideReservesSpace = DoesHiddenAuraReserveLayoutSpace(buttonData, group)
    return status
end

-- Bar mirrors are saved-config projections. Live usability and load-condition
-- results may still inform other preview modes, but they must not leak into a
-- Bar slot's tint, problem badge, or hidden-state explanation.
local function CollectBarEntryStatus(buttonData, group)
    local status = CollectEntryMetadata(buttonData, group)
    status.usable = true
    status.auraHideReservesSpace = DoesHiddenAuraReserveLayoutSpace(buttonData, group)
    return status
end

-- Ordered badge descriptors, same atlases and meaning as the retired
-- workspace entry rows; the identity strip renders the
-- full set. The "warn" label is replaced with the load-conditions wording
-- when status.loadBlocked is set.
local ENTRY_STATUS_BADGES = {
    { key = "disabled", atlas = "GM-icon-visibleDis-pressed", label = "Disabled" },
    { key = "warn", atlas = "Ping_Marker_Icon_Warning", label = "Spell/item unavailable" },
    { key = "override", atlas = "Crosshair_VehichleCursor_32", label = "Has customized sections" },
    { key = "fallback", atlas = "banker", label = "Uses item fallbacks" },
    { key = "sound", atlas = "common-icon-sound", label = "Sound alerts enabled" },
    { key = "talent", atlas = "UI-HUD-MicroMenu-SpecTalents-Mouseover", label = "Has talent conditions" },
}

-- key → atlas, for the hover tooltip's inline badge marks: each tooltip
-- section opens with the same badge the slot corner and identity strip
-- wear, so the two surfaces cannot drift apart.
local ENTRY_STATUS_BADGE_ATLAS = {}
for _, desc in ipairs(ENTRY_STATUS_BADGES) do
    ENTRY_STATUS_BADGE_ATLAS[desc.key] = desc.atlas
end

-- Status indicators in the slot's top-right corner. Disabled and
-- unusable/blocked entries use the existing dark-backed problem marks; an
-- aura whose hidden slot cannot collapse uses the established information
-- badge instead. Entries with appearance overrides carry their own badge
-- (the identity strip's override crosshair) riding left of any problem
-- mark, so overrides read at a glance across the whole preview. Other
-- informational badges (talent, sound, fallback) live in the identity
-- strip and the hover tooltip.
local function ApplySlotBadges(slot, status, scale, suppress)
    local size = math_min(24,
        math_max(12, PANEL_PREVIEW_BADGE_SCREEN_SIZE / math_max(scale, 0.01)))
    local hasVisibilityBadge = slot._cdcVisibilityBadgeShown == true
    local badgeAnchor = hasVisibilityBadge and slot.barBounds or slot
    local cornerOffset = hasVisibilityBadge and -(size + 2) or 0

    local atlas
    local isReservedSpaceBadge = false
    if not suppress and status.disabled then
        atlas = "GM-icon-visibleDis-pressed"
    elseif not suppress and status.warn then
        atlas = "Ping_Marker_Icon_Warning"
    elseif not suppress and status.auraHideReservesSpace then
        atlas = PANEL_PREVIEW_AURA_SPACE_BADGE_ATLAS
        isReservedSpaceBadge = true
    end
    if atlas then
        local tex = slot.problemBadge
        local back = slot.problemBadgeBack
        if not tex then
            back = slot:CreateTexture(nil, "OVERLAY", nil, 6)
            back:SetColorTexture(0, 0, 0, 0.7)
            slot.problemBadgeBack = back
            tex = slot:CreateTexture(nil, "OVERLAY", nil, 7)
            slot.problemBadge = tex
        end
        tex:SetAtlas(atlas, false)
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        tex:SetPoint("TOPRIGHT", badgeAnchor, "TOPRIGHT", cornerOffset, 0)
        back:ClearAllPoints()
        back:SetPoint("CENTER", tex, "CENTER", 0, 0)
        back:SetSize(size + 2, size + 2)
        tex:Show()
        if isReservedSpaceBadge then
            back:Hide()
        else
            back:Show()
        end
    else
        if slot.problemBadge then slot.problemBadge:Hide() end
        if slot.problemBadgeBack then slot.problemBadgeBack:Hide() end
    end

    if not suppress and status.override then
        local tex = slot.overrideBadge
        local back = slot.overrideBadgeBack
        if not tex then
            back = slot:CreateTexture(nil, "OVERLAY", nil, 6)
            back:SetColorTexture(0, 0, 0, 0.7)
            slot.overrideBadgeBack = back
            tex = slot:CreateTexture(nil, "OVERLAY", nil, 7)
            slot.overrideBadge = tex
        end
        tex:SetAtlas("Crosshair_VehichleCursor_32", false)
        tex:SetSize(size, size)
        tex:ClearAllPoints()
        if atlas then
            tex:SetPoint("TOPRIGHT", slot.problemBadge, "TOPLEFT", -4, 0)
        else
            tex:SetPoint("TOPRIGHT", badgeAnchor, "TOPRIGHT", cornerOffset, 0)
        end
        back:ClearAllPoints()
        back:SetPoint("CENTER", tex, "CENTER", 0, 0)
        back:SetSize(size + 2, size + 2)
        tex:Show()
        back:Show()
    else
        if slot.overrideBadge then slot.overrideBadge:Hide() end
        if slot.overrideBadgeBack then slot.overrideBadgeBack:Hide() end
    end
end

local function ApplyBarVisibilityBadge(slot, show, scale)
    if not show then
        if slot.visibilityBadge then slot.visibilityBadge:Hide() end
        slot._cdcVisibilityBadgeShown = false
        return
    end

    local badge = slot.visibilityBadge
    if not badge then
        badge = slot:CreateTexture(nil, "OVERLAY", nil, 7)
        slot.visibilityBadge = badge
    end
    local size = math_min(24, math_max(12,
        PANEL_PREVIEW_VISIBILITY_BADGE_SCREEN_SIZE / math_max(scale or 1, 0.01)))
    badge:SetAtlas(PANEL_PREVIEW_VISIBILITY_BADGE_ATLAS, false)
    badge:SetSize(size, size)
    badge:ClearAllPoints()
    badge:SetPoint("RIGHT", slot.barBounds, "RIGHT", 0, 0)
    badge:Show()
    slot._cdcVisibilityBadgeShown = true
end

local function ApplyBarSlotPreviewVisibility(slot, visibility, scale, isSelected)
    slot._cdcBarPreviewVisibility = visibility
    slot._cdcBarPreviewScale = scale

    local exactPreview = visibility and visibility.exactPreview == true
    local hidden = visibility and visibility.underlyingMode == "hidden"
    local hovered = slot._cdcBarPreviewHovered == true
    if not hovered and slot.IsMouseOver and slot:IsMouseOver() then
        hovered = true
        slot._cdcBarPreviewHovered = true
    end

    local alpha = visibility and visibility.visualAlpha or 1
    if hidden and not exactPreview then
        if isSelected then
            alpha = 1
        elseif hovered then
            alpha = PANEL_PREVIEW_GHOST_HOVER_ALPHA
        end
    end
    ApplyBarSlotVisualAlpha(slot, alpha)
    ApplyBarVisibilityBadge(slot, hidden and not exactPreview, scale)

    if hovered and not exactPreview then
        slot.hoverHighlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
        slot.hoverHighlight:Show()
    else
        slot.hoverHighlight:Hide()
    end
end

local function RefreshBarSlotWorkspacePresentation(slot)
    local visibility = slot._cdcBarPreviewVisibility
    if not visibility then return end
    ApplyBarSlotPreviewVisibility(slot, visibility, slot._cdcBarPreviewScale,
        IsEntrySelected(slot._cdcEntryIndex))
    ApplySlotBadges(slot, slot._cdcEntryStatus or {}, slot._cdcBarPreviewScale,
        visibility.exactPreview == true)
end

------------------------------------------------------------------------
-- In-preview drag-to-reorder, via the shared "layout-slot" drag kind.
-- Slots map 1:1 to group.buttons indices; the resolved drop target is an
-- insertion index in the pre-removal list (PerformButtonReorder's
-- convention). Raw cursor coordinates are compared against GetScaledRect
-- values, matching the drag tracker and the resources layout preview.
------------------------------------------------------------------------
-- Slot placement with tween bookkeeping (the resources preview's
-- ApplySlotGeometry/QueueSlotTween pattern, reduced to position-only:
-- slot sizes never change during a reorder drag).
local function ApplyPreviewSlotGeometry(preview, slot, anchor, x, y)
    slot:ClearAllPoints()
    slot:SetPoint(anchor, preview.content, anchor, x, y)
    slot._cdcPrevAnchor = anchor
    slot._cdcPrevX = x
    slot._cdcPrevY = y
    if preview.tweens then
        preview.tweens[slot] = nil
    end
end

local function QueuePreviewSlotTween(preview, slot, anchor, x, y)
    if slot._cdcPrevAnchor ~= anchor or not slot._cdcPrevX then
        ApplyPreviewSlotGeometry(preview, slot, anchor, x, y)
        return
    end
    local cx, cy = slot._cdcPrevX, slot._cdcPrevY
    if math.abs(cx - x) < 0.5 and math.abs(cy - y) < 0.5 then
        ApplyPreviewSlotGeometry(preview, slot, anchor, x, y)
        return
    end
    preview.tweens[slot] = {
        anchor = anchor,
        sx = cx, sy = cy,
        tx = x, ty = y,
        t0 = GetTime(),
        dur = PANEL_PREVIEW_ANIM_DURATION,
    }
end

local function EaseInOut(t)
    return t < 0.5 and (2 * t * t) or (1 - (((-2 * t + 2) ^ 2) / 2))
end

local function Interpolate(a, b, t)
    return a + ((b - a) * t)
end

local function UpdateGhostPosition(ghost)
    if not (ghost and ghost:IsShown()) then return end
    local uiScale = UIParent:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / uiScale
    cursorY = cursorY / uiScale
    local offsetX = math_floor((ghost:GetWidth() or 0) / 2)
    local offsetY = math_floor((ghost:GetHeight() or 0) / 2)
    ghost:ClearAllPoints()
    ghost:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cursorX - offsetX, cursorY + offsetY)
end

local function TickPanelPreview(preview)
    local active = false
    local now = GetTime()
    for slot, tween in pairs(preview.tweens) do
        local progress = math_min(1, math_max(0, (now - tween.t0) / tween.dur))
        local eased = EaseInOut(progress)
        local x = Interpolate(tween.sx, tween.tx, eased)
        local y = Interpolate(tween.sy, tween.ty, eased)
        slot:ClearAllPoints()
        slot:SetPoint(tween.anchor, preview.content, tween.anchor, x, y)
        slot._cdcPrevAnchor = tween.anchor
        slot._cdcPrevX = x
        slot._cdcPrevY = y
        if progress >= 1 then
            preview.tweens[slot] = nil
        else
            active = true
        end
    end
    UpdateGhostPosition(preview.ghost)
    if not active and not preview.ghostActive then
        preview.root:SetScript("OnUpdate", nil)
    end
end

local function StartPreviewTicker(preview)
    preview.root:SetScript("OnUpdate", function()
        TickPanelPreview(preview)
    end)
end

-- Cursor-following ghost: the dragged entry's footprint with its icon
-- centered, floating on the tooltip strata like the resources ghost.
local function EnsurePreviewGhost(preview)
    local ghost = preview.ghost
    if not ghost then
        ghost = CreateFrame("Frame", nil, UIParent)
        ghost:SetFrameStrata("TOOLTIP")
        ghost:SetFrameLevel(2000)
        ghost:EnableMouse(false)
        ghost.bg = ghost:CreateTexture(nil, "BACKGROUND")
        ghost.bg:SetAllPoints()
        ghost.bg:SetColorTexture(0.05, 0.10, 0.18, 0.55)
        ghost.icon = ghost:CreateTexture(nil, "ARTWORK")
        ghost.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        ghost:Hide()
        preview.ghost = ghost
    end
    return ghost
end

local function ConfigurePreviewGhost(preview, layoutDrag, buttonData)
    local ghost = EnsurePreviewGhost(preview)
    local scale = layoutDrag.scale
    local gw = math_max(8, layoutDrag.slotW * scale)
    local gh = math_max(8, layoutDrag.slotH * scale)
    ghost:SetSize(gw, gh)
    local iconSize = math_min(gw, gh)
    ghost.icon:ClearAllPoints()
    ghost.icon:SetSize(iconSize, iconSize)
    ghost.icon:SetPoint("CENTER")
    local iconResolver = layoutDrag.iconResolver or GetLayoutPreviewIcon
    local icon = iconResolver and iconResolver(buttonData)
    if icon then
        ghost.icon:SetTexture(icon)
        ghost.icon:Show()
    else
        ghost.icon:Hide()
    end
    ghost:SetAlpha(0.9)
    ghost:Show()
    preview.ghostActive = true
    UpdateGhostPosition(ghost)
end

local function ClearPreviewGhost(preview)
    preview.ghostActive = false
    if preview.ghost then
        preview.ghost:Hide()
    end
end

-- Translucent marker filling the cell the entry would land in.
local function EnsureGapFrame(preview)
    local gap = preview.gapFrame
    if not gap then
        gap = CreateFrame("Frame", nil, preview.content)
        gap.bg = gap:CreateTexture(nil, "BACKGROUND")
        gap.bg:SetAllPoints()
        gap.bg:SetColorTexture(PANEL_PREVIEW_RING_COLOR[1], PANEL_PREVIEW_RING_COLOR[2],
            PANEL_PREVIEW_RING_COLOR[3], 0.18)
        preview.gapFrame = gap
    end
    return gap
end

-- Slide the remaining slots into the arrangement they'd have after the
-- drop: the lifted entry's slot goes invisible, the others compact in
-- order with a gap held open at the insertion cell.
local function UpdateGridDragPreview(preview, layoutDrag, sourceIndex, dropTarget)
    local insertIndex = dropTarget and dropTarget.insertIndex
    local gapPos
    if insertIndex then
        gapPos = insertIndex
        if gapPos > sourceIndex then gapPos = gapPos - 1 end
        if gapPos > layoutDrag.count then gapPos = layoutDrag.count end
    end
    local renderIndex = 1
    for i = 1, layoutDrag.count do
        local slot = layoutDrag.slots[i]
        if slot then
            if i == sourceIndex then
                slot:SetAlpha(0)
            else
                local displayIndex = renderIndex
                if gapPos and displayIndex >= gapPos then
                    displayIndex = displayIndex + 1
                end
                local x, y = layoutDrag.cellXY(displayIndex)
                QueuePreviewSlotTween(preview, slot, layoutDrag.anchor, x, y)
                renderIndex = renderIndex + 1
            end
        end
    end
    if gapPos then
        local gap = EnsureGapFrame(preview)
        gap:SetSize(layoutDrag.slotW, layoutDrag.slotH)
        local x, y = layoutDrag.cellXY(gapPos)
        QueuePreviewSlotTween(preview, gap, layoutDrag.anchor, x, y)
        gap:Show()
    elseif preview.gapFrame then
        preview.gapFrame:Hide()
    end
end

local function ResetGridDragPreview(preview, layoutDrag)
    for i = 1, layoutDrag.count do
        local slot = layoutDrag.slots[i]
        if slot then
            local x, y = layoutDrag.cellXY(i)
            QueuePreviewSlotTween(preview, slot, layoutDrag.anchor, x, y)
            slot:SetAlpha(slot._cdcBaseAlpha or 1)
        end
    end
    if preview.gapFrame then
        preview.gapFrame:Hide()
    end
end

local function CreatePreviewLayoutDrag(preview, panelId)
    -- Builders fill in count, slotW/H, scale, anchor, and cellXY (display
    -- cell index -> anchored x,y offset) after creating the model.
    local layoutDrag = {
        panelPreview = true,
        slots = {},
        count = 0,
        slotW = 1,
        slotH = 1,
        scale = 1,
        anchor = "TOPLEFT",
    }

    -- Insertion anchors: midpoints between consecutive slot centers within
    -- a run (row or column), end positions extrapolated half a step beyond
    -- the run, and TWO anchors per wrap boundary (end of the previous run
    -- plus start of the next, same insertion index) — a raw midpoint there
    -- would sit diagonally between the runs in empty space and misassign
    -- drops near row/column edges. Pure geometry: covers both orientations
    -- and every growth origin.
    layoutDrag.resolveDropTarget = function(cursorX, cursorY)
        local count = layoutDrag.count
        if count < 2 then return nil end
        local root = preview.root
        if not (root and root:IsVisible() and root.GetScaledRect) then return nil end
        local left, bottom, width, height = root:GetScaledRect()
        if not left then return nil end
        local margin = 40
        if cursorX < left - margin or cursorX > left + width + margin
            or cursorY < bottom - margin or cursorY > bottom + height + margin then
            return nil
        end

        -- Base cell centers, NOT live slot rects: the slots animate while
        -- a drag is held, and resolving against moving frames would make
        -- the drop target oscillate under the cursor (the "stable slots"
        -- trick from the resources preview).
        local content = preview.content
        local cLeft, cBottom, cWidth, cHeight = content:GetScaledRect()
        if not (cLeft and cBottom and cWidth and cHeight) then return nil end
        local localW = content:GetWidth() or 1
        local localH = content:GetHeight() or 1
        local factor = (localW > 0) and (cWidth / localW) or 1
        local anchor = layoutDrag.anchor
        local slotW, slotH = layoutDrag.slotW, layoutDrag.slotH

        local centers = {}
        for i = 1, count do
            local x, y = layoutDrag.cellXY(i)
            -- Convert the anchored offset to top-left space, then to the
            -- scaled screen coordinates raw cursor values live in.
            local tlX, tlY
            if anchor == "TOPLEFT" then
                tlX, tlY = x + slotW / 2, y - slotH / 2
            elseif anchor == "TOPRIGHT" then
                tlX, tlY = localW + x - slotW / 2, y - slotH / 2
            elseif anchor == "BOTTOMLEFT" then
                tlX, tlY = x + slotW / 2, -localH + y + slotH / 2
            elseif anchor == "TOP" then
                tlX, tlY = localW / 2 + x, y - slotH / 2
            elseif anchor == "BOTTOM" then
                tlX, tlY = localW / 2 + x, -localH + y + slotH / 2
            elseif anchor == "LEFT" then
                tlX, tlY = x + slotW / 2, -localH / 2 + y
            elseif anchor == "RIGHT" then
                tlX, tlY = localW + x - slotW / 2, -localH / 2 + y
            else -- BOTTOMRIGHT
                tlX, tlY = localW + x - slotW / 2, -localH + y + slotH / 2
            end
            centers[i] = {
                x = cLeft + tlX * factor,
                y = cBottom + cHeight + tlY * factor,
            }
        end

        -- Consecutive centers share a run when they stay on the same row
        -- line (small y delta) or column line (small x delta); a wrap jump
        -- always moves a full cell on both axes.
        local halfW = slotW * factor / 2
        local halfH = slotH * factor / 2
        local function sameRun(a, b)
            return math.abs(centers[b].y - centers[a].y) < halfH
                or math.abs(centers[b].x - centers[a].x) < halfW
        end
        -- Intra-run step at slot i; single-slot runs (e.g. a short last
        -- row) borrow the first measurable step so their boundary anchors
        -- still sit beside the slot instead of on top of it.
        local globalStepX, globalStepY = 0, 0
        for i = 1, count - 1 do
            if sameRun(i, i + 1) then
                globalStepX = centers[i + 1].x - centers[i].x
                globalStepY = centers[i + 1].y - centers[i].y
                break
            end
        end
        local function runStep(i)
            if i < count and sameRun(i, i + 1) then
                return centers[i + 1].x - centers[i].x, centers[i + 1].y - centers[i].y
            end
            if i > 1 and sameRun(i - 1, i) then
                return centers[i].x - centers[i - 1].x, centers[i].y - centers[i - 1].y
            end
            return globalStepX, globalStepY
        end

        local candidates = {}
        local function AddCandidate(x, y, insertIndex)
            candidates[#candidates + 1] = { x = x, y = y, insertIndex = insertIndex }
        end
        local sx, sy = runStep(1)
        AddCandidate(centers[1].x - sx / 2, centers[1].y - sy / 2, 1)
        for i = 2, count do
            if sameRun(i - 1, i) then
                AddCandidate((centers[i - 1].x + centers[i].x) / 2,
                    (centers[i - 1].y + centers[i].y) / 2, i)
            else
                local ex, ey = runStep(i - 1)
                AddCandidate(centers[i - 1].x + ex / 2, centers[i - 1].y + ey / 2, i)
                local bx, by = runStep(i)
                AddCandidate(centers[i].x - bx / 2, centers[i].y - by / 2, i)
            end
        end
        local ex, ey = runStep(count)
        AddCandidate(centers[count].x + ex / 2, centers[count].y + ey / 2, count + 1)

        local bestIndex, bestDist
        for _, cand in ipairs(candidates) do
            local dx, dy = cursorX - cand.x, cursorY - cand.y
            local dist = dx * dx + dy * dy
            if not bestDist or dist < bestDist then
                bestDist, bestIndex = dist, cand.insertIndex
            end
        end
        return { insertIndex = bestIndex }
    end

    layoutDrag.onActivate = function(state)
        GameTooltip:Hide()
        local sourceIndex = state.slotData and state.slotData.index
        local slot = sourceIndex and layoutDrag.slots[sourceIndex]
        if slot and slot.hoverHighlight then
            slot.hoverHighlight:Hide()
        end
        ConfigurePreviewGhost(preview, layoutDrag, state.slotData and state.slotData.buttonData)
        UpdateGridDragPreview(preview, layoutDrag, sourceIndex, state.dropTarget)
        StartPreviewTicker(preview)
    end

    layoutDrag.onUpdate = function(state, cursorX, cursorY, dropTarget)
        local sourceIndex = state.slotData and state.slotData.index
        if not sourceIndex then return end
        UpdateGridDragPreview(preview, layoutDrag, sourceIndex, dropTarget)
        if not preview.ghostActive then
            ConfigurePreviewGhost(preview, layoutDrag, state.slotData.buttonData)
        end
        StartPreviewTicker(preview)
    end

    layoutDrag.onCancel = function()
        ResetGridDragPreview(preview, layoutDrag)
        ClearPreviewGhost(preview)
        -- Keep ticking so the return-to-rest tween plays out
        StartPreviewTicker(preview)
    end

    layoutDrag.applyDrop = function(state)
        local dropTarget = state and state.dropTarget
        local sourceIndex = state and state.slotData and state.slotData.index
        local insertIndex = dropTarget and dropTarget.insertIndex
        if not (PerformButtonReorder and sourceIndex and insertIndex) then return end
        if insertIndex == sourceIndex or insertIndex == sourceIndex + 1 then return end
        PerformButtonReorder(panelId, sourceIndex, insertIndex)
        CooldownCompanion:RefreshGroupFrame(panelId)
        CooldownCompanion:RefreshConfigPanel()
    end

    return layoutDrag
end

-- Shift-hover routes through the shared config Shift-tooltip controller
-- (State.lua), same as the shared entry rows: the real spell/item
-- tooltip with the resolved override spell ID, shown and hidden live as
-- the modifier changes. The controller speaks the AceGUI widget shape
-- (frame + user data), so each raw slot carries a small adapter.
local function EnsureSlotShiftTooltipAdapter(slot)
    local adapter = slot._cdcShiftTooltipAdapter
    if not adapter then
        adapter = { frame = slot, userdata = {} }
        function adapter:SetUserData(key, value)
            self.userdata[key] = value
        end
        function adapter:GetUserData(key)
            return self.userdata[key]
        end
        slot._cdcShiftTooltipAdapter = adapter
    end
    return adapter
end

local function ResolveSlotShiftTooltip(buttonData)
    if buttonData.type == "spell" and buttonData.id then
        local resolve = ST._ResolveEntryTooltipSpellId
        return "spell", resolve and resolve(buttonData) or buttonData.id
    end
    if buttonData.type == "item" and buttonData.id then
        return "item", buttonData.id
    end
    if CooldownCompanion.IsEquipmentSlotEntry
        and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
        local effectiveItem = CooldownCompanion.ResolveEffectiveItem
            and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
        if effectiveItem and effectiveItem.trackable and effectiveItem.itemID then
            return "item", effectiveItem.itemID
        end
    end
    return nil
end

-- Plain hover: the entry name with its kind spelled out, plus the same
-- status signals the shared row badges carry (Shift is the controller's
-- job above). Overrides and talent conditions list their actual contents
-- here so nobody has to open the entry's tabs just to see what is set.
local function ShowEntrySlotTooltip(slot, panelId, buttonData, status, visibility)
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    local name = GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
    GameTooltip:SetText(name or "Entry", 1, 1, 1)
    if status.disabled then
        GameTooltip:AddLine(
            ("|A:%s:14:14|a Disabled"):format(ENTRY_STATUS_BADGE_ATLAS.disabled),
            0.6, 0.6, 0.6)
    end
    if status.warn then
        GameTooltip:AddLine(
            ("|A:%s:14:14|a %s"):format(ENTRY_STATUS_BADGE_ATLAS.warn,
                status.loadBlocked and "Hidden by visibility rules" or "Spell/item unavailable"),
            1, 0.3, 0.3)
    end
    if status.override then
        local group = panelId and CooldownCompanion.db
            and CooldownCompanion.db.profile.groups[panelId] or nil
        local displayMode = group and (group.displayMode or "icons") or "icons"
        -- Same order and activity gates the styling tabs use for these
        -- sections: ST.OVERRIDE_SECTION_ORDER, then the per-entry gate.
        local canUse = ST._CanButtonUseConfigOverrideSection
        local sections = buttonData.overrideSections or {}
        local lines = {}
        if buttonData.textFormat ~= nil then
            lines[#lines + 1] = { label = "Text Format", active = displayMode == "text" }
        end
        for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER or {}) do
            if sections[sectionId] then
                local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
                if sectionDef then
                    lines[#lines + 1] = {
                        label = sectionDef.label,
                        active = sectionDef.modes[displayMode] == true
                            and (not canUse or (canUse(buttonData, sectionId))),
                    }
                end
            end
        end
        GameTooltip:AddLine(" ")
        if #lines > 0 then
            GameTooltip:AddLine(
                ("|A:%s:14:14|a Customized:"):format(ENTRY_STATUS_BADGE_ATLAS.override),
                1, 1, 1)
            for _, line in ipairs(lines) do
                if line.active then
                    GameTooltip:AddLine("    " .. line.label, 0.7, 0.7, 0.7)
                else
                    GameTooltip:AddLine("    " .. line.label .. " (inactive)", 0.45, 0.45, 0.45)
                end
            end
        else
            GameTooltip:AddLine(
                ("|A:%s:14:14|a Has customized sections"):format(ENTRY_STATUS_BADGE_ATLAS.override),
                1, 1, 1)
        end
    end
    if status.talent then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            ("|A:%s:14:14|a Talent conditions:"):format(ENTRY_STATUS_BADGE_ATLAS.talent),
            1, 1, 1)
        local getName = ST._GetConditionDisplayName
        for _, cond in ipairs(buttonData.talentConditions or {}) do
            local nameText = getName and getName(cond) or (cond.name or "Unknown Talent")
            local suffix = (cond.show == "not_taken")
                and " |cffff4d4d(not taken)|r" or " |cff33dd33(taken)|r"
            GameTooltip:AddLine("    " .. nameText .. suffix, 0.7, 0.7, 0.7)
        end
    end
    if status.fallback or status.sound then
        GameTooltip:AddLine(" ")
        if status.fallback then
            GameTooltip:AddLine(
                ("|A:%s:14:14|a Uses item fallbacks"):format(ENTRY_STATUS_BADGE_ATLAS.fallback),
                1, 1, 1)
        end
        if status.sound then
            GameTooltip:AddLine(
                ("|A:%s:14:14|a Sound alerts enabled"):format(ENTRY_STATUS_BADGE_ATLAS.sound),
                1, 1, 1)
        end
    end
    if status.auraHideReservesSpace then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            ("|A:%s:14:14|a Hidden aura still reserves layout space")
                :format(PANEL_PREVIEW_AURA_SPACE_BADGE_ATLAS),
            1, 0.82, 0.2)
        GameTooltip:AddLine(
            "Blizzard does not expose the active aura state to addon layout code, so this reserved space cannot safely collapse.",
            0.7, 0.7, 0.7, true)
    end
    if visibility and not visibility.exactPreview
        and visibility.underlyingMode == "hidden" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(
            ("|A:%s:14:14|a Hidden in simulated state")
                :format(PANEL_PREVIEW_VISIBILITY_BADGE_ATLAS),
            1, 0.82, 0.2)
        for _, reason in ipairs(visibility.reasons or {}) do
            GameTooltip:AddLine("    " .. reason.label .. " - " .. reason.rule, 0.7, 0.7, 0.7)
        end
    end
    if CooldownCompanion:HasLocalLoadConditions(buttonData) then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("This entry adds visibility rules.", 0.7, 0.7, 0.7)
    end
    GameTooltip:AddLine(" ")
    local copyState = CS.copyCustomization
    if copyState then
        -- While armed the click grammar changes entirely, so the hint
        -- lines change with it.
        local targetGroup = panelId and CooldownCompanion.db.profile.groups[panelId]
        local label = CopyMode.GetLabel(copyState)
        if CopyMode.IsEligibleTarget(copyState, targetGroup, buttonData) then
            GameTooltip:AddLine("Click to apply " .. label .. " to this entry.",
                CopyMode.COLOR[1], CopyMode.COLOR[2], CopyMode.COLOR[3])
        else
            GameTooltip:AddLine("This entry can't receive " .. label .. ".", 0.6, 0.6, 0.6)
        end
        GameTooltip:AddLine("Right-click to cancel.", 0.75, 0.82, 0.92)
    else
        if slot._cdcDraggable then
            GameTooltip:AddLine("Drag to reorder.", 0.75, 0.82, 0.92)
        end
        -- WireEntryInteraction opens the entry context menu on every display
        -- mode, and that menu holds destructive actions, so every mode
        -- advertises it.
        GameTooltip:AddLine("Right-click for options.", 0.75, 0.82, 0.92)
        if slot._cdcReorderPausedByFilter then
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("Reordering is paused while unavailable entries are hidden.",
                0.7, 0.7, 0.7, true)
        end
    end
    GameTooltip:Show()
end

local function WireEntryInteraction(slot, panelId, index, buttonData, status, layoutDrag, visibility)
    slot:EnableMouse(true)
    slot._cdcDraggable = layoutDrag ~= nil
    slot._cdcEntryIndex = index
    slot._cdcEntryStatus = status
    slot:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or GetCursorInfo() then return end
        -- Armed copy mode: the press belongs to the copy click, not a drag.
        if CS.copyCustomization then return end
        if not (layoutDrag and StartDragTracking) then return end
        local cursorX, cursorY = GetCursorPosition()
        -- No `widget` field: the tracker's dim/restore would fight the
        -- alpha choreography our layoutDrag callbacks run (dragged slot
        -- goes fully invisible; disabled slots rest at reduced alpha).
        CS.dragState = {
            kind = "layout-slot",
            phase = "pending",
            previewSlot = self,
            scrollWidget = UIParent,
            startX = cursorX,
            startY = cursorY,
            layoutDrag = layoutDrag,
            slotData = { index = index, buttonData = buttonData },
        }
        StartDragTracking()
    end)
    slot:SetScript("OnMouseUp", function(self, mouseButton)
        if GetCursorInfo() then return end
        if mouseButton == "LeftButton" then
            local state = CS.dragState
            if state then
                -- Only fall through to selection for our own still-pending
                -- press; active drags finish through the tracker.
                if state.kind ~= "layout-slot" or state.phase ~= "pending" or state.previewSlot ~= self then
                    return
                end
                if CancelDrag then CancelDrag() else CS.dragState = nil end
            end
            if CopyMode.HandleClick(panelId, index, buttonData) then return end
            SelectConfigButton(panelId, index, { multi = IsControlKeyDown() })
            CooldownCompanion:RefreshConfigSelection()
        elseif mouseButton == "RightButton" or mouseButton == "MiddleButton" then
            if CS.dragState and CS.dragState.phase == "active" then return end
            -- Armed copy mode: right/middle-click is a cancel, never a menu.
            if CS.copyCustomization then
                CopyMode.Cancel()
                return
            end
            if ShowEntryContextMenu then
                ShowEntryContextMenu(panelId, index, buttonData)
            end
        end
    end)
    slot:SetScript("OnEnter", function(self)
        if CS.dragState and CS.dragState.phase == "active" then return end
        if self._cdcBarPreviewVisibility then
            self._cdcBarPreviewHovered = true
            RefreshBarSlotWorkspacePresentation(self)
        else
            self.hoverHighlight:SetFrameLevel(self:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
            self.hoverHighlight:Show()
        end
        -- Register with the shared Shift-tooltip controller; when Shift is
        -- already held this shows the real tooltip immediately and the
        -- decorated one is skipped. Later modifier changes are the
        -- controller's MODIFIER_STATE_CHANGED handler's job.
        local kind, id = ResolveSlotShiftTooltip(buttonData)
        local activate = ST._ActivateConfigShiftTooltip
        if kind and id and activate then
            local adapter = EnsureSlotShiftTooltipAdapter(self)
            adapter:SetUserData("cdcShiftTooltipKind", kind)
            adapter:SetUserData("cdcShiftTooltipID", id)
            adapter:SetUserData("cdcShiftTooltipOwner", self)
            adapter:SetUserData("cdcShiftTooltipAnchor", "ANCHOR_RIGHT")
            if activate(adapter) then
                return
            end
        end
        ShowEntrySlotTooltip(self, panelId, buttonData, status, visibility)
    end)
    slot:SetScript("OnLeave", function(self)
        if self._cdcBarPreviewVisibility then
            self._cdcBarPreviewHovered = false
            RefreshBarSlotWorkspacePresentation(self)
        else
            self.hoverHighlight:Hide()
        end
        if self._cdcShiftTooltipAdapter and ST._ClearConfigShiftTooltipHover then
            ST._ClearConfigShiftTooltipHover(self._cdcShiftTooltipAdapter)
        end
        GameTooltip:Hide()
    end)
end

-- Entry footprint and grid settings mirrored from GroupFrame.lua
-- (GetButtonDimensions + ApplyActiveButtonLayout).
local function GetPanelGeometry(group, isBarMode, isTextMode, visibleIndices)
    local style = group.style or {}
    local w, h
    if isTextMode then
        -- Mirror of GroupFrame's text-mode sizing (GetButtonDimensions): a
        -- text entry measures itself from its own format and font, and the
        -- grid pitch is the widest/tallest of them. The panel's own format
        -- seeds a floor so an entry-less panel still has a size.
        --
        -- DIVERGENCE (pre-existing, deliberate): the live panel maxes over
        -- currently USABLE entries only, while the mirror measures every saved
        -- entry, so the mirror shows the pitch the panel takes with everything
        -- showing rather than the pitch of this character's current subset.
        -- The session unavailable filter narrows the scan to the entries it
        -- kept (visibleIndices), so a hidden wide entry stops setting pitch.
        if GetTextEntryMetrics then
            w, h = GetTextEntryMetrics(style, nil, style.textFormat)
            local buttons = group.buttons or {}
            for ordinal = 1, (visibleIndices and #visibleIndices or #buttons) do
                local buttonData = buttons[visibleIndices and visibleIndices[ordinal] or ordinal]
                local effectiveStyle = CooldownCompanion.GetEffectiveStyle
                    and CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
                local fmt = buttonData.textFormat or effectiveStyle.textFormat
                local entryWidth, entryHeight = GetTextEntryMetrics(effectiveStyle, buttonData, fmt)
                w = math_max(w, entryWidth)
                h = math_max(h, entryHeight)
            end
        else
            -- Same floor GroupFrame falls back to when the renderer's export
            -- is missing.
            w, h = 200, 20
        end
    elseif isBarMode then
        w, h = style.barLength or 180, style.barHeight or 20
        if style.barFillVertical then w, h = h, w end
    elseif style.maintainAspectRatio then
        local size = style.buttonSize or ST.BUTTON_SIZE
        w, h = size, size
    else
        w = style.iconWidth or style.buttonSize or ST.BUTTON_SIZE
        h = style.iconHeight or style.buttonSize or ST.BUTTON_SIZE
    end
    -- An Aura BAR Panel is ONE vertical column in the world whatever the stored
    -- orientation and wrap count say: the engine hard-codes it (PanelFlowSpec's
    -- bars branch, GetAuraPanelCellSlot's column 0), and neither row is offered
    -- for one any more. Values left over from before the panel became one must
    -- not wrap the replica into a shape the panel will never take. A wrap count
    -- of "every entry" is what one column means on the vertical axis, where the
    -- count is entries per COLUMN.
    if isBarMode and ST.IsAuraPanelGroup(group) then
        return {
            entryWidth = w,
            entryHeight = h,
            spacing = style.buttonSpacing or ST.BUTTON_SPACING,
            orientation = "vertical",
            buttonsPerRow = math_max(1, #(group.buttons or {})),
        }
    end
    return {
        entryWidth = w,
        entryHeight = h,
        spacing = style.buttonSpacing or ST.BUTTON_SPACING,
        orientation = ST.GetPanelLayoutOrientation(group.displayMode, style),
        buttonsPerRow = style.buttonsPerRow or 12,
    }
end

-- Per-entry text footprint, mirroring TextMode.lua ApplyTextLayout: in the
-- world each text button measures itself and calls button:SetSize with its
-- OWN width/height, while GroupFrame's ApplyActiveButtonLayout only POSITIONS
-- text buttons on the uniform pitch. So the mirror places slots on the pitch
-- grid (GetPanelGeometry above) but sizes each one from its own metrics --
-- otherwise a short entry beside a long one renders full-pitch wide here and
-- narrow in the world. Same call shape as the pitch pass, so the entry's
-- metrics cache slot is shared rather than churned.
--
-- Without the renderer's export the pitch is the only number available, which
-- is exactly the uniform-slot behavior this mirror had before.
local function GetTextSlotSize(group, buttonData, pitchWidth, pitchHeight)
    if not GetTextEntryMetrics then
        return pitchWidth, pitchHeight
    end
    local style = group.style or {}
    local effectiveStyle = CooldownCompanion.GetEffectiveStyle
        and CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    local fmt = buttonData.textFormat or effectiveStyle.textFormat
    local entryWidth, entryHeight = GetTextEntryMetrics(effectiveStyle, buttonData, fmt)
    return entryWidth or pitchWidth, entryHeight or pitchHeight
end

local function IsIconModePanel(group)
    if group.displayMode ~= nil and group.displayMode ~= "icons" then
        return false
    end
    if CooldownCompanion.IsStandaloneTexturePanelGroup
        and CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        return false
    end
    return true
end

local function StyleIconEntry(slot, buttonData, group)
    StyleMirroredIconFrame(slot, { buttonData = buttonData }, group)

    -- Keybind label: live icon buttons pin this above every layer so it stays
    -- readable whatever is drawn over the icon (IconMode.lua). Same font keys,
    -- anchor contract, and resolver as live icons - GetDisplayedKeybindText,
    -- which honors customKeybindText (the text mirror stays on GetKeybindText
    -- by design; see Keybinds.lua). Static lookups only, never live frame
    -- state.
    local style = group and group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end
    local text
    if style.showKeybindText and CooldownCompanion.GetDisplayedKeybindText then
        -- Item entries resolve their bind by the EQUIPPED/effective item id,
        -- and equipment-slot entries carry no id of their own, so pass the
        -- same override live passes. ResolveEffectiveItem is pure C_Item /
        -- ItemLocation; requestLoad = false keeps the preview from kicking off
        -- item-data loads.
        local overrideId
        if CooldownCompanion.IsEntryItemLike and CooldownCompanion.IsEntryItemLike(buttonData)
            and CooldownCompanion.ResolveEffectiveItem then
            local effectiveItem = CooldownCompanion.ResolveEffectiveItem(buttonData, false)
            overrideId = effectiveItem and effectiveItem.itemID
        end
        text = CooldownCompanion:GetDisplayedKeybindText(buttonData, overrideId, nil)
        if text == "" then text = nil end
    end
    if text then
        local host = slot.keybindHost
        if not host then
            host = CreateFrame("Frame", nil, slot)
            host:SetAllPoints(slot)
            slot.keybindHost = host
            slot.keybindText = host:CreateFontString(nil, "OVERLAY")
        end
        -- Live pins the keybind above everything, including the loss-of-control
        -- cooldown (Helpers.lua: locCooldown at top+1, pinned text at top+2).
        -- Mirror that order here: aura swipe +0, text overlay +1, LoC +2, so
        -- the keybind takes +3 or the LoC swipe draws over the label.
        host:SetFrameLevel(slot.cooldown:GetFrameLevel() + 3)
        local kb = slot.keybindText
        CooldownCompanion.ApplyFontStyle(kb, style, "keybind", 10)
        kb:ClearAllPoints()
        kb:SetPoint(style.keybindAnchor or "TOPRIGHT",
            style.keybindXOffset or -2, style.keybindYOffset or -2)
        kb:SetText(text)
        kb:Show()
    elseif slot.keybindText then
        slot.keybindText:Hide()
    end
end

------------------------------------------------------------------------
-- Conditional visual previews on the mirror (icon panels): while a preview
-- toggle is active for an entry or its whole panel, render a config-only
-- stand-in from Preview.lua's stored state and timing contract. Times are
-- literal numbers from that state; this never reads live cooldowns.
------------------------------------------------------------------------
local ICON_FILL_TEXTURE = "Interface\\Buttons\\WHITE8x8"
-- VisualState.lua DEFAULT_ICON_FILL_COOLDOWN_COLOR
local DEFAULT_ICON_FILL_COOLDOWN_COLOR = { 0.6, 0.13, 0.18, 0.55 }

-- Level base for slot sub-widgets that must render above the slot's
-- busiest layer: the cooldown swipe on icon slots, the text frame on
-- bar slots.
local function GetSlotOverlayBaseLevel(slot)
    if slot.cooldown then
        return slot.cooldown:GetFrameLevel()
    end
    if slot.textFrame then
        return slot.textFrame:GetFrameLevel()
    end
    return slot:GetFrameLevel()
end

-- Hosts the count/aura text stand-ins above the cooldown swipe, like
-- the live buttons' overlayFrame.
local function EnsureSlotTextOverlay(slot)
    local overlay = slot.textOverlay
    if not overlay then
        overlay = CreateFrame("Frame", nil, slot)
        overlay:SetAllPoints()
        overlay:EnableMouse(false)
        slot.textOverlay = overlay
    end
    overlay:SetFrameLevel(GetSlotOverlayBaseLevel(slot) + 1)
    return overlay
end

local function EnsureSlotCountText(slot)
    if not slot.count then
        slot.count = EnsureSlotTextOverlay(slot):CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    else
        EnsureSlotTextOverlay(slot)
    end
    return slot.count
end

local function EnsureSlotAuraText(slot)
    if not slot.auraTextFS then
        slot.auraTextFS = EnsureSlotTextOverlay(slot):CreateFontString(nil, "OVERLAY")
    else
        EnsureSlotTextOverlay(slot)
    end
    return slot.auraTextFS
end

-- The pandemic marker rides the aura duration text, so its preview IS the
-- duration-text stand-in with the marker appended. Every render path below
-- treats the two kinds as one and calls the decorator on the way out; the
-- marker's own descriptor is what keeps the sweep inside the window.
local function IsAuraDurationTextKind(kind)
    return kind == "aura_duration_text" or kind == "pandemic_marker"
end

-- Honest about the entry's own switch: an entry with the marker turned off
-- previews the bare countdown rather than a marker it will never draw.
local function DecorateAuraDurationPreviewText(text, kind, style, buttonData)
    if kind == "pandemic_marker"
        and CooldownCompanion:IsPandemicMarkerPreviewWanted(buttonData, style) then
        return CooldownCompanion:DecoratePandemicPreviewText(text, style)
    end
    return text
end

local function EnsureSlotAuraStackText(slot)
    if not slot.auraStackCount then
        slot.auraStackCount = EnsureSlotTextOverlay(slot):CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    else
        EnsureSlotTextOverlay(slot)
    end
    return slot.auraStackCount
end

local function EnsureSlotAuraSwipe(slot)
    local widget = slot.auraSwipe
    if not widget then
        widget = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
        widget:SetAllPoints(slot.icon)
        widget:SetDrawBling(false)
        widget:SetHideCountdownNumbers(true)
        widget:EnableMouse(false)
        slot.auraSwipe = widget
    end
    widget:SetFrameLevel(slot.cooldown:GetFrameLevel())
    return widget
end

local function EnsureSlotLocCooldown(slot)
    local widget = slot.locCooldown
    if not widget then
        widget = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
        widget:SetAllPoints(slot.icon)
        widget:SetDrawBling(false)
        widget:SetHideCountdownNumbers(true)
        widget:EnableMouse(false)
        -- Fixed styling per IconMode.lua CreateButtonFrame's locCooldown
        widget:SetDrawEdge(true)
        widget:SetDrawSwipe(true)
        widget:SetSwipeColor(0.17, 0, 0, 0.8)
        slot.locCooldown = widget
    end
    widget:SetFrameLevel(GetSlotOverlayBaseLevel(slot) + 2)
    return widget
end

-- Self-animating fill, like the live icon fill's OnUpdate driver; reads
-- the stored preview state so loop wraps need no external re-arm.
local function SlotIconFillOnUpdate(self)
    local slot = self._owner
    local state = slot and slot._cdcCondAnim
    if not (state and GetConditionalPreviewTiming and ResolveIconFillTimerValue) then return end
    local startTime, duration, remaining = GetConditionalPreviewTiming(state, GetTime())
    if not (startTime and duration and duration > 0) then return end
    self:SetValue(ResolveIconFillTimerValue(slot, 1 - (remaining / duration)))
end

local function EnsureSlotIconFill(slot)
    local fill = slot.iconFill
    if not fill then
        fill = CreateFrame("StatusBar", nil, slot)
        fill._owner = slot
        fill:SetMinMaxValues(0, 1)
        fill:SetStatusBarTexture(ICON_FILL_TEXTURE)
        fill:EnableMouse(false)
        slot.iconFill = fill
    end
    if AnchorIconFill then AnchorIconFill(slot) end
    if ApplyIconFillLayer then ApplyIconFillLayer(slot) end
    return fill
end

local function ResetSlotConditionalVisuals(slot)
    slot._cdcCondAnim = nil
    slot._cdcCondArmedStart = nil
    if slot.cooldown then
        slot.cooldown:Clear()
        slot.cooldown:Hide()
    end
    if slot.auraSwipe then
        slot.auraSwipe:Clear()
        slot.auraSwipe:Hide()
    end
    if slot.locCooldown then
        slot.locCooldown:Clear()
        slot.locCooldown:Hide()
    end
    if slot.auraTextFS then
        slot.auraTextFS:Hide()
    end
    if slot.auraStackCount then
        slot.auraStackCount:SetText("")
        slot.auraStackCount:Hide()
    end
    if slot.count then
        slot.count:SetText("")
    end
    if slot.iconFill then
        slot.iconFill:SetScript("OnUpdate", nil)
        slot.iconFill:Hide()
    end
end

-- Cooldown text: like live icon mode, restyle the widget's built-in
-- countdown region and let it count the fake loop down. Reapplied after
-- every SetCooldown re-arm (the CooldownFrame may reset the region).
-- Passive aura entries never show cooldown text (live parity).
local function StyleSlotCooldownText(slot, style)
    local region = slot.cooldown:GetRegions()
    if not (region and region.SetFont) then return end
    if style.showCooldownText and not (slot.buttonData and slot.buttonData.isPassive) then
        slot.cooldown:SetHideCountdownNumbers(false)
        if CooldownCompanion.ApplyDurationFormatToCooldown then
            CooldownCompanion.ApplyDurationFormatToCooldown(slot.cooldown, style)
        end
        CooldownCompanion.ApplyFontStyle(region, style, "cooldown")
        region:ClearAllPoints()
        region:SetPoint(style.cooldownTextAnchor or "CENTER",
            style.cooldownTextXOffset or 0, style.cooldownTextYOffset or 0)
    else
        slot.cooldown:SetHideCountdownNumbers(true)
    end
end

-- Renders the entry's active conditional preview (if any) onto its
-- mirror slot, and always restores the baseline tint/desaturation a
-- recycled slot may carry. Runs after the entry-status desaturation:
-- previews may force desaturation on, never off. Each branch follows the
-- corresponding runtime presentation rules and shared style helpers.
local function ApplySlotConditionalPreview(slot, buttonData, group, panelId, index)
    ResetSlotConditionalVisuals(slot)
    -- Read by ApplyIconCountTextStyle and StyleSlotCooldownText
    slot.buttonData = buttonData

    local style = slot.style or group.style or {}
    -- Tracking.lua ResolveIconTintIntent: base = configured icon tint.
    local baseTint = style.iconTintColor
    local tintR = baseTint and baseTint[1] or 1
    local tintG = baseTint and baseTint[2] or 1
    local tintB = baseTint and baseTint[3] or 1
    local tintA = baseTint and baseTint[4] or 1
    local forceDesat = false

    local state = GetStoredConditionalPreviewState
        and GetStoredConditionalPreviewState(panelId, index) or nil
    local kind = state and state.kind or nil
    local now = GetTime()

    -- Any aura-active stand-in mirrors the slot kit's desaturate-while-
    -- active (StyleSlotKit) when the live composition would put an aura-
    -- layer icon region over this slot.icon: keep-swipe entries skip the
    -- takeover unless the aura icon swap is on.
    if CooldownCompanion:IsAuraPreviewKindExposingShell(kind, false)
        and CooldownCompanion:ShouldDesaturateAuraLayerWhileActive(buttonData, style)
        and (not CooldownCompanion:IsKeepSpellCooldownSwipeEntry(buttonData, style)
            or style.auraShowAuraIcon == true) then
        forceDesat = true
    end

    -- Missing tint: EYE-GATED like every missing-aura effect (owner ruling
    -- 2026-08-20) — the mirror rests untinted and wears the tint only while
    -- the "Preview Missing Aura Effects" toggle runs. An aura-active preview
    -- simulates "the aura is up", which live occludes the tinted icon under,
    -- so the block above wins there. Keep-swipe entries skip the tint live
    -- (no cover to hide it while the aura runs), mirrored here.
    local missingTintApplied = false
    if (buttonData.auraTracking or buttonData.addedAs == "aura")
        and style.iconMissingTintEnabled == true
        and style.iconMissingTintColor
        and CooldownCompanion:IsPreviewFlagActive(panelId, index, "_missingAuraPreview")
        and not CooldownCompanion:IsKeepSpellCooldownSwipeEntry(buttonData, style)
        and not CooldownCompanion:IsAuraPreviewKindExposingShell(kind, false) then
        local missingTint = style.iconMissingTintColor
        tintR, tintG, tintB = missingTint[1], missingTint[2], missingTint[3]
        tintA = missingTint[4] or 1
        -- Live precedence (Tracking.lua): the missing tint outranks the
        -- cooldown tint, so the cooldown/zero-charge stand-ins below must
        -- not replace it. Unusable and out-of-range stay above both (state
        -- overrides), matching the runtime resolver.
        missingTintApplied = true
    end


    -- The cooldown family: "cooldown" is the full state (text and rotation
    -- assistant panels still fire it); "cooldown_swipe" is that state with
    -- the countdown numbers withheld; "cooldown_text" is the countdown text
    -- alone on an otherwise resting slot (no fill, no desaturation, no tint).
    if (kind == "cooldown" or kind == "cooldown_swipe" or kind == "cooldown_text")
        and GetConditionalPreviewTiming then
        local startTime, duration = GetConditionalPreviewTiming(state, now)
        if startTime then
            local textOnly = kind == "cooldown_text"
            -- An active icon fill owns the cooldown visual and suppresses
            -- the swipe and edge (VisualState.lua SetIconFillIntent).
            local fillActive = not textOnly
                and style.iconFillEnabled == true
                and group.masqueEnabled ~= true
                and ResolveIconFillTimerValue ~= nil
            local cd = slot.cooldown
            local swipeEnabled = not textOnly
                and style.showCooldownSwipe ~= false and not fillActive
            cd:SetDrawSwipe(swipeEnabled and style.showCooldownSwipeFill ~= false)
            cd:SetDrawEdge(swipeEnabled and style.cooldownSwipeEdgeEnabled == true)
            cd:SetReverse(style.cooldownSwipeReverse or false)
            cd:SetSwipeColor(0, 0, 0, style.cooldownSwipeAlpha or 0.8)
            local edgeColor = style.cooldownSwipeEdgeColor or { 1, 1, 1, 1 }
            cd:SetEdgeColor(edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4])
            if kind == "cooldown_swipe" then
                cd:SetHideCountdownNumbers(true)
            else
                StyleSlotCooldownText(slot, style)
            end
            cd:Show()
            cd:SetCooldown(startTime, duration)
            slot._cdcCondAnim = state
            slot._cdcCondArmedStart = startTime

            if fillActive then
                local fill = EnsureSlotIconFill(slot)
                if ApplyIconFillGeometry then
                    ApplyIconFillGeometry(slot, style)
                end
                local c = style.iconFillCooldownColor or DEFAULT_ICON_FILL_COOLDOWN_COLOR
                fill:SetStatusBarColor(c[1], c[2], c[3], c[4])
                fill:SetScript("OnUpdate", SlotIconFillOnUpdate)
                fill:Show()
                SlotIconFillOnUpdate(fill)
            end

            if not textOnly then
                if style.desaturateOnCooldown then
                    forceDesat = true
                end
                if not missingTintApplied
                    and style.iconCooldownTintEnabled and style.iconCooldownTintColor then
                    local c = style.iconCooldownTintColor
                    tintR, tintG, tintB, tintA = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end
            end
        end
    elseif kind == "charge_full" or kind == "charge_missing" or kind == "charge_zero" then
        if CooldownCompanion.UsesChargeBehavior and CooldownCompanion.UsesChargeBehavior(buttonData) then
            local maxCharges = buttonData.maxCharges or 2
            if maxCharges < 2 then maxCharges = 2 end
            local current = maxCharges
            local colorKey = "chargeFontColor"
            if kind == "charge_missing" then
                current = math_max(1, maxCharges - 1)
                colorKey = "chargeFontColorMissing"
            elseif kind == "charge_zero" then
                current = 0
                colorKey = "chargeFontColorZero"
            end

            local count = EnsureSlotCountText(slot)
            if ApplyIconCountTextStyle then
                ApplyIconCountTextStyle(slot, style)
            end
            if style.showChargeText ~= false then
                count:SetText(current)
            end
            -- CooldownUpdate.lua ApplyChargeTextColor: only recolor when
            -- any charge color is configured at all.
            if style.chargeFontColor or style.chargeFontColorMissing or style.chargeFontColorZero then
                local cc = style[colorKey] or { 1, 1, 1, 1 }
                count:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
            end

            if kind == "charge_zero" then
                -- Live zero charges sets _desatCooldownActive, so the
                -- cooldown desaturate/tint options apply here too.
                if style.desaturateOnCooldown
                    or (buttonData.desaturateWhileZeroCharges
                        and not (CooldownCompanion.HasItemFallbacks
                            and CooldownCompanion.HasItemFallbacks(buttonData))) then
                    forceDesat = true
                end
                if not missingTintApplied
                    and style.iconCooldownTintEnabled and style.iconCooldownTintColor then
                    local c = style.iconCooldownTintColor
                    tintR, tintG, tintB, tintA = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end
            end
        end
    elseif kind == "unusable" then
        -- Tracking.lua IsUnusableVisualActive: aura and passive entries
        -- never show castability state.
        if style.showUnusable
            and not (buttonData.isPassive or buttonData.isPassiveCooldown or buttonData.addedAs == "aura") then
            if ST.UnusableVisualUsesDesaturation(style) then
                forceDesat = true
            end
            if ST.UnusableVisualUsesDimTint(style) then
                local uc = style.iconUnusableTintColor
                tintR = uc and uc[1] or 0.4
                tintG = uc and uc[2] or 0.4
                tintB = uc and uc[3] or 0.4
                tintA = uc and uc[4] or tintA
            end
        end
    elseif kind == "out_of_range" then
        if style.showOutOfRange and not buttonData.isPassive then
            tintR, tintG, tintB = 1, 0.2, 0.2
        end
    elseif IsAuraDurationTextKind(kind) and GetConditionalPreviewTiming then
        if style.showAuraText ~= false then
            local startTime, _, remaining = GetConditionalPreviewTiming(state, now)
            if startTime then
                local fs = EnsureSlotAuraText(slot)
                CooldownCompanion.ApplyFontStyle(fs, style, "auraText", nil,
                    CooldownCompanion.DEFAULT_AURA_TEXT_COLOR)
                local anchor, xOff, yOff = CooldownCompanion:GetAuraDurationTextPlacement(style, buttonData)
                fs:ClearAllPoints()
                fs:SetPoint(anchor, slot, anchor, xOff, yOff)
                fs:SetText(DecorateAuraDurationPreviewText(
                    ("%d"):format(math_ceil(remaining)), kind, style, buttonData))
                fs:Show()
                slot._cdcCondAnim = state
            end
        end
    elseif kind == "aura_stack_text" then
        if style.showAuraStackText ~= false then
            local fs = EnsureSlotAuraStackText(slot)
            CooldownCompanion.ApplyFontStyle(fs, style, "auraStack")
            fs:ClearAllPoints()
            fs:SetPoint(style.auraStackAnchor or "BOTTOMLEFT",
                style.auraStackXOffset or 2, style.auraStackYOffset or 2)
            -- Threshold-aware stand-in (2026-08-15 program); helper lives in
            -- ButtonFrame/Helpers.lua (200-local ceiling here).
            local asText, asR, asG, asB, asA = CooldownCompanion:GetAuraStackPreviewCountAndColor(
                buttonData, style, state.stackText)
            fs:SetText(asText)
            fs:SetTextColor(asR, asG, asB, asA)
            fs:Show()
        end
    elseif kind == "aura_duration_swipe" and GetConditionalPreviewTiming then
        if CooldownCompanion:ShouldDrawAuraDurationSwipe(buttonData, style) then
            local startTime, duration = GetConditionalPreviewTiming(state, now)
            if startTime then
                local widget = EnsureSlotAuraSwipe(slot)
                if CooldownCompanion.ApplyAuraDurationSwipeStyle then
                    CooldownCompanion:ApplyAuraDurationSwipeStyle(widget, style)
                end
                widget:Show()
                widget:SetCooldown(startTime, duration)
                slot._cdcCondAnim = state
                slot._cdcCondArmedStart = startTime
            end
        end
    elseif kind == "loss_of_control" and GetConditionalPreviewTiming then
        -- Runtime gate (Visibility.lua): spells only, never passives.
        if style.showLossOfControl and buttonData.type == "spell" and not buttonData.isPassive then
            local startTime, duration = GetConditionalPreviewTiming(state, now)
            if startTime then
                local widget = EnsureSlotLocCooldown(slot)
                widget:Show()
                widget:SetCooldown(startTime, duration)
                slot._cdcCondAnim = state
                slot._cdcCondArmedStart = startTime
            end
        end
    end

    slot.icon:SetVertexColor(tintR, tintG, tintB, tintA)
    if forceDesat then
        slot.icon:SetDesaturated(true)
    end
end

------------------------------------------------------------------------
-- Bar-slot conditional previews: same stored state and timing, rendered
-- per BarMode.lua's recipes (UpdateBarFill drain/fill + time text,
-- UpdateBarDisplay colors and fill effects).
------------------------------------------------------------------------
local function EnsureBarSlotTimeText(slot)
    if not slot.timeText then
        slot.timeText = slot.textFrame:CreateFontString(nil, "OVERLAY")
    end
    return slot.timeText
end

local function EnsureBarSlotAuraStackText(slot)
    if not slot.auraStackCount then
        slot.auraStackCount = slot.textFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    end
    return slot.auraStackCount
end

-- Time text placement per BarMode.lua CreateBarFrame, including the
-- name/time overlap guard when both sit on the same side.
local function AnchorBarSlotTimeText(slot, style)
    local tt = slot.timeText
    local isVertical = style.barFillVertical or false
    local cdOffX = style.barCdTextOffsetX or 0
    local cdOffY = style.barCdTextOffsetY or 0
    local timeReverse = style.barTimeTextReverse
    tt:ClearAllPoints()
    if isVertical then
        if timeReverse then
            tt:SetPoint("BOTTOM", cdOffX, 3 + cdOffY)
        else
            tt:SetPoint("TOP", cdOffX, -3 + cdOffY)
        end
        tt:SetJustifyH("CENTER")
    else
        if timeReverse then
            tt:SetPoint("LEFT", 3 + cdOffX, cdOffY)
            tt:SetJustifyH("LEFT")
        else
            tt:SetPoint("RIGHT", -3 + cdOffX, cdOffY)
            tt:SetJustifyH("RIGHT")
        end
    end
    -- Raw comparison like live (nil and false differ deliberately there)
    if not isVertical and style.barNameTextReverse == style.barTimeTextReverse
        and slot.nameText and slot.nameText:IsShown() then
        if style.barNameTextReverse then
            slot.nameText:SetPoint("LEFT", tt, "RIGHT", 4, 0)
        else
            slot.nameText:SetPoint("RIGHT", tt, "LEFT", -4, 0)
        end
    end
end

local function ApplyBarReadyPresentation(slot, buttonData, style)
    local tt = EnsureBarSlotTimeText(slot)
    AnchorBarSlotTimeText(slot, style)
    local font = CooldownCompanion:FetchFont(style.barReadyFont or "Friz Quadrata TT")
    local size = style.barReadyFontSize or 12
    local outline = ST.GetEffectiveFontOutline(style.barReadyFontOutline or "OUTLINE")
    tt:SetFont(font, size, outline)
    ST.ApplyFontShadowForOutline(tt, outline)
    if buttonData.isPassive or style.showBarReadyText ~= true then
        tt:SetText("")
        return
    end

    local color = style.barReadyTextColor or DEFAULT_BAR_READY_TEXT_COLOR
    tt:SetTextColor(color[1], color[2], color[3], color[4] or 1)
    tt:SetText(style.barReadyText or "Ready")
    tt:Show()
end

-- Self-animating bar fill: aura previews drain (1->0) like the live kit
-- bar, cooldowns fill (0->1), per BarMode.lua UpdateBarFill.
local function BarSlotFillOnUpdate(self)
    local slot = self._cdcOwner
    local state = slot and slot._cdcCondAnim
    if not (state and GetConditionalPreviewTiming) then return end
    local startTime, duration, remaining = GetConditionalPreviewTiming(state, GetTime())
    if not (startTime and duration and duration > 0) then return end
    local frac
    if state.kind == "aura_duration_bar" then
        frac = remaining / duration
    else
        frac = 1 - (remaining / duration)
    end
    if frac < 0 then frac = 0 end
    if frac > 1 then frac = 1 end
    self:SetValue(frac)
end

-- Effective pandemic enable for a mirror entry: the explicit-true style key.
-- The style handed in is always the entry's EFFECTIVE style (slot.style), so an
-- entry that customized the Pandemic section answers with its own stored value
-- — the same resolution the live bind gate performs (AuraDisplay.lua
-- StyleSlotKit).
local function IsPandemicPreviewEnabled(style, buttonData)
    return style and style.pandemicEffectEnabled == true
end

local function StopBarSlotFillEffects(slot)
    if slot._cdcFillPulseAG then slot._cdcFillPulseAG:Stop() end
    if slot._cdcFillShiftAG then slot._cdcFillShiftAG:Stop() end
    local fillTex = slot.statusBar and slot.statusBar:GetStatusBarTexture()
    if fillTex then
        -- Clears residual shift tint; 4-arg SetVertexColor is the last alpha
        -- write on this mirror region.
        fillTex:SetVertexColor(1, 1, 1, 1)
    end
end

-- Active Aura Indicator fill effects on the mirror bar. Returns true when the
-- color-shift animation owns the fill color (the bar then goes white underneath,
-- matching the kit's layering trick).
-- suppressShift: the pandemic recolor occludes the live fill's color shift
-- (the kit clone draws over the shifting fill), so the mirror must not let
-- the shift animation own the color while the pandemic preview runs — the
-- pulse still applies, matching the clone inheriting the fill frame's
-- pulse alpha.
local function ApplyBarSlotFillEffects(slot, style, suppressShift)
    local fillTex = slot.statusBar:GetStatusBarTexture()
    if not fillTex then return false end
    if style.barAuraPulseEnabled == true then
        if not slot._cdcFillPulseAG then
            local ag = fillTex:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local anim = ag:CreateAnimation("Alpha")
            anim:SetFromAlpha(1.0)
            anim:SetToAlpha(0.3)
            slot._cdcFillPulseAG = ag
            slot._cdcFillPulseAnim = anim
        end
        slot._cdcFillPulseAnim:SetDuration(style.barAuraPulseSpeed or 0.5)
        slot._cdcFillPulseAG:Play()
    end
    if not suppressShift and style.barAuraColorShiftEnabled == true then
        if not slot._cdcFillShiftAG then
            local ag = fillTex:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            slot._cdcFillShiftAG = ag
            slot._cdcFillShiftAnim = ag:CreateAnimation("VertexColor")
        end
        local base = style.barAuraColor or DEFAULT_BAR_AURA_COLOR or { 0, 1, 0.3, 1 }
        local shiftC = style.barAuraColorShiftColor or { 1, 1, 1, 1 }
        slot._cdcFillShiftAnim:SetStartColor(CreateColor(base[1], base[2], base[3], base[4] or 1))
        slot._cdcFillShiftAnim:SetEndColor(CreateColor(shiftC[1], shiftC[2], shiftC[3], shiftC[4] or 1))
        slot._cdcFillShiftAnim:SetDuration(style.barAuraColorShiftSpeed or 0.5)
        slot._cdcFillShiftAG:Play()
        return true
    end
    return false
end

-- Cleanup runs before StyleBarEntry so its neutral texture tint cannot win
-- over the final saved or simulated status-bar color.
local function ResetBarSlotConditionalVisuals(slot)
    slot._cdcCondAnim = nil
    slot._cdcCondArmedStart = nil
    if slot.statusBar then
        slot.statusBar:SetScript("OnUpdate", nil)
    end
    StopBarSlotFillEffects(slot)
    if slot.timeText then
        slot.timeText:SetText("")
    end
    if slot.auraStackCount then
        slot.auraStackCount:SetText("")
        slot.auraStackCount:Hide()
    end
    if slot.count then
        slot.count:SetText("")
    end
    if slot.locCooldown then
        slot.locCooldown:Clear()
        slot.locCooldown:Hide()
    end
end

local function ApplyBarAuraTimeTextPreview(slot, style, remaining, kind, buttonData)
    if style.showAuraText == false then return end
    local tt = EnsureBarSlotTimeText(slot)
    local font = CooldownCompanion:FetchFont(style.auraTextFont or "Friz Quadrata TT")
    local size = style.auraTextFontSize or 12
    local outline = ST.GetEffectiveFontOutline(style.auraTextFontOutline or "OUTLINE")
    tt:SetFont(font, size, outline)
    ST.ApplyFontShadowForOutline(tt, outline)
    local color = style.auraTextFontColor or CooldownCompanion.DEFAULT_AURA_TEXT_COLOR
    tt:SetTextColor(color[1], color[2], color[3], color[4])
    AnchorBarSlotTimeText(slot, style)
    tt:SetText(DecorateAuraDurationPreviewText(
        CooldownCompanion.FormatTime(remaining, style), kind, style, buttonData))
    tt:Show()
end

local function ApplyBarSlotConditionalPreview(slot, buttonData, group, panelId, index,
        style, previewState)
    -- Read by ApplyBarCountTextStyle
    slot.buttonData = buttonData

    style = style or slot.style or group.style or {}
    -- Bars run the same icon tint pipeline live (UpdateIconTint on the
    -- bar icon); baseline restored every rebuild like the icon slots.
    local baseTint = style.iconTintColor
    local tintR = baseTint and baseTint[1] or 1
    local tintG = baseTint and baseTint[2] or 1
    local tintB = baseTint and baseTint[3] or 1
    local tintA = baseTint and baseTint[4] or 1
    local forceDesat = false
    local missingTintApplied = false

    previewState = previewState or GetStoredBarPreviewState(panelId, index)
    local state = previewState.conditional
    local kind = state and state.kind or nil
    local effectFlags = previewState.effectFlags
    local now = GetTime()
    -- Union predicate on purpose: any aura preview simulates "the aura is
    -- active", not just the duration-bar drain.
    local auraPresentationActive = IsBarPreviewAuraActive(state, effectFlags)
    local isAuraEntry = buttonData.type == "spell"
        and (buttonData.auraTracking == true or buttonData.addedAs == "aura")
    if isAuraEntry then
        if auraPresentationActive then
            -- Live needs the bar icon square: the aura layer's cover is
            -- what carries the gray (StyleSlotKit coverWanted).
            forceDesat = style.showBarIcon ~= false
                and CooldownCompanion:ShouldDesaturateAuraLayerWhileActive(buttonData, style)
        elseif buttonData.isPassive then
            forceDesat = not (buttonData.neverDesaturate
                or style.invertAuraDesaturationLogic)
        else
            forceDesat = style.desaturateWhileAuraNotActive == true
        end
        -- Missing tint, eye-gated like the icon slots (owner ruling: the
        -- mirror rests untinted; missing-aura effects render only under the
        -- "Preview Missing Aura Effects" toggle). The toggle is icons-mode
        -- today, so a bar mirror simply never wears it; live bars still tint
        -- their icon square while the aura is down.
        if not auraPresentationActive
            and style.iconMissingTintEnabled == true
            and style.iconMissingTintColor
            and CooldownCompanion:IsPreviewFlagActive(panelId, index, "_missingAuraPreview") then
            local missingTint = style.iconMissingTintColor
            tintR, tintG, tintB = missingTint[1], missingTint[2], missingTint[3]
            tintA = missingTint[4] or 1
            -- Live precedence (Tracking.lua): the missing tint outranks the
            -- cooldown tint, so the cooldown/zero-charge stand-ins below
            -- must not replace it.
            missingTintApplied = true
        end
    end

    -- Deterministic preview-off fill matches the live ready-state rule.
    -- Timed condition previews below replace this baseline when active.
    slot.statusBar:SetValue(buttonData.isPassive and 0 or 1)

    local chargePresentationKind = kind
    if not chargePresentationKind and UsesConfigOnlyBarChargeBehavior(buttonData) then
        chargePresentationKind = "charge_full"
    end

    if (kind == "cooldown" or kind == "cooldown_text" or IsAuraDurationTextKind(kind))
        and slot.timeText then
        slot.timeText:SetText("")
    end

    if kind == "aura_duration_bar" then
        local auraTint = style.iconAuraTintEnabled and style.iconAuraTintColor or baseTint
        tintR = auraTint and auraTint[1] or 1
        tintG = auraTint and auraTint[2] or 1
        tintB = auraTint and auraTint[3] or 1
        tintA = auraTint and auraTint[4] or 1
        local auraColor = style.barAuraColor or DEFAULT_BAR_AURA_COLOR or { 0, 1, 0.3, 1 }
        slot.statusBar:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1)
    end

    if IsAuraDurationTextKind(kind) and GetConditionalPreviewTiming then
        local startTime, _, remaining = GetConditionalPreviewTiming(state, now)
        if startTime then
            slot._cdcCondAnim = state
            ApplyBarAuraTimeTextPreview(slot, style, remaining, kind, buttonData)
        end
    elseif kind == "aura_duration_bar" and GetConditionalPreviewTiming then
        local startTime = GetConditionalPreviewTiming(state, now)
        if startTime then
            -- The Active Aura Indicator preview's fill effects ride the
            -- mirror's aura drain.
            -- Pandemic recolor (PTR 8): live parity is the kit's clone
            -- occluding the fill — including its color shift — while still
            -- inheriting the fill pulse. So with the pandemic preview on,
            -- the fill effects run pulse-only (shift suppressed: a playing
            -- VertexColor animation owns the color channel and the recolor
            -- would never show) and the base color is the pandemic color.
            local pandemicActive = effectFlags and effectFlags._pandemicPreview == true
                and IsPandemicPreviewEnabled(style, buttonData)
            local fxActive = effectFlags
                and (effectFlags._barAuraEffectPreview == true or pandemicActive)
                and ST.IsBarAuraIndicatorEnabled
                and ST.IsBarAuraIndicatorEnabled(style) == true
            local shifted = false
            if fxActive then
                shifted = ApplyBarSlotFillEffects(slot, style, pandemicActive)
            end
            local auraColor = style.barAuraColor or DEFAULT_BAR_AURA_COLOR or { 0, 1, 0.3, 1 }
            if pandemicActive then
                -- Forced opaque, matching the live clone (owner ruling: the
                -- pandemic color replaces the aura fill color, never blends).
                local pc = style.barPandemicColor or { 1, 0.5, 0, 1 }
                slot.statusBar:SetStatusBarColor(pc[1] or 1, pc[2] or 0.5, pc[3] or 0, 1)
            elseif shifted then
                -- White base while the shift animation owns the color.
                slot.statusBar:SetStatusBarColor(1, 1, 1, auraColor[4] or 1)
            else
                slot.statusBar:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1)
            end
            slot.statusBar._cdcOwner = slot
            slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
            slot._cdcCondAnim = state
            BarSlotFillOnUpdate(slot.statusBar)
        end
    elseif kind == "cooldown" and GetConditionalPreviewTiming then
        local startTime, duration, remaining = GetConditionalPreviewTiming(state, now)
        if startTime then
            if not buttonData.isPassive then
                local c = style.barCooldownColor or style.barColor or DEFAULT_BAR_COLOR
                slot.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                if style.desaturateOnCooldown then
                    forceDesat = true
                end
                if not missingTintApplied
                    and style.iconCooldownTintEnabled and style.iconCooldownTintColor then
                    local iconTint = style.iconCooldownTintColor
                    tintR = iconTint[1] or 1
                    tintG = iconTint[2] or 1
                    tintB = iconTint[3] or 1
                    tintA = iconTint[4] or 1
                end
            end
            slot.statusBar._cdcOwner = slot
            slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
            slot._cdcCondAnim = state
            BarSlotFillOnUpdate(slot.statusBar)
            if style.showCooldownText then
                local tt = EnsureBarSlotTimeText(slot)
                CooldownCompanion.ApplyFontStyle(tt, style, "cooldown")
                AnchorBarSlotTimeText(slot, style)
                tt:SetText(CooldownCompanion.FormatCooldownTime(remaining, style))
                tt:Show()
            end
        end
    elseif kind == "cooldown_text" and GetConditionalPreviewTiming then
        -- Countdown text alone on a resting bar: no drain, no cooldown color,
        -- no desaturation or tint.
        -- The conditional ticker keeps the text counting via _cdcCondAnim.
        local startTime, _, remaining = GetConditionalPreviewTiming(state, now)
        if startTime and not buttonData.isPassive and style.showCooldownText then
            local tt = EnsureBarSlotTimeText(slot)
            CooldownCompanion.ApplyFontStyle(tt, style, "cooldown")
            AnchorBarSlotTimeText(slot, style)
            tt:SetText(CooldownCompanion.FormatCooldownTime(remaining, style))
            tt:Show()
            slot._cdcCondAnim = state
        end
    elseif chargePresentationKind == "charge_full"
        or chargePresentationKind == "charge_missing"
        or chargePresentationKind == "charge_zero" then
        if UsesConfigOnlyBarChargeBehavior(buttonData) then
            local maxCharges = buttonData.maxCharges or 2
            if maxCharges < 2 then maxCharges = 2 end
            local current = maxCharges
            local colorKey = "chargeFontColor"
            if chargePresentationKind == "charge_missing" then
                current = math_max(1, maxCharges - 1)
                colorKey = "chargeFontColorMissing"
            elseif chargePresentationKind == "charge_zero" then
                current = 0
                colorKey = "chargeFontColorZero"
            end

            if chargePresentationKind ~= "charge_full" and slot.timeText then
                slot.timeText:SetText("")
            end

            local count = EnsureSlotCountText(slot)
            if ApplyBarCountTextStyle then
                ApplyBarCountTextStyle(slot, style)
            end
            if style.showChargeText ~= false then
                count:SetText(current)
            end
            if style.chargeFontColor or style.chargeFontColorMissing or style.chargeFontColorZero then
                local cc = style[colorKey] or { 1, 1, 1, 1 }
                count:SetTextColor(cc[1], cc[2], cc[3], cc[4] or 1)
            end

            -- Bar color per UpdateBarDisplay's charge states
            if not buttonData.isPassive then
                if chargePresentationKind == "charge_missing" then
                    local c = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR or { 1, 0.8, 0.2, 1 }
                    slot.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                elseif chargePresentationKind == "charge_zero" then
                    local c = style.barCooldownColor or style.barColor or DEFAULT_BAR_COLOR
                    slot.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                end
            end

            if chargePresentationKind ~= "charge_full" and GetConditionalPreviewTiming then
                -- Charge previews have no live recharge object. Use a stable
                -- local 12-second sample with 8 seconds remaining so the Bar
                -- mirror still demonstrates runtime-equivalent fill and text.
                local rechargeDuration = 12
                local rechargeRemaining = 8
                local rechargeElapsed = rechargeDuration - rechargeRemaining
                local rechargeState = {
                    kind = "cooldown",
                    duration = rechargeDuration,
                    startTime = now - rechargeElapsed,
                    loop = true,
                    loopDuration = rechargeDuration,
                    loopStartTime = now - rechargeElapsed,
                }
                slot.statusBar._cdcOwner = slot
                slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
                slot._cdcCondAnim = rechargeState
                BarSlotFillOnUpdate(slot.statusBar)
                if style.showCooldownText then
                    local tt = EnsureBarSlotTimeText(slot)
                    CooldownCompanion.ApplyFontStyle(tt, style, "cooldown")
                    AnchorBarSlotTimeText(slot, style)
                    tt:SetText(CooldownCompanion.FormatCooldownTime(rechargeRemaining, style))
                    tt:Show()
                end
            end

            if chargePresentationKind == "charge_zero" then
                if style.desaturateOnCooldown
                    or (buttonData.desaturateWhileZeroCharges
                        and not (CooldownCompanion.HasItemFallbacks
                            and CooldownCompanion.HasItemFallbacks(buttonData))) then
                    forceDesat = true
                end
                if not missingTintApplied
                    and style.iconCooldownTintEnabled and style.iconCooldownTintColor then
                    local c = style.iconCooldownTintColor
                    tintR, tintG, tintB, tintA = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
                end
            end
        end
    elseif kind == "unusable" then
        if style.showUnusable
            and not (buttonData.isPassive or buttonData.isPassiveCooldown or buttonData.addedAs == "aura") then
            if ST.UnusableVisualUsesDesaturation(style) then
                forceDesat = true
            end
            if ST.UnusableVisualUsesDimTint(style) then
                local uc = style.iconUnusableTintColor
                tintR = uc and uc[1] or 0.4
                tintG = uc and uc[2] or 0.4
                tintB = uc and uc[3] or 0.4
                tintA = uc and uc[4] or tintA
            end
        end
    elseif kind == "out_of_range" then
        if style.showOutOfRange and not buttonData.isPassive then
            tintR, tintG, tintB = 1, 0.2, 0.2
        end
    elseif kind == "aura_stack_text" then
        if style.showAuraStackText ~= false then
            local fs = EnsureBarSlotAuraStackText(slot)
            CooldownCompanion.ApplyFontStyle(fs, style, "auraStack")
            fs:ClearAllPoints()
            local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
            local asX = style.auraStackXOffset or 2
            local asY = style.auraStackYOffset or 2
            if style.showBarIcon ~= false then
                fs:SetPoint(asAnchor, slot.icon, asAnchor, asX, asY)
            else
                fs:SetPoint(asAnchor, slot, asAnchor, asX, asY)
            end
            -- Threshold-aware stand-in (2026-08-15 program); helper lives in
            -- ButtonFrame/Helpers.lua (200-local ceiling here).
            local asText, asR, asG, asB, asA = CooldownCompanion:GetAuraStackPreviewCountAndColor(
                buttonData, style, state.stackText)
            fs:SetText(asText)
            fs:SetTextColor(asR, asG, asB, asA)
            fs:Show()
        end
    elseif kind == "loss_of_control" and GetConditionalPreviewTiming then
        if style.showLossOfControl and buttonData.type == "spell" and not buttonData.isPassive
            and style.showBarIcon ~= false then
            local startTime, duration = GetConditionalPreviewTiming(state, now)
            if startTime then
                local widget = EnsureSlotLocCooldown(slot)
                widget:Show()
                widget:SetCooldown(startTime, duration)
                slot._cdcCondAnim = state
                slot._cdcCondArmedStart = startTime
            end
        end
    end

    if slot.icon then
        slot.icon:SetVertexColor(tintR, tintG, tintB, tintA)
        if forceDesat then
            slot.icon:SetDesaturated(true)
        end
    end
end

------------------------------------------------------------------------
-- Effect previews on the mirror: while a preview toggle is active for an
-- entry (or its whole panel), render the configured glow through the shared
-- Glows.lua setters. Mirror slots carry their own containers and `style` field.
-- Icons support proc/aura/ready/key-press, bars support bar aura effects, and
-- text slots support none.
------------------------------------------------------------------------
local EFFECT_PREVIEWS = {
    { flag = "_procGlowPreview", containerKey = "procGlow", setter = ST._SetProcGlow },
    -- The aura def yields its OFF-call to an active pandemic render: the two
    -- share one container, and an unconditional off-call would cold-reset
    -- the shared cache every pass — hiding a pandemic render mid-pass and
    -- restarting its animations on every config rebuild.
    { flag = "_auraGlowPreview", containerKey = "auraGlow", setter = ST._SetAuraGlow,
        yieldsToPandemic = true },
    -- Pandemic rides the aura glow container with SetAuraGlow's pandemic
    -- override (the pandemicGlow* key family). Listed AFTER the aura def,
    -- and it only ever calls the setter while ACTIVE — the aura def's own
    -- unconditional call reconciles the container whenever this preview is
    -- off (see the loop).
    { flag = "_pandemicPreview", containerKey = "auraGlow", setter = ST._SetAuraGlow,
        pandemicOverride = true },
    { flag = "_readyGlowPreview", containerKey = "readyGlow", setter = ST._SetReadyGlow },
    { flag = "_keyPressHighlightPreview", containerKey = "keyPressHighlight",
        setter = ST._SetKeyPressHighlight, withOverlay = true },
}

local function ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, isBarMode,
        effectiveStyle, barPreviewState)
    local style = effectiveStyle or group.style or {}
    if not effectiveStyle and CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end
    slot.style = style

    local canQuery = CooldownCompanion.IsPreviewFlagActive ~= nil

    if not isBarMode then
        -- Live parity (AuraDisplay bind gate): the pandemic rig renders
        -- nothing while the effect is disabled for this entry. Live shows
        -- the aura glow OUTSIDE the window and the pandemic style inside
        -- it (the window mask swaps them); the two exclusive PCC toggles
        -- preview those two states one at a time. Resolved once here
        -- because both auraGlow-container defs consult it.
        local pandemicWillRender = canQuery
            and CooldownCompanion:IsPreviewFlagActive(panelId, index, "_pandemicPreview")
            and IsPandemicPreviewEnabled(style, buttonData) or false
        for _, def in ipairs(EFFECT_PREVIEWS) do
            if def.setter then
                local active
                if def.pandemicOverride then
                    active = pandemicWillRender
                else
                    active = canQuery
                        and CooldownCompanion:IsPreviewFlagActive(panelId, index, def.flag) or false
                end
                if active and not slot[def.containerKey] and CreateGlowContainer then
                    slot[def.containerKey] = CreateGlowContainer(slot, 32, def.withOverlay)
                end
                if slot[def.containerKey] then
                    if def.pandemicOverride then
                        -- Shares the aura def's container: only an ACTIVE
                        -- pandemic render may touch it. The aura def's own
                        -- call reconciles the container whenever this
                        -- preview is off — an unconditional off-call here
                        -- would hide the aura glow that call just rendered.
                        if active then
                            def.setter(slot, true, true)
                        end
                    elseif def.yieldsToPandemic and not active and pandemicWillRender then
                        -- Skip the off-call: the pandemic def owns the
                        -- container this pass, and a hide here would
                        -- cold-reset its cache and restart its animations
                        -- on every rebuild.
                    else
                        def.setter(slot, active, false)
                    end
                end
            end
        end

        -- Missing Aura Glow: eye-gated from the preview command center like
        -- its siblings ("_missingAuraPreview", shared with the missing tint —
        -- one toggle shows the whole missing-aura presentation), rendered by
        -- the CC-side host renderer rather than the EFFECT_PREVIEWS loop —
        -- its setter is not MakeGlowSetter-shaped and its host is not a glow
        -- container. Same live-parity gates as the runtime: aura entries
        -- only, never keep-swipe (nothing would occlude it while the aura
        -- runs).
        if ST._SetMissingAuraGlowOnHost then
            local wantMissing = canQuery
                and CooldownCompanion:IsPreviewFlagActive(panelId, index, "_missingAuraPreview")
                and buttonData ~= nil
                and (buttonData.auraTracking or buttonData.addedAs == "aura")
                and (style.missingAuraGlowStyle or "none") ~= "none"
                and not CooldownCompanion:IsKeepSpellCooldownSwipeEntry(buttonData, style)
                or false
            local host = slot.missingAuraGlowHost
            if wantMissing and not host then
                host = CreateFrame("Frame", nil, slot)
                slot.missingAuraGlowHost = host
            end
            if host and wantMissing then
                -- The ICON rect, matching live, with an EXPLICIT size (same
                -- rule as the live applier): the dashes renderer measures the
                -- host the same tick it is styled, and a freshly
                -- point-anchored frame can report a stale rect. The renderer
                -- keys the host's dimensions into its cache signature, so a
                -- resize here re-renders.
                local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
                local inset = ST.GetEffectiveBorderLayoutSize(slot, borderSize, ST.GetBorderRenderMode(style))
                local slotW, slotH = slot:GetSize()
                host:ClearAllPoints()
                host:SetPoint("CENTER", slot, "CENTER", 0, 0)
                host:SetSize(math_max((slotW or 0) - 2 * inset, 1), math_max((slotH or 0) - 2 * inset, 1))
            end
            if host then
                ST._SetMissingAuraGlowOnHost(host, style, wantMissing)
            end
        end
        return
    end

    if SetBarAuraEffect then
        -- Live parity (Preview.lua barAuraEffectOnToggle): nothing renders
        -- while the bar aura indicator is disabled.
        barPreviewState = barPreviewState or GetStoredBarPreviewState(panelId, index)
        local effectFlags = barPreviewState.effectFlags
        local active = effectFlags and effectFlags._barAuraEffectPreview == true
            and ST.IsBarAuraIndicatorEnabled
            and ST.IsBarAuraIndicatorEnabled(style) == true
            or false
        if active and not slot.barAuraEffect and CreateGlowContainer then
            slot.barAuraEffect = CreateGlowContainer(slot, 32, false)
        end
        if slot.barAuraEffect then
            SetBarAuraEffect(slot, active)
        end
    end
end

-- Strip slots recycle from the icon pool; a glow left by a grid render
-- must not survive into a picker strip.
local function ClearSlotEffectPreviews(slot)
    for _, def in ipairs(EFFECT_PREVIEWS) do
        if slot[def.containerKey] and def.setter then
            def.setter(slot, false)
        end
    end
    if slot.missingAuraGlowHost and ST._SetMissingAuraGlowOnHost then
        ST._SetMissingAuraGlowOnHost(slot.missingAuraGlowHost, nil, false)
    end
    if slot.barAuraEffect and SetBarAuraEffect then
        SetBarAuraEffect(slot, false)
    end
end

local function StopConditionalTicker(preview)
    if preview.condTicker then
        preview.condTicker:Cancel()
        preview.condTicker = nil
    end
end

-- Forward declaration: defined with the text-slot suite below, referenced
-- by the ticker for the text countdown re-render.
local RenderTextSlot

-- Drives the animated conditional previews: countdown numbers for the
-- aura duration text, and re-arming the looping Cooldown widgets when
-- the stored preview state wraps to a new cycle (within a cycle the
-- computed startTime is constant, so a forward jump means a new cycle).
local function EnsureConditionalTicker(preview)
    if preview.condTicker then return end
    preview.condTicker = C_Timer.NewTicker(PANEL_PREVIEW_COND_TICK, function()
        if not GetConditionalPreviewTiming then return end
        local pool = preview.pools.iconSlots
        local used = preview.used.iconSlots or 0
        local now = GetTime()
        for i = 1, used do
            local slot = pool[i]
            local state = slot and slot:IsShown() and slot._cdcCondAnim or nil
            if state then
                local startTime, duration, remaining = GetConditionalPreviewTiming(state, now)
                if startTime then
                    if IsAuraDurationTextKind(state.kind) and slot.auraTextFS then
                        slot.auraTextFS:SetText(DecorateAuraDurationPreviewText(
                            ("%d"):format(math_ceil(remaining)), state.kind,
                            slot.style or {}, slot.buttonData))
                    end
                    local widget
                    if state.kind == "cooldown"
                        or state.kind == "cooldown_text"
                        or state.kind == "cooldown_swipe" then
                        widget = slot.cooldown
                    elseif state.kind == "aura_duration_swipe" then
                        widget = slot.auraSwipe
                    elseif state.kind == "loss_of_control" then
                        widget = slot.locCooldown
                    end
                    if widget and slot._cdcCondArmedStart
                        and startTime > slot._cdcCondArmedStart + 0.05 then
                        slot._cdcCondArmedStart = startTime
                        widget:SetCooldown(startTime, duration)
                        -- cooldown_swipe keeps its numbers hidden across
                        -- re-arms (a widget flag, not a region style), so
                        -- only the text-bearing kinds restyle here.
                        if state.kind == "cooldown" or state.kind == "cooldown_text" then
                            StyleSlotCooldownText(slot, slot.style or {})
                        end
                    end
                end
            end
        end
        -- Bar slots: time text countdown (the fill self-animates) and
        -- loss-of-control loop re-arms.
        local barPool = preview.pools.barSlots
        local usedBars = preview.used.barSlots or 0
        for i = 1, usedBars do
            local slot = barPool[i]
            local state = slot and slot:IsShown() and slot._cdcCondAnim or nil
            if state then
                local startTime, duration, remaining = GetConditionalPreviewTiming(state, now)
                if startTime then
                    if slot.timeText
                        and (state.kind == "cooldown"
                            or state.kind == "cooldown_text"
                            or IsAuraDurationTextKind(state.kind)) then
                        local style = slot.style or {}
                        local showText = (IsAuraDurationTextKind(state.kind)
                                and style.showAuraText ~= false)
                            or ((state.kind == "cooldown" or state.kind == "cooldown_text")
                                and style.showCooldownText)
                        if showText and CooldownCompanion.FormatTime then
                            -- Cooldown kinds preview the low-time look; aura
                            -- kinds never do (cooldown-only feature).
                            local formatFn = (state.kind == "cooldown" or state.kind == "cooldown_text")
                                and CooldownCompanion.FormatCooldownTime
                                or CooldownCompanion.FormatTime
                            slot.timeText:SetText(DecorateAuraDurationPreviewText(
                                formatFn(remaining, style),
                                state.kind, style, slot.buttonData))
                        end
                    end
                    if state.kind == "loss_of_control" and slot.locCooldown
                        and slot._cdcCondArmedStart
                        and startTime > slot._cdcCondArmedStart + 0.05 then
                        slot._cdcCondArmedStart = startTime
                        slot.locCooldown:SetCooldown(startTime, duration)
                    end
                end
            end
        end
        -- Text slots: re-render the format so the countdown ticks
        local textPool = preview.pools.textSlots
        local usedText = preview.used.textSlots or 0
        for i = 1, usedText do
            local slot = textPool[i]
            local state = slot and slot:IsShown() and slot._cdcCondAnim or nil
            if state and RenderTextSlot then
                RenderTextSlot(slot, slot.buttonData, slot.style or {}, state, now)
            end
        end
    end)
end

-- Static mirror of TextMode.lua CreateTextFrame: same saved settings,
-- entry name in place of the live token-substituted format string.
local function StyleTextEntry(slot, buttonData, group)
    local style = group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end

    local bgColor = style.textBgColor or { 0, 0, 0, 0 }
    slot.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    local borderSize = style.textBorderSize or 0
    local borderRenderMode = ST.GetBorderRenderMode(style, "textBorderRenderMode")
    local borderColor = style.textBorderColor or { 0, 0, 0, 1 }
    for i = 1, 4 do
        slot.borderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end
    ApplyBorderEdgePositions(slot.borderTextures, slot, borderSize, borderRenderMode)

    local ts = slot.textString
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    ts:SetFont(font, fontSize, fontOutline)
    local baseColor = style.textFontColor or { 1, 1, 1, 1 }
    ts:SetTextColor(baseColor[1], baseColor[2], baseColor[3], baseColor[4] or 1)
    ts:SetJustifyH(style.textAlignment or "LEFT")
    ST.ApplyFontShadowForOutline(ts, fontOutline, style.textShadow == true)
    -- Same padding contract as the live renderer: the slot box already
    -- reserves textPadding (GetTextEntryMetrics), so the string must be
    -- inset by it too or the mirror pins text to the border while the
    -- live button pads it.
    local padX, padY = 2, 1
    if ST._GetTextStringPadding then
        padX, padY = ST._GetTextStringPadding(style, slot)
    end
    ts:ClearAllPoints()
    ts:SetPoint("TOPLEFT", padX, -padY)
    ts:SetPoint("BOTTOMRIGHT", -padX, padY)
    -- Text content is rendered by ApplyTextSlotConditionalPreview (the
    -- entry's real token format, in its base or previewed state).
    slot.style = style
end

------------------------------------------------------------------------
-- Text-slot format rendering + conditional previews: the text mirror
-- renders each entry's real token format through the TextMode.lua parser
-- and a mirror-side substitution that reads only saved settings, static
-- name/keybind lookups, and the stored conditional preview state (never
-- live cooldown/aura/charge values). Idle base state: no time, aura
-- inactive, full charges, no stacks. The {pulse} animation is the one
-- live effect the static mirror does not run (its content still shows).
------------------------------------------------------------------------
-- TextMode.lua constants
local DEFAULT_TEXT_FORMAT = "{name}  {status}"
local DEFAULT_CD_COLOR = { 1, 0.3, 0.3, 1 }
local DEFAULT_READY_COLOR = { 0.2, 1.0, 0.2, 1 }
local DEFAULT_TEXT_AURA_COLOR = { 0, 0.925, 1, 1 }
local DEFAULT_CUSTOM_COLOR = { 1, 0.82, 0, 1 }

-- TextMode.lua WrapColor
local function WrapTextColor(text, color)
    if not text or text == "" then return "" end
    if not color then return text end
    return string.format("|cff%02x%02x%02x%s|r",
        math_floor(color[1] * 255),
        math_floor(color[2] * 255),
        math_floor(color[3] * 255),
        text)
end

-- TextMode.lua IsAuraOnlyEntry
local function IsAuraOnlyTextEntry(buttonData)
    return buttonData
        and buttonData.type == "spell"
        and buttonData.addedAs == "aura"
        and buttonData.auraTracking == true
end

-- Mirror twin of TextMode.lua SubstituteTokens for the static + preview
-- domain. Token-for-token parity where the mirror has the data; runtime
-- domains the mirror never reads (live time, aura, stacks) render as
-- their idle state.
local function SubstituteMirrorTokens(segments, style, buttonData, condState, now)
    local parts = {}
    local baseColor = style.textFontColor or { 1, 1, 1, 1 }
    local cdColor = style.textCooldownColor or DEFAULT_CD_COLOR
    local readyColor = style.textReadyColor or DEFAULT_READY_COLOR
    local auraColor = style.textAuraColor or DEFAULT_TEXT_AURA_COLOR
    local customColor = style.textCustomColor or DEFAULT_CUSTOM_COLOR
    local chargeFull = style.chargeFontColor or { 1, 1, 1, 1 }
    local chargeMissing = style.chargeFontColorMissing or { 1, 1, 1, 1 }
    local chargeZero = style.chargeFontColorZero or { 1, 1, 1, 1 }

    local kind = condState and condState.kind or nil
    local timeRemaining
    if kind == "cooldown" and GetConditionalPreviewTiming then
        local startTime, _, remaining = GetConditionalPreviewTiming(condState, now)
        if startTime and remaining and remaining > 0 then
            timeRemaining = remaining
        end
    end

    local usesCharges = CooldownCompanion.UsesChargeBehavior
        and CooldownCompanion.UsesChargeBehavior(buttonData) or false
    local currentCharges, maxCharges, chargeState
    if usesCharges then
        maxCharges = buttonData.maxCharges
        if kind == "charge_missing" or kind == "charge_zero" or kind == "charge_full" then
            local mc = maxCharges or 2
            if mc < 2 then mc = 2 end
            maxCharges = mc
            if kind == "charge_missing" then
                currentCharges = math_max(1, mc - 1)
                chargeState = "missing"
            elseif kind == "charge_zero" then
                currentCharges = 0
                chargeState = "zero"
            else
                currentCharges = mc
                chargeState = "full"
            end
        else
            -- Idle mirror state: full charges (live learns the count at
            -- runtime; a never-observed maxCharges renders empty there too)
            currentCharges = maxCharges
            chargeState = "full"
        end
    end

    local isUnusable = kind == "unusable"
    local isOutOfRange = kind == "out_of_range"
    -- Live {?available}: _desatCooldownActive ~= true
    local notAvailable = kind == "cooldown" or kind == "charge_zero"

    local function TokenPresent(tokenName)
        if tokenName == "time" then
            return timeRemaining ~= nil
        elseif tokenName == "charges" then
            return usesCharges
        elseif tokenName == "maxcharges" then
            return usesCharges and chargeState == "full"
        elseif tokenName == "missingcharges" then
            return usesCharges and chargeState == "missing"
        elseif tokenName == "zerocharges" then
            return usesCharges and chargeState == "zero"
        elseif tokenName == "keybind" then
            local kb = CooldownCompanion:GetKeybindText(buttonData, nil, nil)
            return kb ~= nil and kb ~= ""
        elseif tokenName == "unusable" then
            return isUnusable
        elseif tokenName == "oor" then
            return isOutOfRange
        elseif tokenName == "available" then
            return not notAvailable
        elseif tokenName == "incombat" then
            return UnitAffectingCombat("player") == true
        end
        -- stacks/aura/pandemic/proc: runtime-only domains, idle on the mirror
        return false
    end

    local skipDepth = 0
    local colorOverride = nil
    local colorStack = {}

    for _, seg in ipairs(segments) do
        if seg.type == "cond_start" then
            if skipDepth > 0 then
                skipDepth = skipDepth + 1
            else
                local present = TokenPresent(seg.value)
                local shouldShow = (seg.negated and not present) or (not seg.negated and present)
                if not shouldShow then
                    skipDepth = 1
                end
            end
        elseif seg.type == "cond_end" then
            if skipDepth > 0 then
                skipDepth = skipDepth - 1
            end
        elseif skipDepth > 0 then
            -- Inside a false conditional
        elseif seg.type == "effect_start" or seg.type == "effect_end" then
            -- {pulse} wrappers: content renders, the animation does not
        elseif seg.type == "color_start" then
            colorStack[#colorStack + 1] = colorOverride
            if seg.value == "cooldown" then colorOverride = cdColor
            elseif seg.value == "ready" then colorOverride = readyColor
            elseif seg.value == "active" then colorOverride = auraColor
            elseif seg.value == "custom" then colorOverride = customColor
            end
        elseif seg.type == "color_end" then
            colorOverride = colorStack[#colorStack]
            colorStack[#colorStack] = nil
        elseif seg.type == "literal" then
            if colorOverride then
                parts[#parts + 1] = WrapTextColor(seg.value, colorOverride)
            else
                parts[#parts + 1] = seg.value
            end
        elseif seg.unknown then
            -- Unknown tokens render as empty
        else
            local token = seg.value
            if token == "name" then
                local name = buttonData.customName or buttonData.name or ""
                if not buttonData.customName and buttonData.type == "spell" then
                    local spellName = C_Spell.GetSpellName(buttonData.id)
                    if spellName then name = spellName end
                elseif not buttonData.customName and CooldownCompanion.IsEntryItemLike
                    and CooldownCompanion.IsEntryItemLike(buttonData) then
                    local itemName = buttonData.id and C_Item.GetItemNameByID(buttonData.id)
                    if itemName then name = itemName end
                end
                parts[#parts + 1] = WrapTextColor(name, colorOverride or baseColor)

            elseif token == "time" then
                if timeRemaining then
                    parts[#parts + 1] = WrapTextColor(
                        CooldownCompanion.FormatTime(timeRemaining, style), colorOverride or cdColor)
                end

            elseif token == "charges" then
                if currentCharges ~= nil then
                    local cc
                    if currentCharges == maxCharges then
                        cc = chargeFull
                    elseif currentCharges == 0 then
                        cc = chargeZero
                    else
                        cc = chargeMissing
                    end
                    parts[#parts + 1] = WrapTextColor(tostring(currentCharges), colorOverride or cc)
                end

            elseif token == "maxcharges" then
                if maxCharges and maxCharges > 1 then
                    parts[#parts + 1] = WrapTextColor(tostring(maxCharges), colorOverride or baseColor)
                end

            elseif token == "keybind" then
                local kb = CooldownCompanion:GetKeybindText(buttonData, nil, nil)
                if kb and kb ~= "" then
                    parts[#parts + 1] = WrapTextColor(kb, colorOverride or baseColor)
                end

            elseif token == "status" then
                if IsAuraOnlyTextEntry(buttonData) then
                    -- Aura-only entries have no ready/cooldown fallback
                elseif timeRemaining then
                    parts[#parts + 1] = WrapTextColor(
                        CooldownCompanion.FormatTime(timeRemaining, style), colorOverride or cdColor)
                else
                    parts[#parts + 1] = WrapTextColor(
                        style.textReadyText or "Ready", colorOverride or readyColor)
                end

            elseif token == "icon" then
                local iconTex = GetLayoutPreviewIcon(buttonData)
                if iconTex then
                    parts[#parts + 1] = string.format("|T%s:0|t", tostring(iconTex))
                end

            elseif token == "br" then
                parts[#parts + 1] = "\n"
            end
            -- {stacks}: a runtime-only domain, idle (empty) on the mirror.
            -- {aura}: emits nothing here because it emits nothing at runtime
            -- either -- text panels are aura-blind on 12.1 (SubstituteTokens
            -- in ButtonFrame/TextMode.lua).
        end
    end

    return table.concat(parts)
end

function RenderTextSlot(slot, buttonData, style, condState, now)
    local ts = slot.textString
    if not (ParseFormatString and slot._cdcTextSegments) then
        -- Parser unavailable: fall back to the plain entry name
        ts:SetText(buttonData.customName or buttonData.name
            or GetConfigEntryDisplayName(buttonData) or "")
        return
    end
    ts:SetText(SubstituteMirrorTokens(slot._cdcTextSegments, style, buttonData, condState, now))
end

local function ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index, forceBase)
    slot._cdcCondAnim = nil
    slot.buttonData = buttonData

    local style = slot.style or group.style or {}
    local fmt = buttonData.textFormat or style.textFormat or DEFAULT_TEXT_FORMAT
    slot._cdcTextSegments = ParseFormatString and ParseFormatString(fmt) or nil

    -- Live ApplyTextLayout: multiline formats wrap from the top. buttonData is
    -- the metrics cache key, so this shares the entry's cache slot with the
    -- pitch pass rather than churning the style table's slot.
    if GetTextEntryMetrics then
        local _, _, lineCount = GetTextEntryMetrics(style, buttonData, fmt)
        local isMultiline = (lineCount or 1) > 1
        slot.textString:SetJustifyV(isMultiline and "TOP" or "MIDDLE")
        slot.textString:SetWordWrap(isMultiline)
    end

    local state = not forceBase and GetStoredConditionalPreviewState
        and GetStoredConditionalPreviewState(panelId, index) or nil
    RenderTextSlot(slot, buttonData, style, state, GetTime())
    if state and state.kind == "cooldown" then
        -- The countdown needs re-rendering as it ticks
        slot._cdcCondAnim = state
    end
end

-- Mirror of GroupFrame's ApplyTextGroupHeader, drawn on the content frame.
local function UpdateTextGroupHeader(preview, group, style, headerHeight)
    local header = preview.textHeader
    if headerHeight <= 0 then
        if header then header:Hide() end
        return
    end
    if not header then
        header = preview.content:CreateFontString(nil, "OVERLAY")
        header:SetJustifyV("TOP")
        preview.textHeader = header
    end
    local font = CooldownCompanion:FetchFont(style.textFont or "Friz Quadrata TT")
    local fontSize = style.textHeaderFontSize or style.textFontSize or 12
    local fontOutline = ST.GetEffectiveFontOutline(style.textFontOutline or "OUTLINE")
    header:SetFont(font, fontSize, fontOutline)
    local hdrColor = style.textHeaderFontColor or { 1, 1, 1, 1 }
    header:SetTextColor(hdrColor[1], hdrColor[2], hdrColor[3], hdrColor[4] or 1)
    ST.ApplyFontShadowForOutline(header, fontOutline, style.textShadow == true)
    local align = style.textAlignment or "LEFT"
    header:SetJustifyH(align)
    header:SetText(group.name or "")
    header:ClearAllPoints()
    local growthOrigin = style.growthOrigin or "TOPLEFT"
    -- Raw "BOTTOM" counts only while it is the ACTIVE centered edge, matching
    -- the live header path: an axis-mismatched value folds to TOPLEFT.
    local vEdge = (growthOrigin == "BOTTOMLEFT" or growthOrigin == "BOTTOMRIGHT"
        or ST.GetCenteredGrowthEdge(growthOrigin, ST.GetPanelLayoutOrientation(group.displayMode, style)) == "BOTTOM")
        and "BOTTOM" or "TOP"
    local anchor = align == "RIGHT" and (vEdge .. "RIGHT") or align == "CENTER" and vEdge or (vEdge .. "LEFT")
    local xOff = (align == "CENTER") and 0 or (align == "RIGHT") and -2 or 2
    local yOff = vEdge == "BOTTOM" and 1 or -1
    header:SetPoint(anchor, preview.content, anchor, xOff, yOff)
    header:SetWidth(math_max(1, (preview.content:GetWidth() or 0) - 4))
    header:Show()
end

local function GetHostFitBox(host, readOnly)
    local hostWidth = host:GetWidth() or 0
    local hostHeight = (host:GetHeight() or 0) - GetHostBottomReserve(host)
    if readOnly then
        -- Overview tiles are measured before their final build and can
        -- legitimately be smaller than the focused preview's 80px guard.
        -- Only substitute fallback dimensions when no measurement exists.
        if hostWidth <= 0 then hostWidth = 340 end
        if hostHeight <= 0 then hostHeight = 200 end
    else
        if hostWidth < 40 then hostWidth = 340 end
        if hostHeight < 40 then hostHeight = 200 end
    end
    local minFitSize = readOnly and 1 or 80
    return math_max(minFitSize, hostWidth - (PANEL_PREVIEW_PADDING * 2)),
        math_max(minFitSize, hostHeight - (PANEL_PREVIEW_PADDING * 2))
end

local function GetHostFitScale(host, contentWidth, contentHeight, readOnly)
    local maxWidth, maxHeight = GetHostFitBox(host, readOnly)
    return math_min(1, maxWidth / math_max(1, contentWidth), maxHeight / math_max(1, contentHeight))
end

-- Fallback for panel types with no meaningful geometric mirror (trigger,
-- texture, and rotation-assistant panels): a flat strip of
-- clickable entry icons with the same selection, badges, tooltips, and
-- context-menu behavior as the mirrored slots.
local STRIP_ICON_SIZE = 36
local STRIP_SPACING = 4
local STRIP_PER_ROW = 8

-- Trigger panels stack their display visual above the selection strip inside
-- one preview: the strip may claim at most this share of the fit height, and
-- the band between the two reuses the preview's own padding rhythm.
local TRIGGER_PREVIEW_STRIP_MAX_SHARE = 0.35
-- Bottom band reserved for the "no entries yet" message when there is no strip.
local TRIGGER_PREVIEW_EMPTY_BAND = 44

local function GetStripNaturalSize(count)
    if count <= 0 then
        return 0, 0
    end
    local cols = math_min(count, STRIP_PER_ROW)
    local rows = math_ceil(count / STRIP_PER_ROW)
    return (cols - 1) * (STRIP_ICON_SIZE + STRIP_SPACING) + STRIP_ICON_SIZE,
        (rows - 1) * (STRIP_ICON_SIZE + STRIP_SPACING) + STRIP_ICON_SIZE
end

-- Hidden scratch FontString for measuring trigger text natural size; the
-- metrics helper sets its own font, so no template styling matters here.
local triggerTextMeasure
local function GetTriggerTextMeasureFontString()
    if not triggerTextMeasure then
        local holder = CreateFrame("Frame", nil, UIParent)
        holder:Hide()
        triggerTextMeasure = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    end
    return triggerTextMeasure
end

-- Natural (unscaled) size of a trigger panel's display visual, or 0,0 when
-- that visual is empty. Mirrors the runtime RenderStandaloneDisplay dispatch.
local function GetTriggerDisplayNaturalSize(group)
    local displayType = CooldownCompanion.GetStandaloneDisplayType(group)
    if displayType == "icon" then
        local settings = CooldownCompanion:GetTriggerPanelIconSettings(group)
        if settings and ST._IsValidIconTexture and ST._IsValidIconTexture(settings.manualIcon) then
            return CooldownCompanion.GetTriggerIconDimensions(settings)
        end
        return 0, 0
    end
    if displayType == "text" then
        local settings = CooldownCompanion:GetTriggerPanelTextSettings(group)
        if settings and CooldownCompanion.HasTriggerTextValue(settings) then
            local width, height = CooldownCompanion.GetTriggerTextDisplayMetrics(
                GetTriggerTextMeasureFontString(), settings)
            return width, height
        end
        return 0, 0
    end
    local settings = CooldownCompanion:GetTriggerPanelSignalSettings(group)
    if type(settings) == "table" and settings.sourceType ~= nil and settings.sourceValue ~= nil then
        local scale = tonumber(settings.scale) or 1
        local sourceWidth = (tonumber(settings.width) or 128) * scale
        local sourceHeight = (tonumber(settings.height) or 128) * scale
        local geometry = CooldownCompanion.BuildTexturePanelGeometry
            and CooldownCompanion:BuildTexturePanelGeometry(settings, sourceWidth, sourceHeight)
        if geometry then
            return math_max(1, geometry.boundsWidth or sourceWidth),
                math_max(1, geometry.boundsHeight or sourceHeight)
        end
        return sourceWidth, sourceHeight
    end
    return 0, 0
end

local function GetPanelPreviewNaturalSize(group)
    if type(group) ~= "table" then
        return 220, 90
    end

    if CooldownCompanion:IsTexturePanelGroup(group) then
        local settings = CooldownCompanion:GetTexturePanelSettings(group)
        if type(settings) == "table" and CooldownCompanion.BuildTexturePanelGeometry then
            local scale = tonumber(settings.scale) or 1
            local sourceWidth = (tonumber(settings.width) or 128) * scale
            local sourceHeight = (tonumber(settings.height) or 128) * scale
            local geometry = CooldownCompanion:BuildTexturePanelGeometry(
                settings,
                sourceWidth,
                sourceHeight
            )
            if geometry then
                return math_max(1, geometry.boundsWidth or sourceWidth),
                    math_max(1, geometry.boundsHeight or sourceHeight)
            end
        end
        return 128, 128
    end

    -- Natural size feeds Group Overview tiles only, and a trigger tile renders
    -- the display alone with the entry strip standing in when no display is
    -- configured (see BuildTriggerPanelPreview) - so measure exactly that.
    if CooldownCompanion:IsTriggerPanelGroup(group) then
        local dispW, dispH = GetTriggerDisplayNaturalSize(group)
        if dispW > 0 then
            return dispW, dispH
        end
        local stripW, stripH = GetStripNaturalSize(#(group.buttons or {}))
        if stripW <= 0 then
            return 220, 90
        end
        return stripW, stripH
    end

    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    if isBarMode or isTextMode or IsIconModePanel(group) then
        local count = #(group.buttons or {})
        if count == 0 then
            return 220, 90
        end
        local geo = GetPanelGeometry(group, isBarMode, isTextMode)
        local perRow = math_max(1, geo.buttonsPerRow)
        local cols, rows
        if geo.orientation == "horizontal" then
            cols = math_min(count, perRow)
            rows = math_ceil(count / perRow)
        else
            rows = math_min(count, perRow)
            cols = math_ceil(count / perRow)
        end
        local headerHeight = isTextMode
            and (group.style or {}).showTextGroupHeader == true
            and (((group.style or {}).textHeaderFontSize
                or (group.style or {}).textFontSize or 12) + 4)
            or 0
        return (cols - 1) * (geo.entryWidth + geo.spacing) + geo.entryWidth,
            (rows - 1) * (geo.entryHeight + geo.spacing) + geo.entryHeight + headerHeight
    end

    local count = group.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT
        and 1 or #(group.buttons or {})
    if count == 0 then
        return 220, 90
    end
    local cols = math_min(count, STRIP_PER_ROW)
    local rows = math_ceil(count / STRIP_PER_ROW)
    return (cols - 1) * (STRIP_ICON_SIZE + STRIP_SPACING) + STRIP_ICON_SIZE,
        (rows - 1) * (STRIP_ICON_SIZE + STRIP_SPACING) + STRIP_ICON_SIZE
end

-- layout (optional) is the trigger preview's band placement: scaleOverride
-- replaces the fit-to-host scale (the display visual above owns most of the
-- height) and anchorPoint = "BOTTOM" parks the strip along the bottom edge.
local function BuildSelectionStrip(preview, host, panelId, group, readOnly, layout)
    StopConditionalTicker(preview)
    local isRA = group.displayMode == ST.DISPLAY_MODE_ROTATION_ASSISTANT
    local entries = {}
    if isRA then
        local spellID = CooldownCompanion:GetRotationAssistantActionSpellID()
        entries[1] = {
            buttonData = {
                type = "spell",
                id = spellID,
                name = ST.ROTATION_ASSISTANT_NAME,
                manualIcon = CooldownCompanion:GetRotationAssistantFallbackIcon(spellID),
            },
            isRotationAssistant = true,
        }
    else
        for index, buttonData in ipairs(group.buttons or {}) do
            entries[#entries + 1] = { buttonData = buttonData, index = index }
        end
    end

    local count = #entries
    if count == 0 then
        SetPreviewMessage(preview, readOnly and "Empty Panel"
            or "This panel has no entries yet. Add spells or items in the Panels column.")
        FinalizePreviewState(preview)
        return
    end

    local w, h = STRIP_ICON_SIZE, STRIP_ICON_SIZE
    local cols = math_min(count, STRIP_PER_ROW)
    local rows = math_ceil(count / STRIP_PER_ROW)
    local contentWidth = (cols - 1) * (w + STRIP_SPACING) + w
    local contentHeight = (rows - 1) * (h + STRIP_SPACING) + h
    local scale = layout and layout.scaleOverride
        or GetHostFitScale(host, contentWidth, contentHeight, readOnly)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()

    local layoutDrag = readOnly and { slots = {} } or CreatePreviewLayoutDrag(preview, panelId)
    layoutDrag.count = count
    layoutDrag.slotW, layoutDrag.slotH = w, h
    layoutDrag.scale = scale
    layoutDrag.anchor = "TOPLEFT"
    layoutDrag.cellXY = function(d)
        local row = math_floor((d - 1) / STRIP_PER_ROW)
        local col = (d - 1) % STRIP_PER_ROW
        return col * (w + STRIP_SPACING), -(row * (h + STRIP_SPACING))
    end
    preview.layoutDrag = layoutDrag
    local dragModel = (not readOnly and not isRA and count >= 2) and layoutDrag or nil

    for i, entryInfo in ipairs(entries) do
        local slot = AcquireSlot(preview, content, "iconSlots")
        slot:SetSize(w, h)
        local cx, cy = layoutDrag.cellXY(i)
        ApplyPreviewSlotGeometry(preview, slot, "TOPLEFT", cx, cy)

        local buttonData = entryInfo.buttonData
        StyleMirroredIconFrame(slot, { buttonData = buttonData }, group)
        -- Selection strips are pickers, not mirrors: no conditional or
        -- effect previews here, and recycled grid slots keep neither.
        ResetSlotConditionalVisuals(slot)
        slot.icon:SetVertexColor(1, 1, 1, 1)
        ClearSlotEffectPreviews(slot)
        if slot.keybindText then slot.keybindText:Hide() end

        if readOnly then
            slot.icon:SetDesaturated(false)
            DisableReadOnlySlotInteraction(slot)
        elseif entryInfo.isRotationAssistant then
            slot:EnableMouse(true)
            slot.icon:SetDesaturated(false)
            slot._cdcPreviewButtonData = buttonData
            ApplySlotEffectPreviews(slot, buttonData, group, panelId, 1, false)
            ApplySlotConditionalPreview(slot, buttonData, group, panelId, 1)
            if slot.problemBadge then slot.problemBadge:Hide() end
            if slot.problemBadgeBack then slot.problemBadgeBack:Hide() end
            if slot.overrideBadge then slot.overrideBadge:Hide() end
            if slot.overrideBadgeBack then slot.overrideBadgeBack:Hide() end
            -- The assistant pseudo-entry is never a copy target, and the
            -- recycled slot may carry a ring from a grid render.
            if slot.copyTargetHighlight then slot.copyTargetHighlight:Hide() end
            -- Recycled slots may carry a drag handler from a grid render
            slot:SetScript("OnMouseDown", nil)
            if CS.selectedRotationAssistantEntry == true
                and not IsGlowPreviewActiveOnEntry(panelId, 1) then
                slot.selectedHighlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
                ST.ApplyBorderTextures(slot.selectedHighlight.ringTextures, slot.selectedHighlight,
                    PANEL_PREVIEW_RING_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
                slot.selectedHighlight:Show()
            end
            slot:SetScript("OnMouseUp", function(self, mouseButton)
                if CS.dragState and CS.dragState.phase == "active" then return end
                if GetCursorInfo() then return end
                if mouseButton ~= "LeftButton" then return end
                if CS.selectedRotationAssistantEntry == true then
                    -- This click MEANS "deselect the assistant", and the flag
                    -- is cleared here because SelectConfigButtonPanel's
                    -- same-panel path deliberately leaves selection alone. The
                    -- Visibility tab dispatches on this flag, so a stale true
                    -- would pin it to entry rules with no way back to the
                    -- panel's own.
                    CS.selectedRotationAssistantEntry = nil
                    ST._SelectConfigButtonPanel(panelId, { clearPanelMulti = true })
                else
                    ST._SelectConfigRotationAssistantEntry(panelId, { containerId = CS.selectedContainer })
                end
                CooldownCompanion:RefreshConfigSelection()
            end)
            slot:SetScript("OnEnter", function(self)
                self.hoverHighlight:SetFrameLevel(self:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
                self.hoverHighlight:Show()
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(ST.ROTATION_ASSISTANT_NAME, 1, 1, 1)
                GameTooltip:Show()
            end)
            slot:SetScript("OnLeave", function(self)
                self.hoverHighlight:Hide()
                GameTooltip:Hide()
            end)
            layoutDrag.slots[1] = slot
        else
            local status = CollectEntryStatus(buttonData, group)
            slot.icon:SetDesaturated(not status.usable)
            if status.disabled then
                slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
            end
            slot._cdcBaseAlpha = status.disabled and PANEL_PREVIEW_DISABLED_ALPHA or 1
            ApplySlotBadges(slot, status, scale)
            ApplySelectionVisuals(slot, entryInfo.index)
            CopyMode.ApplyTargetVisuals(slot, panelId, buttonData)
            layoutDrag.slots[entryInfo.index] = slot
            WireEntryInteraction(slot, panelId, entryInfo.index, buttonData, status, dragModel)
        end
    end

    local anyAnimated = false
    for _, slot in pairs(layoutDrag.slots) do
        if slot and slot._cdcCondAnim then
            anyAnimated = true
            break
        end
    end
    if not readOnly and anyAnimated then
        EnsureConditionalTicker(preview)
    end

    content:SetScale(scale)
    content:ClearAllPoints()
    if layout and layout.anchorPoint == "BOTTOM" then
        -- Offset in content-local units so the strip clears the fit-box
        -- padding by exactly PANEL_PREVIEW_PADDING on screen at any scale.
        content:SetPoint("BOTTOM", preview.root, "BOTTOM", 0,
            PANEL_PREVIEW_PADDING / math_max(scale, 0.01))
    else
        content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)
    end

    FinalizePreviewState(preview)
end

-- Static mirror of BarMode.lua CreateBarFrame: same saved settings, same
-- shared area/border helpers, full fill, no runtime state.
local function StyleBarEntry(slot, buttonData, group, effectiveStyle)
    local style = effectiveStyle or group.style or {}
    if not effectiveStyle and CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end
    slot.style = style

    local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(style)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(slot, borderSize, borderRenderMode)
    local showIcon = style.showBarIcon ~= false
    local isVertical = style.barFillVertical or false
    local iconReverse = showIcon and (style.barIconReverse or false)
    local barHeight = style.barHeight or 20
    local iconSize = (style.barIconSizeOverride and style.barIconSize) or barHeight
    local iconOffset = showIcon and (style.barIconOffset or 0) or 0
    local barAreaLeft = showIcon and (iconSize + iconOffset) or 0
    local barAreaTop = barAreaLeft
    local bgColor = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
    local borderColor = style.borderColor or { 0, 0, 0, 1 }

    slot.bg:ClearAllPoints()
    if showIcon then
        SetBarAreaPoints(slot.bg, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        slot.bg:SetAllPoints()
    end
    slot.bg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])

    if showIcon then
        SetIconAreaPoints(slot.icon, slot, isVertical, iconReverse, iconSize, borderLayoutSize)
        ST._ApplyIconTexCoord(slot.icon, iconSize, iconSize, style.iconZoom)
        slot.icon:SetTexture(GetConfigOnlyBarPreviewIcon(buttonData))
        slot.icon:Show()
        SetIconAreaPoints(slot.iconBg, slot, isVertical, iconReverse, iconSize, 0)
        slot.iconBg:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4])
        slot.iconBg:Show()
        SetIconAreaPoints(slot.iconBounds, slot, isVertical, iconReverse, iconSize, 0)
        for i = 1, 4 do
            slot.iconBorderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
        end
        ApplyBorderEdgePositions(slot.iconBorderTextures, slot.iconBounds, borderSize, borderRenderMode)
    else
        slot.icon:Hide()
        slot.iconBg:Hide()
        for i = 1, 4 do
            slot.iconBorderTextures[i]:Hide()
        end
    end

    if showIcon then
        SetBarAreaPoints(slot.barBounds, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, 0)
    else
        slot.barBounds:ClearAllPoints()
        slot.barBounds:SetAllPoints()
    end

    SetBarAreaPoints(slot.statusBar, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
    slot.statusBar:SetOrientation(isVertical and "VERTICAL" or "HORIZONTAL")
    slot.statusBar:SetMinMaxValues(0, 1)
    slot.statusBar:SetValue(1)
    slot.statusBar:SetReverseFill(style.barReverseFill or false)
    slot.statusBar:SetStatusBarTexture(CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
    local barColor = style.barColor or DEFAULT_BAR_COLOR
    slot.statusBar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4])
    slot.statusBar:Show()

    SetBarAreaPoints(slot.textFrame, slot, isVertical, iconReverse, barAreaLeft, barAreaTop, borderLayoutSize)
    slot.textFrame:SetFrameLevel(slot.statusBar:GetFrameLevel() + 2)

    local nameText = slot.nameText
    CooldownCompanion.ApplyFontStyle(nameText, style, "barName", 10)
    local nameOffX = style.barNameTextOffsetX or 0
    local nameOffY = style.barNameTextOffsetY or 0
    local nameReverse = style.barNameTextReverse
    nameText:ClearAllPoints()
    if isVertical then
        if nameReverse then
            nameText:SetPoint("TOP", nameOffX, -3 + nameOffY)
        else
            nameText:SetPoint("BOTTOM", nameOffX, 3 + nameOffY)
        end
        nameText:SetJustifyH("CENTER")
    else
        if nameReverse then
            nameText:SetPoint("RIGHT", -3 + nameOffX, nameOffY)
            nameText:SetJustifyH("RIGHT")
        else
            nameText:SetPoint("LEFT", 3 + nameOffX, nameOffY)
            nameText:SetJustifyH("LEFT")
        end
    end
    if style.showBarNameText ~= false or buttonData.customName then
        nameText:SetText(GetConfigOnlyBarPreviewName(buttonData))
        nameText:Show()
    else
        nameText:Hide()
    end

    ApplyBarReadyPresentation(slot, buttonData, style)

    for i = 1, 4 do
        slot.borderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end
    ApplyBorderEdgePositions(slot.borderTextures, slot.barBounds, borderSize, borderRenderMode)
end

-- Standalone-display Live Preview: draws the panel's actual chosen visual fit
-- to the host, instead of (texture panels) or above (trigger panels) the
-- entry-icon selection strip. For these panels the chosen texture/icon/text IS
-- the visual, so a spell icon alone would show something that never renders
-- in-game. Reuses GroupTabs' fit-to-box renderer (ST._UpdateTexturePanelPreview)
-- for textures; icon and text visuals are drawn by the render helpers below.
local TEXTURE_INDICATOR_MIRROR_PREVIEWS = {
    { key = "proc", flag = "_textureProcPreview" },
    { key = "aura", flag = "_textureAuraPreview" },
    { key = "ready", flag = "_textureReadyPreview" },
    { key = "unusable", flag = "_textureUnusablePreview" },
}

local function StopTextureMirrorEffects(mirror)
    local host = mirror and mirror.effectHost
    if not host then
        return
    end

    if StopAllTextureIndicatorEffects then
        StopAllTextureIndicatorEffects(host)
    else
        host:SetScript("OnUpdate", nil)
        if host.visualRoot then
            host.visualRoot:SetAlpha(1)
            host.visualRoot:SetScale(1)
            host.visualRoot:ClearAllPoints()
            host.visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
        end
    end

    host._activeDisplayType = nil
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._indicatorBaseVisualsReady = nil
end

local function GetStoredTextureIndicatorPreview(panelId)
    if not (panelId and IsStoredPreviewFlagActive) then
        return nil, nil
    end

    for _, preview in ipairs(TEXTURE_INDICATOR_MIRROR_PREVIEWS) do
        if IsStoredPreviewFlagActive(panelId, nil, preview.flag) then
            return preview.key, preview.flag
        end
    end
    return nil, nil
end

local function EnsureTextureMirror(preview)
    local mirror = preview.textureMirror
    if mirror then
        return mirror
    end

    local root = CreateFrame("Frame", nil, preview.root)
    root:SetAllPoints(preview.root)
    root:SetClipsChildren(false)

    -- Effects belong to this config-owned frame tree. The runtime Texture
    -- host is never borrowed, shown, or animated by the pinned Live Preview.
    local effectHost = CreateFrame("Frame", nil, root)
    effectHost:SetAllPoints(root)
    effectHost:SetClipsChildren(false)
    local visualRoot = CreateFrame("Frame", nil, effectHost)
    visualRoot:SetPoint("CENTER", effectHost, "CENTER", 0, 0)
    visualRoot:SetSize(1, 1)
    effectHost.visualRoot = visualRoot

    mirror = {
        root = root,
        effectHost = effectHost,
        anchor = visualRoot,
        clickMode = "texture",
        primary = visualRoot:CreateTexture(nil, "ARTWORK"),
        secondary = visualRoot:CreateTexture(nil, "ARTWORK"),
        placeholder = root:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge"),
    }
    effectHost.primaryTexture = mirror.primary
    effectHost.secondaryTexture = mirror.secondary
    mirror.placeholder:SetPoint("CENTER")
    mirror.placeholder:SetText("No texture selected")

    -- Click the rendered visual to open its picker (inline texture browser or
    -- the trigger icon picker, per the build's clickMode). root is a raw,
    -- module-owned frame, so attaching scripts here is safe (not an AceGUI
    -- underlying frame). Mouse is enabled per build; the browse guard skips
    -- while the inline browser is already open for this panel.
    local hoverFrame = CreateFrame("Frame", nil, root)
    hoverFrame:SetAllPoints(root)
    hoverFrame:SetFrameLevel(effectHost:GetFrameLevel() + 5)
    local hoverCue = hoverFrame:CreateTexture(nil, "OVERLAY")
    hoverCue:SetAllPoints()
    hoverCue:SetColorTexture(1, 1, 1, 0.06)
    hoverCue:Hide()
    mirror.hoverCue = hoverCue

    local function IsBrowsingThisPanel()
        return CS.inlineTextureBrowserOpen ~= nil
            and CS.inlineTextureBrowserOpen == CS.selectedGroup
    end
    -- Named so the in-place clear below can re-present it: clearing rebuilds
    -- the config under a cursor that never leaves the frame, so OnEnter will
    -- not fire again on its own and the hover would strand a cue with no
    -- tooltip and a stale "Right-click to clear" line.
    local function ShowMirrorHover(self)
        if not mirror.clickMode then return end
        if mirror.clickMode == "texture" and IsBrowsingThisPanel() then return end
        hoverCue:Show()
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        if mirror.clickMode == "icon" then
            GameTooltip:AddLine("Click to choose an icon")
            if mirror.hasIcon then
                GameTooltip:AddLine("Right-click to clear", 0.7, 0.7, 0.7)
            end
        else
            GameTooltip:AddLine("Click to browse textures")
        end
        GameTooltip:Show()
    end
    root:SetScript("OnEnter", ShowMirrorHover)
    root:SetScript("OnLeave", function()
        hoverCue:Hide()
        GameTooltip:Hide()
    end)
    root:SetScript("OnMouseUp", function(self, mouseButton)
        if mirror.clickMode == "icon" then
            local group = CS.selectedGroup
                and CooldownCompanion.db.profile.groups[CS.selectedGroup]
            if not group then return end
            if mouseButton == "RightButton" then
                local settings = CooldownCompanion:GetTriggerPanelIconSettings(group)
                if settings and settings.manualIcon ~= nil then
                    settings.manualIcon = nil
                    GameTooltip:Hide()
                    CooldownCompanion:RefreshAllAuraTextureVisuals()
                    CooldownCompanion:RefreshConfigPanel()
                    if self:IsMouseOver() then
                        ShowMirrorHover(self)
                    else
                        hoverCue:Hide()
                    end
                end
                return
            end
            if mouseButton ~= "LeftButton" then return end
            if ST._OpenTriggerPanelIconPicker then
                ST._OpenTriggerPanelIconPicker(CS.selectedGroup)
            end
            return
        end
        if mirror.clickMode ~= "texture" then return end
        if IsBrowsingThisPanel() then return end
        if ST._OpenStandaloneTexturePicker and CS.selectedGroup then
            ST._OpenStandaloneTexturePicker(CS.selectedGroup)
        end
    end)

    preview.textureMirror = mirror
    return mirror
end

-- Hosts are shared across selections and the trigger preview reserves a bottom
-- band for its strip, so the mirror's extent must be re-anchored every build.
local function ApplyMirrorBand(mirror, previewRoot, bottomReserve)
    local root = mirror.root
    root:ClearAllPoints()
    root:SetPoint("TOPLEFT", previewRoot, "TOPLEFT", 0, 0)
    root:SetPoint("BOTTOMRIGHT", previewRoot, "BOTTOMRIGHT", 0, bottomReserve or 0)
end

local function ApplyTextureMirrorEffectPreview(mirror, panelId, group, settings, boxWidth, boxHeight)
    local indicatorKey, previewFlag = GetStoredTextureIndicatorPreview(panelId)
    if not (indicatorKey and previewFlag and type(settings) == "table"
        and ApplyTextureIndicatorEffects and SetTextureIndicatorBaseVisuals) then
        return
    end
    if not (mirror.primary:IsShown() or mirror.secondary:IsShown()) then
        return
    end

    local geometry = CooldownCompanion:GetTexturePanelRenderGeometry(settings)
    if not geometry then
        return
    end
    local fit = math_min(
        (tonumber(boxWidth) or geometry.boundsWidth) / math_max(geometry.boundsWidth, 1),
        (tonumber(boxHeight) or geometry.boundsHeight) / math_max(geometry.boundsHeight, 1),
        1
    )

    local host = mirror.effectHost
    local visualRoot = host.visualRoot
    visualRoot:ClearAllPoints()
    visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
    visualRoot:SetSize(math_max(1, tonumber(boxWidth) or geometry.boundsWidth),
        math_max(1, tonumber(boxHeight) or geometry.boundsHeight))

    host._activeDisplayType = "texture"
    host._activeTextureSettings = settings
    host._activeTextureGeometry = {
        pieces = geometry.pieces,
        rotationRadians = geometry.rotationRadians,
        boundsWidth = geometry.boundsWidth * fit,
        boundsHeight = geometry.boundsHeight * fit,
    }
    host._indicatorBaseVisualsReady = nil
    SetTextureIndicatorBaseVisuals(host)

    local previewButton = mirror.effectPreviewButton or {}
    mirror.effectPreviewButton = previewButton
    for _, preview in ipairs(TEXTURE_INDICATOR_MIRROR_PREVIEWS) do
        previewButton[preview.flag] = nil
    end
    previewButton.buttonData = group and group.buttons and group.buttons[1] or nil
    previewButton[previewFlag] = true
    ApplyTextureIndicatorEffects(host, previewButton, group, indicatorKey)
end

local function GetActiveTextureMirror(groupId)
    if not (ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()) then
        return nil
    end
    if groupId and groupId ~= CS.selectedGroup then
        return nil
    end

    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.buttonsPreviewHost
    if not (host and host:IsShown() and col3._cdcActiveWideHost == host) then
        return nil
    end

    local preview = host._cdcPanelPreview
    local mirror = preview and preview.textureMirror
    if not (mirror and mirror.root:IsShown()) then
        return nil
    end
    return mirror
end

-- Clear paths can run without rebuilding the pinned preview (for example an
-- entry-tab switch). Stop the config-owned effect immediately so a cleared
-- stored flag can never leave an animation running on the mirror.
function ST._StopTextureIndicatorPreviewMirror(groupId)
    local mirror = GetActiveTextureMirror(groupId)
    if not mirror then
        return false
    end
    StopTextureMirrorEffects(mirror)
    return true
end

-- Color and speed controls update continuously. Reapply the saved effect to
-- the existing config-owned host so its phase continues smoothly instead of
-- rebuilding the mirror and restarting the animation on every drag tick.
function ST._RefreshTextureIndicatorMirrorEffect(groupId)
    local mirror = GetActiveTextureMirror(groupId)
    if not (mirror and mirror.texturePanelId == groupId) then
        return false
    end

    local group = CooldownCompanion.db.profile.groups[groupId]
    if not (group and CooldownCompanion:IsTexturePanelGroup(group)) then
        return false
    end

    ApplyTextureMirrorEffectPreview(
        mirror,
        groupId,
        group,
        mirror.texturePanelSettings,
        mirror.texturePanelBoxWidth,
        mirror.texturePanelBoxHeight
    )
    return true
end

-- Lazy per-type visuals: children of mirror.root, so the stale-mirror hide in
-- _BuildButtonPanelPreview and the readOnly release cover them automatically.
local function EnsureMirrorIconVisual(mirror)
    local visual = mirror.iconVisual
    if visual then
        return visual
    end
    local holder = CreateFrame("Frame", nil, mirror.effectHost.visualRoot)
    holder:SetPoint("CENTER", mirror.effectHost.visualRoot, "CENTER", 0, 0)
    holder:SetSize(STRIP_ICON_SIZE, STRIP_ICON_SIZE)
    visual = {
        holder = holder,
        bg = holder:CreateTexture(nil, "BACKGROUND"),
        icon = holder:CreateTexture(nil, "ARTWORK"),
        borders = {},
    }
    visual.bg:SetAllPoints()
    for index = 1, 4 do
        visual.borders[index] = holder:CreateTexture(nil, "OVERLAY")
    end
    holder.bg = visual.bg
    holder.icon = visual.icon
    holder.borderTextures = visual.borders
    mirror.effectHost.iconFrame = holder
    mirror.iconVisual = visual
    return visual
end

local function EnsureMirrorTextVisual(mirror)
    local visual = mirror.textVisual
    if visual then
        return visual
    end
    local holder = CreateFrame("Frame", nil, mirror.effectHost.visualRoot)
    holder:SetPoint("CENTER", mirror.effectHost.visualRoot, "CENTER", 0, 0)
    holder:SetSize(1, 1)
    visual = {
        holder = holder,
        bg = holder:CreateTexture(nil, "BACKGROUND"),
        text = holder:CreateFontString(nil, "OVERLAY"),
    }
    visual.bg:SetAllPoints()
    visual.text:SetJustifyV("MIDDLE")
    visual.text:SetJustifyH("CENTER")
    visual.text:SetWordWrap(false)
    visual.text:SetMaxLines(0)
    holder.bg = visual.bg
    holder.text = visual.text
    holder.borderTextures = {}
    mirror.effectHost.textFrame = holder
    mirror.textVisual = visual
    return visual
end

-- Config-side twin of the runtime ApplyTriggerIconVisual: the saved icon with
-- its background, tint, and border, scaled to fit the display band.
local function RenderTriggerIconMirror(mirror, settings, boxWidth, boxHeight)
    local visual = EnsureMirrorIconVisual(mirror)
    local holder = visual.holder
    local hasIcon = settings and ST._IsValidIconTexture
        and ST._IsValidIconTexture(settings.manualIcon)
    mirror.hasIcon = hasIcon and true or false
    if not hasIcon then
        holder:Hide()
        mirror.placeholder:SetText("No icon selected")
        mirror.placeholder:Show()
        return
    end
    mirror.placeholder:Hide()

    local width, height = CooldownCompanion.GetTriggerIconDimensions(settings)
    holder:SetScale(1)
    holder:SetSize(width, height)

    local borderSize = settings.borderSize or ST.DEFAULT_BORDER_SIZE
    local borderRenderMode = ST.GetBorderRenderMode(settings)
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(holder, borderSize, borderRenderMode)
    local bgColor = settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderColor = settings.borderColor or { 0, 0, 0, 1 }
    local tintColor = settings.iconTintColor or { 1, 1, 1, 1 }

    visual.bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0,
        bgColor[4] ~= nil and bgColor[4] or 0.5)
    visual.bg:Show()
    for _, border in ipairs(visual.borders) do
        border:SetColorTexture(borderColor[1] or 0, borderColor[2] or 0, borderColor[3] or 0,
            borderColor[4] ~= nil and borderColor[4] or 1)
        border:Show()
    end
    ApplyBorderEdgePositions(visual.borders, holder, borderSize, borderRenderMode)

    local icon = visual.icon
    icon:ClearAllPoints()
    icon:SetPoint("TOPLEFT", borderLayoutSize, -borderLayoutSize)
    icon:SetPoint("BOTTOMRIGHT", -borderLayoutSize, borderLayoutSize)
    icon:SetTexture(settings.manualIcon)
    icon:SetVertexColor(tintColor[1] or 1, tintColor[2] or 1, tintColor[3] or 1,
        tintColor[4] ~= nil and tintColor[4] or 1)
    local applyTexCoord = ST._ApplyIconTexCoord
    if applyTexCoord then
        applyTexCoord(icon, width, height, settings.iconZoom)
    end
    icon:Show()

    holder:SetScale(math_min(1, boxWidth / math_max(1, width), boxHeight / math_max(1, height)))
    holder:Show()
end

-- Config-side twin of the runtime ApplyTriggerTextVisual: the display text at
-- its real metrics (font, alignment, background), scaled to fit the band.
local function RenderTriggerTextMirror(mirror, settings, boxWidth, boxHeight)
    local visual = EnsureMirrorTextVisual(mirror)
    local holder = visual.holder
    local hasText = settings and CooldownCompanion.HasTriggerTextValue(settings)
    if not hasText then
        holder:Hide()
        mirror.placeholder:SetText("No text entered")
        mirror.placeholder:Show()
        return
    end
    mirror.placeholder:Hide()

    local bgColor = settings.textBgColor or { 0, 0, 0, 0 }
    local fontColor = settings.textFontColor or { 1, 1, 1, 1 }
    local text = visual.text

    holder:SetScale(1)
    local frameWidth, frameHeight, insetX, insetY, textWidth, textHeight, lineCount =
        CooldownCompanion.GetTriggerTextDisplayMetrics(text, settings)
    holder:SetSize(frameWidth, frameHeight)

    visual.bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0,
        bgColor[4] ~= nil and bgColor[4] or 0)
    text:SetSize(textWidth or math_max(1, frameWidth - (insetX * 2)),
        textHeight or math_max(1, frameHeight - (insetY * 2)))
    text:SetWordWrap((lineCount or 1) > 1)
    text:SetJustifyV((lineCount or 1) > 1 and "TOP" or "MIDDLE")
    text:ClearAllPoints()
    text:SetPoint("TOPLEFT", holder, "TOPLEFT", insetX, -insetY)
    text:SetPoint("BOTTOMRIGHT", holder, "BOTTOMRIGHT", -insetX, insetY)
    text:SetJustifyH(settings.textAlignment or "CENTER")
    text:SetTextColor(fontColor[1] or 1, fontColor[2] or 1, fontColor[3] or 1,
        fontColor[4] ~= nil and fontColor[4] or 1)
    text:Show()

    holder:SetScale(math_min(1, boxWidth / math_max(1, frameWidth), boxHeight / math_max(1, frameHeight)))
    holder:Show()
end

local function ApplyTriggerMirrorEffectPreview(mirror, group, panelId, displayType, settings, boxWidth, boxHeight)
    local host = mirror and mirror.effectHost
    if not host then return end

    local active = CooldownCompanion:IsTriggerPanelEffectsPreviewActive(panelId)
    if not active then
        StopTextureMirrorEffects(mirror)
        return
    end

    host._activeDisplayType = displayType
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._triggerIconBaseColor = nil
    host._triggerTextBaseColor = nil
    host._indicatorBaseVisualsReady = nil

    if displayType == "texture" then
        local geometry = settings and CooldownCompanion:GetTexturePanelRenderGeometry(settings)
        if not geometry or not (mirror.primary:IsShown() or mirror.secondary:IsShown()) then
            StopTextureMirrorEffects(mirror)
            return
        end
        local fit = math_min(
            (tonumber(boxWidth) or geometry.boundsWidth) / math_max(geometry.boundsWidth, 1),
            (tonumber(boxHeight) or geometry.boundsHeight) / math_max(geometry.boundsHeight, 1),
            1
        )
        host._activeTextureSettings = settings
        host._activeTextureGeometry = {
            pieces = geometry.pieces,
            rotationRadians = geometry.rotationRadians,
            boundsWidth = geometry.boundsWidth * fit,
            boundsHeight = geometry.boundsHeight * fit,
        }
    elseif displayType == "icon" then
        if not (mirror.iconVisual and mirror.iconVisual.holder:IsShown()) then
            StopTextureMirrorEffects(mirror)
            return
        end
        local color = settings and settings.iconTintColor or { 1, 1, 1, 1 }
        host._triggerIconBaseColor = { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
    elseif displayType == "text" then
        if not (mirror.textVisual and mirror.textVisual.holder:IsShown()) then
            StopTextureMirrorEffects(mirror)
            return
        end
        local color = settings and settings.textFontColor or { 1, 1, 1, 1 }
        host._triggerTextBaseColor = { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
    end

    local previewGroup = {
        locked = true,
        triggerSettings = group and group.triggerSettings,
    }
    CooldownCompanion:ApplyTriggerPanelEffects(host, mirror.effectPreviewButton or {}, previewGroup, true)
end

-- Paint a trigger panel's display visual into the mirror: the config-side twin
-- of the runtime RenderStandaloneDisplay dispatch. Split out of the builder so
-- a settings change can repaint just this, leaving the selection strip's slots
-- and their wiring alone.
local function RenderTriggerDisplayVisual(mirror, group, panelId, boxWidth, boxHeight, readOnly)
    local displayType = CooldownCompanion.GetStandaloneDisplayType(group)
    local settings
    -- Explicit branches: an and/or chain can't yield nil for the text case.
    if displayType == "icon" then
        mirror.clickMode = "icon"
    elseif displayType == "text" then
        mirror.clickMode = nil
    else
        mirror.clickMode = "texture"
    end

    mirror.primary:Hide()
    mirror.secondary:Hide()
    if mirror.iconVisual then mirror.iconVisual.holder:Hide() end
    if mirror.textVisual then mirror.textVisual.holder:Hide() end

    if displayType == "icon" then
        settings = CooldownCompanion:GetTriggerPanelIconSettings(group)
        RenderTriggerIconMirror(mirror, settings, boxWidth, boxHeight)
    elseif displayType == "text" then
        settings = CooldownCompanion:GetTriggerPanelTextSettings(group)
        RenderTriggerTextMirror(mirror, settings, boxWidth, boxHeight)
    else
        mirror.placeholder:SetText("No texture selected")
        -- Same staged-selection precedence as BuildTextureMirror: picker
        -- selection first, then the config-only continuous-edit copy, then the
        -- saved trigger texture.
        local staged = CS.textureMirrorStage
        local configStaged = CS.textureConfigPreviewStage
        settings = readOnly and CooldownCompanion:GetTriggerPanelSignalSettings(group)
            or (staged and staged.groupId == panelId and staged.selection)
            or (configStaged and configStaged.groupId == panelId and configStaged.settings)
            or CooldownCompanion:GetTriggerPanelSignalSettings(group)
        local render = ST._UpdateTexturePanelPreview
        if render then
            render(mirror, settings, boxWidth, boxHeight)
        end
    end

    if not readOnly then
        ApplyTriggerMirrorEffectPreview(mirror, group, panelId, displayType, settings, boxWidth, boxHeight)
    end
end

local function BuildTextureMirror(preview, host, panelId, group, readOnly)
    -- No animated slots on a texture panel; mirror BuildSelectionStrip's setup.
    StopConditionalTicker(preview)

    local mirror = EnsureTextureMirror(preview)
    mirror.root:Show()
    ApplyMirrorBand(mirror, preview.root, 0)

    -- The mirror is shared with the trigger preview on this host, so restore
    -- the texture-panel presentation before rendering.
    mirror.clickMode = "texture"
    mirror.placeholder:SetText("No texture selected")
    if mirror.iconVisual then mirror.iconVisual.holder:Hide() end
    if mirror.textVisual then mirror.textVisual.holder:Hide() end

    -- Only make the rendered texture clickable when the panel has its entry.
    -- An empty texture panel still offers drop-to-add on the preview host, and
    -- an interactive mirror would swallow the drop.
    local hasEntry = group and group.buttons and group.buttons[1] ~= nil
    mirror.root:EnableMouse(not readOnly and hasEntry and true or false)
    if not hasEntry then
        mirror.hoverCue:Hide()
    end

    -- Focused texture mirrors retain the established measurement guard;
    -- overview mirrors use the tile's actual smaller fit box.
    local boxWidth, boxHeight = GetHostFitBox(host, readOnly)

    -- Prefer the picker's staged selection for the panel being edited, else the
    -- saved texture. Both are NormalizeAuraTextureSettings tables, so the shared
    -- renderer needs no per-source handling; nil means the panel has no texture.
    local staged = CS.textureMirrorStage
    local configStaged = CS.textureConfigPreviewStage
    local settings = readOnly and CooldownCompanion:GetTexturePanelSettings(group)
        or (staged and staged.groupId == panelId and staged.selection)
        or (configStaged and configStaged.groupId == panelId and configStaged.settings)
        or CooldownCompanion:GetTexturePanelSettings(group)

    mirror.texturePanelId = panelId
    mirror.texturePanelSettings = settings
    mirror.texturePanelBoxWidth = boxWidth
    mirror.texturePanelBoxHeight = boxHeight

    local render = ST._UpdateTexturePanelPreview
    if render then
        render(mirror, settings, boxWidth, boxHeight)
    end
    if not readOnly then
        ApplyTextureMirrorEffectPreview(mirror, panelId, group, settings, boxWidth, boxHeight)
    end

    FinalizePreviewState(preview)
end

-- Trigger-panel Live Preview: the panel's actual display visual (texture,
-- icon, or text) renders large on top, with the entry selection strip in a
-- band along the bottom keeping all of its picker behavior. Unlike texture
-- panels, the mirror stays clickable with zero entries: trigger appearance is
-- configurable without entries and the bottom tab has no picker buttons, so
-- the preview click is the only path into the pickers. Drop-to-add is safe
-- either way - the payload drop overlay sits above the mirror whenever a
-- spell or item is on the cursor. Read-only Group Overview tiles do not
-- stack; see the branch below.
local function BuildTriggerPanelPreview(preview, host, panelId, group, readOnly)
    StopConditionalTicker(preview)

    local mirror = EnsureTextureMirror(preview)
    local boxWidth, boxHeight = GetHostFitBox(host, readOnly)

    -- Group Overview tiles stand on a standardized row height with only ~36px
    -- of fit box left, and the strip is an editing affordance a tile cannot be
    -- clicked in anyway. A tile therefore shows the panel's real display
    -- alone, the way a texture panel's tile does, rather than splitting that
    -- band two ways and rendering both halves too small to read. With no
    -- display configured yet the entry strip is the only informative thing
    -- left, so it stands in.
    if readOnly then
        preview.triggerStripReserve = 0
        if GetTriggerDisplayNaturalSize(group) <= 0 then
            mirror.root:Hide()
            return BuildSelectionStrip(preview, host, panelId, group, readOnly)
        end
        mirror.root:Show()
        mirror.root:EnableMouse(false)
        mirror.hoverCue:Hide()
        ApplyMirrorBand(mirror, preview.root, 0)
        RenderTriggerDisplayVisual(mirror, group, panelId, boxWidth, boxHeight, true)
        FinalizePreviewState(preview)
        return
    end

    mirror.root:Show()

    local count = #(group.buttons or {})
    local reserve, stripLayout
    if count > 0 then
        local stripW, stripH = GetStripNaturalSize(count)
        local stripScale = math_min(1, boxWidth / math_max(1, stripW),
            (boxHeight * TRIGGER_PREVIEW_STRIP_MAX_SHARE) / math_max(1, stripH))
        reserve = (stripH * stripScale) + PANEL_PREVIEW_PADDING
        stripLayout = { anchorPoint = "BOTTOM", scaleOverride = stripScale }
    else
        reserve = TRIGGER_PREVIEW_EMPTY_BAND
    end

    ApplyMirrorBand(mirror, preview.root, reserve)
    -- Recorded for ST._RefreshTriggerDisplayVisual: the band depends only on
    -- the entry count and the host, so a display setting cannot move it.
    preview.triggerStripReserve = reserve

    RenderTriggerDisplayVisual(mirror, group, panelId, boxWidth,
        math_max(1, boxHeight - reserve), false)
    mirror.root:EnableMouse(mirror.clickMode ~= nil)
    if not mirror.clickMode then
        mirror.hoverCue:Hide()
    end

    if count > 0 then
        return BuildSelectionStrip(preview, host, panelId, group, readOnly, stripLayout)
    end

    SetPreviewMessage(preview,
        "This panel has no entries yet. Add spells or items in the Panels column.")
    -- Tuck the message into the reserved bottom band so it never overlaps the
    -- display visual; SetPreviewMessage restores the default anchors for the
    -- next build.
    local label = preview.messageLabel
    label:ClearAllPoints()
    label:SetPoint("BOTTOMLEFT", preview.root, "BOTTOMLEFT", 18, PANEL_PREVIEW_PADDING)
    label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, PANEL_PREVIEW_PADDING)
    FinalizePreviewState(preview)
end

-- Repaint ONLY a trigger panel's display visual in the pinned mirror, leaving
-- the selection strip's slots and their wiring untouched. The appearance tabs
-- call this on every tick of a slider drag, where a full preview rebuild would
-- re-run per-entry usability and load-condition queries and re-wire every
-- strip slot each frame. Returns false when there is no live trigger mirror to
-- repaint so callers can fall back to the full rebuild.
function ST._RefreshTriggerDisplayVisual(groupId)
    if not (ST._IsButtonsWideViewActive and ST._IsButtonsWideViewActive()) then return false end
    if not groupId or groupId ~= CS.selectedGroup then return false end
    local col3 = CS.configFrame and CS.configFrame.col3
    local host = col3 and col3.buttonsPreviewHost
    if not (host and host:IsShown() and col3._cdcActiveWideHost == host) then return false end
    local preview = host._cdcPanelPreview
    local mirror = preview and preview.textureMirror
    if not (mirror and mirror.root:IsShown()) then return false end
    local group = CooldownCompanion.db.profile.groups[groupId]
    if not (group and CooldownCompanion:IsTriggerPanelGroup(group)) then return false end

    local boxWidth, boxHeight = GetHostFitBox(host, false)
    RenderTriggerDisplayVisual(mirror, group, groupId, boxWidth,
        math_max(1, boxHeight - (preview.triggerStripReserve or 0)), false)
    mirror.root:EnableMouse(mirror.clickMode ~= nil)
    if not mirror.clickMode then
        mirror.hoverCue:Hide()
    end
    return true
end

function ST._StopTriggerPanelEffectsPreviewMirror(groupId)
    local mirror = GetActiveTextureMirror(groupId)
    if not mirror then return false end
    StopTextureMirrorEffects(mirror)
    return true
end

function ST._BuildButtonPanelPreview(host, panelId, options)
    options = type(options) == "table" and options or nil
    local readOnly = options and options.readOnly == true
    -- Rebuilding pulls the slot frames out from under an in-flight drag
    if not readOnly
        and CS.dragState and CS.dragState.kind == "layout-slot" and CancelDrag then
        CancelDrag()
    end

    local preview = EnsurePreviewState(host)
    preview.panelId = panelId
    preview.readOnly = readOnly
    -- Copy-customization banner surface; nil means the preview's own root.
    preview.copyBannerHost = options and options.bannerHost or nil
    if not readOnly and panelId == CS.selectedGroup then
        -- A full build reconciles the cleared stores by construction; do not
        -- make the next selection-only pass repeat that work.
        CS.panelPreviewVisualsNeedReconcile = nil
    end
    preview.layoutDrag = nil
    StopTextureMirrorEffects(preview.textureMirror)
    -- Fresh static layout: discard any tweens or ghost the canceled drag
    -- queued so they can't fight the rebuilt slot positions
    preview.tweens = preview.tweens or {}
    wipe(preview.tweens)
    ClearPreviewGhost(preview)
    preview.root:SetScript("OnUpdate", nil)
    if preview.gapFrame then
        preview.gapFrame:Hide()
    end
    if preview.textHeader then
        preview.textHeader:Hide()
    end
    -- Hide the texture mirror up front so switching from a texture panel to any
    -- other type never leaves a stale texture drawn over the new mirror; only
    -- BuildTextureMirror re-shows it.
    if preview.textureMirror then
        preview.textureMirror.root:Hide()
    end
    ResetPreviewState(preview)
    HidePreviewMessage(preview)
    preview.content:Hide()
    -- Stop the animation ticker up front: the early exits below (no group,
    -- empty panel) render no animated slots, and the main path re-arms it
    -- only when a slot actually animates. The stored preview state the
    -- ticker reads lives outside the ticker, so a stop/re-arm is seamless.
    StopConditionalTicker(preview)

    -- options.groupData renders a detached panel table (an import payload's
    -- incoming panel) instead of a saved panel. Read-only paths never touch
    -- panelId after this resolution, so a nil id is safe with data supplied.
    local group = options and type(options.groupData) == "table" and options.groupData or nil
    if not group then
        group = panelId and CooldownCompanion.db.profile.groups[panelId]
    end
    if not group then
        SetPreviewMessage(preview, "Select a panel to preview it here.")
        FinalizePreviewState(preview)
        return
    end

    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    if not isBarMode and not isTextMode and not IsIconModePanel(group) then
        -- Texture panels render their real texture; trigger panels stack
        -- their display visual above the strip; rotation-assistant panels
        -- keep the entry-icon selection strip alone.
        if CooldownCompanion:IsTexturePanelGroup(group) then
            return BuildTextureMirror(preview, host, panelId, group, readOnly)
        end
        if CooldownCompanion:IsTriggerPanelGroup(group) then
            return BuildTriggerPanelPreview(preview, host, panelId, group, readOnly)
        end
        return BuildSelectionStrip(preview, host, panelId, group, readOnly)
    end

    local buttons = group.buttons or {}
    local count = #buttons
    if count == 0 then
        SetPreviewMessage(preview, readOnly and "Empty Panel"
            or "This panel has no entries yet. Add spells or items in the Panels column.")
        FinalizePreviewState(preview)
        return
    end

    -- Session view filter (the preview host's quick toggle): drop entries the
    -- warn badge would mark unavailable and reflow the rest, except for any
    -- selected entries the player is still editing. Dense ordinals place the
    -- cells; every per-entry surface keeps its group.buttons index.
    -- Never on Bar panels: their mirror is a saved-design projection that
    -- deliberately keeps live usability out (CollectBarEntryStatus), so there
    -- is no warn signal there for the toggle to hide. Read-only mirrors stay
    -- unfiltered except the unified cast duplicate, which opts in so both
    -- copies of the anchor panel show the same filtered set.
    local visibleIndices
    if (not readOnly or (options and options.applySessionFilter == true))
        and not isBarMode
        and CS.panelPreviewUnavailableHidden
        and not CS.otherClassLibraryActive then
        local kept = {}
        for index, buttonData in ipairs(buttons) do
            if buttonData.enabled == false
                or CooldownCompanion:IsButtonUsable(buttonData, group)
                or IsEntrySelected(index) then
                kept[#kept + 1] = index
            end
        end
        if #kept < count then
            visibleIndices = kept
            count = #kept
        end
    end
    if count == 0 then
        SetPreviewMessage(preview,
            "Every entry here is unavailable and hidden by the preview toggle.")
        FinalizePreviewState(preview)
        return
    end

    local geo = GetPanelGeometry(group, isBarMode, isTextMode, visibleIndices)
    local w, h = geo.entryWidth, geo.entryHeight
    local spacing = geo.spacing
    local perRow = math_max(1, geo.buttonsPerRow)
    local style = group.style or {}
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)
    -- Same gate the live layout applies: aura panels (Blizzard's flow
    -- container) fold centered growth to TOPLEFT.
    local centeredEdge = not CooldownCompanion:IsAuraPanel(group)
        and ST.GetCenteredGrowthEdge(style.growthOrigin, geo.orientation) or nil
    if centeredEdge then
        growthAnchor = centeredEdge
    end

    -- Text-mode group header claims a row of space above (or below, for
    -- bottom growth) the entries, exactly like the live layout.
    local headerHeight = 0
    if isTextMode and style.showTextGroupHeader == true then
        headerHeight = (style.textHeaderFontSize or style.textFontSize or 12) + 4
    end

    local cols, rows
    if geo.orientation == "horizontal" then
        cols = math_min(count, perRow)
        rows = math_ceil(count / perRow)
    else
        rows = math_min(count, perRow)
        cols = math_ceil(count / perRow)
    end
    local contentWidth = (cols - 1) * (w + spacing) + w
    local contentHeight = (rows - 1) * (h + spacing) + h + headerHeight

    -- Scale is needed while styling (badges counter-scale against it), so
    -- compute it up front from the grid extents.
    local scale = GetHostFitScale(host, contentWidth, contentHeight, readOnly)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()
    UpdateTextGroupHeader(preview, group, style, headerHeight)

    local poolName = isBarMode and "barSlots" or (isTextMode and "textSlots" or "iconSlots")
    local styleFn = isBarMode and StyleBarEntry or (isTextMode and StyleTextEntry or StyleIconEntry)

    local layoutDrag = readOnly and { slots = {} } or CreatePreviewLayoutDrag(preview, panelId)
    layoutDrag.iconResolver = isBarMode and GetConfigOnlyBarPreviewIcon or GetLayoutPreviewIcon
    layoutDrag.count = count
    layoutDrag.slotW, layoutDrag.slotH = w, h
    layoutDrag.scale = scale
    layoutDrag.anchor = growthAnchor
    if centeredEdge then
        -- Mirror of the live centered branch in ApplyActiveButtonLayout:
        -- offsets hang off the frame's edge midpoint, so the trailing
        -- partial line centers itself. cellXY doubles as the drag-reorder
        -- hit model, so centering must live here, not after.
        local lineCount = math_ceil(count / perRow)
        layoutDrag.cellXY = function(d)
            local line = math_floor((d - 1) / perRow)
            local indexInLine = (d - 1) % perRow
            local itemsInLine = (line == lineCount - 1) and (count - line * perRow) or perRow
            if geo.orientation == "horizontal" then
                local edgeYMul = centeredEdge == "TOP" and -1 or 1
                return (indexInLine - (itemsInLine - 1) / 2) * (w + spacing),
                    edgeYMul * (line * (h + spacing) + headerHeight)
            end
            local edgeXMul = centeredEdge == "LEFT" and 1 or -1
            return edgeXMul * line * (w + spacing),
                ((itemsInLine - 1) / 2 - indexInLine) * (h + spacing) - headerHeight / 2
        end
    else
        layoutDrag.cellXY = function(d)
            local row, col
            if geo.orientation == "horizontal" then
                row = math_floor((d - 1) / perRow)
                col = (d - 1) % perRow
            else
                col = math_floor((d - 1) / perRow)
                row = (d - 1) % perRow
            end
            return xMul * col * (w + spacing), yMul * (row * (h + spacing) + headerHeight)
        end
    end
    preview.layoutDrag = layoutDrag
    -- Reorder maps dense cells to group.buttons indices, so it stays off
    -- while the unavailable filter has punched holes in that mapping.
    local dragModel = (not readOnly and count >= 2 and not visibleIndices)
        and layoutDrag or nil

    for ordinal = 1, count do
        local index = visibleIndices and visibleIndices[ordinal] or ordinal
        local buttonData = buttons[index]
        local slot = AcquireSlot(preview, content, poolName)
        if isTextMode then
            -- Cell placement stays on the uniform pitch below; only the slot's
            -- own footprint is per-entry, like the live text button.
            slot:SetSize(GetTextSlotSize(group, buttonData, w, h))
        else
            slot:SetSize(w, h)
        end

        local cx, cy = layoutDrag.cellXY(ordinal)
        ApplyPreviewSlotGeometry(preview, slot, growthAnchor, cx, cy)

        local effectiveStyle
        local barPreviewState
        if isBarMode then
            effectiveStyle = group.style or {}
            if CooldownCompanion.GetEffectiveStyle then
                effectiveStyle = CooldownCompanion:GetEffectiveStyle(effectiveStyle, buttonData)
                    or effectiveStyle
            end
            if not readOnly then
                barPreviewState = GetStoredBarPreviewState(panelId, index)
            end
            ResetBarSlotConditionalVisuals(slot)
        end
        styleFn(slot, buttonData, group, effectiveStyle)
        if not readOnly and not isTextMode then
            ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, isBarMode,
                effectiveStyle, barPreviewState)
        elseif not isTextMode then
            ClearSlotEffectPreviews(slot)
        end
        local status = not readOnly and (isBarMode and CollectBarEntryStatus(buttonData, group)
            or CollectEntryStatus(buttonData, group)) or nil
        local barVisibility
        if isBarMode and not readOnly then
            barVisibility = ResolveBarPreviewVisibility(buttonData, group, barPreviewState)
        end
        if slot.icon and not readOnly then
            slot.icon:SetDesaturated(not status.usable)
        elseif slot.icon then
            slot.icon:SetDesaturated(false)
            -- No conditional pass runs on a read-only mirror, so nothing else
            -- would write the configured icon tint (same resolution the
            -- focused mirror uses, base tint only - saved settings, no state).
            local tintStyle = effectiveStyle or group.style or {}
            if not effectiveStyle and CooldownCompanion.GetEffectiveStyle then
                tintStyle = CooldownCompanion:GetEffectiveStyle(tintStyle, buttonData) or tintStyle
            end
            local baseTint = tintStyle.iconTintColor
            slot.icon:SetVertexColor(baseTint and baseTint[1] or 1,
                baseTint and baseTint[2] or 1,
                baseTint and baseTint[3] or 1,
                baseTint and baseTint[4] or 1)
        end
        if readOnly and isTextMode then
            ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index, true)
            slot._cdcCondAnim = nil
        elseif readOnly then
            ResetSlotConditionalVisuals(slot)
        elseif isBarMode then
            ApplyBarSlotConditionalPreview(slot, buttonData, group, panelId, index,
                effectiveStyle, barPreviewState)
        elseif isTextMode then
            ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index)
        else
            ApplySlotConditionalPreview(slot, buttonData, group, panelId, index)
        end
        if not readOnly and not isBarMode and status.disabled then
            slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
        end
        slot._cdcBaseAlpha = readOnly and 1 or (isBarMode and 1
            or (status.disabled and PANEL_PREVIEW_DISABLED_ALPHA or 1))
        if not readOnly and isBarMode then
            ApplyBarSlotPreviewVisibility(slot, barVisibility, scale, IsEntrySelected(index))
        end
        if readOnly then
            ApplySlotBadges(slot, {}, scale, true)
            DisableReadOnlySlotInteraction(slot)
        else
            ApplySlotBadges(slot, status, scale,
                isBarMode and barVisibility.exactPreview == true)
            ApplySelectionVisuals(slot, index,
                (isBarMode and barVisibility.exactPreview == true)
                    or IsGlowPreviewActiveOnEntry(panelId, index))
            CopyMode.ApplyTargetVisuals(slot, panelId, buttonData)
            -- Pooled slots: written every build so a slot leaving a filtered
            -- build does not keep advertising the pause.
            slot._cdcReorderPausedByFilter = visibleIndices and true or nil
            WireEntryInteraction(slot, panelId, index, buttonData, status, dragModel, barVisibility)
        end
        layoutDrag.slots[index] = slot
    end

    -- Tick only while at least one slot is animating a conditional preview
    -- (pairs, not 1..count: the unavailable filter keys slots sparsely).
    local anyAnimated = false
    for _, s in pairs(layoutDrag.slots) do
        if s._cdcCondAnim then
            anyAnimated = true
            break
        end
    end
    if not readOnly and anyAnimated then
        EnsureConditionalTicker(preview)
    else
        StopConditionalTicker(preview)
    end

    content:SetScale(scale)
    content:ClearAllPoints()
    content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)

    FinalizePreviewState(preview)
end

-- Entry selection normally does not change saved panel geometry or mirrored
-- visuals. The unavailable filter is the exception: selection determines
-- whether an unavailable entry remains in the visible subset, so that path
-- falls back to a full mirror rebuild. Otherwise update the existing selection
-- rings (and bar ghost exposure) in place.
function ST._RefreshButtonPanelPreviewSelection(host, panelId)
    local preview = host and host._cdcPanelPreview
    if not (preview and preview.panelId == panelId and preview.readOnly ~= true) then
        return false
    end

    local reconcileVisuals = CS.panelPreviewVisualsNeedReconcile == true
    CS.panelPreviewVisualsNeedReconcile = nil

    local group = panelId and CooldownCompanion.db.profile.groups[panelId]
    if not group then
        return false
    end

    if CS.panelPreviewUnavailableHidden
        and not CS.otherClassLibraryActive
        and ST._PanelPreviewUnavailableEntryState
        and ST._PanelPreviewUnavailableEntryState(group) == true then
        return false
    end

    local slots = preview.layoutDrag and preview.layoutDrag.slots
    if CooldownCompanion:IsTexturePanelGroup(group) then
        return true
    end
    if not slots then
        return false
    end

    if CooldownCompanion:IsRotationAssistantGroup(group) then
        local slot = slots[1]
        if not slot then
            return false
        end
        local buttonData = slot._cdcPreviewButtonData
        if buttonData and reconcileVisuals then
            local status = CollectEntryStatus(buttonData, group)
            if slot.icon then
                slot.icon:SetDesaturated(not status.usable)
            end
            ApplySlotEffectPreviews(slot, buttonData, group, panelId, 1, false)
            ApplySlotConditionalPreview(slot, buttonData, group, panelId, 1)
            if slot._cdcCondAnim then
                EnsureConditionalTicker(preview)
            end
        end
        if CS.selectedRotationAssistantEntry == true
            and not IsGlowPreviewActiveOnEntry(panelId, 1) then
            slot.selectedHighlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
            ST.ApplyBorderTextures(slot.selectedHighlight.ringTextures, slot.selectedHighlight,
                PANEL_PREVIEW_RING_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
            slot.selectedHighlight:Show()
        else
            slot.selectedHighlight:Hide()
        end
        return true
    end

    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    local isGridPanel = isBarMode or isTextMode or IsIconModePanel(group)
    if reconcileVisuals then
        StopConditionalTicker(preview)
    end
    local anyAnimated = false
    for index, slot in pairs(slots) do
        local buttonData = group.buttons and group.buttons[index]
        if reconcileVisuals and isGridPanel and buttonData then
            local status = isBarMode and CollectBarEntryStatus(buttonData, group)
                or CollectEntryStatus(buttonData, group)
            if slot.icon then
                slot.icon:SetDesaturated(not status.usable)
            end
            if isBarMode then
                local effectiveStyle = group.style or {}
                if CooldownCompanion.GetEffectiveStyle then
                    effectiveStyle = CooldownCompanion:GetEffectiveStyle(effectiveStyle, buttonData)
                        or effectiveStyle
                end
                local barPreviewState = GetStoredBarPreviewState(panelId, index)
                ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, true,
                    effectiveStyle, barPreviewState)
                ApplyBarSlotConditionalPreview(slot, buttonData, group, panelId, index,
                    effectiveStyle, barPreviewState)
            elseif isTextMode then
                ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index)
            else
                ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, false)
                ApplySlotConditionalPreview(slot, buttonData, group, panelId, index)
            end
        end
        anyAnimated = anyAnimated or slot._cdcCondAnim ~= nil
        if slot._cdcBarPreviewVisibility then
            RefreshBarSlotWorkspacePresentation(slot)
        end
        local exactBarPreview = slot._cdcBarPreviewVisibility
            and slot._cdcBarPreviewVisibility.exactPreview == true
        ApplySelectionVisuals(slot, index,
            exactBarPreview or IsGlowPreviewActiveOnEntry(panelId, index))
        CopyMode.ApplyTargetVisuals(slot, panelId, buttonData)
    end
    if reconcileVisuals and anyAnimated then
        EnsureConditionalTicker(preview)
    end
    return true
end

-- Saved-design mirror used by Group Panel Overview tiles. The overview owns
-- the only mouse surface; this renderer supplies visuals and natural geometry.
function ST._GetReadOnlyPanelPreviewNaturalSize(panelId)
    local group = panelId and CooldownCompanion.db.profile.groups[panelId]
    return GetPanelPreviewNaturalSize(group)
end

function ST._BuildReadOnlyPanelPreview(host, panelId)
    if not host then return nil, 220, 90 end
    local naturalWidth, naturalHeight =
        ST._GetReadOnlyPanelPreviewNaturalSize(panelId)
    ST._BuildButtonPanelPreview(host, panelId, { readOnly = true })
    local preview = host._cdcPanelPreview
    return preview and preview.root or nil, naturalWidth, naturalHeight
end

-- Detached-data variants for import mode's incoming-panel tiles: the panel
-- exists only inside a decoded (rehydrated) payload, not in the profile.
function ST._GetReadOnlyPanelPreviewNaturalSizeFromData(groupData)
    return GetPanelPreviewNaturalSize(groupData)
end

function ST._BuildReadOnlyPanelPreviewFromData(host, groupData)
    if not host then return nil, 220, 90 end
    local naturalWidth, naturalHeight = GetPanelPreviewNaturalSize(groupData)
    ST._BuildButtonPanelPreview(host, nil, { readOnly = true, groupData = groupData })
    local preview = host._cdcPanelPreview
    return preview and preview.root or nil, naturalWidth, naturalHeight
end

function ST._ReleaseReadOnlyPanelPreview(host)
    local preview = host and host._cdcPanelPreview
    if not preview then return end
    StopConditionalTicker(preview)
    StopTextureMirrorEffects(preview.textureMirror)
    for poolName, pool in pairs(preview.pools) do
        local used = preview.used[poolName] or 0
        for index = 1, used do
            local slot = pool[index]
            if slot then
                DisableReadOnlySlotInteraction(slot)
                slot:Hide()
                slot:ClearAllPoints()
            end
        end
        preview.used[poolName] = 0
    end
    if preview.textureMirror then
        preview.textureMirror.root:EnableMouse(false)
        preview.textureMirror.root:Hide()
    end
    if preview.textHeader then preview.textHeader:Hide() end
    preview.content:Hide()
    preview.root:Hide()
end

ST._CollectEntryStatus = CollectEntryStatus
ST._EntryStatusBadges = ENTRY_STATUS_BADGES

-- Quick-toggle support for the buttons-view preview host: nil when this
-- panel type renders no entry grid the filter touches; otherwise whether any
-- entry currently wears the "Spell/item unavailable" warn signal the
-- unavailable filter hides (same computation as CollectEntryStatus's warn).
-- Bar panels are nil on purpose: their mirror is a saved-design projection
-- the filter never applies to, so the badge must not offer it there.
function ST._PanelPreviewUnavailableEntryState(group)
    if not group then return nil end
    if group.displayMode ~= "text" and not IsIconModePanel(group) then
        return nil
    end
    for _, buttonData in ipairs(group.buttons or {}) do
        if buttonData.enabled ~= false
            and not CooldownCompanion:IsButtonUsable(buttonData, group) then
            return true
        end
    end
    return false
end

function ST._ReleaseButtonPanelPreview(host)
    local preview = host and host._cdcPanelPreview
    if preview then
        StopConditionalTicker(preview)
        StopTextureMirrorEffects(preview.textureMirror)
        local barPool = preview.pools.barSlots or {}
        for index = 1, (preview.used.barSlots or 0) do
            local slot = barPool[index]
            if slot then ResetBarSlotWorkspaceState(slot) end
        end
        -- The banner can live on an external host (unified composition), so
        -- hiding the root does not necessarily take it along.
        if preview.copyBanner then
            preview.copyBanner:Hide()
        end
        preview.root:Hide()
    end
end
