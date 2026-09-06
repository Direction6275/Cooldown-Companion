--[[
    CooldownCompanion - ButtonPanelPreviewShared
    Saved-design state, slot pools, visibility metadata, preview motion, and geometry.

    Part of the ButtonPanelPreview family; see its ordered block in the addon TOC.
    Private helpers are shared through ST._ButtonPanelPreview.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local math_floor = math.floor
local math_min = math.min
local math_max = math.max
local math_ceil = math.ceil
local GetLayoutPreviewIcon = ST._GetLayoutPreviewIcon
local GetTextEntryMetrics = ST._GetTextEntryMetrics
local GetStoredConditionalPreviewState = ST._GetStoredConditionalPreviewState
local IsStoredPreviewFlagActive = ST._IsStoredPreviewFlagActive

local PP = {}
ST._ButtonPanelPreview = PP

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

-- Each rule names the Show & Hide Rules row and the value it holds, the way
-- the entry's own Visibility tab states it: naming the wrong choice sends the
-- owner looking for a switch they never turned on.
local function StateRule(row, buttonData, dimKey)
    return row .. ": " .. (buttonData[dimKey] and "Dim" or "Hide")
end

local BAR_PREVIEW_REASON_DEFS = {
    { key = "disabled", label = "Disabled", rule = "Enabled is off" },
    { key = "aura-inactive", label = "Aura inactive",
        rule = function(buttonData)
            return StateRule("While Aura Inactive", buttonData, "auraShellDim")
        end,
        fallback = "auraShellDim" },
    -- The cooldown labels are the dropdown's own (ST._COOLDOWN_VISIBILITY,
    -- Helpers.lua), so the preview can never name a choice the tab does not.
    { key = "on-cooldown", label = "On cooldown",
        rule = function(buttonData)
            local labels = ST._COOLDOWN_VISIBILITY.labels
            return "Cooldown Visibility: "
                .. (buttonData.useBaselineAlphaFallbackOnCooldown and labels.dim_cooldown or labels.hide_cooldown)
        end,
        fallback = "useBaselineAlphaFallbackOnCooldown" },
    { key = "not-on-cooldown", label = "Not on cooldown",
        rule = function(buttonData)
            local labels = ST._COOLDOWN_VISIBILITY.labels
            -- Same gate the tab's reader and the runtime use: the zero-only
            -- refinement only exists on a spell that actually uses charge
            -- behavior (an aura-added spell does not, whatever hasCharges says).
            if buttonData.showOnlyAtZeroCharges and buttonData.type == "spell"
                and buttonData.hasCharges == true
                and ST._UsesConfigOnlyBarChargeBehavior(buttonData) then
                return "Cooldown Visibility: " .. labels.zero_only
            end
            return "Cooldown Visibility: "
                .. (buttonData.useBaselineAlphaFallbackNotOnCooldown and labels.dim_ready or labels.hide_ready)
        end,
        fallback = "useBaselineAlphaFallbackNotOnCooldown" },
    { key = "no-proc", label = "No proc",
        rule = function(buttonData)
            return StateRule("While No Proc", buttonData, "useBaselineAlphaFallbackNoProc")
        end,
        fallback = "useBaselineAlphaFallbackNoProc" },
    { key = "zero-charges", label = "Zero charges",
        rule = function(buttonData)
            return StateRule("At Zero Charges", buttonData, "useBaselineAlphaFallbackZeroCharges")
        end,
        fallback = "useBaselineAlphaFallbackZeroCharges" },
    -- Items with use-count fallbacks title this row "With No Uses Available"
    -- in the config (ButtonConditions), so the tooltip must name the row the
    -- way that entry's own tab does.
    { key = "zero-stacks", label = "Zero stacks",
        rule = function(buttonData)
            local row = type(CooldownCompanion.HasItemFallbacks) == "function"
                and CooldownCompanion.HasItemFallbacks(buttonData) == true
                and "With No Uses Available"
                or "At Zero Stacks"
            return StateRule(row, buttonData, "useBaselineAlphaFallbackZeroStacks")
        end,
        fallback = "useBaselineAlphaFallbackZeroStacks" },
    { key = "not-equipped", label = "Not equipped",
        rule = function(buttonData)
            return StateRule("While Not Equipped", buttonData, "useBaselineAlphaFallbackNotEquipped")
        end,
        fallback = "useBaselineAlphaFallbackNotEquipped" },
    { key = "unusable", label = "Unusable",
        rule = function(buttonData)
            return StateRule("While Unusable", buttonData, "useBaselineAlphaFallbackUnusable")
        end,
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

-- Mirror of GroupFrameShared.lua GetGrowthMultipliers: anchor corner plus x/y
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
-- ButtonPanelPreviewInteraction.lua populates this shared table before any
-- build invokes the customization-copy helpers.
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
    -- A mixed panel carrying an AURA SECTION owes the same sentence for the
    -- same reason, scoped to that cluster: its members are drawn as fixed slots
    -- here (this is the authoring surface) and packed by Blizzard in the world.
    -- One caption covers either case - the panel that has one says it once.
    --
    -- Every build path passes through here, making the hide reliable when the
    -- preview moves onto an ordinary panel. Empty Aura Panels suppress it
    -- until there is an inactive-aura layout to explain.
    local auraCaptionGroup = preview.readOnly ~= true and preview.panelId
        and CooldownCompanion.db.profile.groups[preview.panelId] or nil
    local emptyAuraPanel = auraCaptionGroup and ST.IsAuraPanelGroup(auraCaptionGroup)
        and #(auraCaptionGroup.buttons or {}) == 0
    if auraCaptionGroup and not emptyAuraPanel and (ST.IsAuraPanelGroup(auraCaptionGroup)
        or ST.PanelHasAuraSection(auraCaptionGroup)) then
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

local function SetPreviewMessage(preview, message, title, note)
    local label = preview.messageLabel
    if not label then
        label = preview.root:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetJustifyH("CENTER")
        label:SetJustifyV("MIDDLE")
        label:SetWordWrap(true)
        preview.messageLabel = label
    end
    label:ClearAllPoints()
    label:SetText(message or "")

    -- A title opts this message into the focused empty-panel treatment. The
    -- plain-message path remains for read-only and filtered states, and for the
    -- compact bands beneath Texture and Trigger mirrors.
    if title then
        local titleLabel = preview.messageTitle
        if not titleLabel then
            titleLabel = preview.root:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
            titleLabel:SetJustifyH("CENTER")
            titleLabel:SetWordWrap(true)
            preview.messageTitle = titleLabel
        end
        titleLabel:ClearAllPoints()
        titleLabel:SetPoint("LEFT", preview.root, "LEFT", 18, 0)
        titleLabel:SetPoint("RIGHT", preview.root, "RIGHT", -18, 0)
        titleLabel:SetPoint("BOTTOM", preview.root, "CENTER", 0, 0)
        titleLabel:SetText(title)
        titleLabel:Show()

        label:SetPoint("TOPLEFT", titleLabel, "BOTTOMLEFT", 0, -8)
        label:SetPoint("TOPRIGHT", titleLabel, "BOTTOMRIGHT", 0, -8)
        label:Show()

        local noteLabel = preview.messageNote
        if note then
            if not noteLabel then
                noteLabel = preview.root:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                noteLabel:SetJustifyH("CENTER")
                noteLabel:SetWordWrap(true)
                preview.messageNote = noteLabel
            end
            noteLabel:ClearAllPoints()
            noteLabel:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -8)
            noteLabel:SetPoint("TOPRIGHT", label, "BOTTOMRIGHT", 0, -8)
            noteLabel:SetText(note)
            noteLabel:Show()
        elseif noteLabel then
            noteLabel:Hide()
        end

        -- Center the complete text stack rather than centering one line and
        -- guessing an offset for the rest. This stays balanced when the body
        -- or Aura note wraps at narrower config widths.
        local titleHeight = math_max(1, titleLabel:GetStringHeight() or 0)
        local belowTitleHeight = 8 + math_max(1, label:GetStringHeight() or 0)
        if note then
            belowTitleHeight = belowTitleHeight
                + 8 + math_max(1, noteLabel:GetStringHeight() or 0)
        end
        titleLabel:ClearAllPoints()
        titleLabel:SetPoint("LEFT", preview.root, "LEFT", 18, 0)
        titleLabel:SetPoint("RIGHT", preview.root, "RIGHT", -18, 0)
        titleLabel:SetPoint("BOTTOM", preview.root, "CENTER", 0,
            (belowTitleHeight - titleHeight) / 2)
        return
    end

    if preview.messageTitle then preview.messageTitle:Hide() end
    if preview.messageNote then preview.messageNote:Hide() end

    -- Re-anchored on every plain call: compact mirrors tuck this label into a
    -- bottom band after calling here, so the full-area default must return for
    -- every other caller on the shared host.
    label:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 18, -18)
    label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, 18)
    label:Show()
end

local function HidePreviewMessage(preview)
    if preview.messageLabel then preview.messageLabel:Hide() end
    if preview.messageTitle then preview.messageTitle:Hide() end
    if preview.messageNote then preview.messageNote:Hide() end
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
-- claiming the opposite of what the panel does. An entry inside an AURA SECTION
-- of a mixed panel renders through that same container, so the badge is just as
-- wrong there - and it is a per-ENTRY answer on a mixed panel, since the base
-- grid beside the section does still reserve.
local function DoesHiddenAuraReserveLayoutSpace(buttonData, group)
    local displayMode = group and (group.displayMode or "icons") or "icons"
    return (displayMode == "icons" or displayMode == "bars")
        and not ST.IsAuraPanelGroup(group)
        and not ST.IsAuraSectionEntry(group, buttonData)
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
        -- Only a lane target ever lights this edge (SectionDrag.SetGapAccent);
        -- the base grid's own insertion gap stays a bare tile.
        gap.border = ST.CreateBorderTextureSet(gap, "OVERLAY")
        preview.gapFrame = gap
    end
    return gap
end

-- Entry footprint and grid settings mirrored from GroupFrameLayout.lua
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
        -- The session filter narrows the scan to the entries it kept
        -- (visibleIndices), so a hidden wide entry stops setting pitch.
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
-- Bottom band reserved for compact entry guidance beneath a specialized mirror.
local EMPTY_ENTRY_GUIDANCE_BAND = 44

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

ST._CollectEntryStatus = CollectEntryStatus
ST._EntryStatusBadges = ENTRY_STATUS_BADGES

-- Private helpers consumed by later ButtonPanelPreview files.
PP.PANEL_PREVIEW_RING_COLOR = PANEL_PREVIEW_RING_COLOR
PP.QueuePreviewSlotTween = QueuePreviewSlotTween
PP.EnsureGapFrame = EnsureGapFrame
PP.PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET
PP.DEFAULT_BAR_READY_TEXT_COLOR = DEFAULT_BAR_READY_TEXT_COLOR
PP.GetStoredBarPreviewState = GetStoredBarPreviewState
PP.IsBarPreviewAuraActive = IsBarPreviewAuraActive
PP.DEFAULT_BAR_COLOR = DEFAULT_BAR_COLOR
PP.GetConfigOnlyBarPreviewIcon = GetConfigOnlyBarPreviewIcon
PP.GetConfigOnlyBarPreviewName = GetConfigOnlyBarPreviewName
PP.PANEL_PREVIEW_COND_TICK = PANEL_PREVIEW_COND_TICK
PP.CopyMode = CopyMode
PP.ConfigurePreviewGhost = ConfigurePreviewGhost
PP.StartPreviewTicker = StartPreviewTicker
PP.ClearPreviewGhost = ClearPreviewGhost
PP.ENTRY_STATUS_BADGE_ATLAS = ENTRY_STATUS_BADGE_ATLAS
PP.PANEL_PREVIEW_AURA_SPACE_BADGE_ATLAS = PANEL_PREVIEW_AURA_SPACE_BADGE_ATLAS
PP.PANEL_PREVIEW_VISIBILITY_BADGE_ATLAS = PANEL_PREVIEW_VISIBILITY_BADGE_ATLAS
PP.RefreshBarSlotWorkspacePresentation = RefreshBarSlotWorkspacePresentation
PP.SLOT_FACTORIES = SLOT_FACTORIES
PP.DisableReadOnlySlotInteraction = DisableReadOnlySlotInteraction
PP.ApplyBarSlotVisualAlpha = ApplyBarSlotVisualAlpha
PP.GetTextSlotSize = GetTextSlotSize
PP.GetPanelGeometry = GetPanelGeometry
PP.GetGrowthMultipliers = GetGrowthMultipliers
PP.GetHostFitScale = GetHostFitScale
PP.HidePreviewMessage = HidePreviewMessage
PP.ApplyPreviewSlotGeometry = ApplyPreviewSlotGeometry
PP.SetPreviewMessage = SetPreviewMessage
PP.FinalizePreviewState = FinalizePreviewState
PP.STRIP_ICON_SIZE = STRIP_ICON_SIZE
PP.STRIP_PER_ROW = STRIP_PER_ROW
PP.STRIP_SPACING = STRIP_SPACING
PP.AcquireSlot = AcquireSlot
PP.IsGlowPreviewActiveOnEntry = IsGlowPreviewActiveOnEntry
PP.PANEL_PREVIEW_DISABLED_ALPHA = PANEL_PREVIEW_DISABLED_ALPHA
PP.ApplySlotBadges = ApplySlotBadges
PP.ApplySelectionVisuals = ApplySelectionVisuals
PP.PANEL_PREVIEW_PADDING = PANEL_PREVIEW_PADDING
PP.EMPTY_ENTRY_GUIDANCE_BAND = EMPTY_ENTRY_GUIDANCE_BAND
PP.GetHostFitBox = GetHostFitBox
PP.GetTriggerDisplayNaturalSize = GetTriggerDisplayNaturalSize
PP.GetStripNaturalSize = GetStripNaturalSize
PP.TRIGGER_PREVIEW_STRIP_MAX_SHARE = TRIGGER_PREVIEW_STRIP_MAX_SHARE
PP.EnsurePreviewState = EnsurePreviewState
PP.ResetPreviewState = ResetPreviewState
PP.IsIconModePanel = IsIconModePanel
PP.IsEntrySelected = IsEntrySelected
PP.CollectBarEntryStatus = CollectBarEntryStatus
PP.ResolveBarPreviewVisibility = ResolveBarPreviewVisibility
PP.ApplyBarSlotPreviewVisibility = ApplyBarSlotPreviewVisibility
PP.GetPanelPreviewNaturalSize = GetPanelPreviewNaturalSize
PP.ResetBarSlotWorkspaceState = ResetBarSlotWorkspaceState
