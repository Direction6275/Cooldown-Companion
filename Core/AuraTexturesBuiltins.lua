--[[
    CooldownCompanion - Core/AuraTexturesBuiltins.lua
    Hand-authored builtin atlas library for the aura texture picker.
]]

local ADDON_NAME, ST = ...
local AT = ST._AT

local ipairs = ipairs
local string_lower = string.lower
local string_trim = strtrim
local type = type

local FILTER_SYMBOLS = AT.FILTER_SYMBOLS
local FILTER_OTHER = AT.FILTER_OTHER
local BUILTIN_LIBRARY = AT.BUILTIN_LIBRARY

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
