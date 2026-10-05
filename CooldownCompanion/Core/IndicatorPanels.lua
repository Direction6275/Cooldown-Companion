-- Indicator identity and saved presentation. Aura state never enters this model.
local _, ST = ...
local Addon = ST.Addon
local I = {}
ST.Indicator = I

function ST.IsIndicatorGroup(group)
    return type(group) == "table" and group.displayMode == "indicator"
end

function I.Settings(group)
    return ST.IsIndicatorGroup(group) and group.indicatorSettings or nil
end

function I.IsAura(group)
    local settings = I.Settings(group)
    return settings and settings.tracking == "aura" or false
end

function I.UsesSourceSounds(group)
    local settings = I.Settings(group)
    if not settings then return false end
    local source = I.Primary(group)
    return settings.tracking == "aura" or (settings.sourceSounds == true and source and source.type == "spell") or false
end

function I.Primary(group)
    return I.Settings(group) and group.buttons and group.buttons[1]
end

-- The aura row's one When rule, saved on the aura entry as
-- `indicatorStackRule` so it leaves with the aura and Change... carries it:
-- "missing" (While Missing), a stack comparison, or nil (While Active). Read
-- it only through AuraWhenOf / ShowsWhileMissing / StackCompare, never by
-- poking `compare` directly: "missing" is not a stack comparison.
local function AuraWhenOf(source)
    local rule = source and source.indicatorStackRule
    local compare = type(rule) == "table" and rule.compare
    return type(compare) == "string" and compare or "active"
end

local function SameSource(a, b)
    return a.type == b.type and a.id == b.id and a.itemSlot == b.itemSlot
end

-- Several auras (AND/OR). The first aura is the main source (slot one); every
-- other aura in the list is flagged `indicatorAuraListed`. Older aura-added
-- rule rows carry no flag and stay rule rows.
local function IsListedAura(group, entry)
    return entry ~= nil and entry.addedAs == "aura"
        and (entry == I.Primary(group) or entry.indicatorAuraListed == true)
end

function I.IsListedAura(group, entry)
    return I.IsAura(group) and IsListedAura(group, entry) or false
end

-- The auras an aura Indicator checks, main source first.
function I.AuraList(group)
    local list = {}
    if not I.IsAura(group) then return list end
    for _, entry in ipairs(group.buttons) do
        if IsListedAura(group, entry) then list[#list + 1] = entry end
    end
    return list
end

-- On the per-update path: a flag scan only (past slot one an aura is in the
-- list exactly when flagged).
function I.IsMultiAura(group)
    if not I.IsAura(group) then return false end
    local buttons = group.buttons
    for index = 2, #buttons do
        local entry = buttons[index]
        if entry.indicatorAuraListed == true and entry.addedAs == "aura" then return true end
    end
    return false
end

-- With two or more auras, each keeps its own When (While Active or While
-- Missing, AuraWhenOf) and the list has one Match, saved in
-- `indicatorSettings.auraMatch`: All (every aura's When holds) or Any (at
-- least one does). A lone aura ignores it.
I.AURA_MATCH_LABELS = {all="All", any="Any"}
I.AURA_MATCH_ORDER = {"all", "any"}

local function SavedMatch(group)
    local match = I.Settings(group).auraMatch
    return I.AURA_MATCH_LABELS[match] and match or "all"
end

function I.AuraMatch(group)
    return I.IsMultiAura(group) and SavedMatch(group) or nil
end

-- An aura in a list shows its Indicator while active, or while missing.
function I.AuraWantsActive(entry)
    return AuraWhenOf(entry) ~= "missing"
end

-- While Missing: nothing is read. A hidden tracker sized by Blizzard opens a
-- clip window over a CC-drawn display only while the aura is absent
-- (AuraDisplay "presence"). With group tracking it shows while nobody in the
-- group has the aura (one tracker per member).
function I.ShowsWhileMissing(group)
    return I.IsAura(group) and not I.IsMultiAura(group)
        and AuraWhenOf(I.Primary(group)) == "missing" or false
end

-- How the presence trackers combine: the list's Match, "all" for a lone
-- aura While Missing (all of one), nil for a native aura.
function I.PresenceMatch(group)
    if I.IsMultiAura(group) then return SavedMatch(group) end
    if I.ShowsWhileMissing(group) then return "all" end
end

-- Drawn by CC behind a presence tracker: While Missing, or several auras.
-- Nothing live (timer, count, drain) can show.
function I.UsesPresence(group)
    return I.PresenceMatch(group) ~= nil
end

-- The aura draws in its native slot (live timer, count, drain). A While
-- Missing or multi-aura Indicator is drawn by CC like a spell or item
-- Indicator instead.
function I.IsNativeAura(group)
    return I.IsAura(group) and not I.UsesPresence(group)
end

-- Also During Pandemic (a lone aura While Missing): the aura's own native
-- display also shows inside its pandemic window, gated by Blizzard
-- (AuraDisplay "pandemicIndicatorAura"). Saved on the aura entry, the same key a
-- panel entry uses (showWhileAuraPandemic). Never with group tracking (owner
-- ruling 2026-10-04).
function I.AlsoDuringPandemic(group)
    -- Nameplate Reminders keep it per DoT: on while any DoT has it.
    if I.IsNameplate(group) then
        for _, aura in ipairs(I.AuraList(group)) do
            if aura.showWhileAuraPandemic == true then return true end
        end
        return false
    end
    if not I.ShowsWhileMissing(group) then return false end
    local source = I.Primary(group)
    -- Same group rule as the presence tracker it rides (AuraDisplay rebind).
    return source.showWhileAuraPandemic == true and source.auraTrackGroup ~= true
end

-- Nameplate Reminders (Core/NameplateReminders.lua): While Missing DoTs drawn
-- on every qualifying enemy nameplate instead of on screen, one icon per DoT
-- in a row (owner rulings 2026-10-04). Saved on each aura as
-- `auraTrackNameplates`, always beside auraUnitOverride "target", so every
-- unit reader (identity gate, previews, an older build) still sees ordinary
-- target auras and the routing is decided here alone. With several DoTs the
-- aura list is the row, never an All / Any match.
function I.IsNameplate(group)
    if not I.IsAura(group) then return false end
    local source = I.Primary(group)
    return source ~= nil and source.auraTrackNameplates == true and AuraWhenOf(source) == "missing"
        and I.AuraUnit(source) == "target"
end

local function FlagNameplateAura(entry)
    entry.auraTrackNameplates = true
    entry.auraUnitOverride = "target"
    entry.auraTrackGroup, entry.auraTrackPet = nil, nil
    entry.auraUnit = "target"
end

-- One of your debuffs, the only kind a nameplate row takes: a spell aura
-- whose automatic unit (any Tracked On override aside) is Target.
local function IsOwnDebuff(entry)
    if entry.addedAs ~= "aura" or entry.type ~= "spell" then return false end
    local automatic = {}
    for key, value in pairs(entry) do automatic[key] = value end
    automatic.auraUnitOverride = nil
    return Addon:ResolveStandaloneAuraDefaultUnit(automatic) == "target"
end

-- The most DoTs that can run on nameplates at once, across every nameplate
-- Indicator (owner ruling 2026-10-04): each costs its own watcher bank.
I.MAX_NAMEPLATE_DOTS = 5

-- Where a nameplate Indicator sits on the plate: a side of the plate's base
-- frame plus an offset. Kept apart from `signal`, which keeps the on-screen
-- position for a switch back. Created on first read.
-- Corners (owner ruling 2026-10-04) sit above or below the plate, lined up
-- with that edge, and grow inward along it.
I.NAMEPLATE_SIDE_ORDER = {"above", "below", "left", "right",
    "topleft", "topright", "bottomleft", "bottomright", "center"}
I.NAMEPLATE_SIDE_LABELS = {above = "Above", below = "Below", left = "Left", right = "Right",
    topleft = "Top Left", topright = "Top Right", bottomleft = "Bottom Left", bottomright = "Bottom Right",
    center = "Center"}
-- Which way a side's row grows from its first DoT: -1 leftward, 1
-- rightward, nil centered on the anchor.
local NAMEPLATE_GROWTH = {left = -1, topright = -1, bottomright = -1,
    right = 1, topleft = 1, bottomleft = 1}
I.NAMEPLATE_GROWTH = NAMEPLATE_GROWTH
function I.NameplatePlacement(group)
    local settings = I.Settings(group)
    if not settings then return end
    local placement = settings.nameplate
    if type(placement) ~= "table" then
        placement = {}
        settings.nameplate = placement
    end
    if not I.NAMEPLATE_SIDE_LABELS[placement.side] then placement.side = "above" end
    placement.x = tonumber(placement.x) or 0
    placement.y = tonumber(placement.y) or 0
    placement.spacing = tonumber(placement.spacing) or 2
    return placement
end

-- Where DoT `index` of `count` sits along the row, from the row's anchor:
-- centered rows above, below or on the plate; rows that grow outward from
-- the plate's side. Fixed spots: a refreshed DoT leaves its gap (aura state
-- is secret, so the row can't close up).
function I.NameplateSpotOffset(group, index, count)
    local placement = I.NameplatePlacement(group)
    local step = I.DisplaySize(group) + placement.spacing
    local growth = NAMEPLATE_GROWTH[placement.side]
    if growth then return growth * (index - 1) * step end
    return (index - (count + 1) / 2) * step
end

function I.NameplateRowWidth(group)
    local width = I.DisplaySize(group)
    local count = math.max(1, #I.AuraList(group))
    return count * width + (count - 1) * I.NameplatePlacement(group).spacing
end

-- The display's drawn size from saved settings (nothing is measured).
function I.DisplaySize(group)
    local visual = I.NativeSettings(group)
    local geometry = visual and visual.enabled ~= false and Addon:GetIndicatorTextureRenderGeometry(visual)
    if not geometry then return 0, 0 end
    return geometry.boundsWidth or 0, geometry.boundsHeight or 0
end

-- A new nameplate reminder starts beside the ones already on that side of
-- the plate (owner ruling 2026-10-04), then keeps its spot: gaps stay.
-- `others` are the profile's other nameplate Indicators.
function I.PlaceBesideNameplates(group, others)
    local placement = I.NameplatePlacement(group)
    local side = placement.side
    -- How far the other rows on this side reach along their growth: leftward
    -- or rightward from the anchor, to the right for centered ones.
    local growth = NAMEPLATE_GROWTH[side]
    local reach
    for _, other in ipairs(others) do
        local theirs = I.NameplatePlacement(other)
        if theirs.side == side then
            local row = I.NameplateRowWidth(other)
            local edge = growth == -1 and row - theirs.x
                or growth == 1 and theirs.x + row
                or theirs.x + row / 2
            reach = math.max(reach or edge, edge)
        end
    end
    if not reach then placement.x = 0; return end
    if growth == -1 then placement.x = -math.floor(reach + 2 + 0.5)
    elseif growth == 1 then placement.x = math.floor(reach + 2 + 0.5)
    else placement.x = math.floor(reach + 2 + I.NameplateRowWidth(group) / 2 + 0.5) end
end

-- Starts a reminder that just moved onto nameplates beside the profile's
-- other nameplate reminders on that side of the plate.
function I.PlaceNewNameplateReminder(group)
    local others = {}
    for _, other in pairs(Addon.db.profile.groups) do
        if other ~= group and I.IsNameplate(other) then others[#others + 1] = other end
    end
    I.PlaceBesideNameplates(group, others)
end

-- Enemy Nameplates is an Anchor Target (owner ruling 2026-10-04, Layout).
-- Why this Indicator can't move there right now, or nil: every source is a
-- debuff of yours (each becomes a DoT in the row), several show as Icons,
-- and the DoT cap has room. `groupId` is left out of the running count.
function I.NameplateRefusal(group, groupId)
    local auras = I.AuraList(group)
    local sources = #(group.buttons or {})
    if sources == 0 then return "Add one of your debuffs first, such as a DoT." end
    if #auras == 0 then return "Only your debuffs can show on nameplates. This Indicator tracks spells or items." end
    if #auras ~= sources then
        return "Only your debuffs can show on nameplates. Remove this Indicator's other sources first."
    end
    for _, aura in ipairs(auras) do
        if not IsOwnDebuff(aura) then return I.EffectFailureText.indicator_nameplate_debuff end
    end
    if #auras > 1 and I.Settings(group).displayType ~= "icon" then
        return I.EffectFailureText.indicator_nameplate_icon
    end
    local reminders = ST._NameplateReminders
    local running = reminders and reminders.RunningDoTCount(groupId) or 0
    if running + #auras > I.MAX_NAMEPLATE_DOTS then
        return ("Up to %d DoTs can show on nameplates at once. Remove one from another nameplate Indicator first.")
            :format(I.MAX_NAMEPLATE_DOTS)
    end
end

-- Why no DoT can be added to a nameplate Indicator right now, or nil: the
-- config greys its add box with this text (owner ruling 2026-10-05). Any add
-- makes a row of several DoTs, which must be Icons, and the DoT cap needs
-- room (its own DoTs counted from saved data, the others from the last
-- rebind). Change... is never blocked: it keeps the count.
function I.NameplateAddBlock(group, groupId)
    if not I.IsNameplate(group) then return end
    -- Short enough for the add box's single line.
    if I.Settings(group).displayType ~= "icon" then return "Switch to Icon to add DoTs" end
    local reminders = ST._NameplateReminders
    local running = (reminders and reminders.RunningDoTCount(groupId) or 0) + #I.AuraList(group)
    if running >= I.MAX_NAMEPLATE_DOTS then
        return ("Max %d DoTs on nameplates"):format(I.MAX_NAMEPLATE_DOTS)
    end
end

-- The Indicator moves onto Enemy Nameplates: every aura becomes a DoT in the
-- row, on a target override, While Missing. Every move turns Also During
-- Pandemic on where it is unset (a nameplate row saves off as false, so a
-- choice made there survives); the first one also starts beside the other
-- reminders. Returns the effects notice SetAuraWhen gives, if any.
function I.MoveToNameplates(group)
    local firstTime = type(I.Settings(group).nameplate) ~= "table"
    local primary = I.Primary(group)
    local notice
    for _, aura in ipairs(I.AuraList(group)) do
        FlagNameplateAura(aura)
        if aura == primary then notice = I.SetAuraWhen(group, "missing") end
        aura.indicatorStackRule = {compare = "missing"}
        if aura.showWhileAuraPandemic == nil then aura.showWhileAuraPandemic = true end
    end
    if firstTime then I.PlaceNewNameplateReminder(group) end
    -- SetAuraWhen adapts only when its own change moves the family.
    local adapted = I.AdaptEffectsToFamily(group)
    if notice and adapted then return notice .. " " .. adapted end
    return notice or adapted
end

-- The Indicator leaves Enemy Nameplates (another Anchor Target): its DoTs
-- stay, tracked on Target While Missing, and several become a list shown
-- while any is missing. Pandemic choices stay for a move back.
function I.LeaveNameplates(group)
    local auras = I.AuraList(group)
    for _, aura in ipairs(auras) do
        aura.auraTrackNameplates = nil
        aura.auraUnit = Addon:ResolveStandaloneAuraDefaultUnit(aura)
    end
    if #auras > 1 then I.Settings(group).auraMatch = "any" end
    ST._NameplateTargetView.Refresh()
    return I.AdaptEffectsToFamily(group)
end

-- The aura's live display can show (always, or in its pandemic window): the
-- timer, count, drain and pandemic settings apply.
function I.ShowsLiveDisplay(group)
    return I.IsNativeAura(group) or I.AlsoDuringPandemic(group)
end

-- Where an aura entry is tracked: "target", "pet", "group" or "player", by
-- the runtime's own precedence (Addon:GetAuraEntryUnitKind).
function I.AuraUnit(entry)
    return Addon:GetAuraEntryUnitKind(entry)
end

-- Each aura in a list has its own tracker on its own unit; group tracking
-- (one tracker per member) works on a lone aura only. Why `auras` (two or
-- more) can't be tracked together, as an EffectFailureText key, or nil.
-- `arriving` (optional): auras joining a non-nameplate Indicator, which drop
-- their nameplate flag on arrival (I.OnSourceAdded).
local function AuraListRefusal(auras, arriving)
    if #auras < 2 then return end
    for _, aura in ipairs(auras) do
        if I.AuraUnit(aura) == "group" then return "indicator_aura_group" end
    end
    local function OnPlates(aura)
        return aura.auraTrackNameplates == true and not (arriving and arriving[aura])
    end
    local onPlates = OnPlates(auras[1])
    for _, aura in ipairs(auras) do
        if OnPlates(aura) ~= onPlates then return "indicator_aura_nameplate" end
    end
end

-- A saved list that can't be tracked (Tracked On changed after adding)
-- stays hidden: the refusal key, or nil.
function I.AuraListProblem(group)
    return AuraListRefusal(I.AuraList(group))
end

-- Which effect rules apply: native auras run Always only; presence-drawn
-- auras may add Only In Combat (CC draws them, but nothing they would animate
-- on is the aura's own state); spell and item sources also get Animate When.
-- Nameplate reminders are their own family: Pulse, Bounce and Color Shift
-- as AnimationGroups, set per look (owner rulings 2026-10-04): the saved
-- `effects` play While Missing, `pandemic.effects` in the refresh window.
function I.EffectFamily(group)
    if I.IsNameplate(group) then return "nameplate" end
    if I.IsNativeAura(group) then return "aura" end
    return I.UsesPresence(group) and "missing" or "conditions"
end

-- Never shown on its own: every source of a conditions Indicator, and every
-- source of an aura Indicator except the main aura.
function I.IsHiddenSource(group, entry)
    return ST.IsIndicatorGroup(group) and not (I.IsAura(group) and entry == I.Primary(group))
end

-- A source checked by rules: every source of a conditions Indicator, and the
-- extra spell/item sources of an aura Indicator. Its auras have no condition
-- rules; a lone aura's only rule is its When (StackRule).
function I.IsConditionSource(group, entry)
    return I.IsHiddenSource(group, entry) and not I.IsListedAura(group, entry)
end

-- An aura Indicator's stack rule, saved on the aura entry so it leaves with
-- the aura. Blizzard drives a hidden stack bar with the secret count and the
-- display is clipped by its fill (AuraDisplay), so the rule never reads stacks.
-- One rule per Indicator: a slot holds a single application bar.
I.STACK_COUNT_MAX = 99
local STACK_COMPARE_LABELS = {atLeast="At Least %d Stacks", fewer="Fewer Than %d Stacks",
    exactly="Exactly %d Stacks", max="At Max Stacks"}

-- Lowest count each comparison accepts: "Fewer Than 1" could never show.
function I.StackCountMin(compare)
    return compare == "fewer" and 2 or 1
end

-- The aura's maximum stacks from spell data (the stack bars' resolver), or
-- nil when the game reports none. Caps the Stacks slider and drives At Max.
function I.StackMax(group)
    local source = I.IsAura(group) and I.Primary(group)
    return source and Addon:GetAuraStackBarMax(source, true) or nil
end

-- compare, count, max for an aura Indicator with a valid rule; nil otherwise.
-- `max` is the aura's reported max (nil when none), resolved once here so
-- callers never look it up again. The saved count keeps its meaning: only the
-- Stacks slider stops at the max. At Max with no max reported returns a nil
-- count and fails closed (the Indicator stays hidden), like any rule that
-- cannot be checked.
-- The saved comparison alone, without the max lookup (Finder checks).
function I.StackCompare(group)
    if not I.IsAura(group) or I.IsMultiAura(group) then return end
    local source = I.Primary(group)
    local compare = AuraWhenOf(source)
    -- Only stack comparisons: While Active and While Missing are not.
    if not STACK_COMPARE_LABELS[compare] then return nil, source and source.indicatorStackRule end
    return compare, source.indicatorStackRule
end

function I.StackRule(group)
    local compare, rule = I.StackCompare(group)
    if not compare then return end
    local max = I.StackMax(group)
    if compare == "max" then return compare, max, max end
    local count = math.floor(tonumber(rule.count) or 0)
    return compare, math.max(I.StackCountMin(compare), math.min(I.STACK_COUNT_MAX, count)), max
end

function I.StackRuleLabel(compare, count)
    local label = STACK_COMPARE_LABELS[compare]
    return label and label:format(count or 0) or "While Active"
end

-- The main aura row's When as text: While Missing, a stack rule, or While
-- Active (in a list, its own While Active / While Missing).
function I.AuraWhenLabel(group)
    if I.IsMultiAura(group) then return I.AuraEntryWhenLabel(I.Primary(group)) end
    if I.ShowsWhileMissing(group) then return "While Missing" end
    local compare, count = I.StackRule(group)
    return I.StackRuleLabel(compare, count)
end

-- A rule from StackRule that the aura's max settles on its own: "never" when
-- it cannot pass, "always" when it always does, nil otherwise. An aura with
-- no max reported is treated as not stacking (owner ruling 2026-09-30): it
-- has 0 stacks, so At Least, Exactly and At Max never pass and Fewer Than
-- always does. With a max, only a count above it is settled.
function I.StackRuleOutcome(compare, count, max)
    if not compare then return end
    if not max or count > max then return compare == "fewer" and "always" or "never" end
end

-- Preview only: whether a sample stack count passes a rule from StackRule.
function I.StackRulePasses(compare, count, stacks)
    if not compare then return true end
    if not count then return false end
    if compare == "atLeast" or compare == "max" then return stacks >= count end
    if compare == "fewer" then return stacks < count end
    return stacks == count
end

-- Saved slot one owns the display; runtime lists omit unavailable entries.
-- Never substitute the first surviving condition for a missing source.
function I.RuntimeSource(frame, group)
    local source = I.Primary(group)
    if not source then return end
    for _, button in ipairs(frame and frame.buttons or {}) do
        if button.buttonData == source then return button end
    end
end

-- Generic entry actions may remove conditions or the complete source set.
-- A partial removal of the primary would silently promote another condition.
function I.GetRemovalError(group, entries)
    local source = I.Primary(group)
    if not source then return end
    local removing = {}
    for _, entry in ipairs(entries) do removing[entry] = true end
    if not removing[source] then return end
    for _, entry in ipairs(group.buttons) do
        if not removing[entry] then
            return "Change or remove this Indicator's source in Visibility before removing it."
        end
    end
end

I.EffectOrder = {"pulse", "colorShift", "shrinkExpand", "bounce"}
I.EffectFailureText = {
    indicator_effects_legacy = "This older Indicator template does not identify its active effects. Update it from the original panel before applying it.",
    indicator_effects_conditions = "Aura Indicators can't use Animate When or Only In Combat. Set each effect to Always with Only In Combat off first.",
    indicator_effects_missing = "Indicators that show While Missing or check several auras can't use Animate When. Set each effect to Always first.",
    indicator_effects_nameplate = "Nameplate reminders can't use Shrink / Expand. Turn it off first.",
    indicator_aura_group = "Group tracking works with a single aura per Indicator.",
    indicator_aura_nameplate = "A nameplate reminder's sources are all your DoTs on enemy nameplates.",
    indicator_nameplate_debuff = "Nameplate reminders track your debuffs only: no buffs, spells or items.",
    indicator_nameplate_icon = "Several DoTs show as icons. Set Display As to Icon first.",
    indicator_nameplate_cap = ("Up to %d DoTs can show on nameplates at once."):format(I.MAX_NAMEPLATE_DOTS),
    indicator_aura_change = "This Indicator checks several auras, so it can only change to another aura. Remove the other auras first to use a spell or item.",
    indicator_effects_text = "This effect cannot run with the destination's Text Only display. Choose Icon or Texture, or turn off the effect first.",
}

-- Pure reader for validation and snapshots. Before the unified store existed,
-- only the active source family owned effects; the other store was dormant.
function I.ReadEffects(group)
    local settings = I.Settings(group) or {}
    if settings.effectVersion == 1 then return settings.effects or {} end
    if group.templateVersion and settings.tracking == nil then
        return nil, "indicator_effects_legacy"
    end
    if settings.tracking ~= "aura" then return settings.effects or {} end
    local legacy = group.style and group.style.textureIndicators and group.style.textureIndicators.aura or {}
    local aura = Addon.NormalizeTextureIndicatorSection("aura", CopyTable(legacy))
    local key = aura.effectType
    local effects = {}
    for _, effectKey in ipairs(I.EffectOrder) do
        -- The old single selector shared duration/color between choices.
        effects[effectKey] = {enabled = effectKey == key and aura.enabled == true, speed = aura.speed}
        if effectKey == "colorShift" then effects[effectKey].color = CopyTable(aura.color) end
    end
    return effects
end

local function StoreEffects(group, effects)
    local settings = I.Settings(group)
    settings.effects = CopyTable(effects)
    -- Retired: the old aura editor's single-effect choice.
    settings.effectSelection = nil
    settings.effectVersion = 1
    if group.style then group.style.textureIndicators = nil end
    return settings.effects
end
I.SetEffects = StoreEffects

function I.Effects(group)
    local settings = I.Settings(group)
    if not settings then return end
    if settings.effectVersion == 1 then return settings.effects end
    local effects = I.ReadEffects(group)
    if effects then return StoreEffects(group, effects) end
end

-- Empty panels defer capability checks until their first source is known.
-- Display switching still retains dormant effects, as the editor advertises;
-- transfers must not introduce an effect that the destination cannot render.
-- Aura effects run together, but only as Always and never Only In Combat:
-- nothing in the aura slot may start or stop once it is bound.
function I.CheckEffects(effects, tracking, displayType)
    if not tracking then return true end
    for _, key in ipairs(I.EffectOrder) do
        if effects[key] and effects[key].enabled == true then
            if tracking == "nameplate" and key == "shrinkExpand" then
                return false, "indicator_effects_nameplate"
            end
            local conditional = (effects[key].activation or "always") ~= "always"
            if tracking == "aura" and (conditional or effects[key].combatOnly) then
                return false, "indicator_effects_conditions"
            end
            if (tracking == "missing" or tracking == "nameplate") and conditional then
                return false, "indicator_effects_missing"
            end
        end
    end
    local unavailable = (tracking == "aura" or tracking == "nameplate") and "colorShift" or "shrinkExpand"
    if displayType == "text" and effects[unavailable] and effects[unavailable].enabled == true then
        return false, "indicator_effects_text"
    end
    return true
end

-- A nameplate row of several DoTs stays Icon: a copied appearance must be one.
local function NameplateIconRefusal(source, destination, appearance)
    if appearance and I.IsNameplate(destination) and I.IsMultiAura(destination)
        and (I.Settings(source) or {}).displayType ~= "icon" then
        return "indicator_nameplate_icon"
    end
end

function I.CanApplyEffects(source, destination, appearance)
    local iconRefusal = NameplateIconRefusal(source, destination, appearance)
    if iconRefusal then return false, iconRefusal end
    local effects, reason = I.ReadEffects(source)
    if not effects then return false, reason end
    local saved, target = I.Settings(source) or {}, I.Settings(destination) or {}
    return I.CheckEffects(effects, I.Primary(destination) and I.EffectFamily(destination),
        appearance and saved.displayType or target.displayType)
end

-- The effect family `source` gives `group` as its display: an aura draws
-- natively unless it shows While Missing (its own rule, or the rule a staged
-- Change... carries over from the aura it replaces).
local function SourceEffectFamily(group, source)
    if source.addedAs ~= "aura" then return "conditions" end
    -- Another debuff stays on nameplates (CommitSourceReplacement); a staged
    -- replacement doesn't know it yet, so it carries the flag.
    if I.IsNameplate(group) or group._stagedNameplate then return "nameplate" end
    if AuraWhenOf(source) == "missing" or group._stagedAuraWhen == "missing" then
        return "missing"
    end
    return "aura"
end

function I.CheckSourceEffects(group, source)
    local effects, reason = I.ReadEffects(group)
    if not effects then return false, reason end
    return I.CheckEffects(effects, SourceEffectFamily(group, source),
        (I.Settings(group) or {}).displayType)
end

-- The native aura renderer plays every enabled effect together for as long
-- as Blizzard shows the slot: Always, never combat-gated. Color Shift has no
-- artwork to tint on Text Only. A derived description keyed by effect, never
-- a second saved store.
local function CollectNativeEffects(group, skipCombatOnly)
    I.Effects(group)
    local settings = I.Settings(group)
    local store = Addon.NormalizeIndicatorEffectStore(settings)
    local effects = {}
    for _, key in ipairs(I.EffectOrder) do
        local effect = store[key]
        if effect.enabled and not (key == "colorShift" and settings.displayType == "text")
            and not (skipCombatOnly and effect.combatOnly) then
            effects[key] = {speed = effect.speed, color = effect.color and CopyTable(effect.color)}
        end
    end
    return effects
end

function I.NativeEffects(group)
    if not I.IsNativeAura(group) then return end
    return CollectNativeEffects(group)
end

-- The pandemic window's native display plays the While Missing look's
-- enabled effects too, except Only In Combat ones: a native slot can't follow
-- combat, so those stay on the missing look only.
function I.PandemicTwinEffects(group)
    if not I.AlsoDuringPandemic(group) then return end
    return CollectNativeEffects(group, true)
end

-- A nameplate reminder's refresh-window effects: their own store inside
-- `pandemic`, so they copy with Effects (ApplyPresentation copies `pandemic`
-- whole) and stay dormant off nameplates. Same shape as `effects`.
function I.PandemicLookEffectStore(group)
    local settings = I.Settings(group)
    if not settings then return end
    settings.pandemic = settings.pandemic or {}
    return Addon.NormalizeIndicatorEffectStore(settings.pandemic)
end

-- A nameplate reminder's effects for one look, "missing" (the saved
-- `effects`) or "pandemic" (I.PandemicLookEffectStore): the enabled
-- AnimationGroup effects. Never Shrink / Expand (a per-frame script), never
-- Color Shift on Text Only (also a script there). Animate When and Only In
-- Combat don't apply: each look is its own choice, and reminders show only in
-- combat.
function I.NameplateEffects(group, look)
    I.Effects(group)
    local settings = I.Settings(group)
    local store = look == "pandemic" and I.PandemicLookEffectStore(group)
        or Addon.NormalizeIndicatorEffectStore(settings)
    local effects = {}
    for _, key in ipairs(I.EffectOrder) do
        local effect = store[key]
        if effect.enabled and key ~= "shrinkExpand" and not (key == "colorShift" and settings.displayType == "text") then
            effects[key] = {speed = effect.speed, color = effect.color and CopyTable(effect.color)}
        end
    end
    return effects
end

-- Timer behavior that belongs to the Indicator rather than to one display
-- type. It lives in `readouts` because the shared duration formatter reads it
-- there, so display switches carry it over. Low Time is Appearance (the
-- Duration Text gear); the marker sits in the Effects tab's Pandemic section
-- and copies with Effects, beside the pandemic glow.
I.LowTimeKeys = {"durationLowTimeThreshold", "durationLowTimeDecimals", "durationLowTimeColor",
    "durationLowTimeThreshold2", "durationLowTimeColor2"}
I.PandemicMarkerKeys = {"pandemicMarkerMode", "pandemicMarkerText", "pandemicMarkerColorMode", "pandemicMarkerColor"}

local function CopyTimerPolicy(from, to, keys)
    for _, key in ipairs(keys) do
        local value = from and from[key]
        to[key] = type(value) == "table" and CopyTable(value) or value
    end
end

local function NewReadouts(displayType)
    return {
        label = displayType == "text" and "name" or "none", timer = displayType == "text",
        count = "none", customText = "",
        labelAnchor = "TOP", labelX = 0, labelY = 0,
        timerAnchor = "CENTER", timerX = 0, timerY = 0,
        countAnchor = "BOTTOM", countX = 0, countY = 0,
        durationFormat = "clock",
    }
end

function I.Initialize(group)
    if not ST.IsIndicatorGroup(group) then return end
    local settings = group.indicatorSettings
    if type(settings) ~= "table" then settings = {}; group.indicatorSettings = settings end
    settings.version = settings.version or 1
    settings.tracking = settings.tracking or "conditions"
    settings.displayType = settings.displayType or "icon"
    settings.signal = settings.signal or {
        blendMode = "BLEND", point = "CENTER", relativePoint = "CENTER",
        relativeTo = "UIParent", x = 0, y = 0, locationType = "CENTER",
    }
    settings.icon = settings.icon or {
        maintainAspectRatio = true, buttonSize = 36, iconWidth = 36, iconHeight = 36,
        iconZoom = 0, borderSize = 1, borderColor = {0, 0, 0, 1},
        iconTintColor = {1, 1, 1, 1}, backgroundColor = {0, 0, 0, 0.5},
    }
    settings.text = settings.text or {
        value = "", textFont = "Friz Quadrata TT", textFontSize = 20,
        textFontOutline = "OUTLINE", textFontColor = {1, 1, 1, 1},
        textBgColor = {0, 0, 0, 0}, width = 180, height = 48,
    }
    settings.readouts = settings.readouts or NewReadouts()
    settings.progress = settings.progress or { enabled = false, direction = "down", dimAlpha = 0.35 }
    settings.effects = settings.effects or {}
    -- Pandemic effect for aura Indicators: the panel pandemicGlow* key family
    -- plus its explicit-true pandemicEffectEnabled. Empty means off.
    settings.pandemic = settings.pandemic or {}
    -- Text displays gained a Pandemic effect (a recolor) in 2026-10. An "on"
    -- stored from an earlier Icon or Texture look was invisible on Text, so
    -- it is turned off once per Indicator. The marker lives in the data, not
    -- a profile sentinel: imports clear sentinels and re-run passes, which
    -- would turn off an effect chosen since.
    if not settings.pandemic.textRecolorReviewed then
        if settings.displayType == "text" then settings.pandemic.pandemicEffectEnabled = nil end
        settings.pandemic.textRecolorReviewed = true
    end
    return settings
end

-- The Pandemic effect is on: the Icon glow, the Texture and Text recolor.
function I.PandemicEffectOn(group)
    local settings = I.Settings(group)
    local pandemic = settings and settings.pandemic
    return pandemic ~= nil and pandemic.pandemicEffectEnabled == true
end

-- A Text display's Pandemic effect recolors its whole text, the timer and
-- its marker included (I.PandemicTimerStyle).
function I.PandemicRecolorsText(group)
    local settings = I.Settings(group)
    return settings ~= nil and settings.displayType == "text" and I.PandemicEffectOn(group)
end

-- The effect has something to show: Icon and Texture artwork always, Text
-- only its label or timer (the stack count is Blizzard's own text).
function I.PandemicEffectApplies(group)
    local settings = I.Settings(group)
    if not settings then return false end
    return settings.displayType ~= "text" or settings.readouts.label ~= "none" or settings.readouts.timer == true
end

-- The Pandemic marker keys live in `readouts` beside the timer's Duration
-- Format and Low Time keys, so the shared aura formatter composes all three
-- from one table. Unlike a panel, a missing mode means off here: Indicators
-- predate the marker and must not gain one unasked. Aura state never enters.
function I.PandemicMarkerOn(group)
    local settings = I.Settings(group)
    local readouts = settings and settings.readouts
    local mode = readouts and readouts.pandemicMarkerMode
    return I.IsAura(group) and readouts.timer == true and mode ~= nil and mode ~= "off" or false
end

-- The primary source follows panel enablement. Preserve an old disabled source
-- as a disabled panel, so removing the redundant source toggle cannot trap it.
function I.NormalizeSourceEnablement(group)
    local source = I.Primary(group)
    if source and source.enabled == false then
        group.enabled = false
        source.enabled = true
    end
end

local function NormalizeCountReadouts(group)
    local settings, source = I.Settings(group), I.Primary(group)
    if not settings or not source then return end
    local count = I.IsAura(group) and "stacks" or source.type == "spell" and "charges" or "item"
    local function adaptReadouts(readouts)
        if readouts and readouts.count and readouts.count ~= "none" then readouts.count = count end
    end
    adaptReadouts(settings.readouts)
    for _, readouts in pairs(settings.readoutsByDisplay or {}) do adaptReadouts(readouts) end
end

local function IndexOf(group, entry)
    for i, button in ipairs(group.buttons or {}) do if button == entry then return i end end
end

local EFFECT_LABELS = {pulse = "Pulse", colorShift = "Color Shift", shrinkExpand = "Shrink / Expand", bounce = "Bounce"}

local function ListNames(names)
    if #names < 2 then return names[1] end
    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

-- What each effect family can't run, for adapting effects when the display
-- source or the aura's When changes (adapt rather than refuse). Native auras:
-- no Animate When or Only In Combat, and Text Only has no Color Shift. While
-- Missing: no Animate When (it would follow the aura entry's own spell
-- state), and Text Only can't Shrink / Expand. Spell and item: Text Only
-- can't Shrink / Expand.
local FAMILY_LIMITS = {
    aura = {rules = "auras can't use Animate When or Only In Combat", dropCombat = true,
        textOff = "colorShift", textWhy = "Text Only auras can't use it"},
    missing = {rules = "While Missing and several auras can't use Animate When",
        textOff = "shrinkExpand", textWhy = "Text Only can't use it here"},
    conditions = {textOff = "shrinkExpand", textWhy = "Text Only spell and item Indicators can't use it"},
    nameplate = {rules = "nameplate reminders can't use Animate When",
        never = "shrinkExpand", neverWhy = "nameplate reminders can't use it",
        textOff = "colorShift", textWhy = "Text Only nameplate reminders can't use it"},
}

-- Adapts the enabled effects to `family` and adds each change's chat note to
-- `notes`. Disabled effects keep their saved rules; for While Missing the
-- store drops Animate When whenever it is read (I.NormalizeEffectsForFamily),
-- and native auras clear theirs when an effect is enabled (Effects tab).
local function AdaptEffects(settings, family, notes)
    local limits = FAMILY_LIMITS[family]
    local effects = settings.effects or {}
    local converted, off, never = {}, {}, {}
    for _, key in ipairs(I.EffectOrder) do
        local effect = effects[key]
        if effect and effect.enabled == true then
            if key == limits.never then
                effect.enabled = false
                never[#never + 1] = EFFECT_LABELS[key]
            elseif key == limits.textOff and settings.displayType == "text" then
                effect.enabled = false
                off[#off + 1] = EFFECT_LABELS[key]
            elseif limits.rules and ((effect.activation or "always") ~= "always"
                or limits.dropCombat and effect.combatOnly) then
                effect.activation = nil
                if limits.dropCombat then effect.combatOnly = nil end
                converted[#converted + 1] = EFFECT_LABELS[key]
            end
        end
    end
    if #converted > 0 then
        notes[#notes + 1] = ListNames(converted) .. (#converted > 1 and " now run" or " now runs")
            .. " while the Indicator is shown (" .. limits.rules .. ")."
    end
    if #never > 0 then notes[#notes + 1] = ListNames(never) .. " is off (" .. limits.neverWhy .. ")." end
    if #off > 0 then notes[#notes + 1] = ListNames(off) .. " is off (" .. limits.textWhy .. ")." end
end

-- The one read-time rule for While Missing: Animate When never applies, so a
-- saved choice (from a spell past, a copy, or any enable path) is dropped
-- whenever the store is read for the runtime or the config.
function I.NormalizeEffectsForFamily(group, store)
    if not (store and I.UsesPresence(group)) then return store end
    for _, key in ipairs(I.EffectOrder) do
        local effect = store[key]
        if type(effect) == "table" then effect.activation = nil end
    end
    return store
end

local function NoticeText(notes)
    return #notes > 0 and table.concat(notes, " ") or nil
end

-- Adapts the enabled effects to the family `group` has now; the notice, or
-- nil. For moves on and off nameplates, which change the family through the
-- aura flags rather than through When.
function I.AdaptEffectsToFamily(group)
    local settings = I.Settings(group)
    if not settings or not I.Primary(group) then return end
    I.Effects(group)
    local notes = {}
    AdaptEffects(settings, I.EffectFamily(group), notes)
    return NoticeText(notes)
end

-- Keeps a list's rules valid for how many auras it has. Growing to two
-- starts Match on All and drops a stack rule (it needs a single aura); each
-- aura keeps its own While Active / While Missing. Shrinking to one clears
-- Match, and the remaining aura keeps its When.
local function SyncAuraList(group, notes)
    local settings = I.Settings(group)
    local list = I.AuraList(group)
    if #list >= 2 then
        if not I.AURA_MATCH_LABELS[settings.auraMatch] then settings.auraMatch = "all" end
        for _, aura in ipairs(list) do
            if STACK_COMPARE_LABELS[AuraWhenOf(aura)] then
                notes[#notes + 1] = (aura.name or tostring(aura.id))
                    .. "'s stack rule was removed (it needs a single aura)."
                aura.indicatorStackRule = nil
            end
        end
    else
        settings.auraMatch = nil
    end
end

-- Runs `change` (any edit of an Indicator's sources), then syncs the aura
-- list and adapts the effects to the family the Indicator ends up in. Adds
-- chat notes to `notes`. A non-Indicator just runs `change`.
local function ReshapeAuraList(group, notes, change)
    local indicator = ST.IsIndicatorGroup(group) and I.Settings(group)
    local before = indicator and I.Primary(group) and I.EffectFamily(group)
    change()
    if not indicator then return end
    -- Emptied: forget the nameplate spot, so the next move onto Enemy
    -- Nameplates is a first move again (I.MoveToNameplates).
    if not I.Primary(group) then indicator.nameplate = nil end
    SyncAuraList(group, notes)
    local after = I.Primary(group) and I.EffectFamily(group)
    if before and after and after ~= before then AdaptEffects(I.Settings(group), after, notes) end
end

-- Generic entry removal (delete, a move or drag to another panel) runs its
-- removal through here so an Indicator's list and effects follow. Returns an
-- optional chat line.
function I.RemoveSources(group, remove)
    local notes = {}
    ReshapeAuraList(group, notes, remove)
    return NoticeText(notes)
end

-- An aura joining a spell/item Indicator becomes what it shows: it takes slot
-- one, and every other row stays with its rules (older aura-added rows too:
-- they are rule rows, and only the main source owns an aura slot).
local function JoinAura(group, entry)
    local buttons = group.buttons
    table.remove(buttons, IndexOf(group, entry))
    -- The old main source stays checked with its rules. Saved source
    -- visibility named its own rules as the display, so it goes.
    if buttons[1] then buttons[1].enabled = true end
    table.insert(buttons, 1, entry)
    entry.enabled = true
    entry.indicatorAuraListed = nil
    I.Settings(group).sourceVisibility = nil
end

-- Returns true plus an optional chat line for the caller to print, or false
-- plus a failure reason.
function I.OnSourceAdded(group, entry)
    local indicator = ST.IsIndicatorGroup(group)
    -- A source that becomes the display (an aura arriving into an Indicator
    -- without one, or the first source, however it gets there: added, moved,
    -- or Change...) adapts the effects to what it can run instead of refusing.
    local auraArrives = indicator and entry.addedAs == "aura" and not I.IsAura(group)
    local firstSource = indicator and (not I.Primary(group) or I.Primary(group) == entry)
    -- Only a nameplate Indicator keeps a DoT on nameplates: one moved or
    -- dragged anywhere else stays a Target While Missing aura, as leaving by
    -- Anchor Target does (I.LeaveNameplates). An Indicator it now heads was
    -- not on nameplates before it arrived.
    if entry.auraTrackNameplates == true and (firstSource or auraArrives or not I.IsNameplate(group)) then
        entry.auraTrackNameplates = nil
        entry.auraUnit = Addon:ResolveStandaloneAuraDefaultUnit(entry)
    end
    if firstSource then
        local effects, reason = I.ReadEffects(group)
        if not effects then return false, reason end
    end
    local settings = I.Initialize(group)
    if not settings then return true end
    I.Effects(group) -- Capture the previous family before tracking changes.
    if entry.enabled == nil then entry.enabled = true end
    -- A DoT joining a nameplate reminder joins the row: on nameplates, While
    -- Missing (set below), Also During Pandemic on by default.
    if indicator and not firstSource and entry.addedAs == "aura" and I.IsNameplate(group) then
        FlagNameplateAura(entry)
        if entry.showWhileAuraPandemic == nil then entry.showWhileAuraPandemic = true end
    end
    local notes = {}
    -- An aura that shows While Missing (its own rule, or one a Change...
    -- carries over) adapts to the While Missing family instead.
    if auraArrives or firstSource then
        AdaptEffects(settings, SourceEffectFamily(group, entry), notes)
    end
    -- Another aura joins the list: no spell rules of its own; its When
    -- restarts on the main aura's side and Match combines them.
    if indicator and entry.addedAs == "aura" and I.IsAura(group) and I.Primary(group) ~= entry then
        -- Unflagged first, so the reshape sees the list it is growing.
        entry.indicatorAuraListed = nil
        ReshapeAuraList(group, notes, function()
            entry.indicatorAuraListed = true
            -- It starts with the main aura's side: a missing-aura reminder
            -- most likely wants another one.
            entry.indicatorStackRule = AuraWhenOf(I.Primary(group)) == "missing"
                and {compare = "missing"} or nil
            entry.enabled = true
        end)
    end
    -- Checklist order never matters to the user: an aura added after spell or
    -- item sources still becomes the display.
    if auraArrives and (IndexOf(group, entry) or 1) > 1 then
        JoinAura(group, entry)
    end
    local notice = NoticeText(notes)
    if I.Primary(group) == entry then
        I.NormalizeSourceEnablement(group)
        settings.tracking = entry.addedAs == "aura" and "aura" or "conditions"
        if settings.tracking == "aura" then
            entry.textureAuraDisplayEnabled = true
        end
        NormalizeCountReadouts(group)
    end
    if I.IsConditionSource(group, entry) and entry.triggerConditions == nil then
        if entry.triggerCondition then
            -- Moving a source preserves its existing rule, including an
            -- unsupported rule that must stay fail-closed until edited.
            entry.triggerConditions = {{key = entry.triggerCondition,
                expected = entry.triggerExpected, state = entry.triggerState}}
        else
            entry.triggerConditions = {{key = "cooldownActive", expected = false}}
            entry.triggerCondition, entry.triggerExpected = "cooldownActive", false
        end
    end
    return true, notice
end

local function SourceIcon(source)
    if source.manualIcon then return source.manualIcon end
    if source.type == "spell" then return C_Spell.GetSpellTexture(source.id) end
    if Addon.ResolveEffectiveItem then
        local item = Addon.ResolveEffectiveItem(source, false)
        return item and item.icon
    end
end

function I.IconSettings(group)
    local settings = I.Settings(group)
    if not settings then return end
    local icon = Addon.NormalizeIndicatorIconSettings(CopyTable(settings.icon))
    local source = I.Primary(group)
    if not icon.manualIcon and source then icon.manualIcon = SourceIcon(source) end
    return icon
end

-- A nameplate row's icon for one DoT: each spot shows its own spell (the
-- aura's own Override Icon first), since one chosen icon would make every
-- spot identical. A lone DoT keeps the Indicator's chosen icon.
function I.NameplateIconSettings(group, aura)
    local icon = I.IconSettings(group)
    if icon and aura and I.IsMultiAura(group) then icon.manualIcon = SourceIcon(aura) end
    return icon
end

-- Just the icon an Icon display draws (a valid chosen icon, else the main
-- source's), without copying the icon settings: the preview asks per tick.
function I.ArtworkIcon(group)
    local settings = I.Settings(group)
    if not settings then return end
    local chosen = settings.icon and settings.icon.manualIcon
    if chosen and Addon.IsValidIndicatorIconTexture(chosen) then return chosen end
    local source = I.Primary(group)
    return source and SourceIcon(source)
end

-- A render description only. Saved placement always belongs to signal.
function I.NativeSettings(group, resolvedIcon)
    local settings = I.Settings(group)
    if not settings then return end
    if settings.displayType == "texture" then
        return Addon:GetIndicatorTextureSettings(group, true)
    end
    local visual = { enabled = true, sourceType = "file", sourceValue = "Interface\\Buttons\\WHITE8x8",
        blendMode = "BLEND", locationType = "CENTER", color = {1, 1, 1, 1} }
    if settings.displayType == "icon" then
        local icon = resolvedIcon or I.IconSettings(group)
        visual.sourceValue = icon.manualIcon
        visual.width, visual.height = Addon.GetIndicatorIconDimensions(icon)
        visual.enabled = icon.manualIcon ~= nil
    else
        visual.width, visual.height = settings.text.width or 180, settings.text.height or 48
        visual.color = {1, 1, 1, 0}
    end
    return visual
end

-- Each readout keeps its own font in `text`, which every display type shares
-- (positions stay per display in `readouts`). A field it has never set reads
-- the shared text font every readout used before, so older Indicators keep
-- their look.
local DEFAULT_READOUT_COLOR = {1, 1, 1, 1}
function I.ReadoutFont(settings, key)
    local text = settings.text
    return text[key .. "Font"] or text.textFont or "Friz Quadrata TT",
        text[key .. "FontSize"] or text.textFontSize or 20,
        text[key .. "FontOutline"] or text.textFontOutline or "OUTLINE",
        text[key .. "FontColor"] or text.textFontColor or DEFAULT_READOUT_COLOR
end

function I.Label(group)
    local settings = I.Settings(group)
    local readouts = settings and settings.readouts
    if not readouts then return "" end
    if readouts.label == "custom" then return readouts.customText or settings.text.value or "" end
    if readouts.label == "name" then
        local source = I.Primary(group)
        return source and source.name or ""
    end
    return ""
end

function I.SetDisplayType(group, displayType)
    local settings = I.Initialize(group)
    if not settings or (displayType ~= "texture" and displayType ~= "icon" and displayType ~= "text") then return end
    if settings.displayType == displayType then return end
    local previous = settings.readouts
    settings.readoutsByDisplay = settings.readoutsByDisplay or {}
    settings.readoutsByDisplay[settings.displayType] = CopyTable(previous)
    settings.readouts = CopyTable(settings.readoutsByDisplay[displayType] or NewReadouts(displayType))
    CopyTimerPolicy(previous, settings.readouts, I.LowTimeKeys)
    CopyTimerPolicy(previous, settings.readouts, I.PandemicMarkerKeys)
    settings.displayType = displayType
end

I.SameAuraText = "This Indicator already checks that aura there. Change its Tracked On first to check it on another unit."
I.SameAuraUnitText = "This Indicator already checks that aura on that unit."

-- One aura's When inside a list, as text and as a saved choice.
function I.AuraEntryWhenLabel(entry)
    return I.AuraWantsActive(entry) and "While Active" or "While Missing"
end

function I.SetAuraEntryWhen(group, entry, value)
    if not (I.IsMultiAura(group) and I.IsListedAura(group, entry)) then return end
    entry.indicatorStackRule = value == "missing" and {compare = "missing"} or nil
end

-- Any's window chains read every earlier aura, so the auras on units that
-- can close the identity gate go last: yours, then your pet's, then your
-- target's (list order otherwise). Returns a new list of `auras` ({unit}).
local ANY_UNIT_ORDER = { player = 1, pet = 2, target = 3 }
function I.OrderForAny(auras)
    local ordered, position = {}, {}
    for index, aura in ipairs(auras) do ordered[index], position[aura] = aura, index end
    table.sort(ordered, function(a, b)
        local rankA, rankB = ANY_UNIT_ORDER[a.unit] or 4, ANY_UNIT_ORDER[b.unit] or 4
        if rankA ~= rankB then return rankA < rankB end
        return position[a] < position[b]
    end)
    return ordered
end

-- The same aura on the same unit: a list never checks it twice, but may check
-- it on two units (you and your pet).
function I.SameAura(a, b)
    return SameSource(a, b) and I.AuraUnit(a) == I.AuraUnit(b)
end

-- Auras can arrive at any time: the first becomes the display
-- (OnSourceAdded), later ones join its list, each on its own unit, never
-- twice on one unit and never group-tracked. Spell and item sources are checked by their
-- rules.
function I.AddRestriction(group, entry)
    if not ST.IsIndicatorGroup(group) then return end
    local entries = entry and (entry[1] and entry or {entry}) or {}
    -- A nameplate reminder's sources are DoTs, each its own icon in the row.
    if #entries > 0 and I.IsNameplate(group) then
        local list = I.AuraList(group)
        for _, source in ipairs(entries) do
            if not IsOwnDebuff(source) then return I.EffectFailureText.indicator_nameplate_debuff end
            for _, aura in ipairs(list) do
                if aura ~= source and I.SameAura(aura, source) then return I.SameAuraUnitText end
            end
        end
        if I.Settings(group).displayType ~= "icon" then return I.EffectFailureText.indicator_nameplate_icon end
        -- A DoT moving over from another nameplate Indicator is already counted.
        local incoming = 0
        for _, source in ipairs(entries) do
            if source.auraTrackNameplates ~= true then incoming = incoming + 1 end
        end
        local reminders = ST._NameplateReminders
        if reminders and reminders.RunningDoTCount() + incoming > I.MAX_NAMEPLATE_DOTS then
            return I.EffectFailureText.indicator_nameplate_cap
        end
        return
    end
    local auras, incoming = I.AuraList(group), false
    local arriving = {}
    for _, source in ipairs(entries) do
        if source.addedAs == "aura" then
            for _, aura in ipairs(auras) do
                if aura ~= source and I.SameAura(aura, source) then return I.SameAuraText end
            end
            auras[#auras + 1] = source
            arriving[source] = true
            incoming = true
        end
    end
    local refusal = incoming and AuraListRefusal(auras, arriving)
    if refusal then return I.EffectFailureText[refusal] end
    if I.Primary(group) then return end
    -- The first source adapts the effects to what it can run (OnSourceAdded),
    -- so they only need to be readable.
    local effects, reason = I.ReadEffects(group)
    if not effects then return I.EffectFailureText[reason] end
end

I.ConditionKeys = {cooldownActive=true, procActive=true, rangeActive=true, usable=true,
    chargesRecharging=true, chargeState=true, countTextActive=true, countState=true}

local function RuntimeButtons(frame)
    local runtime = {}
    for _, button in ipairs(frame and frame.buttons or {}) do runtime[button.buttonData] = button end
    return runtime
end

-- Every rule on every checked source from slot `first` on must be true. Fails
-- closed: a source missing at runtime, a rule this client cannot evaluate, or
-- a secret or unknown reading never matches. Listed auras have no rules
-- (ExtraSourcesMatch checks that they are available).
local function RulesPass(runtime, group, first)
    local entries = group.buttons or {}
    for index = first, #entries do
        local entry = entries[index]
        if entry.enabled ~= false and not I.IsListedAura(group, entry) then
            if not runtime[entry] then return false end
            for _, clause in ipairs(entry.triggerConditions or {}) do
                if clause.unavailable or not I.ConditionKeys[clause.key] then return false end
                local actual = ST._AT.EvaluateTriggerRowCondition(runtime[entry], clause.key, true)
                if issecretvalue(actual) or actual == nil then return false end
                local expected = clause.state
                if expected == nil then expected = clause.expected ~= false end
                if actual ~= expected then return false end
            end
        end
    end
    return true
end

function I.Match(frame, group)
    local settings = I.Settings(group)
    if not settings or I.IsAura(group) then return false end
    local primary = I.Primary(group)
    if not primary then return false end
    local runtime = RuntimeButtons(frame)
    if not runtime[primary] then return false end
    if settings.sourceVisibility and runtime[primary]._rawVisibilityHidden then return false end
    if not RulesPass(runtime, group, 1) then return false end
    -- Empty rules deliberately mean Always, provided the source is available.
    return primary.enabled ~= false
end

-- An aura Indicator's extra spell/item sources (its other auras are the
-- tracker's, never rules). With no extras there is nothing to check (and
-- nothing to pay).
function I.ExtraSourcesMatch(frame, group)
    if not I.IsAura(group) or not group.buttons then return true end
    -- Listed auras have no rules but, like any checked source, must be
    -- available (their own load rules): every one needs a runtime button.
    -- Counted in one pass, so a list without spell or item sources allocates
    -- nothing per update.
    local extras, listed = false, 0
    for index = 2, #group.buttons do
        local entry = group.buttons[index]
        if not I.IsListedAura(group, entry) then
            extras = true
        elseif entry.enabled ~= false then
            listed = listed + 1
        end
    end
    if listed > 0 then
        for _, button in ipairs(frame and frame.buttons or {}) do
            local entry = button.buttonData
            if entry ~= I.Primary(group) and entry.enabled ~= false and I.IsListedAura(group, entry) then
                listed = listed - 1
            end
        end
        if listed > 0 then return false end
    end
    return not extras or RulesPass(RuntimeButtons(frame), group, 2)
end

function I.ClearSource(group)
    local settings = I.Initialize(group)
    I.Effects(group)
    group.buttons = {}
    settings.tracking = "conditions"
    -- A later list starts on All, not on this one's Match.
    settings.auraMatch = nil
    -- Nor does a later move onto nameplates start from this one's spot.
    settings.nameplate = nil
end

-- A condition source that could take over slot one. A migrated Trigger row
-- added as an aura stays a condition; an aura that joins removes it.
local function CanTakeOver(group, entry)
    return entry ~= I.Primary(group) and entry.addedAs ~= "aura"
end

-- Make Main. An aura Indicator always displays its aura, so its extra
-- sources are never offered; they take over only when the aura is removed.
function I.CanBeMainSource(group, entry)
    return CanTakeOver(group, entry) and not I.IsAura(group)
end

-- The source that takes over when the main source is removed: the next
-- aura in the list first, so the Indicator stays an aura Indicator.
function I.NextMainSource(group)
    local list = I.AuraList(group)
    if list[2] then return list[2] end
    for i = 2, #(group.buttons or {}) do
        if CanTakeOver(group, group.buttons[i]) then return group.buttons[i] end
    end
end

-- Tracking follows the main source. Capture the effects of the previous
-- family before it changes, then adapt the count readouts to the new one.
local function SetTracking(group, tracking)
    local settings = I.Settings(group)
    if settings.tracking ~= tracking then
        I.Effects(group)
        settings.tracking = tracking
    end
    NormalizeCountReadouts(group)
end

-- The chosen condition source takes slot one with its own rules. The main
-- source is always checked, so it is turned on. Leaving an aura makes this a
-- spell/item Indicator.
-- Returns true plus an optional chat line, or false plus a failure reason.
local function Promote(group, entry, index)
    -- Leaving an aura: adapt the effects to the spell or item, as an arriving
    -- source does, rather than refusing the removal.
    local notes = {}
    if I.IsAura(group) then AdaptEffects(I.Settings(group), "conditions", notes) end
    local allowed, reason = I.CheckSourceEffects(group, entry)
    if not allowed then return false, reason end
    local buttons = group.buttons
    table.remove(buttons, index)
    table.insert(buttons, 1, entry)
    entry.enabled = true
    -- Saved source visibility named the old main source's own rules.
    I.Settings(group).sourceVisibility = nil
    SetTracking(group, "conditions")
    return true, NoticeText(notes)
end

-- Config's Make Main only; generic entry removal still refuses to promote
-- (GetRemovalError).
function I.PromoteSource(group, entry)
    local index = IndexOf(group, entry)
    if not index or not I.CanBeMainSource(group, entry) then return false end
    return Promote(group, entry, index)
end

-- Another aura in the list takes slot one: its icon and name show on the
-- display. The list, its Match and every aura's When are unchanged.
function I.PromoteAura(group, entry)
    local index = IndexOf(group, entry)
    if not index or index == 1 or not I.IsListedAura(group, entry) then return false end
    local old = group.buttons[1]
    table.remove(group.buttons, index)
    table.insert(group.buttons, 1, entry)
    entry.indicatorAuraListed = nil
    old.indicatorAuraListed = true
    return true
end

-- The list's Match. The list is presence-drawn either way, so effects never
-- change family here.
function I.SetAuraMatch(group, value)
    if not (I.IsMultiAura(group) and I.AURA_MATCH_LABELS[value]) then return end
    I.Settings(group).auraMatch = value
end

-- The aura row's When: "active", "missing", or a stack comparison (with
-- `count`). Moving between native drawing and While Missing adapts effects
-- the way a source change does. Returns an optional chat line.
function I.SetAuraWhen(group, value, count)
    local source = I.IsAura(group) and I.Primary(group)
    if not source then return end
    local before = I.EffectFamily(group)
    I.Effects(group)
    -- Also During Pandemic belongs to While Missing: another choice clears it,
    -- so a later While Missing never brings it back unseen.
    if value ~= "missing" then source.showWhileAuraPandemic = nil end
    if value == "active" then
        source.indicatorStackRule = nil
    elseif value == "missing" then
        source.indicatorStackRule = {compare = "missing"}
    else
        source.indicatorStackRule = {compare = value, count = count}
    end
    local notes = {}
    local after = I.EffectFamily(group)
    if after ~= before then AdaptEffects(I.Settings(group), after, notes) end
    return NoticeText(notes)
end

-- The aura row's When as a choice key: "missing", a valid stack comparison,
-- or "active" (also for anything unrecognised). nil when there is no aura.
function I.AuraWhen(group)
    if not I.IsAura(group) then return nil end
    if I.ShowsWhileMissing(group) then return "missing" end
    return I.StackCompare(group) or "active"
end

-- Remove one source. Removing the main source hands slot one to the next
-- source that can take it; with none, the Indicator is cleared and keeps its
-- look. A source that is no longer in the Indicator removes nothing. Returns
-- removed, a failure reason, and an optional chat line.
function I.RemoveSource(group, entry)
    local buttons = group.buttons or {}
    local index = IndexOf(group, entry)
    if not index then return false end
    local notice
    -- An aura leaving a list: the next aura takes over the display; a list
    -- of one drops Match and the aura keeps its own When.
    if I.IsListedAura(group, entry) and I.IsMultiAura(group) then
        local notes = {}
        local nextAura = index == 1 and I.AuraList(group)[2] or nil
        ReshapeAuraList(group, notes, function()
            if nextAura then
                table.remove(buttons, IndexOf(group, nextAura))
                nextAura.indicatorAuraListed = nil
                buttons[1] = nextAura
            else
                table.remove(buttons, index)
            end
        end)
        return true, nil, NoticeText(notes)
    end
    if index == 1 then
        local nextSource = I.NextMainSource(group)
        if not nextSource then I.ClearSource(group); return true end
        local promoted, detail = Promote(group, nextSource, IndexOf(group, nextSource))
        if not promoted then return false, detail end
        notice, index = detail, 2
    end
    table.remove(buttons, index)
    return true, nil, notice
end

-- Build a replacement off to the side. Failed validation must leave the
-- current source and its conditions intact until the add actually succeeds.
function I.StageSourceReplacement(group, expectedSource)
    if not ST.IsIndicatorGroup(group) or I.Primary(group) ~= expectedSource then return end
    local candidate = {}
    for key, value in pairs(group) do candidate[key] = value end
    candidate.buttons = {}
    candidate.indicatorSettings = CopyTable(I.Settings(group))
    candidate.style = group.style and CopyTable(group.style)
    StoreEffects(candidate, (I.ReadEffects(group)))
    candidate.indicatorSettings.tracking = "conditions"
    -- Transient, never saved: a replacement aura inherits While Missing
    -- (CommitSourceReplacement), so its arrival must not adapt the effects.
    -- A list stays presence-drawn too, so it adapts like While Missing.
    candidate._stagedAuraWhen = I.UsesPresence(group) and "missing" or nil
    candidate._stagedNameplate = I.IsNameplate(group) or nil
    return candidate
end

-- Returns true plus an optional chat line, or false plus a failure reason.
function I.CommitSourceReplacement(group, candidate)
    local newSource = I.Primary(candidate)
    -- A nameplate Indicator changes only to another debuff of yours, which
    -- stays on nameplates (before the list check, which keeps a row
    -- all-nameplate). Leaving is Layout > Anchor Target's job.
    if I.IsNameplate(group) then
        if not IsOwnDebuff(newSource) then return false, "indicator_nameplate_debuff" end
        FlagNameplateAura(newSource)
    end
    local allowed, reason = I.CheckSourceEffects(candidate, newSource)
    if not allowed then return false, reason end
    -- Only the main source changes. The other sources keep their rules, unless
    -- one is the new source (it starts fresh as the main source instead).
    -- Older aura-added rows are rule rows; listed auras stay in the list.
    -- A list's other auras need an aura on their unit to stay with.
    local others = I.AuraList(group)
    table.remove(others, 1)
    local listed
    if #others > 0 then
        if not I.IsAura(candidate) then return false, "indicator_aura_change" end
        local auras = {newSource}
        for _, aura in ipairs(others) do
            if I.SameAura(aura, newSource) then listed = aura else auras[#auras + 1] = aura end
        end
        local refusal = AuraListRefusal(auras)
        if refusal then return false, refusal end
    end
    if listed then
        -- Already in the list: the aura keeps its own When there.
        newSource.indicatorStackRule = listed.indicatorStackRule and CopyTable(listed.indicatorStackRule)
        newSource.showWhileAuraPandemic = listed.showWhileAuraPandemic
    else
        -- Change... swaps the aura, not the rule: a stack rule moves to the new aura.
        local oldRule = I.IsAura(group) and I.Primary(group).indicatorStackRule
        if oldRule and I.IsAura(candidate) and newSource.indicatorStackRule == nil then
            newSource.indicatorStackRule = CopyTable(oldRule)
            -- Its Also During Pandemic goes with While Missing.
            if I.Primary(group).showWhileAuraPandemic == true and newSource.showWhileAuraPandemic == nil then
                newSource.showWhileAuraPandemic = true
            end
        end
    end
    for i = 2, #(group.buttons or {}) do
        local entry = group.buttons[i]
        if entry ~= listed and not (SameSource(entry, newSource) and not I.IsListedAura(group, entry)) then
            candidate.buttons[#candidate.buttons + 1] = entry
        end
    end
    local notes = {}
    ReshapeAuraList(group, notes, function()
        group.buttons = candidate.buttons
        local settings = I.Settings(group)
        settings.tracking = I.Settings(candidate).tracking
        StoreEffects(group, I.Effects(candidate))
    end)
    NormalizeCountReadouts(group)
    return true, NoticeText(notes)
end

local SIGNAL_APPEARANCE = {"sourceType","sourceValue","mediaType","label","scale","alpha","blendMode",
    "rotation","stretchX","stretchY","color","locationType","pairSpacing","width","height"}
local PRESENTATION_FIELDS = {"displayType","icon","text","readouts","readoutsByDisplay","progress"}

function I.CapturePresentation(group)
    local settings = I.Settings(group)
    if not settings then return end
    local copy = {signal={}}
    for _, key in ipairs(PRESENTATION_FIELDS) do copy[key] = type(settings[key]) == "table" and CopyTable(settings[key]) or settings[key] end
    for _, key in ipairs(SIGNAL_APPEARANCE) do
        local value = settings.signal[key]
        copy.signal[key] = type(value) == "table" and CopyTable(value) or value
    end
    copy.effects = CopyTable((I.ReadEffects(group)))
    copy.effectVersion = 1
    -- The pandemic effect sits on the Effects tab and travels with effects.
    copy.pandemic = CopyTable(settings.pandemic or {})
    return copy
end

function I.ApplyPresentation(source, destination, appearance, effects)
    local iconRefusal = NameplateIconRefusal(source, destination, appearance)
    if iconRefusal then return false, iconRefusal end
    if effects then
        local allowed, reason = I.CanApplyEffects(source, destination, appearance)
        if not allowed then return false, reason end
    end
    local saved, target = I.Settings(source), I.Initialize(destination)
    if not saved or not target then return false end
    -- The marker is Effects-owned: an Appearance-only copy keeps the
    -- destination's marker even though it replaces the readouts around it.
    local marker = {}
    CopyTimerPolicy(effects and saved.readouts or target.readouts, marker, I.PandemicMarkerKeys)
    if appearance then
        for _, key in ipairs(PRESENTATION_FIELDS) do
            target[key] = type(saved[key]) == "table" and CopyTable(saved[key]) or saved[key]
        end
        for _, key in ipairs(SIGNAL_APPEARANCE) do
            local value = (saved.signal or {})[key]
            target.signal[key] = type(value) == "table" and CopyTable(value) or value
        end
    end
    if effects then
        StoreEffects(destination, (I.ReadEffects(source)))
        target.pandemic = CopyTable(saved.pandemic or {})
        -- A deliberate copy: keep the copied effect even from a source saved
        -- before the Text recolor (I.Initialize's one-time turn-off).
        target.pandemic.textRecolorReviewed = true
    end
    I.Initialize(destination)
    CopyTimerPolicy(marker, target.readouts, I.PandemicMarkerKeys)
    if appearance then NormalizeCountReadouts(destination) end
    return true
end
