-- Totem slots have panel-wide appearance, never entry/spell settings.
local ADDON_NAME, ST = ...
local Addon, CS = ST.Addon, ST._configState
local Check, Slider, Dropdown, Color = ST._AddCheckboxRow, ST._AddSliderRow,
    ST._AddDropdownRow, ST._AddColorRow

local function SelectedGroup(context)
    return context and context.group or (CS.selectedGroup and Addon.db.profile.groups[CS.selectedGroup])
end

local function Refresh() Addon:UpdateGroupStyle(CS.selectedGroup) end
local function Rebuild()
    Refresh()
    Addon:RefreshConfigPanel()
end

-- Register the same controls the builders draw, including off-tab search.
local function Route(section, label, tab, mode, collapseSection)
    return ST._DefineSettingRoute({
        idPrefix = "panel.totem." .. section, scope = "panel", tab = tab or "appearance",
        section = section, sectionLabel = label, rowScope = "primary",
        collapseKeys = { "totem_" .. (collapseSection or section) },
        applies = function(context)
            local group = SelectedGroup(context)
            return ST.IsTotemPanelGroup(group) and (not mode or group.displayMode == mode)
        end,
    })
end

local shape = Route("shape", "Size and Style")
local bars = Route("bars", "Bar", nil, "bars")
local icon = Route("icon", "Icon")
local duration = Route("duration", "Duration Text")
local name = Route("name", "Name Text", nil, "bars")
local effects = Route("effects", "Active Totem", "effects")
local glow = Route("glow", "Active Totem", "effects", nil, "effects")
local lowTime = Route("lowTime", "Duration Text", nil, nil, "duration")

local function Setting(route, key, label, applies)
    return route:Setting({ key = key, label = label, applies = applies })
end
local function IsIcons(context) return SelectedGroup(context).displayMode == "icons" end
local function IsSquare(context) return IsIcons(context) and SelectedGroup(context).style.maintainAspectRatio == true end
local function IsRectangular(context) return IsIcons(context) and not IsSquare(context) end
local function HasIcon(context)
    local group = SelectedGroup(context)
    return group.displayMode ~= "bars" or group.style.showBarIcon ~= false
end
local function HasDuration(context) return SelectedGroup(context).style.showCooldownText ~= false end
local function HasName(context) return SelectedGroup(context).style.showBarNameText ~= false end
local function HasSwipe(context) return IsIcons(context) and SelectedGroup(context).style.showCooldownSwipe ~= false end
local function HasLowTime(context)
    return HasDuration(context) and (tonumber(SelectedGroup(context).style.durationLowTimeThreshold) or 0) > 0
end
local function HasCriticalTime(context)
    local style = SelectedGroup(context).style
    local first, second = tonumber(style.durationLowTimeThreshold) or 0, tonumber(style.durationLowTimeThreshold2) or 0
    return HasLowTime(context) and second > 0 and second < first
end

local fields = {
    square = Setting(shape, "square", "Square Icons", IsIcons),
    size = Setting(shape, "size", "Icon Size", IsSquare),
    width = Setting(shape, "width", "Icon Width", IsRectangular),
    height = Setting(shape, "height", "Icon Height", IsRectangular),
    spacing = Setting(shape, "spacing", "Spacing"),
    background = Setting(shape, "background", "Background Color", IsIcons),
    border = {
        color = Setting(shape, "borderColor", "Border Color"),
        thickness = shape:Setting({key = "borderMode", label = "Border Thickness", advancedKey = "panelBorder"}),
        size = shape:Setting({key = "borderSize", label = "Border Size", advancedKey = "panelBorder"}),
    },
    length = Setting(bars, "length", "Bar Length"),
    barHeight = Setting(bars, "height", "Bar Height"),
    vertical = Setting(bars, "vertical", "Vertical Fill"),
    reverse = Setting(bars, "reverse", "Reverse Fill"),
    barColor = Setting(bars, "color", "Bar Color"),
    barBg = Setting(bars, "background", "Background Color"),
    texture = Setting(bars, "texture", "Bar Texture"),
    showIcon = Setting(bars, "icon", "Show Icon"),
    iconReverse = Setting(bars, "iconReverse", "Reverse Icon Position", HasIcon),
    iconSizeOverride = Setting(bars, "iconSizeOverride", "Custom Icon Size", HasIcon),
    iconSize = Setting(bars, "iconSize", "Icon Size", function(c) return HasIcon(c) and SelectedGroup(c).style.barIconSizeOverride == true end),
    iconOffset = Setting(bars, "iconOffset", "Icon Offset", HasIcon),
    zoom = Setting(icon, "zoom", "Icon Zoom", HasIcon),
    tint = Setting(icon, "tint", "Icon Tint", HasIcon),
    showDuration = Setting(duration, "show", "Show Duration Text"),
    format = Setting(duration, "format", "Duration Format", HasDuration),
    showName = Setting(name, "show", "Show Name Text"),
    swipe = Setting(effects, "swipe", "Show Duration Swipe", IsIcons),
    swipeFill = Setting(effects, "fill", "Show Swipe Fill", HasSwipe),
    swipeReverse = Setting(effects, "reverse", "Reverse Swipe", HasSwipe),
    swipeEdge = Setting(effects, "edge", "Show Swipe Edge", HasSwipe),
    swipeAlpha = Setting(effects, "alpha", "Swipe Opacity", function(c)
        return HasSwipe(c) and SelectedGroup(c).style.showCooldownSwipeFill ~= false
    end),
    edgeColor = Setting(effects, "edgeColor", "Swipe Edge Color", function(c)
        return HasSwipe(c) and SelectedGroup(c).style.cooldownSwipeEdgeEnabled == true
    end),
    glowEnabled = Setting(glow, "enabled", "Show Active Glow"),
}
fields.glow = ST._DefineAuraGlowSettings(glow, function(c) return SelectedGroup(c).style end)
for _, setting in pairs(fields.glow) do setting.advancedKey = "totemGlow" end
fields.lowTime = lowTime:Settings({
    enabled = {label = "Change Text Near Expiry", applies = HasDuration},
    warningThreshold = {label = "Start Warning Below", applies = HasLowTime, advancedKey = "durationLowTime"},
    warningColor = {label = "Warning Color", applies = HasLowTime, advancedKey = "durationLowTime"},
    critical = {label = "Add Critical Styling", applies = HasLowTime, advancedKey = "durationLowTime"},
    criticalThreshold = {label = "Start Critical Below", applies = HasCriticalTime, advancedKey = "durationLowTime"},
    criticalColor = {label = "Critical Color", applies = HasCriticalTime, advancedKey = "durationLowTime"},
    decimals = {label = "Show Decimals Near Expiry", applies = HasLowTime, advancedKey = "durationLowTime"},
})

local function TextSettings(route, applies)
    local result = {}
    for _, field in ipairs({ {"size", "Font Size"}, {"font", "Font"}, {"outline", "Font Outline"},
        {"color", "Font Color"}, {"anchor", "Anchor"}, {"xOffset", "X Offset"}, {"yOffset", "Y Offset"} }) do
        result[field[1]] = Setting(route, field[1], field[2], applies)
    end
    return result
end
fields.duration = TextSettings(duration, HasDuration)
fields.name = TextSettings(name, HasName)

local function Section(container, key, label)
    local _, collapsed = ST._BuildCollapsibleSection(container, label, "totem_" .. key,
        nil, nil, { leftAligned = true })
    if not collapsed then return ST._BeginRowGrid(container) end
end

local function Toggle(container, setting, style, key, default, rebuild)
    local value = style[key]
    if value == nil then value = default end
    return Check(container, { label = setting.label, setting = setting, value = value,
        onChange = function(value) style[key] = value; if rebuild then Rebuild() else Refresh() end end })
end

local function Number(container, setting, style, key, default, low, high, step)
    return Slider(container, { label = setting.label, setting = setting,
        min = low, max = high, step = step or 1, value = style[key] or default,
        onChange = function(value)
            ST._PreviewScalarSetting(style, key, value, ST._RefreshSelectedButtonsPreview)
        end,
        onRelease = function(value) style[key] = value; Refresh() end,
    })
end

local function Tint(container, setting, style, key, default)
    return Color(container, { label = setting.label, setting = setting, tbl = style,
        key = key, default = default, hasAlpha = true, onChange = Refresh, onConfirm = Refresh })
end

local function TextControls(left, right, style, prefix, settings, isBar, isName)
    ST._AddFontControls(left, style, prefix, { size = isName and 10 or 12 }, Refresh,
        { row = true, settings = settings })
    Tint(left, settings.color, style, prefix .. "FontColor", {1, 1, 1, 1})
    if isBar then
        ST._AddBarTextPositionControls(right, style,
            isName and "barNameTextAnchor" or "barTimeTextAnchor",
            isName and "barNameTextOffsetX" or "barCdTextOffsetX",
            isName and "barNameTextOffsetY" or "barCdTextOffsetY", Refresh,
            { automatic = true, settings = settings })
    else
        ST._AddAnchorDropdown(right, style, "cooldownTextAnchor", "CENTER", Refresh,
            nil, { row = true, setting = settings.anchor })
        ST._AddOffsetSliders(right, style, "cooldownTextXOffset", "cooldownTextYOffset",
            {x = 0, y = 0}, Refresh, { row = true, settings = {x = settings.xOffset, y = settings.yOffset} })
    end
end

function ST._BuildTotemAppearanceTab(container, group)
    local style = group.style
    local isBar = group.displayMode == "bars"
    local left, right = Section(container, "shape", "Size and Style")
    if left then
        if not isBar then
            Toggle(left, fields.square, style, "maintainAspectRatio", false, true)
            if style.maintainAspectRatio then
                Number(left, fields.size, style, "buttonSize", ST.BUTTON_SIZE, 10, 120)
            else
                Number(left, fields.width, style, "iconWidth", style.buttonSize or ST.BUTTON_SIZE, 10, 160)
                Number(left, fields.height, style, "iconHeight", style.buttonSize or ST.BUTTON_SIZE, 10, 160)
            end
            Tint(right, fields.background, style, "backgroundColor", {0, 0, 0, 0.5})
        end
        Number(left, fields.spacing, style, "buttonSpacing", ST.BUTTON_SPACING, 0, 30)
        ST._BuildBorderControls(right, style, Refresh, { settings = fields.border })
    end
    if isBar then
        left, right = Section(container, "bars", "Bar")
        if left then
            Number(left, fields.length, style, "barLength", 180, 20, 600)
            Number(left, fields.barHeight, style, "barHeight", 20, 4, 100)
            Toggle(left, fields.vertical, style, "barFillVertical", false)
            Toggle(left, fields.reverse, style, "barReverseFill", false)
            Tint(left, fields.barColor, style, "barColor", {0.2, 0.6, 1, 1})
            Tint(left, fields.barBg, style, "barBgColor", {0.1, 0.1, 0.1, 0.8})
            local row = Dropdown(left, {label = "Bar Texture", setting = fields.texture, pulloutWidth = 240})
            CS.SetupBarTextureDropdown(row)
            row:SetValue(style.barTexture or "Solid")
            CS.SetBarTextureDropdownCallback(row, function(_, _, value) style.barTexture = value; Refresh() end)
            Toggle(right, fields.showIcon, style, "showBarIcon", true, true)
            if style.showBarIcon ~= false then
                Toggle(right, fields.iconReverse, style, "barIconReverse", false)
                Toggle(right, fields.iconSizeOverride, style, "barIconSizeOverride", false, true)
                if style.barIconSizeOverride then Number(right, fields.iconSize, style, "barIconSize", 20, 4, 100) end
                Number(right, fields.iconOffset, style, "barIconOffset", 0, -20, 40)
            end
        end
    end
    if not isBar or style.showBarIcon ~= false then
        left, right = Section(container, "icon", "Icon")
        if left then
            ST._BuildIconZoomControls(left, style, Refresh, {setting = fields.zoom})
            Tint(right, fields.tint, style, "iconTintColor", {1, 1, 1, 1})
        end
    end
    left, right = Section(container, "duration", "Duration Text")
    if left then
        Toggle(left, fields.showDuration, style, "showCooldownText", true, true)
        if style.showCooldownText ~= false then
            ST._AddDurationFormatDropdown(right, style, Refresh, {setting = fields.format})
            TextControls(left, right, style, "cooldown", fields.duration, isBar, false)
            ST._AddDurationLowTimeRows(left, style, Refresh, {
                settings = fields.lowTime, summaryTarget = "Totem", rebuild = Rebuild,
            })
        end
    end
    if isBar then
        left, right = Section(container, "name", "Name Text")
        if left then
            Toggle(left, fields.showName, style, "showBarNameText", true, true)
            if style.showBarNameText ~= false then
                TextControls(left, right, style, "barName", fields.name, true, true)
            end
        end
    end
end

function ST._BuildTotemEffectsTab(container, group)
    local style = group.style
    local left, right = Section(container, "effects", "Active Totem")
    if not left then return end
    if group.displayMode ~= "bars" then
        Toggle(left, fields.swipe, style, "showCooldownSwipe", true, true)
        if style.showCooldownSwipe ~= false then
            Toggle(left, fields.swipeFill, style, "showCooldownSwipeFill", true, true)
            Toggle(left, fields.swipeReverse, style, "cooldownSwipeReverse", true)
            Toggle(left, fields.swipeEdge, style, "cooldownSwipeEdgeEnabled", false, true)
            if style.showCooldownSwipeFill ~= false then
                Number(left, fields.swipeAlpha, style, "cooldownSwipeAlpha", 0.8, 0, 1, 0.05)
            end
            if style.cooldownSwipeEdgeEnabled then
                Tint(left, fields.edgeColor, style, "cooldownSwipeEdgeColor", {1, 1, 1, 1})
            end
        end
    end
    local enabled = (style.auraGlowStyle or "pulse") ~= "none"
    local function EnableGlow() ST._EnableAuraGlow(style); Rebuild() end
    local row = Check(right, {label = "Show Active Glow", setting = fields.glowEnabled, value = enabled,
        onChange = function(value)
            if value then EnableGlow() else style.auraGlowStyle = "none"; Rebuild() end
        end})
    ST._AddAdvancedToggle(row, "totemGlow", {}, true, {
        title = "Active Totem Glow",
        build = function(panel)
            ST._BuildAuraGlowControls(panel, style, Refresh, {settings = fields.glow})
        end,
        unlock = {enable = not enabled and {label = "Enable Active Glow", run = EnableGlow,
            apply = function() ST._EnableAuraGlow(style) end} or nil},
    })
end
