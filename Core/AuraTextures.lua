--[[
    CooldownCompanion - Core/AuraTextures.lua
    Blizzard-first aura texture library and runtime texture rendering
    for aura-capable buttons.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local LSM = LibStub("LibSharedMedia-3.0")

local C_Item_IsUsableItem = C_Item.IsUsableItem
local C_Spell_GetSpellName = C_Spell.GetSpellName
local C_Spell_IsSpellUsable = C_Spell.IsSpellUsable
local GetTime = GetTime
local ipairs = ipairs
local issecretvalue = issecretvalue
local math_abs = math.abs
local math_cos = math.cos
local math_floor = math.floor
local math_max = math.max
local math_min = math.min
local math_pi = math.pi
local math_rad = math.rad
local math_sin = math.sin
local pairs = pairs
local string_find = string.find
local string_format = string.format
local string_gsub = string.gsub
local string_lower = string.lower
local string_trim = strtrim
local string_upper = string.upper
local table_concat = table.concat
local table_insert = table.insert
local table_sort = table.sort
local tonumber = tonumber
local type = type

local SCREEN_LOCATION = Enum and Enum.ScreenLocationType or {}
local LOCATION_CENTER = SCREEN_LOCATION.Center or 0
local LOCATION_LEFT = SCREEN_LOCATION.Left or 1
local LOCATION_RIGHT = SCREEN_LOCATION.Right or 2
local LOCATION_TOP = SCREEN_LOCATION.Top or 3
local LOCATION_BOTTOM = SCREEN_LOCATION.Bottom or 4
local LOCATION_TOPLEFT = SCREEN_LOCATION.TopLeft or 5
local LOCATION_TOPRIGHT = SCREEN_LOCATION.TopRight or 6
local LOCATION_LEFTOUTSIDE = SCREEN_LOCATION.LeftOutside or 7
local LOCATION_RIGHTOUTSIDE = SCREEN_LOCATION.RightOutside or 8
local LOCATION_LEFTRIGHT = SCREEN_LOCATION.LeftRight or 9
local LOCATION_TOPBOTTOM = SCREEN_LOCATION.TopBottom or 10
local LOCATION_LEFTRIGHTOUTSIDE = SCREEN_LOCATION.LeftRightOutside or 11

local FILTER_SYMBOLS = "symbols"
local FILTER_BLIZZARD_PROC = "blizzardProc"
local FILTER_CUSTOM = "custom"
local FILTER_SHAREDMEDIA = "sharedMedia"
local FILTER_FAVORITES = "favorites"
local FILTER_OTHER = "other"
local DEFAULT_TEXTURE_SIZE = 128
local UI_PARENT_NAME = "UIParent"
local NUDGE_BTN_SIZE = 12
local NUDGE_GAP = 2
local NUDGE_REPEAT_DELAY = 0.5
local NUDGE_REPEAT_INTERVAL = 0.05

local LOCATION_LABELS = {
    [LOCATION_CENTER] = "Center",
    [LOCATION_LEFT] = "Left",
    [LOCATION_RIGHT] = "Right",
    [LOCATION_TOP] = "Top",
    [LOCATION_BOTTOM] = "Bottom",
    [LOCATION_TOPLEFT] = "Top Left",
    [LOCATION_TOPRIGHT] = "Top Right",
    [LOCATION_LEFTRIGHT] = "Left + Right",
    [LOCATION_TOPBOTTOM] = "Top + Bottom",
    [LOCATION_LEFTRIGHTOUTSIDE] = "Left + Right Outside",
}

local SHARED_MEDIA_SOURCE_TYPE = "sharedMedia"
local SHARED_MEDIA_TYPE_ORDER = {
    "background",
    "border",
    "statusbar",
}

local SHARED_MEDIA_TYPE_SORT = {
    background = 1,
    border = 2,
    statusbar = 3,
}

local SHARED_MEDIA_TYPE_LABELS = {
    background = "Background",
    border = "Border",
    statusbar = "Status Bar",
}

local TEXTURE_LAYOUT_LABELS = {
    [LOCATION_CENTER] = "Single",
    [LOCATION_LEFTRIGHT] = "Left + Right",
    [LOCATION_TOPBOTTOM] = "Top + Bottom",
}

local LOCATION_DIMENSIONS = {
    [LOCATION_CENTER] = { width = 1.0, height = 1.0, layout = "single", point = "CENTER", relPoint = "CENTER" },
    [LOCATION_LEFT] = { width = 0.5, height = 1.0, layout = "single", point = "RIGHT", relPoint = "CENTER" },
    [LOCATION_RIGHT] = { width = 0.5, height = 1.0, layout = "single", point = "LEFT", relPoint = "CENTER" },
    [LOCATION_TOP] = { width = 1.0, height = 0.5, layout = "single", point = "BOTTOM", relPoint = "CENTER" },
    [LOCATION_BOTTOM] = { width = 1.0, height = 0.5, layout = "single", point = "TOP", relPoint = "CENTER", flipV = true },
    [LOCATION_TOPLEFT] = { width = 0.5, height = 0.5, layout = "single", point = "BOTTOMRIGHT", relPoint = "TOPLEFT" },
    [LOCATION_TOPRIGHT] = { width = 0.5, height = 0.5, layout = "single", point = "BOTTOMLEFT", relPoint = "TOPRIGHT", flipH = true },
    [LOCATION_LEFTOUTSIDE] = { width = 0.5, height = 1.0, layout = "single", point = "RIGHT", relPoint = "LEFT", outside = true },
    [LOCATION_RIGHTOUTSIDE] = { width = 0.5, height = 1.0, layout = "single", point = "LEFT", relPoint = "RIGHT", outside = true, flipH = true },
    [LOCATION_LEFTRIGHT] = { width = 0.5, height = 1.0, layout = "pair_horizontal" },
    [LOCATION_TOPBOTTOM] = { width = 1.0, height = 0.5, layout = "pair_vertical" },
    [LOCATION_LEFTRIGHTOUTSIDE] = { width = 0.5, height = 1.0, layout = "pair_horizontal_outside" },
}

local BUILTIN_LIBRARY = {}

local function AddBuiltinAtlas(categoryKey, atlas, width, height, subtitle, searchText, label)
    if type(atlas) ~= "string" or atlas == "" then
        return
    end

    BUILTIN_LIBRARY[#BUILTIN_LIBRARY + 1] = {
        key = "builtin:" .. categoryKey .. ":" .. atlas,
        label = label or string_trim(atlas),
        categoryKey = categoryKey or FILTER_OTHER,
        sourceType = "atlas",
        sourceValue = atlas,
        width = width,
        height = height,
        subtitle = subtitle,
        searchText = searchText or string_lower((label or atlas) .. " " .. (subtitle or "")),
    }
end

local ARTIFACT_RUNES_SUBTITLE = "Interface/Artifacts/ArtifactRunes"
local ARTIFACT_RUNES_ATLASES = {
    { "Rune-01-dark", 75, 77 },
    { "Rune-01-light", 75, 77 },
    { "Rune-02-dark", 75, 77 },
    { "Rune-02-light", 75, 77 },
    { "Rune-03-dark", 75, 77 },
    { "Rune-03-light", 75, 77 },
    { "Rune-04-dark", 75, 77 },
    { "Rune-04-light", 75, 77 },
    { "Rune-05-dark", 75, 77 },
    { "Rune-05-light", 75, 77 },
    { "Rune-06-dark", 75, 77 },
    { "Rune-06-light", 75, 77 },
    { "Rune-07-dark", 75, 77 },
    { "Rune-07-light", 75, 77 },
    { "Rune-08-dark", 75, 77 },
    { "Rune-08-light", 75, 77 },
    { "Rune-09-dark", 75, 77 },
    { "Rune-09-light", 75, 77 },
    { "Rune-10-dark ", 75, 77, "Rune-10-dark" },
    { "Rune-10-light", 75, 77 },
    { "Rune-11-dark", 75, 77 },
    { "Rune-11-light", 75, 77 },
}

for _, atlasInfo in ipairs(ARTIFACT_RUNES_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        ARTIFACT_RUNES_SUBTITLE,
        string_lower(label .. " artifact runes rune symbol artifacts"),
        label
    )
end

local WOWLABS_SPECTATOR_MODE_SUBTITLE = "Interface/HUD/UIWowlabsSpectatorMode"
local WOWLABS_SPECTATOR_MODE_ATLASES = {
    { "wowlabs-spectatecycling-arrowleft", 58, 55 },
    { "wowlabs-spectatecycling-arrowleft_disabled", 58, 55 },
    { "wowlabs-spectatecycling-arrowleft_hover", 58, 55 },
    { "wowlabs-spectatecycling-arrowleft_pressed", 58, 55 },
    { "wowlabs-spectatecycling-arrowright", 58, 55 },
    { "wowlabs-spectatecycling-arrowright_disabled", 58, 55 },
    { "wowlabs-spectatecycling-arrowright_hover", 58, 55 },
    { "wowlabs-spectatecycling-arrowright_pressed", 58, 55 },
}

for _, atlasInfo in ipairs(WOWLABS_SPECTATOR_MODE_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        WOWLABS_SPECTATOR_MODE_SUBTITLE,
        string_lower(label .. " wowlabs spectator mode arrow symbol"),
        label
    )
end

local UI_QUEST_CROSSHAIR_SUBTITLE = "Interface/Cursor/Crosshair/UIQuestCrosshair2x"
local UI_QUEST_CROSSHAIR_ATLASES = {
    { "Crosshair_Questturnin_128", 128, 128 },
    { "Crosshair_Questturnin_32", 32, 32 },
    { "Crosshair_Questturnin_48", 48, 48 },
    { "Crosshair_Questturnin_64", 64, 64 },
    { "Crosshair_Questturnin_96", 96, 96 },
    { "Crosshair_Quest_128", 128, 128 },
    { "Crosshair_Quest_32", 32, 32 },
    { "Crosshair_Quest_48", 48, 48 },
    { "Crosshair_Quest_64", 64, 64 },
    { "Crosshair_Quest_96", 96, 96 },
    { "Crosshair_unableQuestturnin_128", 128, 128 },
    { "Crosshair_unableQuestturnin_32", 32, 32 },
    { "Crosshair_unableQuestturnin_48", 48, 48 },
    { "Crosshair_unableQuestturnin_64", 64, 64 },
    { "Crosshair_unableQuestturnin_96", 96, 96 },
    { "Crosshair_unableQuest_128", 128, 128 },
    { "Crosshair_unableQuest_32", 32, 32 },
    { "Crosshair_unableQuest_48", 48, 48 },
    { "Crosshair_unableQuest_64", 64, 64 },
    { "Crosshair_unableQuest_96", 96, 96 },
}

for _, atlasInfo in ipairs(UI_QUEST_CROSSHAIR_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        UI_QUEST_CROSSHAIR_SUBTITLE,
        string_lower(label .. " quest crosshair cursor symbol"),
        label
    )
end

local UI_LFG_ROLE_ICONS_SUBTITLE = "Interface/LFGFrame/UILFGPrompts"
local UI_LFG_ROLE_ICONS_ATLASES = {
    { "UI-LFG-RoleIcon-DPS", 70, 70 },
    { "UI-LFG-RoleIcon-Healer", 70, 70 },
    { "UI-LFG-RoleIcon-Tank", 70, 70 },
    { "UI-LFG-RoleIcon-Ready", 70, 70 },
}

for _, atlasInfo in ipairs(UI_LFG_ROLE_ICONS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        UI_LFG_ROLE_ICONS_SUBTITLE,
        string_lower(label .. " lfg role icon symbol ready tank healer dps"),
        label
    )
end

local UI_LFG_ROLE_ICON_BACKGROUNDS_SUBTITLE = "Interface/LFGFrame/UILFGPrompts"
local UI_LFG_ROLE_ICON_BACKGROUNDS_ATLASES = {
    { "UI-LFG-RoleIcon-DPS-Background", 100, 100 },
    { "UI-LFG-RoleIcon-Healer-Background", 100, 100 },
    { "UI-LFG-RoleIcon-Tank-Background", 100, 100 },
}

for _, atlasInfo in ipairs(UI_LFG_ROLE_ICON_BACKGROUNDS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_OTHER,
        atlas,
        width,
        height,
        UI_LFG_ROLE_ICON_BACKGROUNDS_SUBTITLE,
        string_lower(label .. " lfg role icon background"),
        label
    )
end

local UI_CROSSHAIRS_CURSOR_SUBTITLE = "Interface/Cursor/UICrosshairsCursor2x"
local UI_CROSSHAIRS_CURSOR_ATLASES = {
    { "cursor_crosshairs_128", 128, 128 },
    { "cursor_crosshairs_32", 32, 32 },
    { "cursor_crosshairs_48", 48, 48 },
    { "cursor_crosshairs_64", 64, 64 },
    { "cursor_crosshairs_96", 96, 96 },
    { "cursor_unablecrosshairs_128", 128, 128 },
    { "cursor_unablecrosshairs_32", 32, 32 },
    { "cursor_unablecrosshairs_48", 48, 48 },
    { "cursor_unablecrosshairs_64", 64, 64 },
    { "cursor_unablecrosshairs_96", 96, 96 },
}

for _, atlasInfo in ipairs(UI_CROSSHAIRS_CURSOR_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        UI_CROSSHAIRS_CURSOR_SUBTITLE,
        string_lower(label .. " cursor crosshairs symbol"),
        label
    )
end

local UI_COMBAT_TIMELINE_WARNING_ICONS_SUBTITLE = "Interface/HUD/UICombatTimelineWarningIcons"
local UI_COMBAT_TIMELINE_WARNING_ICONS_ATLASES = {
    { "icons_64x64_bleed", 64, 64 },
    { "icons_64x64_curse", 64, 64 },
    { "icons_64x64_damage", 64, 64 },
    { "icons_64x64_deadly", 64, 64 },
    { "icons_64x64_disease", 64, 64 },
    { "icons_64x64_enrage", 64, 64 },
    { "icons_64x64_heal", 64, 64 },
    { "icons_64x64_important", 64, 64 },
    { "icons_64x64_inturrupt", 64, 64 },
    { "icons_64x64_magic", 64, 64 },
    { "icons_64x64_poison", 64, 64 },
    { "icons_64x64_tank", 64, 64 },
    { "icons_16x16_blood", 20, 20 },
    { "icons_16x16_curse", 20, 20 },
    { "icons_16x16_damage", 20, 20 },
    { "icons_16x16_deadly", 20, 20 },
    { "icons_16x16_disease", 20, 20 },
    { "icons_16x16_enrage", 20, 20 },
    { "icons_16x16_heal", 20, 20 },
    { "icons_16x16_important", 20, 20 },
    { "icons_16x16_inturrupt", 20, 20 },
    { "icons_16x16_magic", 20, 20 },
    { "icons_16x16_poison", 20, 20 },
    { "icons_16x16_tank", 20, 20 },
    { "icons_16x16_heroic", 20, 20 },
    { "icons_16x16_mythic", 20, 20 },
    { "icons_16x16_none", 16, 16 },
}

for _, atlasInfo in ipairs(UI_COMBAT_TIMELINE_WARNING_ICONS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        UI_COMBAT_TIMELINE_WARNING_ICONS_SUBTITLE,
        string_lower(label .. " combat timeline warning icon symbol"),
        label
    )
end

local THE_WAR_WITHIN_MAJOR_FACTIONS_ICONS_SUBTITLE = "Interface/MajorFactions/TheWarWithinMajorFactionsIcons"
local THE_WAR_WITHIN_MAJOR_FACTIONS_ICONS_ATLASES = {
    { "majorfactions_icons_candle512", 512, 512 },
    { "majorfactions_icons_flame512", 512, 512 },
    { "majorfactions_icons_storm512", 512, 512 },
    { "majorfactions_icons_web512", 512, 512 },
    { "majorfactions_icons_rocket512", 512, 512 },
    { "majorfactions_icons_stars512", 512, 512 },
    { "majorfactions_icons_Nightfall512", 512, 512 },
    { "majorfactions_icons_Karesh512", 512, 512 },
    { "majorfactions_icons_ManaforgeVandals512", 512, 512 },
}

for _, atlasInfo in ipairs(THE_WAR_WITHIN_MAJOR_FACTIONS_ICONS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_OTHER,
        atlas,
        width,
        height,
        THE_WAR_WITHIN_MAJOR_FACTIONS_ICONS_SUBTITLE,
        string_lower(label .. " major factions war within icon"),
        label
    )
end

local TALENTS_HEROCLASS_RINGS_SUBTITLE = "Interface/AddOns/Blizzard_PlayerSpells/Icons"
local TALENTS_HEROCLASS_RINGS_ATLASES = {
    { "talents-heroclass-ring-selectionpane-gray", 248, 248 },
    { "talents-heroclass-ring-mainpane", 192, 192 },
}

for _, atlasInfo in ipairs(TALENTS_HEROCLASS_RINGS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        TALENTS_HEROCLASS_RINGS_SUBTITLE,
        string_lower(label .. " talents hero class ring symbol"),
        label
    )
end

local STORE_SERVICES_NUMBERS_SUBTITLE = "Interface/Store/ServicesAtlas"
local STORE_SERVICES_NUMBERS_ATLASES = {
    { "services-number-1", 71, 79 },
    { "services-number-2", 71, 79 },
    { "services-number-3", 71, 79 },
    { "services-number-4", 71, 79 },
    { "services-number-5", 71, 79 },
    { "services-number-6", 71, 79 },
    { "services-number-7", 71, 79 },
    { "services-number-8", 71, 79 },
    { "services-number-9", 71, 79 },
}

for _, atlasInfo in ipairs(STORE_SERVICES_NUMBERS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        STORE_SERVICES_NUMBERS_SUBTITLE,
        string_lower(label .. " services number symbol"),
        label
    )
end

local PVP_PRESTIGE_ICONS_SUBTITLE = "Interface/PVPFrame/PvPPrestigeIcons"
local PVP_PRESTIGE_ICONS_ATLASES = {
    { "honorsystem-icon-prestige-1", 128, 128 },
    { "honorsystem-icon-prestige-10", 128, 128 },
    { "honorsystem-icon-prestige-11", 128, 128 },
    { "honorsystem-icon-prestige-2", 128, 128 },
    { "honorsystem-icon-prestige-3", 128, 128 },
    { "honorsystem-icon-prestige-4", 128, 128 },
    { "honorsystem-icon-prestige-5", 128, 128 },
    { "honorsystem-icon-prestige-6", 128, 128 },
    { "honorsystem-icon-prestige-7", 128, 128 },
    { "honorsystem-icon-prestige-8", 128, 128 },
    { "honorsystem-icon-prestige-9", 128, 128 },
}

for _, atlasInfo in ipairs(PVP_PRESTIGE_ICONS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_OTHER,
        atlas,
        width,
        height,
        PVP_PRESTIGE_ICONS_SUBTITLE,
        string_lower(label .. " pvp prestige icon"),
        label
    )
end

AddBuiltinAtlas(
    FILTER_OTHER,
    "Start-VersusSplash",
    217,
    212,
    "Interface/PetBattles/PetBattleHUDAtlas",
    string_lower("Start-VersusSplash versus splash other"),
    "Start-VersusSplash"
)

local NAMEPLATE_ELITE_ICONS_SUBTITLE = "Interface/TargetingFrame/UI-Nameplates"
local NAMEPLATE_ELITE_ICONS_ATLASES = {
    { "nameplates-icon-elite-gold", 32, 32 },
    { "nameplates-icon-elite-silver", 32, 32 },
    { "nameplates-icon-rareelite", 32, 32 },
}

for _, atlasInfo in ipairs(NAMEPLATE_ELITE_ICONS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_SYMBOLS,
        atlas,
        width,
        height,
        NAMEPLATE_ELITE_ICONS_SUBTITLE,
        string_lower(label .. " elite rare nameplate symbol"),
        label
    )
end

local MOBILE_APP_ICONS_SUBTITLE = "Interface/Garrison/MobileAppIcons"
local MOBILE_APP_ICONS_ATLASES = {
    { "legionmission-map-orderhall-deathknight", 99, 66 },
    { "legionmission-map-orderhall-demonhunter", 99, 66 },
    { "legionmission-map-orderhall-druid", 99, 66 },
    { "legionmission-map-orderhall-glow", 142, 109 },
    { "legionmission-map-orderhall-hunter", 99, 66 },
    { "legionmission-map-orderhall-mage", 99, 66 },
    { "legionmission-map-orderhall-monk", 99, 66 },
    { "legionmission-map-orderhall-paladin", 99, 66 },
    { "legionmission-map-orderhall-priest", 99, 66 },
    { "legionmission-map-orderhall-rogue", 99, 66 },
    { "legionmission-map-orderhall-shaman", 99, 66 },
    { "legionmission-map-orderhall-warlock", 99, 66 },
    { "legionmission-map-orderhall-warrior", 99, 66 },
    { "legionmission-map-orderhall-textglow", 122, 22 },
    { "Mobile-BonusIcon", 128, 128 },
    { "Mobile-CombatBadgeIcon", 128, 128 },
    { "Mobile-CombatIcon", 128, 128 },
    { "Mobile-LegendaryQuestIcon", 128, 128 },
    { "Mobile-QuestIcon", 128, 128 },
    { "Mobile-TreasureIcon", 128, 128 },
    { "Mobile-CombatIcon-Desaturated", 128, 128 },
    { "Mobile-BonusIcon-Desaturated", 128, 128 },
    { "Mobile-TreasureIcon-Desaturated", 128, 128 },
    { "Mobile-QuestIcon-Desaturated", 128, 128 },
    { "Mobile-LegendaryQuestIcon-Desaturated", 128, 128 },
    { "Mobile-Alchemy", 128, 128 },
    { "Mobile-Archeology", 128, 128 },
    { "Mobile-Blacksmithing", 128, 128 },
    { "Mobile-Cooking", 128, 128 },
    { "Mobile-Enchanting", 128, 128 },
    { "Mobile-Enginnering", 128, 128 },
    { "Mobile-FirstAid", 128, 128 },
    { "Mobile-Fishing", 128, 128 },
    { "Mobile-Herbalism", 128, 128 },
    { "Mobile-Inscription", 128, 128 },
    { "Mobile-Jewelcrafting", 128, 128 },
    { "Mobile-Leatherworking", 128, 128 },
    { "Mobile-MechanicIcon-Curse", 128, 128 },
    { "Mobile-MechanicIcon-Disorienting", 128, 128 },
    { "Mobile-MechanicIcon-Lethal", 128, 128 },
    { "Mobile-MechanicIcon-Slowing", 128, 128 },
    { "Mobile-Mining", 128, 128 },
    { "Mobile-Pets", 128, 128 },
    { "Mobile-Skinning", 128, 128 },
    { "Mobile-Tailoring", 128, 128 },
    { "Mobile-MechanicIcon-Powerful", 128, 128 },
}

for _, atlasInfo in ipairs(MOBILE_APP_ICONS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_OTHER,
        atlas,
        width,
        height,
        MOBILE_APP_ICONS_SUBTITLE,
        string_lower(label .. " mobile app icon other"),
        label
    )
end

local MAJOR_FACTIONS_ICONS_SUBTITLE = "Interface/MajorFactions/MajorFactionsIcons"
local MAJOR_FACTIONS_ICONS_ATLASES = {
    { "majorfaction-celebration-toastbg", 275, 77 },
    { "majorfaction-celebration-centaur", 235, 110 },
    { "majorfaction-celebration-valdrakken", 235, 110 },
    { "majorfaction-celebration-bottomglowline", 266, 19 },
    { "majorfaction-celebration-expedition", 235, 110 },
    { "majorfaction-celebration-content-ring", 128, 128 },
    { "majorfaction-celebration-tuskarr", 235, 110 },
    { "majorfaction-celebration-niffen", 235, 110 },
}

for _, atlasInfo in ipairs(MAJOR_FACTIONS_ICONS_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_OTHER,
        atlas,
        width,
        height,
        MAJOR_FACTIONS_ICONS_SUBTITLE,
        string_lower(label .. " major factions icon other"),
        label
    )
end

AddBuiltinAtlas(
    FILTER_OTHER,
    "1f604",
    72,
    72,
    "Interface/DougTestAtlas/DougTestAtlas",
    string_lower("1f604 other"),
    "1f604"
)

local PLUNDERSTORM_MAP_ATLASES_SUBTITLE = "Interface/HUD/UIMapDropPlunderstorm"
local PLUNDERSTORM_MAP_ATLASES = {
    { "plunderstorm-map-iconGreenSelected", 85, 85 },
    { "plunderstorm-map-iconGreen-pressed", 85, 85 },
    { "plunderstorm-map-zoneSelected-hover", 183, 183 },
    { "plunderstorm-map-zoneSelected", 183, 183 },
    { "plunderstorm-map-iconRed-hover", 85, 85 },
    { "plunderstorm-map-iconRedSelected", 85, 85 },
    { "plunderstorm-map-iconYellow", 85, 85 },
    { "plunderstorm-map-iconYellowSelected", 85, 85 },
    { "plunderstorm-map-iconYellowSelected-hover", 85, 85 },
}

for _, atlasInfo in ipairs(PLUNDERSTORM_MAP_ATLASES) do
    local atlas = atlasInfo[1]
    local width = atlasInfo[2]
    local height = atlasInfo[3]
    local label = atlasInfo[4] or string_trim(atlas)
    AddBuiltinAtlas(
        FILTER_OTHER,
        atlas,
        width,
        height,
        PLUNDERSTORM_MAP_ATLASES_SUBTITLE,
        string_lower(label .. " plunderstorm map other"),
        label
    )
end

local FILTER_OPTIONS = {
    [FILTER_SYMBOLS] = "Symbols",
    [FILTER_BLIZZARD_PROC] = "Blizzard Proc Overlays",
    [FILTER_CUSTOM] = "Custom",
    [FILTER_SHAREDMEDIA] = "SharedMedia",
    [FILTER_FAVORITES] = "Favorites",
    [FILTER_OTHER] = "Other",
}

local LOCATION_ORDER = {
    LOCATION_CENTER,
    LOCATION_LEFTRIGHT,
    LOCATION_TOPBOTTOM,
}

local DEFAULT_TEXTURE_PAIR_SPACING = 0
local LEGACY_OUTSIDE_PAIR_SPACING = 0.15
local MIN_TEXTURE_PAIR_SPACING = -5
local MAX_TEXTURE_PAIR_SPACING = 5
local MIN_TEXTURE_ROTATION = -180
local MAX_TEXTURE_ROTATION = 180
local MIN_TEXTURE_STRETCH = -0.75
local MAX_TEXTURE_STRETCH = 2
local TEXTURE_INDICATOR_EFFECT_NONE = "none"
local TEXTURE_INDICATOR_EFFECT_PULSE = "pulse"
local TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT = "colorShift"
local TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND = "shrinkExpand"
local TEXTURE_INDICATOR_EFFECT_BOUNCE = "bounce"
local MIN_TEXTURE_INDICATOR_SPEED = 0.1
local MAX_TEXTURE_INDICATOR_SPEED = 2.0
local DEFAULT_TEXTURE_INDICATOR_SPEED = 0.5
local DEFAULT_TEXTURE_PULSE_ALPHA = 0.45
local DEFAULT_TEXTURE_SHRINK_SCALE = 0.82
local DEFAULT_TEXTURE_BOUNCE_PIXELS = 18

local TEXTURE_INDICATOR_SECTION_ORDER = {
    "proc",
    "aura",
    "pandemic",
    "ready",
    "unusable",
}

local TEXTURE_INDICATOR_DEFAULTS = {
    proc = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_PULSE,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 1, 1, 1 },
        combatOnly = false,
    },
    aura = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 0.84, 0, 1 },
        combatOnly = false,
        invert = false,
    },
    pandemic = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 0.5, 0, 1 },
        combatOnly = false,
    },
    ready = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_BOUNCE,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 0.2, 1, 0.2, 1 },
        combatOnly = false,
    },
    unusable = {
        enabled = false,
        effectType = TEXTURE_INDICATOR_EFFECT_PULSE,
        speed = DEFAULT_TEXTURE_INDICATOR_SPEED,
        color = { 1, 0.35, 0.35, 1 },
        combatOnly = false,
    },
}

local TRIGGER_CONDITION_LABELS = {
    cooldownActive = "Cooldown",
    auraActive = "Aura",
    procActive = "Proc",
    rangeActive = "Range",
    usable = "Usable",
    chargesRecharging = "Charge Recharge",
    chargeState = "Charge State",
    countTextActive = "Count Text",
    countState = "Display Count",
}

local TRIGGER_EXPECTED_LABELS = {
    cooldownActive = {
        ["true"] = "On Cooldown",
        ["false"] = "Off Cooldown",
    },
    auraActive = {
        ["true"] = "Active",
        ["false"] = "Inactive",
    },
    procActive = {
        ["true"] = "Active",
        ["false"] = "Inactive",
    },
    rangeActive = {
        ["true"] = "In Range",
        ["false"] = "Out of Range",
    },
    usable = {
        ["true"] = "Usable",
        ["false"] = "Unusable",
    },
    chargesRecharging = {
        ["true"] = "Recharging",
        ["false"] = "Not Recharging",
    },
    countTextActive = {
        ["true"] = "Shown",
        ["false"] = "Hidden",
    },
}

local TRIGGER_STATE_LABELS = {
    chargeState = {
        full = "Full",
        missing = "Missing",
        zero = "Zero",
    },
    countState = {
        full = "Full",
        missing = "Missing",
        zero = "Zero",
    },
}

local TRIGGER_CONDITION_ORDERS = {
    spell = { "cooldownActive", "auraActive", "procActive", "rangeActive", "usable" },
    passiveSpell = { "auraActive", "procActive" },
    item = { "cooldownActive", "rangeActive", "usable" },
}

local function CopyColor(color)
    if type(color) ~= "table" then
        return nil
    end
    return { color[1] or 1, color[2] or 1, color[3] or 1, color[4] or 1 }
end

local function Clamp(value, minValue, maxValue)
    if type(value) ~= "number" then
        return minValue
    end
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function NormalizeBlendMode(mode)
    local normalized = type(mode) == "string" and string_upper(mode) or "ADD"
    if normalized == "BLEND" or normalized == "ADD" then
        return normalized
    end
    return "ADD"
end

local function NormalizeTextureIndicatorEffect(effectType)
    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE
        or effectType == TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT
        or effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND
        or effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        return effectType
    end
    return TEXTURE_INDICATOR_EFFECT_NONE
end

local function NormalizeTextureIndicatorSection(sectionKey, sectionData)
    local defaults = TEXTURE_INDICATOR_DEFAULTS[sectionKey]
    if not defaults then
        return nil
    end

    sectionData = type(sectionData) == "table" and sectionData or {}
    sectionData.enabled = sectionData.enabled == true
    sectionData.effectType = NormalizeTextureIndicatorEffect(sectionData.effectType or defaults.effectType)
    sectionData.speed = Clamp(tonumber(sectionData.speed) or defaults.speed or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    sectionData.color = CopyColor(sectionData.color) or CopyColor(defaults.color) or { 1, 1, 1, 1 }
    sectionData.combatOnly = sectionData.combatOnly == true
    if defaults.invert ~= nil then
        sectionData.invert = sectionData.invert == true
    else
        sectionData.invert = nil
    end

    return sectionData
end

local function NormalizeTextureIndicatorStore(styleTable)
    if type(styleTable) ~= "table" then
        return nil
    end

    if type(styleTable.textureIndicators) ~= "table" then
        styleTable.textureIndicators = {}
    end

    local store = styleTable.textureIndicators
    for _, sectionKey in ipairs(TEXTURE_INDICATOR_SECTION_ORDER) do
        store[sectionKey] = NormalizeTextureIndicatorSection(sectionKey, store[sectionKey])
    end

    return store
end

local function GetTriggerConditionOrderForButtonData(buttonData)
    if type(buttonData) ~= "table" then
        return TRIGGER_CONDITION_ORDERS.spell
    end

    if buttonData.type == "item" or buttonData.type == "equipitem" then
        local order = { "cooldownActive", "rangeActive", "usable" }
        if buttonData.hasCharges == true then
            order[#order + 1] = "chargesRecharging"
            order[#order + 1] = "chargeState"
        end
        return order
    end

    if buttonData.type == "spell" and buttonData.isPassive == true then
        return { "auraActive", "procActive" }
    end

    local order = { "cooldownActive", "auraActive", "procActive", "rangeActive", "usable" }
    if buttonData.hasCharges == true then
        order[#order + 1] = "chargesRecharging"
        order[#order + 1] = "chargeState"
    elseif CooldownCompanion.HasNonChargeCountTextBehavior
            and CooldownCompanion.HasNonChargeCountTextBehavior(buttonData) then
        order[#order + 1] = "countTextActive"
        if buttonData._hasDisplayCount == true or buttonData._displayCountFamily == true then
            order[#order + 1] = "countState"
        end
    end
    return order
end

local function NormalizeTriggerConditionKey(buttonData, conditionKey)
    local order = GetTriggerConditionOrderForButtonData(buttonData)
    if conditionKey == nil then
        return order[1]
    end

    for _, validKey in ipairs(order) do
        if conditionKey == validKey then
            return conditionKey
        end
    end
    return nil
end

local function NormalizeTriggerStateKey(conditionKey, stateKey)
    if not TRIGGER_STATE_LABELS[conditionKey] then
        return nil
    end

    for _, validKey in ipairs({ "full", "missing", "zero" }) do
        if stateKey == validKey then
            return validKey
        end
    end

    return "full"
end


local VALID_POINTS = {
    TOPLEFT = true,
    TOP = true,
    TOPRIGHT = true,
    LEFT = true,
    CENTER = true,
    RIGHT = true,
    BOTTOMLEFT = true,
    BOTTOM = true,
    BOTTOMRIGHT = true,
}

local function NormalizeAnchorPoint(anchor)
    if type(anchor) ~= "string" or not VALID_POINTS[anchor] then
        return "CENTER"
    end
    return anchor
end

local function NormalizeTextureLayout(locationType)
    if LOCATION_DIMENSIONS[locationType] then
        if locationType == LOCATION_LEFTRIGHTOUTSIDE then
            return LOCATION_LEFTRIGHT, LEGACY_OUTSIDE_PAIR_SPACING
        end
        return locationType, DEFAULT_TEXTURE_PAIR_SPACING
    end
    if locationType == LOCATION_LEFTRIGHT then
        return LOCATION_LEFTRIGHT, DEFAULT_TEXTURE_PAIR_SPACING
    end
    if locationType == LOCATION_TOPBOTTOM then
        return LOCATION_TOPBOTTOM, DEFAULT_TEXTURE_PAIR_SPACING
    end
    if locationType == LOCATION_LEFTRIGHTOUTSIDE then
        return LOCATION_LEFTRIGHT, LEGACY_OUTSIDE_PAIR_SPACING
    end
    return LOCATION_CENTER, DEFAULT_TEXTURE_PAIR_SPACING
end

local function GetStretchMultiplier(value)
    return math_max(0.05, 1 + (tonumber(value) or 0))
end

local function RotateOffset(x, y, radians)
    if not radians or radians == 0 then
        return x, y
    end

    local cosAngle = math_cos(radians)
    local sinAngle = math_sin(radians)
    return (x * cosAngle) - (y * sinAngle), (x * sinAngle) + (y * cosAngle)
end

local function BuildLocationSubtitle(locationType)
    if LOCATION_LABELS[locationType] then
        return LOCATION_LABELS[locationType]
    end

    local normalizedLocationType = NormalizeTextureLayout(locationType)
    return TEXTURE_LAYOUT_LABELS[normalizedLocationType] or LOCATION_LABELS[normalizedLocationType] or "Center"
end

local function NormalizeAuraTextureSourceType(sourceType)
    if sourceType == "atlas" or sourceType == "file" or sourceType == SHARED_MEDIA_SOURCE_TYPE then
        return sourceType
    end
    return nil
end

local function NormalizeSharedMediaType(mediaType)
    if mediaType == "background" or mediaType == "border" or mediaType == "statusbar" then
        return mediaType
    end
    return nil
end

local function BuildSharedMediaLibraryKey(mediaType, mediaKey)
    local normalizedType = NormalizeSharedMediaType(mediaType)
    if not normalizedType or type(mediaKey) ~= "string" or mediaKey == "" then
        return nil
    end

    return "lsm:" .. normalizedType .. ":" .. mediaKey
end

local function ParseSharedMediaLibraryKey(libraryKey)
    if type(libraryKey) ~= "string" then
        return nil, nil
    end

    local mediaType, mediaKey = libraryKey:match("^lsm:([^:]+):(.+)$")
    mediaType = NormalizeSharedMediaType(mediaType)
    if not mediaType or type(mediaKey) ~= "string" or mediaKey == "" then
        return nil, nil
    end

    return mediaType, mediaKey
end

local function BuildSharedMediaLabel(mediaKey, savedLabel)
    if type(savedLabel) == "string" and savedLabel ~= "" then
        return savedLabel
    end
    if type(mediaKey) == "string" and mediaKey ~= "" then
        return mediaKey
    end
    return "SharedMedia Texture"
end

local function BuildSharedMediaEntry(mediaType, mediaKey, savedLabel, options)
    options = type(options) == "table" and options or {}

    local normalizedType = NormalizeSharedMediaType(mediaType)
    if not normalizedType or type(mediaKey) ~= "string" or mediaKey == "" then
        return nil
    end

    local label = BuildSharedMediaLabel(mediaKey, savedLabel)
    local isFavorited = options.isFavorited == true
    local isMissing = options.isMissing == true
    local categoryKey = options.categoryKey or FILTER_SHAREDMEDIA
    local typeLabel = SHARED_MEDIA_TYPE_LABELS[normalizedType] or normalizedType
    local stateLabel = isMissing and "Missing or unavailable"
        or (isFavorited and "Favorited" or "SharedMedia")
    local subtitle = typeLabel .. "  |  " .. stateLabel

    return {
        key = BuildSharedMediaLibraryKey(normalizedType, mediaKey),
        libraryKey = BuildSharedMediaLibraryKey(normalizedType, mediaKey),
        label = label,
        categoryKey = categoryKey,
        category = FILTER_OPTIONS[categoryKey],
        sourceType = SHARED_MEDIA_SOURCE_TYPE,
        sourceValue = mediaKey,
        mediaType = normalizedType,
        layoutAgnostic = true,
        color = { 1, 1, 1, 1 },
        blendMode = "BLEND",
        subtitle = subtitle,
        searchText = string_lower(label .. " " .. mediaKey .. " " .. normalizedType .. " " .. stateLabel),
        favoriteOriginCategoryKey = FILTER_SHAREDMEDIA,
        isMissingSharedMedia = isMissing,
        canFavorite = not isFavorited and not isMissing,
        canRemoveFavorite = isFavorited,
    }
end

local function ReadSharedMediaFavoriteRecord(value)
    if type(value) ~= "table" then
        return nil, nil, nil
    end

    local mediaType = NormalizeSharedMediaType(value.mediaType)
    local mediaKey = value.key or value.mediaKey or value.sourceValue
    mediaKey = type(mediaKey) == "string" and string_trim(mediaKey) or nil
    local label = type(value.label) == "string" and value.label or nil
    if not mediaType or not mediaKey or mediaKey == "" then
        return nil, nil, nil
    end

    return mediaType, mediaKey, label
end

local function BuildAuraTextureFavoriteKey(entry)
    if type(entry) ~= "table" then
        return nil
    end

    local favoriteKey = entry.libraryKey or entry.key
    if type(favoriteKey) == "string" and favoriteKey ~= "" then
        return favoriteKey
    end

    return nil
end

local function BuildAuraTextureFavoriteRecord(entry)
    local favoriteKey = BuildAuraTextureFavoriteKey(entry)
    local originCategoryKey = type(entry) == "table" and entry.favoriteOriginCategoryKey or nil
    if not favoriteKey or not FILTER_OPTIONS[originCategoryKey] or originCategoryKey == FILTER_FAVORITES then
        return nil
    end

    return {
        favoriteKey = favoriteKey,
        label = type(entry.label) == "string" and entry.label or tostring(entry.sourceValue),
        originCategoryKey = originCategoryKey,
        sourceType = entry.sourceType,
        sourceValue = entry.sourceValue,
        mediaType = entry.mediaType,
        layoutAgnostic = entry.layoutAgnostic == true,
        locationType = entry.locationType,
        width = tonumber(entry.width) or nil,
        height = tonumber(entry.height) or nil,
        color = CopyColor(entry.color) or { 1, 1, 1, 1 },
        blendMode = NormalizeBlendMode(entry.blendMode),
        scale = tonumber(entry.scale) or nil,
        subtitle = type(entry.subtitle) == "string" and entry.subtitle or nil,
        searchText = type(entry.searchText) == "string" and entry.searchText or nil,
    }
end

local function ReadAuraTextureFavoriteRecord(value)
    if type(value) ~= "table" then
        return nil
    end

    local favoriteKey = value.favoriteKey or value.key or value.libraryKey
    local originCategoryKey = FILTER_OPTIONS[value.originCategoryKey] and value.originCategoryKey or FILTER_OTHER
    local sourceType = NormalizeAuraTextureSourceType(value.sourceType)
    local sourceValue = value.sourceValue
    local mediaType = sourceType == SHARED_MEDIA_SOURCE_TYPE
        and NormalizeSharedMediaType(value.mediaType)
        or nil

    if type(favoriteKey) ~= "string" or favoriteKey == "" or not sourceType or sourceValue == nil then
        return nil
    end
    if sourceType == SHARED_MEDIA_SOURCE_TYPE and not mediaType then
        return nil
    end

    return {
        favoriteKey = favoriteKey,
        label = type(value.label) == "string" and value.label or tostring(sourceValue),
        originCategoryKey = originCategoryKey,
        sourceType = sourceType,
        sourceValue = sourceValue,
        mediaType = mediaType,
        layoutAgnostic = value.layoutAgnostic ~= false,
        locationType = value.locationType,
        width = tonumber(value.width) or nil,
        height = tonumber(value.height) or nil,
        color = CopyColor(value.color) or { 1, 1, 1, 1 },
        blendMode = NormalizeBlendMode(value.blendMode),
        scale = tonumber(value.scale) or nil,
        subtitle = type(value.subtitle) == "string" and value.subtitle or nil,
        searchText = type(value.searchText) == "string" and value.searchText or nil,
    }
end

local function BuildFavoriteAuraTextureEntry(value)
    local record = ReadAuraTextureFavoriteRecord(value)
    if not record then
        return nil
    end

    local isMissingSharedMedia = false
    local subtitle = record.subtitle
    if record.sourceType == SHARED_MEDIA_SOURCE_TYPE then
        local typeLabel = SHARED_MEDIA_TYPE_LABELS[record.mediaType] or record.mediaType
        isMissingSharedMedia = LSM:Fetch(record.mediaType, record.sourceValue, true) == nil
        local stateLabel = isMissingSharedMedia and "Missing or unavailable" or "Favorite"
        subtitle = typeLabel .. "  |  " .. stateLabel
    elseif subtitle and subtitle ~= "" then
        subtitle = subtitle .. "  |  " .. (FILTER_OPTIONS[record.originCategoryKey] or FILTER_OPTIONS[FILTER_OTHER])
    else
        subtitle = FILTER_OPTIONS[record.originCategoryKey] or FILTER_OPTIONS[FILTER_OTHER]
    end

    return {
        key = record.favoriteKey,
        libraryKey = record.favoriteKey,
        label = record.label,
        categoryKey = FILTER_FAVORITES,
        category = FILTER_OPTIONS[FILTER_FAVORITES],
        favoriteOriginCategoryKey = record.originCategoryKey,
        sourceType = record.sourceType,
        sourceValue = record.sourceValue,
        mediaType = record.mediaType,
        layoutAgnostic = record.layoutAgnostic,
        locationType = record.locationType,
        width = record.width,
        height = record.height,
        color = CopyColor(record.color) or { 1, 1, 1, 1 },
        blendMode = NormalizeBlendMode(record.blendMode),
        scale = record.scale,
        subtitle = subtitle,
        searchText = record.searchText
            or string_lower(record.label .. " " .. tostring(record.sourceValue) .. " " .. subtitle .. " favorite"),
        canFavorite = false,
        canRemoveFavorite = true,
        isFavoriteRecord = true,
        isMissingSharedMedia = isMissingSharedMedia,
    }
end

local function MigrateLegacySharedMediaFavorites(store)
    local favorites = store and store.textureFavorites or nil
    local legacyFavorites = store and store.sharedMediaFavorites or nil
    if type(favorites) ~= "table" or type(legacyFavorites) ~= "table" then
        return
    end

    for storedKey, storedValue in pairs(legacyFavorites) do
        local mediaType, mediaKey, savedLabel = ReadSharedMediaFavoriteRecord(storedValue)
        local libraryKey = BuildSharedMediaLibraryKey(mediaType, mediaKey)
        if libraryKey then
            local favoriteEntry = BuildSharedMediaEntry(mediaType, mediaKey, savedLabel, {
                categoryKey = FILTER_FAVORITES,
                isFavorited = true,
                isMissing = LSM:Fetch(mediaType, mediaKey, true) == nil,
            })
            if favoriteEntry then
                favoriteEntry.favoriteOriginCategoryKey = FILTER_SHAREDMEDIA
                favorites[libraryKey] = favorites[libraryKey] or BuildAuraTextureFavoriteRecord(favoriteEntry)
            end
        end

        legacyFavorites[storedKey] = nil
    end

    store.sharedMediaFavorites = nil
end

local GetAuraTextureFavoriteStore

local function IsLegacyProcFavoriteKey(favoriteKey)
    return type(favoriteKey) == "string" and string_find(favoriteKey, "^favorite:legacy%-proc:", 1, false) ~= nil
end

local function CleanupLegacyRecentArtifacts(store)
    if type(store) ~= "table" then
        return
    end

    if type(store.textureFavorites) == "table" then
        for favoriteKey, favoriteValue in pairs(store.textureFavorites) do
            local favoriteRecord = ReadAuraTextureFavoriteRecord(favoriteValue)
            if IsLegacyProcFavoriteKey(favoriteKey)
                or (favoriteRecord and IsLegacyProcFavoriteKey(favoriteRecord.favoriteKey)) then
                store.textureFavorites[favoriteKey] = nil
            end
        end
    end

    store.recentProcOverlays = nil
end

function CooldownCompanion:NormalizeAuraTextureLibraryStore(store)
    if type(store) ~= "table" then
        return nil
    end

    if type(store.customTextures) ~= "table" then
        store.customTextures = {}
    end

    if type(store.textureFavorites) ~= "table" then
        store.textureFavorites = {}
    end

    MigrateLegacySharedMediaFavorites(store)
    CleanupLegacyRecentArtifacts(store)
    return store
end

GetAuraTextureFavoriteStore = function(store)
    local normalizedStore = CooldownCompanion:NormalizeAuraTextureLibraryStore(store)
    return normalizedStore and normalizedStore.textureFavorites or nil
end

local function ApplyFavoriteStateToEntry(entry, favorites)
    if type(entry) ~= "table" then
        return nil
    end

    local favoriteKey = BuildAuraTextureFavoriteKey(entry)
    local isFavorited = favoriteKey ~= nil and type(favorites) == "table" and favorites[favoriteKey] ~= nil
    entry.canFavorite = not isFavorited
    entry.canRemoveFavorite = isFavorited
    entry.isFavoriteRecord = nil

    if entry.sourceType == SHARED_MEDIA_SOURCE_TYPE then
        local typeLabel = SHARED_MEDIA_TYPE_LABELS[entry.mediaType] or entry.mediaType
        local stateLabel = entry.isMissingSharedMedia and "Missing or unavailable"
            or (isFavorited and "Favorited" or "SharedMedia")
        entry.subtitle = typeLabel .. "  |  " .. stateLabel
        entry.searchText = string_lower(entry.label .. " " .. tostring(entry.sourceValue) .. " " .. tostring(entry.mediaType) .. " " .. stateLabel)
    end

    return entry
end

function CooldownCompanion:ResolveAuraTextureAsset(sourceType, sourceValue, mediaType)
    local normalizedSourceType = NormalizeAuraTextureSourceType(sourceType)

    if normalizedSourceType == "atlas" then
        if type(sourceValue) == "string" and C_Texture.GetAtlasExists(sourceValue) then
            return "atlas", sourceValue
        end
        return nil
    end

    if normalizedSourceType == "file" then
        if sourceValue ~= nil then
            return "file", sourceValue
        end
        return nil
    end

    if normalizedSourceType == SHARED_MEDIA_SOURCE_TYPE then
        local normalizedMediaType = NormalizeSharedMediaType(mediaType)
        if not normalizedMediaType or type(sourceValue) ~= "string" or sourceValue == "" then
            return nil
        end

        local resolvedPath = LSM:Fetch(normalizedMediaType, sourceValue, true)
        if type(resolvedPath) == "string" and resolvedPath ~= "" then
            return "file", resolvedPath
        end
        return nil
    end

    return nil
end

local function NormalizeAuraTextureSettings(settings)
    if type(settings) ~= "table" then
        return nil
    end

    settings.sourceType = NormalizeAuraTextureSourceType(settings.sourceType)
    settings.label = type(settings.label) == "string" and settings.label or nil
    settings.sourceValue = settings.sourceValue
    settings.enabled = settings.sourceType ~= nil and settings.sourceValue ~= nil
    settings.mode = settings.mode == "replace" and "replace" or "overlay"
    settings.scale = Clamp(settings.scale or 1, 0.25, 4)
    settings.alpha = Clamp(settings.alpha or 1, 0.05, 1)
    settings.blendMode = NormalizeBlendMode(settings.blendMode)
    settings.rotation = Clamp(tonumber(settings.rotation) or 0, MIN_TEXTURE_ROTATION, MAX_TEXTURE_ROTATION)
    settings.stretchX = Clamp(tonumber(settings.stretchX) or 0, MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH)
    settings.stretchY = Clamp(tonumber(settings.stretchY) or 0, MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH)
    settings.point = NormalizeAnchorPoint(settings.point or settings.anchor)
    settings.relativePoint = NormalizeAnchorPoint(settings.relativePoint)
    settings.relativeTo = UI_PARENT_NAME
    settings.x = tonumber(settings.x or settings.xOffset) or 0
    settings.y = tonumber(settings.y or settings.yOffset) or 0
    settings.anchor = nil
    settings.mediaType = settings.sourceType == SHARED_MEDIA_SOURCE_TYPE
        and NormalizeSharedMediaType(settings.mediaType)
        or nil
    settings.xOffset = nil
    settings.yOffset = nil
    settings.color = CopyColor(settings.color) or { 1, 1, 1, 1 }
    local normalizedLocationType, defaultPairSpacing = NormalizeTextureLayout(settings.locationType)
    settings.locationType = normalizedLocationType
    local rawPairSpacing = tonumber(settings.pairSpacing)
    if rawPairSpacing == nil then
        settings.pairSpacing = defaultPairSpacing
    else
        settings.pairSpacing = Clamp(rawPairSpacing, MIN_TEXTURE_PAIR_SPACING, MAX_TEXTURE_PAIR_SPACING)
    end
    settings.width = tonumber(settings.width) or nil
    settings.height = tonumber(settings.height) or nil

    return settings
end

local function AreTextureNumbersEqual(a, b)
    if a == nil and b == nil then
        return true
    end
    if type(a) ~= "number" or type(b) ~= "number" then
        return false
    end
    return math_abs(a - b) <= 0.0001
end

local function AreTextureColorsEqual(a, b)
    local left = CopyColor(a) or { 1, 1, 1, 1 }
    local right = CopyColor(b) or { 1, 1, 1, 1 }
    for index = 1, 4 do
        if not AreTextureNumbersEqual(left[index] or 1, right[index] or 1) then
            return false
        end
    end
    return true
end

function CooldownCompanion:DoesAuraTexturePickerEntryMatchSelection(entry, selection)
    if type(entry) ~= "table" or type(selection) ~= "table" then
        return false
    end

    local selectionLibraryKey = selection.libraryKey
    if type(selectionLibraryKey) == "string" and selectionLibraryKey ~= "" then
        return entry.key == selectionLibraryKey
    end

    if entry.sourceType ~= selection.sourceType or entry.sourceValue ~= selection.sourceValue then
        return false
    end

    if entry.sourceType == SHARED_MEDIA_SOURCE_TYPE and entry.mediaType ~= selection.mediaType then
        return false
    end

    if not entry.layoutAgnostic then
        local entryLocationType = NormalizeTextureLayout(entry.locationType)
        local selectionLocationType = NormalizeTextureLayout(selection.locationType)
        if entryLocationType ~= selectionLocationType then
            return false
        end
    end

    if not AreTextureNumbersEqual(entry.scale or 1, selection.scale or 1) then
        return false
    end

    if NormalizeBlendMode(entry.blendMode) ~= NormalizeBlendMode(selection.blendMode) then
        return false
    end

    if not AreTextureColorsEqual(entry.color, selection.color) then
        return false
    end

    return true
end

function CooldownCompanion:FindAuraTexturePickerEntry(entries, selection)
    if type(selection) ~= "table" then
        return nil
    end

    for _, entry in ipairs(entries or {}) do
        if self:DoesAuraTexturePickerEntryMatchSelection(entry, selection) then
            return entry
        end
    end

    return nil
end

function CooldownCompanion:IsAuraTextureButtonSupported(buttonData)
    return type(buttonData) == "table"
        and buttonData.type == "spell"
        and (buttonData.auraTracking == true or buttonData.isPassive == true)
end

function CooldownCompanion:IsTexturePanelGroup(group)
    return type(group) == "table" and group.displayMode == "textures"
end

function CooldownCompanion:IsTriggerPanelGroup(group)
    return type(group) == "table" and group.displayMode == "trigger"
end

function CooldownCompanion:IsStandaloneTexturePanelGroup(group)
    return self:IsTexturePanelGroup(group) or self:IsTriggerPanelGroup(group)
end

function CooldownCompanion:GetTexturePanelLocationOptions()
    local options = {}
    for _, locationType in ipairs(LOCATION_ORDER) do
        options[locationType] = TEXTURE_LAYOUT_LABELS[locationType]
    end
    return options, LOCATION_ORDER
end

function CooldownCompanion:GetTexturePanelLayoutSelectionValue(locationType)
    local normalizedLocationType = NormalizeTextureLayout(locationType)
    if normalizedLocationType == LOCATION_LEFTRIGHT or normalizedLocationType == LOCATION_TOPBOTTOM then
        return normalizedLocationType
    end
    return LOCATION_CENTER
end

local function ResolveGroup(groupOrId)
    if type(groupOrId) == "table" then
        return groupOrId
    end
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    return profile and profile.groups and profile.groups[groupOrId] or nil
end

function CooldownCompanion:GetTexturePanelSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.textureSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.textureSettings = {
            blendMode = "BLEND",
            locationType = LOCATION_CENTER,
            pairSpacing = DEFAULT_TEXTURE_PAIR_SPACING,
            rotation = 0,
            stretchX = 0,
            stretchY = 0,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = UI_PARENT_NAME,
            x = 0,
            y = 0,
        }
    end

    return NormalizeAuraTextureSettings(group.textureSettings)
end

function CooldownCompanion:GetTriggerPanelSignalSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings = {}
    end

    if type(group.triggerSettings.signal) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings.signal = {
            blendMode = "BLEND",
            locationType = LOCATION_CENTER,
            pairSpacing = DEFAULT_TEXTURE_PAIR_SPACING,
            rotation = 0,
            stretchX = 0,
            stretchY = 0,
            point = "CENTER",
            relativePoint = "CENTER",
            relativeTo = UI_PARENT_NAME,
            x = 0,
            y = 0,
        }
    end

    return NormalizeAuraTextureSettings(group.triggerSettings.signal)
end

function CooldownCompanion.NormalizeTriggerDisplayType(displayType)
    if displayType == "icon" or displayType == "text" then
        return displayType
    end
    return "texture"
end

function CooldownCompanion.NormalizeTriggerIconSettings(settings)
    if type(settings) ~= "table" then
        return nil
    end

    settings.manualIcon = (type(settings.manualIcon) == "number" or type(settings.manualIcon) == "string")
            and settings.manualIcon
        or nil
    settings.maintainAspectRatio = settings.maintainAspectRatio ~= false
    settings.buttonSize = Clamp(tonumber(settings.buttonSize) or 36, 10, 150)
    settings.iconWidth = Clamp(tonumber(settings.iconWidth) or settings.buttonSize, 10, 150)
    settings.iconHeight = Clamp(tonumber(settings.iconHeight) or settings.buttonSize, 10, 150)
    settings.borderSize = Clamp(tonumber(settings.borderSize) or 1, 0, 5)
    settings.borderColor = CopyColor(settings.borderColor) or { 0, 0, 0, 1 }
    settings.backgroundColor = CopyColor(settings.backgroundColor) or { 0, 0, 0, 0.5 }
    settings.iconTintColor = CopyColor(settings.iconTintColor) or { 1, 1, 1, 1 }

    return settings
end

function CooldownCompanion.NormalizeTriggerTextSettings(settings)
    if type(settings) ~= "table" then
        return nil
    end

    settings.value = type(settings.value) == "string" and settings.value or ""
    settings.textWidth = Clamp(tonumber(settings.textWidth) or 200, 50, 600)
    settings.textHeight = Clamp(tonumber(settings.textHeight) or 20, 10, 100)
    settings.textFont = type(settings.textFont) == "string" and settings.textFont or "Friz Quadrata TT"
    settings.textFontSize = Clamp(tonumber(settings.textFontSize) or 12, 6, 72)
    settings.textFontOutline = type(settings.textFontOutline) == "string" and settings.textFontOutline or "OUTLINE"
    settings.textFontColor = CopyColor(settings.textFontColor) or { 1, 1, 1, 1 }
    settings.textAlignment = settings.textAlignment == "RIGHT" and "RIGHT"
        or settings.textAlignment == "CENTER" and "CENTER"
        or "LEFT"
    settings.textBgColor = CopyColor(settings.textBgColor) or { 0, 0, 0, 0 }
    settings.textBorderSize = Clamp(tonumber(settings.textBorderSize) or 0, 0, 5)
    settings.textBorderColor = CopyColor(settings.textBorderColor) or { 0, 0, 0, 1 }

    return settings
end

function CooldownCompanion:GetTriggerPanelDisplayType(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return "texture"
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return "texture"
        end
        group.triggerSettings = {}
    end

    group.triggerSettings.displayType = CooldownCompanion.NormalizeTriggerDisplayType(group.triggerSettings.displayType)
    return group.triggerSettings.displayType
end

function CooldownCompanion:GetTriggerPanelIconSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings = {}
    end

    if type(group.triggerSettings.icon) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings.icon = {
            manualIcon = nil,
            maintainAspectRatio = true,
            buttonSize = 36,
            iconWidth = 36,
            iconHeight = 36,
            borderSize = 1,
            borderColor = { 0, 0, 0, 1 },
            backgroundColor = { 0, 0, 0, 0.5 },
            iconTintColor = { 1, 1, 1, 1 },
        }
    end

    return CooldownCompanion.NormalizeTriggerIconSettings(group.triggerSettings.icon)
end

function CooldownCompanion:GetTriggerPanelTextSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.triggerSettings) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings = {}
    end

    if type(group.triggerSettings.text) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.triggerSettings.text = {
            value = "",
            textWidth = 200,
            textHeight = 20,
            textFont = "Friz Quadrata TT",
            textFontSize = 12,
            textFontOutline = "OUTLINE",
            textFontColor = { 1, 1, 1, 1 },
            textAlignment = "LEFT",
            textBgColor = { 0, 0, 0, 0 },
            textBorderSize = 0,
            textBorderColor = { 0, 0, 0, 1 },
        }
    end

    return CooldownCompanion.NormalizeTriggerTextSettings(group.triggerSettings.text)
end

function CooldownCompanion:BuildLegacyTriggerConditionClause(buttonData)
    if type(buttonData) ~= "table" then
        return nil
    end

    local conditionKey = NormalizeTriggerConditionKey(buttonData, buttonData.triggerCondition)
    if not conditionKey then
        return nil
    end

    local clause = { key = conditionKey }
    if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
        clause.expected = buttonData.triggerExpected ~= false
    else
        clause.state = NormalizeTriggerStateKey(conditionKey, buttonData.triggerState)
    end

    return clause
end

function CooldownCompanion:NormalizeTriggerConditionClause(buttonData, clause, usedKeys)
    if type(clause) ~= "table" then
        return nil
    end

    local conditionKey = NormalizeTriggerConditionKey(
        buttonData,
        clause.key or clause.conditionKey or clause.triggerCondition
    )
    if not conditionKey or (usedKeys and usedKeys[conditionKey]) then
        return nil
    end

    local normalized = { key = conditionKey }
    if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
        normalized.expected = clause.expected ~= false and clause.expected ~= "false"
    else
        normalized.state = NormalizeTriggerStateKey(conditionKey, clause.state or clause.triggerState)
    end

    if usedKeys then
        usedKeys[conditionKey] = true
    end

    return normalized
end

function CooldownCompanion:GetTriggerConditionClauses(buttonData)
    if type(buttonData) ~= "table" then
        return {}
    end

    local normalizedClauses = {}
    local usedKeys = {}
    local sourceClauses = type(buttonData.triggerConditions) == "table" and buttonData.triggerConditions or nil

    if sourceClauses then
        for _, clause in ipairs(sourceClauses) do
            local normalizedClause = self:NormalizeTriggerConditionClause(buttonData, clause, usedKeys)
            if normalizedClause then
                normalizedClauses[#normalizedClauses + 1] = normalizedClause
            end
        end

        if #normalizedClauses == 0 then
            return {}
        end
    end

    if #normalizedClauses == 0 then
        local legacyClause = self:BuildLegacyTriggerConditionClause(buttonData)
        if legacyClause then
            usedKeys[legacyClause.key] = true
            normalizedClauses[1] = legacyClause
        elseif buttonData.triggerCondition ~= nil then
            return {}
        end
    end

    if #normalizedClauses == 0 then
        local fallbackKey = NormalizeTriggerConditionKey(buttonData, nil)
        if fallbackKey then
            if TRIGGER_EXPECTED_LABELS[fallbackKey] ~= nil then
                normalizedClauses[1] = {
                    key = fallbackKey,
                    expected = true,
                }
            else
                normalizedClauses[1] = {
                    key = fallbackKey,
                    state = NormalizeTriggerStateKey(fallbackKey, nil),
                }
            end
        end
    end

    return normalizedClauses
end

function CooldownCompanion:NormalizeTriggerConditionRowData(buttonData)
    if type(buttonData) ~= "table" then
        return nil
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    local primaryClause = clauses[1]
    if primaryClause then
        buttonData.triggerCondition = primaryClause.key
        if TRIGGER_EXPECTED_LABELS[primaryClause.key] ~= nil then
            buttonData.triggerExpected = primaryClause.expected ~= false
            buttonData.triggerState = nil
        else
            buttonData.triggerState = NormalizeTriggerStateKey(primaryClause.key, primaryClause.state)
            buttonData.triggerExpected = nil
        end
    end

    if type(buttonData.triggerConditions) == "table" and #clauses > 0 then
        buttonData.triggerConditions = clauses
    end

    if buttonData.type == "spell" then
        local hasAuraClause = false
        for _, clause in ipairs(clauses) do
            if clause.key == "auraActive" then
                hasAuraClause = true
                break
            end
        end

        local shouldAuraTrack = buttonData.isPassive == true
            or buttonData.addedAs == "aura"
            or hasAuraClause
        if shouldAuraTrack then
            buttonData.auraTracking = true
            buttonData.auraIndicatorEnabled = true
            if buttonData.addedAs ~= "aura" and buttonData.isPassive == true then
                buttonData.addedAs = "aura"
            end
        else
            buttonData.auraTracking = false
            buttonData.auraIndicatorEnabled = false
        end
    end

    return buttonData
end

function CooldownCompanion:TriggerRowUsesCondition(buttonData, conditionKey)
    if type(buttonData) ~= "table" or type(conditionKey) ~= "string" then
        return false
    end

    for _, clause in ipairs(self:GetTriggerConditionClauses(buttonData)) do
        if clause.key == conditionKey then
            return true
        end
    end

    return false
end

function CooldownCompanion:GetTriggerConditionTypeOptions(buttonData, excludedKeys)
    local order = GetTriggerConditionOrderForButtonData(buttonData)
    local excluded = {}
    if type(excludedKeys) == "table" then
        for _, key in ipairs(excludedKeys) do
            if type(key) == "string" then
                excluded[key] = true
            end
        end
        for key, value in pairs(excludedKeys) do
            if value == true and type(key) == "string" then
                excluded[key] = true
            end
        end
    end

    local options = {}
    local filteredOrder = {}
    for _, key in ipairs(order) do
        if not excluded[key] then
            options[key] = TRIGGER_CONDITION_LABELS[key]
            filteredOrder[#filteredOrder + 1] = key
        end
    end
    return options, filteredOrder
end

function CooldownCompanion:GetTriggerConditionExpectedOptions(conditionKey)
    if TRIGGER_STATE_LABELS[conditionKey] then
        return TRIGGER_STATE_LABELS[conditionKey], { "full", "missing", "zero" }
    end

    local options = TRIGGER_EXPECTED_LABELS[conditionKey] or TRIGGER_EXPECTED_LABELS.cooldownActive
    return options, { "true", "false" }
end

function CooldownCompanion:GetTriggerConditionStateValue(buttonData, clauseIndex)
    if type(buttonData) ~= "table" then
        return nil
    end

    local clause = self:GetTriggerConditionClauses(buttonData)[clauseIndex or 1]
    if not clause then
        return nil
    end

    local conditionKey = NormalizeTriggerConditionKey(buttonData, clause.key)
    if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
        return clause.expected == false and "false" or "true"
    end

    return NormalizeTriggerStateKey(conditionKey, clause.state)
end

function CooldownCompanion:SetTriggerConditionClauses(buttonData, clauses)
    if type(buttonData) ~= "table" then
        return
    end

    buttonData.triggerConditions = clauses
    self:NormalizeTriggerConditionRowData(buttonData)
end

function CooldownCompanion:SetTriggerConditionKey(buttonData, clauseIndex, conditionKey)
    if type(buttonData) ~= "table" then
        return
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    local clause = clauses[clauseIndex]
    if not clause then
        return
    end

    clause.key = conditionKey
    clause.expected = nil
    clause.state = nil
    self:SetTriggerConditionClauses(buttonData, clauses)
end

function CooldownCompanion:SetTriggerConditionStateValue(buttonData, value, clauseIndex)
    if type(buttonData) ~= "table" then
        return
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    local clause = clauses[clauseIndex or 1]
    if not clause then
        return
    end

    local conditionKey = NormalizeTriggerConditionKey(buttonData, clause.key)
    if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
        clause.expected = (value ~= "false")
        clause.state = nil
        self:SetTriggerConditionClauses(buttonData, clauses)
        return
    end

    clause.state = NormalizeTriggerStateKey(conditionKey, value)
    clause.expected = nil
    self:SetTriggerConditionClauses(buttonData, clauses)
end

function CooldownCompanion:AddTriggerConditionClause(buttonData, conditionKey)
    if type(buttonData) ~= "table" then
        return false
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    local excludedKeys = {}
    for _, clause in ipairs(clauses) do
        excludedKeys[#excludedKeys + 1] = clause.key
    end

    local _, order = self:GetTriggerConditionTypeOptions(buttonData, excludedKeys)
    if #order == 0 then
        return false
    end

    clauses[#clauses + 1] = { key = conditionKey or order[1] }
    self:SetTriggerConditionClauses(buttonData, clauses)
    return true
end

function CooldownCompanion:RemoveTriggerConditionClause(buttonData, clauseIndex)
    if type(buttonData) ~= "table" then
        return false
    end

    local clauses = self:GetTriggerConditionClauses(buttonData)
    if #clauses <= 1 or not clauses[clauseIndex] then
        return false
    end

    table.remove(clauses, clauseIndex)
    self:SetTriggerConditionClauses(buttonData, clauses)
    return true
end

function CooldownCompanion:GetTriggerConditionSummary(buttonData)
    if type(buttonData) ~= "table" then
        return nil
    end

    local summaries = {}
    for _, clause in ipairs(self:GetTriggerConditionClauses(buttonData)) do
        local conditionKey = NormalizeTriggerConditionKey(buttonData, clause.key)
        local conditionLabel = TRIGGER_CONDITION_LABELS[conditionKey]
        local stateLabel
        if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
            stateLabel = (TRIGGER_EXPECTED_LABELS[conditionKey] or TRIGGER_EXPECTED_LABELS.cooldownActive)[clause.expected == false and "false" or "true"]
        else
            local stateKey = NormalizeTriggerStateKey(conditionKey, clause.state)
            stateLabel = TRIGGER_STATE_LABELS[conditionKey] and TRIGGER_STATE_LABELS[conditionKey][stateKey]
        end
        if conditionLabel and stateLabel then
            summaries[#summaries + 1] = conditionLabel .. " " .. stateLabel
        end
    end

    if #summaries == 0 then
        return nil
    end

    return table_concat(summaries, " AND ")
end

function CooldownCompanion:GetCompactTriggerConditionSummary(buttonData, maxVisibleClauses)
    if type(buttonData) ~= "table" then
        return nil
    end

    local count = #self:GetTriggerConditionClauses(buttonData)
    if count <= 0 then
        return nil
    end

    return "Conditions: " .. count
end

function CooldownCompanion:GetTexturePanelIndicatorSettings(groupOrId, createIfMissing)
    local group = ResolveGroup(groupOrId)
    if type(group) ~= "table" then
        return nil
    end

    if type(group.style) ~= "table" then
        if not createIfMissing then
            return nil
        end
        group.style = {}
    end

    if type(group.style.textureIndicators) ~= "table" and not createIfMissing then
        return nil
    end

    return NormalizeTextureIndicatorStore(group.style)
end

function CooldownCompanion:GetTextureIndicatorSectionOrder()
    return TEXTURE_INDICATOR_SECTION_ORDER
end

function CooldownCompanion:ApplyTexturePanelEntry(settings, entry)
    if type(settings) ~= "table" or type(entry) ~= "table" then
        return
    end

    local entryLocationType, entryDefaultPairSpacing
    if entry.locationType ~= nil then
        entryLocationType, entryDefaultPairSpacing = NormalizeTextureLayout(entry.locationType)
    end

    settings.sourceType = entry.sourceType
    settings.sourceValue = entry.sourceValue
    settings.mediaType = entry.mediaType
    settings.libraryKey = entry.libraryKey or entry.key
    settings.label = entry.label
    settings.locationType = entryLocationType or NormalizeTextureLayout(settings.locationType)
    settings.width = entry.width
    settings.height = entry.height
    settings.color = CopyColor(entry.color) or { 1, 1, 1, 1 }
    settings.blendMode = NormalizeBlendMode(settings.blendMode or "BLEND")
    settings.scale = Clamp(entry.scale or settings.scale or 1, 0.25, 4)
    settings.alpha = Clamp(settings.alpha or 1, 0.05, 1)
    settings.rotation = Clamp(settings.rotation or 0, MIN_TEXTURE_ROTATION, MAX_TEXTURE_ROTATION)
    settings.stretchX = Clamp(settings.stretchX or 0, MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH)
    settings.stretchY = Clamp(settings.stretchY or 0, MIN_TEXTURE_STRETCH, MAX_TEXTURE_STRETCH)
    settings.pairSpacing = Clamp(entry.pairSpacing or entryDefaultPairSpacing or settings.pairSpacing or DEFAULT_TEXTURE_PAIR_SPACING, MIN_TEXTURE_PAIR_SPACING, MAX_TEXTURE_PAIR_SPACING)
    settings.point = NormalizeAnchorPoint(settings.point or "CENTER")
    settings.relativePoint = NormalizeAnchorPoint(settings.relativePoint or "CENTER")
    settings.relativeTo = UI_PARENT_NAME
    settings.x = tonumber(settings.x) or 0
    settings.y = tonumber(settings.y) or 0
end

function CooldownCompanion:CreateTexturePanelSelection(entry, baseSettings)
    if type(entry) ~= "table" then
        return nil
    end

    local base = type(baseSettings) == "table" and NormalizeAuraTextureSettings(baseSettings) or nil
    local entryLocationType, entryDefaultPairSpacing
    if entry.locationType ~= nil then
        entryLocationType, entryDefaultPairSpacing = NormalizeTextureLayout(entry.locationType)
    end
    local selection = {
        libraryKey = entry.libraryKey or entry.key,
        sourceType = entry.sourceType,
        sourceValue = entry.sourceValue,
        mediaType = entry.mediaType,
        label = entry.label,
        scale = entry.scale or (base and base.scale) or 1,
        alpha = base and base.alpha or 1,
        blendMode = NormalizeBlendMode((base and base.blendMode) or "BLEND"),
        rotation = base and base.rotation or 0,
        stretchX = base and base.stretchX or 0,
        stretchY = base and base.stretchY or 0,
        point = base and base.point or "CENTER",
        relativePoint = base and base.relativePoint or "CENTER",
        relativeTo = UI_PARENT_NAME,
        x = base and base.x or 0,
        y = base and base.y or 0,
        color = CopyColor(base and base.color) or CopyColor(entry.color) or { 1, 1, 1, 1 },
        locationType = entryLocationType or (base and base.locationType) or LOCATION_CENTER,
        pairSpacing = entry.pairSpacing or entryDefaultPairSpacing or (base and base.pairSpacing) or DEFAULT_TEXTURE_PAIR_SPACING,
        width = entry.width,
        height = entry.height,
    }

    return NormalizeAuraTextureSettings(selection)
end

function CooldownCompanion:GetTexturePanelSelectionLabel(groupOrId)
    local settings = self:GetTexturePanelSettings(groupOrId)
    if not settings or not settings.sourceType then
        return nil
    end
    return settings.label or tostring(settings.sourceValue)
end

local SUPPORTED_CUSTOM_TEXTURE_EXTENSIONS = {
    blp = true,
    jpg = true,
    jpeg = true,
    png = true,
    tga = true,
}

local function NormalizeCustomTexturePath(path)
    if type(path) ~= "string" then
        return nil
    end

    local normalized = string_trim(path)
    if normalized == "" then
        return nil
    end

    normalized = string_gsub(normalized, "/", "\\")
    normalized = string_gsub(normalized, "\\+", "\\")

    local lowerPath = string_lower(normalized)
    if string_find(lowerPath, "^[a-z]:") or not string_find(lowerPath, "^interface\\") then
        return nil
    end

    -- WoW only requires an explicit suffix for PNG paths; BLP/JPG/TGA can be
    -- loaded with or without the extension, so the normalizer must allow both.
    local extension = lowerPath:match("%.([a-z0-9]+)$")
    if extension and not SUPPORTED_CUSTOM_TEXTURE_EXTENSIONS[extension] then
        return nil
    end

    if not extension and string_find(lowerPath, "%.$") then
        return nil
    end

    return normalized
end

local function BuildCustomTexturePathKey(normalizedPath)
    if type(normalizedPath) ~= "string" or normalizedPath == "" then
        return nil
    end
    -- Keep the saved shelf key tied to the exact normalized path so distinct
    -- files like Glow.blp and Glow.tga cannot silently overwrite each other.
    return string_lower(normalizedPath)
end

local function GetCustomTexturePathExtension(normalizedPath)
    if type(normalizedPath) ~= "string" or normalizedPath == "" then
        return nil
    end

    return string_lower(normalizedPath):match("%.([a-z0-9]+)$")
end

local function BuildCustomTextureCanonicalKey(normalizedPath)
    local pathKey = BuildCustomTexturePathKey(normalizedPath)
    if not pathKey then
        return nil
    end

    local extension = GetCustomTexturePathExtension(normalizedPath)
    if extension and extension ~= "png" and SUPPORTED_CUSTOM_TEXTURE_EXTENSIONS[extension] then
        return pathKey:gsub("%.[a-z0-9]+$", "")
    end

    return pathKey
end

local function BuildCustomTextureLabel(normalizedPath)
    if type(normalizedPath) ~= "string" or normalizedPath == "" then
        return "Custom Texture"
    end

    local fileName = normalizedPath:match("([^\\]+)$")
    return fileName or normalizedPath
end

local function NormalizeCustomTextureDimensions(width, height)
    local normalizedWidth = tonumber(width)
    local normalizedHeight = tonumber(height)

    if not normalizedWidth or normalizedWidth <= 0 or not normalizedHeight or normalizedHeight <= 0 then
        return nil, nil
    end

    return normalizedWidth, normalizedHeight
end

local function ReadCustomTextureRecord(value)
    if type(value) == "string" then
        return NormalizeCustomTexturePath(value), nil, nil
    end

    if type(value) ~= "table" then
        return nil, nil, nil
    end

    local normalizedPath = NormalizeCustomTexturePath(value.path or value.sourceValue or value.texturePath)
    local width, height = NormalizeCustomTextureDimensions(value.width, value.height)
    return normalizedPath, width, height
end

local function BuildCustomTextureEntry(value)
    local normalizedPath, width, height = ReadCustomTextureRecord(value)
    local pathKey = BuildCustomTexturePathKey(normalizedPath)
    if not normalizedPath or not pathKey then
        return nil
    end

    local label = BuildCustomTextureLabel(normalizedPath)

    return {
        key = "custom:" .. pathKey,
        libraryKey = "custom:" .. pathKey,
        label = label,
        categoryKey = FILTER_CUSTOM,
        category = FILTER_OPTIONS[FILTER_CUSTOM],
        sourceType = "file",
        sourceValue = normalizedPath,
        layoutAgnostic = true,
        color = { 1, 1, 1, 1 },
        blendMode = "BLEND",
        width = width,
        height = height,
        subtitle = normalizedPath,
        searchText = string_lower(label .. " " .. normalizedPath .. " custom texture"),
        isCustomTexture = true,
    }
end

function CooldownCompanion:NormalizeCustomAuraTexturePath(path)
    return NormalizeCustomTexturePath(path)
end

function CooldownCompanion:IsCustomAuraTextureSelection(selection)
    if type(selection) ~= "table" then
        return false
    end

    if type(selection.libraryKey) == "string" and string_find(selection.libraryKey, "^custom:", 1, false) then
        return true
    end

    return selection.sourceType == "file"
        and type(selection.sourceValue) == "string"
        and NormalizeCustomTexturePath(selection.sourceValue) ~= nil
end

function CooldownCompanion:EnsureAuraTextureLibraryStore()
    local profile = self.db and self.db.profile
    if not profile then
        return nil
    end
    if type(profile.auraTextureLibrary) ~= "table" then
        profile.auraTextureLibrary = {
            customTextures = {},
            textureFavorites = {},
        }
    end

    return self:NormalizeAuraTextureLibraryStore(profile.auraTextureLibrary)
end

function CooldownCompanion:GetSharedMediaAuraTextureEntries()
    local store = self:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    local entries = {}

    for _, mediaType in ipairs(SHARED_MEDIA_TYPE_ORDER) do
        for _, mediaKey in ipairs(LSM:List(mediaType) or {}) do
            local favoriteKey = BuildSharedMediaLibraryKey(mediaType, mediaKey)
            local savedFavorite = favoriteKey and favorites and favorites[favoriteKey] or nil
            local savedRecord = savedFavorite and ReadAuraTextureFavoriteRecord(savedFavorite) or nil
            local entry = BuildSharedMediaEntry(
                mediaType,
                mediaKey,
                savedRecord and savedRecord.label or nil,
                {
                    isFavorited = savedFavorite ~= nil,
                    isMissing = LSM:Fetch(mediaType, mediaKey, true) == nil,
                }
            )
            if entry then
                entries[#entries + 1] = entry
            end
        end
    end

    table_sort(entries, function(a, b)
        local aLabel = string_lower(a.label or "")
        local bLabel = string_lower(b.label or "")
        if aLabel == bLabel then
            local aType = SHARED_MEDIA_TYPE_SORT[a.mediaType] or 99
            local bType = SHARED_MEDIA_TYPE_SORT[b.mediaType] or 99
            if aType == bType then
                return (a.sourceValue or "") < (b.sourceValue or "")
            end
            return aType < bType
        end
        return aLabel < bLabel
    end)

    return entries
end

function CooldownCompanion:GetFavoriteAuraTextureEntries()
    local store = self:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    local entries = {}

    for storedKey, storedValue in pairs(favorites or {}) do
        local record = ReadAuraTextureFavoriteRecord(storedValue)
        if not record then
            favorites[storedKey] = nil
        else
            if record.favoriteKey ~= storedKey then
                favorites[record.favoriteKey] = storedValue
                favorites[storedKey] = nil
            end

            local entry = BuildFavoriteAuraTextureEntry(storedValue)
            if entry then
                entries[#entries + 1] = entry
            else
                favorites[record.favoriteKey] = nil
            end
        end
    end

    table_sort(entries, function(a, b)
        if a.isMissingSharedMedia ~= b.isMissingSharedMedia then
            return not a.isMissingSharedMedia
        end

        local aLabel = string_lower(a.label or "")
        local bLabel = string_lower(b.label or "")
        if aLabel == bLabel then
            return (a.libraryKey or a.key or "") < (b.libraryKey or b.key or "")
        end
        return aLabel < bLabel
    end)

    return entries
end

function CooldownCompanion:SaveFavoriteAuraTexture(entryOrMediaType, mediaKey, label)
    local entry = nil
    if type(entryOrMediaType) == "table" then
        entry = entryOrMediaType
    else
        local normalizedType = NormalizeSharedMediaType(entryOrMediaType)
        local normalizedKey = type(mediaKey) == "string" and string_trim(mediaKey) or nil
        local libraryKey = BuildSharedMediaLibraryKey(normalizedType, normalizedKey)
        if not libraryKey then
            return nil
        end

        entry = BuildSharedMediaEntry(normalizedType, normalizedKey, label, {
            isFavorited = true,
            isMissing = LSM:Fetch(normalizedType, normalizedKey, true) == nil,
        })
    end

    local record = BuildAuraTextureFavoriteRecord(entry)
    if not record then
        return nil
    end

    local store = self:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    if not favorites then
        return nil
    end

    favorites[record.favoriteKey] = record

    return BuildFavoriteAuraTextureEntry(record)
end

function CooldownCompanion:RemoveFavoriteAuraTexture(entryOrKey, mediaKey)
    local store = self:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    if not favorites then
        return
    end

    local favoriteKey = nil
    if type(entryOrKey) == "table" then
        favoriteKey = BuildAuraTextureFavoriteKey(entryOrKey)
    end
    if mediaKey ~= nil then
        favoriteKey = BuildSharedMediaLibraryKey(entryOrKey, mediaKey)
    elseif not favoriteKey and type(entryOrKey) == "string" then
        favoriteKey = entryOrKey
    end

    if not favoriteKey then
        return
    end

    favorites[favoriteKey] = nil
end

function CooldownCompanion:GetCustomAuraTextureEntries()
    local store = self:EnsureAuraTextureLibraryStore()
    local customTextures = store and store.customTextures or nil
    local entries = {}

    for key, storedValue in pairs(customTextures or {}) do
        local entry = BuildCustomTextureEntry(storedValue)
        if entry then
            entries[#entries + 1] = entry
        else
            customTextures[key] = nil
        end
    end

    table_sort(entries, function(a, b)
        return a.label < b.label
    end)

    return entries
end

function CooldownCompanion:SaveCustomAuraTexture(path, width, height)
    local normalizedPath = NormalizeCustomTexturePath(path)
    local pathKey = BuildCustomTexturePathKey(normalizedPath)
    if not normalizedPath or not pathKey then
        return nil
    end

    local store = self:EnsureAuraTextureLibraryStore()
    if not store then
        return nil
    end

    local normalizedWidth, normalizedHeight = NormalizeCustomTextureDimensions(width, height)
    store.customTextures[pathKey] = {
        path = normalizedPath,
        width = normalizedWidth,
        height = normalizedHeight,
    }

    return BuildCustomTextureEntry(store.customTextures[pathKey])
end

function CooldownCompanion:ResolveCustomAuraTextureSubmission(path)
    local normalizedPath = NormalizeCustomTexturePath(path)
    local pathKey = BuildCustomTexturePathKey(normalizedPath)
    if not normalizedPath or not pathKey then
        return nil, nil, "Enter a WoW texture path like Interface\\AddOns\\MyPack\\Texture.tga."
    end

    local store = self:EnsureAuraTextureLibraryStore()
    if not store then
        return nil, nil, "Texture library is unavailable right now."
    end

    local existingExact = store.customTextures[pathKey]
    if existingExact then
        return BuildCustomTextureEntry(existingExact), nil, nil
    end

    local typedExtension = GetCustomTexturePathExtension(normalizedPath)
    if typedExtension ~= nil then
        -- Explicit file variants should stay addable beside an older
        -- extensionless save; only exact path matches should collapse here.
        return nil, normalizedPath, nil
    end

    local canonicalKey = BuildCustomTextureCanonicalKey(normalizedPath)
    local variantCount = 0
    local soleVariantEntry = nil

    for _, storedValue in pairs(store.customTextures) do
        local storedPath = ReadCustomTextureRecord(storedValue)
        if storedPath and BuildCustomTextureCanonicalKey(storedPath) == canonicalKey then
            variantCount = variantCount + 1
            soleVariantEntry = BuildCustomTextureEntry(storedValue)
        end
    end

    if variantCount == 0 then
        return nil, normalizedPath, nil
    end
    if variantCount == 1 then
        return soleVariantEntry, nil, nil
    end

    return nil, nil, "More than one custom texture uses this name. Include the file extension."
end

function CooldownCompanion:RemoveCustomAuraTexture(pathOrKey)
    local store = self:EnsureAuraTextureLibraryStore()
    if not store then
        return
    end

    local pathKey = nil
    if type(pathOrKey) == "string" and string_find(pathOrKey, "^custom:", 1, false) then
        pathKey = pathOrKey:sub(8)
    else
        pathKey = BuildCustomTexturePathKey(pathOrKey)
    end

    if not pathKey then
        return
    end

    store.customTextures[pathKey] = nil
end

local function BuildBlizzardProcOverlayEntries()
    local overlayLibrary = ST._spellActivationOverlayLibrary
    local rows = overlayLibrary and overlayLibrary.entries
    local entries = {}
    local deduped = {}

    if type(rows) ~= "table" then
        return entries
    end

    for _, row in ipairs(rows) do
        local spellID = tonumber(row.spellID)
        local fileDataID = tonumber(row.fileDataID)
        if spellID and spellID > 0 and fileDataID and fileDataID > 0 then
            local spellName = C_Spell_GetSpellName(spellID) or ("Spell " .. tostring(spellID))
            local locationType = tonumber(row.locationType)
            local locationSubtitle = BuildLocationSubtitle(locationType)
            local color = CopyColor(row.color) or { 1, 1, 1, 1 }
            local scale = tonumber(row.scale) or 1
            -- Treat the Blizzard proc browser as an art library, not a layout library.
            -- Different DB2 rows often point at the same visual and only vary by Blizzard's
            -- authored placement metadata, while our config already lets the user choose the
            -- final layout. We intentionally dedupe by visual identity and keep placement only
            -- as searchable/informational metadata so the browser stays consistent.
            local key = string_format(
                "builtin:proc:%d:%.4f:%.4f:%.4f:%.4f:%.4f",
                fileDataID,
                scale,
                color[1] or 1,
                color[2] or 1,
                color[3] or 1,
                color[4] or 1
            )
            local entry = deduped[key]
            if not entry then
                entry = {
                    key = key,
                    label = spellName .. " Proc Overlay",
                    categoryKey = FILTER_BLIZZARD_PROC,
                    category = FILTER_OPTIONS[FILTER_BLIZZARD_PROC],
                    sourceType = "file",
                    sourceValue = fileDataID,
                    -- Leave location unset so selecting a Blizzard proc does not force a
                    -- built-in layout; the layout control remains the source of truth.
                    locationType = nil,
                    layoutAgnostic = true,
                    color = color,
                    blendMode = "ADD",
                    scale = scale,
                    subtitle = tostring(spellID) .. "  |  File " .. tostring(fileDataID),
                    _spellIDs = { tostring(spellID) },
                    _spellNames = { spellName },
                    _spellCount = 1,
                    _locationSubtitles = {
                        [locationSubtitle] = true,
                    },
                    _seenSpellIDs = {
                        [spellID] = true,
                    },
                    _seenSpellNames = {
                        [spellName] = true,
                    },
                }
                deduped[key] = entry
                entries[#entries + 1] = entry
            elseif not entry._seenSpellIDs[spellID] then
                entry._seenSpellIDs[spellID] = true
                entry._spellCount = (entry._spellCount or 1) + 1
                table_insert(entry._spellIDs, tostring(spellID))
                if not entry._seenSpellNames[spellName] then
                    entry._seenSpellNames[spellName] = true
                    table_insert(entry._spellNames, spellName)
                end
                entry._locationSubtitles[locationSubtitle] = true
            end
        end
    end

    for _, entry in ipairs(entries) do
        local locationAliases = {}
        for subtitle in pairs(entry._locationSubtitles or {}) do
            locationAliases[#locationAliases + 1] = subtitle
        end
        table_sort(locationAliases)
        local baseSearchText = entry.label
            .. " "
            .. table_concat(entry._spellNames or {}, " ")
            .. " "
            .. table_concat(entry._spellIDs or {}, " ")
            .. " "
            .. tostring(entry.sourceValue)
            .. " "
            .. table_concat(locationAliases, " ")
        if (entry._spellCount or 1) > 1 then
            entry.subtitle = entry.subtitle .. "  |  Used by " .. tostring(entry._spellCount) .. " spells"
        end
        entry.searchText = string_lower(baseSearchText)
        entry._spellIDs = nil
        entry._spellNames = nil
        entry._spellCount = nil
        entry._locationSubtitles = nil
        entry._seenSpellIDs = nil
        entry._seenSpellNames = nil
    end

    table_sort(entries, function(a, b)
        return a.label < b.label
    end)

    return entries
end

local function BuildBuiltinEntries()
    local entries = {}
    local store = CooldownCompanion:EnsureAuraTextureLibraryStore()
    local favorites = GetAuraTextureFavoriteStore(store)
    for _, entry in ipairs(BUILTIN_LIBRARY) do
        entries[#entries + 1] = ApplyFavoriteStateToEntry({
            key = entry.key,
            label = entry.label,
            categoryKey = entry.categoryKey or FILTER_OTHER,
            category = entry.category or FILTER_OPTIONS[entry.categoryKey] or FILTER_OPTIONS[FILTER_OTHER],
            favoriteOriginCategoryKey = entry.categoryKey or FILTER_OTHER,
            sourceType = entry.sourceType,
            sourceValue = entry.sourceValue,
            width = entry.width,
            height = entry.height,
            color = CopyColor(entry.color) or { 1, 1, 1, 1 },
            blendMode = NormalizeBlendMode(entry.blendMode),
            subtitle = entry.subtitle,
            searchText = entry.searchText or string_lower(entry.label),
        }, favorites)
    end
    for _, entry in ipairs(BuildBlizzardProcOverlayEntries()) do
        entry.favoriteOriginCategoryKey = entry.categoryKey or FILTER_BLIZZARD_PROC
        entries[#entries + 1] = ApplyFavoriteStateToEntry(entry, favorites)
    end
    return entries
end

function CooldownCompanion:GetAuraTexturePickerEntries(searchText, filterValue)
    local query = type(searchText) == "string" and string_lower(string_trim(searchText)) or ""
    local filter = FILTER_OPTIONS[filterValue] and filterValue or FILTER_SYMBOLS
    local entries = {}

    if filter == FILTER_SHAREDMEDIA then
        for _, entry in ipairs(self:GetSharedMediaAuraTextureEntries()) do
            if query == "" or string_find(entry.searchText, query, 1, true) then
                entries[#entries + 1] = entry
            end
        end
        return entries
    end

    if filter == FILTER_FAVORITES then
        for _, entry in ipairs(self:GetFavoriteAuraTextureEntries()) do
            if query == "" or string_find(entry.searchText, query, 1, true) then
                entries[#entries + 1] = entry
            end
        end
        return entries
    end

    for _, entry in ipairs(BuildBuiltinEntries()) do
        if entry.categoryKey == filter and (query == "" or string_find(entry.searchText, query, 1, true)) then
            entries[#entries + 1] = entry
        end
    end

    table_sort(entries, function(a, b)
        return a.label < b.label
    end)

    return entries
end

function CooldownCompanion:GetAuraTexturePickerFilters()
    return FILTER_OPTIONS, {
        FILTER_SYMBOLS,
        FILTER_BLIZZARD_PROC,
        FILTER_SHAREDMEDIA,
        FILTER_FAVORITES,
        FILTER_OTHER,
    }
end

function CooldownCompanion:GetAuraTexturePickerFilterForSelection(selection)
    if type(selection) ~= "table" then
        return FILTER_SYMBOLS
    end

    local favoriteEntry = self:FindAuraTexturePickerEntry(self:GetFavoriteAuraTextureEntries(), selection)
    if favoriteEntry then
        return FILTER_FAVORITES
    end

    local builtinEntry = self:FindAuraTexturePickerEntry(BuildBuiltinEntries(), selection)
    if builtinEntry then
        return builtinEntry.categoryKey or FILTER_OTHER
    end

    local sharedMediaEntry = self:FindAuraTexturePickerEntry(self:GetSharedMediaAuraTextureEntries(), selection)
    if sharedMediaEntry or selection.sourceType == SHARED_MEDIA_SOURCE_TYPE then
        return FILTER_SHAREDMEDIA
    end

    return FILTER_SYMBOLS
end

local function ApplyTextureSource(texture, settings)
    local resolvedSourceType, resolvedSourceValue = CooldownCompanion:ResolveAuraTextureAsset(
        settings.sourceType,
        settings.sourceValue,
        settings.mediaType
    )

    if resolvedSourceType == "atlas" then
        texture:SetAtlas(resolvedSourceValue, false)
        return true
    end

    if resolvedSourceType == "file" then
        texture:SetTexture(resolvedSourceValue)
        return true
    end

    texture:Hide()
    return false
end

local function ApplyTextureVisual(texture, settings, alpha, flipH, flipV, rotationRadians)
    local left, right, top, bottom = 0, 1, 0, 1
    if flipH then
        left, right = 1, 0
    end
    if flipV then
        top, bottom = 1, 0
    end
    texture:SetTexCoord(left, right, top, bottom)
    texture:SetBlendMode(settings.blendMode)
    local color = settings.color or { 1, 1, 1, 1 }
    texture:SetVertexColor(color[1] or 1, color[2] or 1, color[3] or 1, alpha)
    texture:SetRotation(rotationRadians or 0)
    texture:Show()
end

function CooldownCompanion:BuildTexturePanelGeometry(settings, baseWidth, baseHeight)
    local dims = LOCATION_DIMENSIONS[settings.locationType] or LOCATION_DIMENSIONS[LOCATION_CENTER]
    local pieceWidth = math_max(1, (baseWidth or DEFAULT_TEXTURE_SIZE) * (dims.width or 1) * GetStretchMultiplier(settings.stretchX))
    local pieceHeight = math_max(1, (baseHeight or DEFAULT_TEXTURE_SIZE) * (dims.height or 1) * GetStretchMultiplier(settings.stretchY))
    local rotationRadians = math_rad(tonumber(settings.rotation) or 0)
    local pairSpacing = tonumber(settings.pairSpacing) or DEFAULT_TEXTURE_PAIR_SPACING
    local gap = 0
    local pieces = {
        { centerX = 0, centerY = 0, flipH = false, flipV = false },
    }

    if dims.layout == "pair_horizontal" then
        gap = pieceWidth * pairSpacing
        local centerOffset = (pieceWidth + gap) / 2
        pieces = {
            { centerX = -centerOffset, centerY = 0, flipH = false, flipV = false },
            { centerX = centerOffset, centerY = 0, flipH = true, flipV = false },
        }
    elseif dims.layout == "pair_vertical" then
        gap = pieceHeight * pairSpacing
        local centerOffset = (pieceHeight + gap) / 2
        pieces = {
            { centerX = 0, centerY = -centerOffset, flipH = false, flipV = false },
            { centerX = 0, centerY = centerOffset, flipH = false, flipV = true },
        }
    end

    local rotatedPieceWidth = math_max(1, (math_abs(pieceWidth * math_cos(rotationRadians)) + math_abs(pieceHeight * math_sin(rotationRadians))))
    local rotatedPieceHeight = math_max(1, (math_abs(pieceWidth * math_sin(rotationRadians)) + math_abs(pieceHeight * math_cos(rotationRadians))))
    local minLeft, maxRight = nil, nil
    local minBottom, maxTop = nil, nil

    for _, piece in ipairs(pieces) do
        local centerX, centerY = RotateOffset(piece.centerX, piece.centerY, rotationRadians)
        piece.centerX = centerX
        piece.centerY = centerY

        local left = centerX - (rotatedPieceWidth / 2)
        local right = centerX + (rotatedPieceWidth / 2)
        local bottom = centerY - (rotatedPieceHeight / 2)
        local top = centerY + (rotatedPieceHeight / 2)

        minLeft = minLeft and math_min(minLeft, left) or left
        maxRight = maxRight and math_max(maxRight, right) or right
        minBottom = minBottom and math_min(minBottom, bottom) or bottom
        maxTop = maxTop and math_max(maxTop, top) or top
    end

    return {
        rotationRadians = rotationRadians,
        pieceWidth = pieceWidth,
        pieceHeight = pieceHeight,
        rotatedPieceWidth = rotatedPieceWidth,
        rotatedPieceHeight = rotatedPieceHeight,
        boundsWidth = math_max(1, (maxRight or (rotatedPieceWidth / 2)) - (minLeft or -(rotatedPieceWidth / 2))),
        boundsHeight = math_max(1, (maxTop or (rotatedPieceHeight / 2)) - (minBottom or -(rotatedPieceHeight / 2))),
        pieces = pieces,
        layout = dims.layout or "single",
        gap = gap,
    }
end

local function LayoutTexturePieces(host, settings, geometry, alpha)
    local visualRoot = host.visualRoot or host
    local textures = {
        host.primaryTexture,
        host.secondaryTexture,
    }
    local shown = false

    for index, texture in ipairs(textures) do
        local piece = geometry.pieces[index]
        if not texture or not piece then
            if texture then
                texture:Hide()
            end
        else
            texture:ClearAllPoints()
            texture:SetSize(geometry.pieceWidth, geometry.pieceHeight)
            texture:SetPoint("CENTER", visualRoot, "CENTER", piece.centerX, piece.centerY)

            if ApplyTextureSource(texture, settings) then
                ApplyTextureVisual(texture, settings, alpha, piece.flipH, piece.flipV, geometry.rotationRadians)
                shown = true
            else
                texture:Hide()
            end
        end
    end

    return shown
end

local function SetTextureIndicatorBaseVisuals(host)
    if not host then
        return
    end

    local settings = host._activeTextureSettings
    local geometry = host._activeTextureGeometry
    if not settings or not geometry then
        return
    end

    local color = settings.color or { 1, 1, 1, 1 }
    local baseAlpha = Clamp((color[4] or 1) * (settings.alpha or 1), 0.05, 1)
    local textures = {
        host.primaryTexture,
        host.secondaryTexture,
    }

    for index, texture in ipairs(textures) do
        local piece = geometry.pieces[index]
        if texture and piece and texture:IsShown() then
            ApplyTextureVisual(texture, settings, baseAlpha, piece.flipH, piece.flipV, geometry.rotationRadians)
        end
    end

    host._indicatorBaseAlpha = baseAlpha
    host._indicatorBaseColor = CopyColor(color) or { 1, 1, 1, 1 }
end

local function ResetTextureIndicatorTransformState(host)
    if not host or not host.visualRoot then
        return
    end

    host.visualRoot:SetScale(1)
    host.visualRoot:ClearAllPoints()
    host.visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
end

local function GetTextureIndicatorLoopPhase(now, duration)
    duration = Clamp(tonumber(duration) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    local progress = now / duration
    return progress - math_floor(progress)
end

local TextureIndicatorOnUpdate

local function RefreshTextureIndicatorUpdater(host)
    if not host or not host.visualRoot then
        return
    end

    local wantsManualUpdate = host._textureColorShiftActive
        or host._textureShrinkActive
        or host._textureBounceActive

    if not wantsManualUpdate or not host._activeTextureSettings or not host._activeTextureGeometry then
        host:SetScript("OnUpdate", nil)
        ResetTextureIndicatorTransformState(host)
        SetTextureIndicatorBaseVisuals(host)
        return
    end

    host:SetScript("OnUpdate", TextureIndicatorOnUpdate)
    TextureIndicatorOnUpdate(host, 0)
end

TextureIndicatorOnUpdate = function(self)
    if not self or not self.visualRoot or not self._activeTextureSettings or not self._activeTextureGeometry then
        RefreshTextureIndicatorUpdater(self)
        return
    end

    local settings = self._activeTextureSettings
    local now = GetTime()
    SetTextureIndicatorBaseVisuals(self)
    local baseColor = self._indicatorBaseColor or { 1, 1, 1, 1 }
    local baseAlpha = self._indicatorBaseAlpha or 1

    if self._textureColorShiftActive then
        local shift = self._textureColorShiftColor or { 1, 1, 1, 1 }
        local colorPhase = GetTextureIndicatorLoopPhase(now, self._textureColorShiftSpeed)
        local t = 0.5 - (0.5 * math_cos(colorPhase * 2 * math_pi))
        local shiftAlpha = Clamp((shift[4] or 1) * (settings.alpha or 1), 0.05, 1)
        local alpha = baseAlpha + ((shiftAlpha - baseAlpha) * t)

        local primaryTexture = self.primaryTexture
        if primaryTexture and primaryTexture:IsShown() then
            primaryTexture:SetVertexColor(
                (baseColor[1] or 1) + (((shift[1] or 1) - (baseColor[1] or 1)) * t),
                (baseColor[2] or 1) + (((shift[2] or 1) - (baseColor[2] or 1)) * t),
                (baseColor[3] or 1) + (((shift[3] or 1) - (baseColor[3] or 1)) * t),
                alpha
            )
        end

        local secondaryTexture = self.secondaryTexture
        if secondaryTexture and secondaryTexture:IsShown() then
            secondaryTexture:SetVertexColor(
                (baseColor[1] or 1) + (((shift[1] or 1) - (baseColor[1] or 1)) * t),
                (baseColor[2] or 1) + (((shift[2] or 1) - (baseColor[2] or 1)) * t),
                (baseColor[3] or 1) + (((shift[3] or 1) - (baseColor[3] or 1)) * t),
                alpha
            )
        end
    end

    local scale = 1
    if self._textureShrinkActive then
        local shrinkPhase = GetTextureIndicatorLoopPhase(
            now - (self._textureShrinkStartTime or now),
            self._textureShrinkSpeed
        )
        local shrinkT = 0.5 - (0.5 * math_cos(shrinkPhase * 2 * math_pi))
        scale = 1 - ((1 - DEFAULT_TEXTURE_SHRINK_SCALE) * shrinkT)
    end
    self.visualRoot:SetScale(scale)

    local bounceOffsetY = 0
    if self._textureBounceActive then
        local bouncePhase = GetTextureIndicatorLoopPhase(
            now - (self._textureBounceStartTime or now),
            self._textureBounceSpeed
        )
        local amplitude = self._textureBounceAmplitude or DEFAULT_TEXTURE_BOUNCE_PIXELS
        if bouncePhase < 0.5 then
            local riseT = bouncePhase / 0.5
            bounceOffsetY = amplitude * (1 - ((1 - riseT) * (1 - riseT)))
        else
            local fallT = (bouncePhase - 0.5) / 0.5
            bounceOffsetY = amplitude * (1 - (fallT * fallT))
        end
    end

    self.visualRoot:ClearAllPoints()
    self.visualRoot:SetPoint("CENTER", self, "CENTER", 0, bounceOffsetY)
end

local function StopTextureIndicatorAnimation(host, effectType)
    if not host or not host.visualRoot or not host._textureIndicatorAnimations then
        return
    end

    local animData = host._textureIndicatorAnimations[effectType]
    if not animData or not animData.group then
        return
    end

    animData.group:Stop()
end

local function EnsureTextureIndicatorAnimation(host, effectType)
    if not host or not host.visualRoot then
        return nil
    end

    host._textureIndicatorAnimations = host._textureIndicatorAnimations or {}
    local existing = host._textureIndicatorAnimations[effectType]
    if existing then
        return existing
    end

    local visualRoot = host.visualRoot
    local group = visualRoot:CreateAnimationGroup()
    group:SetLooping("BOUNCE")

    local animData = { group = group }
    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE then
        local alphaAnim = group:CreateAnimation("Alpha")
        alphaAnim:SetFromAlpha(1)
        alphaAnim:SetToAlpha(DEFAULT_TEXTURE_PULSE_ALPHA)
        animData.alpha = alphaAnim
    elseif effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND then
        local scaleAnim = group:CreateAnimation("Scale")
        scaleAnim:SetScaleFrom(1, 1)
        scaleAnim:SetScaleTo(DEFAULT_TEXTURE_SHRINK_SCALE, DEFAULT_TEXTURE_SHRINK_SCALE)
        scaleAnim:SetOrigin("CENTER", 0, 0)
        animData.scale = scaleAnim
    elseif effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        local translation = group:CreateAnimation("Translation")
        translation:SetOffset(0, DEFAULT_TEXTURE_BOUNCE_PIXELS)
        animData.translation = translation
    end

    host._textureIndicatorAnimations[effectType] = animData
    return animData
end

local function SetTextureIndicatorAnimation(host, effectType, active, speed, amplitude)
    if not host or not host.visualRoot then
        return
    end

    if effectType == TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND then
        local wasActive = host._textureShrinkActive == true
        host._textureShrinkActive = active and true or nil
        host._textureShrinkSpeed = active and Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED) or nil
        if host._textureShrinkActive and not wasActive then
            host._textureShrinkStartTime = GetTime()
        elseif not host._textureShrinkActive then
            host._textureShrinkStartTime = nil
        end
        RefreshTextureIndicatorUpdater(host)
        return
    elseif effectType == TEXTURE_INDICATOR_EFFECT_BOUNCE then
        local wasActive = host._textureBounceActive == true
        host._textureBounceActive = active and true or nil
        host._textureBounceSpeed = active and Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED) or nil
        host._textureBounceAmplitude = active and (amplitude or DEFAULT_TEXTURE_BOUNCE_PIXELS) or nil
        if host._textureBounceActive and not wasActive then
            host._textureBounceStartTime = GetTime()
        elseif not host._textureBounceActive then
            host._textureBounceStartTime = nil
        end
        RefreshTextureIndicatorUpdater(host)
        return
    end

    if not active then
        StopTextureIndicatorAnimation(host, effectType)
        if effectType == TEXTURE_INDICATOR_EFFECT_PULSE then
            host.visualRoot:SetAlpha(1)
        end
        return
    end

    local animData = EnsureTextureIndicatorAnimation(host, effectType)
    if not animData then
        return
    end

    speed = Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    if effectType == TEXTURE_INDICATOR_EFFECT_PULSE and animData.alpha then
        animData.alpha:SetDuration(speed)
    end

    if not animData.group:IsPlaying() then
        animData.group:Play()
    end
end

local function StopTextureColorShift(host)
    if not host then
        return
    end

    host._textureColorShiftActive = nil
    RefreshTextureIndicatorUpdater(host)
end

local function StartTextureColorShift(host, shiftColor, speed)
    if not host then
        return
    end

    host._textureColorShiftActive = true
    host._textureColorShiftColor = CopyColor(shiftColor) or { 1, 1, 1, 1 }
    host._textureColorShiftSpeed = Clamp(tonumber(speed) or DEFAULT_TEXTURE_INDICATOR_SPEED, MIN_TEXTURE_INDICATOR_SPEED, MAX_TEXTURE_INDICATOR_SPEED)
    RefreshTextureIndicatorUpdater(host)
end

local function StopAllTextureIndicatorEffects(host)
    if not host or not host.visualRoot then
        return
    end

    StopTextureIndicatorAnimation(host, TEXTURE_INDICATOR_EFFECT_PULSE)
    host._textureShrinkActive = nil
    host._textureShrinkSpeed = nil
    host._textureShrinkStartTime = nil
    host._textureBounceActive = nil
    host._textureBounceSpeed = nil
    host._textureBounceAmplitude = nil
    host._textureBounceStartTime = nil
    host._textureColorShiftActive = nil
    host._textureColorShiftColor = nil
    host._textureColorShiftSpeed = nil
    host.visualRoot:SetAlpha(1)
    ResetTextureIndicatorTransformState(host)
    host:SetScript("OnUpdate", nil)
    SetTextureIndicatorBaseVisuals(host)
end

local function IsTextureIndicatorSectionActive(button, sectionKey, config)
    if not button or type(config) ~= "table" or not config.enabled then
        return false
    end

    if sectionKey == "proc" and button._textureProcPreview then
        return true
    end
    if sectionKey == "aura" and button._textureAuraPreview then
        return true
    end
    if sectionKey == "pandemic" and button._texturePandemicPreview then
        return true
    end
    if sectionKey == "ready" and button._textureReadyPreview then
        return true
    end
    if sectionKey == "unusable" and button._textureUnusablePreview then
        return true
    end

    if config.combatOnly and not InCombatLockdown() then
        return false
    end

    if sectionKey == "proc" then
        return button._procOverlayActive == true
    end

    if sectionKey == "aura" then
        if button._auraTrackingReady ~= true or not button._auraSpellID then
            return false
        end
        if config.invert then
            if button._auraUnit == "target" and not UnitExists("target") then
                return false
            end
            return button._auraActive ~= true
        end
        return button._auraActive == true
    end

    if sectionKey == "pandemic" then
        return button._auraActive == true and button._inPandemic == true
    end

    if sectionKey == "ready" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive or button._noCooldown then
            return false
        end
        return button._desatCooldownActive == false
    end

    if sectionKey == "unusable" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive then
            return false
        end
        if buttonData.type == "spell" then
            return not C_Spell_IsSpellUsable(buttonData.id)
        end
        if buttonData.type == "item" or buttonData.type == "equipitem" then
            return not C_Item_IsUsableItem(buttonData.id)
        end
        return false
    end

    return false
end

local function EvaluateTriggerRowCondition(button, conditionKey)
    if not button then
        return false
    end

    if conditionKey == "cooldownActive" then
        return button._desatCooldownActive == true
    end

    if conditionKey == "auraActive" then
        return button._auraActive == true
    end

    if conditionKey == "procActive" then
        return button._procOverlayActive == true
    end

    if conditionKey == "rangeActive" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive then
            return nil
        end

        if buttonData.type == "spell" then
            if button._spellOutOfRange == nil then
                return nil
            end
            return button._spellOutOfRange == false
        end

        if buttonData.type == "item" or buttonData.type == "equipitem" then
            if not InCombatLockdown() or UnitCanAttack("player", "target") then
                local inRange = C_Item.IsItemInRange(buttonData.id, "target")
                if inRange == nil then
                    return nil
                end
                return inRange == true
            end
            return nil
        end

        return nil
    end

    if conditionKey == "usable" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.isPassive then
            return false
        end
        if buttonData.type == "spell" then
            return C_Spell_IsSpellUsable(buttonData.id)
        end
        if buttonData.type == "item" or buttonData.type == "equipitem" then
            return C_Item_IsUsableItem(buttonData.id)
        end
        return false
    end

    if conditionKey == "chargesRecharging" then
        return button._chargeRecharging == true
    end

    if conditionKey == "chargeState" then
        local buttonData = button.buttonData
        if not buttonData or buttonData.hasCharges ~= true then
            return nil
        end

        local currentCharges = button._currentReadableCharges
        local maxCharges = buttonData.maxCharges
        if currentCharges ~= nil then
            if currentCharges <= 0 then
                return "zero"
            end
            if maxCharges ~= nil and maxCharges > 0 then
                if currentCharges >= maxCharges then
                    return "full"
                end
                return "missing"
            end
        end

        if button._zeroChargesConfirmed == true then
            return "zero"
        end
        if button._chargeRecharging == true then
            return "missing"
        end
        if button._chargeRecharging == false then
            return "full"
        end
        return nil
    end

    if conditionKey == "countTextActive" then
        local buttonData = button.buttonData
        if not buttonData
                or not CooldownCompanion.HasNonChargeCountTextBehavior
                or not CooldownCompanion.HasNonChargeCountTextBehavior(buttonData) then
            return nil
        end

        local countText = button.count and button.count:GetText() or nil
        if issecretvalue(countText) then
            return true
        end
        return countText ~= nil and countText ~= ""
    end

    if conditionKey == "countState" then
        local buttonData = button.buttonData
        if not buttonData
                or (buttonData._hasDisplayCount ~= true and buttonData._displayCountFamily ~= true)
                or buttonData.hasCharges == true
        then
            return nil
        end

        local currentCount = button._currentReadableCharges
        local maxCount = buttonData.maxCharges
        if currentCount == nil then
            return nil
        end
        if currentCount <= 0 then
            return "zero"
        end
        if maxCount ~= nil and maxCount > 0 then
            if currentCount >= maxCount then
                return "full"
            end
            return "missing"
        end
        return nil
    end

    return false
end

local function DoesTriggerPanelMatch(frame)
    if not frame then
        return false
    end

    local group = frame.groupId and ResolveGroup(frame.groupId) or nil
    local configuredRows = group and group.buttons
    if type(configuredRows) ~= "table" or #configuredRows == 0 then
        return false
    end

    local runtimeButtonsByIndex = {}
    for _, button in ipairs(frame.buttons or {}) do
        if button and button.index then
            runtimeButtonsByIndex[button.index] = button
        end
    end

    local activeRowCount = 0
    for rowIndex, buttonData in ipairs(configuredRows) do
        if type(buttonData) ~= "table" then
            return false
        end

        if buttonData.enabled ~= false then
            local clauses = CooldownCompanion:GetTriggerConditionClauses(buttonData)
            if #clauses == 0 then
                return false
            end

            activeRowCount = activeRowCount + 1
            local runtimeButton = runtimeButtonsByIndex[rowIndex]
            if not runtimeButton then
                return false
            end

            for _, clause in ipairs(clauses) do
                local conditionKey = NormalizeTriggerConditionKey(buttonData, clause.key)
                if not conditionKey then
                    return false
                end

                local actualState = EvaluateTriggerRowCondition(runtimeButton, conditionKey)
                if TRIGGER_EXPECTED_LABELS[conditionKey] ~= nil then
                    local expected = clause.expected ~= false
                    if actualState ~= expected then
                        return false
                    end
                else
                    local expectedState = NormalizeTriggerStateKey(conditionKey, clause.state)
                    if actualState ~= expectedState then
                        return false
                    end
                end
            end
        end
    end

    return activeRowCount > 0
end

local function ApplyTextureIndicatorEffects(host, button, group)
    if not host or not button or type(group) ~= "table" then
        return
    end

    local indicators = CooldownCompanion:GetTexturePanelIndicatorSettings(group)
    if not indicators then
        StopAllTextureIndicatorEffects(host)
        return
    end

    local effectStates = {}
    for _, sectionKey in ipairs(TEXTURE_INDICATOR_SECTION_ORDER) do
        local config = indicators[sectionKey]
        if IsTextureIndicatorSectionActive(button, sectionKey, config) then
            local effectType = NormalizeTextureIndicatorEffect(config.effectType)
            if effectType ~= TEXTURE_INDICATOR_EFFECT_NONE and not effectStates[effectType] then
                effectStates[effectType] = config
            end
        end
    end

    local bounceAmplitude = math_max(6, math_min(DEFAULT_TEXTURE_BOUNCE_PIXELS, (host._activeTextureGeometry and host._activeTextureGeometry.boundsHeight or DEFAULT_TEXTURE_BOUNCE_PIXELS) * 0.12))

    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_PULSE,
        effectStates[TEXTURE_INDICATOR_EFFECT_PULSE] ~= nil,
        effectStates[TEXTURE_INDICATOR_EFFECT_PULSE] and effectStates[TEXTURE_INDICATOR_EFFECT_PULSE].speed or nil
    )
    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND,
        effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND] ~= nil,
        effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND] and effectStates[TEXTURE_INDICATOR_EFFECT_SHRINK_EXPAND].speed or nil
    )
    SetTextureIndicatorAnimation(
        host,
        TEXTURE_INDICATOR_EFFECT_BOUNCE,
        effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE] ~= nil,
        effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE] and effectStates[TEXTURE_INDICATOR_EFFECT_BOUNCE].speed or nil,
        bounceAmplitude
    )

    local colorShift = effectStates[TEXTURE_INDICATOR_EFFECT_COLOR_SHIFT]
    if colorShift then
        StartTextureColorShift(host, colorShift.color, colorShift.speed)
    else
        StopTextureColorShift(host)
    end
end

local function CreateAuraTextureOutline(host)
    local fill = host:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", host, "TOPLEFT", -4, 4)
    fill:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", 4, -4)
    fill:SetColorTexture(0.05, 0.35, 0.5, 0.12)
    fill:Hide()

    local edges = {}
    local edgeSpecs = {
        { point1 = "TOPLEFT", point2 = "TOPRIGHT", x1 = -4, y1 = 4, x2 = 4, y2 = 4, width = 1, height = nil },
        { point1 = "BOTTOMLEFT", point2 = "BOTTOMRIGHT", x1 = -4, y1 = -4, x2 = 4, y2 = -4, width = 1, height = nil },
        { point1 = "TOPLEFT", point2 = "BOTTOMLEFT", x1 = -4, y1 = 4, x2 = -4, y2 = -4, width = nil, height = 1 },
        { point1 = "TOPRIGHT", point2 = "BOTTOMRIGHT", x1 = 4, y1 = 4, x2 = 4, y2 = -4, width = nil, height = 1 },
    }

    for index, spec in ipairs(edgeSpecs) do
        local edge = host:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(0.2, 0.8, 1, 0.95)
        edge:SetPoint(spec.point1, host, spec.point1, spec.x1, spec.y1)
        edge:SetPoint(spec.point2, host, spec.point2, spec.x2, spec.y2)
        if spec.width then
            edge:SetHeight(spec.width)
        end
        if spec.height then
            edge:SetWidth(spec.height)
        end
        edge:Hide()
        edges[index] = edge
    end

    host.auraTextureOutlineFill = fill
    host.auraTextureOutlineEdges = edges
end

local function SetAuraTextureOutlineShown(host, shown)
    if not host.auraTextureOutlineFill then
        CreateAuraTextureOutline(host)
    end

    host.auraTextureOutlineFill:SetShown(shown)
    for _, edge in ipairs(host.auraTextureOutlineEdges or {}) do
        edge:SetShown(shown)
    end
end

local function UpdateTextureHostCoordLabel(host, x, y)
    if host and host.coordLabel and host.coordLabel.text then
        host.coordLabel.text:SetText(("x:%.1f, y:%.1f"):format(x or 0, y or 0))
    end
end

local function SaveTextureHostPosition(host)
    if not host then
        return
    end

    local owner = host._ownerButton
    local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
    local settings
    local requiresConfiguredTexture = false
    if group and CooldownCompanion:IsTriggerPanelGroup(group) then
        settings = CooldownCompanion:GetTriggerPanelSignalSettings(group)
    else
        settings = group and CooldownCompanion:GetTexturePanelSettings(group)
        requiresConfiguredTexture = true
    end
    if not settings then
        return
    end
    if requiresConfiguredTexture and not settings.sourceType then
        return
    end

    local point, _, relPoint, x, y = host:GetPoint(1)
    settings.point = NormalizeAnchorPoint(point)
    settings.relativePoint = NormalizeAnchorPoint(relPoint)
    settings.relativeTo = UI_PARENT_NAME
    settings.x = math_floor(((x or 0) * 10) + 0.5) / 10
    settings.y = math_floor(((y or 0) * 10) + 0.5) / 10

    UpdateTextureHostCoordLabel(host, settings.x, settings.y)
    CooldownCompanion:UpdateAuraTextureVisual(owner)
    if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
        CooldownCompanion:RefreshConfigPanel()
    end
end

local function EnsureAuraTextureNudger(host)
    if host.nudger then
        return
    end

    local nudger = CreateFrame("Frame", nil, host.dragHandle, "BackdropTemplate")
    nudger:SetSize(NUDGE_BTN_SIZE * 2 + NUDGE_GAP, NUDGE_BTN_SIZE * 2 + NUDGE_GAP)
    nudger:SetPoint("BOTTOM", host.dragHandle, "TOP", 0, 2)
    nudger:SetFrameStrata(host.dragHandle:GetFrameStrata())
    nudger:SetFrameLevel(host.dragHandle:GetFrameLevel() + 5)
    nudger:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    nudger:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(nudger)
    nudger.buttons = {}

    local directions = {
        { atlas = "common-dropdown-icon-back", rotation = -math_pi / 2, anchor = "BOTTOM", dx =  0, dy =  1, ox = 0,         oy = NUDGE_GAP },
        { atlas = "common-dropdown-icon-next", rotation = -math_pi / 2, anchor = "TOP",    dx =  0, dy = -1, ox = 0,         oy = -NUDGE_GAP },
        { atlas = "common-dropdown-icon-back", rotation = 0,            anchor = "RIGHT",  dx = -1, dy =  0, ox = -NUDGE_GAP, oy = 0 },
        { atlas = "common-dropdown-icon-next", rotation = 0,            anchor = "LEFT",   dx =  1, dy =  0, ox = NUDGE_GAP,  oy = 0 },
    }

    local function DoNudge(dx, dy)
        host:AdjustPointsOffset(dx, dy)
        local _, _, _, x, y = host:GetPoint()
        local owner = host._ownerButton
        local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
        local settings
        if group and CooldownCompanion:IsTriggerPanelGroup(group) then
            settings = CooldownCompanion:GetTriggerPanelSignalSettings(group)
        else
            settings = group and CooldownCompanion:GetTexturePanelSettings(group)
        end
        if settings then
            settings.x = math_floor((x or 0) * 10 + 0.5) / 10
            settings.y = math_floor((y or 0) * 10 + 0.5) / 10
        end
        UpdateTextureHostCoordLabel(host, x, y)
    end

    for _, dir in ipairs(directions) do
        local btn = CreateFrame("Button", nil, nudger)
        btn:SetSize(NUDGE_BTN_SIZE, NUDGE_BTN_SIZE)
        btn:SetPoint(dir.anchor, nudger, "CENTER", dir.ox, dir.oy)
        btn:EnableMouse(true)
        nudger.buttons[#nudger.buttons + 1] = btn

        local arrow = btn:CreateTexture(nil, "OVERLAY")
        arrow:SetAtlas(dir.atlas)
        arrow:SetAllPoints()
        arrow:SetRotation(dir.rotation)
        arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
        btn.arrow = arrow

        btn:SetScript("OnEnter", function(self)
            self.arrow:SetVertexColor(1, 1, 1, 1)
        end)
        btn:SetScript("OnLeave", function(self)
            self.arrow:SetVertexColor(0.8, 0.8, 0.8, 0.8)
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
            SaveTextureHostPosition(host)
        end)

        btn:SetScript("OnMouseDown", function(self)
            DoNudge(dir.dx, dir.dy)
            self.nudgeDelayTimer = C_Timer.NewTimer(NUDGE_REPEAT_DELAY, function()
                self.nudgeTicker = C_Timer.NewTicker(NUDGE_REPEAT_INTERVAL, function()
                    DoNudge(dir.dx, dir.dy)
                end)
            end)
        end)

        btn:SetScript("OnMouseUp", function(self)
            if self.nudgeDelayTimer then
                self.nudgeDelayTimer:Cancel()
                self.nudgeDelayTimer = nil
            end
            if self.nudgeTicker then
                self.nudgeTicker:Cancel()
                self.nudgeTicker = nil
            end
            SaveTextureHostPosition(host)
        end)
    end

    host.nudger = nudger
end

local function EnsureAuraTextureDragHandle(host)
    if host.dragHandle then
        return
    end

    local dragHandle = CreateFrame("Frame", nil, host, "BackdropTemplate")
    dragHandle:SetPoint("BOTTOMLEFT", host, "TOPLEFT", 0, 2)
    dragHandle:SetPoint("BOTTOMRIGHT", host, "TOPRIGHT", 0, 2)
    dragHandle:SetHeight(15)
    dragHandle:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    dragHandle:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(dragHandle)
    dragHandle:RegisterForDrag("LeftButton")
    dragHandle:EnableMouse(true)

    local text = dragHandle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("CENTER")
    text:SetTextColor(1, 1, 1, 1)
    dragHandle.text = text

    local coordLabel = CreateFrame("Frame", nil, dragHandle, "BackdropTemplate")
    coordLabel:SetHeight(15)
    coordLabel:SetPoint("TOPLEFT", dragHandle, "BOTTOMLEFT", 0, -2)
    coordLabel:SetPoint("TOPRIGHT", dragHandle, "BOTTOMRIGHT", 0, -2)
    coordLabel:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
    coordLabel:SetBackdropColor(0.2, 0.2, 0.2, 0.8)
    ST.CreatePixelBorders(coordLabel)
    coordLabel.text = coordLabel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    coordLabel.text:SetPoint("CENTER")
    coordLabel.text:SetTextColor(1, 1, 1, 1)

    dragHandle:SetScript("OnDragStart", function()
        if host._dragEnabled then
            host._isDragging = true
            host:StartMoving()
        end
    end)
    dragHandle:SetScript("OnDragStop", function()
        host._isDragging = nil
        host:StopMovingOrSizing()
        SaveTextureHostPosition(host)
    end)
    dragHandle:SetScript("OnMouseUp", function(_, button)
        if button ~= "MiddleButton" then
            return
        end

        local owner = host._ownerButton
        local group = owner and owner._groupId and ResolveGroup(owner._groupId) or nil
        if not group then
            return
        end

        group.locked = nil
        CooldownCompanion:RefreshGroupFrame(owner._groupId)
        CooldownCompanion:RefreshAllAuraTextureVisuals()
        if ST._configState and ST._configState.configFrame and ST._configState.configFrame.frame and ST._configState.configFrame.frame:IsShown() then
            CooldownCompanion:RefreshConfigPanel()
        end
        CooldownCompanion:Print((group.name or "Texture Panel") .. " locked.")
    end)

    host.dragHandle = dragHandle
    host.coordLabel = coordLabel
    EnsureAuraTextureNudger(host)
end

local function SyncAuraTextureControlLevels(host)
    if not host then
        return
    end

    local strata = host:GetFrameStrata()
    local baseLevel = host:GetFrameLevel() or 1

    if host.dragHandle then
        host.dragHandle:SetFrameStrata(strata)
        host.dragHandle:SetFrameLevel(baseLevel + 5)
    end
    if host.coordLabel then
        host.coordLabel:SetFrameStrata(strata)
        host.coordLabel:SetFrameLevel(baseLevel + 6)
    end
    if host.nudger then
        host.nudger:SetFrameStrata(strata)
        host.nudger:SetFrameLevel(baseLevel + 10)
        for index, btn in ipairs(host.nudger.buttons or {}) do
            btn:SetFrameStrata(strata)
            btn:SetFrameLevel(baseLevel + 11 + index)
        end
    end
end

local function EnsureAuraTextureHost(button)
    if button.auraTextureHost then
        return button.auraTextureHost
    end

    local host = CreateFrame("Frame", nil, UIParent)
    host:SetMovable(true)
    host:SetClampedToScreen(true)
    host:EnableMouse(false)
    host:Hide()
    host._ownerButton = button

    local visualRoot = CreateFrame("Frame", nil, host)
    visualRoot:SetPoint("CENTER", host, "CENTER", 0, 0)
    visualRoot:SetSize(1, 1)
    host.visualRoot = visualRoot

    local primary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    local secondary = visualRoot:CreateTexture(nil, "ARTWORK", nil, 1)
    primary:Hide()
    secondary:Hide()
    host.primaryTexture = primary
    host.secondaryTexture = secondary

    host:SetScript("OnDragStart", function(self)
        if not self._dragEnabled then
            return
        end
        self._isDragging = true
        self:StartMoving()
    end)

    host:SetScript("OnDragStop", function(self)
        self._isDragging = nil
        self:StopMovingOrSizing()
        SaveTextureHostPosition(self)
    end)

    CreateAuraTextureOutline(host)
    EnsureAuraTextureDragHandle(host)
    button.auraTextureHost = host
    return host
end

function CooldownCompanion.EnsureTriggerIconVisual(host)
    if host.iconFrame then
        return host.iconFrame
    end

    local frame = CreateFrame("Frame", nil, host.visualRoot)
    frame:SetPoint("CENTER")
    frame:SetSize(36, 36)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()

    frame.icon = frame:CreateTexture(nil, "ARTWORK")

    frame.borderTextures = {}
    for index = 1, 4 do
        frame.borderTextures[index] = frame:CreateTexture(nil, "OVERLAY")
    end

    host.iconFrame = frame
    return frame
end

function CooldownCompanion.EnsureTriggerTextVisual(host)
    if host.textFrame then
        return host.textFrame
    end

    local frame = CreateFrame("Frame", nil, host.visualRoot)
    frame:SetPoint("CENTER")
    frame:SetSize(200, 20)
    frame:Hide()

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()

    frame.borderTextures = {}
    for index = 1, 4 do
        frame.borderTextures[index] = frame:CreateTexture(nil, "OVERLAY")
    end

    frame.text = frame:CreateFontString(nil, "OVERLAY")
    frame.text:SetPoint("TOPLEFT", 2, -1)
    frame.text:SetPoint("BOTTOMRIGHT", -2, 1)
    frame.text:SetJustifyV("MIDDLE")
    frame.text:SetWordWrap(true)

    host.textFrame = frame
    return frame
end

function CooldownCompanion.HideStandaloneDisplayVisuals(host)
    if not host then
        return
    end

    if host.primaryTexture then
        host.primaryTexture:Hide()
    end
    if host.secondaryTexture then
        host.secondaryTexture:Hide()
    end
    if host.iconFrame then
        host.iconFrame:Hide()
    end
    if host.textFrame then
        host.textFrame:Hide()
    end
end

function CooldownCompanion.GetTriggerIconDimensions(settings)
    if settings.maintainAspectRatio then
        local size = settings.buttonSize or 36
        return size, size
    end
    return settings.iconWidth or 36, settings.iconHeight or 36
end

function CooldownCompanion.HasTriggerTextValue(settings)
    return type(settings) == "table" and type(settings.value) == "string" and string_trim(settings.value) ~= ""
end

local function GetTexturePanelAlphaModuleId(groupId)
    if not groupId then
        return nil
    end
    return "texture_panel_" .. tostring(groupId)
end

local function GetTexturePanelLayoutPreviewAlpha(button)
    local CS = ST._configState
    if not button or not CS or CS.panelSettingsTab ~= "layout" or CS.selectedGroup ~= button._groupId then
        return nil
    end

    local preview = CS.texturePanelAlphaPreview
    if type(preview) ~= "table" then
        return nil
    end

    return preview[button._groupId]
end

function CooldownCompanion:HideAuraTextureVisual(button)
    local alphaModuleId = button and GetTexturePanelAlphaModuleId(button._groupId) or nil
    if alphaModuleId then
        self:UnregisterModuleAlpha(alphaModuleId, true)
    end

    local host = button and button.auraTextureHost
    if not host then
        return
    end

    StopAllTextureIndicatorEffects(host)
    if host._isDragging then
        host._isDragging = nil
        host:StopMovingOrSizing()
    end
    CooldownCompanion.HideStandaloneDisplayVisuals(host)
    host._activeDisplayType = nil
    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._dragEnabled = nil
    host:EnableMouse(false)
    host:SetAlpha(1)
    SetAuraTextureOutlineShown(host, false)
    if host.dragHandle then
        host.dragHandle:Hide()
    end
    if host.coordLabel then
        host.coordLabel:Hide()
    end
    if host.nudger then
        for _, btn in ipairs(host.nudger.buttons or {}) do
            if btn.nudgeDelayTimer then
                btn.nudgeDelayTimer:Cancel()
                btn.nudgeDelayTimer = nil
            end
            if btn.nudgeTicker then
                btn.nudgeTicker:Cancel()
                btn.nudgeTicker = nil
            end
        end
        host.nudger:Hide()
    end
    host:Hide()
end

function CooldownCompanion:ReleaseAuraTextureVisual(button)
    if not button or not button.auraTextureHost then
        return
    end

    local alphaModuleId = GetTexturePanelAlphaModuleId(button._groupId)
    self:HideAuraTextureVisual(button)
    if alphaModuleId then
        self:UnregisterModuleAlpha(alphaModuleId)
    end
    button.auraTextureHost:SetParent(nil)
    button.auraTextureHost = nil
end

local function IsStandaloneTextureEditingButton(button)
    local CS = ST._configState
    if not CS or not CS.configFrame or not CS.configFrame.frame or not CS.configFrame.frame:IsShown() then
        return false
    end
    if CS.selectedGroup ~= button._groupId then
        return false
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        return false
    end

    if CS.panelSettingsTab == "appearance" or CS.panelSettingsTab == "effects" or CS.panelSettingsTab == "layout" then
        if CooldownCompanion:IsTriggerPanelGroup(group) then
            return true
        end
        if CS.selectedButton == nil then
            return true
        end
    end

    local pickerWindow = CS.auraTexturePickerWindow
    return pickerWindow and pickerWindow._targetGroupId == button._groupId
end

local function IsTexturePanelConfigForceVisible(button)
    if not button then
        return false
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not CooldownCompanion:IsTexturePanelGroup(group) then
        return false
    end

    return ST.IsConfigButtonForceVisible(button)
end

local function GetStandaloneTextureSettings(group)
    if CooldownCompanion:IsTriggerPanelGroup(group) then
        return CooldownCompanion:GetTriggerPanelSignalSettings(group)
    end

    if CooldownCompanion:IsTexturePanelGroup(group) then
        return CooldownCompanion:GetTexturePanelSettings(group)
    end

    return nil
end

function CooldownCompanion.GetStandaloneDisplayType(group)
    if CooldownCompanion:IsTriggerPanelGroup(group) then
        return CooldownCompanion:GetTriggerPanelDisplayType(group, true)
    end
    if CooldownCompanion:IsTexturePanelGroup(group) then
        return "texture"
    end
    return nil
end

function CooldownCompanion.ResolveActiveStandaloneDisplay(button)
    local preview = button._auraTexturePreviewSelection
    if type(preview) == "table" then
        return "texture", NormalizeAuraTextureSettings(preview)
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        return nil, nil
    end

    local displayType = CooldownCompanion.GetStandaloneDisplayType(group)
    if displayType == "icon" then
        local settings = CooldownCompanion:GetTriggerPanelIconSettings(group, false)
        if not settings or settings.manualIcon == nil then
            return "icon", nil
        end
        return "icon", settings
    end

    if displayType == "text" then
        local settings = CooldownCompanion:GetTriggerPanelTextSettings(group, false)
        if not settings or not CooldownCompanion.HasTriggerTextValue(settings) then
            return "text", nil
        end
        return "text", settings
    end

    local settings = GetStandaloneTextureSettings(group)
    if not settings or not settings.sourceType or settings.sourceValue == nil then
        return "texture", nil
    end
    if not settings.enabled and not IsStandaloneTextureEditingButton(button) then
        return "texture", nil
    end

    return "texture", settings
end

function CooldownCompanion.ApplyTriggerIconVisual(host, settings)
    local iconFrame = CooldownCompanion.EnsureTriggerIconVisual(host)
    local width, height = CooldownCompanion.GetTriggerIconDimensions(settings)
    local borderSize = settings.borderSize or 0
    local iconTint = settings.iconTintColor or { 1, 1, 1, 1 }
    local backgroundColor = settings.backgroundColor or { 0, 0, 0, 0.5 }
    local borderColor = settings.borderColor or { 0, 0, 0, 1 }

    ResetTextureIndicatorTransformState(host)
    StopAllTextureIndicatorEffects(host)
    host:SetScript("OnUpdate", nil)
    CooldownCompanion.HideStandaloneDisplayVisuals(host)

    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._activeDisplayType = "icon"

    host:SetSize(width, height)
    host.visualRoot:SetSize(width, height)

    iconFrame:SetSize(width, height)
    iconFrame.bg:SetColorTexture(
        backgroundColor[1] or 0,
        backgroundColor[2] or 0,
        backgroundColor[3] or 0,
        backgroundColor[4] ~= nil and backgroundColor[4] or 0.5
    )
    iconFrame.icon:ClearAllPoints()
    iconFrame.icon:SetPoint("TOPLEFT", borderSize, -borderSize)
    iconFrame.icon:SetPoint("BOTTOMRIGHT", -borderSize, borderSize)
    iconFrame.icon:SetTexture(settings.manualIcon)
    iconFrame.icon:SetVertexColor(
        iconTint[1] or 1,
        iconTint[2] or 1,
        iconTint[3] or 1,
        iconTint[4] ~= nil and iconTint[4] or 1
    )
    ST._ApplyIconTexCoord(iconFrame.icon, width, height)

    for _, border in ipairs(iconFrame.borderTextures) do
        border:SetColorTexture(
            borderColor[1] or 0,
            borderColor[2] or 0,
            borderColor[3] or 0,
            borderColor[4] ~= nil and borderColor[4] or 1
        )
    end
    ST._ApplyEdgePositions(iconFrame.borderTextures, iconFrame, borderSize)
    iconFrame:Show()

    return true
end

function CooldownCompanion.ApplyTriggerTextVisual(host, settings)
    local textFrame = CooldownCompanion.EnsureTriggerTextVisual(host)
    local borderSize = settings.textBorderSize or 0
    local textColor = settings.textFontColor or { 1, 1, 1, 1 }
    local backgroundColor = settings.textBgColor or { 0, 0, 0, 0 }
    local borderColor = settings.textBorderColor or { 0, 0, 0, 1 }
    local font = CooldownCompanion:FetchFont(settings.textFont or "Friz Quadrata TT")

    ResetTextureIndicatorTransformState(host)
    StopAllTextureIndicatorEffects(host)
    host:SetScript("OnUpdate", nil)
    CooldownCompanion.HideStandaloneDisplayVisuals(host)

    host._activeTextureSettings = nil
    host._activeTextureGeometry = nil
    host._activeDisplayType = "text"

    host:SetSize(settings.textWidth, settings.textHeight)
    host.visualRoot:SetSize(settings.textWidth, settings.textHeight)

    textFrame:SetSize(settings.textWidth, settings.textHeight)
    textFrame.bg:SetColorTexture(
        backgroundColor[1] or 0,
        backgroundColor[2] or 0,
        backgroundColor[3] or 0,
        backgroundColor[4] ~= nil and backgroundColor[4] or 0
    )
    for _, border in ipairs(textFrame.borderTextures) do
        border:SetColorTexture(
            borderColor[1] or 0,
            borderColor[2] or 0,
            borderColor[3] or 0,
            borderColor[4] ~= nil and borderColor[4] or 1
        )
    end
    ST._ApplyEdgePositions(textFrame.borderTextures, textFrame, borderSize)

    textFrame.text:SetFont(font, settings.textFontSize or 12, settings.textFontOutline or "OUTLINE")
    textFrame.text:SetTextColor(
        textColor[1] or 1,
        textColor[2] or 1,
        textColor[3] or 1,
        textColor[4] ~= nil and textColor[4] or 1
    )
    textFrame.text:SetJustifyH(settings.textAlignment or "LEFT")
    textFrame.text:ClearAllPoints()
    textFrame.text:SetPoint("TOPLEFT", borderSize + 2, -1)
    textFrame.text:SetPoint("BOTTOMRIGHT", -(borderSize + 2), 1)
    textFrame.text:SetText(settings.value or "")
    textFrame:Show()

    return true
end

function CooldownCompanion:UpdateAuraTextureVisual(button)
    if not button or button._isText then
        return
    end

    local group = button._groupId and ResolveGroup(button._groupId) or nil
    if not self:IsStandaloneTexturePanelGroup(group) then
        self:HideAuraTextureVisual(button)
        return
    end

    local frame = button:GetParent()
    local isTriggerPanel = self:IsTriggerPanelGroup(group)
    local driverButton = button
    if isTriggerPanel then
        driverButton = frame and frame.buttons and frame.buttons[1] or nil
        if not driverButton then
            self:HideAuraTextureVisual(button)
            return
        end
    end

    local displayType, settings = CooldownCompanion.ResolveActiveStandaloneDisplay(driverButton)
    local isEditing = IsStandaloneTextureEditingButton(driverButton)
    local isConfigForceVisible = (not isTriggerPanel) and IsTexturePanelConfigForceVisible(driverButton)
    local isUnlocked = group and group.locked == false
    local hasPreviewSelection = type(driverButton._auraTexturePreviewSelection) == "table"
    local triggerMatched = isTriggerPanel and frame and frame:IsShown() and DoesTriggerPanelMatch(frame) or false
    local triggerSoundVisible = false
    local showDisplay = false

    if settings then
        if hasPreviewSelection then
            showDisplay = true
        elseif isTriggerPanel then
            showDisplay = triggerMatched or isEditing or isUnlocked
        elseif isEditing then
            showDisplay = true
        elseif isConfigForceVisible then
            showDisplay = true
        elseif isUnlocked then
            showDisplay = true
        elseif driverButton:GetParent()
            and driverButton:GetParent():IsShown()
            and not (driverButton._rawVisibilityHidden == true) then
            showDisplay = true
        end
    end

    if isTriggerPanel and self.UpdateTriggerPanelSoundAlerts then
        triggerSoundVisible = settings ~= nil and triggerMatched and showDisplay
        self:UpdateTriggerPanelSoundAlerts(frame, group, triggerSoundVisible)
    end

    if not settings or not showDisplay then
        self:HideAuraTextureVisual(driverButton)
        if driverButton:GetAlpha() ~= 0 then
            driverButton:SetAlpha(0)
            driverButton._lastVisAlpha = 0
        end
        return
    end

    local host = EnsureAuraTextureHost(driverButton)
    local relativeFrame = UIParent
    local sharedSettings = GetStandaloneTextureSettings(group) or {
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
    }
    local hostWidth, hostHeight
    local shown = false
    local bypassModuleAlpha = hasPreviewSelection or isEditing or isConfigForceVisible or isUnlocked

    host:SetFrameStrata(driverButton:GetFrameStrata())
    host:SetFrameLevel((driverButton:GetFrameLevel() or 1) + 20)
    SyncAuraTextureControlLevels(host)

    if displayType == "texture" then
        local baseAlpha = Clamp((settings.color and settings.color[4] or 1) * settings.alpha, 0.05, 1)
        local alpha = Clamp(baseAlpha, 0, 1)
        local sourceWidth = settings.width and settings.width > 0 and settings.width or DEFAULT_TEXTURE_SIZE
        local sourceHeight = settings.height and settings.height > 0 and settings.height or DEFAULT_TEXTURE_SIZE
        local geometry = self:BuildTexturePanelGeometry(settings, sourceWidth * settings.scale, sourceHeight * settings.scale)
        hostWidth = geometry.boundsWidth
        hostHeight = geometry.boundsHeight
        host:SetSize(hostWidth, hostHeight)
        if host.visualRoot then
            host.visualRoot:SetSize(hostWidth, hostHeight)
        end
        shown = LayoutTexturePieces(host, settings, geometry, alpha)
        if shown then
            host._activeTextureSettings = settings
            host._activeTextureGeometry = geometry
            host._activeDisplayType = "texture"
            SetTextureIndicatorBaseVisuals(host)
            if not isTriggerPanel then
                ApplyTextureIndicatorEffects(host, driverButton, group)
            else
                StopAllTextureIndicatorEffects(host)
            end
        end
    elseif displayType == "icon" then
        hostWidth, hostHeight = CooldownCompanion.GetTriggerIconDimensions(settings)
        host:SetSize(hostWidth, hostHeight)
        if host.visualRoot then
            host.visualRoot:SetSize(hostWidth, hostHeight)
        end
        shown = CooldownCompanion.ApplyTriggerIconVisual(host, settings)
    elseif displayType == "text" then
        hostWidth = settings.textWidth
        hostHeight = settings.textHeight
        host:SetSize(hostWidth, hostHeight)
        if host.visualRoot then
            host.visualRoot:SetSize(hostWidth, hostHeight)
        end
        shown = CooldownCompanion.ApplyTriggerTextVisual(host, settings)
    end

    if not host._isDragging then
        host:ClearAllPoints()
        host:SetPoint(sharedSettings.point, relativeFrame, sharedSettings.relativePoint, sharedSettings.x, sharedSettings.y)
    end
    host:Show()

    if not shown then
        self:HideAuraTextureVisual(driverButton)
        if driverButton:GetAlpha() ~= 0 then
            driverButton:SetAlpha(0)
            driverButton._lastVisAlpha = 0
        end
        return
    end

    local alphaModuleId = GetTexturePanelAlphaModuleId(driverButton._groupId)
    local layoutPreviewAlpha = GetTexturePanelLayoutPreviewAlpha(driverButton)
    local visibilityAlpha = Clamp(driverButton._rawVisibilityAlphaOverride or 1, 0, 1)
    if alphaModuleId then
        if bypassModuleAlpha then
            self:UnregisterModuleAlpha(alphaModuleId, true)
            host:SetAlpha(layoutPreviewAlpha ~= nil and layoutPreviewAlpha or 1)
        else
            self:RegisterModuleAlpha(alphaModuleId, group, { host })
            local alphaState = self.alphaState and self.alphaState[alphaModuleId]
            if alphaState and alphaState.currentAlpha ~= nil then
                host:SetAlpha(Clamp(alphaState.currentAlpha * visibilityAlpha, 0, 1))
            else
                host:SetAlpha(visibilityAlpha)
            end
        end
    else
        host:SetAlpha(bypassModuleAlpha and (layoutPreviewAlpha ~= nil and layoutPreviewAlpha or 1) or visibilityAlpha)
    end

    local savedSettings = isTriggerPanel and group and group.triggerSettings and group.triggerSettings.signal or group and group.textureSettings or nil
    local hasSavedDisplay = false
    if displayType == "texture" then
        hasSavedDisplay = type(savedSettings) == "table" and savedSettings.sourceType ~= nil
    elseif displayType == "icon" then
        hasSavedDisplay = settings.manualIcon ~= nil
    elseif displayType == "text" then
        hasSavedDisplay = CooldownCompanion.HasTriggerTextValue(settings)
    end
    host._dragEnabled = isUnlocked and hasSavedDisplay
    host:EnableMouse(false)
    SetAuraTextureOutlineShown(host, false)
    if host.dragHandle and host.coordLabel then
        host.dragHandle.text:SetText(group and group.name or "Texture Panel")
        if host._isDragging then
            local _, _, _, currentX, currentY = host:GetPoint()
            UpdateTextureHostCoordLabel(host, currentX, currentY)
        else
            UpdateTextureHostCoordLabel(host, sharedSettings.x, sharedSettings.y)
        end
        local showHeader = host._dragEnabled == true
        host.dragHandle:SetShown(showHeader)
        host.coordLabel:SetShown(showHeader)
        if host.nudger then
            host.nudger:SetShown(showHeader)
        end
    end
    if driverButton:GetAlpha() ~= 0 then
        driverButton:SetAlpha(0)
        driverButton._lastVisAlpha = 0
    end
    if ST.SetFrameClickThroughRecursive then
        -- The visible texture host is intentionally non-interactive. Make every hidden
        -- backing button fully click/hover-through too, so stacked trigger rows do not
        -- leave invisible tooltip hotspots behind the visible texture.
        if isTriggerPanel and frame and type(frame.buttons) == "table" then
            for _, backingButton in ipairs(frame.buttons) do
                ST.SetFrameClickThroughRecursive(backingButton, true, true)
            end
        else
            ST.SetFrameClickThroughRecursive(driverButton, true, true)
        end
    end
end

function CooldownCompanion:RefreshAllAuraTextureVisuals()
    for _, frame in pairs(self.groupFrames or {}) do
        for _, button in ipairs(frame.buttons or {}) do
            self:UpdateAuraTextureVisual(button)
        end
    end
end
