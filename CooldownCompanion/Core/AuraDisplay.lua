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
    The display therefore uses ONE AuraContainer PER (HOST BUTTON, UNIT
    TOKEN) — a host needs more than one only when an entry is tracked on
    several units at once — created as
    a child of that button's auraLayer (containers are plain CC frames; the
    parent is set at CreateFrame and never changed — only the BUTTONS carry
    the forbidden aspects), with the slot button anchored once inside
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

local ipairs = ipairs
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame
local IsInRaid = IsInRaid
local GetNumGroupMembers = GetNumGroupMembers
local GetNumSubgroupMembers = GetNumSubgroupMembers

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
    target = { polarity = "HARMFUL", filter = "HARMFUL", ownOnly = true },
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

-- Deferred-rebind retry events: PLAYER_REGEN_ENABLED for player combat, and
-- target-scoped UNIT_FLAGS for the case where ONLY target combat blocks (an
-- OOC player never gets a regen event, so the target's own combat-flag change
-- must wake the retry). The handler re-checks the gate, so extra fires are
-- harmless; PLAYER_TARGET_CHANGED retries live on the target watcher.
local rebindDeferFrame = CreateFrame("Frame")

-- `anyUnit` widens UNIT_FLAGS from target-only to unfiltered. Ally tokens can
-- block a pass, and RegisterUnitEvent accepts at most two units, so there is no
-- way to filter party1..raid40 — an ally's combat ENDING would otherwise produce
-- no event at all (PLAYER_REGEN_ENABLED cannot fire for a player who never
-- entered combat), leaving the retry armed with no trigger. Blizzard registers
-- unfiltered UNIT_FLAGS for exactly this purpose in
-- Blizzard_CompactRaidFrames/Mainline/Blizzard_CompactRaidFrameManager.lua:80.
-- The handler disarms and re-checks the gate first, so extra fires are harmless.
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
local groupWatcher
local RunAuraRebind

-- The player's own combat is the ONLY gate. There is deliberately no per-unit
-- rebind gate — do not re-add one.
--
-- P11 assumed aura secrecy follows each unit's own state, so a slot on a fighting
-- ally would be untouchable even with the player at rest. That extrapolated from
-- aura-DATA secrecy (which may well be per-unit) to slot-ACCESS (which is not),
-- and CC never reads aura data — the rebind pass only writes filters and styling.
--
-- Measured in game 2026-07-29 (`/ccat g2 write`), three states, writes chosen to
-- mirror this file's own bind calls (a container mutator, two slot-button
-- methods, and a write to a region under the slot button):
--   * player OOC, ally OOC          -> all succeed
--   * player IN COMBAT              -> slot-button and kit-region writes ERROR
--     ("Attempt to access forbidden object"), proving the test detects failure
--   * player OOC, ALLY IN COMBAT    -> all succeed, and the slot kept being
--     shown and hidden by Blizzard afterwards
-- So slot forbidden-ness is player-scoped, consistent with PTR 5 ("AuraButtons
-- are forbidden whenever auras are secret") and with the restriction windows
-- — combat, encounter, challenge mode, PvP — all being conditions about the
-- player. `slotButton:CanBeAccessedInContext()` agrees: it flips with the
-- player's combat state and reported accessible for an ally slot while that ally
-- fought.
--
-- Not covered by that probe: whether an encounter/M+/PvP restriction window
-- restricts while the player is out of combat. That would affect the player token
-- too, so it is a question about this function, not about ally units.
local function CanRunRebindNow()
    return not InCombatLockdown()
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
local function RefreshRecordsForToken(isMatch)
    for _, record in ipairs(records) do
        if isMatch(record.unit) then
            record.container:UpdateAllAuras()
        end
    end
end

local function IsTargetToken(unit) return unit == "target" end
local function IsAllyToken(unit) return unit ~= "player" and unit ~= "target" end

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
        RefreshRecordsForToken(IsTargetToken)
        -- Opportunistic: service a rebind that was deferred by player combat if we
        -- are already out of it. PLAYER_REGEN_ENABLED normally gets there first, so
        -- this is a cheap extra wake rather than the primary path.
        if pendingRebind and CanRunRebindNow() then
            pendingRebind = false
            DisarmRebindRetry()
            RunAuraRebind()
        end
    end)
end

-- Ally-scope entries derive their token set from group size, so the set changes
-- whenever the roster does — and joining a raid switches the whole set from
-- party* to raid*. Slots can only be created out of combat, so a mid-fight join
-- is covered from the next OOC pass, not immediately.
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
    -- pinnedTextFrame, which is where the keybind text lives — and CC can't
    -- re-show it with aura state (secret in combat) — so the kit re-renders
    -- the keybind text while the aura display is the whole visible button.
    -- Base font template only; styled at bind.
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

ST.STACK_SEGMENT_GAP_RATIO = 10 / 512 -- baked into the atlas artwork
ST.STACK_SEGMENT_ATLAS_MAX = 20

function ST.GetStackSegmentsTexture(max)
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
function ST.LayoutStackBlocks(blocks, host, max, vertical, color, alpha, length)
    length = length or (vertical and host:GetHeight() or host:GetWidth())
    if length <= 0 then
        ST.HideStackBlocks(blocks)
        return
    end
    local gap = length * ST.STACK_SEGMENT_GAP_RATIO
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
    local n = style.auraTextFontColor or CooldownCompanion.DEFAULT_AURA_TEXT_COLOR
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
    local resShapes = isResourceHost and (style.resourceShapes or {}) or nil
    -- Hidden and dimmed shells alike: the kit composes the full active
    -- visual either way (the dim key stands alone on 12.1).
    local shellEntry = CooldownCompanion:IsAuraShellEntry(buttonData)
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

    -- Resource overlays never swap in an aura icon: live's overlay has no
    -- icon of any kind.
    local auraIconShown = not isResourceHost
        and showAuraIcon and (not isBar or barIconShown)
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
            local cropW, cropH = button:GetWidth(), button:GetHeight()
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
                kit.durationText:SetPoint("BOTTOM", slotButton, "BOTTOM", 0, 2)
            else
                kit.durationText:SetPoint("CENTER", slotButton, "CENTER", 0, 0)
            end
            if showDur then
                kit.stackText:SetPoint("TOP", slotButton, "TOP", 0, -2)
            else
                kit.stackText:SetPoint("CENTER", slotButton, "CENTER", 0, 0)
            end
        else
            if showStack then
                kit.durationText:SetPoint("LEFT", slotButton, "LEFT", 4, 0)
            else
                kit.durationText:SetPoint("CENTER", slotButton, "CENTER", 0, 0)
            end
            if showDur then
                kit.stackText:SetPoint("RIGHT", slotButton, "RIGHT", -4, 0)
            else
                kit.stackText:SetPoint("CENTER", slotButton, "CENTER", 0, 0)
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
    -- aura swipe — the draining bar is the timer, and a resource overlay
    -- has no icon square for one to ride.
    if isBar and isResourceHost then
        kit.swipe:ClearAllPoints()
        kit.swipe:SetAllPoints(slotButton)
        kit.swipe:SetDrawSwipe(false)
        kit.swipe:SetDrawEdge(false)
    elseif isBar then
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
            ST.LayoutStackBlocks(kit.stackBgBlocks, button.statusBar or slotButton,
                slot.boundStackMax, button._isVertical, blockBg, blockAlpha)
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

-- One display per host button (D-A0 rung (c)): the container is a plain CC
-- frame whose parent is set once at CreateFrame and never changed (only the
-- BUTTONS carry the ChangeParent aspect), and the slot button is anchored
-- inside initializeFrame — the sanctioned setup window — and never moved,
-- re-leveled, or reparented afterwards. The container is pinned to the
-- layer's frame level so the slot lands at layer+1, exactly where the
-- pre-PTR 7 design put it — but the layer's own level is now a configurable
-- slot, so where that band SITS follows the panel's strata order.
-- Visibility, alpha, and strata all reach the
-- slot through plain parentage; a hidden container is inert (P1a) and
-- re-registers + refreshes itself on show (OnShow_Intrinsic).
-- Keyed by (button, unit), which makes record.unit IMMUTABLE: a record is for
-- one unit for its whole life, and the container's SetUnit is only ever called
-- once, here. The alternative — one record per button whose unit is swapped at
-- bind — cannot represent an entry tracked on several units at once.
--
-- Consequence: a pooled button re-acquired for an entry of the other polarity
-- now gains a second record rather than mutating its first. The first is parked
-- (hidden, deregistered, rendering nothing), so this is invisible; the cost is
-- at most one extra container per polarity that button has ever hosted.
local function EnsureDisplay(button, unit, groupScoped)
    local byUnit = displays[button]
    if byUnit then
        local existing = byUnit[unit]
        if existing then return existing end
    else
        byUnit = {}
        displays[button] = byUnit
    end
    local layer = EnsureAuraLayer(button)
    slotCounter = slotCounter + 1
    local record = { button = button, key = "cc" .. slotCounter, unit = unit }
    -- Direct calls, no pcall: the TOC pins this client generation, so the
    -- AuraContainer API always exists — a failure here is a real setup error
    -- that must surface, not read as "feature unavailable".
    local container = CreateFrame("AuraContainer", nil, layer, "CustomAuraContainerTemplate")
    container:SetAllPoints(layer)
    container:SetFrameLevel(layer:GetFrameLevel())
    container:SetUnit(unit)
    local slotButton = container:AddAuraSlot(record.key, SlotContract(unit, groupScoped).filter, {
        candidateFilters = BuildParkFilters(unit),
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
    byUnit[unit] = record
    records[#records + 1] = record
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

local function BindDisplay(record, buttonData, spellSet, unit, style, stackBarMax, soundsAllowed, groupScoped)
    local button = record.button
    local wasParked = record.parked
    local layer = EnsureAuraLayer(button)
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
        -- Segmented smoothing (C2 follow-on): Blizzard sweeps the driven
        -- fill between stack counts (interpolation is Blizzard-evaluated —
        -- the only smoothing path for secret values; the CC-side resource
        -- mechanism can't apply here). Continuous style always smooths
        -- (owner ruling, resource parity); segmented follows the per-entry
        -- toggle. Plain duration binds (wantMax == 1) never use the stack
        -- fill, so they keep the creation-time registration untouched.
        local wantSmooth = false
        if wantMax > 1 and ST.STATUS_BAR_INTERPOLATION_SMOOTH then
            wantSmooth = CooldownCompanion:GetBarPanelAuraStackDisplayMode(buttonData) == "continuous"
                or CooldownCompanion:GetBarPanelAuraSegmentedSmoothing(buttonData) == ST.SEGMENTED_SMOOTHING_ON
        end
        if kit.stackFillMax ~= wantMax or kit.stackFillSmooth ~= wantSmooth then
            record.slotButton:SetApplicationBar(kit.stackFill, {
                maxApplications = wantMax,
                interpolation = wantSmooth and ST.STATUS_BAR_INTERPOLATION_SMOOTH or nil,
            })
            kit.stackFillMax = wantMax
            kit.stackFillSmooth = wantSmooth
        end
    end
    -- Set before styling: StyleSlotKit selects the stack fill from this tag.
    record.boundStackMax = stackBarMax
    StyleSlotKit(record, button, buttonData, style)
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
    record.slotButton:SetMouseMotionEnabled(button._ccTooltipMotion == true)
    -- Tooltip position + combat hide (tracker D-C1): plain per-bind mixin
    -- state on the slot button, same OOC re-call pattern as the motion line
    -- above; Blizzard's OnEnter path reads it. ANCHOR_NONE with zero offsets
    -- is what an untouched button resolves to, so re-calling it converges
    -- pooled buttons when the setting goes back to Default.
    record.slotButton:SetTooltipAnchorPoint(
        AURA_TOOLTIP_ANCHORS[style.tooltipAnchor] or "ANCHOR_NONE", 0, 0)
    record.slotButton:SetHideTooltipInCombat(style.tooltipHideInCombat == true)
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
local function ResolveEntryAuraUnits(self, buttonData)
    local first = self:ResolveAuraSpellID(buttonData)
    local harmful
    if first and C_Spell.DoesSpellExist(first) then
        harmful = C_Spell.IsSpellHarmful(first)
    else
        harmful = buttonData.auraUnit == "target"
    end
    if harmful then return { "target" } end
    if buttonData.auraTrackGroup then return GroupAuraTokens() end
    return { "player" }
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
    deferNoteShown = false

    -- Collect wanted bindings from live buttons (icon/bar groups only — text
    -- mode has no compliant aura display; trigger/texture panels lost aura
    -- conditions by design; dormant flags there stay dormant).
    local wanted = {}
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
                            style = self:GetEffectiveStyle(group.style, buttonData),
                            stackBarMax = stackBarMax,
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
        want.units = want.unit and { want.unit } or ResolveEntryAuraUnits(self, want.buttonData)
        want.groupScoped = want.buttonData.auraTrackGroup == true and want.units[1] ~= "target"
        -- Armed from the opt-in, not from a resolved ally token: solo the set is
        -- { "player" } and there would be no ally record to trigger it.
        if want.groupScoped then
            EnsureGroupWatcher()
        end
    end

    -- Park everything, then bind fresh — simple and idempotent; runs at
    -- config-change frequency, never per tick. No per-unit gate: the player's
    -- combat state is the only thing that can make a slot untouchable (see
    -- CanRunRebindNow), and every caller has already checked it.
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
            local record = EnsureDisplay(want.button, unit, want.groupScoped)
            if record then
                BindDisplay(record, want.buttonData, want.spellSet, unit,
                    want.style, want.stackBarMax, soundsAllowed, want.groupScoped)
            end
        end
    end

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
end

rebindDeferFrame:SetScript("OnEvent", function()
    -- Unregister BEFORE running so an error can't leave the events stuck
    -- (FrameAnchoring's combat-defer pattern).
    DisarmRebindRetry()
    pendingRebind = false
    if CanRunRebindNow() then
        RunAuraRebind()
    else
        -- Still in combat lockdown (a pull started before the retry landed).
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
    return status
end
