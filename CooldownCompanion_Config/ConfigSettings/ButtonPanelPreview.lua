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
local GetEffectiveTextHeight = ST._GetEffectiveTextHeight
local CreateGlowContainer = ST._CreateGlowContainer
local SetBarAuraEffect = ST._SetBarAuraEffect
local GetStoredConditionalPreviewState = ST._GetStoredConditionalPreviewState
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

local PANEL_PREVIEW_PADDING = 12
local PANEL_PREVIEW_DISABLED_ALPHA = 0.45
local PANEL_PREVIEW_RING_COLOR = { 0.38, 0.60, 0.92, 1 }
-- Above the bar slots' text frame (statusBar level + 2)
local PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET = 5
-- Badges counter-scale against the preview's scale-to-fit so they stay
-- readable, clamped so they never dwarf a heavily scaled-down slot.
local PANEL_PREVIEW_BADGE_SCREEN_SIZE = 14
-- Matches the resources layout preview's tween timing
local PANEL_PREVIEW_ANIM_DURATION = 0.08
-- Update cadence for animated conditional previews (countdown numbers,
-- loop re-arms); the swipes and fills self-animate between ticks.
local PANEL_PREVIEW_COND_TICK = 0.25
local DEFAULT_BAR_COLOR = { 0.2, 0.6, 1.0, 1.0 }

-- Mirror of GroupFrame.lua GetGrowthMultipliers: anchor corner plus x/y
-- offset signs for the configured growth origin.
local function GetGrowthMultipliers(growthOrigin)
    if growthOrigin == "TOPRIGHT" then return -1, -1, "TOPRIGHT" end
    if growthOrigin == "BOTTOMLEFT" then return 1, 1, "BOTTOMLEFT" end
    if growthOrigin == "BOTTOMRIGHT" then return -1, 1, "BOTTOMRIGHT" end
    return 1, -1, "TOPLEFT"
end

local function EnsurePreviewState(host)
    local preview = host._cdcPanelPreview
    if preview then
        preview.buildId = (preview.buildId or 0) + 1
        return preview
    end

    preview = {
        buildId = 1,
        pools = { iconSlots = {}, barSlots = {}, textSlots = {} },
        used = { iconSlots = 0, barSlots = 0, textSlots = 0 },
    }
    host._cdcPanelPreview = preview

    local root = CreateFrame("Frame", nil, host)
    root:SetAllPoints(host)
    root:SetClipsChildren(false)
    root:Hide()
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

local function FinalizePreviewState(preview)
    for poolName, pool in pairs(preview.pools) do
        local used = preview.used[poolName] or 0
        for index = used + 1, #pool do
            local frame = pool[index]
            frame:Hide()
            frame:ClearAllPoints()
            frame:SetScript("OnMouseDown", nil)
            frame:SetScript("OnMouseUp", nil)
            frame:SetScript("OnEnter", nil)
            frame:SetScript("OnLeave", nil)
        end
    end
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
        label:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 18, -18)
        label:SetPoint("BOTTOMRIGHT", preview.root, "BOTTOMRIGHT", -18, 18)
        preview.messageLabel = label
    end
    label:SetText(message or "")
    label:Show()
end

local function HidePreviewMessage(preview)
    if preview.messageLabel then
        preview.messageLabel:Hide()
    end
end

local function ApplySelectionVisuals(slot, index)
    local isSelected = CS.selectedButton == index or CS.selectedButtons[index] == true
    if not isSelected then
        slot.selectedHighlight:Hide()
        return
    end
    slot.selectedHighlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
    ST.ApplyBorderTextures(slot.selectedHighlight.ringTextures, slot.selectedHighlight,
        PANEL_PREVIEW_RING_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
    slot.selectedHighlight:Show()
end

------------------------------------------------------------------------
-- One-shot override targeting: armed by the promote badges in the panel
-- settings tabs (Helpers.lua) while no entry is selected in the wide
-- view. The next left-click on an eligible entry promotes the armed
-- section for it and lands in its Overrides tab; the badge, right-click,
-- Esc, the banner's X, or a panel switch cancels.
------------------------------------------------------------------------
local PANEL_PREVIEW_TARGETING_COLOR = { 0.30, 0.90, 0.45, 1 }

local function GetActiveOverrideTargeting(panelId)
    local targeting = CS.overrideTargeting
    if targeting and targeting.panelId == panelId then
        return targeting
    end
    return nil
end

local function CancelOverrideTargeting()
    if not CS.overrideTargeting then return end
    CS.overrideTargeting = nil
    CooldownCompanion:RefreshConfigPanel()
end

local function CanTargetEntryForOverride(buttonData, sectionId)
    -- Resolved at call time: Helpers.lua exports this after this file's
    -- top-level locals are captured. Parenthesized to drop the reason.
    local canUse = ST._CanButtonUseConfigOverrideSection
    if canUse then
        return (canUse(buttonData, sectionId))
    end
    return true
end

-- Returns true when the click was consumed by targeting mode.
local function HandleOverrideTargetingClick(panelId, index, buttonData)
    local targeting = GetActiveOverrideTargeting(panelId)
    if not targeting then return false end
    local group = CooldownCompanion.db.profile.groups[panelId]
    if not group then return false end
    local sectionId = targeting.sectionId
    if not CanTargetEntryForOverride(buttonData, sectionId) then
        -- Ineligible entry: stay armed; the hover tooltip explains why.
        return true
    end
    CS.overrideTargeting = nil
    SelectConfigButton(panelId, index)
    if not (buttonData.overrideSections and buttonData.overrideSections[sectionId]) then
        CooldownCompanion:PromoteSection(buttonData, group.style, sectionId)
        CooldownCompanion:UpdateGroupStyle(panelId)
    end
    CS.buttonSettingsTab = "overrides"
    CooldownCompanion:RefreshConfigPanel()
    return true
end

local function EnsureTargetingBanner(preview)
    local banner = preview.targetingBanner
    if banner then return banner end

    -- Slim full-width strip whose dark fill and green accent line fade
    -- out toward the sides: v1's shape with the pill's lighter feel.
    banner = CreateFrame("Frame", nil, preview.root)
    banner:SetPoint("TOPLEFT", preview.root, "TOPLEFT", 0, 0)
    banner:SetPoint("TOPRIGHT", preview.root, "TOPRIGHT", 0, 0)
    banner:SetHeight(20)

    local clear = CreateColor(0, 0, 0, 0)
    local fill = CreateColor(0, 0, 0, 0.7)
    local accent = CreateColor(PANEL_PREVIEW_TARGETING_COLOR[1],
        PANEL_PREVIEW_TARGETING_COLOR[2], PANEL_PREVIEW_TARGETING_COLOR[3], 0.8)
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
    banner.crosshair:SetVertexColor(PANEL_PREVIEW_TARGETING_COLOR[1],
        PANEL_PREVIEW_TARGETING_COLOR[2], PANEL_PREVIEW_TARGETING_COLOR[3])

    -- No close button: Esc, right-click, and re-clicking the armed
    -- badge are the cancel paths (owner call — keeps the strip clean).

    -- Esc cancels. SetPropagateKeyboardInput is combat-restricted
    -- (10.1.5), so keyboard capture only runs out of combat; in combat
    -- the badge, right-click, and the X still cancel.
    banner:SetScript("OnKeyDown", function(self, key)
        if InCombatLockdown() then return end
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            CancelOverrideTargeting()
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)
    banner:RegisterEvent("PLAYER_REGEN_DISABLED")
    banner:SetScript("OnEvent", function(self)
        self:EnableKeyboard(false)
    end)

    banner:Hide()
    preview.targetingBanner = banner
    return banner
end

local function UpdateTargetingBanner(preview, panelId)
    local targeting = CS.overrideTargeting
    if targeting and targeting.panelId ~= panelId then
        -- The preview now shows a different panel: the armed target
        -- surface is gone. Clear silently — we're already mid-rebuild.
        CS.overrideTargeting = nil
        targeting = nil
    end

    local banner = preview.targetingBanner
    if not targeting then
        if banner then
            banner:Hide()
            banner:EnableKeyboard(false)
        end
        return
    end

    banner = EnsureTargetingBanner(preview)
    local sectionDef = ST.OVERRIDE_SECTIONS[targeting.sectionId]
    local label = sectionDef and sectionDef.label or targeting.sectionId
    banner.text:SetText("Click an entry to override |cffffd100" .. label .. "|r")
    banner:SetFrameLevel(preview.root:GetFrameLevel() + 40)
    banner:Show()
    if InCombatLockdown() then
        banner:EnableKeyboard(false)
    else
        banner:EnableKeyboard(true)
        banner:SetPropagateKeyboardInput(true)
    end
end

-- Green ring on the entries an armed targeting click can land on.
-- Runs after ApplySelectionVisuals; targeting is only armable with no
-- selection, so the shared highlight frame is free.
local function ApplyOverrideTargetingVisuals(slot, panelId, buttonData)
    local targeting = GetActiveOverrideTargeting(panelId)
    if not (targeting and CanTargetEntryForOverride(buttonData, targeting.sectionId)) then
        return
    end
    slot.selectedHighlight:SetFrameLevel(slot:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
    ST.ApplyBorderTextures(slot.selectedHighlight.ringTextures, slot.selectedHighlight,
        PANEL_PREVIEW_TARGETING_COLOR, 1, ST.GetEffectiveBorderRenderMode(nil, nil, 1))
    slot.selectedHighlight:Show()
end

-- Entry status signals, mirroring the column 2 row badges exactly.
local function CollectEntryStatus(buttonData, group)
    local usable = CooldownCompanion:IsButtonUsable(buttonData, group)
    local loadAllowed = CooldownCompanion:IsButtonLoadConditionMet(buttonData, group)
    local status = {
        usable = usable,
        disabled = buttonData.enabled == false,
        warn = (not usable) and buttonData.enabled ~= false,
        loadBlocked = not loadAllowed,
        override = CooldownCompanion:HasStyleOverrides(buttonData) and true or false,
        fallback = CooldownCompanion.HasItemFallbacks(buttonData) and true or false,
        talent = (buttonData.talentConditions and #buttonData.talentConditions > 0) and true or false,
        sound = false,
    }
    if buttonData.type == "spell" then
        local enabledSoundEvents = CooldownCompanion:GetEnabledSoundAlertEventsForButton(buttonData)
        -- The aura-applied sound is config-only (played by the game's aura
        -- system, never the runtime engine), so it needs its own check.
        if not enabledSoundEvents
            and (buttonData.auraTracking or buttonData.addedAs == "aura")
            and CooldownCompanion:GetAuraAppliedSoundFileForButton(buttonData) then
            enabledSoundEvents = true
        end
        status.sound = enabledSoundEvents and true or false
    end
    return status
end

-- Ordered badge descriptors, same atlases and meaning as the retired
-- column 2 entry rows; the identity strip in the wide column renders the
-- full set. The "warn" label is replaced with the load-conditions wording
-- when status.loadBlocked is set.
local ENTRY_STATUS_BADGES = {
    { key = "disabled", atlas = "GM-icon-visibleDis-pressed", label = "Disabled" },
    { key = "warn", atlas = "Ping_Marker_Icon_Warning", label = "Spell/item unavailable" },
    { key = "override", atlas = "Crosshair_VehichleCursor_32", label = "Has appearance overrides" },
    { key = "fallback", atlas = "banker", label = "Uses item fallbacks" },
    { key = "sound", atlas = "common-icon-sound", label = "Sound alerts enabled" },
    { key = "talent", atlas = "UI-HUD-MicroMenu-SpecTalents-Mouseover", label = "Has talent conditions" },
}

-- Single problem indicator in the slot's top-right corner: only states
-- where the entry won't behave normally (disabled, or unusable/blocked)
-- earn a mark on the icon, drawn over a dark backdrop so it reads against
-- bright icon art. Informational badges (talent, sound, override,
-- fallback) live in the identity strip and the hover tooltip instead.
local function ApplySlotBadges(slot, status, scale)
    local atlas
    if status.disabled then
        atlas = "GM-icon-visibleDis-pressed"
    elseif status.warn then
        atlas = "Ping_Marker_Icon_Warning"
    end
    if not atlas then
        if slot.problemBadge then slot.problemBadge:Hide() end
        if slot.problemBadgeBack then slot.problemBadgeBack:Hide() end
        return
    end
    local tex = slot.problemBadge
    local back = slot.problemBadgeBack
    if not tex then
        back = slot:CreateTexture(nil, "OVERLAY", nil, 6)
        back:SetColorTexture(0, 0, 0, 0.7)
        slot.problemBadgeBack = back
        tex = slot:CreateTexture(nil, "OVERLAY", nil, 7)
        slot.problemBadge = tex
    end
    local size = math_min(24, math_max(12, PANEL_PREVIEW_BADGE_SCREEN_SIZE / math_max(scale, 0.01)))
    tex:SetAtlas(atlas, false)
    tex:SetSize(size, size)
    tex:ClearAllPoints()
    tex:SetPoint("TOPRIGHT", slot, "TOPRIGHT", 0, 0)
    back:ClearAllPoints()
    back:SetPoint("CENTER", tex, "CENTER", 0, 0)
    back:SetSize(size + 2, size + 2)
    tex:Show()
    back:Show()
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
    local icon = GetLayoutPreviewIcon and GetLayoutPreviewIcon(buttonData)
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

    -- Insertion anchors: midpoints between consecutive slot centers, with
    -- the two end positions extrapolated half a step beyond the run, so
    -- the nearest anchor is the insertion index. Works for any growth
    -- origin and wrapping because it only uses actual slot geometry.
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
            else -- BOTTOMRIGHT
                tlX, tlY = localW + x - slotW / 2, -localH + y + slotH / 2
            end
            centers[i] = {
                x = cLeft + tlX * factor,
                y = cBottom + cHeight + tlY * factor,
            }
        end

        local bestIndex, bestDist
        for i = 1, count + 1 do
            local ax, ay
            if i == 1 then
                ax = centers[1].x - (centers[2].x - centers[1].x) / 2
                ay = centers[1].y - (centers[2].y - centers[1].y) / 2
            elseif i == count + 1 then
                ax = centers[count].x + (centers[count].x - centers[count - 1].x) / 2
                ay = centers[count].y + (centers[count].y - centers[count - 1].y) / 2
            else
                ax = (centers[i - 1].x + centers[i].x) / 2
                ay = (centers[i - 1].y + centers[i].y) / 2
            end
            local dx, dy = cursorX - ax, cursorY - ay
            local dist = dx * dx + dy * dy
            if not bestDist or dist < bestDist then
                bestDist, bestIndex = dist, i
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

-- Shift-hover shows the real spell/item tooltip, mirroring the column 2
-- entry rows; a plain hover shows the decorated entry name plus the same
-- status lines the row badges carry.
local function ShowEntrySlotTooltip(slot, buttonData, status)
    GameTooltip:SetOwner(slot, "ANCHOR_RIGHT")
    if IsShiftKeyDown() then
        if buttonData.type == "spell" and buttonData.id then
            GameTooltip:SetSpellByID(buttonData.id)
            GameTooltip:Show()
            return
        elseif buttonData.type == "item" and buttonData.id then
            GameTooltip:SetItemByID(buttonData.id)
            GameTooltip:Show()
            return
        elseif CooldownCompanion.IsEquipmentSlotEntry
            and CooldownCompanion.IsEquipmentSlotEntry(buttonData) then
            local effectiveItem = CooldownCompanion.ResolveEffectiveItem
                and CooldownCompanion.ResolveEffectiveItem(buttonData, true) or nil
            if effectiveItem and effectiveItem.trackable and effectiveItem.itemID then
                GameTooltip:SetItemByID(effectiveItem.itemID)
                GameTooltip:Show()
                return
            end
        end
    end
    local name = GetConfigEntryDisplayName(buttonData, { includeDecorations = true })
    GameTooltip:SetText(name or "Entry", 1, 1, 1)
    if buttonData.type == "spell" then
        -- Same addedAs fallback the name decorations use.
        local addedAs = buttonData.addedAs
        if addedAs ~= "spell" and addedAs ~= "aura" then
            addedAs = buttonData.isPassive and "aura" or "spell"
        end
        GameTooltip:AddLine(addedAs == "aura" and "Tracked as an aura" or "Tracked as a spell",
            0.6, 0.6, 0.6)
    end
    if status.disabled then
        GameTooltip:AddLine("Disabled", 0.6, 0.6, 0.6)
    end
    if status.warn then
        if status.loadBlocked then
            GameTooltip:AddLine("Hidden by load conditions", 1, 0.3, 0.3)
        else
            GameTooltip:AddLine("Spell/item unavailable", 1, 0.3, 0.3)
        end
    end
    if status.override then
        GameTooltip:AddLine("Has appearance overrides", 1, 1, 1)
    end
    if status.fallback then
        GameTooltip:AddLine("Uses item fallbacks", 1, 1, 1)
    end
    if status.sound then
        GameTooltip:AddLine("Sound alerts enabled", 1, 1, 1)
    end
    if status.talent then
        GameTooltip:AddLine("Has talent conditions", 1, 1, 1)
    end
    if CooldownCompanion:HasLocalLoadConditions(buttonData) then
        GameTooltip:AddLine("This entry adds load conditions.", 0.7, 0.7, 0.7)
    end
    if slot._cdcDraggable then
        GameTooltip:AddLine("Drag to reorder.", 0.75, 0.82, 0.92)
    end
    GameTooltip:Show()
end

local function WireEntryInteraction(slot, panelId, index, buttonData, status, layoutDrag)
    slot._cdcDraggable = layoutDrag ~= nil
    slot:SetScript("OnMouseDown", function(self, mouseButton)
        if mouseButton ~= "LeftButton" or GetCursorInfo() then return end
        -- No drag-reorder while override targeting is armed: the press
        -- is a targeting click, consumed on mouse-up.
        if CS.overrideTargeting then return end
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
            if HandleOverrideTargetingClick(panelId, index, buttonData) then return end
            SelectConfigButton(panelId, index, { multi = IsControlKeyDown() })
            CooldownCompanion:RefreshConfigPanel()
        elseif mouseButton == "RightButton" or mouseButton == "MiddleButton" then
            if CS.dragState and CS.dragState.phase == "active" then return end
            if GetActiveOverrideTargeting(panelId) then
                CancelOverrideTargeting()
                return
            end
            if ShowEntryContextMenu then
                ShowEntryContextMenu(panelId, index, buttonData)
            end
        end
    end)
    slot:SetScript("OnEnter", function(self)
        if CS.dragState and CS.dragState.phase == "active" then return end
        self.hoverHighlight:SetFrameLevel(self:GetFrameLevel() + PANEL_PREVIEW_HIGHLIGHT_LEVEL_OFFSET)
        self.hoverHighlight:Show()
        ShowEntrySlotTooltip(self, buttonData, status)
        local targeting = GetActiveOverrideTargeting(panelId)
        if targeting then
            local sectionDef = ST.OVERRIDE_SECTIONS[targeting.sectionId]
            local label = sectionDef and sectionDef.label or targeting.sectionId
            if CanTargetEntryForOverride(buttonData, targeting.sectionId) then
                GameTooltip:AddLine("Click to override " .. label .. " for this entry", 0.3, 0.9, 0.45)
            else
                GameTooltip:AddLine("This entry cannot use the " .. label .. " override", 0.5, 0.5, 0.5)
            end
            GameTooltip:Show()
        end
    end)
    slot:SetScript("OnLeave", function(self)
        self.hoverHighlight:Hide()
        GameTooltip:Hide()
    end)
end

-- Entry footprint and grid settings mirrored from GroupFrame.lua
-- (GetButtonDimensions + ApplyActiveButtonLayout).
local function GetPanelGeometry(group, isBarMode, isTextMode)
    local style = group.style or {}
    local w, h
    if isTextMode then
        -- Mirror of GroupFrame's text-mode sizing: widest entry width and
        -- tallest effective format height win (the config mirror measures
        -- every entry, not just currently usable ones).
        w = style.textWidth or 200
        h = style.textHeight or 20
        if GetEffectiveTextHeight then
            h = GetEffectiveTextHeight(style, style.textFormat)
            for _, buttonData in ipairs(group.buttons or {}) do
                local effectiveStyle = CooldownCompanion.GetEffectiveStyle
                    and CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
                local fmt = buttonData.textFormat or effectiveStyle.textFormat
                w = math_max(w, effectiveStyle.textWidth or 200)
                -- Parenthesized: GetEffectiveTextHeight returns a second
                -- (boolean) value that must not reach math_max.
                h = math_max(h, (GetEffectiveTextHeight(effectiveStyle, fmt)))
            end
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
    return {
        entryWidth = w,
        entryHeight = h,
        spacing = style.buttonSpacing or ST.BUTTON_SPACING,
        orientation = style.orientation or (isBarMode and "vertical" or "horizontal"),
        buttonsPerRow = style.buttonsPerRow or 12,
    }
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
end

------------------------------------------------------------------------
-- Conditional visual previews on the mirror (icon panels): while a
-- conditional preview toggle (cooldown, charges, unusable, out of
-- range, aura duration/stacks, loss of control) is active for an entry
-- or its whole panel, render the same CC-side stand-in the live world
-- buttons show - from the same stored preview state (Preview.lua) and
-- the same timing math (CooldownUpdate.lua), so the mirror stays
-- time-synced with the live preview. Times are literal numbers from
-- the stored state (config-only; never live cooldown reads).
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
-- previews may force desaturation on, never off. Each branch mirrors
-- the live interpreter (CooldownUpdate.lua ApplyConditionalVisualPreview)
-- plus that state's render outcome (Tracking.lua tint/desaturation,
-- IconMode.lua swipe/fill), gated on the same style keys.
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

    if kind == "cooldown" and GetConditionalPreviewTiming then
        local startTime, duration = GetConditionalPreviewTiming(state, now)
        if startTime then
            -- An active icon fill owns the cooldown visual and suppresses
            -- the swipe and edge (VisualState.lua SetIconFillIntent).
            local fillActive = style.iconFillEnabled == true
                and group.masqueEnabled ~= true
                and ResolveIconFillTimerValue ~= nil
            local cd = slot.cooldown
            local swipeEnabled = style.showCooldownSwipe ~= false and not fillActive
            cd:SetDrawSwipe(swipeEnabled and style.showCooldownSwipeFill ~= false)
            cd:SetDrawEdge(swipeEnabled and style.showCooldownSwipeEdge ~= false)
            cd:SetReverse(style.cooldownSwipeReverse or false)
            cd:SetSwipeColor(0, 0, 0, style.cooldownSwipeAlpha or 0.8)
            local edgeColor = style.cooldownSwipeEdgeColor or { 1, 1, 1, 1 }
            cd:SetEdgeColor(edgeColor[1], edgeColor[2], edgeColor[3], edgeColor[4])
            StyleSlotCooldownText(slot, style)
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

            if style.desaturateOnCooldown then
                forceDesat = true
            end
            if style.iconCooldownTintEnabled and style.iconCooldownTintColor then
                local c = style.iconCooldownTintColor
                tintR, tintG, tintB, tintA = c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1
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
                if style.iconCooldownTintEnabled and style.iconCooldownTintColor then
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
    elseif kind == "aura_duration_text" and GetConditionalPreviewTiming then
        if style.showAuraText ~= false then
            local startTime, _, remaining = GetConditionalPreviewTiming(state, now)
            if startTime then
                local fs = EnsureSlotAuraText(slot)
                CooldownCompanion.ApplyFontStyle(fs, style, "auraText")
                local anchor, xOff, yOff = CooldownCompanion:GetAuraDurationTextPlacement(style)
                fs:ClearAllPoints()
                fs:SetPoint(anchor, slot, anchor, xOff, yOff)
                fs:SetFormattedText("%d", math_ceil(remaining))
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
            fs:SetText(state.stackText or "3")
            fs:Show()
        end
    elseif kind == "aura_duration_swipe" and GetConditionalPreviewTiming then
        if style.showAuraDurationSwipe ~= false then
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
        -- Live gate (CooldownUpdate.lua): spells only, never passives.
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
-- BarMode.lua DEFAULT_AURA_TEXT_COLOR
local DEFAULT_AURA_TEXT_COLOR = { 0, 0.925, 1, 1 }

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

local function StopBarSlotFillEffects(slot)
    if slot._cdcFillPulseAG then slot._cdcFillPulseAG:Stop() end
    if slot._cdcFillShiftAG then slot._cdcFillShiftAG:Stop() end
    local fillTex = slot.statusBar and slot.statusBar:GetStatusBarTexture()
    if fillTex then
        -- Clears residual shift tint; 4-arg SetVertexColor is the last
        -- alpha write on this region (live UpdateBarDisplay parity).
        fillTex:SetVertexColor(1, 1, 1, 1)
    end
end

-- Active Aura Indicator fill effects on the mirror bar, per BarMode.lua
-- UpdateBarDisplay. Returns true when the color-shift animation owns the
-- fill color (the bar then goes white underneath, kit trick).
local function ApplyBarSlotFillEffects(slot, style)
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
    if style.barAuraColorShiftEnabled == true then
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

-- StyleBarEntry re-baselines the fill value and color on every rebuild
-- before this runs, so the reset only has to clear what it added.
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

local function ApplyBarSlotConditionalPreview(slot, buttonData, group, panelId, index)
    ResetBarSlotConditionalVisuals(slot)
    -- Read by ApplyBarCountTextStyle
    slot.buttonData = buttonData

    local style = slot.style or group.style or {}
    -- Bars run the same icon tint pipeline live (UpdateIconTint on the
    -- bar icon); baseline restored every rebuild like the icon slots.
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

    if kind == "aura_duration_bar" and GetConditionalPreviewTiming then
        local startTime, duration, remaining = GetConditionalPreviewTiming(state, now)
        if startTime then
            -- The Active Aura Indicator preview's fill effects ride the
            -- aura drain (live UpdateBarDisplay, keyed off the flag).
            local fxActive = CooldownCompanion.IsPreviewFlagActive
                and CooldownCompanion:IsPreviewFlagActive(panelId, index, "_barAuraEffectPreview")
                and ST.IsBarAuraIndicatorEnabled
                and ST.IsBarAuraIndicatorEnabled(style) == true
            local shifted = false
            if fxActive then
                shifted = ApplyBarSlotFillEffects(slot, style)
            end
            local auraColor = style.barAuraColor or DEFAULT_BAR_AURA_COLOR or { 0, 1, 0.3, 1 }
            if shifted then
                -- White base while the shift animation owns the color.
                slot.statusBar:SetStatusBarColor(1, 1, 1, auraColor[4] or 1)
            else
                slot.statusBar:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1)
            end
            slot.statusBar._cdcOwner = slot
            slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
            slot._cdcCondAnim = state
            BarSlotFillOnUpdate(slot.statusBar)
            if style.showAuraText ~= false then
                -- Aura-styled time text per UpdateBarFill's aura mode
                local tt = EnsureBarSlotTimeText(slot)
                local f = CooldownCompanion:FetchFont(style.auraTextFont or "Friz Quadrata TT")
                local s = style.auraTextFontSize or 12
                local o = ST.GetEffectiveFontOutline(style.auraTextFontOutline or "OUTLINE")
                tt:SetFont(f, s, o)
                ST.ApplyFontShadowForOutline(tt, o)
                local cc = style.auraTextFontColor or DEFAULT_AURA_TEXT_COLOR
                tt:SetTextColor(cc[1], cc[2], cc[3], cc[4])
                AnchorBarSlotTimeText(slot, style)
                tt:SetText(CooldownCompanion.FormatTime(remaining, style))
            end
        end
    elseif kind == "cooldown" and GetConditionalPreviewTiming then
        local startTime, duration, remaining = GetConditionalPreviewTiming(state, now)
        if startTime then
            if not buttonData.isPassive then
                local c = style.barCooldownColor or style.barColor or DEFAULT_BAR_COLOR
                slot.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
            end
            slot.statusBar._cdcOwner = slot
            slot.statusBar:SetScript("OnUpdate", BarSlotFillOnUpdate)
            slot._cdcCondAnim = state
            BarSlotFillOnUpdate(slot.statusBar)
            if style.showCooldownText then
                local tt = EnsureBarSlotTimeText(slot)
                CooldownCompanion.ApplyFontStyle(tt, style, "cooldown")
                AnchorBarSlotTimeText(slot, style)
                tt:SetText(CooldownCompanion.FormatTime(remaining, style))
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
                if kind == "charge_missing" then
                    local c = style.barChargeColor or DEFAULT_BAR_CHARGE_COLOR or { 1, 0.8, 0.2, 1 }
                    slot.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                elseif kind == "charge_zero" then
                    local c = style.barCooldownColor or style.barColor or DEFAULT_BAR_COLOR
                    slot.statusBar:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
                end
            end

            if kind == "charge_zero" then
                if style.desaturateOnCooldown
                    or (buttonData.desaturateWhileZeroCharges
                        and not (CooldownCompanion.HasItemFallbacks
                            and CooldownCompanion.HasItemFallbacks(buttonData))) then
                    forceDesat = true
                end
                if style.iconCooldownTintEnabled and style.iconCooldownTintColor then
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
            fs:SetText(state.stackText or "3")
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
-- entry (or its whole panel), render the same glow the live buttons
-- show, through the very same Glows.lua setters. Mirror slots carry
-- their own glow containers and a `style` field - all the setters read.
-- Parity rule: live glow previews only render where the live frames have
-- containers (icons: proc/aura/ready/key-press; bars: bar aura effect;
-- text: none).
------------------------------------------------------------------------
local EFFECT_PREVIEWS = {
    { flag = "_procGlowPreview", containerKey = "procGlow", setter = ST._SetProcGlow },
    { flag = "_auraGlowPreview", containerKey = "auraGlow", setter = ST._SetAuraGlow },
    { flag = "_readyGlowPreview", containerKey = "readyGlow", setter = ST._SetReadyGlow },
    { flag = "_keyPressHighlightPreview", containerKey = "keyPressHighlight",
        setter = ST._SetKeyPressHighlight, withOverlay = true },
}

local function ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, isBarMode)
    local style = group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end
    slot.style = style

    local canQuery = CooldownCompanion.IsPreviewFlagActive ~= nil

    if not isBarMode then
        for _, def in ipairs(EFFECT_PREVIEWS) do
            if def.setter then
                local active = canQuery
                    and CooldownCompanion:IsPreviewFlagActive(panelId, index, def.flag) or false
                if active and not slot[def.containerKey] and CreateGlowContainer then
                    slot[def.containerKey] = CreateGlowContainer(slot, 32, def.withOverlay)
                end
                if slot[def.containerKey] then
                    def.setter(slot, active)
                end
            end
        end
        return
    end

    if SetBarAuraEffect then
        -- Live parity (Preview.lua barAuraEffectOnToggle): nothing renders
        -- while the bar aura indicator is disabled.
        local active = canQuery
            and CooldownCompanion:IsPreviewFlagActive(panelId, index, "_barAuraEffectPreview")
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
                    if state.kind == "aura_duration_text" and slot.auraTextFS then
                        slot.auraTextFS:SetFormattedText("%d", math_ceil(remaining))
                    end
                    local widget
                    if state.kind == "cooldown" then
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
                        if state.kind == "cooldown" then
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
                        and (state.kind == "cooldown" or state.kind == "aura_duration_bar") then
                        local style = slot.style or {}
                        local showText = (state.kind == "aura_duration_bar" and style.showAuraText ~= false)
                            or (state.kind == "cooldown" and style.showCooldownText)
                        if showText and CooldownCompanion.FormatTime then
                            slot.timeText:SetText(CooldownCompanion.FormatTime(remaining, style))
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
    local borderLayoutSize = ST.GetEffectiveBorderLayoutSize(slot, borderSize, borderRenderMode)
    local inset = ((borderSize > 0
        or ST.IsEffectiveCrispBorderRenderMode(borderRenderMode, nil, borderSize)) and borderLayoutSize or 0) + 2
    ts:ClearAllPoints()
    ts:SetPoint("TOPLEFT", inset, -1)
    ts:SetPoint("BOTTOMRIGHT", -inset, 1)
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
            -- stacks/aura tokens: idle (empty) on the mirror
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

local function ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index)
    slot._cdcCondAnim = nil
    slot.buttonData = buttonData

    local style = slot.style or group.style or {}
    local fmt = buttonData.textFormat or style.textFormat or DEFAULT_TEXT_FORMAT
    slot._cdcTextSegments = ParseFormatString and ParseFormatString(fmt) or nil

    -- Live ApplyTextLayout: multiline formats wrap from the top
    if GetEffectiveTextHeight then
        local _, isMultiline = GetEffectiveTextHeight(style, fmt)
        slot.textString:SetJustifyV(isMultiline and "TOP" or "MIDDLE")
        slot.textString:SetWordWrap(isMultiline and true or false)
    end

    local state = GetStoredConditionalPreviewState
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
    local vEdge = (growthOrigin == "BOTTOMLEFT" or growthOrigin == "BOTTOMRIGHT") and "BOTTOM" or "TOP"
    local anchor = align == "RIGHT" and (vEdge .. "RIGHT") or align == "CENTER" and vEdge or (vEdge .. "LEFT")
    local xOff = (align == "CENTER") and 0 or (align == "RIGHT") and -2 or 2
    local yOff = vEdge == "BOTTOM" and 1 or -1
    header:SetPoint(anchor, preview.content, anchor, xOff, yOff)
    header:SetWidth(math_max(1, (preview.content:GetWidth() or 0) - 4))
    header:Show()
end

local function GetHostFitScale(host, contentWidth, contentHeight)
    local hostWidth = host:GetWidth() or 0
    local hostHeight = host:GetHeight() or 0
    if hostWidth < 40 then hostWidth = 340 end
    if hostHeight < 40 then hostHeight = 200 end
    local maxWidth = math_max(80, hostWidth - (PANEL_PREVIEW_PADDING * 2))
    local maxHeight = math_max(80, hostHeight - (PANEL_PREVIEW_PADDING * 2))
    return math_min(1, maxWidth / math_max(1, contentWidth), maxHeight / math_max(1, contentHeight))
end

-- Fallback for panel types with no meaningful geometric mirror (trigger,
-- texture, and rotation-assistant panels): a flat strip of
-- clickable entry icons with the same selection, badges, tooltips, and
-- context-menu behavior as the mirrored slots.
local STRIP_ICON_SIZE = 36
local STRIP_SPACING = 4
local STRIP_PER_ROW = 8

local function BuildSelectionStrip(preview, host, panelId, group)
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
        SetPreviewMessage(preview, "This panel has no entries yet. Add spells or items in the Panels column.")
        FinalizePreviewState(preview)
        return
    end

    local w, h = STRIP_ICON_SIZE, STRIP_ICON_SIZE
    local cols = math_min(count, STRIP_PER_ROW)
    local rows = math_ceil(count / STRIP_PER_ROW)
    local contentWidth = (cols - 1) * (w + STRIP_SPACING) + w
    local contentHeight = (rows - 1) * (h + STRIP_SPACING) + h
    local scale = GetHostFitScale(host, contentWidth, contentHeight)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()

    local layoutDrag = CreatePreviewLayoutDrag(preview, panelId)
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
    local dragModel = (not isRA and count >= 2) and layoutDrag or nil

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

        if entryInfo.isRotationAssistant then
            slot.icon:SetDesaturated(false)
            if slot.problemBadge then slot.problemBadge:Hide() end
            if slot.problemBadgeBack then slot.problemBadgeBack:Hide() end
            -- Recycled slots may carry a drag handler from a grid render
            slot:SetScript("OnMouseDown", nil)
            if CS.selectedRotationAssistantEntry == true then
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
                    ST._SelectConfigButtonPanel(panelId, { clearPanelMulti = true })
                else
                    ST._SelectConfigRotationAssistantEntry(panelId, { containerId = CS.selectedContainer })
                end
                CooldownCompanion:RefreshConfigPanel()
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
        else
            local status = CollectEntryStatus(buttonData, group)
            slot.icon:SetDesaturated(not status.usable)
            if status.disabled then
                slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
            end
            slot._cdcBaseAlpha = status.disabled and PANEL_PREVIEW_DISABLED_ALPHA or 1
            ApplySlotBadges(slot, status, scale)
            ApplySelectionVisuals(slot, entryInfo.index)
            ApplyOverrideTargetingVisuals(slot, panelId, buttonData)
            layoutDrag.slots[entryInfo.index] = slot
            WireEntryInteraction(slot, panelId, entryInfo.index, buttonData, status, dragModel)
        end
    end

    content:SetScale(scale)
    content:ClearAllPoints()
    content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)

    FinalizePreviewState(preview)
end

-- Static mirror of BarMode.lua CreateBarFrame: same saved settings, same
-- shared area/border helpers, full fill, no runtime state.
local function StyleBarEntry(slot, buttonData, group)
    local style = group.style or {}
    if CooldownCompanion.GetEffectiveStyle then
        style = CooldownCompanion:GetEffectiveStyle(style, buttonData) or style
    end

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
        slot.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        slot.icon:SetTexture(GetLayoutPreviewIcon(buttonData))
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
        nameText:SetText(buttonData.customName or buttonData.name or GetConfigEntryDisplayName(buttonData) or "")
        nameText:Show()
    else
        nameText:Hide()
    end

    for i = 1, 4 do
        slot.borderTextures[i]:SetColorTexture(borderColor[1], borderColor[2], borderColor[3], borderColor[4])
    end
    ApplyBorderEdgePositions(slot.borderTextures, slot.barBounds, borderSize, borderRenderMode)
end

function ST._BuildButtonPanelPreview(host, panelId)
    -- Rebuilding pulls the slot frames out from under an in-flight drag
    if CS.dragState and CS.dragState.kind == "layout-slot" and CancelDrag then
        CancelDrag()
    end

    local preview = EnsurePreviewState(host)
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
    ResetPreviewState(preview)
    HidePreviewMessage(preview)
    preview.content:Hide()
    UpdateTargetingBanner(preview, panelId)

    local group = panelId and CooldownCompanion.db.profile.groups[panelId]
    if not group then
        SetPreviewMessage(preview, "Select a panel to preview it here.")
        FinalizePreviewState(preview)
        return
    end

    local isBarMode = group.displayMode == "bars"
    local isTextMode = group.displayMode == "text"
    if not isBarMode and not isTextMode and not IsIconModePanel(group) then
        return BuildSelectionStrip(preview, host, panelId, group)
    end

    local buttons = group.buttons or {}
    local count = #buttons
    if count == 0 then
        SetPreviewMessage(preview, "This panel has no entries yet. Add spells or items in the Panels column.")
        FinalizePreviewState(preview)
        return
    end

    local geo = GetPanelGeometry(group, isBarMode, isTextMode)
    local w, h = geo.entryWidth, geo.entryHeight
    local spacing = geo.spacing
    local perRow = math_max(1, geo.buttonsPerRow)
    local style = group.style or {}
    local xMul, yMul, growthAnchor = GetGrowthMultipliers(style.growthOrigin)

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
    local scale = GetHostFitScale(host, contentWidth, contentHeight)

    local content = preview.content
    content:SetSize(contentWidth, contentHeight)
    content:Show()
    UpdateTextGroupHeader(preview, group, style, headerHeight)

    local poolName = isBarMode and "barSlots" or (isTextMode and "textSlots" or "iconSlots")
    local styleFn = isBarMode and StyleBarEntry or (isTextMode and StyleTextEntry or StyleIconEntry)

    local layoutDrag = CreatePreviewLayoutDrag(preview, panelId)
    layoutDrag.count = count
    layoutDrag.slotW, layoutDrag.slotH = w, h
    layoutDrag.scale = scale
    layoutDrag.anchor = growthAnchor
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
    preview.layoutDrag = layoutDrag
    local dragModel = (count >= 2) and layoutDrag or nil

    for index, buttonData in ipairs(buttons) do
        local slot = AcquireSlot(preview, content, poolName)
        slot:SetSize(w, h)

        local cx, cy = layoutDrag.cellXY(index)
        ApplyPreviewSlotGeometry(preview, slot, growthAnchor, cx, cy)

        styleFn(slot, buttonData, group)
        if not isTextMode then
            ApplySlotEffectPreviews(slot, buttonData, group, panelId, index, isBarMode)
        end
        local status = CollectEntryStatus(buttonData, group)
        if slot.icon then
            slot.icon:SetDesaturated(not status.usable)
        end
        if isBarMode then
            ApplyBarSlotConditionalPreview(slot, buttonData, group, panelId, index)
        elseif isTextMode then
            ApplyTextSlotConditionalPreview(slot, buttonData, group, panelId, index)
        else
            ApplySlotConditionalPreview(slot, buttonData, group, panelId, index)
        end
        if status.disabled then
            slot:SetAlpha(PANEL_PREVIEW_DISABLED_ALPHA)
        end
        slot._cdcBaseAlpha = status.disabled and PANEL_PREVIEW_DISABLED_ALPHA or 1
        ApplySlotBadges(slot, status, scale)
        ApplySelectionVisuals(slot, index)
        ApplyOverrideTargetingVisuals(slot, panelId, buttonData)
        layoutDrag.slots[index] = slot
        WireEntryInteraction(slot, panelId, index, buttonData, status, dragModel)
    end

    -- Tick only while at least one slot is animating a conditional preview
    local anyAnimated = false
    for i = 1, count do
        local s = layoutDrag.slots[i]
        if s and s._cdcCondAnim then
            anyAnimated = true
            break
        end
    end
    if anyAnimated then
        EnsureConditionalTicker(preview)
    else
        StopConditionalTicker(preview)
    end

    content:SetScale(scale)
    content:ClearAllPoints()
    content:SetPoint("CENTER", preview.root, "CENTER", 0, 0)

    FinalizePreviewState(preview)
end

ST._CollectEntryStatus = CollectEntryStatus
ST._EntryStatusBadges = ENTRY_STATUS_BADGES

function ST._ReleaseButtonPanelPreview(host)
    local preview = host and host._cdcPanelPreview
    if preview then
        StopConditionalTicker(preview)
        -- The targeting mode's only click surface is this preview; a
        -- release means the surface is gone, so disarm (state only —
        -- whoever released us is already driving a refresh).
        CS.overrideTargeting = nil
        if preview.targetingBanner then
            preview.targetingBanner:Hide()
            preview.targetingBanner:EnableKeyboard(false)
        end
        preview.root:Hide()
    end
end
