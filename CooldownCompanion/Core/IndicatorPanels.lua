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

-- A source checked by rules: every source of a conditions Indicator, and the
-- extra spell/item sources of an aura Indicator. The aura itself has no
-- condition rules; its only rule is its stack rule (StackRule).
function I.IsConditionSource(group, entry)
    return ST.IsIndicatorGroup(group) and not (I.IsAura(group) and entry == I.Primary(group))
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
    if not I.IsAura(group) then return end
    local source = I.Primary(group)
    local rule = source and source.indicatorStackRule
    local compare = type(rule) == "table" and rule.compare
    return STACK_COMPARE_LABELS[compare] and compare or nil, rule
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
            if tracking == "aura" and ((effects[key].activation or "always") ~= "always" or effects[key].combatOnly) then
                return false, "indicator_effects_conditions"
            end
        end
    end
    local unavailable = tracking == "aura" and "colorShift" or "shrinkExpand"
    if displayType == "text" and effects[unavailable] and effects[unavailable].enabled == true then
        return false, "indicator_effects_text"
    end
    return true
end

function I.CanApplyEffects(source, destination, appearance)
    local effects, reason = I.ReadEffects(source)
    if not effects then return false, reason end
    local saved, target = I.Settings(source) or {}, I.Settings(destination) or {}
    return I.CheckEffects(effects, I.Primary(destination) and target.tracking,
        appearance and saved.displayType or target.displayType)
end

function I.CheckSourceEffects(group, source)
    local effects, reason = I.ReadEffects(group)
    if not effects then return false, reason end
    return I.CheckEffects(effects, source.addedAs == "aura" and "aura" or "conditions",
        (I.Settings(group) or {}).displayType)
end

-- The native aura renderer plays every enabled effect together for as long
-- as Blizzard shows the slot: Always, never combat-gated. Color Shift has no
-- artwork to tint on Text Only. A derived description keyed by effect, never
-- a second saved store.
function I.NativeEffects(group)
    if not I.IsAura(group) then return end
    I.Effects(group)
    local settings = I.Settings(group)
    local store = Addon.NormalizeTriggerPanelEffectStore(settings)
    local effects = {}
    for _, key in ipairs(I.EffectOrder) do
        local effect = store[key]
        if effect.enabled and not (key == "colorShift" and settings.displayType == "text") then
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
    return settings
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

-- Aura effects run only while the aura is shown, so an aura arriving adapts
-- them rather than being refused: Animate When and Only In Combat clear, and
-- Text Only drops Color Shift. Adds each change's chat note to `notes`.
local function AdaptEffectsForAura(settings, notes)
    local effects = settings.effects or {}
    local converted, off = {}, {}
    for _, key in ipairs(I.EffectOrder) do
        local effect = effects[key]
        if effect and effect.enabled == true then
            if key == "colorShift" and settings.displayType == "text" then
                effect.enabled = false
                off[#off + 1] = EFFECT_LABELS[key]
            elseif (effect.activation or "always") ~= "always" or effect.combatOnly then
                effect.activation, effect.combatOnly = nil, nil
                converted[#converted + 1] = EFFECT_LABELS[key]
            end
        end
    end
    if #converted > 0 then
        notes[#notes + 1] = ListNames(converted) .. (#converted > 1 and " now run" or " now runs")
            .. " while the Indicator is shown (auras can't use Animate When or Only In Combat)."
    end
    if #off > 0 then notes[#notes + 1] = ListNames(off) .. " is off (Text Only auras can't use it)." end
end

-- The same for a spell or item becoming the display: Text Only spell and item
-- Indicators can't Shrink / Expand, so it turns off instead of blocking.
local function AdaptEffectsForConditions(settings, notes)
    local shrink = (settings.effects or {}).shrinkExpand
    if settings.displayType == "text" and shrink and shrink.enabled == true then
        shrink.enabled = false
        notes[#notes + 1] = EFFECT_LABELS.shrinkExpand .. " is off (Text Only spell and item Indicators can't use it)."
    end
end

local function NoticeText(notes)
    return #notes > 0 and table.concat(notes, " ") or nil
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
    if firstSource then
        local effects, reason = I.ReadEffects(group)
        if not effects then return false, reason end
    end
    local settings = I.Initialize(group)
    if not settings then return true end
    I.Effects(group) -- Capture the previous family before tracking changes.
    if entry.enabled == nil then entry.enabled = true end
    local notes = {}
    if auraArrives then
        AdaptEffectsForAura(settings, notes)
    elseif firstSource then
        AdaptEffectsForConditions(settings, notes)
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
    local icon = Addon.NormalizeTriggerIconSettings(CopyTable(settings.icon))
    local source = I.Primary(group)
    if not icon.manualIcon and source then icon.manualIcon = SourceIcon(source) end
    return icon
end

-- Just the icon an Icon display draws (a valid chosen icon, else the main
-- source's), without copying the icon settings: the preview asks per tick.
function I.ArtworkIcon(group)
    local settings = I.Settings(group)
    if not settings then return end
    local chosen = settings.icon and settings.icon.manualIcon
    if chosen and Addon.IsValidTriggerPanelIconTexture(chosen) then return chosen end
    local source = I.Primary(group)
    return source and SourceIcon(source)
end

-- A render description only. Saved placement always belongs to signal.
function I.NativeSettings(group, resolvedIcon)
    local settings = I.Settings(group)
    if not settings then return end
    if settings.displayType == "texture" then
        return Addon:GetTexturePanelSettings(group, true)
    end
    local visual = { enabled = true, sourceType = "file", sourceValue = "Interface\\Buttons\\WHITE8x8",
        blendMode = "BLEND", locationType = "CENTER", color = {1, 1, 1, 1} }
    if settings.displayType == "icon" then
        local icon = resolvedIcon or I.IconSettings(group)
        visual.sourceValue = icon.manualIcon
        visual.width, visual.height = Addon.GetTriggerIconDimensions(icon)
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

I.OneAuraText = "This Indicator already checks an aura. Remove it first, or create another Indicator."

-- One aura per Indicator. It can arrive at any time and always becomes the
-- display (OnSourceAdded); spell and item sources are checked by their rules.
function I.AddRestriction(group, entry)
    if not ST.IsIndicatorGroup(group) then return end
    local entries = entry and (entry[1] and entry or {entry}) or {}
    local auras = I.Primary(group) and I.IsAura(group) and 1 or 0
    for _, source in ipairs(entries) do
        if source.addedAs == "aura" then
            auras = auras + 1
            if auras > 1 then return I.OneAuraText end
        end
    end
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
-- a secret or unknown reading never matches.
local function RulesPass(runtime, group, first)
    local entries = group.buttons or {}
    for index = first, #entries do
        local entry = entries[index]
        if entry.enabled ~= false then
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

-- An aura Indicator's extra sources: the aura itself shows while active and
-- has no rules. With no extras there is nothing to check (and nothing to pay).
function I.ExtraSourcesMatch(frame, group)
    if not I.IsAura(group) or not group.buttons or #group.buttons < 2 then return true end
    return RulesPass(RuntimeButtons(frame), group, 2)
end

function I.ClearSource(group)
    local settings = I.Initialize(group)
    I.Effects(group)
    group.buttons = {}
    settings.tracking = "conditions"
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

-- The source that takes over when the main source is removed.
function I.NextMainSource(group)
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
    if I.IsAura(group) then AdaptEffectsForConditions(I.Settings(group), notes) end
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

-- Remove one source. Removing the main source hands slot one to the next
-- source that can take it; with none, the Indicator is cleared and keeps its
-- look. A source that is no longer in the Indicator removes nothing. Returns
-- removed, a failure reason, and an optional chat line.
function I.RemoveSource(group, entry)
    local buttons = group.buttons or {}
    local index = IndexOf(group, entry)
    if not index then return false end
    local notice
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

local function SameSource(a, b)
    return a.type == b.type and a.id == b.id and a.itemSlot == b.itemSlot
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
    return candidate
end

function I.CommitSourceReplacement(group, candidate)
    local allowed, reason = I.CheckSourceEffects(candidate, I.Primary(candidate))
    if not allowed then return false, reason end
    -- Only the main source changes. The other sources keep their rules, unless
    -- one is the new source (it starts fresh as the main source instead).
    -- Older aura-added rows are rule rows; only the main source owns an aura.
    local newSource = I.Primary(candidate)
    -- Change... swaps the aura, not the rule: a stack rule moves to the new aura.
    local oldRule = I.IsAura(group) and I.Primary(group).indicatorStackRule
    if oldRule and I.IsAura(candidate) and newSource.indicatorStackRule == nil then
        newSource.indicatorStackRule = CopyTable(oldRule)
    end
    for i = 2, #(group.buttons or {}) do
        local entry = group.buttons[i]
        if not SameSource(entry, newSource) then
            candidate.buttons[#candidate.buttons + 1] = entry
        end
    end
    group.buttons = candidate.buttons
    local settings = I.Settings(group)
    settings.tracking = I.Settings(candidate).tracking
    StoreEffects(group, I.Effects(candidate))
    NormalizeCountReadouts(group)
    return true
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
    end
    I.Initialize(destination)
    CopyTimerPolicy(marker, target.readouts, I.PandemicMarkerKeys)
    if appearance then NormalizeCountReadouts(destination) end
    return true
end
