--[[
    CooldownCompanion - ButtonFrame/Helpers
    Shared utilities, constants, and helper frames for button modules
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon

-- Localize frequently-used globals
local ipairs = ipairs
local math_floor = math.floor
local pairs = pairs
local string_format = string.format
local tostring = tostring
local tonumber = tonumber
local type = type

-- Color constants
local DEFAULT_BAR_AURA_COLOR = {0.2, 1.0, 0.2, 1.0}
local DEFAULT_BAR_PANDEMIC_COLOR = {1.0, 0.5, 0.0, 1.0}
local DEFAULT_BAR_CHARGE_COLOR = {1.0, 0.82, 0.0, 1.0}
local HEALTHSTONE_ITEM_ID = 5512
local EQUIPMENT_SLOT_TYPE = "equipmentSlot"
local EQUIPMENT_SLOT_KIND_TRINKET = "trinket"
local TRINKET_SLOT_1 = 13
local TRINKET_SLOT_2 = 14
local UNKNOWN_ICON = 134400

local EQUIPMENT_SLOT_NAMES = {
    [TRINKET_SLOT_1] = "Trinket Slot 1",
    [TRINKET_SLOT_2] = "Trinket Slot 2",
}

CooldownCompanion.EQUIPMENT_SLOT_TYPE = EQUIPMENT_SLOT_TYPE
CooldownCompanion.EQUIPMENT_SLOT_KIND_TRINKET = EQUIPMENT_SLOT_KIND_TRINKET
CooldownCompanion.TRINKET_SLOT_1 = TRINKET_SLOT_1
CooldownCompanion.TRINKET_SLOT_2 = TRINKET_SLOT_2

local function IsEquipmentSlotEntry(buttonData)
    if not (buttonData and buttonData.type == EQUIPMENT_SLOT_TYPE) then
        return false
    end
    return buttonData.itemSlotKind == EQUIPMENT_SLOT_KIND_TRINKET
        and (buttonData.itemSlot == TRINKET_SLOT_1 or buttonData.itemSlot == TRINKET_SLOT_2)
end
CooldownCompanion.IsEquipmentSlotEntry = IsEquipmentSlotEntry

local function GetEquipmentSlotDisplayName(buttonData)
    if not IsEquipmentSlotEntry(buttonData) then
        return nil
    end
    return EQUIPMENT_SLOT_NAMES[buttonData.itemSlot] or buttonData.name
end
CooldownCompanion.GetEquipmentSlotDisplayName = GetEquipmentSlotDisplayName

local function GetEntryStableKey(buttonData)
    if IsEquipmentSlotEntry(buttonData) then
        return EQUIPMENT_SLOT_TYPE .. ":" .. buttonData.itemSlotKind .. ":" .. tostring(buttonData.itemSlot)
    end
    if buttonData and buttonData.type and buttonData.id ~= nil then
        return tostring(buttonData.type) .. ":" .. tostring(buttonData.id)
    end
    return nil
end
CooldownCompanion.GetEntryStableKey = GetEntryStableKey

local function GetEntrySettingsKind(buttonData)
    if IsEquipmentSlotEntry(buttonData) then
        return EQUIPMENT_SLOT_TYPE
    end
    return buttonData and buttonData.type or nil
end
CooldownCompanion.GetEntrySettingsKind = GetEntrySettingsKind

local function IsEntryItemLike(buttonData)
    return buttonData and (buttonData.type == "item" or IsEquipmentSlotEntry(buttonData))
end
CooldownCompanion.IsEntryItemLike = IsEntryItemLike

-- Format remaining seconds for time display (shared across bar, text, and preview modes).
local DURATION_FORMAT_CLOCK = "clock"
local DURATION_FORMAT_UNITS = "units"
local DURATION_FORMAT_DECIMAL_UNDER_10 = "decimal_under_10"
local DURATION_FORMAT_DECIMAL_UNDER_60 = "decimal_under_60"

local DURATION_FORMAT_LABELS = {
    [DURATION_FORMAT_CLOCK] = "1:30 / 45 / 8",
    [DURATION_FORMAT_UNITS] = "1m 30s / 45s / 8s",
    [DURATION_FORMAT_DECIMAL_UNDER_10] = "1:30 / 45 / 8.7",
    [DURATION_FORMAT_DECIMAL_UNDER_60] = "1:30 / 45.0 / 8.7",
}

local DURATION_FORMAT_ORDER = {
    DURATION_FORMAT_CLOCK,
    DURATION_FORMAT_UNITS,
    DURATION_FORMAT_DECIMAL_UNDER_10,
    DURATION_FORMAT_DECIMAL_UNDER_60,
}

local DURATION_FORMAT_SET = {
    [DURATION_FORMAT_CLOCK] = true,
    [DURATION_FORMAT_UNITS] = true,
    [DURATION_FORMAT_DECIMAL_UNDER_10] = true,
    [DURATION_FORMAT_DECIMAL_UNDER_60] = true,
}

CooldownCompanion.DURATION_FORMAT_CLOCK = DURATION_FORMAT_CLOCK
CooldownCompanion.DURATION_FORMAT_UNITS = DURATION_FORMAT_UNITS
CooldownCompanion.DURATION_FORMAT_DECIMAL_UNDER_10 = DURATION_FORMAT_DECIMAL_UNDER_10
CooldownCompanion.DURATION_FORMAT_DECIMAL_UNDER_60 = DURATION_FORMAT_DECIMAL_UNDER_60

local secondsFormatterCache = {}
local durationTextFormatterCache = {}

local function NormalizeDurationFormat(value, decimalTimers)
    if DURATION_FORMAT_SET[value] then
        return value
    end
    if decimalTimers == true then
        return DURATION_FORMAT_DECIMAL_UNDER_60
    end
    return DURATION_FORMAT_CLOCK
end
CooldownCompanion.NormalizeDurationFormat = NormalizeDurationFormat

local function GetDurationFormat(source, decimalTimers)
    if type(source) == "table" then
        return NormalizeDurationFormat(source.durationFormat, source.decimalTimers)
    end
    return NormalizeDurationFormat(source, decimalTimers)
end
CooldownCompanion.GetDurationFormat = GetDurationFormat

function CooldownCompanion:GetDurationFormatOptions()
    return DURATION_FORMAT_LABELS, DURATION_FORMAT_ORDER
end

local function GetEnumValue(enumName, valueName, fallback)
    local enumTable = Enum and Enum[enumName]
    if enumTable and enumTable[valueName] ~= nil then
        return enumTable[valueName]
    end
    return fallback
end

local function GetUnitsSecondsFormatter()
    if secondsFormatterCache[DURATION_FORMAT_UNITS] ~= nil then
        return secondsFormatterCache[DURATION_FORMAT_UNITS]
    end

    local formatter
    if C_StringUtil and C_StringUtil.CreateSecondsFormatter then
        formatter = C_StringUtil.CreateSecondsFormatter()
        formatter:SetDefaultAbbreviation(GetEnumValue("SecondsFormatterAbbrevation", "OneLetter", 2))
        formatter:SetDesiredUnitCount(2)
        formatter:SetMinInterval(GetEnumValue("SecondsFormatterInterval", "Seconds", 0))
        formatter:SetMillisecondsThreshold(0)
        formatter:SetCanRoundUpLastUnit(false)
        formatter:SetCanRoundUpIntervals(false)
        formatter:SetConvertToLower(true)
        formatter:SetStripIntervalWhitespace(GetEnumValue("SecondsFormatterIntervalWhitespace", "StripIgnoreLocale", 2))
    end

    secondsFormatterCache[DURATION_FORMAT_UNITS] = formatter or false
    return formatter
end

local function FormatUnitsTime(seconds)
    local total = math_floor(seconds)
    if total >= 3600 then
        return string_format("%dh %dm", math_floor(total / 3600), math_floor(total / 60) % 60)
    elseif total >= 60 then
        return string_format("%dm %ds", math_floor(total / 60), total % 60)
    elseif total > 0 then
        return string_format("%ds", total)
    end
    if seconds > 0 then
        return "0s"
    end
    return ""
end

local function FormatTime(seconds, formatOrDecimal)
    if seconds >= 3600 then
        local formatKey = GetDurationFormat(formatOrDecimal)
        if formatKey == DURATION_FORMAT_UNITS then
            return FormatUnitsTime(seconds)
        end
        return string_format("%d:%02d:%02d", math_floor(seconds / 3600), math_floor(seconds / 60) % 60, math_floor(seconds % 60))
    elseif seconds >= 60 then
        local formatKey = GetDurationFormat(formatOrDecimal)
        if formatKey == DURATION_FORMAT_UNITS then
            return FormatUnitsTime(seconds)
        end
        return string_format("%d:%02d", math_floor(seconds / 60), math_floor(seconds % 60))
    elseif seconds > 0 then
        local formatKey
        if type(formatOrDecimal) == "boolean" then
            formatKey = NormalizeDurationFormat(nil, formatOrDecimal)
        else
            formatKey = GetDurationFormat(formatOrDecimal)
        end
        if formatKey == DURATION_FORMAT_UNITS then
            return FormatUnitsTime(seconds)
        elseif formatKey == DURATION_FORMAT_DECIMAL_UNDER_60
            or (formatKey == DURATION_FORMAT_DECIMAL_UNDER_10 and seconds < 10) then
            return string_format("%.1f", seconds)
        end
        return string_format("%d", math_floor(seconds))
    end
    return ""
end
CooldownCompanion.FormatTime = FormatTime

local function GetDurationSecretFormatSpec(source)
    local formatKey = GetDurationFormat(source)
    if formatKey == DURATION_FORMAT_DECIMAL_UNDER_60 then
        return "%.1f"
    end
    return "%.0f"
end
CooldownCompanion.GetDurationSecretFormatSpec = GetDurationSecretFormatSpec

local function GetDurationTextRoundingDown()
    return GetEnumValue("NumericRuleFormatRounding", "Down", 2)
end

local function FloorComponent(divisor, modulo)
    return {
        div = divisor,
        mod = modulo,
        step = 1,
        rounding = GetDurationTextRoundingDown(),
    }
end

local function AddFloorBreakpoint(formatter, threshold, format)
    formatter:AddBreakpoint({
        threshold = threshold,
        step = 1,
        rounding = GetDurationTextRoundingDown(),
        format = format,
    })
end

local function AddClockBreakpoints(formatter, decimalThreshold)
    if decimalThreshold and decimalThreshold > 0 then
        formatter:AddBreakpoint({
            threshold = 0,
            format = "%.1f",
        })
    else
        AddFloorBreakpoint(formatter, 0, "%.0f")
    end

    if decimalThreshold == 10 then
        AddFloorBreakpoint(formatter, 10, "%.0f")
    end

    formatter:AddBreakpoint({
        threshold = 60,
        format = "%.0f:%02.0f",
        components = {
            FloorComponent(60),
            FloorComponent(nil, 60),
        },
    })
    formatter:AddBreakpoint({
        threshold = 3600,
        format = "%.0f:%02.0f:%02.0f",
        components = {
            FloorComponent(3600),
            FloorComponent(60, 60),
            FloorComponent(nil, 60),
        },
    })
end

local function AddUnitsBreakpoints(formatter)
    AddFloorBreakpoint(formatter, 0, "%.0fs")
    formatter:AddBreakpoint({
        threshold = 60,
        format = "%.0fm %.0fs",
        components = {
            FloorComponent(60),
            FloorComponent(nil, 60),
        },
    })
    formatter:AddBreakpoint({
        threshold = 3600,
        format = "%.0fh %.0fm",
        components = {
            FloorComponent(3600),
            FloorComponent(60, 60),
        },
    })
end

local function CreateDurationTextFormatter(formatKey)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
        return nil
    end

    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    if not (formatter and type(formatter.AddBreakpoint) == "function") then
        return nil
    end

    if formatKey == DURATION_FORMAT_UNITS then
        AddUnitsBreakpoints(formatter)
    elseif formatKey == DURATION_FORMAT_DECIMAL_UNDER_10 then
        AddClockBreakpoints(formatter, 10)
    elseif formatKey == DURATION_FORMAT_DECIMAL_UNDER_60 then
        AddClockBreakpoints(formatter, 60)
    else
        AddClockBreakpoints(formatter)
    end

    return formatter
end

local function GetDurationTextFormatter(source)
    local formatKey = GetDurationFormat(source)
    local cached = durationTextFormatterCache[formatKey]
    if cached ~= nil then
        if cached == false then
            return nil, formatKey
        end
        return cached, formatKey
    end

    local formatter = CreateDurationTextFormatter(formatKey)
    durationTextFormatterCache[formatKey] = formatter or false
    return formatter, formatKey
end

local function DurationTextBindingHasMethods(binding)
    return binding
        and type(binding.SetFontString) == "function"
        and type(binding.SetDuration) == "function"
        and type(binding.SetFormatter) == "function"
        and type(binding.SetUpdateInterval) == "function"
        and type(binding.SetZeroDurationText) == "function"
        and type(binding.SetExpiredText) == "function"
        and type(binding.Enable) == "function"
        and type(binding.Disable) == "function"
end

local function IsDurationTextBindingSupported()
    return C_DurationUtil
        and type(C_DurationUtil.CreateDurationTextBinding) == "function"
        and C_StringUtil
        and type(C_StringUtil.CreateNumericRuleFormatter) == "function"
        or false
end
CooldownCompanion.IsDurationTextBindingSupported = IsDurationTextBindingSupported

local function UnbindDurationText(fontString, clearText)
    if not fontString then return end

    local binding = fontString._ccDurationTextBinding
    local wasActive = fontString._ccDurationTextBindingActive
    if binding and wasActive and type(binding.Disable) == "function" then
        binding:Disable()
    end

    fontString._ccDurationTextBindingActive = nil
    fontString._ccDurationTextDuration = nil
    fontString._ccDurationTextFormatterKey = nil
    if (wasActive or clearText) and fontString.SetText then
        fontString:SetText("")
    end
end
CooldownCompanion.UnbindDurationText = UnbindDurationText

local function BindDurationText(fontString, durationObj, source)
    if not (fontString and durationObj and IsDurationTextBindingSupported()) then
        UnbindDurationText(fontString, true)
        return false
    end

    local formatter, formatKey = GetDurationTextFormatter(source)
    if not formatter then
        UnbindDurationText(fontString, true)
        return false
    end

    local binding = fontString._ccDurationTextBinding
    if not binding then
        binding = C_DurationUtil.CreateDurationTextBinding()
        if not DurationTextBindingHasMethods(binding) then
            UnbindDurationText(fontString, true)
            return false
        end

        binding:SetFontString(fontString)
        binding:SetZeroDurationText("")
        binding:SetExpiredText("")
        binding:SetUpdateInterval(0.1)
        fontString._ccDurationTextBinding = binding
        fontString._ccDurationTextBindingReady = true
    elseif not fontString._ccDurationTextBindingReady and not DurationTextBindingHasMethods(binding) then
        UnbindDurationText(fontString, true)
        return false
    else
        fontString._ccDurationTextBindingReady = true
    end

    local changed = false
    if fontString._ccDurationTextFormatterKey ~= formatKey then
        binding:SetFormatter(formatter)
        fontString._ccDurationTextFormatterKey = formatKey
        changed = true
    end

    local wasActive = fontString._ccDurationTextBindingActive
    if fontString._ccDurationTextDuration ~= durationObj then
        binding:SetDuration(durationObj)
        fontString._ccDurationTextDuration = durationObj
        changed = true
    end

    if not wasActive then
        binding:Enable()
        changed = true
    end
    if changed and type(binding.UpdateFontString) == "function" then
        binding:UpdateFontString()
    end
    fontString._ccDurationTextBindingActive = true
    return true
end
CooldownCompanion.BindDurationText = BindDurationText

local function ApplyDurationFormatToCooldown(cooldown, source)
    if not cooldown then return end

    local formatKey = GetDurationFormat(source)
    local formatter
    if formatKey == DURATION_FORMAT_UNITS then
        formatter = GetUnitsSecondsFormatter()
    end

    if cooldown.SetCountdownFormatter then
        cooldown:SetCountdownFormatter(formatter or nil)
    end
    if cooldown.SetCountdownMillisecondsThreshold then
        local threshold = 0
        if formatKey == DURATION_FORMAT_DECIMAL_UNDER_10 then
            threshold = 10
        elseif formatKey == DURATION_FORMAT_DECIMAL_UNDER_60 then
            threshold = 60
        end
        cooldown:SetCountdownMillisecondsThreshold(threshold)
    end
end
CooldownCompanion.ApplyDurationFormatToCooldown = ApplyDurationFormatToCooldown

-- Apply font, size, outline, and text color to a FontString from a style table.
-- Keys are derived from prefix: e.g. prefix="charge" reads chargeFont, chargeFontSize,
-- chargeFontOutline, chargeFontColor. defaultSize overrides the 12pt fallback.
local function ApplyFontStyle(region, source, prefix, defaultSize)
    local font = CooldownCompanion:FetchFont(source[prefix .. "Font"] or "Friz Quadrata TT")
    local size = source[prefix .. "FontSize"] or defaultSize or 12
    local outline = ST.GetEffectiveFontOutline(source[prefix .. "FontOutline"] or "OUTLINE")
    region:SetFont(font, size, outline)
    ST.ApplyFontShadowForOutline(region, outline)
    local color = source[prefix .. "FontColor"] or {1, 1, 1, 1}
    region:SetTextColor(color[1], color[2], color[3], color[4])
end
CooldownCompanion.ApplyFontStyle = ApplyFontStyle

-- Cast-count text is intentionally explicit rather than auto-discovered.
-- Blizzard's cast-count/use APIs also fire for proc/override families
-- like Execute/Thunder Clap, which makes generic detection unreliable.
local CAST_COUNT_SPELL_FAMILIES = {
    [115294] = {
        buttons = {
            [115294] = true, -- Mana Tea
        },
        spells = {
            [115294] = true,
        },
    },
    [116670] = {
        buttons = {
            [116670] = true, -- Vivify button that displays Sheilun's Gift count
        },
        spells = {
            [116670] = true,
            [399491] = true, -- Sheilun's Gift cast-count spell
        },
    },
    [322101] = {
        buttons = {
            [322101] = true, -- Expel Harm
        },
        spells = {
            [322101] = true,
        },
    },
}

-- Conditional cast-count text is narrower than the always-on allowlist above.
-- These families only render count text when a vetted transform/use event has
-- opted the button in, and only for the approved live display spell(s).
local CONDITIONAL_CAST_COUNT_SPELL_FAMILIES = {
    [6343] = {
        buttons = {
            [6343] = true, -- Thunder Clap button that can transform into Thunderblast
        },
        eventSpells = {
            [6343] = true,   -- base spell payload
            [435222] = true, -- Thunderblast override payload
        },
        displaySpells = {
            [435222] = true, -- only Thunderblast should render count text
        },
    },
}

local function GetCastCountFamily(buttonData)
    if not buttonData then return nil end
    for _, family in pairs(CAST_COUNT_SPELL_FAMILIES) do
        if family.buttons[buttonData.id] then
            return family
        end
    end
    return nil
end

local function GetConditionalCastCountFamily(buttonData)
    if not buttonData then return nil end
    for _, family in pairs(CONDITIONAL_CAST_COUNT_SPELL_FAMILIES) do
        if family.buttons[buttonData.id] then
            return family
        end
    end
    return nil
end

local function HasCastCountText(buttonData)
    return GetCastCountFamily(buttonData) ~= nil
end
CooldownCompanion.HasCastCountText = HasCastCountText

local function HasConditionalCastCountText(buttonData)
    return GetConditionalCastCountFamily(buttonData) ~= nil
end
CooldownCompanion.HasConditionalCastCountText = HasConditionalCastCountText

local function GetCastCountSpellID(buttonData, currentSpellID)
    local family = GetCastCountFamily(buttonData)
    if not family then return nil end

    if currentSpellID and family.spells[currentSpellID] then
        return currentSpellID
    end

    if family.spells[buttonData.id] then
        return buttonData.id
    end

    return nil
end
CooldownCompanion.GetCastCountSpellID = GetCastCountSpellID

local function MatchesConditionalCastCountEvent(buttonData, spellID, baseSpellID)
    local family = GetConditionalCastCountFamily(buttonData)
    if not family then return false end
    return (spellID and family.eventSpells[spellID] == true)
        or (baseSpellID and family.eventSpells[baseSpellID] == true)
        or false
end
CooldownCompanion.MatchesConditionalCastCountEvent = MatchesConditionalCastCountEvent

local function GetConditionalCastCountSpellID(buttonData, currentSpellID)
    local family = GetConditionalCastCountFamily(buttonData)
    if not family or not currentSpellID then return nil end
    if family.displaySpells[currentSpellID] then
        return currentSpellID
    end
    return nil
end
CooldownCompanion.GetConditionalCastCountSpellID = GetConditionalCastCountSpellID

local function UsesChargeBehavior(buttonData)
    if not buttonData then
        return false
    end
    if buttonData.type == "spell" and buttonData.addedAs == "aura" then
        return false
    end
    return buttonData.hasCharges == true
        or buttonData._hasDisplayCount == true
        or buttonData._displayCountFamily == true
end
CooldownCompanion.UsesChargeBehavior = UsesChargeBehavior

local function HasNonChargeCountTextBehavior(buttonData)
    if not buttonData or buttonData.type ~= "spell" then
        return false
    end
    if buttonData.hasCharges == true then
        return false
    end
    return buttonData._hasDisplayCount == true
        or buttonData._displayCountFamily == true
        or HasCastCountText(buttonData)
        or HasConditionalCastCountText(buttonData)
end
CooldownCompanion.HasNonChargeCountTextBehavior = HasNonChargeCountTextBehavior

-- Count text intentionally shares the charge font lane for real charges,
-- Blizzard display/use counts, and spell cast-count stacks.
local function UsesChargeTextLane(buttonData)
    if not buttonData then return false end
    return UsesChargeBehavior(buttonData)
        or buttonData._castCountCandidate == true
        or HasCastCountText(buttonData)
        or buttonData.isPassive == true
end
CooldownCompanion.UsesChargeTextLane = UsesChargeTextLane

local function GetItemAvailableQuantity(itemID, forceChargeCount)
    itemID = tonumber(itemID)
    if not itemID then
        return 0, "stacks"
    end

    local stackCount = C_Item.GetItemCount(itemID) or 0
    local useCount = C_Item.GetItemCount(itemID, false, true) or stackCount
    if forceChargeCount then
        return useCount, "charges"
    end
    if useCount ~= stackCount then
        return useCount, "charges"
    end
    return stackCount, "stacks"
end
CooldownCompanion.GetItemAvailableQuantity = GetItemAvailableQuantity

local function HasItemFallbacks(buttonData)
    return buttonData
        and buttonData.type == "item"
        and type(buttonData.itemFallbacks) == "table"
        and #buttonData.itemFallbacks > 0
end
CooldownCompanion.HasItemFallbacks = HasItemFallbacks

local function IsDeferredHealthstoneItem(itemID)
    itemID = tonumber(itemID)
    if itemID ~= HEALTHSTONE_ITEM_ID then
        return false
    end
    if C_Item.IsUsableItem(itemID) then
        return false
    end

    local cdStart, _, enableCooldownTimer = C_Item.GetItemCooldown(itemID)
    return enableCooldownTimer == false and cdStart and cdStart > 0
end

local function UpdateItemChargeMetadata(buttonData, itemID)
    if not (buttonData and buttonData.type == "item") then
        return false
    end

    itemID = tonumber(itemID or buttonData.id)
    if not itemID then
        return false
    end

    local stackCount = C_Item.GetItemCount(itemID) or 0
    local useCount = C_Item.GetItemCount(itemID, false, true) or stackCount
    if useCount == stackCount then
        return false
    end

    buttonData.hasCharges = true
    buttonData.showChargeText = true
    if useCount > (buttonData.maxCharges or 0) then
        buttonData.maxCharges = useCount
    end
    return true
end
CooldownCompanion.UpdateItemChargeMetadata = UpdateItemChargeMetadata

local function NormalizeItemFallbackVisibilitySettings(buttonData, hasFallbacks, hadFallbacks)
    local changed = false

    if hasFallbacks then
        if buttonData.hideWhileZeroCharges then
            buttonData.hideWhileZeroStacks = true
        end
        if buttonData.desaturateWhileZeroCharges then
            buttonData.desaturateWhileZeroStacks = true
        end
        if buttonData.useBaselineAlphaFallbackZeroCharges then
            buttonData.useBaselineAlphaFallbackZeroStacks = true
        end

        if buttonData.hideWhileZeroCharges ~= nil then
            buttonData.hideWhileZeroCharges = nil
            changed = true
        end
        if buttonData.desaturateWhileZeroCharges ~= nil then
            buttonData.desaturateWhileZeroCharges = nil
            changed = true
        end
        if buttonData.useBaselineAlphaFallbackZeroCharges ~= nil then
            buttonData.useBaselineAlphaFallbackZeroCharges = nil
            changed = true
        end
    elseif hadFallbacks and buttonData.type == "item" and UsesChargeBehavior(buttonData) then
        if buttonData.hideWhileZeroStacks then
            buttonData.hideWhileZeroCharges = true
        end
        if buttonData.desaturateWhileZeroStacks then
            buttonData.desaturateWhileZeroCharges = true
        end
        if buttonData.useBaselineAlphaFallbackZeroStacks then
            buttonData.useBaselineAlphaFallbackZeroCharges = true
        end

        if buttonData.hideWhileZeroStacks ~= nil then
            buttonData.hideWhileZeroStacks = nil
            changed = true
        end
        if buttonData.desaturateWhileZeroStacks ~= nil then
            buttonData.desaturateWhileZeroStacks = nil
            changed = true
        end
        if buttonData.useBaselineAlphaFallbackZeroStacks ~= nil then
            buttonData.useBaselineAlphaFallbackZeroStacks = nil
            changed = true
        end
    end

    return changed
end
CooldownCompanion.NormalizeItemFallbackVisibilitySettings = NormalizeItemFallbackVisibilitySettings

local function NormalizeItemFallbacks(buttonData)
    if not (buttonData and type(buttonData.itemFallbacks) == "table") then
        return false
    end

    local primaryID = tonumber(buttonData.id)
    local hadFallbacks = true
    local seen = {}
    local normalized = {}
    local changed = false
    for index, rawID in ipairs(buttonData.itemFallbacks) do
        local itemID = tonumber(rawID)
        if itemID and itemID > 0 and itemID ~= primaryID and not seen[itemID] then
            seen[itemID] = true
            normalized[#normalized + 1] = itemID
            if rawID ~= itemID or #normalized ~= index then
                changed = true
            end
        else
            changed = true
        end
    end

    if #normalized == 0 then
        buttonData.itemFallbacks = nil
    else
        buttonData.itemFallbacks = normalized
    end
    if NormalizeItemFallbackVisibilitySettings(buttonData, #normalized > 0, hadFallbacks) then
        changed = true
    end
    return changed
end
CooldownCompanion.NormalizeItemFallbacks = NormalizeItemFallbacks

local function ResolveItemFallback(buttonData)
    if not (buttonData and buttonData.type == "item") then
        return nil, 0, "stacks"
    end

    local primaryID = tonumber(buttonData.id)
    local hasFallbacks = HasItemFallbacks(buttonData)
    local primaryQuantity, primaryKind = GetItemAvailableQuantity(primaryID, buttonData.hasCharges == true)
    if (primaryQuantity > 0 and not (hasFallbacks and IsDeferredHealthstoneItem(primaryID)))
            or not hasFallbacks then
        return primaryID, primaryQuantity, primaryKind
    end

    for _, rawID in ipairs(buttonData.itemFallbacks) do
        local itemID = tonumber(rawID)
        if itemID and itemID ~= primaryID then
            local quantity, quantityKind = GetItemAvailableQuantity(itemID)
            if quantity > 0 and not IsDeferredHealthstoneItem(itemID) then
                return itemID, quantity, quantityKind
            end
        end
    end

    return primaryID, primaryQuantity, primaryKind
end
CooldownCompanion.ResolveItemFallback = ResolveItemFallback

-- Position a region in the icon area of a bar button.
-- inset=0 for backgrounds/bounds, inset=borderSize for the icon texture itself.
local function SetIconAreaPoints(region, button, isVertical, iconReverse, iconSize, inset)
    region:ClearAllPoints()
    local s = iconSize - 2 * inset
    region:SetSize(s, s)
    if isVertical then
        if iconReverse then
            region:SetPoint("BOTTOM", button, "BOTTOM", 0, inset)
        else
            region:SetPoint("TOP", button, "TOP", 0, -inset)
        end
    else
        if iconReverse then
            region:SetPoint("RIGHT", button, "RIGHT", -inset, 0)
        else
            region:SetPoint("LEFT", button, "LEFT", inset, 0)
        end
    end
end

-- Position a region in the bar area of a bar button (the non-icon portion).
-- inset=0 for backgrounds/bounds, inset=borderSize for the statusBar.
local function SetBarAreaPoints(region, button, isVertical, iconReverse, barAreaLeft, barAreaTop, inset)
    region:ClearAllPoints()
    if isVertical then
        if iconReverse then
            region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, barAreaTop + inset)
        else
            region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -(barAreaTop + inset))
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
        end
    else
        if iconReverse then
            region:SetPoint("TOPLEFT", button, "TOPLEFT", inset, -inset)
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -(barAreaLeft + inset), inset)
        else
            region:SetPoint("TOPLEFT", button, "TOPLEFT", barAreaLeft + inset, -inset)
            region:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -inset, inset)
        end
    end
end

-- Anchor charge/item count text on bar buttons: relative to icon when visible, relative to bar otherwise.
local function AnchorBarCountText(button, showIcon, anchor, xOff, yOff)
    button.count:ClearAllPoints()
    if showIcon then
        button.count:SetPoint(anchor, button.icon, anchor, xOff, yOff)
    else
        button.count:SetPoint(anchor, button, anchor, xOff, yOff)
    end
end

-- Returns true if the given item ID is equippable (trinkets, weapons, armor, etc.)
-- Caches result on buttonData to avoid repeated API calls.
local function IsItemEquippable(buttonData)
    if IsEquipmentSlotEntry(buttonData) then
        return true
    end
    if not (buttonData and buttonData.id) then
        return false
    end
    local _, _, _, equipLoc = C_Item.GetItemInfoInstant(buttonData.id)
    return equipLoc ~= nil and equipLoc ~= "" and not equipLoc:find("NON_EQUIP")
end
CooldownCompanion.IsItemEquippable = IsItemEquippable

local function RequestEquipmentSlotItemData(itemLocation, itemID)
    if itemID then
        CooldownCompanion._pendingEquipmentSlotItemLoads = CooldownCompanion._pendingEquipmentSlotItemLoads or {}
        CooldownCompanion._pendingEquipmentSlotItemLoads[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    elseif itemLocation then
        CooldownCompanion._pendingEquipmentSlotLocationLoad = true
        C_Item.RequestLoadItemData(itemLocation)
    end
end

local function ResolveEquipmentSlotItem(buttonData, requestLoad)
    local result = {
        isEquipmentSlot = true,
        itemSlot = buttonData and buttonData.itemSlot or nil,
        itemSlotKind = buttonData and buttonData.itemSlotKind or nil,
        name = GetEquipmentSlotDisplayName(buttonData),
        icon = UNKNOWN_ICON,
        trackable = false,
        availableQuantity = 0,
        quantityKind = "equipment",
    }

    if not IsEquipmentSlotEntry(buttonData) then
        result.reason = "invalid"
        return result
    end

    local itemLocation = ItemLocation:CreateFromEquipmentSlot(buttonData.itemSlot)
    result.itemLocation = itemLocation
    if not C_Item.DoesItemExist(itemLocation) then
        result.reason = "empty"
        return result
    end

    local itemID = C_Item.GetItemID(itemLocation)
    result.itemID = itemID
    if not itemID then
        result.reason = "loading"
        if requestLoad then
            RequestEquipmentSlotItemData(itemLocation)
        end
        return result
    end

    result.icon = C_Item.GetItemIcon(itemLocation) or C_Item.GetItemIconByID(itemID) or UNKNOWN_ICON
    result.itemName = C_Item.GetItemName(itemLocation) or C_Item.GetItemNameByID(itemID)
    result.availableQuantity = 1

    if C_Item.IsItemDataCached(itemLocation) == false or C_Item.IsItemDataCachedByID(itemID) == false then
        result.reason = "loading"
        if requestLoad then
            RequestEquipmentSlotItemData(itemLocation, itemID)
        end
        return result
    end

    local inventoryType = C_Item.GetItemInventoryType(itemLocation)
    result.inventoryType = inventoryType
    if inventoryType ~= Enum.InventoryType.IndexTrinketType then
        result.reason = "not-trinket"
        return result
    end

    local spellName, spellID = C_Item.GetItemSpell(itemID)
    result.itemSpellName = spellName
    result.itemSpellID = spellID
    if not spellName then
        result.reason = "no-use"
        return result
    end

    result.trackable = true
    result.reason = "resolved"
    return result
end

local function ResolveEffectiveItem(buttonData, requestLoad)
    if IsEquipmentSlotEntry(buttonData) then
        return ResolveEquipmentSlotItem(buttonData, requestLoad)
    end
    if not (buttonData and buttonData.type == "item") then
        return nil
    end

    local resolvedItemID, availableQuantity, quantityKind = ResolveItemFallback(buttonData)
    local itemID = resolvedItemID or buttonData.id
    return {
        itemID = itemID,
        itemName = itemID and C_Item.GetItemNameByID(itemID) or nil,
        icon = itemID and C_Item.GetItemIconByID(itemID) or UNKNOWN_ICON,
        trackable = itemID ~= nil,
        availableQuantity = availableQuantity or 0,
        quantityKind = quantityKind or "stacks",
        isEquipmentSlot = false,
    }
end
CooldownCompanion.ResolveEffectiveItem = ResolveEffectiveItem

-- Apply configurable strata (frame level) ordering to button sub-elements.
-- order: array of 6 keys or nil for default.
-- Index 1 = lowest layer (baseLevel+1), index 6 = highest (baseLevel+6).
-- Loss of Control is always baseLevel+7 (above all configurable elements).
local function ApplyStrataOrder(button, order)
    if not order or #order ~= #ST.DEFAULT_STRATA_ORDER then
        order = ST.DEFAULT_STRATA_ORDER
    end
    local baseLevel = button:GetFrameLevel()

    -- Map element keys to their frames
    local frameMap = {
        cooldown = {button.cooldown},
        chargeText = {button.overlayFrame},
        procGlow = {
            button.procGlow and button.procGlow.solidFrame,
            button.procGlow and button.procGlow.procFrame,
        },
        auraGlow = {
            button.auraGlow and button.auraGlow.solidFrame,
            button.auraGlow and button.auraGlow.procFrame,
        },
        readyGlow = {
            button.readyGlow and button.readyGlow.solidFrame,
            button.readyGlow and button.readyGlow.procFrame,
        },
        assistedHighlight = {
            button.assistedHighlight and button.assistedHighlight.solidFrame,
            button.assistedHighlight and button.assistedHighlight.blizzardFrame,
            button.assistedHighlight and button.assistedHighlight.procFrame,
        },
    }

    for i, key in ipairs(order) do
        local frames = frameMap[key]
        if frames then
            for _, frame in ipairs(frames) do
                if frame then
                    frame:SetFrameLevel(baseLevel + i)
                end
            end
        end
    end

    -- LoC always on top
    if button.locCooldown then
        button.locCooldown:SetFrameLevel(baseLevel + #ST.DEFAULT_STRATA_ORDER + 1)
    end
end

-- Apply edge positions to 4 border/highlight textures using the shared spec
local function ApplyEdgePositions(textures, button, size)
    ST.PositionBorderTextures(textures, button, size, ST.BORDER_RENDER_MODE_CUSTOM)
end

local function ApplyBorderEdgePositions(textures, button, size, renderMode)
    ST.PositionBorderTextures(textures, button, size, ST.GetEffectiveBorderRenderMode(renderMode, nil, size))
end

-- Apply aspect-ratio-aware texture cropping to an icon.
-- Crops the narrower dimension so the icon image stays undistorted.
local function ApplyIconTexCoord(icon, width, height)
    if width ~= height then
        local texMin, texMax = 0.08, 0.92
        local texRange = texMax - texMin
        local aspectRatio = width / height
        if aspectRatio > 1.0 then
            local crop = (texRange - texRange / aspectRatio) / 2
            icon:SetTexCoord(texMin, texMax, texMin + crop, texMax - crop)
        else
            local crop = (texRange - texRange * aspectRatio) / 2
            icon:SetTexCoord(texMin + crop, texMax - crop, texMin, texMax)
        end
    else
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end

-- Shared click-through helpers from Utils.lua
local SetFrameClickThrough = ST.SetFrameClickThrough
local SetFrameClickThroughRecursive = ST.SetFrameClickThroughRecursive

-- Fit a Blizzard highlight template frame to a button.
-- The flipbook texture must overhang the button edges to create the border effect.
-- Original template: 45x45 frame, 66x66 texture => ~23% overhang per side.
-- Per-axis overhang keeps the border flush with non-square icons.
local function FitHighlightFrame(frame, button, overhangPct)
    local w, h = button:GetSize()
    local pct = (overhangPct or 32) / 100
    local overhangW = w * pct
    local overhangH = h * pct

    frame:ClearAllPoints()
    frame:SetPoint("CENTER", button, "CENTER")
    frame:SetSize(w, h)

    -- Resize child regions (flipbook textures) to overhang the frame edges
    for _, region in ipairs({frame:GetRegions()}) do
        if region.ClearAllPoints then
            region:ClearAllPoints()
            region:SetPoint("CENTER", frame, "CENTER")
            region:SetSize(w + overhangW * 2, h + overhangH * 2)
        end
    end
    -- Also handle textures nested inside child frames
    for _, child in ipairs({frame:GetChildren()}) do
        child:ClearAllPoints()
        child:SetPoint("CENTER", frame, "CENTER")
        child:SetSize(w + overhangW * 2, h + overhangH * 2)
        for _, region in ipairs({child:GetRegions()}) do
            if region.ClearAllPoints then
                region:ClearAllPoints()
                region:SetAllPoints(child)
            end
        end
    end
end

-- F3: native cooldown-expiry signal. One shared handler for every button's
-- primary Cooldown widget; marks the scheduler dirty so expiry is a signal
-- rather than something the clean ticker polls for. Reads no game or widget
-- state at fire time, so it is safe to run re-entrantly mid-pass.
function ST.OnButtonCooldownDone(cooldown)
    CooldownCompanion:MarkCooldownsDirty("cd-done")
end

-- Exports
ST._DEFAULT_BAR_AURA_COLOR = DEFAULT_BAR_AURA_COLOR
ST._DEFAULT_BAR_PANDEMIC_COLOR = DEFAULT_BAR_PANDEMIC_COLOR
ST._DEFAULT_BAR_CHARGE_COLOR = DEFAULT_BAR_CHARGE_COLOR
ST._SetIconAreaPoints = SetIconAreaPoints
ST._SetBarAreaPoints = SetBarAreaPoints
ST._AnchorBarCountText = AnchorBarCountText
ST._ApplyStrataOrder = ApplyStrataOrder
ST._ApplyEdgePositions = ApplyEdgePositions
ST._ApplyBorderEdgePositions = ApplyBorderEdgePositions
ST._ApplyIconTexCoord = ApplyIconTexCoord
ST._FitHighlightFrame = FitHighlightFrame
