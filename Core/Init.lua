--[[
    CooldownCompanion - Track spells and items with customizable action bar style panels
    Core/Init.lua: Addon creation, constants, library setup, minimap button
]]

local ADDON_NAME, ST = ...

-- Create the main addon using Ace3
local CooldownCompanion = LibStub("AceAddon-3.0"):NewAddon(ADDON_NAME, "AceConsole-3.0", "AceEvent-3.0")
ST.Addon = CooldownCompanion
_G.CooldownCompanion = CooldownCompanion

-- Expose the private table for other modules
CooldownCompanion.ST = ST

-- Event-driven range check registry (spellID -> true)
CooldownCompanion._rangeCheckSpells = {}

-- Viewer-based aura tracking: spellID → cooldown viewer child frame
CooldownCompanion.viewerAuraFrames = {}
-- Multi-child tracking: spellID → {child1, child2, ...} for duplicate CDM entries
CooldownCompanion.viewerAuraAllChildren = {}

-- Event-driven proc glow tracking: spellID → true when overlay active
-- Replaces per-tick C_SpellActivationOverlay.IsSpellOverlayed polling
-- (that API is AllowedWhenUntainted and cannot be called from addon code in combat)
CooldownCompanion.procOverlaySpells = {}

-- Instance & resting state cache for load conditions
CooldownCompanion._currentInstanceType = "none"  -- "none"|"pvp"|"arena"|"party"|"raid"|"scenario"|"delve"
CooldownCompanion._isResting = false

-- Constants
ST.BUTTON_SIZE = 36
ST.BUTTON_SPACING = 2
ST.DEFAULT_BORDER_SIZE = 1
ST.DEFAULT_STRATA_ORDER = {"cooldown", "assistedHighlight", "chargeText", "procGlow"}

-- Minimap icon setup using LibDataBroker and LibDBIcon
local LDB = LibStub("LibDataBroker-1.1")
local LDBIcon = LibStub("LibDBIcon-1.0")
ST._LDBIcon = LDBIcon

-- LibSharedMedia for font/texture selection
local LSM = LibStub("LibSharedMedia-3.0")

-- Masque skinning support (optional)
local Masque = LibStub("Masque", true)
local MasqueGroups = {} -- Maps groupId -> Masque Group object

CooldownCompanion.Masque = Masque
CooldownCompanion.MasqueGroups = MasqueGroups

local minimapButton = LDB:NewDataObject(ADDON_NAME, {
    type = "launcher",
    text = "Cooldown Companion",
    icon = "Interface\\AddOns\\CooldownCompanion\\Media\\cdcminimap",
    OnClick = function(self, button)
        if button == "LeftButton" then
            CooldownCompanion:ToggleConfig()
        end
    end,
    OnTooltipShow = function(tooltip)
        tooltip:AddLine("Cooldown Companion")
        tooltip:AddLine("|cffeda55fLeft-Click|r to open options", 0.2, 1, 0.2)
    end,
})
ST._minimapButton = minimapButton
