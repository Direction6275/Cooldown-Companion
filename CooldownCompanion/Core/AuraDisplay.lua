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
    Evidence: docs/12.1-aura-tracking-research.md; validation matrix V1-V18 and
    Phase 0 probes P1-P11.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

local ipairs = ipairs
local pairs = pairs
local InCombatLockdown = InCombatLockdown
local UnitExists = UnitExists
local UnitAffectingCombat = UnitAffectingCombat
local CreateFrame = CreateFrame

-- Parking (P1b/P1c): slots can never be removed; unbound slots get a sentinel
-- filter + a hidden parent. Empty includeSpellIDs is BANNED — it wedges the
-- slot permanently. Sentinels are POLARITY-CROSSED so they are structurally
-- never-match: a HELPFUL slot parked on a debuff spellID (debuffs can never
-- appear in HELPFUL results) and a HARMFUL slot parked on a buff spellID.
local PARK_SENTINEL = {
    player = 155722, -- Rake (a bleed debuff; never matches a HELPFUL filter)
    target = 5217,   -- Tiger's Fury (a self buff; never matches a HARMFUL filter)
}

local UNIT_FILTER = { player = "HELPFUL", target = "HARMFUL" }

-- Module state. Slot records deliberately live only here — no slot-button
-- references are ever stored on CC buttons, so no sweep or diagnostic walk
-- can reach the forbidden subtree by accident.
local holder, park
local containers = {}     -- unit -> AuraContainer
local slots = { player = {}, target = {} } -- unit -> array of slot records
local slotCounter = 0
local pendingRebind = false
local rebindQueued = false
local containerCreateFailed = false

------------------------------------------------------------------------
-- Containers
------------------------------------------------------------------------

local targetWatcher
local RunAuraRebind

local function CanRunRebindNow()
    if InCombatLockdown() then return false end
    -- P11 (conservative): secrecy follows the unit's state, so target slots
    -- are only touchable while the target is also out of combat.
    local hasTargetSlots = #slots.target > 0
    if hasTargetSlots and UnitExists("target") and UnitAffectingCombat("target") then
        return false
    end
    return true
end

local function EnsureTargetWatcher()
    if targetWatcher then return end
    targetWatcher = CreateFrame("Frame")
    targetWatcher:RegisterEvent("PLAYER_TARGET_CHANGED")
    targetWatcher:SetScript("OnEvent", function()
        -- Container-level call: combat-safe (V13, re-validated V18). Without
        -- it the target container never re-parses on same-token target swaps.
        local container = containers.target
        if container then
            container:UpdateAllAuras()
        end
        -- A deferred rebind may have been blocked only by target combat.
        if pendingRebind and CanRunRebindNow() then
            pendingRebind = false
            RunAuraRebind()
        end
    end)
end

local function EnsureContainer(unit)
    local container = containers[unit]
    if container then return container end
    if containerCreateFailed then return nil end
    if not holder then
        -- P1a: the holder must stay SHOWN — a hidden parent makes the
        -- container unregister UNIT_AURA (AuraContainerPrivateMixin:
        -- ShouldRegisterForDynamicEvents requires IsVisible()). It is 2px in
        -- the corner and owns no textures; nothing ever renders from it
        -- because slot buttons are reparented out into CC buttons.
        holder = CreateFrame("Frame", nil, UIParent)
        holder:SetSize(2, 2)
        holder:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 2, 2)
        -- The park frame IS hidden: parked slot buttons must never render,
        -- and slot visibility does not affect the container's registration.
        park = CreateFrame("Frame", nil, UIParent)
        park:SetSize(2, 2)
        park:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 2, 2)
        park:Hide()
    end
    local ok, created = pcall(CreateFrame, "AuraContainer", nil, holder, "CustomAuraContainerTemplate")
    if not ok or not created then
        -- Degrade to no aura display rather than erroring on load; this only
        -- fires if the client predates the AuraContainer API.
        containerCreateFailed = true
        CooldownCompanion:Print("Aura tracking unavailable: AuraContainer API missing on this client.")
        return nil
    end
    created:SetUnit(unit)
    containers[unit] = created
    if unit == "target" then
        EnsureTargetWatcher()
    end
    return created
end

------------------------------------------------------------------------
-- Slot kit — built ONCE per slot, inside initializeFrame (the sanctioned
-- setup window). Regions cover every configuration because slots are reused
-- across entries; per-entry enable/disable is alpha at bind time (P6).
------------------------------------------------------------------------

local function BuildSlotKit(slotButton)
    local kit = {}

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
    slotButton:SetDurationCooldown(kit.swipe)

    kit.textOverlay = CreateFrame("Frame", nil, slotButton)
    kit.textOverlay:SetAllPoints(slotButton)
    kit.textOverlay:SetFrameLevel(kit.swipe:GetFrameLevel() + 1)

    -- Default formatter ONLY: custom formatters/curves error on secret values
    -- mid-refresh and freeze the button (V14/V15 — banned until Blizzard fixes).
    kit.durationText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightOutline")
    kit.durationText:SetPoint("BOTTOM", slotButton, "BOTTOM", 0, 1)
    slotButton:SetDurationText(kit.durationText)

    kit.stackText = kit.textOverlay:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmallOutline")
    kit.stackText:SetPoint("TOPRIGHT", slotButton, "TOPRIGHT", -1, -1)
    slotButton:SetApplicationCount(kit.stackText)

    return kit
end

-- Phase 1 styling: defaults only (per-feature style keys arrive in Phases 2-3).
local function StyleSlotKit(slot, button, buttonData)
    local kit = slot.kit
    if not kit then return end
    kit.auraIcon:SetAlpha(buttonData.auraShowAuraIcon and 1 or 0)
    -- Occluding cover: the entry's icon, cropped like the CC icon underneath
    -- (read at bind time — CC-owned texture, OOC-safe). Known edge: a combat
    -- icon override (form swap) can't refresh the cover until the next rebind;
    -- Phase 2's icon-swap work owns that.
    local ccIcon = button.icon
    if ccIcon and ccIcon.GetTexture and ccIcon:GetTexture() then
        kit.iconCover:SetTexture(ccIcon:GetTexture())
        kit.iconCover:SetTexCoord(ccIcon:GetTexCoord())
        kit.iconCover:SetAlpha(1)
    elseif buttonData.type == "spell" and buttonData.id then
        kit.iconCover:SetTexture(C_Spell.GetSpellTexture(buttonData.id))
        kit.iconCover:SetAlpha(1)
    else
        kit.iconCover:SetAlpha(0)
    end
    kit.durationText:SetAlpha(1)
    kit.stackText:SetAlpha(1)
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

local function CreateSlot(unit)
    local container = EnsureContainer(unit)
    if not container then return nil end
    slotCounter = slotCounter + 1
    local record = {
        key = "cc" .. slotCounter,
        unit = unit,
    }
    local ok, slotButton = pcall(container.AddAuraSlot, container, record.key, UNIT_FILTER[unit], {
        candidateFilters = BuildCandidateFilters(unit, { [PARK_SENTINEL[unit]] = true }),
        initializeFrame = function(frame)
            record.kit = BuildSlotKit(frame)
        end,
    })
    if not ok or not slotButton then
        CooldownCompanion:Print("Aura slot creation failed: " .. tostring(slotButton))
        return nil
    end
    record.slotButton = slotButton
    record.container = container
    local unitSlots = slots[unit]
    unitSlots[#unitSlots + 1] = record
    return record
end

local function ParkSlot(slot)
    if slot.hostButton then
        slot.hostButton._auraSlotHostToken = nil
        slot.hostButton = nil
    end
    if not slot.parked then
        slot.parked = true
        slot.boundEntry = nil
        slot.slotButton:SetParent(park)
        slot.slotButton:ClearAllPoints()
        slot.slotButton:SetPoint("CENTER", park, "CENTER")
        slot.container:SetAuraSlotCandidateFilters(slot.key,
            BuildCandidateFilters(slot.unit, { [PARK_SENTINEL[slot.unit]] = true }))
    end
end

-- The auraLayer is the CC-owned mount point for the slot subtree. It (and
-- everything under it) is excluded from every recursive frame sweep via the
-- _ccNoTouch flag; the layer itself is safe to touch, its children are not.
local function EnsureAuraLayer(button)
    local layer = button.auraLayer
    if not layer then
        layer = CreateFrame("Frame", nil, button)
        layer._ccNoTouch = true
        local anchorTo = button.icon or button
        layer:SetPoint("TOPLEFT", anchorTo, "TOPLEFT", 0, 0)
        layer:SetPoint("BOTTOMRIGHT", anchorTo, "BOTTOMRIGHT", 0, 0)
        button.auraLayer = layer
    end
    -- Above every configurable button element (LoC sits at baseLevel+7).
    layer:SetFrameLevel(button:GetFrameLevel() + 8)
    return layer
end

local function BindSlot(slot, button, buttonData, spellSet)
    local layer = EnsureAuraLayer(button)
    local slotButton = slot.slotButton
    slotButton:SetParent(layer)
    slotButton:ClearAllPoints()
    slotButton:SetPoint("TOPLEFT", layer, "TOPLEFT", 0, 0)
    slotButton:SetPoint("BOTTOMRIGHT", layer, "BOTTOMRIGHT", 0, 0)
    slot.container:SetAuraSlotCandidateFilters(slot.key, BuildCandidateFilters(slot.unit, spellSet))
    StyleSlotKit(slot, button, buttonData)
    -- Tooltip suppression follows the click-through sweep's recorded motion
    -- state (the sweep itself never reaches the slot subtree). P7-validated.
    slotButton:SetMouseMotionEnabled(not button._cdcClickThroughMotion)
    slot.parked = nil
    slot.boundEntry = buttonData
    slot.hostButton = button
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

function RunAuraRebind()
    local self = CooldownCompanion
    if not (self.db and self.groupFrames) then return end

    -- Collect wanted bindings from live buttons (icon/bar groups only — text
    -- mode has no compliant aura display; trigger/texture panels lost aura
    -- conditions by design; dormant flags there stay dormant).
    local wanted = { player = {}, target = {} }
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
                        local list = wanted[unit]
                        list[#list + 1] = { button = button, buttonData = buttonData, spellSet = spellSet }
                    end
                end
            end
        end
    end

    for unit, list in pairs(wanted) do
        local unitSlots = slots[unit]
        -- Park everything first (also clears host tokens), then bind fresh —
        -- simple and idempotent; runs at config-change frequency, never per tick.
        for _, slot in ipairs(unitSlots) do
            ParkSlot(slot)
        end
        for i, want in ipairs(list) do
            local slot = unitSlots[i] or CreateSlot(unit)
            if not slot then break end
            BindSlot(slot, want.button, want.buttonData, want.spellSet)
        end
    end
end

local rebindDeferFrame = CreateFrame("Frame")
rebindDeferFrame:SetScript("OnEvent", function(frame)
    -- Unregister BEFORE running so an error can't leave the event stuck
    -- (FrameAnchoring's combat-defer pattern).
    frame:UnregisterEvent("PLAYER_REGEN_ENABLED")
    pendingRebind = false
    if CanRunRebindNow() then
        RunAuraRebind()
    else
        -- Still blocked (target fighting while we left combat): re-arm; the
        -- target watcher also retries on target changes.
        pendingRebind = true
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
    end
end)

-- Single entry point. OOC requests coalesce into one next-frame pass (group
-- populates arrive once per group on a reload); the timer callback re-checks
-- combat and re-defers if a pull started in between.
function CooldownCompanion:RequestAuraRebind(reason)
    if not self.db then return end
    if not CanRunRebindNow() then
        if pendingRebind then return end
        pendingRebind = true
        rebindDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        return
    end
    if rebindQueued then return end
    rebindQueued = true
    C_Timer.After(0, function()
        rebindQueued = false
        if CanRunRebindNow() then
            RunAuraRebind()
        elseif not pendingRebind then
            pendingRebind = true
            rebindDeferFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        end
    end)
end

-- Read-only status for validation/DevBridge (module state is otherwise local).
function CooldownCompanion:GetAuraDisplayStatus()
    local status = { pendingRebind = pendingRebind, units = {} }
    for unit, unitSlots in pairs(slots) do
        local bound = 0
        for _, slot in ipairs(unitSlots) do
            if slot.boundEntry then bound = bound + 1 end
        end
        status.units[unit] = { slots = #unitSlots, bound = bound }
    end
    return status
end
