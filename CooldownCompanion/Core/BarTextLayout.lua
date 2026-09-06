-- Shared, write-only bar text layout. Inputs are saved style and known geometry;
-- registered aura regions are never queried for text, points, size, or visibility.
local ADDON_NAME, ST = ...

local Layout = {}
ST.BarTextLayout = Layout

local points = {
    TOPLEFT = "LEFT", TOP = "CENTER", TOPRIGHT = "RIGHT",
    LEFT = "LEFT", CENTER = "CENTER", RIGHT = "RIGHT",
    BOTTOMLEFT = "LEFT", BOTTOM = "CENTER", BOTTOMRIGHT = "RIGHT",
}

function Layout.IsAnchor(point)
    return points[point] ~= nil
end

function Layout.Resolve(style, lane, vertical)
    if lane == "aura" then
        if style.barAuraTextIndependent == true then
            local point = style.barAuraTextAnchor
            if points[point] then
                return point, style.barAuraTextOffsetX or 0, style.barAuraTextOffsetY or 0
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
    if points[point] then return point, x, y end
    local reverse
    if isName then reverse = style.barNameTextReverse else reverse = style.barTimeTextReverse end
    if vertical then
        local top = isName and reverse or (not isName and not reverse)
        return top and "TOP" or "BOTTOM", x, y + (top and -3 or 3)
    end
    local left = isName and not reverse or (not isName and reverse)
    return left and "LEFT" or "RIGHT", x + (left and 3 or -3), y
end

function Layout.ResolveCustom(style, lane, vertical, otherShown)
    local point = style[lane .. "Anchor"]
    local x = style[lane .. "XOffset"] or 0
    local y = style[lane .. "YOffset"] or 0
    if points[point] then return point, x, y end
    if not otherShown then return "CENTER", x, y end
    local duration = lane == "durationText"
    if vertical then
        return duration and "BOTTOM" or "TOP", x, y + (duration and 2 or -2)
    end
    return duration and "LEFT" or "RIGHT", x + (duration and 4 or -4), y
end

function Layout.Apply(text, target, point, x, y)
    text:ClearAllPoints()
    text:SetPoint(point, target, point, x, y)
    text:SetJustifyH(points[point] or "CENTER")
end

-- A second name anchor lets the renderer truncate even secret spell names.
-- Custom placements only opt into this conventional single-row edge layout.
function Layout.ApplyName(nameText, target, timerText, style, vertical, timerLane, timerShown)
    local point, x, y = Layout.Resolve(style, "name", vertical)
    Layout.Apply(nameText, target, point, x, y)
    if vertical or not timerText or not timerShown then return end
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

-- Snapshot once, then retain the independent position while following Time.
function Layout.SetAuraIndependent(store, effectiveStyle, vertical, enabled)
    if enabled and not Layout.IsAnchor(rawget(store, "barAuraTextAnchor")) then
        local point, x, y = Layout.Resolve(effectiveStyle, "aura", vertical)
        store.barAuraTextAnchor = point
        store.barAuraTextOffsetX = x
        store.barAuraTextOffsetY = y
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
    end
end
