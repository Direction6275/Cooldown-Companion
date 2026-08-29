--[[
    CooldownCompanion - ResourceBarConstants
    Shared constant tables, color defaults, and power mappings used by the
    runtime modules (ResourceBarHelpers, ResourceBarVisuals, ResourceBar)
    and the config panel modules (ResourceBarPanelsHelpers, ResourceBarPanels).

    Exported via ST._RB table. Consuming files alias to locals at load time
    so there is no runtime lookup cost.
]]

local ADDON_NAME, ST = ...

------------------------------------------------------------------------
-- Timing & Limits
------------------------------------------------------------------------

local UPDATE_INTERVAL = 1 / 30  -- 30 Hz
local PERCENT_SCALE_CURVE = C_CurveUtil.CreateCurve()
PERCENT_SCALE_CURVE:SetType(Enum.LuaCurveType.Linear)
PERCENT_SCALE_CURVE:AddPoint(0.0, 0)
PERCENT_SCALE_CURVE:AddPoint(1.0, 100)

local CUSTOM_AURA_BAR_BASE = 201  -- 201-205 for slots 1-5
local RAGING_MAELSTROM_SPELL_ID = 384143
-- The Active Aura stand-in: what a custom bar shows while its preview runs.
-- Deliberately invented values (no aura is running), shared so the config
-- canvas and the runtime tell the same story.
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL = 0.65
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS = 3
local CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION = 12.3
local RESOURCE_HEALTH = -1
local RESOURCE_MAELSTROM_WEAPON = 100
-- Stagger power type ID: 101 (used inline to stay under Lua 200-local limit)

------------------------------------------------------------------------
-- Default Colors
------------------------------------------------------------------------

local DEFAULT_MW_BASE_COLOR = { 0, 0.5, 1 }
local DEFAULT_MW_OVERLAY_COLOR = { 1, 0.84, 0 }
local DEFAULT_MW_MAX_COLOR = { 0.5, 0.8, 1 }
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = { 1, 0.84, 0 }
local DEFAULT_SEG_THRESHOLD_COLOR = { 1, 0.84, 0 }
local DEFAULT_HEALTH_BAR_COLOR = { 0.25, 0.78, 0.22 }
local DEFAULT_HEALTH_BAR_OPACITY = 0.7
local DEFAULT_HEALTH_BAR_FULL_COLOR = DEFAULT_HEALTH_BAR_COLOR
local DEFAULT_HEALTH_BAR_HALF_COLOR = { 1.00, 0.84, 0.00 }
local DEFAULT_HEALTH_BAR_LOW_COLOR = { 0.80, 0.00, 0.00 }
local DEFAULT_HEALTH_BAR_GRADIENT = false
local DEFAULT_HEALTH_BACKGROUND_COLOR = { 0.08, 0.08, 0.08 }
local DEFAULT_HEALTH_BACKGROUND_FULL_COLOR = { 0.90, 0.95, 1.00 }
local DEFAULT_HEALTH_BACKGROUND_HALF_COLOR = { 1.00, 0.84, 0.00 }
local DEFAULT_HEALTH_BACKGROUND_LOW_COLOR = { 0.80, 0.00, 0.00 }
local DEFAULT_HEALTH_BACKGROUND_OPACITY = 1
local DEFAULT_HEALTH_BACKGROUND_GRADIENT = true
local DEFAULT_HEALTH_ABSORB_COLOR = { 0.55, 0.85, 1.0, 0.45 }
local DEFAULT_HEALTH_HEAL_ABSORB_COLOR = { 1.0, 0.12, 0.12, 0.55 }
local DEFAULT_HEALTH_INCOMING_HEAL_COLOR = { 0.1, 0.85, 0.35, 0.45 }
local DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR = { 1.0, 0.08, 0.04, 0.35 }
local DEFAULT_HEALTH_EFFECT_TEXTURE = "Solid"
local DEFAULT_RESOURCE_TEXT_FORMAT = "current"
local DEFAULT_RESOURCE_TEXT_FONT = "Friz Quadrata TT"
local DEFAULT_RESOURCE_TEXT_SIZE = 10
local DEFAULT_RESOURCE_TEXT_OUTLINE = "OUTLINE"
local DEFAULT_RESOURCE_TEXT_COLOR = { 1, 1, 1, 1 }
local DEFAULT_RESOURCE_RECHARGE_TEXT_ENABLED = false
local DEFAULT_CONTINUOUS_TICK_COLOR = { 1, 0.84, 0, 1 }
local DEFAULT_CONTINUOUS_TICK_MODE = "percent"
local DEFAULT_CONTINUOUS_TICK_PERCENT = 50
local DEFAULT_CONTINUOUS_TICK_ABSOLUTE = 50
local DEFAULT_CONTINUOUS_TICK_WIDTH = 2
local INDEPENDENT_NUDGE_BTN_SIZE = 12

------------------------------------------------------------------------
-- Power Colors & Names
------------------------------------------------------------------------

local DEFAULT_POWER_COLORS = {
    [RESOURCE_HEALTH] = DEFAULT_HEALTH_BAR_COLOR,
    [0]  = { 0, 0, 1 },              -- Mana
    [1]  = { 1, 0, 0 },              -- Rage
    [2]  = { 1, 0.5, 0.25 },         -- Focus
    [3]  = { 1, 1, 0 },              -- Energy
    [4]  = { 1, 0.96, 0.41 },        -- ComboPoints
    [5]  = { 0.5, 0.5, 0.5 },        -- Runes
    [6]  = { 0, 0.82, 1 },           -- RunicPower
    [7]  = { 0.5, 0.32, 0.55 },      -- SoulShards
    [8]  = { 0.3, 0.52, 0.9 },       -- LunarPower
    [9]  = { 0.95, 0.9, 0.6 },       -- HolyPower
    [11] = { 0, 0.5, 1 },            -- Maelstrom
    [12] = { 0.71, 1, 0.92 },        -- Chi
    [13] = { 0.4, 0, 0.8 },          -- Insanity
    [16] = { 0.1, 0.1, 0.98 },       -- ArcaneCharges
    [17] = { 0.788, 0.259, 0.992 },  -- Fury
    [18] = { 1, 0.612, 0 },          -- Pain
    [19] = { 0.286, 0.773, 0.541 },  -- Essence
}

local POWER_NAMES = {
    [RESOURCE_HEALTH] = "Health",
    [0]  = "Mana",
    [1]  = "Rage",
    [2]  = "Focus",
    [3]  = "Energy",
    [4]  = "Combo Points",
    [5]  = "Runes",
    [6]  = "Runic Power",
    [7]  = "Soul Shards",
    [8]  = "Astral Power",
    [9]  = "Holy Power",
    [11] = "Maelstrom",
    [12] = "Chi",
    [13] = "Insanity",
    [16] = "Arcane Charges",
    [17] = "Fury",
    [100] = "Maelstrom Weapon",
    [101] = "Stagger",
    [102] = "Icicles",
    [103] = "Tip of the Spear",
    -- The Devourer pair is named for the outcome spell the player knows,
    -- not for the stack aura the plumbing reads underneath.
    [104] = "Void Metamorphosis",
    [105] = "Collapsing Star",
    [18] = "Pain",
    [19] = "Essence",
}

local POWER_SHORT_NAMES = {
    [RESOURCE_HEALTH] = "HP",
}

------------------------------------------------------------------------
-- Per-resource default color tables
------------------------------------------------------------------------

local DEFAULT_COMBO_COLOR = { 1, 0.96, 0.41 }
local DEFAULT_COMBO_MAX_COLOR = { 1, 0.96, 0.41 }
local DEFAULT_COMBO_CHARGED_COLOR = { 0.24, 0.65, 1.0 }

local DEFAULT_RUNE_READY_COLOR = { 0.8, 0.8, 0.8 }
local DEFAULT_RUNE_RECHARGING_COLOR = { 0.490, 0.490, 0.490 }
local DEFAULT_RUNE_MAX_COLOR = { 0.8, 0.8, 0.8 }

local DEFAULT_SHARD_READY_COLOR = { 0.5, 0.32, 0.55 }
local DEFAULT_SHARD_RECHARGING_COLOR = { 0.490, 0.490, 0.490 }
local DEFAULT_SHARD_MAX_COLOR = { 0.5, 0.32, 0.55 }

local DEFAULT_HOLY_COLOR = { 0.95, 0.9, 0.6 }
local DEFAULT_HOLY_MAX_COLOR = { 0.95, 0.9, 0.6 }

local DEFAULT_CHI_COLOR = { 0.71, 1, 0.92 }
local DEFAULT_CHI_MAX_COLOR = { 0.71, 1, 0.92 }

local DEFAULT_ARCANE_COLOR = { 0.1, 0.1, 0.98 }
local DEFAULT_ARCANE_MAX_COLOR = { 0.1, 0.1, 0.98 }

local DEFAULT_ESSENCE_READY_COLOR = { 0.851, 0.482, 0.780 }
local DEFAULT_ESSENCE_RECHARGING_COLOR = { 0.490, 0.490, 0.490 }
local DEFAULT_ESSENCE_MAX_COLOR = { 0.851, 0.482, 0.780 }

------------------------------------------------------------------------
-- Type classifications
------------------------------------------------------------------------

local SEGMENTED_TYPES = {
    [4]  = true,  -- ComboPoints
    [5]  = true,  -- Runes
    [7]  = true,  -- SoulShards
    [9]  = true,  -- HolyPower
    [12] = true,  -- Chi
    [16] = true,  -- ArcaneCharges
    [19] = true,  -- Essence
}

-- Atlas info for class-specific bar textures (from PowerBarColorUtil.lua)
-- Only continuous power types that have a direct atlas field in Blizzard's data
local POWER_ATLAS_INFO = {
    [8]  = { atlas = "Unit_Druid_AstralPower_Fill" },
    [11] = { atlas = "Unit_Shaman_Maelstrom_Fill" },
    [13] = { atlas = "Unit_Priest_Insanity_Fill" },
    [17] = { atlas = "Unit_DemonHunter_Fury_Fill" },
    [18] = { atlas = "_DemonHunter-DemonicPainBar" },
}

-- Power types eligible for "hide at zero" config option (config UI only)
local HIDE_AT_ZERO_ELIGIBLE = {
    [4]  = true, [7]  = true, [9]  = true,
    [12] = true, [16] = true, [100] = true,
    [102] = true, [103] = true,
    [104] = true, [105] = true,
}

------------------------------------------------------------------------
-- Class / Spec resource mappings
------------------------------------------------------------------------

-- Class-to-resource mapping (classID -> ordered list of power types)
-- Order = stacking order (first = closest to anchor)
local CLASS_RESOURCES = {
    [1]  = { 1 },           -- Warrior: Rage
    [2]  = { 9, 0 },        -- Paladin: HolyPower, Mana
    [3]  = { 2 },           -- Hunter: Focus
    [4]  = { 4, 3 },        -- Rogue: ComboPoints, Energy
    [5]  = { 0 },           -- Priest: Mana (Insanity added per spec)
    [6]  = { 5, 6 },        -- DK: Runes, RunicPower
    [7]  = { 0 },           -- Shaman: Mana (Maelstrom added per spec)
    [8]  = { 0 },           -- Mage: Mana (ArcaneCharges added per spec)
    [9]  = { 7, 0 },        -- Warlock: SoulShards, Mana
    [10] = { 0 },           -- Monk: Mana (Energy, Chi added per spec)
    [11] = nil,             -- Druid: form-dependent (handled separately)
    [12] = { 17 },          -- DH: Fury
    [13] = { 19, 0 },       -- Evoker: Essence, Mana
}

-- Spec-specific resource overrides (specID -> replaces class defaults)
local SPEC_RESOURCES = {
    [258] = { 13, 0 },      -- Shadow Priest: Insanity, Mana
    [262] = { 11, 0 },      -- Elemental Shaman: Maelstrom, Mana
    [263] = { 100, 0 },      -- Enhancement Shaman: MW, Mana
    [62]  = { 16, 0 },      -- Arcane Mage: ArcaneCharges, Mana
    [269] = { 12, 3 },      -- Windwalker Monk: Chi, Energy
    [268] = { 101, 3 },        -- Brewmaster Monk: Stagger, Energy
    [581] = { 17 },         -- Vengeance DH: Fury
    [64]  = { 102, 0 },     -- Frost Mage: Icicles, Mana
    [255] = { 103, 2 },     -- Survival Hunter: Tip of the Spear, Focus
    -- Devourer DH: both halves of the Void Metamorphosis pair ahead of
    -- Fury. Only one of the two is ever materialized — the runtime filter
    -- in ApplyResourceBars drops the suppressed half — but both stay in
    -- this list so the swap happens in place, without reordering Fury.
    [1480] = { 104, 105, 17 },
}

-- Druid specialization resources that can remain visible across forms.
-- This is Cooldown Companion display policy, not a Blizzard form mapping.
local DRUID_PERSISTENT_RESOURCES_BY_SPEC = {
    [102] = { 8 },            -- Balance: Astral Power
    [103] = { 4, 3 },         -- Feral: Combo Points, Energy
    [104] = { 1 },            -- Guardian: Rage
    [105] = {},               -- Restoration: Mana is appended separately
}

-- Druid form mapping (verified in-game: Bear=5, Cat=1, Moonkin=31)
local DRUID_FORM_RESOURCES = {
    [5]  = { 1 },           -- Bear: Rage
    [1]  = { 4, 3 },        -- Cat: ComboPoints, Energy
    [31] = { 8 },           -- Moonkin: LunarPower
}
local DRUID_DEFAULT_RESOURCES = { 0 }  -- No form: Mana

-- Class-to-resource mapping for config UI (Druid shows all possible)
local CLASS_RESOURCES_CONFIG = {
    [1]  = { 1 },
    [2]  = { 9, 0 },
    [3]  = { 2 },
    [4]  = { 4, 3 },
    [5]  = { 0 },
    [6]  = { 5, 6 },
    [7]  = { 0 },
    [8]  = { 0 },
    [9]  = { 7, 0 },
    [10] = { 0 },
    [11] = { 1, 4, 3, 8, 0 },  -- All possible druid resources
    [12] = { 17 },
    [13] = { 19, 0 },
}

local SPEC_RESOURCES_CONFIG = {
    [258] = { 13, 0 },
    [262] = { 11, 0 },
    [263] = { 100, 0 },
    [62]  = { 16, 0 },
    [269] = { 12, 3 },
    [268] = { 101, 3 },  -- Brewmaster: Stagger, Energy
    [581] = { 17 },
    [64]  = { 102, 0 },  -- Frost Mage: Icicles, Mana
    [255] = { 103, 2 },  -- Survival: Tip of the Spear, Focus
    -- Devourer: the config always lists both halves of the pair, whichever
    -- one the player happens to be showing right now.
    [1480] = { 104, 105, 17 },
}

------------------------------------------------------------------------
-- Color definition lookup table (used by GetResourceColors)
------------------------------------------------------------------------

local RESOURCE_COLOR_DEFS = {
    [4]   = { keys = { "comboColor", "comboMaxColor", "comboChargedColor" },
              defaults = { DEFAULT_COMBO_COLOR, DEFAULT_COMBO_MAX_COLOR, DEFAULT_COMBO_CHARGED_COLOR } },
    [5]   = { keys = { "runeReadyColor", "runeRechargingColor", "runeMaxColor" },
              defaults = { DEFAULT_RUNE_READY_COLOR, DEFAULT_RUNE_RECHARGING_COLOR, DEFAULT_RUNE_MAX_COLOR } },
    [7]   = { keys = { "shardReadyColor", "shardRechargingColor", "shardMaxColor" },
              defaults = { DEFAULT_SHARD_READY_COLOR, DEFAULT_SHARD_RECHARGING_COLOR, DEFAULT_SHARD_MAX_COLOR } },
    [9]   = { keys = { "holyColor", "holyMaxColor" },
              defaults = { DEFAULT_HOLY_COLOR, DEFAULT_HOLY_MAX_COLOR } },
    [12]  = { keys = { "chiColor", "chiMaxColor" },
              defaults = { DEFAULT_CHI_COLOR, DEFAULT_CHI_MAX_COLOR } },
    [16]  = { keys = { "arcaneColor", "arcaneMaxColor" },
              defaults = { DEFAULT_ARCANE_COLOR, DEFAULT_ARCANE_MAX_COLOR } },
    [19]  = { keys = { "essenceReadyColor", "essenceRechargingColor", "essenceMaxColor" },
              defaults = { DEFAULT_ESSENCE_READY_COLOR, DEFAULT_ESSENCE_RECHARGING_COLOR, DEFAULT_ESSENCE_MAX_COLOR } },
    [100] = { keys = { "mwBaseColor", "mwOverlayColor", "mwMaxColor" },
              defaults = { DEFAULT_MW_BASE_COLOR, DEFAULT_MW_OVERLAY_COLOR, DEFAULT_MW_MAX_COLOR } },
    [101] = { keys = { "staggerGreenColor", "staggerYellowColor", "staggerRedColor" },
              defaults = { { 0.52, 0.90, 0.52 }, { 1.0, 0.85, 0.36 }, { 1.0, 0.42, 0.42 } } },
}

------------------------------------------------------------------------
-- Config UI text defaults (used by ResourceBarPanels)
------------------------------------------------------------------------

local DEFAULT_RESOURCE_TEXT_ANCHOR = "CENTER"
local DEFAULT_RESOURCE_TEXT_X_OFFSET = 0
local DEFAULT_RESOURCE_TEXT_Y_OFFSET = 0

------------------------------------------------------------------------
-- Export via ST._RB
------------------------------------------------------------------------

ST._RB = {
    -- Timing & limits
    UPDATE_INTERVAL = UPDATE_INTERVAL,
    PERCENT_SCALE_CURVE = PERCENT_SCALE_CURVE,
    CUSTOM_AURA_BAR_BASE = CUSTOM_AURA_BAR_BASE,
    CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL = CUSTOM_AURA_BAR_EFFECT_PREVIEW_FILL,
    CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS = CUSTOM_AURA_BAR_EFFECT_PREVIEW_STACKS,
    CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION = CUSTOM_AURA_BAR_EFFECT_PREVIEW_DURATION,
    RAGING_MAELSTROM_SPELL_ID = RAGING_MAELSTROM_SPELL_ID,
    -- The APPLIED Maelstrom Weapon aura (CumulativeAura=5 in SpellAuraOptions,
    -- 10 with Raging Maelstrom). Not live's 187880, which is the proc trigger
    -- carrying no stacks — live only resolved the real aura through a CDM
    -- viewer frame's auraInstanceID, a path 12.1 closed. Written inline
    -- rather than as a local: this chunk is at Lua 5.1's 200-local ceiling.
    MW_AURA_SPELL_ID = 344179,
    RESOURCE_HEALTH = RESOURCE_HEALTH,
    RESOURCE_MAELSTROM_WEAPON = RESOURCE_MAELSTROM_WEAPON,

    -- The aura-stack resource family: pseudo resources whose value is an
    -- aura's stack count rather than a power type, read with the same plain
    -- GetPlayerAuraBySpellID call Maelstrom Weapon runs on. Membership in
    -- this table is what makes a power type one of them — engine, config and
    -- previews all ask it rather than testing ids. Maelstrom Weapon is
    -- deliberately NOT a member: its shipped mw* keys, its third (overlay)
    -- shape and its talent-driven maximum are its own, and generalizing them
    -- would change what already ships. Written inline rather than as locals:
    -- this chunk is at Lua 5.1's 200-local ceiling.
    --   102 Icicles (Frost Mage), 103 Tip of the Spear (Survival Hunter),
    --   104 Void Metamorphosis / 105 Collapsing Star (Devourer DH)
    --
    -- Three optional fields describe what a member cannot state as a
    -- constant, all resolved by the engine so no function lives here:
    --   dynamicMax     the maximum comes from an API, not from maxStacks;
    --                  fallbackMax stands in until that API answers, and is
    --                  the aura's own base cap out of game data so the
    --                  stand-in is the untalented truth rather than a guess
    --   defaultStyle   the shape this member ships with, when its own
    --                  maximum makes one segment per stack the wrong read
    --   metaVisibility this member is half of a mutually exclusive pair,
    --                  shown only in ("inMeta") or only out of
    --                  ("outOfMeta") Void Metamorphosis
    --   canonicalHalf  this member owns none of its SLOT-SHAPED settings:
    --                  they are read from and written to the named member's
    --                  entries instead. A mutually exclusive pair is ONE bar
    --                  in the world, so it is ONE slot in the stack, ONE
    --                  slot on the layout canvas, and one store for every
    --                  setting that describes that one slot: placement
    --                  (side, order, per-bar thickness) in layout.resources,
    --                  plus stack display shape and the max-stack border in
    --                  settings.resources. What is per-HALF rather than
    --                  per-slot — colors and stack thresholds — stays in
    --                  each half's own settings.resources bucket. One field,
    --                  because the two must never disagree about which half
    --                  is canonical.
    -- Members without them behave exactly as they did before: fixed
    -- maximum, segmented by default, always visible, placed on their own.
    AURA_STACK_RESOURCES = {
        [102] = {
            auraSpellID = 205473,
            maxStacks = 5,
            colorKeys = { "iciclesColor", "iciclesMaxColor" },
            colorDefaults = { { 0.45, 0.75, 1.0 }, { 0.8, 0.95, 1.0 } },
            colorLabels = { "Icicles", "Icicles (Max)" },
        },
        [103] = {
            auraSpellID = 260286,
            maxStacks = 3,
            colorKeys = { "tipOfSpearColor", "tipOfSpearMaxColor" },
            colorDefaults = { { 0.65, 0.75, 0.4 }, { 0.9, 0.95, 0.6 } },
            colorLabels = { "Tip of the Spear", "Tip of the Spear (Max)" },
        },
        -- Devourer, out of meta: Dark Heart stacks, capped by the aura's own
        -- cumulative maximum. Continuous by default — that cap is large
        -- enough that one segment per stack reads as noise.
        [104] = {
            auraSpellID = 1225789,
            dynamicMax = "cumulativeAura",
            -- Dark Heart's own CumulativeAura (SpellAuraOptions, live 12.1).
            fallbackMax = 50,
            defaultStyle = "continuous",
            metaVisibility = "outOfMeta",
            colorKeys = { "vmColor", "vmMaxColor" },
            colorDefaults = { { 0.79, 0.26, 0.99 }, { 0.92, 0.6, 1.0 } },
            colorLabels = { "Void Metamorphosis", "Void Metamorphosis (Max)" },
        },
        -- Devourer, in meta: Silence the Whispers stacks, capped by what
        -- Collapsing Star currently costs.
        [105] = {
            auraSpellID = 1227702,
            dynamicMax = "collapsingStarCost",
            -- Silence the Whispers' own CumulativeAura (SpellAuraOptions,
            -- live 12.1), which bounds what the star can cost.
            fallbackMax = 40,
            defaultStyle = "continuous",
            metaVisibility = "inMeta",
            canonicalHalf = 104,
            colorKeys = { "starColor", "starMaxColor" },
            colorDefaults = { { 0.45, 0.15, 0.75 }, { 0.75, 0.4, 1.0 } },
            colorLabels = { "Collapsing Star", "Collapsing Star (Max)" },
        },
    },

    -- The aura whose presence decides which half of the Devourer pair is
    -- shown. Read exactly the way Blizzard's own Devourer bar reads it:
    -- presence only, through the plain never-secret aura call.
    VOID_METAMORPHOSIS_SPELL_ID = 1217607,

    -- Key names for the max-stack border, per resource. Maelstrom Weapon
    -- keeps the mw* keys it shipped with (never renamed, no migration); the
    -- aura-stack family uses the generic set in its own resource bucket.
    -- Shared so the runtime and the config write the same names; the config
    -- hands these straight to the shared glow-slider rows, which is why
    -- solidSizeDefault rides along.
    MAX_STACK_BORDER_KEYS = {
        [RESOURCE_MAELSTROM_WEAPON] = {
            enabled = "mwMaxStackBorderEnabled",
            style = "mwMaxStackBorderStyle",
            color = "mwMaxStackBorderColor",
            size = "mwMaxStackBorderSize",
            thickness = "mwMaxStackBorderThickness",
            speed = "mwMaxStackBorderSpeed",
            lines = "mwMaxStackBorderLines",
            solidSizeDefault = 2,
        },
        default = {
            enabled = "maxStackBorderEnabled",
            style = "maxStackBorderStyle",
            color = "maxStackBorderColor",
            size = "maxStackBorderSize",
            thickness = "maxStackBorderThickness",
            speed = "maxStackBorderSpeed",
            lines = "maxStackBorderLines",
            solidSizeDefault = 2,
        },
    },

    -- Default colors
    DEFAULT_MW_BASE_COLOR = DEFAULT_MW_BASE_COLOR,
    DEFAULT_MW_OVERLAY_COLOR = DEFAULT_MW_OVERLAY_COLOR,
    DEFAULT_MW_MAX_COLOR = DEFAULT_MW_MAX_COLOR,
    -- Max-stack border default. Deliberately NOT the max fill colour: the
    -- border draws on top of the at-max fill, and matching it would make
    -- the border invisible. Written inline: 200-local ceiling.
    DEFAULT_MW_MAX_STACK_BORDER_COLOR = { 1, 1, 1, 1 },
    DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR,
    -- How far above a resource bar its aura overlay mounts. Clear of every
    -- non-text layer the bar draws: segment children at bar+3, MW overlay
    -- segments at +4, the CC-side aura lane pool at +7. Frame level beats
    -- draw layer, so anything short of this renders behind the bar it
    -- decorates. The config canvas stands the overlay in at the same
    -- height, which is why this is shared rather than local to the host.
    RESOURCE_OVERLAY_HOLDER_LEVEL = 9,
    -- The resource-stack band order (owner ruling 2026-08-09): bar fills at
    -- the bottom, borders/glows/aura kit above them, tick markers above the
    -- kit (they are value landmarks and must stay readable over the aura
    -- fill tint), RESOURCE text above everything. Bars in the stack are
    -- same-level siblings, so a large font spilling past its bar's rect
    -- used to lose to the neighboring bar's aura kit; every resource text
    -- layer now mounts at this shared offset above its bar instead of a
    -- per-shape bump. Derivation: the tallest kit is the aura overlay
    -- holder at bar+9 whose strata map reserves through holder+15
    -- (auraDisplay at +8, span 8 — Core/Init.lua), so ticks clear bar+24
    -- and texts sit one above the ticks. Custom bar text layers
    -- deliberately do NOT use this band: CC keeps writing spell-bar
    -- cooldown text with no way to know an aura is showing, so their kit
    -- must keep occluding their text (they stay at bar+2, under their
    -- holder at bar+3).
    RESOURCE_TICK_LAYER_LEVEL = 25,
    RESOURCE_TEXT_LAYER_LEVEL = 26,
    DEFAULT_SEG_THRESHOLD_COLOR = DEFAULT_SEG_THRESHOLD_COLOR,
    DEFAULT_HEALTH_BAR_COLOR = DEFAULT_HEALTH_BAR_COLOR,
    DEFAULT_HEALTH_BAR_OPACITY = DEFAULT_HEALTH_BAR_OPACITY,
    DEFAULT_HEALTH_BAR_FULL_COLOR = DEFAULT_HEALTH_BAR_FULL_COLOR,
    DEFAULT_HEALTH_BAR_HALF_COLOR = DEFAULT_HEALTH_BAR_HALF_COLOR,
    DEFAULT_HEALTH_BAR_LOW_COLOR = DEFAULT_HEALTH_BAR_LOW_COLOR,
    DEFAULT_HEALTH_BAR_GRADIENT = DEFAULT_HEALTH_BAR_GRADIENT,
    DEFAULT_HEALTH_BACKGROUND_COLOR = DEFAULT_HEALTH_BACKGROUND_COLOR,
    DEFAULT_HEALTH_BACKGROUND_FULL_COLOR = DEFAULT_HEALTH_BACKGROUND_FULL_COLOR,
    DEFAULT_HEALTH_BACKGROUND_HALF_COLOR = DEFAULT_HEALTH_BACKGROUND_HALF_COLOR,
    DEFAULT_HEALTH_BACKGROUND_LOW_COLOR = DEFAULT_HEALTH_BACKGROUND_LOW_COLOR,
    DEFAULT_HEALTH_BACKGROUND_OPACITY = DEFAULT_HEALTH_BACKGROUND_OPACITY,
    DEFAULT_HEALTH_BACKGROUND_GRADIENT = DEFAULT_HEALTH_BACKGROUND_GRADIENT,
    DEFAULT_HEALTH_ABSORB_COLOR = DEFAULT_HEALTH_ABSORB_COLOR,
    DEFAULT_HEALTH_HEAL_ABSORB_COLOR = DEFAULT_HEALTH_HEAL_ABSORB_COLOR,
    DEFAULT_HEALTH_INCOMING_HEAL_COLOR = DEFAULT_HEALTH_INCOMING_HEAL_COLOR,
    DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR = DEFAULT_HEALTH_LOW_HEALTH_ALERT_COLOR,
    DEFAULT_HEALTH_EFFECT_TEXTURE = DEFAULT_HEALTH_EFFECT_TEXTURE,
    DEFAULT_RESOURCE_TEXT_FORMAT = DEFAULT_RESOURCE_TEXT_FORMAT,
    DEFAULT_RESOURCE_TEXT_FONT = DEFAULT_RESOURCE_TEXT_FONT,
    DEFAULT_RESOURCE_TEXT_SIZE = DEFAULT_RESOURCE_TEXT_SIZE,
    DEFAULT_RESOURCE_TEXT_OUTLINE = DEFAULT_RESOURCE_TEXT_OUTLINE,
    DEFAULT_RESOURCE_TEXT_COLOR = DEFAULT_RESOURCE_TEXT_COLOR,
    DEFAULT_RESOURCE_RECHARGE_TEXT_ENABLED = DEFAULT_RESOURCE_RECHARGE_TEXT_ENABLED,
    DEFAULT_CONTINUOUS_TICK_COLOR = DEFAULT_CONTINUOUS_TICK_COLOR,
    DEFAULT_CONTINUOUS_TICK_MODE = DEFAULT_CONTINUOUS_TICK_MODE,
    DEFAULT_CONTINUOUS_TICK_PERCENT = DEFAULT_CONTINUOUS_TICK_PERCENT,
    DEFAULT_CONTINUOUS_TICK_ABSOLUTE = DEFAULT_CONTINUOUS_TICK_ABSOLUTE,
    DEFAULT_CONTINUOUS_TICK_WIDTH = DEFAULT_CONTINUOUS_TICK_WIDTH,
    INDEPENDENT_NUDGE_BTN_SIZE = INDEPENDENT_NUDGE_BTN_SIZE,

    -- Per-resource default colors
    DEFAULT_COMBO_COLOR = DEFAULT_COMBO_COLOR,
    DEFAULT_COMBO_MAX_COLOR = DEFAULT_COMBO_MAX_COLOR,
    DEFAULT_COMBO_CHARGED_COLOR = DEFAULT_COMBO_CHARGED_COLOR,
    DEFAULT_RUNE_READY_COLOR = DEFAULT_RUNE_READY_COLOR,
    DEFAULT_RUNE_RECHARGING_COLOR = DEFAULT_RUNE_RECHARGING_COLOR,
    DEFAULT_RUNE_MAX_COLOR = DEFAULT_RUNE_MAX_COLOR,
    DEFAULT_SHARD_READY_COLOR = DEFAULT_SHARD_READY_COLOR,
    DEFAULT_SHARD_RECHARGING_COLOR = DEFAULT_SHARD_RECHARGING_COLOR,
    DEFAULT_SHARD_MAX_COLOR = DEFAULT_SHARD_MAX_COLOR,
    DEFAULT_HOLY_COLOR = DEFAULT_HOLY_COLOR,
    DEFAULT_HOLY_MAX_COLOR = DEFAULT_HOLY_MAX_COLOR,
    DEFAULT_CHI_COLOR = DEFAULT_CHI_COLOR,
    DEFAULT_CHI_MAX_COLOR = DEFAULT_CHI_MAX_COLOR,
    DEFAULT_ARCANE_COLOR = DEFAULT_ARCANE_COLOR,
    DEFAULT_ARCANE_MAX_COLOR = DEFAULT_ARCANE_MAX_COLOR,
    DEFAULT_ESSENCE_READY_COLOR = DEFAULT_ESSENCE_READY_COLOR,
    DEFAULT_ESSENCE_RECHARGING_COLOR = DEFAULT_ESSENCE_RECHARGING_COLOR,
    DEFAULT_ESSENCE_MAX_COLOR = DEFAULT_ESSENCE_MAX_COLOR,

    -- Power data
    DEFAULT_POWER_COLORS = DEFAULT_POWER_COLORS,
    POWER_NAMES = POWER_NAMES,
    POWER_SHORT_NAMES = POWER_SHORT_NAMES,
    SEGMENTED_TYPES = SEGMENTED_TYPES,
    POWER_ATLAS_INFO = POWER_ATLAS_INFO,
    HIDE_AT_ZERO_ELIGIBLE = HIDE_AT_ZERO_ELIGIBLE,
    RESOURCE_COLOR_DEFS = RESOURCE_COLOR_DEFS,

    -- Class/spec mappings
    CLASS_RESOURCES = CLASS_RESOURCES,
    SPEC_RESOURCES = SPEC_RESOURCES,
    DRUID_PERSISTENT_RESOURCES_BY_SPEC = DRUID_PERSISTENT_RESOURCES_BY_SPEC,
    DRUID_FORM_RESOURCES = DRUID_FORM_RESOURCES,
    DRUID_DEFAULT_RESOURCES = DRUID_DEFAULT_RESOURCES,
    CLASS_RESOURCES_CONFIG = CLASS_RESOURCES_CONFIG,
    SPEC_RESOURCES_CONFIG = SPEC_RESOURCES_CONFIG,

    -- Config UI text defaults
    DEFAULT_RESOURCE_TEXT_ANCHOR = DEFAULT_RESOURCE_TEXT_ANCHOR,
    DEFAULT_RESOURCE_TEXT_X_OFFSET = DEFAULT_RESOURCE_TEXT_X_OFFSET,
    DEFAULT_RESOURCE_TEXT_Y_OFFSET = DEFAULT_RESOURCE_TEXT_Y_OFFSET,
}

-- Every aura-stack family member carries the same two-key colour shape as
-- Holy Power (base, at-max), so its colour def is derived from the family
-- entry instead of restated here: adding a member stays one table entry.
-- Written as explicit statements rather than a loop to add no locals to this
-- chunk (200-local ceiling). RESOURCE_COLOR_DEFS is exported by reference,
-- so mutating it after the export is what every consumer sees.
RESOURCE_COLOR_DEFS[102] = {
    keys = ST._RB.AURA_STACK_RESOURCES[102].colorKeys,
    defaults = ST._RB.AURA_STACK_RESOURCES[102].colorDefaults,
}
RESOURCE_COLOR_DEFS[103] = {
    keys = ST._RB.AURA_STACK_RESOURCES[103].colorKeys,
    defaults = ST._RB.AURA_STACK_RESOURCES[103].colorDefaults,
}
RESOURCE_COLOR_DEFS[104] = {
    keys = ST._RB.AURA_STACK_RESOURCES[104].colorKeys,
    defaults = ST._RB.AURA_STACK_RESOURCES[104].colorDefaults,
}
RESOURCE_COLOR_DEFS[105] = {
    keys = ST._RB.AURA_STACK_RESOURCES[105].colorKeys,
    defaults = ST._RB.AURA_STACK_RESOURCES[105].colorDefaults,
}

-- Direct ST exports for files that import individual constants rather than the _RB table
ST.POWER_ATLAS_TYPES = { [8] = true, [11] = true, [13] = true, [17] = true, [18] = true }
