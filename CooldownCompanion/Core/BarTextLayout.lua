-- Shared, write-only bar text layout. Inputs are saved style and known geometry;
-- registered aura regions are never queried for text, points, size, or visibility.
local ADDON_NAME, ST = ...

local Layout = {}
ST.BarTextLayout = Layout
local TextLayout = ST.TextAnchorLayout

local points = {
    TOPLEFT = "LEFT", TOP = "CENTER", TOPRIGHT = "RIGHT",
    LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT",
    BOTTOMLEFT = "LEFT", BOTTOM = "CENTER", BOTTOMRIGHT = "RIGHT",
}

function Layout.IsAnchor(point)
    return points[point] ~= nil
end

local function GetAuraSelfPoint(style)
    -- Old entry overrides can own an anchor without the newer snapshot field.
    -- Inherit the attachment only when the anchor itself is inherited too.
    if rawget(style, "barAuraTextAnchor") ~= nil then
        return rawget(style, "barAuraTextSelfPoint")
    end
    return style.barAuraTextSelfPoint
end

function Layout.Resolve(style, lane, vertical)
    if lane == "aura" then
        if style.barAuraTextIndependent == true then
            local point = style.barAuraTextAnchor
            if points[point] then
                return point, style.barAuraTextOffsetX or 0, style.barAuraTextOffsetY or 0,
                    GetAuraSelfPoint(style) or TextLayout.GetSelfPoint(point)
            end
        end
        return Layout.Resolve(style, "time", vertical)
    end
    local isName = lane == "name"
    local point, x, y
    if isName then
        point, x, y = style.barNameTextAnchor, style.barNameTextOffsetX, style.barNameTextOffsetY
    else
        point, x, y = style.barTimeTextAnchor, style.barCdTextOffsetX, style.barCdTextOffsetY
    end
    x, y = x or 0, y or 0
    if points[point] then return point, x, y, TextLayout.GetSelfPoint(point) end
    local reverse
    if isName then reverse = style.barNameTextReverse else reverse = style.barTimeTextReverse end
    if vertical then
        local top = isName and reverse or (not isName and not reverse)
        point = top and "TOP" or "BOTTOM"
        return point, x, y + (top and -3 or 3), point
    end
    local left = isName and not reverse or (not isName and reverse)
    point = left and "LEFT" or "RIGHT"
    return point, x + (left and 3 or -3), y, point
end

function Layout.ResolveCustom(style, lane, vertical, otherShown)
    local point = style[lane .. "Anchor"]
    local x = style[lane .. "XOffset"] or 0
    local y = style[lane .. "YOffset"] or 0
    if points[point] then return point, x, y, TextLayout.GetSelfPoint(point) end
    if not otherShown then return "CENTER", x, y, "CENTER" end
    local duration = lane == "durationText"
    if vertical then
        point = duration and "BOTTOM" or "TOP"
        return point, x, y + (duration and 2 or -2), point
    end
    point = duration and "LEFT" or "RIGHT"
    return point, x + (duration and 4 or -4), y, point
end

function Layout.Apply(text, target, point, x, y, selfPoint)
    selfPoint = selfPoint or TextLayout.GetSelfPoint(point)
    TextLayout.Apply(text, target, point, x, y, selfPoint)
    text:SetJustifyH(points[selfPoint] or "CENTER")
end

-- A second name anchor lets the renderer truncate even secret spell names.
-- Custom placements only opt into this conventional single-row edge layout.
function Layout.ApplyName(nameText, target, timerText, style, vertical, timerLane, timerShown)
    local point, x, y, selfPoint = Layout.Resolve(style, "name", vertical)
    Layout.Apply(nameText, target, point, x, y, selfPoint)
    if vertical or not timerText or not timerShown then return end
    -- Centered text must keep its natural width; a second anchor would resize it.
    if selfPoint ~= "LEFT" and selfPoint ~= "RIGHT" then return end
    local timerPoint, _, timerY = Layout.Resolve(style, timerLane or "time", vertical)
    local legacy = style.barNameTextAnchor == nil and style.barTimeTextAnchor == nil
        and (timerLane ~= "aura" or style.barAuraTextIndependent ~= true)
    if legacy then
        -- Untouched profiles retain their original two-anchor layout exactly,
        -- including the distinction between absent and explicit false Flip.
        if style.barNameTextReverse ~= style.barTimeTextReverse then return end
    elseif y ~= timerY then
        return
    end
    if point == "LEFT" and timerPoint == "RIGHT" then
        nameText:SetPoint("RIGHT", timerText, "LEFT", -4, 0)
    elseif point == "RIGHT" and timerPoint == "LEFT" then
        nameText:SetPoint("LEFT", timerText, "RIGHT", 4, 0)
    end
end

-- A persistent Aura name cannot follow a native timer's width: several units
-- can supply that timer, and their text/layout is restricted. Reserve a stable
-- lane using only saved settings and a private, unanchored measuring region.
local auraTimerMeasure
local AURA_TIMER_SAMPLES = { 359999, 59.9, 9.9 }
local function MeasureAuraTimerLane(style, entry)
    if not auraTimerMeasure then
        local host = CreateFrame("Frame", nil, UIParent)
        host:Hide()
        auraTimerMeasure = host:CreateFontString(nil, "ARTWORK")
    end
    local addon = ST.Addon
    addon.ApplyFontStyle(auraTimerMeasure, style, "auraText")
    local width = 0
    local markerWanted = addon:IsPandemicMarkerPreviewWanted(entry, style)
    -- Capacity for two hour digits, minutes, and decimal seconds. Longer
    -- timers still stay inside the lane; the font renderer truncates them.
    for _, seconds in ipairs(AURA_TIMER_SAMPLES) do
        local text = addon.FormatTime(seconds, style)
        if markerWanted then
            text = addon:DecoratePandemicPreviewText(text, style)
        end
        width = math.max(width, auraTimerMeasure:GetUnboundedStringWidthForText(text))
    end
    return math.ceil(width) + 2
end

local function ResolveAuraTimerLane(style, vertical, entry)
    if not entry or vertical or (style.showBarNameText == false and not entry.customName) then return end
    local namePoint, nameX, nameY, nameSelf = Layout.Resolve(style, "name", vertical)
    local point, x, y, selfPoint = Layout.Resolve(style, "aura", vertical)
    -- Preserve explicit centered/corner placements and separate text rows.
    if nameSelf ~= namePoint or selfPoint ~= point or nameY ~= y then return end
    if not ((namePoint == "LEFT" and point == "RIGHT")
        or (namePoint == "RIGHT" and point == "LEFT")) then return end
    -- With duration text off, the name keeps the full row's outer boundary.
    if style.showAuraText == false then return point, x, y, 0 end

    local width = MeasureAuraTimerLane(style, entry)
    local icon = 0
    if style.showBarIcon ~= false then
        icon = (style.barIconSizeOverride and style.barIconSize or style.barHeight or 20)
            + (style.barIconOffset or 0)
    end
    local span = (style.barLength or 180) - icon - 2 * (style.borderSize or ST.DEFAULT_BORDER_SIZE)
    span = span + (point == "RIGHT" and (x - nameX) or (nameX - x)) - 4
    -- On short bars neither text may consume the other's half of the row.
    width = math.min(width, math.max(1, span / 2))
    return point, x, y, width
end

function Layout.ResetTimerLane(timerText)
    timerText:SetWidth(0)
    timerText:SetMaxLines(0)
end

function Layout.ApplyAuraTimer(timerText, target, style, vertical, persistentEntry)
    Layout.ResetTimerLane(timerText)
    Layout.Apply(timerText, target, Layout.Resolve(style, "aura", vertical))
    local _, _, _, width = ResolveAuraTimerLane(style, vertical, persistentEntry)
    if width and width > 0 then
        timerText:SetWidth(width)
        timerText:SetMaxLines(1)
    end
end

-- Runtime and preview use this owner for both cooldown and persistent-name
-- placement. A ready/cooldown transition cannot restore the empty-timer anchor.
function Layout.ApplyBarTexts(nameText, timerText, target, style, vertical, lane, persistentEntry)
    if lane == "aura" then
        Layout.ApplyAuraTimer(timerText, target, style, vertical, persistentEntry)
    else
        Layout.ResetTimerLane(timerText)
        Layout.Apply(timerText, target, Layout.Resolve(style, lane, vertical))
    end
    if not nameText then return end
    nameText:SetMaxLines(0)
    if not persistentEntry then
        Layout.ApplyName(nameText, target, timerText, style, vertical, lane,
            lane ~= "aura" or style.showAuraText ~= false)
        return
    end
    Layout.Apply(nameText, target, Layout.Resolve(style, "name", vertical))
    local point, x, y, width = ResolveAuraTimerLane(style, vertical, persistentEntry)
    if width then
        local inset = width > 0 and (width + 4) or 0
        nameText:SetPoint(point, target, point, x + (point == "RIGHT" and -inset or inset), y)
        nameText:SetMaxLines(1)
    end
end

-- Snapshot once, then retain the independent position while following Time.
function Layout.SetAuraIndependent(store, effectiveStyle, vertical, enabled)
    if enabled and not Layout.IsAnchor(rawget(store, "barAuraTextAnchor")) then
        local point, x, y, selfPoint = Layout.Resolve(effectiveStyle, "aura", vertical)
        store.barAuraTextAnchor = point
        store.barAuraTextOffsetX = x
        store.barAuraTextOffsetY = y
        store.barAuraTextSelfPoint = selfPoint
    end
    store.barAuraTextIndependent = enabled == true
end

-- Complete baselines prevent newly promoted entry settings reading back through
-- the effective-style metatable when their former panel values were implicit.
function Layout.SnapshotSection(store, source, sectionId)
    if sectionId == "barNameText" then
        store.barNameTextAnchor = source.barNameTextAnchor or "AUTO"
        store.barNameTextOffsetX = source.barNameTextOffsetX or 0
        store.barNameTextOffsetY = source.barNameTextOffsetY or 0
        store.barNameTextReverse = source.barNameTextReverse == true
    elseif sectionId == "cooldownText" then
        store.barTimeTextAnchor = source.barTimeTextAnchor or "AUTO"
        store.barCdTextOffsetX = source.barCdTextOffsetX or 0
        store.barCdTextOffsetY = source.barCdTextOffsetY or 0
        store.barTimeTextReverse = source.barTimeTextReverse == true
    elseif sectionId == "auraText" then
        store.barAuraTextIndependent = source.barAuraTextIndependent == true
        store.barAuraTextAnchor = source.barAuraTextAnchor or false
        store.barAuraTextOffsetX = source.barAuraTextOffsetX or 0
        store.barAuraTextOffsetY = source.barAuraTextOffsetY or 0
        store.barAuraTextSelfPoint = GetAuraSelfPoint(source) or false
    end
end
