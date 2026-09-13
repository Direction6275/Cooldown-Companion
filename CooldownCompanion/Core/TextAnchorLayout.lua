-- Text geometry shared by runtime renderers and configuration previews.
-- Only saved settings and known targets are used; text regions are write-only.
local ADDON_NAME, ST = ...

local Layout = {}
ST.TextAnchorLayout = Layout

local corners = {
    TOPLEFT = {2, -2}, TOPRIGHT = {-2, -2},
    BOTTOMLEFT = {2, 2}, BOTTOMRIGHT = {-2, 2},
}

function Layout.GetOffsets(point)
    local offsets = corners[point]
    if offsets then return offsets[1], offsets[2] end
    return 0, 0
end

function Layout.GetSelfPoint(point)
    return corners[point] and point or "CENTER"
end

function Layout.Apply(text, target, point, x, y, selfPoint)
    text:ClearAllPoints()
    text:SetPoint(selfPoint or Layout.GetSelfPoint(point), target, point, x, y)
end
