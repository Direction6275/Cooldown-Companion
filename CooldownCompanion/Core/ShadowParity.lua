--[[
    CooldownCompanion - Core/ShadowParity.lua: D1 shadow-parity harness
    (F1 program Phase 2). Observe-only; never alters refresh behavior.

    Question it answers: if identity-carrying cooldown/charge events were
    routed through the SpellButtonIndex (updating only matching buttons)
    instead of triggering today's broad walk, would any button's visuals have
    been left stale? Every routable event stamps the buttons routing WOULD
    have updated; the broad pass then runs unchanged; after the pass, any
    uncovered button whose visual state changed is classified.

    Dev-gated like RefreshTelemetry: enabled at PLAYER_LOGIN only when the
    CC_DevBridge dev addon is loaded. Inert otherwise (one table lookup and
    branch per tapped event/pass).

    Signature fields are the always-maintained per-button state caches — the
    same fields VisualStateDiagnostics compares as authoritative. The
    intent/applied sidecar tables are NOT used here: they are only stored
    while visual-state snapshot capture is on, so they cannot back an
    every-pass diff. No time-varying numbers are included (remaining-time
    animation happens in OnUpdate self-animation, not these fields);
    visibility alpha is quantized to hundredths.

    Expected-noise classes (counted separately so the hard mismatch counter
    can meaningfully reach and hold zero, mirroring falseIdleTotal):
    - cross-family: only proc/aura-glow/pandemic/visibility fields changed.
      Those families are not being routed (aura/target is last-or-never);
      the broad pass applied their pending state opportunistically.
    - usability: only the unusable tint changed. Usability is polled per
      pass with no identity event; the in-combat ticker re-applies it within
      ~0.1s in a routed world. Latency-only, never lost state.
    - gcd-settle: a cooldown-state transition into/out of STATE_GCD with only
      GCD-shaped fields changed. GCD display is the per-pass shared snapshot
      (D4 inventory A1); routed mini-passes snapshot it per batch and the
      ticker settles the rest.
    - expiry-settle: a cooldown-state transition to STATE_READY with only
      expiry-shaped fields changed. Cooldown expiry is event-covered by F3's
      OnCooldownDone signal independent of broadcasts.
    Anything else on an uncovered button is a HARD MISMATCH
    (shadowParityMismatchTotal, per-family) — the number Gate 2 requires to
    be zero across the D7 matrix.

    Index-miss identity fires (spells no button tracks — most of the
    spellbook fires SPELL_UPDATE_COOLDOWN) are what the intended router
    DROPS. Batches of identity + miss fires get their own mismatch counter
    (mismatchDropOnly): a core change there means a dropped fire may have
    mattered, i.e. the index was stale for a tracked identity. Secret or
    unreadable args instead force the broad path (never mismatch-eligible).

    Broadcast demotion evidence (the Gate 1 question): batches containing
    broadcast fires (ACTIONBAR/BAG_UPDATE_COOLDOWN, no-arg
    SPELL_UPDATE_COOLDOWN, SPELL_UPDATE_CHARGES) or secret args are not
    mismatch-eligible — Phase 3 keeps those on the broad path — but are
    measured instead: did the broad pass change any uncovered cooldown-core
    state (broadcastCarriedChanges) or not (broadcastSilentPasses)?

    Owner-runnable:
      /run CooldownCompanion:PrintShadowParitySummary()
      /run CooldownCompanion:ResetShadowParity()
      /dump CooldownCompanion:GetShadowParityDiagnostics()
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CooldownLogic = ST.CooldownLogic or {}
local STATE_READY = CooldownLogic.STATE_READY
local STATE_GCD = CooldownLogic.STATE_GCD

local pairs = pairs
local ipairs = ipairs
local type = type
local select = select
local floor = math.floor
local issecretvalue = issecretvalue or function() return false end

local SECRET = "\1secret"   -- placeholder for secret-typed field values

-- Signature fields: { shortKey, buttonField }. Short keys name the changed
-- fields in log lines and drive the classification sets below.
local FIELDS = {
    { "cd",          "_cooldownState" },
    { "desatCd",     "_desatCooldownActive" },
    { "desat",       "_desaturated" },
    { "charge",      "_chargeState" },
    { "chargeRe",    "_chargeRecharging" },
    { "chargeSpent", "_chargesSpent" },
    { "nocd",        "_noCooldown" },
    { "tint",        "_unusableTintActive" },
    { "fill",        "_iconFillActive" },
    { "fillMode",    "_iconFillMode" },
    { "fillAura",    "_iconFillAuraActive" },
    { "fillUpd",     "_iconFillOnUpdateInstalled" },
    { "proc",        "_procGlowActive" },
    { "aglow",       "_auraGlowActive" },
    { "pand",        "_auraGlowPandemic" },
    { "ready",       "_readyGlowActive" },
    { "hid",         "_visibilityHidden" },
    { "alpha",       "_visibilityAlphaOverride" },
    { "vmode",       "_visibilityFinalMode" },
    { "gsup",        "_barGCDSuppressed" },
}
local FIELD_COUNT = #FIELDS

-- Fields owned by families this program is not routing (aura/proc/visibility).
local CROSS_FAMILY = {
    proc = true, aglow = true, pand = true, fillAura = true,
    hid = true, alpha = true, vmode = true,
}
-- Fields a GCD start/end legitimately flips across all buttons (A1 aggregate).
local GCD_SHAPE = {
    cd = true, desatCd = true, desat = true, gsup = true,
    fill = true, fillMode = true, fillUpd = true, ready = true, tint = true,
}
-- Fields a cooldown/charge expiry legitimately flips (F3-covered).
local EXPIRY_SHAPE = {
    cd = true, desatCd = true, desat = true, ready = true,
    fill = true, fillMode = true, fillUpd = true,
    charge = true, chargeRe = true, chargeSpent = true, nocd = true, tint = true,
}
local CHARGE_ONLY = { charge = true, chargeRe = true, chargeSpent = true }

local LOG_SIZE = 64

local SP = {
    enabled = false,
    passGen = 0,
    -- pass counters
    passTotal = 0,              -- every completed broad pass (signature refresh)
    passesEvaluated = 0,        -- passes that consumed a non-empty event batch
    passesIdentityOnly = 0,     -- batch was pure tracked-identity fires
    passesDropOnly = 0,         -- identity + index-miss fires only (router
                                -- would route the hits and drop the misses)
    passesWithBroadcast = 0,    -- batch forces the broad path (broadcast or
                                -- secret/unreadable arg)
    -- event fire counters (lifetime, by "EVENT:id|bc|miss|secret" tag)
    fireCounts = {},
    identityFireTotal = 0,
    broadcastFireTotal = 0,
    missFireTotal = 0,          -- identity fires for untracked spells (dropped)
    secretFireTotal = 0,        -- secret/unreadable args (broad fallback)
    -- per-button change classifications on evaluated passes
    routedCoveredChanges = 0,   -- changed AND covered: routing caught it
    crossFamilyChanges = 0,
    usabilityChanges = 0,
    gcdSettleChanges = 0,
    expirySettleChanges = 0,
    shadowParityMismatchTotal = 0,
    mismatchCooldown = 0,
    mismatchCharges = 0,
    mismatchDropOnly = 0,       -- core change in an identity+miss batch: a
                                -- dropped fire may have mattered (drop-safety
                                -- evidence, kept separate from the pure counter)
    -- Gate 1 broadcast-demotion evidence
    broadcastCarriedChanges = 0,
    broadcastSilentPasses = 0,
    secretFieldSeen = 0,
    -- mismatch / broadcast-carried detail ring (formatted strings, SV-safe)
    log = {},
    logCursor = 0,
    logTotal = 0,
}
ST.ShadowParity = SP

-- Pending event batch: everything fired since the last completed broad pass.
local batch = {
    id = 1,
    fireCount = 0,
    identityFires = 0,
    broadcastFires = 0,
    missFires = 0,
    secretFires = 0,
    events = {},                -- tag -> count for the current batch
}

local changedKeys = {}          -- per-pass scratch, reused

local function CountFire(tag)
    batch.fireCount = batch.fireCount + 1
    batch.events[tag] = (batch.events[tag] or 0) + 1
    SP.fireCounts[tag] = (SP.fireCounts[tag] or 0) + 1
end

-- Stamp every button the D3 index maps this spellID to as covered by the
-- current batch. Returns true when at least one button was stamped.
local function StampCovered(spellID)
    local index = CooldownCompanion:GetSpellButtonIndex()
    local bucket = index.spell[spellID]
    if not bucket then
        return false
    end
    for _, button in ipairs(bucket) do
        button._shadowParityCoveredBatch = batch.id
    end
    return true
end

-- Secret or non-number identity arg: the router cannot inspect it and must
-- broad-fallback. Batches containing these are never mismatch-eligible.
local function CountSecret(event)
    batch.secretFires = batch.secretFires + 1
    SP.secretFireTotal = SP.secretFireTotal + 1
    CountFire(event .. ":secret")
end

-- Identity fire naming a spell no button tracks (index miss). The intended
-- router DROPS these — most SPELL_UPDATE_COOLDOWN fires name untracked
-- spellbook spells. Whether dropping is safe is exactly what the drop-batch
-- mismatch counter (mismatchDropOnly) tests: a stale-index miss on a spell a
-- button DOES track would surface there.
local function CountMiss(event)
    batch.missFires = batch.missFires + 1
    SP.missFireTotal = SP.missFireTotal + 1
    CountFire(event .. ":miss")
end

-- Identity-arg fire. issecretvalue runs before any other operation touches
-- the arg.
local function NoteIdentityArg(event, spellID)
    if issecretvalue(spellID) then
        CountSecret(event)
        return true
    end
    if type(spellID) == "number" then
        if StampCovered(spellID) then
            batch.identityFires = batch.identityFires + 1
            SP.identityFireTotal = SP.identityFireTotal + 1
            CountFire(event .. ":id")
        else
            CountMiss(event)
        end
        return true
    end
    if spellID ~= nil then
        CountSecret(event)
        return true
    end
    return false
end

local function NoteBroadcast(event)
    batch.broadcastFires = batch.broadcastFires + 1
    SP.broadcastFireTotal = SP.broadcastFireTotal + 1
    CountFire(event .. ":bc")
end

-- Tap for OnCooldownStateChanged (SPELL/BAG/ACTIONBAR_UPDATE_COOLDOWN).
-- Args pass through untouched; issecretvalue is checked before any read.
function SP:NoteCooldownEvent(event, ...)
    if event == "SPELL_UPDATE_COOLDOWN" then
        local spellID
        if select("#", ...) > 0 then
            spellID = select(1, ...)
        end
        if not NoteIdentityArg(event, spellID) then
            NoteBroadcast(event)
        end
    else
        NoteBroadcast(event)
    end
end

-- Tap for OnChargesChanged (SPELL_UPDATE_CHARGES / SPELL_UPDATE_USES).
function SP:NoteChargesEvent(event, spellID, baseSpellID)
    if event == "SPELL_UPDATE_USES" then
        if not NoteIdentityArg(event, spellID) then
            NoteBroadcast(event)
        end
        -- Also cover the base spell when it differs. Never compare against
        -- spellID unless both are known non-secret plain values.
        if not issecretvalue(baseSpellID) and type(baseSpellID) == "number"
                and (issecretvalue(spellID) or baseSpellID ~= spellID) then
            StampCovered(baseSpellID)
        end
    else
        NoteBroadcast(event)
    end
end

local function DescribeButton(button)
    local buttonData = button.buttonData
    local groupId = button._groupId or (button:GetParent() and button:GetParent().groupId)
    return ("%s#%s:%s:%s"):format(
        tostring(groupId),
        tostring(button.index),
        tostring(buttonData and buttonData.type),
        tostring(buttonData and (buttonData.id or buttonData.itemSlot)))
end

local function BatchSummary()
    local parts, n = {}, 0
    for tag, count in pairs(batch.events) do
        n = n + 1
        parts[n] = tag .. "x" .. count
    end
    return table.concat(parts, ",", 1, n)
end

local function LogChange(kind, passSource, button, changedCount)
    local cursor = SP.logCursor % LOG_SIZE + 1
    SP.logCursor = cursor
    SP.logTotal = SP.logTotal + 1
    SP.log[cursor] = ("%.1f|%s|%s|%s|%s|%s"):format(
        GetTime(), kind, tostring(passSource),
        BatchSummary(), DescribeButton(button),
        table.concat(changedKeys, ",", 1, changedCount))
end

-- Read the signature fields into the button's reusable state table and
-- collect changed short keys into the shared scratch. When suppress is true
-- (first observation, or the button was not observed in the immediately
-- previous pass — new button, frame re-shown) the baseline is refreshed
-- without reporting changes.
local function ObserveButton(button, suppress)
    local st = button._shadowParityState
    if not st then
        st = {}
        button._shadowParityState = st
        suppress = true
    end
    local changedCount = 0
    local oldCd, newCd
    for i = 1, FIELD_COUNT do
        local field = FIELDS[i]
        local key = field[1]
        local value = button[field[2]]
        if issecretvalue(value) then
            SP.secretFieldSeen = SP.secretFieldSeen + 1
            value = SECRET
        elseif key == "alpha" and type(value) == "number" then
            value = floor(value * 100 + 0.5)
        end
        if key == "cd" then
            oldCd = st.cd
            newCd = value
        end
        if st[key] ~= value then
            if not suppress then
                changedCount = changedCount + 1
                changedKeys[changedCount] = key
            end
            st[key] = value
        end
    end
    return changedCount, oldCd, newCd
end

-- Classify an uncovered button's change set. Returns "cross", "usability",
-- "gcd", "expiry", or "core" (+ family "cooldown"/"charges" for "core").
local function Classify(changedCount, oldCd, newCd)
    local coreCount = 0
    local onlyTint = true
    local onlyGsup = true
    local cdChanged = false
    local gcdOk, expiryOk, chargeOnly = true, true, true
    for i = 1, changedCount do
        local key = changedKeys[i]
        if not CROSS_FAMILY[key] then
            coreCount = coreCount + 1
            if key == "cd" then cdChanged = true end
            if key ~= "tint" then onlyTint = false end
            if key ~= "gsup" then onlyGsup = false end
            if not GCD_SHAPE[key] then gcdOk = false end
            if not EXPIRY_SHAPE[key] then expiryOk = false end
            if not CHARGE_ONLY[key] then chargeOnly = false end
        end
    end
    if coreCount == 0 then
        return "cross"
    end
    if onlyTint then
        return "usability"
    end
    if onlyGsup then
        -- _barGCDSuppressed flips only with GCD activity (A1 shared
        -- snapshot); a gsup-only change is GCD settle even when the
        -- cooldown state itself did not change this pass.
        return "gcd"
    end
    if cdChanged and gcdOk and (oldCd == STATE_GCD or newCd == STATE_GCD) then
        return "gcd"
    end
    if cdChanged and expiryOk and newCd == STATE_READY then
        return "expiry"
    end
    return "core", chargeOnly and "charges" or "cooldown"
end

-- Called from the tail of every UpdateAllCooldowns pass (before telemetry's
-- RecordPass clears its pending attribution). Refreshes every visible
-- button's signature; when the pass consumed a pending event batch, changed
-- uncovered buttons are classified and counted.
function SP:NotePassEnd(passSource, passDetail)
    local passGen = self.passGen + 1
    self.passGen = passGen
    self.passTotal = self.passTotal + 1

    local evaluate = batch.fireCount > 0
    local broadRequired = batch.broadcastFires > 0 or batch.secretFires > 0
    local identityOnly = evaluate and not broadRequired and batch.missFires == 0
    local dropOnly = evaluate and not broadRequired and not identityOnly
    local uncoveredCoreChanges = 0
    local source = passDetail or passSource

    for _, frame in pairs(CooldownCompanion.groupFrames) do
        if frame and frame.UpdateCooldowns and frame.buttons and frame:IsShown() then
            for _, button in ipairs(frame.buttons) do
                local buttonData = button.buttonData
                if buttonData and buttonData._rotationAssistantVirtual ~= true then
                    local suppress = button._shadowParitySigGen ~= passGen - 1
                    local changedCount, oldCd, newCd = ObserveButton(button, suppress)
                    button._shadowParitySigGen = passGen
                    if evaluate and changedCount > 0 then
                        if button._shadowParityCoveredBatch == batch.id then
                            self.routedCoveredChanges = self.routedCoveredChanges + 1
                        else
                            local class, family = Classify(changedCount, oldCd, newCd)
                            if class == "cross" then
                                self.crossFamilyChanges = self.crossFamilyChanges + 1
                            elseif class == "usability" then
                                self.usabilityChanges = self.usabilityChanges + 1
                            elseif class == "gcd" then
                                self.gcdSettleChanges = self.gcdSettleChanges + 1
                            elseif class == "expiry" then
                                self.expirySettleChanges = self.expirySettleChanges + 1
                            elseif identityOnly then
                                self.shadowParityMismatchTotal = self.shadowParityMismatchTotal + 1
                                if family == "charges" then
                                    self.mismatchCharges = self.mismatchCharges + 1
                                else
                                    self.mismatchCooldown = self.mismatchCooldown + 1
                                end
                                uncoveredCoreChanges = uncoveredCoreChanges + 1
                                LogChange("MISMATCH", source, button, changedCount)
                            elseif dropOnly then
                                self.mismatchDropOnly = self.mismatchDropOnly + 1
                                uncoveredCoreChanges = uncoveredCoreChanges + 1
                                LogChange("DROPMISS", source, button, changedCount)
                            else
                                -- broadcasts stay on the broad path in Phase 3;
                                -- this is demotion evidence, not a mismatch
                                self.broadcastCarriedChanges = self.broadcastCarriedChanges + 1
                                uncoveredCoreChanges = uncoveredCoreChanges + 1
                                LogChange("BCARRY", source, button, changedCount)
                            end
                        end
                    end
                end
            end
        end
    end

    if evaluate then
        self.passesEvaluated = self.passesEvaluated + 1
        if identityOnly then
            self.passesIdentityOnly = self.passesIdentityOnly + 1
        elseif dropOnly then
            self.passesDropOnly = self.passesDropOnly + 1
        else
            self.passesWithBroadcast = self.passesWithBroadcast + 1
            if uncoveredCoreChanges == 0 then
                self.broadcastSilentPasses = self.broadcastSilentPasses + 1
            end
        end
        batch.id = batch.id + 1
        batch.fireCount = 0
        batch.identityFires = 0
        batch.broadcastFires = 0
        batch.missFires = 0
        batch.secretFires = 0
        wipe(batch.events)
    end
end

function CooldownCompanion:GetShadowParity()
    return SP
end

-- SV-safe copy (scalars + string tables only; no frame references).
function CooldownCompanion:GetShadowParityDiagnostics()
    local fires = {}
    for tag, count in pairs(SP.fireCounts) do
        fires[tag] = count
    end
    local log = {}
    for i = 1, LOG_SIZE do
        if SP.log[i] then
            log[#log + 1] = SP.log[i]
        end
    end
    return {
        enabled = SP.enabled,
        passTotal = SP.passTotal,
        passesEvaluated = SP.passesEvaluated,
        passesIdentityOnly = SP.passesIdentityOnly,
        passesDropOnly = SP.passesDropOnly,
        passesWithBroadcast = SP.passesWithBroadcast,
        identityFireTotal = SP.identityFireTotal,
        broadcastFireTotal = SP.broadcastFireTotal,
        missFireTotal = SP.missFireTotal,
        secretFireTotal = SP.secretFireTotal,
        routedCoveredChanges = SP.routedCoveredChanges,
        crossFamilyChanges = SP.crossFamilyChanges,
        usabilityChanges = SP.usabilityChanges,
        gcdSettleChanges = SP.gcdSettleChanges,
        expirySettleChanges = SP.expirySettleChanges,
        shadowParityMismatchTotal = SP.shadowParityMismatchTotal,
        mismatchCooldown = SP.mismatchCooldown,
        mismatchCharges = SP.mismatchCharges,
        mismatchDropOnly = SP.mismatchDropOnly,
        broadcastCarriedChanges = SP.broadcastCarriedChanges,
        broadcastSilentPasses = SP.broadcastSilentPasses,
        secretFieldSeen = SP.secretFieldSeen,
        logTotal = SP.logTotal,
        fireCounts = fires,
        log = log,
    }
end

function CooldownCompanion:ResetShadowParity()
    -- passGen keeps running (baseline continuity survives a reset)
    SP.passTotal = 0
    SP.passesEvaluated = 0
    SP.passesIdentityOnly = 0
    SP.passesDropOnly = 0
    SP.passesWithBroadcast = 0
    SP.identityFireTotal = 0
    SP.broadcastFireTotal = 0
    SP.missFireTotal = 0
    SP.secretFireTotal = 0
    SP.routedCoveredChanges = 0
    SP.crossFamilyChanges = 0
    SP.usabilityChanges = 0
    SP.gcdSettleChanges = 0
    SP.expirySettleChanges = 0
    SP.shadowParityMismatchTotal = 0
    SP.mismatchCooldown = 0
    SP.mismatchCharges = 0
    SP.mismatchDropOnly = 0
    SP.broadcastCarriedChanges = 0
    SP.broadcastSilentPasses = 0
    SP.secretFieldSeen = 0
    SP.logCursor = 0
    SP.logTotal = 0
    wipe(SP.log)
    wipe(SP.fireCounts)
end

function CooldownCompanion:PrintShadowParitySummary()
    self:Print(("ShadowParity: %d passes, %d evaluated (%d pure-id, %d id+miss, %d broad) | MISMATCH %d (cd %d, ch %d) dropMISM %d | noise: gcd %d, expiry %d, cross %d, usab %d | covered %d | bcast carried %d, silent %d | fires id %d, miss %d, bc %d, secret %d"):format(
        SP.passTotal, SP.passesEvaluated, SP.passesIdentityOnly, SP.passesDropOnly, SP.passesWithBroadcast,
        SP.shadowParityMismatchTotal, SP.mismatchCooldown, SP.mismatchCharges, SP.mismatchDropOnly,
        SP.gcdSettleChanges, SP.expirySettleChanges, SP.crossFamilyChanges, SP.usabilityChanges,
        SP.routedCoveredChanges,
        SP.broadcastCarriedChanges, SP.broadcastSilentPasses,
        SP.identityFireTotal, SP.missFireTotal, SP.broadcastFireTotal, SP.secretFireTotal))
    if SP.shadowParityMismatchTotal > 0 then
        self:Print("ShadowParity: mismatches logged — /dump CooldownCompanion:GetShadowParityDiagnostics()")
    end
end

-- Gate: enable only when the CC_DevBridge dev addon is present (same pattern
-- and reason as RefreshTelemetry).
local gateFrame = CreateFrame("Frame")
gateFrame:RegisterEvent("PLAYER_LOGIN")
gateFrame:SetScript("OnEvent", function(frame)
    frame:UnregisterAllEvents()
    local _, loaded = C_AddOns.IsAddOnLoaded("CC_DevBridge")
    if loaded then
        SP.enabled = true
    end
end)
