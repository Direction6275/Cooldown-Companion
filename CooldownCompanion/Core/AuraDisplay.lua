--[[
    CooldownCompanion - Core/AuraDisplay.lua: 12.1 AuraContainer-based aura
    display (rebuild Phase 1+).

    THE SINGLE-WRITER RULE: this file is the ONLY code in the addon allowed to
    hold or touch aura slot buttons or the regions created under them. Once
    auras are secret, the entire slot subtree is FORBIDDEN to addon
    code — reads and writes both error, an error freezes the display, and
    IsForbidden() does NOT report the state. Safety is structural and uses
    Blizzard's aura-secrecy predicate alongside combat lockdown:
      * All slot work happens in the restriction-gated rebind pass
        (RequestAuraRebind).
      * Slot buttons live under an _ccNoTouch mount: button.auraLayer for
        icon/bar hosts, or the Texture panel's UIParent-level runtime root.
        Frame sweeps never recurse into either flagged frame.
      * While auras are secret the only permitted aura-system calls are container-level
        (UpdateAllAuras, SetAuraSlotCandidateFilters).

    PTR 7 (tracker D-A0): aura buttons carry a permanent ChangeParent
    forbidden aspect — SetParent on a slot button errors even out of combat.
    The display therefore uses ONE AuraContainer PER (HOST BUTTON, UNIT
    TOKEN, HOST KIND) — a host needs more than one only when an entry is
    tracked on several units at once — created beneath that button's
    auraLayer through a plain CC visibility parent (the parent is set at
    CreateFrame and never changed — only the BUTTONS carry the forbidden
    aspects), with the slot button anchored once inside
    initializeFrame and never moved, re-leveled, or reparented afterwards.
    Bind is a container-mutator filter swap. Park is a polarity-crossed
    sentinel filter PLUS container:Hide() — the sentinel is applied inside
    Blizzard's identity gate and stops being applied at all once a unit is not
    assistable, so hiding the container is what actually guarantees a parked
    display renders nothing (and drops it out of the aura event path).
    Host Show/Hide, alpha fades, and strata changes reach the slot through
    plain parentage again, and a re-shown container re-registers its events
    and refreshes itself (AuraContainerPrivateMixin:OnShow_Intrinsic).
    Evidence: docs/12.1-aura-tracking-research.md; validation matrix V1-V18,
    Phase 0 probes P1-P11, and V25 (PTR 7 reparent enforcement).
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AT = ST._AT

local ipairs = ipairs
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local UnitCanAssist = UnitCanAssist
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers
local LayoutTexturePieces = AT.LayoutTexturePieces
local Clamp = AT.Clamp
local NormalizeTextureIndicatorEffect = AT.NormalizeTextureIndicatorEffect
local TEXTURE_INDICATOR_EFFECT_PULSE = AT.TEXTURE_INDICATOR_EFFECT_PULSE
local TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT = AT.TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT
local TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND = AT.TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND
local TEXTURE_INDICATOR_EFFECT_BOUNCE = AT.TEXTURE_INDICATOR_EFFECT_BOUNCE
local MIN_TEXTURE_INDICATOR_SPEED = AT.MIN_TEXTURE_INDICATOR_SPEED
local MAX_TEXTURE_INDICATOR_SPEED = AT.MAX_TEXTURE_INDICATOR_SPEED
local DEFAULT_TEXTURE_INDICATOR_SPEED = AT.DEFAULT_TEXTURE_INDICATOR_SPEED
local DEFAULT_TEXTURE_PULSE_ALPHA = AT.DEFAULT_TEXTURE_PULSE_ALPHA
local DEFAULT_TEXTURE_SHRINK_SCALE = AT.DEFAULT_TEXTURE_SHRINK_SCALE
local DEFAULT_TEXTURE_BOUNCE_PIXELS = AT.DEFAULT_TEXTURE_BOUNCE_PIXELS

-- Parking (P1b/P1c + V25 Q4): slots can never be removed, so an unbound slot is
-- given a sentinel candidate filter that cannot match, and Blizzard hides an
-- unmatched slot button. Empty includeSpellIDs is BANNED — it wedges the slot
-- permanently.
--
-- Sentinels are POLARITY-CROSSED so they are structurally never-match: a
-- HELPFUL slot parked on a debuff spellID (debuffs can never appear in HELPFUL
-- results) and a HARMFUL slot parked on a buff spellID. Hence the keying by
-- POLARITY rather than by unit — polarity stops being derivable from the unit
-- once ally units are tracked, since buffs on you and buffs on a party member
-- are both HELPFUL. Get this wrong and a HELPFUL slot parked on a buff sentinel
-- MATCHES and shows the wrong aura.
--
-- The sentinel is NOT sufficient on its own; see ParkDisplay for why the
-- container is also hidden.
local PARK_SENTINEL = {
    HELPFUL = 155722, -- Rake (a bleed debuff; never matches a HELPFUL filter)
    HARMFUL = 5217,   -- Tiger's Fury (a self buff; never matches a HARMFUL filter)
}

-- The per-unit slot contract: aura polarity (which picks the park sentinel),
-- the filter string handed to Blizzard, and whether the slot is restricted to
-- auras the player cast. One table so the sentinel, the filter string, and the
-- caster filter can never disagree.
--
-- A plain self-buff entry keeps a bare HELPFUL filter on `player` — it tracks
-- buffs from ANY caster (Power Word: Fortitude, Blessing of the Bronze), which
-- is shipped behavior and must not narrow. Group scope is the opposite: it means
-- "my own buff, wherever I put it", so every unit in a group-scoped set carries
-- PLAYER and the isFromPlayerOrPlayerPet candidate filter. That candidate filter
-- is evaluated OUTSIDE Blizzard's identity gate
-- (Blizzard_AuraContainerUtil.lua:85-87), so it is the one restriction that
-- survives when a unit stops being assistable.
local ALLY_CONTRACT = { polarity = "HELPFUL", filter = "HELPFUL|PLAYER", ownOnly = true }
local SLOT_CONTRACT = {
    player = { polarity = "HELPFUL", filter = "HELPFUL", ownOnly = false },
    target = { polarity = "HARMFUL", filter = "HARMFUL|PLAYER", ownOnly = true },
}

-- The contract depends on the ENTRY'S SCOPE as well as the unit, not on the unit
-- alone. It has to: in a party a group-scoped set contains `player`, but in a
-- raid the player is covered by their own raidN index instead
-- (GroupAuraTokens). Keying off the token alone therefore made the same entry
-- match any caster's buff on you in a party and only your own in a raid — the
-- exact narrowing the note above forbids. Scope decides, so all three group
-- sizes agree.
--
-- The unknown-token fallback is deliberate: a token must never yield a nil
-- sentinel, because an empty includeSpellIDs set wedges a slot permanently.
local function SlotContract(unit, groupScoped)
    if groupScoped and unit ~= "target" then
        return ALLY_CONTRACT
    end
    return SLOT_CONTRACT[unit] or ALLY_CONTRACT
end

-- Blizzard applies includeSpellIDs only when the aura's polarity agrees with
-- the unit's current reaction to the player. When that relationship flips
-- (vehicle possession, charm, or a friendly/hostile target transition), an
-- incompatible slot would otherwise accept every aura of its base polarity.
-- Fail closed until the relationship agrees again; the visibility switch is
-- on a CC-owned parent, never on the restricted AuraButton subtree.
local function CanApplySpellIdentityFilter(unit, groupScoped)
    local isAssistable = UnitCanAssist("player", unit) == true
    if SlotContract(unit, groupScoped).polarity == "HELPFUL" then
        return isAssistable
    end
    return not isAssistable
end

local function SetIdentityVisibility(record, shown)
    shown = shown == true
    local changed = record.identityVisible ~= shown
    record.identityVisible = shown
    record.visibilityRoot:SetShown(shown)
    return changed
end

-- Module state. Display records (container + slot + kit) live only here — no
-- slot-button references are ever stored on CC buttons, so no sweep or
-- diagnostic walk can reach the forbidden subtree by accident.
--
-- One record per (host button, unit token). A host needs more than one only
-- when an entry tracks the same aura across several units — an ally-scope
-- entry watching you and each group member — because a container tracks
-- exactly one unit (AuraContainerSharedMixin:SetUnit) and there is no way to
-- ask which one currently holds the aura. Coincident records with mutually
-- exclusive tokens are what make that read as a single display.
--
-- `records` is the iteration list and is append-only: records are permanent
-- (buttons are pooled and never destroyed; slots can never be removed), so
-- nothing is ever taken out of it. Iterate `records`; index `displays` only to
-- find or create a specific (button, unit) pair.
local displays = {}       -- host button -> { [unitToken] = record }
local records = {}        -- flat, append-only list of every record
local slotCounter = 0
local pendingRebind = false
local rebindQueued = false

-- Idle-health counters (2026-08-10 feedback-loop lesson): rebind work runs at
-- config-change frequency, so these climbing on an idle session IS a feedback
-- loop. Read-only, never reset; surfaced in GetAuraDisplayStatus and copied
-- into DevBridge snapshots.
local rebindRequestCount = 0
local rebindPassCount = 0
local lastRebindPassAt = nil

-- A blocked rebind keeps its current bindings intact and retries after player
-- combat. The gates below are player-global combat lockdown and aura secrecy;
-- target and ally combat flags are not part of that contract, so UNIT_FLAGS
-- has no role in this retry path.
local rebindDeferFrame = CreateFrame("Frame")

local function ArmRebindRetry()
    pendingRebind = true
    rebindDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function DisarmRebindRetry()
    rebindDeferFrame:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

------------------------------------------------------------------------
-- Containers
------------------------------------------------------------------------

local targetWatcher
local groupWatcher
local identityWatcher
local RunAuraRebind
local RefreshIdentityVisibilityForToken

-- Custom AuraButtons carry DenyTaintedAccessWhenAurasAreSecret, so use the
-- matching global secrecy predicate. This pass also performs layout/topology
-- writes, which remain gated by combat lockdown. Texture rendering uses the
-- same helper, so keep it O(1).
local function CanRunRebindNow()
    return not InCombatLockdown() and not C_Secrets.ShouldAurasBeSecret()
end

-- Exported for display code that must decide what to draw while no slot is
-- bound yet. A Texture panel's production artwork lives entirely inside the
-- slot kit, so "not bound" means "nothing to show" — and the caller needs to
-- know whether that is a frame-long wait for the queued pass or a wait for the
-- current aura-restriction window, which is far too long to leave the panel dark.
function CooldownCompanion:CanRunAuraRebindNow()
    return CanRunRebindNow()
end

-- The friendly units an ally-scope entry watches, in bind order. Chosen so no
-- two tokens can ever resolve to the SAME person: coincident slots only read as
-- a single display while at most one of them can match.
--
-- In a raid, raid1..raidN ALREADY includes the player's own slot, so "player"
-- must not be added or a self-cast would light two slots at once. In a party,
-- party1..partyN are the other members only — Blizzard's own roster code uses
-- index 0 for "player" (SecureGroupHeaders.lua:290-296) — so "player" is added
-- explicitly. "target" is deliberately absent: it aliases whichever group
-- member happens to be targeted, and would double-draw.
local function GroupAuraTokens()
    local tokens = {}
    if IsInRaid() then
        for index = 1, GetNumGroupMembers() do
            tokens[#tokens + 1] = "raid" .. index
        end
    else
        tokens[1] = "player"
        for index = 1, GetNumSubgroupMembers() do
            tokens[#tokens + 1] = "party" .. index
        end
    end
    -- Never return an empty set: an entry with no tokens would bind nothing and
    -- go silently dark instead of falling back to tracking the aura on you.
    if #tokens == 0 then tokens[1] = "player" end
    return tokens
end

-- Container-level refresh for records whose token may now resolve to a different
-- person. Combat-safe (V13, re-validated V18). Shared by both watchers so a
-- change to the refresh shape can never apply to only one token family.
-- Assigned in the AURA BLOCKS and AURA PANELS sections, where each record list
-- is in scope; the watcher must cover EVERY container family or a target-scoped
-- block or panel keeps the previous target's aura across a same-token swap.
local RefreshBlockRecordsForToken
local RefreshPanelRecordsForToken
-- The relationship-only half of the same coverage rule (see
-- RefreshIdentityVisibilityForToken); assigned in the AURA PANELS section.
local RefreshPanelIdentityVisibilityForToken

local function RefreshRecordsForToken(isMatch)
    local identityChanged
    if RefreshIdentityVisibilityForToken then
        identityChanged = RefreshIdentityVisibilityForToken(isMatch)
    end
    for _, record in ipairs(records) do
        if isMatch(record.unit) then
            record.container:UpdateAllAuras()
        end
    end
    if RefreshBlockRecordsForToken then
        RefreshBlockRecordsForToken(isMatch)
    end
    if RefreshPanelRecordsForToken then
        RefreshPanelRecordsForToken(isMatch)
    end
    return identityChanged
end

local function IsTargetToken(unit) return unit == "target" end
local function IsAllyToken(unit) return unit ~= "player" and unit ~= "target" end

local function EnsureIdentityWatcher()
    if identityWatcher then return end
    identityWatcher = CreateFrame("Frame")
    identityWatcher:RegisterEvent("UNIT_FACTION")
    identityWatcher:SetScript("OnEvent", function(_, _, unit)
        -- A player faction change can alter the player's relationship to
        -- every tracked unit, not just the player token. Blizzard's target
        -- frame follows the same rule when reconfiguring its aura container.
        local refreshUnit = unit
        if unit == "player" then refreshUnit = nil end
        if CooldownCompanion:RefreshAuraIdentityVisibility(refreshUnit) then
            -- A block bucket suppressed by the previous relationship needs a
            -- fresh topology pass before it can rejoin its side's chain.
            CooldownCompanion:RequestAuraRebind("unit-faction")
        end
    end)
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
        if RefreshRecordsForToken(IsTargetToken) then
            CooldownCompanion:RequestAuraRebind("target-reaction")
        end
    end)
end

-- Ally-scope entries derive their token set from group size, so the set changes
-- whenever the roster does — and joining a raid switches the whole set from
-- party* to raid*. Slots can only be created while the aura objects are
-- accessible, so a restricted mid-fight join is covered by the deferred pass,
-- not immediately.
-- Armed from the ENTRY'S OPT-IN, not from ally record creation: while solo a
-- group-scoped entry resolves to { "player" } only, so waiting for a party/raid
-- record meant the watcher never existed and joining a group did nothing until
-- some unrelated rebind happened. GROUP_ROSTER_UPDATE has no other handler in
-- the addon.
local function EnsureGroupWatcher()
    if groupWatcher then return end
    groupWatcher = CreateFrame("Frame")
    groupWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
    groupWatcher:SetScript("OnEvent", function()
        -- Same same-token problem the target watcher solves: raid indices are
        -- roster-ordered, so raidN can start meaning a different person without
        -- the token changing, and the container would keep the old parse.
        -- Container-level call, combat-safe (V13/V18) — the rebind below is
        -- combat-deferred and cannot cover a mid-fight reshuffle.
        RefreshRecordsForToken(IsAllyToken)
        -- Not "config"/"style", so this never prints a combat-defer note.
        CooldownCompanion:RequestAuraRebind("roster")
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

        -- Pandemic fill recolor (PTR 8, Phase 0-validated): a clone texture
        -- riding the duration fill — same file, pandemic color — registered
        -- as a pandemic region so Blizzard reveals it only inside the
        -- refresh window. Anchored at creation to the creation-captured
        -- fill region: the engine resizes that region with the secret
        -- drain, so the clone tracks it. Child of kit.barFill, so
        -- RestBarFill's frame alpha-0 and the fill pulse both carry over.
        -- Own alpha starts 0 (feature defaults off); bar binds dress it.
        if slotButton.AddPandemicRegion then
            kit.pandemicFillClone = kit.barFill:CreateTexture(nil, "ARTWORK", nil, 2)
            kit.pandemicFillClone:SetAllPoints(fillTex)
            kit.pandemicFillClone:SetTexture("Interface\\Buttons\\WHITE8x8")
            kit.pandemicFillClone:SetAlpha(0)
            slotButton:AddPandemicRegion(kit.pandemicFillClone)
        end
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
        -- CC-side memos of the last options written (registered regions are
        -- write-only; the next bind decides from these, never a read-back).
        -- Smoothing (tracker C2 follow-on): stack binds may re-register with
        -- interpolation so Blizzard sweeps the fill between stack counts.
        kit.stackFillMax = 1
        kit.stackFillSmooth = false

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

        -- Stack threshold bands (2026-08-15 program): recolor textures over
        -- the stack fill, created here (write-once subtree) and dressed at
        -- bind time by StyleStackThresholdBands. ARTWORK 1/2: above the
        -- fill texture, below the OVERLAY separator stripes — so painted
        -- gaps stay visible over a band. The max band spans only the FINAL
        -- segment ((max-1)/max onward); where it overlaps the threshold
        -- band on that stretch, the higher sublayer wins by draw order,
        -- never by comparison.
        kit.stackThresholdBand = kit.stackFill:CreateTexture(nil, "ARTWORK", nil, 1)
        kit.stackThresholdBand:SetAlpha(0)
        kit.stackMaxBand = kit.stackFill:CreateTexture(nil, "ARTWORK", nil, 2)
        kit.stackMaxBand:SetAlpha(0)
        -- Widget-bind band mask: the bands are solid textures, so on a
        -- block-atlas fill their span would paint over the atlas's baked
        -- transparent gaps. Both bands share this mask; widget binds dress
        -- it with the SAME block atlas across the full bar (the bands then
        -- render only over block artwork), every other bind dresses it
        -- all-pass white. Created here (write-once subtree), dressed at
        -- bind time by StyleStackThresholdBands.
        kit.stackBandMask = kit.stackFill:CreateMaskTexture()
        kit.stackBandMask:SetTexture("Interface\\Buttons\\WHITE8X8",
            "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        kit.stackBandMask:SetAllPoints(kit.stackFill)
        kit.stackThresholdBand:AddMaskTexture(kit.stackBandMask)
        kit.stackMaxBand:AddMaskTexture(kit.stackBandMask)

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

    -- Pandemic glow (PTR 8, Phase 0-validated): a second glow kit registered
    -- as a pandemic region — Blizzard alone flips its secret Shown state
    -- while the aura sits inside its refresh window; CC styles it at OOC
    -- bind time and never reads it back. Registration is creation-only (no
    -- re-call evidence exists for AddPandemicRegion), so every slot carries
    -- the rig and per-entry enable is style-time "none" (P6). Same level as
    -- the aura glow, created after it, so the pandemic effect draws above.
    if slotButton.AddPandemicRegion then
        -- withCdm: only pandemic rigs carry the CDM-parity region set.
        kit.pandemicGlow = ST._BuildKitGlowRegions(slotButton, true)
        kit.pandemicGlow.host:SetFrameLevel(kit.swipe:GetFrameLevel() + 1)
        -- The CDM rig is a child FRAME of the host; left at its default
        -- level it would TIE kit.textOverlay at swipe+2. Pin it to swipe+1
        -- with every other pandemic style so the texts stay strictly above.
        kit.pandemicGlow.cdm.frame:SetFrameLevel(kit.swipe:GetFrameLevel() + 1)
        slotButton:AddPandemicRegion(kit.pandemicGlow.host)
    end

    kit.textOverlay = CreateFrame("Frame", nil, slotButton)
    kit.textOverlay:SetAllPoints(slotButton)
    kit.textOverlay:SetFrameLevel(kit.swipe:GetFrameLevel() + 2)

    -- Initial registration with no options = stock Blizzard formatting.
    -- Every bind re-calls SetDurationText with the group's Duration Format
    -- options at bind time (StyleSlotKit; V23 PTR 7 — re-calls outside
    -- initializeFrame are legal again), so nothing CC-owned is registered
    -- here.
    kit.durationText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.durationText:SetPoint("BOTTOM", slotButton, "BOTTOM", 0, 1)
    slotButton:SetDurationText(kit.durationText)

    kit.stackText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    kit.stackText:SetPoint("TOPRIGHT", slotButton, "TOPRIGHT", -1, -1)
    slotButton:SetApplicationCount(kit.stackText)

    -- Stack threshold colors: a per-slot NumericRuleFormatter whose
    -- breakpoints the engine compares against the SECRET count when
    -- formatting the stack text (FormatNumber is ConstSecretAccessor — the
    -- comparison never happens in Lua). Created here, mutated at bind time
    -- by ConvergeApplicationCount; the creation registration above stays
    -- formatter-FREE so non-threshold entries keep stock behavior.
    if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter then
        kit.stackFormatter = C_StringUtil.CreateNumericRuleFormatter()
        kit.stackCountFormatterKey = "off"
    end

    -- Bar name replica: the bar backdrop occludes the CC name text along with
    -- everything else on the bar, so the kit re-renders the entry name.
    -- CC-authored, bind-time text (live aura names via SetSpellName are an
    -- unvalidated future option). The template is a base font only: SetText
    -- errors on a FontString with no font, and icon-host binds clear the text
    -- before ApplyFontStyle ever runs (bar binds restyle it).
    kit.barNameText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.barNameText:SetAlpha(0)

    -- Keybind replica (icon shells): show-only-while-active entries hide CC's
    -- pinnedTextFrame, which is where the keybind text lives — and CC can't
    -- re-show it with aura state (secret in combat) — so the kit re-renders
    -- the keybind text while the aura display is the whole visible button.
    -- Base font template only; styled at bind.
    kit.keybindText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.keybindText:SetAlpha(0)

    return kit
end

-- Texture panels keep a permanent copy of their selected artwork beneath
-- AuraButton. Nothing is registered as the aura icon, so Blizzard controls
-- presence visibility without replacing the chosen asset. Every effect is a
-- native AnimationGroup created in this sanctioned setup window: addon code
-- never has to touch the forbidden subtree when the aura changes in combat.
local function BuildTexturePanelSlotKit(slotButton)
    -- The AuraButton lives under UIParent rather than the alpha-zero driver
    -- button, so make it permanently click-through at creation time. The
    -- dedicated Texture record never needs tooltip or cancel-aura input.
    slotButton:SetMouseClickEnabled(false)
    slotButton:SetMouseMotionEnabled(false)

    local visualRoot = CreateFrame("Frame", nil, slotButton)
    visualRoot:SetAllPoints(slotButton)
    visualRoot:SetAlpha(0)

    local host = {
        visualRoot = visualRoot,
        primaryTexture = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1),
        secondaryTexture = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1),
    }

    host.pulseAG = visualRoot:CreateAnimationGroup()
    host.pulseAG:SetLooping("BOUNCE")
    host.pulseAnim = host.pulseAG:CreateAnimation("Alpha")
    host.pulseAnim:SetFromAlpha(1)
    host.pulseAnim:SetToAlpha(DEFAULT_TEXTURE_PULSE_ALPHA)

    host.shrinkAG = visualRoot:CreateAnimationGroup()
    host.shrinkAG:SetLooping("BOUNCE")
    host.shrinkAnim = host.shrinkAG:CreateAnimation("Scale")
    host.shrinkAnim:SetScaleFrom(1, 1)
    host.shrinkAnim:SetScaleTo(DEFAULT_TEXTURE_SHRINK_SCALE, DEFAULT_TEXTURE_SHRINK_SCALE)
    host.shrinkAnim:SetOrigin("CENTER", 0, 0)
    host.shrinkAnim:SetSmoothing("IN_OUT")

    host.bounceAG = visualRoot:CreateAnimationGroup()
    host.bounceAG:SetLooping("BOUNCE")
    host.bounceAnim = host.bounceAG:CreateAnimation("Translation")
    host.bounceAnim:SetSmoothing("OUT")

    host.colorShift = {}
    for index, texture in ipairs({ host.primaryTexture, host.secondaryTexture }) do
        local group = texture:CreateAnimationGroup()
        group:SetLooping("BOUNCE")
        host.colorShift[index] = {
            group = group,
            animation = group:CreateAnimation("VertexColor"),
        }
        host.colorShift[index].animation:SetSmoothing("IN_OUT")
    end

    host.primaryTexture:Hide()
    host.secondaryTexture:Hide()
    return { texturePanelHost = host }
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
    local edgeEnabled = style.auraDurationSwipeEdgeEnabled == true
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

ST.STACK_SEGMENT_GAP_RATIO = 10 / 512 -- the default artwork's baked gap
ST.STACK_SEGMENT_ATLAS_MAX = 30

-- Gap presets ship as separate atlas sets (stack-segments-g<gap>-<max>);
-- the original gap-10 files keep their unsuffixed names.
function ST.GetStackSegmentsTexture(max, gapTexels)
    if gapTexels and gapTexels ~= ST.STACK_BLOCK_GAP_DEFAULT then
        return "Interface\\AddOns\\CooldownCompanion\\Media\\stack-segments-g" .. gapTexels .. "-" .. max .. ".tga"
    end
    return "Interface\\AddOns\\CooldownCompanion\\Media\\stack-segments-" .. max .. ".tga"
end

-- Lay out `max` capacity blocks over `host` with the atlas proportions.
-- Opaque by default like the bar backdrop: a translucent block would let
-- the layer underneath bleed through while the aura display is occluding
-- it. Custom-bar hosts pass `alpha` so their blocks follow the configured
-- background instead — nothing renders beneath them that needs hiding.
-- `alpha = 0` lays the blocks out without drawing them at all, which is how
-- occlusion-free hosts get anchor rects for their per-block border rings
-- while the CC layer underneath supplies the visible background.
-- `length` overrides the measured host extent, for callers that know the
-- size but whose host has not been through a layout pass yet (the config
-- canvas builds its bars and lays out its lanes in the same frame).
function ST.LayoutStackBlocks(blocks, host, max, vertical, color, alpha, length, gapRatio)
    length = length or (vertical and host:GetHeight() or host:GetWidth())
    if length <= 0 then
        ST.HideStackBlocks(blocks)
        return
    end
    local gap = length * (gapRatio or ST.STACK_SEGMENT_GAP_RATIO)
    local blockLen = (length - (max - 1) * gap) / max
    for i, tex in ipairs(blocks) do
        if i <= max then
            local start = (i - 1) * (blockLen + gap)
            tex:SetColorTexture(color[1] or 0.1, color[2] or 0.1, color[3] or 0.1, alpha or 1)
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

    pulseAG:Stop()
    csAG:Stop()
    -- Residual-anim vertex reset BEFORE the color write, never after:
    -- SetStatusBarColor lands on this same fill-texture vertex channel, so
    -- a trailing white reset clobbers the configured color to white (the
    -- aura-pass 1B white-fill bug — bind-time prints proved the correct
    -- color arriving while the fill rendered white).
    fillTex:SetVertexColor(1, 1, 1, 1)
    fill:SetStatusBarColor(auraColor[1], auraColor[2], auraColor[3], auraColor[4] or 1)
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

-- The host rect, in numbers CC owns. Aura-host descriptors stamp
-- _ccKitRectW/H because measuring them is either stale (a freshly anchored
-- holder reports last frame's rect — the lane lesson) or forbidden (a block
-- host lives under a Blizzard-positioned group frame, whose geometry is
-- secret). CC buttons carry neither and measure their own mount rect exactly
-- as before.
local function HostRectSize(button)
    local w, h = button._ccKitRectW, button._ccKitRectH
    if w and h then return w, h end
    local host = button.statusBar or button
    return host:GetWidth(), host:GetHeight()
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
    local rectW, rectH = HostRectSize(button)
    local length = vertical and rectH or rectW
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

-- Stack threshold bands (2026-08-15 program): recolor the portion of the
-- stack fill beyond a stack boundary. Geometry is engine-driven: the fixed
-- edge sits at the boundary (a static offset from CC-owned geometry at bind
-- time), the moving edge anchors to the creation-captured fill texture
-- region, which the ENGINE resizes with the SECRET count (the
-- pandemicFillClone precedent). Below the boundary the rect has crossed
-- anchors and renders nothing; the count is never read in Lua. On
-- widget/block binds the shared kit.stackBandMask wears the block atlas,
-- so the solid bands render per block and the baked gaps stay genuinely
-- empty; the OVERLAY separator stripes and block rings draw above the
-- bands.
local function DressStackThresholdBand(band, kit, button, style, boundMax, atStack, color, length)
    local off = length * (atStack - 1) / boundMax
    local vertical = button._isVertical
    local reverse = style.barReverseFill or false
    band:ClearAllPoints()
    if vertical then
        if reverse then
            band:SetPoint("TOPLEFT", kit.stackFill, "TOPLEFT", 0, -off)
            band:SetPoint("BOTTOMRIGHT", kit.stackFillTexture, "BOTTOMRIGHT", 0, 0)
        else
            band:SetPoint("BOTTOMLEFT", kit.stackFill, "BOTTOMLEFT", 0, off)
            band:SetPoint("TOPRIGHT", kit.stackFillTexture, "TOPRIGHT", 0, 0)
        end
    else
        if reverse then
            band:SetPoint("TOPRIGHT", kit.stackFill, "TOPRIGHT", -off, 0)
            band:SetPoint("BOTTOMLEFT", kit.stackFillTexture, "BOTTOMLEFT", 0, 0)
        else
            band:SetPoint("TOPLEFT", kit.stackFill, "TOPLEFT", off, 0)
            band:SetPoint("BOTTOMRIGHT", kit.stackFillTexture, "BOTTOMRIGHT", 0, 0)
        end
    end
    band:SetTexture(CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
    -- 4-arg SetVertexColor LAST (pandemic clone rule): it replaces region
    -- alpha through the non-SetAlpha C slot, so this write is also what
    -- makes the band visible. Forced opaque — the band REPLACES the fill
    -- color (same ruling as the pandemic recolor).
    band:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, 1)
end

local function StyleStackThresholdBands(kit, button, buttonData, style, boundMax, shown, widgetStack)
    local tBand, mBand = kit.stackThresholdBand, kit.stackMaxBand
    if not (tBand and mBand) then return end
    -- All clamp/prefer rules live in ResolveAuraStackThresholdPolicy; the
    -- only band-local rule is the defensive cap at boundMax (the bound
    -- geometry), which normally equals the policy's maxStacks.
    local policy = shown and boundMax and boundMax > 1
        and CooldownCompanion:ResolveAuraStackThresholdPolicy(buttonData) or nil
    local threshold = policy and policy.threshold
    if threshold and threshold > boundMax then threshold = boundMax end
    local rectW, rectH = HostRectSize(button)
    local length = (button._isVertical and rectH or rectW) or 0
    -- Mask convergence: slots are reused across entries, so any bind that
    -- can show a band re-dresses the shared mask — atlas for widget binds,
    -- all-pass white otherwise.
    local mask = kit.stackBandMask
    if mask and policy and length > 0 then
        if widgetStack then
            mask:SetTexture(ST.GetStackSegmentsTexture(boundMax,
                    CooldownCompanion:GetAuraStackBlockGapTexels(buttonData, boundMax)),
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            if button._isVertical then
                -- The fill atlas is rotated onto vertical bars
                -- (SetRotatesTexture); rotate the mask the same way via the
                -- 8-arg corner mapping (Blizzard's digit masks are the
                -- SetTexCoord-on-MaskTexture precedent). The uniform
                -- block/gap pattern is symmetric end to end, so boundary
                -- alignment holds for either 90-degree direction.
                mask:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
            else
                mask:SetTexCoord(0, 1, 0, 1)
            end
        else
            mask:SetTexture("Interface\\Buttons\\WHITE8X8",
                "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetTexCoord(0, 1, 0, 1)
        end
    end
    if threshold and length > 0 then
        DressStackThresholdBand(tBand, kit, button, style, boundMax, threshold,
            policy.thresholdColor, length)
    else
        tBand:SetAlpha(0)
    end
    if policy and policy.maxOn and length > 0 then
        DressStackThresholdBand(mBand, kit, button, style, boundMax, boundMax,
            policy.maxColor, length)
    else
        mBand:SetAlpha(0)
    end
end

-- The resource overlay stack lane: a thin Blizzard-driven strip over the
-- live bar (the resource fill stays visible — nothing occludes on these
-- hosts). It takes the inner half of the bar's thickness on the near edge,
-- which is live's lane convention: bottom on horizontal bars, left on
-- vertical ones. Thickness reads the HOST rect (CC-owned geometry, valid
-- at bind time) — never the slot button.
local function AnchorResourceStackLane(fill, slotButton, host, vertical)
    local thickness = (vertical and host:GetWidth() or host:GetHeight()) or 0
    local size = math.floor(thickness * 0.5 + 0.5)
    if size < 1 then size = 1 end
    if thickness >= 1 and size > thickness then size = thickness end
    fill:ClearAllPoints()
    if vertical then
        fill:SetPoint("TOPLEFT", slotButton, "TOPLEFT", 0, 0)
        fill:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMLEFT", 0, 0)
        fill:SetWidth(size)
    else
        fill:SetPoint("BOTTOMLEFT", slotButton, "BOTTOMLEFT", 0, 0)
        fill:SetPoint("BOTTOMRIGHT", slotButton, "BOTTOMRIGHT", 0, 0)
        fill:SetHeight(size)
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
local function GetPandemicBaseDuration(buttonData, constrainImplicitFallbacks)
    local anchorID = FindPlayerAuraAnchorInstanceID()
    if not anchorID then return nil end
    local candidates = CooldownCompanion:GetOrderedAuraCandidateSpellIDs(
        buttonData, constrainImplicitFallbacks)
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

-- One breakpoint cloned from a shared Duration Format bracket, optionally
-- with a suffix baked onto its format string and a new threshold. Clones
-- because the source brackets are a shared cache and must never be mutated;
-- the components table is composition-only and safe to share.
local function CloneBracket(bracket, threshold, suffix)
    return {
        threshold = threshold or bracket.threshold,
        step = bracket.step,
        rounding = bracket.rounding,
        components = bracket.components,
        format = suffix and (bracket.format .. suffix) or bracket.format,
    }
end

-- Marker formatter for one bind: the countdown keeps the group's own
-- Duration Format brackets on both sides of the threshold — inside the
-- pandemic window each bracket's format gains the marker suffix, above it
-- the brackets render plain, so only the marker distinguishes the window.
-- Marker-only coloring is baked escapes (V21); in whole-text mode the
-- marker stays plain so the curve colors number and marker together.
local function BuildPandemicMarkerFormatter(threshold, marker, style)
    local suffix
    if (style.pandemicMarkerColorMode or "marker") == "marker" then
        suffix = " " .. PandemicColorEscape(style.pandemicMarkerColor) .. marker .. "|r"
    else
        suffix = " " .. marker
    end

    local brackets = CooldownCompanion.GetDurationFormatBrackets(style)
    local list = {}
    local containing, atThreshold
    for _, bracket in ipairs(brackets) do
        if bracket.threshold < threshold then
            containing = bracket
            list[#list + 1] = CloneBracket(bracket, nil, suffix)
        elseif bracket.threshold == threshold then
            atThreshold = true
        end
    end
    -- Re-enter the containing bracket's plain format exactly at the
    -- threshold (the first bracket sits at 0 and the threshold is always
    -- positive, so one always contains it), then keep every higher bracket
    -- as-is. The list stays ascending for any threshold; a bracket sitting
    -- exactly at the threshold already is the re-entry.
    if containing and not atThreshold then
        list[#list + 1] = CloneBracket(containing, threshold)
    end
    for _, bracket in ipairs(brackets) do
        if bracket.threshold >= threshold then
            list[#list + 1] = CloneBracket(bracket)
        end
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
    local n = style.auraTextFontColor or CooldownCompanion.DEFAULT_AURA_TEXT_COLOR
    local curve = C_CurveUtil.CreateColorCurve()
    curve:AddPoint(threshold, CreateColor(p[1] or 1, p[2] or 0.5, p[3] or 0, p[4] or 1))
    curve:AddPoint(threshold + 0.1, CreateColor(n[1] or 1, n[2] or 1, n[3] or 1, n[4] or 1))
    return curve
end

-- SetDurationText options for one marker bind; nil when there is nothing
-- to render (empty marker without whole-text coloring). With an empty
-- marker in whole-text mode the options are curve-only; the bind site
-- adds the group's plain Duration Format formatter to them.
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

------------------------------------------------------------------------
-- PREVIEW TWINS
--
-- Previews are forbidden to touch the aura slot subtree, so no stand-in can
-- reach SetDurationText or the formatter/curve it takes. Each surface writes
-- its own fontstring and asks these two how to dress it, which keeps one
-- definition of "is the marker on" and one of "what does it look like"
-- instead of four reimplementations drifting apart.
------------------------------------------------------------------------

-- The live resolver reads the unit off a live aura bind. A preview has none,
-- so it reads the entry's synced auraUnit (SyncDerivedAuraUnit refreshes it
-- whenever tracking config changes) — the same fallback the entry's own
-- Pandemic Marker checkbox resolves its default from. They can only disagree
-- before a spell's data is cached, which the next config write corrects.
function CooldownCompanion:IsPandemicMarkerPreviewWanted(buttonData, style)
    if type(buttonData) ~= "table" or type(style) ~= "table" then
        return false
    end
    return IsPandemicMarkerWanted(buttonData, style, buttonData.auraUnit or "player")
end

-- Mirrors BuildPandemicMarkerFormatter's three modes on an already-formatted
-- countdown: "marker" colors the marker alone, "whole" colors the number with
-- it (the live curve's below-threshold segment), "off" appends it plain. An
-- empty marker leaves whole-text coloring as the only effect, matching the
-- curve-only options the live path builds in that case.
function CooldownCompanion:DecoratePandemicPreviewText(text, style)
    text = tostring(text or "")
    if type(style) ~= "table" then
        return text
    end
    local marker = SanitizePandemicMarkerText(style.pandemicMarkerText or "!!")
    local mode = style.pandemicMarkerColorMode or "marker"
    if mode == "whole" then
        local body = marker ~= "" and (text .. " " .. marker) or text
        return PandemicColorEscape(style.pandemicMarkerColor) .. body .. "|r"
    end
    if marker == "" then
        return text
    end
    if mode == "marker" then
        return text .. " " .. PandemicColorEscape(style.pandemicMarkerColor) .. marker .. "|r"
    end
    return text .. " " .. marker
end

local function StopTexturePanelSlotIndicator(host)
    host.pulseAG:Stop()
    host.shrinkAG:Stop()
    host.bounceAG:Stop()
    for _, colorShift in ipairs(host.colorShift) do
        colorShift.group:Stop()
    end
end

local function StyleTexturePanelSlotKit(slot, settings, indicator)
    local host = slot.kit and slot.kit.texturePanelHost
    if not host then return end

    -- BindDisplay is OOC. Stop/reset before writing the selected texture so a
    -- pooled slot cannot retain the previous entry's animation or end state.
    StopTexturePanelSlotIndicator(host)
    host.visualRoot:SetAlpha(0)
    host.visualRoot:SetScale(1)

    local geometry, alpha = CooldownCompanion:GetTexturePanelRenderGeometry(settings)
    if not geometry then
        host.primaryTexture:Hide()
        host.secondaryTexture:Hide()
        return
    end

    local shown = LayoutTexturePieces(host, settings, geometry, alpha)
    host.visualRoot:SetAlpha(shown and 1 or 0)
    if not shown or type(indicator) ~= "table" or indicator.enabled ~= true then
        return
    end

    local effectType = NormalizeTextureIndicatorEffect(indicator.effectType)
    local speed = Clamp(tonumber(indicator.speed) or DEFAULT_TEXTURE_INDICATOR_SPEED,
        MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE then
        host.pulseAnim:SetDuration(speed)
        host.pulseAG:Play()
    elseif effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND then
        host.shrinkAnim:SetDuration(speed / 2)
        host.shrinkAG:Play()
    elseif effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        local amplitude = math.max(6, math.min(DEFAULT_TEXTURE_BOUNCE_PIXELS,
            (geometry.boundsHeight or DEFAULT_TEXTURE_BOUNCE_PIXELS) * 0.12))
        host.bounceAnim:SetOffset(0, amplitude)
        host.bounceAnim:SetDuration(speed / 2)
        host.bounceAG:Play()
    elseif effectType == TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT then
        local base = settings.color or { 1, 1, 1, 1 }
        local shift = indicator.color or { 1, 1, 1, 1 }
        local startColor = CreateColor(base[1] or 1, base[2] or 1, base[3] or 1, alpha or 1)
        local endColor = CreateColor(shift[1] or 1, shift[2] or 1, shift[3] or 1, shift[4] or 1)
        for _, colorShift in ipairs(host.colorShift) do
            colorShift.animation:SetStartColor(startColor)
            colorShift.animation:SetEndColor(endColor)
            colorShift.animation:SetDuration(speed / 2)
            colorShift.group:Play()
        end
    end
end

local function StyleSlotKit(slot, button, buttonData, style)
    local kit = slot.kit
    if not kit then return end
    style = style or {}

    local slotButton = slot.slotButton
    local isBar = button._isBar == true
    -- Custom-bar hosts (ResourceBarAuraHost holders): same kit, three host
    -- differences — text placement follows the custom-bar convention, and
    -- non-shell aura bars keep the CC layer visible (no occlusion backdrop,
    -- no kit bg blocks: the bar's own configured background/borders/blocks
    -- ARE the absent-state layer and must show through).
    local isCustomBarHost = button._ccAuraHostKind == "customBar"
    -- Resource-bar hosts (Phase 2 overlay holders): the kit renders one
    -- overlay shape over the live resource bar — no icon, no text, no
    -- occlusion, no shell, no glow; the bar itself is the absent state.
    local isResourceHost = button._ccAuraHostKind == "resourceBar"
    -- Aura Panel hosts (the panel's own aura container): a Blizzard-laid group
    -- frame with NOTHING of CC's underneath it — the panel materializes no CC
    -- buttons at all. Every other host composes the kit over a CC layer that
    -- renders the aura-down state; here the kit IS the entire button, so it
    -- always runs the full shell composition below regardless of what the
    -- entry's own hide/dim keys say. This is the ONLY panel-specific branch in
    -- the styler: the rest of the icon and bar vocabulary applies unchanged,
    -- because an Aura Panel entry is an ordinary panel entry that happens to be
    -- drawn by Blizzard.
    local isAuraPanelHost = button._ccAuraHostKind == "auraPanel"
    local resShapes = isResourceHost and (style.resourceShapes or {}) or nil
    -- Hidden and dimmed shells alike: the kit composes the full active
    -- visual either way (the dim key stands alone on 12.1).
    local shellEntry = isAuraPanelHost or CooldownCompanion:IsAuraShellEntry(buttonData)
    local barIconShown = isBar and style.showBarIcon ~= false and button.icon ~= nil
    local showAuraIcon = ShouldShowAuraIcon(buttonData)
    -- Keep-swipe entries (icon hosts only) skip the icon takeover: the CC
    -- icon and its own cooldown swipe stay visible under the aura overlays.
    local keepSwipeActive = not isBar
        and CooldownCompanion:IsKeepSpellCooldownSwipeEntry(buttonData)
    local kitDesat = CooldownCompanion:ShouldDesaturateAuraLayerWhileActive(buttonData)

    -- Inset-aware anchor host: on block hosts the statusBar proxy is the
    -- border-inset rect while slotButton is the full Blizzard-laid group
    -- frame; on every other host the two rects are identical. Texts, name
    -- and icon regions anchor here so styling can never undo the
    -- creation-time inset (fills already ride the proxy).
    local innerHost = button.statusBar or slotButton
    -- Icon regions cover the slot rect on icon hosts. Bar hosts mount the
    -- slot on the bar rect, so the aura icon and its cover re-anchor onto the
    -- bar's icon square instead (host regions are sanctioned anchor targets;
    -- the duration text has host-anchored since Phase 3). Slots are reused
    -- across entries and modes, so both anchorings reset every bind.
    local iconAnchor = barIconShown and button.icon or innerHost
    kit.auraIcon:ClearAllPoints()
    kit.auraIcon:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    kit.auraIcon:SetPoint("BOTTOMRIGHT", iconAnchor, "BOTTOMRIGHT", 0, 0)
    kit.iconCover:ClearAllPoints()
    kit.iconCover:SetPoint("TOPLEFT", iconAnchor, "TOPLEFT", 0, 0)
    kit.iconCover:SetPoint("BOTTOMRIGHT", iconAnchor, "BOTTOMRIGHT", 0, 0)

    -- Resource overlays never swap in an aura icon: live's overlay has no
    -- icon of any kind.
    local auraIconShown = not isResourceHost
        and showAuraIcon and (not isBar or barIconShown)
    kit.auraIcon:SetAlpha(auraIconShown and 1 or 0)
    -- The cover occludes the CC icon underneath: always on icon hosts; on bar
    -- hosts only when the icon square participates (aura icon swap enabled,
    -- a shell entry whose hidden CC icon needs the static replica, or
    -- active desaturation, which needs a visible gray region while the
    -- aura runs -- the CC bar icon can't carry it).
    local coverWanted = (not isBar)
        or (barIconShown and (showAuraIcon or shellEntry or kitDesat))
    if keepSwipeActive then
        -- Keep-swipe entries skip the takeover; the CC icon stays visible.
        coverWanted = false
    end
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
            -- Explicit dims first: a block host must never be measured.
            local cropW, cropH = button._ccKitRectW, button._ccKitRectH
            if not (cropW and cropH) then
                cropW, cropH = button:GetWidth(), button:GetHeight()
            end
            ApplyIconTexCoord(kit.iconCover, cropW, cropH, style.iconZoom)
            ApplyIconTexCoord(kit.auraIcon, cropW, cropH, style.iconZoom)
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

    -- Desaturate-while-active desaturates the aura layer (any aura entry);
    -- the complementary "desaturate while missing" is a static desaturate
    -- on the CC icon (Tracking.lua) that this layer occludes. Inert by
    -- construction whenever neither region is visible (keep-swipe entries
    -- without the aura icon swap; bar hosts with the icon square off) --
    -- the alpha writes above already carry that.
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
        ApplyFontStyle(kit.durationText, style, "auraText", nil,
            CooldownCompanion.DEFAULT_AURA_TEXT_COLOR)
        ApplyFontStyle(kit.stackText, style, "auraStack")
    end
    kit.durationText:ClearAllPoints()
    kit.stackText:ClearAllPoints()
    if isBar and isResourceHost then
        -- Resource overlays run no text of their own — the resource bar's
        -- own text is the only text over a resource bar. Both regions still
        -- need a point: an unanchored FontString is a layout error even at
        -- alpha 0, and slots are reused across entries and hosts.
        kit.durationText:SetPoint("CENTER", slotButton, "CENTER", 0, 0)
        kit.stackText:SetPoint("CENTER", slotButton, "CENTER", 0, 0)
        kit.durationText:SetAlpha(0)
        kit.stackText:SetAlpha(0)
    elseif isBar and isCustomBarHost then
        -- Custom-bar convention (StyleCustomAuraBar parity): duration text
        -- centers when alone and moves to the start end when the stack text
        -- shares the bar; stack text mirrors on the far end.
        local showDur = style.showAuraText ~= false
        local showStack = style.showAuraStackText ~= false
        if button._isVertical then
            if showStack then
                kit.durationText:SetPoint("BOTTOM", innerHost, "BOTTOM", 0, 2)
            else
                kit.durationText:SetPoint("CENTER", innerHost, "CENTER", 0, 0)
            end
            if showDur then
                kit.stackText:SetPoint("TOP", innerHost, "TOP", 0, -2)
            else
                kit.stackText:SetPoint("CENTER", innerHost, "CENTER", 0, 0)
            end
        else
            if showStack then
                kit.durationText:SetPoint("LEFT", innerHost, "LEFT", 4, 0)
            else
                kit.durationText:SetPoint("CENTER", innerHost, "CENTER", 0, 0)
            end
            if showDur then
                kit.stackText:SetPoint("RIGHT", innerHost, "RIGHT", -4, 0)
            else
                kit.stackText:SetPoint("CENTER", innerHost, "CENTER", 0, 0)
            end
        end
        kit.durationText:SetJustifyH("CENTER")
        kit.durationText:SetAlpha(showDur and 1 or 0)
        kit.stackText:SetAlpha(showStack and 1 or 0)
    elseif isBar then
        -- Bar texts replicate the CC bar's own placement conventions (the
        -- backdrop occludes the originals): duration text at the bar
        -- time-text spot, stack text against the icon square like the old
        -- aura stack count.
        local cdOffX = style.barCdTextOffsetX or 0
        local cdOffY = style.barCdTextOffsetY or 0
        local timeReverse = style.barTimeTextReverse
        if button._isVertical then
            if timeReverse then
                kit.durationText:SetPoint("BOTTOM", innerHost, "BOTTOM", cdOffX, 3 + cdOffY)
            else
                kit.durationText:SetPoint("TOP", innerHost, "TOP", cdOffX, -3 + cdOffY)
            end
            kit.durationText:SetJustifyH("CENTER")
        else
            if timeReverse then
                kit.durationText:SetPoint("LEFT", innerHost, "LEFT", 3 + cdOffX, cdOffY)
                kit.durationText:SetJustifyH("LEFT")
            else
                kit.durationText:SetPoint("RIGHT", innerHost, "RIGHT", -3 + cdOffX, cdOffY)
                kit.durationText:SetJustifyH("RIGHT")
            end
        end
        kit.durationText:SetAlpha(style.showAuraText ~= false and 1 or 0)
        local asAnchor = style.auraStackAnchor or "BOTTOMLEFT"
        local stackAnchorTo = barIconShown and button.icon or innerHost
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
    -- pass is structurally OOC). Marker binds carry per-spell options;
    -- Blizzard's setter resets the binding before applying whatever a bind
    -- passes, so slots reused across entries always converge.
    local pandemicOptions
    if style.showAuraText ~= false and IsPandemicMarkerWanted(buttonData, style, slot.unit) then
        local baseDuration = GetPandemicBaseDuration(
            buttonData, not isCustomBarHost and not isResourceHost)
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
    -- Duration Format: every bind carries the group's own formatter so the
    -- aura countdown renders like the cooldown text instead of Blizzard's
    -- stock "12 s" SecondsFormatter. Marker binds already built a formatter
    -- on the same brackets; color-only pandemic options gain the plain one.
    local durationOptions = pandemicOptions
    if not (durationOptions and durationOptions.textFormatter) then
        local formatter = CooldownCompanion.GetDurationTextFormatter
            and CooldownCompanion.GetDurationTextFormatter(style)
        if formatter then
            durationOptions = durationOptions or {}
            durationOptions.textFormatter = formatter
        end
    end
    slotButton:SetDurationText(kit.durationText, durationOptions)

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
                kit.barNameText:SetPoint("TOP", innerHost, "TOP", nameOffX, -3 + nameOffY)
            else
                kit.barNameText:SetPoint("BOTTOM", innerHost, "BOTTOM", nameOffX, 3 + nameOffY)
            end
            kit.barNameText:SetJustifyH("CENTER")
        else
            if nameReverse then
                kit.barNameText:SetPoint("RIGHT", innerHost, "RIGHT", -3 + nameOffX, nameOffY)
                kit.barNameText:SetJustifyH("RIGHT")
            else
                kit.barNameText:SetPoint("LEFT", innerHost, "LEFT", 3 + nameOffX, nameOffY)
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
    -- aura swipe — the draining bar is the timer, and a resource overlay
    -- has no icon square for one to ride.
    if isBar and isResourceHost then
        kit.swipe:ClearAllPoints()
        kit.swipe:SetAllPoints(slotButton)
        kit.swipe:SetDrawSwipe(false)
        kit.swipe:SetDrawEdge(false)
    elseif isBar or not CooldownCompanion:ShouldDrawAuraDurationSwipe(buttonData) then
        -- Bars have no aura swipe; keep-swipe entries show the spell's own
        -- cooldown swipe instead (two swipes would stack). Draw flags only --
        -- the swipe stays registered so Blizzard keeps driving it.
        kit.swipe:SetDrawSwipe(false)
        kit.swipe:SetDrawEdge(false)
    else
        CooldownCompanion:ApplyAuraDurationSwipeStyle(kit.swipe, style)
    end

    -- Pandemic display enable (PTR 8): per-entry override wins, else the
    -- panel style's explicit-true enable. Custom-bar hosts read the same
    -- style key, synthesized by BuildStyleAdapter from the entry's own
    -- fresh pandemicEffect key (the entry has no panel level to follow).
    -- Resource overlays carry no pandemic story at all. Blizzard flips the
    -- rig's secret Shown state regardless; this gate only decides whether
    -- the rig has anything visible to show.
    local pandemicOn = false
    if isCustomBarHost then
        pandemicOn = style.pandemicEffectEnabled == true
    elseif not isResourceHost then
        if buttonData.pandemicEffect ~= nil then
            pandemicOn = buttonData.pandemicEffect == true
        else
            pandemicOn = style.pandemicEffectEnabled == true
        end
    end

    -- Bar composition: opaque backdrop occludes the CC bar underneath
    -- (skipped for shell entries — nothing visible to occlude); Blizzard
    -- drains the registered fill while the aura runs. Color writes carry
    -- their own alpha and only happen in the enabled branch
    -- (SetVertexColor-alpha gotcha: a 4-arg color write after SetAlpha(0)
    -- would resurrect the region).
    if isBar and isResourceHost then
        -- Resource overlay composition: occlusion-free by construction (the
        -- live resource bar IS the absent state). Two INDEPENDENT visuals
        -- (owner rulings 2026-08-02): a BORDER (replacing the tint wash)
        -- wrapping the whole bar rect on every shape — segment clusters
        -- included, as if the bar were continuous — via the shared glow
        -- kit call below, gated there by barAuraIndicatorEnabled; and the
        -- stack LANE strip. Never the whole-rect fills the other bar hosts
        -- run. The lane fills CONTINUOUS (match the preview) — the painted
        -- stack separators are a bar-panel look, so the shared stripe
        -- painter stays off here.
        kit.barBackdrop:SetAlpha(0)
        ST.HideStackBlocks(kit.stackBgBlocks)
        ST.HideStackBlockBorders(kit.stackBlockBorders)
        local laneHost = button.statusBar or button
        local laneVertical = button._isVertical == true
        -- The duration fill never runs on a resource host: live's overlay
        -- has no duration readout, and the tint carries the active state.
        if kit.barFill then
            RestBarFill(kit.barFill, kit.barFillTexture, kit.barFillPulseAG, kit.barFillCsAG)
        end
        local stackLaneOn = resShapes.stackLane == true
            and kit.stackFill ~= nil and slot.boundStackMax ~= nil
        if kit.stackFill then
            if stackLaneOn then
                AnchorResourceStackLane(kit.stackFill, slotButton, laneHost, laneVertical)
                StyleActiveBarFill(kit.stackFill, kit.stackFillTexture,
                    kit.stackFillPulseAG, kit.stackFillPulseAnim,
                    kit.stackFillCsAG, kit.stackFillCsAnim, button, style)
            else
                RestBarFill(kit.stackFill, kit.stackFillTexture, kit.stackFillPulseAG, kit.stackFillCsAG)
            end
        end
        StyleStackSegments(kit, button, buttonData, style, nil, false)
        -- Resource-lane bands deferred (v1 ruling): always off here.
        StyleStackThresholdBands(kit, button, buttonData, style, nil, false)
    elseif isBar then
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
        -- Occlusion-free binds (owner ruling, attempt-1 failure 4): a pure
        -- aura custom bar has nothing running beneath that must be hidden —
        -- the CC bar renders the absent state and follows the configured
        -- background, so the opaque backdrop and the kit's own bg blocks
        -- stay off and the kit adds only fill/texts/effects. Spell custom
        -- bars keep the opaque backdrop (a live cooldown fill and its texts
        -- render beneath and must be occluded), as do panel bars and shells.
        local occlusionFree = isCustomBarHost and buttonData.addedAs == "aura" and not shellEntry
        if shellEntry or widgetStack or occlusionFree then
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
            local blockBg = style.barBgColor or { 0.1, 0.1, 0.1, 0.8 }
            -- Alpha: forced opaque is an OCCLUSION rule, so it applies only
            -- where something renders beneath.
            --   * occlusion-free: the CC-side blocks under the holder ARE
            --     the background, so the kit's stay invisible.
            --   * custom-bar shell: the CC frame is at whole-frame alpha 0,
            --     so these blocks are the whole background and follow the
            --     configured alpha (otherwise the shell toggle would change
            --     a bar's opacity).
            --   * panels: opaque, occluding whatever runs beneath.
            local blockAlpha
            if occlusionFree then
                blockAlpha = 0
            elseif isCustomBarHost then
                blockAlpha = blockBg[4] or 1
            end
            local rectW, rectH = HostRectSize(button)
            ST.LayoutStackBlocks(kit.stackBgBlocks, button.statusBar or slotButton,
                slot.boundStackMax, button._isVertical, blockBg, blockAlpha,
                button._isVertical and rectH or rectW,
                CooldownCompanion:GetAuraStackBlockGapTexels(buttonData, slot.boundStackMax) / 512)
            -- The per-block rings always come from the KIT, even when its
            -- blocks are invisible (they are laid out purely to anchor
            -- these). The kit's rings live inside the fill frame and draw
            -- above it; the CC-side rings sit on the bar frame, which the
            -- holder and its fill cover entirely — so relying on those made
            -- a segmented bar read as one continuous fill for exactly as
            -- long as the aura was up.
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
        -- Pandemic fill recolor: dress the clone in the file the duration
        -- fill wears plus the pandemic color. The 4-arg SetVertexColor is
        -- the LAST write and carries the color's own alpha (it replaces
        -- region alpha through the non-SetAlpha C slot — a trailing
        -- SetAlpha would clobber the picker's alpha to opaque while the
        -- mirror honors it). The disabled leg writes only alpha 0 — no
        -- color write that could resurrect it. Stack-mode, icon, and
        -- resource binds are covered by RestBarFill's frame alpha-0 (the
        -- clone is barFill's child), but slots are reused across entries
        -- so the enable is converged here every bar bind regardless.
        -- Accepted cosmetic limit: the clone stretches its full texture
        -- into the drained rect (no per-frame texcoord crop is possible on
        -- a secret-driven fill), visible only on bar textures with
        -- horizontal variation.
        if kit.pandemicFillClone then
            if pandemicOn and not useStackFill then
                local pc = style.barPandemicColor or { 1, 0.5, 0, 1 }
                -- Forced opaque (owner ruling: the pandemic color REPLACES
                -- the aura fill color, never blends with it) — the alpha
                -- slot carries the region's visibility, not the picker's.
                kit.pandemicFillClone:SetTexture(
                    CooldownCompanion:FetchEffectiveBarTexture(style.barTexture or "Solid"))
                kit.pandemicFillClone:SetVertexColor(pc[1] or 1, pc[2] or 0.5, pc[3] or 0, 1)
            else
                kit.pandemicFillClone:SetAlpha(0)
            end
        end
        if kit.stackFill then
            if useStackFill then
                local atlas = widgetStack and ST.GetStackSegmentsTexture(slot.boundStackMax,
                    CooldownCompanion:GetAuraStackBlockGapTexels(buttonData, slot.boundStackMax)) or nil
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
        StyleStackThresholdBands(kit, button, buttonData, style, slot.boundStackMax,
            useStackFill, widgetStack)
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
        StyleStackThresholdBands(kit, button, buttonData, style, nil, false)
    end

    -- Aura active glow: icon hosts style from the auraGlow* keys, bar hosts
    -- from the barAura* keys (whole-bar anchor — resource hosts included,
    -- where the barAura* keys ARE the aura border). Style resolution and
    -- the "none"/enable gates live in the builders; the config preview
    -- renders equivalent visuals CC-side (Glows.lua
    -- NormalizeAuraGlowPreviewStyle / NormalizeBarAuraEffectStyle), never
    -- here.
    if isBar then
        ST._StyleKitBarGlowRegions(kit.glow, style, button, true)
    else
        ST._StyleKitGlowRegions(kit.glow, style, button, true)
    end

    -- Icon entries with both enabled show the aura glow AND the pandemic
    -- glow together during the window (owner ruling 2026-08-05, accepting
    -- the fallback): the replace-while-shown ideal has no supported path —
    -- a window mask over the aura glow textures (a black MaskTexture
    -- registered as a pandemic region) was built and probed in game, and a
    -- shown SetColorTexture mask observably does not blank its targets on
    -- build 69111. Bars achieve true replacement structurally (the opaque
    -- clone overlays the fill), so no such compromise exists there.

    -- Pandemic glow: icon hosts only — the bar pandemic presentation is the
    -- fill recolor above, not a border effect (owner ruling). Anchors to the
    -- host button exactly like the aura glow; a disabled entry styles to
    -- "none", which fully resets and hides the rig even though Blizzard
    -- still flips its secret Shown state.
    if kit.pandemicGlow then
        ST._StyleKitPandemicGlowRegions(kit.pandemicGlow, style, button,
            pandemicOn and not isBar)
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
        -- Custom-bar hosts always use the bar bounds — the holder (button)
        -- is the border-inset mount, and the shell bg must fill the bar's
        -- real footprint. Widget-stack shells skip the slab AND the
        -- whole-bar border ring — the capacity blocks laid out above ARE
        -- the background, each with its own border ring (owner ruling:
        -- every stack its own widget; a slab would fill the gaps and one
        -- ring would wrap all stacks).
        local bgAnchor = (barIconShown or isCustomBarHost) and barBounds or button
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
    -- An Aura Panel offers no Keybind Text (owner ruling 2026-08-15): the
    -- toggle is gone from its Appearance tab, so a style value surviving a
    -- conversion or a copied customization is the only way showKeybindText can
    -- still read true here, and it must not put the replica back.
    local keybindText
    if shellEntry and not isBar and not isAuraPanelHost and style.showKeybindText then
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

local function BuildCandidateFilters(unit, spellSet, groupScoped)
    local filters = { includeSpellIDs = spellSet }
    if SlotContract(unit, groupScoped).ownOnly then
        filters.isFromPlayerOrPlayerPet = true
    end
    return filters
end

-- The never-match filter set for a parked slot. Scope is deliberately omitted:
-- the sentinel is chosen by POLARITY, which scope never changes, and a park set
-- can never match either way — so parking does not need to know which entry (if
-- any) last owned the record.
local function BuildParkFilters(unit)
    return BuildCandidateFilters(unit, { [PARK_SENTINEL[SlotContract(unit).polarity]] = true })
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
        -- Icon hosts: the aura display is a CONFIGURABLE layer, so its level
        -- comes from the panel's strata order. ApplyStrataOrder
        -- (ButtonFrame/Helpers.lua) is the single owner of every level on an
        -- icon button; this asks it for one rather than keeping a second copy
        -- of the arithmetic in sync by hand. It does NOT touch overlayFrame:
        -- the text overlay is its own slot now, and CC's text that must
        -- survive an active display lives on button.pinnedTextFrame.
        local levels, top = ST._ResolveStrataLevels(button, button.style and button.style.strataOrder)
        layer:SetFrameLevel(levels.auraDisplay or top)
    end
    return layer
end

-- Texture panels' driver buttons are intentionally alpha-zero 1x1 identity
-- shells, so their production AuraContainer mounts under the existing movable
-- UIParent-level texture host instead. The host and root are permanent once a
-- slot exists; only the safe root's alpha is used to suppress it for previews.
local function EnsureTexturePanelAuraLayer(button)
    local host = CooldownCompanion:EnsureAuraTextureHost(button)
    return host.auraRuntimeRoot
end

-- One display per host button (D-A0 rung (c)): the container's parent is a
-- plain CC visibility frame set once at CreateFrame and never changed (only
-- the BUTTONS carry the ChangeParent aspect), and the slot button is anchored
-- inside initializeFrame — the sanctioned setup window — and never moved,
-- re-leveled, or reparented afterwards. The container is pinned to the
-- layer's frame level so the slot lands at layer+1, exactly where the
-- pre-PTR 7 design put it — but the layer's own level is now a configurable
-- slot, so where that band SITS follows the panel's strata order.
-- Visibility, alpha, and strata all reach the slot through plain parentage;
-- a hidden container is inert (P1a) and
-- re-registers + refreshes itself on show (OnShow_Intrinsic).
-- Keyed by (button, host kind, unit), which makes record.unit IMMUTABLE: a
-- record is for one unit for its whole life, and the container's SetUnit is
-- only ever called once, here. The alternative — one record per button whose
-- unit is swapped at bind — cannot represent an entry tracked on several
-- units at once.
--
-- Consequence: a pooled button re-acquired for an entry of the other polarity
-- now gains a second record rather than mutating its first. The first is parked
-- (hidden, deregistered, rendering nothing), so this is invisible; the cost is
-- at most one extra container per polarity that button has ever hosted.
local function EnsureDisplay(button, unit, groupScoped, hostKind)
    hostKind = hostKind or "button"
    local recordKey = hostKind .. "\031" .. unit
    local byUnit = displays[button]
    if byUnit then
        local existing = byUnit[recordKey]
        if existing then return existing end
    else
        byUnit = {}
        displays[button] = byUnit
    end
    local layer = hostKind == "texturePanel"
        and EnsureTexturePanelAuraLayer(button)
        or EnsureAuraLayer(button)
    slotCounter = slotCounter + 1
    local record = {
        button = button,
        key = "cc" .. slotCounter,
        unit = unit,
        hostKind = hostKind,
        layer = layer,
    }
    -- This plain frame is the runtime fail-closed switch for reaction changes.
    -- Hiding it cannot inspect or mutate the restricted aura subtree, while
    -- still suppressing every Blizzard-owned region below the container.
    local visibilityRoot = CreateFrame("Frame", nil, layer)
    visibilityRoot:SetAllPoints(layer)
    visibilityRoot:SetFrameLevel(layer:GetFrameLevel())
    visibilityRoot:Hide()
    record.visibilityRoot = visibilityRoot
    -- Direct calls, no pcall: the TOC pins this client generation, so the
    -- AuraContainer API always exists — a failure here is a real setup error
    -- that must surface, not read as "feature unavailable".
    local container = CreateFrame("AuraContainer", nil, visibilityRoot, "CustomAuraContainerTemplate")
    container:SetAllPoints(visibilityRoot)
    container:SetFrameLevel(layer:GetFrameLevel())
    container:SetUnit(unit)
    local slotButton = container:AddAuraSlot(record.key, SlotContract(unit, groupScoped).filter, {
        candidateFilters = BuildParkFilters(unit),
        initializeFrame = function(frame)
            -- The ONLY place the slot button is ever positioned.
            frame:SetAllPoints(container)
            record.kit = hostKind == "texturePanel"
                and BuildTexturePanelSlotKit(frame)
                or BuildSlotKit(frame)
        end,
    })
    if not slotButton then
        CooldownCompanion:Print("Aura slot creation failed.")
        return nil
    end
    record.slotButton = slotButton
    record.container = container
    if hostKind == "texturePanel" and button.auraTextureHost then
        button.auraTextureHost._auraSlotOwned = true
    end
    byUnit[recordKey] = record
    records[#records + 1] = record
    EnsureIdentityWatcher()
    if unit == "target" then
        EnsureTargetWatcher()
    end
    -- No group-watcher arming here: the rebind pass arms it from the entry's
    -- opt-in, which covers strictly more cases (it runs for blocked wants too,
    -- and while solo where no ally record is created at all).
    return record
end

-- Park = sentinel filter swap PLUS hiding the container.
--
-- The sentinel alone is not a park. It works by handing Blizzard a spell ID
-- that can never match, but that filter is applied INSIDE the identity gate
-- (Blizzard_AuraContainerUtil.lua:43-55), and the gate stops applying spell-ID
-- filters entirely for a helpful aura on a unit the player cannot assist
-- (:31-33). A charmed ally therefore makes a sentinel-parked slot match the
-- next aura the player has on that unit — wrong icon, wrong timer, on a display
-- the user has switched off. Slots can never be removed, so that state would
-- persist until /reload.
--
-- Hiding the container is unconditional: the slot's AuraButton is a direct
-- child of the container (Blizzard_CustomAuraContainer.lua:656 ->
-- Blizzard_AuraContainerFrameProviders.lua:73), so Hide() clears the button and
-- every kit region inside it regardless of Blizzard's secret shown state, and
-- it also drops the container out of the aura event path entirely
-- (ShouldRegisterForDynamicEvents requires IsVisible(), Blizzard_AuraContainer
-- .lua:158) — which is what makes a parked container cost nothing.
--
-- Validated in game 2026-07-29: SetEnabled(false) is NOT sufficient (it stops
-- updates but leaves a stale icon with a frozen timer, because ParseAllAuras
-- never consults IsEnabled()); Hide()/Show() clears and restores cleanly.
--
-- Do NOT split this into "sentinel now, Hide() later". An earlier attempt did, so
-- that a record could be half-neutralised while its unit was in combat, and it was
-- wrong in both directions: it leaves a VISIBLE container carrying a sentinel
-- filter, and the sentinel is exactly what the identity gate stops applying on a
-- non-assistable unit — a charmed ally would light that visible slot with an
-- unrelated buff of yours. And clearing `boundEntry` while the container is still
-- shown makes the pass's token reconciliation treat the host as slot-free,
-- releasing the pool lock on a live visible slot. The two halves must stay
-- together; there is no longer any caller that needs them apart.
--
-- `_auraSlotHostToken` is deliberately NOT cleared here. A host can carry
-- several records, and clearing the shared token while a sibling keeps a live
-- binding would release the pool lock protecting a visible slot. The pass
-- reconciles the token once, after binding.
local function ParkDisplay(record)
    if not record.parked then
        record.parked = true
        record.boundEntry = nil
        record.boundGroupScoped = nil
        SetIdentityVisibility(record, false)
        -- CC-side tag only: the registered max stays whatever the last bind
        -- wrote (the fill is alpha-0; the next bind converges it).
        record.boundStackMax = nil
        ReleaseSlotAuraSounds(record)
        record.container:SetAuraSlotCandidateFilters(record.key, BuildParkFilters(record.unit))
        record.container:Hide()
    end
end

-- Style key -> AuraButton tooltip anchor (tracker D-C1). Unlisted values
-- (incl. "default"/nil) fall back to ANCHOR_NONE, the untouched-button
-- behavior. Must stay a subset of the mixin's valid-anchor list — an
-- invalid name asserts (bind-time, OOC, but still an error to avoid).
local AURA_TOOLTIP_ANCHORS = {
    above = "ANCHOR_TOP",
    below = "ANCHOR_BOTTOM",
    left = "ANCHOR_LEFT",
    right = "ANCHOR_RIGHT",
    cursor = "ANCHOR_CURSOR",
}

-- Stack fill re-call (tracker C2): converge the registered max to this bind
-- before styling — always a number (ApplyApplicationBar runs math.max(max, 1),
-- so a nil errors inside Blizzard's refresh and freezes the display), 1 =
-- duration-only bind. Same per-bind re-call pattern as the C9 SetDurationText
-- call inside StyleSlotKit (V23 PTR 7 — re-calls are legal again; the
-- ApplicationBar leg is probe-gated by the v24 retest), structurally OOC in
-- the rebind pass. Skipped when unchanged: the max is CC-side state
-- (kit.stackFillMax), never a read-back.
--
-- Segmented smoothing (C2 follow-on): Blizzard sweeps the driven fill between
-- stack counts (interpolation is Blizzard-evaluated — the only smoothing path
-- for secret values). Continuous style always smooths (owner ruling, resource
-- parity); segmented follows the per-entry toggle. Plain duration binds
-- (wantMax == 1) never use the stack fill, so they keep the creation-time
-- registration untouched.
local function ConvergeApplicationBar(slotButton, kit, buttonData, stackBarMax)
    if not (kit and kit.stackFill) then return end
    local wantMax = stackBarMax or 1
    local wantSmooth = false
    if wantMax > 1 and ST.STATUS_BAR_INTERPOLATION_SMOOTH then
        wantSmooth = CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData) == "continuous"
            or CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(buttonData) == ST.SEGMENTED_SMOOTHING_ON
    end
    if kit.stackFillMax ~= wantMax or kit.stackFillSmooth ~= wantSmooth then
        slotButton:SetApplicationBar(kit.stackFill, {
            maxApplications = wantMax,
            interpolation = wantSmooth and ST.STATUS_BAR_INTERPOLATION_SMOOTH or nil,
        })
        kit.stackFillMax = wantMax
        kit.stackFillSmooth = wantSmooth
    end
end

-- Stack text threshold colors (2026-08-15 program): converge the stack
-- text registration to this bind's threshold policy. Same per-bind re-call
-- family as ConvergeApplicationBar above and the C9 SetDurationText call —
-- structurally OOC in the rebind pass, skipped when unchanged via a
-- CC-side fingerprint (registered regions are write-only; never a
-- read-back). Threshold entries re-register WITH the per-slot formatter
-- (breakpoints rebuilt first); entries without threshold config converge
-- back to the bare stock registration. All clamp/prefer rules live in
-- ResolveAuraStackThresholdPolicy — never re-derive them here.
--
-- Breakpoint contract: the engine picks the highest breakpoint whose
-- threshold is <= the (secret) count. {0, ""} reproduces stock
-- hidden-below-2 behavior (a formatter otherwise formats EVERY count);
-- {2, "%d"} renders plain counts in the fontstring's styled color; the
-- threshold/max entries wrap the number in their color escape. Max wins a
-- collision with the threshold by overwriting its slot in the map.
local function ConvergeApplicationCount(slotButton, kit, buttonData)
    if not (kit and kit.stackText and kit.stackFormatter) then return end
    local policy = CooldownCompanion:ResolveAuraStackThresholdPolicy(buttonData)
    local wantKey = "off"
    if policy then
        local parts = {}
        if policy.threshold then
            parts[#parts + 1] = "t" .. policy.threshold .. PandemicColorEscape(policy.thresholdColor)
        end
        if policy.maxOn then
            parts[#parts + 1] = "m" .. policy.maxStacks .. PandemicColorEscape(policy.maxColor)
        end
        wantKey = table.concat(parts, "/")
    end
    if kit.stackCountFormatterKey == wantKey then return end
    if not policy then
        slotButton:SetApplicationCount(kit.stackText)
    else
        -- threshold -> format map; later writes win collisions (max last).
        local formats = { [0] = "", [2] = "%d" }
        if policy.threshold then
            formats[policy.threshold] = PandemicColorEscape(policy.thresholdColor) .. "%d|r"
        end
        if policy.maxOn then
            formats[policy.maxStacks < 2 and 2 or policy.maxStacks] =
                PandemicColorEscape(policy.maxColor) .. "%d|r"
        end
        local thresholds = {}
        for value in pairs(formats) do thresholds[#thresholds + 1] = value end
        table.sort(thresholds)
        local breakpoints = {}
        for i = 1, #thresholds do
            breakpoints[i] = { threshold = thresholds[i], format = formats[thresholds[i]] }
        end
        kit.stackFormatter:ClearBreakpoints()
        kit.stackFormatter:SetBreakpoints(breakpoints)
        slotButton:SetApplicationCount(kit.stackText, { formatter = kit.stackFormatter })
    end
    kit.stackCountFormatterKey = wantKey
end

local function BindDisplay(record, buttonData, spellSet, unit, style, stackBarMax, soundsAllowed, groupScoped, textureSettings, textureIndicator)
    local button = record.button
    local wasParked = record.parked
    local layer = record.hostKind == "texturePanel" and record.layer or EnsureAuraLayer(button)
    -- Undo the park's Hide() before any slot writes, so the deferred re-parse
    -- sees the finished state. OnShow_Intrinsic re-registers the container's
    -- events and refreshes it on its own.
    --
    -- The pass parks everything then rebinds, so a record that stays bound is
    -- hidden and re-shown every pass. That is free rather than clever: nothing
    -- renders between the two calls (both happen inside one RunAuraRebind), and
    -- each only sets the same FullAuraRebuild dirty flag that the
    -- SetAuraSlotCandidateFilters below sets anyway, so it coalesces to the one
    -- rebuild the bind already required. The guard exists only to skip a
    -- pointless Show() on a first bind, where the container is already shown
    -- from creation and was never parked.
    if wasParked then
        record.container:Show()
    end
    -- Re-pin after the layer's level dance: the cascade keeps the subtree's
    -- relative levels on its own; this heals any drift without ever touching
    -- the slot button.
    record.visibilityRoot:SetFrameLevel(layer:GetFrameLevel())
    record.container:SetFrameLevel(layer:GetFrameLevel())
    -- No unit swap here: records are keyed by (button, unit), so record.unit is
    -- immutable and always equals `unit`. SetUnit is called once, in
    -- EnsureDisplay. A host that needs a different unit gets its own record.
    --
    -- Converge the whole contract every bind rather than only on a unit change.
    -- The filter string is baked at AddAuraSlot, so writing it from the same
    -- source as the sentinel and the caster filter here is what keeps the three
    -- from drifting apart — it removes the fragile invariant that the string is
    -- only ever rewritten when the unit changes. Blizzard's setter early-outs
    -- when unchanged (Blizzard_CustomAuraContainer.lua:427), so it costs nothing
    -- in the common case; SetAuraSlotFilterString self-refreshes otherwise
    -- (RebuildAuraParseFilters + UpdateAllAuras).
    record.container:SetAuraSlotFilterString(record.key, SlotContract(unit, groupScoped).filter)
    record.container:SetAuraSlotCandidateFilters(record.key,
        BuildCandidateFilters(unit, spellSet, groupScoped))
    if record.hostKind ~= "texturePanel" then
        ConvergeApplicationBar(record.slotButton, record.kit, buttonData, stackBarMax)
        ConvergeApplicationCount(record.slotButton, record.kit, buttonData)
    end
    -- Set before styling: StyleSlotKit selects the stack fill from this tag.
    record.boundStackMax = stackBarMax
    if record.hostKind == "texturePanel" then
        StyleTexturePanelSlotKit(record, textureSettings, textureIndicator)
    else
        StyleSlotKit(record, button, buttonData, style)
    end
    -- CC-side capacity blocks sync here too: rebinds are OOC by design, so
    -- this repairs bars whose style pass ran in combat (where the block
    -- helper defers). Panel buttons only — custom-bar hosts sync their
    -- absent-state blocks in the collector.
    if button._isBar and not button._ccAuraHostKind and ST._UpdateBarStackBlocks then
        ST._UpdateBarStackBlocks(button, style)
    end
    -- Skipped for multi-unit (ally-scope) entries; see the caller. ParkDisplay
    -- still calls ReleaseSlotAuraSounds unconditionally, which no-ops when
    -- nothing was registered.
    if soundsAllowed then
        RegisterSlotAuraSounds(record, buttonData, spellSet)
    end
    -- Tooltip suppression follows the button's recorded tooltip intent
    -- (_ccTooltipMotion, written by the same style passes that run the
    -- click-through sweep; the sweep itself never reaches the slot subtree).
    -- Not the sweep's motion state: entry pings widen motion without wanting
    -- tooltips. P7-validated shape.
    record.slotButton:SetMouseMotionEnabled(
        record.hostKind ~= "texturePanel" and button._ccTooltipMotion == true)
    -- Tooltip position + combat hide (tracker D-C1): plain per-bind mixin
    -- state on the slot button, same OOC re-call pattern as the motion line
    -- above; Blizzard's OnEnter path reads it. ANCHOR_NONE with zero offsets
    -- is what an untouched button resolves to, so re-calling it converges
    -- pooled buttons when the setting goes back to Default.
    record.slotButton:SetTooltipAnchorPoint(
        record.hostKind ~= "texturePanel"
            and (AURA_TOOLTIP_ANCHORS[style.tooltipAnchor] or "ANCHOR_NONE")
            or "ANCHOR_NONE",
        0, 0)
    record.slotButton:SetHideTooltipInCombat(
        record.hostKind == "texturePanel" or style.tooltipHideInCombat == true)
    record.parked = nil
    record.boundEntry = buttonData
    record.boundGroupScoped = groupScoped
    record.identityApplicable = CanApplySpellIdentityFilter(unit, groupScoped)
    SetIdentityVisibility(record, record.identityApplicable)
    -- Combat pool lock: while this button is pooled in combat it may only be
    -- re-acquired for the same entry (GroupFrame.AcquireButtonFromPool).
    button._auraSlotHostToken = buttonData
    if record.hostKind == "texturePanel" and CooldownCompanion.UpdateAuraTextureVisual then
        -- Release hides the permanent UIParent host. A pooled host reused for
        -- a different entry also stays suppressed until this matching token is
        -- installed; now reconverge only the safe outer host/preview switch.
        CooldownCompanion:UpdateAuraTextureVisual(button)
    end
end

------------------------------------------------------------------------
-- The rebind pass — the single place slot subtrees are touched. Idempotent,
-- coalesced, OOC-only: park everything, then bind every aura-tracking entry
-- currently materialized as a button.
------------------------------------------------------------------------

-- The units an entry is tracked on, in bind order.
--
-- Polarity is still derived from the spell every pass (Blizzard's identity gate
-- permits spell-ID matching only for helpful auras on assistable units and
-- harmful auras on non-assistable ones); the stored auraUnit is a fallback for
-- uncached spells, so config, migration and runtime can't drift.
--
-- Harmful entries resolve to the target UNCONDITIONALLY and ignore the group
-- opt-in. That is what keeps an illegal pairing — your debuff on an ally, which
-- the gate would silently refuse to filter — unrepresentable at runtime even if
-- stored config drifts.
local function ResolveEntryAuraUnits(self, buttonData, allowGroupScope)
    local first = allowGroupScope == false
        and self:ResolveTexturePanelAuraSpellID(buttonData)
        or self:ResolveAuraSpellID(buttonData)
    local harmful
    if first and C_Spell.DoesSpellExist(first) then
        harmful = C_Spell.IsSpellHarmful(first)
    else
        harmful = buttonData.auraUnit == "target"
    end
    if harmful then return { "target" } end
    if allowGroupScope ~= false and buttonData.auraTrackGroup then return GroupAuraTokens() end
    return { "player" }
end

------------------------------------------------------------------------
-- AURA BLOCKS — custom-bar aura entries that hide when inactive.
--
-- Such an entry cannot hold a fixed slot in the CC-laid-out resource stack:
-- aura presence is secret, so CC can never pack the stack around it. Each
-- side of the stack instead gets ONE AuraContainer running in GROUP mode.
-- Blizzard assigns a pooled AuraButton per ACTIVE aura and packs the
-- survivors with its own flow layout, in the layoutIndex order written here;
-- CC never learns which groups are up.
--
-- Groups are APPEND-ONLY — there is no public removal (ClearAuraGroups is
-- deliberately private) — so a block group record is permanent exactly like a
-- slot record, and retiring an entry parks it instead.
--
-- The container takes the UntrustedLayoutScriptExecution forbidden aspect at
-- its first AddAuraGroup and Blizzard resizes it with secret values from then
-- on. Nothing here reads the container's or a group frame's rect: every
-- geometry number arrives from the CC-side block contract
-- (OtherBars/ResourceBarAuraHost.lua).
--
-- One container per (side, UNIT). A container tracks exactly one unit and
-- SetUnit is called once, at creation — the same immutability the slot
-- records rely on. A side whose entries resolve to BOTH units therefore
-- renders as two CHAINED buckets: the player container takes the stack-end
-- mount and the target container hangs off its trailing edge, riding a size
-- CC never reads. Buckets never interleave, and player is always the one
-- nearer the panel.
--
-- Every container is created with DisableUntrustedLayoutScriptsTemplate
-- alongside CustomAuraContainerTemplate, which is what makes it legal to
-- anchor one aspected container to another (runtime-probed 2026-08-08).
------------------------------------------------------------------------

-- Flow geometry per side. The layout AXIS is the direction bars stack along,
-- so a horizontal resource stack (above/below) flows vertically and a
-- vertical one (left/right) flows horizontally. Anchor point and growth
-- mirror RelayoutBars' own accumulator signs for that side, and the anchor
-- point matches the container's own mount corner so both grow the same way.
local BLOCK_FLOW = {
    above = { axis = "Vertical", anchor = "BOTTOMLEFT", h = "Right", v = "Up" },
    below = { axis = "Vertical", anchor = "TOPLEFT", h = "Right", v = "Down" },
    left = { axis = "Horizontal", anchor = "TOPRIGHT", h = "Left", v = "Down" },
    right = { axis = "Horizontal", anchor = "TOPLEFT", h = "Right", v = "Down" },
}

local blockContainers = {} -- side .. "\031" .. unit -> block record
local blockRecords = {}    -- flat, append-only list of every block record
local blockChainBlocked = 0 -- entries the last bind dropped for a dead chain

local function RefreshSlotIdentityVisibility(record)
    local applicable = CanApplySpellIdentityFilter(record.unit, record.boundGroupScoped)
    local changed = record.identityApplicable ~= applicable
    record.identityApplicable = applicable
    return SetIdentityVisibility(record, record.boundEntry ~= nil and applicable) or changed
end

local function RefreshBlockIdentityVisibility(record)
    local applicable = CanApplySpellIdentityFilter(record.unit)
    local changed = record.identityApplicable ~= applicable
    record.identityApplicable = applicable
    return SetIdentityVisibility(record, record.shown == true and applicable) or changed
end

-- Relationship-only refresh: no AuraButton reads or writes. UNIT_FACTION,
-- target swaps, roster remaps, and vehicle transitions can therefore suppress
-- an unsafe record immediately even while a full rebind is deferred.
function RefreshIdentityVisibilityForToken(isMatch)
    local changed = false
    for _, record in ipairs(records) do
        if isMatch(record.unit) then
            changed = RefreshSlotIdentityVisibility(record) or changed
        end
    end
    for _, record in ipairs(blockRecords) do
        if isMatch(record.unit) then
            changed = RefreshBlockIdentityVisibility(record) or changed
        end
    end
    if RefreshPanelIdentityVisibilityForToken then
        changed = RefreshPanelIdentityVisibilityForToken(isMatch) or changed
    end
    return changed
end

function CooldownCompanion:RefreshAuraIdentityVisibility(unit)
    if unit then
        return RefreshIdentityVisibilityForToken(function(token)
            return token == unit
        end)
    end
    return RefreshIdentityVisibilityForToken(function() return true end)
end

-- The watcher-side half of the token refresh (forward-declared above the
-- watchers). Same container-level call the slot loop makes: sanctioned
-- combat surface, and hidden containers self-heal on show regardless.
function RefreshBlockRecordsForToken(isMatch)
    for _, record in ipairs(blockRecords) do
        if isMatch(record.unit) then
            record.container:UpdateAllAuras()
        end
    end
end

local function ApplyBlockMount(record)
    local getMount = ST._GetCustomBarAuraBlockMount
    if not getMount then return false end
    local parent, point, x, y, level = getMount(record.side)
    if not parent then return false end
    -- ONE point: the container's extent is secret from its first group, so a
    -- second point would ask the engine to reconcile a secret size against a
    -- CC-side one. Position only — the size is Blizzard's.
    record.container:ClearAllPoints()
    record.container:SetPoint(point, parent, point, x, y)
    record.container:SetFrameLevel(level)
    return true
end

-- The second bucket's mount: same one-point rule, but the anchor is the
-- FIRST bucket's container rather than the stack container, so this bucket
-- rides a secret extent instead of a CC-side offset. Legal only because both
-- containers carry DisableUntrustedLayoutScriptsTemplate — callers must have
-- checked `chainable` on both.
local function ApplyBlockChainMount(record, anchorRecord)
    local getMount = ST._GetCustomBarAuraBlockChainMount
    if not getMount then return false end
    local point, relPoint, x, y, level = getMount(record.side)
    if not point then return false end
    record.container:ClearAllPoints()
    record.container:SetPoint(point, anchorRecord.container, relPoint, x, y)
    record.container:SetFrameLevel(level)
    return true
end

-- Re-anchor every existing container from the current contract. Container
-- geometry is OOC-only (the validated combat surface is container METHODS),
-- so every call site gates on InCombatLockdown; in combat a moved stack just
-- leaves the block stale until the deferred rebind. A chained record
-- re-anchors to its anchor container, never to the stack mount.
function ST._SyncCustomBarAuraBlockMounts()
    for _, record in ipairs(blockRecords) do
        if record.chainAnchor then
            ApplyBlockChainMount(record, record.chainAnchor)
        else
            ApplyBlockMount(record)
        end
    end
end

-- The TAIL of a side's chain, for a trailing frame (cast bar) to hang off.
-- The chained record is by construction the far bucket whichever order the
-- side binds in, so it wins; a lone bucket is the whole block. CC-side shown
-- flag, never an IsShown read.
function ST._GetCustomBarAuraBlockContainer(side)
    local head
    for _, record in ipairs(blockRecords) do
        if record.side == side and record.shown and record.identityVisible then
            if record.chainAnchor then return record.container end
            head = head or record.container
        end
    end
    return head
end

local function EnsureBlockContainer(side, unit)
    local key = side .. "\031" .. unit
    local record = blockContainers[key]
    if record then return record end
    local flow = BLOCK_FLOW[side]
    if not flow then return nil end
    -- Parented through a plain CC visibility root beneath the custom-bar aura
    -- host. The host still carries resource-stack state and alpha; the extra
    -- parent is only the fail-closed identity switch.
    -- Both templates, always: DisableUntrustedLayoutScriptsTemplate is what
    -- lets a second container anchor to this one's edge and ride its secret
    -- size, and which container ends up serving as a chain anchor is not
    -- known at creation time.
    local hostRoot = CooldownCompanion:GetCustomBarAuraHostRoot()
    local visibilityRoot = CreateFrame("Frame", nil, hostRoot)
    visibilityRoot:Hide()
    local container = CreateFrame("AuraContainer", nil,
        visibilityRoot,
        "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
    -- Seed only; Blizzard resizes from its own layout pass once a group
    -- exists, and that size is never CC's to read.
    container:SetSize(1, 1)
    container:SetUnit(unit)
    container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis[flow.axis])
    container:SetFlowLayoutAnchorPoint(flow.anchor)
    container:SetFlowLayoutGrowthDirection(
        AnchorUtil.FlowDirection[flow.h], AnchorUtil.FlowDirection[flow.v])
    container:SetFlowLayoutPadding(0, 0, 0, 0)
    container:Hide()
    record = {
        side = side,
        unit = unit,
        container = container,
        visibilityRoot = visibilityRoot,
        -- Stamped at creation, never inferred later: a container built before
        -- this rule (same session, code swapped under a live client) has no
        -- way back to the aspect, and anchoring one errors.
        chainable = true,
        groups = {},
        groupList = {},
    }
    blockContainers[key] = record
    blockRecords[#blockRecords + 1] = record
    EnsureIdentityWatcher()
    if unit == "target" then
        EnsureTargetWatcher()
    end
    return record
end

-- The geometry every host of a group carries. Explicit numbers throughout:
-- the frame's own size is what Blizzard's flow layout reserves space for
-- (GetElementSize prefers the group's elementWidth/Height but never resizes
-- the frame), so the two must be written from the same source every bind.
local function ApplyBlockHostGeometry(group, host)
    host.frame:SetSize(group.frameWidth, group.frameHeight)
    -- The holder split, mirrored: the proxy (statusBar mount) sits INSIDE the
    -- border ring so the kit fill never paints over it, while the bounds
    -- child spans the full rect for the shell bg/border replicas. Single
    -- points + explicit sizes; the group frame's size is CC's, its position
    -- is Blizzard's.
    local inset = group.inset or 0
    local innerW = group.frameWidth - inset * 2
    local innerH = group.frameHeight - inset * 2
    if innerW < 1 then innerW = 1 end
    if innerH < 1 then innerH = 1 end
    local proxy = host.proxy
    proxy:ClearAllPoints()
    proxy:SetPoint("TOPLEFT", host.frame, "TOPLEFT", inset, -inset)
    proxy:SetSize(innerW, innerH)
    proxy._isVertical = group.isVertical
    proxy._ccKitRectW = innerW
    proxy._ccKitRectH = innerH
    local bounds = proxy._ccBounds
    bounds:ClearAllPoints()
    bounds:SetPoint("TOPLEFT", proxy, "TOPLEFT", -inset, inset)
    bounds:SetSize(group.frameWidth, group.frameHeight)
end

-- One host per pooled group frame. Blizzard pre-creates a batch of frames at
-- AddAuraGroup and runs this for each, so every frame the group can ever
-- assign leaves here with a finished kit — nothing is built later, in combat,
-- or on a frame CC has not seen. maxFrameCount 1 keeps the group inside that
-- batch forever (see EnsureBlockGroup).
--
-- The proxy is the bar-host descriptor the kit vocabulary needs
-- (statusBar/_barBounds/orientation/explicit rect dims). It lives UNDER the
-- group frame on purpose: the frame's position is Blizzard-owned and secret,
-- so a descriptor anchored anywhere else would drag every host-anchored kit
-- region off the bar. It is CC-created and never registered, so it carries no
-- secrets of its own.
local function BuildBlockGroupHost(group, frame)
    local proxy = CreateFrame("Frame", nil, frame)
    proxy:EnableMouse(false)
    proxy._ccAuraHostKind = "customBar"
    proxy._isBar = true
    proxy.statusBar = proxy
    proxy._cdcClickThroughMotion = true
    -- Full-footprint bounds for the shell replicas, like the holders'
    -- _ccBounds; the proxy itself mounts inside the border ring
    -- (ApplyBlockHostGeometry owns both rects).
    proxy._ccBounds = CreateFrame("Frame", nil, proxy)
    proxy._ccBounds:EnableMouse(false)
    proxy._barBounds = proxy._ccBounds
    local host = { frame = frame, proxy = proxy, kit = BuildSlotKit(frame) }
    -- On the slot path the whole kit anchors to the BUTTON, and the button
    -- itself is mounted on the inset holder — the border inset arrives
    -- through button geometry. Block buttons are full-rect and
    -- Blizzard-positioned, so everything button-anchored must move to the
    -- inset proxy instead, or fills paint over the border ring. Creation
    -- window only — never re-anchored after registration.
    local kit = host.kit
    local inner = {
        kit.iconCover, kit.auraIcon, kit.swipe, kit.barBackdrop,
        kit.barFill, kit.stackFill, kit.textOverlay,
    }
    for i = 1, #inner do
        local region = inner[i]
        if region then
            region:ClearAllPoints()
            region:SetAllPoints(proxy)
        end
    end
    ApplyBlockHostGeometry(group, host)
    group.hosts[#group.hosts + 1] = host
end

-- SetAuraGroupLayout REPLACES the whole options table, so every field the
-- group needs is written every time. elementSpacing must stay 0: the flow
-- layout advances the cursor by elementSpacing after an element AND adds
-- groupSpacing before the next group, so a nonzero pair doubles every gap
-- between consecutive single-frame groups (seen in game 2026-08-08).
-- groupSpacing alone carries the stack's own spacing.
local function BlockGroupLayout(entry, layoutIndex)
    return {
        layoutIndex = layoutIndex,
        elementWidth = entry.width,
        elementHeight = entry.height,
        elementSpacing = 0,
        groupSpacing = entry.spacing,
    }
end

local function EnsureBlockGroup(record, entry, layoutIndex)
    local group = record.groups[entry.id]
    if group then
        group.frameWidth = entry.width
        group.frameHeight = entry.height
        group.isVertical = entry.vertical
        group.inset = entry.inset
        record.container:SetAuraGroupLayout(entry.id, BlockGroupLayout(entry, layoutIndex))
        return group
    end
    group = {
        key = entry.id,
        record = record,
        unit = record.unit,
        hosts = {},
        parked = true,
        frameWidth = entry.width,
        frameHeight = entry.height,
        isVertical = entry.vertical,
        inset = entry.inset,
    }
    -- maxFrameCount 1 is structural, not a display choice: a group that could
    -- outgrow its pre-created batch would run AcquireFrame -> CreateFrameBatch
    -- -> initializeFrame IN COMBAT, from tainted code, on a forbidden subtree.
    -- Born parked like a slot; the bind below writes the real contract.
    record.container:AddAuraGroup(entry.id, SlotContract(record.unit).filter, {
        candidateFilters = BuildParkFilters(record.unit),
        maxFrameCount = 1,
        layout = BlockGroupLayout(entry, layoutIndex),
        initializeFrame = function(frame)
            BuildBlockGroupHost(group, frame)
        end,
    })
    record.groups[entry.id] = group
    record.groupList[#record.groupList + 1] = group
    return group
end

-- Park = zero frames PLUS the polarity-crossed sentinel, the group analog of
-- ParkDisplay. The container is hidden by the pass when a side keeps nothing;
-- a side that still renders something cannot hide its container, so the
-- sentinel is what keeps a retired entry dark inside a live one.
local function ParkBlockGroup(group)
    if group.parked then return end
    group.parked = true
    group.boundEntry = nil
    group.boundStackMax = nil
    ReleaseSlotAuraSounds(group)
    local container = group.record.container
    container:SetAuraGroupMaxFrameCount(group.key, 0)
    container:SetAuraGroupCandidateFilters(group.key, BuildParkFilters(group.unit))
end

local function BindBlockGroup(group, entry)
    local container = group.record.container
    container:SetAuraGroupMaxFrameCount(group.key, 1)
    -- Converge the whole contract every bind, exactly like the slot path: the
    -- filter string, the candidate set and the park sentinel all come from
    -- one source, so they can never drift apart.
    container:SetAuraGroupFilterString(group.key, SlotContract(group.unit).filter)
    container:SetAuraGroupCandidateFilters(group.key,
        BuildCandidateFilters(group.unit, entry.spellSet))
    group.boundStackMax = entry.stackBarMax
    -- Re-style every owned frame, not just the assigned one: initializeFrame
    -- ran once per pooled frame at group creation, and which frame the group
    -- hands out next is Blizzard's business.
    for _, host in ipairs(group.hosts) do
        ApplyBlockHostGeometry(group, host)
        ConvergeApplicationBar(host.frame, host.kit, entry.buttonData, entry.stackBarMax)
        ConvergeApplicationCount(host.frame, host.kit, entry.buttonData)
        StyleSlotKit({
            kit = host.kit,
            slotButton = host.frame,
            unit = group.unit,
            boundStackMax = entry.stackBarMax,
        }, host.proxy, entry.buttonData, entry.style)
        -- Resource bars never show aura tooltips (their CC holders are
        -- click-through), and pooled frames are reused across entries, so the
        -- untouched-button defaults are converged every bind.
        host.frame:SetMouseMotionEnabled(false)
        host.frame:SetTooltipAnchorPoint("ANCHOR_NONE", 0, 0)
        host.frame:SetHideTooltipInCombat(true)
    end
    RegisterSlotAuraSounds(group, entry.buttonData, entry.spellSet)
    group.parked = nil
    group.boundEntry = entry.buttonData
end

-- One unit bucket of one side. `anchorRecord` nil means this bucket takes the
-- stack-end mount; non-nil means it chains off that bucket's trailing edge.
-- Returns the bound record, or nil when nothing could be mounted.
local function BindBlockBucket(side, unit, entries, anchorRecord)
    -- Mounting an incompatible unit would let Blizzard ignore includeSpellIDs
    -- for every non-exempt aura candidate. Leave the whole unit bucket parked;
    -- the reaction watcher requests another topology pass if it becomes safe.
    local record = EnsureBlockContainer(side, unit)
    if not record then return nil end
    record.identityApplicable = CanApplySpellIdentityFilter(unit)
    if not record.identityApplicable then return nil end
    local mounted
    if anchorRecord then
        if not (record.chainable and anchorRecord.chainable) then
            -- A container from before the dual-template rule cannot be
            -- anchored to or from: the call errors on the forbidden aspect,
            -- and an error inside the aura refresh pipeline freezes the whole
            -- display until reload. So this bucket simply does not render
            -- this session; /reload rebuilds every container chainable.
            blockChainBlocked = blockChainBlocked + #entries
            return nil
        end
        mounted = ApplyBlockChainMount(record, anchorRecord)
        if mounted then record.chainAnchor = anchorRecord end
    else
        mounted = ApplyBlockMount(record)
    end
    if not mounted then return nil end
    local layoutIndex = 0
    for _, entry in ipairs(entries) do
        layoutIndex = layoutIndex + 1
        BindBlockGroup(EnsureBlockGroup(record, entry, layoutIndex), entry)
    end
    record.container:Show()
    record.shown = true
    record.identityApplicable = true
    SetIdentityVisibility(record, true)
    return record
end

-- Park everything, then bind — the same discipline (and the same coalescing
-- argument) as the slot pass above. OOC by RunAuraRebind's guarantee, which
-- is also what makes the chain anchor legal here: it is container geometry.
local function RebindCustomBarAuraBlocks(self)
    for _, record in ipairs(blockRecords) do
        for _, group in ipairs(record.groupList) do
            ParkBlockGroup(group)
        end
        record.container:Hide()
        record.shown = false
        SetIdentityVisibility(record, false)
        record.chainAnchor = nil
    end
    blockChainBlocked = 0
    local collect = ST._CollectCustomBarAuraBlockWants
    if not collect then return end
    for _, want in ipairs(collect()) do
        -- Split the side's ordered entry list into per-unit buckets. Appending
        -- in list order is what preserves each bucket's relative order; the
        -- buckets themselves never interleave, and want.targetFirst decides
        -- which of the two sits nearer the panel.
        local playerEntries, targetEntries
        for _, entry in ipairs(want.entries) do
            if entry.unit == "target" then
                targetEntries = targetEntries or {}
                targetEntries[#targetEntries + 1] = entry
            else
                playerEntries = playerEntries or {}
                playerEntries[#playerEntries + 1] = entry
            end
        end
        -- Every entry's unit was resolved ONCE at partition time and rides the
        -- contract, so this pass can never re-derive a different answer.
        local firstUnit, firstEntries = "player", playerEntries
        local secondUnit, secondEntries = "target", targetEntries
        if want.targetFirst then
            firstUnit, firstEntries = "target", targetEntries
            secondUnit, secondEntries = "player", playerEntries
        end
        local anchorRecord
        if firstEntries then
            anchorRecord = BindBlockBucket(want.side, firstUnit, firstEntries, nil)
        end
        if secondEntries then
            -- The chain exists only while BOTH buckets are populated: a hidden
            -- container is not something to hang geometry off, so a one-bucket
            -- side takes the stack-end mount itself.
            BindBlockBucket(want.side, secondUnit, secondEntries, anchorRecord)
        end
    end
end

------------------------------------------------------------------------
-- AURA PANELS — whole panels (icon or bar) whose every entry is an aura.
--
-- The block section above hangs aura groups off ONE side of the resource
-- stack. This one does the same thing to a PANEL: an Aura Panel materializes
-- no CC buttons at all (GroupFrame's PopulateGroupButtons short-circuits),
-- and instead mounts ONE AuraContainer under its group frame with ONE aura
-- group per entry. Blizzard's flow layout packs only the ACTIVE ones, so an
-- inactive entry takes no space and the survivors close up — which is the
-- whole point of the panel subtype and the one thing CC's own layout can
-- never do, because aura presence is secret.
--
-- Everything the blocks section establishes applies here unchanged:
--   * Containers and groups are APPEND-ONLY. There is no removal API, so a
--     retired entry's group is PARKED (maxFrameCount 0 + the polarity-crossed
--     sentinel), never deleted, and a record whose panel frame was replaced is
--     ABANDONED rather than reparented (see EnsurePanelContainer).
--   * maxFrameCount 1 per group is structural: a group that could outgrow its
--     pre-created frame batch would run initializeFrame from tainted code, in
--     combat, on a forbidden subtree.
--   * All of it runs OOC inside RunAuraRebind. The only combat-time calls are
--     the container-level UpdateAllAuras the token watchers make, and Show/Hide
--     on the panel's own plain visibilityRoot (see ApplyPanelRootVisibility) —
--     no container or aura-group API is ever touched in combat.
--   * Every container carries DisableUntrustedLayoutScriptsTemplate alongside
--     CustomAuraContainerTemplate, matching the blocks — the panel never
--     anchors one container to another today, but the aspect has to be stamped
--     at creation (there is no way back to it later).
--
-- What is new here is the GRID. The panel frame is sized to the FULL expanded
-- grid (GetAuraPanelGridMetrics) so its footprint holds still while auras come
-- and go, and the container is mounted at the growth-origin corner of that
-- frame with a flow layout configured to fill the same cells in the same order
-- CC's own GetAuraPanelCellSlot walks. Get that mapping wrong and the unlock
-- placeholders sit somewhere the real auras never appear.
--
-- One container per (PANEL, unit). The unit is derived from the panel's first
-- resolvable aura entry (GetAuraPanelUnit) and the creation surfaces refuse
-- entries of the other polarity, so in practice a panel has exactly one — but
-- imported config can still carry a stray, and those entries are counted and
-- skipped rather than bound onto the wrong unit's container.
------------------------------------------------------------------------

-- growthOrigin -> the flow layout's anchor corner and its two growth signs.
-- The anchor decides the FILL ORDER inside the block (and which edge a partial
-- line hugs) — the same convention GetGrowthMultipliers encodes for the
-- CC-side grid (TOPLEFT = +x/-y, TOPRIGHT = -x/-y, and so on). Where the packed
-- block SITS on the panel's fixed footprint is a separate, user-picked
-- question: ApplyPanelMount folds the panel's growth direction into the one
-- point the container hangs from, so the block can hug the growth corner
-- ("start", which resolves to exactly this anchor), stay centered ("center",
-- the ruled default) or hug the far end ("end"). growthOrigin is nil on older
-- panels; GetGrowthMultipliers treats nil as TOPLEFT, so this table's fallback
-- must agree.
local PANEL_FLOW = {
    TOPLEFT = { anchor = "TOPLEFT", h = "Right", v = "Down" },
    TOPRIGHT = { anchor = "TOPRIGHT", h = "Left", v = "Down" },
    BOTTOMLEFT = { anchor = "BOTTOMLEFT", h = "Right", v = "Up" },
    BOTTOMRIGHT = { anchor = "BOTTOMRIGHT", h = "Left", v = "Up" },
}

local panelContainers = {} -- groupId .. "\031" .. unit -> panel record
local panelRecords = {}    -- flat, append-only list of every panel record

-- Per-pass skip tallies, rewritten by every bind pass and surfaced in
-- GetAuraDisplayStatus. These are the only way to see an entry that silently
-- did not render: a nonzero count is stored config the display cannot serve,
-- not a runtime fault.
local panelSkippedNoKey = 0
local panelUnitMismatches = 0
local panelNoCandidates = 0
-- Two entries in ONE panel carrying the same _auraKey. The engine keys its aura
-- groups by that string, so the second entry binds onto the FIRST one's group
-- instead of getting its own: the later contract wins and the earlier entry
-- stops rendering, with nothing else on screen to say so. Every creation path
-- stamps a fresh key (and the config normalizer backfills missing ones), so
-- only a hand-crafted payload can produce this -- which is exactly why it needs
-- a number rather than staying invisible.
local panelDuplicateKeys = 0

-- TOPOLOGY vs PRESENTATION.
--
-- A panel's groups bind regardless of its lock state, and they have to: the
-- bind pass is OOC-only (RunAuraRebind), while the drag chrome comes down at
-- the combat pull. Keying the BIND on the chrome meant a panel unlocked at the
-- pull stayed parked for the whole fight — nothing could re-bind it until
-- combat ended and it re-locked.
--
-- What the chrome legitimately changes is PRESENTATION: while WP3's unlock
-- placeholders are on screen they ARE the panel's visual, and a live container
-- underneath would double-draw the entries whose auras are up.
--
-- Both suppression reasons land on the same frame — the visibilityRoot is the
-- only handle CC owns over this subtree — so they are combined here instead of
-- overwriting each other. Identity stays FAIL-CLOSED: an incompatible unit
-- relationship hides the root in every chrome state. The root is a plain CC
-- frame, so the chrome term is a legal combat-time write, which is exactly what
-- lets the forced lock hand the panel back to its live display at the pull with
-- no rebind at all.
local function ApplyPanelRootVisibility(record)
    record.visibilityRoot:SetShown(
        record.identityVisible == true and record.chromeSuppressed ~= true)
end

-- The panel-local twin of SetIdentityVisibility: same bookkeeping, same
-- "changed" contract, one extra term. Blocks and slots keep the shared helper
-- untouched — they have no second suppression reason.
local function SetPanelIdentityVisibility(record, shown)
    shown = shown == true
    local changed = record.identityVisible ~= shown
    record.identityVisible = shown
    ApplyPanelRootVisibility(record)
    return changed
end

-- The chrome writers' one entry point, called at the moment a writer changes a
-- panel's drag chrome and never polled. Three writers exist:
-- SetGroupDragControlsShown (the ordinary lock/unlock path) and the combat
-- forced-lock pair, which suppresses and restores the chrome directly without
-- going through it.
--
-- The state lives on the FRAME because that is what the chrome belongs to: a
-- record created later reads the current answer at birth (EnsurePanelContainer)
-- instead of starting unsuppressed, and every bind pass re-reads it
-- (BindAuraPanel), so a park-all/bind cycle that straddled a lock change
-- converges rather than carrying a stale term.
function CooldownCompanion:SetAuraPanelChromeSuppressed(frame, suppressed)
    if not frame then return end
    suppressed = suppressed == true
    if (frame._auraPanelChromeSuppressed == true) == suppressed then return end
    frame._auraPanelChromeSuppressed = suppressed or nil
    for _, record in ipairs(panelRecords) do
        if record.hostFrame == frame then
            record.chromeSuppressed = suppressed
            ApplyPanelRootVisibility(record)
        end
    end
end

local function RefreshPanelIdentityVisibility(record)
    local applicable = CanApplySpellIdentityFilter(record.unit)
    local changed = record.identityApplicable ~= applicable
    record.identityApplicable = applicable
    return SetPanelIdentityVisibility(record, record.shown == true and applicable) or changed
end

-- The two watcher-side halves (both forward-declared above the watchers).
-- Identical in shape to the block versions on purpose: a panel tracking the
-- target has exactly the same same-token staleness problem a target-scoped
-- block does, and the same fail-closed relationship gate.
function RefreshPanelIdentityVisibilityForToken(isMatch)
    local changed = false
    for _, record in ipairs(panelRecords) do
        if isMatch(record.unit) then
            changed = RefreshPanelIdentityVisibility(record) or changed
        end
    end
    return changed
end

function RefreshPanelRecordsForToken(isMatch)
    for _, record in ipairs(panelRecords) do
        if isMatch(record.unit) then
            record.container:UpdateAllAuras()
        end
    end
end

-- The flow contract for one panel: mount corner + growth signs, the layout
-- axis, and the line ceiling that makes the container wrap where CC's grid
-- wraps. Returns flow, axis, maximumLineSize (nil = no ceiling).
--
-- The axis has to agree with GetAuraPanelCellSlot's fill order, which is the
-- order the unlock placeholders are laid out in:
--   * icons, horizontal orientation: col advances first, wrapping to the next
--     row -> the primary axis is X (Horizontal).
--   * icons, vertical orientation: ROW advances first, wrapping to the next
--     column -> the primary axis is Y (Vertical), and buttonsPerRow counts
--     cells per COLUMN.
--   * bars: a single column, always (buttonsPerRow has no meaning for a bar
--     list) -> Vertical with no ceiling at all.
--
-- maximumLineSize is measured along the PRIMARY axis, so the cell's primary
-- dimension is its width on the horizontal axis and its height on the vertical
-- one. The ceiling has to land in the half-open window
-- [N*W + (N-1)*S, N*W + N*S): the flow layout wraps when the accumulated line
-- size PLUS the next group's groupSpacing exceeds it, so anything at or above
-- the low end fits N cells and anything below the high end refuses N+1. Half a
-- spacing above the low end is the middle of that window, and the max(S, 1)
-- floor keeps it a real gap when the panel's spacing is 0 (where the wrap
-- happens at the element step instead, W being far larger than 0.5).
local function PanelFlowSpec(group, cellWidth, cellHeight, spacing)
    local style = group.style or {}
    local flow = PANEL_FLOW[style.growthOrigin] or PANEL_FLOW.TOPLEFT
    if group.displayMode == "bars" then
        return flow, "Vertical", nil
    end
    local horizontal = ST.GetPanelLayoutOrientation(group.displayMode, style) == "horizontal"
    local perLine = math.max(1, style.buttonsPerRow or 12)
    local primary = horizontal and cellWidth or cellHeight
    return flow,
        horizontal and "Horizontal" or "Vertical",
        perLine * primary + (perLine - 1) * spacing + math.max(spacing, 1) * 0.5
end

-- An Aura Panel stores its collapse direction in the panel's own
-- compactGrowthDirection key — the same key, the same three values and the same
-- vocabulary the 12.0 compact-mode option used, because it is the same question
-- ("which end does the packed block hold?") answered by a different engine.
-- CC's compact layout never runs on an Aura Panel (compactLayout is forced
-- false at birth), so the key is this display's alone in practice. GroupFrame's
-- NormalizeCompactGrowthDirection is file-local, so this repeats the fold
-- rather than reaching across for it; both must stay the same three-way.
local function NormalizePanelGrowthDirection(growthDirection)
    if growthDirection == "start" or growthDirection == "left" or growthDirection == "top" then
        return "start"
    end
    if growthDirection == "end" or growthDirection == "right" or growthDirection == "bottom" then
        return "end"
    end
    return "center"
end

-- ONE point (owner ruling 2026-08-15): the container's extent becomes secret
-- with its first group (Blizzard resizes it from its own layout pass), so a
-- second point would ask the engine to reconcile a secret size against a
-- CC-side one. Anchor resolution is engine-side too, which is what makes a
-- single point enough: whichever point CC hangs the container from, the engine
-- re-resolves the packed block against the panel's fixed footprint every time
-- its secret size changes. So that ONE point is the whole collapse behaviour,
-- and the owner picks it.
--
-- The direction runs along the PRIMARY (flow) axis. The CROSS axis always stays
-- pinned at the growth-origin edge, so a multi-row icon grid keeps its first
-- row where the unlock placeholders promised it instead of drifting as rows
-- appear. "start" resolves to flow.anchor exactly — the old corner-pinned
-- behaviour — "center" is the ruled default, and "end" pins the far side so the
-- block fills backwards toward the origin. When every aura is up the content
-- rect equals the frame rect, so all three land on exactly the cells the
-- placeholders promise.
local function ApplyPanelMount(record, flow, axis, direction)
    local point
    if axis == "Horizontal" then
        -- Cross axis is Y: the edge the rows stack away from.
        local cross = flow.v == "Down" and "TOP" or "BOTTOM"
        if direction == "center" then
            point = cross
        elseif direction == "end" then
            point = cross .. (flow.h == "Right" and "RIGHT" or "LEFT")
        else
            point = cross .. (flow.h == "Right" and "LEFT" or "RIGHT")
        end
    else
        -- Cross axis is X: the edge the columns stack away from (a bar list has
        -- exactly one column, so this is simply the side it hangs on).
        local cross = flow.h == "Right" and "LEFT" or "RIGHT"
        if direction == "center" then
            point = cross
        elseif direction == "end" then
            point = (flow.v == "Down" and "BOTTOM" or "TOP") .. cross
        else
            point = (flow.v == "Down" and "TOP" or "BOTTOM") .. cross
        end
    end
    record.container:ClearAllPoints()
    record.container:SetPoint(point, record.visibilityRoot, point, 0, 0)
end

local function EnsurePanelContainer(groupId, unit, hostFrame)
    local key = groupId .. "\031" .. unit
    local record = panelContainers[key]
    if record then
        if record.hostFrame == hostFrame then return record end
        -- The panel's group frame was discarded and rebuilt under the same id.
        -- A container can never follow it: SetParent on the AuraButtons beneath
        -- it errors even out of combat (the permanent ChangeParent aspect), and
        -- there is no way to take the groups back. So the old record is
        -- ABANDONED — it stays in panelRecords, where the pass keeps it parked
        -- and hidden forever, and a fresh record takes the key. Bounded leak,
        -- the same doctrine the block records use, and unreachable in normal
        -- play (CC pools group frames rather than destroying them).
        panelContainers[key] = nil
    end
    -- Parented through a plain CC visibility root beneath the panel's group
    -- frame, so panel alpha, fades, load-condition hides and strata all reach
    -- the display through ordinary parentage. The root is the fail-closed
    -- identity switch and nothing else.
    --
    -- _ccNoTouch on both: PropagateFrameStrata and the click-through sweep both
    -- recurse into a group frame's children, and neither may reach an aura
    -- subtree. Flagging the root stops the walk; flagging the container too
    -- means any future walk that starts lower still stops.
    local visibilityRoot = CreateFrame("Frame", nil, hostFrame)
    visibilityRoot._ccNoTouch = true
    visibilityRoot:SetAllPoints(hostFrame)
    visibilityRoot:Hide()
    local container = CreateFrame("AuraContainer", nil,
        visibilityRoot,
        "CustomAuraContainerTemplate, DisableUntrustedLayoutScriptsTemplate")
    container._ccNoTouch = true
    -- Seed only; Blizzard resizes from its own layout pass once a group
    -- exists, and that size is never CC's to read.
    container:SetSize(1, 1)
    container:SetUnit(unit)
    container:Hide()
    record = {
        key = key,
        groupId = groupId,
        unit = unit,
        container = container,
        visibilityRoot = visibilityRoot,
        -- Identity of the frame this container is welded to. Compared, never
        -- followed; see the abandon path above.
        hostFrame = hostFrame,
        -- Seeded from the frame, never assumed false: a panel created (or
        -- rebuilt) while its drag chrome is up must not flash its live display
        -- over the placeholders before the next chrome write.
        chromeSuppressed = hostFrame._auraPanelChromeSuppressed == true,
        groups = {},
        groupList = {},
    }
    panelContainers[key] = record
    panelRecords[#panelRecords + 1] = record
    EnsureIdentityWatcher()
    if unit == "target" then
        EnsureTargetWatcher()
    end
    return record
end

-- The bar cell's icon square, in BarMode's own vocabulary (CreateBarFrame):
-- the square is as thick as the bar unless the size override is on, it sits at
-- the LEADING edge (left on a horizontal bar, top on a vertical one; the far
-- end when barIconReverse is set), and barIconOffset is the gap between the
-- square and the fill. Returns shown, size, offset, reverse.
--
-- Cell dimensions are the PANEL's and uniform across it by construction, so an
-- entry override of the icon keys only changes what happens INSIDE that
-- entry's cell — never the cell's footprint. Size and gap are both clamped to
-- leave at least a 1px bar area: BarMode lets an oversized icon overflow its
-- own bar, but a degenerate fill rect here would be a layout error on a frame
-- Blizzard lays out.
local function PanelBarIconGeometry(style, isBar, isVertical, cellWidth, cellHeight)
    if not (isBar and style.showBarIcon ~= false) then return false end
    local thickness = isVertical and cellWidth or cellHeight
    local length = isVertical and cellHeight or cellWidth
    local size = (style.barIconSizeOverride and style.barIconSize) or thickness
    size = math.max(1, math.min(size, length - 1))
    local offset = math.max(0, math.min(style.barIconOffset or 0, length - size - 1))
    return true, size, offset, style.barIconReverse == true
end

-- The geometry every host of a group carries. Explicit numbers throughout: the
-- frame's own size is what the flow layout reserves space for (GetElementSize
-- prefers the group's elementWidth/Height but never resizes the frame), so the
-- two are written from the same source every bind.
--
-- No border inset, unlike the block hosts: a block sits inside a CC bar's own
-- border ring, while a panel cell has nothing underneath at all — the kit's
-- shell replicas draw the ring themselves, over the full cell. The icon square
-- follows the same rule (inset 0 on the square and its bounds alike), so a bar
-- cell's two chrome sets sit exactly where the icon cell's single one does.
--
-- The bar-host descriptor is re-stamped here rather than at creation because an
-- Aura Panel can be switched between its icon and bar forms, and the pooled
-- group frames (and their proxies) outlive that switch. The BAR AREA and the
-- icon square move with it: the kit's registered regions are anchored to the
-- bar area once, in the creation window, and everything that has to move per
-- bind moves by moving these two plain CC frames instead.
local function ApplyPanelHostGeometry(pgroup, host)
    host.frame:SetSize(pgroup.frameWidth, pgroup.frameHeight)
    local proxy = host.proxy
    proxy:ClearAllPoints()
    proxy:SetPoint("TOPLEFT", host.frame, "TOPLEFT", 0, 0)
    proxy:SetSize(pgroup.frameWidth, pgroup.frameHeight)
    local barArea, iconBounds = proxy._ccBarArea, proxy._iconBounds
    local barW, barH = pgroup.frameWidth, pgroup.frameHeight
    barArea:ClearAllPoints()
    iconBounds:ClearAllPoints()
    if pgroup.isBar and pgroup.iconShown then
        local reverse = pgroup.iconReverse
        local step = pgroup.iconSize + pgroup.iconOffset
        -- Square centered on the cross axis at the leading edge, bar area
        -- taking the remainder — SetIconAreaPoints / SetBarAreaPoints with
        -- inset 0, written as explicit numbers because this rect is CC's.
        iconBounds:SetSize(pgroup.iconSize, pgroup.iconSize)
        if pgroup.isVertical then
            local iconEdge, barEdge = "TOP", "BOTTOM"
            if reverse then iconEdge, barEdge = "BOTTOM", "TOP" end
            iconBounds:SetPoint(iconEdge, proxy, iconEdge, 0, 0)
            barH = math.max(pgroup.frameHeight - step, 1)
            barArea:SetPoint(barEdge, proxy, barEdge, 0, 0)
        else
            local iconEdge, barEdge = "LEFT", "RIGHT"
            if reverse then iconEdge, barEdge = "RIGHT", "LEFT" end
            iconBounds:SetPoint(iconEdge, proxy, iconEdge, 0, 0)
            barW = math.max(pgroup.frameWidth - step, 1)
            barArea:SetPoint(barEdge, proxy, barEdge, 0, 0)
        end
    else
        -- Icon cells, and bars with the square switched off: the bar area IS
        -- the cell, and the square is parked (nothing anchors to it, and it
        -- draws nothing of its own — only the kit's replicas ever ring it).
        iconBounds:SetSize(1, 1)
        iconBounds:SetPoint("TOPLEFT", proxy, "TOPLEFT", 0, 0)
        barArea:SetPoint("TOPLEFT", proxy, "TOPLEFT", 0, 0)
    end
    barArea:SetSize(barW, barH)
    if pgroup.isBar then
        proxy._isBar = true
        proxy.statusBar = barArea
        proxy._barBounds = barArea
    else
        proxy._isBar = nil
        proxy.statusBar = nil
        proxy._barBounds = nil
    end
    proxy._isVertical = pgroup.isVertical
    -- Explicit rect dims: a Blizzard-laid group frame must never be measured,
    -- and the kit's crop/dash/segment math asks for these first. They describe
    -- the BAR AREA, which is what that math is about (fill length, stack
    -- boundaries, capacity blocks) — the icon square is never part of it.
    proxy._ccKitRectW = barW
    proxy._ccKitRectH = barH
end

-- The icon square's artwork. On the slot path the CC button underneath owns
-- button.icon, and StyleSlotKit reads its texture and crop for the occluding
-- cover while Blizzard writes the live aura texture into the registered
-- kit.auraIcon anchored over it. An Aura Panel has no CC button, so the host's
-- own square carries the entry's spell texture with BarMode's square crop and
-- the styler consumes it unchanged.
--
-- Cleared on every other flavor: with no texture on it the styler takes its
-- textureless path instead, which crops from the host rect dims and is exactly
-- what icon cells (and squareless bars) have always run.
local function ApplyPanelHostIcon(pgroup, host, buttonData, style)
    local icon = host.proxy.icon
    if pgroup.isBar and pgroup.iconShown
        and buttonData.type == "spell" and buttonData.id then
        icon:SetTexture(C_Spell.GetSpellTexture(buttonData.id))
        local ApplyIconTexCoord = ST._ApplyIconTexCoord
        if ApplyIconTexCoord then
            ApplyIconTexCoord(icon, pgroup.iconSize, pgroup.iconSize, style.iconZoom)
        end
    else
        icon:SetTexture(nil)
    end
end

-- One host per pooled group frame. Blizzard pre-creates a batch of frames at
-- AddAuraGroup and runs this for each, so every frame the group can ever assign
-- leaves here with a finished kit — nothing is built later, in combat, or on a
-- frame CC has not seen. maxFrameCount 1 keeps the group inside that batch
-- forever (see EnsurePanelGroup).
--
-- The proxy is the host descriptor the kit vocabulary needs, living UNDER the
-- group frame because the frame's position is Blizzard-owned and secret: a
-- descriptor anchored anywhere else would drag every host-anchored kit region
-- off the cell. It is CC-created and never registered, so it carries no secrets
-- of its own. `auraPanel` is what tells StyleSlotKit the kit is the ENTIRE
-- button here rather than an overlay on a CC one.
local function BuildPanelGroupHost(pgroup, frame)
    local proxy = CreateFrame("Frame", nil, frame)
    proxy:EnableMouse(false)
    proxy._ccAuraHostKind = "auraPanel"
    proxy._cdcClickThroughMotion = true
    -- The BAR AREA: the rect the kit's bar vocabulary owns — the cell MINUS
    -- the icon square on a bar cell that shows one, the whole cell everywhere
    -- else. One anchor target serves both flavors, which is what makes the
    -- square possible at all: registered kit regions may only be anchored in
    -- this creation window, so anything that has to move at bind time has to
    -- move by re-positioning a plain CC frame they are anchored TO. Pooled
    -- frames survive an icon <-> bar conversion, so that frame must exist on
    -- both flavors from the start.
    local barArea = CreateFrame("Frame", nil, proxy)
    barArea:EnableMouse(false)
    proxy._ccBarArea = barArea
    -- The icon square, mirroring BarMode's trio: _iconBounds is the square's
    -- rect (the kit's shell replicas ring it and back it), and `icon` is the
    -- field StyleSlotKit reads to decide the square participates at all — it
    -- re-anchors the aura icon and the occluding cover onto it every bind and
    -- takes its texture and crop for the cover. The square itself stays
    -- invisible: an Aura Panel has no CC layer, so everything that shows is
    -- drawn by the kit.
    local iconBounds = CreateFrame("Frame", nil, proxy)
    iconBounds:EnableMouse(false)
    proxy._iconBounds = iconBounds
    proxy.icon = proxy:CreateTexture(nil, "BACKGROUND")
    proxy.icon:SetAllPoints(iconBounds)
    proxy.icon:SetAlpha(0)
    local host = { frame = frame, proxy = proxy, kit = BuildSlotKit(frame) }
    -- Before the kit is anchored to it, so the bar area already carries the
    -- rect those anchors resolve against.
    ApplyPanelHostGeometry(pgroup, host)
    -- On the slot path the whole kit anchors to the BUTTON. Panel cells are
    -- Blizzard-positioned, so everything button-anchored moves to the bar area
    -- instead. Creation window only — never re-anchored after registration;
    -- the bar area moves in their place.
    local kit = host.kit
    local inner = {
        kit.iconCover, kit.auraIcon, kit.swipe, kit.barBackdrop,
        kit.barFill, kit.stackFill, kit.textOverlay,
    }
    for i = 1, #inner do
        local region = inner[i]
        if region then
            region:ClearAllPoints()
            region:SetAllPoints(barArea)
        end
    end
    pgroup.hosts[#pgroup.hosts + 1] = host
end

-- SetAuraGroupLayout REPLACES the whole options table, so every field the group
-- needs is written every time. elementSpacing must stay 0 for the same reason
-- the blocks keep it there: the flow layout advances the cursor by
-- elementSpacing after an element AND adds groupSpacing before the next group,
-- so a nonzero pair doubles every gap between consecutive single-frame groups.
-- groupSpacing carries the panel's own spacing along the line; lineSpacing
-- carries it across lines (groupLineSpacing defaults to lineSpacing, which
-- covers the wrap that groupSpacing itself triggers).
local function PanelGroupLayout(entry, layoutIndex)
    return {
        layoutIndex = layoutIndex,
        elementWidth = entry.width,
        elementHeight = entry.height,
        elementSpacing = 0,
        groupSpacing = entry.spacing,
        lineSpacing = entry.spacing,
    }
end

local function EnsurePanelGroup(record, entry, layoutIndex)
    local pgroup = record.groups[entry.id]
    if pgroup then
        pgroup.frameWidth = entry.width
        pgroup.frameHeight = entry.height
        pgroup.isVertical = entry.vertical
        pgroup.isBar = entry.isBar
        pgroup.iconShown = entry.iconShown
        pgroup.iconSize = entry.iconSize
        pgroup.iconOffset = entry.iconOffset
        pgroup.iconReverse = entry.iconReverse
        record.container:SetAuraGroupLayout(entry.id, PanelGroupLayout(entry, layoutIndex))
        return pgroup
    end
    pgroup = {
        key = entry.id,
        record = record,
        unit = record.unit,
        hosts = {},
        parked = true,
        frameWidth = entry.width,
        frameHeight = entry.height,
        isVertical = entry.vertical,
        isBar = entry.isBar,
        -- Set BEFORE AddAuraGroup below: initializeFrame runs inside it, and
        -- the host geometry it stamps reads these.
        iconShown = entry.iconShown,
        iconSize = entry.iconSize,
        iconOffset = entry.iconOffset,
        iconReverse = entry.iconReverse,
    }
    -- maxFrameCount 1 is structural, not a display choice: one entry is one
    -- aura, and a group that could outgrow its pre-created batch would run
    -- AcquireFrame -> CreateFrameBatch -> initializeFrame IN COMBAT, from
    -- tainted code, on a forbidden subtree. Born parked like a slot; the bind
    -- below writes the real contract.
    record.container:AddAuraGroup(entry.id, SlotContract(record.unit).filter, {
        candidateFilters = BuildParkFilters(record.unit),
        maxFrameCount = 1,
        layout = PanelGroupLayout(entry, layoutIndex),
        initializeFrame = function(frame)
            BuildPanelGroupHost(pgroup, frame)
        end,
    })
    record.groups[entry.id] = pgroup
    record.groupList[#record.groupList + 1] = pgroup
    return pgroup
end

-- Park = zero frames PLUS the polarity-crossed sentinel. A parked group
-- contributes no elements to the flow layout, so it also stops consuming
-- spacing: the entries around it close up exactly as if it were gone. That is
-- what makes "retire an entry" and "the aura is not up" render identically,
-- which they must, because CC can never tell the two apart.
local function ParkPanelGroup(pgroup)
    if pgroup.parked then return end
    pgroup.parked = true
    pgroup.boundEntry = nil
    pgroup.boundStackMax = nil
    ReleaseSlotAuraSounds(pgroup)
    local container = pgroup.record.container
    container:SetAuraGroupMaxFrameCount(pgroup.key, 0)
    container:SetAuraGroupCandidateFilters(pgroup.key, BuildParkFilters(pgroup.unit))
end

local function BindPanelGroup(pgroup, entry)
    local container = pgroup.record.container
    container:SetAuraGroupMaxFrameCount(pgroup.key, 1)
    -- Converge the whole contract every bind, exactly like the slot and block
    -- paths: the filter string, the candidate set and the park sentinel all
    -- come from one source, so they can never drift apart.
    container:SetAuraGroupFilterString(pgroup.key, SlotContract(pgroup.unit).filter)
    container:SetAuraGroupCandidateFilters(pgroup.key,
        BuildCandidateFilters(pgroup.unit, entry.spellSet))
    pgroup.boundStackMax = entry.stackBarMax
    -- Re-style every owned frame, not just the assigned one: initializeFrame
    -- ran once per pooled frame at group creation, and which frame the group
    -- hands out next is Blizzard's business.
    for _, host in ipairs(pgroup.hosts) do
        ApplyPanelHostGeometry(pgroup, host)
        -- Before StyleSlotKit: the styler reads the square's texture and crop
        -- for the occluding cover and the aura icon's own texcoords.
        ApplyPanelHostIcon(pgroup, host, entry.buttonData, entry.style)
        ConvergeApplicationBar(host.frame, host.kit, entry.buttonData, entry.stackBarMax)
        ConvergeApplicationCount(host.frame, host.kit, entry.buttonData)
        StyleSlotKit({
            kit = host.kit,
            slotButton = host.frame,
            unit = pgroup.unit,
            boundStackMax = entry.stackBarMax,
        }, host.proxy, entry.buttonData, entry.style)
        -- Tooltips: an Aura Panel cell has no CC button under it, so this frame
        -- is the ONLY surface a tooltip could hang off — panels therefore honor
        -- the panel's own Show Tooltips setting rather than forcing motion off
        -- the way the click-through resource holders do. Pooled frames are
        -- reused across entries, so all three are converged every bind.
        host.frame:SetMouseMotionEnabled(entry.style.showTooltips == true)
        host.frame:SetTooltipAnchorPoint(
            AURA_TOOLTIP_ANCHORS[entry.style.tooltipAnchor] or "ANCHOR_NONE", 0, 0)
        -- Same expression the slot path uses for a non-texture host: the panel
        -- owns a real Show Tooltips setting, so the combat-hide setting beside
        -- it has to be the one that answers here too.
        host.frame:SetHideTooltipInCombat(entry.style.tooltipHideInCombat == true)
    end
    RegisterSlotAuraSounds(pgroup, entry.buttonData, entry.spellSet)
    pgroup.parked = nil
    pgroup.boundEntry = entry.buttonData
end

-- Bind one panel's container. Returns nothing; every refusal leaves the
-- container parked from the pass's park-all phase, which is the safe state.
local function BindAuraPanel(self, groupId, group, frame)
    -- One unit for the whole panel, derived from its first resolvable aura
    -- entry. No entry, or no resolvable polarity, means there is nothing to
    -- mount a container for yet.
    local unit = self:GetAuraPanelUnit(group)
    if not unit then return end

    local record = EnsurePanelContainer(groupId, unit, frame)
    -- Binding is chrome-INDEPENDENT (see ApplyPanelRootVisibility): the lock
    -- state only decides whether the bound display is PRESENTED, and the chrome
    -- writers flip that term themselves, in combat if they have to. Re-read here
    -- so a pass that was deferred across a lock change converges on the frame's
    -- current answer instead of whatever the record last heard.
    record.chromeSuppressed = frame._auraPanelChromeSuppressed == true
    -- Mounting an incompatible unit would let Blizzard ignore includeSpellIDs
    -- for every non-exempt aura candidate. Leave the whole panel parked; the
    -- reaction watcher requests another pass if it becomes safe.
    record.identityApplicable = CanApplySpellIdentityFilter(unit)
    if not record.identityApplicable then return end

    -- The SAME metrics the frame was sized from and the placeholders were laid
    -- out from, so the container's cells land exactly on the CC-side grid.
    local usability = self:GetGroupButtonUsabilityOptions(groupId, group)
    local _, _, _, cellWidth, cellHeight, spacing =
        self:GetAuraPanelGridMetrics(groupId, group, usability)
    local isBar = group.displayMode == "bars"
    -- Fill direction comes from the PANEL's style, not each entry's effective
    -- one: the cell dimensions above were derived from the panel style too
    -- (GetButtonDimensions swaps them for a vertical bar), and a per-entry
    -- override would draw a vertical fill inside a horizontal cell. Cells are
    -- uniform across an Aura Panel by construction.
    local isVertical = isBar and (group.style or {}).barFillVertical == true

    -- Mount and flow config BEFORE the groups bind, the same order the block
    -- buckets use: an unanchored container would be laid out by Blizzard's
    -- deferred pass from whatever point it last had. Every one of these setters
    -- diff-checks internally (FlowLayoutMixin returns false when unchanged and
    -- only then does the container mark itself dirty), so re-applying the whole
    -- contract each pass costs nothing and removes the fragile invariant that a
    -- style edit remembered to touch the right one.
    local flow, axis, maximumLineSize = PanelFlowSpec(group, cellWidth, cellHeight, spacing)
    ApplyPanelMount(record, flow, axis, NormalizePanelGrowthDirection(group.compactGrowthDirection))
    record.container:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis[axis])
    record.container:SetFlowLayoutAnchorPoint(flow.anchor)
    record.container:SetFlowLayoutGrowthDirection(
        AnchorUtil.FlowDirection[flow.h], AnchorUtil.FlowDirection[flow.v])
    record.container:SetFlowLayoutPadding(0, 0, 0, 0)
    -- nil restores the default ceiling (math.huge) for the single-column bar
    -- list, which must never wrap.
    record.container:SetFlowLayoutMaximumLineSize(maximumLineSize)

    local layoutIndex = 0
    -- Keyed exactly the way EnsurePanelGroup keys record.groups, so "seen
    -- before" here and "reuses an existing group" there are the same question.
    local seenKeys
    for _, buttonData in ipairs(group.buttons or {}) do
        if self:IsButtonUsable(buttonData, group, usability) then
            local auraKey = buttonData._auraKey
            local entryUnit = self:ResolveAuraEntryUnit(buttonData)
            if not auraKey then
                -- Pre-subtype or hand-edited data: without a stable key there
                -- is no aura group to own this entry, and inventing one per
                -- pass would leak a permanent group every rebind. The config
                -- normalizer owns the repair.
                panelSkippedNoKey = panelSkippedNoKey + 1
            elseif entryUnit and entryUnit ~= unit then
                -- Imported config can carry an entry of the other polarity.
                -- Binding it onto this container's unit would hand Blizzard a
                -- filter its identity gate refuses to apply.
                panelUnitMismatches = panelUnitMismatches + 1
            else
                local spellSet = self:GetAuraCandidateSpellIDSet(buttonData, true)
                if not spellSet then
                    -- Empty includeSpellIDs wedges a group permanently, so an
                    -- entry with no resolvable candidates stays parked.
                    panelNoCandidates = panelNoCandidates + 1
                else
                    local style = self:GetEffectiveStyle(group.style, buttonData)
                    -- The icon square rides the entry's effective style, so
                    -- Show Bar Icon (and the size/offset/side keys beside it)
                    -- work on an Aura Panel exactly as on a bar panel. Cell
                    -- dimensions stay panel-wide either way.
                    local iconShown, iconSize, iconOffset, iconReverse =
                        PanelBarIconGeometry(style, isBar, isVertical, cellWidth, cellHeight)
                    -- Stack fill (tracker C2): bar panels only, max is
                    -- automatic. nil means "not a stacking aura" and the bind
                    -- falls back to the duration fill.
                    local stackBarMax
                    if isBar and self:IsBarPanelAuraStackDisplay(buttonData) then
                        stackBarMax = self:GetAuraStackBarMax(buttonData, true)
                    end
                    -- Counted at the moment the reuse actually happens: an
                    -- entry refused above never reaches EnsurePanelGroup, so a
                    -- key it shares with a later entry collides with nothing.
                    -- Counting only -- the second bind winning is left alone.
                    seenKeys = seenKeys or {}
                    if seenKeys[auraKey] then
                        panelDuplicateKeys = panelDuplicateKeys + 1
                    else
                        seenKeys[auraKey] = true
                    end
                    -- Dense over BOUND entries only: layoutIndex is a relative
                    -- ordering, not a grid coordinate (Blizzard packs the
                    -- active survivors), so a skipped entry leaves no hole.
                    layoutIndex = layoutIndex + 1
                    local entry = {
                        id = auraKey,
                        buttonData = buttonData,
                        spellSet = spellSet,
                        style = style,
                        width = cellWidth,
                        height = cellHeight,
                        spacing = spacing,
                        isBar = isBar,
                        vertical = isVertical,
                        stackBarMax = stackBarMax,
                        iconShown = iconShown,
                        iconSize = iconSize,
                        iconOffset = iconOffset,
                        iconReverse = iconReverse,
                    }
                    BindPanelGroup(EnsurePanelGroup(record, entry, layoutIndex), entry)
                end
            end
        end
    end

    -- Nothing bound: a shown container would register for aura events and
    -- render nothing, so leave it parked and hidden like an empty block side.
    if layoutIndex == 0 then return end

    record.container:Show()
    record.shown = true
    SetPanelIdentityVisibility(record, true)
end

-- Park everything, then bind — the same discipline (and the same coalescing
-- argument) as the slot and block passes. OOC by RunAuraRebind's guarantee.
local function RebindAuraPanels(self)
    for _, record in ipairs(panelRecords) do
        for _, pgroup in ipairs(record.groupList) do
            ParkPanelGroup(pgroup)
        end
        record.container:Hide()
        record.shown = false
        SetPanelIdentityVisibility(record, false)
    end
    panelSkippedNoKey = 0
    panelUnitMismatches = 0
    panelNoCandidates = 0
    panelDuplicateKeys = 0

    -- Walked from the LIVE FRAMES, like the slot pass above, not from stored
    -- config: the container mounts on the frame, so a panel without one has
    -- nothing to bind to. A frame that merely happens to be HIDDEN (load
    -- conditions, character visibility) is still bound — visibility rides
    -- parentage, a hidden container is inert, and it re-registers and refreshes
    -- itself on show.
    for groupId, frame in pairs(self.groupFrames) do
        local group = self.db.profile.groups[groupId]
        if frame and ST.IsAuraPanelGroup(group) then
            BindAuraPanel(self, groupId, group, frame)
        end
    end
end

-- One combat-defer note per deferral window: config edits made in combat keep
-- applying to CC-side visuals immediately, but the aura display (slot kit)
-- only restyles at the deferred rebind, so the player is told once why the
-- aura visuals lag. Cleared when a rebind actually runs.
local deferNoteShown = false

-- A host is only slot-free once none of its records holds a binding. Several
-- records share one button, so this must be asked per host, not per record.
local function HostHoldsBinding(byUnit)
    for _, record in pairs(byUnit) do
        if record.boundEntry then
            return true
        end
    end
    return false
end

local function HasBoundSlots(groupId)
    for _, record in ipairs(records) do
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
    -- Authoritative guard at the mutation boundary. Callers also check so they
    -- can coalesce/defer early, but no caller timing may reach the destructive
    -- park-all phase after the AuraButton subtree becomes inaccessible.
    if not CanRunRebindNow() then
        ArmRebindRetry()
        return
    end
    deferNoteShown = false
    rebindPassCount = rebindPassCount + 1
    lastRebindPassAt = GetTime()

    -- Collect wanted bindings from live buttons. Icon/bar behavior keeps its
    -- existing aura flags. Texture panels always bind primary Aura entries and
    -- require an explicit opt-in for ordinary spells, so retained pre-12.1
    -- auraTracking residue stays dormant; Trigger/Text remain excluded. A
    -- client-drawn aura readout docked into a text entry's format was trialed
    -- and removed by owner decision, so text panels are aura-blind by design
    -- rather than by omission.
    local wanted = {}
    for groupId, frame in pairs(self.groupFrames) do
        local group = self.db.profile.groups[groupId]
        local displayMode = group and (group.displayMode or "icons")
        if (displayMode == "icons" or displayMode == "bars" or displayMode == "textures") and frame.buttons then
            for _, button in ipairs(frame.buttons) do
                local buttonData = button.buttonData
                local textureAura = displayMode == "textures"
                    and self:IsTexturePanelAuraDisplayEnabled(group, buttonData)
                local standardAura = displayMode ~= "textures"
                    and buttonData
                    and (buttonData.auraTracking or buttonData.addedAs == "aura")
                if buttonData and buttonData.type == "spell" and (textureAura or standardAura) then
                    local spellSet = self:GetAuraCandidateSpellIDSet(buttonData, true)
                    local textureSettings = textureAura and self:GetTexturePanelSettings(group) or nil
                    local textureIndicators = textureAura and self:GetTexturePanelIndicatorSettings(group) or nil
                    if spellSet and (not textureAura or (textureSettings and textureSettings.enabled)) then
                        -- Stack fill (tracker C2): bar hosts only; the max is
                        -- automatic (owner ruling). A nil resolve means "not
                        -- a stacking aura" and the bind falls back to the
                        -- duration fill.
                        local stackBarMax
                        if displayMode == "bars" and self:IsBarPanelAuraStackDisplay(buttonData) then
                            stackBarMax = self:GetAuraStackBarMax(buttonData, true)
                        end
                        wanted[#wanted + 1] = {
                            button = button,
                            buttonData = buttonData,
                            spellSet = spellSet,
                            style = self:GetEffectiveStyle(group.style, buttonData),
                            stackBarMax = stackBarMax,
                            hostKind = textureAura and "texturePanel" or "button",
                            textureSettings = textureSettings,
                            textureIndicator = textureIndicators and textureIndicators.aura or nil,
                        }
                    end
                end
            end
        end
    end

    -- Custom-bar hosts (OtherBars/ResourceBarAuraHost.lua): appends want
    -- records in the same shape, hosted on stable holder frames. Looked up
    -- at run time (the module loads after this file).
    local collectCustomWants = ST._CollectCustomBarAuraWants
    if collectCustomWants then
        collectCustomWants(wanted)
    end

    -- Shared unit resolution: every want derives its token set the same way
    -- (custom-bar wants arrive with unit unset). One want fans out to one
    -- record per token.
    for _, want in ipairs(wanted) do
        want.units = want.unit and { want.unit }
            or ResolveEntryAuraUnits(self, want.buttonData, want.hostKind ~= "texturePanel")
        want.groupScoped = want.hostKind ~= "texturePanel"
            and want.buttonData.auraTrackGroup == true
            and want.units[1] ~= "target"
        -- Armed from the opt-in, not from a resolved ally token: solo the set is
        -- { "player" } and there would be no ally record to trigger it.
        if want.groupScoped then
            EnsureGroupWatcher()
        end
    end

    -- Park everything, then bind fresh — simple and idempotent; runs at
    -- config-change frequency, never per tick. The mutation-boundary guard
    -- above has established that combat lockdown and aura secrecy are both
    -- clear before any binding is hidden or rewritten.
    for _, record in ipairs(records) do
        ParkDisplay(record)
    end
    for _, want in ipairs(wanted) do
        -- Aura sounds are registered per unit token, so a multi-unit set would
        -- register one per member and fire a removed+applied pair every time the
        -- aura moved between people — a false "it dropped" alert. Single-unit
        -- entries keep today's behavior exactly.
        local soundsAllowed = #want.units == 1
        for _, unit in ipairs(want.units) do
            local record = EnsureDisplay(want.button, unit, want.groupScoped, want.hostKind)
            if record then
                BindDisplay(record, want.buttonData, want.spellSet, unit,
                    want.style, want.stackBarMax, soundsAllowed, want.groupScoped,
                    want.textureSettings, want.textureIndicator)
            end
        end
    end

    -- Aura blocks (custom-bar aura entries that hide when inactive): their own
    -- park-then-bind pass over the group containers. Disjoint from the slot
    -- records above — no host button, no pool lock — so ordering is free.
    RebindCustomBarAuraBlocks(self)

    -- Aura Panels (whole panels drawn by their own aura container): likewise a
    -- self-contained park-then-bind pass. Disjoint from both passes above — an
    -- Aura Panel materializes no CC buttons, so the `wanted` walk never saw one
    -- and no record here shares a host with anything.
    RebindAuraPanels(self)

    -- Reconcile the shared pool lock once, after binding: a host is only
    -- slot-free when NONE of its records holds a binding. ParkDisplay must not
    -- do this per record — several records share one button, and clearing the
    -- token while a sibling is still bound and visible would release the lock
    -- that stops the pool handing this host to a different entry.
    for button, byUnit in pairs(displays) do
        if not HostHoldsBinding(byUnit) then
            button._auraSlotHostToken = nil
        end
    end

    -- A pass that reaches here bound everything it wanted: nothing is deferred, so
    -- close any retry state a caller left armed rather than leaving pendingRebind
    -- set (which would suppress later RequestAuraRebind bookkeeping).
    DisarmRebindRetry()
    pendingRebind = false

    -- The cast bar anchors to the block chain's TAIL, and this pass is the
    -- only writer of which container that is. Coalesced next-frame cast-bar
    -- re-evaluation, so the combat-deferred rebind cannot leave the cast bar
    -- pointing at last pull's tail. CAST BAR LEG ONLY — never the full
    -- stacking evaluation: its resource leg re-applies the bars, whose apply
    -- ends in RequestAuraRebind("custom-bars"), which re-ran this pass every
    -- frame forever (2026-08-10 feedback-loop diagnosis). The stack-end pin
    -- rule means resource bars never move in response to a tail change, so
    -- the cast bar is the only trailing frame with anything to re-anchor.
    if self.UpdateCastBarStackAnchor then
        self:UpdateCastBarStackAnchor()
    end
end

rebindDeferFrame:SetScript("OnEvent", function()
    -- Unregister BEFORE running so an error can't leave the events stuck
    -- (FrameAnchoring's combat-defer pattern).
    DisarmRebindRetry()
    pendingRebind = false
    if CanRunRebindNow() then
        RunAuraRebind()
    else
        -- Combat lockdown or aura secrecy is still enforced (a pull may have
        -- restarted before the retry landed).
        ArmRebindRetry()
    end
end)

-- Single entry point. Accessible requests coalesce into one next-frame pass (group
-- populates arrive once per group on a reload); the timer callback re-checks
-- combat lockdown and aura secrecy and re-defers if restrictions started in
-- between.
function CooldownCompanion:RequestAuraRebind(reason, groupId)
    if not self.db then return end
    rebindRequestCount = rebindRequestCount + 1
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
    -- Seeded so the two always-present units report zeroes rather than going
    -- missing; any other tracked token is added on demand, so ally records
    -- can't silently vanish from diagnostics.
    status.units.player = { slots = 0, bound = 0, stackBound = 0 }
    status.units.target = { slots = 0, bound = 0, stackBound = 0 }
    for _, record in ipairs(records) do
        local unitStatus = status.units[record.unit]
        if not unitStatus then
            unitStatus = { slots = 0, bound = 0, stackBound = 0 }
            status.units[record.unit] = unitStatus
        end
        unitStatus.slots = unitStatus.slots + 1
        if record.boundEntry then unitStatus.bound = unitStatus.bound + 1 end
        if record.boundStackMax then unitStatus.stackBound = unitStatus.stackBound + 1 end
    end
    -- Aura blocks: containers created (permanent once created), groups by
    -- bind state, how many sides run a two-bucket chain, and any entries the
    -- chain safety dropped (see BindBlockBucket — clears on /reload).
    local blocks = {
        containers = #blockRecords,
        shown = 0,
        bound = 0,
        parked = 0,
        hosts = 0,
        chained = 0,
        chainBlocked = blockChainBlocked,
    }
    for _, record in ipairs(blockRecords) do
        -- CC-side tags, not container reads: these are the only diagnostics
        -- that can be asked for in combat.
        if record.shown then blocks.shown = blocks.shown + 1 end
        if record.chainAnchor then blocks.chained = blocks.chained + 1 end
        for _, group in ipairs(record.groupList) do
            if group.boundEntry then
                blocks.bound = blocks.bound + 1
            else
                blocks.parked = blocks.parked + 1
            end
            -- Observability for the batch-size assumption: every pooled frame
            -- Blizzard pre-created ran initializeFrame and built a full kit.
            blocks.hosts = blocks.hosts + #group.hosts
        end
    end
    status.blocks = blocks
    -- Aura Panels: containers created (permanent once created), groups by bind
    -- state, pooled hosts built, and the four reasons the last pass refused (or
    -- silently doubled up) an entry. The skip counters are the only visible
    -- trace of stored config the display cannot serve, so a nonzero one is a
    -- config question, not a fault.
    local panels = {
        containers = #panelRecords,
        shown = 0,
        boundGroups = 0,
        parkedGroups = 0,
        hosts = 0,
        skippedNoKey = panelSkippedNoKey,
        unitMismatches = panelUnitMismatches,
        noCandidates = panelNoCandidates,
        duplicateKeys = panelDuplicateKeys,
        -- Per-container detail. The totals above cannot say WHICH panel is
        -- dark, and an abandoned record (see EnsurePanelContainer) is
        -- indistinguishable from a live one in an aggregate -- it shows up here
        -- as a second record on the same groupId with nothing bound.
        records = {},
    }
    for _, record in ipairs(panelRecords) do
        -- CC-side tags, not container reads: these are the only diagnostics
        -- that can be asked for in combat.
        if record.shown then panels.shown = panels.shown + 1 end
        local groups, bound = 0, 0
        for _, pgroup in ipairs(record.groupList) do
            groups = groups + 1
            if pgroup.boundEntry then
                panels.boundGroups = panels.boundGroups + 1
                bound = bound + 1
            else
                panels.parkedGroups = panels.parkedGroups + 1
            end
            panels.hosts = panels.hosts + #pgroup.hosts
        end
        panels.records[#panels.records + 1] = {
            groupId = record.groupId,
            unit = record.unit,
            shown = record.shown == true,
            -- A BOUND panel can still be dark on purpose: its unlock
            -- placeholders are standing in for it. Without this the two dark
            -- reasons are indistinguishable in a snapshot.
            chromeSuppressed = record.chromeSuppressed == true,
            groups = groups,
            bound = bound,
        }
    end
    status.panels = panels
    -- Idle health: requests/passes since login, and how long ago the last
    -- pass ran. On an idle session these must hold still — climbing numbers
    -- mean something is re-requesting the pass without a real change.
    status.rebindRequests = rebindRequestCount
    status.rebindPasses = rebindPassCount
    status.rebindPassAge = lastRebindPassAt and (GetTime() - lastRebindPassAt) or nil
    return status
end
