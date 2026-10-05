--[[
    CooldownCompanion - Core/NameplateReminders.lua: Nameplate Reminders.

    An aura Indicator anchored to Enemy Nameplates (Layout > Anchor Target,
    ST.Indicator.IsNameplate) draws its While Missing look, and its Also
    During Pandemic look, on every qualifying enemy nameplate instead of on
    screen. Nothing here reads aura
    state: each reminder is a nameplate WATCHER (AuraDisplay's
    Presence.NewPlateWatcher, the only code that builds or binds its slot
    subtree) whose hidden Blizzard tracker opens a clip window while the aura
    is missing (CC_PlateMissProbe v1-v4, live 12.1, 2026-10-04).

    This file owns everything that does not touch a slot:
      * BANKS: 8 watchers per running nameplate DoT, 20 once you have been
        in an instance this session (each DoT is its
        own spot in its Indicator's row), at most 5 banks. A bank is built
        once and then re-pointed (a filter swap plus a restyle on hidden
        watchers) whenever the Indicators change, so spec, profile and
        Indicator edits never build more: every AuraButton is permanent,
        about 0.3 MB a watcher.
      * The BUILDER: a couple of watchers per frame, only while the rebind
        pass could run (out of combat, auras not secret). Never inside
        RunAuraRebind: one long pass brushes the script watchdog at login.
      * The HAND-OUT: a watcher goes only to a mob that qualifies (hostile,
        in combat, not minor or trivial) while you are in combat. Its cell is
        parented to the nameplate and its container re-pointed with SetUnit,
        both combat-safe (probe v4). UNIT_FLAGS rarely fires as a plate unit
        enters combat, so threat updates and UNIT_COMBAT re-check too.
      * Placement on the plate, the unload release, and status counters.
]]

local _, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local pairs = pairs
local issecretvalue = issecretvalue
local UnitExists = UnitExists
local UnitCanAttack = UnitCanAttack
local UnitCanAssist = UnitCanAssist
local UnitAffectingCombat = UnitAffectingCombat
local UnitThreatSituation = UnitThreatSituation
local UnitClassification = UnitClassification
local GetNamePlateForUnit = C_NamePlate.GetNamePlateForUnit
local InCombatLockdown = InCombatLockdown
local debugprofilestop = debugprofilestop

-- Mobs per DoT at once (owner rulings 2026-10-05): 8 until you first enter an
-- instance (dungeon, raid, delve, battleground, arena), then 20 for the rest of the
-- session, everywhere and for every DoT, new ones too: watchers are
-- permanent, so the memory is spent once grown, and using it costs nothing.
-- The first instance grows the banks, out of combat. A freed watcher passes
-- to the next mob waiting.
local OPEN_WORLD_BANK, INSTANCE_BANK = 8, 20
local IsInInstance = IsInInstance
-- Instances with mob packs. Housing ("neighborhood", "interior") and other
-- instanced places don't count (IsInInstance's instanceType, generated records).
local PACK_INSTANCES = { party = true, raid = true, scenario = true, pvp = true, arena = true }
local seenInstance = false
local function BankSize()
    if not seenInstance then
        local inInstance, instanceType = IsInInstance()
        if inInstance and PACK_INSTANCES[instanceType] then seenInstance = true end
    end
    return seenInstance and INSTANCE_BANK or OPEN_WORLD_BANK
end
local MAX_BANKS = ST.Indicator.MAX_NAMEPLATE_DOTS
local BUILD_PER_FRAME = 2
local MAX_PLATE_TOKENS = 80

local N = {}
ST._NameplateReminders = N

-- O(1) token test for unfiltered unit events (UNIT_COMBAT fires per hit).
local PLATE_TOKENS = {}
for index = 1, MAX_PLATE_TOKENS do PLATE_TOKENS["nameplate" .. index] = true end

-- Where a released cell waits: hidden, so its containers hear nothing.
local holder = CreateFrame("Frame", nil, UIParent)
holder:Hide()

-- banks[i] = { watchers = {}, free = {}, byToken = {}, waiting = {},
--   groupId, group, aura, spellSet, spellKey, point, x, y }
local banks = {}
local runningDoTs = {}   -- groupId of every running nameplate DoT, bank order
local overCap = {}       -- groupId -> true when one of its DoTs runs past MAX_BANKS
local playerInCombat = false
local status = {
    watchersBuilt = 0, buildMs = 0, handedOut = 0, handedOutNow = 0, maxHandedOut = 0,
    combatMoves = 0, exhausted = 0, released = 0, missingPlate = 0,
}

local eventFrame = CreateFrame("Frame")
local builderFrame = CreateFrame("Frame")
local baseEventsOn, combatEventsOn = false, false

------------------------------------------------------------------------
-- Rules
------------------------------------------------------------------------

-- A secret answer counts as "yes" (the probe's rule): the reminder stays
-- visible rather than silently missing a mob.
local function Truthy(value)
    if issecretvalue(value) then return true end
    return value == true
end

-- CC's fail-closed identity rule for a HARMFUL tracker (AuraDisplay's
-- CanApplySpellIdentityFilter), plus attackable.
local function Hostile(token)
    return UnitExists(token) == true
        and Truthy(UnitCanAttack("player", token))
        and UnitCanAssist("player", token, true, true) ~= true
end

local IGNORED_CLASSIFICATION = { minus = true, trivial = true }

-- You are on the mob's threat list: what Blizzard's own nameplate reads to
-- turn its in-combat color (CompactUnitFrame_IsOnThreatListWithPlayer). It
-- arrives with UNIT_THREAT_LIST_UPDATE, before a body-pulled mob's combat
-- flag reads true (owner report 2026-10-05: the rest of a pack lagged).
-- Only a readable answer counts: a secret one (threat state restricted, per
-- the generated records) leaves the combat flag to decide.
local function OnYourThreatList(token)
    local status = UnitThreatSituation("player", token)
    return not issecretvalue(status) and status ~= nil
end

-- Owner ruling 2026-10-04: in-combat hostile mobs (their combat flag, or you
-- on their threat list), while you are in combat, never minor or trivial ones. UnitAffectingCombat and UnitClassification
-- are not secret-annotated (generated records, build 69587).
local function Qualifies(token)
    if not playerInCombat or not Hostile(token) then return false end
    if not (Truthy(UnitAffectingCombat(token)) or OnYourThreatList(token)) then return false end
    local classification = UnitClassification(token)
    if issecretvalue(classification) then return true end
    return not IGNORED_CLASSIFICATION[classification]
end

------------------------------------------------------------------------
-- Placement
------------------------------------------------------------------------

-- The cell is the padded presence cell with the display at its center, so
-- each side puts the DISPLAY's near edge on the plate's edge, then the
-- user's offset, then DoT `index` of `count`'s spot along the row. Shared
-- with the config's target-plate preview.
local function PlacementAt(group, along)
    local I = ST.Indicator
    local placement = I.NameplatePlacement(group)
    local width, height = I.DisplaySize(group)
    local x, y, side = placement.x + along, placement.y, placement.side
    if side == "above" then return "TOP", x, y + height / 2 end
    if side == "below" then return "BOTTOM", x, y - height / 2 end
    if side == "left" then return "LEFT", x - width / 2, y end
    if side == "right" then return "RIGHT", x + width / 2, y end
    -- Corners: outside the top or bottom edge, inside the side edge.
    if side == "topleft" then return "TOPLEFT", x + width / 2, y + height / 2 end
    if side == "topright" then return "TOPRIGHT", x - width / 2, y + height / 2 end
    if side == "bottomleft" then return "BOTTOMLEFT", x + width / 2, y - height / 2 end
    if side == "bottomright" then return "BOTTOMRIGHT", x - width / 2, y - height / 2 end
    return "CENTER", x, y
end

local function PlacementFor(group, index, count)
    return PlacementAt(group, ST.Indicator.NameplateSpotOffset(group, index or 1, count or 1))
end

N.PlacementFor = PlacementFor

-- The whole row as one box (the unlock view's frame): where its center sits
-- on the plate, its size, and how far along the row that center is from the
-- first DoT's spot.
function N.RowBox(group, count)
    local I = ST.Indicator
    local width, height = I.DisplaySize(group)
    local low, high = 0, 0
    for index = 1, math.max(1, count) do
        local along = I.NameplateSpotOffset(group, index, count)
        if index == 1 or along < low then low = along end
        if index == 1 or along > high then high = along end
    end
    local center = (low + high) / 2
    local point, x, y = PlacementAt(group, center)
    return point, x, y, high - low + width, height, center
end

------------------------------------------------------------------------
-- Hand-out
------------------------------------------------------------------------

local function Release(bank, token)
    local watcher = bank.byToken[token]
    if not watcher then return end
    bank.byToken[token] = nil
    status.handedOutNow = status.handedOutNow - 1
    watcher.cell:Hide()
    watcher.cell:SetParent(holder)
    watcher.token = nil
    bank.free[#bank.free + 1] = watcher
    status.released = status.released + 1
end

local Grant -- ServeWaiting re-enters it

local function ServeWaiting(bank)
    while #bank.free > 0 do
        local token = next(bank.waiting)
        if not token then return end
        bank.waiting[token] = nil
        if UnitExists(token) and Qualifies(token) then Grant(bank, token) end
    end
end

function Grant(bank, token)
    if bank.byToken[token] or not bank.groupId then return end
    local watcher = table.remove(bank.free)
    if not watcher then
        status.exhausted = status.exhausted + 1
        bank.waiting[token] = true
        return
    end
    local plate = GetNamePlateForUnit(token)
    if not plate then
        status.missingPlate = status.missingPlate + 1
        bank.free[#bank.free + 1] = watcher
        return
    end
    bank.byToken[token] = watcher
    watcher.token = token
    local cell = watcher.cell
    -- A CC frame onto the protected plate: never blocked in combat (probe:
    -- 62 attaches and moves, 0 ADDON_ACTION_BLOCKED). The AuraButtons below
    -- are never reparented themselves.
    cell:SetParent(plate)
    cell:ClearAllPoints()
    cell:SetPoint("CENTER", plate, bank.point, bank.x, bank.y)
    -- SetUnit re-parses only when the token changes; a watcher handed back
    -- to the same token (a new mob in that slot) needs the parse itself.
    -- Showing the cell re-registers the container, so parse after.
    local container = watcher.container
    local sameToken = container:GetUnit() == token
    if not sameToken then container:SetUnit(token) end
    cell:Show()
    if sameToken then container:UpdateAllAuras() end
    if InCombatLockdown() then status.combatMoves = status.combatMoves + 1 end
    status.handedOut = status.handedOut + 1
    status.handedOutNow = status.handedOutNow + 1
    if status.handedOutNow > status.maxHandedOut then status.maxHandedOut = status.handedOutNow end
end

-- `token`'s rule may have changed: hand a watcher out, or give it back.
local function Reevaluate(token)
    local qualifies = Qualifies(token)
    for _, bank in ipairs(banks) do
        if bank.groupId and not bank.suspended then
            if qualifies then
                if not bank.byToken[token] and not bank.waiting[token] then Grant(bank, token) end
            else
                bank.waiting[token] = nil
                if bank.byToken[token] then
                    Release(bank, token)
                    ServeWaiting(bank)
                end
            end
        end
    end
end

-- Whether every running bank already holds (or queues) `token`: UNIT_COMBAT
-- fires per hit, so a covered plate costs one loop and no API calls.
local function Covered(token)
    for _, bank in ipairs(banks) do
        if bank.groupId and not bank.suspended and not bank.byToken[token] and not bank.waiting[token] then
            return false
        end
    end
    return true
end

local function ReleaseBank(bank)
    for token in pairs(bank.byToken) do Release(bank, token) end
    for token in pairs(bank.waiting) do bank.waiting[token] = nil end
end

local function ReleaseAll()
    for _, bank in ipairs(banks) do ReleaseBank(bank) end
end

local function EvaluateAllPlates()
    for index = 1, MAX_PLATE_TOKENS do
        local token = "nameplate" .. index
        if UnitExists(token) then Reevaluate(token) end
    end
end

------------------------------------------------------------------------
-- Events
------------------------------------------------------------------------

local BASE_EVENTS = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "UNIT_FACTION" }
-- Only while you fight: a plate's own combat entry, threat and hits.
local COMBAT_EVENTS = { "UNIT_FLAGS", "UNIT_THREAT_LIST_UPDATE", "UNIT_COMBAT",
    "UNIT_CLASSIFICATION_CHANGED" }

local function SetCombatEvents(on)
    if combatEventsOn == on then return end
    combatEventsOn = on
    for _, event in ipairs(COMBAT_EVENTS) do
        if on then eventFrame:RegisterEvent(event) else eventFrame:UnregisterEvent(event) end
    end
end

local function SetBaseEvents(on)
    if baseEventsOn == on then return end
    baseEventsOn = on
    for _, event in ipairs(BASE_EVENTS) do
        if on then eventFrame:RegisterEvent(event) else eventFrame:UnregisterEvent(event) end
    end
    if not on then SetCombatEvents(false) end
end

eventFrame:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_REGEN_DISABLED" then
        playerInCombat = true
        SetCombatEvents(true)
        EvaluateAllPlates()
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Reminders show only while you fight: out of combat none is out.
        playerInCombat = false
        SetCombatEvents(false)
        ReleaseAll()
        return
    end
    if issecretvalue(unit) or not PLATE_TOKENS[unit] then return end
    if event == "NAME_PLATE_UNIT_REMOVED" then
        for _, bank in ipairs(banks) do
            bank.waiting[unit] = nil
            if bank.byToken[unit] then
                Release(bank, unit)
                ServeWaiting(bank)
            end
        end
    elseif event == "UNIT_COMBAT" then
        if not Covered(unit) then Reevaluate(unit) end
    else
        Reevaluate(unit)
    end
end)

------------------------------------------------------------------------
-- Builder
------------------------------------------------------------------------

local function NextBankToBuild()
    for _, bank in ipairs(banks) do
        if bank.groupId and #bank.watchers < BankSize() then return bank end
    end
end

local function BindWatcherOnly(bank, watcher)
    ST._PlateWatcher.Bind(watcher, bank.group, bank.spellSet, bank.aura)
end

local function BindWatcher(bank, watcher)
    BindWatcherOnly(bank, watcher)
    bank.free[#bank.free + 1] = watcher
end

local function StopBuilder()
    builderFrame:SetScript("OnUpdate", nil)
end

local function BuildStep()
    if not CooldownCompanion:CanRunAuraRebindNow() then
        -- Combat or secret auras: AuraButton setup is restricted. Wait for
        -- the window to reopen (the builder's events below).
        StopBuilder()
        builderFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        builderFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
        return
    end
    for _ = 1, BUILD_PER_FRAME do
        local bank = NextBankToBuild()
        if not bank then
            StopBuilder()
            return
        end
        local started = debugprofilestop()
        local watcher = ST._PlateWatcher.New(holder)
        bank.watchers[#bank.watchers + 1] = watcher
        BindWatcher(bank, watcher)
        status.watchersBuilt = status.watchersBuilt + 1
        status.buildMs = status.buildMs + (debugprofilestop() - started)
    end
end

local function StartBuilder()
    if NextBankToBuild() then builderFrame:SetScript("OnUpdate", BuildStep) end
end

builderFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
builderFrame:SetScript("OnEvent", function(self, event, _, restrictionState)
    -- A loading screen may have entered an instance: grow the banks to its
    -- size (BuildStep waits out combat and secret auras itself).
    if event == "PLAYER_ENTERING_WORLD" then
        BankSize() -- notes an instance even with no reminder running yet
        StartBuilder()
        return
    end
    -- Only Inactive is a wakeup (AuraDisplay's rebind retry rule).
    if event == "ADDON_RESTRICTION_STATE_CHANGED"
        and restrictionState ~= Enum.AddOnRestrictionState.Inactive then return end
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
    self:UnregisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    StartBuilder()
end)

------------------------------------------------------------------------
-- Binding (from RunAuraRebind, out of combat)
------------------------------------------------------------------------

-- Rebind reasons that never change how a reminder looks (who is loaded,
-- the roster, vehicles): a full pass made only of these re-points the banks
-- without restyling their watchers. Anything else restyles them all.
local ROUTINE_REBIND_REASONS = {
    roster = true, unload = true, recover = true, availability = true, delete = true,
    ["vehicle-ui"] = true, ["vehicle-actionbar"] = true, ["viewer-map"] = true,
    ["pandemic-anchor"] = true, ["talent-charge-settle"] = true, ["sound-media"] = true,
    ["bar-layers"] = true, resources = true,
}
local restylePending = true

-- From RequestAuraRebind, for every request.
function N.NoteRebindRequest(reason)
    if not ROUTINE_REBIND_REASONS[reason] then restylePending = true end
end

local function SpellKey(spellSet)
    local ids = {}
    for spellID in pairs(spellSet) do ids[#ids + 1] = spellID end
    table.sort(ids)
    return table.concat(ids, ",")
end

local function NewBank()
    return { watchers = {}, free = {}, byToken = {}, waiting = {} }
end

-- `wants` = every running nameplate DoT ({groupId, group, aura, spellSet,
-- index, count}); `panelIds` = the pass's scope (nil for a full pass).
-- Called only by the rebind pass, so never in combat: no watcher is out,
-- all are hidden.
function N.Bind(wants, panelIds)
    table.sort(wants, function(a, b)
        if a.groupId ~= b.groupId then return a.groupId < b.groupId end
        return a.index < b.index
    end)
    ReleaseAll()
    -- Taken now: a request made during this pass belongs to the next one.
    local restyle = restylePending
    restylePending = false
    for key in pairs(overCap) do overCap[key] = nil end
    for index = #runningDoTs, 1, -1 do runningDoTs[index] = nil end
    for index, want in ipairs(wants) do
        runningDoTs[index] = want.groupId
        if index > MAX_BANKS then overCap[want.groupId] = true end
    end
    for index = 1, MAX_BANKS do
        local want = wants[index]
        local bank = banks[index]
        if want then
            if not bank then
                bank = NewBank()
                banks[index] = bank
            end
            local spellKey = SpellKey(want.spellSet)
            local changed = bank.groupId ~= want.groupId or bank.group ~= want.group or bank.aura ~= want.aura
                or bank.spellKey ~= spellKey
                or (panelIds and panelIds[want.groupId]) or (not panelIds and restyle)
            bank.groupId, bank.group, bank.aura = want.groupId, want.group, want.aura
            bank.spellSet, bank.spellKey = want.spellSet, spellKey
            bank.suspended = nil
            bank.point, bank.x, bank.y = PlacementFor(want.group, want.index, want.count)
            if changed then
                for _, watcher in ipairs(bank.watchers) do BindWatcherOnly(bank, watcher) end
            end
        elseif bank and bank.groupId then
            for _, watcher in ipairs(bank.watchers) do ST._PlateWatcher.Park(watcher) end
            bank.groupId, bank.group, bank.aura, bank.spellSet, bank.spellKey = nil, nil, nil, nil, nil
        end
    end
    local running = wants[1] ~= nil
    -- While listening, the regen events own the combat flag (InCombatLockdown
    -- can still read false inside PLAYER_REGEN_DISABLED); only a fresh start
    -- reads it.
    local wasListening = baseEventsOn
    SetBaseEvents(running)
    if running and not wasListening then playerInCombat = InCombatLockdown() end
    if running then StartBuilder() else StopBuilder() end
end

-- An Indicator stopped running between passes (unloaded, deleted, its load
-- conditions changed mid-fight): give its watchers back at once, CC-frame
-- writes only, and keep the bank quiet until the deferred pass re-points it.
function N.ReleaseGroup(groupId)
    ST._NameplateTargetView.Forget(groupId)
    for _, bank in ipairs(banks) do
        if bank.groupId == groupId then
            ReleaseBank(bank)
            bank.suspended = true
        end
    end
end

-- Config: how many nameplate DoTs run (optionally leaving out one
-- Indicator's own), and whether an Indicator has a DoT past the cap.
function N.RunningDoTCount(excludeGroupId)
    local count = 0
    for _, groupId in ipairs(runningDoTs) do
        if groupId ~= excludeGroupId then count = count + 1 end
    end
    return count
end

function N.IsOverCap(groupId)
    return overCap[groupId] == true
end

N.MAX_DOTS = MAX_BANKS
N.BankSize = BankSize

function CooldownCompanion:GetNameplateReminderStatus()
    local built = 0
    for _, bank in ipairs(banks) do built = built + #bank.watchers end
    return {
        banks = #banks,
        watchers = built,
        bankSize = BankSize(),
        watchersBuilt = status.watchersBuilt,
        buildMs = status.buildMs,
        runningDoTs = #runningDoTs,
        handedOutNow = status.handedOutNow,
        handedOutTotal = status.handedOut,
        maxHandedOut = status.maxHandedOut,
        combatMoves = status.combatMoves,
        exhausted = status.exhausted,
        released = status.released,
        missingPlate = status.missingPlate,
    }
end
