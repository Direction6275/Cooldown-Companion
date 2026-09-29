-- The same appearance controls and scope chrome serve panel entries and modules.
local _, ST = ...
local Addon, CS = ST.Addon, ST._configState
local finder = { panel = {}, resource = {}, castbar = {}, health = {}, resourceWide = {} }
local appearanceSections = { "barTexture", "barBgColor", "barDirection", "borderSettings" }
local textSections = {
    { "Name Text", { "barNameTypography" } },
    { "Duration Text", { "barDurationTypography" } },
    { "Value Text", { "barValueTypography" } },
    { "Icon", { "barIconAppearance", "iconZoom" } },
}
local function IsTextSection(id)
    return id == "barNameTypography" or id == "barDurationTypography"
        or id == "barValueTypography" or id == "barIconAppearance" or id == "iconZoom"
end
-- One collapse state per page kind. Module pages are not namespaced by
-- presentation, so a shared key would fold the cast bar and resources together.
-- Pages build their sections from these keys. Older Finder routes in the text
-- sections (and PreviewCommandCenter, which loads first) still spell the text
-- keys out; shared_bar_settings_grouping reopens both kinds to pin them together.
local SECTION_KEYS = {
    -- A bar panel's Background Color sits with its fill colors (BarModeTabs).
    panel = { appearance = "shared_bar_appearance", segments = "shared_bar_segments", text = "barappearance_textIcon",
        colors = "barappearance_colors" },
    castbar = { appearance = "castbar_appearance", text = "castbar_contents" },
    resource = { appearance = "rb_resource_appearance", segments = "shared_bar_segments", text = "rb_text", textStore = "resource" },
    health = { appearance = "rb_health_appearance", text = "rb_health_text", textStore = "resource" },
    resourceWide = { appearance = "rb_wide_appearance", segments = "rb_appearance_segments", segmentsStore = "resource" },
}
local function CollapseKey(id, scope)
    local keys = SECTION_KEYS[scope] or SECTION_KEYS.panel
    if id == "barSmoothing" then return keys.segments or "shared_bar_segments" end
    if id == "barBgColor" and keys.colors then return keys.colors end
    return IsTextSection(id) and keys.text or keys.appearance
end
-- The Finder's store name ("resource") for a section, or nil for the default.
local function CollapseStore(id, scope)
    local keys = SECTION_KEYS[scope] or SECTION_KEYS.panel
    if id == "barSmoothing" then return keys.segmentsStore end
    return IsTextSection(id) and keys.textStore or nil
end
ST._SharedBarStyleCollapseKey = CollapseKey
ST._SharedBarStyleCollapseStore = CollapseStore
local function ScopeOf(group)
    local context = group._settingsContext
    if context and context.resourceWide then return "resourceWide" end
    local kind = context and context.kind
    if kind == "castbar" then return "castbar" end
    if kind == "resources" then return context.powerType == ST._RB.RESOURCE_HEALTH and "health" or "resource" end
    return "panel"
end
-- The Resources Appearance tab exists while Resources are independent.
function ST._ResourceWideAppearanceApplies(context)
    local settings = context and context.resourceSettings
    return settings and settings.enabled == true
        and ST.GetModuleGeometryPanel("resources", context.resourceSpecID) == nil or false
end
local function Allowed(group, id)
    if ST.IsTotemPanelGroup(group) then return false end
    local shared
    for _, section in ipairs(ST.SHARED_BAR_STYLE_SECTIONS) do if section == id then shared = true; break end end
    if not shared then return false end
    local context = group._settingsContext
    -- Independent Resources as a whole: the defaults every resource starts
    -- from. Fill direction follows orientation and text is per resource.
    if context and context.resourceWide then
        return id == "barTexture" or id == "barBgColor" or id == "borderSettings" or id == "barSmoothing"
    end
    if context and context.kind then
        if not ST.CanModuleUseBarStyleSection(context.kind, id) then return false end
        if id == "barSmoothing" then
            return ST._RB.SupportsResourceAuraStackMode(context.powerType)
                and not ST._RB.IsContinuousResourceShape(context.settings, context.powerType, context.spec)
        end
        if id == "barDurationTypography" and context.kind == "resources" then return context.powerType == 5 end
        if (id == "barDirection" or id == "barBgColor") and context.powerType == ST._RB.RESOURCE_HEALTH then return false end
        return true
    end
    if context and context.contents and not context.contents.bars and context.contents.modules then
        local resources = ST._PanelHasConfiguredModuleBars(CS.selectedGroup, "resources")
        local cast = ST._PanelHasConfiguredModuleBars(CS.selectedGroup, "castbar")
        return (resources and ST.CanModuleUseBarStyleSection("resources", id))
            or (cast and ST.CanModuleUseBarStyleSection("castbar", id)) or false
    end
    local entry = ST._GetPanelSettingsSelection(group)
    if id == "barSmoothing" then return not entry or ST.CanUseBarSegmentGap(group, entry) end
    return true
end
ST._SharedBarStyleAllowed = Allowed

local fields = {
    barTexture = { { "barTexture", "Bar Texture", "texture" }, {"barClassTextureBrightness", "Class Texture Brightness", "size", 0.5, 2} },
    barBgColor = { { "barBgColor", "Background Color", "color" } },
    borderSettings = { { "barBorderStyle", "Border Style", "borderStyle" }, { "borderColor", "Border Color", "color" },
        { "borderRenderMode", "Border Thickness Mode", "border" }, { "borderSize", "Border Thickness", "size", 0, 5 } },
    barDirection = { { "barReverseFill", "Reverse Fill Direction", "check" } },
    barSmoothing = { { "barSegmentedSmoothing", "Segmented Smoothing", "smoothing" } },
    barIconAppearance = { { "barIconReverse", "Icon on Right Side", "check" },
        { "barIconSizeOverride", "Custom Icon Size", "check" },
        { "barIconSize", "Icon Size", "size", 4, 100 }, { "barIconOffset", "Icon Offset", "size", -50, 50 } },
    iconZoom = { { "iconZoom", "Icon Zoom", "zoom" } },
}
for _, role in ipairs({ { "barNameTypography", "barName" }, { "barDurationTypography", "barDuration" }, { "barValueTypography", "barValue" } }) do
    fields[role[1]] = { {role[2].."Font", "Font", "font"}, {role[2].."FontSize", "Font Size", "size", 6, 32},
        {role[2].."FontOutline", "Font Outline", "outline"}, {role[2].."FontColor", "Text Color", "color"} }
end

local function BuildRows(column, group, id)
    if not Allowed(group, id) then return end
    local context = group._settingsContext
    local kind = context and context.kind
    local scope = ScopeOf(group)
    local lens = ST._ResolveStyleLens(group)
    local complete = kind and function() context:Refresh("style-settings") end or ST._MakeConfigEditRefresh(group)
    local refresh = function() return complete("style-settings") end
    local sec = ST._BeginLensSection(lens, group, id)
    local firstChild = #(column.children or {}) + 1
    sec:Mark(column)
    local function set(key, value)
        if not sec.write or context and not context:IsCurrent() then return end
        if key == "borderSize" and ST.IsBorderThicknessLocked() then return end
        if key == "barClassTextureBrightness" and ST.IsBarTexturePickerLocked and ST.IsBarTexturePickerLocked() then return end
        sec.write[key] = value
        refresh()
    end
    local textureLocked = ST.IsBarTexturePickerLocked and ST.IsBarTexturePickerLocked()
    -- A module's read table resolves its whole style per key, so the values
    -- that decide this section's shape are read once.
    local read = sec.read
    local classTexture = id == "barTexture" and kind == "resources" and (context.resourceWide
            or ST.POWER_ATLAS_TYPES and ST.POWER_ATLAS_TYPES[context.powerType])
        and ST.GetEffectiveBarTextureName(read.barTexture) == "blizzard_class"
    local iconSizeOverride = id == "barIconAppearance" and read.barIconSizeOverride
    local borderStyle = id == "borderSettings" and read.barBorderStyle
    local crisp = id == "borderSettings" and ST.GetBorderRenderMode(read) == ST.BORDER_RENDER_MODE_CRISP
    for _, field in ipairs(fields[id]) do
        local key, label, widget = unpack(field)
        local setting = finder[scope][key]
        local row
        local shown = not (key == "barClassTextureBrightness" and not classTexture)
            and not (key == "barIconSize" and not iconSizeOverride)
            and not (key == "barIconOffset" and kind == "castbar" and context.settings.iconOffset)
            and not (key == "borderSize" and crisp)
            and not (id == "borderSettings" and key ~= "barBorderStyle" and borderStyle and borderStyle ~= "pixel")
            -- Aura timers keep their own color, so an Aura Panel has nothing
            -- this shared duration color would paint.
            and not (key == "barDurationFontColor" and not kind and ST.IsAuraPanelGroup(group))
        if not shown then
            -- Hidden controls have no applicable value in this shape.
        elseif widget == "color" then
            row = ST._AddColorRow(column, { label=label, setting=setting, tbl=sec.tbl, key=key,
                default=ST.ATTACHED_BAR_DEFAULTS[key] or {1,1,1,1}, hasAlpha=true,
                disabled=sec.disabled, onConfirm=refresh })
        elseif widget == "borderStyle" then
            local list, order = {pixel="Pixel",none="None"}, {"pixel","none"}
            if kind == "castbar" then list.blizzard="Blizzard"; order[#order+1]="blizzard" end
            row = ST._AddDropdownRow(column,{label=label,setting=setting,list=list,order=order,
                value=sec.read[key] or "pixel",onChange=function(value) set(key,value) end})
        elseif widget == "check" then
            row = ST._AddCheckboxRow(column, { label=label, setting=setting, value=sec.read[key] == true,
                disabled=sec.disabled, onChange=function(value) set(key,value) end })
        elseif widget == "size" and not key:match("FontSize$") then
            row = ST._AddSliderRow(column, { label=label, setting=setting, min=field[4], max=field[5], step=0.1,
                value=sec.read[key] or ST.ATTACHED_BAR_DEFAULTS[key] or 0,
                disabled=sec.disabled or key == "borderSize" and ST.IsBorderThicknessLocked()
                    or key == "barClassTextureBrightness" and textureLocked,
                onChange=function(value)
                    if key == "borderSize" and ST.IsBorderThicknessLocked() then return end
                    if key == "barClassTextureBrightness" and textureLocked then return end
                    if sec.write then ST._PreviewScalarSetting(sec.write,key,value,
                        kind and ST._RefreshResourcesCanvasForDrag or ST._RefreshSelectedButtonsPreview) end
                end,
                onRelease=function(value) set(key,value) end })
        elseif widget == "border" then
            local _, modeRow = ST._AddBorderRenderModeDropdown(column,sec.tbl,key,refresh,sec.disabled,
                {row=true,setting=setting,label=label})
            row = modeRow
        elseif widget == "zoom" then
            row = ST._BuildIconZoomControls(column,sec.tbl,refresh,{setting=setting,
                disabled=sec.disabled,masqueEnabled=not kind and lens.effective and lens.effective.masqueEnabled,
                previewRefresh=kind and ST._RefreshResourcesCanvasForDrag or ST._RefreshSelectedButtonsPreview})
        elseif widget == "texture" then
            row = ST._AddDropdownRow(column,{label=label,setting=setting,pulloutWidth=260})
            local list
            if kind == "resources" then
                list = {}; for _, name in ipairs(LibStub("LibSharedMedia-3.0"):List("statusbar")) do list[name]=name end
                if context.resourceWide or ST.POWER_ATLAS_TYPES and ST.POWER_ATLAS_TYPES[context.powerType] then
                    list.blizzard_class = "Blizzard (Class)"
                end
            end
            CS.SetupBarTextureDropdown(row, list and {list=list} or nil)
            row:SetValue(sec.read[key] or "Solid")
            CS.SetBarTextureDropdownCallback(row,function(_,_,value) set(key,value) end)
        elseif widget == "smoothing" then
            row = ST._AddDropdownRow(column,{label=label,setting=setting,list={on="On",off="Off"},order={"on","off"},
                value=ST.NormalizeSegmentedSmoothing(sec.read[key]),onChange=function(value) set(key,value) end})
            local tip = { label, {"On animates segments as they fill.", 1, 1, 1, true},
                " ", {"Off snaps them straight to each value.", 1, 1, 1, true} }
            if context and context.resourceWide then
                tip[#tip + 1] = " "; tip[#tip + 1] = {"Continuous resources are not affected.", 1, 1, 1, true}
            end
            ST._AnchorRowBadge(row, ST._CreateInfoButton(row.frame, row.frame, "LEFT", "LEFT", 0, 0, tip, row))
        elseif widget == "font" or widget == "outline" then
            -- The font helper owns profile-wide font locks and media lists.
            if widget == "font" then
                local prefix = key:sub(1,-5)
                ST._AddFontControls(column,sec.tbl,prefix,{size=10,sizeMin=6,sizeMax=32},refresh,{
                    row=true,settings={font=setting,size=finder[scope][prefix.."FontSize"],outline=finder[scope][prefix.."FontOutline"]}})
            end
        end
    end
    local firstRow = column.children and column.children[firstChild]
    if firstRow then sec:Chrome(firstRow) end
    sec:Finish()
end
ST._BuildSharedBarStyleRows = BuildRows

local function HasAny(group, ids)
    for _, id in ipairs(ids) do if Allowed(group, id) then return true end end
    return false
end

-- Visible groups follow the thing being edited, independently of override owners.
-- Callers with local text/icon behavior place these same rows beside that behavior.
-- opts.leadingRows / opts.trailingRows(left, right) place a surface's own
-- bar rows (thickness, fill color) inside Bar Appearance; opts.skip names
-- sections a surface builds elsewhere with _BuildSharedBarStyleRows.
local function Build(container, group, part, opts)
    local scope = ScopeOf(group)
    local function Section(title, key, ids, leading, trailing)
        if not (HasAny(group, ids) or leading or trailing) then return end
        local _, collapsed = ST._BuildCollapsibleSection(container,title,key,nil,nil,{leftAligned=true})
        if not collapsed then
            local left, right = ST._BeginRowGrid(container)
            if leading then leading(left, right) end
            for _, id in ipairs(ids) do BuildRows(id == "borderSettings" and right or left, group, id) end
            if trailing then trailing(left, right) end
        end
    end
    if not part or part == "appearance" then
        local ids = appearanceSections
        if opts and opts.skip then
            ids = {}
            for _, id in ipairs(appearanceSections) do
                if not opts.skip[id] then ids[#ids + 1] = id end
            end
        end
        Section("Bar Appearance", CollapseKey("barTexture", scope), ids,
            opts and opts.leadingRows, opts and opts.trailingRows)
    end
    if not part or part == "segments" then
        Section("Segments", CollapseKey("barSmoothing", scope), {"barSmoothing"})
    end
    if not part or part == "text" then
        local any
        for _, section in ipairs(textSections) do any = any or HasAny(group, section[2]) end
        if not any then return end
        local store = CollapseStore("barNameTypography", scope) and ST._RBP.collapsedSections or nil
        local _, collapsed = ST._BuildCollapsibleSection(container,"Text & Icon",CollapseKey("barNameTypography",scope),store,nil,{leftAligned=true})
        if not collapsed then
            for _, section in ipairs(textSections) do
                if HasAny(group, section[2]) then
                    ST._AddSettingsSubheading(container,section[1])
                    local column = ST._BeginRowGrid(container)
                    for _, id in ipairs(section[2]) do BuildRows(column,group,id) end
                end
            end
        end
    end
end
ST._BuildSharedBarStyle = Build
local function ModuleStyleContext(kind, powerType, spec, resourceWide)
    local context = ST._CreateModuleSettingsContext(kind,powerType,spec)
    if not context then return end
    -- An independent cast bar, and independent Resources as a whole, are
    -- their own appearance owners: these rows edit their saved settings as a
    -- panel's rows edit the panel. Saved per-bar customizations stay put.
    local store
    if resourceWide then
        context.resourceWide = true
        store = ST._RB.GetSpecResourceDisplayProfile(context.settings, context.spec)
    elseif kind == "castbar" and not context.owner then
        store = context.settings
    end
    if store then
        context.mode, context.entry = "panel", nil
        local keys = {}
        for localKey, sharedKey in pairs(ST.MODULE_BAR_STYLE_MAPS[kind]) do
            local section = ST.BAR_STYLE_KEY_SECTIONS[sharedKey]
            -- Resource text has no resource-wide owner.
            if not (resourceWide and (section == "barValueTypography" or section == "barDurationTypography")) then
                keys[sharedKey] = localKey
            end
        end
        context.group.style = setmetatable({}, {
            __index = function(_, key) return context:ReadStyle()[key] end,
            __newindex = function(_, key, value)
                if context:IsCurrent() and keys[key] then store[keys[key]] = value end
            end,
            _settingsPreviewTarget = {
                isCurrent = function() return context:IsCurrent() end,
                capture = function(sharedKeys)
                    local localKeys = {}
                    for _, key in ipairs(sharedKeys) do if keys[key] then localKeys[#localKeys + 1] = keys[key] end end
                    return ST._CaptureRawSettingsFields(store, localKeys)
                end,
            },
        })
    end
    return context
end
-- opts.resourceWide edits independent Resources as a whole (no powerType).
function ST._BuildModuleBarStyle(container, kind, powerType, spec, part, opts)
    local context = ModuleStyleContext(kind,powerType,spec,opts and opts.resourceWide)
    if not context then return end
    Build(ST._NewPanelSettingsSectionHost(container,context),context.group,part,opts)
end
function ST._BuildModuleBarStyleRows(column, kind, powerType, spec, id, opts)
    local context = ModuleStyleContext(kind,powerType,spec,opts and opts.resourceWide)
    if not context then return end
    BuildRows(ST._NewPanelSettingsSectionHost(column,context),context.group,id)
end

local aliases = { barTexture = {"statusbar texture"}, barBgColor = {"empty color"},
    barSegmentedSmoothing = {"smooth animation"}, borderSize = {"border size"} }

-- Both the settings finder and Customizations links land on these exact rows.
-- resourceWide is the independent Resources tab: the defaults every resource starts from.
if ST._DefineSettingRoute then
    for _, scope in ipairs({"panel","resource","castbar","health","resourceWide"}) do
        for _, id in ipairs(ST.SHARED_BAR_STYLE_SECTIONS) do
            local kind = scope == "castbar" and "castbar" or "resources"
            local healthSection = id == "barTexture" or id == "borderSettings" or id == "barValueTypography"
            local wideSection = id == "barTexture" or id == "barBgColor" or id == "borderSettings" or id == "barSmoothing"
            if scope == "panel" or ST.CanModuleUseBarStyleSection(kind,id) and (scope ~= "health" or healthSection)
                and (scope ~= "resourceWide" or wideSection) then
                local primary = scope == "health" or scope == "resourceWide"
                local route = ST._DefineSettingRoute({idPrefix=(scope == "health" and "resources.health"
                        or scope == "resourceWide" and "resources" or scope)..".sharedBar."..id,
                    scope=scope == "panel" and {"panel","entry"} or scope == "castbar" and "castBar" or primary and "resources" or scope,
                    tab=scope == "resource" and "settings" or scope == "health" and "health" or "appearance",tabLabel=scope == "health" and "Health" or "Appearance",
                    tabStateKey=scope == "castbar" and "castBarHomeTab" or scope == "resource" and "resourcesSettingsTab" or nil,
                    rowScope=primary and "primary" or scope ~= "panel" and "detail" or nil,
                    -- Breadcrumbs name the heading the row sits under.
                    section=id,sectionId=id,sectionLabel=IsTextSection(id) and ST.OVERRIDE_SECTIONS[id].label
                        or id == "barSmoothing" and "Segments"
                        or id == "barBgColor" and scope == "panel" and "Colors" or "Bar Appearance",
                    -- A panel of only attached modules has no Colors section:
                    -- its Background Color stays in Bar Appearance.
                    collapseKeys=id == "barBgColor" and scope == "panel" and function(context)
                        return { context.group and context.group._moduleGeometryOnly
                            and CollapseKey("barTexture", scope) or CollapseKey(id, scope) }
                    end or {CollapseKey(id,scope)},
                    collapseStore=CollapseStore(id,scope),
                    applies=function(context)
                        if scope == "panel" then return context.group and context.group.displayMode == "bars" and Allowed(context.group,id) end
                        if scope == "resourceWide" then return ST._ResourceWideAppearanceApplies(context) end
                        if scope == "resource" and context.resourcePowerType == ST._RB.RESOURCE_HEALTH then return false end
                        local powerType = scope == "health" and ST._RB.RESOURCE_HEALTH or context.resourcePowerType
                        if scope == "health" then
                            local settings = context.resourceSettings
                            local health = settings and settings.resources and settings.resources[powerType]
                            if not (settings and settings.enabled and health and health.enabled == true) then return false end
                        end
                        local ctx = ST._CreateModuleSettingsContext(kind,powerType,context.resourceSpecID)
                        return ctx and Allowed(ctx.group,id) or false
                    end})
                for _, field in ipairs(fields[id]) do
                    local key = field[1]
                    finder[scope][key]=route:Setting({key=key,label=field[2],aliases=aliases[key],applies=function(context)
                        local style = context.style or context.group and context.group.style or {}
                        if scope ~= "panel" then
                            local powerType = scope == "health" and ST._RB.RESOURCE_HEALTH
                                or scope ~= "resourceWide" and context.resourcePowerType or nil
                            local ctx = ST._CreateModuleSettingsContext(kind,powerType,context.resourceSpecID)
                            if not ctx then return false end
                            style = ctx:ReadStyle()
                        end
                        if key == "barClassTextureBrightness" then
                            return (scope == "resourceWide" or scope == "resource" and ST.POWER_ATLAS_TYPES
                                and ST.POWER_ATLAS_TYPES[context.resourcePowerType] == true)
                                and ST.GetEffectiveBarTextureName(style.barTexture) == "blizzard_class" or false
                        end
                        if key == "barIconSize" then return style.barIconSizeOverride == true end
                        if key == "barIconOffset" and scope == "castbar" and Addon:GetCastBarSettings().iconOffset then return false end
                        if key == "borderSize" and ST.GetBorderRenderMode(style) == ST.BORDER_RENDER_MODE_CRISP then return false end
                        if key == "barDurationFontColor" and scope == "panel" and context.group
                            and ST.IsAuraPanelGroup(context.group) then return false end
                        return id ~= "borderSettings" or key == "barBorderStyle" or style.barBorderStyle == nil or style.barBorderStyle == "pixel"
                    end})
                end
            end
        end
    end
end
ST._SharedBarStyleFinder = finder
