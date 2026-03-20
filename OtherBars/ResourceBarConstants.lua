--[[
    CooldownCompanion - ResourceBarConstants
    Shared constant tables, color defaults, and power mappings used by both
    ResourceBar.lua (runtime) and ResourceBarPanels.lua (config UI).

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
local MAX_CUSTOM_AURA_BARS = 5
local MW_SPELL_ID = 187880
local RAGING_MAELSTROM_SPELL_ID = 384143
local RESOURCE_MAELSTROM_WEAPON = 100
-- Stagger power type ID: 101 (used inline to stay under Lua 200-local limit)

------------------------------------------------------------------------
-- Default Colors
------------------------------------------------------------------------

local DEFAULT_MW_BASE_COLOR = { 0, 0.5, 1 }
local DEFAULT_MW_OVERLAY_COLOR = { 1, 0.84, 0 }
local DEFAULT_MW_MAX_COLOR = { 0.5, 0.8, 1 }
local DEFAULT_CUSTOM_AURA_MAX_COLOR = { 1, 0.84, 0 }
local DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = { 1, 0.84, 0 }
local DEFAULT_SEG_THRESHOLD_COLOR = { 1, 0.84, 0 }
local DEFAULT_RESOURCE_TEXT_FORMAT = "current"
local DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT = "current_max"
local DEFAULT_RESOURCE_TEXT_FONT = "Friz Quadrata TT"
local DEFAULT_RESOURCE_TEXT_SIZE = 10
local DEFAULT_RESOURCE_TEXT_OUTLINE = "OUTLINE"
local DEFAULT_RESOURCE_TEXT_COLOR = { 1, 1, 1, 1 }
local DEFAULT_CONTINUOUS_TICK_COLOR = { 1, 0.84, 0, 1 }
local DEFAULT_CONTINUOUS_TICK_MODE = "percent"
local DEFAULT_CONTINUOUS_TICK_PERCENT = 50
local DEFAULT_CONTINUOUS_TICK_ABSOLUTE = 50
local DEFAULT_CONTINUOUS_TICK_WIDTH = 2
local INDEPENDENT_NUDGE_BTN_SIZE = 12
local INDEPENDENT_NUDGE_REPEAT_DELAY = 0.5
local INDEPENDENT_NUDGE_REPEAT_INTERVAL = 0.05

------------------------------------------------------------------------
-- Power Colors & Names
------------------------------------------------------------------------

local DEFAULT_POWER_COLORS = {
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
    [18] = "Pain",
    [19] = "Essence",
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
    MAX_CUSTOM_AURA_BARS = MAX_CUSTOM_AURA_BARS,
    MW_SPELL_ID = MW_SPELL_ID,
    RAGING_MAELSTROM_SPELL_ID = RAGING_MAELSTROM_SPELL_ID,
    RESOURCE_MAELSTROM_WEAPON = RESOURCE_MAELSTROM_WEAPON,

    -- Default colors
    DEFAULT_MW_BASE_COLOR = DEFAULT_MW_BASE_COLOR,
    DEFAULT_MW_OVERLAY_COLOR = DEFAULT_MW_OVERLAY_COLOR,
    DEFAULT_MW_MAX_COLOR = DEFAULT_MW_MAX_COLOR,
    DEFAULT_CUSTOM_AURA_MAX_COLOR = DEFAULT_CUSTOM_AURA_MAX_COLOR,
    DEFAULT_RESOURCE_AURA_ACTIVE_COLOR = DEFAULT_RESOURCE_AURA_ACTIVE_COLOR,
    DEFAULT_SEG_THRESHOLD_COLOR = DEFAULT_SEG_THRESHOLD_COLOR,
    DEFAULT_RESOURCE_TEXT_FORMAT = DEFAULT_RESOURCE_TEXT_FORMAT,
    DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT = DEFAULT_CUSTOM_AURA_STACK_TEXT_FORMAT,
    DEFAULT_RESOURCE_TEXT_FONT = DEFAULT_RESOURCE_TEXT_FONT,
    DEFAULT_RESOURCE_TEXT_SIZE = DEFAULT_RESOURCE_TEXT_SIZE,
    DEFAULT_RESOURCE_TEXT_OUTLINE = DEFAULT_RESOURCE_TEXT_OUTLINE,
    DEFAULT_RESOURCE_TEXT_COLOR = DEFAULT_RESOURCE_TEXT_COLOR,
    DEFAULT_CONTINUOUS_TICK_COLOR = DEFAULT_CONTINUOUS_TICK_COLOR,
    DEFAULT_CONTINUOUS_TICK_MODE = DEFAULT_CONTINUOUS_TICK_MODE,
    DEFAULT_CONTINUOUS_TICK_PERCENT = DEFAULT_CONTINUOUS_TICK_PERCENT,
    DEFAULT_CONTINUOUS_TICK_ABSOLUTE = DEFAULT_CONTINUOUS_TICK_ABSOLUTE,
    DEFAULT_CONTINUOUS_TICK_WIDTH = DEFAULT_CONTINUOUS_TICK_WIDTH,
    INDEPENDENT_NUDGE_BTN_SIZE = INDEPENDENT_NUDGE_BTN_SIZE,
    INDEPENDENT_NUDGE_REPEAT_DELAY = INDEPENDENT_NUDGE_REPEAT_DELAY,
    INDEPENDENT_NUDGE_REPEAT_INTERVAL = INDEPENDENT_NUDGE_REPEAT_INTERVAL,

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
    SEGMENTED_TYPES = SEGMENTED_TYPES,
    POWER_ATLAS_INFO = POWER_ATLAS_INFO,
    HIDE_AT_ZERO_ELIGIBLE = HIDE_AT_ZERO_ELIGIBLE,
    RESOURCE_COLOR_DEFS = RESOURCE_COLOR_DEFS,

    -- Class/spec mappings
    CLASS_RESOURCES = CLASS_RESOURCES,
    SPEC_RESOURCES = SPEC_RESOURCES,
    DRUID_FORM_RESOURCES = DRUID_FORM_RESOURCES,
    DRUID_DEFAULT_RESOURCES = DRUID_DEFAULT_RESOURCES,
    CLASS_RESOURCES_CONFIG = CLASS_RESOURCES_CONFIG,
    SPEC_RESOURCES_CONFIG = SPEC_RESOURCES_CONFIG,

    -- Config UI text defaults
    DEFAULT_RESOURCE_TEXT_ANCHOR = DEFAULT_RESOURCE_TEXT_ANCHOR,
    DEFAULT_RESOURCE_TEXT_X_OFFSET = DEFAULT_RESOURCE_TEXT_X_OFFSET,
    DEFAULT_RESOURCE_TEXT_Y_OFFSET = DEFAULT_RESOURCE_TEXT_Y_OFFSET,
}

-- Existing individual exports (used directly by ConfigSettings before _RB existed)
ST.POWER_ATLAS_TYPES = { [8] = true, [11] = true, [13] = true, [17] = true, [18] = true }
ST.CUSTOM_AURA_BAR_BASE = CUSTOM_AURA_BAR_BASE
ST.MAX_CUSTOM_AURA_BARS = MAX_CUSTOM_AURA_BARS
