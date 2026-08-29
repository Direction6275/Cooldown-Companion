local ADDON_NAME, ST = ...
local CooldownCompanion = ST.Addon
local AceGUI = LibStub("AceGUI-3.0")
local CS = ST._configState
local ShowPopupAboveConfig = CS.ShowPopupAboveConfig
local IsNoCooldownSpellID = ST.IsNoCooldownSpell
local UsesChargeBehavior = CooldownCompanion.UsesChargeBehavior

-- Continuous controls in the Buttons workspace render against the pinned
-- mirror while they are being manipulated.  The mirror helper is published
-- later in the config load order, so resolve it at call time.
local function RefreshSelectedButtonsPreview()
    if ST._RefreshButtonsPreviewMirror then
        ST._RefreshButtonsPreviewMirror(CS.selectedGroup, true)
    end
end

local function RefreshActiveConfigPreview()
    -- The Resources destination intentionally leaves selectedContainer in
    -- memory when it clears selectedGroup, so workspace ownership has to win
    -- over the stale Buttons selection here.
    if CS.barsEntrySelected and ST._RefreshResourcesLayoutPreview then
        ST._RefreshResourcesLayoutPreview()
    elseif CS.selectedGroup or CS.selectedContainer then
        RefreshSelectedButtonsPreview()
    end
end

local function PreviewScalarSetting(tbl, key, value, previewFn)
    local committed = tbl[key]
    tbl[key] = value
    previewFn()
    tbl[key] = committed
end

-- Helper: tint AceGUI Heading labels with player class color.
-- Also restores the stock right-line anchors: AceGUI recycles Heading
-- widgets and neither OnAcquire nor SetText repairs the right line, so a
-- heading whose right line was re-anchored to a decoration (info button,
-- collapse arrow, preview badge) carries that stale anchor into its next
-- life. Decorated call sites re-anchor again after calling this.
--
-- The label/left-line reset below is the same defence for the opt-in
-- left-aligned variant further down: those are the two pieces of stock
-- Heading anatomy that neither OnAcquire nor SetText puts back, and the
-- Heading pool is shared with every other addon. Re-asserting the stock
-- state here is a no-op for every centered heading.
local function ColorHeading(heading)
    local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if cc then
        heading.label:SetTextColor(cc.r, cc.g, cc.b)
    end
    heading.label:ClearAllPoints()
    heading.label:SetPoint("TOP")
    heading.label:SetPoint("BOTTOM")
    heading.label:SetJustifyH("CENTER")
    heading.left:ClearAllPoints()
    heading.left:SetPoint("LEFT", 3, 0)
    local headingText = heading.label:GetText()
    if headingText and headingText ~= "" then
        heading.left:SetPoint("RIGHT", heading.label, "LEFT", -5, 0)
    else
        heading.left:SetPoint("RIGHT", -3, 0)
    end
    heading.left:Show()
    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", heading.label, "RIGHT", 5, 0)
    local rule = heading.frame._cdcHeadingRule
    if rule then
        rule:Hide()
    end
end

-- Helper: attach a reusable collapse/expand arrow button to an AceGUI Heading.
-- Stores the button on heading.frame._cdcCollapseBtn so it survives widget
-- recycling without creating duplicate textures or stale handlers.
local COLLAPSE_ARROW_ATLAS = "glues-characterselect-icon-arrowdown-small"
local COLLAPSE_ROTATION_RIGHT = math.pi / 2   -- collapsed: arrow points right
local COLLAPSE_ROTATION_DOWN  = 0              -- expanded:  arrow points down

local function AttachCollapseButton(heading, isCollapsed, onClickFn)
    local frame = heading.frame
    local btn = frame._cdcCollapseBtn

    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(16, 16)
        btn._arrow = btn:CreateTexture(nil, "ARTWORK")
        btn._arrow:SetSize(12, 12)
        btn._arrow:SetPoint("CENTER")
        btn._arrow:SetAtlas(COLLAPSE_ARROW_ATLAS)
        frame._cdcCollapseBtn = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", heading.label, "RIGHT", 4, 0)
    btn:Show()
    btn._arrow:Show()

    heading.right:ClearAllPoints()
    heading.right:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
    heading.right:SetPoint("LEFT", btn, "RIGHT", 4, 0)

    btn._arrow:SetRotation(isCollapsed and COLLAPSE_ROTATION_RIGHT or COLLAPSE_ROTATION_DOWN)

    btn:SetScript("OnClick", onClickFn)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(isCollapsed and "Expand" or "Collapse")
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    heading:SetCallback("OnRelease", function()
        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
    end)

    return btn
end

-- Helper: re-shape a Heading into the row-grammar section header: caret at
-- the far left, then the label, then a thin rule fading out to the right,
-- with breathing room above the whole line so sections do not butt together.
-- The stock left/right border textures are hidden rather than re-textured,
-- and the fading rule is cached on heading.frame._cdcHeadingRule so it
-- survives widget recycling without stacking duplicate textures.
--
-- Everything touched here is put back on release, and the acquire side is
-- covered too: ColorHeading above re-asserts the label/left/right anatomy on
-- every acquire, and the taller frame is re-asserted by stock Heading's own
-- OnAcquire (`self:SetHeight(18)`), which is the one piece of state AceGUI
-- resets for us. So a Heading that passes through this variant can never
-- carry it into another addon's use of the shared pool.
local HEADING_CARET_INSET = 2
local HEADING_CARET_SIZE = 16          -- matches AttachCollapseButton's button
local HEADING_CARET_GAP = 4
local HEADING_RULE_GAP = 8
local HEADING_RULE_HEIGHT = 1
local HEADING_RULE_ALPHA = 0.35
-- Stock AceGUI Heading height; its own OnAcquire re-asserts this, which is
-- why the taller variant below only has to undo itself on release.
local HEADING_STOCK_HEIGHT = 18
-- Sections must not butt against each other, and the HEADER owns that gap so
-- every tab stamped from the row-grammar template inherits it. The frame
-- grows by HEADING_TOP_PAD and the header line is pinned to the frame's
-- BOTTOM, so the extra space lands ABOVE the text - air before a section,
-- never after it.
local HEADING_TOP_PAD = 10
-- The header line therefore sits half a pad below the frame's vertical
-- centre. Caret and badges hang off the LABEL and follow it for free, but
-- every point taken against the FRAME carries this offset - LEFT/RIGHT points
-- also declare a vertical centre, and two anchors declaring DIFFERENT centres
-- on the same region is over-constrained and resolves by luck.
local HEADING_LINE_Y = -HEADING_TOP_PAD / 2
-- Caret first, then label. The label sits at this inset whether or not the
-- section has a caret, so collapsible and plain section titles line up.
local HEADING_LABEL_INSET = HEADING_CARET_INSET + HEADING_CARET_SIZE + HEADING_CARET_GAP

-- flush: park the label at the caret column's left edge instead of the shared
-- label inset. For headings that never carry a caret or icon (the family
-- scoping lines), where the reserved column would read as a hole.
local function ApplyLeftAlignedHeading(heading, btn, flush)
    local frame = heading.frame
    local rule = frame._cdcHeadingRule

    if not rule then
        rule = frame:CreateTexture(nil, "BACKGROUND")
        rule:SetTexture("Interface/Buttons/WHITE8x8")
        rule:SetHeight(HEADING_RULE_HEIGHT)
        frame._cdcHeadingRule = rule
    end

    heading.left:Hide()
    heading.right:Hide()

    -- Taller than stock, with the label pushed down by the whole pad: the
    -- text keeps its 18px line at the BOTTOM of the frame and the extra room
    -- opens above it.
    heading:SetHeight(HEADING_STOCK_HEIGHT + HEADING_TOP_PAD)

    heading.label:ClearAllPoints()
    heading.label:SetJustifyH("LEFT")
    heading.label:SetPoint("TOP", frame, "TOP", 0, -HEADING_TOP_PAD)
    heading.label:SetPoint("BOTTOM")
    heading.label:SetPoint("LEFT", frame, "LEFT",
        flush and HEADING_CARET_INSET or HEADING_LABEL_INSET, HEADING_LINE_Y)
    -- Caret hangs off the LABEL, not the frame, so it rides the shifted line
    -- and the label's inset stays the same with or without one.
    if btn then
        btn:ClearAllPoints()
        btn:SetPoint("RIGHT", heading.label, "LEFT", -HEADING_CARET_GAP, 0)
    end

    local r, g, b = 0.8, 0.8, 0.8
    local cc = C_ClassColor.GetClassColor(select(2, UnitClass("player")))
    if cc then
        r, g, b = cc.r, cc.g, cc.b
    end
    rule:ClearAllPoints()
    rule:SetPoint("LEFT", heading.label, "RIGHT", HEADING_RULE_GAP, 0)
    rule:SetPoint("RIGHT", frame, "RIGHT", -3, HEADING_LINE_Y)
    rule:SetGradient("HORIZONTAL", CreateColor(r, g, b, HEADING_RULE_ALPHA), CreateColor(r, g, b, 0))
    rule:Show()

    -- Chain, don't replace: AttachCollapseButton already installed its own
    -- detach handler on this heading.
    local prevOnRelease = heading.events and heading.events["OnRelease"]
    heading:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then
            prevOnRelease(widget, event, ...)
        end
        rule:Hide()
        rule:ClearAllPoints()
        heading:SetHeight(HEADING_STOCK_HEIGHT)
        heading.label:ClearAllPoints()
        heading.label:SetPoint("TOP")
        heading.label:SetPoint("BOTTOM")
        heading.label:SetJustifyH("CENTER")
        heading.left:ClearAllPoints()
        heading.left:SetPoint("LEFT", 3, 0)
        heading.left:SetPoint("RIGHT", heading.label, "LEFT", -5, 0)
        heading.left:Show()
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", heading.frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", heading.label, "RIGHT", 5, 0)
        heading.right:Show()
    end)

    return rule
end

-- Re-anchor a left-aligned heading's fading rule to sit after the last badge
-- on the heading line. Returns false for centered headings so decorated call
-- sites can fall back to their stock `heading.right` re-anchor.
local function AnchorLeftAlignedHeadingRule(heading, afterFrame)
    local frame = heading and heading.frame
    local rule = frame and frame._cdcHeadingRule
    if not (rule and rule:IsShown()) then
        return false
    end
    rule:ClearAllPoints()
    rule:SetPoint("LEFT", afterFrame or heading.label, "RIGHT", HEADING_RULE_GAP, 0)
    -- Badges are label-anchored, so the LEFT point already rides the header
    -- line; the frame-anchored RIGHT point has to be dropped to match it.
    rule:SetPoint("RIGHT", frame, "RIGHT", -3, HEADING_LINE_Y)
    return true
end

-- Append one decoration to a heading's badge line and keep the trailing rule
-- (or the stock right line) behind it.
--
-- The chain grows label -> first badge -> second badge, so N decorations
-- compose without any caller having to know what came before it: the tail is
-- kept on the heading's FRAME, which is what AceGUI recycles. The tail is
-- cleared on release for the same reason ApplyLeftAlignedHeading restores the
-- stock anatomy there - a Heading that comes back out of the shared pool must
-- not still be chaining off a decoration from its previous life.
local HEADING_BADGE_GAP = 4

local function ChainHeadingBadges(heading, widget)
    local frame = heading and heading.frame
    if not (frame and widget) then
        return widget
    end

    local tail = frame._cdcHeadingBadgeTail or heading.label
    widget:SetParent(frame)
    widget:ClearAllPoints()
    widget:SetPoint("LEFT", tail, "RIGHT", HEADING_BADGE_GAP, 0)
    frame._cdcHeadingBadgeTail = widget

    -- Left-aligned headings fade a rule out to the right of the line; centered
    -- ones use the stock right texture. Same branch every badge helper takes.
    if not AnchorLeftAlignedHeadingRule(heading, widget) then
        heading.right:ClearAllPoints()
        heading.right:SetPoint("RIGHT", frame, "RIGHT", -3, 0)
        heading.right:SetPoint("LEFT", widget, "RIGHT", HEADING_BADGE_GAP, 0)
    end

    -- Chain, don't replace: the collapse button and the left-aligned variant
    -- already installed handlers of their own on this heading.
    local prevOnRelease = heading.events and heading.events["OnRelease"]
    heading:SetCallback("OnRelease", function(w, event, ...)
        if prevOnRelease then
            prevOnRelease(w, event, ...)
        end
        frame._cdcHeadingBadgeTail = nil
    end)

    return widget
end

-- Helper: build a class-colored collapsible section Heading wired to a
-- collapse-state store. store defaults to CS.collapsedSections (the config
-- columns' store); resource-bar panels pass their own. refreshFn defaults to
-- a full config-panel refresh. Returns the heading, its collapsed state, and
-- the collapse button (for callers that anchor extra controls to it).
--
-- opts.leftAligned opts into the row-grammar header shape (caret, then a
-- left-aligned label, then a rule fading right). Omitting opts keeps the
-- stock centered heading every existing call site draws today.
local RegisterLensAnchorHeading
local function BuildCollapsibleSection(container, title, key, store, refreshFn, opts)
    store = store or CS.collapsedSections
    local heading = AceGUI:Create("Heading")
    heading:SetText(title)
    ColorHeading(heading)
    heading:SetFullWidth(true)
    container:AddChild(heading)
    if RegisterLensAnchorHeading then
        RegisterLensAnchorHeading(heading, key)
    end

    local collapsed = store[key]
    local btn = AttachCollapseButton(heading, collapsed, function()
        store[key] = not store[key]
        if refreshFn then
            refreshFn()
        else
            CooldownCompanion:RefreshConfigPanel()
        end
    end)

    -- The navigated-to section (gear / Customizations link): remember its
    -- heading so the deferred fire can scroll to it and pulse it. First match
    -- wins - a route can force several nested keys open, and the first one
    -- built is the outermost destination.
    local pendingHighlight = CS.pendingSettingHighlight
    if pendingHighlight and pendingHighlight.collapseKeys
        and pendingHighlight.collapseKeys[key]
        and not pendingHighlight.headingWidget then
        pendingHighlight.headingWidget = heading
    end

    if opts and opts.leftAligned then
        ApplyLeftAlignedHeading(heading, btn)
    end

    return heading, collapsed, btn
end

------------------------------------------------------------------------
-- Entry identity heading
------------------------------------------------------------------------

-- One quiet line at the top of an entry pane (Settings, Aura, and the
-- trigger panels' Condition) naming what the tabs below are editing: the
-- entry's icon, its display name, and its tracking kind. Informational, not
-- a section, so it carries no caret and no collapse state - but it keeps the
-- row grammar's shape, so the sections that follow line up under it.
local IDENTITY_ICON_SIZE = 18
-- Spell and item art ships with a baked border that reads as a pasted
-- sticker at this size, so the outer 8% is trimmed off - the crop every
-- other icon in the config wears.
local IDENTITY_ICON_CROP = 0.08
-- The "Editing:" breadcrumb's muted grey, so "(Spell)" reads the same in
-- both places.
local IDENTITY_KIND_COLOR = "|cff7d7566"
-- Stock GameFontNormal gold. The section headings below wear the class
-- colour; this line names the entry rather than opening a section, so it
-- stays the plain heading gold and does not read as one of them.
local IDENTITY_LABEL_COLOR = { 1, 0.82, 0 }

-- Cached on the heading's FRAME, which is what AceGUI recycles, so a heading
-- that passes through here twice does not stack duplicate textures. Hidden
-- again on release (below) for the same reason the fading rule is: the
-- Heading pool is shared with every other user of it.
local function EnsureIdentityHeadingIcon(heading)
    local frame = heading.frame
    local icon = frame._cdcIdentityIcon
    if not icon then
        icon = frame:CreateTexture(nil, "OVERLAY")
        icon:SetSize(IDENTITY_ICON_SIZE, IDENTITY_ICON_SIZE)
        -- Set once: the crop survives every later SetTexture.
        icon:SetTexCoord(IDENTITY_ICON_CROP, 1 - IDENTITY_ICON_CROP,
            IDENTITY_ICON_CROP, 1 - IDENTITY_ICON_CROP)
        frame._cdcIdentityIcon = icon
    end
    return icon
end

-- The "Editing:" breadcrumb's kind string, replicated rather than shared:
-- its owner (UpdateEditingContext in Config/ButtonsWideColumn.lua) keeps it
-- in local scope. Same addedAs fallback the entry name decorations use.
-- Change the two together. Only spell entries carry a kind; items and
-- trigger entries show icon and name alone, exactly as the breadcrumb does.
local function GetEntryIdentityKindText(buttonData)
    if buttonData.type ~= "spell" then return nil end
    local addedAs = buttonData.addedAs
    if addedAs ~= "spell" and addedAs ~= "aura" then
        addedAs = buttonData.isPassive and "aura" or "spell"
    end
    return addedAs == "aura" and "Aura" or "Spell"
end

local function BuildEntryIdentityHeading(container, buttonData)
    if not (container and buttonData) then return nil end

    local name = (ST._GetConfigEntryDisplayName
        and ST._GetConfigEntryDisplayName(buttonData)) or buttonData.name
    if not name or name == "" then return nil end

    local kindText = GetEntryIdentityKindText(buttonData)
    if kindText then
        name = name .. " " .. IDENTITY_KIND_COLOR .. "(" .. kindText .. ")|r"
    end

    local heading = AceGUI:Create("Heading")
    heading:SetText(name)
    -- Restores the stock label/left/right anatomy a recycled Heading can
    -- arrive with stale; the class tint it also applies is overwritten below.
    ColorHeading(heading)
    heading.label:SetTextColor(IDENTITY_LABEL_COLOR[1], IDENTITY_LABEL_COLOR[2],
        IDENTITY_LABEL_COLOR[3])
    heading:SetFullWidth(true)
    container:AddChild(heading)

    -- The icon takes the caret column, so the label sits at the same inset as
    -- every collapsible section heading under it and the whole pane reads on
    -- one left edge.
    local icon = EnsureIdentityHeadingIcon(heading)
    icon:SetTexture((ST._GetButtonIcon and ST._GetButtonIcon(buttonData)) or 134400)
    ApplyLeftAlignedHeading(heading, icon)
    icon:Show()

    -- Chain, don't replace: ApplyLeftAlignedHeading just installed its own
    -- restore handler on this heading.
    local prevOnRelease = heading.events and heading.events["OnRelease"]
    heading:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then
            prevOnRelease(widget, event, ...)
        end
        icon:Hide()
        icon:ClearAllPoints()
    end)

    return heading
end

-- Helper: add an advanced-settings button on a parent widget (CheckBox or Heading).
-- The button opens the shared side editor when options.build is provided.
local ADVANCED_TOGGLE_ATLAS = "QuestLog-icon-setting"
local ADVANCED_TOGGLE_INERT_ALPHA = 0.4
-- The gear's idle tint. Named because the Customizations list's own gear wears
-- it too (ApplyAdvancedGlyphLook below), and two copies of the same four
-- numbers is two chances for the two gears to stop looking like one control.
local ADVANCED_TOGGLE_IDLE_COLOR = { 0.72, 0.72, 0.72, 0.85 }
-- What the gear says under the pointer. Shared for the same reason.
local ADVANCED_TOGGLE_OPEN_TOOLTIP = "Open advanced settings"

local function GetAdvancedToggleTitle(parentWidget, options)
    if options and options.title and options.title ~= "" then
        return options.title
    end

    local labelText
    if parentWidget.text and parentWidget.text.GetText then
        labelText = parentWidget.text:GetText()
    elseif parentWidget.label and parentWidget.label.GetText then
        labelText = parentWidget.label:GetText()
    elseif parentWidget.rowLabel and parentWidget.rowLabel.GetText then
        -- Row-grammar widgets (RowWidgets.lua) name their label rowLabel.
        labelText = parentWidget.rowLabel:GetText()
    end

    if labelText and labelText ~= "" then
        return labelText .. " Advanced"
    end

    return "Advanced Settings"
end

local function BuildAdvancedDescriptor(parentWidget, settingKey, options)
    return {
        settingKey = settingKey,
        title = GetAdvancedToggleTitle(parentWidget, options),
        build = options and options.build,
        isAvailable = options and options.isAvailable,
        context = options and options.context,
        deferBuild = options and options.deferBuild,
    }
end

local function SetAdvancedToggleActive(btn, active)
    if btn and btn._icon then
        if active then
            btn._icon:SetVertexColor(1, 0.82, 0, 1)
        else
            btn._icon:SetVertexColor(ADVANCED_TOGGLE_IDLE_COLOR[1], ADVANCED_TOGGLE_IDLE_COLOR[2],
                ADVANCED_TOGGLE_IDLE_COLOR[3], ADVANCED_TOGGLE_IDLE_COLOR[4])
        end
    end
end

-- A gear that sits inside a read-only (inert) section is dimmed with
-- desaturation plus frame-level alpha, deliberately NOT with the vertex color
-- SetAdvancedToggleActive owns: object alpha and vertex alpha multiply, so the
-- two states stay independent and either one can be restored without having to
-- know the other's current value.
local function SetAdvancedToggleInert(btn, inert)
    if btn and btn._icon then
        btn._icon:SetDesaturated(inert and true or false)
        btn._icon:SetAlpha(inert and ADVANCED_TOGGLE_INERT_ALPHA or 1)
    end
end

local function SetActiveAdvancedSettingsToggleButton(btn)
    local current = CS.activeAdvancedSettingsToggleButton
    if current and current ~= btn then
        SetAdvancedToggleActive(current, false)
    end

    CS.activeAdvancedSettingsToggleButton = btn
    SetAdvancedToggleActive(btn, true)
end

local function AddAdvancedToggle(parentWidget, settingKey, tabInfoBtns, isEnabled, options)
    local useSidePanel = options and type(options.build) == "function" and CS.OpenAdvancedSettingsPanel
    local isActive = false
    if useSidePanel then
        if CS.ConsumeQueuedAdvancedSettingsPanelOpen then
            CS.ConsumeQueuedAdvancedSettingsPanelOpen(BuildAdvancedDescriptor(parentWidget, settingKey, options))
        end
        isActive = CS.IsAdvancedSettingsPanelOpen and CS.IsAdvancedSettingsPanelOpen(settingKey, options.context) or false
        if isActive and CS.RebindAdvancedSettingsPanel then
            CS.RebindAdvancedSettingsPanel(BuildAdvancedDescriptor(parentWidget, settingKey, options))
        end
    end

    local frame = parentWidget.frame
    local btn = frame._cdcAdvancedBtn

    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(14, 14)
        btn._icon = btn:CreateTexture(nil, "ARTWORK")
        btn._icon:SetSize(13, 13)
        btn._icon:SetPoint("CENTER")
        btn._icon:SetAtlas(ADVANCED_TOGGLE_ATLAS, false)
        frame._cdcAdvancedBtn = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    -- The gear is cached on the widget's frame and outlives the build that put
    -- it there, so an inert section (ApplyInertRange below) can leave it
    -- disabled and dimmed. Re-assert the interactive state here: the next
    -- tenant of a recycled frame must never inherit the previous one's gate.
    btn:Enable()
    SetAdvancedToggleInert(btn, false)
    btn._advancedSettingKey = settingKey

    -- Clean up on widget release (prevent leaking into recycled widgets).
    -- Also covers any collapse button on the same frame, since AddAdvancedToggle
    -- may run after AttachCollapseButton on the same heading.
    --
    -- Chain, don't replace: the left-aligned heading variant and the row
    -- widgets install their own restore/detach handlers, and clobbering those
    -- would leave stock Heading anatomy re-anchored in the shared pool. The
    -- collapse-button detach below is idempotent with AttachCollapseButton's
    -- own handler, so running both is a no-op for existing call sites.
    --
    -- Every close below names its own setting key. A settings-side gear owns
    -- exactly one panel, and the preview command center can have a second one
    -- open whose gear lives on another tab - closing that one too would be a
    -- gear reaching past its own panel.
    local prevOnRelease = parentWidget.events and parentWidget.events["OnRelease"]
    parentWidget:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then
            prevOnRelease(widget, event, ...)
        end
        local activeSidePanelToggleReleased = useSidePanel and CS.activeAdvancedSettingsToggleButton == btn
        if activeSidePanelToggleReleased
            and not CS.configRefreshInProgress
            and not CS.advancedSettingsPanelRefreshing
            and CS.CloseAdvancedSettingsPanel
        then
            CS.CloseAdvancedSettingsPanel({ settingKey = settingKey })
        end

        btn:ClearAllPoints()
        btn:Hide()
        btn:SetParent(nil)
        SetAdvancedToggleActive(btn, false)
        if CS.activeAdvancedSettingsToggleButton == btn then
            CS.activeAdvancedSettingsToggleButton = nil
        end
        local colBtn = frame._cdcCollapseBtn
        if colBtn then
            colBtn:ClearAllPoints()
            colBtn:Hide()
            colBtn:SetParent(nil)
        end
    end)

    -- The navigated-to setting's own row: the most specific thing a route can
    -- name, so it wins over the section-anchor and heading matches. Recorded
    -- ahead of the disabled gate below - the ROW is drawn and worth pointing
    -- at even while its gear is hidden or inert.
    local pendingHighlight = CS.pendingSettingHighlight
    if pendingHighlight and pendingHighlight.rowKey == settingKey then
        pendingHighlight.rowWidget = parentWidget
    end

    -- Hide when parent setting is disabled
    if isEnabled == false then
        if useSidePanel and isActive and CS.CloseAdvancedSettingsPanel then
            CS.CloseAdvancedSettingsPanel({ settingKey = settingKey })
        end
        btn:Hide()
        btn._icon:Hide()
        table.insert(tabInfoBtns, btn)
        return false, btn
    end

    btn:Show()
    btn._icon:Show()

    -- Position for row-grammar widgets: badges chain off the end of the row's
    -- label text (RowWidgets.lua). The gear is normally created first, so it
    -- is the badge nearest the label.
    if parentWidget.badgeAnchor then
        ST._AnchorRowBadge(parentWidget, btn)
    -- Position for CheckBox widgets (has checkbg and text)
    elseif parentWidget.checkbg then
        btn:SetPoint("LEFT", parentWidget.checkbg, "RIGHT", parentWidget.text:GetStringWidth() + 6, 0)
    end
    -- For headings, caller positions manually (use returned btn reference)

    SetAdvancedToggleActive(btn, isActive)
    if isActive then
        SetActiveAdvancedSettingsToggleButton(btn)
    elseif CS.activeAdvancedSettingsToggleButton == btn then
        CS.activeAdvancedSettingsToggleButton = nil
    end

    btn:SetScript("OnClick", function()
        if useSidePanel then
            if CS.IsAdvancedSettingsPanelOpen and CS.IsAdvancedSettingsPanelOpen(settingKey, options.context) then
                CS.CloseAdvancedSettingsPanel({ settingKey = settingKey })
            else
                local descriptor = BuildAdvancedDescriptor(parentWidget, settingKey, options)
                if CS.OpenAdvancedSettingsPanel(descriptor) and btn:GetParent() == frame then
                    SetActiveAdvancedSettingsToggleButton(btn)
                end
            end
        else
            CooldownCompanion:RefreshConfigPanel()
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local active = CS.IsAdvancedSettingsPanelOpen and CS.IsAdvancedSettingsPanelOpen(settingKey, options and options.context)
        GameTooltip:AddLine(active and "Close advanced settings" or ADVANCED_TOGGLE_OPEN_TOOLTIP)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    table.insert(tabInfoBtns, btn)

    return isActive, btn
end

CS.SetActiveAdvancedSettingsToggleButton = SetActiveAdvancedSettingsToggleButton

------------------------------------------------------------------------
-- Navigated-setting highlight
--
-- A gear or name link that routes the user to a setting (the preview command
-- center's gear, the Customizations list's name link and gear, the Resources
-- object routes) stashes a one-shot request in CS.pendingSettingHighlight
-- before it refreshes:
--   collapseKeys - the section collapse keys the route force-opens (both the
--                  raw key and its lens-resolved variant)
--   sectionId    - the override section the route is about, when it is one
--   rowKey       - the setting row's advanced key, when the route names one
-- The rebuild the navigation triggers consumes it, most specific match first:
-- AddAdvancedToggle records the row wearing the matching gear (rowKey),
-- LensSection:Chrome records the section's anchor row (sectionId - attached
-- in every lens mode, so an entry-lens destination still lands on its row),
-- and BuildCollapsibleSection records the first heading whose collapse key
-- matches as the fallback. One frame later, with layout settled (the same
-- deferred seam AceGUI's own FixScroll rides), the scheduled fire scrolls
-- the target into view and pulses a gold wash over it.
--
-- One-shot by construction: the fire consumes the request, and any OTHER
-- rebuild starting first discards it (BeginNavSettingHighlightRefresh below)
-- because that rebuild releases the recorded widgets back to the pool.
------------------------------------------------------------------------

-- Peak intensity lives in the textures' baked alpha; the animation only takes
-- the frame from 0 to 1 and back, so the two knobs stay independent.
local NAV_FLASH_ALPHA = 0.30
-- The wash hugs the row: a slight vertical inset so it sits on the text line
-- rather than bridging into its neighbours, and ends that fade out over this
-- many pixels instead of cutting off (SetGradient, live-verified signature -
-- Blizzard_NamePlates does the same underline fade).
local NAV_FLASH_INSET_V = 1
local NAV_FLASH_EDGE_FADE = 28
-- Padding above a target that has to be scrolled to, so it lands just under
-- the tab's top edge rather than flush against it.
local NAV_SCROLL_PAD = 24

local navFlashFrame

local function EnsureNavFlashFrame()
    if navFlashFrame then
        return navFlashFrame
    end
    local f = CreateFrame("Frame")
    f:EnableMouse(false)
    f:Hide()
    local gold = CreateColor(1, 0.82, 0, NAV_FLASH_ALPHA)
    local goldFaded = CreateColor(1, 0.82, 0, 0)
    local left = f:CreateTexture(nil, "OVERLAY")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(NAV_FLASH_EDGE_FADE)
    left:SetColorTexture(1, 1, 1, 1)
    left:SetGradient("HORIZONTAL", goldFaded, gold)
    local right = f:CreateTexture(nil, "OVERLAY")
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(NAV_FLASH_EDGE_FADE)
    right:SetColorTexture(1, 1, 1, 1)
    right:SetGradient("HORIZONTAL", gold, goldFaded)
    local mid = f:CreateTexture(nil, "OVERLAY")
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    mid:SetColorTexture(1, 0.82, 0, NAV_FLASH_ALPHA)
    local ag = f:CreateAnimationGroup()
    local function AddPulse(order, from, to, duration)
        local anim = ag:CreateAnimation("Alpha")
        anim:SetOrder(order)
        anim:SetFromAlpha(from)
        anim:SetToAlpha(to)
        anim:SetDuration(duration)
    end
    -- Two pulses, then gone (~1.5s total).
    AddPulse(1, 0, 1, 0.15)
    AddPulse(2, 1, 0.25, 0.3)
    AddPulse(3, 0.25, 1, 0.3)
    AddPulse(4, 1, 0, 0.7)
    ag:SetScript("OnFinished", function()
        f:Hide()
    end)
    f._animation = ag
    navFlashFrame = f
    return f
end

local function StopNavSettingFlash()
    if navFlashFrame then
        navFlashFrame._animation:Stop()
        navFlashFrame:Hide()
        navFlashFrame:ClearAllPoints()
        navFlashFrame:SetParent(nil)
    end
end

-- The AceGUI scroll container the target widget lives in, found by walking
-- the widget parent chain AceGUI maintains - generic on purpose, so the same
-- fire path serves the buttons workspace and the resource-bar panes.
local function FindOwningScrollWidget(widget)
    local cur = widget
    for _ = 1, 12 do
        cur = cur.parent
        if not cur then
            return nil
        end
        if cur.type == "ScrollFrame" then
            return cur
        end
    end
    return nil
end

local function ScrollNavTargetIntoView(widget)
    local scroll = FindOwningScrollWidget(widget)
    if not (scroll and scroll.content and scroll.scrollframe) then
        return
    end
    local frame = widget.frame
    local contentTop = scroll.content:GetTop()
    local targetTop = frame:GetTop()
    local targetHeight = frame:GetHeight()
    local viewHeight = scroll.scrollframe:GetHeight()
    local maxOffset = (scroll.content:GetHeight() or 0) - (viewHeight or 0)
    if not (contentTop and targetTop and targetHeight and viewHeight) or maxOffset <= 0 then
        return
    end

    -- Where the target sits inside the content, in pixels from the content
    -- top. Rect-based but offset-independent: the content and the target move
    -- together, so however far the pane is scrolled right now cancels out.
    local targetOffset = contentTop - targetTop

    -- Visibility is judged against the scroll's PENDING offset, not the
    -- screen: a restored offset can still be waiting on AceGUI's deferred
    -- FixScroll, which runs this same frame in no defined order with this
    -- fire, and the rects only show whichever applied first.
    local status = scroll.status or scroll.localstatus
    local pendingOffset = (status and status.offset) or 0
    if targetOffset >= pendingOffset
        and (targetOffset + targetHeight) <= (pendingOffset + viewHeight) then
        -- Ends up fully in view: the flash alone is the pointer.
        return
    end

    local desired = targetOffset - NAV_SCROLL_PAD
    if desired < 0 then desired = 0 end
    if desired > maxOffset then desired = maxOffset end
    local value = desired / maxOffset * 1000
    -- SetScroll writes the anchor AND the status, so a FixScroll landing
    -- after this rederives the same place; the scrollbar is synced so the
    -- knob tracks the jump (its OnValueChanged re-runs SetScroll, same value).
    scroll:SetScroll(value)
    if scroll.scrollBarShown and scroll.scrollbar then
        scroll.scrollbar:SetValue(value)
    end
end

------------------------------------------------------------------------
-- Place-preserving Panel <-> Entry lens handoff
------------------------------------------------------------------------

local function NormalizeLensAnchorKey(key)
    if type(key) == "string" and key:sub(1, 5) == "lens_" then
        return key:sub(6)
    end
    return key
end

local function BeginLensAnchorBuild(scroll)
    CS.lensAnchorRegistry = {
        scroll = scroll,
        panelId = CS.selectedGroup,
        tab = CS.selectedTab,
        headings = {},
        building = true,
    }
end

local function EndLensAnchorBuild()
    local registry = CS.lensAnchorRegistry
    if registry then
        registry.building = false
    end
end

RegisterLensAnchorHeading = function(widget, key)
    local registry = CS.lensAnchorRegistry
    if not (registry and registry.building and widget and key) then
        return
    end
    registry.headings[#registry.headings + 1] = {
        widget = widget,
        semanticKey = NormalizeLensAnchorKey(key),
    }
end

local function GetLensAnchorHeadingOffset(scroll, heading)
    local contentTop = scroll and scroll.content and scroll.content:GetTop()
    local frame = heading and heading.widget and heading.widget.frame
    local headingTop = frame and frame:GetTop()
    if not (contentTop and headingTop) then
        return nil
    end
    return contentTop - headingTop
end

local function CaptureLensAnchor()
    CS.pendingLensAnchor = nil
    if CS.pendingSettingHighlight then
        return nil
    end

    local registry = CS.lensAnchorRegistry
    local scroll = CS.col4Scroll
    if not (registry and registry.scroll == scroll and scroll and scroll.scrollframe) then
        return nil
    end

    local status = scroll.status or scroll.localstatus
    local offset = (status and status.offset) or 0
    local anchorIndex
    local anchorOffset
    local orderKeys = {}
    for index, heading in ipairs(registry.headings or {}) do
        orderKeys[index] = heading.semanticKey
        local headingOffset = GetLensAnchorHeadingOffset(scroll, heading)
        if headingOffset ~= nil then
            if not anchorIndex then
                anchorIndex = index
                anchorOffset = headingOffset
            end
            if headingOffset <= offset then
                anchorIndex = index
                anchorOffset = headingOffset
            end
        end
    end
    if not anchorIndex then
        return nil
    end

    CS.pendingLensAnchor = {
        panelId = registry.panelId,
        tab = registry.tab,
        semanticKey = orderKeys[anchorIndex],
        anchorIndex = anchorIndex,
        orderKeys = orderKeys,
        relativeOffset = anchorOffset - offset,
        rawOffset = offset,
    }
    return CS.pendingLensAnchor
end

local function FindLensAnchorDestination(registry, pending)
    local byKey = {}
    for _, heading in ipairs(registry.headings or {}) do
        if heading.semanticKey ~= nil and byKey[heading.semanticKey] == nil then
            byKey[heading.semanticKey] = heading
        end
    end
    if byKey[pending.semanticKey] then
        return byKey[pending.semanticKey]
    end

    local keys = pending.orderKeys or {}
    local index = pending.anchorIndex or 1
    for i = index + 1, #keys do
        if byKey[keys[i]] then
            return byKey[keys[i]]
        end
    end
    for i = index - 1, 1, -1 do
        if byKey[keys[i]] then
            return byKey[keys[i]]
        end
    end
    return nil
end

local function RestoreLensAnchor()
    local pending = CS.pendingLensAnchor
    CS.pendingLensAnchor = nil
    if not pending or CS.pendingSettingHighlight then
        return
    end

    local registry = CS.lensAnchorRegistry
    local scroll = registry and registry.scroll
    if not (registry and scroll and scroll.scrollframe and scroll.content
        and registry.panelId == pending.panelId
        and registry.tab == pending.tab
        and CS.selectedGroup == pending.panelId
        and CS.selectedTab == pending.tab) then
        return
    end

    local viewHeight = scroll.scrollframe:GetHeight() or 0
    local maxOffset = math.max(0, (scroll.content:GetHeight() or 0) - viewHeight)
    local desired = pending.rawOffset or 0
    local destination = FindLensAnchorDestination(registry, pending)
    local destinationOffset = destination
        and GetLensAnchorHeadingOffset(scroll, destination) or nil
    if destinationOffset ~= nil then
        desired = destinationOffset - (pending.relativeOffset or 0)
    end
    desired = math.max(0, math.min(desired, maxOffset))

    local value = maxOffset > 0 and (desired / maxOffset * 1000) or 0
    scroll:SetScroll(value)
    if scroll.scrollBarShown and scroll.scrollbar then
        scroll.scrollbar:SetValue(value)
    end
end

local function ScheduleLensAnchorRestore()
    local pending = CS.pendingLensAnchor
    if not pending or pending.scheduled then
        return
    end
    pending.scheduled = true
    C_Timer.After(0, RestoreLensAnchor)
end

local function FireNavSettingHighlight()
    local pending = CS.pendingSettingHighlight
    CS.pendingSettingHighlight = nil
    if not pending then
        return
    end
    local widget = pending.rowWidget or pending.sectionRowWidget or pending.headingWidget
    local frame = widget and widget.frame
    if not (frame and frame:IsVisible()) then
        return
    end
    ScrollNavTargetIntoView(widget)

    local flash = EnsureNavFlashFrame()
    flash._animation:Stop()
    flash:SetParent(frame)
    flash:SetFrameLevel(frame:GetFrameLevel() + 5)
    flash:ClearAllPoints()
    flash:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -NAV_FLASH_INSET_V)
    flash:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, NAV_FLASH_INSET_V)
    flash:Show()
    flash._animation:Play()

    -- The row can be released out from under a playing flash by any rebuild
    -- (a tab click does not pass through the config refresh entry points), and
    -- its frame goes straight back into the pool for the next tenant. Chain,
    -- don't replace - and this registration is one-shot by nature: release
    -- wipes the widget's callbacks along with it.
    local prevOnRelease = widget.events and widget.events["OnRelease"]
    widget:SetCallback("OnRelease", function(w, event, ...)
        if prevOnRelease then
            prevOnRelease(w, event, ...)
        end
        if navFlashFrame and navFlashFrame:GetParent() == frame then
            StopNavSettingFlash()
        end
    end)
end

-- Called by the navigation writers AFTER their RefreshConfigPanel: the build
-- has recorded the target widgets, and one frame from now layout has settled.
local function ScheduleNavSettingHighlight()
    if CS.pendingSettingHighlight then
        C_Timer.After(0, FireNavSettingHighlight)
    end
end

-- Called at the top of every config rebuild. The rebuild the navigation
-- itself triggered is the request's first, and consumes it; any LATER rebuild
-- releases the recorded widgets back to the pool, so the request dies there
-- instead of flashing a recycled frame's next tenant.
local function BeginNavSettingHighlightRefresh()
    StopNavSettingFlash()
    local pending = CS.pendingSettingHighlight
    if pending then
        -- Explicit setting navigation owns this rebuild's semantic scroll.
        CS.pendingLensAnchor = nil
        pending.refreshCount = (pending.refreshCount or 0) + 1
        if pending.refreshCount > 1 then
            CS.pendingSettingHighlight = nil
        end
    end
end

ST._ScheduleNavSettingHighlight = ScheduleNavSettingHighlight
ST._BeginNavSettingHighlightRefresh = BeginNavSettingHighlightRefresh
ST._BeginLensAnchorBuild = BeginLensAnchorBuild
ST._EndLensAnchorBuild = EndLensAnchorBuild
ST._CaptureLensAnchor = CaptureLensAnchor
ST._ScheduleLensAnchorRestore = ScheduleLensAnchorRestore

local function GroupSupportsPerButtonOverrides(group)
    return group and (group.displayMode or "icons") ~= "textures"
end

local function GetSelectedRuntimeButton(buttonData)
    local groupId = CS.selectedGroup
    local buttonIndex = CS.selectedButton
    if not (buttonData and groupId and buttonIndex) then
        return nil
    end

    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    if not (group and group.buttons and group.buttons[buttonIndex] == buttonData) then
        return nil
    end

    local frame = CooldownCompanion.groupFrames and CooldownCompanion.groupFrames[groupId]
    if not (frame and frame.buttons) then
        return nil
    end

    for _, button in ipairs(frame.buttons) do
        if button and button.buttonData == buttonData then
            return button
        end
    end
    return nil
end

-- Owner ruling (aura rebuild plan): group-level aura style sections are shown
-- only while the group actually has an aura-tracking entry. Shared by
-- GroupTabs and BarModeTabs (load order: Helpers loads first).
local function GroupHasAuraTrackingEntry(group)
    if not (group and group.buttons) then
        return false
    end
    for _, buttonData in ipairs(group.buttons) do
        if buttonData.type == "spell"
            and (buttonData.auraTracking or buttonData.addedAs == "aura") then
            return true
        end
    end
    return false
end

-- Aura style sections only apply while an entry tracks an aura. This gate is
-- config-visibility only, NOT part of ST.CanButtonUseOverrideSection: aura
-- tracking is a toggle, and the runtime check feeds GetEffectiveStyle's prune
-- pass, which would permanently delete the saved override on toggle-off.
local AURA_TRACKING_CONFIG_ONLY_SECTIONS = {
    auraText = true,
    auraStackText = true,
    auraDurationSwipe = true,
    auraIndicator = true,
    barActiveAura = true,
    pandemic = true,
    whileAuraActive = true,
    auraMissingDesaturation = true,
}

-- Keybind and custom text never reach a packed aura cell: the renderer draws
-- no replica for an aura host (AuraDisplay.lua), and an Aura Only Section's
-- members are exactly that. Config-visibility only, for the same reason the
-- list above is: membership is POSITIONAL, an entry can be dragged back out to
-- the base grid, and the runtime gate feeds GetEffectiveStyle's prune pass,
-- which would delete the saved keybind override on the way in.
--
-- `group` is optional: the runtime callers (prune, promote, migrations) never
-- pass one and are unaffected, which is exactly the separation this gate wants.
local function CanButtonUseConfigOverrideSection(buttonData, sectionId, group)
    if ST.CanButtonUseOverrideSection then
        local allowed, reason = ST.CanButtonUseOverrideSection(buttonData, sectionId)
        if not allowed then
            return false, reason
        end
    elseif buttonData and buttonData.type == "equipmentSlot"
        and ST.EQUIPMENT_SLOT_DENIED_OVERRIDE_SECTIONS
        and ST.EQUIPMENT_SLOT_DENIED_OVERRIDE_SECTIONS[sectionId] then
        return false, "entryType"
    end

    if AURA_TRACKING_CONFIG_ONLY_SECTIONS[sectionId]
        and not (buttonData and (buttonData.auraTracking or buttonData.addedAs == "aura")) then
        return false, "auraTracking"
    end

    if sectionId == "keybindText" and group and buttonData
        and ST.IsAuraSectionEntry and ST.IsAuraSectionEntry(group, buttonData) then
        return false, "auraSection"
    end

    if not (ST.NO_COOLDOWN_DENIED_OVERRIDE_SECTIONS
        and ST.NO_COOLDOWN_DENIED_OVERRIDE_SECTIONS[sectionId]
        and buttonData
        and buttonData.type == "spell"
        and not buttonData.isPassive) then
        return true
    end

    if UsesChargeBehavior and UsesChargeBehavior(buttonData) then
        return true
    end

    local cooldownSpellId = buttonData.id
    local button = GetSelectedRuntimeButton(buttonData)
    if button then
        local displaySpellId = button._displaySpellId or buttonData.id
        if button._noCooldown ~= nil and button._noCooldownSpellId == displaySpellId then
            return not button._noCooldown, button._noCooldown and "noCooldown" or nil
        end
        cooldownSpellId = displaySpellId
    end

    if IsNoCooldownSpellID and IsNoCooldownSpellID(cooldownSpellId) == true then
        return false, "noCooldown"
    end

    return true
end

------------------------------------------------------------------------
-- STYLE LENS
--
-- Selecting an entry turns the panel's styling tabs into a lens onto that
-- entry: every control reads the entry's effective value, and only the
-- sections the entry has actually customized write anywhere.
--
-- The lens is resolved once per build and handed down, so a single tab cannot
-- disagree with itself about which entry (or none) it is showing.
------------------------------------------------------------------------

-- One level deep is the whole contract: style tables are colors and other
-- flat value bags, and rows edit them IN PLACE. Handing a row the group's own
-- table would make a panel edit land on the entry's lens (or the reverse), so
-- every table value gets a fresh copy.
local function CopyDetachedStyleValue(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = v
    end
    return copy
end

-- Build a DETACHED snapshot of what an entry actually renders with: the
-- panel's style with the entry's overrides laid on top.
--
-- Deliberately not GetEffectiveStyle: that returns buttonData.styleOverrides
-- itself wearing an __index metatable pointing at the group style, i.e. a live
-- alias of saved data. A config row handed that table would write straight
-- into the override store even for a section the entry never customized.
--
-- `pairs` never walks __index, so a metatable the runtime left on
-- styleOverrides is simply not seen here.
local function BuildDetachedEffectiveStyle(groupStyle, buttonData)
    local effective = {}
    for key, value in pairs(groupStyle or {}) do
        effective[key] = CopyDetachedStyleValue(value)
    end
    for key, value in pairs(buttonData and buttonData.styleOverrides or {}) do
        effective[key] = CopyDetachedStyleValue(value)
    end
    return effective
end

-- Resolve which lens the styling tabs are looking through:
--   "panel" - no entry selected (or the panel has no per-entry overrides at
--             all, as with texture panels): tabs edit the panel style.
--   "entry" - exactly one entry selected: tabs read that entry's effective
--             style; per-section scope decides where (or whether) they write.
--   "multi" - two or more entries selected: no single entry to show, so the
--             tabs stay on the panel style.
-- Multi-select is counted the same way every other per-entry surface counts
-- it, so scope chrome availability and lens mode can never disagree.
local function ResolveStyleLens(group)
    if not GroupSupportsPerButtonOverrides(group) then
        return { mode = "panel" }
    end

    local multiCount = 0
    if CS.selectedButtons then
        for _ in pairs(CS.selectedButtons) do multiCount = multiCount + 1 end
    end

    local buttonData = CS.selectedButton and group.buttons and group.buttons[CS.selectedButton]
    if buttonData and multiCount < 2 then
        return {
            mode = "entry",
            buttonIndex = CS.selectedButton,
            buttonData = buttonData,
            effective = BuildDetachedEffectiveStyle(group.style, buttonData),
        }
    end

    if multiCount >= 2 then
        return { mode = "multi" }
    end

    return { mode = "panel" }
end

-- Resolve one section against the lens. Returns scope, the table its controls
-- READ from, and the table they WRITE to.
--
-- A nil writeStyle is the inert marker and needs no separate flag: there is
-- nowhere for the section's controls to commit, so they are read-only.
--   "panel"/"multi" - panel style, read and written.
--   "panelOnly"     - a section with no override identity at all (sectionId
--                     nil): shown through the lens, never written per entry.
--   "denied"        - this entry type cannot use the section.
--   "customized"    - the entry owns this section: writes land in its
--                     styleOverrides.
--   "inherited"     - the entry follows the panel here: shown, not written.
local function ResolveLensSection(lens, group, sectionId)
    local mode = lens and lens.mode or "panel"

    if mode ~= "entry" then
        local groupStyle = group and group.style
        return (mode == "multi") and "multi" or "panel", groupStyle, groupStyle
    end

    if sectionId == nil then
        return "panelOnly", lens.effective, nil
    end

    local buttonData = lens.buttonData
    -- The denied REASON rides along as a fourth return so scope chrome can
    -- show the centralized copy for it. Callers that only want the first three
    -- are unaffected.
    local allowed, deniedReason = CanButtonUseConfigOverrideSection(buttonData, sectionId, group)
    if not allowed then
        return "denied", lens.effective, nil, deniedReason
    end

    if buttonData.overrideSections and buttonData.overrideSections[sectionId] then
        return "customized", lens.effective, buttonData.styleOverrides
    end

    return "inherited", lens.effective, nil
end

-- Inert sections are built exactly like live ones and then gated afterwards,
-- so a read-only section can never drift from the section it mirrors. Mark the
-- column before the section's widgets go in, apply after.
local function MarkInertRange(column)
    local children = column and column.children
    return children and #children or 0
end

local function MakeWidgetTreeInert(widget)
    if widget.SetDisabled then
        widget:SetDisabled(true)
    end

    -- Badges live on the widget's FRAME, not in the AceGUI child tree, so the
    -- walk below would never reach a gear. Gate it here instead - an inert
    -- section's advanced panel is just more controls for the same values.
    local frame = widget.frame
    local advancedBtn = frame and frame._cdcAdvancedBtn
    if advancedBtn then
        advancedBtn:Disable()
        SetAdvancedToggleInert(advancedBtn, true)
    end

    local children = widget.children
    if children then
        for i = 1, #children do
            local child = children[i]
            if child then
                MakeWidgetTreeInert(child)
            end
        end
    end
end

local function ApplyInertRange(column, mark)
    local children = column and column.children
    if not children then
        return
    end
    for i = (mark or 0) + 1, #children do
        local child = children[i]
        if child then
            MakeWidgetTreeInert(child)
        end
    end
end

-- Why an entry cannot use a section, single-sourced as one clause per reason:
-- the scope chrome's denied tooltip AND the Customizations list both explain
-- the same denials, and the two must never describe one differently.
-- Each surface supplies only its own framing around the shared clause.
-- displayMode is list-only: a section from another display mode is never
-- DRAWN, so no chrome ever asks about it.
local SECTION_DENIAL_CLAUSES = {
    noCooldown = "this spell does not have a real cooldown",
    auraTracking = "this entry is not tracking an aura",
    auraSection = "this entry sits in an Aura Only Section",
    displayMode = "the panel's current display mode does not use it",
    entryType = "this entry type cannot use it",
}

local function GetSectionDenialClause(reason)
    return SECTION_DENIAL_CLAUSES[reason] or SECTION_DENIAL_CLAUSES.entryType
end

local function AddSectionDeniedTooltipLines(reason)
    GameTooltip:AddLine("Not available: " .. GetSectionDenialClause(reason) .. ".", 0.5, 0.5, 0.5)
end

------------------------------------------------------------------------
-- REVERT GLYPH HELPER (shared by the per-section scope chrome below)
------------------------------------------------------------------------
local REVERT_GLYPH_ATLAS = "common-search-clearbutton"
local REVERT_GLYPH_SIZE = 12

local function GetOverrideSectionLabel(sectionId)
    local sectionDef = sectionId and ST.OVERRIDE_SECTIONS[sectionId]
    return sectionDef and sectionDef.label or sectionId
end

-- The revert's WORDING and its CLICK, split out from the glyph so the heading
-- chrome's text affordance is the same action in a different shape. Any change
-- to what reverting says or does lands here for both.
--
-- The label form exists because ONE revert in the config is not a style section:
-- the per-entry text format is a flat field (buttonData.textFormat) outside the
-- section machinery, and it must still read as the same action.
local function GetRevertTooltipTextForLabel(label)
    return "Revert " .. label .. " to panel settings"
end

local function GetRevertTooltipText(sectionId)
    return GetRevertTooltipTextForLabel(GetOverrideSectionLabel(sectionId))
end

local function PerformSectionRevert(buttonData, sectionId)
    CooldownCompanion:RevertSection(buttonData, sectionId)
    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    CooldownCompanion:RefreshConfigPanel()
end

-- The revert glyph's LOOK and its HOVER/CLICK contract, split so a revert that
-- is not a style section wears exactly the same control without restating the
-- atlas, the size or the tooltip shape.
local function ApplyRevertGlyphLook(icon)
    icon:SetSize(REVERT_GLYPH_SIZE, REVERT_GLYPH_SIZE)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER")
    icon:SetAtlas(REVERT_GLYPH_ATLAS)
end

local function BindRevertGlyph(revertBtn, tooltipText, onClick)
    revertBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(tooltipText)
        GameTooltip:Show()
    end)
    revertBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    revertBtn:SetScript("OnClick", onClick)
end

-- The revert glyph's look, wording and click flow. Worn by the scope chrome's
-- ROW reverts (the heading uses the text affordance below). The caller owns
-- creating and placing the button.
local function WireRevertGlyph(revertBtn, icon, buttonData, sectionId)
    ApplyRevertGlyphLook(icon)
    BindRevertGlyph(revertBtn, GetRevertTooltipText(sectionId), function()
        PerformSectionRevert(buttonData, sectionId)
    end)
end

------------------------------------------------------------------------
-- SCOPE CHROME
--
-- With an entry selected the styling tabs become a lens onto that entry, and
-- each section has to say whose values it is showing plus offer the one action
-- that changes that: Customize on a section the entry inherits from the panel,
-- Revert on one the entry owns. Sections the entry cannot use say so instead.
--
-- The chrome is the ESCAPE HATCH out of a read-only section, so it must stay
-- live where everything else is gated: it hangs off the widget's FRAME under
-- _cdcScope* names, and MakeWidgetTreeInert only ever walks AceGUI children
-- plus _cdcAdvancedBtn. Keep it that way - a scope control the inert pass can
-- reach would strand the entry with no way back out.
--
-- Every element is cached on that frame, re-styled from scratch on each
-- attach, and hidden both at attach time and on widget release, because the
-- Heading and row pools are shared and a recycled frame must never wear the
-- previous tenant's scope.
------------------------------------------------------------------------
local SCOPE_CHROME_GOLD = { 1, 0.82, 0 }
local SCOPE_CHROME_GOLD_HOVER = { 1, 0.93, 0.45 }
local SCOPE_CHROME_GREY = { 0.5, 0.5, 0.5 }
local SCOPE_CHROME_HEIGHT = 14
local SCOPE_GLYPH_BUTTON_SIZE = 16
local SCOPE_GLYPH_ICON_SIZE = 12
-- A long entry name would push the heading's fading rule (or a row's control
-- column) off the line, so the NAME is cut rather than the sentence round it.
local SCOPE_ENTRY_NAME_MAX_CHARS = 18

-- _cdcScopeRevert is the heading's RETIRED glyph. The heading reverts through
-- _cdcScopeRevertText now, but a Heading frame that already carries the glyph
-- from an earlier build must still have it hidden, so the field stays on the
-- cleanup list. Rows keep the glyph and use their own field.
local HEADING_SCOPE_FIELDS = { "_cdcScopeNote", "_cdcScopeAction", "_cdcScopeRevert", "_cdcScopeRevertText" }
local ROW_SCOPE_FIELDS = { "_cdcScopeRowAction", "_cdcScopeRowRevert", "_cdcScopeRowPanel" }

-- A grey row has no affordance to explain itself, so the explanation is a
-- HOVER - on the CONTROL, not the row. It rides RowWidgets' SetScopeTooltip,
-- which stores the lines and raises a transparent overlay over the row's
-- control region; the row frame's own OnEnter never renders them, so hovering
-- the label or the empty middle of a grey row says nothing about scope (owner
-- ruling 2026-08-14: a row-wide scope hover was tooltip soup).
local ROW_SCOPE_INHERITED_TOOLTIP = {
    "Panel setting",
    { "Follows the panel. Customize to edit.", 1, 1, 1, true },
}

-- Cutting a multi-byte character in half renders as a broken glyph, so walk
-- whole UTF-8 sequences instead of taking a byte slice.
local function TruncateEntryName(name)
    if not name or name == "" then
        return nil
    end
    local pos, count, len = 1, 0, #name
    while pos <= len do
        if count >= SCOPE_ENTRY_NAME_MAX_CHARS then
            return name:sub(1, pos - 1) .. "..."
        end
        local byte = name:byte(pos)
        pos = pos + ((byte < 0xC0 and 1) or (byte < 0xE0 and 2) or (byte < 0xF0 and 3) or 4)
        count = count + 1
    end
    return name
end

local function GetLensEntryName(lens)
    local buttonData = lens and lens.buttonData
    if not buttonData then
        return nil
    end
    -- The config already has one entry-name resolver (override spells, custom
    -- names, equipment slots, CDM child slots); never grow a second.
    local name = ST._GetConfigEntryDisplayName
        and ST._GetConfigEntryDisplayName(buttonData)
        or buttonData.name
    return TruncateEntryName(name)
end

-- Customize: copy the panel's values for this section onto the entry, then
-- rebuild. Deliberately no tab navigation - the section the owner is looking
-- at is the section that just became editable, in place.
--
-- The preview command center is the one caller that defers the config rebuild:
-- it has to prepare the destination and queue the section's advanced panel
-- first, then its existing navigation path performs the one refresh that
-- consumes both. The pinned mirror still updates immediately through
-- UpdateGroupStyle, so the preview never waits on that navigation.
local function PromoteLensSection(lens, group, sectionId, opts)
    local buttonData = lens and lens.buttonData
    local groupStyle = group and group.style
    if not (buttonData and groupStyle and sectionId) then
        return false
    end
    CooldownCompanion:PromoteSection(buttonData, groupStyle, sectionId)
    CooldownCompanion:UpdateGroupStyle(CS.selectedGroup)
    if not (opts and opts.deferRefresh) then
        CooldownCompanion:RefreshConfigPanel()
    end
    return true
end

-- One-click promotion for an inherited color control rebuilds the whole tab,
-- so the physical AceGUI ColorPicker the user clicked is released. Carry only
-- semantic identity across that rebuild; the replacement row consumes this
-- request and opens its own picker on the next frame.
local pendingInheritedColorOpen
local INHERITED_COLOR_CONTROL_TOOLTIP = {
    "Panel setting",
    { "Click to customize this color for the selected entry.", 1, 1, 1, true },
}

local function HideScopeChrome(frame, fields)
    for i = 1, #fields do
        local element = frame[fields[i]]
        if element then
            element:ClearAllPoints()
            element:Hide()
            element:EnableMouse(false)
            element:SetScript("OnEnter", nil)
            element:SetScript("OnLeave", nil)
            -- Frames have no OnClick script to clear, and asking for one is an
            -- error. Dropping it on the buttons releases the build's lens and
            -- group upvalues with the chrome.
            if element:GetObjectType() == "Button" then
                element:SetScript("OnClick", nil)
            end
            element:SetParent(nil)
            -- Re-attaching on the same frame in one build must not chain off
            -- the chrome that was just hidden.
            if frame._cdcHeadingBadgeTail == element then
                frame._cdcHeadingBadgeTail = nil
            end
        end
    end
end

-- The scope tooltip is DATA on the widget, and the row - not this file - owns
-- the overlay that shows it, so it is cleared the same way it is set: through
-- the row. Every path that hides row chrome clears it in the same breath, which
-- is what lowers the overlay. Guarded because only the row-grammar widgets
-- carry the channel.
local function SetRowScopeTooltip(rowWidget, lines)
    if rowWidget and rowWidget.SetScopeTooltip then
        rowWidget:SetScopeTooltip(lines)
    end
end

-- Denied rows explain themselves with the SHARED denial clause, so the row
-- hover and the heading's denied tooltip can never describe one denial
-- differently. Built per call because the clause depends on the reason.
local function BuildRowDeniedScopeTooltip(reason)
    local clause = GetSectionDenialClause(reason)
    return {
        "Not available",
        { clause:sub(1, 1):upper() .. clause:sub(2) .. ".", 1, 1, 1, true },
    }
end

-- Text chrome: a note (plain Frame) or an affordance (Button), both a single
-- line of text sized to the string so the badge chain can measure them.
local function EnsureScopeText(frame, field, clickable)
    local element = frame[field]
    if not element then
        element = CreateFrame(clickable and "Button" or "Frame", nil, frame)
        element:SetHeight(SCOPE_CHROME_HEIGHT)
        element.text = element:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        element.text:SetPoint("LEFT")
        frame[field] = element
    end

    element:SetParent(frame)
    element:ClearAllPoints()
    element:EnableMouse(clickable and true or false)
    element:SetScript("OnEnter", nil)
    element:SetScript("OnLeave", nil)
    if clickable then
        element:SetScript("OnClick", nil)
    end
    element:Show()
    element.text:Show()
    return element
end

local function SetScopeText(element, text, color)
    element.text:SetText(text or "")
    element.text:SetTextColor(color[1], color[2], color[3])
    element:SetWidth(math.max(element.text:GetStringWidth(), 1))
end

-- Glyph chrome: one 16px hit area carrying a 12px icon, worn by the revert
-- glyph. Every icon state it can wear is re-asserted here for pool reuse.
local function EnsureScopeGlyph(frame, field)
    local btn = frame[field]
    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetSize(SCOPE_GLYPH_BUTTON_SIZE, SCOPE_GLYPH_BUTTON_SIZE)
        btn.icon = btn:CreateTexture(nil, "OVERLAY")
        btn.icon:SetSize(SCOPE_GLYPH_ICON_SIZE, SCOPE_GLYPH_ICON_SIZE)
        btn.icon:SetPoint("CENTER")
        frame[field] = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn:EnableMouse(true)
    btn:Enable()
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn:SetScript("OnClick", nil)
    btn:Show()
    btn.icon:Show()
    btn.icon:SetDesaturated(false)
    btn.icon:SetVertexColor(1, 1, 1)
    return btn
end

-- The gold text affordance's hover language: brighten, and say what the click
-- does. Shared so Customize and Revert read as one family of controls.
local function WireScopeTextHover(action, tooltipText)
    action:SetScript("OnEnter", function(self)
        self.text:SetTextColor(SCOPE_CHROME_GOLD_HOVER[1], SCOPE_CHROME_GOLD_HOVER[2], SCOPE_CHROME_GOLD_HOVER[3])
        if tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(tooltipText)
            GameTooltip:Show()
        end
    end)
    action:SetScript("OnLeave", function(self)
        self.text:SetTextColor(SCOPE_CHROME_GOLD[1], SCOPE_CHROME_GOLD[2], SCOPE_CHROME_GOLD[3])
        GameTooltip:Hide()
    end)
end

local function WireScopeAction(action, lens, group, sectionId, tooltipText)
    WireScopeTextHover(action, tooltipText)
    action:SetScript("OnClick", function()
        PromoteLensSection(lens, group, sectionId)
    end)
end

-- Revert as text, for section headings. Same wording and same click as the row
-- glyph (both go through GetRevertTooltipText / PerformSectionRevert); only the
-- shape differs, so a heading's pair of controls reads as one line.
local function WireScopeRevertAction(action, buttonData, sectionId)
    WireScopeTextHover(action, GetRevertTooltipText(sectionId))
    action:SetScript("OnClick", function()
        PerformSectionRevert(buttonData, sectionId)
    end)
end

-- Scope chrome for a section HEADING: the note says whose values the section
-- is showing, and the affordance after it is the only way to change that.
-- Returns the resolved scope for callers that also gate the section's body.
local function AttachHeadingScopeChrome(heading, lens, group, sectionId)
    local frame = heading and heading.frame
    if not frame then
        return nil
    end

    local scope, _, _, deniedReason = ResolveLensSection(lens, group, sectionId)
    HideScopeChrome(frame, HEADING_SCOPE_FIELDS)

    local attached = false

    if scope == "inherited" then
        local note = EnsureScopeText(frame, "_cdcScopeNote", false)
        SetScopeText(note, "Panel setting", SCOPE_CHROME_GREY)
        ChainHeadingBadges(heading, note)

        local action = EnsureScopeText(frame, "_cdcScopeAction", true)
        SetScopeText(action, "Customize for this entry", SCOPE_CHROME_GOLD)
        WireScopeAction(action, lens, group, sectionId)
        ChainHeadingBadges(heading, action)
        attached = true

    elseif scope == "customized" then
        local entryName = GetLensEntryName(lens)
        local note = EnsureScopeText(frame, "_cdcScopeNote", false)
        SetScopeText(note, "Customized for " .. (entryName or "this entry"), SCOPE_CHROME_GOLD)
        ChainHeadingBadges(heading, note)

        -- The note already carries the state, so the action beside it is the
        -- bare verb: "Customized for X" then "Revert", not two sentences.
        local revert = EnsureScopeText(frame, "_cdcScopeRevertText", true)
        SetScopeText(revert, "Revert", SCOPE_CHROME_GOLD)
        WireScopeRevertAction(revert, lens.buttonData, sectionId)
        ChainHeadingBadges(heading, revert)
        attached = true

    elseif scope == "denied" then
        local note = EnsureScopeText(frame, "_cdcScopeNote", false)
        SetScopeText(note, "Not available", SCOPE_CHROME_GREY)
        note:EnableMouse(true)
        note:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            AddSectionDeniedTooltipLines(deniedReason)
            GameTooltip:Show()
        end)
        note:SetScript("OnLeave", function() GameTooltip:Hide() end)
        ChainHeadingBadges(heading, note)
        attached = true

    elseif scope == "panelOnly" then
        local note = EnsureScopeText(frame, "_cdcScopeNote", false)
        SetScopeText(note, "Applies to all entries", SCOPE_CHROME_GREY)
        ChainHeadingBadges(heading, note)
        attached = true
    end

    if attached then
        -- Chain, don't replace: the collapse button, the left-aligned heading
        -- variant and ChainHeadingBadges all keep handlers here.
        local prevOnRelease = heading.events and heading.events["OnRelease"]
        heading:SetCallback("OnRelease", function(widget, event, ...)
            if prevOnRelease then
                prevOnRelease(widget, event, ...)
            end
            HideScopeChrome(frame, HEADING_SCOPE_FIELDS)
        end)
    end

    return scope
end

-- Scope chrome for a single ROW, for sections whose identity is one setting
-- rather than a whole heading. Chained through the row's badge anchor so it
-- composes with the gear and info badges instead of fighting them.
--
-- Call this AFTER the row's disabled state is set: a row greyed out by its own
-- dependency keeps that grey, and the revert glyph still shows ownership.
local function AttachRowScopeChrome(rowWidget, lens, group, sectionId)
    local frame = rowWidget and rowWidget.frame
    if not (frame and rowWidget.badgeAnchor) then
        return nil
    end

    local scope, _, _, deniedReason = ResolveLensSection(lens, group, sectionId)
    HideScopeChrome(frame, ROW_SCOPE_FIELDS)
    SetRowScopeTooltip(rowWidget, nil)

    local attached = false

    if scope == "inherited" then
        local action = EnsureScopeText(frame, "_cdcScopeRowAction", true)
        SetScopeText(action, "Customize", SCOPE_CHROME_GOLD)
        WireScopeAction(action, lens, group, sectionId,
            "Customize " .. GetOverrideSectionLabel(sectionId) .. " for this entry")
        ST._AnchorRowBadge(rowWidget, action)
        -- The grey row states WHOSE values it shows only on the CONTROL's
        -- hover; the gold affordance beside the label is the visible half of
        -- the same message.
        SetRowScopeTooltip(rowWidget, ROW_SCOPE_INHERITED_TOOLTIP)
        attached = true

    elseif scope == "customized" then
        if rowWidget.rowLabel and not rowWidget.disabled then
            rowWidget.rowLabel:SetTextColor(SCOPE_CHROME_GOLD[1], SCOPE_CHROME_GOLD[2], SCOPE_CHROME_GOLD[3])
            frame._cdcScopeRowTinted = true
        end
        local revert = EnsureScopeGlyph(frame, "_cdcScopeRowRevert")
        WireRevertGlyph(revert, revert.icon, lens.buttonData, sectionId)
        ST._AnchorRowBadge(rowWidget, revert)
        attached = true

    elseif scope == "denied" then
        -- Still no BADGE on a denied row: the row is already inert-dimmed, and
        -- per-row badges read as clutter (owner ruling 2026-08-14). The reason
        -- is a hover on the CONTROL instead, so a row whose section heading is
        -- off screen can still say why it cannot be edited - and reaching for
        -- the control it cannot use is exactly when the owner asks.
        SetRowScopeTooltip(rowWidget, BuildRowDeniedScopeTooltip(deniedReason))
        attached = true

    end

    if attached then
        local prevOnRelease = rowWidget.events and rowWidget.events["OnRelease"]
        rowWidget:SetCallback("OnRelease", function(widget, event, ...)
            if prevOnRelease then
                prevOnRelease(widget, event, ...)
            end
            HideScopeChrome(frame, ROW_SCOPE_FIELDS)
            SetRowScopeTooltip(widget, nil)
            if frame._cdcScopeRowTinted then
                frame._cdcScopeRowTinted = nil
                -- Hand the label colour back to the row: SetIndent re-derives
                -- it from the row's own disabled/indented state. The row's
                -- OnAcquire does this again on reuse; this just does not wait.
                if widget.SetIndent then
                    widget:SetIndent(widget.indented)
                end
            end
        end)
    end

    return scope
end

-- Chrome for a row that stays PANEL-OWNED inside an entry-scope section: its
-- key has no override identity, so it always reads and writes the panel style,
-- and under an entry lens the grey label says so instead of the section's
-- Customize/Revert chrome. No affordance - there is nothing to promote.
local function AttachPanelSettingRowChrome(rowWidget)
    local frame = rowWidget and rowWidget.frame
    if not (frame and rowWidget.badgeAnchor) then
        return
    end

    HideScopeChrome(frame, ROW_SCOPE_FIELDS)
    -- The note is visible, so this row needs no hover explanation - but it must
    -- not keep one a previous tenant of the pooled row left behind.
    SetRowScopeTooltip(rowWidget, nil)

    local note = EnsureScopeText(frame, "_cdcScopeRowPanel", false)
    SetScopeText(note, "Panel setting", SCOPE_CHROME_GREY)
    ST._AnchorRowBadge(rowWidget, note)

    local prevOnRelease = rowWidget.events and rowWidget.events["OnRelease"]
    rowWidget:SetCallback("OnRelease", function(widget, event, ...)
        if prevOnRelease then
            prevOnRelease(widget, event, ...)
        end
        HideScopeChrome(frame, ROW_SCOPE_FIELDS)
        SetRowScopeTooltip(widget, nil)
    end)
end

------------------------------------------------------------------------
-- LENS SECTION HOST
------------------------------------------------------------------------
-- One context object owns the ritual every overridable section otherwise
-- repeats by hand: resolve the scope, pick the write-or-read table, derive the
-- disabled flag and shared-builder fallback, bracket the section's rows for
-- the inert pass, and attach scope chrome. Sections read fields and call
-- methods off the context instead of re-deriving the rules, so a convention
-- change lands here once.
--
--   local sec = ST._BeginLensSection(lens, group, "cooldownText", { column = textLeft })
--   ...rows bind tbl = sec.tbl, pass disabled = sec.disabled, guard commits
--      with `if not sec.write then return end`...
--   sec:Chrome(row)   -- row-level scope chrome, AFTER the row's disabled state is final
--   sec:Finish()      -- applies the inert bracket when the section is read-only
--
-- Field contract, all derived once at Begin:
--   scope         "panel" | "multi" | "panelOnly" | "denied" | "customized" | "inherited"
--   read / write  ResolveLensSection's tables; write == nil is the inert marker
--   tbl           write or read: the table value-displaying controls bind to.
--                 NOT for panel-only (nil sectionId) sections - their read is
--                 the detached snapshot, so writes would silently vanish;
--                 panel-only rows keep binding group.style and take only
--                 disabled/brackets from the host
--   disabled      write == nil: what row builders take as `disabled`
--   inert         the same test, named for bracket decisions
--   fallbackStyle group.style under "customized", else nil: what shared
--                 builders that layer overrides over panel values expect
--   deniedReason  ResolveLensSection's fourth return, for denial copy
--
-- A nil sectionId resolves "panelOnly" with no write table exactly under an
-- entry lens - the idiom for panel-only blocks that only need the bracket.
--
-- disabled/inert lean on group.style being non-nil in panel and multi modes
-- (a real panel always has one); a nil style would read as inert there. And
-- fallbackStyle IS group.style: sites that hand shared builders a local
-- `style` stay equivalent only while that local is the group's own style.
--
-- Brackets: passing opts.column marks it at Begin and Finish applies the inert
-- sweep to everything added since. A row that must stay live ahead of the
-- sweep is built first and the mark retaken with sec:Mark() (the foreign
-- dim-color row pattern), and a section spanning two columns takes a second
-- bracket with sec:Bracket()/sec:FinishBracket(). In practice opts.column fits
-- only sections whose column exists before Begin; heading-owning sections
-- create their columns after the chrome attaches, so they take their first
-- mark with sec:Mark() - that is the common path, not the exception.
local LensSection = {}
LensSection.__index = LensSection

-- The explicit-false rule for boolean override keys: under "customized" a
-- false must be STORED (deleting the key would fall back to the panel value
-- through the runtime __index), everywhere else false clears the key.
-- Spelled as statements: `and false or nil` collapses to nil, which is the
-- trap that kept explicit false from ever landing.
function LensSection:BoolValue(val)
    if val then
        return true
    end
    if self.scope == "customized" then
        return false
    end
    return nil
end

function LensSection:Chrome(row)
    -- The navigated-to section's anchor row (deferred highlight, see
    -- FireNavSettingHighlight): preciser than the collapsible's heading -
    -- several override sections can share one collapsible - and, unlike the
    -- advanced gear's rowKey match, present in every lens mode, including a
    -- section the entry only inherits.
    local pendingHighlight = CS.pendingSettingHighlight
    if pendingHighlight and pendingHighlight.sectionId
        and pendingHighlight.sectionId == self.sectionId
        and not pendingHighlight.sectionRowWidget then
        pendingHighlight.sectionRowWidget = row
    end
    return AttachRowScopeChrome(row, self.lens, self.group, self.sectionId)
end

-- Make an inherited color swatch direct-manipulable without enabling the
-- underlying inert ColorPicker. Promotion still owns the whole override
-- section; this is only a second entrance to the same Customize action.
function LensSection:DirectColorControl(row, key, externallyDisabled)
    if not (row and key) then return end

    if row.SetScopeControlAction then
        row:SetScopeControlAction(nil)
    end

    local pending = pendingInheritedColorOpen
    local contextMatches = pending
        and pending.group == self.group
        and pending.buttonData == (self.lens and self.lens.buttonData)
        and pending.groupId == CS.selectedGroup
        and pending.buttonIndex == CS.selectedButton
        and pending.sectionId == self.sectionId
        and pending.key == key

    if contextMatches and self.scope == "customized" then
        pendingInheritedColorOpen = nil
        local picker = row.colorPicker
        C_Timer.After(0, function()
            if CS.selectedGroup == pending.groupId
                and CS.selectedButton == pending.buttonIndex
                and self.lens and self.lens.buttonData == pending.buttonData
                and row.colorPicker == picker
                and row.disabled ~= true
                and picker and picker.frame and picker.frame:IsShown()
            then
                picker.frame:Click()
            end
        end)
    elseif pending and pending.sectionId == self.sectionId and pending.key == key then
        -- A rebuild landed on a different selection or scope. Never let its
        -- delayed action leak onto a later pooled row with the same setting.
        pendingInheritedColorOpen = nil
    end

    if self.scope ~= "inherited" or externallyDisabled
        or not row.SetScopeControlAction or not row.SetScopeTooltip then
        return
    end

    local expectedGroupId = CS.selectedGroup
    local expectedButtonIndex = self.lens and self.lens.buttonIndex
    row:SetScopeTooltip(INHERITED_COLOR_CONTROL_TOOLTIP)
    row:SetScopeControlAction(function(_, mouseButton)
        if mouseButton and mouseButton ~= "LeftButton" then return end
        if not (self.lens and self.lens.buttonData)
            or CS.selectedGroup ~= expectedGroupId
            or CS.selectedButton ~= expectedButtonIndex
        then
            return
        end

        local request = {
            group = self.group,
            buttonData = self.lens.buttonData,
            groupId = expectedGroupId,
            buttonIndex = expectedButtonIndex,
            sectionId = self.sectionId,
            key = key,
        }
        pendingInheritedColorOpen = request
        PromoteLensSection(self.lens, self.group, self.sectionId)
        if pendingInheritedColorOpen == request then
            pendingInheritedColorOpen = nil
        end
    end)
end

function LensSection:HeadingChrome(heading)
    return AttachHeadingScopeChrome(heading, self.lens, self.group, self.sectionId)
end

-- Chrome for a panel-owned row inside this section (see
-- AttachPanelSettingRowChrome): label only, and only under an entry lens.
function LensSection:PanelRowChrome(row)
    if self.lens and self.lens.mode == "entry" then
        AttachPanelSettingRowChrome(row)
    end
end

-- Take (or retake) the primary bracket mark. Heading-owning sections take
-- their FIRST mark here - their columns do not exist until after the heading
-- chrome attaches - and the dim-color pattern retakes it so rows already in
-- the column stay live.
function LensSection:Mark(column)
    self.column = column or self.column
    self.mark = MarkInertRange(self.column)
end

-- A second, independent bracket for sections spanning more than one column.
function LensSection:Bracket(column)
    return { column = column, mark = MarkInertRange(column) }
end

function LensSection:FinishBracket(bracket)
    if self.inert and bracket and bracket.column then
        ApplyInertRange(bracket.column, bracket.mark)
    end
end

function LensSection:Finish()
    if self.inert and self.column then
        ApplyInertRange(self.column, self.mark)
    end
end

local function BeginLensSection(lens, group, sectionId, opts)
    local scope, read, write, deniedReason = ResolveLensSection(lens, group, sectionId)
    local sec = setmetatable({
        lens = lens,
        group = group,
        sectionId = sectionId,
        scope = scope,
        read = read,
        write = write,
        deniedReason = deniedReason,
        tbl = write or read,
        disabled = write == nil,
        inert = write == nil,
        fallbackStyle = (scope == "customized") and group and group.style or nil,
    }, LensSection)

    local column = opts and opts.column
    if column then
        sec.column = column
        sec.mark = MarkInertRange(column)
    end
    return sec
end

------------------------------------------------------------------------
-- LENS NAVIGATION CHROME
------------------------------------------------------------------------

-- THE one decision point for which collapse key a section uses under the
-- current lens. Every navigation and section-building caller must route its
-- collapse key through here rather than testing the lens itself, so "which
-- sections open by default for this selection" has a single owner.
--
-- Sections an entry cannot edit ("panelOnly", "denied") are noise in an entry
-- lens, so they get their OWN key and open COLLAPSED the first time that key is
-- seen. The key is per SECTION, never per entry: collapsing one entry's inert
-- sections collapses them for the next entry too, which is the point - the
-- owner is expressing "hide what I cannot edit here", not a per-entry state.
-- Everything else keeps its base key, so a section's normal collapse state
-- survives selecting an entry and coming back.
--
-- Seeding writes to CS.collapsedSections, the store BuildCollapsibleSection
-- defaults to (truthy = collapsed). Lens sections must use that default store;
-- a caller with its own store would seed the wrong table.
local function ResolveLensCollapseKey(lens, group, sectionId, baseKey, opts)
    if not baseKey or not (lens and lens.mode == "entry") then
        return baseKey
    end

    local scope = ResolveLensSection(lens, group, sectionId)
    if scope ~= "panelOnly" and scope ~= "denied" then
        return baseKey
    end

    -- A panel-only collapsible can HOST an override section (Icon Settings
    -- hosts Icon Zoom). While the entry has CUSTOMIZED a hosted section it has
    -- live business inside, so the fold-by-default gives way (owner ruling
    -- 2026-08-14); an inherited hosted section stays behind the fold with its
    -- Customize one click away.
    local hosts = opts and opts.hostsSections
    if hosts then
        for i = 1, #hosts do
            if ResolveLensSection(lens, group, hosts[i]) == "customized" then
                return baseKey
            end
        end
    end

    local lensKey = "lens_" .. baseKey
    local store = CS.collapsedSections
    -- nil means never seen, which is exactly what the default-collapsed seed
    -- must not overwrite once the owner has expanded it (false is stored).
    if store and store[lensKey] == nil then
        store[lensKey] = true
    end
    return lensKey
end

-- One grey line at the top of a styling tab when several entries are selected.
-- The tabs edit the PANEL under a multi selection, and nothing else on the
-- surface says so: the per-section scope chrome only speaks under an entry
-- lens. Any other lens mode draws nothing.
--
-- includeEntryLens widens the note to a single-entry lens as well. The Layout
-- tab is the one caller: it has no per-entry sections, so it never grows the
-- scope chrome that tells the other tabs' story, and this line is the only
-- thing saying its edits land on the panel while an entry sits selected.
--
-- A plain AceGUI Label, the shape every other single-line note in the config
-- uses. Its stock font is already the small one the scope chrome wears, so
-- only the colour is set.
local function AddLensPanelScopeNote(container, lens, includeEntryLens)
    local mode = lens and lens.mode
    local speaks = mode == "multi" or (includeEntryLens and mode == "entry")
    if not (container and speaks) then
        return nil
    end

    local note = AceGUI:Create("Label")
    if ST._ConfigureWrappedHelperLabel then
        ST._ConfigureWrappedHelperLabel(note)
    end
    note:SetFullWidth(true)
    note:SetText("Editing panel settings. Changes apply to every entry.")
    note:SetColor(SCOPE_CHROME_GREY[1], SCOPE_CHROME_GREY[2], SCOPE_CHROME_GREY[3])
    container:AddChild(note)
    return note
end

------------------------------------------------------------------------
-- INFO BUTTON HELPER
------------------------------------------------------------------------
local tooltipMeasureFrame = CreateFrame("Frame", nil, UIParent)
tooltipMeasureFrame:Hide()

local tooltipMeasureHeader = tooltipMeasureFrame:CreateFontString(nil, "ARTWORK", "GameTooltipHeaderText")
local tooltipMeasureBody = tooltipMeasureFrame:CreateFontString(nil, "ARTWORK", "GameTooltipText")

local function ResetInfoTooltipWidth()
    GameTooltip:SetMinimumWidth(0)
end

local function MeasureInfoTooltipLineWidth(text, isHeader)
    local fs = isHeader and tooltipMeasureHeader or tooltipMeasureBody
    fs:SetText(text or "")
    return fs:GetUnboundedStringWidth()
end

-- Creates a (?) info button anchored to a frame. Replaces the repeated
-- CreateFrame→SetSize→SetPoint→CreateTexture→SetAtlas→tooltip pattern.
--
-- tooltipLines: array of entries. Strings become title lines (AddLine).
--   Tables {text, r, g, b, wrap} become body lines with color/wrapping.
--
-- cleanup: determines lifecycle management.
--   If it's a table:  button is inserted for lifecycle cleanup.
--   If it's an AceGUI widget: button is cleaned up via OnRelease callback.
local function CreateInfoButton(parentFrame, anchorFrame, anchorPoint, anchorRelPoint, xOff, yOff, tooltipLines, cleanup)
    local btn = CreateFrame("Button", nil, parentFrame)
    btn:SetSize(16, 16)
    btn:SetPoint(anchorPoint, anchorFrame, anchorRelPoint, xOff, yOff)
    local icon = btn:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("CENTER")
    icon:SetAtlas("QuestRepeatableTurnin")
    btn:SetScript("OnEnter", function(self)
        ResetInfoTooltipWidth()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        for _, line in ipairs(tooltipLines) do
            if type(line) == "table" then
                GameTooltip:AddLine(line[1], line[2], line[3], line[4], line[5])
            else
                GameTooltip:AddLine(line)
            end
        end
        GameTooltip:Show()
        -- Expand tooltip width to fit the widest non-wrapping line.
        -- Wrapping lines don't drive width directly but enforce a
        -- comfortable minimum so wrapped text isn't cramped.
        local pad = 20
        local wrapFloor = 250
        local maxW = 0
        local hasWrap = false
        for i, entry in ipairs(tooltipLines) do
            local isWrapping = type(entry) == "table" and entry[5]
            if isWrapping then
                hasWrap = true
            else
                local text = type(entry) == "table" and entry[1] or entry
                local w = MeasureInfoTooltipLineWidth(text, i == 1)
                if w > maxW then maxW = w end
            end
        end
        if hasWrap and maxW < wrapFloor then maxW = wrapFloor end
        if maxW > 0 then
            GameTooltip:SetMinimumWidth(maxW + pad)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        ResetInfoTooltipWidth()
        GameTooltip:Hide()
    end)

    if cleanup and cleanup.SetCallback then
        -- AceGUI widget: chain OnRelease cleanup so existing handlers (e.g.
        -- collapse/advanced button detach) are preserved.
        local prevOnRelease = cleanup.events and cleanup.events["OnRelease"]
        cleanup:SetCallback("OnRelease", function()
            if prevOnRelease then
                prevOnRelease(cleanup, "OnRelease")
            end
            btn:ClearAllPoints()
            btn:Hide()
            btn:SetParent(nil)
        end)
    else
        -- Array of buttons: insert for lifecycle cleanup.
        if CS.advancedSettingsPanelRefreshing then
            CS.advancedSettingsInfoButtons = CS.advancedSettingsInfoButtons or {}
            cleanup = CS.advancedSettingsInfoButtons
        end
        if type(cleanup) ~= "table" then
            return btn
        end
        table.insert(cleanup, btn)
    end

    return btn
end

local function ResetIndependentAnchorToParent(anchor)
    anchor.point = "CENTER"
    anchor.relativeTo = nil
    anchor.relativePoint = "CENTER"
    anchor.x = 0
    anchor.y = 0
end

local function ValidateIndependentAnchorTarget(frameName)
    local options = { domain = "external" }
    local ok = CooldownCompanion:ValidateAddonFrameAnchorTarget(frameName, options)
    if not ok then
        CooldownCompanion:PrintInvalidAnchorTargetReason(frameName, options)
        return false
    end
    return true
end

-- Row grammar only (RowWidgets.lua): the frame name takes the whole 140px
-- control column, so Pick does not share it - it goes to opts.pickContainer
-- (the head of the grid's other column) instead. The pre-redesign Flow
-- editbox + button pair had no call sites left after the conversion packets.
local function BuildIndependentAnchorTargetRow(container, anchor, applyFn, opts)
    local currentTargetName = anchor.relativeTo
    if not currentTargetName or currentTargetName == "UIParent" then
        currentTargetName = ""
    end

    local function CommitAnchorTargetText(text)
        if text == "" then
            local wasAnchored = anchor.relativeTo and anchor.relativeTo ~= "UIParent"
            if wasAnchored then
                ResetIndependentAnchorToParent(anchor)
            else
                anchor.relativeTo = nil
            end
        else
            local targetFrame = _G[text]
            if not targetFrame then
                CooldownCompanion:Print("Frame '" .. text .. "' not found.")
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            if not ValidateIndependentAnchorTarget(text) then
                CooldownCompanion:RefreshConfigPanel()
                return
            end
            anchor.relativeTo = text
        end
        applyFn()
        CooldownCompanion:RefreshConfigPanel()
    end

    local function StartAnchorTargetPick()
        CS.StartPickFrame(function(name)
            if CS.configFrame then
                CS.configFrame.frame:Show()
            end
            if name then
                if not ValidateIndependentAnchorTarget(name) then
                    CooldownCompanion:RefreshConfigPanel()
                    return
                end
                anchor.point = "TOPLEFT"
                anchor.relativeTo = name
                anchor.relativePoint = "BOTTOMLEFT"
                anchor.x = 0
                anchor.y = -5
                applyFn()
            end
            CooldownCompanion:RefreshConfigPanel()
        end, nil, { domain = "external" })
    end

    local targetRow = ST._AddEditBoxRow(container, {
        label = "Anchor to Frame",
        indent = opts and opts.indent,
        value = currentTargetName,
        onEnterPressed = function(text)
            CommitAnchorTargetText(text)
        end,
    })
    if targetRow.editbox and targetRow.editbox.Instructions then
        targetRow.editbox.Instructions:Hide()
    end

    -- Exactly one grammar row tall so the button's centre lands on the
    -- editbox's: Flow insets its single row by 3px and the button is 24 tall,
    -- so 3 + 24 + 3 fills the 30px band. noAutoHeight keeps Flow's own 27px
    -- report from shrinking it back.
    local pickRow = AceGUI:Create("SimpleGroup")
    pickRow:SetFullWidth(true)
    pickRow:SetLayout("Flow")
    pickRow:SetHeight(ST._RowGrammar and ST._RowGrammar.ROW_HEIGHT or 30)
    pickRow.noAutoHeight = true

    local rowPickBtn = AceGUI:Create("Button")
    rowPickBtn:SetText("Pick")
    rowPickBtn:SetAutoWidth(true)
    rowPickBtn:SetCallback("OnClick", StartAnchorTargetPick)
    pickRow:AddChild(rowPickBtn)

    -- Added last so the List-layout column measures a populated row.
    ;((opts and opts.pickContainer) or container):AddChild(pickRow)
    return targetRow
end

------------------------------------------------------------------------
-- COMPACT MODE CONTROLS
------------------------------------------------------------------------
local function NormalizeCompactGrowthDirection(growthDirection)
    if growthDirection == "start" or growthDirection == "left" or growthDirection == "top" then
        return "start"
    end
    if growthDirection == "end" or growthDirection == "right" or growthDirection == "bottom" then
        return "end"
    end
    return "center"
end

-- orientationOverride exists for the Aura Panel row: an Aura BAR Panel is one
-- vertical column no matter what style.barOrientation still says (the aura
-- container's bars branch hard-codes the axis), and a stale horizontal key from
-- before the conversion would otherwise label the row Left/Center/Right for a
-- block that moves up and down.
local function GetCompactGrowthDirectionLabels(group, orientationOverride)
    local style = group.style or {}
    local orientation = orientationOverride or ST.GetPanelLayoutOrientation(group.displayMode, style)
    local growthOrigin = style.growthOrigin or "TOPLEFT"
    if ST.IsCenteredGrowthOrigin(growthOrigin) then
        -- An ACTIVE centered edge hides the compact alignment row entirely
        -- (it supersedes start/center/end), so a centered value here is
        -- axis-mismatched and the runtime folds it to TOPLEFT; these labels
        -- must agree with that fold.
        growthOrigin = "TOPLEFT"
    end
    if orientation == "vertical" then
        local startIsTop = (growthOrigin == "TOPLEFT" or growthOrigin == "TOPRIGHT")
        return {
            start = startIsTop and "Top" or "Bottom",
            center = "Center",
            ["end"] = startIsTop and "Bottom" or "Top",
        }
    end
    local startIsLeft = (growthOrigin == "TOPLEFT" or growthOrigin == "BOTTOMLEFT")
    return {
        start = startIsLeft and "Left" or "Right",
        center = "Center",
        ["end"] = startIsLeft and "Right" or "Left",
    }
end

------------------------------------------------------------------------
-- CUSTOMIZATIONS (entry Settings pane)
--
-- The one actionable index of everything this entry customizes. The styling
-- tabs chrome a customization IN PLACE, but only where they draw it: a section
-- belongs to one display mode's tabs, and a section the entry can no longer use
-- resolves "denied" with no revert at all. The saved keys survive either state
-- on purpose - they apply again when the block lifts - so a list that only
-- showed the unreachable ones answered "how do I undo this?" for the hard cases
-- and stayed silent for the easy ones.
--
-- So the list shows them ALL (owner ruling 2026-08-14, superseding the earlier
-- inactive-only list): active ones plain, inactive ones carrying the same
-- denial clause the scope chrome uses, each with its own revert, the name a
-- link to where the section is edited, and one Revert All on the heading.
-- Built only while at least one customization exists.
------------------------------------------------------------------------

-- One list for both frames the chrome lands on: a heading frame has no row
-- field and a row frame has no heading field, so HideScopeChrome skipping the
-- absent ones costs a nil read and removes a second constant.
local CUSTOMIZATIONS_CHROME_FIELDS = {
    "_cdcCustomizationsRevertAll",
    "_cdcCustomizationsRevert",
    "_cdcCustomizationsGear",
    "_cdcCustomizationsName",
}

-- The per-entry text format is a FLAT field (buttonData.textFormat) outside the
-- styleOverrides section machinery, so it has no section id, no label of its
-- own, and no home in ST._SECTION_HOME. It is still a customization, and the
-- one index of them cannot be the surface that forgets it.
--
-- Named for the THING, not its state: inside a section titled Customizations
-- every row is already custom. Word-for-word what the entry-slot hover tooltip
-- (ButtonPanelPreview) calls the same field, because Defaults.lua contracts
-- these two surfaces to never list a customization differently.
local FORMAT_ROW_LABEL = "Text Format"

local CUSTOMIZATIONS_TOOLTIP = {
    "Customizations",
    {"Everything this entry has its own settings for.", 1, 1, 1, true},
    " ",
    {"Click a name to open where it is edited.", 1, 1, 1, true},
    " ",
    {"Inactive ones stay saved and apply again when whatever blocks them changes.", 1, 1, 1, true},
}

-- This list's framing around the single-sourced denial clause (see
-- SECTION_DENIAL_CLAUSES above - never word a denial here directly).
local function GetInactiveCustomizationReason(reason)
    return "Saved for this entry, but inactive: " .. GetSectionDenialClause(reason) .. "."
end

-- Where this section is EDITED in the panel's display mode. Read straight off
-- the registry the tab builders state (ST._SECTION_HOME), because the answer is
-- only needed to decide whether the row's name is a link at all; the navigation
-- itself belongs to PreviewCommandCenter's route core and is never rebuilt here.
-- A mode with no home for the section (another mode's section, a trigger panel,
-- the rotation assistant) answers nil and the name stays plain text.
--
-- The WHOLE entry, not just its tab: the home also carries the optional
-- availability predicates the two helpers below consult (contract stated at the
-- first registration, ST._SECTION_HOME.bars in BarModeTabs.lua).
local function GetSectionHome(displayMode, sectionId)
    local homes = ST._SECTION_HOME
    local byMode = homes and homes[displayMode]
    return byMode and byMode[sectionId] or nil
end

-- Sections are drawn CONDITIONALLY. A bar panel with the icon hidden draws no
-- Icon Tint and no Timers/States block at all; the aura sections exist only
-- while the group tracks an aura. A name link into a section that is not there
-- lands on a tab where nothing answers the click, so the list asks the home
-- first. A section whose home registers no predicate is always drawn.
-- The panel-wide answer comes FIRST and needs no per-section registration: an
-- Aura Panel's tabs leave the sections its pure-aura entries can never use out
-- entirely rather than drawing them denied, so there is no row left for a name
-- link to land on. Every one of those gates cites ST.CanGroupUseOverrideSection,
-- so asking it here covers them all at once and cannot drift from them.
local function IsSectionHomeAvailable(home, group, style, sectionId)
    if sectionId and not ST.CanGroupUseOverrideSection(group, sectionId) then
        return false
    end
    local available = home and home.available
    if not available then
        return true
    end
    return available(group, style) and true or false
end

-- Same question for the section's advanced GEAR, which has a gate of its own:
-- a drawn section whose parent readout toggle is off builds no gear
-- (AddAdvancedToggle's isEnabled), and a queued advanced key with no gear left
-- to consume it would open a panel behind a gear that is not on screen.
local function IsSectionHomeGearBuilt(home, group, style)
    local gearEnabled = home and home.gearEnabled
    if not gearEnabled then
        return true
    end
    return gearEnabled(group, style) and true or false
end

-- Which advanced GEAR a section owns in the panel's display mode, inverted from
-- the per-mode maps the tab builders state (those are keyed advancedKey ->
-- sectionId; this list wants the other direction).
--
-- The maps are named, not referenced: every file that declares one loads AFTER
-- this one (the .toc), so they are fetched off ST at build time, exactly as
-- ST._SECTION_HOME is above.
--
-- A mode's sources are EXACTLY the maps that mode's own builders sweep, so this
-- list can never offer a gear the mode does not draw. Icons builds both the
-- Appearance and Indicators tabs and each of those sweeps both maps; bars builds
-- its two tabs off the one bars map (its pandemic, unusable and tooltip gears
-- are listed there, so the indicators map is not a bars source); text's map is
-- deliberately empty today. Textures has no override sections at all, so it has
-- no entry and no row here ever resolves a gear.
local CUSTOMIZATIONS_GEAR_MAPS_BY_MODE = {
    icons = { "_APPEARANCE_SECTION_BY_ADVANCED_KEY", "_INDICATORS_OVERRIDE_SECTION_BY_ADVANCED_KEY" },
    bars = { "_BARMODE_SECTION_BY_ADVANCED_KEY" },
    text = { "_TEXTMODE_SECTION_BY_ADVANCED_KEY" },
}

-- A section with TWO OR MORE gears in one mode gets NO gear on its row. Pandemic
-- is the live case: the glow and the marker are two advanced panels under one
-- override section. Two gears on one list row is clutter, and silently picking
-- either one would misstate where the click lands - the name link already opens
-- the section with both gears in view, which is the honest answer.
--
-- A sentinel rather than a delete, so a third key arriving later cannot re-claim
-- the row the first pair disqualified.
local CUSTOMIZATIONS_GEAR_AMBIGUOUS = {}

local function BuildCustomizationsGearMap(displayMode)
    local sources = CUSTOMIZATIONS_GEAR_MAPS_BY_MODE[displayMode]
    if not sources then
        return nil
    end

    local bySection
    for i = 1, #sources do
        local map = ST[sources[i]]
        if map then
            for advancedKey, sectionId in pairs(map) do
                bySection = bySection or {}
                local current = bySection[sectionId]
                if current == nil then
                    bySection[sectionId] = advancedKey
                elseif current ~= advancedKey then
                    bySection[sectionId] = CUSTOMIZATIONS_GEAR_AMBIGUOUS
                end
            end
        end
    end
    return bySection
end

-- The list gear wears the settings-side gear's LOOK (AddAdvancedToggle's atlas,
-- icon size and idle tint) on the scope chrome's 16px glyph hit area, so it sits
-- in a row's badge chain beside the revert glyph rather than at the gear's own
-- 14px settings size.
--
-- Only the look and the panel QUEUE are shared with that gear. This one has no
-- live panel binding: it never goes gold, never rebinds a descriptor and never
-- toggles a panel shut. It is a link that happens to end in a panel.
local ADVANCED_GLYPH_ICON_SIZE = 13

local function ApplyAdvancedGlyphLook(icon)
    icon:SetSize(ADVANCED_GLYPH_ICON_SIZE, ADVANCED_GLYPH_ICON_SIZE)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER")
    icon:SetAtlas(ADVANCED_TOGGLE_ATLAS, false)
    icon:SetVertexColor(ADVANCED_TOGGLE_IDLE_COLOR[1], ADVANCED_TOGGLE_IDLE_COLOR[2],
        ADVANCED_TOGGLE_IDLE_COLOR[3], ADVANCED_TOGGLE_IDLE_COLOR[4])
end

-- The row NAME as a link: a transparent hit area pinned over the label's text,
-- carrying the row's OWN FontString as its `text` so the scope chrome's
-- hover-brighten (WireScopeTextHover) works on the real label rather than a
-- second string laid over it.
--
-- Cached on the row FRAME like every other piece of chrome, and permanently
-- paired with that frame's label (BuildRowBase creates both, and neither
-- outlives the other), so the stored reference can never name another row's
-- text. The width is re-measured per build because the label is set per build.
local function EnsureRowNameButton(row, field)
    local frame = row.frame
    local btn = frame[field]
    if not btn then
        btn = CreateFrame("Button", nil, frame)
        btn:SetHeight(SCOPE_CHROME_HEIGHT)
        btn.text = row.rowLabel
        frame[field] = btn
    end

    btn:SetParent(frame)
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", row.rowLabel, "LEFT", 0, 0)
    btn:SetWidth(math.max(row.rowLabel:GetStringWidth(), 1))
    btn:EnableMouse(true)
    btn:Enable()
    btn:SetScript("OnEnter", nil)
    btn:SetScript("OnLeave", nil)
    btn:SetScript("OnClick", nil)
    btn:Show()
    return btn
end

-- Clearing the entry's text format. Same two refreshes the Format tab's own
-- "Revert to Panel Format" makes, minus its CancelTextFormatTabCommit: a
-- debounced format write cannot be pending while this list is on screen. The
-- format editor is torn down at every seam that takes its container away, and
-- selecting the entry Settings tab is one of them - Panel.lua's entry TabGroup
-- calls ST._ReleaseTextFormatTabEditor before it builds anything, which flushes
-- the pending write and drops the timer. No guard, because there is nothing
-- reachable to guard against.
local function PerformFormatRevert(buttonData)
    buttonData.textFormat = nil
    CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
    CooldownCompanion:RefreshConfigPanel()
end

-- Every customization on one entry, in one pass. Deliberately NOT a loop over
-- PerformSectionRevert: that helper ends in UpdateGroupStyle plus a full config
-- rebuild, and paying for both once per section would rebuild the pane N times
-- to arrive exactly where one rebuild lands.
--
-- Resolved from ids rather than handed live tables: this runs behind a confirm
-- popup, and the entry it names can be gone by the time the click comes back.
local function RevertAllEntryCustomizations(groupId, buttonIndex)
    local profile = CooldownCompanion.db and CooldownCompanion.db.profile
    local group = profile and profile.groups and profile.groups[groupId]
    local buttonData = group and group.buttons and group.buttons[buttonIndex]
    if not buttonData then
        return
    end

    local sections = buttonData.overrideSections
    if sections then
        -- RevertSection clears keys out of this same table, so the local stays
        -- in step with it even on the call that empties it and detaches it from
        -- the entry.
        for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER or {}) do
            if sections[sectionId] then
                CooldownCompanion:RevertSection(buttonData, sectionId)
            end
        end
    end

    -- Gated on being SET, which is the same gate the list draws the row on, so
    -- Revert All clears exactly the rows it was shown beside - including a
    -- format stranded on a panel that is no longer a text panel, which the list
    -- shows as inactive rather than hiding.
    local formatCleared = false
    if buttonData.textFormat ~= nil then
        buttonData.textFormat = nil
        formatCleared = true
    end

    CooldownCompanion:UpdateGroupStyle(groupId)
    -- The format is re-parsed on the way through PopulateGroupButtons, which
    -- only the frame refresh reaches. Paid once, and only when a format was
    -- actually cleared.
    if formatCleared then
        CooldownCompanion:RefreshGroupFrame(groupId)
    end
    CooldownCompanion:RefreshConfigPanel()
end

local function BuildCustomizationsSection(scroll, group, buttonData, infoButtons)
    if not (group and buttonData) then
        return
    end

    -- Collect first, build second: the heading only exists when a row does.
    -- Same order and gates the entry-slot hover tooltip uses for these
    -- sections, so the two surfaces can never list them differently.
    local displayMode = group.displayMode or "icons"
    local sections = buttonData.overrideSections
    local items = {}

    -- The style the section homes' availability predicates are asked about.
    -- This list is built with exactly ONE entry selected, so the lens resolves
    -- "entry" and hands over the detached effective style - the same table a
    -- builder's `sec.read` resolves to there, which is what those predicates
    -- mirror. The fallback is the panel style for the same reason: under any
    -- other lens that is what the builders' gates read.
    local lens = ResolveStyleLens(group)
    local predicateStyle = (lens and lens.mode == "entry" and lens.effective) or group.style or {}

    -- Leads the list: the format is what a text entry IS, so its customization
    -- reads first rather than under the style sections.
    --
    -- A saved format on a panel that is no longer a text panel is stranded, not
    -- gone - the same "saved but unreachable" state the sections have - so it
    -- takes the same inactive shape: the displayMode clause, its own revert, and
    -- NO name link, because the Format tab it would open only exists in text
    -- mode (tab = nil is what drives that, exactly as it does for a section
    -- with no home in this mode).
    if buttonData.textFormat ~= nil then
        local textMode = displayMode == "text"
        items[#items + 1] = {
            format = true,
            label = FORMAT_ROW_LABEL,
            reason = (not textMode) and "displayMode" or nil,
            tab = textMode and "format" or nil,
        }
    end

    if sections then
        for _, sectionId in ipairs(ST.OVERRIDE_SECTION_ORDER or {}) do
            if sections[sectionId] then
                local sectionDef = ST.OVERRIDE_SECTIONS[sectionId]
                local allowed, deniedReason = CanButtonUseConfigOverrideSection(buttonData, sectionId, group)
                local modeOk = sectionDef and sectionDef.modes and sectionDef.modes[displayMode] == true
                local reason
                if not allowed then
                    reason = deniedReason or "entryType"
                elseif not modeOk then
                    reason = "displayMode"
                end
                local home = GetSectionHome(displayMode, sectionId)
                items[#items + 1] = {
                    sectionId = sectionId,
                    label = GetOverrideSectionLabel(sectionId),
                    reason = reason,
                    home = home,
                    tab = home and home.tab or nil,
                }
            end
        end
    end

    if #items == 0 then
        return
    end

    local heading, collapsed = BuildCollapsibleSection(scroll, "Customizations",
        CS.selectedGroup .. "_" .. CS.selectedButton .. "_customizations",
        nil, nil, { leftAligned = true })
    ChainHeadingBadges(heading, CreateInfoButton(heading.frame, heading.label,
        "LEFT", "RIGHT", 4, 0, CUSTOMIZATIONS_TOOLTIP, infoButtons))

    -- Heading-level action in the scope chrome's own shape: gold text that
    -- brightens on hover, beside the thing it acts on. Behind a confirm popup
    -- because it is the one control here that cannot be undone one row at a
    -- time. Attached whether or not the section is collapsed - the whole point
    -- of a folded list is still being able to empty it.
    local groupId, buttonIndex = CS.selectedGroup, CS.selectedButton
    local headingFrame = heading.frame
    local revertAll = EnsureScopeText(headingFrame, "_cdcCustomizationsRevertAll", true)
    SetScopeText(revertAll, "Revert All", SCOPE_CHROME_GOLD)
    WireScopeTextHover(revertAll, "Revert every customization on this entry")
    revertAll:SetScript("OnClick", function()
        local entryName = ST._GetConfigEntryDisplayName
            and ST._GetConfigEntryDisplayName(buttonData)
            or buttonData.name
        -- Through the house raiser, not StaticPopup_Show: the config window
        -- sits high enough to cover a stock dialog.
        local showPopup = ST._ShowPopupAboveConfig
        if showPopup then
            showPopup("CDC_REVERT_ENTRY_CUSTOMIZATIONS", entryName or "this entry",
                { groupId = groupId, buttonIndex = buttonIndex })
        end
    end)
    ChainHeadingBadges(heading, revertAll)

    -- Chain, don't replace: BuildCollapsibleSection installs its own handler.
    local prevHeadingRelease = heading.events and heading.events["OnRelease"]
    heading:SetCallback("OnRelease", function(widget, event, ...)
        if prevHeadingRelease then
            prevHeadingRelease(widget, event, ...)
        end
        HideScopeChrome(headingFrame, CUSTOMIZATIONS_CHROME_FIELDS)
    end)

    if collapsed then
        return
    end

    -- Row-grammar label rows in the grid's left column, so the list keeps the
    -- config's half-width cell instead of stretching across the pane. The
    -- revert glyph rides the label's badge chain; the reason is the row's
    -- hover tooltip. Read at call time, not load time: RowWidgets and Helpers
    -- have no load-order contract between them.
    local AddLabelRow = ST._AddLabelRow
    local AnchorRowBadge = ST._AnchorRowBadge
    local listLeft = ST._BeginRowGrid(scroll)
    -- Built once for the whole list: the mode is fixed for this pane, and the
    -- inversion walks every gear map the mode owns.
    local gearBySection = BuildCustomizationsGearMap(displayMode)

    for _, item in ipairs(items) do
        local label = item.label
        local reasonText = item.reason and GetInactiveCustomizationReason(item.reason) or nil
        local row = AddLabelRow(listLeft, {
            label = label,
            -- Active rows say nothing in the control column: the section is
            -- listed here, which already means it is customized. Only the
            -- inactive ones have news.
            controlText = item.reason and "Inactive" or nil,
            tooltip = reasonText and { label, {reasonText, 1, 1, 1, true} } or nil,
        })

        -- Every piece of chrome is cached on the row's FRAME (the pool recycles
        -- frames), re-wired per build, and hidden on release so a recycled row
        -- never wears a previous tenant's revert or link.
        local frame = row.frame

        -- Read before the badges so the gear can require it: a gear whose
        -- section has no home in this mode - or whose home is not DRAWN for
        -- this group and this entry - would navigate nowhere. An unavailable
        -- row keeps everything else it had: its revert, and its inactive clause
        -- when it has one. Only the link goes.
        local navigable = item.tab ~= nil
            and IsSectionHomeAvailable(item.home, group, predicateStyle, item.sectionId)

        -- ADVANCED GEAR (owner ruling 2026-08-14): a row whose section has an
        -- advanced panel carries the gear too, so the list is one click from the
        -- deep settings rather than a stop on the way to them.
        --
        -- ACTIVE rows only, and never the Text Format row. An inactive section
        -- is not drawn anywhere in this mode, so the tab it would land on builds
        -- no gear to consume the queue and the panel would never open; the
        -- format row is a flat field with no section and no advanced panel at
        -- all. Both fall out of the gates below rather than being special-cased.
        --
        -- The gear ALSO has to exist at the destination: its section can be
        -- drawn with the gear itself unbuilt (parent readout toggled off), and
        -- the queue is consumed before that gate runs, so a panel would open
        -- behind a gear that is not on screen.
        local advancedKey
        if navigable and not item.reason and item.sectionId and gearBySection
            and IsSectionHomeGearBuilt(item.home, group, predicateStyle) then
            advancedKey = gearBySection[item.sectionId]
            if advancedKey == CUSTOMIZATIONS_GEAR_AMBIGUOUS then
                advancedKey = nil
            end
        end

        -- Anchored FIRST, so the chain reads [name][gear][revert]. That is the
        -- row grammar's own order (RowWidgets' AnchorRowBadge: gear, then info,
        -- then scope chrome), and the revert is scope chrome.
        if advancedKey then
            local gear = EnsureScopeGlyph(frame, "_cdcCustomizationsGear")
            ApplyAdvancedGlyphLook(gear.icon)
            gear:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ADVANCED_TOGGLE_OPEN_TOOLTIP)
                GameTooltip:Show()
            end)
            gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
            -- Same route the name link takes, plus the key: the destination is
            -- resolved by PreviewCommandCenter from the section registry, and
            -- the panel is queued there after every navigation write.
            local gearSectionId = item.sectionId
            gear:SetScript("OnClick", function()
                local navigate = ST._NavigateToSectionHome
                if navigate then
                    navigate(gearSectionId, { advancedKey = advancedKey })
                end
            end)
            AnchorRowBadge(row, gear)
        end

        local revert = EnsureScopeGlyph(frame, "_cdcCustomizationsRevert")
        if item.format then
            ApplyRevertGlyphLook(revert.icon)
            BindRevertGlyph(revert, GetRevertTooltipTextForLabel(label), function()
                PerformFormatRevert(buttonData)
            end)
        else
            WireRevertGlyph(revert, revert.icon, buttonData, item.sectionId)
        end
        AnchorRowBadge(row, revert)

        -- The name becomes a link only where there is somewhere to go. Gold is
        -- the affordance here, not the "customized" tint the scope chrome uses
        -- on a row label: inside a section titled Customizations every row is
        -- customized, so the colour is free to mean "clickable".
        if navigable then
            row.rowLabel:SetTextColor(SCOPE_CHROME_GOLD[1], SCOPE_CHROME_GOLD[2], SCOPE_CHROME_GOLD[3])
            local nav = EnsureRowNameButton(row, "_cdcCustomizationsName")
            -- The link covers the label, so the row frame's own hover no longer
            -- fires there; the clause rides the link's tooltip so an inactive
            -- row still explains itself under the pointer.
            WireScopeTextHover(nav, reasonText)
            -- The route resolves the destination itself, from the same
            -- registry consulted above; the format row has no section and
            -- names its tab instead.
            local sectionId, formatRow = item.sectionId, item.format
            nav:SetScript("OnClick", function()
                local navigate = ST._NavigateToSectionHome
                if navigate then
                    navigate(sectionId, formatRow and { tab = "format" } or nil)
                end
            end)
        end

        local prevOnRelease = row.events and row.events["OnRelease"]
        row:SetCallback("OnRelease", function(widget, event, ...)
            if prevOnRelease then
                prevOnRelease(widget, event, ...)
            end
            HideScopeChrome(frame, CUSTOMIZATIONS_CHROME_FIELDS)
            if navigable then
                -- Hand the label colour back to the row: SetIndent re-derives
                -- it from the row's own disabled/indented state. The row's
                -- OnAcquire does this again on reuse; this just does not wait.
                if widget.SetIndent then
                    widget:SetIndent(widget.indented)
                end
            end
        end)
    end
end

-- Builds the compact mode section shared by the icon (GroupTabs), bar
-- (BarModeTabs) and text (TextModeTabs) tabs: a CDC-CheckBoxRow whose gear
-- and info badge chain off the end of its label, with the growth-direction
-- and max-visible-buttons controls behind the gear.
--
-- Row grammar only (RowWidgets.lua) - the pre-redesign full-width/half-width
-- checkbox shape had no call sites left once the bar and text tabs converted.
-- opts.indent makes it a child row.
--
-- An Aura Panel builds NOTHING here. Blizzard's aura container packs only the
-- active auras, so collapsing is inherent and always on (compactLayout is
-- forced false at birth) and Max Visible Buttons would be a limit CC never
-- applies. The one question that survives - WHICH END the packed block holds -
-- is not a compact-mode sub-setting for such a panel, it is simply how the
-- panel arranges itself, so it lives on the Layout tab's Arrangement section as
-- "Collapse Direction" (owner ruling 2026-08-15) rather than behind a toggle
-- that does not exist here.
local function BuildCompactModeControls(container, group, tabInfoButtons, opts)
    if CooldownCompanion:IsAuraPanel(group) then return end

    local suppressionReasons = CooldownCompanion.GetGroupCompactLayoutSuppressionReasons
        and CooldownCompanion:GetGroupCompactLayoutSuppressionReasons(CS.selectedGroup)
        or nil
    local compactSuppressed = type(suppressionReasons) == "table" and #suppressionReasons > 0

    local function ApplyCompactLayout(val)
        group.compactLayout = val == true
        CooldownCompanion:PopulateGroupButtons(CS.selectedGroup)
        local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
        if frame then frame._layoutDirty = true end
        CooldownCompanion:RefreshConfigPanel()
    end

    local compactCb = ST._AddCheckboxRow(container, {
        label = compactSuppressed and "Compact Mode (temporarily inactive)" or "Compact Mode",
        value = group.compactLayout or false,
        indent = opts and opts.indent,
        onChange = ApplyCompactLayout,
    })

    -- Single rail (AdvancedSettingsPanel.lua): a panel is one narrow column, so
    -- both rows go straight onto the panel scroll and their (?) badges chain off
    -- the end of each row's label. The row builders are read at CALL time, for
    -- the load-order reason stated at AddFontControls' row branch below.
    local function BuildCompactAdvanced(panel)
        -- A centered Growth Direction on the Layout tab already answers the
        -- alignment question per line (owner ruling 2026-08-16), so the
        -- start/center/end row would contradict it and stays hidden.
        local style = group.style or {}
        local centeredActive = ST.GetCenteredGrowthEdge(
            style.growthOrigin,
            ST.GetPanelLayoutOrientation(group.displayMode, style)
        ) ~= nil
        if not centeredActive then
            local growthRow = ST._AddDropdownRow(panel, {
                label = "Growth Direction",
                list = GetCompactGrowthDirectionLabels(group),
                order = {"start", "center", "end"},
                value = NormalizeCompactGrowthDirection(group.compactGrowthDirection),
                onChange = function(val)
                    group.compactGrowthDirection = NormalizeCompactGrowthDirection(val)
                    local frame = CooldownCompanion.groupFrames[CS.selectedGroup]
                    if frame then
                        frame._layoutDirty = true
                        if frame:IsShown() then
                            CooldownCompanion:UpdateGroupLayout(CS.selectedGroup)
                        end
                    end
                end,
            })
            -- Anchor args are a placeholder - AnchorRowBadge re-points the button
            -- onto the end of the row's label.
            ST._AnchorRowBadge(growthRow, CreateInfoButton(growthRow.frame, growthRow.frame, "LEFT", "LEFT", 0, 0, {
                "Growth Direction",
                {"Choose which edge acts as the compact anchor icon/bar as visibility changes. Horizontal uses Left/Center/Right, vertical uses Top/Center/Bottom.", 1, 1, 1, true},
            }, tabInfoButtons))
        end

        local totalButtons = #group.buttons
        local function SetMaxVisibleButtons(val)
            val = math.floor(val + 0.5)
            if val >= totalButtons then
                group.maxVisibleButtons = 0
            else
                group.maxVisibleButtons = val
            end
        end
        local maxVisRow = ST._AddSliderRow(panel, {
            label = "Max Visible Buttons",
            min = 1, max = math.max(totalButtons, 1), step = 1,
            value = group.maxVisibleButtons == 0 and totalButtons or group.maxVisibleButtons,
            onChange = function(val)
                local committed = group.maxVisibleButtons
                SetMaxVisibleButtons(val)
                RefreshSelectedButtonsPreview()
                group.maxVisibleButtons = committed
            end,
            onRelease = function(val)
                SetMaxVisibleButtons(val)
                CooldownCompanion:RefreshGroupFrame(CS.selectedGroup)
            end,
        })
        -- The cap counts CC's own buttons, and an Aura Only Section builds none
        -- (GroupFrame's visible-button pass skips its members). Said only on a
        -- panel that actually has one, so every other panel reads as before.
        local maxVisTooltip = {
            "Max Visible Buttons",
            {"Limits how many buttons can appear at once. The first buttons (by group order) that pass visibility checks are shown; the rest are hidden.", 1, 1, 1, true},
        }
        if ST.PanelHasAuraSection and ST.PanelHasAuraSection(group) then
            maxVisTooltip[#maxVisTooltip + 1] = {" ", 1, 1, 1, true}
            maxVisTooltip[#maxVisTooltip + 1] = {"Aura Only Sections are not counted.", 1, 1, 1, true}
        end
        ST._AnchorRowBadge(maxVisRow, CreateInfoButton(maxVisRow.frame, maxVisRow.frame, "LEFT", "LEFT", 0, 0,
            maxVisTooltip, tabInfoButtons))
    end

    AddAdvancedToggle(compactCb, "compactLayout", tabInfoButtons, group.compactLayout, {
        title = "Compact Mode Advanced",
        build = BuildCompactAdvanced,
    })

    -- (?) tooltip for compact mode. The gear is already chained off the label,
    -- so this info button lands to its right; the anchor args below are a
    -- placeholder - AnchorRowBadge re-points the button.
    local compactTooltip = {
        "Compact Mode",
        {"Compacts visible buttons or bars when hide conditions remove entries, helping centered layouts stay centered.", 1, 1, 1, true},
        {" ", 1, 1, 1},
        {"Auras set to |cffffd100Show Only While Aura Active|r always keep their space reserved. The game hides whether auras are active from addons, so the panel cannot tighten around a hidden aura.", 1, 1, 1, true},
        {" ", 1, 1, 1},
    }
    if compactSuppressed then
        local reasonLabels = {
            frameAnchoring = "Unit Frames",
            resourceBars = "Resources",
            castBar = "Cast Bar",
        }
        local activeLabels = {}
        for _, reason in ipairs(suppressionReasons) do
            activeLabels[#activeLabels + 1] = reasonLabels[reason] or tostring(reason)
        end
        compactTooltip[#compactTooltip + 1] = {
            "Temporarily inactive while these attached features use this panel: "
                .. table.concat(activeLabels, ", ")
                .. ". Your preference is saved and will resume automatically when each attachment is disabled or given an independent anchor.",
            1, 1, 1, true,
        }
    else
        compactTooltip[#compactTooltip + 1] = {
            "When Unit Frames, Resources, or the Cast Bar uses this panel as its attached anchor, Compact Mode pauses temporarily so the attached layout keeps a stable footprint. Your preference remains saved.",
            1, 1, 1, true,
        }
    end
    local compactInfo = CreateInfoButton(compactCb.frame, compactCb.frame, "LEFT", "LEFT", 0, 0,
        compactTooltip, tabInfoButtons)
    ST._AnchorRowBadge(compactCb, compactInfo)
end

local charCopyButtons = {}

local CHARACTER_COPY_TOOLTIP_DETAILS = {
    frameAnchoring = {
        "Copies: enable state, unit-frame addon/custom frame choices, player/target anchors, mirroring, and alpha inheritance.",
        "Does not copy: Resource Bars, Cast Bar, panels, or panel contents.",
    },
    castBar = {
        "Copies: enable state, anchor/position mode, styling, icon, text, and cast effects.",
        "Does not copy: Resource Bars, Unit Frames, panels, or panel contents.",
    },
}

local function CreateCharacterCopyButton(enableCb, systemKey, label, onCopied)
    local _, copyOrder = CooldownCompanion:GetCharacterScopedSettingsCopyOptions(systemKey)
    if #copyOrder == 0 then return end

    -- Pool one button per systemKey to avoid frame leaks across panel rebuilds
    local btn = charCopyButtons[systemKey]
    if not btn then
        btn = CreateFrame("Button", nil, enableCb.frame)
        btn:SetSize(16, 16)

        local icon = btn:CreateTexture(nil, "OVERLAY")
        icon:SetSize(14, 14)
        icon:SetPoint("CENTER")
        icon:SetAtlas("BattleBar-SwapPetIcon", false)

        charCopyButtons[systemKey] = btn
    else
        btn:SetParent(enableCb.frame)
    end

    -- Row-grammar checkboxes have no checkbg/text anatomy: the badge chains
    -- off the end of the row's label instead, like every other row badge.
    -- AnchorRowBadge does the SetParent and ClearAllPoints itself.
    if enableCb.badgeAnchor then
        ST._AnchorRowBadge(enableCb, btn)
    else
        btn:ClearAllPoints()
        btn:SetPoint("LEFT", enableCb.checkbg, "RIGHT", enableCb.text:GetStringWidth() + 4, 0)
    end
    btn:Show()

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Copy " .. label .. " Settings")
        local tooltipDetails = CHARACTER_COPY_TOOLTIP_DETAILS[systemKey]
        if tooltipDetails then
            for _, line in ipairs(tooltipDetails) do
                if line == "" then
                    GameTooltip:AddLine(" ")
                elseif line == "What is copied:" or line == "What is not copied:" then
                    GameTooltip:AddLine(line, 1, 0.82, 0, true)
                else
                    GameTooltip:AddLine(line, 1, 1, 1, true)
                end
            end
        else
            GameTooltip:AddLine("Copy settings from another character on this profile.", 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    btn:SetScript("OnClick", function()
        if not CS.charCopyMenu then
            CS.charCopyMenu = CreateFrame("Frame", "CDCCharCopyMenu", UIParent, "UIDropDownMenuTemplate")
        end
        local vals, order = CooldownCompanion:GetCharacterScopedSettingsCopyOptions(systemKey)
        if #order == 0 then return end

        UIDropDownMenu_Initialize(CS.charCopyMenu, function(self, level)
            for _, charKey in ipairs(order) do
                local info = UIDropDownMenu_CreateInfo()
                info.text = vals[charKey]
                info.notCheckable = true
                info.func = function()
                    CloseDropDownMenus()
                    if not ShowPopupAboveConfig then
                        CooldownCompanion:Print("Copy confirmation is unavailable.")
                        return
                    end
                    ShowPopupAboveConfig("CDC_CONFIRM_CHARACTER_SCOPED_COPY", label .. " settings from " .. (vals[charKey] or charKey) .. " to this character", {
                        systemKey = systemKey,
                        systemLabel = label,
                        sourceCharKey = charKey,
                        onCopied = onCopied,
                    })
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end, "MENU")
        CS.charCopyMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        ToggleDropDownMenu(1, nil, CS.charCopyMenu, "cursor", 0, 0)
    end)

    -- Clean up on widget release (raw frame persists across AceGUI recycling)
    local prevOnRelease = enableCb.events and enableCb.events["OnRelease"]
    enableCb:SetCallback("OnRelease", function()
        if prevOnRelease then
            prevOnRelease(enableCb, "OnRelease")
        end
        btn:ClearAllPoints()
        btn:Hide()
    end)

    return btn
end

-- The modern ColorPickerFrame never delivers AceGUI's OnValueConfirmed:
-- the OK button runs swatchFunc/opacityFunc BEFORE Hide(), so the widget's
-- "picker still open" test routes them to OnValueChanged — and its no-change
-- guard swallows them anyway, because the last drag tick already carried the
-- same values. Commit is therefore detected by picker CLOSE. Every close
-- path (OK, Cancel, Esc, any click outside the picker — including on
-- another swatch, which cancels via GLOBAL_MOUSE_DOWN before its own click
-- lands) runs through OnHide, and the cancel paths restore the original
-- color into the bound table via OnValueChanged before hiding — so flushing
-- the armed commit on hide applies the right value on every path.
local pendingColorCommit
local colorCommitHookInstalled
local function ArmColorCommitOnClose(onConfirmedFn)
    if not colorCommitHookInstalled then
        if not ColorPickerFrame then return end
        colorCommitHookInstalled = true
        ColorPickerFrame:HookScript("OnHide", function()
            local commit = pendingColorCommit
            pendingColorCommit = nil
            if commit then commit() end
        end)
    end
    pendingColorCommit = onConfirmedFn
end

-- Helper: wire up OnValueChanged and OnValueConfirmed for a ColorPicker widget.
-- Stores {r,g,b,a} into tbl[key]. onConfirmedFn fires when the color picker
-- closes (via the commit-on-close bridge above); onChangeFn (optional) fires
-- during drag for live preview.
-- With deferCommit, the drag value never rests in the bound table: it is
-- swapped in only for the duration of the onChangeFn call and committed for
-- real when the picker closes. Use it when a live renderer re-reads the same
-- table every tick and must keep showing the committed color during a drag.
local function SetupColorCallbacks(widget, tbl, key, onConfirmedFn, onChangeFn, deferCommit)
    widget:SetCallback("OnValueChanged", function(_, _, r, g, b, a)
        if deferCommit then
            -- Deferred mode: the live renderers re-read this table every tick,
            -- so an uncommitted drag value may only exist in it for the moment
            -- the config canvas rebuild reads it. Arm the close commit FIRST so
            -- a failed refresh still converges when the picker closes — and arm
            -- it unconditionally, because this closure is the only writer of
            -- tbl[key] in deferred mode; without it the edit would be silently
            -- discarded when no confirm callback is supplied.
            local pending = {r, g, b, a}
            ArmColorCommitOnClose(function()
                tbl[key] = pending
                if onConfirmedFn then onConfirmedFn() end
            end)
            local committed = tbl[key]
            tbl[key] = pending
            if onChangeFn then onChangeFn() end
            tbl[key] = committed
        else
            tbl[key] = {r, g, b, a}
            if onConfirmedFn then ArmColorCommitOnClose(onConfirmedFn) end
            if onChangeFn then onChangeFn() end
        end
    end)
    -- Kept wired so nothing double-fires if a future Ace3 update restores
    -- OnValueConfirmed: disarm the pending close commit before running it here.
    widget:SetCallback("OnValueConfirmed", function(_, _, r, g, b, a)
        pendingColorCommit = nil
        tbl[key] = {r, g, b, a}
        if onConfirmedFn then onConfirmedFn() end
    end)
end

------------------------------------------------------------------------
-- WIDGET FACTORIES
-- Composable builders that replace repeated AceGUI boilerplate.
-- Each creates, configures, and adds to container; single-widget factories return the widget.
------------------------------------------------------------------------

-- Create an anchor-point row using the pre-built list from State.lua.
-- Optional label param overrides the default "Anchor" label.
--
-- Row grammar only (RowWidgets.lua); opts.indent makes it a child row. The
-- pre-redesign full-width stock Dropdown had no call sites left after the
-- conversion packets.
--
-- The row builder is read at CALL time rather than hoisted to file scope:
-- Helpers.lua loads BEFORE RowWidgets.lua (TOC 46 vs 47), so ST._AddDropdownRow
-- does not exist yet while this file is being read.
local function AddAnchorDropdown(container, tbl, key, default, refreshFn, label, opts)
    return ST._AddDropdownRow(container, {
        label = label or "Anchor",
        indent = opts and opts.indent,
        list = CS.anchorDropdownList,
        order = CS.anchorPoints,
        value = tbl[key] or default,
        onChange = function(val)
            tbl[key] = val
            refreshFn()
        end,
    })
end

-- LibSharedMedia font names run well past the 140px control column, and a
-- dropdown sizes its menu from the control it hangs under.
local FONT_ROW_PULLOUT_WIDTH = 300

-- Create Font Size slider + Font dropdown + Font Outline dropdown.
-- prefix: key prefix (e.g. "cooldown" reads cooldownFont, cooldownFontSize, cooldownFontOutline).
-- defaults: {size, sizeMin, sizeMax, sizeStep, font, outline} — all optional with sane fallbacks.
--
-- Row grammar only (RowWidgets.lua); opts.indent makes them child rows. The
-- pre-redesign full-width stock trio had no call sites left after the
-- conversion packets.
--
-- The row builders are read at CALL time rather than hoisted to file scope:
-- Helpers.lua loads BEFORE RowWidgets.lua (TOC 46 vs 47), so ST._AddSliderRow
-- does not exist yet while this file is being read. Same rule the alpha and
-- anchor-target builders above follow.
local function AddFontControls(container, tbl, prefix, defaults, refreshFn, opts)
    local fontKey = prefix .. "Font"
    local sizeKey = prefix .. "FontSize"
    local outlineKey = prefix .. "FontOutline"
    local indent = opts and opts.indent
    -- The slider is mirror-first everywhere. Resources and cast bars provide
    -- their own canvas callback; ordinary panel controls use the pinned
    -- Buttons preview. Dropdowns have no drag phase and remain discrete live
    -- commits through refreshFn.
    local previewRefresh = (opts and opts.previewRefresh) or RefreshSelectedButtonsPreview

    ST._AddSliderRow(container, {
        label = "Font Size",
        indent = indent,
        min = defaults.sizeMin or 8,
        max = defaults.sizeMax or 32,
        step = defaults.sizeStep or 1,
        value = tbl[sizeKey] or defaults.size or 12,
        onChange = function(val)
            PreviewScalarSetting(tbl, sizeKey, val, previewRefresh)
        end,
        onRelease = function(val)
            tbl[sizeKey] = val
            refreshFn()
        end,
    })

    -- FONT ROW (the Item Settings pilot's rule, stated at that call site):
    -- the row is created with a label and a widened pullout but NO list and
    -- NO onChange, then handed to the shared font helpers exactly as a
    -- stock Dropdown would be. CDC-DropdownRow forwards SetList/SetDisabled
    -- to its embedded child and forwards the child's OnOpened with
    -- self = the row (aliasing row.pullout), which is everything
    -- CS.SetupFontDropdown touches. AddDropdownRow registers OnValueChanged
    -- only when opts.onChange is given, so SetFontDropdownCallback is the
    -- one registration and the profile-wide font lock still gates every
    -- write. The value is set AFTER SetupFontDropdown, because SetList
    -- rebuilds the list the displayed text is read from.
    local fontRow = ST._AddDropdownRow(container, {
        label = "Font",
        indent = indent,
        pulloutWidth = FONT_ROW_PULLOUT_WIDTH,
    })
    CS.SetupFontDropdown(fontRow)
    fontRow:SetValue(tbl[fontKey] or defaults.font or "Friz Quadrata TT")
    CS.SetFontDropdownCallback(fontRow, function(widget, event, val)
        tbl[fontKey] = val
        refreshFn()
    end)

    local outlineRow = ST._AddDropdownRow(container, {
        label = "Font Outline",
        indent = indent,
    })
    CS.SetupFontOutlineDropdown(outlineRow)
    outlineRow:SetValue(tbl[outlineKey] or defaults.outline or "OUTLINE")
    CS.SetFontOutlineDropdownCallback(outlineRow, function(widget, event, val)
        tbl[outlineKey] = val
        refreshFn()
    end)
end

-- Create X Offset + Y Offset slider pair.
-- defaults: {x, y, range (default 20), step (default 0.1)}
--
-- Row grammar only (RowWidgets.lua); opts.indent makes them child rows. Same
-- call-time row-builder read as AddFontControls above, and for the same
-- load-order reason. The pre-redesign full-width stock pair had no call sites
-- left after the conversion packets.
local function AddOffsetSliders(container, tbl, xKey, yKey, defaults, refreshFn, opts)
    local range = defaults.range or 20
    local step = defaults.step or 0.1
    local indent = opts and opts.indent
    local previewRefresh = (opts and opts.previewRefresh) or RefreshSelectedButtonsPreview

    local xRow = ST._AddSliderRow(container, {
        label = "X Offset",
        indent = indent,
        min = -range, max = range, step = step,
        value = tbl[xKey] or defaults.x or 0,
        onChange = function(val)
            PreviewScalarSetting(tbl, xKey, val, previewRefresh)
        end,
        onRelease = function(val)
            tbl[xKey] = val
            refreshFn()
        end,
    })

    local yRow = ST._AddSliderRow(container, {
        label = "Y Offset",
        indent = indent,
        min = -range, max = range, step = step,
        value = tbl[yKey] or defaults.y or 0,
        onChange = function(val)
            PreviewScalarSetting(tbl, yKey, val, previewRefresh)
        end,
        onRelease = function(val)
            tbl[yKey] = val
            refreshFn()
        end,
    })

    return xRow, yRow
end

local BORDER_THICKNESS_MODE_TOOLTIPS = {
    [ST.BORDER_RENDER_MODE_CUSTOM] = {
        "Custom Thickness",
        "Uses the Border Size slider, including fractional values.",
    },
    [ST.BORDER_RENDER_MODE_CRISP] = {
        "One-pixel",
        "Uses a stable one-pixel border for your current UI scale.",
    },
}

local function AddDropdownItemTooltips(dropdown, tooltipByValue)
    if not (dropdown and dropdown.pullout and tooltipByValue) then return end

    for _, item in dropdown.pullout:IterateItems() do
        local value = item.userdata and item.userdata.value
        local tooltip = tooltipByValue[value]
        if tooltip then
            item:SetCallback("OnEnter", function(widget)
                GameTooltip:SetOwner(widget.frame, "ANCHOR_RIGHT")
                GameTooltip:AddLine(tooltip[1], 1, 0.82, 0, true)
                GameTooltip:AddLine(tooltip[2], 1, 1, 1, true)
                GameTooltip:Show()
            end)
            item:SetCallback("OnLeave", function()
                GameTooltip:Hide()
            end)
        end
    end
end

-- Row grammar only (RowWidgets.lua); opts.indent makes it a child row. The
-- pre-redesign full-width stock Dropdown had no call sites left after the
-- conversion packets.
local function AddBorderRenderModeDropdown(container, tbl, key, refreshFn, disabled, opts)
    key = key or "borderRenderMode"
    local controlsDisabled = disabled == true or ST.IsBorderThicknessLocked()
    local modeList = {
        [ST.BORDER_RENDER_MODE_CUSTOM] = "Custom Thickness",
        [ST.BORDER_RENDER_MODE_CRISP] = "One-pixel",
    }
    local modeOrder = { ST.BORDER_RENDER_MODE_CUSTOM, ST.BORDER_RENDER_MODE_CRISP }

    local function ApplyRenderMode(val)
        if controlsDisabled then return end
        tbl[key] = ST.GetBorderRenderMode(val)
        if refreshFn then
            refreshFn()
        end
    end

    local modeRow = ST._AddDropdownRow(container, {
        label = "Border Thickness",
        indent = opts and opts.indent,
        list = modeList,
        order = modeOrder,
        value = ST.GetBorderRenderMode(tbl, key),
        disabled = controlsDisabled,
        onChange = ApplyRenderMode,
    })
    AddDropdownItemTooltips(modeRow, BORDER_THICKNESS_MODE_TOOLTIPS)
    modeRow:SetCallback("OnClosed", function()
        GameTooltip:Hide()
    end)

    return ST.GetBorderRenderMode(tbl, key), modeRow
end

-- Expose helpers for other ConfigSettings files
ST._ColorHeading = ColorHeading
ST._AttachCollapseButton = AttachCollapseButton
ST._ApplyLeftAlignedHeading = ApplyLeftAlignedHeading
ST._AnchorLeftAlignedHeadingRule = AnchorLeftAlignedHeadingRule
ST._BuildEntryIdentityHeading = BuildEntryIdentityHeading
ST._ChainHeadingBadges = ChainHeadingBadges
ST._BuildCollapsibleSection = BuildCollapsibleSection
ST._AddAdvancedToggle = AddAdvancedToggle
ST._CanButtonUseConfigOverrideSection = CanButtonUseConfigOverrideSection
ST._GroupSupportsPerButtonOverrides = GroupSupportsPerButtonOverrides
ST._ResolveStyleLens = ResolveStyleLens
ST._ResolveLensSection = ResolveLensSection
ST._PromoteLensSection = PromoteLensSection
ST._BeginLensSection = BeginLensSection
ST._ResolveLensCollapseKey = ResolveLensCollapseKey
ST._AddLensPanelScopeNote = AddLensPanelScopeNote
-- The text Format tab writes its own scope note (its field lives outside the
-- section machinery), so it borrows the NAME the chrome would have shown
-- rather than re-deriving one and truncating it differently.
ST._GetLensEntryName = GetLensEntryName
ST._GroupHasAuraTrackingEntry = GroupHasAuraTrackingEntry
ST._CreateInfoButton = CreateInfoButton
ST._BuildCustomizationsSection = BuildCustomizationsSection
-- Reached from the confirm popup (Config/Popups.lua), not from a builder.
ST._RevertAllEntryCustomizations = RevertAllEntryCustomizations
ST._BuildCompactModeControls = BuildCompactModeControls
-- The compact vocabulary outlives the compact section: an Aura Panel's
-- Collapse Direction row (GroupTabsLayout.lua, Arrangement) asks the same
-- start/center/end question against the same compactGrowthDirection key, so it
-- reads and writes through these two rather than restating the mapping.
ST._GetCompactGrowthDirectionLabels = GetCompactGrowthDirectionLabels
ST._NormalizeCompactGrowthDirection = NormalizeCompactGrowthDirection
ST._CreateCharacterCopyButton = CreateCharacterCopyButton
ST._AddAnchorDropdown = AddAnchorDropdown
ST._RefreshSelectedButtonsPreview = RefreshSelectedButtonsPreview
ST._RefreshActiveConfigPreview = RefreshActiveConfigPreview
ST._PreviewScalarSetting = PreviewScalarSetting
-- Exposed so the row-grammar color row can bind the exact same
-- commit-on-close contract described above (see RowWidgets.lua).
ST._SetupColorCallbacks = SetupColorCallbacks

-- Shared alpha UI builder for groups, containers, resource bars, and other
-- shared alpha consumers.
-- container: AceGUI parent widget
-- config: table with alpha fields (baselineAlpha, forceAlpha*, forceHide*, fade*, etc.)
-- refreshFn: function called after value changes (typically RefreshConfigPanel)
-- collapseKey: string key for CS.collapsedSections
-- opts (optional): { previewRefresh = fn(), onBaselinePreview = fn(val),
-- onBaselineCommitted = fn(val), isGlobal = bool, disabled = bool,
-- disabledText = string, infoButtons = table, hideHeading = bool }
--
-- Row grammar only (RowWidgets.lua): a collapsible left-aligned section header
-- and a two-column grid of fixed-height rows. Every caller opts in, so there is
-- no stock shape left to draw; opts.row is accepted and ignored for callers
-- that still state it.
local function BuildAlphaControls(container, config, refreshFn, collapseKey, opts)
    opts = opts or {}
    local tabInfoBtns = opts.infoButtons or CS.tabInfoButtons
    local controlsDisabled = opts.disabled == true
    local previewRefresh = opts.previewRefresh or RefreshSelectedButtonsPreview

    local function ApplyAlphaSettingChange(refreshPanel)
        if CooldownCompanion.RefreshAlphaUpdateDriver then
            CooldownCompanion:RefreshAlphaUpdateDriver()
        end
        if refreshPanel and refreshFn then
            refreshFn()
        end
    end

    local ALPHA_TOOLTIP = {
        "Alpha",
        {"Controls transparency: 1 is fully visible, 0 is hidden.\n\nThe first four options (In Combat, Out of Combat, Regular Mount, Skyriding) cycle on click through Disabled, |cff00ff00Fully Visible|r, and |cffff0000Fully Hidden|r.\n\n|cff00ff00Fully Visible|r forces the display fully shown while its condition applies; |cffff0000Fully Hidden|r hides it.\n\nIf both apply at once, |cff00ff00Fully Visible|r wins.", 1, 1, 1, true},
    }

    if opts.hideHeading ~= true then
        local alphaHeading, alphaCollapsed = BuildCollapsibleSection(container, "Alpha", collapseKey, nil, nil, { leftAligned = true })

        -- The tooltip describes the whole section (the tri-state force
        -- conditions above all), so it rides the header rather than badging
        -- the Baseline Alpha row: a slider row's track starts exactly where a
        -- badge chain would run into it.
        local headingInfoBtn = CreateInfoButton(alphaHeading.frame, alphaHeading.label, "LEFT", "RIGHT", 4, 0,
            ALPHA_TOOLTIP, tabInfoBtns)
        AnchorLeftAlignedHeadingRule(alphaHeading, headingInfoBtn)

        if alphaCollapsed then return end
    end

    if controlsDisabled and opts.disabledText and opts.disabledText ~= "" then
        local disabledLabel = AceGUI:Create("Label")
        if ST._ConfigureWrappedHelperLabel then
            ST._ConfigureWrappedHelperLabel(disabledLabel)
        end
        disabledLabel:SetText("|cff888888" .. opts.disabledText .. "|r")
        disabledLabel:SetFullWidth(true)
        container:AddChild(disabledLabel)
    end

    -- LEFT column holds the baseline and the four combat/mount force
    -- conditions, RIGHT the unit and mouseover conditions plus the fade
    -- behaviour they all share. Both halves are top-aligned, so the gated
    -- child rows on either side just end their column early.
    local leftTarget, rightTarget = ST._BeginRowGrid(container)

    local function ApplyBaselineAlpha(val)
        if controlsDisabled then return end
        local committed = config.baselineAlpha
        config.baselineAlpha = val
        if opts.onBaselinePreview then
            opts.onBaselinePreview(val)
        else
            previewRefresh()
        end
        config.baselineAlpha = committed
    end

    ST._AddSliderRow(leftTarget, {
        label = "Baseline Alpha",
        min = 0, max = 1, step = 0.1,
        value = config.baselineAlpha or 1,
        disabled = controlsDisabled,
        onChange = ApplyBaselineAlpha,
        onRelease = function(val)
            if controlsDisabled then return end
            config.baselineAlpha = val
            if opts.onBaselineCommitted then
                opts.onBaselineCommitted(val)
            end
            ApplyAlphaSettingChange(false)
        end,
    })

    do
        local function GetTriState(visibleKey, hiddenKey)
            if config[hiddenKey] then return nil end
            if config[visibleKey] then return true end
            return false
        end

        local function TriStateLabel(base, value)
            if value == true then
                return base .. " - |cff00ff00Fully Visible|r"
            elseif value == nil then
                return base .. " - |cffff0000Fully Hidden|r"
            end
            return base
        end

        local function ApplyTriState(visibleKey, hiddenKey, newVal)
            if controlsDisabled then return end
            config[visibleKey] = (newVal == true)
            config[hiddenKey] = (newVal == nil)
            ApplyAlphaSettingChange(true)
        end

        local function AddTriStateToggle(parent, label, visibleKey, hiddenKey)
            local val = GetTriState(visibleKey, hiddenKey)
            return ST._AddCheckboxRow(parent, {
                label = TriStateLabel(label, val),
                tristate = true,
                value = val,
                disabled = controlsDisabled,
                onChange = function(newVal)
                    ApplyTriState(visibleKey, hiddenKey, newVal)
                end,
            })
        end

        AddTriStateToggle(leftTarget, "In Combat", "forceAlphaInCombat", "forceHideInCombat")
        AddTriStateToggle(leftTarget, "Out of Combat", "forceAlphaOutOfCombat", "forceHideOutOfCombat")
        AddTriStateToggle(leftTarget, "Regular Mount", "forceAlphaRegularMounted", "forceHideRegularMounted")
        AddTriStateToggle(leftTarget, "Skyriding", "forceAlphaDragonriding", "forceHideDragonriding")

        local mountedActive = config.forceAlphaRegularMounted
            or config.forceHideRegularMounted
            or config.forceAlphaDragonriding
            or config.forceHideDragonriding
        local isDruid = CooldownCompanion._playerClassID == 11
        if mountedActive and (opts.isGlobal or isDruid) then
            local travelVal = config.treatTravelFormAsMounted or false
            local function ApplyTravelForm(val)
                if controlsDisabled then return end
                config.treatTravelFormAsMounted = val
                ApplyAlphaSettingChange(false)
            end

            -- Child of the two mount toggles above it, so it is indented and
            -- stays in their column.
            ST._AddCheckboxRow(leftTarget, {
                label = "Include Druid Travel Form (applies to both)",
                indent = true,
                value = travelVal,
                disabled = controlsDisabled,
                onChange = ApplyTravelForm,
            })
        end

        local function ApplyForceFlag(key, val, refreshPanel)
            if controlsDisabled then return end
            config[key] = val
            ApplyAlphaSettingChange(refreshPanel)
        end

        local targetVal = config.forceAlphaTargetExists or false
        local targetLabel = targetVal and "Target Exists - |cff00ff00Fully Visible|r" or "Target Exists"
        ST._AddCheckboxRow(rightTarget, {
            label = targetLabel,
            value = targetVal,
            disabled = controlsDisabled,
            onChange = function(val) ApplyForceFlag("forceAlphaTargetExists", val, true) end,
        })

        if targetVal then
            ST._AddCheckboxRow(rightTarget, {
                label = "Enemy Only",
                indent = true,
                value = config.forceAlphaTargetEnemyOnly or false,
                disabled = controlsDisabled,
                onChange = function(val) ApplyForceFlag("forceAlphaTargetEnemyOnly", val, true) end,
            })
        end

        local focusVal = config.forceAlphaFocusExists or false
        local focusLabel = focusVal and "Focus Exists - |cff00ff00Fully Visible|r" or "Focus Exists"
        ST._AddCheckboxRow(rightTarget, {
            label = focusLabel,
            value = focusVal,
            disabled = controlsDisabled,
            onChange = function(val) ApplyForceFlag("forceAlphaFocusExists", val, true) end,
        })

        local mouseoverVal = config.forceAlphaMouseover or false
        local mouseoverLabel = mouseoverVal and "Mouseover - |cff00ff00Fully Visible|r" or "Mouseover"
        local mouseoverRow = ST._AddCheckboxRow(rightTarget, {
            label = mouseoverLabel,
            value = mouseoverVal,
            disabled = controlsDisabled,
            onChange = function(val) ApplyForceFlag("forceAlphaMouseover", val, true) end,
        })
        -- Row grammar: the badge hangs off the end of the label. The anchor
        -- args below are a placeholder - AnchorRowBadge re-points it.
        ST._AnchorRowBadge(mouseoverRow, CreateInfoButton(mouseoverRow.frame, mouseoverRow.frame, "LEFT", "LEFT", 0, 0, {
            "Mouseover",
            {"When enabled, mousing over forces full visibility. Like all |cff00ff00Force Visible|r conditions, this overrides |cffff0000Force Hidden|r.", 1, 1, 1, true},
        }, tabInfoBtns))

        local function ApplyCustomFade(val)
            if controlsDisabled then return end
            config.customFade = val or nil
            ApplyAlphaSettingChange(true)
        end

        ST._AddCheckboxRow(rightTarget, {
            label = "Custom Fade Settings",
            value = config.customFade or false,
            disabled = controlsDisabled,
            onChange = ApplyCustomFade,
        })

        if config.customFade then
        local function AddFadeSlider(label, key, default)
            ST._AddSliderRow(rightTarget, {
                label = label,
                indent = true,
                min = 0, max = 5, step = 0.1,
                value = config[key] or default,
                disabled = controlsDisabled,
                onRelease = function(val)
                    if controlsDisabled then return end
                    config[key] = val
                    ApplyAlphaSettingChange(false)
                end,
            })
        end

        AddFadeSlider("Fade Delay (seconds)", "fadeDelay", 1)
        AddFadeSlider("Fade In Duration (seconds)", "fadeInDuration", 0.2)
        AddFadeSlider("Fade Out Duration (seconds)", "fadeOutDuration", 0.2)
        end -- config.customFade
    end
end
ST._BuildAlphaControls = BuildAlphaControls
ST._BuildIndependentAnchorTargetRow = BuildIndependentAnchorTargetRow

ST._AddFontControls = AddFontControls
ST._AddOffsetSliders = AddOffsetSliders
ST._AddBorderRenderModeDropdown = AddBorderRenderModeDropdown
