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

--------------------------------------------------------------------------------
-- Entry Pings (12.1 ping system)
--
-- Mirrors Blizzard's PingableType contract (Blizzard_SharedXML/PingableType.lua):
-- the hover surface carries a "ping-receiver" attribute and implements
-- GetIsPingable / GetAllowRadialWheel / GetTargetInfo. Blizzard's PingManager
-- finds the surface via a secure hit test, then calls these methods insecurely
-- (securecallfunction) and performs the secure send itself, so no C_PingSecure
-- access is needed. Target info is plain config-owned IDs; nothing secret
-- crosses the boundary.
--------------------------------------------------------------------------------

-- Cooldown-style entries only: aura declarations are not pingable, mirroring
-- the Cooldown Manager, which pings its Essential/Utility viewers but never
-- tracked buffs (owner ruling 2026-07-31). Spell entries that also track their
-- aura keep their cooldown identity and stay pingable.
local function IsEntryPingEligible(buttonData)
    if not buttonData or buttonData.addedAs == "aura" then
        return false
    end
    return buttonData.type == "spell" or IsEntryItemLike(buttonData)
end
CooldownCompanion.IsEntryPingEligible = IsEntryPingEligible

-- Same resolution the tooltip path uses (Glows.lua ShowButtonTooltip): the
-- ping should name what the tooltip shows.
local function ResolvePingTarget(owner)
    local buttonData = owner.buttonData
    if not IsEntryPingEligible(buttonData) then
        return nil
    end
    -- A Rotation Assistant placeholder stores the fallback action spell as its
    -- id; never announce that while no recommendation exists.
    if buttonData._rotationAssistantMissing then
        return nil
    end
    if buttonData.type == "spell" then
        local spellID = tonumber(owner._displaySpellId or buttonData.id)
        if spellID then
            return "spellID", spellID
        end
        return nil
    end
    local itemID = tonumber(owner._resolvedItemId or buttonData.id)
    if itemID then
        return "itemID", itemID
    end
    return nil
end

-- Live pingability, re-read at ping time (same pattern as
-- PrepareButtonTooltip). Answering false here does NOT pass the ping through
-- to the world: Blizzard treats a found receiver that declines as blocking UI
-- and shows its ping-failed message. Pass-through requires the attribute to
-- be absent, which the style passes and visibility edges manage; these checks
-- are the backstop for any stale window between those passes.
local function IsPingAllowedForButton(owner)
    local groups = CooldownCompanion.db and CooldownCompanion.db.profile.groups
    local group = groups and owner._groupId and groups[owner._groupId]
    local style = group and group.style
    if not (style ~= nil and style.allowPings == true) then
        return false
    end
    if owner._visibilityHidden then
        return false
    end
    if CooldownCompanion.IsStandaloneTexturePanelGroup ~= nil
        and CooldownCompanion:IsStandaloneTexturePanelGroup(group) then
        return false
    end
    return true
end

local function Ping_GetIsPingable(self)
    local owner = self._ccPingOwner or self
    return IsPingAllowedForButton(owner) and ResolvePingTarget(owner) ~= nil
end

local function Ping_GetAllowRadialWheel(self)
    -- Contextual pings only, matching Cooldown Manager items.
    return false
end

local function Ping_GetTargetInfo(self)
    local owner = self._ccPingOwner or self
    local info = {}
    local key, id = ResolvePingTarget(owner)
    if key then
        info[key] = id
    end
    return info
end

-- Install or remove the ping receiver on a hover surface. `owner` is the entry
-- button carrying buttonData; omit it when the surface is the button itself
-- (icon mode). Bar mode passes its _iconBounds child as the surface.
function ST.SetEntryPingReceiver(surface, enabled, owner)
    if not surface or not surface.SetAttribute then
        return
    end
    if enabled then
        surface._ccPingOwner = (owner ~= nil and owner ~= surface) and owner or nil
        surface.GetIsPingable = Ping_GetIsPingable
        surface.GetAllowRadialWheel = Ping_GetAllowRadialWheel
        surface.GetTargetInfo = Ping_GetTargetInfo
        surface:SetAttribute("ping-receiver", true)
    elseif surface.GetIsPingable ~= nil then
        surface._ccPingOwner = nil
        surface.GetIsPingable = nil
        surface.GetAllowRadialWheel = nil
        surface.GetTargetInfo = nil
        surface:SetAttribute("ping-receiver", nil)
    end
end

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

-- Low Time Threshold (cooldown texts ONLY — aura duration text keeps pandemic
-- as its urgency system; owner ruling 2026-08-15). Reads the three panel-owned
-- keys beside durationFormat. Returns nil when the feature is off, else:
-- threshold seconds, decimals flag, and the color as a raw "rrggbb" hex (nil
-- when no recolor). Only surfaces that are structurally cooldown-side may call
-- the allowLowTime/FormatCooldownTime variants below.
local function LowTimeHex(color)
    if type(color) ~= "table" then return nil end
    return string_format("%02x%02x%02x",
        math_floor((color[1] or 1) * 255 + 0.5),
        math_floor((color[2] or 0) * 255 + 0.5),
        math_floor((color[3] or 0) * 255 + 0.5))
end

-- Fifth/sixth returns: the optional SECOND, more urgent window — its own
-- color below threshold2 seconds. Only honored when strictly inside the
-- first window (threshold2 < threshold); anything else is ignored rather
-- than guessed at.
local function GetDurationLowTime(source)
    if type(source) ~= "table" then return nil end
    local threshold = tonumber(source.durationLowTimeThreshold)
    if not threshold or threshold <= 0 then return nil end
    local decimals = source.durationLowTimeDecimals == true
    local colorHex = LowTimeHex(source.durationLowTimeColor)
    if not decimals and not colorHex then return nil end

    local threshold2 = tonumber(source.durationLowTimeThreshold2)
    local colorHex2 = LowTimeHex(source.durationLowTimeColor2)
    if not (threshold2 and threshold2 > 0 and threshold2 < threshold and colorHex2) then
        threshold2, colorHex2 = nil, nil
    end
    return threshold, decimals, colorHex, threshold2, colorHex2
end
CooldownCompanion.GetDurationLowTime = GetDurationLowTime

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

-- Manual-path twin of the low-time brackets, for COOLDOWN text call sites
-- that format plain (non-secret) values. FormatTime itself stays untouched:
-- aura-side callers share it and must never pick the low-time look up.
local function FormatCooldownTime(seconds, source)
    local text = FormatTime(seconds, source)
    local threshold, decimals, colorHex, threshold2, colorHex2 = GetDurationLowTime(source)
    if not threshold or text == "" or not (seconds > 0) or seconds >= threshold then
        return text
    end
    if decimals and not text:find(".", 1, true) then
        if GetDurationFormat(source) == DURATION_FORMAT_UNITS then
            text = string_format("%.1fs", seconds)
        else
            text = string_format("%.1f", seconds)
        end
    end
    local hex = colorHex
    if threshold2 and colorHex2 and seconds < threshold2 then
        hex = colorHex2
    end
    if hex then
        text = "|cff" .. hex .. text .. "|r"
    end
    return text
end
CooldownCompanion.FormatCooldownTime = FormatCooldownTime

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

local function FloorBreakpoint(threshold, format)
    return {
        threshold = threshold,
        step = 1,
        rounding = GetDurationTextRoundingDown(),
        format = format,
    }
end

-- One ascending breakpoint list per format key: the single definition of what
-- each Duration Format looks like for NumericRuleFormatter consumers. The
-- cooldown text formatter below builds straight from it, and the aura display
-- reads it to derive per-spell pandemic marker formatters that keep the same
-- shape. Cached lists are shared and must never be mutated.
local function BuildDurationFormatBrackets(formatKey)
    local brackets = {}

    if formatKey == DURATION_FORMAT_UNITS then
        brackets[1] = FloorBreakpoint(0, "%.0fs")
        brackets[2] = {
            threshold = 60,
            format = "%.0fm %.0fs",
            components = {
                FloorComponent(60),
                FloorComponent(nil, 60),
            },
        }
        brackets[3] = {
            threshold = 3600,
            format = "%.0fh %.0fm",
            components = {
                FloorComponent(3600),
                FloorComponent(60, 60),
            },
        }
        return brackets
    end

    if formatKey == DURATION_FORMAT_DECIMAL_UNDER_10 then
        brackets[#brackets + 1] = { threshold = 0, format = "%.1f" }
        brackets[#brackets + 1] = FloorBreakpoint(10, "%.0f")
    elseif formatKey == DURATION_FORMAT_DECIMAL_UNDER_60 then
        brackets[#brackets + 1] = { threshold = 0, format = "%.1f" }
    else
        brackets[#brackets + 1] = FloorBreakpoint(0, "%.0f")
    end
    brackets[#brackets + 1] = {
        threshold = 60,
        format = "%.0f:%02.0f",
        components = {
            FloorComponent(60),
            FloorComponent(nil, 60),
        },
    }
    brackets[#brackets + 1] = {
        threshold = 3600,
        format = "%.0f:%02.0f:%02.0f",
        components = {
            FloorComponent(3600),
            FloorComponent(60, 60),
            FloorComponent(nil, 60),
        },
    }
    return brackets
end

local durationFormatBracketsCache = {}

local function GetDurationFormatBrackets(source)
    local formatKey = GetDurationFormat(source)
    local brackets = durationFormatBracketsCache[formatKey]
    if not brackets then
        brackets = BuildDurationFormatBrackets(formatKey)
        durationFormatBracketsCache[formatKey] = brackets
    end
    return brackets, formatKey
end
CooldownCompanion.GetDurationFormatBrackets = GetDurationFormatBrackets

-- Low-time overlay over a format's bracket list. Built from FRESH bracket
-- tables (BuildDurationFormatBrackets constructs new ones per call; the shared
-- cached lists are never touched). The [0, threshold) region keeps the
-- format's own zero-bracket shape — decimals only upgrade "%.0f" to "%.1f",
-- and the color escape wraps whatever the format already renders there — then
-- the stock zero bracket re-enters at the threshold so text returns to the
-- group's normal look the moment the low window is left. Base brackets whose
-- threshold falls inside the low window are re-thresholded to its edge (the
-- config slider caps well below the 60s clock boundary, so in practice this
-- only ever moves a decimal_under_10 boundary).
-- Shallow bracket copy: zero brackets carry no components table; higher
-- brackets' components are shared by reference and never mutated.
local function CopyBracket(bracket)
    local copy = {}
    for k, v in pairs(bracket) do
        copy[k] = v
    end
    return copy
end

local function BuildLowTimeBrackets(formatKey, threshold, decimals, colorHex, threshold2, colorHex2)
    local base = BuildDurationFormatBrackets(formatKey)

    -- Colored copy of one base segment, clipped to start at `at`. Force
    -- Decimals upgrades plain-seconds formats only: a component format like
    -- m:ss would have its FIRST field mangled by the same substitution
    -- (unreachable at the 30s threshold cap, guarded anyway).
    local function WindowBracket(segment, at, hex)
        local b = CopyBracket(segment)
        b.threshold = at
        local fmt = b.format
        if decimals and not b.components then
            local upgraded = fmt:gsub("%%%.0f", "%%.1f", 1)
            if upgraded ~= fmt then
                fmt = upgraded
                -- FloorBreakpoint carries step=1 rounding-down; a floored
                -- value renders ".0" forever, so the step goes with the
                -- upgrade.
                b.step = nil
                b.rounding = nil
            end
        end
        if hex then
            fmt = "|cff" .. hex .. fmt .. "|r"
        end
        b.format = fmt
        return b
    end

    -- The low window(s): [0, threshold2) in color2, [threshold2, threshold)
    -- in color1 (GetDurationLowTime guarantees threshold2 < threshold when
    -- present). Base-format transitions INSIDE a window are preserved and
    -- recolored (review 2026-08-16): the feature colors text, it must never
    -- change which format renders — only Force Decimals may do that, and it
    -- is applied per segment so manual and bound paths agree.
    local windows = {}
    if threshold2 and colorHex2 then
        windows[1] = { lo = 0, hi = threshold2, hex = colorHex2 }
        windows[2] = { lo = threshold2, hi = threshold, hex = colorHex }
    else
        windows[1] = { lo = 0, hi = threshold, hex = colorHex }
    end

    local out = {}
    for _, window in ipairs(windows) do
        for i = 1, #base do
            local segStart = base[i].threshold
            local segEnd = base[i + 1] and base[i + 1].threshold
            if segStart < window.hi and (not segEnd or segEnd > window.lo) then
                out[#out + 1] = WindowBracket(base[i], math.max(segStart, window.lo), window.hex)
            end
        end
    end

    -- Stock re-entry at the threshold edge — an unmodified copy of the base
    -- segment containing it — then every base bracket beyond it, unchanged.
    local tail = {}
    local containing = base[1]
    for i = 1, #base do
        if base[i].threshold <= threshold then
            containing = base[i]
        else
            tail[#tail + 1] = base[i]
        end
    end
    local reentry = CopyBracket(containing)
    reentry.threshold = threshold
    out[#out + 1] = reentry
    for i = 1, #tail do
        out[#out + 1] = tail[i]
    end
    return out
end

local function CreateDurationTextFormatter(formatKey, lowThreshold, lowDecimals, lowColorHex, lowThreshold2, lowColorHex2)
    if not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
        return nil
    end

    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    if not (formatter and type(formatter.AddBreakpoint) == "function") then
        return nil
    end

    local brackets
    if lowThreshold then
        brackets = BuildLowTimeBrackets(formatKey, lowThreshold, lowDecimals, lowColorHex, lowThreshold2, lowColorHex2)
    else
        brackets = BuildDurationFormatBrackets(formatKey)
    end
    for _, breakpoint in ipairs(brackets) do
        formatter:AddBreakpoint(breakpoint)
    end

    return formatter
end

-- Second return is the CACHE key (formatKey when low-time is off, composite
-- when on) — BindDurationText uses it for change detection, so a low-time
-- config edit re-applies the formatter even when the format key is unchanged.
-- allowLowTime must only be passed by cooldown-side surfaces.
local function GetDurationTextFormatter(source, allowLowTime)
    local formatKey = GetDurationFormat(source)
    local cacheKey = formatKey
    local lowThreshold, lowDecimals, lowColorHex, lowThreshold2, lowColorHex2
    if allowLowTime then
        lowThreshold, lowDecimals, lowColorHex, lowThreshold2, lowColorHex2 = GetDurationLowTime(source)
        if lowThreshold then
            cacheKey = formatKey .. "#low" .. lowThreshold
                .. (lowDecimals and "d" or "") .. (lowColorHex or "")
            if lowThreshold2 then
                cacheKey = cacheKey .. "#2:" .. lowThreshold2 .. (lowColorHex2 or "")
            end
        end
    end

    local cached = durationTextFormatterCache[cacheKey]
    if cached ~= nil then
        if cached == false then
            return nil, cacheKey
        end
        return cached, cacheKey
    end

    local formatter = CreateDurationTextFormatter(formatKey, lowThreshold, lowDecimals, lowColorHex, lowThreshold2, lowColorHex2)
    durationTextFormatterCache[cacheKey] = formatter or false
    return formatter, cacheKey
end
CooldownCompanion.GetDurationTextFormatter = GetDurationTextFormatter

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

-- allowLowTime: pass true ONLY from cooldown-text call sites (bar-mode cd
-- text, custom-bar cd text). Aura-side callers must omit it — the low-time
-- feature is cooldown-only by owner ruling (auras have pandemic).
local function BindDurationText(fontString, durationObj, source, allowLowTime)
    if not (fontString and durationObj and IsDurationTextBindingSupported()) then
        UnbindDurationText(fontString, true)
        return false
    end

    local formatter, formatKey = GetDurationTextFormatter(source, allowLowTime)
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
    local lowThreshold, lowDecimals, lowColorHex = GetDurationLowTime(source)

    -- Low-time COLOR is the one thing native countdown rendering cannot do:
    -- it needs the bracket formatter (which reproduces the format's whole
    -- shape, escapes baked into the low bracket). Color off — or a client
    -- without rule formatters — keeps the legacy nil-formatter path
    -- byte-for-byte: that is the feature's kill switch (pandemic
    -- fragile-surface precedent). Decimals-only rides the native
    -- milliseconds threshold below and adds no new surface.
    local formatter
    if lowColorHex then
        formatter = GetDurationTextFormatter(source, true)
    end
    if not formatter and formatKey == DURATION_FORMAT_UNITS then
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
        if lowDecimals and lowThreshold and lowThreshold > threshold then
            threshold = lowThreshold
        end
        cooldown:SetCountdownMillisecondsThreshold(threshold)
    end
end
CooldownCompanion.ApplyDurationFormatToCooldown = ApplyDurationFormatToCooldown

-- Advertised config default for aura duration text: the color pickers offer
-- this same literal, and saved styles carry no key until the user changes it,
-- so every aura-text styling site must fall back to this instead of white.
CooldownCompanion.DEFAULT_AURA_TEXT_COLOR = {0, 0.925, 1, 1}

-- Apply font, size, outline, and text color to a FontString from a style table.
-- Keys are derived from prefix: e.g. prefix="charge" reads chargeFont, chargeFontSize,
-- chargeFontOutline, chargeFontColor. defaultSize overrides the 12pt fallback and
-- defaultColor the white fallback.
local function ApplyFontStyle(region, source, prefix, defaultSize, defaultColor)
    local font = CooldownCompanion:FetchFont(source[prefix .. "Font"] or "Friz Quadrata TT")
    local size = source[prefix .. "FontSize"] or defaultSize or 12
    local outline = ST.GetEffectiveFontOutline(source[prefix .. "FontOutline"] or "OUTLINE")
    region:SetFont(font, size, outline)
    ST.ApplyFontShadowForOutline(region, outline)
    local color = source[prefix .. "FontColor"] or defaultColor or {1, 1, 1, 1}
    region:SetTextColor(color[1], color[2], color[3], color[4])
end
CooldownCompanion.ApplyFontStyle = ApplyFontStyle

-- Stack threshold preview stand-in (2026-08-15 program): the simulated
-- count and its color for config previews of the aura stack text. Live
-- text is colored engine-side (NumericRuleFormatter breakpoints) because
-- the real count is secret; this mirrors those breakpoints for a PLAIN
-- pretend number, preferring the most interesting configured state (max
-- when the max color is on, else the threshold) so the feature shows in
-- previews. Defined here, rather than in the preview file, to stay below its
-- Lua 5.1 local-variable ceiling.
function CooldownCompanion:GetAuraStackPreviewCountAndColor(buttonData, style, fallbackText)
    -- Thin reader of the ONE policy resolver (review batch 2026-08-15):
    -- the clamp/prefer rules live there, so the preview can never disagree
    -- with the live formatter about where a color starts.
    local policy = self:ResolveAuraStackThresholdPolicy(buttonData)
    local count = tonumber(fallbackText) or 3
    local color
    if policy then
        if policy.maxOn then
            count = policy.maxStacks
        elseif policy.threshold then
            count = policy.threshold
        end
        if policy.maxOn and count >= policy.maxStacks then
            color = policy.maxColor
        elseif policy.threshold and count >= policy.threshold then
            color = policy.thresholdColor
        end
    end
    color = color or (style and style.auraStackFontColor) or { 1, 1, 1, 1 }
    return tostring(count), color[1], color[2], color[3], color[4] or 1
end

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

local STRATA_VALID_KEYS = {}
for _, key in ipairs(ST.DEFAULT_STRATA_ORDER) do
    STRATA_VALID_KEYS[key] = true
end

-- Will the renderer actually honor this saved order? Length alone is not
-- enough: an old import can carry the right count with a retired key in it (the
-- aura display replaced "auraGlow"), which would leave a layer unassigned.
--
-- Exported, because the profile normalizer and the preset-apply path have to
-- test the SAME definition of valid. When they each kept their own length
-- check, a saved order could be rejected here while both of those still
-- believed it was fine, leaving the Custom Icon Strata checkbox reading ON with
-- none of its values in effect.
local function IsUsableStrataOrder(order)
    if type(order) ~= "table" or #order ~= #ST.DEFAULT_STRATA_ORDER then
        return false
    end
    local seen = {}
    for _, key in ipairs(order) do
        if not STRATA_VALID_KEYS[key] or seen[key] then
            return false
        end
        seen[key] = true
    end
    return true
end

-- Resolve the frame level of every configurable icon layer.
--
-- Slots are NOT one level each: ST.STRATA_SLOT_SPANS gives the aura display a
-- reserved band because its subtree occupies five levels (Core/Init.lua has
-- the map). Levels therefore accumulate spans instead of using the slot index,
-- which is what lets a slot sit genuinely ABOVE the whole aura display.
--
-- Returns (levels, top): a key -> level map, and the highest occupied level so
-- the pinned elements above the stack derive from it instead of repeating a
-- magic offset. THE single source of truth for icon button levels — callers
-- outside this file (EnsureAuraLayer) ask here rather than computing their own.
local function ResolveStrataLevels(button, order)
    if not IsUsableStrataOrder(order) then
        order = ST.DEFAULT_STRATA_ORDER
    end
    local levels = {}
    local cursor = button:GetFrameLevel()
    for _, key in ipairs(order) do
        cursor = cursor + 1
        levels[key] = cursor
        cursor = cursor + (ST.STRATA_SLOT_SPANS[key] or 1) - 1
    end
    return levels, cursor
end

-- Apply the resolved levels to a button's sub-elements.
local function ApplyStrataOrder(button, order)
    local levels, top = ResolveStrataLevels(button, order)

    -- Map element keys to their frames
    local frameMap = {
        iconFill = {button.iconFill},
        cooldown = {button.cooldown},
        chargeText = {button.overlayFrame},
        auraDisplay = {button.auraLayer},
        procGlow = {
            button.procGlow and button.procGlow.solidFrame,
            button.procGlow and button.procGlow.procFrame,
        },
        readyGlow = {
            button.readyGlow and button.readyGlow.solidFrame,
            button.readyGlow and button.readyGlow.procFrame,
        },
        keyPressHighlight = {
            button.keyPressHighlight and button.keyPressHighlight.solidFrame,
            button.keyPressHighlight and button.keyPressHighlight.procFrame,
        },
        assistedHighlight = {
            button.assistedHighlight and button.assistedHighlight.solidFrame,
            button.assistedHighlight and button.assistedHighlight.blizzardFrame,
            button.assistedHighlight and button.assistedHighlight.procFrame,
        },
    }

    for key, frames in pairs(frameMap) do
        local level = levels[key]
        if level then
            for _, frame in ipairs(frames) do
                if frame then
                    frame:SetFrameLevel(level)
                end
            end
        end
    end

    -- Pinned above the whole configurable stack, derived from its top rather
    -- than hardcoded. Loss of Control is a "you cannot act" alert and must
    -- never be buried, not even by an aura display. The pinned text host rides
    -- above even that: it carries keybind text (owner ruling: never underneath
    -- anything) and the countdown text when the While Aura Active keep-text
    -- state lifts it.
    if button.iconGCDCooldown then
        button.iconGCDCooldown:SetFrameLevel(top + 1)
    end
    if button.locCooldown then
        button.locCooldown:SetFrameLevel(top + 2)
    end
    if button.pinnedTextFrame then
        button.pinnedTextFrame:SetFrameLevel(top + 3)
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
-- zoom (0-100, optional) shrinks the crop window toward the center on top of
-- the standard 0.08-0.92 border trim: the frame keeps its size, the artwork
-- enlarges. Clamped below 100 so the window can never collapse to a point.
local function ApplyIconTexCoord(icon, width, height, zoom)
    zoom = tonumber(zoom) or 0
    if zoom < 0 then zoom = 0 elseif zoom > 99 then zoom = 99 end
    local halfRange = 0.42 * (1 - zoom / 100)
    local texMin, texMax = 0.5 - halfRange, 0.5 + halfRange
    if width ~= height then
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
        icon:SetTexCoord(texMin, texMax, texMin, texMax)
    end
end

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
ST._DEFAULT_BAR_CHARGE_COLOR = DEFAULT_BAR_CHARGE_COLOR
ST._SetIconAreaPoints = SetIconAreaPoints
ST._SetBarAreaPoints = SetBarAreaPoints
ST._AnchorBarCountText = AnchorBarCountText
ST._ApplyStrataOrder = ApplyStrataOrder
ST._ResolveStrataLevels = ResolveStrataLevels
ST._IsUsableStrataOrder = IsUsableStrataOrder
ST._ApplyEdgePositions = ApplyEdgePositions
ST._ApplyBorderEdgePositions = ApplyBorderEdgePositions
ST._ApplyIconTexCoord = ApplyIconTexCoord
ST._FitHighlightFrame = FitHighlightFrame
