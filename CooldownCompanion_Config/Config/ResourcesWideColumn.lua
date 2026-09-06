--[[
    CooldownCompanion - Config/ResourcesWideColumn
    Shared resource, custom-bar, cast-bar and frame settings surfaces.
    Attached objects reuse these builders in the panel workspace. Independent,
    disabled or unplaced objects use their own inventory destination and pinned
    preview, sharing the panel workspace's editing chrome and split divider.
]]

local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local CS = ST._configState
local AceGUI = LibStub("AceGUI-3.0")
local RB = ST._RB

-- Imports from earlier Config/ files
local PruneConfigCustomBarSelection = ST._PruneConfigCustomBarSelection
local SetConfigResourceSettingsSpecID = ST._SetConfigResourceSettingsSpecID
local PruneConfigResourceSelection = ST._PruneConfigResourceSelection

local function ClearInfoButtons(buttons)
    if type(buttons) ~= "table" then
        return
    end

    for _, btn in ipairs(buttons) do
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(buttons)
end

local function HideWidgetFrame(widget)
    if widget and widget.frame then
        widget.frame:Hide()
    end
end

local function FindCustomBarById(settings, customBarId)
    if not customBarId then
        return nil
    end

    if ST._RB and ST._RB.FindCustomBarById then
        return ST._RB.FindCustomBarById(settings, customBarId)
    end

    if not CooldownCompanion.GetSpecCustomAuraBars then
        return nil
    end

    for _, entry in ipairs(CooldownCompanion:GetSpecCustomAuraBars() or {}) do
        if type(entry) == "table" and entry.customBarId == customBarId then
            return entry
        end
    end
    return nil
end

local function FindSelectedCustomBar()
    return FindCustomBarById(CooldownCompanion:GetResourceBarSettings(), CS.selectedCustomBarId)
end

local function EnsureResourcesAddBox(col3)
    local host = col3._resourcesAddBoxHost
    if not host then
        host = AceGUI:Create("SimpleGroup")
        host:SetLayout("Fill")
        host:SetHeight(26)
        host.noAutoHeight = true
        host.frame:SetParent(col3.content)
        host.frame._cdcEditingHeight = 26
        host.frame:SetScript("OnSizeChanged", function(_, width, height)
            host.content.width = width
            host.content.height = height
            host:DoLayout()
        end)
        col3._resourcesAddBoxHost = host
    end
    local settings = CooldownCompanion:GetResourceBarSettings()
    local specID = CooldownCompanion._currentSpecId
    local sameContext = host._cdcAddContextRevision == CS.customBarAddContextRevision
        and host._cdcAddSettings == settings and host._cdcAddSpecID == specID
    local query = sameContext and host._cdcAddInput and host._cdcAddInput:GetText() or ""
    host._cdcAddContextRevision = CS.customBarAddContextRevision
    host._cdcAddSettings = settings
    host._cdcAddSpecID = specID
    host._cdcAddInput = nil
    host:ReleaseChildren()
    if ST._BuildCustomBarWorkspaceAddBox then
        local _, input = ST._BuildCustomBarWorkspaceAddBox(host)
        host._cdcAddInput = input
        if input then
            input.editbox:SetPoint("BOTTOMRIGHT", input.frame, "BOTTOMRIGHT", -18, 0)
            ST._CreateAddBoxInfoButton(input.frame, input.frame, input, true)
            if query ~= "" then input:SetText(query) end
        end
    end
    host.frame:Show()
    if ST._SetWideEditingAddBox then
        ST._SetWideEditingAddBox(col3, host)
    end
end

------------------------------------------------------------------------
-- Module enable, shared by the introduction buttons and the canvas's
-- enable pills. Either route leaves exactly the state the module checkbox
-- on the settings surface leaves, then lands on that module's own
-- settings: the cast bar and the unit frames select their object, while
-- Resource Bars clears the selection because the Resources home tabs ARE
-- its settings surface.
------------------------------------------------------------------------
local function SelectBarsCastFramesItem(item)
    if ST._SelectConfigCastFramesItem then
        ST._SelectConfigCastFramesItem(item)
    else
        CS.castFramesSelectedItem = item
    end
end

local function EnableResourceBarsModule()
    local settings = CooldownCompanion:GetResourceBarSettings()
    if not settings then
        return
    end
    settings.enabled = true
    ST._PrepareBarWorkspaceEnable("resources")
    -- Nothing to select: the Resources home tabs are the surface. Clearing
    -- all three selection families is what lands there, and a stale one can
    -- be standing (a Custom Bar selection survives the module being turned
    -- off, since the bar itself still exists).
    if ST._ClearConfigBarsHomeSelection then
        ST._ClearConfigBarsHomeSelection()
    else
        CS.castFramesSelectedItem = nil
    end
    CooldownCompanion:EvaluateResourceBars()
    CooldownCompanion:UpdateAnchorStacking()
    CooldownCompanion:RefreshConfigPanel()
end

local function EnableCastBarModule()
    local settings = CooldownCompanion:GetCastBarSettings()
    if not settings then
        return
    end
    settings.enabled = true
    ST._PrepareBarWorkspaceEnable("castbar")
    SelectBarsCastFramesItem("castbar")
    CooldownCompanion:EvaluateCastBar()
    CooldownCompanion:UpdateAnchorStacking()
    CooldownCompanion:RefreshConfigPanel()
end

local function EnableFrameAnchoringModule()
    local settings = CooldownCompanion:GetFrameAnchoringSettings()
    if not settings then
        return
    end
    settings.enabled = true
    SelectBarsCastFramesItem("player")
    CooldownCompanion:EvaluateFrameAnchoring()
    CooldownCompanion:RefreshConfigPanel()
end

-- Enable actions for the canvas's recovery controls. Disabled standalone
-- destinations use the full introduction instead of building this canvas.
local function CollectBarsEnableItems()
    local items = {}
    local kind = CS.barsEntrySelected and CS.barWorkspaceKind or nil

    local settings = CooldownCompanion:GetResourceBarSettings()
    if (not kind or kind == "resources") and not (settings and settings.enabled == true) then
        items[#items + 1] = {
            label = "Enable Resource Bars",
            tooltip = "Resource Bars",
            tooltipLine = "Turn them on and open their settings.",
            onClick = EnableResourceBarsModule,
        }
    end

    local castSettings = CooldownCompanion:GetCastBarSettings()
    if (not kind or kind == "castbar") and not (castSettings and castSettings.enabled == true) then
        items[#items + 1] = {
            label = "Enable Cast Bar",
            tooltip = "Cast Bar",
            tooltipLine = "Turn it on and open its settings.",
            onClick = EnableCastBarModule,
        }
    end

    local frameSettings = CooldownCompanion.GetFrameAnchoringSettings
        and CooldownCompanion:GetFrameAnchoringSettings()
    if (not kind or kind == "player" or kind == "target") and not (frameSettings and frameSettings.enabled == true) then
        items[#items + 1] = {
            label = "Enable Unit Frame Anchoring",
            tooltip = "Unit Frames",
            tooltipLine = "Turn frame anchoring on and open the player frame's settings.",
            onClick = EnableFrameAnchoringModule,
        }
    end

    return items
end

-- Every OBJECT this workspace can configure that the shared canvas is not
-- drawing right now, as items for the quiet "Not currently shown:" chip
-- strip below the editing divider. One list for the whole workspace,
-- because one canvas serves every selection within it. `rendered` is the
-- canvas's own selection-key set from the build that just ran, so the
-- strip and the canvas can never disagree about what is on screen.
--
-- A chip is a left-click destination that also answers the canvas slot's
-- right-click context menu, since an object the canvas is not drawing has
-- no other route to it. Multi-select stays on the canvas slots, where the
-- object is actually visible.
--
-- The player and target frames are never chips: with frame anchoring on
-- they are badges on the canvas, and with it off the corner cluster's
-- enable pill is the only thing to offer.
local function CollectBarsOffCanvasChipItems(rendered)
    rendered = rendered or {}
    local items = {}
    if CS.barsEntrySelected and CS.barWorkspaceKind ~= "resources" then
        if CS.barWorkspaceKind == "player" or CS.barWorkspaceKind == "target" then
            for _, kind in ipairs({ "player", "target" }) do
                local item = kind
                items[#items + 1] = {
                    label = item == "player" and "Player Frame" or "Target Frame",
                    selected = CS.castFramesSelectedItem == item,
                    onClick = function()
                        ST._OpenBarWorkspace(item)
                        CooldownCompanion:RefreshConfigPanel()
                    end,
                }
            end
        end
        return items
    end
    local settings = CooldownCompanion:GetResourceBarSettings()
    local RBP = ST._RBP
    local powerNames = RB and RB.POWER_NAMES or {}

    for _, powerType in ipairs(RBP and RBP.GetConfigEditableResources
        and RBP.GetConfigEditableResources(settings, true) or {}) do
        local capturedPowerType = powerType
        local key = "resource:" .. tostring(powerType)
        if not rendered[key] then
            items[#items + 1] = {
                label = powerNames[powerType] or ("Power " .. tostring(powerType)),
                selected = (CS.barsEntrySelected or CS.unifiedBarKind == "resource")
                    and tostring(CS.selectedResourcePowerType) == tostring(powerType),
                onClick = function()
                    ST._SelectConfigResource(capturedPowerType, { toggle = true })
                    CooldownCompanion:RefreshConfigPanel()
                end,
            }
        end
    end

    -- Custom bars ride on the Resource Bars module: with it disabled none of
    -- them can render and selecting one lands on the disabled intro pane, so
    -- they are not offered as destinations. (The resource loop above already
    -- self-gates the same way, inside GetConfigEditableResources.)
    local customBars
    if settings and settings.enabled == true then
        customBars = RB and RB.GetAllCustomBars and RB.GetAllCustomBars(settings)
            or CooldownCompanion:GetSpecCustomAuraBars()
    end
    for index, entry in ipairs(customBars or {}) do
        local customBarId = RB and RB.EnsureCustomBarId and RB.EnsureCustomBarId(settings, entry)
            or entry.customBarId
        local capturedCustomBarId = customBarId
        local key = customBarId and ("custom:" .. tostring(customBarId)) or nil
        if customBarId and not rendered[key] then
            local label = entry.label
                or (entry.spellID and C_Spell.GetSpellName(entry.spellID))
                or ("Custom Bar " .. tostring(index))
            items[#items + 1] = {
                label = label,
                selected = (CS.barsEntrySelected or CS.unifiedBarKind == "custom")
                    and (tostring(CS.selectedCustomBarId) == tostring(customBarId)
                        or CS.selectedCustomBars[customBarId] == true),
                onClick = function()
                    ST._SelectConfigCustomBar(capturedCustomBarId, { toggle = true })
                    CooldownCompanion:RefreshConfigPanel()
                end,
                -- Same select-then-menu gesture the canvas slot answers to, so
                -- a Custom Bar the canvas is not drawing is still reachable by
                -- right-click. Resources and the cast bar carry no context menu
                -- on the canvas either, so their chips stay left-click only.
                onRightClick = function()
                    ST._SelectConfigCustomBar(capturedCustomBarId)
                    CooldownCompanion:RefreshConfigPanel()
                    if ST._OpenConfigCustomBarMenu then
                        ST._OpenConfigCustomBarMenu(capturedCustomBarId)
                    end
                end,
            }
        end
    end

    return items
end

-- Built after the canvas, since it asks the canvas what it drew, and
-- before the settings surface anchors, since the strip is part of the
-- chrome that surface is offset by.
local function SetBarsOffCanvasChips(col3)
    if not ST._SetWideEditingChips then
        return
    end
    local rendered = ST._GetLayoutPreviewRenderedSelectionKeys
        and ST._GetLayoutPreviewRenderedSelectionKeys(col3._resourcesPreviewHost)
        or nil
    local items = CollectBarsOffCanvasChipItems(rendered or {})
    if CS.barWorkspaceKind == "resources" then
        table.insert(items, 1, {
            label = "Resources",
            selected = not CS.selectedResourcePowerType and not CS.selectedCustomBarId,
            onClick = function()
                ST._OpenBarWorkspace("resources")
                CooldownCompanion:RefreshConfigPanel()
            end,
        })
    end
    ST._SetWideEditingChips(col3, "Select:", items)
end

local function PrepareResourcesEditingChrome(col3)
    EnsureResourcesAddBox(col3)
end

------------------------------------------------------------------------
-- A disabled feature has one introduction and one Enable action. The full
-- editor, preview and split divider are built only once the feature is on.
------------------------------------------------------------------------
local BAR_WORKSPACE_INTROS = {
    resources = {
        title = "Resource Bars",
        body = "Display your class resources as customizable bars. Add Custom Bars to track spell cooldowns or auras."
            .. "\n\nKeep the stack alongside your panels with automatic anchoring, or position it independently.",
        buttonText = "Enable Resource Bars",
        onEnable = EnableResourceBarsModule,
    },
    castbar = {
        title = "Cast Bar",
        body = "Display your casts and channels in a customizable bar."
            .. "\n\nKeep it alongside your panels with automatic anchoring, or position it independently.",
        buttonText = "Enable Cast Bar",
        onEnable = EnableCastBarModule,
    },
    frames = {
        title = "Unit Frame Anchoring",
        body = "Keep Blizzard's player and target frames positioned alongside your panels."
            .. "\n\nAdjust their placement together with the rest of your setup.",
        buttonText = "Enable Unit Frame Anchoring",
        onEnable = EnableFrameAnchoringModule,
    },
}

local function GetBarWorkspaceIntroDefinition()
    local kind = ST._GetBarWorkspaceIntroKind()
    return kind and BAR_WORKSPACE_INTROS[kind] or nil
end

local function LayoutBarWorkspaceIntro(pane)
    local width = math.max(120, math.min(560, (pane:GetWidth() or 0) - 96))
    pane.heading:SetWidth(width)
    pane.body:SetWidth(width)
    pane.button:SetWidth(math.min(220, width))
    local total = pane.heading:GetStringHeight() + 18
        + pane.body:GetStringHeight() + 24 + 24
    pane.heading:ClearAllPoints()
    pane.heading:SetPoint("TOP", pane, "TOP", 0,
        -math.max(12, ((pane:GetHeight() or 0) - total) * 0.5))
end

local function ShowBarWorkspaceIntro(col3)
    local definition = GetBarWorkspaceIntroDefinition()
    if not definition then return end
    ST._HideWideEditingChrome(col3)
    CS.RunAdvancedGearBuildPass(function() end)
    local pane = col3._barWorkspaceIntroPane
    if not pane then
        local content = col3.content or col3
        pane = CreateFrame("Frame", nil, content)
        pane:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
        pane:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", 0, 0)
        pane.heading = pane:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
        pane.heading:SetJustifyH("CENTER")
        pane.body = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        pane.body:SetJustifyH("CENTER")
        pane.body:SetSpacing(3)
        pane.body:SetPoint("TOP", pane.heading, "BOTTOM", 0, -18)
        pane.button = AceGUI:Create("Button")
        pane.button:SetHeight(24)
        pane.button.frame:SetParent(pane)
        pane.button.frame:SetPoint("TOP", pane.body, "BOTTOM", 0, -24)
        pane.button:SetCallback("OnClick", function()
            if pane.definition then pane.definition.onEnable() end
        end)
        pane.button.frame:Show()
        pane:SetScript("OnSizeChanged", LayoutBarWorkspaceIntro)
        col3._barWorkspaceIntroPane = pane
    end
    pane.definition = definition
    pane.heading:SetText(definition.title)
    pane.body:SetText(definition.body)
    pane.button:SetText(definition.buttonText)
    pane:Show()
    LayoutBarWorkspaceIntro(pane)
end

-- Attached-bar tabs join the unified tab row beside the panel tabs, so they
-- carry the same accent tint the entry cluster does: `text` is what the tab
-- measures against and what the selected one shows, `accentText` is what
-- the rest wear while the row is shared. UnifiedTabRow drops the tint when
-- the strip owns the whole row (the Resources and Cast Bar homes).
local function AddTabAccent(tabs)
    for _, tab in ipairs(tabs) do
        tab.accentText = ST._GetClassColoredText(tab.text)
    end
    return tabs
end

-- Every tab strip in this file shows the same way: its tabs go into the
-- unified row unconditionally, content is built only when this strip owns
-- the settings surface, and the scroll position survives a rebuild that
-- lands on the same tab. Each strip's scroll widget and the key naming
-- what it was built for live on the strip itself, so no two surfaces can
-- clobber each other's reference.
local function GetStripScrollState(tabGroup)
    local scroll = tabGroup._cdcScroll
    return scroll and (scroll.status or scroll.localstatus) or nil
end

local function ShowStrip(col3, tabGroup, tabs, activeTab, scrollKey, stripOnly)
    ST._AnchorButtonsContentFrame(col3, tabGroup.frame)
    tabGroup.frame:Show()
    tabGroup:SetTabs(tabs)

    if stripOnly then
        -- Another strip owns the surface: these tabs stay in the row
        -- unselected and build nothing.
        ST._UnifiedRowApply()
        return
    end

    local savedOffset, savedScrollvalue
    if tabGroup._cdcScrollKey == scrollKey then
        local state = GetStripScrollState(tabGroup)
        if state and state.offset and state.offset > 0 then
            savedOffset = state.offset
            savedScrollvalue = state.scrollvalue
        end
    end

    tabGroup:SelectTab(activeTab)

    -- Apply after the full page (including its inline Advanced editor) is ready.
    if savedOffset then
        local state = GetStripScrollState(tabGroup)
        if state then
            state.offset = savedOffset
            state.scrollvalue = savedScrollvalue
            CS.FixConfigScroll(tabGroup._cdcScroll)
        end
    end
end

-- One Settings tab, panel-entry parity: the bar's icon rides the label the
-- same way an entry's does (DecorateEntryTabs, read at call time -
-- ButtonSettings.lua loads after this file). Bars without a tracked spell
-- get the accent-only label, same as today's iconless tabs.
local function GetCustomBarEntryTabs(entry)
    local tabs = {
        { value = "settings", text = "Settings" },
    }

    local decorate = ST._DecorateEntryTabs
    if decorate then
        local spellID = type(entry) == "table" and tonumber(entry.spellID) or nil
        return decorate(tabs, spellID and C_Spell.GetSpellTexture(spellID) or nil)
    end
    return AddTabAccent(tabs)
end

local function GetCustomBarDetailScrollKey()
    if not CS.selectedCustomBarId then return nil end
    return tostring(CS.selectedCustomBarId)
end

local function GetResourceSettingsDetailScrollKey()
    if not CS.selectedResourcePowerType or not CS.resourceSettingsSpecID then return nil end
    return tostring(CS.selectedResourcePowerType) .. ":" .. tostring(CS.resourceSettingsSpecID)
end

-- Returns the plain label and its accent-tinted twin; the spec icon stays
-- outside the colour escape.
local function GetResourceSettingsSpecTabText(info, specID)
    local specName = (info and info.name) or tostring(specID)
    local icon = info and info.icon
    local prefix = ""
    if icon and icon ~= "" then
        prefix = string.format("|T%s:13:13:0:0|t ", tostring(icon))
    end
    return prefix .. specName, prefix .. ST._GetClassColoredText(specName)
end

local function GetResourceSettingsSpecTabs(powerType)
    local RBP = ST._RBP
    if not (RBP and RBP.GetResourceApplicableSpecIDs and RBP.GetPlayerSpecOptionsConfig) then
        return {}
    end

    local _, _, specInfoByID = RBP.GetPlayerSpecOptionsConfig()
    local tabs = {}
    for _, specID in ipairs(RBP.GetResourceApplicableSpecIDs(powerType) or {}) do
        local info = specInfoByID and specInfoByID[specID] or nil
        local text, accentText = GetResourceSettingsSpecTabText(info, specID)
        tabs[#tabs + 1] = {
            value = tostring(specID),
            text = text,
            accentText = accentText,
        }
    end
    return tabs
end

------------------------------------------------------------------------
-- Icon-panel mirrors lent to the pinned canvas
------------------------------------------------------------------------

-- The canvas used to draw its own stand-in for the icon panel the bars
-- anchor to, capped at four icons plus a "+x" tile - so the previewed panel
-- width, and every attached bar that inherits it, was wrong for any panel
-- wider than that. It now borrows the REAL read-only button-panel mirror
-- instead, one instance per copy of the panel it draws (the vertical layout
-- draws a second copy for the cast section).
--
-- Built on demand, from the canvas's own render path: it hands us the panel
-- data it resolved, so this side re-derives nothing and cannot drift from
-- the states where the canvas actually wraps a panel. Every message state
-- and the independent-stack path simply never ask.
local RESOURCES_MIRROR_MEASURE_SIZE = 4000

local function AcquireResourcesMirrorHost(host, index)
    local hosts = host._cdcResourcesMirrorHosts
    if not hosts then
        hosts = {}
        host._cdcResourcesMirrorHosts = hosts
    end
    local inner = hosts[index]
    if not inner then
        inner = CreateFrame("Frame", nil, host)
        inner:SetClipsChildren(false)
        -- This canvas arranges bars; the icon row is scenery here, so the
        -- mirror wears the canvas's own "icons stay in place" refusal. Wired
        -- once - the frame is reused by every later rebuild.
        if ST._ApplyLayoutPreviewIconPanelClickShield then
            ST._ApplyLayoutPreviewIconPanelClickShield(inner)
        end
        hosts[index] = inner
    end
    return inner
end

local function ReleaseResourcesMirrorHost(host, index)
    local hosts = host and host._cdcResourcesMirrorHosts
    local inner = hosts and hosts[index]
    if not inner then
        return
    end
    -- Hosts are retained for reuse. Buttons-view selection refreshes call the
    -- resources teardown defensively, so an already released hidden host must
    -- not walk its preview pools again on every entry click.
    if inner._cdcMirrorPanelId == nil and not inner:IsShown() then
        return
    end
    if ST._ReleaseReadOnlyPanelPreview then
        ST._ReleaseReadOnlyPanelPreview(inner)
    end
    -- The reuse guard's only ticket. Cleared here so a released host can
    -- never be handed back as a live mirror.
    inner._cdcMirrorPanelId = nil
    inner:Hide()
end

local function ReleaseResourcesPanelMirrors(host)
    local hosts = host and host._cdcResourcesMirrorHosts
    if not hosts then
        return
    end
    for index in pairs(hosts) do
        ReleaseResourcesMirrorHost(host, index)
    end
end

-- Oversized measuring rect first so the mirror builds at scale 1, then the
-- host shrinks to the mirror content's natural size and the lanes wrap it
-- exactly. Same trick the buttons view's unified preview uses.
--
-- `mirrorReuse` is the canvas-value edit ticket (see RefreshResourcesLayoutPreview):
-- a dragged bar slider repaints this canvas on every OnValueChanged tick, and
-- nothing a resource, custom bar or cast bar setting can change reaches the
-- ICON panel - so rebuilding the mirror per tick is pure cost, doubled in the
-- vertical layout, which draws a second copy for its cast section. It is an
-- explicit ticket rather than a staleness guess: only the mirror-first slider
-- path passes it, and only a host still carrying a built mirror for THIS panel
-- honours it. Every other build path (workspace switch, RefreshConfigPanel,
-- selection change, divider drag) rebuilds exactly as before.
local function BuildResourcesPanelMirror(host, index, panelData, mirrorReuse)
    local panelId = panelData and panelData.groupId
    if not (panelId and ST._BuildReadOnlyPanelPreview) then
        return nil
    end

    local inner = AcquireResourcesMirrorHost(host, index)

    if mirrorReuse and inner._cdcMirrorPanelId == panelId then
        local built = inner._cdcPanelPreview
        local builtContent = built and built.content
        -- The previous build already sized this host to the mirror's natural
        -- rect and nothing released it since, so re-showing it is the whole
        -- job. (ReleaseLentPanelFrames hides the host between builds; the
        -- mirror inside keeps its own shown state.)
        if builtContent and builtContent:IsShown() then
            inner:Show()
            return inner
        end
    end

    inner:SetSize(RESOURCES_MIRROR_MEASURE_SIZE, RESOURCES_MIRROR_MEASURE_SIZE)
    inner:Show()
    ST._BuildReadOnlyPanelPreview(inner, panelId)

    local mirror = inner._cdcPanelPreview
    local content = mirror and mirror.content
    if not (content and content:IsShown()) then
        -- The mirror had nothing to draw (it renders from saved settings, so
        -- it can disagree with the canvas about an emptied panel). Releasing
        -- clears the reuse stamp, so the next build starts clean; the canvas
        -- wraps its neutral placeholder for this one pass.
        ReleaseResourcesMirrorHost(host, index)
        return nil
    end
    inner:SetSize(math.max(1, content:GetWidth() or 1), math.max(1, content:GetHeight() or 1))
    inner._cdcMirrorPanelId = panelId
    return inner
end

-- Hides every surface this file owns and releases the shared divider if
-- the resources preview host holds it. Called from every view branch that
-- takes col3 over (buttons wide view, cast frames, the normal fall-through,
-- the talent picker) and at the top of this view's own refresh.
local function HideResourcesWideSurfaces(col3, preserveFinderState)
    HideWidgetFrame(col3._resourcesConflictScroll)
    HideWidgetFrame(col3._resourcesTabGroup)
    HideWidgetFrame(col3._resourceSettingsTabGroup)
    HideWidgetFrame(col3._customBarEntryTabGroup)
    HideWidgetFrame(col3._customBarsMultiSelectScroll)
    HideWidgetFrame(col3._castBarHomeTabGroup)
    HideWidgetFrame(col3._castFramesSettingsScroll)
    HideWidgetFrame(col3._resourcesAddBoxHost)
    if ST._ClearWideEditingExtras then
        ST._ClearWideEditingExtras(col3, preserveFinderState)
    end
    if col3._barWorkspaceIntroPane then col3._barWorkspaceIntroPane:Hide() end
    local host = col3._resourcesPreviewHost
    if host then
        ReleaseResourcesPanelMirrors(host)
        if col3.buttonsSplitDivider and col3._cdcActiveWideHost == host then
            if ST._HideWideEditingChrome then
                ST._HideWideEditingChrome(col3)
            else
                col3.buttonsSplitDivider:CancelDrag()
                col3.buttonsSplitDivider:Hide()
            end
        end
        if ST._ClearActiveWidePreview then
            ST._ClearActiveWidePreview(col3, host)
        end
        host:Hide()
    end
end

-- Profile conflict: the gate replaces the whole wide column.
local function ShowResourcesConflictScroll(col3)
    if not col3._resourcesConflictScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(col3.content)
        col3._resourcesConflictScroll = scroll
    end

    local scroll = col3._resourcesConflictScroll
    scroll.frame:ClearAllPoints()
    scroll.frame:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    scroll.frame:SetPoint("BOTTOMRIGHT", col3.content, "BOTTOMRIGHT", 0, 0)
    scroll:ReleaseChildren()
    scroll.frame:Show()

    local RBP = ST._RBP
    if RBP and RBP.BuildResourceBarConflictGate
        and RBP.BuildResourceBarConflictGate(scroll, "Layout & Order", true)
    then
        return
    end

    local label = AceGUI:Create("Label")
    ST._ConfigureWrappedHelperLabel(label)
    label:SetText("Resolve Resource Bars before editing Layout & Order.")
    label:SetFullWidth(true)
    scroll:AddChild(label)
end

-- Single build entry for this workspace's pinned preview. The preview
-- command center owns the host's bottom reserve, so it has to settle
-- before the renderer measures itself; routing every rebuild through here
-- keeps the two in step without a second hook, and refreshes the bar on
-- divider drags, split reapplies and workspace switches alike.
local function BuildResourcesLayoutPreview(host, mirrorReuse)
    if ST._UpdateResourcesPreviewCommandCenter then
        ST._UpdateResourcesPreviewCommandCenter(host)
    end

    -- Only the instances this build actually asked for stay live; a layout
    -- that stops needing the second copy (vertical to horizontal) puts it
    -- away rather than leaving a built mirror parked behind a hidden frame.
    local used = {}
    ST._BuildLayoutOrderPanel(host, {
        panelFrameProvider = function(index, panelData)
            local mirror = BuildResourcesPanelMirror(host, index, panelData, mirrorReuse)
            used[index] = mirror ~= nil
            return mirror
        end,
    })
    local hosts = host._cdcResourcesMirrorHosts
    if hosts then
        for index in pairs(hosts) do
            if not used[index] then
                ReleaseResourcesMirrorHost(host, index)
            end
        end
    end
end

-- Pinned Layout & Order preview at the top of the wide column, registered
-- as the active wide preview so the shared divider drags and the persisted
-- split reapply rebuild it.
local function UpdateResourcesPreviewHost(col3)
    local host = col3._resourcesPreviewHost
    if not host then
        host = CreateFrame("Frame", nil, col3.content)
        host:SetClipsChildren(false)
        col3._resourcesPreviewHost = host
    end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", col3.content, "TOPLEFT", 0, 0)
    host:SetPoint("TOPRIGHT", col3.content, "TOPRIGHT", 0, 0)
    if ST._SetActiveWidePreview then
        ST._SetActiveWidePreview(col3, host, function(hostFrame)
            if ST._BuildLayoutOrderPanel then
                BuildResourcesLayoutPreview(hostFrame)
            end
        end)
    end
    if ST._ComputeWidePreviewHostHeight then
        host:SetHeight(ST._ComputeWidePreviewHostHeight(col3))
    end
    host:Show()
    BuildResourcesLayoutPreview(host)
end

-- Targeted preview rebuild (value changes that only affect the layout
-- preview), without a full config refresh.
--
-- `mirrorReuse` marks the caller as a canvas-value edit - the mirror-first
-- slider drag, which repaints on every tick and cannot touch the icon panel.
-- Everything else omits it and gets a full rebuild, mirror included.
local function RefreshResourcesLayoutPreview(mirrorReuse)
    if CS.barsEntrySelected then
        local col3 = CS.configFrame and CS.configFrame.col3
        local host = col3 and col3._resourcesPreviewHost
        if host and host:IsShown() and ST._BuildLayoutOrderPanel then
            BuildResourcesLayoutPreview(host, mirrorReuse)
        end
        return
    end
    -- Buttons view: the lanes live inside the unified anchor preview on
    -- the buttons preview host; the mirror refresh self-gates.
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(CS.selectedGroup, mirrorReuse == true)
    end
end

local function ShowCustomBarMultiSelect(col3, selectedIds, selectedEntries)
    if not col3._customBarsMultiSelectScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(col3.content)
        col3._customBarsMultiSelectScroll = scroll
    end
    local scroll = col3._customBarsMultiSelectScroll
    ST._AnchorButtonsContentFrame(col3, scroll.frame)
    scroll:ReleaseChildren()
    scroll.frame:Show()

    local heading = AceGUI:Create("Heading")
    heading:SetText(#selectedEntries .. " Custom Bars Selected")
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", heading.label, "RIGHT", 5, 0)
    heading:SetFullWidth(true)
    scroll:AddChild(heading)

    local function AddSpacer()
        local sp = AceGUI:Create("Label")
        sp:SetText(" ")
        sp:SetFullWidth(true)
        local f, _, fl = sp.label:GetFont()
        sp:SetFont(f, 3, fl or "")
        scroll:AddChild(sp)
    end

    local anyDisabled = false
    for _, entry in ipairs(selectedEntries) do
        if entry.enabled ~= true then
            anyDisabled = true
            break
        end
    end

    local enableBtn = AceGUI:Create("Button")
    enableBtn:SetText(anyDisabled and "Enable Selected" or "Disable Selected")
    enableBtn:SetFullWidth(true)
    enableBtn:SetCallback("OnClick", function()
        for _, entry in ipairs(selectedEntries) do
            entry.enabled = anyDisabled and true or false
            if entry.enabled and not entry.trackingMode then
                entry.trackingMode = "active"
            end
        end
        CooldownCompanion:ApplyResourceBars()
        CooldownCompanion:UpdateAnchorStacking()
        CooldownCompanion:RefreshConfigPanel()
    end)
    scroll:AddChild(enableBtn)

    AddSpacer()

    local deleteBtn = AceGUI:Create("Button")
    deleteBtn:SetText("Delete Selected")
    deleteBtn:SetFullWidth(true)
    deleteBtn:SetCallback("OnClick", function()
        CS.ShowPopupAboveConfig("CDC_DELETE_SELECTED_CUSTOM_BARS", #selectedIds, { ids = selectedIds })
    end)
    scroll:AddChild(deleteBtn)
end

local function ShowResourceSettingsPanel(col3)
    local tabs = GetResourceSettingsSpecTabs(CS.selectedResourcePowerType)
    if #tabs == 0 then
        return false
    end
    if SetConfigResourceSettingsSpecID then
        SetConfigResourceSettingsSpecID(CS.resourceSettingsSpecID)
    end
    if not CS.resourceSettingsSpecID then
        return false
    end

    if not col3._resourceSettingsTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(col3.content)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            -- Selecting a bar tab hands the settings surface to the bar;
            -- any panel tabs sharing the row just go unselected.
            ST._UnifiedRowSetScope("detail")
            SetConfigResourceSettingsSpecID(tab)
            widget:ReleaseChildren()

            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            widget._cdcScroll = scroll
            widget._cdcScrollKey = GetResourceSettingsDetailScrollKey()
            -- One advanced-gear build pass per surface rebuild
            -- (AdvancedSettingsPanel.lua): its foot sweep closes every gear
            -- panel whose gear did not rebuild this pass.
            CS.RunAdvancedGearBuildPass(function()
                if ST._BuildResourceSettingsPanel then
                    ST._BuildResourceSettingsPanel(scroll, CS.selectedResourcePowerType, CS.resourceSettingsSpecID)
                else
                    local label = AceGUI:Create("Label")
                    ST._ConfigureWrappedHelperLabel(label)
                    label:SetText("|cff888888Resource settings are unavailable.|r")
                    label:SetFullWidth(true)
                    scroll:AddChild(label)
                end
            end)
            -- Re-run the layout with final widths: AddChild lays out on every
            -- insertion, so a row grid added before its siblings measures
            -- against a stale width and renders clipped until something else
            -- triggers a layout.
            scroll:DoLayout()
        end)
        ST._UnifiedRowInstallStrip(tabGroup, "detail")
        -- The spec tabs run straight on from the primary tabs across the
        -- fixed seam, the same grammar as the panel entry cluster, instead
        -- of being pinned to the right edge.
        ST._UnifiedRowSetSeamFlow(tabGroup)
        col3._resourceSettingsTabGroup = tabGroup
    end

    -- A primary tab is showing its own content: the bar keeps its place in
    -- the row and stays selected, it just does not own the surface.
    ShowStrip(col3, col3._resourceSettingsTabGroup, tabs,
        tostring(CS.resourceSettingsSpecID), GetResourceSettingsDetailScrollKey(),
        ST._UnifiedRowPrimaryOwnsSurface())

    return true
end

local function ShowCustomBarDetail(col3, selectedEntry)
    if not col3._customBarEntryTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(col3.content)
        tabGroup:SetCallback("OnGroupSelected", function(widget)
            -- Selecting the bar's tab hands the settings surface to the bar;
            -- any panel tabs sharing the row just go unselected.
            ST._UnifiedRowSetScope("detail")
            ClearInfoButtons(CS.customBarInfoButtons)
            widget:ReleaseChildren()

            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            widget._cdcScroll = scroll
            widget._cdcScrollKey = GetCustomBarDetailScrollKey()
            -- One advanced-gear build pass per surface rebuild
            -- (AdvancedSettingsPanel.lua): its foot sweep closes every gear
            -- panel whose gear did not rebuild this pass.
            CS.RunAdvancedGearBuildPass(ST._BuildCustomAuraBarPanel, scroll, CS.selectedCustomBarId)
            -- Re-run the layout with final widths: nested Flow rows resize
            -- themselves after their children land, and that height never
            -- reaches the scroll frame until something relayouts it.
            scroll:DoLayout()
        end)
        ST._UnifiedRowInstallStrip(tabGroup, "detail")
        -- The bar's Settings tab runs straight on from the primary tabs
        -- across the fixed seam, the same grammar as the panel entry
        -- cluster, instead of being pinned to the right edge.
        ST._UnifiedRowSetSeamFlow(tabGroup)
        col3._customBarEntryTabGroup = tabGroup
    end

    -- A primary tab is showing its own content: the bar keeps its place in
    -- the row and stays selected, it just does not own the surface.
    ShowStrip(col3, col3._customBarEntryTabGroup, GetCustomBarEntryTabs(selectedEntry),
        "settings", GetCustomBarDetailScrollKey(),
        ST._UnifiedRowPrimaryOwnsSurface())

    -- A routed gear click named one section of the pane; the build above
    -- remembered its heading. Writing the pixel offset into the scroll
    -- state here wins over ShowStrip's saved-offset restore - the widget's
    -- deferred FixScroll applies (and clamps) it next frame. The pending
    -- name is dropped either way, so a stale target never re-scrolls a
    -- later rebuild.
    local tabGroup = col3._customBarEntryTabGroup
    local scroll = tabGroup and tabGroup._cdcScroll
    local heading = scroll and scroll._cdcPendingScrollHeading
    if heading then
        scroll._cdcPendingScrollHeading = nil
        local state = GetStripScrollState(tabGroup)
        local contentTop = scroll.content and scroll.content:GetTop()
        local headingTop = heading.frame and heading.frame:GetTop()
        if state and contentTop and headingTop then
            -- scrollvalue is left alone: the deferred FixScroll rederives
            -- it from the offset, and nil would break a mousewheel that
            -- lands before it runs.
            state.offset = math.max(0, contentTop - headingTop)
        end
    end
    CS.pendingCustomBarScrollSection = nil
end

-- Default page for the Resources home: the tabbed shared settings view.
-- Re-hosts the existing bars-mode builders unmodified: General = anchoring,
-- Appearance = bar text styling, Layout = positioning, Health (when the
-- health resource is enabled). The Layout & Order preview lives in the
-- pinned host above this page, not in a tab.
local function ShowResourcesTabPage(col3, stripOnly)
    if not col3._resourcesTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(col3.content)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            -- These are the module-scope tabs of the Resources home, the
            -- left cluster of its unified row; selecting one hands them the
            -- settings surface without dropping the selected bar.
            ST._UnifiedRowSetScope("primary")
            CS.resourcesSettingsTab = tab
            -- Clean up info buttons from the previous tab before recycling widgets
            ClearInfoButtons(CS.tabInfoButtons)
            widget:ReleaseChildren()
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            widget._cdcScroll = scroll
            widget._cdcScrollKey = "resources:" .. tab
            -- One advanced-gear build pass per surface rebuild
            -- (AdvancedSettingsPanel.lua): its foot sweep closes every gear
            -- panel whose gear did not rebuild this pass.
            CS.RunAdvancedGearBuildPass(function()
                if tab == "general" then
                    ST._BuildResourceBarAnchoringPanel(scroll)
                elseif tab == "appearance" then
                    ST._BuildResourceBarBarTextStylingPanel(scroll)
                elseif tab == "layout" then
                    ST._BuildResourceBarPositioningPanel(scroll)
                elseif tab == "health" then
                    ST._BuildResourceBarHealthStylingPanel(scroll)
                end
            end)
            -- Re-run the layout with final widths: AddChild lays out on every
            -- insertion, so a row grid added before its siblings measures
            -- against a stale width and renders clipped until something else
            -- triggers a layout.
            scroll:DoLayout()
        end)
        ST._UnifiedRowInstallStrip(tabGroup, "primary")
        col3._resourcesTabGroup = tabGroup
    end

    local settings = CooldownCompanion:GetResourceBarSettings()
    local RESOURCE_HEALTH = ST._RB and ST._RB.RESOURCE_HEALTH
    local health = settings and settings.resources and RESOURCE_HEALTH
        and settings.resources[RESOURCE_HEALTH]
    local healthEnabled = health and health.enabled == true

    -- Layout before Appearance, matching the panel strip's order.
    local tabs = {
        { value = "general", text = "General" },
        { value = "layout", text = "Layout" },
        { value = "appearance", text = "Appearance" },
    }
    if healthEnabled then
        tabs[#tabs + 1] = { value = "health", text = "Health" }
    end

    local tab = CS.resourcesSettingsTab
    local valid = { general = true, appearance = true, layout = true }
    if healthEnabled then valid.health = true end
    if not tab or not valid[tab] then tab = "general" end
    CS.resourcesSettingsTab = tab

    ShowStrip(col3, col3._resourcesTabGroup, tabs, tab, "resources:" .. tab, stripOnly)
end

-- Settings surfaces for the Resources home: the module tab page, plus the
-- selected resource's or custom bar's own tabs beside it.
local function ShowResourcesHomeSurfaces(col3, CustomBarExists)
    local selectedEntry = CS.selectedCustomBarId and FindSelectedCustomBar()
    local wantsBarDetail = CS.selectedResourcePowerType ~= nil or selectedEntry ~= nil

    -- The module tabs are the left cluster of this home's unified row:
    -- they stay put while a bar is selected, and the bar's own tabs are
    -- appended beside them. Built first, since the bar strip is offset
    -- by their measured width - which is also why the scope is read
    -- directly here: every strip is still hidden at this point, so
    -- PrimaryOwnsSurface would report false whatever the scope is.
    ShowResourcesTabPage(col3, wantsBarDetail and ST._UnifiedRowGetScope() ~= "primary")

    local barShown = false
    if CS.selectedResourcePowerType then
        barShown = ShowResourceSettingsPanel(col3) == true
    end
    if not barShown and selectedEntry then
        ShowCustomBarDetail(col3, selectedEntry)
        barShown = true
    end
    if not barShown then
        if CS.selectedCustomBarId then
            PruneConfigCustomBarSelection(CustomBarExists)
        end
        if wantsBarDetail then
            -- The bar surface did not materialise after all (a resource
            -- with no applicable specs); the module tabs take the row
            -- back rather than leaving it empty.
            ShowResourcesTabPage(col3)
        end
    end
end

------------------------------------------------------------------------
-- Cast Bar & Unit Frames objects
------------------------------------------------------------------------

-- Cast Bar settings tabs below the pinned preview.
local function ShowCastBarSettings(col3)
    if not col3._castBarHomeTabGroup then
        local tabGroup = AceGUI:Create("TabGroup")
        tabGroup:SetLayout("Fill")
        tabGroup.frame:SetParent(col3.content)
        tabGroup:SetCallback("OnGroupSelected", function(widget, event, tab)
            -- Selecting a bar tab hands the settings surface to the bar;
            -- any panel tabs sharing the row just go unselected.
            ST._UnifiedRowSetScope("detail")
            CS.castBarHomeTab = tab
            -- Clean up info buttons from the previous tab before recycling widgets
            ClearInfoButtons(CS.tabInfoButtons)
            widget:ReleaseChildren()
            local scroll = AceGUI:Create("ScrollFrame")
            scroll:SetLayout("List")
            widget:AddChild(scroll)
            widget._cdcScroll = scroll
            widget._cdcScrollKey = "castbar:" .. tab
            -- One advanced-gear build pass per surface rebuild
            -- (AdvancedSettingsPanel.lua): its foot sweep closes every gear
            -- panel whose gear did not rebuild this pass - the cast bar's
            -- gears open panels like every other surface's.
            CS.RunAdvancedGearBuildPass(function()
                if tab == "general" then
                    ST._BuildCastBarAnchoringPanel(scroll)
                elseif tab == "appearance" then
                    ST._BuildCastBarStylingPanel(scroll)
                elseif tab == "layout" then
                    ST._BuildCastBarPositioningPanel(scroll)
                end
            end)
            -- Re-run the layout with final widths: AddChild lays out on every
            -- insertion, so a row grid added before its siblings measures
            -- against a stale width and renders clipped until something else
            -- triggers a layout.
            scroll:DoLayout()
        end)
        ST._UnifiedRowInstallStrip(tabGroup, "detail")
        col3._castBarHomeTabGroup = tabGroup
    end

    local tab = CS.castBarHomeTab
    if tab ~= "general" and tab ~= "appearance" and tab ~= "layout" then
        tab = "general"
    end
    CS.castBarHomeTab = tab

    -- A primary tab is showing its own content: the cast bar keeps its
    -- place in the row and stays selected, it just does not own the
    -- surface.
    ShowStrip(col3, col3._castBarHomeTabGroup, AddTabAccent({
        { value = "general", text = "General" },
        { value = "layout", text = "Layout" },
        { value = "appearance", text = "Appearance" },
    }), tab, "castbar:" .. tab, ST._UnifiedRowPrimaryOwnsSurface())
end

-- Player or target frame anchoring panel, below the pinned preview.
local function ShowUnitFrameSettings(col3, item)
    if not col3._castFramesSettingsScroll then
        local scroll = AceGUI:Create("ScrollFrame")
        scroll:SetLayout("List")
        scroll.frame:SetParent(col3.content)
        col3._castFramesSettingsScroll = scroll
    end

    local scroll = col3._castFramesSettingsScroll
    ST._AnchorButtonsContentFrame(col3, scroll.frame)

    -- Preserve scroll position across value-change refreshes on the same row
    local savedOffset, savedScrollvalue
    local currentScrollKey = "unitframe:" .. tostring(item)
    if col3._castFramesSettingsScrollKey == currentScrollKey then
        local state = scroll.status or scroll.localstatus
        if state and state.offset and state.offset > 0 then
            savedOffset = state.offset
            savedScrollvalue = state.scrollvalue
        end
    end

    scroll:ReleaseChildren()
    scroll.frame:Show()
    -- One advanced-gear build pass per surface rebuild
    -- (AdvancedSettingsPanel.lua): gearless today, but the pass's foot sweep
    -- still closes whatever stale gear panels the previous surface left open.
    CS.RunAdvancedGearBuildPass(function()
        if item == "player" then
            ST._BuildFrameAnchoringPlayerPanel(scroll)
        else
            ST._BuildFrameAnchoringTargetPanel(scroll)
        end
    end)
    -- Re-run the layout with final widths: AddChild lays out on every
    -- insertion, so a row grid added before its siblings measures against a
    -- stale width and renders clipped until something else triggers a layout.
    scroll:DoLayout()
    col3._castFramesSettingsScrollKey = currentScrollKey

    if savedOffset then
        local state = scroll.status or scroll.localstatus
        if state then
            state.offset = savedOffset
            state.scrollvalue = savedScrollvalue
            CS.FixConfigScroll(scroll)
        end
    end
end

------------------------------------------------------------------------
-- Workspace dispatch
------------------------------------------------------------------------

-- Disabled standalone features show their introduction. Enabled destinations
-- build the preview and the selected object's settings beneath the divider.
local function RefreshBarsWideColumn(col3)
    -- Everything restarts hidden; the active surface re-shows below.
    HideResourcesWideSurfaces(col3, true)

    if CS.barWorkspaceKind == "resources" and CooldownCompanion.GetCurrentResourceBarConflict and CooldownCompanion:GetCurrentResourceBarConflict() then
        if ST._ClearSettingsFinderActionRowState then
            ST._ClearSettingsFinderActionRowState(col3)
        end
        ShowResourcesConflictScroll(col3)
        return
    end

    if ST._GetBarWorkspaceIntroKind() then
        if ST._ClearSettingsFinderActionRowState then
            ST._ClearSettingsFinderActionRowState(col3)
        end
        ShowBarWorkspaceIntro(col3)
        return
    end

    local item = CS.castFramesSelectedItem
    if item ~= nil and item ~= "castbar" and item ~= "player" and item ~= "target" then
        -- Unknown item: fall back to the home rather than inventing a
        -- selection the canvas would not highlight.
        item = nil
        CS.castFramesSelectedItem = nil
    end

    local settings = CooldownCompanion:GetResourceBarSettings()
    local function CustomBarExists(customBarId)
        return FindCustomBarById(settings, customBarId) ~= nil
    end
    PruneConfigCustomBarSelection(CustomBarExists)
    if PruneConfigResourceSelection then
        local RBP = ST._RBP
        PruneConfigResourceSelection(function(powerType)
            if not (RBP and RBP.IsResourceEditableInColumn4) then
                return false
            end
            return RBP.IsResourceEditableInColumn4(powerType, settings, true)
        end)
    end

    UpdateResourcesPreviewHost(col3)

    -- Whatever objects the canvas left out are offered by the quiet chip
    -- strip below the divider, for every selection; the modules that are
    -- off entirely are offered by the canvas's own bottom-right corner.
    SetBarsOffCanvasChips(col3)

    -- The Custom Bar add box and the import/export actions are the
    -- Resources home's own chrome, so they ride on the home selection -
    -- and the add box builds nothing while Resource Bars are disabled.
    if item == nil and settings and settings.enabled == true then
        PrepareResourcesEditingChrome(col3)
    end

    local selectedCustomBarIds = {}
    local selectedCustomBarEntries = {}
    for customBarId in pairs(CS.selectedCustomBars) do
        local entry = FindCustomBarById(settings, customBarId)
        selectedCustomBarIds[#selectedCustomBarIds + 1] = customBarId
        selectedCustomBarEntries[#selectedCustomBarEntries + 1] = entry
    end
    table.sort(selectedCustomBarIds)

    if #selectedCustomBarEntries >= 2 then
        -- Batch edits replace the surface outright, as panel multi-select
        -- does in the buttons workspace.
        ShowCustomBarMultiSelect(col3, selectedCustomBarIds, selectedCustomBarEntries)
    elseif item == "castbar" then
        ShowCastBarSettings(col3)
    elseif item then
        ShowUnitFrameSettings(col3, item)
    else
        ShowResourcesHomeSurfaces(col3, CustomBarExists)
    end

    -- Final height pass: the settings surface just anchored below the
    -- divider, so re-clamp the persisted split against current overhead.
    if ST._ReapplyPanelPreviewSplit then
        ST._ReapplyPanelPreviewSplit()
    end
end

------------------------------------------------------------------------
-- ST._ exports
------------------------------------------------------------------------
ST._GetBarWorkspaceIntroDefinition = GetBarWorkspaceIntroDefinition
ST._RefreshResourcesWideColumn = RefreshBarsWideColumn
ST._HideResourcesWideSurfaces = HideResourcesWideSurfaces
-- Read by the shared canvas (ConfigSettings/, loaded after this file) while
-- it builds its bottom-right module-enable cluster.
ST._CollectBarsEnableItems = CollectBarsEnableItems
ST._RefreshResourcesLayoutPreview = RefreshResourcesLayoutPreview
-- The unified anchor preview (buttons view) re-hosts these settings
-- surfaces below its divider when an attached bar is selected there.
ST._ShowResourceSettingsSurface = ShowResourceSettingsPanel
ST._ShowCustomBarDetailSurface = ShowCustomBarDetail
ST._ShowCastBarSettingsSurface = ShowCastBarSettings
ST._FindSelectedConfigCustomBar = FindSelectedCustomBar

ST._ShowResourceWorkspaceSurfaces = function(col3)
    local settings = CooldownCompanion:GetResourceBarSettings()
    ShowResourcesHomeSurfaces(col3, function(id)
        return FindCustomBarById(settings, id) ~= nil
    end)
end
ST._ShowUnitFrameSettingsSurface = ShowUnitFrameSettings
ST._EnsureCustomBarAddBox = EnsureResourcesAddBox
ST._CollectBarsOffCanvasChips = CollectBarsOffCanvasChipItems
ST._ShowCustomBarMultiSelectSurface = ShowCustomBarMultiSelect
