--[[
    CooldownCompanion - Core/AuraDisplay.lua: 12.1 AuraContainer-based aura
    display (rebuild Phase 1+).

    THE SINGLE-WRITER RULE: this file is the ONLY code in the addon allowed to
    hold or touch aura slot buttons or the regions created under them. Once
    auras are secret (combat), the entire slot subtree is FORBIDDEN to addon
    code — reads and writes both error, an error freezes the display, and
    IsForbidden() does NOT report the state. Safety is structural, not checked:
      * All slot work happens in the OOC rebind pass (RequestAuraRebind).
      * Slot buttons live under button.auraLayer (_ccNoTouch = true); frame
        sweeps never recurse into flagged frames.
      * In combat the only permitted aura-system calls are container-level
        (UpdateAllAuras, SetAuraSlotCandidateFilters).

    PTR 7 (tracker D-A0): aura buttons carry a permanent ChangeParent
    forbidden aspect — SetParent on a slot button errors even out of combat.
    The display therefore uses ONE AuraContainer PER HOST BUTTON, created as
    a child of that button's auraLayer (containers are plain CC frames; the
    parent is set at CreateFrame and never changed — only the BUTTONS carry
    the forbidden aspects), with the slot button anchored once inside
    initializeFrame and never moved, re-leveled, or reparented afterwards.
    Bind and park are container-mutator filter swaps (park = polarity-crossed
    sentinel; V25 Q4: Blizzard hides an unmatched slot button entirely).
    Host Show/Hide, alpha fades, and strata changes reach the slot through
    plain parentage again, and a re-shown container re-registers its events
    and refreshes itself (AuraContainerPrivateMixin:OnShow_Intrinsic).
    Evidence: docs/12.1-aura-tracking-research.md; validation matrix V1-V18,
    Phase 0 probes P1-P11, and V25 (PTR 7 reparent enforcement).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame = CreateFrame

-- Parking (P1b/P1c + V25 Q4): slots can never be removed; unbound slots get a
-- sentinel candidate filter, and Blizzard hides an unmatched slot button
-- entirely — a parked slot renders nothing even though it stays anchored on
-- its host. Empty includeSpellIDs is BANNED — it wedges the slot permanently.
-- Sentinels are POLARITY-CROSSED so they are structurally never-match: a
-- HELPFUL slot parked on a debuff spellID (debuffs can never appear in
-- HELPFUL results) and a HARMFUL slot parked on a buff spellID.
local PARK_SENTINEL = {
    player = 155722, -- Rake (a bleed debuff; never matches a HELPFUL filter)
    target = 5217,   -- Tiger's Fury (a self buff; never matches a HARMFUL filter)
}

local UNIT_FILTER = { player = "HELPFUL", target = "HARMFUL" }

-- Module state. One display record (container + slot + kit) per host button,
-- living only here — no slot-button references are ever stored on CC buttons,
-- so no sweep or diagnostic walk can reach the forbidden subtree by accident.
-- Records are keyed by host button and permanent (buttons are pooled, never
-- destroyed; slots can never be removed).
local displays = {}       -- host button -> display record
local slotCounter = 0
local pendingRebind = false
local rebindQueued = false

-- Deferred-rebind retry events: PLAYER_REGEN_ENABLED for player combat, and
-- target-scoped UNIT_FLAGS for the case where ONLY target combat blocks (an
-- OOC player never gets a regen event, so the target's own combat-flag change
-- must wake the retry). The handler re-checks the gate, so extra fires are
-- harmless; PLAYER_TARGET_CHANGED retries live on the target watcher.
local rebindDeferFrame = CreateFrame("Frame")

local function ArmRebindRetry()
    pendingRebind = true
    rebindDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    rebindDeferFrame:RegisterUnitEvent("UNIT_FLAGS", "target")
end

local function DisarmRebindRetry()
    rebindDeferFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    rebindDeferFrame:UnregisterEvent("UNIT_FLAGS")
end

------------------------------------------------------------------------
-- Containers
------------------------------------------------------------------------

local targetWatcher
local RunAuraRebind

local function HasTargetDisplays()
    for _, record in pairs(displays) do
        if record.unit == "target" then return true end
    end
    return false
end

local function CanRunRebindNow()
    if InCombatLockdown() then return false end
    -- P11 (conservative): secrecy follows the unit's state, so target slots
    -- are only touchable while the target is also out of combat.
    if HasTargetDisplays() and UnitExists("target") and UnitAffectingCombat("target") then
        return false
    end
    return true
end

local function EnsureTargetWatcher()
    if targetWatcher then return end
    targetWatcher = CreateFrame("Frame")
    targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetWatcher:SetScript("OnEvent", function()
        -- Container-level calls: combat-safe (V13, re-validated V18). Without
        -- them target containers never re-parse on same-token target swaps.
        -- Hidden hosts self-heal instead: OnShow_Intrinsic re-runs
        -- UpdateAllAuras, so a container that missed swaps while hidden
        -- catches up the moment its host shows again.
        for _, record in pairs(displays) do
            if record.unit == "target" then
                record.container:UpdateAllAuras()
            end
        end
        -- A deferred rebind may have been blocked only by target combat.
        if pendingRebind and CanRunRebindNow() then
            pendingRebind = false
            DisarmRebindRetry()
            RunAuraRebind()
        end
    end)
end

------------------------------------------------------------------------
-- Slot kit — built ONCE per slot, inside initializeFrame (the sanctioned
-- setup window). Regions cover every configuration because slots are reused
-- across entries; per-entry enable/disable is alpha at bind time (P6).
------------------------------------------------------------------------

local function BuildSlotKit(slotButton)
    local kit = {}

    -- Shell composition (show-only-while-active entries): background and
    -- border replicas let the slot render the ENTIRE visible button while the
    -- CC frame underneath is an invisible layout shell. They deliberately
    -- overhang the slot (which covers only the icon rect); geometry is
    -- anchored to the host button at bind time and they stay alpha-0 for
    -- ordinary entries.
    kit.bg = slotButton:CreateTexture(nil, "BACKGROUND")
    kit.bg:SetAlpha(0)
    kit.border = {}
    for i = 1, 4 do
        local tex = slotButton:CreateTexture(nil, "OVERLAY")
        tex:SetAlpha(0)
        kit.border[i] = tex
    end

    -- Static occluder (two-layer compositing): while the aura runs, this
    -- covers the CC button's own icon + cooldown swipe, so the aura display
    -- REPLACES the cooldown display instead of stacking on it. CC-authored,
    -- never registered with the button.
    kit.iconCover = slotButton:CreateTexture(nil, "ARTWORK", nil, 1)
    kit.iconCover:SetAllPoints(slotButton)
    kit.iconCover:SetAlpha(0)

    kit.auraIcon = slotButton:CreateTexture(nil, "ARTWORK", nil, 2)
    kit.auraIcon:SetAllPoints(slotButton)
    slotButton:SetIcon(kit.auraIcon)

    kit.swipe = CreateFrame("Cooldown", nil, slotButton, "CooldownFrameTemplate")
    kit.swipe:SetAllPoints(slotButton)
    kit.swipe:SetHideCountdownNumbers(true)
    kit.swipe:SetDrawBling(false)
    slotButton:SetDurationCooldown(kit.swipe)

    -- Bar-mode composition. On bar hosts the slot covers the bar rect: an
    -- opaque backdrop occludes the CC fill and per-tick bar texts underneath
    -- (the iconCover analog), and Blizzard drains the registered StatusBar
    -- while the aura runs (V8b: keeps animating in combat). Alpha-0 until a
    -- bar bind.
    kit.barBackdrop = slotButton:CreateTexture(nil, "BACKGROUND", nil, 2)
    kit.barBackdrop:SetAllPoints(slotButton)
    kit.barBackdrop:SetAlpha(0)
    if slotButton.SetDurationBar then
        kit.barFill = CreateFrame("StatusBar", nil, slotButton)
        kit.barFill:SetAllPoints(slotButton)
        kit.barFill:EnableMouse(false)
        kit.barFill:SetAlpha(0)
        slotButton:SetDurationBar(kit.barFill, {
            interpolation = ST.STATUS_BAR_INTERPOLATION_SMOOTH,
            direction = ST.STATUS_BAR_TIMER_DIRECTION_REMAINING,
        })

        -- Fill effects for the bar aura indicator: alpha pulse on the fill
        -- frame, color shift on the fill texture. Write-once AnimationGroups
        -- (forbidden-subtree rule), configured at bar bind time. The texture
        -- region is materialized here so the VertexColor anim has its target;
        -- later SetStatusBarTexture calls swap the file on the same region.
        kit.barFillPulseAG = kit.barFill:CreateAnimationGroup()
        kit.barFillPulseAG:SetLooping("BOUNCE")
        kit.barFillPulseAnim = kit.barFillPulseAG:CreateAnimation("Alpha")
        kit.barFillPulseAnim:SetFromAlpha(1.0)
        kit.barFillPulseAnim:SetToAlpha(0.3)
        kit.barFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        local fillTex = kit.barFill:GetStatusBarTexture()
        -- Creation-time ref, reused at every bind: registered regions are
        -- write-only once the slot exists (PTR 7 stamps initial secrets at
        -- creation), so bind-time code must not call getters on barFill.
        -- Later SetStatusBarTexture(file) calls swap the file on this same
        -- region (already load-bearing for the VertexColor anim target).
        kit.barFillTexture = fillTex
        kit.barFillCsAG = fillTex:CreateAnimationGroup()
        kit.barFillCsAG:SetLooping("BOUNCE")
        kit.barFillCsAnim = kit.barFillCsAG:CreateAnimation("VertexColor")
    end

    -- Stack fill (tracker C2): a second StatusBar Blizzard drives with the
    -- secret application count. Registered at creation with a placeholder
    -- max of 1 — ALWAYS a number: ApplyApplicationBar runs math.max(max, 1),
    -- so a nil errors inside Blizzard's refresh and freezes the display.
    -- Every bar bind whose entry resolves a stacking max RE-CALLS
    -- SetApplicationBar with that max (the C9 SetDurationText per-bind
    -- pattern; legal again on PTR 7 per V23, probe-gated for ApplicationBar
    -- by the v24 retest). Separator stripes and capacity blocks are fixed
    -- pools sized to the atlas cap — the bound max varies per bind now, and
    -- regions can only be created here (write-once subtree).
    if slotButton.SetApplicationBar then
        kit.stackFill = CreateFrame("StatusBar", nil, slotButton)
        kit.stackFill:SetAllPoints(slotButton)
        kit.stackFill:EnableMouse(false)
        kit.stackFill:SetAlpha(0)
        slotButton:SetApplicationBar(kit.stackFill, { maxApplications = 1 })
        -- CC-side memo of the last max written (registered regions are
        -- write-only; the next bind decides from this, never a read-back).
        kit.stackFillMax = 1

        kit.stackFillPulseAG = kit.stackFill:CreateAnimationGroup()
        kit.stackFillPulseAG:SetLooping("BOUNCE")
        kit.stackFillPulseAnim = kit.stackFillPulseAG:CreateAnimation("Alpha")
        kit.stackFillPulseAnim:SetFromAlpha(1.0)
        kit.stackFillPulseAnim:SetToAlpha(0.3)
        kit.stackFill:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        local stackFillTex = kit.stackFill:GetStatusBarTexture()
        -- Creation-time ref, same rule as kit.barFillTexture.
        kit.stackFillTexture = stackFillTex
        kit.stackFillCsAG = stackFillTex:CreateAnimationGroup()
        kit.stackFillCsAG:SetLooping("BOUNCE")
        kit.stackFillCsAnim = kit.stackFillCsAG:CreateAnimation("VertexColor")

        kit.stackSegments = {}
        for i = 1, ST.STACK_SEGMENT_ATLAS_MAX - 1 do
            local tex = kit.stackFill:CreateTexture(nil, "OVERLAY")
            tex:SetAlpha(0)
            kit.stackSegments[i] = tex
        end
        -- Same background layer + sublayer as the barBackdrop slab these
        -- replace in widget mode.
        kit.stackBgBlocks = {}
        for i = 1, ST.STACK_SEGMENT_ATLAS_MAX do
            local tex = slotButton:CreateTexture(nil, "BACKGROUND", nil, 2)
            tex:SetAlpha(0)
            kit.stackBgBlocks[i] = tex
        end
        -- Per-block border rings (each stack is its own widget — owner
        -- ruling): above the fill and the separator stripes.
        kit.stackBlockBorders = {}
        for i = 1, ST.STACK_SEGMENT_ATLAS_MAX do
            local set = {}
            for edge = 1, 4 do
                local tex = kit.stackFill:CreateTexture(nil, "OVERLAY", nil, 2)
                tex:SetAlpha(0)
                set[edge] = tex
            end
            kit.stackBlockBorders[i] = set
        end
    end

    -- Bar shell composition (show-only-while-active bar entries): the bar's
    -- icon square carries its own background and border ring, so the kit
    -- needs a second replica set beside kit.bg/kit.border.
    kit.iconBg = slotButton:CreateTexture(nil, "BACKGROUND", nil, 1)
    kit.iconBg:SetAlpha(0)
    kit.iconBorder = {}
    for i = 1, 4 do
        local tex = slotButton:CreateTexture(nil, "OVERLAY")
        tex:SetAlpha(0)
        kit.iconBorder[i] = tex
    end

    -- Aura active glow: shares the slot's Blizzard-driven visibility, so it
    -- glows exactly while the aura runs. Animated styles are AnimationGroup-
    -- driven (P3: they keep playing on the forbidden subtree in combat).
    -- Above the swipe, below the texts.
    kit.glow = ST._BuildKitGlowRegions(slotButton)
    kit.glow.host:SetFrameLevel(kit.swipe:GetFrameLevel() + 1)

    kit.textOverlay = CreateFrame("Frame", nil, slotButton)
    kit.textOverlay:SetAllPoints(slotButton)
    kit.textOverlay:SetFrameLevel(kit.swipe:GetFrameLevel() + 2)

    -- Initial registration with no options = stock Blizzard formatting.
    -- Marker binds re-call SetDurationText with per-spell options at bind
    -- time (StyleSlotKit; V23 PTR 7 — re-calls outside initializeFrame are
    -- legal again), so nothing CC-owned is registered here.
    kit.durationText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.durationText:SetPoint("BOTTOM", slotButton, "BOTTOM", 0, 1)
    slotButton:SetDurationText(kit.durationText)

    kit.stackText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    kit.stackText:SetPoint("TOPRIGHT", slotButton, "TOPRIGHT", -1, -1)
    slotButton:SetApplicationCount(kit.stackText)

    -- Bar name replica: the bar backdrop occludes the CC name text along with
    -- everything else on the bar, so the kit re-renders the entry name.
    -- CC-authored, bind-time text (live aura names via SetSpellName are an
    -- unvalidated future option). The template is a base font only: SetText
    -- errors on a FontString with no font, and icon-host binds clear the text
    -- before ApplyFontStyle ever runs (bar binds restyle it).
    kit.barNameText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.barNameText:SetAlpha(0)

    -- Keybind replica (icon shells): show-only-while-active entries hide CC's
    -- overlayFrame — and CC can't re-show it with aura state (secret in
    -- combat) — so the kit re-renders the keybind text while the aura display
    -- is the whole visible button. Base font template only; styled at bind.
    kit.keybindText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.keybindText:SetAlpha(0)

    return kit
end

-- Position contract for the aura duration text: it shares the Cooldown Text
-- position unless separateTextPositions switches it to the aura keys. Shared
-- with the config preview, which renders a CC-side stand-in FontString from
-- the same keys (the preview never touches the aura slot subtree).
function CooldownCompanion:GetAuraDurationTextPlacement(style)
    style = style or {}
    if style.separateTextPositions == true then
        return style.auraTextAnchor or "TOPLEFT", style.auraTextXOffset or 2, style.auraTextYOffset or -2
    end
    return style.cooldownTextAnchor or "CENTER", style.cooldownTextXOffset or 0, style.cooldownTextYOffset or 0
end

-- Blizzard-style aura swipe preset (pre-12.1 parity): the bright highlight
-- overlay Blizzard draws for tracked auras, rendered in aura display time.
local BLIZZARD_AURA_SWIPE_TEXTURE = "Interface\\HUD\\UI-HUD-CoolDownManager-Icon-Swipe"
local BLIZZARD_AURA_SWIPE_TEX_LOW = { x = 0.15, y = 0.15 }
local BLIZZARD_AURA_SWIPE_TEX_HIGH = { x = 0.85, y = 0.85 }
-- Solid-fill restore texture: CooldownFrameTemplate's default swipe is a
-- file-less solid color, which SetSwipeTexture cannot return to directly;
-- a white fill under the black swipe color renders identically.
local DEFAULT_SWIPE_TEXTURE = "Interface\\Buttons\\WHITE8X8"
local DEFAULT_SWIPE_TEX_LOW = { x = 0, y = 0 }
local DEFAULT_SWIPE_TEX_HIGH = { x = 1, y = 1 }

-- Duration swipe styling: draw flags and colors from the aura swipe keys,
-- mirroring the CC cooldown swipe's ApplyDefaultCooldownSwipeStyle semantics.
-- Shared with the config preview, which styles a CC-side stand-in Cooldown
-- widget from the same keys (the preview never touches the aura slot subtree).
function CooldownCompanion:ApplyAuraDurationSwipeStyle(swipe, style)
    style = style or {}
    local swipeEnabled = style.showAuraDurationSwipe ~= false

    if swipeEnabled and style.auraUseBlizzardSwipe == true then
        -- Fixed preset: the normal swipe settings below do not apply.
        swipe:SetUseAuraDisplayTime(true)
        swipe:SetDrawSwipe(true)
        swipe:SetDrawEdge(false)
        swipe:SetReverse(false)
        swipe:SetSwipeTexture(BLIZZARD_AURA_SWIPE_TEXTURE, 1, 1, 1, 1)
        swipe:SetSwipeColor(1, 0.95, 0.57, 0.7)
        swipe:SetTexCoordRange(BLIZZARD_AURA_SWIPE_TEX_LOW, BLIZZARD_AURA_SWIPE_TEX_HIGH)
        return
    end

    local fillEnabled = style.showAuraDurationSwipeFill ~= false
    local edgeEnabled = style.showAuraDurationSwipeEdge ~= false
    swipe:SetUseAuraDisplayTime(false)
    swipe:SetSwipeTexture(DEFAULT_SWIPE_TEXTURE, 1, 1, 1, 1)
    swipe:SetTexCoordRange(DEFAULT_SWIPE_TEX_LOW, DEFAULT_SWIPE_TEX_HIGH)
    swipe:SetDrawSwipe(swipeEnabled and fillEnabled)
    swipe:SetDrawEdge(swipeEnabled and edgeEnabled)
    swipe:SetReverse(swipeEnabled and style.auraDurationSwipeReverse ~= false)
    swipe:SetSwipeColor(0, 0, 0, style.auraDurationSwipeAlpha or 0.8)
    local edgeColor = style.auraDurationSwipeEdgeColor
    swipe:SetEdgeColor(edgeColor and edgeColor[1] or 1, edgeColor and edgeColor[2] or 1,
        edgeColor and edgeColor[3] or 1, edgeColor and edgeColor[4] or 1)
end

-- Parity predicate (pre-12.1 ShouldUseActiveAuraIcon): standalone and passive
-- entries always show the live aura icon (Blizzard writes the aura instance's
-- icon, so snapshot-empowered DoT icons flip in combat); ordinary entries opt
-- in via auraShowAuraIcon.
local function ShouldShowAuraIcon(buttonData)
    return buttonData.auraShowAuraIcon == true
        or buttonData.addedAs == "aura"
        or buttonData.isPassive == true
end

------------------------------------------------------------------------
-- True-widget stack rendering (tracker C2, owner ruling): standalone aura
-- entries in stack mode render per-stack blocks with genuinely empty gaps.
-- The fill uses a bundled block atlas — StatusBars CROP their texture as
-- they fill (they don't stretch it), so Blizzard's secret-driven fill
-- reveals whole blocks one stack at a time. Capacity blocks are plain
-- CC-drawn textures laid out with the SAME proportions as the atlas so the
-- two always align; BarMode draws an identical set under the kit for the
-- aura-down state.
------------------------------------------------------------------------

ST.STACK_SEGMENT_GAP_RATIO = 10 / 512 -- baked into the atlas artwork
ST.STACK_SEGMENT_ATLAS_MAX = 20

function ST.GetStackSegmentsTexture(max)
    return "Interface\\AddOns\\CooldownCompanion\\Media\\stack-segments-" .. max .. ".tga"
end

-- Lay out `max` capacity blocks over `host` with the atlas proportions.
-- Forced opaque like the bar backdrop: a translucent block would let the
-- layer underneath bleed through while the aura display is occluding it.
function ST.LayoutStackBlocks(blocks, host, max, vertical, color)
    local length = vertical and host:GetHeight() or host:GetWidth()
    if length <= 0 then
        ST.HideStackBlocks(blocks)
        return
    end
    local gap = length * ST.STACK_SEGMENT_GAP_RATIO
    local blockLen = (length - (max - 1) * gap) / max
    for i, tex in ipairs(blocks) do
        if i <= max then
            local start = (i - 1) * (blockLen + gap)
            tex:SetColorTexture(color[1] or 0.1, color[2] or 0.1, color[3] or 0.1, 1)
            tex:ClearAllPoints()
            if vertical then
                -- VERTICAL fills bottom-up; blocks stack from the bottom.
                tex:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 0, start)
                tex:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 0, start)
                tex:SetHeight(blockLen)
            else
                tex:SetPoint("TOPLEFT", host, "TOPLEFT", start, 0)
                tex:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", start, 0)
                tex:SetWidth(blockLen)
            end
            tex:SetAlpha(1)
        else
            tex:SetAlpha(0)
        end
    end
end

function ST.HideStackBlocks(blocks)
    if not blocks then return end
    for _, tex in ipairs(blocks) do
        tex:SetAlpha(0)
    end
end

-- Per-stack widget borders (owner ruling 2026-07-24): each capacity block
-- carries its own border ring so a stack-mode bar reads as N separate bar
-- widgets — the whole-bar border ring is suppressed for these entries
-- (one ring around all stacks was the look the ruling rejected). Rings are
-- drawn INSIDE each block's rect (ST.EDGE_ANCHOR_SPEC geometry, same as
-- every CC border), overlapping the fill edge from an overlay layer, so the
-- block/atlas proportions are untouched and the gaps stay genuinely empty.
-- borderSets[i] = 4 edge textures for block i; pools follow their block
-- pools. Alpha-driven (kit convention), styled from the same border keys as
-- the ring they replace.
function ST.LayoutStackBlockBorders(borderSets, blocks, max, style)
    if not borderSets then return end
    local size = style.borderSize or ST.DEFAULT_BORDER_SIZE
    local mode = ST.GetEffectiveBorderRenderMode(ST.GetBorderRenderMode(style), nil, size)
    local color = style.borderColor or { 0, 0, 0, 1 }
    local shown = ST.IsCrispBorderRenderMode(mode) or size > 0
    for i, set in ipairs(borderSets) do
        if shown and i <= max and blocks[i] then
            ST.PositionBorderTexturesBetween(set, blocks[i], blocks[i], size, mode)
            for _, tex in ipairs(set) do
                tex:SetColorTexture(color[1] or 0, color[2] or 0, color[3] or 0, color[4] or 1)
                tex:SetAlpha(1)
            end
        else
            for _, tex in ipairs(set) do
                tex:SetAlpha(0)
            end
        end
    end
end

function ST.HideStackBlockBorders(borderSets)
    if not borderSets then return end
    for _, set in ipairs(borderSets) do
        for _, tex in ipairs(set) do
            tex:SetAlpha(0)
        end
    end
end

-- Shared styling for whichever bar fill carries a bar bind — the duration
-- fill and the stack fill are visually identical; only the Blizzard-side
-- driver differs. fillTex is the creation-captured status-bar texture
-- region (registered regions are write-only — GetStatusBarTexture at bind
-- time is banned). While color-shifting, the base color stays white so the
-- VertexColor animation owns the full color range (same trick as the kit
-- border colorShift). fillTexture/rotates override the user bar texture
-- for the widget-stack atlas (rotated so vertical bars keep the blocks).
local function StyleActiveBarFill(fill, fillTex, pulseAG, pulseAnim, csAG, csAnim, button, style, fillTexture, rotates)
    local auraColor = style.barAuraColor or { 0.2, 1.0, 0.2, 1.0 }
    fill:SetOrientation(button._isVertical and "VERTICAL" or "HORIZONTAL")
    fill:SetReverseFill(style.barReverseFill or false)
    fill:SetRotatesTexture(rotates == true)
    fill:SetStatusBarTexture(fillTexture or CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
    fill:SetAlpha(1)
    fill:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1)

    pulseAG:Stop()
    csAG:Stop()
    fillTex:SetVertexColor(1, 1, 1, 1)
    local indicatorOn = ST.IsBarAuraIndicatorEnabled(style)
    if indicatorOn and style.barAuraPulseEnabled then
        pulseAnim:SetDuration(style.barAuraPulseSpeed or 0.5)
        pulseAG:Play()
    end
    if indicatorOn and style.barAuraColorShiftEnabled then
        fill:SetStatusBarColor(1, 1, 1, auraColor[4] or 1)
        local shift = style.barAuraColorShiftColor or { 1, 1, 1, 1 }
        csAnim:SetStartColor(CreateColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1))
        csAnim:SetEndColor(CreateColor(shift[1], shift[2], shift[3], shift[4] or 1))
        csAnim:SetDuration(style.barAuraColorShiftSpeed or 0.5)
        csAG:Play()
    end
end

local function RestBarFill(fill, fillTex, pulseAG, csAG)
    pulseAG:Stop()
    csAG:Stop()
    fillTex:SetVertexColor(1, 1, 1, 1)
    fill:SetAlpha(0)
end

-- Segment separators: backdrop-colored stripes at each stack boundary so the
-- fill reads as "N of max" at a glance. Stacks are whole numbers, so the
-- Blizzard fill edge always lands exactly on a boundary — a stripe centered
-- there is pixel-equivalent to live's true per-segment gaps. Stripe width is
-- the per-button segment gap (0 = solid fill). Pixel positions come from the
-- host statusBar (CC-owned geometry, valid at bind time; geometry restyles
-- always re-request a rebind). The stripe pool is sized to the atlas cap;
-- a larger bound max runs continuous (fill alone still reads correctly).
local function StyleStackSegments(kit, button, buttonData, style, boundMax, shown)
    local segments = kit.stackSegments
    if not segments then return end
    local vertical = button._isVertical
    local host = button.statusBar or button
    local length = vertical and host:GetHeight() or host:GetWidth()
    local gap = CooldownCompanion:GetBarPanelAuraSegmentGap(buttonData)
    if not shown or length <= 0 or gap <= 0
        or not boundMax or boundMax - 1 > #segments then
        for _, tex in ipairs(segments) do
            tex:SetAlpha(0)
        end
        return
    end
    local bg = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
    for i, tex in ipairs(segments) do
        if i < boundMax then
            tex:SetColorTexture(bg[1] or 0.1, bg[2] or 0.1, bg[3] or 0.1, 1)
            tex:ClearAllPoints()
            local offset = length * i / boundMax
            if vertical then
                -- VERTICAL fills bottom-up; boundaries measure from the bottom.
                tex:SetHeight(gap)
                tex:SetPoint("LEFT", kit.stackFill, "BOTTOMLEFT", 0, offset)
                tex:SetPoint("RIGHT", kit.stackFill, "BOTTOMRIGHT", 0, offset)
            else
                tex:SetWidth(gap)
                tex:SetPoint("TOP", kit.stackFill, "TOPLEFT", offset, 0)
                tex:SetPoint("BOTTOM", kit.stackFill, "BOTTOMLEFT", offset, 0)
            end
            tex:SetAlpha(1)
        else
            tex:SetAlpha(0)
        end
    end
end

-- Widget-stack eligibility for the CURRENT bind: a SEGMENTED stack-mode
-- bind on a standalone aura entry whose max fits the block atlas.
-- Continuous-style binds and spell-entry stack binds use the plain-bar /
-- painted-divider rendering.
local function IsWidgetStackBind(slot, buttonData)
    local kit = slot.kit
    return kit ~= nil and kit.stackFill ~= nil and kit.stackBgBlocks ~= nil
        and slot.boundStackMax ~= nil
        and slot.boundStackMax <= ST.STACK_SEGMENT_ATLAS_MAX
        and buttonData.addedAs == "aura"
        and CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData) == "segmented"
end

------------------------------------------------------------------------
-- Pandemic marker + color (tracker C9): per-spell SetDurationText options
-- on the kit's duration text. The marker is a breakpoint format suffix
-- ("4 s !!") below the threshold (V15/V21); pandemic color is a Blizzard-
-- evaluated color curve over the whole text (V14 PTR 7 — the real,
-- combat-legal pandemic color) or baked |cff escapes for marker-only
-- coloring. Every bind RE-CALLS SetDurationText on the creation-captured
-- fontstring — legal again on PTR 7 (V23) and structurally OOC in the
-- rebind pass; non-marker binds pass no options, which resets the binding
-- to stock Blizzard default formatting. Blizzard evaluates everything
-- against the secret remaining time; CC only bakes static per-spell data.
-- Threshold: fixed 30% of base duration via the V22 static lookup.
-- Fragile surface — froze displays on PTR 5; retest each build (tracker
-- B1/B2), kill switch = style.pandemicMarkerEnabled.
------------------------------------------------------------------------

local PANDEMIC_FRACTION = 0.3
local PANDEMIC_MARKER_MAX_LEN = 8

local DURATION_ROUND_DOWN = Enum.NumericRuleFormatRounding
    and Enum.NumericRuleFormatRounding.Down or 2

-- Effective per-entry enable: the explicit per-button setting wins; the
-- auto default is on for target debuffs (where pandemic refresh lives)
-- and off for player buffs. style.pandemicMarkerEnabled is the group-wide
-- kill switch.
local function IsPandemicMarkerWanted(buttonData, style, unit)
    if style.pandemicMarkerEnabled == false then return false end
    if buttonData.pandemicMarker ~= nil then
        return buttonData.pandemicMarker == true
    end
    return unit == "target"
end

-- The marker is user text embedded in a format string: pipes would corrupt
-- the baked color escapes and '%' would read as a format specifier, so both
-- are stripped rather than escaped.
local function SanitizePandemicMarkerText(text)
    text = tostring(text or ""):gsub("[|%%]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    return text:sub(1, PANDEMIC_MARKER_MAX_LEN)
end

-- V22: GetAuraBaseDuration requires a live aura instance as an anchor, but
-- the spellID override drives the answer — ANY readable player aura serves.
-- OOC-only by the rebind pass's structural guarantee. Nil when no anchor
-- aura exists this pass; the threshold stays uncomputed until a later
-- rebind (marker silently absent, default formatting).
local function FindPlayerAuraAnchorInstanceID()
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then return nil end
        if not issecretvalue(aura) and aura.auraInstanceID then
            return aura.auraInstanceID
        end
    end
    return nil
end

-- First candidate aura ID that reports a real duration wins: cast-spell IDs
-- whose aura lives on a linked spell return 0 (V22: Rake), and permanent
-- auras have no duration — both mean "no pandemic window on this ID".
local function GetPandemicBaseDuration(buttonData)
    local anchorID = FindPlayerAuraAnchorInstanceID()
    if not anchorID then return nil end
    local candidates = CooldownCompanion:GetOrderedAuraCandidateSpellIDs(buttonData)
    for _, spellID in ipairs(candidates) do
        if C_Spell.DoesSpellExist(spellID) then
            local duration = C_UnitAuras.GetAuraBaseDuration("player", anchorID, spellID)
            if duration and not issecretvalue(duration) and duration > 0 then
                return duration
            end
        end
    end
    return nil
end

local function PandemicColorEscape(color)
    local r = math.floor((color and color[1] or 1) * 255 + 0.5)
    local g = math.floor((color and color[2] or 0.5) * 255 + 0.5)
    local b = math.floor((color and color[3] or 0) * 255 + 0.5)
    return ("|cff%02x%02x%02x"):format(r, g, b)
end

local function AppendLongDurationBreakpoints(list)
    list[#list + 1] = {
        threshold = 91,
        format = "%.0f m",
        components = { { div = 60, step = 1, rounding = DURATION_ROUND_DOWN } },
    }
    list[#list + 1] = {
        threshold = 5401,
        format = "%.0f h",
        components = { { div = 3600, step = 1, rounding = DURATION_ROUND_DOWN } },
    }
end

-- Marker formatter for one bind: the number keeps the default "%d s" form
-- on both sides of the threshold — only the marker distinguishes the
-- pandemic window. Marker-only coloring is baked escapes (V21); in whole-
-- text mode the marker stays plain so the curve colors number and marker
-- together.
local function BuildPandemicMarkerFormatter(threshold, marker, style)
    local below
    if (style.pandemicMarkerColorMode or "marker") == "marker" then
        below = "%d s " .. PandemicColorEscape(style.pandemicMarkerColor) .. marker .. "|r"
    else
        below = "%d s " .. marker
    end
    local list = {
        { threshold = 0, step = 1, rounding = DURATION_ROUND_DOWN, format = below },
        { threshold = threshold, step = 1, rounding = DURATION_ROUND_DOWN, format = "%d s" },
    }
    -- Long-duration brackets only when they keep the list ascending (a
    -- pandemic threshold above 90s means a 5min+ aura; raw seconds above it
    -- is an accepted cosmetic edge).
    if threshold < 91 then
        AppendLongDurationBreakpoints(list)
    end
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    formatter:SetBreakpoints(list)
    return formatter
end

-- Hard color cut at the threshold (owner ruling: instant switch); the 0.1s
-- ramp is the V14-proven near-step construction. The curve owns the WHOLE
-- fontstring while bound, so its above-threshold segment carries the
-- user's own aura text color — and the fontstring's static color is
-- forced white at bind so the curve's colors render unmodulated.
local function BuildPandemicColorCurve(threshold, style)
    local p = style.pandemicMarkerColor or { 1, 0.5, 0, 1 }
    local n = style.auraTextFontColor or { 1, 1, 1, 1 }
    local curve = C_CurveUtil.CreateColorCurve()
    curve:AddPoint(threshold, CreateColor(p[1] or 1, p[2] or 0.5, p[3] or 0, p[4] or 1))
    curve:AddPoint(threshold + 0.1, CreateColor(n[1] or 1, n[2] or 1, n[3] or 1, n[4] or 1))
    return curve
end

-- SetDurationText options for one marker bind; nil when there is nothing
-- to render (empty marker without whole-text coloring). With an empty
-- marker in whole-text mode the options are curve-only: stock Blizzard
-- formatting, pandemic-colored.
local function BuildPandemicDurationOptions(baseDuration, style)
    local threshold = baseDuration * PANDEMIC_FRACTION
    local marker = SanitizePandemicMarkerText(style.pandemicMarkerText or "!!")
    local options
    if marker ~= "" then
        options = { textFormatter = BuildPandemicMarkerFormatter(threshold, marker, style) }
    end
    if (style.pandemicMarkerColorMode or "marker") == "whole" then
        options = options or {}
        options.textColor = {
            curve = BuildPandemicColorCurve(threshold, style),
            property = Enum.DurationTextBindingProperty.RemainingDuration,
        }
    end
    return options
end

local function StyleSlotKit(slot, button, buttonData, style)
    local kit = slot.kit
    if not kit then return end
    style = style or {}

    local slotButton = slot.slotButton
    local isBar = button._isBar == true
    local shellEntry = buttonData.hideWhileAuraNotActive == true
    local barIconShown = isBar and style.showBarIcon ~= false and button.icon ~= nil
    local showAuraIcon = ShouldShowAuraIcon(buttonData)

    -- Icon regions cover the slot rect on icon hosts. Bar hosts mount the
    -- slot on the bar rect, so the aura icon and its cover re-anchor onto the
    -- bar's icon square instead (host regions are sanctioned anchor targets;
    -- the duration text has host-anchored since Phase 3). Slots are reused
    -- across entries and modes, so both anchorings reset every bind.
    local iconAnchor = barIconShown and button.icon or slotButton
    kit.auraIcon:ClearAllPoints()
    kit.auraIcon:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    kit.auraIcon:SetPoint("BOTTOMRIGHT", iconAnchor, "BOTTOMRIGHT", 0, 0)
    kit.iconCover:ClearAllPoints()
    kit.iconCover:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    kit.iconCover:SetPoint("BOTTOMRIGHT", iconAnchor, "BOTTOMRIGHT", 0, 0)

    local auraIconShown = showAuraIcon and (not isBar or barIconShown)
    kit.auraIcon:SetAlpha(auraIconShown and 1 or 0)
    -- The cover occludes the CC icon underneath: always on icon hosts; on bar
    -- hosts only when the icon square participates (aura icon swap enabled,
    -- or a shell entry whose hidden CC icon needs the static replica).
    local coverWanted = (not isBar) or (barIconShown and (showAuraIcon or shellEntry))
    local coverShown = false

    -- Occluding cover: the entry's icon, cropped like the CC icon underneath
    -- (read at bind time — CC-owned texture, OOC-safe). Known edge: a combat
    -- icon override (form swap) can't refresh the cover until the next rebind.
    -- The aura icon gets the same crop: Blizzard writes only the texture into
    -- it (SetIconTextureForAura), so bind-time texcoords persist, and slots
    -- are reused across entries so the crop must be reset every bind.
    local ccIcon = button.icon
    if ccIcon and ccIcon.GetTexture and ccIcon:GetTexture() then
        kit.iconCover:SetTexture(ccIcon:GetTexture())
        kit.iconCover:SetTexCoord(ccIcon:GetTexCoord())
        kit.auraIcon:SetTexCoord(ccIcon:GetTexCoord())
        coverShown = coverWanted
    else
        local ApplyIconTexCoord = ST._ApplyIconTexCoord
        if ApplyIconTexCoord then
            ApplyIconTexCoord(kit.iconCover, button:GetWidth(), button:GetHeight())
            ApplyIconTexCoord(kit.auraIcon, button:GetWidth(), button:GetHeight())
        end
        if buttonData.type == "spell" and buttonData.id then
            kit.iconCover:SetTexture(C_Spell.GetSpellTexture(buttonData.id))
            coverShown = coverWanted
        end
    end
    kit.iconCover:SetAlpha(coverShown and 1 or 0)

    -- Aura-active icon tint lives on the aura layer now (the layer IS the
    -- aura-active state); the CC icon keeps its own tint pipeline. With no
    -- aura tint configured, carry the user's base icon tint so the icon
    -- doesn't visibly un-tint whenever an aura activates.
    local tint = style.iconAuraTintEnabled and style.iconAuraTintColor or style.iconTintColor
    local tr = tint and tint[1] or 1
    local tg = tint and tint[2] or 1
    local tb = tint and tint[3] or 1
    local ta = tint and tint[4] or 1
    -- The color's own alpha carries each region's visibility: a 4-arg
    -- SetVertexColor write REPLACES the region alpha through a non-SetAlpha
    -- C path (Phase 2 gotcha), so a plain tint alpha here would resurrect
    -- regions the alpha writes above just hid.
    kit.auraIcon:SetVertexColor(tr, tg, tb, auraIconShown and ta or 0)
    kit.iconCover:SetVertexColor(tr, tg, tb, coverShown and ta or 0)

    -- Inverted passive desaturation ("desaturate while active") desaturates
    -- the aura layer; the default "desaturate while missing" is a static
    -- desaturate on the CC icon (Tracking.lua) that this layer occludes.
    local kitDesat = buttonData.isPassive == true
        and buttonData.invertAuraDesaturationLogic == true
        and not buttonData.neverDesaturate
    kit.auraIcon:SetDesaturated(kitDesat)
    kit.iconCover:SetDesaturated(kitDesat)

    -- Duration/stack text: font/color from the aura text style keys (same
    -- helper the CC texts use), anchored to the HOST BUTTON rect so positions
    -- match the CC-side texts (the slot itself covers only the icon rect).
    -- Position contract (pre-12.1 parity, promised by the config tooltips):
    -- the duration text shares the Cooldown Text position unless the user
    -- enables separateTextPositions, which switches it to the aura keys.
    local ApplyFontStyle = CooldownCompanion.ApplyFontStyle
    if ApplyFontStyle then
        ApplyFontStyle(kit.durationText, style, "auraText")
        ApplyFontStyle(kit.stackText, style, "auraStack")
    end
    kit.durationText:ClearAllPoints()
    kit.stackText:ClearAllPoints()
    if isBar then
        -- Bar texts replicate the CC bar's own placement conventions (the
        -- backdrop occludes the originals): duration text at the bar
        -- time-text spot, stack text against the icon square like the old
        -- aura stack count.
        local cdOffX = style.barCdTextOffsetX or 0
        local cdOffY = style.barCdTextOffsetY or 0
        local timeReverse = style.barTimeTextReverse
        if button._isVertical then
            if timeReverse then
                kit.durationText:SetPoint("BOTTOM", slotButton, "BOTTOM", cdOffX, 3 + cdOffY)
            else
                kit.durationText:SetPoint("TOP", slotButton, "TOP", cdOffX, -3 + cdOffY)
            end
            kit.durationText:SetJustifyH("CENTER")
        else
            if timeReverse then
                kit.durationText:SetPoint("LEFT", slotButton, "LEFT", 3 + cdOffX, cdOffY)
                kit.durationText:SetJustifyH("LEFT")
            else
                kit.durationText:SetPoint("RIGHT", slotButton, "RIGHT", -3 + cdOffX, cdOffY)
                kit.durationText:SetJustifyH("RIGHT")
            end
        end
        kit.durationText:SetAlpha(style.showAuraText ~= false and 1 or 0)
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local stackAnchorTo = barIconShown and button.icon or slotButton
        kit.stackText:SetPoint(asAnchor, stackAnchorTo, asAnchor,
            style.auraStackXOffset or 2, style.auraStackYOffset or 2)
        kit.stackText:SetAlpha(style.showAuraStackText ~= false and 1 or 0)
    else
        local durAnchor, durX, durY = CooldownCompanion:GetAuraDurationTextPlacement(style)
        kit.durationText:SetPoint(durAnchor, button, durAnchor, durX, durY)
        kit.durationText:SetJustifyH("CENTER")
        kit.durationText:SetAlpha(style.showAuraText ~= false and 1 or 0)
        kit.stackText:SetPoint(style.auraStackAnchor or "BOTTOMLEFT",
            button, style.auraStackAnchor or "BOTTOMLEFT",
            style.auraStackXOffset or 2, style.auraStackYOffset or 2)
        kit.stackText:SetAlpha(style.showAuraStackText ~= false and 1 or 0)
    end

    -- Pandemic marker + color (C9): per-bind SetDurationText re-call on the
    -- creation-captured fontstring (V23 PTR 7 — re-calls are legal; this
    -- pass is structurally OOC). Marker binds carry per-spell options; every
    -- other bind re-calls with none, resetting the binding to stock Blizzard
    -- formatting — so slots reused across entries always converge.
    local pandemicOptions
    if style.showAuraText ~= false and IsPandemicMarkerWanted(buttonData, style, slot.unit) then
        local baseDuration = GetPandemicBaseDuration(buttonData)
        if baseDuration then
            pandemicOptions = BuildPandemicDurationOptions(baseDuration, style)
        end
    end
    if pandemicOptions and pandemicOptions.textColor then
        -- White base so the curve's colors render unmodulated (the binding
        -- drives the fontstring's vertex color, which modulates against the
        -- static text color — same trick as the bar colorShift fill).
        kit.durationText:SetTextColor(1, 1, 1, 1)
    end
    slotButton:SetDurationText(kit.durationText, pandemicOptions)

    -- Bar name replica: bind-time entry name in the bar name-text style (the
    -- backdrop occludes CC's name text; a live aura-name override would need
    -- the unvalidated SetSpellName registration).
    kit.barNameText:ClearAllPoints()
    if isBar and (style.showBarNameText ~= false or buttonData.customName) then
        if ApplyFontStyle then
            ApplyFontStyle(kit.barNameText, style, "barName", 10)
        end
        local nameOffX = style.barNameTextOffsetX or 0
        local nameOffY = style.barNameTextOffsetY or 0
        local nameReverse = style.barNameTextReverse
        if button._isVertical then
            if nameReverse then
                kit.barNameText:SetPoint("TOP", slotButton, "TOP", nameOffX, -3 + nameOffY)
            else
                kit.barNameText:SetPoint("BOTTOM", slotButton, "BOTTOM", nameOffX, 3 + nameOffY)
            end
            kit.barNameText:SetJustifyH("CENTER")
        else
            if nameReverse then
                kit.barNameText:SetPoint("RIGHT", slotButton, "RIGHT", -3 + nameOffX, nameOffY)
                kit.barNameText:SetJustifyH("RIGHT")
            else
                kit.barNameText:SetPoint("LEFT", slotButton, "LEFT", 3 + nameOffX, nameOffY)
                kit.barNameText:SetJustifyH("LEFT")
            end
            -- Same-side truncation guard, replicated from CreateBarFrame:
            -- when the visible duration text shares the name's side, pin the
            -- name against it so the two can't overlap. Decided from the
            -- style key CC just wrote the alpha FROM — never read back from a
            -- registered kit region: PTR 7 stamps "initial secrets" into them
            -- at creation (AuraContainerFrameProviders.lua CreateFrame forces
            -- UpdateAuraDisplay), so GetAlpha returns a SECRET number even
            -- OOC and any comparison errors. Registered regions are
            -- write-only from the moment the slot exists.
            if style.barNameTextReverse == style.barTimeTextReverse
                and style.showAuraText ~= false then
                if nameReverse then
                    kit.barNameText:SetPoint("LEFT", kit.durationText, "RIGHT", 4, 0)
                else
                    kit.barNameText:SetPoint("RIGHT", kit.durationText, "LEFT", -4, 0)
                end
            end
        end
        local displayName = buttonData.customName
        if not displayName and buttonData.type == "spell" and buttonData.id then
            -- Same resolution as the CC name text underneath: the live
            -- override spell when one is displayed (bind-time CC field read).
            displayName = C_Spell.GetSpellName(button._displaySpellId or buttonData.id)
        end
        kit.barNameText:SetText(displayName or buttonData.name or "")
        kit.barNameText:SetAlpha(1)
    else
        kit.barNameText:SetText("")
        kit.barNameText:SetAlpha(0)
    end

    -- Duration swipe: Blizzard drives the swipe's cooldown; draw flags and
    -- colors are CC styling and persist across those writes. Bars have no
    -- aura swipe — the draining bar is the timer.
    if isBar then
        kit.swipe:SetDrawSwipe(false)
        kit.swipe:SetDrawEdge(false)
    else
        CooldownCompanion:ApplyAuraDurationSwipeStyle(kit.swipe, style)
    end

    -- Bar composition: opaque backdrop occludes the CC bar underneath
    -- (skipped for shell entries — nothing visible to occlude); Blizzard
    -- drains the registered fill while the aura runs. Color writes carry
    -- their own alpha and only happen in the enabled branch
    -- (SetVertexColor-alpha gotcha: a 4-arg color write after SetAlpha(0)
    -- would resurrect the region).
    if isBar then
        -- Fill mode (tracker C2): a stack-mode bind carries boundStackMax
        -- (resolved by the rebind pass, re-called onto the registered stack
        -- bar before styling); every other bind runs the duration fill.
        -- Exactly one fill is visible per bind. Stack style (live parity):
        -- SEGMENTED standalone aura entries render stacks as true widgets
        -- (owner ruling): capacity blocks with empty gaps + the block-atlas
        -- fill; segmented spell entries keep the painted-divider look (the
        -- CC bar underneath needs the slab); CONTINUOUS renders the plain
        -- bar with no per-stack decoration at all.
        local useStackFill = kit.stackFill ~= nil and slot.boundStackMax ~= nil
        local widgetStack = IsWidgetStackBind(slot, buttonData)
        local segmentedStyle = useStackFill
            and CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData) == "segmented"
        if shellEntry or widgetStack then
            kit.barBackdrop:SetAlpha(0)
        else
            local bg = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
            -- Backdrop alpha forced opaque: a translucent backdrop would let
            -- the CC fill bleed through as the aura bar drains.
            kit.barBackdrop:SetColorTexture(bg[1] or 0.1, bg[2] or 0.1, bg[3] or 0.1, 1)
            kit.barBackdrop:SetAlpha(1)
        end
        if widgetStack then
            -- Block geometry reads the CC statusBar (sanctioned anchor
            -- target + CC-owned width), matching BarMode's block set exactly.
            ST.LayoutStackBlocks(kit.stackBgBlocks, button.statusBar or slotButton,
                slot.boundStackMax, button._isVertical, style.barBgColor or { 0.1, 0.1, 0.1, 0.8 })
            ST.LayoutStackBlockBorders(kit.stackBlockBorders, kit.stackBgBlocks,
                slot.boundStackMax, style)
        else
            ST.HideStackBlocks(kit.stackBgBlocks)
            ST.HideStackBlockBorders(kit.stackBlockBorders)
        end
        if kit.barFill then
            if useStackFill then
                RestBarFill(kit.barFill, kit.barFillTexture, kit.barFillPulseAG, kit.barFillCsAG)
            else
                StyleActiveBarFill(kit.barFill, kit.barFillTexture,
                    kit.barFillPulseAG, kit.barFillPulseAnim,
                    kit.barFillCsAG, kit.barFillCsAnim, button, style)
            end
        end
        if kit.stackFill then
            if useStackFill then
                local atlas = widgetStack and ST.GetStackSegmentsTexture(slot.boundStackMax) or nil
                StyleActiveBarFill(kit.stackFill, kit.stackFillTexture,
                    kit.stackFillPulseAG, kit.stackFillPulseAnim,
                    kit.stackFillCsAG, kit.stackFillCsAnim, button, style,
                    atlas, widgetStack and button._isVertical)
            else
                RestBarFill(kit.stackFill, kit.stackFillTexture, kit.stackFillPulseAG, kit.stackFillCsAG)
            end
        end
        StyleStackSegments(kit, button, buttonData, style, slot.boundStackMax,
            segmentedStyle and not widgetStack)
    else
        kit.barBackdrop:SetAlpha(0)
        ST.HideStackBlocks(kit.stackBgBlocks)
        ST.HideStackBlockBorders(kit.stackBlockBorders)
        if kit.barFill then
            RestBarFill(kit.barFill, kit.barFillTexture, kit.barFillPulseAG, kit.barFillCsAG)
        end
        if kit.stackFill then
            RestBarFill(kit.stackFill, kit.stackFillTexture, kit.stackFillPulseAG, kit.stackFillCsAG)
        end
        StyleStackSegments(kit, button, buttonData, style, nil, false)
    end

    -- Aura active glow: icon hosts style from the auraGlow* keys, bar hosts
    -- from the barAura* keys (whole-bar anchor). Style resolution and the
    -- "none"/enable gates live in the builders; the config preview renders
    -- equivalent visuals CC-side (Glows.lua NormalizeAuraGlowPreviewStyle /
    -- NormalizeBarAuraEffectStyle), never here.
    if isBar then
        ST._StyleKitBarGlowRegions(kit.glow, style, button, true)
    else
        ST._StyleKitGlowRegions(kit.glow, style, button, true)
    end

    -- Full-button composition for show-only-while-active entries: bg + border
    -- replicas anchored to the host frames (pixel-identical to the CC shell).
    -- Bars carry two chrome sets — the bar ring and the icon square's own
    -- background/border — so bar shells style the second replica set too.
    if shellEntry and not isBar then
        kit.bg:ClearAllPoints()
        kit.bg:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)
        kit.bg:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
        local bgColor = style.backgroundColor or { 0, 0, 0, 0.5 }
        kit.bg:SetColorTexture(bgColor[1] or 0, bgColor[2] or 0, bgColor[3] or 0, bgColor[4] or 0.5)
        kit.bg:SetAlpha(1)
        local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
        -- Effective mode, not raw: the profile one-pixel-borders option
        -- promotes CUSTOM to CRISP exactly like ApplyBorderEdgePositions.
        local renderMode = ST.GetEffectiveBorderRenderMode(ST.GetBorderRenderMode(style), nil, borderSize)
        ST.ApplyBorderTexturesBetween(kit.border, button, button,
            style.borderColor or { 0, 0, 0, 1 }, borderSize, renderMode)
        for _, tex in ipairs(kit.border) do
            tex:SetAlpha(1)
        end
        kit.iconBg:SetAlpha(0)
        for _, tex in ipairs(kit.iconBorder) do
            tex:SetAlpha(0)
        end
    elseif shellEntry and isBar then
        local bgColor = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
        local barBounds = button._barBounds or button
        -- CC parity: with the icon square shown the background covers only
        -- the bar area (the square has its own), otherwise the whole button.
        -- Widget-stack shells skip the slab AND the whole-bar border ring —
        -- the capacity blocks laid out above ARE the background, each with
        -- its own border ring (owner ruling: every stack its own widget; a
        -- slab would fill the gaps and one ring would wrap all stacks).
        local bgAnchor = barIconShown and barBounds or button
        local widgetShell = IsWidgetStackBind(slot, buttonData)
        if widgetShell then
            kit.bg:SetAlpha(0)
        else
            kit.bg:ClearAllPoints()
            kit.bg:SetPoint("TOPLEFT", bgAnchor, "TOPLEFT", 0, 0)
            kit.bg:SetPoint("BOTTOMRIGHT", bgAnchor, "BOTTOMRIGHT", 0, 0)
            kit.bg:SetColorTexture(bgColor[1] or 0.1, bgColor[2] or 0.1, bgColor[3] or 0.1, bgColor[4] or 0.8)
            kit.bg:SetAlpha(1)
        end
        local borderSize = style.borderSize or ST.DEFAULT_BORDER_SIZE
        local renderMode = ST.GetEffectiveBorderRenderMode(ST.GetBorderRenderMode(style), nil, borderSize)
        local borderColor = style.borderColor or { 0, 0, 0, 1 }
        if widgetShell then
            for _, tex in ipairs(kit.border) do
                tex:SetAlpha(0)
            end
        else
            ST.ApplyBorderTexturesBetween(kit.border, barBounds, barBounds,
                borderColor, borderSize, renderMode)
            for _, tex in ipairs(kit.border) do
                tex:SetAlpha(1)
            end
        end
        if barIconShown and button._iconBounds then
            kit.iconBg:ClearAllPoints()
            kit.iconBg:SetPoint("TOPLEFT", button._iconBounds, "TOPLEFT", 0, 0)
            kit.iconBg:SetPoint("BOTTOMRIGHT", button._iconBounds, "BOTTOMRIGHT", 0, 0)
            kit.iconBg:SetColorTexture(bgColor[1] or 0.1, bgColor[2] or 0.1, bgColor[3] or 0.1, bgColor[4] or 0.8)
            kit.iconBg:SetAlpha(1)
            ST.ApplyBorderTexturesBetween(kit.iconBorder, button._iconBounds, button._iconBounds,
                borderColor, borderSize, renderMode)
            for _, tex in ipairs(kit.iconBorder) do
                tex:SetAlpha(1)
            end
        else
            kit.iconBg:SetAlpha(0)
            for _, tex in ipairs(kit.iconBorder) do
                tex:SetAlpha(0)
            end
        end
    else
        kit.bg:SetAlpha(0)
        for _, tex in ipairs(kit.border) do
            tex:SetAlpha(0)
        end
        kit.iconBg:SetAlpha(0)
        for _, tex in ipairs(kit.iconBorder) do
            tex:SetAlpha(0)
        end
    end

    -- Keybind replica (icon shells only): same style keys, placement, and
    -- text resolution as CC's own keybindText (IconMode), read at bind time.
    -- Keybind edits are config-time and every restyle re-requests a rebind,
    -- so bind-time reads stay current. Bars keep their CC-side conventions
    -- (bar hosts never showed keybind text).
    local keybindText
    if shellEntry and not isBar and style.showKeybindText then
        keybindText = CooldownCompanion.GetDisplayedKeybindText
            and CooldownCompanion:GetDisplayedKeybindText(buttonData, button._resolvedItemId, button)
    end
    if keybindText and keybindText ~= "" then
        if ApplyFontStyle then
            ApplyFontStyle(kit.keybindText, style, "keybind", 10)
        end
        kit.keybindText:ClearAllPoints()
        local kbAnchor = style.keybindAnchor or "TOPRIGHT"
        kit.keybindText:SetPoint(kbAnchor, button, kbAnchor,
            style.keybindXOffset or -2, style.keybindYOffset or -2)
        kit.keybindText:SetText(keybindText)
        kit.keybindText:SetAlpha(1)
    else
        kit.keybindText:SetText("")
        kit.keybindText:SetAlpha(0)
    end
end

------------------------------------------------------------------------
-- Aura sounds — the compliant aura sound events in 12.1:
-- C_UnitAuras.AddAuraSound (PTR 6 rename of AddAuraAppliedSound, now with
-- applied / stack gained / removed triggers) plays a sound file whenever
-- the spellID's aura hits the trigger on the unit, entirely Blizzard-side
-- (validated in combat). Registered at bind, released at park. Refcounted
-- because entries can share candidate spellIDs (linked-aura sets) and the
-- same trigger + sound.
------------------------------------------------------------------------

local auraSounds = {} -- key -> { id = auraSoundID, count = n }

-- Config event key -> Enum.UnitAuraSoundTrigger name, resolved at
-- registration time (the enum ships with AddAuraSound, which the
-- capability guard below already requires).
local AURA_SOUND_EVENT_TRIGGERS = {
    { eventKey = "onAuraApplied", triggerName = "Added" },
    { eventKey = "onAuraStackGained", triggerName = "ApplicationsIncreased" },
    { eventKey = "onAuraRemoved", triggerName = "Removed" },
}

local function RegisterSlotAuraSounds(slot, buttonData, spellSet)
    if not (C_UnitAuras.AddAuraSound and C_UnitAuras.RemoveAuraSound) then return end
    local keys
    for _, eventInfo in ipairs(AURA_SOUND_EVENT_TRIGGERS) do
        local soundFile, channel = CooldownCompanion:GetAuraSoundFileForButton(buttonData, eventInfo.eventKey)
        if soundFile then
            local trigger = Enum.UnitAuraSoundTrigger[eventInfo.triggerName]
            for spellID in pairs(spellSet) do
                local key = slot.unit .. ":" .. spellID .. ":" .. trigger .. ":" .. soundFile .. ":" .. (channel or "")
                local entry = auraSounds[key]
                if entry then
                    entry.count = entry.count + 1
                else
                    local id = C_UnitAuras.AddAuraSound(trigger, {
                        unitToken = slot.unit,
                        spellID = spellID,
                        soundFileName = soundFile,
                        outputChannel = channel,
                    })
                    if id then
                        entry = { id = id, count = 1 }
                        auraSounds[key] = entry
                    end
                end
                if entry then
                    keys = keys or {}
                    keys[#keys + 1] = key
                end
            end
        end
    end
    slot.auraSoundKeys = keys
end

local function ReleaseSlotAuraSounds(slot)
    local keys = slot.auraSoundKeys
    if not keys then return end
    slot.auraSoundKeys = nil
    for _, key in ipairs(keys) do
        local entry = auraSounds[key]
        if entry then
            entry.count = entry.count - 1
            if entry.count <= 0 then
                auraSounds[key] = nil
                C_UnitAuras.RemoveAuraSound(entry.id)
            end
        end
    end
end

------------------------------------------------------------------------
-- Slot lifecycle
------------------------------------------------------------------------

local function BuildCandidateFilters(unit, spellSet)
    local filters = { includeSpellIDs = spellSet }
    if unit == "target" then
        -- Match today's behavior: only the player's own debuffs.
        filters.isFromPlayerOrPlayerPet = true
    end
    return filters
end

-- The auraLayer is the CC-owned mount point for the display subtree. It (and
-- everything under it) is excluded from every recursive frame sweep via the
-- _ccNoTouch flag; the layer itself is safe to touch, its children are not.
local function EnsureAuraLayer(button)
    local layer = button.auraLayer
    if not layer then
        layer = CreateFrame("Frame", nil, button)
        layer._ccNoTouch = true
        button.auraLayer = layer
    end
    -- Re-anchored every call: idempotent, and frame-relative anchoring tracks
    -- geometry restyles for free. Bar hosts mount the slot on the bar rect
    -- (statusBar is already inset by the border layout, so the CC border ring
    -- stays visible around the aura display).
    local anchorTo = (button._isBar and button.statusBar) or button.icon or button
    layer:ClearAllPoints()
    layer:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", 0, 0)
    layer:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", 0, 0)
    -- Level writes here cascade through the container into the slot subtree
    -- (the engine preserves children's relative levels), which is how bind-
    -- time re-levels reach the slot without ever touching it.
    if button._isBar and button.barTextFrame then
        -- Above barTextFrame (statusBar+20): CC keeps writing cooldown time
        -- text per tick with no way to know an aura is showing, so the kit
        -- backdrop must occlude it. Charge/count text hoists above the kit's
        -- textOverlay (slot+3) to stay readable. UpdateBarStyle re-sets
        -- barTextFrame's level on restyles, and UpdateGroupStyle always
        -- re-requests a rebind, so this ordering re-converges after every
        -- style edit.
        layer:SetFrameLevel(button.barTextFrame:GetFrameLevel() + 1)
        if button.overlayFrame then
            button.overlayFrame:SetFrameLevel(layer:GetFrameLevel() + 10)
        end
    else
        -- Above every configurable button element (LoC sits at baseLevel+7).
        -- ApplyStrataOrder (ButtonFrame/Helpers.lua) keeps these two levels in
        -- sync on restyles: CC's text overlay rides ABOVE the aura display so
        -- count/keybind text stays readable while an aura is showing.
        layer:SetFrameLevel(button:GetFrameLevel() + 8)
        if button.overlayFrame then
            button.overlayFrame:SetFrameLevel(button:GetFrameLevel() + 9)
        end
    end
    return layer
end

-- One display per host button (D-A0 rung (c)): the container is a plain CC
-- frame whose parent is set once at CreateFrame and never changed (only the
-- BUTTONS carry the ChangeParent aspect), and the slot button is anchored
-- inside initializeFrame — the sanctioned setup window — and never moved,
-- re-leveled, or reparented afterwards. The container is pinned to the
-- layer's frame level so the slot lands at layer+1, exactly where the
-- pre-PTR 7 design put it (the ApplyStrataOrder/EnsureAuraLayer overlay
-- coordination is unchanged). Visibility, alpha, and strata all reach the
-- slot through plain parentage; a hidden container is inert (P1a) and
-- re-registers + refreshes itself on show (OnShow_Intrinsic).
local function EnsureDisplay(button, unit)
    local record = displays[button]
    if record then return record end
    local layer = EnsureAuraLayer(button)
    slotCounter = slotCounter + 1
    record = { button = button, key = "cc" .. slotCounter, unit = unit }
    -- Direct calls, no pcall: the TOC pins this client generation, so the
    -- AuraContainer API always exists — a failure here is a real setup error
    -- that must surface, not read as "feature unavailable".
    local container = CreateFrame("AuraContainer", nil, layer, "CustomAuraContainerTemplate")
    container:SetAllPoints(layer)
    container:SetFrameLevel(layer:GetFrameLevel())
    container:SetUnit(unit)
    local slotButton = container:AddAuraSlot(record.key, UNIT_FILTER[unit], {
        candidateFilters = BuildCandidateFilters(unit, { [PARK_SENTINEL[unit]] = true }),
        initializeFrame = function(frame)
            -- The ONLY place the slot button is ever positioned.
            frame:SetAllPoints(container)
            record.kit = BuildSlotKit(frame)
        end,
    })
    if not slotButton then
        CooldownCompanion:Print("Aura slot creation failed.")
        return nil
    end
    record.slotButton = slotButton
    record.container = container
    displays[button] = record
    if unit == "target" then
        EnsureTargetWatcher()
    end
    return record
end

-- Park = sentinel filter swap, nothing else. The slot stays anchored on its
-- host; Blizzard hides an unmatched slot button entirely (V25 Q4), so a
-- parked display renders nothing.
local function ParkDisplay(record)
    record.button._auraSlotHostToken = nil
    if not record.parked then
        record.parked = true
        record.boundEntry = nil
        -- CC-side tag only: parking is container-mutator-only and never
        -- touches the slot subtree, so the registered max stays whatever the
        -- last bind wrote (the fill is alpha-0; the next bind converges it).
        record.boundStackMax = nil
        ReleaseSlotAuraSounds(record)
        record.container:SetAuraSlotCandidateFilters(record.key,
            BuildCandidateFilters(record.unit, { [PARK_SENTINEL[record.unit]] = true }))
    end
end

local function BindDisplay(record, buttonData, spellSet, unit, style, stackBarMax)
    local button = record.button
    local layer = EnsureAuraLayer(button)
    -- Re-pin after the layer's level dance: the cascade keeps the subtree's
    -- relative levels on its own; this heals any drift without ever touching
    -- the slot button.
    record.container:SetFrameLevel(layer:GetFrameLevel())
    if record.unit ~= unit then
        -- Polarity swap (player <-> target): container-level mutators only.
        -- SetAuraSlotFilterString self-refreshes (RebuildAuraParseFilters +
        -- UpdateAllAuras).
        record.container:SetUnit(unit)
        record.container:SetAuraSlotFilterString(record.key, UNIT_FILTER[unit])
        record.unit = unit
        if unit == "target" then
            EnsureTargetWatcher()
        end
    end
    record.container:SetAuraSlotCandidateFilters(record.key, BuildCandidateFilters(unit, spellSet))
    -- Stack fill re-call (tracker C2): converge the registered max to this
    -- bind before styling — always a number (ApplyApplicationBar hazard),
    -- 1 = duration-only bind. Same per-bind re-call pattern as the C9
    -- SetDurationText below (V23 PTR 7 — re-calls are legal again; the
    -- ApplicationBar leg is probe-gated by the v24 retest), structurally
    -- OOC in the rebind pass. Skipped when unchanged: the max is CC-side
    -- state (kit.stackFillMax), never a read-back.
    local kit = record.kit
    if kit and kit.stackFill then
        local wantMax = stackBarMax or 1
        if kit.stackFillMax ~= wantMax then
            record.slotButton:SetApplicationBar(kit.stackFill, { maxApplications = wantMax })
            kit.stackFillMax = wantMax
        end
    end
    -- Set before styling: StyleSlotKit selects the stack fill from this tag.
    record.boundStackMax = stackBarMax
    StyleSlotKit(record, button, buttonData, style)
    -- CC-side capacity blocks sync here too: rebinds are OOC by design, so
    -- this repairs bars whose style pass ran in combat (where the block
    -- helper defers).
    if button._isBar and ST._UpdateBarStackBlocks then
        ST._UpdateBarStackBlocks(button, style)
    end
    RegisterSlotAuraSounds(record, buttonData, spellSet)
    -- Tooltip suppression follows the click-through sweep's recorded motion
    -- state (the sweep itself never reaches the slot subtree). P7-validated.
    record.slotButton:SetMouseMotionEnabled(not button._cdcClickThroughMotion)
    record.parked = nil
    record.boundEntry = buttonData
    -- Combat pool lock: while this button is pooled in combat it may only be
    -- re-acquired for the same entry (GroupFrame.AcquireButtonFromPool).
    button._auraSlotHostToken = buttonData
end

------------------------------------------------------------------------
-- The rebind pass — the single place slot subtrees are touched. Idempotent,
-- coalesced, OOC-only: park everything, then bind every aura-tracking entry
-- currently materialized as a button.
------------------------------------------------------------------------

-- Derive the tracked unit from spell polarity every pass (the anti-cheat gate
-- allows only buffs-on-player and own-debuffs-on-target); the stored auraUnit
-- is a fallback for uncached spells, so config/migration/runtime can't drift.
local function ResolveEntryAuraUnit(self, buttonData)
    local first = self:ResolveAuraSpellID(buttonData)
    if first and C_Spell.DoesSpellExist(first) then
        return C_Spell.IsSpellHarmful(first) and "target" or "player"
    end
    return buttonData.auraUnit == "target" and "target" or "player"
end

-- One combat-defer note per deferral window: config edits made in combat keep
-- applying to CC-side visuals immediately, but the aura display (slot kit)
-- only restyles at the deferred rebind, so the player is told once why the
-- aura visuals lag. Cleared when a rebind actually runs.
local deferNoteShown = false

local function HasBoundSlots(groupId)
    for _, record in pairs(displays) do
        if record.boundEntry then
            if groupId == nil then return true end
            if record.button._groupId == groupId then return true end
        end
    end
    return false
end

local function NoteDeferredConfigEdit(reason, groupId)
    if deferNoteShown then return end
    -- Only config-originated requests note the deferral: "config" is always an
    -- aura settings edit; "style" is any style edit, so it only matters when
    -- the edited group actually has an aura display. Automatic requests defer
    -- silently.
    if reason == "config" or (reason == "style" and HasBoundSlots(groupId)) then
        deferNoteShown = true
        CooldownCompanion:Print("Aura display changes will apply when combat ends.")
    end
end

function RunAuraRebind()
    local self = CooldownCompanion
    if not (self.db and self.groupFrames) then return end
    deferNoteShown = false

    -- Collect wanted bindings from live buttons (icon/bar groups only — text
    -- mode has no compliant aura display; trigger/texture panels lost aura
    -- conditions by design; dormant flags there stay dormant).
    local wanted = {}
    local anyTargetWant = false
    for groupId, frame in pairs(self.groupFrames) do
        local group = self.db.profile.groups[groupId]
        local displayMode = group and (group.displayMode or "icons")
        if (displayMode == "icons" or displayMode == "bars") and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local buttonData = button.buttonData
                if buttonData and buttonData.type == "spell"
                    and (buttonData.auraTracking or buttonData.addedAs == "aura") then
                    local spellSet = self:GetAuraCandidateSpellIDSet(buttonData)
                    if spellSet then
                        local unit = ResolveEntryAuraUnit(self, buttonData)
                        anyTargetWant = anyTargetWant or unit == "target"
                        -- Stack fill (tracker C2): bar hosts only; the max is
                        -- automatic (owner ruling). A nil resolve means "not
                        -- a stacking aura" and the bind falls back to the
                        -- duration fill.
                        local stackBarMax
                        if displayMode == "bars" and self:IsBarPanelAuraStackDisplay(buttonData) then
                            stackBarMax = self:GetAuraStackBarMax(buttonData)
                        end
                        wanted[#wanted + 1] = {
                            button = button,
                            buttonData = buttonData,
                            spellSet = spellSet,
                            unit = unit,
                            style = self:GetEffectiveStyle(group.style, buttonData),
                            stackBarMax = stackBarMax,
                        }
                    end
                end
            end
        end
    end

    -- Authoritative P11 gate: CanRunRebindNow only sees EXISTING target
    -- displays, so the very first target bind could otherwise slip into the
    -- forbidden window (target fighting while the player is OOC). Existing
    -- target displays can't reach here blocked — every caller checks
    -- CanRunRebindNow first — so skipping target wants skips only the
    -- first-bind case; player binds proceed and the armed retry re-runs the
    -- full pass. (Parking below is container-mutator-only and never touches
    -- the slot subtree, so it needs no unit gate.)
    local targetBlocked = anyTargetWant
        and UnitExists("target") and UnitAffectingCombat("target")

    -- Park everything first (also clears host tokens), then bind fresh —
    -- simple and idempotent; runs at config-change frequency, never per tick.
    for _, record in pairs(displays) do
        ParkDisplay(record)
    end
    for _, want in ipairs(wanted) do
        if not (want.unit == "target" and targetBlocked) then
            local record = EnsureDisplay(want.button, want.unit)
            if record then
                BindDisplay(record, want.buttonData, want.spellSet, want.unit,
                    want.style, want.stackBarMax)
            end
        end
    end

    if targetBlocked then
        ArmRebindRetry()
    end
end

rebindDeferFrame:SetScript("OnEvent", function()
    -- Unregister BEFORE running so an error can't leave the events stuck
    -- (FrameAnchoring's combat-defer pattern).
    DisarmRebindRetry()
    pendingRebind = false
    if CanRunRebindNow() then
        -- RunAuraRebind re-arms itself if a first target bind is still blocked.
        RunAuraRebind()
    else
        -- Still blocked (target fighting while we left combat): re-arm; the
        -- target watcher also retries on target changes.
        ArmRebindRetry()
    end
end)

-- Single entry point. OOC requests coalesce into one next-frame pass (group
-- populates arrive once per group on a reload); the timer callback re-checks
-- combat and re-defers if a pull started in between.
function CooldownCompanion:RequestAuraRebind(reason, groupId)
    if not self.db then return end
    if not CanRunRebindNow() then
        NoteDeferredConfigEdit(reason, groupId)
        if pendingRebind then return end
        ArmRebindRetry()
        return
    end
    if rebindQueued then return end
    rebindQueued = true
    C_Timer.After(0, function()
        rebindQueued = false
        if CanRunRebindNow() then
            RunAuraRebind()
        elseif not pendingRebind then
            NoteDeferredConfigEdit(reason, groupId)
            ArmRebindRetry()
        end
    end)
end

-- Read-only status for validation/DevBridge (module state is otherwise local).
function CooldownCompanion:GetAuraDisplayStatus()
    local auraSoundCount = 0
    for _ in pairs(auraSounds) do
        auraSoundCount = auraSoundCount + 1
    end
    local status = { pendingRebind = pendingRebind, auraSounds = auraSoundCount, units = {} }
    status.units.player = { slots = 0, bound = 0, stackBound = 0 }
    status.units.target = { slots = 0, bound = 0, stackBound = 0 }
    for _, record in pairs(displays) do
        local unitStatus = status.units[record.unit]
        if unitStatus then
            unitStatus.slots = unitStatus.slots + 1
            if record.boundEntry then unitStatus.bound = unitStatus.bound + 1 end
            if record.boundStackMax then unitStatus.stackBound = unitStatus.stackBound + 1 end
        end
    end
    return status
end
